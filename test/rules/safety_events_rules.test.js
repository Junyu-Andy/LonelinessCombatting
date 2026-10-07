/**
 * T7 — safety_events create rules (source bucket, trigger-only fields)
 * and hotline_filter_log (Cloud Functions only); T8
 * safety_classifier_calls (App adds own fallback rows only).
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
  doc, getDoc, addDoc, collection, updateDoc, deleteDoc, setDoc,
  serverTimestamp,
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

const event = (over) => Object.assign({
  uid: 'alice',
  source: 'user_input',
  inputPoint: 'thought_exercise',
  turnId: 't1',
  textHash: 'abc',
  level: 'acute',
  tier: 'acute',
}, over);

describe('safety_events (T7)', () => {
  const db = () => testEnv.authenticatedContext('alice').firestore();

  for (const source of ['user_input', 'ai_output_scan', 'form',
    'gateway_input', 'rule_turn']) {
    it(`accepts source ${source}`, async () => {
      await assertSucceeds(addDoc(collection(db(), 'safety_events'),
          event({source})));
    });
  }

  it('rejects a missing source', async () => {
    const e = event();
    delete e.source;
    await assertFails(addDoc(collection(db(), 'safety_events'), e));
  });

  it('rejects an unknown source', async () => {
    await assertFails(addDoc(collection(db(), 'safety_events'),
        event({source: 'whatever'})));
  });

  it('rejects another user\'s uid', async () => {
    await assertFails(addDoc(collection(db(), 'safety_events'),
        event({uid: 'bob'})));
  });

  it('rejects client-set dedup fields', async () => {
    await assertFails(addDoc(collection(db(), 'safety_events'),
        event({isDuplicate: false})));
    await assertFails(addDoc(collection(db(), 'safety_events'),
        event({dedup_key: 'x'})));
  });
});

describe('hotline_filter_log (T7)', () => {
  it('clients can neither read nor write', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await addDoc(collection(ctx.firestore(), 'hotline_filter_log'),
          {uid: 'alice', count: 1});
    });
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(addDoc(collection(db, 'hotline_filter_log'),
        {uid: 'alice', count: 1}));
    await assertFails(getDoc(doc(db, 'hotline_filter_log', 'x')));
  });
});

describe('safety_classifier_calls (T8)', () => {
  const db = () => testEnv.authenticatedContext('alice').firestore();
  const row = (over) => Object.assign({
    uid: 'alice', writer: 'app', status: 'client_timeout',
    input_point: 'check_in_note', source: 'user_input', turn_id: 't1',
    latency_ms: 1500, ts: serverTimestamp(),
  }, over);

  it('accepts the App fallback row (timeout / error)', async () => {
    await assertSucceeds(addDoc(collection(db(), 'safety_classifier_calls'),
        row()));
    await assertSucceeds(addDoc(collection(db(), 'safety_classifier_calls'),
        row({status: 'client_error'})));
  });

  it('rejects another uid, server rows, other statuses, extra fields',
      async () => {
        const c = collection(db(), 'safety_classifier_calls');
        await assertFails(addDoc(c, row({uid: 'bob'})));
        await assertFails(addDoc(c, row({writer: 'server'})));
        await assertFails(addDoc(c, row({status: 'ok'})));
        await assertFails(addDoc(c, row({level: 'acute'})));
        await assertFails(addDoc(c, row({text: '我想死'})));
      });

  it('no client reads, updates or deletes', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'safety_classifier_calls', 'x'),
          {uid: 'alice', writer: 'server', status: 'ok'});
    });
    const ref = doc(db(), 'safety_classifier_calls', 'x');
    await assertFails(getDoc(ref));
    await assertFails(updateDoc(ref, {status: 'error'}));
    await assertFails(deleteDoc(ref));
  });

  it('safety_events still accepts the T8 classifier fields', async () => {
    await assertSucceeds(addDoc(collection(db(), 'safety_events'),
        event({detector: 'classifier', classifierStatus: 'ok',
          classifierLevel: 'acute', classifierScore: 0.9,
          classifierVersion: 'lora-1'})));
  });
});
