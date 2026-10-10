import { randomBytes } from 'node:crypto';
import { pino } from 'pino';
import { createApp } from '../src/app.js';
import { initFirebase } from '../src/services/firebase.js';
import { LiveKitTokenIssuer, type LiveKitAdmin } from '../src/services/livekit.js';
import { RoomService } from '../src/services/rooms.js';

export const PROJECT_ID = 'demo-connectcall';
export const API_KEY = 'test-key';
export const API_SECRET = 'test-secret-that-is-long-enough-for-hs256';

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Tests need the Firebase emulators. Run `npm test` (it starts them) instead of calling node directly.');
}

/** Records owner actions instead of calling a real LiveKit server. */
export class FakeLiveKitAdmin implements LiveKitAdmin {
  removed: Array<[string, string]> = [];
  ended: string[] = [];
  async removeParticipant(room: string, identity: string) {
    this.removed.push([room, identity]);
  }
  async endCall(room: string) {
    this.ended.push(room);
  }
}

export function setup(now?: () => Date) {
  const { auth, db } = initFirebase(PROJECT_ID);
  const livekit = new FakeLiveKitAdmin();
  const rooms = new RoomService(
    db,
    new LiveKitTokenIssuer('wss://example.livekit.cloud', API_KEY, API_SECRET, 600),
    livekit,
    now,
  );
  const app = createApp({
    env: { CORS_ORIGINS: ['http://localhost:5000'], TRUST_PROXY: 0 },
    logger: pino({ level: 'silent' }),
    auth,
    rooms,
  });
  return { app, auth, db, livekit };
}

export interface TestUser {
  uid: string;
  email: string;
  idToken: string;
  bearer: string;
}

/** Creates an account in the Auth emulator and returns a real ID token for it. */
export async function newUser(displayName?: string): Promise<TestUser> {
  const email = `t${randomBytes(6).toString('hex')}@example.test`;
  const base = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1`;
  const post = async (path: string, body: object) => {
    const res = await fetch(`${base}/${path}?key=fake`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    return (await res.json()) as { idToken: string; localId: string };
  };
  const password = 'correct-horse-battery';
  let result = await post('accounts:signUp', { email, password, returnSecureToken: true });
  if (displayName) {
    await post('accounts:update', { idToken: result.idToken, displayName });
    // Sign in again so the ID token carries the new name claim.
    result = await post('accounts:signInWithPassword', { email, password, returnSecureToken: true });
  }
  return { uid: result.localId, email, idToken: result.idToken, bearer: `Bearer ${result.idToken}` };
}
