import { Router } from 'express';
import { z } from 'zod';
import { requireAccessKey } from '../middleware/accessKey.js';
import { HttpError } from '../middleware/errors.js';
import { createRoomLimiter, joinLimiter } from '../middleware/rateLimit.js';
import { newGuestIdentity, type TokenIssuer } from '../services/livekit.js';
import { normalizeRoomCode, RoomLimitError, type InMemoryRoomStore } from '../services/roomStore.js';

const DisplayName = z
  .string()
  .trim()
  .min(1, 'Display name is required')
  .max(40, 'Display name must be at most 40 characters')
  // Letters, marks, numbers, spaces and a few punctuation marks; no control characters.
  .regex(/^[\p{L}\p{M}\p{N} .,'_-]+$/u, 'Display name contains unsupported characters');

const CreateRoomBody = z.object({ displayName: DisplayName }).strict();
const JoinRoomBody = z.object({ displayName: DisplayName }).strict();

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const result = schema.safeParse(body ?? {});
  if (!result.success) {
    throw new HttpError(400, 'invalid_request', result.error.issues[0]?.message ?? 'Invalid request');
  }
  return result.data;
}

export function roomsRouter(deps: { store: InMemoryRoomStore; tokens: TokenIssuer; createRoomKey: string }) {
  const router = Router();

  router.post('/', createRoomLimiter, requireAccessKey(deps.createRoomKey), (req, res) => {
    const { displayName } = parse(CreateRoomBody, req.body);
    try {
      const room = deps.store.create(displayName);
      req.log.info({ room: room.code }, 'room created');
      res.status(201).json({ roomCode: room.code, expiresAt: new Date(room.expiresAt).toISOString() });
    } catch (err) {
      if (err instanceof RoomLimitError) throw new HttpError(503, 'room_limit', 'Server is at capacity, try later');
      throw err;
    }
  });

  router.post('/:code/join', joinLimiter, async (req, res) => {
    const { displayName } = parse(JoinRoomBody, req.body);
    const code = normalizeRoomCode(String(req.params.code ?? ''));
    // Unknown, malformed and expired codes give the same answer so the
    // endpoint does not reveal which codes exist.
    const room = code ? deps.store.get(code) : undefined;
    if (!room) throw new HttpError(404, 'room_not_found', 'Room not found or expired');

    const identity = newGuestIdentity();
    const token = await deps.tokens.createJoinToken({ roomName: room.code, identity, displayName });
    req.log.info({ room: room.code, identity }, 'join token issued');
    res.json({ serverUrl: deps.tokens.serverUrl, token, roomCode: room.code, identity });
  });

  return router;
}
