import { rateLimit } from 'express-rate-limit';

const handler = (_req: unknown, res: { status: (n: number) => { json: (b: unknown) => void } }) =>
  res.status(429).json({ error: { code: 'rate_limited', message: 'Too many requests, slow down' } });

/** Baseline limit for every API route. */
export const apiLimiter = rateLimit({
  windowMs: 60_000,
  limit: 120,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  handler,
});

/** Room creation is cheap to abuse, so it gets a tighter budget. */
export const createRoomLimiter = rateLimit({
  windowMs: 10 * 60_000,
  limit: 20,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  handler,
});

/** Join attempts are limited to make guessing room codes impractical. */
export const joinLimiter = rateLimit({
  windowMs: 60_000,
  limit: 30,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  handler,
});
