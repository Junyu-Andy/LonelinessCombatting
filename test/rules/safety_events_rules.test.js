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

// 1020e 二.9 — the 「誤觸」 (false alarm) mark is the server's
// (markSafetyFalseAlarm): no client sets it on a safety event or on a chat
// check-in row; the App still writes its own check-in row as before.
describe('false alarm mark is server-only (1020e 二.9)', () => {
  const db = () => testEnv.authenticatedContext('alice').firestore();
  const row = (id) => doc(db(), 'users', 'alice', 'check_in_responses', id);
  const plain = {flow: 'chat_v2', date_iso: '2026-10-21',
    stopped_by_safety: true, completed: false};

  for (const field of ['falseAlarm', 'markedBy', 'markedAt']) {
    it(`safety_events: a client create may not carry ${field}`, async () => {
      await assertFails(addDoc(collection(db(), 'safety_events'),
          event({[field]: field === 'falseAlarm' ? true : 'x'})));
    });

    it(`check_in_responses: a client create may not carry ${field}`,
        async () => {
          await assertFails(setDoc(row('c1'), Object.assign({}, plain,
              {[field]: field === 'falseAlarm' ? true : 'x'})));
        });
  }

  it('check_in_responses: the App row writes and merges as before',
      async () => {
        await assertSucceeds(setDoc(row('c1'), plain));
        await assertSucceeds(setDoc(row('c1'), {completed: true},
            {merge: true}));
        await assertSucceeds(getDoc(row('c1')));
      });

  it('check_in_responses: a client may not set or clear the mark later',
      async () => {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          await setDoc(doc(ctx.firestore(), 'users', 'alice',
              'check_in_responses', 'c2'), Object.assign({}, plain,
              {falseAlarm: true, markedBy: 'r1', markedAt: 'x'}));
        });
        await assertFails(setDoc(row('c1'), Object.assign({}, plain,
            {falseAlarm: true})));
        await assertFails(updateDoc(row('c2'), {falseAlarm: false}));
        await assertFails(updateDoc(row('c2'), {markedBy: 'alice'}));
        // Other fields of a marked row stay the App's; the mark survives.
        await assertSucceeds(setDoc(row('c2'), {completed: false},
            {merge: true}));
        await assertSucceeds(getDoc(row('c2')));
      });

  it('safety_events: still no client update (cannot mark)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'safety_events', 'e1'), event());
    });
    await assertFails(updateDoc(doc(db(), 'safety_events', 'e1'),
        {falseAlarm: true}));
  });

  it('pi_alerts: no client write of the mark, even for unblinded',
      async () => {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          await setDoc(doc(ctx.firestore(), 'pi_alerts', 'a1'),
              {uid: 'alice', level: 'acute', eventPath: 'safety_events/e1'});
        });
        const r = testEnv.authenticatedContext('r1', {role: 'unblinded'})
            .firestore();
        await assertFails(updateDoc(doc(r, 'pi_alerts', 'a1'),
            {falseAlarm: true}));
      });
});
