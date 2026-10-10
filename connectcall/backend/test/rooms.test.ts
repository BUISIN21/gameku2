import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { TokenVerifier } from 'livekit-server-sdk';
import { pino } from 'pino';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { LiveKitTokenIssuer } from '../src/services/livekit.js';
import { InMemoryRoomStore, normalizeRoomCode, ROOM_CODE_PATTERN } from '../src/services/roomStore.js';

const API_KEY = 'test-key';
const API_SECRET = 'test-secret-that-is-long-enough-for-hs256';

function setup(opts: { createRoomKey?: string; now?: () => number } = {}) {
  const store = new InMemoryRoomStore(60 * 60_000, opts.now);
  const tokens = new LiveKitTokenIssuer('wss://example.livekit.cloud', API_KEY, API_SECRET, 600);
  const app = createApp({
    env: { CORS_ORIGINS: ['http://localhost:5000'], CREATE_ROOM_KEY: opts.createRoomKey ?? '', TRUST_PROXY: 0 },
    logger: pino({ level: 'silent' }),
    store,
    tokens,
  });
  return { app, store };
}

describe('room codes', () => {
  it('normalises user input', () => {
    assert.equal(normalizeRoomCode(' ABCD efgh-JKMN '), 'abcd-efgh-jkmn');
    assert.equal(normalizeRoomCode('abcd-efgh-jkm'), null);
    assert.equal(normalizeRoomCode('abcd-efgh-jkm0'), null, 'ambiguous characters are rejected');
  });
});

describe('POST /api/rooms', () => {
  it('creates a room with a well-formed code', async () => {
    const { app } = setup();
    const res = await request(app).post('/api/rooms').send({ displayName: 'Alice' }).expect(201);
    assert.match(res.body.roomCode, ROOM_CODE_PATTERN);
    assert.ok(Date.parse(res.body.expiresAt) > Date.now());
  });

  it('rejects invalid display names and unknown fields', async () => {
    const { app } = setup();
    await request(app).post('/api/rooms').send({ displayName: '' }).expect(400);
    await request(app).post('/api/rooms').send({ displayName: 'x'.repeat(41) }).expect(400);
    await request(app).post('/api/rooms').send({ displayName: 'Bob\u0000' }).expect(400);
    await request(app).post('/api/rooms').send({ displayName: 'Bob', admin: true }).expect(400);
  });

  it('rejects malformed JSON without leaking details', async () => {
    const { app } = setup();
    const res = await request(app).post('/api/rooms').set('Content-Type', 'application/json').send('{bad').expect(400);
    assert.equal(res.body.error.code, 'bad_request');
  });

  it('enforces the access key when configured', async () => {
    const { app } = setup({ createRoomKey: 'open-sesame' });
    await request(app).post('/api/rooms').send({ displayName: 'Alice' }).expect(401);
    await request(app).post('/api/rooms').set('X-Access-Key', 'wrong').send({ displayName: 'Alice' }).expect(401);
    await request(app).post('/api/rooms').set('X-Access-Key', 'open-sesame').send({ displayName: 'Alice' }).expect(201);
  });
});

describe('POST /api/rooms/:code/join', () => {
  it('issues a LiveKit token scoped to that room only', async () => {
    const { app } = setup();
    const created = await request(app).post('/api/rooms').send({ displayName: 'Alice' }).expect(201);
    const code: string = created.body.roomCode;

    const res = await request(app)
      .post(`/api/rooms/${code.toUpperCase()}/join`)
      .send({ displayName: 'Bob' })
      .expect(200);
    assert.equal(res.body.serverUrl, 'wss://example.livekit.cloud');
    assert.equal(res.body.roomCode, code);

    const claims = await new TokenVerifier(API_KEY, API_SECRET).verify(res.body.token);
    assert.equal(claims.name, 'Bob');
    assert.equal(claims.sub, res.body.identity);
    assert.match(String(claims.sub), /^guest-[0-9a-f]{16}$/);
    assert.equal(claims.video?.room, code);
    assert.equal(claims.video?.roomJoin, true);
    assert.ok(!claims.video?.roomAdmin, 'no admin rights');
    assert.ok(!claims.video?.roomCreate, 'no room-create rights');
    const ttl = Number(claims.exp) - Number(claims.nbf ?? claims.iat);
    assert.ok(ttl > 0 && ttl <= 600, `short-lived token (ttl=${ttl})`);
  });

  it('gives each join a distinct identity', async () => {
    const { app } = setup();
    const { body } = await request(app).post('/api/rooms').send({ displayName: 'Alice' });
    const a = await request(app).post(`/api/rooms/${body.roomCode}/join`).send({ displayName: 'Same' });
    const b = await request(app).post(`/api/rooms/${body.roomCode}/join`).send({ displayName: 'Same' });
    assert.notEqual(a.body.identity, b.body.identity);
  });

  it('refuses unknown, malformed and expired rooms identically', async () => {
    let now = Date.now();
    const { app } = setup({ now: () => now });
    const { body } = await request(app).post('/api/rooms').send({ displayName: 'Alice' });

    const unknown = await request(app).post('/api/rooms/abcd-efgh-jkmn/join').send({ displayName: 'Bob' });
    const malformed = await request(app).post('/api/rooms/nope/join').send({ displayName: 'Bob' });
    now += 61 * 60_000;
    const expired = await request(app).post(`/api/rooms/${body.roomCode}/join`).send({ displayName: 'Bob' });

    for (const res of [unknown, malformed, expired]) {
      assert.equal(res.status, 404);
      assert.equal(res.body.error.code, 'room_not_found');
      assert.equal(res.body.token, undefined);
    }
  });
});

describe('misc', () => {
  it('health check works and unknown routes 404', async () => {
    const { app } = setup();
    await request(app).get('/healthz').expect(200, { status: 'ok' });
    await request(app).get('/api/nothing').expect(404);
  });

  it('only allows configured CORS origins', async () => {
    const { app } = setup();
    const ok = await request(app).options('/api/rooms').set('Origin', 'http://localhost:5000');
    assert.equal(ok.headers['access-control-allow-origin'], 'http://localhost:5000');
    const bad = await request(app).options('/api/rooms').set('Origin', 'https://evil.example');
    assert.equal(bad.headers['access-control-allow-origin'], undefined);
  });
});

describe('configuration', () => {
  const base = { LIVEKIT_URL: 'wss://x.livekit.cloud', LIVEKIT_API_KEY: 'k', LIVEKIT_API_SECRET: 's' };
  it('requires LiveKit credentials and never echoes values', () => {
    assert.throws(() => loadEnv({ LIVEKIT_URL: 'wss://x', LIVEKIT_API_SECRET: 'super-secret' }), (err: Error) => {
      assert.match(err.message, /LIVEKIT_API_KEY/);
      assert.doesNotMatch(err.message, /super-secret/);
      return true;
    });
  });
  it('rejects insecure ws:// in production', () => {
    assert.throws(() => loadEnv({ ...base, NODE_ENV: 'production', LIVEKIT_URL: 'ws://x:7880' }), /wss/);
    assert.equal(loadEnv({ ...base, NODE_ENV: 'production' }).LIVEKIT_URL, 'wss://x.livekit.cloud');
  });
});
