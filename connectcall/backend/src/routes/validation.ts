import { z } from 'zod';
import { HttpError } from '../middleware/errors.js';

export const DisplayName = z
  .string()
  .trim()
  .min(1, 'Display name is required')
  .max(40, 'Display name must be at most 40 characters')
  // Letters, marks, numbers, spaces and a few punctuation marks; no control characters.
  .regex(/^[\p{L}\p{M}\p{N} .,'_-]+$/u, 'Display name contains unsupported characters');

export const RoomName = z
  .string()
  .trim()
  .min(1, 'Room name is required')
  .max(60, 'Room name must be at most 60 characters')
  .regex(/^[\p{L}\p{M}\p{N}\p{Zs}.,'!?&()_#:-]+$/u, 'Room name contains unsupported characters');

export const PhotoUrl = z
  .string()
  .trim()
  .max(500)
  .url()
  .refine((u) => u.startsWith('https://'), 'Photo URL must use https://')
  .nullable();

export const RoomId = z.string().regex(/^[A-Za-z0-9]{20}$/);
export const InviteId = z.string().regex(/^[A-Za-z0-9_-]{22}$/);
export const Uid = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);

export function parseBody<T>(schema: z.ZodType<T>, body: unknown): T {
  const result = schema.safeParse(body ?? {});
  if (!result.success) {
    throw new HttpError(400, 'invalid_request', result.error.issues[0]?.message ?? 'Invalid request');
  }
  return result.data;
}

/** Validates a path parameter; malformed ids get the same 404 as unknown ones. */
export function parseParam<T>(schema: z.ZodType<T>, value: unknown, notFound: [string, string]): T {
  const result = schema.safeParse(value);
  if (!result.success) throw new HttpError(404, notFound[0], notFound[1]);
  return result.data;
}
