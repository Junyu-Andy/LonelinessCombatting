/**
 * T30 — the assessor view against the Firestore emulator
 * (dev-tasks-1010 §四 T30 §7 items 1–3, 5; dev-tasks-1014 §三 T30 2–4):
 *   - switch off: every callable refuses; only `blinded` gets the list;
 *   - the due list: W4 window day 25–31, open / before / after, entered
 *     marked, out-of-window marked; two synthetic assessor accounts get the
 *     same list; no arm / group / Brief PR / usage / chat / sequence key;
 *   - the entry: validation, scores computed server-side and never
 *     returned, stored in outcome_entries, immutable (second entry
 *     refused), out-of-window accepted and flagged, weekly_status
 *     .w4VisitDate for T24;
 *   - PHQ-9 item 9 ≠ 0 → one safety_events row, source assessor_entry;
 *   - correction (tool/correct_outcome_entry.js path) re-scores and logs;
 *   - pooled completion for `unblinded`: hidden under 5, shown at 5+.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/assessor_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const A = require("../assessor");
const R = require("../randomization");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();

const KERAN = {uid: "assessorKeran0000000000000001", email: "keran@x.test",
  role: "blinded"};
const MINGYAN = {uid: "assessorMingyan000000000000002",
  email: "mingyan@x.test", role: "blinded"};
const JUNYU = {uid: "junyuUnblinded00000000000003", email: "junyu@x.test",
  role: "unblinded"};
const CALVIN = {uid: "calvinUploader00000000000004", email: "calvin@x.test",
  role: "sequence_uploader"};
const NOW = new Date("2026-11-27T04:00:00Z"); // HK 2026-11-27

async function reset() {
  for (const c of ["users", "enrollments", "research_ids", "research_id_map",
    "outcome_entries", "outcome_entry_corrections", "weekly_status",
    "safety_events", "safety_event_dedup", "pi_alerts", "app_config",
    "meta"]) {
    const docs = await db.collection(c).listDocuments();
    for (const d of docs) await db.recursiveDelete(d);
  }
}

async function flags(on) {
  await db.doc("app_config/feature_flags").set({assessorViewEnabled: on,
    outcomeCompletionSummaryEnabled: on});
}

// A Phase B participant with the leaky fields planted.
async function participant(uid, rid, w0Date, arm) {
  await db.doc(`users/${uid}`).set({uid, displayName: "陳太", arm,
    cohort: "phase_b", armAssignmentMode: "randomise", w0Date,
    strataCell: 1, ahJanAhBakVariant: "feminine",
    email: `${uid}@x.test`});
  await db.doc(`enrollments/${uid}`).set({uid, researchId: rid,
    studyPeriod: "B", stratum: "high", arm, w0Date, sequencePosition: 3,
    companionVariant: "feminine", enrolledAt: new Date(w0Date)});
  await db.doc(`research_ids/${rid}`).set({uid, via: "enrollment"});
  await db.doc(`research_id_map/${uid}`).set({researchId: rid});
  await db.collection(`users/${uid}/brief_pr`).add({understanding: 7});
  await db.collection(`users/${uid}/sessions`).add({startedAt: new Date()});
  await db.collection(`users/${uid}/turns`).add({text: "我今日好唔開心"});
}

const code = async (p) => {
  try {
    await p;
  } catch (e) {
    return e.assessorCode || e.message;
  }
  return "no error";
};

const answers = (over) => Object.assign({q1: "yes", q2: "mostly", q3: "no",
  q4: "yes", q5: "mostly", q6: "no"}, over || {});

const entry = (rid, over) => Object.assign({researchId: rid,
  instrument: "DJG-ES", timepoint: "W4", assessmentDate: "2026-11-27",
  mode: "in_person", answers: answers(), confirmed: true}, over || {});

const FORBIDDEN = new RegExp("arm|group|brief|weekly|usage|session|turn|" +
  "chat|sequence|strat|safety|uid|email|score", "i");

function assertNoForbiddenKeys(obj, where) {
  if (Array.isArray(obj)) {
    return obj.forEach((o) => assertNoForbiddenKeys(o,
        where));
  }
  if (obj && typeof obj === "object") {
    for (const k of Object.keys(obj)) {
      assert.ok(!FORBIDDEN.test(k), `${where}: key ${k}`);
      assertNoForbiddenKeys(obj[k], `${where}.${k}`);
    }
  }
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("switch off (default): due list, entry and summary all refuse",
    async () => {
      await reset();
      await participant("p1uid000000000000000000000001", "PB-001", "2026-11-01",
          "A");
      assert.strictEqual(await code(A.dueList(db, KERAN, {now: NOW})), "disabled");
      assert.strictEqual(await code(A.submitEntry(db, KERAN, entry("PB-001"),
          {now: NOW})), "disabled");
      assert.strictEqual(await code(A.completionSummary(db, JUNYU, {now: NOW})),
          "disabled");
    });

test("only `blinded` gets the list; unblinded, uploader, participant, " +
    "legacy names refused", async () => {
  await flags(true);
  for (const c of [JUNYU, CALVIN, {uid: "p", role: null},
    {uid: "old", role: "pi"}, {uid: "old2", role: "researcher"}]) {
    assert.strictEqual(await code(A.dueList(db, c, {now: NOW})),
        "not_blinded", String(c.role));
    assert.strictEqual(await code(A.submitEntry(db, c, entry("PB-001"),
        {now: NOW})), "not_blinded", String(c.role));
  }
  assert.strictEqual(await code(A.completionSummary(db, KERAN, {now: NOW})),
      "not_unblinded");
});

test("due list: window day 25–31, states, two assessors see the same, " +
    "no leaky key", async () => {
  await reset();
  await flags(true);
  // W0 2026-11-01 → window 11-26..12-02; today 11-27 = day 26 (open).
  await participant("p1uid000000000000000000000001", "PB-001", "2026-11-01",
      "A");
  // W0 2026-11-10 → day 17 (before).
  await participant("p2uid000000000000000000000002", "PB-002", "2026-11-10",
      "B");
  // W0 2026-10-20 → day 38 (after).
  await participant("p3uid000000000000000000000003", "PB-003", "2026-10-20",
      "B");
  // A pilot account and a tester must not appear.
  await db.doc("users/pilotUid000000000000000000004").set({arm: "A",
    cohort: "pilot", w0Date: "2026-11-01"});
  await db.doc("enrollments/pilotUid000000000000000000004").set({
    researchId: "PILOT-01", studyPeriod: "PILOT", w0Date: "2026-11-01"});
  await db.doc("research_ids/PILOT-01").set({
    uid: "pilotUid000000000000000000004"});
  const l1 = await A.dueList(db, KERAN, {now: NOW});
  const l2 = await A.dueList(db, MINGYAN, {now: NOW});
  assert.deepStrictEqual(l1, l2, "both assessors see the same list");
  assert.strictEqual(l1.today, "2026-11-27");
  assert.deepStrictEqual(l1.rows.map((r) => r.researchId),
      ["PB-001", "PB-002", "PB-003"]);
  const r1 = l1.rows[0];
  assert.deepStrictEqual(r1, {researchId: "PB-001",
    windowStartDate: "2026-11-26", windowEndDate: "2026-12-02", studyDay: 26,
    windowState: "open", entered: {}});
  assert.strictEqual(l1.rows[1].windowState, "before");
  assert.strictEqual(l1.rows[2].windowState, "after");
  assertNoForbiddenKeys(l1, "dueList");
  assert.ok(!JSON.stringify(l1).match(/"[AB]"/), "no arm letter");
});

test("entry: validation codes", async () => {
  const cases = [
    [entry("PB 001"), "invalid_research_id"],
    [entry("PB-001", {instrument: "UCLA-3"}), "unknown_instrument"],
    [entry("PB-001", {timepoint: "W8"}), "invalid_timepoint"],
    [entry("PB-001", {assessmentDate: "2026-12-25"}),
      "invalid_assessment_date"],
    [entry("PB-001", {mode: "letter"}), "invalid_mode"],
    [entry("PB-001", {answers: answers({q1: "maybe"})}), "invalid_answers"],
    [entry("PB-001", {confirmed: false}), "not_confirmed"],
    [entry("PB-999"), "unknown_research_id"],
    [entry("PILOT-01"), "not_phase_b"],
  ];
  for (const [input, expected] of cases) {
    assert.strictEqual(await code(A.submitEntry(db, KERAN, input,
        {now: NOW})), expected, JSON.stringify(input));
  }
  assert.strictEqual((await db.collection("outcome_entries").get()).size, 0);
});

test("entry: stored with server scores, nothing returned but the receipt; " +
    "second entry refused; w4VisitDate for T24", async () => {
  const r = await A.submitEntry(db, KERAN, entry("PB-001",
      {answers: answers({q6: "skipped"})}), {now: NOW});
  assert.deepStrictEqual(r, {recorded: true, researchId: "PB-001",
    instrument: "DJG-ES", timepoint: "W4", outOfWindow: false,
    missingItems: ["q6"]});
  assert.ok(!("scores" in r));
  const snap = await db.collection("outcome_entries")
      .where("researchId", "==", "PB-001").get();
  assert.strictEqual(snap.size, 1);
  const e = snap.docs[0].data();
  assert.strictEqual(e.uid, "p1uid000000000000000000000001");
  assert.strictEqual(e.assessorUid, KERAN.uid);
  assert.strictEqual(e.mode, "in_person");
  assert.strictEqual(e.studyDay, 26);
  assert.strictEqual(e.outOfWindow, false);
  assert.deepStrictEqual(e.scores, {emotional: 2, social: null, total: null});
  assert.strictEqual(e.scoringVersion, "djg6_v1");
  assert.deepStrictEqual(e.missingItems, ["q6"]);
  assert.strictEqual(e.status, "submitted");
  assert.strictEqual(await code(A.submitEntry(db, MINGYAN, entry("PB-001"),
      {now: NOW})), "already_entered");
  assert.strictEqual(await A.w4VisitDateFor(db,
      "p1uid000000000000000000000001"), "2026-11-27");
  const list = await A.dueList(db, MINGYAN, {now: NOW});
  assert.deepStrictEqual(list.rows[0].entered,
      {"DJG-ES": {assessmentDate: "2026-11-27", outOfWindow: false}});
});

test("entry outside the window is accepted and marked outOfWindow",
    async () => {
      // PB-003: W0 10-20, assessed 11-27 = day 38.
      const r = await A.submitEntry(db, MINGYAN, entry("PB-003"), {now: NOW});
      assert.strictEqual(r.outOfWindow, true);
      const list = await A.dueList(db, KERAN, {now: NOW});
      const row = list.rows.find((x) => x.researchId === "PB-003");
      assert.strictEqual(row.entered["DJG-ES"].outOfWindow, true);
      // PB-002 assessed early (day 17) is also accepted and flagged.
      const early = await A.submitEntry(db, KERAN, entry("PB-002"), {now: NOW});
      assert.strictEqual(early.outOfWindow, true);
    });

test("PHQ-9 entry: item 9 = 0 → no safety event; ≠ 0 → one " +
    "assessor_entry event (T34 hook)", async () => {
  const phq = (q9) => {
    const a = {};
    for (let i = 1; i <= 8; i++) a[`q${i}`] = 1;
    a.q9 = q9;
    return a;
  };
  await A.submitEntry(db, KERAN, entry("PB-002", {instrument: "PHQ-9",
    answers: phq(0)}), {now: NOW});
  assert.strictEqual((await db.collection("safety_events").get()).size, 0);
  const r = await A.submitEntry(db, KERAN, entry("PB-003", {instrument: "PHQ-9",
    answers: phq(2)}), {now: NOW});
  assert.strictEqual(r.recorded, true);
  const ev = await db.collection("safety_events").get();
  assert.strictEqual(ev.size, 1);
  const e = ev.docs[0].data();
  assert.strictEqual(e.source, "assessor_entry");
  assert.strictEqual(e.instrument, "PHQ-9");
  assert.strictEqual(e.item, 9);
  assert.strictEqual(e.rawValue, 2);
  assert.strictEqual(e.uid, "p3uid000000000000000000000003");
  assert.strictEqual(e.researchId, "PB-003");
  assert.strictEqual(e.enteredBy, KERAN.uid);
  assert.strictEqual(e.alwaysAlert, true);
  // The PHQ-9 entry itself was stored with its total.
  const stored = await db.collection("outcome_entries")
      .where("instrument", "==", "PHQ-9").get();
  assert.strictEqual(stored.size, 2);
});

test("correction: reason required; re-scores; before/after logged",
    async () => {
      const snap = await db.collection("outcome_entries")
          .where("researchId", "==", "PB-001").get();
      const id = snap.docs[0].id;
      assert.strictEqual(await code(A.correctEntry(db, {entryId: id, item: "q6",
        value: "no", reason: "short", operator: "junyu@x"})), "reason_required");
      assert.strictEqual(await code(A.correctEntry(db, {entryId: id, item: "q9",
        value: "no", reason: "paper form shows 不是", operator: "junyu@x"})),
      "unknown_item");
      const r = await A.correctEntry(db, {entryId: id, item: "q6", value: "no",
        reason: "paper form shows 不是 for item 6", operator: "junyu@x"},
      {now: NOW});
      assert.deepStrictEqual(r.before, {answers: {q6: "skipped"}});
      assert.deepStrictEqual(r.after, {answers: {q6: "no"}});
      const e = (await db.doc(`outcome_entries/${id}`).get()).data();
      assert.deepStrictEqual(e.scores, {emotional: 2, social: 2, total: 4});
      assert.deepStrictEqual(e.missingItems, []);
      assert.ok(e.correctedAt);
      const log = await db.collection("outcome_entry_corrections").get();
      assert.strictEqual(log.size, 1);
      const l = log.docs[0].data();
      assert.strictEqual(l.entryId, id);
      assert.strictEqual(l.by, "junyu@x");
      assert.match(l.reason, /item 6/);
      assert.deepStrictEqual(l.before, {answers: {q6: "skipped"}});
    });

test("pooled completion: hidden under 5 participants, shown at 5+, no arm",
    async () => {
      let s = await A.completionSummary(db, JUNYU, {now: NOW});
      const w4 = s.rows.find((r) => r.instrument === "DJG-ES" &&
        r.timepoint === "W4");
      assert.strictEqual(w4.suppressed, true, "3 due → hidden");
      assert.strictEqual(w4.n, null);
      // Five more Phase B participants past day 25; two entered.
      for (let i = 4; i <= 8; i++) {
        const uid = `p${i}uid00000000000000000000000${i}`;
        await participant(uid, `PB-00${i}`, "2026-10-25", "A");
      }
      await A.submitEntry(db, KERAN, entry("PB-004"), {now: NOW});
      await A.submitEntry(db, KERAN, entry("PB-005"), {now: NOW});
      s = await A.completionSummary(db, JUNYU, {now: NOW});
      const row = s.rows.find((r) => r.instrument === "DJG-ES" &&
        r.timepoint === "W4");
      // Due: PB-001 (day 26), PB-003 (38), PB-004..008 (33) = 7; PB-002 not.
      // Entered among them: PB-001, PB-003, PB-004, PB-005 = 4.
      assert.deepStrictEqual(row, {instrument: "DJG-ES", timepoint: "W4",
        suppressed: false, n: 7, completed: 4, rate: 0.571});
      assert.ok(!JSON.stringify(s).match(/"arm"|groupCode|researchId/));
      const w2 = s.rows.find((r) => r.timepoint === "W2");
      assert.strictEqual(w2.suppressed, false);
      assert.strictEqual(w2.completed, 0);
    });

test("R.normaliseResearchId accepts the W4 entry's ID form", () => {
  assert.strictEqual(R.normaliseResearchId(" pb-001 "), "PB-001");
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
