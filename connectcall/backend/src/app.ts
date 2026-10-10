import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import { pinoHttp } from 'pino-http';
import type { Auth } from 'firebase-admin/auth';
import type { Logger } from 'pino';
import type { Env } from './config/env.js';
import { requireUser } from './middleware/auth.js';
import { errorHandler, notFound } from './middleware/errors.js';
import { apiLimiter } from './middleware/rateLimit.js';
import { invitesRouter } from './routes/invites.js';
import { meRouter } from './routes/me.js';
import { roomsRouter } from './routes/rooms.js';
import type { RoomService } from './services/rooms.js';

export interface AppDeps {
  env: Pick<Env, 'CORS_ORIGINS' | 'TRUST_PROXY'>;
  logger: Logger;
  auth: Auth;
  rooms: RoomService;
}

export function createApp(deps: AppDeps) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', deps.env.TRUST_PROXY);

  app.use(
    pinoHttp({
      logger: deps.logger,
      // Never log headers (they carry ID tokens) or bodies.
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
      methods: ['GET', 'POST', 'PUT', 'DELETE'],
      allowedHeaders: ['Content-Type', 'Authorization'],
      maxAge: 600,
    }),
  );
  app.use(express.json({ limit: '10kb' }));

  app.get('/healthz', (_req, res) => {
    res.json({ status: 'ok' });
  });

  // Every /api route requires a verified Firebase user.
  app.use('/api', apiLimiter, requireUser(deps.auth));
  app.use('/api/me', meRouter(deps.rooms));
  app.use('/api/rooms', roomsRouter(deps.rooms));
  app.use('/api/invites', invitesRouter(deps.rooms));

  app.use(notFound);
  app.use(errorHandler);
  return app;
}
