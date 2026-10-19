/**
 * T30 — tool/analysis_export.js against the Firestore emulator
 * (dev-tasks-1010 §四 T30 §7 item 8): no lock → refuse; --lock needs two
 * confirmations (CLI) and refuses a second lock; after the lock the export
 * carries the arm and the outcome values, Phase B only, research ID
 * instead of uid, no conversation text; the synthetic set has exactly the
 * same tables and columns; every run is logged.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/analysis_export_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const admin = require("firebase-admin");
const X = require("../../tool/analysis_export");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();

const SECRET = "我個仔叫陳大文，佢住喺沙田";
const UID_A = "hybridUid0000000000000000001";
const UID_B = "ruleUid000000000000000000002";
const UID_RCT = "rctUid0000000000000000000005";

async function reset() {
  for (const c of ["users", "meta", "enrollments", "research_id_map",
    "research_ids", "outcome_entries", "allocation_records", "safety_events",
    "llm_calls", "analysis_export_log"]) {
    const docs = await db.collection(c).listDocuments();
    for (const d of docs) await db.recursiveDelete(d);
  }
}

async function seed() {
  await reset();
  const mk = async (uid, rid, arm, stratum) => {
    await db.doc(`users/${uid}`).set({uid, arm, cohort: "phase_b",
      armAssignmentMode: "randomise", w0Date: "2026-11-01",
      strataCell: stratum === "low" ? 0 : 1, displayName: "陳太",
      email: `${uid}@x.test`, ageGroup: "70-74", baselineUclaScore: 44});
    await db.doc(`enrollments/${uid}`).set({uid, researchId: rid,
      studyPeriod: "B", stratum, arm, w0Date: "2026-11-01",
      companionVariant: "feminine", enrolledAt: new Date("2026-11-01")});
    await db.doc(`research_id_map/${uid}`).set({researchId: rid});
    const u = db.doc(`users/${uid}`);
    await u.collection("djg_responses").doc("W2").set({timepoint: "W2",
      answers: {q1: "yes", q2: "no", q3: "no", q4: "yes", q5: "yes", q6: "yes"},
      scores: {emotional: 1, social: 0, total: 1}, status: "submitted"});
    await u.collection("sessions").doc("s1").set({sessionId: "s1",
      agentId: "siu_yan", moduleId: "check_in",
      startedAt: new Date("2026-11-03T02:00:00Z"), isValid: true});
    await u.collection("turns").add({sessionId: "s1", agentId: "siu_yan",
      ts: new Date("2026-11-03T02:01:00Z"), text: SECRET,
      reply: {text: SECRET}, llm: {status: arm === "A" ? "ok" : "rule_based",
        latencyMs: 900}, input: {charCount: 12}});
    await u.collection("events").add({name: "chat_open",
      ts: new Date("2026-11-03T02:00:00Z"), params: {note: SECRET}});
    await u.collection("brief_pr").doc("s1").set({schemaVersion: 3,
      sessionId: "s1", finalStatus: "completed", understanding: 6});
    await u.collection("mem_facts").add({value: SECRET});
    await db.collection("outcome_entries").add({researchId: rid, uid,
      instrument: "DJG-ES", instrumentVersion: "djg6_pkg3_v1",
      timepoint: "W4", assessmentDate: "2026-11-28", mode: "phone",
      enteredAt: new Date("2026-11-28"), answers: {q1: "yes", q2: "yes",
        q3: "yes", q4: "no", q5: "no", q6: "no"}, missingItems: [],
      scores: {emotional: 3, social: 3, total: 6}, scoringVersion: "djg6_v1",
      studyDay: 27, outOfWindow: false, correctedAt: null,
      assessorUid: "assessorKeran0000000000000001"});
    await db.collection("safety_events").add({uid, source: "user_input",
      level: "acute", tier: "acute", matchedTerm: "唔想活", textHash: "h",
      createdAt: new Date("2026-11-05")});
    await db.collection("llm_calls").add({uid, call_type: "chat",
      model_requested: "deepseek-flash", http_status: 200, latency_ms: 800,
      session_id: "s1", ts: new Date("2026-11-03")});
  };
  await mk(UID_A, "PB-101", "A", "low");
  await mk(UID_B, "PB-102", "B", "high");
  // dev-tasks-1020 §C(5): PB-102's arm was corrected after allocation (the
  // drawn arm is then not known from enrollments); RCT-01 (cohort rct,
  // 1020b §1) drew from v2.
  await db.doc(`enrollments/${UID_B}`).set(
      {correctedAt: new Date("2026-11-04")}, {merge: true});
  await db.doc(`users/${UID_RCT}`).set({arm: "B", cohort: "rct",
    armAssignmentMode: "randomise", w0Date: "2026-11-02", strataCell: 1});
  await db.doc(`enrollments/${UID_RCT}`).set({uid: UID_RCT,
    researchId: "RCT-01", studyPeriod: "B", stratum: "high", arm: "B",
    allocatedArm: "B", sequenceVersion: "v2", sequencePosition: 1,
    w0Date: "2026-11-02", enrolledAt: new Date("2026-11-02")});
  // Pilot and tester accounts: never exported.
  await db.doc("users/pilotUid000000000000000000004").set({arm: "A",
    cohort: "pilot", w0Date: "2026-11-01"});
  await db.doc("users/testerUid00000000000000003").set({arm: "B",
    isTester: true, cohort: "phase_b"});
  // A withdrawn participant's one remaining row.
  await db.doc("allocation_records/PB-103").set({researchId: "PB-103",
    studyPeriod: "B", stratum: "low", arm: "B", sequencePosition: 3,
    allocatedAt: new Date("2026-11-02"), withdrawnAt: new Date("2026-11-20")});
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("without the lock the export refuses", async () => {
  await seed();
  await assert.rejects(X.collectReal(db, {operator: "junyu@x"}),
      /not_locked/);
  assert.strictEqual((await db.collection("analysis_export_log").get()).size,
      0);
});

test("--lock writes meta/data_lock once and logs it", async () => {
  const doc = await X.lock(db, {operator: "junyu@x", note: "final",
    now: new Date("2026-12-20T02:00:00Z")});
  assert.strictEqual(doc.lockedBy, "junyu@x");
  const stored = (await db.doc(X.LOCK_DOC).get()).data();
  assert.strictEqual(stored.lockedBy, "junyu@x");
  await assert.rejects(X.lock(db, {operator: "someone@x"}), /already_locked/);
  const log = await db.collection(X.LOG_COLLECTION).get();
  assert.strictEqual(log.size, 1);
  assert.strictEqual(log.docs[0].get("mode"), "lock");
});

let real;

test("after the lock: arm + outcome values, Phase B only, research IDs, " +
    "no text, no uid, no e-mail", async () => {
  real = await X.collectReal(db, {operator: "junyu@x"});
  const f = real.files;
  assert.deepStrictEqual(f.participants.map((p) => [p.researchId, p.arm,
    p.stratum]).sort(), [["PB-101", "A", "low"], ["PB-102", "B", "high"],
    ["RCT-01", "B", "high"]]);
  const pick = (rid) => f.participants.find((p) => p.researchId === rid);
  const cols = (p) => [p.allocatedArm, p.receivedArm, p.sequenceVersion,
    p.runIn, p.analysisSet];
  assert.deepStrictEqual(cols(pick("PB-101")), ["A", "A", "v1", true,
    "run_in"]);
  assert.deepStrictEqual(cols(pick("PB-102")), [null, "B", "v1", true,
    "run_in"], "corrected: drawn arm left for a manual check");
  assert.deepStrictEqual(cols(pick("RCT-01")), ["B", "B", "v2", false,
    "rct"]);
  assert.strictEqual(f.outcome_entries.length, 2);
  const oe = f.outcome_entries.find((e) => e.researchId === "PB-101");
  assert.strictEqual(oe.arm, "A");
  assert.deepStrictEqual(oe.scores, {emotional: 3, social: 3, total: 6});
  assert.strictEqual(oe.dataset, "real");
  assert.strictEqual(f.djg_responses.length, 2);
  assert.strictEqual(f.djg_responses[0].scores.total, 1);
  assert.strictEqual(f.turns.length, 2);
  assert.strictEqual(f.turns[0].llmStatus === "ok" ||
    f.turns[0].llmStatus === "rule_based", true);
  assert.strictEqual(f.events.length, 2);
  assert.deepStrictEqual(f.memory_counts.find((m) =>
    m.researchId === "PB-101"), {dataset: "real", researchId: "PB-101",
    arm: "A", facts: 1, summaries: 0, followups: 0});
  assert.strictEqual(f.allocation_records.length, 1);
  assert.strictEqual(f.allocation_records[0].researchId, "PB-103");
  assert.strictEqual(f.allocation_records[0].sequenceVersion, "v1");
  assert.strictEqual(f.allocation_records[0].analysisSet, "run_in");
  assert.strictEqual(f.safety_events[0].matchedTerm, undefined);
  assert.strictEqual(f.llm_calls.length, 2);
  const json = JSON.stringify(f);
  assert.ok(!json.includes(SECRET), "conversation text leaked");
  assert.ok(!json.includes(UID_A) && !json.includes(UID_B), "uid leaked");
  assert.ok(!json.includes("x.test"), "e-mail leaked");
  assert.ok(!json.includes("陳太"), "name leaked");
  assert.ok(!json.includes("assessorKeran"), "assessor uid leaked");
  assert.ok(!json.includes("PILOT"), "pilot leaked");
  for (const t of Object.keys(f)) {
    for (const r of f[t]) {
      assert.deepStrictEqual(Object.keys(r), X.TABLES[t], t);
    }
  }
  assert.strictEqual(real.manifest.dataLock.lockedBy, "junyu@x");
});

test("--synthetic has the same tables and columns as the real export, " +
    "labelled synthetic", async () => {
  const syn = X.generateSynthetic({seed: "osf-dry-run", n: 72});
  assert.deepStrictEqual(Object.keys(syn.files).sort(),
      Object.keys(real.files).sort());
  assert.deepStrictEqual(X.schemaOf(syn), X.schemaOf(real));
  for (const t of Object.keys(syn.files)) {
    for (const r of syn.files[t]) assert.strictEqual(r.dataset, "synthetic");
  }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "t30-syn-"));
  const written = X.writeOut(dir, syn);
  assert.ok(written.every((f) => path.basename(f).startsWith("synthetic_")));
  const m = JSON.parse(fs.readFileSync(path.join(dir,
      "synthetic_manifest.json"), "utf8"));
  assert.strictEqual(m.synthetic, true);
  assert.strictEqual(m.participants, 72);
  fs.rmSync(dir, {recursive: true, force: true});
});

test("writeOut: one NDJSON per table plus manifest; rows parse back",
    async () => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), "t30-real-"));
      const written = X.writeOut(dir, real);
      assert.strictEqual(written.length, Object.keys(X.TABLES).length + 1);
      const rows = fs.readFileSync(path.join(dir, "outcome_entries.ndjson"),
          "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
      assert.strictEqual(rows.length, 2);
      fs.rmSync(dir, {recursive: true, force: true});
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
