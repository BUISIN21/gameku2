import { Router } from 'express';
import { z } from 'zod';
import type { RoomService } from '../services/rooms.js';
import { DisplayName, parseBody, PhotoUrl } from './validation.js';

const UpdateProfile = z.object({ displayName: DisplayName, photoUrl: PhotoUrl.default(null) }).strict();

export function meRouter(rooms: RoomService) {
  const router = Router();

  router.get('/', async (req, res) => {
    const profile = await rooms.getProfile(req.user!);
    res.json({ ...profile, email: req.user!.email ?? null });
  });

  router.put('/profile', async (req, res) => {
    const body = parseBody(UpdateProfile, req.body);
    res.json(await rooms.updateProfile(req.user!.uid, body));
  });

  return router;
}
