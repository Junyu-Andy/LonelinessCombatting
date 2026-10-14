/**
 * Action Loop (M7) follow-up reminders — server-side delivery
 * (SPEC:C07, decision 0022).
 *
 * The app queues each reminder at users/{uid}/reminders/{id} (both arms,
 * lib/core/reminders/reminder_service.dart) but nothing ever sent them.
 * dispatchDueReminders runs from a scheduled function every 15 minutes,
 * 08:00–21:45 Hong Kong time, and sends each due `m7_followup` reminder
 * as an FCM notification to the participant's own devices (fcm_tokens).
 *
 * Off unless app_config/reminders.m7FollowupPushEnabled === true.
 * No arm check (both arms get the same reminder) and no LLM call.
 *
 * Per reminder:
 *   - fireAt is the app's local ISO string without an offset; it is read
 *     as Hong Kong time.
 *   - Not yet due → left alone.
 *   - Due more than staleHours ago (default 12) → skipped_stale, so
 *     turning the switch on never floods old reminders.  Overnight
 *     reminders go out at 08:00 (≤ ~10 h late), inside the window.
 *   - 今日休息 active today (HK date) → skipped_quiet_today (B.10: the
 *     day's reminders are dropped, not delayed).
 *   - Linked plan deleted → skipped_plan_missing; plan already has an
 *     outcome → skipped_followed_up.
 *   - Otherwise send.  At least one device accepted → sent.  No device
 *     or every send failed → retry on the next run, up to maxAttempts
 *     (default 3), then failed / no_tokens.
 *
 * The doc is claimed (precondition on its update time) before sending, so
 * two overlapping runs can't both send it: at most once per reminder.
 * A run that dies mid-send leaves the doc "sending" and it is not retried
 * (a missed reminder is better than a duplicate).
 *
 * The notification copy is the existing doorbell title and, since T33,
 * the final text S4a (docs/spec/copy/short-texts.md).  The plan text
 * (bodyZh) is NOT sent, so the participant's own words never show on a
 * lock screen.
 */

"use strict";

const KIND = "m7_followup";
const PUSH_TITLE = "陪住";
const PUSH_BODY = "你今日有個小計劃，得閒打開睇下。"; // S4a
const DEFAULTS = {staleHours: 12, maxAttempts: 3};
const TERMINAL = new Set([
  "sending", "sent", "failed", "no_tokens", "skipped_stale",
  "skipped_quiet_today", "skipped_plan_missing", "skipped_followed_up",
]);

/**
 * Parse a reminder's fireAt.  A string without an offset is HK local time.
 * @param {*} raw string | Timestamp | Date
 * @return {?Date}
 */
function parseFireAt(raw) {
  if (!raw) return null;
  if (raw instanceof Date) return raw;
  if (typeof raw.toDate === "function") return raw.toDate();
  if (typeof raw !== "string") return null;
  const hasZone = /(Z|[+-]\d\d:?\d\d)$/.test(raw);
  const d = new Date(hasZone ? raw : `${raw}+08:00`);
  return isNaN(d.getTime()) ? null : d;
}

/**
 * YYYY-MM-DD in Hong Kong.
 * @param {Date} d
 * @return {string}
 */
function hkDateKey(d) {
  return d.toLocaleDateString("en-CA", {timeZone: "Asia/Hong_Kong"});
}

/**
 * True when 今日休息 was activated on the HK date of [now].  The app stores
 * a local ISO string (device time = HK); a Timestamp is converted.
 * @param {*} raw users/{uid}.quietTodayActivatedAt
 * @param {Date} now
 * @return {boolean}
 */
function isQuietToday(raw, now) {
  if (!raw) return false;
  let key = null;
  if (typeof raw === "string") key = raw.slice(0, 10);
  else if (typeof raw.toDate === "function") key = hkDateKey(raw.toDate());
  return key === hkDateKey(now);
}

/**
 * Decide what to do with one queued reminder, before any token lookup.
 * @param {object} r reminder doc data
 * @param {{now: Date, staleHours: number}} opts
 * @return {string} "skip" | "wait" | "due" | "skipped_stale"
 */
function classify(r, {now, staleHours}) {
  if (!r || r.kind !== KIND) return "skip";
  if (r.delivered === true || TERMINAL.has(r.dispatchStatus)) return "skip";
  const fireAt = parseFireAt(r.fireAt);
  if (!fireAt) return "skip";
  if (fireAt.getTime() > now.getTime()) return "wait";
  if (now.getTime() - fireAt.getTime() > staleHours * 3600 * 1000) {
    return "skipped_stale";
  }
  return "due";
}

/**
 * Read the switch and policy from app_config/reminders.
 * @param {object} db
 * @return {Promise<{enabled: boolean, staleHours: number,
 *     maxAttempts: number}>}
 */
async function readConfig(db) {
  const snap = await db.doc("app_config/reminders").get();
  const data = snap.exists ? (snap.data() || {}) : {};
  const num = (v, d) => (typeof v === "number" && v > 0 ? v : d);
  return {
    enabled: data.m7FollowupPushEnabled === true,
    staleHours: num(data.staleHours, DEFAULTS.staleHours),
    maxAttempts: num(data.maxAttempts, DEFAULTS.maxAttempts),
  };
}

/**
 * Send every due M7 follow-up reminder.  Safe to call when the switch is
 * off (returns immediately).
 * @param {object} db admin.firestore()
 * @param {{send: function(object): Promise<string>}} messaging
 *     admin.messaging() or a test fake
 * @param {{now: (Date|undefined), log: (function|undefined)}} opts
 * @return {Promise<object>} counts per outcome
 */
async function dispatchDueReminders(db, messaging, opts = {}) {
  const now = opts.now || new Date();
  const log = opts.log || console.log;
  const cfg = await readConfig(db);
  const counts = {enabled: cfg.enabled};
  const bump = (k) => {
    counts[k] = (counts[k] || 0) + 1;
  };
  if (!cfg.enabled) return counts;

  const users = await db.collection("users").get();
  for (const userDoc of users.docs) {
    const queued = await userDoc.ref.collection("reminders")
        .where("delivered", "==", false).get();
    if (queued.empty) continue;
    const user = userDoc.data() || {};
    for (const rem of queued.docs) {
      try {
        const outcome = await dispatchOne(
            db, messaging, userDoc, user, rem, cfg, now);
        if (outcome) bump(outcome);
      } catch (err) {
        bump("error");
        log(`reminder ${userDoc.id}/${rem.id} failed: ${err.message}`);
      }
    }
  }
  log(`dispatchDueReminders: ${JSON.stringify(counts)}`);
  return counts;
}

/**
 * Handle one queued reminder.
 * @param {object} db
 * @param {object} messaging
 * @param {object} userDoc users/{uid} snapshot
 * @param {object} user its data
 * @param {object} rem reminder snapshot
 * @param {object} cfg readConfig() result
 * @param {Date} now
 * @return {Promise<?string>} outcome, or null when left for later
 */
async function dispatchOne(db, messaging, userDoc, user, rem, cfg, now) {
  const r = rem.data() || {};
  const state = classify(r, {now, staleHours: cfg.staleHours});
  if (state === "skip" || state === "wait") return null;

  let outcome = state === "skipped_stale" ? state : null;
  if (!outcome && isQuietToday(user.quietTodayActivatedAt, now)) {
    outcome = "skipped_quiet_today";
  }
  if (!outcome && r.linkedDocId) {
    const plan = await userDoc.ref.collection("action_plans")
        .doc(String(r.linkedDocId)).get();
    if (!plan.exists) outcome = "skipped_plan_missing";
    else if (plan.get("outcome")) outcome = "skipped_followed_up";
  }

  const attempts = (Number(r.dispatchAttempts) || 0) + (outcome ? 0 : 1);
  // Claim the doc: fails if another run touched it since we read it.
  await rem.ref.update({
    dispatchStatus: outcome || "sending",
    dispatchAttempts: attempts,
    dispatchUpdatedAt: now,
  }, {lastUpdateTime: rem.updateTime});
  if (outcome) return outcome;

  const tokensSnap = await userDoc.ref.collection("fcm_tokens").get();
  const tokens = tokensSnap.docs
      .map((t) => (t.data() || {}).token)
      .filter((t) => typeof t === "string" && t.length > 0);
  let delivered = 0;
  const errors = [];
  for (const token of tokens) {
    try {
      await messaging.send({
        token,
        notification: {title: PUSH_TITLE, body: PUSH_BODY},
        android: {priority: "normal"},
        data: {kind: KIND, reminderId: rem.id},
      });
      delivered++;
    } catch (err) {
      errors.push(String(err.code || err.message));
    }
  }

  if (delivered > 0) {
    await rem.ref.update({
      delivered: true,
      dispatchStatus: "sent",
      dispatchedAt: now,
      dispatchTokens: tokens.length,
      dispatchDelivered: delivered,
    });
    await userDoc.ref.collection("events").add({
      name: "m7_reminder_sent",
      params: {reminderId: rem.id, tokens: tokens.length, delivered},
      source: "cf_dispatchReminders",
      timestamp: now,
    });
    return "sent";
  }
  const giveUp = attempts >= cfg.maxAttempts;
  const status = tokens.length === 0 ?
    (giveUp ? "no_tokens" : "retry_no_tokens") :
    (giveUp ? "failed" : "retry");
  await rem.ref.update({
    dispatchStatus: status,
    lastDispatchError: errors.slice(0, 3).join(",") || null,
  });
  return status;
}

module.exports = {
  KIND, PUSH_TITLE, PUSH_BODY, DEFAULTS,
  parseFireAt, hkDateKey, isQuietToday, classify, readConfig,
  dispatchDueReminders,
};
