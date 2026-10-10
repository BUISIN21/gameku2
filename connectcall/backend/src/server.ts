import 'dotenv/config';
import { pino } from 'pino';
import { createApp } from './app.js';
import { loadEnv } from './config/env.js';
import { LiveKitTokenIssuer } from './services/livekit.js';
import { InMemoryRoomStore } from './services/roomStore.js';

const env = loadEnv();
const logger = pino({
  level: env.LOG_LEVEL,
  // Defence in depth: scrub anything that looks like a credential.
  redact: ['token', '*.token', 'req.headers.authorization', 'req.headers["x-access-key"]'],
});

const app = createApp({
  env,
  logger,
  store: new InMemoryRoomStore(env.ROOM_TTL_MINUTES * 60_000),
  tokens: new LiveKitTokenIssuer(env.LIVEKIT_URL, env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, env.TOKEN_TTL_SECONDS),
});

const server = app.listen(env.PORT, () => {
  logger.info(
    { port: env.PORT, livekitUrl: env.LIVEKIT_URL, roomCreationKeyRequired: env.CREATE_ROOM_KEY !== '' },
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
