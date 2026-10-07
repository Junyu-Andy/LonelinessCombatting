/**
 * T19 allocation rules (decision 0029): the sequences, the pointer, the
 * enrolment records, the allocation log, the LLM-refusal log, the switch
 * and the retired counter are server-only.  No client — participant,
 * blinded (PI), unblinded researcher or anonymous — reads or writes them.
 * The W0 date and the other new assignment fields on users/{uid} are
 * server-only like the arm.
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
  doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, collection, addDoc,
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

const participant = () => testEnv.authenticatedContext('u1').firestore();
const blinded = () => testEnv.authenticatedContext('pi1',
  { role: 'blinded' }).firestore();
const unblinded = () => testEnv.authenticatedContext('k1',
  { role: 'unblinded' }).firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();
const everyone = () => [participant(), blinded(), unblinded(), anon()];

const SERVER_DOCS = [
  ['randomization_sequences', 'low'],
  ['randomization_sequences', 'high'],
  ['randomization_state', 'low'],
  ['enrollments', 'u1'],
  ['arm_assignment_log', 'log1'],
  ['llm_denied_log', 'd1'],
  ['meta', 'randomization_config'],
  ['meta', 'arm_counter'],
];

describe('T19 allocation rules', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'randomization_sequences', 'low'),
        { arms: ['A', 'B'], blocks: [2], length: 2 });
      await setDoc(doc(db, 'randomization_sequences', 'high'),
        { arms: ['B', 'A'], blocks: [2], length: 2 });
      await setDoc(doc(db, 'randomization_state', 'low'), { next: 1 });
      await setDoc(doc(db, 'enrollments', 'u1'),
        { uid: 'u1', arm: 'A', researchId: 'B001' });
      await setDoc(doc(db, 'arm_assignment_log', 'log1'),
        { uid: 'u1', arm: 'A' });
      await setDoc(doc(db, 'llm_denied_log', 'd1'), { uid: 'u2' });
      await setDoc(doc(db, 'meta', 'randomization_config'),
        { enabled: true });
      await setDoc(doc(db, 'meta', 'arm_counter'),
        { cell_0: { aCount: 1, bCount: 0 } });
      await setDoc(doc(db, 'users', 'u1'), {
        displayName: 'x', arm: 'A', strataCell: 0,
        armAssignmentMode: 'randomise', w0Date: '2026-10-07',
      });
      await setDoc(doc(db, 'users', 'u2'), { displayName: 'y' });
    });
  });

  it('no client reads any allocation doc or collection', async () => {
    for (const db of everyone()) {
      for (const [c, id] of SERVER_DOCS) {
        await assertFails(getDoc(doc(db, c, id)));
      }
      for (const c of ['randomization_sequences', 'randomization_state',
        'enrollments', 'arm_assignment_log', 'llm_denied_log']) {
        await assertFails(getDocs(collection(db, c)));
      }
    }
  });

  it('no client writes, updates or deletes them', async () => {
    for (const db of everyone()) {
      for (const [c, id] of SERVER_DOCS) {
        await assertFails(setDoc(doc(db, c, id), { arms: ['A'] }));
        await assertFails(updateDoc(doc(db, c, id), { next: 0 }));
        await assertFails(deleteDoc(doc(db, c, id)));
      }
      await assertFails(addDoc(collection(db, 'arm_assignment_log'),
        { uid: 'u1', arm: 'B' }));
      // The old counter's legitimate-looking increment is refused now.
      await assertFails(setDoc(doc(db, 'meta', 'arm_counter'),
        { cell_0: { aCount: 1, bCount: 1 } }));
    }
  });

  it('the participant cannot set or change the W0 date or method',
    async () => {
      const db = participant();
      await assertFails(updateDoc(doc(db, 'users', 'u1'),
        { w0Date: '2026-09-01' }));
      await assertFails(updateDoc(doc(db, 'users', 'u1'),
        { armAssignmentMethod: 'x' }));
      await assertFails(updateDoc(doc(db, 'users', 'u1'), { arm: 'B' }));
      const db2 = testEnv.authenticatedContext('u2').firestore();
      await assertFails(updateDoc(doc(db2, 'users', 'u2'),
        { w0Date: '2026-10-01' }));
      // Ordinary profile writes still pass.
      await assertSucceeds(updateDoc(doc(db, 'users', 'u1'),
        { displayName: 'z', w0Date: '2026-10-07' }));
    });

  it('a new account cannot be created with a W0 date', async () => {
    const db = testEnv.authenticatedContext('u3').firestore();
    await assertFails(setDoc(doc(db, 'users', 'u3'),
      { displayName: 'n', w0Date: '2026-10-01' }));
    await assertSucceeds(setDoc(doc(db, 'users', 'u3'),
      { displayName: 'n' }));
  });

  it('blinded and unblinded staff cannot read a participant profile',
    async () => {
      await assertFails(getDoc(doc(blinded(), 'users', 'u1')));
      await assertFails(getDoc(doc(unblinded(), 'users', 'u1')));
    });
});
