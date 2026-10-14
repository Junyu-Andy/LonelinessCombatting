/**
 * T24 weekly bundle rules: the study-week fields (studyWeek, studyDay,
 * window, missed, scheduleMode) on weekly_pr / pgic / brief_pr /
 * social_contact_probes are server-only; the probe record is validated
 * like the DJG one; the DJG collection accepts W1–W3; weekly_status is
 * server-only.
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
  doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp,
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
const at = (db, col, id, uid) => doc(db, 'users', uid || 'u1', col, id);

async function seed(col, id, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(at(ctx.firestore(), col, id), data);
  });
}

const SERVER_ONLY = ['studyWeek', 'studyDay', 'submittedStudyDay', 'pushedAt',
  'windowStart', 'windowEnd', 'missed', 'missedAt', 'scheduleMode',
  'stampedAt', 'studyWeekBasis'];

describe('T24 study-week fields are server-only', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  for (const col of ['weekly_pr', 'pgic', 'brief_pr']) {
    it(`${col}: a plain record still writes, with bundle too`, async () => {
      await assertSucceeds(setDoc(at(me(), col, 'W1'),
          {bundle: 'W1', status: 'completed', value: 3}));
      await assertSucceeds(setDoc(at(me(), col, 'free'),
          {weekIso: '2026-W44', status: 'completed'}));
    });

    for (const f of SERVER_ONLY) {
      it(`${col}: create carrying ${f} is refused`, async () => {
        const data = {bundle: 'W1', status: 'completed'};
        data[f] = 1;
        await assertFails(setDoc(at(me(), col, 'W1'), data));
      });
    }

    it(`${col}: update touching studyWeek / missed is refused; other ` +
       'fields pass; server stamps already present do not block', async () => {
      await seed(col, 'W1', {bundle: 'W1', status: 'in_progress',
        studyWeek: 1, studyDay: 7, scheduleMode: 'standard'});
      await assertFails(updateDoc(at(me(), col, 'W1'), {studyWeek: 2}));
      await assertFails(updateDoc(at(me(), col, 'W1'), {missed: false}));
      await assertFails(setDoc(at(me(), col, 'W1'), {studyDay: 9},
          {merge: true}));
      await assertSucceeds(updateDoc(at(me(), col, 'W1'),
          {status: 'completed'}));
      // A merge that repeats the stored stamps changes nothing → allowed.
      await assertSucceeds(setDoc(at(me(), col, 'W1'),
          {status: 'completed', studyWeek: 1}, {merge: true}));
    });

    it(`${col}: another user cannot write it`, async () => {
      await assertFails(setDoc(at(other(), col, 'W1'),
          {bundle: 'W1', status: 'completed'}));
    });
  }
});

describe('T24 social_contact_probes rules', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  const inProgress = (extra) => Object.assign({
    bundle: 'W1',
    itemsVersion: 's12_v1',
    answers: {q1: 2},
    status: 'in_progress',
    startedAt: serverTimestamp(),
    startedAtLocal: '2026-10-26T20:05:00.000',
    updatedAt: serverTimestamp(),
  }, extra || {});

  it('owner creates an in-progress record with values 0–3', async () => {
    await assertSucceeds(setDoc(at(me(), 'social_contact_probes', 'W1'),
        inProgress()));
  });

  it('values outside 0–3, extra items, wrong bundle, unknown keys fail',
      async () => {
        await assertFails(setDoc(at(me(), 'social_contact_probes', 'W1'),
            inProgress({answers: {q1: 4}})));
        await assertFails(setDoc(at(me(), 'social_contact_probes', 'W1'),
            inProgress({answers: {q1: -1}})));
        await assertFails(setDoc(at(me(), 'social_contact_probes', 'W1'),
            inProgress({answers: {q1: 'none'}})));
        await assertFails(setDoc(at(me(), 'social_contact_probes', 'W1'),
            inProgress({answers: {q3: 1}})));
        await assertFails(setDoc(at(me(), 'social_contact_probes', 'W1'),
            inProgress({bundle: 'W2'})));
        await assertFails(setDoc(at(me(), 'social_contact_probes', 'W1'),
            inProgress({studyWeek: 1})));
        await assertFails(setDoc(at(me(), 'social_contact_probes', 'W1'),
            inProgress({missed: false})));
        await assertFails(setDoc(at(me(), 'social_contact_probes', 'x'),
            inProgress({bundle: 'x'})));
      });

  it('submit needs submittedAt = server time; then frozen; never deleted',
      async () => {
        await seed('social_contact_probes', 'W1', inProgress());
        await assertFails(updateDoc(at(me(), 'social_contact_probes', 'W1'),
            {status: 'submitted', answers: {q1: 2, q2: 0}}));
        await assertSucceeds(updateDoc(at(me(), 'social_contact_probes', 'W1'),
            {status: 'submitted', answers: {q1: 2, q2: 0},
              submittedAt: serverTimestamp(), submittedAtLocal: 'x',
              updatedAt: serverTimestamp()}));
        await assertFails(updateDoc(at(me(), 'social_contact_probes', 'W1'),
            {answers: {q1: 0, q2: 0}}));
        await assertFails(deleteDoc(at(me(), 'social_contact_probes', 'W1')));
      });

  it('a missed record is frozen; another user reads nothing', async () => {
    await seed('social_contact_probes', 'W1', {bundle: 'W1',
      status: 'missed', missed: true});
    await assertFails(updateDoc(at(me(), 'social_contact_probes', 'W1'),
        {status: 'in_progress', answers: {}}));
    await assertSucceeds(getDoc(at(me(), 'social_contact_probes', 'W1')));
    await assertFails(getDoc(at(other(), 'social_contact_probes', 'W1')));
  });
});

describe('T24 djg_responses accepts W1–W3; weekly_status is server-only',
    () => {
      beforeEach(async () => {
        await testEnv.clearFirestore();
      });

      const djg = (tp, extra) => Object.assign({
        timepoint: tp,
        bundle: tp,
        itemsVersion: 'djg6_pkg3_v1',
        answers: {q1: 'yes'},
        status: 'in_progress',
        startedAt: serverTimestamp(),
        startedAtLocal: 'x',
        updatedAt: serverTimestamp(),
      }, extra || {});

      it('W1 and W3 create; W4 refused; bundle must match the id', async () => {
        await assertSucceeds(setDoc(at(me(), 'djg_responses', 'W1'), djg('W1')));
        await assertSucceeds(setDoc(at(me(), 'djg_responses', 'W3'), djg('W3')));
        await assertFails(setDoc(at(me(), 'djg_responses', 'W4'), djg('W4')));
        await assertFails(setDoc(at(me(), 'djg_responses', 'W1'),
            djg('W1', {bundle: 'W2'})));
        await assertFails(setDoc(at(me(), 'djg_responses', 'W1'),
            djg('W1', {studyWeek: 1})));
      });

      it('T18 W2 without bundle still works', async () => {
        const d = djg('W2');
        delete d.bundle;
        await assertSucceeds(setDoc(at(me(), 'djg_responses', 'W2'), d));
      });

      it('weekly_status: no client reads or writes', async () => {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          await setDoc(doc(ctx.firestore(), 'weekly_status', 'u1'),
              {uid: 'u1', researchId: 'PB-A01'});
        });
        await assertFails(getDoc(doc(me(), 'weekly_status', 'u1')));
        await assertFails(setDoc(doc(me(), 'weekly_status', 'u1'), {x: 1}));
      });
    });
