/**
 * dev-tasks-1020 F(5) — the two daily check-in pushes (1020b §4 5.3 P1,
 * P2).  Both arms identical; no LLM; no arm check.
 *
 * Switch: app_config/feature_flags.checkInChatV2Enabled (F's switch, the
 * same one the App reads for the chat check-in; ON only when literally
 * true).  Off, exactly today's behaviour:
 *   - 08:30 (dailyCheckInMorningPush) does nothing;
 *   - 19:00 (dailyMoodReminder) sends the old topic broadcast
 *     "今日過得點？…" Monday to Saturday and nothing on Sunday.
 * On:
 *   - 08:30 HKT, every day: P1 to every target (below), per device
 *     (users/{uid}/fcm_tokens), never a topic.
 *   - 19:00 HKT, every day: P2 per device, only to a target who has not
 *     completed today's check-in (Hong Kong date, checkInDoneOn) and who
 *     gets no weekly-questionnaire push today
 *     (weekly_schedule.weeklyPushDueToday — the per-person form of the old
 *     "no daily reminder on Sunday, the weekly reminder goes then").
 *   - Quiet hours (functions/quiet_hours.js, fixed on, 22:00–08:00 by
 *     default) skip the push; each slot runs once a day, so a skipped push
 *     is not sent later.
 *   - At most one P1 and one P2 per person per Hong Kong day: every send
 *     writes users/{uid}/events `daily_checkin_push_sent` (slot, dateKey,
 *     copyId, tokens, delivered) and a second run of the same day finds it.
 *
 * Targets: a registered participant (study_period.isEnrolled: the cohort
 * lists — PILOT, the PB- run-in, RCT-).  Testers are left out, except a
 * tester who switched their own arm in 測試員工具 (tester_arm.js), who runs
 * like a pilot participant — the rule weekly_schedule.js uses.  A withdrawn
 * participant is deleted by tool/delete_participant.js (account, user
 * document, tokens), so nothing reaches them; there is no separate
 * "stopped" field in the data, and no end date: like the weekly schedule,
 * the pushes follow the cohort.
 */

"use strict";

const featureFlags = require("./feature_flags");
const quietHours = require("./quiet_hours");
const studyPeriod = require("./study_period");
const studyWeek = require("./study_week");
const testerArm = require("./tester_arm");
const weeklySchedule = require("./weekly_schedule");
const pushCopy = require("./push_copy");

const FLAG = "checkInChatV2Enabled";
const EVENT = "daily_checkin_push_sent";
const SLOT_P1 = "P1";
const SLOT_P2 = "P2";
const CHECK_IN_COLLECTION = "check_in_responses";
const CHAT_V2_FLOW = "chat_v2";
const CHECK_IN_EVENT = "check_in_submitted";

/**
 * @param {?object} user users/{uid} data
 * @return {boolean} gets P1 / P2 (when the switch is on)
 */
function isTarget(user) {
  const u = user || {};
  if (u.isTester === true && !testerArm.isSwitchedTester(u)) return false;
  return studyPeriod.isEnrolled(u);
}

/**
 * Day of the week in Hong Kong, 0 = Sunday.
 * @param {Date} d
 * @return {number}
 */
function hkWeekday(d) {
  return new Date(d.getTime() + 8 * 3600 * 1000).getUTCDay();
}

/**
 * Is one check_in_responses row a check-in completed on `dateKey`?
 *   - old form (CheckInArmB, no `flow` field): the row is written only on
 *     submit, so its date_iso is a completed check-in;
 *   - batch 2 chat (`flow: "chat_v2"`): `completed: true`; a check-in that
 *     an acute safety hit ended (`stopped_by_safety: true`) also counts, so
 *     nobody is nudged back after the crisis flow.
 * `date_iso` is the phone's date (Hong Kong for these participants).
 * @param {?object} row
 * @param {string} dateKey YYYY-MM-DD
 * @return {boolean}
 */
function rowCompletes(row, dateKey) {
  if (!row || row.date_iso !== dateKey) return false;
  if (row.flow === undefined || row.flow === null) return true;
  return row.flow === CHAT_V2_FLOW &&
    (row.completed === true || row.stopped_by_safety === true);
}

/**
 * Has this participant completed a check-in on the Hong Kong day
 * `dateKey`?  Reads the check_in_responses rows of that date first; then
 * the `check_in_submitted` event that every check-in page writes on
 * completion — the only record of the Hybrid arm's old chat check-in
 * (CheckInArmA writes no row) and the signal the App's own "done today"
 * uses (AdherenceCheck).
 * @param {object} userRef users/{uid}
 * @param {string} dateKey YYYY-MM-DD (Hong Kong)
 * @return {Promise<?string>} how it was recognised ("form_v1",
 *     "chat_v2", "event"), or null when not done
 */
async function checkInDoneOn(userRef, dateKey) {
  const rows = await userRef.collection(CHECK_IN_COLLECTION)
      .where("date_iso", "==", dateKey).get();
  for (const doc of rows.docs) {
    const r = doc.data() || {};
    if (rowCompletes(r, dateKey)) {
      return r.flow === CHAT_V2_FLOW ? "chat_v2" : "form_v1";
    }
  }
  const events = await userRef.collection("events")
      .where("name", "==", CHECK_IN_EVENT).get();
  for (const doc of events.docs) {
    const at = studyWeek.toDate((doc.data() || {}).timestamp);
    if (at && studyWeek.hkDateKey(at) === dateKey) return "event";
  }
  return null;
}

/**
 * Was this slot already sent to this participant on `dateKey`?
 * @param {object} userRef
 * @param {string} slot "P1" | "P2"
 * @param {string} dateKey
 * @return {Promise<boolean>}
 */
async function alreadySent(userRef, slot, dateKey) {
  const snap = await userRef.collection("events")
      .where("name", "==", EVENT).get();
  return snap.docs.some((d) => {
    const p = (d.data() || {}).params || {};
    return p.slot === slot && p.dateKey === dateKey;
  });
}

/**
 * @param {object} db
 * @param {{flagOn: (boolean|undefined)}} o
 * @return {Promise<boolean>}
 */
async function flagOn(db, o) {
  if (o.flagOn !== undefined) return o.flagOn === true;
  return featureFlags.isFeatureEnabled(db, FLAG);
}

/**
 * Send one slot to every target the `decide` callback lets through.
 * @param {object} db
 * @param {{send: function(object): Promise<string>}} messaging
 * @param {string} slot "P1" | "P2"
 * @param {object} o opts of the public functions
 * @param {function(object, string): Promise<?string>} decide null = send,
 *     else the count key of the reason to skip
 * @return {Promise<object>} counts
 */
async function sendSlot(db, messaging, slot, o, decide) {
  const now = o.now || new Date();
  const log = o.log || console.log;
  const counts = {enabled: true, slot};
  const bump = (k) => {
    counts[k] = (counts[k] || 0) + 1;
  };
  const quietCfg = o.quiet || await quietHours.readQuietHoursConfig(db);
  const dateKey = studyWeek.hkDateKey(now);
  const body = o.copy && typeof o.copy[slot] === "string" ?
    o.copy[slot] : pushCopy.TEXT[slot];
  const kind = slot === SLOT_P1 ? "daily_checkin_p1" : "daily_checkin_p2";
  const users = await db.collection("users").get();
  for (const userDoc of users.docs) {
    const u = userDoc.data() || {};
    if (!isTarget(u)) continue;
    try {
      if (quietHours.inQuietHours(u, now, quietCfg)) {
        bump("quiet_hours");
        continue;
      }
      if (await alreadySent(userDoc.ref, slot, dateKey)) {
        bump("already_sent");
        continue;
      }
      const skip = await decide(userDoc, dateKey);
      if (skip) {
        bump(skip);
        continue;
      }
      if (weeklySchedule.isPlaceholder(body)) {
        bump("blocked_placeholder");
        continue;
      }
      const res = await weeklySchedule.sendToDevices(messaging, userDoc, body,
          kind);
      await userDoc.ref.collection("events").add({
        name: EVENT,
        params: {slot, dateKey, copyId: slot,
          copyVersion: pushCopy.COPY_VERSION, tokens: res.tokens,
          delivered: res.delivered},
        source: slot === SLOT_P1 ? "cf_dailyCheckInMorningPush" :
          "cf_dailyMoodReminder",
        timestamp: now,
      });
      bump(res.tokens > 0 ? "pushed" : "no_tokens");
    } catch (err) {
      bump("error");
      log(`daily ${slot} ${userDoc.id} failed: ${err.message}`);
    }
  }
  log(`daily check-in push ${slot}: ${JSON.stringify(counts)}`);
  return counts;
}

/**
 * 08:30 job: P1 to every target.  Switch off: nothing.
 * @param {object} db admin.firestore()
 * @param {{send: function(object): Promise<string>}} messaging
 * @param {{now: (Date|undefined), log: (function|undefined),
 *     quiet: (object|undefined), copy: (object|undefined),
 *     flagOn: (boolean|undefined)}} opts now / quiet / copy / flagOn
 *     override the clock, the quiet-hours config, the text and the switch
 *     (tests only)
 * @return {Promise<object>} counts
 */
async function sendMorningPush(db, messaging, opts) {
  const o = opts || {};
  if (!(await flagOn(db, o))) return {enabled: false};
  return sendSlot(db, messaging, SLOT_P1, o, async () => null);
}

/**
 * 19:00 job.  Switch off: today's behaviour — `legacyDoorbell()` (the
 * topic broadcast, index.js sendDoorbell) Monday to Saturday, nothing on
 * Sunday.  On: P2 to every target who has not completed today's check-in
 * and has no weekly-questionnaire push today.
 * @param {object} db admin.firestore()
 * @param {{send: function(object): Promise<string>}} messaging
 * @param {{now: (Date|undefined), log: (function|undefined),
 *     quiet: (object|undefined), copy: (object|undefined),
 *     flagOn: (boolean|undefined), reminderV2: (boolean|undefined),
 *     legacyDoorbell: function(): Promise<void>}} opts
 * @return {Promise<object>} counts
 */
async function runEveningPush(db, messaging, opts) {
  const o = opts || {};
  const now = o.now || new Date();
  if (!(await flagOn(db, o))) {
    if (hkWeekday(now) === 0) return {enabled: false, legacy: "sunday_none"};
    if (o.legacyDoorbell) await o.legacyDoorbell();
    return {enabled: false, legacy: "broadcast"};
  }
  const cfg = await weeklySchedule.readConfig(db);
  const reminderV2 = o.reminderV2 !== undefined ? o.reminderV2 === true :
    await weeklySchedule.reminderV2On(db);
  return sendSlot(db, messaging, SLOT_P2, Object.assign({}, o, {now}),
      async (userDoc, dateKey) => {
        const done = await checkInDoneOn(userDoc.ref, dateKey);
        if (done) return `done_${done}`;
        if (await weeklySchedule.weeklyPushDueToday(db, userDoc, now,
            {cfg, reminderV2})) {
          return "weekly_push_day";
        }
        return null;
      });
}

module.exports = {
  FLAG, EVENT, SLOT_P1, SLOT_P2, CHAT_V2_FLOW, isTarget, hkWeekday,
  rowCompletes, checkInDoneOn, alreadySent, sendMorningPush, runEveningPush,
};
