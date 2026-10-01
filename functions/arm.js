/**
 * Server-side RCT arm assignment (arm_assignment_scheme_v1 D2).
 *
 * The client used to pick its own arm inside a Firestore transaction.
 * Now one callable does it with admin rights, so a client can no longer
 * influence its allocation, and the counter and the arm are written in
 * the same transaction.
 *
 * Stratification and balancing are unchanged from the client version
 * (lib/features/auth/data/arm_assigner.dart):
 *   cell = UCLA-LS-V3 total (> 44 = high) × age band (≥ 70 = older)
 *   within a cell: the arm with fewer participants; a tie is a coin flip.
 *
 * Mode: app_config/arm_assignment.randomise === true randomises (Phase B);
 * anything else assigns Arm A to everyone (Phase A pilot). The counter
 * still increments in the participant's cell either way.
 */

"use strict";

const UCLA_MEDIAN_SPLIT = 44;

const AGE_GROUP_YEARS = {
  "60-64": 62,
  "65-69": 67,
  "70-74": 72,
  "75+": 77,
};

/**
 * Strata cell 0–3. Missing inputs fall into the low/younger defaults,
 * exactly like the client helper.
 * @param {{uclaScore: ?number, ageGroup: ?string}} p
 * @return {number}
 */
function strataCell({uclaScore, ageGroup}) {
  const ucla = typeof uclaScore === "number" ? uclaScore : UCLA_MEDIAN_SPLIT;
  const years = AGE_GROUP_YEARS[ageGroup] || 60;
  const high = ucla > UCLA_MEDIAN_SPLIT;
  const older = years >= 70;
  if (!high && !older) return 0;
  if (!high && older) return 1;
  if (high && !older) return 2;
  return 3;
}

/**
 * @param {{aCount: number, bCount: number}} counts this cell's counts
 * @param {{randomise: boolean, rng: function(): number}} opts
 * @return {string} "A" | "B"
 */
function chooseArm({aCount, bCount}, {randomise, rng}) {
  if (!randomise) return "A";
  if (aCount < bCount) return "A";
  if (bCount < aCount) return "B";
  return rng() < 0.5 ? "A" : "B";
}

/**
 * Assign the participant's arm once. Idempotent: a participant who
 * already has an arm gets it back and nothing is counted again, so
 * retries and concurrent calls (signup + login backfill) are safe.
 *
 * @param {object} db admin.firestore()
 * @param {string} uid
 * @param {{rng: (function(): number|undefined)}} opts
 * @return {Promise<{arm: string, cell: number, mode: string,
 *     assigned: boolean}>}
 */
async function assignArm(db, uid, opts = {}) {
  const rng = opts.rng || Math.random;
  const userRef = db.collection("users").doc(uid);
  const counterRef = db.doc("meta/arm_counter");
  const configRef = db.doc("app_config/arm_assignment");

  return db.runTransaction(async (tx) => {
    const [user, counter, config] = await Promise.all([
      tx.get(userRef), tx.get(counterRef), tx.get(configRef),
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

    const cell = strataCell({
      uclaScore: user.get("baselineUclaScore"),
      ageGroup: user.get("ageGroup"),
    });
    const key = `cell_${cell}`;
    const prior = (counter.exists && counter.get(key)) || {};
    const counts = {
      aCount: Number(prior.aCount) || 0,
      bCount: Number(prior.bCount) || 0,
    };
    const randomise = config.exists && config.get("randomise") === true;
    const arm = chooseArm(counts, {randomise, rng});
    const mode = randomise ? "randomise" : "force_a";

    tx.set(counterRef, {
      [key]: {
        aCount: counts.aCount + (arm === "A" ? 1 : 0),
        bCount: counts.bCount + (arm === "B" ? 1 : 0),
      },
      updatedAt: new Date(),
    }, {merge: true});
    tx.set(userRef, {
      arm,
      strataCell: cell,
      armAssignedBy: "server",
      armAssignedAt: new Date(),
      armAssignmentMode: mode,
    }, {merge: true});

    return {arm, cell, mode, assigned: true};
  });
}

module.exports = {UCLA_MEDIAN_SPLIT, strataCell, chooseArm, assignArm};
