/**
 * assignArm — what the App calls right after signup (and on login while
 * the profile has no arm).
 *
 * T19 (decision 0029): Phase B allocation moved to researcher enrolment
 * (functions/randomization.js — permuted blocks, strata from the W0 paper
 * DJG).  The old minimisation (UCLA × age group, counter in
 * meta/arm_counter) is deleted, so only one allocation path exists:
 *
 *   meta/randomization_config.enabled === true  → never assigns here.
 *       The participant waits for the researcher's registration; until
 *       then arm is null and the App shows the rule-arm UI (decision 0004).
 *   otherwise, app_config/arm_assignment.randomise === true → refuses
 *       (returns arm null).  That flag used to mean "minimise"; assigning
 *       Arm A here instead would silently put a Phase B participant in
 *       Arm A for good.
 *   otherwise → Arm A for everyone (Phase A / pilot, mode "force_a").
 *
 * Idempotent: a stored arm is returned unchanged.
 */

"use strict";

const randomization = require("./randomization");

/**
 * @param {object} db admin.firestore()
 * @param {string} uid
 * @return {Promise<{arm: ?string, cell: ?number, mode: ?string,
 *     assigned: boolean}>}
 */
async function assignArm(db, uid) {
  const userRef = db.collection("users").doc(uid);
  const legacyRef = db.doc("app_config/arm_assignment");
  const randRef = db.doc(randomization.CONFIG_DOC);

  return db.runTransaction(async (tx) => {
    const [user, legacy, rand] = await Promise.all([
      tx.get(userRef), tx.get(legacyRef), tx.get(randRef),
    ]);
    if (!user.exists) {
      throw new Error("profile_missing");
    }
    const existing = user.get("arm");
    if (existing === "A" || existing === "B") {
      const cell = user.get("strataCell");
      return {
        arm: existing,
        cell: typeof cell === "number" ? cell : null,
        mode: user.get("armAssignmentMode") || null,
        assigned: false,
      };
    }
    if (randomization.configFromSnap(rand).enabled) {
      return {arm: null, cell: null, mode: "enrollment", assigned: false};
    }
    if (legacy.exists && legacy.get("randomise") === true) {
      return {arm: null, cell: null, mode: "randomise_retired",
        assigned: false};
    }
    tx.set(userRef, {
      arm: "A",
      armAssignedBy: "server",
      armAssignedAt: new Date(),
      armAssignmentMode: "force_a",
    }, {merge: true});
    return {arm: "A", cell: null, mode: "force_a", assigned: true};
  });
}

module.exports = {assignArm};
