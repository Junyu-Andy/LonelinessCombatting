/**
 * Firestore security-rules tests for the write-once RCT arm on
 * `users/{uid}`. Once a participant has an arm ('A' | 'B') no client write
 * may change or erase it; ordinary profile merge-writes must still pass,
 * and subcollections keep plain owner-only access.
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
const { doc, setDoc, updateDoc, getDoc, deleteField } =
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

describe('users/{uid} write-once arm', () => {
  it('ALLOWS signup create with an arm', async () => {
    await assertSucceeds(
      setDoc(profile(owner()), { uid: 'u1', arm: 'B' }),
    );
  });

  it('ALLOWS create without an arm (assignment failed at signup)', async () => {
    await assertSucceeds(setDoc(profile(owner()), { uid: 'u1' }));
  });

  it('DENIES create with an invalid arm value', async () => {
    await assertFails(setDoc(profile(owner()), { uid: 'u1', arm: 'C' }));
  });

  it('ALLOWS the arm==null backfill', async () => {
    await seed({ uid: 'u1', arm: null });
    await assertSucceeds(
      setDoc(profile(owner()), { arm: 'A', strataCell: 0 }, { merge: true }),
    );
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
});
