/**
 * T17 (decision 0026) — Firestore rules for the Phase A ADA and day-7
 * open questions (users/{uid}/ada_responses, day7_open_responses).
 * Synthetic data only.  The owner saves a draft per screen, submits once,
 * and can't change or delete it afterwards; nobody else can read or write.
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
  doc, setDoc, getDoc, deleteDoc, collection, getDocs,
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

const AGENTS = ['siu_yan', 'ah_jan_ah_bak', 'tung_tung'];
const TRAITS = ['warm', 'same_age', 'curious', 'non_judgmental'];
const SCENARIOS = ['day_recap', 'memories', 'learn_new', 'feeling_down',
  'small_talk'];

/** What AdaPage writes for one synthetic participant. */
function adaDoc(form, timepoint, status, extra) {
  const usage = {};
  const traits = {};
  for (const a of AGENTS) usage[a] = 2;
  for (const t of TRAITS) {
    traits[t] = {};
    for (const a of AGENTS) traits[t][a] = 4;
  }
  traits.curious.tung_tung = 'skipped';
  const d = Object.assign({
    schemaVersion: 1, instrument: 'ada', studyPhase: 'A', uid: 'u1',
    timepoint, formVersion: form, itemsVersion: 'ada-placeholder-20261007',
    recallWindowZh: '喺過去兩個星期，正常一個禮拜入面', allowSkip: true,
    ahJanAhBakVariant: 'masculine', usage, traits,
    freeText: '通通識好多嘢。', freeTextStatus: 'answered',
    freeTextInputMode: 'typed', status, lastScreen: 3,
    startedAt: new Date('2026-10-07T02:00:00Z'),
  }, extra || {});
  if (form === 'full') {
    d.scenarios = {};
    for (const s of SCENARIOS) d.scenarios[s] = 'ah_jan_ah_bak';
    d.scenarios.learn_new = 'any';
  }
  return d;
}

describe('ada_responses rules', () => {
  for (const [form, tp] of [['short', 'visit1'], ['full', 'day7']]) {
    it(`owner saves ${form} form per screen, then submits`, async () => {
      const ref = doc(owner(), 'users', 'u1', 'ada_responses', tp);
      await assertSucceeds(setDoc(ref, adaDoc(form, tp, 'in_progress')));
      await assertSucceeds(setDoc(ref,
          adaDoc(form, tp, 'in_progress', {lastScreen: 5}), {merge: true}));
      await assertSucceeds(setDoc(ref, adaDoc(form, tp, 'submitted'),
          {merge: true}));
      const snap = await assertSucceeds(getDoc(ref));
      if (snap.get('formVersion') !== form) throw new Error('round trip');
    });
  }

  it('submitted answers are frozen and never deletable', async () => {
    const ref = doc(owner(), 'users', 'u1', 'ada_responses', 'visit1');
    await assertSucceeds(setDoc(ref, adaDoc('short', 'visit1', 'submitted')));
    await assertFails(setDoc(ref,
        adaDoc('short', 'visit1', 'submitted', {freeText: 'changed'})));
    await assertFails(setDoc(ref,
        adaDoc('short', 'visit1', 'in_progress'), {merge: true}));
    await assertFails(deleteDoc(ref));
  });

  it('a draft cannot be deleted either', async () => {
    const ref = doc(owner(), 'users', 'u1', 'ada_responses', 'visit1');
    await assertSucceeds(setDoc(ref, adaDoc('short', 'visit1', 'in_progress')));
    await assertFails(deleteDoc(ref));
  });

  it('uid, timepoint and status must be consistent', async () => {
    const ref = doc(owner(), 'users', 'u1', 'ada_responses', 'visit1');
    await assertFails(setDoc(ref,
        adaDoc('short', 'visit1', 'in_progress', {uid: 'u2'})));
    await assertFails(setDoc(ref, adaDoc('short', 'day7', 'in_progress')));
    await assertFails(setDoc(ref, adaDoc('short', 'visit1', 'done')));
  });

  it('another participant can neither read nor write', async () => {
    await assertSucceeds(setDoc(
        doc(owner(), 'users', 'u1', 'ada_responses', 'visit1'),
        adaDoc('short', 'visit1', 'in_progress')));
    await assertFails(getDoc(doc(other(), 'users', 'u1', 'ada_responses',
        'visit1')));
    await assertFails(getDocs(collection(other(), 'users', 'u1',
        'ada_responses')));
    await assertFails(setDoc(
        doc(other(), 'users', 'u1', 'ada_responses', 'day7'),
        adaDoc('short', 'day7', 'in_progress', {uid: 'u2'})));
  });

  it('unauthenticated clients are refused', async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'users', 'u1', 'ada_responses',
        'visit1')));
  });
});

describe('day7_open_responses rules', () => {
  const d7 = (status, extra) => Object.assign({
    schemaVersion: 1, instrument: 'day7_open', studyPhase: 'A', uid: 'u1',
    timepoint: 'day7', itemsVersion: 'day7-open-placeholder-20261007',
    answers: {
      q1: {text: '每朝同小欣講早晨。', status: 'answered', inputMode: 'typed'},
      q2: {text: null, status: 'skipped'},
      q3: {text: '想多啲新聞。', status: 'answered', inputMode: 'typed'},
    },
    status, lastScreen: 2,
  }, extra || {});

  it('owner saves, submits; then frozen', async () => {
    const ref = doc(owner(), 'users', 'u1', 'day7_open_responses', 'day7');
    await assertSucceeds(setDoc(ref, d7('in_progress')));
    await assertSucceeds(setDoc(ref, d7('submitted'), {merge: true}));
    await assertFails(setDoc(ref, d7('submitted', {lastScreen: 0}),
        {merge: true}));
    await assertFails(deleteDoc(ref));
  });

  it('another participant can neither read nor write', async () => {
    const ref = doc(owner(), 'users', 'u1', 'day7_open_responses', 'day7');
    await assertSucceeds(setDoc(ref, d7('in_progress')));
    await assertFails(getDoc(doc(other(), 'users', 'u1',
        'day7_open_responses', 'day7')));
    await assertFails(setDoc(doc(other(), 'users', 'u1',
        'day7_open_responses', 'day7'), d7('in_progress', {uid: 'u2'})));
  });
});

describe('other owner subcollections unchanged', () => {
  it('owner still writes and deletes e.g. agent_diff (old page)', async () => {
    const ref = doc(owner(), 'users', 'u1', 'agent_diff', 'x');
    await assertSucceeds(setDoc(ref, {wave: 2, timepoint: 'week2'}));
    await assertSucceeds(deleteDoc(ref));
  });
});
