/**
 * T21 (registry v8 C01, dev-tasks-1010b) — pure logic: the study period
 * from the research-ID prefix, who counts as enrolled, and when the
 * enrolment gate refuses an LLM call.
 *
 * Run:  cd functions && node test/study_period_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const SP = require("../study_period");
const R = require("../randomization");
const memory = require("../memory");

let passed = 0;
const failures = [];
function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`ok - ${name}`);
  } catch (err) {
    failures.push(name);
    console.log(`FAIL - ${name}\n      ${err.stack}`);
  }
}

const period = (raw) => {
  const p = SP.periodForResearchId(R.normaliseResearchId(raw));
  return p && p.studyPeriod;
};

test("prefix: PB- is Phase B, PILOT- is the pilot run", () => {
  assert.strictEqual(period("PB-001"), "B");
  assert.strictEqual(period(" pb-017 "), "B");
  assert.strictEqual(period("PB-A1-2"), "B");
  assert.strictEqual(period("PILOT-01"), "PILOT");
  assert.strictEqual(period("pilot-12"), "PILOT");
  assert.strictEqual(SP.periodForResearchId("PB-001").cohort, "phase_b");
  assert.strictEqual(SP.periodForResearchId("PILOT-01").cohort, "pilot");
});

test("prefix: PA- (Phase A paused) and anything else refused", () => {
  for (const bad of ["PA-001", "pa-01", "B001", "P001", "PB001", "PILOT01",
    "PB-", "PILOT-", "PB--1", "XPB-001", "PILOTX-01", "", null, undefined,
    7]) {
    assert.strictEqual(period(bad), null, String(bad));
  }
  // The T19 format still applies to the whole ID (12 characters at most).
  assert.strictEqual(period("PILOT-1234567"), null);
  assert.strictEqual(period("PILOT-123456"), "PILOT");
});

test("enrolled: cohort phase_b or pilot, set by the server", () => {
  assert.strictEqual(SP.isEnrolled({cohort: "phase_b"}), true);
  assert.strictEqual(SP.isEnrolled({cohort: "pilot"}), true);
  for (const u of [{}, {cohort: "phase_a"}, {cohort: "B"}, {arm: "A"},
    {isTester: true}, null, undefined]) {
    assert.strictEqual(SP.isEnrolled(u), false, JSON.stringify(u));
  }
});

test("LLM refusal: gate off changes nothing", () => {
  assert.strictEqual(SP.llmRefusal({gateOn: false, user: {}}), null);
  assert.strictEqual(SP.llmRefusal({gateOn: false, user: null}), null);
  assert.strictEqual(SP.llmRefusal({gateOn: false,
    user: {arm: "A", armAssignmentMode: "force_a"}}), null);
  assert.strictEqual(SP.llmRefusal({gateOn: false, user: {arm: "B"}}),
      "rule_arm");
});

test("LLM refusal: gate on refuses only unenrolled non-testers", () => {
  const on = (user) => SP.llmRefusal({gateOn: true, user});
  assert.strictEqual(on(null), "not_enrolled");
  assert.strictEqual(on({}), "not_enrolled");
  assert.strictEqual(on({arm: "A", armAssignmentMode: "force_a"}),
      "not_enrolled");
  assert.strictEqual(on({isTester: "true"}), "not_enrolled");
  assert.strictEqual(on({isTester: true}), null);
  assert.strictEqual(on({cohort: "phase_b", arm: "A"}), null);
  assert.strictEqual(on({cohort: "pilot", arm: "A"}), null);
  // Arm B is refused whatever the gate says, with the T19 reason.
  assert.strictEqual(on({cohort: "phase_b", arm: "B"}), "rule_arm");
  assert.strictEqual(on({cohort: "pilot", arm: "B", isTester: true}),
      "rule_arm");
});

test("week2Push (Phase A doorbell): never pilot; unregistered when gated",
    () => {
      const skip = (gateOn, user) =>
        SP.skipsPhaseAWeek2Push({gateOn, user});
      assert.strictEqual(skip(false, {cohort: "pilot", arm: "A"}), true);
      assert.strictEqual(skip(true, {cohort: "pilot", arm: "B"}), true);
      // Gate off: everyone else as before (decided by djg_w2.js).
      assert.strictEqual(skip(false, {}), false);
      assert.strictEqual(skip(false, {cohort: "phase_b", arm: "A"}), false);
      // Gate on: unregistered non-testers are left out.
      assert.strictEqual(skip(true, {arm: "A"}), true);
      assert.strictEqual(skip(true, {isTester: true}), false);
      assert.strictEqual(skip(true, {cohort: "phase_b", arm: "B"}), false);
    });

test("gate flag: only a literal true turns it on", () => {
  const snap = (v, exists = true) => ({exists, get: () => v});
  assert.strictEqual(SP.gateOnFromSnap(snap(true)), true);
  for (const v of [false, "true", 1, null, undefined]) {
    assert.strictEqual(SP.gateOnFromSnap(snap(v)), false, String(v));
  }
  assert.strictEqual(SP.gateOnFromSnap(snap(true, false)), false);
  assert.strictEqual(SP.gateOnFromSnap(null), false);
});

test("memory v1: pilot Arm A like Phase B Arm A; force_a and Arm B not",
    () => {
      const cfg = {enabled: true, phaseBArmA: true};
      assert.strictEqual(memory.inScope(cfg,
          {arm: "A", armAssignmentMode: "pilot_designated"}), true);
      assert.strictEqual(memory.inScope(cfg,
          {arm: "A", armAssignmentMode: "randomise"}), true);
      assert.strictEqual(memory.inScope(cfg,
          {arm: "A", armAssignmentMode: "force_a"}), false);
      assert.strictEqual(memory.inScope(cfg,
          {arm: "B", armAssignmentMode: "pilot_designated"}), false);
      assert.strictEqual(memory.inScope({enabled: true, phaseBArmA: false},
          {arm: "A", armAssignmentMode: "pilot_designated"}), false);
    });

test("10/19: RCT- is Phase B with sequence v2 and cohort rct; PB- still " +
    "resolves but is retired", () => {
  const rct = SP.periodForResearchId(R.normaliseResearchId(" rct-01 "));
  assert.strictEqual(rct.studyPeriod, "B");
  assert.strictEqual(rct.cohort, "rct");
  assert.strictEqual(rct.sequenceVersion, "v2");
  assert.notStrictEqual(rct.retired, true);
  const pb = SP.periodForResearchId("PB-01");
  assert.strictEqual(pb.retired, true);
  assert.strictEqual(pb.cohort, "phase_b");
  assert.strictEqual(SP.periodForResearchId("RCT-"), null);
});

test("1020b §1: one list per question — enrolled has run-in, rct, pilot; " +
    "Phase B follow-up has run-in and rct", () => {
  assert.deepStrictEqual(SP.ENROLLED_COHORTS, ["phase_b", "rct", "pilot"]);
  assert.deepStrictEqual(SP.PHASE_B_COHORTS, ["phase_b", "rct"]);
  for (const c of ["phase_b", "rct", "pilot"]) {
    assert.strictEqual(SP.isEnrolled({cohort: c}), true, c);
  }
  assert.strictEqual(SP.isEnrolled({cohort: "phase_b_rct"}), false);
  assert.strictEqual(SP.isPhaseBCohort({cohort: "rct"}), true);
  assert.strictEqual(SP.isPhaseBCohort({cohort: "phase_b"}), true);
  assert.strictEqual(SP.isPhaseBCohort({cohort: "pilot"}), false);
  assert.strictEqual(SP.analysisSetForCohort("rct"), "rct");
  assert.strictEqual(SP.analysisSetForCohort("phase_b"), "run_in");
  assert.strictEqual(SP.analysisSetForCohort("pilot"), "pilot");
  assert.strictEqual(SP.analysisSetForCohort(null), null);
  // An RCT- account that is not a tester gets past the gate and the LLM.
  assert.strictEqual(SP.llmRefusal({gateOn: true,
    user: {cohort: "rct", arm: "A"}}), null);
  assert.strictEqual(SP.skipsPhaseAWeek2Push({gateOn: true,
    user: {cohort: "rct"}}), SP.skipsPhaseAWeek2Push({gateOn: true,
    user: {cohort: "phase_b"}}), "rct like the run-in");
});

console.log(`\n${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
