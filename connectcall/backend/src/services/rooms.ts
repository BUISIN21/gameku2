import { randomBytes } from 'node:crypto';
import { FieldValue, Timestamp, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { HttpError } from '../middleware/errors.js';
import type { LiveKitAdmin, TokenIssuer } from './livekit.js';

export type Role = 'owner' | 'member';

export interface AuthUser {
  uid: string;
  email?: string;
  name?: string;
}

export interface Profile {
  uid: string;
  displayName: string;
  photoUrl: string | null;
}

export const LIMITS = {
  ownedRooms: 50,
  activeInvitesPerRoom: 50,
  membersPerRoom: 100,
  waitingPerRoom: 50,
};

const iso = (t: Timestamp | undefined) => (t ? t.toDate().toISOString() : null);

/** A display name derived from the sign-in data, used until the user sets one. */
function fallbackName(user: AuthUser): string {
  const raw = (user.name ?? user.email?.split('@')[0] ?? 'User').replace(/[^\p{L}\p{M}\p{N} .,'_-]/gu, '').trim();
  return (raw || 'User').slice(0, 40);
}

/**
 * All room, membership and invitation logic. Every method takes the verified
 * caller and checks their permission itself, so the HTTP layer cannot forget to.
 *
 * Firestore layout (see firebase/firestore.rules for who can read what):
 *   users/{uid}                          public profile
 *   users/{uid}/memberships/{roomId}     rooms the user belongs to
 *   rooms/{roomId}                       name, owner, settings
 *   rooms/{roomId}/members/{uid}         authorised participants
 *   rooms/{roomId}/waiting/{uid}         join requests awaiting approval
 *   rooms/{roomId}/blocked/{uid}         removed users; invites no longer work for them
 *   invites/{inviteId}                   expiring, revocable, use-limited invitations
 */
export class RoomService {
  constructor(
    private readonly db: Firestore,
    private readonly tokens: TokenIssuer,
    private readonly livekit: LiveKitAdmin,
    private readonly now: () => Date = () => new Date(),
  ) {}

  private users = () => this.db.collection('users');
  private rooms = () => this.db.collection('rooms');
  private invites = () => this.db.collection('invites');
  private room = (id: string) => this.rooms().doc(id);
  private member = (roomId: string, uid: string) => this.room(roomId).collection('members').doc(uid);

  // ---------------------------------------------------------------- profiles

  async getProfile(user: AuthUser): Promise<Profile> {
    const ref = this.users().doc(user.uid);
    const snap = await ref.get();
    if (snap.exists) {
      const d = snap.data()!;
      return { uid: user.uid, displayName: d.displayName, photoUrl: d.photoUrl ?? null };
    }
    const profile = { displayName: fallbackName(user), photoUrl: null };
    await ref.set({ ...profile, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return { uid: user.uid, ...profile };
  }

  async updateProfile(uid: string, update: { displayName: string; photoUrl: string | null }): Promise<Profile> {
    await this.users().doc(uid).set({ ...update, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    // Keep the copies shown in member lists in step with the profile.
    const memberships = await this.users().doc(uid).collection('memberships').get();
    const batch = this.db.batch();
    for (const m of memberships.docs) batch.set(this.member(m.id, uid), { displayName: update.displayName }, { merge: true });
    await batch.commit();
    return { uid, ...update };
  }

  // ---------------------------------------------------------------- rooms

  async createRoom(user: AuthUser, input: { name: string; requireApproval: boolean }) {
    const owned = await this.rooms().where('ownerUid', '==', user.uid).count().get();
    if (owned.data().count >= LIMITS.ownedRooms) {
      throw new HttpError(409, 'room_limit', `You can own at most ${LIMITS.ownedRooms} rooms`);
    }
    const profile = await this.getProfile(user);
    const ref = this.rooms().doc();
    const now = Timestamp.fromDate(this.now());
    const batch = this.db.batch();
    batch.set(ref, {
      name: input.name,
      ownerUid: user.uid,
      ownerName: profile.displayName,
      requireApproval: input.requireApproval,
      createdAt: now,
    });
    batch.set(this.member(ref.id, user.uid), {
      uid: user.uid,
      displayName: profile.displayName,
      role: 'owner',
      joinedAt: now,
    });
    batch.set(this.users().doc(user.uid).collection('memberships').doc(ref.id), {
      roomName: input.name,
      role: 'owner',
      joinedAt: now,
    });
    await batch.commit();
    return { id: ref.id, name: input.name, role: 'owner' as Role, requireApproval: input.requireApproval };
  }

  async listMyRooms(uid: string) {
    const snap = await this.users().doc(uid).collection('memberships').orderBy('joinedAt', 'desc').limit(100).get();
    return snap.docs.map((d) => ({ id: d.id, name: d.get('roomName') as string, role: d.get('role') as Role }));
  }

  /** Loads the room and the caller's role, or refuses if they are not a member. */
  private async requireMember(roomId: string, uid: string) {
    const [room, member] = await Promise.all([this.room(roomId).get(), this.member(roomId, uid).get()]);
    // Non-members get the same answer whether or not the room exists.
    if (!room.exists || !member.exists) throw new HttpError(404, 'room_not_found', 'Room not found or you are not a member');
    return { room: room.data()!, role: member.get('role') as Role };
  }

  private async requireOwner(roomId: string, uid: string) {
    const r = await this.requireMember(roomId, uid);
    if (r.role !== 'owner') throw new HttpError(403, 'not_owner', 'Only the room owner can do this');
    return r;
  }

  async getRoom(roomId: string, uid: string) {
    const { room, role } = await this.requireMember(roomId, uid);
    return {
      id: roomId,
      name: room.name as string,
      ownerUid: room.ownerUid as string,
      ownerName: room.ownerName as string,
      requireApproval: room.requireApproval as boolean,
      createdAt: iso(room.createdAt),
      role,
    };
  }

  async listMembers(roomId: string, uid: string) {
    await this.requireMember(roomId, uid);
    const snap = await this.room(roomId).collection('members').orderBy('joinedAt').limit(LIMITS.membersPerRoom).get();
    return snap.docs.map((d) => ({
      uid: d.id,
      displayName: d.get('displayName') as string,
      role: d.get('role') as Role,
      joinedAt: iso(d.get('joinedAt')),
    }));
  }

  /**
   * The owner removes someone (they are blocked from rejoining via invites and
   * dropped from the live call), or a member removes themselves (leaves the room).
   */
  async removeMember(roomId: string, actorUid: string, targetUid: string) {
    const { role } = await this.requireMember(roomId, actorUid);
    const leaving = actorUid === targetUid;
    if (leaving && role === 'owner') {
      throw new HttpError(400, 'owner_cannot_leave', 'The owner cannot leave their own room');
    }
    if (!leaving && role !== 'owner') throw new HttpError(403, 'not_owner', 'Only the room owner can remove people');

    const target = await this.member(roomId, targetUid).get();
    if (!target.exists) throw new HttpError(404, 'member_not_found', 'That person is not a member');

    const batch = this.db.batch();
    batch.delete(this.member(roomId, targetUid));
    batch.delete(this.users().doc(targetUid).collection('memberships').doc(roomId));
    if (!leaving) {
      batch.set(this.room(roomId).collection('blocked').doc(targetUid), {
        blockedAt: Timestamp.fromDate(this.now()),
        by: actorUid,
      });
    }
    await batch.commit();
    await this.livekit.removeParticipant(roomId, targetUid);
  }

  async endCall(roomId: string, uid: string) {
    await this.requireOwner(roomId, uid);
    await this.livekit.endCall(roomId);
  }

  // ---------------------------------------------------------------- tokens

  /** Issues a short-lived LiveKit token, only to current members. */
  async issueToken(roomId: string, user: AuthUser) {
    const { role } = await this.requireMember(roomId, user.uid);
    const profile = await this.getProfile(user);
    const token = await this.tokens.createJoinToken({
      roomName: roomId,
      identity: user.uid,
      displayName: profile.displayName,
    });
    return { serverUrl: this.tokens.serverUrl, token, roomId, identity: user.uid, role };
  }

  // ---------------------------------------------------------------- invites

  async createInvite(roomId: string, uid: string, input: { expiresInHours: number; maxUses: number }) {
    await this.requireOwner(roomId, uid);
    const now = this.now();
    const active = await this.invites()
      .where('roomId', '==', roomId)
      .where('revoked', '==', false)
      .where('expiresAt', '>', Timestamp.fromDate(now))
      .count()
      .get();
    if (active.data().count >= LIMITS.activeInvitesPerRoom) {
      throw new HttpError(409, 'invite_limit', 'Too many active invitations; revoke some first');
    }
    // 128 random bits: the invitation id is itself the secret.
    const id = randomBytes(16).toString('base64url');
    const expiresAt = Timestamp.fromMillis(now.getTime() + input.expiresInHours * 3600_000);
    await this.invites().doc(id).create({
      roomId,
      createdBy: uid,
      createdAt: Timestamp.fromDate(now),
      expiresAt,
      maxUses: input.maxUses,
      uses: 0,
      revoked: false,
    });
    return { id, roomId, expiresAt: iso(expiresAt), maxUses: input.maxUses, uses: 0, revoked: false };
  }

  async listInvites(roomId: string, uid: string) {
    await this.requireOwner(roomId, uid);
    const snap = await this.invites().where('roomId', '==', roomId).get();
    return snap.docs
      .map((d) => ({
        id: d.id,
        createdAt: iso(d.get('createdAt')),
        expiresAt: iso(d.get('expiresAt')),
        maxUses: d.get('maxUses') as number,
        uses: d.get('uses') as number,
        revoked: d.get('revoked') as boolean,
        status: this.inviteStatus(d.data()),
      }))
      .sort((a, b) => (b.createdAt ?? '').localeCompare(a.createdAt ?? ''));
  }

  async revokeInvite(roomId: string, uid: string, inviteId: string) {
    await this.requireOwner(roomId, uid);
    const ref = this.invites().doc(inviteId);
    const snap = await ref.get();
    if (!snap.exists || snap.get('roomId') !== roomId) throw new HttpError(404, 'invite_not_found', 'Invitation not found');
    await ref.update({ revoked: true, revokedAt: Timestamp.fromDate(this.now()) });
  }

  private inviteStatus(d: FirebaseFirestore.DocumentData): 'valid' | 'revoked' | 'expired' | 'used_up' {
    if (d.revoked) return 'revoked';
    if ((d.expiresAt as Timestamp).toMillis() <= this.now().getTime()) return 'expired';
    if (d.uses >= d.maxUses) return 'used_up';
    return 'valid';
  }

  /** What an invitee sees before accepting. */
  async previewInvite(inviteId: string, uid: string) {
    const invite = await this.invites().doc(inviteId).get();
    if (!invite.exists) throw new HttpError(404, 'invite_not_found', 'This invitation link is not valid');
    const roomId = invite.get('roomId') as string;
    const [room, member] = await Promise.all([this.room(roomId).get(), this.member(roomId, uid).get()]);
    if (!room.exists) throw new HttpError(404, 'invite_not_found', 'This invitation link is not valid');
    return {
      roomId,
      roomName: room.get('name') as string,
      ownerName: room.get('ownerName') as string,
      requireApproval: room.get('requireApproval') as boolean,
      expiresAt: iso(invite.get('expiresAt')),
      status: this.inviteStatus(invite.data()!),
      alreadyMember: member.exists,
    };
  }

  /**
   * Redeems an invitation inside a transaction so use limits cannot be
   * exceeded by concurrent requests. Returns whether the caller is now a
   * member or waiting for the owner's approval.
   */
  async acceptInvite(inviteId: string, user: AuthUser): Promise<{ roomId: string; status: 'member' | 'waiting' }> {
    const profile = await this.getProfile(user);
    return this.db.runTransaction(async (tx: Transaction) => {
      const inviteRef = this.invites().doc(inviteId);
      const invite = await tx.get(inviteRef);
      if (!invite.exists) throw new HttpError(404, 'invite_not_found', 'This invitation link is not valid');
      const roomId = invite.get('roomId') as string;
      const roomRef = this.room(roomId);
      const [room, member, blocked, waiting, members] = await Promise.all([
        tx.get(roomRef),
        tx.get(this.member(roomId, user.uid)),
        tx.get(roomRef.collection('blocked').doc(user.uid)),
        tx.get(roomRef.collection('waiting').doc(user.uid)),
        tx.get(roomRef.collection('members').count()),
      ]);
      if (!room.exists) throw new HttpError(404, 'invite_not_found', 'This invitation link is not valid');
      if (member.exists) return { roomId, status: 'member' as const };
      if (blocked.exists) throw new HttpError(403, 'blocked', 'The owner removed you from this room');
      if (waiting.exists) return { roomId, status: 'waiting' as const };

      const status = this.inviteStatus(invite.data()!);
      if (status === 'revoked') throw new HttpError(410, 'invite_revoked', 'This invitation was cancelled by the owner');
      if (status === 'expired') throw new HttpError(410, 'invite_expired', 'This invitation has expired');
      if (status === 'used_up') throw new HttpError(410, 'invite_used_up', 'This invitation has already been used');

      if (members.data().count >= LIMITS.membersPerRoom) throw new HttpError(409, 'member_limit', 'This room is full');

      const now = Timestamp.fromDate(this.now());
      tx.update(inviteRef, { uses: FieldValue.increment(1) });
      if (room.get('requireApproval')) {
        tx.set(roomRef.collection('waiting').doc(user.uid), {
          uid: user.uid,
          displayName: profile.displayName,
          requestedAt: now,
          inviteId,
        });
        return { roomId, status: 'waiting' as const };
      }
      this.addMemberInTx(tx, roomId, room.get('name'), user.uid, profile.displayName, now);
      return { roomId, status: 'member' as const };
    });
  }

  private addMemberInTx(tx: Transaction, roomId: string, roomName: string, uid: string, displayName: string, now: Timestamp) {
    tx.set(this.member(roomId, uid), { uid, displayName, role: 'member', joinedAt: now });
    tx.set(this.users().doc(uid).collection('memberships').doc(roomId), { roomName, role: 'member', joinedAt: now });
  }

  // ---------------------------------------------------------------- waiting room

  async listWaiting(roomId: string, uid: string) {
    await this.requireOwner(roomId, uid);
    const snap = await this.room(roomId).collection('waiting').orderBy('requestedAt').limit(LIMITS.waitingPerRoom).get();
    return snap.docs.map((d) => ({
      uid: d.id,
      displayName: d.get('displayName') as string,
      requestedAt: iso(d.get('requestedAt')),
    }));
  }

  async decideWaiting(roomId: string, ownerUid: string, targetUid: string, approve: boolean) {
    await this.requireOwner(roomId, ownerUid);
    await this.db.runTransaction(async (tx) => {
      const roomRef = this.room(roomId);
      const [room, waiting, members] = await Promise.all([
        tx.get(roomRef),
        tx.get(roomRef.collection('waiting').doc(targetUid)),
        approve ? tx.get(roomRef.collection('members').count()) : Promise.resolve(null),
      ]);
      if (!waiting.exists) throw new HttpError(404, 'request_not_found', 'No pending request from that person');
      tx.delete(waiting.ref);
      if (!approve) return;
      if ((members?.data().count ?? 0) >= LIMITS.membersPerRoom) {
        throw new HttpError(409, 'member_limit', 'This room is full');
      }
      this.addMemberInTx(tx, roomId, room.get('name'), targetUid, waiting.get('displayName'), Timestamp.fromDate(this.now()));
    });
  }
}
