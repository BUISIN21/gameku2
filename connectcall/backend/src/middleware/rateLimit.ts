import type { Request, Response } from 'express';
import { ipKeyGenerator, rateLimit } from 'express-rate-limit';

const handler = (_req: Request, res: Response) =>
  res.status(429).json({ error: { code: 'rate_limited', message: 'Too many requests, slow down' } });

/** Signed-in routes are limited per user, so people behind one NAT don't share a budget. */
const byUser = (req: Request) => req.user?.uid ?? ipKeyGenerator(req.ip ?? '');

const common = { standardHeaders: 'draft-8' as const, legacyHeaders: false, handler };

/** Baseline limit for every API route, per IP (runs before authentication). */
export const apiLimiter = rateLimit({ ...common, windowMs: 60_000, limit: 300 });

export const createRoomLimiter = rateLimit({ ...common, windowMs: 10 * 60_000, limit: 20, keyGenerator: byUser });

export const tokenLimiter = rateLimit({ ...common, windowMs: 60_000, limit: 30, keyGenerator: byUser });

export const acceptInviteLimiter = rateLimit({ ...common, windowMs: 60_000, limit: 30, keyGenerator: byUser });
