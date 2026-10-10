import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { TokenVerifier } from 'livekit-server-sdk';
import request from 'supertest';
import { API_KEY, API_SECRET, newUser, setup } from './helpers.js';

const { app, auth, livekit } = setup();

async function createRoom(bearer: string, body: object = { name: 'Team sync' }) {
  const res = await request(app).post('/api/rooms').set('Authorization', bearer).send(body);
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.id as string;
}

async function createInvite(bearer: string, roomId: string, body: object = {}) {
  const res = await request(app).post(`/api/rooms/${roomId}/invites`).set('Authorization', bearer).send(body);
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.id as string;
}

async function join(bearer: string, inviteId: string, expected = 200) {
  return request(app).post(`/api/invites/${inviteId}/accept`).set('Authorization', bearer).expect(expected);
}

async function token(bearer: string, roomId: string, expected: number) {
  return request(app).post(`/api/rooms/${roomId}/token`).set('Authorization', bearer).expect(expected);
}

describe('authentication', () => {
  it('rejects missing, malformed and forged tokens', async () => {
    await request(app).get('/api/me').expect(401);
    await request(app).get('/api/me').set('Authorization', 'Bearer nonsense').expect(401);
    const forged = 'eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0.';
    const res = await request(app).get('/api/me').set('Authorization', `Bearer ${forged}`).expect(401);
    assert.equal(res.body.error.code, 'unauthenticated');
  });

  it('accepts a real ID token and creates a profile from it', async () => {
    const u = await newUser('Ana Lima');
    const res = await request(app).get('/api/me').set('Authorization', u.bearer).expect(200);
    assert.equal(res.body.uid, u.uid);
    assert.equal(res.body.displayName, 'Ana Lima');
  });

  it('rejects tokens after the session is revoked (sign out everywhere)', async () => {
    const u = await newUser('Revoked');
    await request(app).get('/api/me').set('Authorization', u.bearer).expect(200);
    await new Promise((r) => setTimeout(r, 1100)); // revocation has 1-second granularity
    await auth.revokeRefreshTokens(u.uid);
    const res = await request(app).get('/api/me').set('Authorization', u.bearer).expect(401);
    assert.equal(res.body.error.code, 'session_revoked');
  });

  it('health check needs no auth', async () => {
    await request(app).get('/healthz').expect(200, { status: 'ok' });
  });
});

describe('profile', () => {
  it('validates and saves display name and photo URL', async () => {
    const u = await newUser();
    const put = (body: object) => request(app).put('/api/me/profile').set('Authorization', u.bearer).send(body);
    await put({ displayName: '' }).expect(400);
    await put({ displayName: 'Bo', photoUrl: 'http://insecure.example/a.png' }).expect(400);
    await put({ displayName: 'Bo', role: 'admin' }).expect(400);
    const ok = await put({ displayName: 'Bo Chen', photoUrl: 'https://example.com/bo.png' }).expect(200);
    assert.equal(ok.body.displayName, 'Bo Chen');
    const me = await request(app).get('/api/me').set('Authorization', u.bearer).expect(200);
    assert.equal(me.body.photoUrl, 'https://example.com/bo.png');
  });
});

describe('rooms and tokens', () => {
  it('owner can create a room, list it and get a token scoped to it', async () => {
    const owner = await newUser('Owner');
    const roomId = await createRoom(owner.bearer);
    const list = await request(app).get('/api/rooms').set('Authorization', owner.bearer).expect(200);
    assert.deepEqual(list.body.rooms[0], { id: roomId, name: 'Team sync', role: 'owner' });

    const tok = await token(owner.bearer, roomId, 200);
    assert.equal(tok.body.identity, owner.uid);
    const claims = await new TokenVerifier(API_KEY, API_SECRET).verify(tok.body.token);
    assert.equal(claims.sub, owner.uid);
    assert.equal(claims.name, 'Owner');
    assert.equal(claims.video?.room, roomId);
    assert.ok(!claims.video?.roomAdmin && !claims.video?.roomCreate, 'no admin rights');
    assert.ok(Number(claims.exp) - Number(claims.nbf ?? claims.iat) <= 600, 'short-lived');
  });

  it('a signed-in stranger cannot see the room or get a token', async () => {
    const owner = await newUser('Owner');
    const stranger = await newUser('Stranger');
    const roomId = await createRoom(owner.bearer);
    for (const path of ['', '/members', '/invites', '/waiting']) {
      const r = await request(app).get(`/api/rooms/${roomId}${path}`).set('Authorization', stranger.bearer);
      assert.equal(r.status, 404, path);
    }
    const t = await token(stranger.bearer, roomId, 404);
    assert.equal(t.body.token, undefined);
    // Unknown and malformed ids look the same as a private room.
    await token(stranger.bearer, 'AAAAAAAAAAAAAAAAAAAA', 404);
    await token(stranger.bearer, 'bad%20id', 404);
  });

  it('validates room input', async () => {
    const u = await newUser();
    const bad = [{ name: '' }, { name: 'x'.repeat(61) }, { name: 'ok', extra: 1 }, { name: 'ok', requireApproval: 'yes' }];
    for (const body of bad) {
      await request(app).post('/api/rooms').set('Authorization', u.bearer).send(body).expect(400);
    }
  });
});

describe('invitations', () => {
  it('invite → accept → member can get a token; uses are counted', async () => {
    const owner = await newUser('Owner');
    const guest = await newUser('Guest');
    const roomId = await createRoom(owner.bearer);
    const inviteId = await createInvite(owner.bearer, roomId, { maxUses: 2, expiresInHours: 1 });
    assert.match(inviteId, /^[A-Za-z0-9_-]{22}$/);

    const preview = await request(app).get(`/api/invites/${inviteId}`).set('Authorization', guest.bearer).expect(200);
    assert.equal(preview.body.roomName, 'Team sync');
    assert.equal(preview.body.ownerName, 'Owner');
    assert.equal(preview.body.status, 'valid');
    assert.equal(preview.body.alreadyMember, false);

    const acc = await join(guest.bearer, inviteId);
    assert.deepEqual(acc.body, { roomId, status: 'member' });
    await join(guest.bearer, inviteId); // accepting twice does not use it up again

    await token(guest.bearer, roomId, 200);
    const invites = await request(app).get(`/api/rooms/${roomId}/invites`).set('Authorization', owner.bearer).expect(200);
    assert.equal(invites.body.invites[0].uses, 1);
    const members = await request(app).get(`/api/rooms/${roomId}/members`).set('Authorization', guest.bearer).expect(200);
    assert.deepEqual(members.body.members.map((m: { role: string }) => m.role).sort(), ['member', 'owner']);
  });

  it('only the owner can create, list or revoke invitations', async () => {
    const owner = await newUser('Owner');
    const member = await newUser('Member');
    const roomId = await createRoom(owner.bearer);
    const inviteId = await createInvite(owner.bearer, roomId);
    await join(member.bearer, inviteId);
    const as = (r: request.Test) => r.set('Authorization', member.bearer);
    await as(request(app).post(`/api/rooms/${roomId}/invites`).send({})).expect(403);
    await as(request(app).get(`/api/rooms/${roomId}/invites`)).expect(403);
    await as(request(app).post(`/api/rooms/${roomId}/invites/${inviteId}/revoke`)).expect(403);
  });

  it('revoked, expired and used-up invitations are refused', async () => {
    let now = new Date();
    const timed = setup(() => now).app;
    const owner = await newUser('Owner');
    const roomId = (await request(timed).post('/api/rooms').set('Authorization', owner.bearer).send({ name: 'R' })).body.id;
    const create = async (body: object) =>
      (await request(timed).post(`/api/rooms/${roomId}/invites`).set('Authorization', owner.bearer).send(body)).body
        .id as string;

    const revoked = await create({});
    await request(timed)
      .post(`/api/rooms/${roomId}/invites/${revoked}/revoke`)
      .set('Authorization', owner.bearer)
      .expect(204);
    const once = await create({ maxUses: 1 });
    const expiring = await create({ expiresInHours: 1 });

    const first = await newUser('First');
    await request(timed).post(`/api/invites/${once}/accept`).set('Authorization', first.bearer).expect(200);

    now = new Date(now.getTime() + 61 * 60_000);
    const late = await newUser('Late');
    const cases: Array<[string, string]> = [
      [revoked, 'invite_revoked'],
      [once, 'invite_used_up'],
      [expiring, 'invite_expired'],
    ];
    for (const [id, code] of cases) {
      const res = await request(timed).post(`/api/invites/${id}/accept`).set('Authorization', late.bearer);
      assert.equal(res.status, 410, code);
      assert.equal(res.body.error.code, code);
    }
    await request(timed).post(`/api/rooms/${roomId}/token`).set('Authorization', late.bearer).expect(404);
    await request(timed).post('/api/invites/AAAAAAAAAAAAAAAAAAAAAA/accept').set('Authorization', late.bearer).expect(404);
  });

  it('concurrent accepts cannot exceed maxUses', async () => {
    const owner = await newUser('Owner');
    const roomId = await createRoom(owner.bearer);
    const inviteId = await createInvite(owner.bearer, roomId, { maxUses: 1 });
    const users = await Promise.all([newUser('A'), newUser('B'), newUser('C')]);
    const results = await Promise.all(
      users.map((u) => request(app).post(`/api/invites/${inviteId}/accept`).set('Authorization', u.bearer)),
    );
    const statuses = results.map((r) => r.status);
    assert.equal(statuses.filter((s) => s === 200).length, 1, JSON.stringify(statuses));
  });
});

describe('waiting room', () => {
  it('approval rooms hold guests until the owner approves or denies', async () => {
    const owner = await newUser('Owner');
    const alice = await newUser('Alice');
    const bob = await newUser('Bob');
    const roomId = await createRoom(owner.bearer, { name: 'Private', requireApproval: true });
    const inviteId = await createInvite(owner.bearer, roomId);

    for (const u of [alice, bob]) {
      const r = await join(u.bearer, inviteId);
      assert.equal(r.body.status, 'waiting');
      await token(u.bearer, roomId, 404);
    }
    await request(app).get(`/api/rooms/${roomId}/waiting`).set('Authorization', alice.bearer).expect(404);
    const waiting = await request(app).get(`/api/rooms/${roomId}/waiting`).set('Authorization', owner.bearer).expect(200);
    const names = waiting.body.waiting.map((w: { displayName: string }) => w.displayName).sort();
    assert.deepEqual(names, ['Alice', 'Bob']);

    const decide = (uid: string, d: string) =>
      request(app).post(`/api/rooms/${roomId}/waiting/${uid}/${d}`).set('Authorization', owner.bearer);
    await decide(alice.uid, 'approve').expect(204);
    await decide(bob.uid, 'deny').expect(204);
    await token(alice.bearer, roomId, 200);
    await token(bob.bearer, roomId, 404);
  });
});

describe('participant management', () => {
  it('owner removes a member: access ends, they are kicked from the call, the invite stops working for them', async () => {
    const owner = await newUser('Owner');
    const guest = await newUser('Guest');
    const roomId = await createRoom(owner.bearer);
    const inviteId = await createInvite(owner.bearer, roomId);
    await join(guest.bearer, inviteId);

    await request(app).delete(`/api/rooms/${roomId}/members/${owner.uid}`).set('Authorization', guest.bearer).expect(403);
    await request(app).delete(`/api/rooms/${roomId}/members/${guest.uid}`).set('Authorization', owner.bearer).expect(204);
    assert.deepEqual(livekit.removed.at(-1), [roomId, guest.uid]);

    await token(guest.bearer, roomId, 404);
    const again = await join(guest.bearer, inviteId, 403);
    assert.equal(again.body.error.code, 'blocked');
    const list = await request(app).get('/api/rooms').set('Authorization', guest.bearer).expect(200);
    assert.equal(list.body.rooms.length, 0);
  });

  it('members can leave; the owner cannot', async () => {
    const owner = await newUser('Owner');
    const guest = await newUser('Guest');
    const roomId = await createRoom(owner.bearer);
    const inviteId = await createInvite(owner.bearer, roomId);
    await join(guest.bearer, inviteId);
    await request(app).delete(`/api/rooms/${roomId}/members/me`).set('Authorization', owner.bearer).expect(400);
    await request(app).delete(`/api/rooms/${roomId}/members/me`).set('Authorization', guest.bearer).expect(204);
    await join(guest.bearer, inviteId); // leaving is not a ban
  });

  it('only the owner can end the call for everyone', async () => {
    const owner = await newUser('Owner');
    const guest = await newUser('Guest');
    const roomId = await createRoom(owner.bearer);
    await join(guest.bearer, await createInvite(owner.bearer, roomId));
    await request(app).post(`/api/rooms/${roomId}/end`).set('Authorization', guest.bearer).expect(403);
    await request(app).post(`/api/rooms/${roomId}/end`).set('Authorization', owner.bearer).expect(204);
    assert.equal(livekit.ended.at(-1), roomId);
  });
});
