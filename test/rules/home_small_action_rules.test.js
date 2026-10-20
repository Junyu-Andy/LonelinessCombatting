/**
 * 1020m 第二节 — Firestore rules for page 1's small-action row
 * (「今日想做啲咩小行動？」 / 「今日計劃：{…}」 「做咗」「改日」; both arms).
 *
 *   - usage_events: the home_small_action_* rows (five from 1020m, _more
 *     and _list from 1020n) with exactly their own extra fields —
 *     rowState (ask / plan / done / next_day_plan), planId (an
 *     action_plans id: letters, digits, _ and -), moved (bool).  No text
 *     fits; before registration nothing is written; no reads.
 *   - action_plans: the owner's 「做咗」 / 「改日」 merges (outcome,
 *     followedUpAt, followUpSource, homeRowStatus, homeRowAnsweredDate,
 *     homeRowAnsweredAt, homeRowLaterCount, homeRowDueDate, homeRowLog)
 *     pass the generic owner rule with the enrolment gate on; another
 *     account cannot write them.
 *   - reminders: the owner moves fireAt (+ movedFromFireAt, movedBy),
 *     deletes one, or queues a new one for the next day.
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
  doc, collection, setDoc, addDoc, getDoc, updateDoc, deleteDoc,
  serverTimestamp, arrayUnion, Timestamp,
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

const me = () => testEnv.authenticatedContext('u1').firestore();
const other = () => testEnv.authenticatedContext('u2').firestore();
const unblinded = () =>
  testEnv.authenticatedContext('staff', { role: 'unblinded' }).firestore();

async function seed(p, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), p), data);
  });
}

const usage = (db, uid) =>
  collection(db, 'users', uid || 'u1', 'usage_events');

function row(type, extra) {
  return Object.assign({
    type,
    clientAt: Timestamp.fromDate(new Date('2026-10-20T03:59:58Z')),
    receivedAt: serverTimestamp(),
    appVersion: '1.0.0',
    buildNumber: '3',
    platform: 'android',
    schemaVersion: 1,
  }, extra || {});
}

const PLAN = 'Xy7Qk2LmN0pRs3TuVw9a'; // a Firestore auto id

describe('1020m: home_small_action_* usage rows', () => {
  for (const [cohort, arm] of [['phase_b', 'A'], ['rct', 'B'],
    ['pilot', 'B']]) {
    it(`ALLOWS the rows for an enrolled owner (${cohort}, ${arm})`,
      async () => {
        await seed('users/u1', { uid: 'u1', cohort, arm });
        const db = me();
        await assertSucceeds(addDoc(usage(db),
          row('home_small_action_shown', { rowState: 'ask' })));
        await assertSucceeds(addDoc(usage(db),
          row('home_small_action_shown', { rowState: 'plan', planId: PLAN })));
        await assertSucceeds(addDoc(usage(db),
          row('home_small_action_shown', { rowState: 'done', planId: PLAN })));
        await assertSucceeds(addDoc(usage(db), row('home_small_action_open')));
        await assertSucceeds(addDoc(usage(db), row('home_small_action_later')));
        await assertSucceeds(addDoc(usage(db),
          row('home_small_action_done', { planId: PLAN })));
        await assertSucceeds(addDoc(usage(db),
          row('home_small_action_postpone', { planId: PLAN, moved: true })));
        await assertSucceeds(addDoc(usage(db),
          row('home_small_action_postpone', { planId: 'p_1-b', moved: false })));
        // 1020n 第三节.
        await assertSucceeds(addDoc(usage(db),
          row('home_small_action_shown',
            { rowState: 'next_day_plan', planId: PLAN })));
        await assertSucceeds(addDoc(usage(db), row('home_small_action_more')));
        await assertSucceeds(addDoc(usage(db), row('home_small_action_list')));
      });
  }

  it('DENIES the rows before registration (no cohort, even a tester)',
    async () => {
      await seed('users/u1', { uid: 'u1', isTester: true });
      await assertFails(addDoc(usage(me()), row('home_small_action_later')));
      await assertFails(addDoc(usage(me()),
        row('home_small_action_done', { planId: PLAN })));
    });

  it('DENIES text in the plan id or the row state', async () => {
    await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
    const db = me();
    await assertFails(addDoc(usage(db),
      row('home_small_action_done', { planId: '去公園行下' })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_done', { planId: 'go to the park' })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_done', { planId: 'x'.repeat(65) })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_shown', { rowState: 'hidden' })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_shown', { rowState: '今日計劃' })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_later', { text: '遲啲先' })));
  });

  it('DENIES a missing or a foreign extra field', async () => {
    await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'B' });
    const db = me();
    // shown: plan / done need the plan id; ask has none.
    await assertFails(addDoc(usage(db),
      row('home_small_action_shown', { rowState: 'plan' })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_shown', { rowState: 'ask', planId: PLAN })));
    await assertFails(addDoc(usage(db), row('home_small_action_shown')));
    // 1020n: next_day_plan needs the plan id; more / list carry nothing.
    await assertFails(addDoc(usage(db),
      row('home_small_action_shown', { rowState: 'next_day_plan' })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_more', { planId: PLAN })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_list', { count: 3 })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_more', { text: '仲有冇其他計劃？' })));
    // open / later: nothing extra.
    await assertFails(addDoc(usage(db),
      row('home_small_action_open', { planId: PLAN })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_later', { rowState: 'ask' })));
    // done: only the plan id.
    await assertFails(addDoc(usage(db), row('home_small_action_done')));
    await assertFails(addDoc(usage(db),
      row('home_small_action_done', { planId: PLAN, moved: true })));
    // postpone: the plan id and a bool.
    await assertFails(addDoc(usage(db),
      row('home_small_action_postpone', { planId: PLAN })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_postpone', { planId: PLAN, moved: 'yes' })));
    await assertFails(addDoc(usage(db),
      row('home_small_action_postpone',
        { planId: PLAN, moved: true, rowState: 'plan' })));
    // reader fields never ride along; an unknown home type is refused.
    await assertFails(addDoc(usage(db),
      row('home_small_action_done', { planId: PLAN, unitId: 'u1' })));
    await assertFails(addDoc(usage(db), row('home_small_action_skip')));
  });

  it('DENIES a client-side server field, a read, an update', async () => {
    await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
    await assertFails(addDoc(usage(me()),
      row('home_small_action_later', { researchId: 'PB-01' })));
    await seed('users/u1/usage_events/e1',
      row('home_small_action_later', { receivedAt: Timestamp.now() }));
    await assertFails(getDoc(doc(me(), 'users', 'u1', 'usage_events', 'e1')));
    await assertFails(updateDoc(doc(me(), 'users', 'u1', 'usage_events', 'e1'),
      { type: 'home_small_action_open' }));
  });

  it('DENIES another account writing the rows', async () => {
    await seed('users/u1', { uid: 'u1', cohort: 'phase_b', arm: 'A' });
    await assertFails(addDoc(usage(other(), 'u1'),
      row('home_small_action_later')));
    await assertFails(addDoc(usage(unblinded(), 'u1'),
      row('home_small_action_later')));
  });
});

describe('1020m: 做咗 / 改日 writes to action_plans and reminders', () => {
  async function seedPlan(cohort) {
    await seed('app_config/feature_flags', { enrollmentGateEnabled: true });
    await seed('users/u1', { uid: 'u1', cohort: cohort || 'phase_b', arm: 'B' });
    await seed(`users/u1/action_plans/${PLAN}`, {
      action: '去公園行下', whenText: '上晝', whereText: '', whoWith: '',
      fallback: '', arm: 'B', createdAt: Timestamp.now(),
      scheduledFor: null, outcome: null, followUpNote: null,
    });
    await seed('users/u1/reminders/r1', {
      kind: 'm7_followup', fireAt: '2026-10-21T09:30:00.000',
      titleZh: '件事點呀？', titleEn: 'How did it go?',
      bodyZh: '你之前計劃做：去公園行下。', bodyEn: 'Your plan: 去公園行下.',
      linkedDocId: PLAN, delivered: false, createdAt: Timestamp.now(),
    });
  }
  const planRef = (db) => doc(db, 'users', 'u1', 'action_plans', PLAN);
  const done = () => ({
    outcome: 'happened',
    followUpSource: 'home_row',
    homeRowStatus: 'done',
    homeRowAnsweredDate: '2026-10-21',
    followedUpAt: serverTimestamp(),
    homeRowAnsweredAt: serverTimestamp(),
    homeRowLog: arrayUnion({ status: 'done',
      atLocal: '2026-10-21T10:00:00.000', forDate: '2026-10-21',
      movedTo: null }),
  });
  const later = (n, movedTo) => Object.assign({
    homeRowStatus: 'later',
    homeRowAnsweredDate: '2026-10-21',
    homeRowLaterCount: n,
    homeRowAnsweredAt: serverTimestamp(),
    homeRowLog: arrayUnion({ status: 'later',
      atLocal: '2026-10-21T10:00:00.000', forDate: '2026-10-21',
      movedTo: movedTo || null }),
  }, movedTo ? { homeRowDueDate: movedTo } : {});

  for (const cohort of ['phase_b', 'rct']) {
    it(`ALLOWS the owner's 做咗 merge and dropping the reminder (${cohort})`,
      async () => {
        await seedPlan(cohort);
        await assertSucceeds(setDoc(planRef(me()), done(), { merge: true }));
        await assertSucceeds(
          deleteDoc(doc(me(), 'users', 'u1', 'reminders', 'r1')));
      });
  }

  it('ALLOWS the owner\'s first 改日: plan moved, reminder moved', async () => {
    await seedPlan();
    await assertSucceeds(setDoc(planRef(me()), later(1, '2026-10-22'),
      { merge: true }));
    await assertSucceeds(updateDoc(doc(me(), 'users', 'u1', 'reminders', 'r1'),
      { fireAt: '2026-10-22T09:30:00.000',
        movedFromFireAt: '2026-10-21T09:30:00.000', movedBy: 'home_row' }));
  });

  it('ALLOWS queuing the next day\'s reminder when today\'s was sent',
    async () => {
      await seedPlan();
      await assertSucceeds(addDoc(collection(me(), 'users', 'u1', 'reminders'), {
        kind: 'm7_followup', fireAt: '2026-10-22T09:30:00.000',
        titleZh: '件事點呀？', titleEn: 'How did it go?',
        bodyZh: '你之前計劃做：去公園行下。', bodyEn: 'Your plan: 去公園行下.',
        linkedDocId: PLAN, delivered: false, createdAt: serverTimestamp(),
        movedBy: 'home_row',
      }));
    });

  it('ALLOWS the owner\'s second 改日 (not moved) and dropping the reminder',
    async () => {
      await seedPlan();
      await assertSucceeds(setDoc(planRef(me()), later(2), { merge: true }));
      await assertSucceeds(
        deleteDoc(doc(me(), 'users', 'u1', 'reminders', 'r1')));
    });

  it('DENIES another account, unblinded staff, an unregistered owner',
    async () => {
      await seedPlan();
      await assertFails(setDoc(planRef(other()), done(), { merge: true }));
      await assertFails(setDoc(planRef(unblinded()), later(1, '2026-10-22'),
        { merge: true }));
      await assertFails(updateDoc(
        doc(other(), 'users', 'u1', 'reminders', 'r1'),
        { fireAt: '2026-10-22T09:30:00.000' }));
      // Enrolment gate on: an account with no cohort cannot write.
      await seed('users/u1', { uid: 'u1' });
      await assertFails(setDoc(planRef(me()), done(), { merge: true }));
    });
});
