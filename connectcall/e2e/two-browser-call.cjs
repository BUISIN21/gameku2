// End-to-end check: two real Chromium browsers join one room through the
// ConnectCall web build, backend and a local LiveKit server.
const { chromium } = require('playwright');
//
// Prerequisites (see docs/TESTING.md):
//   livekit-server --dev --bind 127.0.0.1 --node-ip 127.0.0.1
//   backend on :8080 with LIVEKIT_URL=ws://localhost:7880 devkey/secret
//   web build served on :5000
// Usage: npm install && node two-browser-call.cjs [screenshot-dir]
const path = require('node:path');
const { RoomServiceClient } = require('livekit-server-sdk');
const OUT = process.argv[2] || path.join(__dirname, 'screenshots');
require('node:fs').mkdirSync(OUT, { recursive: true });
const WEB = process.env.WEB_URL || 'http://localhost:5000';
const API = process.env.API_URL || 'http://localhost:8080';
const svc = new RoomServiceClient(
  process.env.LIVEKIT_HTTP_URL || 'http://localhost:7880',
  process.env.LIVEKIT_API_KEY || 'devkey',
  process.env.LIVEKIT_API_SECRET || 'secret',
);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`); };

async function openClient(browser, name, code) {
  const ctx = await browser.newContext({ permissions: ['camera', 'microphone'], viewport: { width: 1100, height: 700 } });
  const page = await ctx.newPage();
  (global.__pages ||= []).push(page);
  page.on('console', (m) => { if (m.type() === 'error') console.log(`[${name}] console.${m.type()}`, m.text().slice(0, 300)); });
  page.on('pageerror', (e) => console.log(`[${name}] pageerror`, e.message));
  await page.goto(`${WEB}/?room=${code}`);
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 60000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
  const box = page.getByRole('textbox', { name: 'Your name' });
  await box.click();
  await page.waitForTimeout(300);
  await page.keyboard.type(name, { delay: 20 });
  await page.getByText(`${40 - name.length} characters remaining`).first().waitFor({ timeout: 5000 });
  await page.getByRole('button', { name: 'Join' }).click();
  return page;
}

async function videoStats(page) {
  return page.evaluate(() => [...document.querySelectorAll('video')].map((v) => ({ w: v.videoWidth, h: v.videoHeight, playing: !v.paused, t: v.currentTime })));
}

async function participants(room) {
  return (await svc.listParticipants(room)).map((p) => ({
    name: p.name,
    identity: p.identity,
    tracks: p.tracks.map((t) => ({ type: t.type, source: t.source, muted: t.muted })),
  }));
}

(async () => {
  const create = await fetch(`${API}/api/rooms`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ displayName: 'Alice' }) });
  const { roomCode } = await create.json();
  check('backend creates room', create.status === 201, roomCode);

  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || undefined,
    args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', '--autoplay-policy=no-user-gesture-required', '--enable-unsafe-swiftshader'],
  });
  const alice = await openClient(browser, 'Alice Laptop', roomCode);
  await alice.getByText(/Connected ·/).first().waitFor({ timeout: 30000 });
  const bob = await openClient(browser, 'Bob Browser', roomCode);
  await bob.getByText(/Connected ·/).first().waitFor({ timeout: 30000 });
  await sleep(6000);

  let ps = await participants(roomCode);
  check('2 participants in LiveKit room', ps.length === 2, JSON.stringify(ps.map((p) => p.name)));
  check('each participant publishes camera + mic', ps.every((p) => p.tracks.length === 2 && p.tracks.every((t) => !t.muted)), JSON.stringify(ps.map((p) => p.tracks)));
  check('identities are server-issued guest ids', ps.every((p) => /^guest-[0-9a-f]{16}$/.test(p.identity)));

  for (const [name, page] of [['Alice', alice], ['Bob', bob]]) {
    const v = await videoStats(page);
    const live = v.filter((x) => x.w > 0 && x.playing && x.t > 0);
    check(`${name} renders local + remote video`, live.length >= 2, JSON.stringify(v));
    const remoteAudio = await page.evaluate(() => [...document.querySelectorAll('audio')].filter((a) => a.srcObject && !a.paused).length);
    check(`${name} plays remote audio`, remoteAudio >= 1, `audio elements playing=${remoteAudio}`);
  }
  await alice.screenshot({ path: `${OUT}/alice-in-call.png` });
  await bob.screenshot({ path: `${OUT}/bob-in-call.png` });

  // Mute Alice's mic, turn off Bob's camera, and confirm via the server.
  await alice.getByRole('button', { name: 'Mute microphone' }).click();
  await bob.getByRole('button', { name: 'Turn camera off' }).click();
  await sleep(2500);
  ps = await participants(roomCode);
  const a = ps.find((p) => p.name === 'Alice Laptop');
  const b = ps.find((p) => p.name === 'Bob Browser');
  const aMic = a?.tracks.find((t) => t.type === 0);
  const bCam = b?.tracks.find((t) => t.type === 1);
  check('mute mic is seen by the server', !aMic || aMic.muted === true, JSON.stringify(a?.tracks));
  check('camera off is seen by the server', !bCam || bCam.muted === true, JSON.stringify(b?.tracks));
  await alice.screenshot({ path: `${OUT}/alice-after-toggles.png` });

  await alice.getByRole('button', { name: 'Unmute microphone' }).click();
  await bob.getByRole('button', { name: 'Turn camera on' }).click();
  await sleep(2500);
  ps = await participants(roomCode);
  check('unmute + camera on restore tracks', ps.every((p) => p.tracks.filter((t) => !t.muted).length === 2), JSON.stringify(ps.map((p) => p.tracks)));

  // Bob leaves via the confirm dialog.
  await bob.getByRole('button', { name: 'Leave meeting' }).click();
  await bob.getByRole('button', { name: 'Leave', exact: true }).click();
  await bob.getByRole('button', { name: 'New meeting' }).waitFor({ timeout: 10000 });
  await sleep(1500);
  ps = await participants(roomCode);
  check('leave removes participant', ps.length === 1 && ps[0].name === 'Alice Laptop', JSON.stringify(ps.map((p) => p.name)));
  await alice.screenshot({ path: `${OUT}/alice-after-bob-left.png` });

  // Unknown room is refused before any LiveKit connection is made.
  const intruder = await openClient(browser, 'Mallory', 'zzzz-zzzz-zzzz');
  await intruder.getByText(/does not exist or has expired/).first().waitFor({ timeout: 15000 });
  check('unknown room code is refused with a clear message', true);
  await intruder.screenshot({ path: `${OUT}/unknown-room.png` });

  await browser.close();
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch(async (e) => {
  console.error('E2E ERROR', e);
  for (const [i, pg] of (global.__pages || []).entries()) {
    await pg.screenshot({ path: `${OUT}/error-${i}.png` }).catch(() => {});
    console.log(`page ${i} text:`, await pg.evaluate(() => document.body.innerText).catch(() => ''));
  }
  process.exit(2);
});
