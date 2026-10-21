/**
 * T35 — the W8 questionnaire rules (handover 1021-W8 四 (2), 五 (5);
 * decision 0036), and the App-version field (开工方式 (4)).
 *
 *   - users/{uid}/{ucla3|ci|lsns6|aimhs}_responses/W8: the owner writes raw
 *     answers (each item one of its values or "skipped"), per-item answer
 *     times (server time only), status and times; studyWeek, studyDay,
 *     outOfWindow, the window and scores are server-only; frozen once
 *     submitted / declined; AIMHS alone may be "declined"; no deletes.
 *   - djg_responses/W8: the T18 rule, now also W8 with answer times.
 *   - pgic/W8 (generic owner rule): studyWeek, studyDay, outOfWindow
 *     refused from a client.
 *   - users/{uid}.appBuild: exact shape, server time, never removed.
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
  deleteField,
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
const rec = (db, col, id, uid) =>
  doc(db, 'users', uid || 'u1', col, id || 'W8');

const draft = (extra) => Object.assign({
  timepoint: 'W8',
  bundle: 'W8',
  itemsVersion: 'w8_v1',
  answers: { q1: 2 },
  answeredAt: { q1: serverTimestamp() },
  status: 'in_progress',
  startedAt: serverTimestamp(),
  startedAtLocal: '2026-12-10T10:05:00.000',
  updatedAt: serverTimestamp(),
}, extra || {});

async function seed(col, data, id) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(rec(ctx.firestore(), col, id), data);
  });
}

async function seedUser(data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', 'u1'), Object.assign({
      uid: 'u1', cohort: 'rct', arm: 'B', w0Date: '2026-10-15',
    }, data || {}));
  });
}

const W8_COLS = ['ucla3_responses', 'ci_responses', 'lsns6_responses',
  'aimhs_responses'];
const SERVER_FIELDS = {
  studyWeek: 8, studyDay: 56, submittedStudyDay: 57, outOfWindow: false,
  windowStart: Timestamp.fromDate(new Date('2026-12-09T16:00:00Z')),
  windowEnd: Timestamp.fromDate(new Date('2026-12-17T16:00:00Z')),
  acceptUntil: Timestamp.fromDate(new Date('2026-12-24T16:00:00Z')),
  scores: { total: 6 }, scoringVersion: 'x', scoredAt: serverTimestamp(),
  stampedAt: serverTimestamp(), missed: true, missedAt: serverTimestamp(),
};

describe('T35 W8 records ({ucla3,ci,lsns6,aimhs}_responses/W8)', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  it('owner creates each W8 record in progress and reads it back',
    async () => {
      for (const col of W8_COLS) {
        await assertSucceeds(setDoc(rec(me(), col), draft()));
        await assertSucceeds(getDoc(rec(me(), col)));
      }
    });

  it('another participant can neither read nor write them', async () => {
    for (const col of W8_COLS) {
      await seed(col, draft({ answeredAt: {}, startedAt: null,
        updatedAt: null }));
      await assertFails(getDoc(rec(other(), col, 'W8', 'u1')));
      await assertFails(setDoc(rec(other(), col, 'W8', 'u1'), draft()));
    }
  });

  it('only doc id W8, timepoint and bundle W8', async () => {
    await assertFails(setDoc(rec(me(), 'ucla3_responses', 'W4'),
      draft({ timepoint: 'W4', bundle: 'W4' })));
    await assertFails(setDoc(rec(me(), 'ucla3_responses'),
      draft({ timepoint: 'W4' })));
    await assertFails(setDoc(rec(me(), 'ucla3_responses'),
      draft({ bundle: 'W7' })));
  });

  it('values: UCLA-3 1–3, CI and AIMHS 1–5, LSNS-6 0–5, or "skipped"',
    async () => {
      const ok = [
        ['ucla3_responses', { q1: 1, q2: 3, q3: 'skipped' }],
        ['ci_responses', { q1: 1, q2: 5, q3: 'skipped' }],
        ['lsns6_responses', { q1: 0, q2: 5, q3: 'skipped', q4: 2, q5: 3,
          q6: 4 }],
        ['aimhs_responses', { q1: 1, q2: 5, q3: 3, q4: 'skipped', q5: 2 }],
      ];
      for (const [col, answers] of ok) {
        await assertSucceeds(setDoc(rec(me(), col),
          draft({ answers, answeredAt: {} })));
      }
      await testEnv.clearFirestore();
      const bad = [
        ['ucla3_responses', { q1: 4 }],
        ['ucla3_responses', { q1: 0 }],
        ['ucla3_responses', { q4: 1 }],
        ['ci_responses', { q1: 6 }],
        ['ci_responses', { q4: 3 }],
        ['lsns6_responses', { q1: 6 }],
        ['lsns6_responses', { q7: 1 }],
        ['aimhs_responses', { q1: 0 }],
        ['aimhs_responses', { q6: 2 }],
        ['ucla3_responses', { q1: '2' }],
        ['lsns6_responses', { q1: 'missing' }],
      ];
      for (const [col, answers] of bad) {
        await assertFails(setDoc(rec(me(), col),
          draft({ answers, answeredAt: {} })));
      }
    });

  it('client cannot write studyWeek, studyDay, outOfWindow, window or '
    + 'scores (create)', async () => {
    for (const [k, v] of Object.entries(SERVER_FIELDS)) {
      await assertFails(setDoc(rec(me(), 'ucla3_responses'),
        draft({ [k]: v })), k);
    }
  });

  it('client cannot change the server stamps on a stamped draft (update)',
    async () => {
      await seed('ucla3_responses', Object.assign(draft({
        answeredAt: {}, startedAt: null, updatedAt: null }), {
        studyWeek: 8, studyDay: 56, windowStart: SERVER_FIELDS.windowStart,
        windowEnd: SERVER_FIELDS.windowEnd,
        acceptUntil: SERVER_FIELDS.acceptUntil,
      }));
      // An ordinary answer save (merge) leaves the stamps alone: allowed.
      await assertSucceeds(setDoc(rec(me(), 'ucla3_responses'), {
        answers: { q1: 2, q2: 1 }, answeredAt: { q2: serverTimestamp() },
        updatedAt: serverTimestamp() }, { merge: true }));
      for (const [k, v] of Object.entries({ studyWeek: 7, studyDay: 60,
        outOfWindow: true, scores: { total: 3 } })) {
        await assertFails(updateDoc(rec(me(), 'ucla3_responses'),
          { [k]: v }), k);
      }
      await assertFails(updateDoc(rec(me(), 'ucla3_responses'),
        { studyWeek: deleteField() }));
    });

  it('answer times: the server time of the write, or unchanged', async () => {
    await assertFails(setDoc(rec(me(), 'ci_responses'), draft({
      answeredAt: { q1: Timestamp.fromDate(new Date('2026-12-10T02:00:00Z')) },
    })));
    await assertFails(setDoc(rec(me(), 'ci_responses'), draft({
      answeredAt: { q9: serverTimestamp() } })));
    await seed('ci_responses', draft({
      answeredAt: { q1: Timestamp.fromDate(new Date('2026-12-10T02:00:00Z')) },
      startedAt: null, updatedAt: null }));
    // Keeping q1's stored time and stamping q2 now: allowed.
    await assertSucceeds(setDoc(rec(me(), 'ci_responses'), {
      answers: { q1: 2, q2: 4 }, answeredAt: { q2: serverTimestamp() },
    }, { merge: true }));
    // Back-dating q1: refused.
    await assertFails(setDoc(rec(me(), 'ci_responses'), {
      answeredAt: { q1: Timestamp.fromDate(new Date('2026-12-01T02:00:00Z')) },
    }, { merge: true }));
  });

  it('submit needs the server time; frozen afterwards; no deletes',
    async () => {
      await assertFails(setDoc(rec(me(), 'lsns6_responses'), draft({
        status: 'submitted',
        submittedAt: Timestamp.fromDate(new Date('2026-12-10T02:00:00Z')),
      })));
      await assertSucceeds(setDoc(rec(me(), 'lsns6_responses'), draft({
        status: 'submitted', submittedAt: serverTimestamp() })));
      await assertFails(setDoc(rec(me(), 'lsns6_responses'), {
        answers: { q1: 3 } }, { merge: true }));
      await assertFails(updateDoc(rec(me(), 'lsns6_responses'),
        { status: 'in_progress' }));
      await assertFails(deleteDoc(rec(me(), 'lsns6_responses')));
    });

  it('a missed record (server) is frozen too', async () => {
    await seed('ucla3_responses', { timepoint: 'W8', bundle: 'W8',
      status: 'missed', missed: true, studyWeek: 8 });
    await assertFails(setDoc(rec(me(), 'ucla3_responses'), {
      answers: { q1: 1 }, status: 'in_progress' }, { merge: true }));
  });

  it('only AIMHS may be declined (the optional questionnaire)', async () => {
    await assertSucceeds(setDoc(rec(me(), 'aimhs_responses'), draft({
      answers: {}, answeredAt: {}, status: 'declined',
      declinedAt: serverTimestamp() })));
    await assertFails(setDoc(rec(me(), 'aimhs_responses'), {
      status: 'in_progress' }, { merge: true }), 'declined is final');
    await assertFails(setDoc(rec(me(), 'ci_responses'), draft({
      answers: {}, answeredAt: {}, status: 'declined',
      declinedAt: serverTimestamp() })));
    await testEnv.clearFirestore();
    await assertFails(setDoc(rec(me(), 'aimhs_responses'), draft({
      answers: {}, answeredAt: {}, status: 'declined',
      declinedAt: Timestamp.fromDate(new Date('2026-12-10T02:00:00Z')) })));
    // From a started AIMHS, 「唔填喇」 still declines.
    await seed('aimhs_responses', draft({ answeredAt: {}, startedAt: null,
      updatedAt: null }));
    await assertSucceeds(setDoc(rec(me(), 'aimhs_responses'), {
      status: 'declined', declinedAt: serverTimestamp() }, { merge: true }));
  });

  it('enrolment gate on: a non-enrolled, non-tester account cannot write',
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, 'app_config', 'feature_flags'),
          { enrollmentGateEnabled: true });
        await setDoc(doc(db, 'users', 'u1'), { uid: 'u1' });
      });
      await assertFails(setDoc(rec(me(), 'ucla3_responses'), draft()));
      await seedUser();
      await assertSucceeds(setDoc(rec(me(), 'ucla3_responses'), draft()));
    });
});

describe('T35 djg_responses/W8 and pgic/W8', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  const djg = (extra) => Object.assign({
    timepoint: 'W8', bundle: 'W8', itemsVersion: 'djg6_pkg3_v1',
    answers: { q1: 'yes', q2: 'skipped' },
    answeredAt: { q1: serverTimestamp(), q2: serverTimestamp() },
    status: 'in_progress', startedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }, extra || {});

  it('owner writes DJG W8 with answer times; submits with server time',
    async () => {
      await assertSucceeds(setDoc(rec(me(), 'djg_responses'), djg()));
      await assertSucceeds(setDoc(rec(me(), 'djg_responses'), {
        answers: { q1: 'yes', q2: 'skipped', q3: 'no' },
        answeredAt: { q3: serverTimestamp() },
        status: 'submitted', submittedAt: serverTimestamp(),
      }, { merge: true }));
      await assertFails(setDoc(rec(me(), 'djg_responses'), {
        answers: { q1: 'no' } }, { merge: true }), 'frozen');
    });

  it('DJG W8: back-dated answer time, scores, studyWeek, outOfWindow '
    + 'refused', async () => {
    await assertFails(setDoc(rec(me(), 'djg_responses'), djg({
      answeredAt: { q1: Timestamp.fromDate(new Date('2026-12-01T00:00:00Z')) },
    })));
    for (const k of ['scores', 'studyWeek', 'studyDay', 'outOfWindow']) {
      await assertFails(setDoc(rec(me(), 'djg_responses'),
        djg({ [k]: SERVER_FIELDS[k] })), k);
    }
  });

  it('DJG W1 without answer times still works (unchanged)', async () => {
    await assertSucceeds(setDoc(rec(me(), 'djg_responses', 'W1'), {
      timepoint: 'W1', bundle: 'W1', itemsVersion: 'djg6_pkg3_v1',
      answers: { q1: 'yes' }, status: 'in_progress',
      startedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });

  it('PGIC W8: value and times allowed; studyWeek, studyDay, outOfWindow '
    + 'refused (create and update)', async () => {
    const pgic = { bundle: 'W8', itemsVersion: 'pgic_w8_v1', value: 3,
      answeredAt: serverTimestamp(), status: 'in_progress' };
    await assertSucceeds(setDoc(rec(me(), 'pgic'), pgic));
    await testEnv.clearFirestore();
    for (const [k, v] of Object.entries({ studyWeek: 8, studyDay: 56,
      outOfWindow: false, acceptUntil: SERVER_FIELDS.acceptUntil })) {
      await assertFails(setDoc(rec(me(), 'pgic'),
        Object.assign({}, pgic, { [k]: v })), k);
    }
    await seed('pgic', Object.assign({}, pgic, { answeredAt: null,
      studyWeek: 8, studyDay: 56, outOfWindow: false }));
    for (const [k, v] of Object.entries({ studyWeek: 7, studyDay: 60,
      outOfWindow: true })) {
      await assertFails(updateDoc(rec(me(), 'pgic'), { [k]: v }), k);
    }
    await assertSucceeds(setDoc(rec(me(), 'pgic'), { value: 'skipped',
      answeredAt: serverTimestamp() }, { merge: true }));
  });
});

describe('T35 开工方式 (4): users/{uid}.appBuild', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seedUser();
  });

  const build = (extra) => Object.assign({ version: '1.0.0', build: '3',
    w8: true, platform: 'android', seenAt: serverTimestamp() }, extra || {});
  const user = (db) => doc(db, 'users', 'u1');

  it('owner reports the build with the server time', async () => {
    await assertSucceeds(updateDoc(user(me()), { appBuild: build() }));
    await assertSucceeds(updateDoc(user(me()), {
      appBuild: build({ platform: 'ios' }) }));
    const noPlatform = build();
    delete noPlatform.platform;
    await assertSucceeds(updateDoc(user(me()), { appBuild: noPlatform }));
  });

  it('wrong shape, client time, other keys or removal: refused', async () => {
    const bad = [
      build({ seenAt: Timestamp.fromDate(new Date('2026-12-01T00:00:00Z')) }),
      build({ extra: 'x' }),
      build({ w8: 'yes' }),
      build({ version: 1 }),
      build({ version: 'x'.repeat(33) }),
      (() => { const b = build(); delete b.w8; return b; })(),
      (() => { const b = build(); delete b.seenAt; return b; })(),
      'v1.0.0',
    ];
    for (const b of bad) {
      await assertFails(updateDoc(user(me()), { appBuild: b }),
        JSON.stringify(b));
    }
    await assertSucceeds(updateDoc(user(me()), { appBuild: build() }));
    await assertFails(updateDoc(user(me()), { appBuild: deleteField() }));
    await assertFails(updateDoc(user(other()), { appBuild: build() }));
  });

  it('ordinary profile saves without appBuild still pass', async () => {
    await assertSucceeds(updateDoc(user(me()), { appBuild: build() }));
    await assertSucceeds(setDoc(user(me()), { displayName: '陳太' },
      { merge: true }));
  });

  it('weekly_status (where W8 completion lives) stays server-only',
    async () => {
      await assertFails(getDoc(doc(me(), 'weekly_status', 'u1')));
      await assertFails(setDoc(doc(me(), 'weekly_status', 'u1'),
        { bundles: { W8: { completedAt: serverTimestamp() } } }));
    });
});
