/**
 * T24 — study-week arithmetic (SPEC:C15; research note 10/9 item 11 and
 * its correction).  THE one place the server turns a moment into a study
 * day / study week.  The App mirrors it in
 * lib/core/scheduling/study_week.dart; test/fixtures/study_week_table.json
 * feeds both tests the same cases.
 *
 *   W0 (the enrolment visit, users/{uid}.w0Date, a Hong Kong date) is
 *   study day 0.  Study day k is the k-th Hong Kong calendar day after W0
 *   (negative before W0).  Study week:
 *       day 0           → week 0
 *       days 1–7        → week 1
 *       days 8–14       → week 2       i.e. week = ceil(day / 7)
 *       …                 (follow-up weeks keep counting)
 *   Days before W0 report week 0 as well.
 *
 * Nothing here reads Firestore.  T35 (W8 in the App) and T25 (Brief PR
 * week attribution) call these functions instead of re-deriving dates.
 */

"use strict";

const HK_TZ = "Asia/Hong_Kong";
const HK_OFFSET = "+08:00"; // Hong Kong has no daylight saving time.
const DATE_KEY = /^\d{4}-\d{2}-\d{2}$/;

/**
 * YYYY-MM-DD in Hong Kong.
 * @param {Date} d
 * @return {string}
 */
function hkDateKey(d) {
  return d.toLocaleDateString("en-CA", {timeZone: HK_TZ});
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
 * @param {number} n days to add (may be negative)
 * @return {string}
 */
function addDays(key, n) {
  const d = new Date(`${key}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/**
 * The instant `hour`:00 Hong Kong time on the day `key`.
 * @param {string} key YYYY-MM-DD
 * @param {number} hour 0–23
 * @return {Date}
 */
function hkInstant(key, hour) {
  const hh = String(hour).padStart(2, "0");
  return new Date(`${key}T${hh}:00:00${HK_OFFSET}`);
}

/**
 * The first instant after the Hong Kong day `key` (i.e. the next day's
 * 00:00).  A window that "closes at the end of day N" closes here.
 * @param {string} key YYYY-MM-DD
 * @return {Date}
 */
function hkEndOfDay(key) {
  return hkInstant(addDays(key, 1), 0);
}

/**
 * @param {*} v
 * @return {boolean} a YYYY-MM-DD string
 */
function isDateKey(v) {
  return typeof v === "string" && DATE_KEY.test(v) &&
    !isNaN(new Date(`${v}T00:00:00Z`).getTime());
}

/**
 * The W0 date, Hong Kong calendar day.  THE single place the server
 * decides W0: the date the researcher entered at registration
 * (users/{uid}.w0Date, T19; the registration day for a pilot account,
 * T21), else the account's createdAt (unregistered accounts, old data).
 * The App mirrors this in lib/core/scheduling/w0_date.dart.
 * @param {?object} user users/{uid} data
 * @return {?string} YYYY-MM-DD, or null when unknown
 */
function w0DateKey(user) {
  const registered = user && user.w0Date;
  if (isDateKey(registered)) return registered;
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
 * Study day of a Hong Kong date.  W0 = 0.
 * @param {string} w0Key YYYY-MM-DD
 * @param {string} dateKey YYYY-MM-DD
 * @return {number} whole days, negative before W0
 */
function studyDayOf(w0Key, dateKey) {
  return daysBetween(w0Key, dateKey);
}

/**
 * Study week of a study day: 0 for day 0 (and before), ceil(day / 7)
 * after.
 * @param {number} day
 * @return {number}
 */
function studyWeekOf(day) {
  if (typeof day !== "number" || !isFinite(day)) return 0;
  if (day <= 0) return 0;
  return Math.ceil(day / 7);
}

/**
 * Study day of an instant, by its Hong Kong date.
 * @param {?string} w0Key YYYY-MM-DD (anything else → null)
 * @param {Date} at
 * @return {?number} null when W0 or the instant is unknown
 */
function studyDayAt(w0Key, at) {
  if (!isDateKey(w0Key)) return null;
  if (!(at instanceof Date) || isNaN(at.getTime())) return null;
  return studyDayOf(w0Key, hkDateKey(at));
}

/**
 * Study week of an instant.
 * @param {?string} w0Key
 * @param {Date} at
 * @return {?number}
 */
function studyWeekAt(w0Key, at) {
  const day = studyDayAt(w0Key, at);
  return day === null ? null : studyWeekOf(day);
}

/**
 * Both numbers at once, for stamping a record.
 * @param {?string} w0Key
 * @param {Date} at
 * @return {?{studyDay: number, studyWeek: number}}
 */
function studyPositionAt(w0Key, at) {
  const day = studyDayAt(w0Key, at);
  if (day === null) return null;
  return {studyDay: day, studyWeek: studyWeekOf(day)};
}

/**
 * Firestore Timestamp / Date / ISO string → Date, else null.
 * @param {*} v
 * @return {?Date}
 */
function toDate(v) {
  if (!v) return null;
  if (v instanceof Date) return isNaN(v.getTime()) ? null : v;
  if (typeof v.toDate === "function") return v.toDate();
  if (typeof v === "string") {
    const d = new Date(v);
    return isNaN(d.getTime()) ? null : d;
  }
  return null;
}

module.exports = {
  HK_TZ, HK_OFFSET,
  hkDateKey, hkHour, daysBetween, addDays, hkInstant, hkEndOfDay, isDateKey,
  w0DateKey, studyDayOf, studyWeekOf, studyDayAt, studyWeekAt,
  studyPositionAt, toDate,
};
