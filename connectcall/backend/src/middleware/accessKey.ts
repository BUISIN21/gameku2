import { createHash, timingSafeEqual } from 'node:crypto';
import type { RequestHandler } from 'express';
import { HttpError } from './errors.js';

const digest = (s: string) => createHash('sha256').update(s).digest();

/**
 * Phase 2 gate for room creation. When `expectedKey` is empty the check is
 * disabled. The key is compared in constant time and is never logged.
 */
export function requireAccessKey(expectedKey: string): RequestHandler {
  const expected = expectedKey ? digest(expectedKey) : null;
  return (req, _res, next) => {
    if (!expected) return next();
    const provided = req.get('x-access-key') ?? '';
    if (provided && timingSafeEqual(digest(provided), expected)) return next();
    next(new HttpError(401, 'invalid_access_key', 'A valid access key is required to create rooms'));
  };
}
