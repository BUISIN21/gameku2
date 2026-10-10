import type { Auth, DecodedIdToken } from 'firebase-admin/auth';
import type { RequestHandler } from 'express';
import { HttpError } from './errors.js';

declare module 'express-serve-static-core' {
  interface Request {
    user?: { uid: string; email?: string; name?: string };
  }
}

/**
 * Requires `Authorization: Bearer <Firebase ID token>`. The token's signature,
 * expiry, audience (our project) and revocation status are all checked, so a
 * signed-out or disabled user is rejected immediately.
 */
export function requireUser(auth: Auth): RequestHandler {
  return async (req, _res, next) => {
    const header = req.get('authorization') ?? '';
    const match = /^Bearer (.+)$/.exec(header);
    if (!match) return next(new HttpError(401, 'unauthenticated', 'Sign in required'));
    let decoded: DecodedIdToken;
    try {
      decoded = await auth.verifyIdToken(match[1]!, true);
    } catch (err) {
      const code = (err as { code?: string }).code;
      if (code === 'auth/id-token-expired') {
        return next(new HttpError(401, 'token_expired', 'Your session expired, please sign in again'));
      }
      if (code === 'auth/id-token-revoked' || code === 'auth/user-disabled') {
        return next(new HttpError(401, 'session_revoked', 'Your session was ended, please sign in again'));
      }
      return next(new HttpError(401, 'unauthenticated', 'Sign in required'));
    }
    req.user = { uid: decoded.uid, email: decoded.email, name: decoded.name as string | undefined };
    next();
  };
}
