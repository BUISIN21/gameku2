// Phase 3 end-to-end test: real browsers, real accounts (Firebase Auth
// emulator), real Firestore rules (emulator), the real backend and a real
// LiveKit server.
//
// Prerequisites (see docs/TESTING.md):
//   cd backend && npm run emulators
//   livekit-server --dev --bind 127.0.0.1 --node-ip 127.0.0.1
//   backend on :8080 against the emulators (FIREBASE_PROJECT_ID=demo-connectcall ...)
//   web build made with --dart-define-from-file=config/emulator.json, served on :5000
// Usage: npm install && npm test [screenshot-dir]
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');
const { RoomServiceClient } = require('livekit-server-sdk');

const OUT = process.argv[2] || path.join(__dirname, 'screenshots');
fs.mkdirSync(OUT, { recursive: true });
const WEB = process.env.WEB_URL || 'http://localhost:5000';
const API = process.env.API_URL || 'http://localhost:8080';
const AUTH_EMU = process.env.AUTH_EMULATOR || 'http://127.0.0.1:9099';
const svc = new RoomServiceClient(
  process.env.LIVEKIT_HTTP_URL || 'http://localhost:7880',
  process.env.LIVEKIT_API_KEY || 'devkey',
  process.env.LIVEKIT_API_SECRET || 'secret',
);
// Serve the Firebase JS SDK locally (same version FlutterFire requests from
// gstatic.com) so the test also runs on machines without CDN access.
const FIREBASE_JS = path.dirname(require.resolve('firebase/package.json'));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`);
};
const run = Date.now().toString(36);
const PASSWORD = 'correct-horse-battery';
const pages = [];

async function newPage(browser, label) {
  // CI runners have no system locale; Flutter web needs a valid one.
  const ctx = await browser.newContext({
    locale: 'en-US',
    permissions: ['camera', 'microphone'],
    viewport: { width: 1100, height: 760 },
  });
  await ctx.route(/https:\/\/www\.gstatic\.com\/firebasejs\/[\d.]+\/(.+\.js)$/, (route) => {
    const file = path.join(FIREBASE_JS, route.request().url().split('/').pop());
    route.fulfill({ path: file, contentType: 'text/javascript' });
  });
  const page = await ctx.newPage();
  pages.push([label, page]);
  page.on('pageerror', (e) => console.log(`[${label}] pageerror`, e.message.slice(0, 300)));
  return page;
}

async function open(page, url) {
  await page.goto(url);
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 60000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
}

async function type(page, label, text) {
  const box = page.getByRole('textbox', { name: label });
  await box.click();
  await page.waitForTimeout(250);
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.type(text, { delay: 15 });
}

const button = (page, name, exact = false) => page.getByRole('button', { name, exact });
const text = (page, t) => page.getByText(t).first();

async function register(page, name, email) {
  await button(page, 'New here? Create an account').click();
  await type(page, 'Your name', name);
  await type(page, 'E-mail', email);
  await type(page, 'Password', PASSWORD);
  await button(page, 'Create account').click();
}

/** ID token for API calls made directly by the test (as that user). */
async function idTokenFor(email) {
  const res = await fetch(`${AUTH_EMU}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD, returnSecureToken: true }),
  });
  return (await res.json()).idToken;
}

async function apiAs(email, method, p) {
  const res = await fetch(`${API}${p}`, { method, headers: { Authorization: `Bearer ${await idTokenFor(email)}` } });
  return res.status;
}

async function createRoom(page, name, waitingRoom) {
  await button(page, 'New room').click();
  await type(page, 'Room name', name);
  if (waitingRoom) await page.getByRole('switch', { name: /Waiting room/ }).click();
  await button(page, 'Create', true).click();
  await button(page, 'Join call').waitFor({ timeout: 15000 });
}

async function createInviteLink(page) {
  await button(page, 'New link').click();
  await button(page, 'Create link').click();
  const handle = await page.waitForFunction(
    () => (document.body.innerText.match(/https?:\/\/\S+\?invite=[A-Za-z0-9_-]{22}/) || [])[0],
    null,
    { timeout: 15000 },
  );
  const link = await handle.jsonValue();
  await button(page, 'Close').click();
  return link;
}

/** Opens an invitation from inside the app (paste box on the home screen). */
async function pasteInvite(page, link) {
  await type(page, 'Paste invitation link', link);
  await button(page, 'Open', true).click();
}

async function participants(roomId) {
  return (await svc.listParticipants(roomId)).map((p) => ({ name: p.name, identity: p.identity, tracks: p.tracks.length }));
}

async function liveVideos(page) {
  return page.evaluate(
    () => [...document.querySelectorAll('video')].filter((v) => v.videoWidth > 0 && !v.paused && v.currentTime > 0).length,
  );
}

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || undefined,
    args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', '--enable-unsafe-swiftshader'],
  });
  const aliceEmail = `alice-${run}@example.test`;
  const bobEmail = `bob-${run}@example.test`;
  const malloryEmail = `mallory-${run}@example.test`;

  // --- Alice signs up and creates a room with an invitation link.
  const alice = await newPage(browser, 'Alice');
  await open(alice, WEB);
  await register(alice, 'Alice Owner', aliceEmail);
  await text(alice, 'No rooms yet').waitFor({ timeout: 20000 });
  check('registration signs the user in and shows an empty home', true);

  await createRoom(alice, 'Team sync', false);
  const inviteLink = await createInviteLink(alice);
  check('owner creates a room and an invitation link', /\?invite=/.test(inviteLink || ''), inviteLink);

  // --- Bob opens the link while signed out, registers, accepts.
  const bob = await newPage(browser, 'Bob');
  await open(bob, inviteLink);
  await text(bob, 'accept your invitation').waitFor({ timeout: 20000 });
  await register(bob, 'Bob Guest', bobEmail);
  await text(bob, 'Alice Owner invited you to').waitFor({ timeout: 20000 });
  check('invitation link survives sign-up and shows who invited you', true);
  await button(bob, 'Accept invitation').click();
  await button(bob, 'Join call').waitFor({ timeout: 15000 });
  check('accepting makes Bob a member (room page opens)', true);

  // --- Mallory: a signed-in stranger cannot get in without an invitation.
  const mallory = await newPage(browser, 'Mallory');
  await open(mallory, WEB);
  await register(mallory, 'Mallory', malloryEmail);
  await text(mallory, 'No rooms yet').waitFor({ timeout: 20000 });

  // --- Both join the call.
  await button(alice, 'Join call').click();
  await alice.getByText(/Connected ·/).first().waitFor({ timeout: 30000 });
  await button(bob, 'Join call').click();
  await bob.getByText(/Connected ·/).first().waitFor({ timeout: 30000 });
  await sleep(6000);

  const rooms = await svc.listRooms();
  const live = rooms.map((r) => r.name);
  let ps = [];
  let callRoom = null;
  for (const name of live) {
    const p = await participants(name);
    if (p.some((x) => x.name === 'Bob Guest')) {
      callRoom = name;
      ps = p;
    }
  }
  check('two accounts are in the same LiveKit room', ps.length === 2, JSON.stringify(ps));
  check('LiveKit identities are Firebase uids, names come from profiles', ps.every((p) => /^[A-Za-z0-9]{20,}$/.test(p.identity) && p.tracks === 2));
  check('Alice sees and renders 2 live videos', (await liveVideos(alice)) >= 2);
  check('Bob sees and renders 2 live videos', (await liveVideos(bob)) >= 2);
  await alice.screenshot({ path: `${OUT}/p3-alice-call.png` });
  for (const [label, pg] of [['Alice', alice], ['Bob', bob]]) {
    const audio = await pg.evaluate(() => [...document.querySelectorAll('audio')].filter((a) => a.srcObject && !a.paused).length);
    check(`${label} plays the other person's audio`, audio >= 1, `playing=${audio}`);
  }

  // --- Mute / camera toggles are seen by the server, and can be undone.
  const tracksOf = async (name) =>
    (await svc.listParticipants(callRoom)).find((p) => p.name === name)?.tracks.map((t) => ({ type: t.type, muted: t.muted })) ?? [];
  await button(alice, 'Mute microphone').click();
  await button(bob, 'Turn camera off').click();
  await sleep(2500);
  const aMic = (await tracksOf('Alice Owner')).find((t) => t.type === 0);
  const bCam = (await tracksOf('Bob Guest')).find((t) => t.type === 1);
  check('mute and camera-off reach the server', (!aMic || aMic.muted) && (!bCam || bCam.muted));
  await button(alice, 'Unmute microphone').click();
  await button(bob, 'Turn camera on').click();
  await sleep(2500);
  const restored = [...(await tracksOf('Alice Owner')), ...(await tracksOf('Bob Guest'))];
  check('unmute and camera-on restore all tracks', restored.length === 4 && restored.every((t) => !t.muted));

  // --- Server-side authorization checks as Mallory (direct API calls).
  check('stranger cannot get a call token for the room', (await apiAs(malloryEmail, 'POST', `/api/rooms/${callRoom}/token`)) === 404);
  check('stranger cannot list members', (await apiAs(malloryEmail, 'GET', `/api/rooms/${callRoom}/members`)) === 404);
  check('member (not owner) cannot list invitations', (await apiAs(bobEmail, 'GET', `/api/rooms/${callRoom}/invites`)) === 403);
  check('unauthenticated API call is refused', (await fetch(`${API}/api/rooms`)).status === 401);

  // --- Owner removes Bob from inside the call.
  await button(alice, 'People in the call').click();
  await button(alice, 'Remove from room').first().click();
  await button(alice, 'Remove', true).click();
  await text(bob, 'You were removed from the meeting.').waitFor({ timeout: 15000 });
  await sleep(1500);
  ps = await participants(callRoom);
  check('owner removes a participant: they are disconnected', ps.length === 1 && ps[0].name === 'Alice Owner', JSON.stringify(ps.map((p) => p.name)));
  check('removed member can no longer get a token', (await apiAs(bobEmail, 'POST', `/api/rooms/${callRoom}/token`)) === 404);
  await bob.screenshot({ path: `${OUT}/p3-bob-removed.png` });

  // --- Owner revokes the invitation; Mallory tries the link.
  await alice.getByRole('button', { name: 'Leave meeting' }).click();
  await button(alice, 'Leave', true).click();
  await button(alice, 'Cancel invitation').first().click();
  await button(alice, 'Cancel invitation').last().click();
  await text(alice, 'Cancelled').waitFor({ timeout: 10000 });
  // (Release builds against the Auth *emulator* lose the session on a full
  // page reload, a FlutterFire dev-tool limitation, so stay inside the app.)
  await pasteInvite(mallory, inviteLink);
  await text(mallory, 'This invitation was cancelled by the owner.').waitFor({ timeout: 20000 });
  check('revoked invitation link is refused', true);
  await mallory.screenshot({ path: `${OUT}/p3-revoked.png` });

  // --- Waiting room: Mallory asks to join a second room, Alice approves live.
  await button(mallory, 'Back', true).click();
  await button(alice, 'Back', true).click();
  await text(alice, 'Your rooms').waitFor({ timeout: 20000 });
  await createRoom(alice, 'Private room', true);
  const privateLink = await createInviteLink(alice);
  await pasteInvite(mallory, privateLink);
  await button(mallory, 'Ask to join').click();
  await text(mallory, 'Waiting for Alice Owner to let you in').waitFor({ timeout: 15000 });
  check('waiting-room invite puts the guest in the waiting room', true);
  await button(alice, 'Approve').click({ timeout: 15000 });
  await button(mallory, 'Join call').waitFor({ timeout: 15000 });
  check('owner approval reaches the guest live (Firestore rules + listener)', true);

  // --- Sign out returns to the login screen; API calls stop working for that page.
  await button(bob, 'Profile and settings').click();
  await button(bob, 'Sign out').click();
  await button(bob, 'Sign out', true).last().click();
  await button(bob, 'Sign in', true).waitFor({ timeout: 15000 });
  check('sign out returns to the login screen', true);

  await browser.close();
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch(async (e) => {
  console.error('E2E ERROR', e.message);
  for (const [label, pg] of pages) {
    await pg.screenshot({ path: `${OUT}/error-${label}.png` }).catch(() => {});
    console.log(`--- ${label}:`, (await pg.evaluate(() => document.body.innerText).catch(() => '')).slice(0, 600));
  }
  process.exit(2);
});
