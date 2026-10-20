/**
 * 10/14 (lead's decision) — the elder's 「安靜時段」 toggle is real.
 * 10/20 (dev-tasks-1020 §H(2)) — quiet hours are fixed on for everyone; the
 * switch is gone from the App and users/{uid}.quietHoursEnabled (which the
 * App used to mirror the toggle onto) is ignored.
 *
 * The window lives in app_config/reminders
 * (quietHoursStart / quietHoursEnd, Hong Kong local "HH:mm", defaults
 * 22:00–08:00).  Every per-person push sender calls inQuietHours() first and
 * leaves the push for a later tick when it returns true.  Topic broadcasts
 * (dailyMoodReminder, weeklySurveyReminder) cannot be filtered per person
 * and are scheduled outside the default window anyway.
 */

"use strict";

const DEFAULT_START = "22:00";
const DEFAULT_END = "08:00";
const HK_OFFSET_MS = 8 * 3600 * 1000;

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
 * @param {?object} data app_config/reminders document data
 * @return {{startMin: number, endMin: number, start: string, end: string}}
 */
function quietHoursConfigFrom(data) {
  const d = data || {};
  const startMin = parseHHmm(d.quietHoursStart, DEFAULT_START);
  const endMin = parseHHmm(d.quietHoursEnd, DEFAULT_END);
  const fmt = (mins) => `${String(Math.floor(mins / 60)).padStart(2, "0")}:` +
      `${String(mins % 60).padStart(2, "0")}`;
  return {startMin, endMin, start: fmt(startMin), end: fmt(endMin)};
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
 * @param {?object} user users/{uid} data
 * @param {Date} now
 * @param {{startMin: number, endMin: number}} cfg
 * @return {boolean} true = do not push now
 */
function inQuietHours(user, now, cfg) {
  // [user] is kept for the callers; quietHoursEnabled no longer matters.
  const c = cfg || quietHoursConfigFrom({});
  if (c.startMin === c.endMin) return false; // zero-length window = off
  const m = hkMinutes(now);
  if (c.startMin < c.endMin) return m >= c.startMin && m < c.endMin;
  // Window crosses midnight (the default 22:00–08:00).
  return m >= c.startMin || m < c.endMin;
}

module.exports = {
  DEFAULT_START, DEFAULT_END, parseHHmm, quietHoursConfigFrom,
  readQuietHoursConfig, hkMinutes, inQuietHours,
};
