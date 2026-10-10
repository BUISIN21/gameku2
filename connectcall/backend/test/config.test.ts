import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { loadEnv } from '../src/config/env.js';

describe('configuration', () => {
  const base = {
    LIVEKIT_URL: 'wss://x.livekit.cloud',
    LIVEKIT_API_KEY: 'k',
    LIVEKIT_API_SECRET: 's',
    FIREBASE_PROJECT_ID: 'my-project',
  };

  it('requires credentials and never echoes values', () => {
    assert.throws(() => loadEnv({ LIVEKIT_URL: 'wss://x', LIVEKIT_API_SECRET: 'super-secret' }), (err: Error) => {
      assert.match(err.message, /LIVEKIT_API_KEY/);
      assert.match(err.message, /FIREBASE_PROJECT_ID/);
      assert.doesNotMatch(err.message, /super-secret/);
      return true;
    });
  });

  it('refuses insecure or emulator settings in production', () => {
    assert.throws(() => loadEnv({ ...base, NODE_ENV: 'production', LIVEKIT_URL: 'ws://x:7880' }), /wss/);
    assert.throws(
      () => loadEnv({ ...base, NODE_ENV: 'production', FIRESTORE_EMULATOR_HOST: 'localhost:8085' }),
      /emulator/,
    );
    assert.equal(loadEnv({ ...base, NODE_ENV: 'production' }).FIREBASE_PROJECT_ID, 'my-project');
  });
});
