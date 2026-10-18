/**
 * Tester arm switch (functions/tester_arm.js, callable setTesterArm)
 * against the Firestore emulator, with synthetic accounts only:
 *   - a tester switched to A passes assertLlmAllowed at once; switched to
 *     B it is refused at once and logged in llm_denied_log (no cache);
 *   - a participant (isTester not true) is refused and nothing is written;
 *   - the switch writes cohort / mode / w0Date only when missing, never
 *     strataCell, updates an existing enrollments doc, and logs one
 *     arm_assignment_log row with action "tester_switch";
 *   - the switch app_config/feature_flags.testerArmSwitchEnabled is off
 *     by default;
 *   - a tester in A has memory v1 (inScope, extraction writes mem_facts /
 *     mem_summaries); switching to B and back keeps the items;
 *   - the weekly bundle dispatch includes a switched tester only.
 * DeepSeek is stubbed: nothing leaves the machine.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/tester_arm_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ||
  "loneliness-pilot-dev";
process.env.DEEPSEEK_API_KEY = "test-key";

let modelCalls = 0;
let extraction = {summary: "", facts: [], followups: []};
global.fetch = async (url, init) => {
  modelCalls++;
  const body = JSON.parse(init.body);
  const content = body.response_format ?
    JSON.stringify(extraction) : "今日去咗飲茶呀？";
  const resp = {model: "deepseek-flash",
    choices: [{message: {role: "assistant", content}}],
    usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}};
  return {ok: true, status: 200, json: async () => resp,
    text: async () => JSON.stringify(resp)};
};

const fns = require("../index");
const testerArm = require("../tester_arm");
const memory = require("../memory");
const studyPeriod = require("../study_period");
const weeklySchedule = require("../weekly_schedule");
const admin = require("firebase-admin");
const db = admin.firestore();

async function clear(name) {
  const docs = await db.collection(name).listDocuments();
  await Promise.all(docs.map((d) => db.recursiveDelete(d)));
}

async function reset(flagOn) {
  for (const n of ["users", "enrollments", "arm_assignment_log",
    "llm_denied_log", "llm_calls", "app_config", "weekly_bundle_status"]) {
    await clear(n);
  }
  await db.doc("meta/memory_config").set({enabled: true, policy: "C",
    phaseBArmA: true});
  if (flagOn !== undefined) {
    await db.doc("app_config/feature_flags").set(
        {testerArmSwitchEnabled: flagOn});
  }
  studyPeriod.resetGateCache();
  modelCalls = 0;
}

const switchArm = (uid, arm) => fns.setTesterArm.run({auth: {uid},
  data: {arm}});

const chat = (uid) => fns.proxyDeepSeek.run({
  auth: {uid},
  data: {promptKey: "siu_yan_v1", agentId: "siu_yan",
    moduleId: "m2_check_in", messages: [{role: "user", content: "早晨"}]},
});

const rows = async (name) => (await db.collection(name).get())
    .docs.map((d) => d.data());

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("userPatch / isSwitchedTester (pure)", async () => {
  const now = new Date("2026-10-16T17:00:00Z"); // 10-17 01:00 HKT
  assert.deepStrictEqual(testerArm.userPatch({}, "A", now), {
    arm: "A", armAssignedBy: "tester_switch", armAssignedAt: now,
    cohort: "pilot", armAssignmentMode: "pilot_designated",
    armAssignmentMethod: "pilot_designated_v1", w0Date: "2026-10-17"});
  assert.deepStrictEqual(testerArm.userPatch({cohort: "phase_b",
    armAssignmentMode: "randomise", w0Date: "2026-09-01", strataCell: 1},
  "B", now), {arm: "B", armAssignedBy: "tester_switch", armAssignedAt: now});
  assert.strictEqual(testerArm.isSwitchedTester({isTester: true,
    armAssignedBy: "tester_switch"}), true);
  assert.strictEqual(testerArm.isSwitchedTester({isTester: false,
    armAssignedBy: "tester_switch"}), false);
  assert.strictEqual(testerArm.isSwitchedTester(null), false);
});

test("switch to A passes the LLM guard, switch to B is refused at once",
    async () => {
      await reset(true);
      await db.doc("users/t1").set({isTester: true, displayName: "T"});
      // Warm the arm cache as B first: a cached participant would stay B
      // for 10 minutes; a tester must not.
      await switchArm("t1", "B");
      await assert.rejects(chat("t1"), /permission-denied|not part/);
      await switchArm("t1", "A");
      const out = await chat("t1");
      assert.ok(out.text);
      await switchArm("t1", "B");
      await assert.rejects(chat("t1"), /permission-denied|not part/);
      const denied = (await rows("llm_denied_log"))
          .filter((r) => r.uid === "t1");
      assert.strictEqual(denied.length, 2);
      assert.strictEqual(denied[0].endpoint, "proxyDeepSeek");
      assert.strictEqual(modelCalls, 1, "only the Arm A call reached it");
    });

test("a participant is refused and nothing is written", async () => {
  await reset(true);
  const before = {arm: "A", armAssignmentMode: "randomise",
    cohort: "phase_b", strataCell: 1, w0Date: "2026-10-01"};
  await db.doc("users/p1").set(before);
  await db.doc("users/p2").set({isTester: false, arm: "B"});
  await db.doc("enrollments/p1").set({arm: "A", researchId: "PB-001"});
  for (const [uid, arm] of [["p1", "B"], ["p2", "A"], ["ghost", "A"]]) {
    await assert.rejects(switchArm(uid, arm),
        (e) => e.code === "permission-denied", uid);
  }
  assert.deepStrictEqual((await db.doc("users/p1").get()).data(), before);
  assert.strictEqual((await db.doc("users/p2").get()).get("arm"), "B");
  assert.strictEqual((await db.doc("enrollments/p1").get()).get("arm"), "A");
  assert.strictEqual((await db.doc("users/ghost").get()).exists, false);
  assert.strictEqual((await rows("arm_assignment_log")).length, 0);
});

test("unauthenticated, flag off and a bad arm are refused", async () => {
  await reset();
  await db.doc("users/t1").set({isTester: true});
  await assert.rejects(fns.setTesterArm.run({data: {arm: "A"}}),
      (e) => e.code === "unauthenticated");
  await assert.rejects(switchArm("t1", "A"),
      (e) => e.code === "failed-precondition", "no flags doc = off");
  await db.doc("app_config/feature_flags").set(
      {testerArmSwitchEnabled: "true"});
  await assert.rejects(switchArm("t1", "A"),
      (e) => e.code === "failed-precondition", "only literal true");
  await db.doc("app_config/feature_flags").set(
      {testerArmSwitchEnabled: true});
  await assert.rejects(switchArm("t1", "C"),
      (e) => e.code === "invalid-argument");
  assert.strictEqual((await db.doc("users/t1").get()).get("arm"), undefined);
  assert.strictEqual((await rows("arm_assignment_log")).length, 0);
});

test("fields written, enrollments updated, one log row per switch",
    async () => {
      await reset(true);
      await db.doc("users/t1").set({isTester: true, arm: "A",
        armAssignmentMode: "force_a", strataCell: 0});
      const now = new Date();
      const r = await switchArm("t1", "B");
      assert.deepStrictEqual(r, {arm: "B", from: "A", changed: true});
      const u = (await db.doc("users/t1").get()).data();
      assert.strictEqual(u.arm, "B");
      assert.strictEqual(u.cohort, "pilot");
      assert.strictEqual(u.armAssignmentMode, "pilot_designated");
      assert.strictEqual(u.armAssignmentMethod, "pilot_designated_v1");
      assert.strictEqual(u.armAssignedBy, "tester_switch");
      assert.strictEqual(u.w0Date,
          require("../randomization").hkDateKey(now));
      assert.strictEqual(u.strataCell, 0, "strataCell untouched");
      assert.strictEqual((await db.doc("enrollments/t1").get()).exists,
          false, "no enrollments row created");
      const log = await rows("arm_assignment_log");
      assert.strictEqual(log.length, 1);
      assert.strictEqual(log[0].action, "tester_switch");
      assert.strictEqual(log[0].uid, "t1");
      assert.strictEqual(log[0].from, "A");
      assert.strictEqual(log[0].to, "B");
      assert.strictEqual(log[0].by, "t1");
      assert.ok(log[0].at);
      assert.strictEqual(log[0].researchId, undefined);
      assert.strictEqual(log[0].sequencePosition, undefined);

      // Existing values are kept; an existing enrollments doc follows.
      await db.doc("users/t2").set({isTester: true, cohort: "phase_b",
        armAssignmentMode: "randomise", w0Date: "2026-09-01"});
      await db.doc("enrollments/t2").set({arm: "B", researchId: "PB-T2"});
      await switchArm("t2", "A");
      const u2 = (await db.doc("users/t2").get()).data();
      assert.strictEqual(u2.cohort, "phase_b");
      assert.strictEqual(u2.armAssignmentMode, "randomise");
      assert.strictEqual(u2.w0Date, "2026-09-01");
      const e2 = (await db.doc("enrollments/t2").get()).data();
      assert.strictEqual(e2.arm, "A");
      assert.strictEqual(e2.researchId, "PB-T2");
      assert.strictEqual((await rows("arm_assignment_log")).length, 2);
    });

test("memory: tester in A is in scope, items survive B and back",
    async () => {
      await reset(true);
      const uid = "tmem";
      const u = db.collection("users").doc(uid);
      await u.set({isTester: true, consent: {sharedContextUse: true}});
      await switchArm(uid, "A");
      const cfg = await memory.loadConfig(db);
      assert.strictEqual(memory.inScope(cfg, (await u.get()).data()), true);

      // One chat: the App leaves the user's turns in the buffer, then
      // calls memoryEndSession.
      await u.collection("agent_contexts").doc("siu_yan").set({
        shortTermBuffer: [{fromUser: true, text: "我個孫叫阿明",
          timestamp: new Date().toISOString()}],
        lastUpdated: new Date()});
      extraction = {summary: "傾咗孫仔阿明", followups: [], facts: [{
        op: "add", category: "family", key: "孫", value: "阿明",
        quote: "我個孫叫阿明"}]};
      const r = await fns.memoryEndSession.run({auth: {uid},
        data: {agentId: "siu_yan"}});
      assert.strictEqual(r.status, "done", JSON.stringify(r));
      const facts = await u.collection("mem_facts").get();
      const sums = await u.collection("mem_summaries").get();
      assert.strictEqual(facts.size, 1);
      assert.strictEqual(sums.size, 1);

      await switchArm(uid, "B");
      assert.strictEqual(memory.inScope(cfg, (await u.get()).data()), false);
      assert.strictEqual(await memory.memoryActive(db, uid), null);
      assert.strictEqual((await u.collection("mem_facts").get()).size, 1,
          "switching to B deletes nothing");

      await switchArm(uid, "A");
      assert.ok(await memory.memoryActive(db, uid));
      assert.strictEqual((await u.collection("mem_facts").get()).size, 1);
      assert.strictEqual((await u.collection("mem_summaries").get()).size,
          1);
      const block = await memory.injectMemory(db, {uid, agentId: "siu_yan",
        moduleId: "m2_check_in",
        messages: [{role: "user", content: "你好"}]});
      assert.ok(block.includes("阿明"), "memory injected again");
      extraction = {summary: "", facts: [], followups: []};
    });

test("memory: withdrawn tester and kill switch still win", async () => {
  const user = {isTester: true, arm: "A"};
  const on = {enabled: true, phaseBArmA: true};
  assert.strictEqual(memory.inScope(on, user), true);
  assert.strictEqual(memory.inScope({enabled: false, phaseBArmA: true},
      user), false);
  assert.strictEqual(memory.inScope(on,
      Object.assign({memoryWithdrawnAt: new Date()}, user)), false);
  assert.strictEqual(memory.inScope(on, {isTester: true, arm: "B"}), false);
  assert.strictEqual(memory.inScope(on, {arm: "A",
    armAssignmentMode: "force_a"}), false, "participant rule unchanged");
});

test("weekly dispatch: a switched tester is scheduled, others are not",
    async () => {
      await reset(true);
      await db.recursiveDelete(db.collection("weekly_status"));
      await db.doc(weeklySchedule.CONFIG_DOC).set(
          {weeklyScheduleV2Enabled: true});
      const W0 = "2026-10-01";
      // Switched tester (w0Date kept as set).
      await db.doc("users/sw").set({isTester: true, w0Date: W0});
      await switchArm("sw", "B");
      // A tester with a cohort but no switch (e.g. set_tester.js
      // --allow-registered) stays out, as before.
      await db.doc("users/old").set({isTester: true, cohort: "pilot",
        w0Date: W0, arm: "A", armAssignedBy: "researcher"});
      for (const uid of ["sw", "old"]) {
        await db.doc(`users/${uid}/fcm_tokens/d1`).set({token: `tok-${uid}`});
      }
      const sent = [];
      // Study day 7, 20:00 Hong Kong time: W1 opens.
      const counts = await weeklySchedule.dispatchWeeklyBundles(db,
          {send: async (m) => {
            sent.push(m);
            return "id";
          }},
          {now: new Date("2026-10-08T12:00:00Z"), log: () => {},
            quiet: require("../quiet_hours").quietHoursConfigFrom({})});
      assert.strictEqual(counts.pushed, 1, JSON.stringify(counts));
      assert.deepStrictEqual(sent.map((m) => m.token), ["tok-sw"]);
      const st = await db.doc(`${weeklySchedule.STATUS_COLLECTION}/sw`).get();
      assert.ok(st.exists);
      assert.strictEqual(st.get("researchId"), null);
      assert.strictEqual((await db.doc(
          `${weeklySchedule.STATUS_COLLECTION}/old`).get()).exists, false);
      await db.doc(weeklySchedule.CONFIG_DOC).delete();
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
