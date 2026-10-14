/**
 * T21 (registry v8 C01, dev-tasks-1010 §3 T21 item 2) — Firestore rules
 * for the study period and the enrolment gate.
 *
 *   - `cohort` (phase_b / pilot, from the research-ID prefix) is written
 *     by enrollParticipant only: no client sets, changes or erases it.
 *   - pilot_assignment_log is server-only.
 *   - With app_config/feature_flags.enrollmentGateEnabled on, an account
 *     that is neither enrolled nor a tester cannot write research data
 *     under users/{uid}/ (fcm_tokens excepted); its profile doc stays
 *     writable.  Off — the default — nothing changes.
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
const { doc, setDoc, getDoc, updateDoc, deleteField, addDoc, collection } =
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

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

async function gate(on) {
  await seed('app_config/feature_flags', { enrollmentGateEnabled: on });
}

const event = (db) => addDoc(collection(db, 'users', 'u1', 'events'),
  { name: 'app_open' });
const turn = (db) => setDoc(doc(db, 'users', 'u1', 'turns', 't1'),
  { text: 'x' });
const djg = (db) => setDoc(doc(db, 'users', 'u1', 'djg_responses', 'W2'), {
  timepoint: 'W2', itemsVersion: 'v', answers: { q1: 'yes' },
  status: 'in_progress',
});
const token = (db) => setDoc(doc(db, 'users', 'u1', 'fcm_tokens', 'd1'),
  { token: 'x' });

describe('users/{uid}.cohort is server-only (T21)', () => {
  it('DENIES signup create with a cohort', async () => {
    await assertFails(setDoc(doc(owner(), 'users', 'u1'),
      { uid: 'u1', cohort: 'phase_b' }));
    await assertFails(setDoc(doc(owner(), 'users', 'u1'),
      { uid: 'u1', cohort: 'pilot' }));
  });

  it('DENIES setting, changing or erasing a cohort', async () => {
    await seed('users/u1', { uid: 'u1' });
    await assertFails(setDoc(doc(owner(), 'users', 'u1'),
      { cohort: 'phase_b' }, { merge: true }));
    await seed('users/u1', { uid: 'u1', cohort: 'pilot', arm: 'A' });
    await assertFails(setDoc(doc(owner(), 'users', 'u1'),
      { cohort: 'phase_b' }, { merge: true }));
    await assertFails(updateDoc(doc(owner(), 'users', 'u1'),
      { cohort: deleteField() }));
  });

  it('ALLOWS a profile merge-write that repeats or omits the cohort',
    async () => {
      await seed('users/u1', { uid: 'u1', cohort: 'pilot', arm: 'A' });
      await assertSucceeds(setDoc(doc(owner(), 'users', 'u1'),
        { displayName: 'y' }, { merge: true }));
      await assertSucceeds(setDoc(doc(owner(), 'users', 'u1'),
        { cohort: 'pilot', displayName: 'z' }, { merge: true }));
    });

  it('DENIES any client access to pilot_assignment_log', async () => {
    await seed('pilot_assignment_log/l1', { researchId: 'PILOT-01' });
    const unblinded = testEnv.authenticatedContext('k',
      { role: 'unblinded' }).firestore();
    for (const db of [owner(), unblinded]) {
      await assertFails(getDoc(doc(db, 'pilot_assignment_log', 'l1')));
      await assertFails(setDoc(doc(db, 'pilot_assignment_log', 'l2'),
        { researchId: 'PILOT-02' }));
    }
  });
});

describe('enrolment gate on research data (T21)', () => {
  it('gate absent or off: an unregistered account writes as before',
    async () => {
      await seed('users/u1', { uid: 'u1', arm: 'A' });
      await assertSucceeds(event(owner()));
      await assertSucceeds(turn(owner()));
      await assertSucceeds(djg(owner()));
      await gate(false);
      await assertSucceeds(event(owner()));
      await gate('true'); // only a literal true turns it on
      await assertSucceeds(event(owner()));
    });

  it('gate on: an unregistered account cannot write research data',
    async () => {
      await gate(true);
      await seed('users/u1', { uid: 'u1', arm: 'A',
        armAssignmentMode: 'force_a' });
      await assertFails(event(owner()));
      await assertFails(turn(owner()));
      await assertFails(djg(owner()));
    });

  it('gate on: the device token and the profile doc stay writable',
    async () => {
      await gate(true);
      await seed('users/u1', { uid: 'u1' });
      await assertSucceeds(token(owner()));
      await assertSucceeds(setDoc(doc(owner(), 'users', 'u1'),
        { consent: { sharedContextUse: true } }, { merge: true }));
      await assertSucceeds(getDoc(doc(owner(), 'users', 'u1')));
    });

  it('gate on: Phase B, pilot and tester accounts write as before',
    async () => {
      await gate(true);
      for (const profile of [
        { uid: 'u1', arm: 'A', cohort: 'phase_b' },
        { uid: 'u1', arm: 'B', cohort: 'pilot' },
        { uid: 'u1', isTester: true },
      ]) {
        await seed('users/u1', profile);
        await assertSucceeds(event(owner()));
        await assertSucceeds(turn(owner()));
        await assertSucceeds(djg(owner()));
      }
    });

  it('gate on: a cohort outside phase_b / pilot does not count', async () => {
    await gate(true);
    await seed('users/u1', { uid: 'u1', cohort: 'phase_a' });
    await assertFails(event(owner()));
  });

  it('gate on: reading your own data is unaffected', async () => {
    await seed('users/u1/events/e1', { name: 'x' });
    await gate(true);
    await seed('users/u1', { uid: 'u1' });
    await assertSucceeds(getDoc(doc(owner(), 'users', 'u1', 'events', 'e1')));
  });
});
