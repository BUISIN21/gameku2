import { Router } from 'express';
import { z } from 'zod';
import { createRoomLimiter, tokenLimiter } from '../middleware/rateLimit.js';
import type { RoomService } from '../services/rooms.js';
import { InviteId, parseBody, parseParam, RoomId, RoomName, Uid } from './validation.js';

const CreateRoom = z.object({ name: RoomName, requireApproval: z.boolean().default(false) }).strict();
const CreateInvite = z
  .object({
    expiresInHours: z.number().int().min(1).max(168).default(24),
    maxUses: z.number().int().min(1).max(100).default(10),
  })
  .strict();

const ROOM_404: [string, string] = ['room_not_found', 'Room not found or you are not a member'];

export function roomsRouter(rooms: RoomService) {
  const router = Router();
  const roomId = (v: unknown) => parseParam(RoomId, v, ROOM_404);
  const uid = (v: unknown) => parseParam(Uid, v, ['member_not_found', 'That person is not a member']);

  router.get('/', async (req, res) => {
    res.json({ rooms: await rooms.listMyRooms(req.user!.uid) });
  });

  router.post('/', createRoomLimiter, async (req, res) => {
    const body = parseBody(CreateRoom, req.body);
    const room = await rooms.createRoom(req.user!, body);
    req.log.info({ room: room.id }, 'room created');
    res.status(201).json(room);
  });

  router.get('/:roomId', async (req, res) => {
    res.json(await rooms.getRoom(roomId(req.params.roomId), req.user!.uid));
  });

  router.post('/:roomId/token', tokenLimiter, async (req, res) => {
    const id = roomId(req.params.roomId);
    const result = await rooms.issueToken(id, req.user!);
    req.log.info({ room: id, uid: req.user!.uid }, 'join token issued');
    res.json(result);
  });

  router.post('/:roomId/end', async (req, res) => {
    const id = roomId(req.params.roomId);
    await rooms.endCall(id, req.user!.uid);
    req.log.info({ room: id }, 'call ended by owner');
    res.status(204).end();
  });

  // Members
  router.get('/:roomId/members', async (req, res) => {
    res.json({ members: await rooms.listMembers(roomId(req.params.roomId), req.user!.uid) });
  });

  router.delete('/:roomId/members/:uid', async (req, res) => {
    const id = roomId(req.params.roomId);
    const target = req.params.uid === 'me' ? req.user!.uid : uid(req.params.uid);
    await rooms.removeMember(id, req.user!.uid, target);
    req.log.info({ room: id, target, self: target === req.user!.uid }, 'member removed');
    res.status(204).end();
  });

  // Invitations (owner only)
  router.get('/:roomId/invites', async (req, res) => {
    res.json({ invites: await rooms.listInvites(roomId(req.params.roomId), req.user!.uid) });
  });

  router.post('/:roomId/invites', async (req, res) => {
    const body = parseBody(CreateInvite, req.body);
    const invite = await rooms.createInvite(roomId(req.params.roomId), req.user!.uid, body);
    res.status(201).json(invite);
  });

  router.post('/:roomId/invites/:inviteId/revoke', async (req, res) => {
    const invite = parseParam(InviteId, req.params.inviteId, ['invite_not_found', 'Invitation not found']);
    await rooms.revokeInvite(roomId(req.params.roomId), req.user!.uid, invite);
    res.status(204).end();
  });

  // Waiting room (owner only)
  router.get('/:roomId/waiting', async (req, res) => {
    res.json({ waiting: await rooms.listWaiting(roomId(req.params.roomId), req.user!.uid) });
  });

  router.post('/:roomId/waiting/:uid/:decision', async (req, res) => {
    const decision = req.params.decision;
    if (decision !== 'approve' && decision !== 'deny') {
      res.status(404).json({ error: { code: 'not_found', message: 'Route not found' } });
      return;
    }
    await rooms.decideWaiting(roomId(req.params.roomId), req.user!.uid, uid(req.params.uid), decision === 'approve');
    res.status(204).end();
  });

  return router;
}
