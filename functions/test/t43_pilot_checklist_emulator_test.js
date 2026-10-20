/**
 * T43 (dev-tasks-1014c §2) — the PILOT designation checklist, run as one
 * chain against the Firestore emulator in the order the W0 day will go:
 *
 *   1. meta/randomization_config.enabled = true; both strata sequences
 *      uploaded; the two sequence pointers noted.
 *   2. The unblinded researcher registers PILOT-01 (Hybrid, A), PILOT-02
 *      (Hybrid, A), PILOT-03 (rule arm, B) — three fresh uids, a pairing
 *      each.  users/{uid}: cohort pilot, arm, w0Date = registration day,
 *      armAssignmentMode pilot_designated, no isTester.
 *   3. Both pointers exactly as in step 1 (no position used); the
 *      allocation log is empty.
 *   4. pilot_assignment_log holds exactly 3 `designate` rows.
 *   5. The blinded assessor calls the W4 due list on PILOT day 25: since
 *      dev-tasks-1014e §2.12 (functions/assessor.js assessedParticipants)
 *      the three PILOT accounts are on it next to an RCT- control
 *      participant, and nothing in the returned object says arm / cohort /
 *      version / hybrid / rule / A 組 / B 組.
 *   6. meta/alert_config on (T34 field names); PILOT-01 (no isTester)
 *      writes an acute safety_events row → one e-mail to the primary,
 *      no arm, no wording.  A tester account → row, no e-mail.
 *   7. Enrolment gate on: PILOT-01 (Hybrid) may call proxyDeepSeek; an
 *      unregistered uid is refused (not_enrolled); PILOT-03 (rule arm) is
 *      refused as always (rule_arm, no reason field).
 *
 * No behaviour code is changed by this task.  Mail and Auth are the T34
 * test stubs; DeepSeek is a fetch stub.  Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/t43_pilot_checklist_emulator_test.js"
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
process.env.SMTP_HOST = "smtp.test.invalid";
process.env.SMTP_USER = "sender@test.invalid";
process.env.SMTP_PASS = "x";
process.env.PI_EMAIL = "legacy-pi@test.invalid";

// DeepSeek stub (step 7): no network, counts calls.
let modelCalls = 0;
global.fetch = async () => {
  modelCalls++;
  const resp = {
    model: "deepseek-flash",
    choices: [{message: {role: "assistant", content: "今日去咗飲茶呀？"}}],
    system_fingerprint: "fp_stub",
    usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
  };
  return {ok: true, status: 200, json: async () => resp,
    text: async () => ""};
};

const fns = require("../index");
const admin = require("firebase-admin");
const R = require("../randomization");
const A = require("../assessor");
const piAlert = require("../pi_alert");
const studyPeriod = require("../study_period");
const seqTool = require("../../tool/randomization_sequence");
const db = admin.firestore();

// Synthetic accounts and addresses only.
const JUNYU = {uid: "t43_unblinded_junyu", email: "junyu@t43.invalid",
  role: "unblinded"};
const KERAN = {uid: "t43_blinded_keran", email: "keran@t43.invalid",
  role: "blinded"};
const PRIMARY = "primary@t43.invalid";
const BACKUP = "backup@t43.invalid";
const SEED = "synthetic-test-seed-t43-0001";
// Registration happens "now": the alert trigger stamps the e-mail with the
// real clock, so the study day in it is 0 only when W0 is today.
const NOW = new Date();
const W0 = R.hkDateKey(NOW);
// PILOT day 25 (1014c: 11/9 for a 10/15 registration).
const DAY25 = new Date(NOW.getTime() + 25 * 24 * 3600 * 1000);

const PILOTS = [
  {uid: "t43_pilot_01", rid: "PILOT-01", arm: "A", variant: "feminine"},
  {uid: "t43_pilot_02", rid: "PILOT-02", arm: "A", variant: "masculine"},
  {uid: "t43_pilot_03", rid: "PILOT-03", arm: "B", variant: "feminine"},
];
const TESTER_UID = "t43_tester";
const UNREGISTERED_UID = "t43_not_registered";
// 10/19: the Phase B control registers as RCT- (PB- retired, 1020b §1).
const PB_CONTROL = {uid: "t43_pb_control", rid: "RCT-901"};

// Captured mail; Auth stub: the primary has an unblinded App account.
let sent = [];
piAlert.setMailerForTests(async (msg) => {
  sent.push(msg);
});
piAlert.setAuthForTests({
  getUserByEmail: async (email) => {
    if (email === PRIMARY) return {customClaims: {role: "unblinded"}};
    const e = new Error("not found");
    e.code = "auth/user-not-found";
    throw e;
  },
});

const COLLECTIONS = ["users", "meta", "app_config", "randomization_sequences",
  "randomization_state", "enrollments", "arm_assignment_log",
  "pilot_assignment_log", "research_id_map", "research_ids",
  "outcome_entries", "safety_events", "safety_event_dedup", "pi_alerts",
  "alert_audit_log", "llm_calls", "llm_denied_log"];

async function reset() {
  for (const c of COLLECTIONS) {
    await db.recursiveDelete(db.collection(c));
  }
  studyPeriod.resetGateCache();
  sent = [];
  modelCalls = 0;
}

async function account(uid, extra) {
  await db.doc(`users/${uid}`).set(Object.assign({
    displayName: `Synthetic ${uid}`, createdAt: "2026-10-01T10:00:00",
  }, extra || {}));
}

async function pointers() {
  const out = {};
  for (const s of R.STRATA) {
    out[s] = (await db.doc(`randomization_state/${R.sequenceDocId("v2", s)}`)
        .get()).get("next");
  }
  return out;
}

const pilotLog = async () => (await db.collection("pilot_assignment_log")
    .get()).docs.map((d) => d.data());

/** Keys AND values, recursively, plus the whole JSON string. */
const LEAK = new RegExp("arm|cohort|version|hybrid|rule|A 組|B 組|group_|" +
  "pilot_designated|randomise|strat|sequence", "i");
function assertNoLeak(obj, where) {
  if (Array.isArray(obj)) {
    obj.forEach((o, i) => assertNoLeak(o, `${where}[${i}]`));
    return;
  }
  if (obj && typeof obj === "object") {
    for (const k of Object.keys(obj)) {
      assert.ok(!LEAK.test(k), `${where}: key "${k}"`);
      assertNoLeak(obj[k], `${where}.${k}`);
    }
    return;
  }
  if (typeof obj === "string") {
    assert.ok(!LEAK.test(obj), `${where}: value "${obj}"`);
  }
}

async function fireAcute(uid, turnId) {
  const ref = await db.collection("safety_events").add({
    uid, source: "user_input", textHash: "t43hash", level: "acute",
    tier: "acute", category: "ideation", lexiconVersion: "v5-2026-09",
    crisisPageShown: true, turnId, agentId: "siu_yan", matchedTerm: "想死",
    inputPoint: "chat_reflective",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  const snap = await ref.get();
  await fns.onSafetyEventCreated.run({data: snap, params: {eventId: ref.id}});
  return ref;
}

const chat = (uid) => fns.proxyDeepSeek.run({
  auth: {uid},
  data: {
    promptKey: "siu_yan_v1",
    agentId: "siu_yan",
    moduleId: "m2_check_in",
    messages: [{role: "user", content: "早晨"}],
  },
});

const denied = async () => (await db.collection("llm_denied_log").get())
    .docs.map((d) => d.data());

let pointersAtStart = null;

const tests = [];
const test = (name, fn) => tests.push({name, fn});

// ---------------------------------------------------------------------
// Step 1
test("1. randomization switch on, both sequences uploaded, pointers noted",
    async () => {
      await reset();
      await db.doc(R.CONFIG_DOC).set({enabled: true});
      const up = await seqTool.upload(db, R.generateSequences(SEED, 80),
          {operator: JUNYU.email, version: "v2"});
      assert.ok(up.ok, up.lines.join("\n"));
      pointersAtStart = await pointers();
      for (const s of R.STRATA) {
        assert.strictEqual(typeof pointersAtStart[s], "number", s);
      }
      assert.strictEqual((await db.collection("arm_assignment_log").get())
          .size, 0);
      assert.strictEqual((await pilotLog()).length, 0);
    });

// Step 2
test("2. PILOT-01 / 02 Hybrid, PILOT-03 rule arm: cohort pilot, " +
    "studyPeriod PILOT, arm, w0Date = today, pilot_designated, no isTester",
async () => {
  // T47: the pairing is the elder's own choice from the App's onboarding;
  // the registration records it and never writes it.
  for (const p of PILOTS) await account(p.uid, {ahJanAhBakVariant: p.variant});
  for (const p of PILOTS) {
    const r = await R.enrol(db, JUNYU, {uid: p.uid, researchId: p.rid,
      pilotArm: p.arm, confirmed: true},
    {now: NOW});
    assert.strictEqual(r.companionVariant, p.variant, `${p.rid} recorded`);
    assert.notStrictEqual(r.alreadyEnrolled, true, `${p.rid} first time`);
    assert.strictEqual(r.researchId, p.rid);
    assert.strictEqual(r.studyPeriod, "PILOT");
    assert.strictEqual(r.arm, p.arm);

    const u = (await db.doc(`users/${p.uid}`).get()).data();
    assert.strictEqual(u.cohort, "pilot", `${p.rid} cohort`);
    assert.strictEqual(u.arm, p.arm, `${p.rid} arm`);
    assert.strictEqual(u.w0Date, W0, `${p.rid} w0Date = registration day`);
    assert.strictEqual(u.armAssignmentMode, "pilot_designated");
    assert.strictEqual(u.armAssignmentMethod, "pilot_designated_v1");
    assert.strictEqual(u.armAssignedBy, "researcher");
    assert.strictEqual(u.ahJanAhBakVariant, p.variant);
    assert.strictEqual(u.strataCell, undefined, "no stratum");
    assert.strictEqual(u.isTester, undefined, `${p.rid} is not a tester`);

    const e = (await db.doc(`enrollments/${p.uid}`).get()).data();
    assert.strictEqual(e.studyPeriod, "PILOT");
    assert.strictEqual(e.researchId, p.rid);
    assert.strictEqual(e.arm, p.arm);
    assert.strictEqual(e.w0Date, W0);
    assert.strictEqual(e.sequencePosition, null);
    assert.strictEqual(e.stratum, null);
    assert.strictEqual(e.w0DjgEmotional, null);
    assert.strictEqual((await db.doc(`research_id_map/${p.uid}`).get())
        .get("researchId"), p.rid);
    assert.strictEqual((await db.doc(`research_ids/${p.rid}`).get())
        .get("uid"), p.uid);
  }
});

// Step 3
test("3. both sequence pointers unchanged; allocation log still empty",
    async () => {
      assert.ok(pointersAtStart, "step 1 ran");
      assert.deepStrictEqual(await pointers(), pointersAtStart);
      assert.strictEqual((await db.collection("arm_assignment_log").get())
          .size, 0);
    });

// Step 4
test("4. pilot_assignment_log: exactly 3 rows, all `designate`", async () => {
  const logs = await pilotLog();
  assert.strictEqual(logs.length, 3);
  assert.deepStrictEqual(logs.map((l) => l.action), ["designate",
    "designate", "designate"]);
  assert.deepStrictEqual(logs.map((l) => l.researchId).sort(),
      ["PILOT-01", "PILOT-02", "PILOT-03"]);
  assert.deepStrictEqual(logs.map((l) => `${l.researchId}:${l.arm}`).sort(),
      ["PILOT-01:A", "PILOT-02:A", "PILOT-03:B"]);
  for (const l of logs) {
    assert.ok(l.at, "timestamp");
    assert.strictEqual(l.by, JUNYU.uid, "operator");
    assert.strictEqual(l.stratum, undefined);
    assert.strictEqual(l.sequencePosition, undefined);
  }
});

// Step 5
test("5a. assessor W4 list on PILOT day 25: the three PILOT accounts are " +
    "listed with the RCT- control (1014e §2.12; 1014c §0 item 1)",
async () => {
  await db.doc("app_config/feature_flags").set({assessorViewEnabled: true},
      {merge: true});
  // An RCT- control participant (PB- is retired, 1020b §1), W0 today, so
  // the list has a real row to leak-check.  It takes one sequence
  // position — the pilots took none.
  await account(PB_CONTROL.uid);
  await R.enrol(db, JUNYU, {uid: PB_CONTROL.uid, researchId: PB_CONTROL.rid,
    w0DjgEmotional: 1, companionVariant: "feminine", w0Date: W0,
    confirmed: true}, {now: NOW});
  const after = await pointers();
  const used = R.STRATA.reduce((n, s) => n + after[s] - pointersAtStart[s],
      0);
  assert.strictEqual(used, 1, "the RCT- control used exactly one position");

  const list = await A.dueList(db, KERAN, {now: DAY25});
  const ids = list.rows.map((r) => r.researchId);
  const pilotRows = ids.filter((id) => id.startsWith("PILOT-"));
  assert.strictEqual(pilotRows.length, 3, "the three PILOT accounts listed");
  assert.deepStrictEqual(ids.slice().sort(),
      ["PILOT-01", "PILOT-02", "PILOT-03", PB_CONTROL.rid].sort());
  for (const r of list.rows) {
    assert.strictEqual(r.studyDay, 25);
    assert.strictEqual(r.windowState, "open");
  }
});

test("5b. nothing in the assessor's list says arm / cohort / version / " +
    "hybrid / rule / A 組 / B 組 (keys, values, whole JSON)", async () => {
  const list = await A.dueList(db, KERAN, {now: DAY25});
  assert.ok(list.rows.length >= 1, "a row to check");
  assertNoLeak(list, "dueList");
  assert.ok(!LEAK.test(JSON.stringify(list)), JSON.stringify(list));
  assert.ok(!/"[AB]"/.test(JSON.stringify(list)), "no bare arm letter");
  assert.deepStrictEqual(Object.keys(list.rows[0]).sort(),
      ["entered", "researchId", "studyDay", "windowEndDate",
        "windowStartDate", "windowState"]);
  // The unblinded researcher is not given this list either.
  await assert.rejects(A.dueList(db, JUNYU, {now: DAY25}),
      (e) => e.assessorCode === "not_blinded");
});

// Step 6
test("6a. alert_config on; PILOT-01 acute event → one e-mail to the " +
    "primary, no arm, no wording", async () => {
  await db.doc("meta/alert_config").set({enabled: true,
    primaryEmail: PRIMARY, backupEmail: BACKUP, escalateAfterHours: 12});
  sent = [];
  const p1 = PILOTS[0];
  assert.notStrictEqual((await db.doc(`users/${p1.uid}`).get())
      .get("isTester"), true, "PILOT-01 is not a tester");
  const ref = await fireAcute(p1.uid, "t43-turn-1");

  const rows = (await db.collection("pi_alerts").get()).docs
      .map((d) => d.data());
  assert.strictEqual(rows.length, 1);
  const row = rows[0];
  assert.strictEqual(row.alertVersion, 3);
  assert.strictEqual(row.isTester, false);
  assert.strictEqual(row.researchId, "PILOT-01");
  assert.strictEqual(row.studyPeriod, "PILOT");
  assert.strictEqual(row.studyDay, 0, "registered today");
  assert.strictEqual(row.eventPath, ref.path);
  assert.deepStrictEqual(row.emailSentTo, [PRIMARY]);
  assert.ok(row.emailSentAt, "emailSentAt");
  assert.strictEqual(row.escalationPending, true);
  for (const k of ["arm", "matchedTerm", "textHash", "inputPoint",
    "cohort", "armAssignmentMode"]) {
    assert.strictEqual(row[k], undefined, `pi_alerts.${k}`);
  }

  assert.strictEqual(sent.length, 1, "exactly one e-mail");
  const m = sent[0];
  assert.strictEqual(m.to, PRIMARY, "to the primary recipient");
  assert.ok(m.text.includes("研究编号 Research ID: PILOT-01"), m.text);
  assert.ok(m.text.includes("研究期 Study period: 试跑 Pilot run"), m.text);
  assert.ok(m.text.includes("研究第几天 Study day: 0"), m.text);
  assert.ok(m.text.includes("来源 Source: 老人输入 Participant input"));
  for (const bad of ["想死", "chat_reflective", p1.uid, "Hybrid", "hybrid",
    "Arm A", "Arm B", "A 組", "B 組", "規則組", "规则组", "pilot_designated",
    "cohort", "t43hash"]) {
    assert.ok(!m.text.includes(bad) && !m.subject.includes(bad),
        `e-mail must not contain "${bad}"`);
  }
  const audit = (await db.collection("alert_audit_log")
      .where("type", "==", "email_sent").get()).size;
  assert.strictEqual(audit, 1);
});

test("6b. a tester account (isTester: true): alert row tagged, no e-mail",
    async () => {
      await account(TESTER_UID, {isTester: true, arm: "A", w0Date: W0});
      sent = [];
      await fireAcute(TESTER_UID, "t43-turn-tester");
      const rows = (await db.collection("pi_alerts").get()).docs
          .map((d) => d.data()).filter((r) => r.uid === TESTER_UID);
      assert.strictEqual(rows.length, 1, "row still written");
      assert.strictEqual(rows[0].isTester, true);
      assert.strictEqual(rows[0].escalationPending, false);
      assert.strictEqual(sent.length, 0, "no e-mail for a tester");
      assert.strictEqual((await db.collection("alert_audit_log")
          .where("type", "==", "tester_no_email").get()).size, 1);
    });

// Step 7
test("7a. enrolment gate on: PILOT-01 (Hybrid) may call the LLM entry",
    async () => {
      await db.doc("app_config/feature_flags").set(
          {enrollmentGateEnabled: true}, {merge: true});
      await db.doc("meta/memory_config").set({enabled: false});
      // The server caches the gate for 1 minute; forget it as T21's test does.
      studyPeriod.resetGateCache();
      modelCalls = 0;
      const out = await chat(PILOTS[0].uid);
      assert.ok(out.text, "a reply came back");
      assert.strictEqual(modelCalls, 1, "the model was called once");
      assert.strictEqual((await denied()).length, 0);
    });

test("7b. enrolment gate on: an unregistered uid is refused (not_enrolled)",
    async () => {
      await account(UNREGISTERED_UID);
      modelCalls = 0;
      await assert.rejects(chat(UNREGISTERED_UID),
          /permission-denied|Not registered/);
      assert.strictEqual(modelCalls, 0, "the model was not called");
      const rows = await denied();
      assert.strictEqual(rows.length, 1);
      assert.strictEqual(rows[0].uid, UNREGISTERED_UID);
      assert.strictEqual(rows[0].endpoint, "proxyDeepSeek");
      assert.strictEqual(rows[0].reason, "not_enrolled");
      assert.strictEqual(rows[0].arm, undefined);
    });

test("7c. PILOT-03 (rule arm) is refused the LLM as always (no reason field)",
    async () => {
      modelCalls = 0;
      await assert.rejects(chat(PILOTS[2].uid), /permission-denied|not part/);
      assert.strictEqual(modelCalls, 0);
      const rows = (await denied()).filter((r) => r.uid === PILOTS[2].uid);
      assert.strictEqual(rows.length, 1);
      assert.strictEqual(rows[0].reason, undefined);
      assert.strictEqual(rows[0].arm, undefined);
    });

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`  ok  ${t.name}`);
    } catch (err) {
      failed++;
      console.log(`  FAIL ${t.name}\n       ${err.stack}`);
    }
  }
  // Leave the emulator as the next test file expects it: switches off,
  // no synthetic rows.
  try {
    await reset();
  } catch (err) {
    console.error("cleanup failed:", err.message);
  }
  console.log(`t43_pilot_checklist_emulator_test: ${tests.length - failed}/` +
    `${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();
