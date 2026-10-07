/**
 * T12 blinding against the Firestore emulator: research IDs at arm
 * assignment and as a backfill, and the v2 export built from a synthetic
 * two-arm cohort (with every leaky field we know of planted in it),
 * scanned by tool/check_blinded_export.js.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/blinding_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {spawnSync} = require("child_process");
const admin = require("firebase-admin");
const {assignArm} = require("../arm");
const blinding = require("../blinding");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const CHECKER = path.join(__dirname, "..", "..", "tool",
    "check_blinded_export.js");

// 28-character ids, the shape of real Firebase uids, so the checker's
// raw-uid pattern would catch any that leak.
const UID_A = "hybridParticipant00000000001";
const UID_B = "ruleParticipant0000000000002";
const UID_PHASE_A = "phaseAParticipant00000000003";
const UID_TESTER = "testerAccount000000000000004";

async function wipe(ref) {
  const cols = await ref.listCollections();
  for (const c of cols) {
    const docs = await c.listDocuments();
    for (const d of docs) {
      await wipe(d);
      await d.delete();
    }
  }
}

async function reset() {
  for (const name of ["users", "meta", "app_config", "research_id_map",
    "research_ids", "export_blind_keys", "safety_events"]) {
    const docs = await db.collection(name).listDocuments();
    for (const d of docs) {
      await wipe(d);
      await d.delete();
    }
  }
}

const ts = (iso) => admin.firestore.Timestamp.fromDate(new Date(iso));

async function seedUser(uid, arm, extra) {
  await db.doc(`users/${uid}`).set(Object.assign({
    uid, email: `${uid}@example.test`, displayName: "陳太",
    ageGroup: "70-74", baselineUclaScore: 50, strataCell: 3,
    arm, armAssignmentMode: "randomise", armAssignedBy: "server",
    emergencyContactPhone: "91234567", avoidTopics: "唔想講我個仔嘅事",
    interests: ["粵劇"], hasCompletedIntake: true,
    consent: {transcriptRetention: true},
    createdAt: ts("2026-10-01T02:00:00Z"),
  }, extra || {}));
  const u = db.doc(`users/${uid}`);
  const sessionRef = `users/${uid}/sessions/s1`;
  await u.collection("brief_pr").add({schemaVersion: 2, agentId: "siu_yan",
    agentDisplayName: "小欣", sessionRef, understanding: 6, validation: 5,
    caring: 6, insensitivity: 2, isAnchorPrompt: false, status: "completed",
    promptedAt: ts("2026-10-02T02:00:00Z"),
    respondedAt: ts("2026-10-02T02:01:00Z"), arm});
  await u.collection("weekly_pr").add({weekIso: "2026-W40",
    agentId: "tung_tung", items: {u1: 5, v1: 6}, status: "completed",
    sessionCountThisWeek: arm === "A" ? 9 : 3, referentRule: "max_sessions",
    promptedAt: ts("2026-10-04T12:00:00Z"), arm});
  await u.collection("pgic").add({value: 5, isoWeek: "2026-W40",
    weekIso: "2026-W40", answeredAt: ts("2026-10-04T12:05:00Z")});
  await u.collection("djg_es").add({timepoint: "t0", itemsVersion: "v1",
    answers: {e1: 1, e2: 0}, score: 3, status: "completed",
    answeredAt: ts("2026-10-01T03:00:00Z"),
    answeredAtLocal: "2026-10-01T11:00:00.000"});
  // T18: the W2 DJG doc as the App + server leave it after scoring.
  await u.collection("djg_responses").doc("W2").set({timepoint: "W2",
    itemsVersion: "djg6_pkg3_v1",
    answers: {q1: "yes", q2: "mostly", q3: "no", q4: "no", q5: "skipped",
      q6: "yes"},
    status: "submitted", startedAt: ts("2026-10-14T02:05:00Z"),
    startedAtLocal: "2026-10-14T10:05:00.000",
    submittedAt: ts("2026-10-14T02:08:00Z"),
    submittedAtLocal: "2026-10-14T10:08:00.000",
    updatedAt: ts("2026-10-14T02:08:00Z"),
    pushSentAt: ts("2026-10-14T02:00:00Z"),
    scores: {emotional: 2, social: null, total: null},
    scoringVersion: "djg6_pkg3_v1", scoredAt: ts("2026-10-14T02:08:01Z"),
    outsideWindow: false, w0Date: "2026-10-01",
    windowStartDate: "2026-10-14", windowEndDate: "2026-10-20"});
  await u.collection("agent_diff").add({wave: 1, timepoint: "d7",
    usageFreq: {siu_yan: 3}, personality: {siu_yan: {warm: 5}},
    function: null, freeResponse: "小欣好似識得諗嘢咁",
    answeredAt: ts("2026-10-07T03:00:00Z")});
  await u.collection("daily_mood").add({mood: 4, date_iso: "2026-10-03",
    is_primary: true, entry_seq_today: 1,
    source_surface: arm === "A" ? "check_in_arm_a" : "check_in_arm_b",
    responded_at: ts("2026-10-03T11:00:00Z"), arm});
  await u.collection("loneliness_probes").add({score: 4, isoWeek: "2026-W40",
    answeredAt: "2026-10-04T12:00:00.000"});
  await u.collection("sessions").add({participantId: uid, kind: "agent",
    moduleId: arm === "A" ? "reflective_dialogue" : "m2_check_in",
    startedAt: ts("2026-10-05T02:00:00Z"), fallbackCount: 1});
  await u.collection("sessions").add({participantId: uid, kind: "agent",
    moduleId: "m2_check_in", startedAt: ts("2026-10-06T02:00:00Z")});
  await u.collection("turns").add({participantId: uid,
    llm: arm === "A" ?
      {status: "ok", model: "deepseek-flash", promptVersion: "v3"} :
      {status: "rule_based"}});
  await u.collection("events").add({name: arm === "A" ? "te_offer" :
    "rule_submit", params: {offerText: "我覺得好孤單"}, arm});
  if (arm === "A") {
    await u.collection("llm_turn_features").add({agentId: "siu_yan"});
    await u.collection("mem_facts").add({quote: "我個女喺加拿大"});
  } else {
    await u.collection("check_in_responses").add({note: "今日去咗街市"});
  }
}

async function seedCohort() {
  await seedUser(UID_A, "A");
  await seedUser(UID_B, "B");
  await seedUser(UID_PHASE_A, "A", {armAssignmentMode: "force_a"});
  await seedUser(UID_TESTER, "B", {isTester: true});
  const ev = (uid, source, level) => db.collection("safety_events").add({
    uid, source, level, tier: level, category: "loneliness",
    lexiconVersion: "v5", agentId: "siu_yan", textHash: "f".repeat(64),
    matchedTerm: "好想死", createdAt: ts("2026-10-05T03:00:00Z"),
  });
  await ev(UID_A, "gateway_input", "moderate");
  await ev(UID_A, "gateway_output", "moderate"); // Hybrid-only source
  await ev(UID_B, "rule_turn", "acute");
  await ev(UID_PHASE_A, "gateway_input", "acute");
}

function fakeBucket(dir) {
  return {
    file: (name) => ({
      save: async (content) => {
        const full = path.join(dir, name);
        fs.mkdirSync(path.dirname(full), {recursive: true});
        fs.writeFileSync(full, content);
      },
    }),
  };
}

async function exportToDir(opts) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "blind-export-"));
  const built = await blinding.buildBlindedExport(db, Object.assign(
      {dateKey: "2026-10-11"}, opts || {}));
  await blinding.writeBlindedExport(fakeBucket(dir), built, "2026-10-11");
  return {built, dir: path.join(dir, blinding.EXPORT_PREFIX, "2026-10-11")};
}

const readNdjson = (dir, name) => {
  const f = path.join(dir, `${name}.ndjson`);
  if (!fs.existsSync(f)) return [];
  return fs.readFileSync(f, "utf8").split("\n").filter(Boolean)
      .map((l) => JSON.parse(l));
};

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("assignArm, switch off (default): no research ID", async () => {
  await reset();
  await db.doc("users/u1").set({ageGroup: "60-64"});
  await assignArm(db, "u1");
  assert.strictEqual((await db.doc("research_id_map/u1").get()).exists,
      false);
  assert.strictEqual((await db.collection("research_ids").get()).size, 0);
});

test("assignArm, switch on: research ID in both lookup collections, " +
    "never on the profile", async () => {
  await reset();
  await db.doc(blinding.CONFIG_DOC).set({enabled: true});
  await db.doc("app_config/arm_assignment").set({randomise: true});
  await db.doc("users/u1").set({ageGroup: "60-64"});
  await assignArm(db, "u1");
  const map = (await db.doc("research_id_map/u1").get()).data();
  assert.ok(blinding.RID_PATTERN.test(map.researchId), map.researchId);
  assert.strictEqual(map.via, "assign_arm");
  const back = (await db.doc(`research_ids/${map.researchId}`).get()).data();
  assert.strictEqual(back.uid, "u1");
  const profile = (await db.doc("users/u1").get()).data();
  assert.strictEqual(JSON.stringify(profile).indexOf(map.researchId), -1);
  // A second call (already assigned) keeps the same ID.
  await assignArm(db, "u1");
  assert.strictEqual((await db.collection("research_ids").get()).size, 1);
  assert.strictEqual(await blinding.ensureResearchId(db, "u1"),
      map.researchId);
});

test("a taken research ID is skipped", async () => {
  await reset();
  await db.doc("research_ids/P000000").set({uid: "someone-else"});
  let calls = 0;
  const randomInt = () => (calls++ < 6 ? 0 : 1);
  const rid = await blinding.ensureResearchId(db, "u9", {randomInt});
  assert.strictEqual(rid, "P111111");
  assert.strictEqual(
      (await db.doc("research_ids/P000000").get()).get("uid"),
      "someone-else");
});

test("concurrent ensureResearchId calls give one ID", async () => {
  await reset();
  const ids = await Promise.all([1, 2, 3, 4].map(
      () => blinding.ensureResearchId(db, "u5")));
  assert.strictEqual(new Set(ids).size, 1);
  assert.strictEqual((await db.collection("research_ids").get()).size, 1);
});

test("v2 export of a synthetic two-arm cohort passes the checker",
    async () => {
      await reset();
      await seedCohort();
      const {built, dir} = await exportToDir({includeUsageSummary: true});
      const withBpr = await exportToDir({includeBriefPr: true});
      assert.strictEqual(readNdjson(withBpr.dir, "brief_pr").length, 2);
      assert.strictEqual(spawnSync("node", [CHECKER, withBpr.dir]).status, 0);

      const run = spawnSync("node", [CHECKER, dir], {encoding: "utf8"});
      assert.strictEqual(run.status, 0, run.stdout + run.stderr);

      const files = fs.readdirSync(dir).sort();
      for (const held of ["turns", "events", "sessions", "llm_turn_features",
        "mem_facts", "check_in_responses", "users", "pi_alerts"]) {
        assert.ok(files.indexOf(`${held}.ndjson`) < 0, held);
      }
      // Only the two randomised, non-tester participants.
      const people = readNdjson(dir, "participants");
      assert.strictEqual(people.length, 2);
      assert.deepStrictEqual(people.map((p) => p.groupCode).sort(),
          ["Group_X", "Group_Y"]);
      assert.deepStrictEqual(Object.keys(people[0]).sort(), [
        "ageGroup", "baselineUclaScore", "enrolledDate", "groupCode",
        "hasCompletedIntake", "researchId", "strataCell"]);
      assert.deepStrictEqual(built.manifest.excludedParticipants,
          {notRandomised: 1, tester: 1});
      // Safety: the Hybrid-only AI-output row is dropped, user-input
      // rows from both arms stay, without `source`.
      const safety = readNdjson(dir, "safety_events");
      assert.strictEqual(safety.length, 2);
      assert.ok(safety.every((r) => r.source === undefined));
      assert.strictEqual(built.manifest.safetyEventsNotFromUserInput, 1);
      // Outcomes from both arms, stripped of arm-specific fields.
      const weekly = readNdjson(dir, "weekly_pr");
      assert.strictEqual(weekly.length, 2);
      assert.ok(weekly.every((r) => r.sessionCountThisWeek === undefined));
      const usage = readNdjson(dir, "usage_weekly");
      assert.strictEqual(usage.length, 2); // both sessions in 2026-W41
      assert.ok(usage.every((r) => r.isoWeek === "2026-W41" &&
          r.sessionCount === 2 && r.activeDays === 2));
      // T18: W2 DJG rows from both arms, scores kept, same field set.
      const djg = readNdjson(dir, "djg_responses");
      assert.strictEqual(djg.length, 2);
      assert.deepStrictEqual(djg.map((r) => r.groupCode).sort(),
          ["Group_X", "Group_Y"]);
      assert.deepStrictEqual(djg[0].scores,
          {emotional: 2, social: null, total: null});
      assert.deepStrictEqual(Object.keys(djg[0]).sort(),
          Object.keys(djg[1]).sort());
      for (const r of djg) {
        assert.strictEqual(r.startedAtLocal, undefined);
        assert.strictEqual(r.scoredAt, undefined);
      }
      // Brief PR is held back unless asked for (decision 0021).
      assert.strictEqual(readNdjson(dir, "brief_pr").length, 0);
      // No raw uid anywhere in any file.
      for (const f of files) {
        const text = fs.readFileSync(path.join(dir, f), "utf8");
        for (const uid of [UID_A, UID_B, UID_PHASE_A, UID_TESTER]) {
          assert.strictEqual(text.indexOf(uid), -1, `${uid} in ${f}`);
        }
      }
    });

test("research IDs and group codes are stable from week to week",
    async () => {
      await reset();
      await seedCohort();
      const w1 = await exportToDir();
      const w2 = await exportToDir();
      const key = (dir) => readNdjson(dir, "participants")
          .map((p) => `${p.researchId}:${p.groupCode}`).sort().join(",");
      assert.strictEqual(key(w1.dir), key(w2.dir));
      const ridA = (await db.doc(`research_id_map/${UID_A}`).get())
          .get("researchId");
      const mapping = (await db.doc(blinding.STABLE_KEY_DOC).get())
          .get("mapping");
      const rowA = readNdjson(w2.dir, "participants")
          .find((p) => p.researchId === ridA);
      assert.strictEqual(rowA.groupCode, mapping.A);
      // Usage summary is off unless asked for.
      assert.strictEqual(readNdjson(w2.dir, "usage_weekly").length, 0);
    });

test("the checker fails a legacy-style export of the same cohort",
    async () => {
      // Shape of what the old blindedDataExport wrote (T2 report 3.3).
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), "legacy-export-"));
      fs.writeFileSync(path.join(dir, "turns.ndjson"), JSON.stringify({
        participantId: UID_B, llm: {status: "rule_based"},
        uidHash: "0123456789abcdef"}));
      fs.writeFileSync(path.join(dir, "users.ndjson"), JSON.stringify({
        groupCode: "Group_X", armAssignmentMode: "randomise"}));
      const run = spawnSync("node", [CHECKER, dir], {encoding: "utf8"});
      assert.strictEqual(run.status, 1, run.stdout);
    });

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`ok - ${t.name}`);
    } catch (e) {
      failed++;
      console.error(`not ok - ${t.name}\n${e.stack}`);
    }
  }
  await reset();
  if (failed) {
    console.error(`${failed} test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} blinding emulator tests passed`);
  process.exit(0);
})();
