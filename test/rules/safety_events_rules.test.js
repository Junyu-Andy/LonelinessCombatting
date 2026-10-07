/**
 * T7 — safety_events create rules (source bucket, trigger-only fields)
 * and hotline_filter_log (Cloud Functions only).
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
  doc, getDoc, addDoc, collection,
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
