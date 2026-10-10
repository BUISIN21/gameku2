import 'dotenv/config';
import { pino } from 'pino';
import { createApp } from './app.js';
import { loadEnv } from './config/env.js';
import { initFirebase } from './services/firebase.js';
import { LiveKitRoomAdmin, LiveKitTokenIssuer } from './services/livekit.js';
import { RoomService } from './services/rooms.js';

const env = loadEnv();
const logger = pino({
  level: env.LOG_LEVEL,
  // Defence in depth: scrub anything that looks like a credential.
  redact: ['token', '*.token', 'req.headers.authorization'],
});

const { auth, db } = initFirebase(env.FIREBASE_PROJECT_ID);
const rooms = new RoomService(
  db,
  new LiveKitTokenIssuer(env.LIVEKIT_URL, env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, env.TOKEN_TTL_SECONDS),
  new LiveKitRoomAdmin(env.LIVEKIT_URL, env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET),
);

const app = createApp({ env, logger, auth, rooms });

const server = app.listen(env.PORT, () => {
  logger.info(
    {
      port: env.PORT,
      livekitUrl: env.LIVEKIT_URL,
      firebaseProject: env.FIREBASE_PROJECT_ID,
      emulators: Boolean(env.FIRESTORE_EMULATOR_HOST || env.FIREBASE_AUTH_EMULATOR_HOST),
    },
    'ConnectCall API listening',
  );
});

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    logger.info({ signal }, 'shutting down');
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10_000).unref();
  });
}
