/**
 * 1020e §2.14 — Firestore rules for `users/{uid}.intakeGateUnlockedAt`,
 * the time the researcher unlocked the explanation gate in front of the
 * intake (switch app_config/feature_flags.researcherIntakeGateEnabled).
 *
 *   - The owner may write it once, as the server time only (the App sends
 *     serverTimestamp() with a merge write).
 *   - A phone time, null, a second write, a change or a removal are
 *     refused, so "unlocked" cannot be undone or back-dated from a client.
 *   - Ordinary profile saves (which leave the field out) still pass on a
 *     profile that holds it; both arms, registered or not, enrolment gate
 *     on or off.
 *   - It opens no door to the server-only assignment fields.
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
const {
  doc, setDoc, updateDoc, getDoc, deleteField, serverTimestamp, Timestamp,
} = require('firebase/firestore');

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
const FIELD = 'intakeGateUnlockedAt';

async function seed(p, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), p), data);
  });
}

describe('1020e §2.14: users/{uid}.intakeGateUnlockedAt', () => {
  for (const arm of ['A', 'B', null]) {
    it(`ALLOWS the owner to set it once to the server time (arm ${arm})`,
      async () => {
        await seed('users/u1', {
          uid: 'u1', displayName: 'x',
          consent: { functionalData: true },
          ...(arm ? { arm, cohort: 'phase_b', armAssignmentMode: 'randomise' }
            : {}),
        });
        await assertSucceeds(setDoc(profile(owner()),
          { [FIELD]: serverTimestamp() }, { merge: true }));
        const snap = await getDoc(profile(owner()));
        if (!(snap.get(FIELD) instanceof Timestamp)) {
          throw new Error('not stored as a timestamp');
        }
      });
  }

  it('ALLOWS it while the enrolment gate is on (the profile doc is not ' +
    'research data)', async () => {
    await seed('app_config/feature_flags',
      { enrollmentGateEnabled: true, researcherIntakeGateEnabled: true });
    await seed('users/u1', { uid: 'u1' });
    await assertSucceeds(updateDoc(profile(owner()),
      { [FIELD]: serverTimestamp() }));
  });

  it('DENIES a phone time, a string or null', async () => {
    await seed('users/u1', { uid: 'u1' });
    await assertFails(updateDoc(profile(owner()),
      { [FIELD]: Timestamp.fromDate(new Date('2026-10-20T02:00:00Z')) }));
    await assertFails(updateDoc(profile(owner()),
      { [FIELD]: '2026-10-20T02:00:00.000Z' }));
    await assertFails(updateDoc(profile(owner()), { [FIELD]: null }));
    await assertFails(setDoc(profile(owner()),
      { [FIELD]: new Date() }, { merge: true }));
  });

  it('DENIES a second write, a change or a removal once set', async () => {
    await seed('users/u1', {
      uid: 'u1', [FIELD]: Timestamp.fromDate(new Date('2026-10-20T02:00:00Z')),
    });
    await assertFails(updateDoc(profile(owner()),
      { [FIELD]: serverTimestamp() }));
    await assertFails(updateDoc(profile(owner()),
      { [FIELD]: Timestamp.fromDate(new Date('2026-10-21T02:00:00Z')) }));
    await assertFails(updateDoc(profile(owner()), { [FIELD]: deleteField() }));
    await assertFails(updateDoc(profile(owner()), { [FIELD]: null }));
  });

  it('ALLOWS ordinary profile saves on a profile that holds it ' +
    '(the App leaves the field out)', async () => {
    await seed('users/u1', {
      uid: 'u1', displayName: 'x', arm: 'B', cohort: 'phase_b',
      [FIELD]: Timestamp.fromDate(new Date('2026-10-20T02:00:00Z')),
    });
    await assertSucceeds(setDoc(profile(owner()), {
      displayName: 'y', hasCompletedIntake: true, intakePeopleDone: true,
      interests: ['yum_cha'], arm: 'B',
    }, { merge: true }));
    await assertSucceeds(updateDoc(profile(owner()),
      { onboardingCompletedAt: '2026-10-20T03:00:00.000Z' }));
  });

  it('create: ALLOWS the server time, DENIES a phone time', async () => {
    await assertSucceeds(setDoc(profile(owner()),
      { uid: 'u1', [FIELD]: serverTimestamp() }));
    await testEnv.clearFirestore();
    await assertFails(setDoc(profile(owner()),
      { uid: 'u1', [FIELD]: Timestamp.fromDate(new Date()) }));
  });

  it('DENIES smuggling an assignment field or isTester in with it',
    async () => {
      await seed('users/u1', { uid: 'u1' });
      await assertFails(updateDoc(profile(owner()),
        { [FIELD]: serverTimestamp(), cohort: 'phase_b' }));
      await assertFails(updateDoc(profile(owner()),
        { [FIELD]: serverTimestamp(), arm: 'A' }));
      await assertFails(updateDoc(profile(owner()),
        { [FIELD]: serverTimestamp(), isTester: true }));
    });

  it('DENIES another account writing it', async () => {
    await seed('users/u1', { uid: 'u1' });
    await assertFails(setDoc(doc(other(), 'users', 'u1'),
      { [FIELD]: serverTimestamp() }, { merge: true }));
  });
});
