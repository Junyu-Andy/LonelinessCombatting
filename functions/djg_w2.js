/**
 * T18 — Week 2 DJG in the App, all 6 items (SPEC:C15, decision 0027).
 * Phase B only, both arms identical, no LLM.
 *
 * Data: users/{uid}/djg_responses/W2.  The App writes the raw answers
 * (q1–q6 → yes / mostly / no / skipped), status in_progress | submitted
 * and the start / submit times.  Only the server writes the scores,
 * outsideWindow, the push / reminder times and the missed mark
 * (firestore.rules).
 *
 * Switch: app_config/phase_b.djgW2InAppEnabled === true (default off).
 * Every djgW2* key in app_config/phase_b belongs to Phase B only.
 *
 * Day counting: W0 (enrolment) date is day 1, as the existing
 * 「入組第 N 天」 (lib/core/scheduling/enrolment_day.dart).  Window =
 * days [dayOffset, dayOffset + windowDays - 1], Hong Kong dates.
 *
 * Scoring (questionnaire package §3):
 *   q1–q3 emotional: yes / mostly = 1, no = 0 → 0–3
 *   q4–q6 social (reversed): no / mostly = 1, yes = 0 → 0–3
 *   total = emotional + social (0–6)
 *   An item skipped or missing → that subscale is null, and so is total.
 */

"use strict";

const CONFIG_DOC = "app_config/phase_b";
const COLLECTION = "djg_responses";
const TIMEPOINT = "W2";
const SCORING_VERSION = "djg6_pkg3_v1";

const DEFAULTS = {
  enabled: false,
  dayOffset: 14,
  windowDays: 7,
  pushHour: 10,
  reminderHours: 24,
};

// A missed mark is only written during the first days after the window
// closes, so switching the flag on mid-trial does not stamp "missed" on
// everyone who enrolled long ago (they never had the in-app version).
const MISSED_LOOKBACK_DAYS = 7;

// The cron runs on the hour; the push stamp lands a few seconds after.
// Without slack the 24 h reminder would slip to the following hour.
const REMINDER_SLACK_MS = 5 * 60 * 1000;

const ITEMS = [
  {id: "q1", subscale: "emotional"},
  {id: "q2", subscale: "emotional"},
  {id: "q3", subscale: "emotional"},
  {id: "q4", subscale: "social"},
  {id: "q5", subscale: "social"},
  {id: "q6", subscale: "social"},
];
const ANSWERS = ["yes", "mostly", "no", "skipped"];

// Draft copy — the research team writes the final text.  While it still
// carries the placeholder mark the dispatcher sends nothing.
const PLACEHOLDER_MARK = "【占位】";
const PUSH_TITLE = "陪住";
const PUSH_BODY = "【占位】第 2 週問卷已經開咗，得閒入嚟答 6 條短問題。";
const REMINDER_BODY = "【占位】第 2 週問卷仲未答，得閒入嚟答埋佢。";

/**
 * Score one set of raw answers.
 * @param {object} answers {q1: "yes" | "mostly" | "no" | "skipped", ...}
 * @return {{emotional: ?number, social: ?number, total: ?number}}
 */
function scoreAnswers(answers) {
  const a = answers || {};
  const sums = {emotional: 0, social: 0};
  const missing = {emotional: false, social: false};
  for (const it of ITEMS) {
    const v = a[it.id];
    if (v !== "yes" && v !== "mostly" && v !== "no") {
      missing[it.subscale] = true;
      continue;
    }
    const point = it.subscale === "emotional" ?
      (v === "no" ? 0 : 1) :
      (v === "yes" ? 0 : 1);
    sums[it.subscale] += point;
  }
  const emotional = missing.emotional ? null : sums.emotional;
  const social = missing.social ? null : sums.social;
  const total = emotional === null || social === null ?
    null : emotional + social;
  return {emotional, social, total};
}

/**
 * @param {object} db admin.firestore()
 * @return {Promise<{enabled: boolean, dayOffset: number,
 *     windowDays: number, pushHour: number, reminderHours: number}>}
 */
async function readConfig(db) {
  try {
    const snap = await db.doc(CONFIG_DOC).get();
    return configFromData(snap.exists ? snap.data() : {});
  } catch (err) {
    console.warn("phase_b config read failed; djg W2 off",
        {err: err && err.message});
    return Object.assign({}, DEFAULTS);
  }
}

/**
 * @param {object} data app_config/phase_b fields
 * @return {object} merged config
 */
function configFromData(data) {
  const d = data || {};
  const num = (v, def, min) =>
    (typeof v === "number" && isFinite(v) && v >= min ? Math.floor(v) : def);
  return {
    enabled: d.djgW2InAppEnabled === true,
    dayOffset: num(d.djgW2DayOffset, DEFAULTS.dayOffset, 1),
    windowDays: num(d.djgW2WindowDays, DEFAULTS.windowDays, 1),
    pushHour: num(d.djgW2PushHour, DEFAULTS.pushHour, 0),
    reminderHours: num(d.djgW2ReminderHours, DEFAULTS.reminderHours, 1),
  };
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
 * Hour of day (0–23) in Hong Kong.
 * @param {Date} d
 * @return {number}
 */
function hkHour(d) {
  return (d.getUTCHours() + 8) % 24;
}

/**
 * Whole days from one YYYY-MM-DD to another.
 * @param {string} fromKey
 * @param {string} toKey
 * @return {number}
 */
function daysBetween(fromKey, toKey) {
  const a = new Date(`${fromKey}T00:00:00Z`);
  const b = new Date(`${toKey}T00:00:00Z`);
  return Math.round((b - a) / 86400000);
}

/**
 * @param {string} key YYYY-MM-DD
 * @param {number} n days to add
 * @return {string}
 */
function addDays(key, n) {
  const d = new Date(`${key}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/**
 * The W0 (enrolment) date, Hong Kong calendar day.  THE single place the
 * server decides W0: the date the researcher entered at registration
 * (users/{uid}.w0Date, T19), else the account's createdAt.
 * @param {object} user users/{uid} data
 * @return {?string} YYYY-MM-DD, or null when unknown
 */
function w0DateKey(user) {
  // T19 (decision 0029): the W0 date entered at registration wins; the
  // account's createdAt is the fallback (lib/core/scheduling/w0_date.dart).
  const registered = user && user.w0Date;
  if (typeof registered === "string" &&
      /^\d{4}-\d{2}-\d{2}$/.test(registered)) {
    return registered;
  }
  const raw = user && user.createdAt;
  if (!raw) return null;
  if (typeof raw === "string") {
    return /^\d{4}-\d{2}-\d{2}/.test(raw) ? raw.slice(0, 10) : null;
  }
  if (typeof raw.toDate === "function") return hkDateKey(raw.toDate());
  if (raw instanceof Date) return hkDateKey(raw);
  return null;
}

/**
 * Where a participant stands relative to the W2 window.
 * @param {string} w0Key YYYY-MM-DD (day 1)
 * @param {string} todayKey YYYY-MM-DD
 * @param {object} cfg readConfig() result
 * @return {{day: number, state: string, startKey: string,
 *     endKey: string}} state: "before" | "open" | "after"
 */
function windowState(w0Key, todayKey, cfg) {
  const day = daysBetween(w0Key, todayKey) + 1;
  const first = cfg.dayOffset;
  const last = cfg.dayOffset + cfg.windowDays - 1;
  const state = day < first ? "before" : (day > last ? "after" : "open");
  return {
    day, state,
    startKey: addDays(w0Key, first - 1),
    endKey: addDays(w0Key, last - 1),
  };
}

/**
 * Phase B participant?  Same test as the blinded export
 * (functions/blinding.js isBlindedParticipant) without the tester part:
 * cohort "phase_b", or — before cohort exists — a randomised arm.
 * T21 replaces this with the participant's study-phase field.
 * @param {object} u users/{uid} data
 * @return {boolean}
 */
function isPhaseBParticipant(u) {
  if (!u || (u.arm !== "A" && u.arm !== "B")) return false;
  if (typeof u.cohort === "string") return u.cohort === "phase_b";
  return u.armAssignmentMode === "randomise";
}

/**
 * week2Push (the Phase A doorbell) leaves these users to djgW2Dispatch,
 * so nobody gets two pushes the same day.
 * @param {object} cfg readConfig() result
 * @param {object} u users/{uid} data
 * @return {boolean}
 */
function week2PushShouldSkip(cfg, u) {
  return cfg.enabled === true && isPhaseBParticipant(u);
}

/**
 * @param {string} text
 * @return {boolean}
 */
function isPlaceholder(text) {
  return typeof text !== "string" || text.length === 0 ||
    text.indexOf(PLACEHOLDER_MARK) >= 0;
}

/**
 * Send one notification to every device of the participant.
 * @param {object} messaging
 * @param {object} userDoc
 * @param {string} body
 * @param {string} kind
 * @return {Promise<{tokens: number, delivered: number}>}
 */
async function sendToDevices(messaging, userDoc, body, kind) {
  const tokensSnap = await userDoc.ref.collection("fcm_tokens").get();
  const tokens = tokensSnap.docs
      .map((t) => (t.data() || {}).token)
      .filter((t) => typeof t === "string" && t.length > 0);
  let delivered = 0;
  for (const token of tokens) {
    try {
      await messaging.send({
        token,
        notification: {title: PUSH_TITLE, body},
        android: {priority: "normal"},
        data: {kind},
      });
      delivered++;
    } catch (err) {
      console.warn(`djgW2 ${kind} send failed for ${userDoc.id}: ` +
        `${err.code || err.message}`);
    }
  }
  return {tokens: tokens.length, delivered};
}

/**
 * Hourly job: W2 push, the 24 h reminder, and the missed mark.  Safe to
 * call with the switch off (returns immediately).
 * @param {object} db admin.firestore()
 * @param {{send: function(object): Promise<string>}} messaging
 * @param {{now: (Date|undefined), log: (function|undefined),
 *     copy: (object|undefined)}} opts copy overrides the draft text
 *     (tests only)
 * @return {Promise<object>} counts per outcome
 */
async function dispatchDjgW2(db, messaging, opts = {}) {
  const now = opts.now || new Date();
  const log = opts.log || console.log;
  const copy = Object.assign({push: PUSH_BODY, reminder: REMINDER_BODY},
      opts.copy || {});
  const cfg = await readConfig(db);
  const counts = {enabled: cfg.enabled};
  const bump = (k) => {
    counts[k] = (counts[k] || 0) + 1;
  };
  if (!cfg.enabled) return counts;

  const todayKey = hkDateKey(now);
  const hour = hkHour(now);
  const users = await db.collection("users").get();
  for (const userDoc of users.docs) {
    const u = userDoc.data() || {};
    if (u.isTester === true || !isPhaseBParticipant(u)) continue;
    const w0 = w0DateKey(u);
    if (!w0) continue;
    const win = windowState(w0, todayKey, cfg);
    if (win.state === "before") continue;
    if (win.state === "after" &&
        win.day > cfg.dayOffset + cfg.windowDays - 1 + MISSED_LOOKBACK_DAYS) {
      continue;
    }
    const ref = userDoc.ref.collection(COLLECTION).doc(TIMEPOINT);
    try {
      const snap = await ref.get();
      const r = snap.exists ? (snap.data() || {}) : {};
      if (r.status === "submitted" || r.status === "missed") continue;
      const windowFields = {
        timepoint: TIMEPOINT, w0Date: w0,
        windowStartDate: win.startKey, windowEndDate: win.endKey,
      };

      if (win.state === "after") {
        await ref.set(Object.assign({}, windowFields,
            {status: "missed", missedAt: now}), {merge: true});
        await userDoc.ref.collection("events").add({
          name: "djg_w2_missed",
          params: {enrolmentDay: win.day},
          source: "cf_djgW2Dispatch",
          timestamp: now,
        });
        bump("missed");
        continue;
      }

      if (!r.pushSentAt) {
        if (hour < cfg.pushHour) continue;
        if (isPlaceholder(copy.push)) {
          bump("blocked_placeholder");
          continue;
        }
        const res = await sendToDevices(messaging, userDoc, copy.push,
            "djg_w2_push");
        await ref.set(Object.assign({}, windowFields,
            snap.exists ? {} : {status: "pending"},
            {pushSentAt: now}), {merge: true});
        await userDoc.ref.collection("events").add({
          name: "djg_w2_push_sent",
          params: {enrolmentDay: win.day, tokens: res.tokens,
            delivered: res.delivered},
          source: "cf_djgW2Dispatch",
          timestamp: now,
        });
        bump("pushed");
        continue;
      }

      if (r.reminderSentAt) continue;
      const pushedAt = typeof r.pushSentAt.toDate === "function" ?
        r.pushSentAt.toDate() : new Date(r.pushSentAt);
      const due = pushedAt.getTime() + cfg.reminderHours * 3600 * 1000 -
        REMINDER_SLACK_MS;
      if (now.getTime() < due) continue;
      if (isPlaceholder(copy.reminder)) {
        bump("blocked_placeholder");
        continue;
      }
      const res = await sendToDevices(messaging, userDoc, copy.reminder,
          "djg_w2_reminder");
      await ref.set({reminderSentAt: now}, {merge: true});
      await userDoc.ref.collection("events").add({
        name: "djg_w2_reminder_sent",
        params: {enrolmentDay: win.day, tokens: res.tokens,
          delivered: res.delivered},
        source: "cf_djgW2Dispatch",
        timestamp: now,
      });
      bump("reminded");
    } catch (err) {
      bump("error");
      log(`djgW2 ${userDoc.id} failed: ${err.message}`);
    }
  }
  log(`dispatchDjgW2: ${JSON.stringify(counts)}`);
  return counts;
}

/**
 * Score a submitted response (Firestore trigger body).  Writes scores,
 * outsideWindow and the window dates once; a doc that already has
 * scoredAt is left alone, so the trigger's own write is a no-op.
 * @param {object} db admin.firestore()
 * @param {string} uid
 * @param {string} timepoint doc id
 * @param {?object} after doc data after the write
 * @param {{now: (Date|undefined)}} opts
 * @return {Promise<?object>} the fields written, or null
 */
async function scoreSubmission(db, uid, timepoint, after, opts = {}) {
  if (!after || after.status !== "submitted" || after.scoredAt) return null;
  if (timepoint !== TIMEPOINT) return null;
  const now = opts.now || new Date();
  const scores = scoreAnswers(after.answers);
  const cfg = await readConfig(db);
  const userSnap = await db.collection("users").doc(uid).get();
  const w0 = userSnap.exists ? w0DateKey(userSnap.data()) : null;
  const submitted = after.submittedAt && typeof after.submittedAt.toDate ===
    "function" ? after.submittedAt.toDate() : now;
  const out = {scores, scoringVersion: SCORING_VERSION, scoredAt: now};
  if (w0) {
    const win = windowState(w0, hkDateKey(submitted), cfg);
    out.outsideWindow = win.state !== "open";
    out.w0Date = w0;
    out.windowStartDate = win.startKey;
    out.windowEndDate = win.endKey;
  } else {
    out.outsideWindow = null;
  }
  await db.collection("users").doc(uid).collection(COLLECTION)
      .doc(timepoint).set(out, {merge: true});
  return out;
}

module.exports = {
  CONFIG_DOC, COLLECTION, TIMEPOINT, SCORING_VERSION, DEFAULTS, ITEMS,
  ANSWERS, MISSED_LOOKBACK_DAYS, PLACEHOLDER_MARK, PUSH_TITLE, PUSH_BODY,
  REMINDER_BODY,
  scoreAnswers, readConfig, configFromData, hkDateKey, hkHour, daysBetween,
  addDays, w0DateKey, windowState, isPhaseBParticipant, week2PushShouldSkip,
  isPlaceholder, dispatchDjgW2, scoreSubmission,
};
