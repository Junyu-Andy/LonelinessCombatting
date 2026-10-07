/**
 * T18 W2 DJG rules (decision 0027): the participant writes only raw
 * answers / status / times of their own W2 doc; scores, push times and
 * the missed mark are server-only; submitted and missed docs are frozen.
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
  doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp,
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

const me = () => testEnv.authenticatedContext('u1').firestore();
const other = () => testEnv.authenticatedContext('u2').firestore();
const w2 = (db, uid) => doc(db, 'users', uid || 'u1', 'djg_responses', 'W2');

const inProgress = (extra) => Object.assign({
  timepoint: 'W2',
  itemsVersion: 'djg6_pkg3_v1',
  answers: { q1: 'yes', q2: 'skipped' },
  status: 'in_progress',
  startedAt: serverTimestamp(),
  startedAtLocal: '2026-10-14T10:05:00.000',
  updatedAt: serverTimestamp(),
}, extra || {});

async function seed(data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(w2(ctx.firestore()), data);
  });
}

describe('T18 djg_responses rules', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  it('owner creates W2 in progress, reads it back', async () => {
    await assertSucceeds(setDoc(w2(me()), inProgress()));
    await assertSucceeds(getDoc(w2(me())));
  });

  it('another participant can neither read nor write it', async () => {
    await seed({ timepoint: 'W2', status: 'pending', answers: {} });
    await assertFails(getDoc(w2(other(), 'u1')));
    await assertFails(setDoc(w2(other(), 'u1'), inProgress()));
  });

  it('only doc id W2', async () => {
    await assertFails(setDoc(doc(me(), 'users', 'u1', 'djg_responses', 'W4'),
      inProgress()));
  });

  it('client cannot write scores or other server fields', async () => {
    for (const extra of [
      { scores: { emotional: 0, social: 0, total: 0 } },
      { outsideWindow: false },
      { pushSentAt: serverTimestamp() },
      { reminderSentAt: serverTimestamp() },
      { scoredAt: serverTimestamp() },
      { researchId: 'P0ZAHP5' },
    ]) {
      await assertFails(setDoc(w2(me()), inProgress(extra)));
    }
  });

  it('client cannot set status pending or missed', async () => {
    await assertFails(setDoc(w2(me()), inProgress({ status: 'missed' })));
    await assertFails(setDoc(w2(me()), inProgress({ status: 'pending' })));
  });

  it('answers: only q1–q6, only the four values', async () => {
    await assertFails(setDoc(w2(me()),
      inProgress({ answers: { q7: 'yes' } })));
    await assertFails(setDoc(w2(me()),
      inProgress({ answers: { q1: 1 } })));
    await assertFails(setDoc(w2(me()),
      inProgress({ answers: { q1: '係' } })));
    await assertSucceeds(setDoc(w2(me()), inProgress({ answers: {
      q1: 'yes', q2: 'mostly', q3: 'no', q4: 'skipped', q5: 'no', q6: 'yes',
    } })));
  });

  it('submit needs the server time; in progress may not carry it',
    async () => {
      await assertFails(setDoc(w2(me()), inProgress({
        status: 'submitted',
        submittedAt: Timestamp.fromDate(new Date('2026-10-14T02:00:00Z')),
      })));
      await assertFails(setDoc(w2(me()),
        inProgress({ submittedAt: serverTimestamp() })));
      await assertSucceeds(setDoc(w2(me()), inProgress({
        status: 'submitted', submittedAt: serverTimestamp(),
      })));
    });

  it('server-created pending doc: owner may answer, server fields stay',
    async () => {
      await seed({ timepoint: 'W2', status: 'pending',
        pushSentAt: Timestamp.now(), windowEndDate: '2026-10-20' });
      await assertSucceeds(setDoc(w2(me()), inProgress(), { merge: true }));
      await assertFails(updateDoc(w2(me()), { pushSentAt: null }));
      await assertSucceeds(updateDoc(w2(me()), {
        answers: { q1: 'yes', q2: 'no' }, status: 'submitted',
        submittedAt: serverTimestamp(),
      }));
    });

  it('submitted and missed docs are frozen for the client', async () => {
    await seed({ timepoint: 'W2', status: 'submitted', answers: {} });
    await assertFails(updateDoc(w2(me()),
      { answers: { q1: 'no' }, status: 'in_progress' }));
    await seed({ timepoint: 'W2', status: 'missed', answers: {} });
    await assertFails(setDoc(w2(me()), inProgress({ status: 'submitted',
      submittedAt: serverTimestamp() }), { merge: true }));
  });

  it('no client delete', async () => {
    await seed({ timepoint: 'W2', status: 'in_progress', answers: {} });
    await assertFails(deleteDoc(w2(me())));
  });

  it('other subcollections keep the owner catch-all', async () => {
    await assertSucceeds(setDoc(doc(me(), 'users', 'u1', 'djg_es', 'x'),
      { timepoint: 'week2', score: 3 }));
  });
});
