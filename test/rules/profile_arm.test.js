/**
 * Firestore security-rules tests for the RCT assignment fields on
 * `users/{uid}` (decision 0003 / 0022, SPEC:C01). Only the assignArm
 * Cloud Function (admin SDK) writes `arm`, `strataCell` and the
 * armAssigned* fields; no client may set, change or erase them, nor
 * delete the profile to be re-randomised. Ordinary profile merge-writes
 * — including the app's signup and backfill writes, which repeat or omit
 * the stored arm — must still pass, and subcollections keep plain
 * owner-only access.
 *
 * Run inside the emulator (see README.md).
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, getDoc, deleteDoc, deleteField } =
  require('firebase/firestore');

const PROJECT_ID = 'loneliness-pilot-dev';
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, '../../firestore.rules'),
        'utf8',
      ),
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

const owner = () => testEnv.authenticatedContext('u1').firestore();
const other = () => testEnv.authenticatedContext('u2').firestore();
const profile = (db) => doc(db, 'users', 'u1');

async function seed(data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(profile(ctx.firestore()), data);
  });
}

describe('users/{uid} server-only arm', () => {
  it('DENIES signup create with an arm', async () => {
    await assertFails(setDoc(profile(owner()), { uid: 'u1', arm: 'B' }));
    await assertFails(setDoc(profile(owner()), { uid: 'u1', arm: 'A' }));
  });

  it('DENIES signup create with a strataCell', async () => {
    await assertFails(setDoc(profile(owner()), { uid: 'u1', strataCell: 2 }));
  });

  it('ALLOWS the app signup create (no assignment fields)', async () => {
    // Mirrors AuthService.signUp: profile.toMap() omits null arm/strataCell.
    await assertSucceeds(setDoc(profile(owner()), {
      uid: 'u1', displayName: 'x', ageGroup: '70-74',
      baselineUclaScore: 50, consent: {}, memory_enabled: false,
    }, { merge: true }));
  });

  it('ALLOWS create without an arm (assignment failed at signup)', async () => {
    await assertSucceeds(setDoc(profile(owner()), { uid: 'u1' }));
  });

  it('DENIES create with an invalid arm value', async () => {
    await assertFails(setDoc(profile(owner()), { uid: 'u1', arm: 'C' }));
  });

  it('DENIES a client-side arm==null backfill (server only now)', async () => {
    await seed({ uid: 'u1', arm: null });
    await assertFails(
      setDoc(profile(owner()), { arm: 'A', strataCell: 0 }, { merge: true }),
    );
    await seed({ uid: 'u1' });
    await assertFails(setDoc(profile(owner()), { arm: 'B' }, { merge: true }));
  });

  it('DENIES changing or erasing strataCell', async () => {
    await seed({ uid: 'u1', arm: 'A', strataCell: 1 });
    await assertFails(
      setDoc(profile(owner()), { strataCell: 3 }, { merge: true }));
    await assertFails(updateDoc(profile(owner()), { strataCell: deleteField() }));
    await seed({ uid: 'u1' });
    await assertFails(
      setDoc(profile(owner()), { strataCell: 0 }, { merge: true }));
  });

  it('ALLOWS rewriting the same strataCell', async () => {
    await seed({ uid: 'u1', arm: 'A', strataCell: 1 });
    await assertSucceeds(setDoc(profile(owner()),
      { arm: 'A', strataCell: 1, displayName: 'y' }, { merge: true }));
  });

  it('DENIES deleting the profile (delete + re-create would re-randomise)',
    async () => {
      await seed({ uid: 'u1', arm: 'B', strataCell: 0 });
      await assertFails(deleteDoc(profile(owner())));
      await seed({ uid: 'u1' });
      await assertFails(deleteDoc(profile(owner())));
    });

  it('ALLOWS a profile merge-write that omits arm', async () => {
    await seed({ uid: 'u1', arm: 'B', displayName: 'x' });
    await assertSucceeds(
      setDoc(profile(owner()), { displayName: 'y' }, { merge: true }),
    );
  });

  it('ALLOWS rewriting the same arm', async () => {
    await seed({ uid: 'u1', arm: 'B' });
    await assertSucceeds(
      setDoc(profile(owner()), { arm: 'B' }, { merge: true }),
    );
  });

  it('DENIES switching arm B → A', async () => {
    await seed({ uid: 'u1', arm: 'B' });
    await assertFails(setDoc(profile(owner()), { arm: 'A' }, { merge: true }));
  });

  it('DENIES erasing the arm with null', async () => {
    await seed({ uid: 'u1', arm: 'A' });
    await assertFails(setDoc(profile(owner()), { arm: null }, { merge: true }));
  });

  it('DENIES deleting the arm field', async () => {
    await seed({ uid: 'u1', arm: 'A' });
    await assertFails(updateDoc(profile(owner()), { arm: deleteField() }));
  });

  it('DENIES a full overwrite that drops the arm', async () => {
    await seed({ uid: 'u1', arm: 'A' });
    await assertFails(setDoc(profile(owner()), { uid: 'u1' }));
  });

  it('DENIES another user reading or writing the profile', async () => {
    await seed({ uid: 'u1', arm: 'A' });
    await assertFails(getDoc(profile(other())));
    await assertFails(
      setDoc(profile(other()), { displayName: 'z' }, { merge: true }),
    );
  });

  it('keeps owner-only access to subcollections', async () => {
    const own = doc(owner(), 'users', 'u1', 'agent_contexts', 'siu_yan');
    const theirs = doc(other(), 'users', 'u1', 'agent_contexts', 'siu_yan');
    await assertSucceeds(setDoc(own, { rollingSummary: 's' }));
    await assertSucceeds(getDoc(own));
    await assertFails(getDoc(theirs));
    await assertFails(setDoc(theirs, { rollingSummary: 'x' }));
    const deep = doc(owner(), 'users', 'u1', 'memory', 'm2_check_in',
        'entries', 'e1');
    await assertSucceeds(setDoc(deep, { summary: 's' }));
  });
  it('DENIES a client setting the server assignment fields', async () => {
    await assertFails(setDoc(profile(owner()),
      { uid: 'u1', armAssignmentMode: 'randomise' }));
    await seed({ uid: 'u1', arm: 'A', armAssignmentMode: 'force_a' });
    await assertFails(setDoc(profile(owner()),
      { armAssignmentMode: 'randomise' }, { merge: true }));
    await assertFails(updateDoc(profile(owner()),
      { armAssignedBy: 'client' }));
  });

  it('DENIES a client setting or clearing memoryWithdrawnAt (T10)',
      async () => {
    await assertFails(setDoc(profile(owner()),
      { uid: 'u1', memoryWithdrawnAt: new Date() }));
    await seed({ uid: 'u1', arm: 'A', armAssignmentMode: 'randomise',
      memoryWithdrawnAt: new Date() });
    await assertFails(setDoc(profile(owner()),
      { memoryWithdrawnAt: null }, { merge: true }));
    await assertSucceeds(setDoc(profile(owner()),
      { displayName: 'y', memory_enabled: false }, { merge: true }));
  });

  it('ALLOWS ordinary writes to a server-assigned profile', async () => {
    await seed({ uid: 'u1', arm: 'A', armAssignmentMode: 'randomise',
      armAssignedBy: 'server' });
    await assertSucceeds(setDoc(profile(owner()),
      { displayName: 'y', memory_enabled: true }, { merge: true }));
  });
});
