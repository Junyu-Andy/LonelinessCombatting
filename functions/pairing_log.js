/**
 * T30 (dev-tasks-1010 §四 T30 §5.2; backlog 98) — server-side log of
 * Ah Jan / Ah Bak pairing changes.
 *
 * T37 already logs a change the participant makes in the App as an
 * `events` row (`ah_jan_ah_bak_changed`, client-written).  This trigger
 * body logs the same change from the server, from the profile write
 * itself, so the log does not depend on the App: one row in
 * `pairing_change_log` (server only) with the uid, time, before, after,
 * and the registration value for comparison.  The registration value is
 * `enrollments/{uid}.companionVariant`, which no client can write
 * (firestore.rules) and which the analysis uses — nothing here touches it.
 *
 * Switch: app_config/feature_flags.pairingChangeServerLogEnabled (OFF
 * unless literally true).  Off, the trigger returns without writing.
 */

"use strict";

const featureFlags = require("./feature_flags");

const FLAG = "pairingChangeServerLogEnabled";
const LOG_COLLECTION = "pairing_change_log";
const FIELD = "ahJanAhBakVariant";

/**
 * @param {?object} before users/{uid} data before the write (null = create)
 * @param {?object} after data after the write (null = delete)
 * @return {?{from: ?string, to: ?string}} the change, or null when the
 *     pairing did not change (or the doc was created / deleted)
 */
function pairingChange(before, after) {
  if (!before || !after) return null;
  const from = before[FIELD] == null ? null : String(before[FIELD]);
  const to = after[FIELD] == null ? null : String(after[FIELD]);
  if (from === to) return null;
  return {from, to};
}

/**
 * Trigger body.  Returns the log row written, or null.
 * @param {object} db admin.firestore()
 * @param {{uid: string, before: ?object, after: ?object,
 *     now: (Date|undefined)}} p
 * @return {Promise<?object>}
 */
async function logPairingChange(db, p) {
  const change = pairingChange(p.before, p.after);
  if (!change) return null;
  if (!(await featureFlags.isFeatureEnabled(db, FLAG))) return null;
  const enrol = await db.collection("enrollments").doc(p.uid).get();
  const row = {
    uid: p.uid,
    from: change.from,
    to: change.to,
    at: p.now || new Date(),
    registeredVariant: enrol.exists ?
      enrol.get("companionVariant") || null : null,
    researchId: enrol.exists ? enrol.get("researchId") || null : null,
    source: "profile_write",
  };
  await db.collection(LOG_COLLECTION).add(row);
  return row;
}

module.exports = {FLAG, LOG_COLLECTION, FIELD, pairingChange,
  logPairingChange};
