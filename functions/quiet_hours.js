/**
 * 10/14 (lead's decision) — the elder's 「安靜時段」 toggle is real.
 * 10/20 (dev-tasks-1020 §H(2)) — quiet hours are fixed on for everyone; the
 * switch is gone from the App and users/{uid}.quietHoursEnabled (which the
 * App used to mirror the toggle onto) is ignored.
 * 1020o 第三节 (decision 0066) — the elder sets the window in 自己 → 我的設定
 * → 安靜時段 (「由」 / 「到」, half-hour steps, no on/off switch).  Stored on
 * users/{uid}.quietHoursStart / quietHoursEnd (Hong Kong "HH:mm").
 *
 * The global window lives in app_config/reminders
 * (quietHoursStart / quietHoursEnd, Hong Kong local "HH:mm", defaults
 * 22:00–08:00).  windowFor() takes the elder's own value first, field by
 * field, otherwise the global one; an own value outside RANGE is moved to
 * the nearest edge of the range, a malformed one is ignored.  Every
 * per-person push sender calls inQuietHours(user, …) first and leaves the
 * push for a later tick when it returns true.  Topic broadcasts
 * (dailyMoodReminder with checkInChatV2Enabled off, weeklySurveyReminder
 * with weeklyScheduleV2Enabled off) cannot be filtered per person and are
 * scheduled outside every allowed window anyway (19:00; Sunday 20:00 only
 * on the old path).
 */

"use strict";

const DEFAULT_START = "22:00";
const DEFAULT_END = "08:00";
const HK_OFFSET_MS = 8 * 3600 * 1000;

/**
 * 1020o: what the elder may pick (【待 Junyu 定】).  Change it here AND in
 * lib/core/notifications/quiet_hours_range.dart (the App's pickers) AND in
 * firestore.rules (quietStartValues / quietEndValues);
 * functions/test/quiet_hours_test.js fails while the three differ.  The
 * research pushes at 08:30, 10:00 and 19:00 stay outside every allowed
 * window.
 */
const RANGE = {
  startEarliest: "20:00",
  startLatest: "23:00",
  endEarliest: "06:00",
  endLatest: "08:00",
  stepMinutes: 30,
};

/** users/{uid} fields (1020o). */
const USER_START_FIELD = "quietHoursStart";
const USER_END_FIELD = "quietHoursEnd";

/**
 * @param {*} raw "HH:mm"
 * @param {string} fallback
 * @return {number} minutes since midnight
 */
function parseHHmm(raw, fallback) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(typeof raw === "string" ? raw : "");
  const src = m ? raw : fallback;
  const parts = src.split(":");
  const h = Number(parts[0]);
  const min = Number(parts[1]);
  if (h < 0 || h > 23 || min < 0 || min > 59) {
    return parseHHmm(fallback, fallback);
  }
  return h * 60 + min;
}

/**
 * @param {number} mins minutes since midnight
 * @return {string} "HH:mm"
 */
function fmtHHmm(mins) {
  return `${String(Math.floor(mins / 60)).padStart(2, "0")}:` +
      `${String(mins % 60).padStart(2, "0")}`;
}

/**
 * @param {?object} data app_config/reminders document data
 * @return {{startMin: number, endMin: number, start: string, end: string}}
 */
function quietHoursConfigFrom(data) {
  const d = data || {};
  const startMin = parseHHmm(d.quietHoursStart, DEFAULT_START);
  const endMin = parseHHmm(d.quietHoursEnd, DEFAULT_END);
  return {startMin, endMin, start: fmtHHmm(startMin), end: fmtHHmm(endMin)};
}

/**
 * Every value between [from] and [to] in RANGE.stepMinutes steps — what
 * the App's picker offers and what firestore.rules accept.
 * @param {string} from "HH:mm"
 * @param {string} to "HH:mm"
 * @return {Array<string>}
 */
function steps(from, to) {
  const out = [];
  const end = parseHHmm(to, to);
  for (let m = parseHHmm(from, from); m <= end; m += RANGE.stepMinutes) {
    out.push(fmtHHmm(m));
  }
  return out;
}

/** @return {Array<string>} the 「由」 choices, e.g. 20:00 … 23:00 */
function allowedStarts() {
  return steps(RANGE.startEarliest, RANGE.startLatest);
}

/** @return {Array<string>} the 「到」 choices, e.g. 06:00 … 08:00 */
function allowedEnds() {
  return steps(RANGE.endEarliest, RANGE.endLatest);
}

/**
 * The elder's own value in minutes, moved into [lo, hi]; null when it is
 * missing or not a valid "HH:mm" (then the global value applies).
 * @param {*} raw users/{uid}.quietHoursStart or quietHoursEnd
 * @param {string} lo "HH:mm"
 * @param {string} hi "HH:mm"
 * @return {?number}
 */
function personalMinutes(raw, lo, hi) {
  if (typeof raw !== "string") return null;
  const m = /^(\d{2}):(\d{2})$/.exec(raw);
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) return null;
  const v = h * 60 + min;
  return Math.min(Math.max(v, parseHHmm(lo, lo)), parseHHmm(hi, hi));
}

/**
 * The window that applies to one person: their own start / end first (each
 * clamped to RANGE), otherwise the global config's.
 * @param {?object} user users/{uid} data
 * @param {{startMin: number, endMin: number}} cfg global window
 * @return {{startMin: number, endMin: number, start: string, end: string,
 *     personalStart: boolean, personalEnd: boolean}}
 */
function windowFor(user, cfg) {
  const u = user || {};
  const c = cfg || quietHoursConfigFrom({});
  const ownStart = personalMinutes(u[USER_START_FIELD],
      RANGE.startEarliest, RANGE.startLatest);
  const ownEnd = personalMinutes(u[USER_END_FIELD],
      RANGE.endEarliest, RANGE.endLatest);
  const startMin = ownStart === null ? c.startMin : ownStart;
  const endMin = ownEnd === null ? c.endMin : ownEnd;
  return {
    startMin, endMin, start: fmtHHmm(startMin), end: fmtHHmm(endMin),
    personalStart: ownStart !== null, personalEnd: ownEnd !== null,
  };
}

/**
 * @param {object} db admin.firestore()
 * @return {Promise<{startMin: number, endMin: number, start: string,
 *     end: string}>}
 */
async function readQuietHoursConfig(db) {
  let data = {};
  try {
    const snap = await db.doc("app_config/reminders").get();
    data = snap.exists ? (snap.data() || {}) : {};
  } catch (err) {
    console.warn("quiet hours config read failed; using defaults",
        {err: err && err.message});
  }
  return quietHoursConfigFrom(data);
}

/**
 * Minutes since midnight, Hong Kong time.
 * @param {Date} now
 * @return {number}
 */
function hkMinutes(now) {
  const hk = new Date(now.getTime() + HK_OFFSET_MS);
  return hk.getUTCHours() * 60 + hk.getUTCMinutes();
}

/**
 * @param {?object} user users/{uid} data (1020o: its quietHoursStart /
 *     quietHoursEnd come first; quietHoursEnabled no longer matters)
 * @param {Date} now
 * @param {{startMin: number, endMin: number}} cfg global window
 * @return {boolean} true = do not push now
 */
function inQuietHours(user, now, cfg) {
  const c = windowFor(user, cfg);
  if (c.startMin === c.endMin) return false; // zero-length window = off
  const m = hkMinutes(now);
  if (c.startMin < c.endMin) return m >= c.startMin && m < c.endMin;
  // Window crosses midnight (the default 22:00–08:00).
  return m >= c.startMin || m < c.endMin;
}

/**
 * 1020o: when a push due at [at] may go out — the end of the person's
 * quiet window that [at] falls in; null when [at] is outside it.
 * @param {?object} user users/{uid} data
 * @param {Date} at
 * @param {{startMin: number, endMin: number}} cfg global window
 * @return {?Date}
 */
function quietEndAfter(user, at, cfg) {
  if (!inQuietHours(user, at, cfg)) return null;
  const c = windowFor(user, cfg);
  let delta = c.endMin - hkMinutes(at);
  if (delta <= 0) delta += 24 * 60;
  const minuteStart = at.getTime() - (at.getTime() % 60000);
  return new Date(minuteStart + delta * 60000);
}

module.exports = {
  DEFAULT_START, DEFAULT_END, RANGE, USER_START_FIELD, USER_END_FIELD,
  parseHHmm, fmtHHmm, quietHoursConfigFrom, allowedStarts, allowedEnds,
  personalMinutes, windowFor, readQuietHoursConfig, hkMinutes, inQuietHours,
  quietEndAfter,
};
