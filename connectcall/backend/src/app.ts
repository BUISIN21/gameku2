import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import { pinoHttp } from 'pino-http';
import type { Logger } from 'pino';
import type { Env } from './config/env.js';
import { errorHandler, notFound } from './middleware/errors.js';
import { apiLimiter } from './middleware/rateLimit.js';
import { roomsRouter } from './routes/rooms.js';
import type { TokenIssuer } from './services/livekit.js';
import type { InMemoryRoomStore } from './services/roomStore.js';

export interface AppDeps {
  env: Pick<Env, 'CORS_ORIGINS' | 'CREATE_ROOM_KEY' | 'TRUST_PROXY'>;
  logger: Logger;
  store: InMemoryRoomStore;
  tokens: TokenIssuer;
}

export function createApp(deps: AppDeps) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', deps.env.TRUST_PROXY);

  app.use(
    pinoHttp({
      logger: deps.logger,
      // Never log headers (they may carry access keys / ID tokens) or bodies.
      serializers: {
        req: (req) => ({ id: req.id, method: req.method, url: req.url }),
        res: (res) => ({ statusCode: res.statusCode }),
      },
      autoLogging: { ignore: (req) => req.url === '/healthz' },
    }),
  );
  app.use(helmet());
  app.use(
    cors({
      origin: deps.env.CORS_ORIGINS,
      methods: ['GET', 'POST'],
      allowedHeaders: ['Content-Type', 'Authorization', 'X-Access-Key'],
      maxAge: 600,
    }),
  );
  app.use(express.json({ limit: '10kb' }));

  app.get('/healthz', (_req, res) => {
    res.json({ status: 'ok' });
  });

  app.use('/api', apiLimiter);
  app.use(
    '/api/rooms',
    roomsRouter({ store: deps.store, tokens: deps.tokens, createRoomKey: deps.env.CREATE_ROOM_KEY }),
  );

  app.use(notFound);
  app.use(errorHandler);
  return app;
}
