/**
 * tool/delete_participant.js against the Auth + Firestore + Storage
 * emulators, with synthetic users only (SPEC:C20, decision 0020).
 *
 * Run from the repo root (tool/ci_backend_tests.sh does this):
 *   firebase emulators:exec --config test/delete_participant/firebase.json \
 *     --only auth,firestore,storage --project loneliness-pilot-dev \
 *     "NODE_PATH=functions/node_modules node \
 *      test/delete_participant/delete_participant_test.js"
 */
'use strict';
/* eslint-disable require-jsdoc */

const assert = require('assert');
const admin = require('firebase-admin');
const tool = require('../../tool/delete_participant');

for (const v of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST',
  'FIREBASE_STORAGE_EMULATOR_HOST']) {
  if (!process.env[v]) {
    console.error(`${v} not set — run inside the emulators.`);
    process.exit(1);
  }
}

const BUCKET = 'loneliness-pilot-dev.firebasestorage.app';
admin.initializeApp({projectId: 'loneliness-pilot-dev', storageBucket: BUCKET});
const db = admin.firestore();
const auth = admin.auth();
const bucket = admin.storage().bucket();

// Synthetic, realistic-length uids (Auth uids are 28 characters).
const UID = 'synthWithdrawUser0000000001';
const OTHER = 'synthStayingUser00000000002';
const SECRET = '我個仔叫陳大文，佢住喺沙田'; // must never reach the receipt
const SALT = 'feedfacefeedfacefeedfacefeedface';
const DATE = '2026-10-04';

async function clearAll() {
  for (const col of await db.listCollections()) {
    await db.recursiveDelete(col);
  }
  const [files] = await bucket.getFiles();
  await Promise.all(files.map((f) => f.delete()));
  for (const uid of [UID, OTHER]) {
    try {
      await auth.deleteUser(uid);
    } catch (_) {/* not there */}
  }
}

async function seedUser(uid) {
  await auth.createUser({uid, email: `${uid}@example.invalid`,
    password: 'synthetic-only'});
  const u = db.collection('users').doc(uid);
  await u.set({uid, email: `${uid}@example.invalid`, displayName: 'Synth',
    arm: 'A', consent: {transcriptRetention: true}});
  const sub = {
    'onboarding/intake': {onMind: SECRET},
    'sessions/s1': {participantId: uid},
    'turns/t1': {participantId: uid, input: {charCount: 12}},
    'events/e1': {name: 'open'},
    'brief_pr/b1': {understanding: 5},
    'daily_mood/d1': {mood: 3},
    'thought_exercise/x1': {thought: SECRET},
    'action_plans/a1': {action: SECRET},
    'reminders/r1': {bodyZh: SECRET},
    'agent_contexts/siu_yan': {rollingSummary: SECRET},
    'shared_context/current': {pendingReferrals: [{triggerSnippet: SECRET}]},
    'memory/m3_reminiscence/sessions/week_1': {turns: [SECRET]},
    'memory/m2_check_in/entries/e1': {summary: SECRET},
    'mem_facts/f1': {value: SECRET, quote: SECRET},
    'mem_summaries/m1': {summary: SECRET},
    'mem_followups/f1': {quote: SECRET},
    'mem_injections/i1': {memory_ids: ['f1']},
    'mem_extractions/x1': {raw_output: SECRET},
    'fcm_tokens/dev1': {token: 'synthetic'},
    'djg_es/d1': {timepoint: 'week2', score: 3},
    'djg_responses/W2': {timepoint: 'W2', answers: {q1: 'yes'},
      scores: {emotional: null, social: null, total: null}},
    // T24: weekly bundle part record (S12 probe) with study-week stamps.
    'social_contact_probes/W1': {bundle: 'W1', answers: {q1: 2, q2: 0},
      status: 'submitted', studyWeek: 1, studyDay: 7},
    // T17 (decision 0026): Phase A ADA + day-7 open questions.
    'ada_responses/visit1': {uid, timepoint: 'visit1', formVersion: 'short',
      freeText: SECRET, status: 'submitted'},
    'day7_open_responses/day7': {uid, timepoint: 'day7',
      answers: {q1: {text: SECRET}}, status: 'in_progress'},
  };
  for (const [path, data] of Object.entries(sub)) {
    await u.collection(path.split('/')[0]).doc(path.split('/').slice(1)
        .join('/')).set(data);
  }
  await db.collection('llm_calls').add({uid, call_type: 'chat'});
  await db.collection('safety_events').add({uid, textHash: 'abc',
    matchedTerm: '唔想活'});
  await db.collection('safety_event_dedup').doc(`${uid}_k`).set({uid});
  await db.collection('pi_alerts').add({uid, level: 'acute'});
  await db.collection('te_audit_queue').add({uid, thoughtPreview: SECRET});
  await db.collection('stt_usage').add({uid, bytes: 10});
  await db.collection('pending_loneliness_probes').doc(uid).set({uid});
  // T17b: server-only day-7 status (doc id = uid).
  await db.collection('ada_status').doc(uid).set({uid, researchId: null,
    day7Status: 'in_progress'});
  // T24: server-only weekly bundle status (doc id = uid).
  await db.collection('weekly_status').doc(uid).set({uid, researchId: null,
    scheduleMode: 'standard', bundles: {W1: {pushedAt: new Date()}}});
  await bucket.file(`users/${uid}/note.txt`).save('synthetic file');
}

async function seedExport() {
  await db.collection('export_blind_keys').doc(DATE).set({salt: SALT,
    mapping: {A: 'Group_X', B: 'Group_Y'}});
  const rows = (uid) => [
    {uidHash: tool.hashUid(uid, SALT), groupCode: 'Group_X'},
    {uidHash: tool.hashUid(uid, SALT), participantId: uid},
  ];
  const lines = [...rows(UID), ...rows(OTHER)].map((r) => JSON.stringify(r));
  await bucket.file(`exports/${DATE}/turns.ndjson`).save(lines.join('\n'), {
    contentType: 'application/x-ndjson',
    metadata: {metadata: {rowCount: '4'}},
  });
}

async function exportRows() {
  const [buf] = await bucket.file(`exports/${DATE}/turns.ndjson`).download();
  return buf.toString('utf8').split('\n').filter((l) => l.trim())
      .map((l) => JSON.parse(l));
}

async function residue(uid) {
  const left = [];
  const u = db.collection('users').doc(uid);
  if ((await u.get()).exists) left.push('users doc');
  if ((await u.listCollections()).length) left.push('users subcollections');
  for (const t of tool.TOP_LEVEL) {
    const s = await db.collection(t.collection).where(t.field, '==', uid)
        .get();
    if (s.size) left.push(t.collection);
  }
  if ((await db.collection('pending_loneliness_probes').doc(uid).get())
      .exists) left.push('pending_loneliness_probes/{uid}');
  try {
    await auth.getUser(uid);
    left.push('auth');
  } catch (_) {/* gone */}
  const [files] = await bucket.getFiles({prefix: `users/${uid}/`});
  if (files.length) left.push('storage');
  return left;
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});
const ctx = (extra) => Object.assign({db, auth, bucket, uid: UID,
  confirm: false, rewriteExports: false}, extra);

test('dry run lists everything and deletes nothing', async () => {
  await clearAll();
  await seedUser(UID);
  await seedUser(OTHER);
  await seedExport();
  const r = await tool.run(ctx());
  assert.strictEqual(r.mode, 'dry-run');
  const by = Object.fromEntries(r.found.firestore.map((g) =>
    [g.location, g.count]));
  assert.strictEqual(by['users/{uid}'], 1);
  assert.strictEqual(by['users/{uid}/memory/*/sessions/*'], 1);
  assert.strictEqual(by['users/{uid}/mem_facts/*'], 1);
  assert.strictEqual(by['users/{uid}/onboarding/*'], 1);
  assert.strictEqual(by['users/{uid}/ada_responses/*'], 1);
  assert.strictEqual(by['users/{uid}/day7_open_responses/*'], 1);
  assert.strictEqual(by['users/{uid}/social_contact_probes/*'], 1);
  for (const c of ['llm_calls', 'safety_events', 'safety_event_dedup',
    'pi_alerts', 'te_audit_queue', 'stt_usage',
    'pending_loneliness_probes', 'ada_status', 'weekly_status']) {
    assert.strictEqual(by[c], 1, c);
  }
  assert.strictEqual(by['safety_classifier_calls'], 0);
  assert.strictEqual(r.found.auth, 1);
  assert.strictEqual(r.found.storageUserFiles, 1);
  assert.deepStrictEqual(r.found.exports.map((e) => e.rows), [2]);
  assert.deepStrictEqual(await residue(UID).then((l) => l.length > 0), true);
  // 14 places: the user tree (2) + the top-level collections incl. T24's
  // weekly_status.
  assert.strictEqual((await residue(UID)).length, 14, 'all still there');
});

test('--confirm deletes everything of that person, nothing else', async () => {
  const r = await tool.run(ctx({confirm: true}));
  assert.strictEqual(r.verified, true, JSON.stringify(r.remaining));
  assert.deepStrictEqual(await residue(UID), []);
  // The other participant is untouched.
  const again = await tool.run(ctx({uid: OTHER}));
  const n = again.found.firestore.reduce((s, g) => s + g.count, 0);
  // incl. djg_es + djg_responses (T18), ada + day-7 (T17), ada_status
  // (T17b), social_contact_probes + weekly_status (T24)
  assert.strictEqual(n, 34);
  assert.strictEqual(again.found.auth, 1);
  // Exports are only counted by default.
  assert.strictEqual(r.exportsPolicy, 'counted only, files not modified');
  assert.strictEqual((await exportRows()).length, 4);
  assert.deepStrictEqual(r.remaining.exports.map((e) => e.rows), [2]);
});

test('the receipt carries counts only, never the text', async () => {
  await clearAll();
  await seedUser(UID);
  await seedExport();
  const r = await tool.run(ctx({confirm: true}));
  const json = JSON.stringify(r);
  assert.ok(!json.includes(SECRET), 'raw text in receipt');
  assert.ok(!json.includes('example.invalid'), 'email in receipt');
  assert.ok(!json.includes('唔想活'), 'matched term in receipt');
  assert.ok(r.notCovered.some((s) => s.startsWith('vector index: none')));
});

test('--rewrite-exports removes only that person\'s rows', async () => {
  await clearAll();
  await seedUser(UID);
  await seedUser(OTHER);
  await seedExport();
  const r = await tool.run(ctx({confirm: true, rewriteExports: true}));
  assert.strictEqual(r.verified, true);
  const rows = await exportRows();
  assert.strictEqual(rows.length, 2);
  assert.ok(rows.every((x) => x.uidHash === tool.hashUid(OTHER, SALT)));
  const [meta] = await bucket.file(`exports/${DATE}/turns.ndjson`)
      .getMetadata();
  assert.strictEqual(meta.metadata.rowCount, '2');
});

// T30 (dev-tasks-1010 §四 T30 §5.1): with --allocation-record the whole
// person goes, including the allocation-log rows that carry the uid, and
// ONE row allocation_records/{researchId} stays: research ID, stratum,
// arm, allocation time, withdrawal date — no uid, name or contact.
test('--allocation-record keeps one row without personal data and ' +
    'deletes the allocation log rows; T30 collections are covered', async () => {
  await clearAll();
  await seedUser(UID);
  await seedUser(OTHER);
  await db.collection('enrollments').doc(UID).set({uid: UID,
    researchId: 'PB-017', studyPeriod: 'B', stratum: 'high', arm: 'A',
    sequencePosition: 4, companionVariant: 'feminine',
    enrolledAt: new Date('2026-11-01T02:00:00Z'),
    enrolledByEmail: 'junyu@example.invalid'});
  await db.collection('arm_assignment_log').add({action: 'allocate', uid: UID,
    researchId: 'PB-017', arm: 'A'});
  await db.collection('arm_assignment_log').add({action: 'allocate',
    uid: OTHER, researchId: 'PB-018', arm: 'B'});
  await db.collection('outcome_entries').add({uid: UID, researchId: 'PB-017',
    instrument: 'DJG-ES', answers: {q1: 'yes'}});
  await db.collection('pairing_change_log').add({uid: UID, from: 'feminine',
    to: 'masculine'});
  await db.collection('weekly_status').doc(UID).set({w4VisitDate: '2026-11-27'});
  // Without the flag (T19 behaviour): the log rows are not in the plan.
  const dry = await tool.run(ctx());
  const byDry = Object.fromEntries(dry.found.firestore.map((g) =>
    [g.location, g.count]));
  assert.strictEqual(byDry['arm_assignment_log'], undefined);
  assert.strictEqual(byDry['outcome_entries'], 1);
  assert.strictEqual(byDry['pairing_change_log'], 1);
  assert.strictEqual(byDry['weekly_status'], 1);
  assert.ok(String(dry.allocationRecord).startsWith('not requested'));
  // With the flag.
  const r = await tool.run(ctx({confirm: true, allocationRecord: true,
    now: new Date('2026-11-20T03:00:00Z')}));
  assert.strictEqual(r.verified, true, JSON.stringify(r.remaining));
  assert.deepStrictEqual(r.allocationRecord.path,
      'allocation_records/PB-017');
  assert.deepStrictEqual(await residue(UID), []);
  assert.strictEqual((await db.collection('arm_assignment_log')
      .where('uid', '==', UID).get()).size, 0, 'log row with uid deleted');
  assert.strictEqual((await db.collection('arm_assignment_log')
      .where('uid', '==', OTHER).get()).size, 1, 'other person untouched');
  const rec = (await db.collection('allocation_records').doc('PB-017').get())
      .data();
  assert.deepStrictEqual(Object.keys(rec).sort(), ['allocatedAt', 'arm',
    'researchId', 'sequencePosition', 'sequenceVersion', 'stratum',
    'studyPeriod', 'withdrawnAt', 'writtenBy']);
  assert.strictEqual(rec.arm, 'A');
  assert.strictEqual(rec.stratum, 'high');
  assert.strictEqual(rec.withdrawnAt.toDate().toISOString(),
      '2026-11-20T03:00:00.000Z');
  // The receipt names the uid on purpose (it is the operator's record of
  // whom it deleted); the kept row and its receipt entry must not.
  const json = JSON.stringify(rec) + JSON.stringify(r.allocationRecord);
  assert.ok(!json.includes(UID), 'uid in the kept row');
  assert.ok(!json.includes('example.invalid'), 'e-mail kept');
  assert.ok(!json.includes('Synth'), 'name kept');
  assert.ok(!r.notCovered.some((l) => l.startsWith('arm_assignment_log')));
});

test('row matching: uidHash, participantId or the raw uid in a path', () => {
  const h = tool.hashUid(UID, SALT);
  assert.ok(tool.rowMatches(JSON.stringify({uidHash: h}), UID, h));
  assert.ok(tool.rowMatches(JSON.stringify({participantId: UID}), UID, null));
  assert.ok(tool.rowMatches(JSON.stringify(
      {originTurnRef: `users/${UID}/turns/t1`}), UID, null));
  assert.ok(!tool.rowMatches(JSON.stringify(
      {uidHash: tool.hashUid(OTHER, SALT)}), UID, h));
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`PASS  ${t.name}`);
    } catch (err) {
      failed++;
      console.log(`FAIL  ${t.name}\n      ${err.stack}`);
    }
  }
  console.log(`\n${tests.length - failed} passed, ${failed} failed.`);
  process.exit(failed ? 1 : 0);
})();
