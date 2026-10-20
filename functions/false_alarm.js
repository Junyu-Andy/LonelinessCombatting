/**
 * 1020e 二.9 — 「誤觸」 (false alarm) mark on a safety alert.
 *
 * The researcher dashboard's safety-alert list (App,
 * safety_alerts_section.dart) offers 「標記誤觸」 on a `pi_alerts` row to
 * the `unblinded` role only, behind the remote switch
 * `app_config/feature_flags.safetyFalseAlarmMarkEnabled` (default off;
 * this function checks it too).  The callable `markSafetyFalseAlarm`:
 *
 *   1. checks the role (same rule as `acknowledgeAlert`) and the switch;
 *   2. stamps `falseAlarm: true`, `markedBy` (researcher uid), `markedAt`
 *      (server time) on the alert's `safety_events` document and on the
 *      `pi_alerts` row (the dashboard reads only the alert);
 *   3. when the event came from that day's chat check-in — a
 *      `users/{uid}/check_in_responses` row with `flow: chat_v2`,
 *      `stopped_by_safety: true`, the same Hong Kong date (`date_iso`) and,
 *      when both carry one, the same session — stamps the same three fields
 *      on that row.  The App then resumes the check-in on the elder's next
 *      visit that day, and the row no longer counts as a crisis-stopped
 *      day (batch 4 reads `falseAlarm` on the row for P2);
 *   4. writes one `alert_audit_log` row (`false_alarm_marked`).
 *
 * The level, the event, the alert and the e-mail are not changed
 * otherwise; nothing is deleted.  Clients can never write these fields
 * (firestore.rules).  No participant text is read or written.
 */
"use strict";

const {isFeatureEnabled} = require("./feature_flags");
const piAlert = require("./pi_alert");

const FLAG = "safetyFalseAlarmMarkEnabled";
const EVENTS = "safety_events";
const CHECK_IN = "check_in_responses";
const SIU_YAN = "siu_yan";

/**
 * Error with a callable code (index.js maps it to HttpsError).
 * @param {string} code
 * @param {string} message
 * @return {Error}
 */
function markError(code, message) {
  const err = new Error(message);
  err.markCode = code;
  return err;
}

/**
 * @param {*} v Timestamp | Date | null
 * @return {?Date}
 */
function toDate(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v.toDate === "function") return v.toDate();
  return null;
}

/**
 * Whether a check-in row is the one this event stopped.  Pure.
 * @param {object} row check_in_responses data
 * @param {object} event safety_events data
 * @param {string} dayKey Hong Kong date of the event, YYYY-MM-DD
 * @return {boolean}
 */
function stoppedCheckInFor(row, event, dayKey) {
  const r = row || {};
  const e = event || {};
  if (r.flow !== "chat_v2" || r.stopped_by_safety !== true) return false;
  if (r.date_iso !== dayKey) return false;
  if (e.agentId && e.agentId !== SIU_YAN) return false;
  if (e.sessionId && r.session_id && r.session_id !== e.sessionId) {
    return false;
  }
  return true;
}

/**
 * Stamp the stopped check-in row(s) of the event's day.
 * @param {object} db Firestore
 * @param {object} event safety_events data
 * @param {object} fields {falseAlarm, markedBy, markedAt}
 * @return {Promise<Array<string>>} paths stamped
 */
async function stampCheckIn(db, event, fields) {
  const uid = event && event.uid;
  const at = toDate(event && event.createdAt);
  if (!uid || !at) return [];
  const dayKey = piAlert.hkDateKey(at);
  const snap = await db.collection("users").doc(uid).collection(CHECK_IN)
      .where("date_iso", "==", dayKey).get();
  const hits = snap.docs.filter((d) =>
    stoppedCheckInFor(d.data(), event, dayKey) &&
    d.get("falseAlarm") !== true);
  if (!hits.length) return [];
  const batch = db.batch();
  for (const d of hits) batch.update(d.ref, fields);
  await batch.commit();
  return hits.map((d) => d.ref.path);
}

/**
 * Callable body: mark one alert's safety event a false alarm.
 * @param {object} db Firestore
 * @param {{alertId: string}} data
 * @param {?object} auth request.auth
 * @param {{serverTimestamp: function(): *}} deps
 * @return {Promise<object>} {ok, alreadyMarked, eventPath, checkInStamped}
 */
async function markFalseAlarm(db, data, auth, deps) {
  if (!auth || !auth.uid) throw markError("unauthenticated", "sign_in");
  const role = auth.token ? auth.token.role : null;
  if (role !== piAlert.UNBLINDED_ROLE) {
    throw markError("permission-denied", "unblinded_role_required");
  }
  if (!(await isFeatureEnabled(db, FLAG))) {
    throw markError("failed-precondition", `feature disabled: ${FLAG}`);
  }
  const alertId = data && typeof data.alertId === "string" ?
    data.alertId.trim() : "";
  if (!alertId || alertId.indexOf("/") >= 0) {
    throw markError("invalid-argument", "alert_id_required");
  }
  const alertRef = db.collection(piAlert.ALERTS).doc(alertId);
  const stamp = deps.serverTimestamp();
  const fields = {falseAlarm: true, markedBy: auth.uid, markedAt: stamp};

  const result = await db.runTransaction(async (tx) => {
    const alertSnap = await tx.get(alertRef);
    if (!alertSnap.exists) throw markError("not-found", "alert_not_found");
    const eventPath = alertSnap.get("eventPath");
    const parts = typeof eventPath === "string" ? eventPath.split("/") : [];
    if (parts.length !== 2 || parts[0] !== EVENTS || !parts[1]) {
      throw markError("not-found", "event_not_found");
    }
    const eventRef = db.collection(EVENTS).doc(parts[1]);
    const eventSnap = await tx.get(eventRef);
    if (!eventSnap.exists) throw markError("not-found", "event_not_found");
    const event = eventSnap.data() || {};
    if (event.falseAlarm === true) {
      return {already: true, event: event, eventPath: eventPath};
    }
    tx.update(eventRef, fields);
    tx.update(alertRef, fields);
    return {already: false, event: event, eventPath: eventPath};
  });

  // A repeat call (e.g. after a failed first stamp) uses the original mark.
  const checkInFields = result.already ? {
    falseAlarm: true,
    markedBy: result.event.markedBy || auth.uid,
    markedAt: result.event.markedAt || stamp,
  } : fields;
  const stamped = await stampCheckIn(db, result.event, checkInFields);
  if (!result.already) {
    await piAlert.audit(db, {type: "false_alarm_marked", alertId: alertId,
      by: auth.uid, eventPath: result.eventPath,
      checkInStamped: stamped.length}, stamp);
  }
  return {
    ok: true,
    alreadyMarked: result.already,
    eventPath: result.eventPath,
    checkInStamped: stamped.length,
  };
}

module.exports = {
  FLAG, markFalseAlarm, stampCheckIn, stoppedCheckInFor,
};
