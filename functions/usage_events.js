/**
 * T40 (registry C23) — usage events: the server side.
 *
 * The App appends `users/{uid}/usage_events/{id}` when it comes to the
 * foreground and when it goes to the background (switch
 * app_config/feature_flags.usageEventsEnabled, App side; enrolled accounts
 * only; both arms).  Client fields: type, clientAt (the phone's clock),
 * receivedAt (server timestamp, resolved when the write is committed),
 * appVersion, buildNumber, platform, schemaVersion.
 *
 * `onUsageEventCreated` stamps what the client cannot know or must not
 * hold (firestore.rules: the owner only creates, never reads):
 *   researchId   from research_id_map/{uid} (decision 0021: never in a
 *                document the participant can read — this one it cannot)
 *   dayKey       the Hong Kong calendar day of clientAt (T39 groups by it)
 *   studyDay     study day of clientAt (W0 = 0; null when W0 unknown)
 *   uploadedLate receivedAt − clientAt > LATE_AFTER_MS: the row was cached
 *                offline and uploaded later (dev-tasks-1014d T40 item 3).
 *                clientAt is kept as written.  A phone clock far AHEAD of
 *                the server is flagged as clockSkew instead.
 *   lateByMs     receivedAt − clientAt (may be negative on clock skew)
 *   stampedAt    when the trigger ran
 *
 * Idempotent: a stamped row (stampedAt present) is left alone.  Nothing
 * here reads an outcome, a memory or a conversation.
 *
 * 1020c §1(5): the 小讀本 rows (reader_open / reader_section / reader_cta /
 * reader_close; ids, a CTA code and seconds only — firestore.rules) are
 * stamped the same way, so they carry the research ID and the study day.
 * They are not foreground / background: ops_dashboard.js counts only
 * LIFECYCLE_TYPES for opens and foreground minutes.
 */
"use strict";

const studyWeek = require("./study_week");

const COLLECTION = "usage_events";
const LIFECYCLE_TYPES = ["foreground", "background"];
const READER_TYPES = ["reader_open", "reader_section", "reader_cta",
  "reader_close"];
const TYPES = LIFECYCLE_TYPES.concat(READER_TYPES);

/** A row uploaded this long after its client time counts as late. */
const LATE_AFTER_MS = 5 * 60 * 1000;

/** clientAt this far ahead of receivedAt = the phone clock is wrong. */
const SKEW_AHEAD_MS = 5 * 60 * 1000;

const SERVER_FIELDS = ["researchId", "dayKey", "studyDay", "uploadedLate",
  "lateByMs", "clockSkew", "stampedAt"];

/**
 * The stamp for one row.  Pure.
 * @param {object} data the row as written by the client
 * @param {{user: ?object, researchId: ?string, now: Date}} ctx
 * @return {?object} fields to merge, or null when the row is not ours to
 *     stamp (already stamped, bad type, no client / server time)
 */
function stampFor(data, ctx) {
  if (!data || data.stampedAt !== undefined) return null;
  if (TYPES.indexOf(data.type) < 0) return null;
  const clientAt = studyWeek.toDate(data.clientAt);
  const receivedAt = studyWeek.toDate(data.receivedAt) || ctx.now;
  if (!clientAt || !receivedAt) return null;
  const lateByMs = receivedAt.getTime() - clientAt.getTime();
  const w0Key = studyWeek.w0DateKey(ctx.user);
  return {
    researchId: typeof ctx.researchId === "string" ? ctx.researchId : null,
    dayKey: studyWeek.hkDateKey(clientAt),
    studyDay: w0Key ? studyWeek.studyDayAt(w0Key, clientAt) : null,
    uploadedLate: lateByMs > LATE_AFTER_MS,
    lateByMs: lateByMs,
    clockSkew: lateByMs < -SKEW_AHEAD_MS,
    stampedAt: ctx.now,
  };
}

/**
 * Trigger body: read the user (W0) and the research-ID map, stamp the row.
 * @param {object} db admin.firestore()
 * @param {string} uid
 * @param {string} eventId
 * @param {?object} data row data after the create
 * @param {{now: (Date|undefined)}} opts
 * @return {Promise<?object>} fields written, or null
 */
async function stampCreated(db, uid, eventId, data, opts) {
  const o = opts || {};
  if (!data || data.stampedAt !== undefined) return null;
  const now = o.now || new Date();
  const userSnap = await db.collection("users").doc(uid).get();
  const mapSnap = await db.collection("research_id_map").doc(uid).get();
  const stamp = stampFor(data, {
    user: userSnap.exists ? userSnap.data() : null,
    researchId: mapSnap.exists ? mapSnap.get("researchId") : null,
    now: now,
  });
  if (!stamp) return null;
  await db.collection("users").doc(uid).collection(COLLECTION).doc(eventId)
      .set(stamp, {merge: true});
  return stamp;
}

module.exports = {
  COLLECTION, TYPES, LIFECYCLE_TYPES, READER_TYPES, LATE_AFTER_MS,
  SKEW_AHEAD_MS, SERVER_FIELDS, stampFor, stampCreated,
};
