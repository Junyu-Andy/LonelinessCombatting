/**
 * tool/readonly_check_1020.js (dev-tasks-1020 B(2), §1(2)(3)(4), H(3))
 * against the Firestore emulator with synthetic accounts: what it reports,
 * that it writes nothing, never prints an arm, and refuses off the
 * emulator without the production confirmation.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/readonly_check_1020_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const path = require("path");
const {spawnSync} = require("child_process");
const admin = require("firebase-admin");
const tool = require("../../tool/readonly_check_1020");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const SCRIPT = path.resolve(__dirname, "../../tool/readonly_check_1020.js");
const NODE_PATH = path.resolve(__dirname, "../node_modules");

const at = (iso) => admin.firestore.Timestamp.fromDate(new Date(iso));

async function reset() {
  for (const p of ["users", "enrollments"]) {
    await db.recursiveDelete(db.collection(p));
  }
}

async function seed() {
  // PB-01: retention off for 通通; one follow-up push failed (iPhone, no
  // APNs key); 今日休息 used once; one Brief PR expired unseen, from a
  // session started while on 搵人傾.
  await db.doc("enrollments/u1").set({researchId: "PB-01", studyPeriod: "B",
    arm: "A"});
  await db.doc("users/u1").set({arm: "A", cohort: "phase_b",
    consent: {transcriptRetention: true,
      transcriptRetentionByAgent: {siu_yan: true, ah_jan_ah_bak: true,
        tung_tung: false}},
    quietTodayActivatedAt: "2026-10-19T09:00:00.000"});
  await db.doc("users/u1/fcm_tokens/t1").set({token: "secret-token-1",
    platform: "iOS"});
  await db.doc("users/u1/reminders/r1").set({kind: "action_plan_followup",
    dispatchStatus: "failed",
    lastDispatchError: "messaging/third-party-auth-error"});
  await db.collection("users/u1/events").add({name: "quiet_today_activated",
    params: {}, timestamp: at("2026-10-19T01:00:00Z")});
  await db.collection("users/u1/events").add({name: "tab_view",
    params: {tab: "talk", durationSeconds: 600},
    timestamp: at("2026-10-19T02:10:00Z")});
  await db.doc("users/u1/sessions/s1").set({
    startedAt: at("2026-10-19T02:05:00Z")});
  await db.doc("users/u1/brief_pr/s1").set({sessionId: "s1",
    finalStatus: "expired", everShown: false});
  // An expired card that WAS shown does not count.
  await db.doc("users/u1/brief_pr/s2").set({sessionId: "s2",
    finalStatus: "expired", everShown: true});

  // PILOT-01: all fine, one push sent to an Android phone.
  await db.doc("enrollments/u2").set({researchId: "PILOT-01",
    studyPeriod: "PILOT", arm: "B"});
  await db.doc("users/u2").set({arm: "B", cohort: "pilot",
    consent: {transcriptRetention: true}});
  await db.doc("users/u2/fcm_tokens/t2").set({token: "secret-token-2",
    platform: "android"});
  await db.doc("users/u2/reminders/r1").set({kind: "action_plan_followup",
    dispatchStatus: "sent", delivered: true,
    dispatchedAt: at("2026-10-18T01:00:00Z")});
  await db.collection("users/u2/events").add({name: "m7_reminder_sent",
    params: {}, timestamp: at("2026-10-18T01:00:00Z")});

  // A tester with no enrolment is not a participant.
  await db.doc("users/u3").set({isTester: true,
    consent: {transcriptRetention: false}});
}

async function countAll() {
  let n = 0;
  for (const c of await db.listCollections()) {
    for (const d of (await c.get()).docs) {
      n++;
      for (const sub of await d.ref.listCollections()) {
        n += (await sub.get()).size;
      }
    }
  }
  return n;
}

function run(extraEnv, args) {
  return spawnSync(process.execPath, [SCRIPT].concat(args || []),
      {env: Object.assign({}, process.env, {NODE_PATH}, extraEnv || {}),
        encoding: "utf8"});
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("reports the four checks for PB- and PILOT- only; writes nothing",
    async () => {
      await reset();
      await seed();
      const before = await countAll();
      const r = run();
      assert.strictEqual(r.status, 0, r.stderr);
      const out = r.stdout;
      assert.match(out, /参与者（PB- 和 PILOT-）：2 人：PB-01, PILOT-01/);
      // B(2)
      assert.match(out, /✗ PB-01 .*tung_tung=false/);
      assert.match(out, /✓ PILOT-01/);
      assert.match(out, /关掉的账号：1 个/);
      // §1(2)
      assert.match(out, /PB-01: 提醒 1 条 \{"failed":1\}.*\[iOS\].*third-party-auth-error/);
      assert.match(out, /PILOT-01: 提醒 1 条 \{"sent":1\}；发出事件 1 次；最后发出 10-18 09:00/);
      // H(3)
      assert.match(out, /PB-01: 1 次 \[10-19 09:00\]/);
      assert.match(out, /合计 1 次/);
      // §1(4)
      assert.match(out, /PB-01: \{"第二页（搵人傾）":1\}/);
      // Never an arm, a token or an e-mail.
      assert.doesNotMatch(out, /arm|secret-token|@/i);
      assert.strictEqual(await countAll(), before, "nothing written");
    });

test("tabAt: the stay that covers the moment; none → null", () => {
  const v = [{at: new Date("2026-10-19T02:10:00Z"), tab: "talk",
    durationSeconds: 600}];
  assert.strictEqual(tool.tabAt(v, new Date("2026-10-19T02:01:00Z")), "talk");
  assert.strictEqual(tool.tabAt(v, new Date("2026-10-19T01:59:00Z")), null);
});

test("guard: exits 2 off the emulator without --production-confirm", () => {
  const env = {FIRESTORE_EMULATOR_HOST: ""};
  const r = run(env, ["--project=loneliness-pilot-dev"]);
  assert.strictEqual(r.status, 2, r.stderr);
  assert.match(r.stderr, /拒绝运行/);
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`  ✓ ${t.name}`);
    } catch (err) {
      failed++;
      console.error(`  ✗ ${t.name}\n    ${err.stack}`);
    }
  }
  console.log(failed ? `${failed} failed` : `${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();
