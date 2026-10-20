/**
 * 1020b §1(5) — the cohort "rct" end to end against the Firestore
 * emulator.  A synthetic RCT- account that is NOT a tester (testers get
 * past the enrolment gate, so a missed cohort check would not show) is
 * registered through the real path (v2 sequence) and walked through the
 * schedule next to a synthetic PB- run-in account seeded as on the real
 * project:
 *   - past the enrolment gate; the LLM is not refused;
 *   - the weekly questionnaire opens on study days 7, 14, 21 and 26 for
 *     both (one push each, per person);
 *   - W2 carries the DJG part, the W2 DJG record is stamped and scored;
 *   - day 56 is study week 8 for both (the W8 bundle itself, T35, is not
 *     built yet — the ops dashboard reports it "not_built");
 *   - blinded, process and analysis exports include both: the process
 *     export carries cohort "rct" / "phase_b", the analysis export
 *     analysisSet "rct" / "run_in"; the blinded export has no cohort
 *     column (tool/check_blinded_export.js denies it) — the research ID
 *     prefix (RCT- / PB-) tells them apart.
 * Writing research data with the gate on is covered in test/rules
 * (firestore.rules enrolledCohort()).
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/rct_cohort_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const R = require("../randomization");
const SP = require("../study_period");
const ws = require("../weekly_schedule");
const sw = require("../study_week");
const djg = require("../djg_w2");
const qh = require("../quiet_hours");
const blinding = require("../blinding");
const processExport = require("../process_export");
const seqTool = require("../../tool/randomization_sequence");
const analysisExport = require("../../tool/analysis_export");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const silent = () => {};

// W0 = 2026-10-21 (the first RCT- day) = study day 0.
const W0 = "2026-10-21";
function hk(day, hour, minute) {
  const key = sw.addDays(W0, day);
  const hh = String(hour).padStart(2, "0");
  const mm = String(minute || 0).padStart(2, "0");
  return new Date(`${key}T${hh}:${mm}:00+08:00`);
}
const K1 = {uid: "keran", email: "k1@example.org", role: "unblinded"};
const FINAL_COPY = {push: "（測試）每週問卷", reminder: "（測試）提醒"};
const RCT = "rctUid00000000000000000000001";
const PB = "pbUid000000000000000000000002";

async function reset() {
  for (const c of ["users", "meta", "app_config", "randomization_sequences",
    "randomization_state", "sequence_versions", "enrollments",
    "arm_assignment_log", "research_id_map", "research_ids", "weekly_status",
    "export_blind_keys", "analysis_export_log"]) {
    await db.recursiveDelete(db.collection(c));
  }
}

async function setup() {
  await reset();
  await db.doc(SP.FLAGS_DOC).set({enrollmentGateEnabled: true});
  await db.doc(R.CONFIG_DOC).set({enabled: true});
  await db.doc(ws.CONFIG_DOC).set({weeklyScheduleV2Enabled: true,
    djgW2InAppEnabled: true});
  const up = await seqTool.upload(db,
      R.generateSequences("rct-cohort-test-seed-0001", 80),
      {operator: "uploader@example.org", version: "v2"});
  assert.ok(up.ok, up.lines.join("\n"));

  // RCT-01 through the real registration (cohort written by the server).
  await db.doc(`users/${RCT}`).set({displayName: "Synthetic RCT",
    createdAt: "2026-10-20T10:00:00", isTester: false});
  await R.enrol(db, K1, {uid: RCT, researchId: "RCT-01", w0DjgEmotional: 2,
    w0Date: W0, confirmed: true}, {now: hk(0, 10)});
  // PB-01 as on the real project (registered before 10/19, cohort phase_b).
  await db.doc(`users/${PB}`).set({displayName: "Synthetic PB",
    createdAt: "2026-10-18T10:00:00", isTester: false, arm: "B",
    cohort: "phase_b", armAssignmentMode: "randomise", w0Date: W0,
    strataCell: 0});
  await db.doc(`enrollments/${PB}`).set({uid: PB, researchId: "PB-01",
    studyPeriod: "B", stratum: "low", arm: "B", sequencePosition: 1,
    w0Date: W0, enrolledAt: hk(0, 9)});
  await db.doc(`research_id_map/${PB}`).set({researchId: "PB-01"});
  for (const uid of [RCT, PB]) {
    await db.doc(`users/${uid}/fcm_tokens/dev1`).set({token: `tok-${uid}`});
  }
}

const user = async (uid) => (await db.doc(`users/${uid}`).get()).data();

function fakeMessaging() {
  const sent = [];
  return {sent, send: async (msg) => {
    sent.push(msg);
    return `id-${sent.length}`;
  }};
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("RCT-01 registers with cohort rct, not a tester", async () => {
  await setup();
  const u = await user(RCT);
  assert.strictEqual(u.cohort, "rct");
  assert.notStrictEqual(u.isTester, true);
  assert.strictEqual(u.w0Date, W0);
  assert.strictEqual((await db.doc(`enrollments/${RCT}`).get())
      .get("sequenceVersion"), "v2");
});

test("enrolment gate on: both get past it; the LLM is not refused",
    async () => {
      SP.resetGateCache();
      assert.strictEqual(await SP.enrollmentGateOn(db), true);
      for (const uid of [RCT, PB]) {
        const u = await user(uid);
        assert.strictEqual(SP.isEnrolled(u), true, uid);
        assert.strictEqual(SP.llmRefusal({gateOn: true,
          user: Object.assign({}, u, {arm: "A"})}), null, uid);
      }
    });

test("weekly questionnaire opens on study days 7, 14, 21 and 26 for both",
    async () => {
      const m = fakeMessaging();
      const run = (now) => ws.dispatchWeeklyBundles(db, m,
          {now, log: silent, copy: FINAL_COPY,
            quiet: qh.quietHoursConfigFrom({})});
      // Not before day 7.
      await run(hk(6, 20));
      assert.strictEqual(m.sent.length, 0);
      const days = {7: "W1", 14: "W2", 21: "W3", 26: "W4"};
      for (const day of Object.keys(days)) {
        const before = m.sent.length;
        const c = await run(hk(Number(day), 20));
        assert.strictEqual(c.pushed, 2, `day ${day}`);
        assert.deepStrictEqual(m.sent.slice(before).map((x) => x.token).sort(),
            [`tok-${PB}`, `tok-${RCT}`].sort(), `day ${day}`);
        for (const uid of [RCT, PB]) {
          const st = (await db.doc(`weekly_status/${uid}`).get()).data();
          assert.ok(st.bundles[days[day]].pushedAt, `${uid} ${days[day]}`);
        }
      }
      const rid = (await db.doc(`weekly_status/${RCT}`).get())
          .get("researchId");
      assert.strictEqual(rid, "RCT-01");
    });

test("W2 has the DJG part; the RCT W2 DJG record is stamped and scored",
    async () => {
      const cfg = await ws.readConfig(db);
      const mode = ws.scheduleModeFor(await user(RCT));
      assert.strictEqual(mode, ws.scheduleModeFor(await user(PB)));
      assert.ok(ws.bundleById(cfg, mode, "W2").parts.indexOf("djg") >= 0);
      assert.strictEqual(djg.isPhaseBParticipant(await user(RCT)), true);
      assert.strictEqual(djg.isPhaseBParticipant(await user(PB)), true);
      const answers = {q1: "yes", q2: "no", q3: "no", q4: "yes", q5: "yes",
        q6: "yes"};
      const after = {bundle: "W2", status: "submitted", answers,
        submittedAt: admin.firestore.Timestamp.fromDate(hk(14, 21))};
      await db.doc(`users/${RCT}/djg_responses/W2`).set(after);
      const stamp = await ws.stampPartRecord(db, RCT, "djg_responses", "W2",
          after);
      assert.ok(stamp, "stamped");
      assert.strictEqual(stamp.studyWeek, 2);
      const scored = await djg.scoreSubmission(db, RCT, "W2", after);
      assert.ok(scored, "scored");
    });

test("day 56 is study week 8 for both (W8 bundle not built yet, T35)",
    async () => {
      for (const uid of [RCT, PB]) {
        const w0 = sw.w0DateKey(await user(uid));
        assert.strictEqual(sw.studyDayAt(w0, hk(56, 9)), 56);
        assert.strictEqual(sw.studyWeekAt(w0, hk(56, 9)), 8);
      }
    });

test("blinded, process and analysis exports include both; labels",
    async () => {
      const blind = await blinding.buildBlindedExport(db,
          {dateKey: "2026-12-20", includeUsageSummary: false,
            includeBriefPr: false});
      const rids = blind.files.participants.map((p) => p.researchId).sort();
      assert.deepStrictEqual(rids, ["PB-01", "RCT-01"]);
      assert.ok(blind.files.participants.every((p) => p.cohort === undefined),
          "no cohort column in the blinded export");

      const proc = await processExport.buildProcessExport(db,
          {dateKey: "2026-12-20"});
      const cohorts = {};
      for (const p of proc.files.participants) cohorts[p.researchId] = p.cohort;
      assert.deepStrictEqual(cohorts, {"RCT-01": "rct", "PB-01": "phase_b"});

      await db.doc("meta/data_lock").set({lockedAt: new Date(),
        lockedBy: "junyu@x"});
      const real = await analysisExport.collectReal(db, {operator: "junyu@x"});
      const sets = {};
      for (const p of real.files.participants) {
        sets[p.researchId] = [p.analysisSet, p.runIn, p.sequenceVersion];
      }
      assert.deepStrictEqual(sets, {"RCT-01": ["rct", false, "v2"],
        "PB-01": ["run_in", true, "v1"]});
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
