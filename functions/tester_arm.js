/**
 * Tester self-switch between the Hybrid arm (A) and the rule arm (B)
 * (decision record draft "测试员自切组别", number to be assigned).
 *
 * Only an account whose users/{uid}.isTester is true (admin-only field,
 * tool/set_tester.js) may call it, and only with the switch
 * app_config/feature_flags.testerArmSwitchEnabled on (default off).
 * Participants are never touched: their arm still comes only from
 * enrollParticipant / tool/correct_arm_assignment.js.
 *
 * What a switch writes (Admin SDK — firestore.rules keep the client from
 * writing any of these):
 *   users/{uid}       arm; armAssignedBy "tester_switch"; armAssignedAt;
 *                     and, only when missing, cohort "pilot",
 *                     armAssignmentMode "pilot_designated",
 *                     armAssignmentMethod "pilot_designated_v1",
 *                     w0Date = today (Hong Kong).  With those the weekly
 *                     schedule and memory v1 treat the tester like a
 *                     pilot-run participant.  strataCell is never touched.
 *   enrollments/{uid} arm, only if that document already exists.
 *   arm_assignment_log one row: action "tester_switch", uid, from, to,
 *                     at, by (the tester themself).  No research ID, no
 *                     stratum, no sequence position.
 *
 * Research data still leaves testers out: by `isTester` in blinding.js,
 * process_export.js and tool/analysis_export.js; and because no
 * enrollments row or research ID is ever written here, the assessor list,
 * outcome completion summary and ops dashboard (which list enrollments
 * only) never see the tester.  A switched tester gets the weekly bundle
 * pushes (weekly_schedule.js, isSwitchedTester) and stays a tester for
 * tool/purge_tester_data.js.  Memory items are never deleted: switching
 * to B only stops memory from being used (memory.js inScope); switching
 * back finds it.
 */
"use strict";

const studyPeriod = require("./study_period");
const randomization = require("./randomization");

const FLAG = "testerArmSwitchEnabled";
const FLAGS_DOC = "app_config/feature_flags";
const ACTION = "tester_switch";
const ASSIGNED_BY = "tester_switch";
const ARMS = ["A", "B"];

/**
 * @param {string} code machine-readable reason
 * @return {Error} error carrying `testerArmCode`
 */
function testerArmError(code) {
  const err = new Error(code);
  err.testerArmCode = code;
  return err;
}

/**
 * The switch is on only when the field is literally true; a read error
 * counts as off.
 * @param {object} db admin.firestore()
 * @return {Promise<boolean>}
 */
async function switchEnabled(db) {
  try {
    const snap = await db.doc(FLAGS_DOC).get();
    return snap.exists && snap.get(FLAG) === true;
  } catch (err) {
    console.warn("tester arm switch flag read failed; treating as off",
        {err: err && err.message});
    return false;
  }
}

/**
 * The users/{uid} fields a switch to `arm` writes, given the current data.
 * Pure (tests).
 * @param {object} u current users/{uid} data
 * @param {string} arm "A" | "B"
 * @param {Date} now
 * @return {object} fields to merge
 */
function userPatch(u, arm, now) {
  const patch = {arm, armAssignedBy: ASSIGNED_BY, armAssignedAt: now};
  if (!u.cohort) patch.cohort = studyPeriod.COHORT_PILOT;
  if (studyPeriod.PHASE_B_MODES.indexOf(u.armAssignmentMode) < 0) {
    patch.armAssignmentMode = studyPeriod.PILOT_MODE;
    patch.armAssignmentMethod = studyPeriod.PILOT_METHOD;
  }
  if (!u.w0Date) patch.w0Date = randomization.hkDateKey(now);
  return patch;
}

/**
 * Switch the calling tester's own arm.
 * @param {object} db admin.firestore()
 * @param {string} uid the caller (from request.auth)
 * @param {*} arm requested arm
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{arm: string, from: ?string, changed: boolean}>}
 */
async function switchArm(db, uid, arm, opts) {
  const now = (opts && opts.now) || new Date();
  if (!uid) throw testerArmError("not_tester");
  const userRef = db.collection("users").doc(uid);
  // Tester check first, so a participant learns nothing else and nothing
  // is written for them.
  const first = await userRef.get();
  if (!first.exists || first.get("isTester") !== true) {
    throw testerArmError("not_tester");
  }
  if (!(await switchEnabled(db))) throw testerArmError("disabled");
  if (ARMS.indexOf(arm) < 0) throw testerArmError("invalid_arm");

  const enrolRef = db.collection(randomization.ENROLL_COLLECTION).doc(uid);
  const logRef = db.collection(randomization.LOG_COLLECTION).doc();
  return db.runTransaction(async (tx) => {
    const [user, enrol] = await Promise.all([tx.get(userRef),
      tx.get(enrolRef)]);
    const u = user.exists ? (user.data() || {}) : {};
    if (u.isTester !== true) throw testerArmError("not_tester");
    const from = u.arm === "A" || u.arm === "B" ? u.arm : null;
    tx.set(userRef, userPatch(u, arm, now), {merge: true});
    if (enrol.exists) tx.update(enrolRef, {arm});
    tx.create(logRef, {action: ACTION, uid, from, to: arm, at: now,
      by: uid});
    return {arm, from, changed: from !== arm};
  });
}

/**
 * Did this tester's arm come from the self-switch?  Such a tester runs
 * the weekly schedule like a pilot participant (weekly_schedule.js).
 * @param {?object} u users/{uid} data
 * @return {boolean}
 */
function isSwitchedTester(u) {
  return !!u && u.isTester === true && u.armAssignedBy === ASSIGNED_BY;
}

module.exports = {
  FLAG, FLAGS_DOC, ACTION, ASSIGNED_BY, testerArmError, switchEnabled,
  userPatch, switchArm, isSwitchedTester,
};
