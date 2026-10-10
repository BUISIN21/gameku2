import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, setDoc, updateDoc } from 'firebase/firestore';

// Exercises firebase/firestore.rules in the Firestore emulator with
// simulated signed-in users. A separate project id keeps this data apart.
const PROJECT = 'demo-connectcall-rules';
let env: RulesTestEnvironment;

before(async () => {
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST!.split(':');
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync(new URL('../../firebase/firestore.rules', import.meta.url), 'utf8'), host, port: Number(port) },
  });
  await env.clearFirestore();
  // Seed data as the backend (Admin SDK) would write it.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/owner'), { displayName: 'Owner' });
    await setDoc(doc(db, 'users/owner/memberships/room1'), { roomName: 'R', role: 'owner' });
    await setDoc(doc(db, 'rooms/room1'), { name: 'R', ownerUid: 'owner', requireApproval: true });
    await setDoc(doc(db, 'rooms/room1/members/owner'), { role: 'owner', displayName: 'Owner' });
    await setDoc(doc(db, 'rooms/room1/members/member'), { role: 'member', displayName: 'Member' });
    await setDoc(doc(db, 'rooms/room1/waiting/waiter'), { displayName: 'Waiter' });
    await setDoc(doc(db, 'rooms/room1/blocked/banned'), { by: 'owner' });
    await setDoc(doc(db, 'invites/secretinvite'), { roomId: 'room1', revoked: false });
  });
});

after(async () => {
  await env?.cleanup();
});

const as = (uid: string | null) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

describe('firestore.rules', () => {
  it('signed-out users can read nothing', async () => {
    const db = as(null);
    await assertFails(getDoc(doc(db, 'users/owner')));
    await assertFails(getDoc(doc(db, 'rooms/room1')));
    await assertFails(getDoc(doc(db, 'rooms/room1/members/owner')));
  });

  it('profiles are readable by signed-in users but not writable or listable', async () => {
    const db = as('stranger');
    await assertSucceeds(getDoc(doc(db, 'users/owner')));
    await assertFails(getDocs(collection(db, 'users')));
    await assertFails(setDoc(doc(db, 'users/stranger'), { displayName: 'Me' }));
    await assertFails(updateDoc(doc(as('owner'), 'users/owner'), { displayName: 'Hacked' }));
  });

  it('memberships mirror is private to its user', async () => {
    await assertSucceeds(getDocs(collection(as('owner'), 'users/owner/memberships')));
    await assertFails(getDocs(collection(as('stranger'), 'users/owner/memberships')));
  });

  it('rooms and member lists are visible to members only', async () => {
    await assertSucceeds(getDoc(doc(as('member'), 'rooms/room1')));
    await assertSucceeds(getDocs(collection(as('member'), 'rooms/room1/members')));
    await assertFails(getDoc(doc(as('stranger'), 'rooms/room1')));
    await assertFails(getDocs(collection(as('stranger'), 'rooms/room1/members')));
    await assertFails(getDocs(collection(as('stranger'), 'rooms')));
  });

  it('a user can watch their own membership doc even before joining (approval)', async () => {
    await assertSucceeds(getDoc(doc(as('waiter'), 'rooms/room1/members/waiter')));
    await assertFails(getDoc(doc(as('waiter'), 'rooms/room1/members/owner')));
  });

  it('nobody can grant themselves membership or ownership from the client', async () => {
    await assertFails(setDoc(doc(as('stranger'), 'rooms/room1/members/stranger'), { role: 'member' }));
    await assertFails(setDoc(doc(as('member'), 'rooms/room1/members/member'), { role: 'owner' }));
    await assertFails(updateDoc(doc(as('member'), 'rooms/room1'), { ownerUid: 'member' }));
    await assertFails(setDoc(doc(as('stranger'), 'rooms/newroom'), { ownerUid: 'stranger' }));
    await assertFails(setDoc(doc(as('owner'), 'rooms/room1/members/x'), { role: 'member' }));
  });

  it('waiting room: requester sees own request, owner sees all, members see none', async () => {
    await assertSucceeds(getDoc(doc(as('waiter'), 'rooms/room1/waiting/waiter')));
    await assertSucceeds(getDocs(collection(as('owner'), 'rooms/room1/waiting')));
    await assertFails(getDocs(collection(as('member'), 'rooms/room1/waiting')));
    await assertFails(setDoc(doc(as('stranger'), 'rooms/room1/waiting/stranger'), { displayName: 'S' }));
  });

  it('invitations and block list are never readable by clients', async () => {
    await assertFails(getDoc(doc(as('owner'), 'invites/secretinvite')));
    await assertFails(getDocs(collection(as('owner'), 'invites')));
    await assertFails(getDoc(doc(as('owner'), 'rooms/room1/blocked/banned')));
    await assertFails(setDoc(doc(as('banned'), 'rooms/room1/blocked/banned'), {}));
  });
});
