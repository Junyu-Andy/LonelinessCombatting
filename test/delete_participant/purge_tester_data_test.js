/**
 * tool/purge_tester_data.js (T32 item 6) against the Auth + Firestore +
 * Storage emulators, with synthetic accounts only.
 *
 * Run from the repo root (tool/ci_backend_tests.sh does this):
 *   firebase emulators:exec --config test/delete_participant/firebase.json \
 *     --only auth,firestore,storage --project loneliness-pilot-dev \
 *     "NODE_PATH=functions/node_modules node \
 *      test/delete_participant/purge_tester_data_test.js"
 */
'use strict';
/* eslint-disable require-jsdoc */

const assert = require('assert');
const admin = require('firebase-admin');
const purge = require('../../tool/purge_tester_data');
const deletion = require('../../tool/delete_participant');

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

const SECRET = '我個仔叫陳大文，佢住喺沙田'; // must never reach any log

// Synthetic accounts (Auth uids are 28 characters).
const TESTER_BIG = 'synthTesterBig0000000000001';
const TESTER_SMALL = 'synthTesterSmall00000000002';
const UNENROLLED = 'synthUnenrolledArmB00000003';
const AUTH_ONLY = 'synthAuthOnlyNoUserDoc00004';
const DOC_ONLY = 'synthDocOnlyNoAuth000000005';
const PHASE_A_OLD = 'synthOldPhaseACohort0000006';
const PB = 'synthEnrolledPhaseB00000007';
const PILOT = 'synthEnrolledPilot000000008';
const STAFF = 'synthUnblindedStaff00000009';
const BLINDED = 'synthBlindedAssessor0000010';
const ENROLLED_TESTER = 'synthEnrolledTester00000011';
const ALL = [TESTER_BIG, TESTER_SMALL, UNENROLLED, AUTH_ONLY, DOC_ONLY,
  PHASE_A_OLD, PB, PILOT, STAFF, BLINDED, ENROLLED_TESTER];
const TO_PURGE = [AUTH_ONLY, DOC_ONLY, PHASE_A_OLD, TESTER_BIG,
  TESTER_SMALL, UNENROLLED].sort();
const TO_KEEP = [BLINDED, ENROLLED_TESTER, PB, PILOT, STAFF].sort();

async function clearAll() {
  for (const col of await db.listCollections()) {
    await db.recursiveDelete(col);
  }
  const [files] = await bucket.getFiles();
  await Promise.all(files.map((f) => f.delete()));
  // Earlier test files in the same emulator run leave their synthetic
  // Auth accounts behind; the listing counts every account, so start
  // from an empty Auth emulator.
  let token;
  do {
    const page = await auth.listUsers(1000, token);
    for (const u of page.users) await auth.deleteUser(u.uid);
    token = page.pageToken;
  } while (token);
}

async function createAuth(uid, claims) {
  await auth.createUser({uid, email: `${uid}@example.invalid`,
    password: 'synthetic-only'});
  if (claims) await auth.setCustomUserClaims(uid, claims);
}

/** users/{uid} plus a realistic spread of data; `big` adds more. */
async function seedData(uid, fields, big) {
  const u = db.collection('users').doc(uid);
  await u.set(Object.assign({uid, displayName: 'Synth'}, fields));
  const sub = {
    'sessions/s1': {participantId: uid},
    'turns/t1': {participantId: uid, input: {charCount: 12}},
    'events/e1': {name: 'open'},
    'fcm_tokens/dev1': {token: 'synthetic'},
  };
  if (big) {
    Object.assign(sub, {
      'onboarding/intake': {onMind: SECRET},
      'brief_pr/b1': {understanding: 5},
      'daily_mood/d1': {mood: 3},
      'agent_contexts/siu_yan': {rollingSummary: SECRET},
      'memory/m2_check_in/entries/e1': {summary: SECRET},
      'mem_facts/f1': {value: SECRET, quote: SECRET},
      'mem_summaries/m1': {summary: SECRET},
      'djg_responses/W2': {timepoint: 'W2', answers: {q1: 'yes'}},
    });
  }
  for (const [path, data] of Object.entries(sub)) {
    await u.collection(path.split('/')[0]).doc(path.split('/').slice(1)
        .join('/')).set(data);
  }
  await db.collection('llm_calls').add({uid, call_type: 'chat'});
  if (big) {
    await db.collection('safety_events').add({uid, textHash: 'abc',
      matchedTerm: '唔想活'});
    await db.collection('pi_alerts').add({uid, level: 'acute'});
    await db.collection('stt_usage').add({uid, bytes: 10});
    await db.collection('research_id_map').doc(uid).set({uid,
      researchId: 'TEST-OLD'});
    await bucket.file(`users/${uid}/note.txt`).save('synthetic file');
  }
}

async function enrol(uid, researchId, cohort, studyPeriod) {
  await db.collection('enrollments').doc(uid).set({uid, researchId,
    studyPeriod, w0Score: 5});
  await db.collection('research_id_map').doc(uid).set({uid, researchId});
  await db.collection('arm_assignment_log').add({uid, researchId,
    action: 'allocate', arm: 'A'});
}

async function seedAll() {
  await clearAll();
  // Testers: one with lots of data (Hybrid), one tiny.
  await createAuth(TESTER_BIG);
  await seedData(TESTER_BIG, {isTester: true, arm: 'A'}, true);
  await createAuth(TESTER_SMALL);
  await seedData(TESTER_SMALL, {isTester: true, arm: 'B'}, false);
  // Registered in the App but never enrolled (no cohort), arm B.
  await createAuth(UNENROLLED);
  await seedData(UNENROLLED, {arm: 'B'}, false);
  // Auth account that never wrote users/{uid}.
  await createAuth(AUTH_ONLY);
  // users/{uid} left behind after its Auth account went.
  await seedData(DOC_ONLY, {arm: 'A'}, false);
  // Old Phase A cohort label: not a study period any more.
  await createAuth(PHASE_A_OLD);
  await seedData(PHASE_A_OLD, {cohort: 'phase_a', arm: 'A'}, true);
  // Enrolled Phase B participant (PB-…) with data.
  await createAuth(PB);
  await seedData(PB, {cohort: 'phase_b', arm: 'A',
    researchId: 'PB-001'}, true);
  await enrol(PB, 'PB-001', 'phase_b', 'B');
  // Enrolled pilot-run account (PILOT-…).
  await createAuth(PILOT);
  await seedData(PILOT, {cohort: 'pilot', arm: 'B',
    researchId: 'PILOT-01'}, false);
  await enrol(PILOT, 'PILOT-01', 'pilot', 'PILOT');
  // Staff: unblinded researcher (no cohort, not a tester) and a blinded
  // assessor marked isTester (the T21 §4.5 transition).
  await createAuth(STAFF, {role: 'unblinded'});
  await seedData(STAFF, {}, false);
  await createAuth(BLINDED, {role: 'blinded'});
  await seedData(BLINDED, {isTester: true}, false);
  // A tester flag on an enrolled account: enrolment wins.
  await createAuth(ENROLLED_TESTER);
  await seedData(ENROLLED_TESTER, {isTester: true, cohort: 'phase_b',
    arm: 'B', researchId: 'PB-002'}, false);
  await enrol(ENROLLED_TESTER, 'PB-002', 'phase_b', 'B');
}

/** Total items delete_participant.js would find for uid (counts only). */
async function footprint(uid) {
  const r = await deletion.run({db, auth, bucket, uid, confirm: false,
    rewriteExports: false});
  return r.found.auth + r.found.storageUserFiles +
    r.found.firestore.reduce((n, g) => n + g.count, 0);
}

const ctx = (extra) => Object.assign({db, auth, bucket, confirm: false,
  keep: [], target: 'emulator'}, extra);

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test('classify: each kind, enrolment and role win over isTester', () => {
  const c = (a) => purge.classify(Object.assign({user: null, role: null,
    enrollment: false, keep: false}, a)).kind;
  assert.strictEqual(c({user: {isTester: true}}), 'tester');
  assert.strictEqual(c({user: {arm: 'B'}}), 'unenrolled');
  assert.strictEqual(c({user: null}), 'unenrolled');
  assert.strictEqual(c({user: {cohort: 'phase_a'}}), 'unenrolled');
  assert.strictEqual(c({user: {cohort: 'phase_b'}}), 'enrolled');
  assert.strictEqual(c({user: {cohort: 'pilot', isTester: true}}),
      'enrolled');
  assert.strictEqual(c({user: {isTester: true}, enrollment: true}),
      'enrolled');
  for (const role of ['unblinded', 'blinded', 'pi', 'researcher']) {
    assert.strictEqual(c({user: {isTester: true}, role}), 'staff', role);
  }
  assert.strictEqual(c({user: {isTester: true}, keep: true}), 'keep');
  assert.deepStrictEqual(purge.PURGEABLE, ['tester', 'unenrolled']);
});

test('list-only shows the right set with volumes and deletes nothing',
    async () => {
      await seedAll();
      const before = {};
      for (const uid of ALL) before[uid] = await footprint(uid);
      assert.ok(before[TESTER_BIG] > 15, 'big tester has data');

      const {log} = await purge.run(ctx());
      assert.strictEqual(log.mode, 'list-only');
      assert.strictEqual(log.accountsSeen, ALL.length);
      assert.deepStrictEqual(log.selected.map((r) => r.uid).sort(), TO_PURGE);
      assert.deepStrictEqual(log.kept.map((r) => r.uid).sort(), TO_KEEP);
      const kind = Object.fromEntries(
          [...log.selected, ...log.kept].map((r) => [r.uid, r.kind]));
      assert.strictEqual(kind[TESTER_BIG], 'tester');
      assert.strictEqual(kind[TESTER_SMALL], 'tester');
      assert.strictEqual(kind[UNENROLLED], 'unenrolled');
      assert.strictEqual(kind[AUTH_ONLY], 'unenrolled');
      assert.strictEqual(kind[DOC_ONLY], 'unenrolled');
      assert.strictEqual(kind[PHASE_A_OLD], 'unenrolled');
      assert.strictEqual(kind[PB], 'enrolled');
      assert.strictEqual(kind[PILOT], 'enrolled');
      assert.strictEqual(kind[ENROLLED_TESTER], 'enrolled');
      assert.strictEqual(kind[STAFF], 'staff');
      assert.strictEqual(kind[BLINDED], 'staff');
      assert.deepStrictEqual(log.byKind, {tester: 2, unenrolled: 4,
        enrolled: 3, staff: 2});

      // Volumes: per-subcollection counts, top-level rows, auth, storage.
      const big = log.selected.find((r) => r.uid === TESTER_BIG);
      assert.strictEqual(big.volume.auth, 1);
      assert.strictEqual(big.volume.storageUserFiles, 1);
      assert.strictEqual(big.volume.firestore['users/{uid}/mem_facts/*'], 1);
      assert.strictEqual(big.volume.firestore['llm_calls'], 1);
      assert.strictEqual(big.volume.firestore['research_id_map'], 1);
      assert.strictEqual(big.volume.firestoreDocs + big.volume.auth +
        big.volume.storageUserFiles, before[TESTER_BIG]);
      const authOnly = log.selected.find((r) => r.uid === AUTH_ONLY);
      assert.strictEqual(authOnly.hasUserDoc, false);
      assert.strictEqual(authOnly.volume.auth, 1);
      assert.strictEqual(authOnly.volume.firestoreDocs, 0);
      const docOnly = log.selected.find((r) => r.uid === DOC_ONLY);
      assert.strictEqual(docOnly.hasAuth, false);
      assert.strictEqual(docOnly.volume.auth, 0);
      assert.ok(docOnly.volume.firestoreDocs >= 5);
      assert.ok(log.selected.every((r) => r.deleted === false));

      // Nothing changed, no run log written.
      for (const uid of ALL) {
        assert.strictEqual(await footprint(uid), before[uid], uid);
      }
      assert.strictEqual((await db.collection('admin_runs').get()).size, 0);
      // Counts only: no text, no e-mail in the log.
      const json = JSON.stringify(log);
      assert.ok(!json.includes(SECRET));
      assert.ok(!json.includes('example.invalid'));
      assert.ok(!json.includes('唔想活'));
    });

test('--only, --keep and --created-before narrow the set', async () => {
  let r = await purge.run(ctx({only: 'testers'}));
  assert.deepStrictEqual(r.log.selected.map((x) => x.uid).sort(),
      [TESTER_BIG, TESTER_SMALL].sort());
  const left = r.log.kept.find((x) => x.uid === UNENROLLED);
  assert.ok(left && /--only=testers/.test(left.reason));

  r = await purge.run(ctx({only: 'unenrolled', volumes: false}));
  assert.deepStrictEqual(r.log.selected.map((x) => x.uid).sort(),
      [AUTH_ONLY, DOC_ONLY, PHASE_A_OLD, UNENROLLED].sort());
  assert.ok(r.log.selected.every((x) => x.volume === undefined));

  r = await purge.run(ctx({keep: [TESTER_BIG, UNENROLLED], volumes: false}));
  assert.deepStrictEqual(r.log.selected.map((x) => x.uid).sort(),
      [AUTH_ONLY, DOC_ONLY, PHASE_A_OLD, TESTER_SMALL].sort());
  assert.strictEqual(r.log.kept.find((x) => x.uid === TESTER_BIG).kind,
      'keep');

  // Every Auth account was created just now; only the account without
  // an Auth record qualifies as "created before 2000".
  r = await purge.run(ctx({createdBefore: '2000-01-01T00:00:00Z',
    volumes: false}));
  assert.deepStrictEqual(r.log.selected.map((x) => x.uid), [DOC_ONLY]);
  assert.ok(/--created-before/.test(
      r.log.kept.find((x) => x.uid === TESTER_BIG).reason));
  // Future cut-off: back to the full set.
  r = await purge.run(ctx({createdBefore: '2999-01-01T00:00:00Z',
    volumes: false}));
  assert.deepStrictEqual(r.log.selected.map((x) => x.uid).sort(), TO_PURGE);
});

test('--confirm deletes exactly the listed set and logs the run',
    async () => {
      const before = {};
      for (const uid of TO_KEEP) before[uid] = await footprint(uid);
      const logsBefore = (await db.collection('arm_assignment_log').get())
          .size;

      const {log, receipts} = await purge.run(ctx({confirm: true,
        operator: 'synthetic-operator'}));
      assert.strictEqual(log.mode, 'confirm');
      assert.deepStrictEqual(log.selected.map((r) => r.uid).sort(), TO_PURGE);
      assert.ok(log.selected.every((r) => r.deleted && r.verified),
          JSON.stringify(log.selected));
      assert.strictEqual(log.allVerified, true);
      assert.deepStrictEqual(Object.keys(receipts).sort(), TO_PURGE);
      assert.ok(receipts[TESTER_BIG].verified);

      // Purged accounts are gone everywhere delete_participant.js looks.
      for (const uid of TO_PURGE) {
        assert.strictEqual(await footprint(uid), 0, uid);
      }
      // Kept accounts are untouched, including their enrolment records
      // and the allocation log.
      for (const uid of TO_KEEP) {
        assert.strictEqual(await footprint(uid), before[uid], uid);
        if (uid !== STAFF && uid !== BLINDED) {
          assert.ok((await db.collection('enrollments').doc(uid).get())
              .exists, `enrollments/${uid}`);
        }
        await auth.getUser(uid); // throws if the account went
      }
      assert.strictEqual((await db.collection('arm_assignment_log').get())
          .size, logsBefore);

      // Server-only run log: one admin_runs doc, counts only.
      const runs = await db.collection('admin_runs').get();
      assert.strictEqual(runs.size, 1);
      const doc = runs.docs[0].data();
      assert.strictEqual(runs.docs[0].id, log.adminRunId);
      assert.strictEqual(doc.tool, 'tool/purge_tester_data.js');
      assert.strictEqual(doc.mode, 'confirm');
      assert.strictEqual(doc.operator, 'synthetic-operator');
      assert.strictEqual(doc.allVerified, true);
      assert.deepStrictEqual(doc.selected.map((r) => r.uid).sort(), TO_PURGE);
      assert.deepStrictEqual(doc.kept.map((r) => r.uid).sort(), TO_KEEP);
      assert.ok(doc.kept.find((r) => r.uid === STAFF).reason
          .includes('unblinded'));
      const json = JSON.stringify(Object.assign({}, doc, {receipts}));
      assert.ok(!json.includes(SECRET), 'raw text in run log');
      assert.ok(!json.includes('example.invalid'), 'email in run log');
      assert.ok(!json.includes('唔想活'), 'matched term in run log');

      // Running again finds nothing left to delete.
      const again = await purge.run(ctx({volumes: false}));
      assert.deepStrictEqual(again.log.selected, []);
      assert.deepStrictEqual(again.log.kept.map((r) => r.uid).sort(),
          TO_KEEP);
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
  try {
    await clearAll();
  } catch (_) {/* best effort */}
  console.log(`\n${tests.length - failed} passed, ${failed} failed.`);
  process.exit(failed ? 1 : 0);
})();
