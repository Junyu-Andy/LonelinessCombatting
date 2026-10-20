/**
 * T30 — server pieces besides the assessor view, against the Firestore
 * emulator (dev-tasks-1010 §四 T30 §7 items 4, 5, 7):
 *   - sequence upload: only `sequence_uploader`; switch off refuses; a
 *     second upload refuses; after an allocation even --replace refuses;
 *     the log has lengths and fingerprints, never arms or a seed;
 *   - process export: research ID + real arm, Brief PR v3 / sessions.
 *     isValid / validSessionCount (T25), safety source; no outcome value,
 *     no text; outcomeExportPaused switch is read;
 *   - pairing change: server log row with before / after; registration
 *     value untouched; switch off writes nothing.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/t30_server_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const R = require("../randomization");
const SU = require("../sequence_upload");
const PE = require("../process_export");
const PL = require("../pairing_log");
const blinding = require("../blinding");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();

const CALVIN = {uid: "calvinUploader00000000000004", email: "calvin@x.test",
  role: "sequence_uploader"};
const JUNYU = {uid: "junyuUnblinded00000000000003", email: "junyu@x.test",
  role: "unblinded"};
const KERAN = {uid: "assessorKeran0000000000000001", role: "blinded"};
const SEED = "calvin-local-seed-000000000001";
const NOW = new Date("2026-10-20T04:00:00Z");

async function reset() {
  for (const c of ["users", "meta", "app_config", "randomization_sequences",
    "randomization_state", "enrollments", "arm_assignment_log",
    "sequence_upload_log", "sequence_versions", "research_id_map",
    "research_ids",
    "safety_events", "pairing_change_log"]) {
    const docs = await db.collection(c).listDocuments();
    for (const d of docs) await db.recursiveDelete(d);
  }
}

const code = async (p) => {
  try {
    await p;
  } catch (e) {
    return e.uploadCode || e.message;
  }
  return "no error";
};

// 10/19 (dev-tasks-1020 §C): uploads name their version (v2) and need
// ≥ 80 positions per stratum.
const payload = (seed, replace, opts) => {
  const o = opts || {};
  const seqs = R.generateSequences(seed || SEED, o.length || 80);
  const sequences = {};
  for (const s of R.STRATA) {
    sequences[s] = {arms: seqs[s].arms, blocks: seqs[s].blocks,
      sha256: seqs[s].sha256};
  }
  return {sequences, replace: !!replace,
    version: "version" in o ? o.version : "v2"};
};

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("sequence upload: switch off refuses; only the uploader role",
    async () => {
      await reset();
      assert.strictEqual(await code(SU.uploadSequence(db, CALVIN, payload(),
          {now: NOW})), "disabled");
      await db.doc(R.CONFIG_DOC).set({enabled: true, sequenceUploadEnabled: true});
      for (const c of [JUNYU, KERAN, {uid: "p", role: null},
        {uid: "old", role: "pi"}]) {
        assert.strictEqual(await code(SU.uploadSequence(db, c, payload(),
            {now: NOW})), "not_uploader", String(c.role));
      }
      assert.strictEqual((await db.collection("sequence_upload_log").get()).size,
          0);
    });

test("sequence upload: validates, writes both strata + state, logs " +
    "without arms or seed; second upload refused", async () => {
  assert.strictEqual(await code(SU.uploadSequence(db, CALVIN,
      {version: "v2", sequences: {low: {arms: ["A", "A"], blocks: [2]}}},
      {now: NOW})),
  "invalid_sequences");
  const r = await SU.uploadSequence(db, CALVIN, payload(), {now: NOW});
  assert.strictEqual(r.replaced, false);
  assert.strictEqual(r.version, "v2");
  const seqs = R.generateSequences(SEED, 80);
  for (const s of R.STRATA) {
    assert.strictEqual(r.uploaded[s].sha256, seqs[s].sha256);
    const doc = (await db.doc(`randomization_sequences/v2_${s}`).get())
        .data();
    assert.deepStrictEqual(doc.arms, seqs[s].arms);
    assert.strictEqual(doc.version, "v2");
    assert.strictEqual(doc.uploadedBy, CALVIN.uid);
    assert.strictEqual(doc.via, "callable");
    assert.strictEqual(doc.seed, undefined);
    assert.strictEqual((await db.doc(`randomization_state/v2_${s}`).get())
        .get("next"), 0);
  }
  const v2 = (await db.doc("sequence_versions/v2").get()).data();
  assert.strictEqual(v2.status, "active");
  assert.strictEqual(v2.strata.low.sha256, seqs.low.sha256);
  const log = await db.collection("sequence_upload_log").get();
  assert.strictEqual(log.size, 1);
  const l = log.docs[0].data();
  assert.strictEqual(l.by, CALVIN.uid);
  assert.strictEqual(l.byEmail, CALVIN.email);
  assert.strictEqual(l.version, "v2");
  assert.strictEqual(l.strata.low.length, seqs.low.length);
  assert.strictEqual(l.strata.high.sha256, seqs.high.sha256);
  const json = JSON.stringify(l);
  assert.ok(!json.includes(SEED), "seed in log");
  assert.ok(!json.includes("arms"), "arms in log");
  assert.ok(!/"[AB]"/.test(json), "arm letters in log");
  assert.strictEqual(await code(SU.uploadSequence(db, CALVIN, payload(),
      {now: NOW})), "already_uploaded");
  // --replace before any allocation is allowed and logged as replaced.
  const r2 = await SU.uploadSequence(db, CALVIN,
      payload("another-local-seed-00000002", true), {now: NOW});
  assert.strictEqual(r2.replaced, true);
});

test("sequence upload: refused once anyone is allocated, even with replace",
    async () => {
      await db.doc("randomization_state/v2_low").set({next: 1});
      assert.strictEqual(await code(SU.uploadSequence(db, CALVIN,
          payload(SEED, true), {now: NOW})), "already_allocated");
      assert.strictEqual(await code(SU.uploadSequence(db, CALVIN,
          payload(SEED, false), {now: NOW})), "already_allocated");
    });

test("10/19 §C: version must be v2; ≥ 80 positions; nothing written " +
    "when refused", async () => {
  await reset();
  await db.doc(R.CONFIG_DOC).set({enabled: true, sequenceUploadEnabled: true});
  for (const v of [undefined, null, "v1", "v3", "V2", ""]) {
    assert.strictEqual(await code(SU.uploadSequence(db, CALVIN,
        payload(SEED, false, {version: v}), {now: NOW})), "version_required",
    String(v));
  }
  assert.strictEqual(await code(SU.uploadSequence(db, CALVIN,
      payload(SEED, false, {length: 60}), {now: NOW})), "too_short");
  assert.strictEqual((await db.collection("randomization_sequences").get())
      .size, 0);
  assert.strictEqual((await db.collection("sequence_versions").get()).size,
      0);
});

test("10/19 §C: v1 archived once (length, used, sha256 only) and left " +
    "untouched; a v2 from v1's seed is refused", async () => {
  await reset();
  await db.doc(R.CONFIG_DOC).set({enabled: true, sequenceUploadEnabled: true});
  // v1 as on the real project: ≥ 60 positions, 4 used in "low".
  const V1_SEED = "v1-synthetic-seed-000001";
  const v1 = R.generateSequences(V1_SEED, 60);
  for (const s of R.STRATA) {
    await db.doc(`randomization_sequences/${s}`).set({stratum: s,
      arms: v1[s].arms, blocks: v1[s].blocks, length: v1[s].length,
      sha256: v1[s].sha256});
  }
  await db.doc("randomization_state/low").set({next: 4});
  await db.doc("randomization_state/high").set({next: 0});
  const before = {};
  for (const s of R.STRATA) {
    before[s] = (await db.doc(`randomization_sequences/${s}`).get())
        .updateTime.toMillis();
  }
  // Same seed, longer: starts with v1 → refused, nothing written.
  assert.strictEqual(await code(SU.uploadSequence(db, CALVIN,
      payload(V1_SEED), {now: NOW})), "same_seed_as_v1");
  assert.strictEqual((await db.doc("sequence_versions/v1").get()).exists,
      false);
  // A new seed goes through and archives v1.
  await SU.uploadSequence(db, CALVIN, payload(SEED), {now: NOW});
  const rec = (await db.doc("sequence_versions/v1").get()).data();
  assert.strictEqual(rec.status, "retired");
  assert.deepStrictEqual(rec.strata.low, {length: v1.low.length, used: 4,
    sha256: v1.low.sha256});
  assert.deepStrictEqual(rec.strata.high, {length: v1.high.length, used: 0,
    sha256: v1.high.sha256});
  assert.ok(!JSON.stringify(rec).includes("arms"), "no arms in the record");
  for (const s of R.STRATA) {
    assert.strictEqual((await db.doc(`randomization_sequences/${s}`).get())
        .updateTime.toMillis(), before[s], `v1 ${s} untouched`);
  }
  assert.strictEqual((await db.doc("randomization_state/low").get())
      .get("next"), 4);
  // A replace before any v2 allocation keeps the first v1 record.
  const retiredAt = rec.retiredAt.toMillis();
  await SU.uploadSequence(db, CALVIN,
      payload("another-local-seed-00000003", true), {now: new Date()});
  assert.strictEqual((await db.doc("sequence_versions/v1").get())
      .get("retiredAt").toMillis(), retiredAt);
});

async function seedProcessParticipants() {
  await reset();
  const mk = async (uid, rid, arm) => {
    await db.doc(`users/${uid}`).set({uid, arm, cohort: "phase_b",
      armAssignmentMode: "randomise", w0Date: "2026-11-01", strataCell: 0,
      displayName: "陳太", email: `${uid}@x.test`});
    await db.doc(`research_id_map/${uid}`).set({researchId: rid});
    await db.doc(`enrollments/${uid}`).set({uid, researchId: rid,
      studyPeriod: "B", arm, w0Date: "2026-11-01"});
    const u = db.doc(`users/${uid}`);
    await u.collection("brief_pr").doc("s1").set({schemaVersion: 3,
      scheduleVersion: 2, uid, sessionId: "s1",
      sessionRef: `users/${uid}/sessions/s1`,
      agentId: "siu_yan", agentDisplayName: "小欣", finalStatus: "completed",
      understanding: 6, validation: 5, caring: 6, insensitivity: 2,
      inviteChannel: "list_page", everShown: true, arm});
    await u.collection("sessions").doc("s1").set({participantId: uid,
      sessionId: "s1", agentId: "siu_yan", moduleId: "check_in",
      startedAt: new Date("2026-11-03T02:00:00Z"),
      endedAt: new Date("2026-11-03T02:10:00Z"), isValid: true,
      scheduleVersion: 2, userMessageCount: 4, replyCount: 4});
    await u.collection("sessions").doc("s2").set({participantId: uid,
      sessionId: "s2", agentId: "tung_tung", moduleId: "free_chat",
      startedAt: new Date("2026-11-04T02:00:00Z"), isValid: false});
    await u.collection("turns").add({text: "我今日好唔開心", sessionId: "s1"});
    await u.collection("weekly_pr").add({weekIso: "2026-W45",
      agentId: "siu_yan", items: {u: 5}, status: "completed"});
    await u.collection("djg_responses").doc("W2").set({timepoint: "W2",
      answers: {q1: "yes"}, scores: {total: 3}, status: "submitted"});
    await u.collection("pgic").add({value: 5});
    await u.collection("daily_mood").add({mood: 2});
    // T49c — two S1a rows for the Hybrid elder, one for the rule elder,
    // plus an unrelated event that must not be counted.
    const s1a = (n) => u.collection("events").add({name: "s1a_fixed_reply",
      arm, params: {agentId: "tung_tung", sessionId: `s${n}`, arm,
        matchedVersion: "2026-10-10-s1a",
        clientTime: "2026-11-04T10:00:00.000"}});
    await s1a(1);
    if (arm === "A") await s1a(2);
    await u.collection("events").add({name: "tung_tung_search_off_reply",
      arm, params: {arm, version: "2026-10-10-s1a"}});
    // 1020e 二.9: the rule-arm event carries a 「誤觸」 mark.
    await db.collection("safety_events").add(Object.assign({uid,
      source: arm === "A" ? "ai_output_scan" : "rule_turn", level: "acute",
      tier: "acute", matchedTerm: "唔想活", textHash: "h",
      crisisPageShown: true, createdAt: new Date("2026-11-05T02:00:00Z")},
    arm === "B" ? {falseAlarm: true, markedBy: "researcherUid1",
      markedAt: new Date("2026-11-05T03:00:00Z")} : {}));
  };
  await mk("hybridUid0000000000000000001", "PB-101", "A");
  await mk("ruleUid000000000000000000002", "PB-102", "B");
  await db.doc("users/testerUid00000000000000003").set({arm: "A",
    isTester: true, cohort: "phase_b"});
  await db.doc("users/pilotUid000000000000000000004").set({arm: "A",
    cohort: "pilot"});
  await db.collection("outcome_entries").add({researchId: "PB-101",
    uid: "hybridUid0000000000000000001", instrument: "DJG-ES",
    scores: {total: 4}, answers: {q1: "yes"}});
}

test("process export: research ID + real arm, T25 fields, sources; no " +
    "outcome values, no text, no uid", async () => {
  await seedProcessParticipants();
  const built = await PE.buildProcessExport(db, {dateKey: "2026-11-09"});
  assert.deepStrictEqual(PE.leakCheck(built), []);
  const f = built.files;
  assert.deepStrictEqual(f.participants.map((p) => [p.researchId, p.arm]),
      [["PB-101", "A"], ["PB-102", "B"]]);
  assert.strictEqual(built.manifest.excludedParticipants.tester, 1);
  assert.strictEqual(built.manifest.excludedParticipants.notPhaseB, 1);
  const bp = f.brief_pr.find((r) => r.researchId === "PB-101");
  assert.strictEqual(bp.schemaVersion, 3);
  assert.strictEqual(bp.finalStatus, "completed");
  assert.strictEqual(bp.arm, "A");
  assert.strictEqual(bp.sessionRef, undefined, "no refs / uid paths");
  assert.strictEqual(bp.agentDisplayName, undefined);
  const uw = f.usage_weekly.find((r) => r.researchId === "PB-102");
  assert.deepStrictEqual(uw, {researchId: "PB-102", arm: "B",
    isoWeek: "2026-W45", weekBasis: "endedAt", sessionCount: 2,
    validSessionCount: 1, activeDays: 2});
  assert.strictEqual(f.sessions.length, 4);
  assert.strictEqual(f.sessions[0].participantId, undefined);
  const se = f.safety_events;
  assert.strictEqual(se.length, 2);
  const hy = se.find((r) => r.researchId === "PB-101");
  assert.strictEqual(hy.source, "ai_output_scan");
  assert.strictEqual(hy.sourceGroup, "ai_reply_scan");
  assert.strictEqual(hy.matchedTerm, undefined);
  assert.strictEqual(hy.textHash, undefined);
  assert.strictEqual(hy.falseAlarm, undefined, "1020e: unmarked event");
  const ru = se.find((r) => r.researchId === "PB-102");
  assert.strictEqual(ru.falseAlarm, true, "1020e: 誤觸 mark exported");
  assert.ok(ru.markedAt, "1020e: markedAt exported");
  assert.strictEqual(ru.markedBy, undefined, "who marked is not exported");
  for (const name of ["outcome_entries", "djg_responses", "pgic", "daily_mood",
    "turns"]) {
    assert.strictEqual(f[name], undefined, `${name} must not be exported`);
  }
  const json = JSON.stringify(f);
  assert.ok(!json.includes("hybridUid0000000000000000001"), "uid leaked");
  assert.ok(!json.includes("我今日好唔開心"), "text leaked");
  assert.ok(!json.includes("x.test"), "email leaked");
  assert.ok(!json.includes("陳太"), "name leaked");
  assert.ok(built.manifest.neverHere.includes("outcome_entries"));
  // T49c — S1a counts per person and per arm; counts only.
  assert.deepStrictEqual(f.event_counts, [
    {researchId: "PB-101", arm: "A", name: "s1a_fixed_reply", count: 2},
    {researchId: "PB-102", arm: "B", name: "s1a_fixed_reply", count: 1},
  ]);
  assert.deepStrictEqual(built.manifest.eventCountsByArm,
      {s1a_fixed_reply: {A: 2, B: 1}});
  assert.ok(!json.includes("2026-10-10-s1a"), "event params leaked");
});

test("switches: processExportEnabled and outcomeExportPaused default off, " +
    "on only when literally true", async () => {
  const off = PE.switchesFromSnap(await db.doc(blinding.CONFIG_DOC).get());
  assert.deepStrictEqual(off, {processExportEnabled: false,
    outcomeExportPaused: false});
  await db.doc(blinding.CONFIG_DOC).set({enabled: true,
    processExportEnabled: "true", outcomeExportPaused: true});
  const on = PE.switchesFromSnap(await db.doc(blinding.CONFIG_DOC).get());
  assert.deepStrictEqual(on, {processExportEnabled: false,
    outcomeExportPaused: true});
});

test("pairing change: switch off → no log; on → one row with before / " +
    "after, registration value untouched", async () => {
  await reset();
  const uid = "elderUid00000000000000000001";
  await db.doc(`enrollments/${uid}`).set({uid, researchId: "PB-201",
    companionVariant: "feminine", studyPeriod: "B"});
  const before = {ahJanAhBakVariant: "feminine", displayName: "陳太"};
  const after = {ahJanAhBakVariant: "masculine", displayName: "陳太"};
  assert.strictEqual(PL.pairingChange(before, before), null);
  assert.strictEqual(PL.pairingChange(null, after), null, "create");
  assert.deepStrictEqual(PL.pairingChange(before, after),
      {from: "feminine", to: "masculine"});
  assert.strictEqual(await PL.logPairingChange(db, {uid, before, after}),
      null, "switch off");
  await db.doc("app_config/feature_flags").set(
      {pairingChangeServerLogEnabled: true});
  const row = await PL.logPairingChange(db, {uid, before, after, now: NOW});
  assert.strictEqual(row.from, "feminine");
  assert.strictEqual(row.to, "masculine");
  assert.strictEqual(row.registeredVariant, "feminine");
  assert.strictEqual(row.researchId, "PB-201");
  const log = await db.collection("pairing_change_log").get();
  assert.strictEqual(log.size, 1);
  assert.strictEqual(log.docs[0].get("uid"), uid);
  assert.strictEqual((await db.doc(`enrollments/${uid}`).get())
      .get("companionVariant"), "feminine", "registration value unchanged");
  // Unrelated profile write: nothing logged.
  assert.strictEqual(await PL.logPairingChange(db, {uid, before: after,
    after: Object.assign({}, after, {displayName: "陳老太"})}), null);
  assert.strictEqual((await db.collection("pairing_change_log").get()).size,
      1);
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
