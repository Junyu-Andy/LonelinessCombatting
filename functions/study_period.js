/**
 * T21 (registry v8 C01; dev-tasks-1010 §3 T21 as corrected by
 * dev-tasks-1010b) — the study period comes from the research-ID prefix,
 * and an account that is not enrolled gets nothing until it is.
 *
 * Phase A is paused (decision 0034).  10/19 (dev-tasks-1020 §C, 1020b §1):
 * PB-01…04 became the run-in and the randomised analysis set registers
 * with RCT- from 10/21, drawing from the second sequence (v2):
 *
 *   RCT-…    Phase B    users/{uid}.cohort = "rct"
 *                       enrollments/{uid}.studyPeriod = "B", sequence v2
 *   PILOT-…  pilot run  users/{uid}.cohort = "pilot"
 *                       enrollments/{uid}.studyPeriod = "PILOT"
 *   PB-…     retired for NEW registrations (code
 *            research_id_prefix_retired); the four PB- accounts keep
 *            cohort "phase_b", studyPeriod "B" and stay in follow-up.
 *
 * "PA-…" and any ID without one of these prefixes is refused at
 * registration (code research_id_prefix).  The whole ID still follows the
 * T19 format (randomization.RESEARCH_ID_PATTERN), and something must come
 * after the prefix.
 *
 * Cohort lists (1020b §1(2)): every server check by cohort reads
 * ENROLLED_COHORTS or PHASE_B_COHORTS below, never a string of its own;
 * the App has lib/core/study/cohorts.dart and firestore.rules
 * enrolledCohort().  functions/test/cohort_list_guard_test.js fails on a
 * direct comparison anywhere else.
 *
 * `cohort` is the field of decision 0011.  It is written by the server at
 * registration only (firestore.rules lists it with the arm fields), so a
 * client cannot enrol itself.
 *
 * Enrolment gate — app_config/feature_flags.enrollmentGateEnabled, OFF
 * unless literally true.  When on, an account with no cohort that is not a
 * tester (`isTester: true`):
 *   - is refused every LLM call, logged in llm_denied_log with reason
 *     "not_enrolled" (functions/index.js assertLlmAllowed);
 *   - cannot write under users/{uid}/ except fcm_tokens (firestore.rules);
 *   - sees only the waiting page S8 in the App (EnrollmentWaitGate);
 *   - gets no week2Push (Phase A's day-14 doorbell; see below).
 * Off, nothing changes.
 */

"use strict";

// `retired`: still resolves (existing PB- accounts: alerts, exports), but
// a NEW registration with it is refused (randomization.enrol).
const PERIODS = [
  {prefix: "RCT-", studyPeriod: "B", cohort: "rct", sequenceVersion: "v2"},
  {prefix: "PB-", studyPeriod: "B", cohort: "phase_b", retired: true},
  {prefix: "PILOT-", studyPeriod: "PILOT", cohort: "pilot"},
];

/** The cohort labels (decision 0011; "rct" since 10/19). */
const COHORT_RUN_IN = "phase_b";
const COHORT_RCT = "rct";
const COHORT_PILOT = "pilot";

/** Cohorts that count as registered: the enrolment gate, the LLM gate,
 * the weekly schedule (the pilot runs the standard one since 10/15). */
const ENROLLED_COHORTS = [COHORT_RUN_IN, COHORT_RCT, COHORT_PILOT];

/** Phase B follow-up: the PB- run-in (still followed up) and the RCT-
 * analysis set — DJG W2 and the blinded / analysis / process exports. */
const PHASE_B_COHORTS = [COHORT_RUN_IN, COHORT_RCT];

/** armAssignmentMode of a pilot account whose arm the researcher chose. */
const PILOT_MODE = "pilot_designated";
const PILOT_METHOD = "pilot_designated_v1";

/**
 * Assignment modes that get the Phase B intervention as allocated: a
 * randomised Phase B participant, or a pilot account set to a version by
 * the researcher.  Memory v1 for Arm A follows this (memory.js inScope).
 */
const PHASE_B_MODES = ["randomise", PILOT_MODE];

const GATE_FLAG = "enrollmentGateEnabled";
const FLAGS_DOC = "app_config/feature_flags";

/**
 * @param {?string} researchId already normalised (upper case, trimmed)
 * @return {?{prefix: string, studyPeriod: string, cohort: string,
 *     sequenceVersion: (string|undefined), retired: (boolean|undefined)}}
 *     the study period (PB- comes back with retired: true), or null when
 *     the prefix is missing or unknown (PA-) or nothing follows it
 */
function periodForResearchId(researchId) {
  if (typeof researchId !== "string") return null;
  for (const p of PERIODS) {
    if (researchId.startsWith(p.prefix) &&
        /^[A-Z0-9][A-Z0-9-]*$/.test(researchId.slice(p.prefix.length))) {
      return p;
    }
  }
  return null;
}

/**
 * @param {?object} user users/{uid} data
 * @return {boolean} registered for Phase B or the pilot run
 */
function isEnrolled(user) {
  return !!user && ENROLLED_COHORTS.indexOf(user.cohort) >= 0;
}

/**
 * @param {?object} user users/{uid} data
 * @return {boolean} a Phase B participant by cohort (run-in or RCT)
 */
function isPhaseBCohort(user) {
  return !!user && PHASE_B_COHORTS.indexOf(user.cohort) >= 0;
}

/**
 * The analysis set a cohort belongs to (exports derive it, 1020b §1(1)).
 * @param {?string} cohort
 * @return {?string} "rct" | "run_in" | "pilot" | null
 */
function analysisSetForCohort(cohort) {
  if (cohort === COHORT_RCT) return "rct";
  if (cohort === COHORT_RUN_IN) return "run_in";
  if (cohort === COHORT_PILOT) return "pilot";
  return null;
}

/**
 * Why this account may not use an LLM, or null when it may.  Arm B is
 * refused whatever the gate says (T19); with the gate on, so is an
 * account that is neither enrolled nor a tester.
 * @param {{gateOn: boolean, user: ?object}} p
 * @return {?string} "rule_arm" | "not_enrolled" | null
 */
function llmRefusal(p) {
  const u = p.user || {};
  if (u.arm === "B") return "rule_arm";
  if (p.gateOn === true && !isEnrolled(u) && u.isTester !== true) {
    return "not_enrolled";
  }
  return null;
}

/**
 * @param {?object} snap app_config/feature_flags snapshot
 * @return {boolean} the gate is on (field literally true)
 */
function gateOnFromSnap(snap) {
  return !!snap && snap.exists === true && snap.get(GATE_FLAG) === true;
}

/**
 * week2Push is Phase A's day-14 doorbell (Phase A is paused, decision
 * 0034).  A pilot-run account follows Phase B — its own compressed
 * schedule comes with T24 / T28 — so it never gets this push; with the
 * gate on, neither does an account that is not registered.
 * @param {{gateOn: boolean, user: ?object}} p
 * @return {boolean} leave this account out of week2Push
 */
function skipsPhaseAWeek2Push(p) {
  const u = p.user || {};
  if (u.cohort === COHORT_PILOT) return true;
  return p.gateOn === true && !isEnrolled(u) && u.isTester !== true;
}

// Read at most once a minute per Functions instance.
let gateCache = null;
const GATE_CACHE_MS = 60 * 1000;

/**
 * Is the enrolment gate on?  A read error counts as off, like every
 * other flag in app_config/feature_flags (functions/feature_flags.js).
 * @param {object} db admin.firestore()
 * @return {Promise<boolean>}
 */
async function enrollmentGateOn(db) {
  if (gateCache && Date.now() - gateCache.at < GATE_CACHE_MS) {
    return gateCache.on;
  }
  let on = false;
  try {
    on = gateOnFromSnap(await db.doc(FLAGS_DOC).get());
  } catch (err) {
    console.warn("enrolment gate read failed; treating as off",
        {err: err && err.message});
  }
  gateCache = {on, at: Date.now()};
  return on;
}

/** Tests: forget the cached gate value. */
function resetGateCache() {
  gateCache = null;
}

module.exports = {
  PERIODS, COHORT_RUN_IN, COHORT_RCT, COHORT_PILOT,
  ENROLLED_COHORTS, PHASE_B_COHORTS, PILOT_MODE, PILOT_METHOD, PHASE_B_MODES,
  GATE_FLAG, FLAGS_DOC, periodForResearchId, isEnrolled, isPhaseBCohort,
  analysisSetForCohort, llmRefusal,
  skipsPhaseAWeek2Push, gateOnFromSnap, enrollmentGateOn, resetGateCache,
};
