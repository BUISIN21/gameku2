import { Router } from 'express';
import { acceptInviteLimiter } from '../middleware/rateLimit.js';
import type { RoomService } from '../services/rooms.js';
import { InviteId, parseParam } from './validation.js';

const INVITE_404: [string, string] = ['invite_not_found', 'This invitation link is not valid'];

export function invitesRouter(rooms: RoomService) {
  const router = Router();

  router.get('/:inviteId', acceptInviteLimiter, async (req, res) => {
    res.json(await rooms.previewInvite(parseParam(InviteId, req.params.inviteId, INVITE_404), req.user!.uid));
  });

  router.post('/:inviteId/accept', acceptInviteLimiter, async (req, res) => {
    const result = await rooms.acceptInvite(parseParam(InviteId, req.params.inviteId, INVITE_404), req.user!);
    req.log.info({ room: result.roomId, uid: req.user!.uid, status: result.status }, 'invite accepted');
    res.json(result);
  });

  return router;
}
