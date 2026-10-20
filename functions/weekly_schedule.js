/**
 * T24 — study weeks and the weekly questionnaire bundle (SPEC:C15, C17;
 * dev-tasks-1009 T24 third edition, dev-tasks-1014 §3 T24).  Phase B and
 * the pilot run; both arms identical; no LLM anywhere here.
 *
 * Switch: app_config/phase_b.weeklyScheduleV2Enabled === true (default
 * off).  Off, nothing in this file runs: the Sunday calendar-week window
 * and T18's single day-14 DJG stay as they are.
 *
 * Schedule (standard, cohort "phase_b"; days are study days, W0 = 0):
 *   W1–W3  push on weeklyBundleDays[0..2] (7, 14, 21) at weeklyPushHour;
 *          window = weeklyWindowDays × 24 h from the push instant;
 *          parts DJG-ES (djgWeeks) → Weekly PR → PGIC → social-contact
 *          probe (socialContactProbeEnabled).
 *   W4     opens on weeklyBundleDays[3] (26); closes at the end of day
 *          week4CloseDay (29) or the W4 visit day, whichever is later
 *          (week4CloseFor — the visit date arrives with T30); no DJG.
 *   W5–W7  PGIC only, pgicOnlyDays (35, 42, 49), weeklyWindowDays window.
 * Pilot (cohort "pilot"): the SAME standard schedule (10/15: the pilot run
 *   follows Phase B day for day).  The compressed mode below (pilotBundleDays
 *   1, 3, 5, 7, pilotWindowDays 1, no PGIC-only weeks) is kept only for the
 *   shared table test; no cohort maps to it any more.
 *
 * Records (one document per part, id = bundle id W1…W7):
 *   users/{uid}/djg_responses/{W1|W2|W3}      (T18 schema; server scores)
 *   users/{uid}/weekly_pr/{Wn}
 *   users/{uid}/pgic/{Wn}
 *   users/{uid}/social_contact_probes/{W1…W4}
 * The App writes the answers and `bundle`; the server stamps studyWeek,
 * studyDay (of the push), submittedStudyDay, pushedAt, windowStart,
 * windowEnd, missed, scheduleMode (stampPartRecord, Firestore triggers)
 * and writes the missed records (dispatcher).  firestore.rules refuses
 * those fields from a client.
 *   weekly_status/{uid}  server-only: research ID, per-bundle push /
 *                        reminder / missed times (like T17b ada_status).
 *   users/{uid}/brief_pr/{id}  stampBriefPr adds studyWeek / studyDay by
 *                        sessionEndedAt (T25 records).
 *
 * Dispatcher (dispatchWeeklyBundles, hourly 08:00–21:00 HKT): per person
 * (fcm_tokens, never a topic), one push when the window opens, T18's one
 * reminder djgW2ReminderHours later if a part is still open, the missed
 * marks after the window.  Copy is final since 10/15 (item 6); a draft
 * override carrying 【占位】 is never sent, so nothing is
 * sent until the research team signs the text off (counted as
 * blocked_placeholder, like T18).  Quiet hours (functions/quiet_hours.js;
 * 1020o: the elder's own window first) postpone a push to the next tick.
 *
 * Reminders v2 (dev-tasks-1020 G(1) as changed by 1020e 二.1–二.3) —
 * switch app_config/feature_flags.weeklyReminderV2Enabled (literal true;
 * read into cfg.reminderV2 by readConfig; needs weeklyScheduleV2Enabled
 * too, this whole dispatcher being off without it).  Both arms
 * identical.  For W1–W4 only (mirrored in the App,
 * lib/core/scheduling/weekly_schedule.dart, same fixture):
 *   W1–W3  window = whole Hong Kong days: day 7 00:00 → end of day 9
 *          (14–16, 21–23).  Pushes at 10:00: preview day 6 (all), open
 *          day 7 (all), reminders day 8 and day 9 (parts still open
 *          only).  E-mail day 9.
 *   W4     opens day 26 00:00; closes at the end of the day the assessor
 *          records the W4 visit (users/{uid}.w4RecordedOn, assessor.js;
 *          never before the end of day 26), at the latest the end of day
 *          42.  Pushes at 10:00: preview day 25, open day 26 (all),
 *          reminder day 28 (parts still open).  E-mail day 28.
 *   T18's 24-hour reminder is not sent for these four bundles; the
 *   missed marks follow the v2 windows; part records also get
 *   `outsideWindow` (stampPartRecord).  W5–W7 (PGIC only) keep the T24
 *   window, push + 24-hour reminder and S14 copy.  weekly_status
 *   bundles[Wn] gains previewSentAt, remind1SentAt, remind2SentAt,
 *   pushCopyId.  The e-mail is functions/weekly_email.js.  Off:
 *   everything exactly as above.
 */

"use strict";

const studyWeek = require("./study_week");
const quietHours = require("./quiet_hours");
const testerArm = require("./tester_arm");
const studyPeriod = require("./study_period");
const featureFlags = require("./feature_flags");
const pushCopy = require("./push_copy");

const CONFIG_DOC = "app_config/phase_b";
const STATUS_COLLECTION = "weekly_status";
const SOCIAL_COLLECTION = "social_contact_probes";
const DJG_COLLECTION = "djg_responses";
const WEEKLY_PR_COLLECTION = "weekly_pr";
const PGIC_COLLECTION = "pgic";
const BRIEF_PR_COLLECTION = "brief_pr";

const PART = {
  DJG: "djg",
  WEEKLY_PR: "weekly_pr",
  PGIC: "pgic",
  SOCIAL: "social_contact",
};
const PART_COLLECTION = {
  djg: DJG_COLLECTION,
  weekly_pr: WEEKLY_PR_COLLECTION,
  pgic: PGIC_COLLECTION,
  social_contact: SOCIAL_COLLECTION,
};

const MODE_STANDARD = "standard";
const MODE_PILOT = "pilot";

const DEFAULTS = {
  enabled: false,
  bundleDays: [7, 14, 21, 26],
  windowDays: 3,
  week4CloseDay: 29,
  djgWeeks: [1, 2, 3],
  pgicOnlyDays: [35, 42, 49],
  // The hour of today's weekly push (weeklySurveyReminder, Sunday 20:00).
  pushHour: 20,
  socialContactProbeEnabled: false,
  pilotBundleDays: [1, 3, 5, 7],
  pilotWindowDays: 1,
  // T18's reminder rule, reused unchanged
  // (app_config/phase_b.djgW2ReminderHours).
  reminderHours: 24,
};

/** Server-only fields on a part record (firestore.rules mirrors this). */
const SERVER_ONLY_FIELDS = [
  "studyWeek", "studyDay", "submittedStudyDay", "pushedAt", "windowStart",
  "windowEnd", "missed", "missedAt", "scheduleMode", "stampedAt",
  // 1020e: stamped with reminders v2 on.
  "outsideWindow",
];

// Missed marks are written only in the first week after a window closes,
// so turning the switch on mid-trial does not stamp "missed" on bundles
// nobody ever saw (same idea as T18 MISSED_LOOKBACK_DAYS).
const MISSED_LOOKBACK_MS = 7 * 86400000;
// The cron runs on the hour; the push stamp lands a few seconds after.
const REMINDER_SLACK_MS = 5 * 60 * 1000;

const PLACEHOLDER_MARK = "【占位】";
const PUSH_TITLE = "陪住";
// Final copy (10/15 item 6 C(1)(2), docs/spec/copy/short-texts.md S14).
// isPlaceholder() still guards any override that carries the mark.
const PUSH_BODY = "今個禮拜嘅問卷開咗，得閒入嚟答幾條。";
const REMINDER_BODY = "今個禮拜嘅問卷仲未答完，得閒入嚟答埋佢。";

/** 1020 G(1): app_config/feature_flags switch for the reminders v2. */
const REMINDER_V2_FLAG = "weeklyReminderV2Enabled";
/** 1020e 二.1 / 二.2: every v2 push goes at 10:00 Hong Kong time. */
const V2_PUSH_HOUR = 10;
/** 1020e 二.2(1): W4 closes at the end of day 42 at the latest. */
const V2_WEEK4_LATEST_CLOSE_DAY = 42;

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

/**
 * @param {*} v
 * @param {number[]} def
 * @param {number} min
 * @return {number[]} strictly increasing whole numbers ≥ min, else def
 */
function dayList(v, def, min) {
  if (!Array.isArray(v) || v.length === 0) return def.slice();
  const out = [];
  for (const x of v) {
    if (typeof x !== "number" || !isFinite(x) || x < min) return def.slice();
    const n = Math.floor(x);
    if (out.length > 0 && n <= out[out.length - 1]) return def.slice();
    out.push(n);
  }
  return out;
}

/**
 * @param {object} data app_config/phase_b fields
 * @param {?object} flags app_config/feature_flags fields (1020: only
 *     weeklyReminderV2Enabled is read; absent = off)
 * @return {object} merged config
 */
function configFromData(data, flags) {
  const d = data || {};
  const num = (v, def, min) =>
    (typeof v === "number" && isFinite(v) && v >= min ? Math.floor(v) : def);
  return {
    enabled: d.weeklyScheduleV2Enabled === true,
    // 1020e 二.1 / 二.2: the v2 windows, pushes and e-mail (literal true).
    reminderV2: !!flags && flags[REMINDER_V2_FLAG] === true,
    bundleDays: dayList(d.weeklyBundleDays, DEFAULTS.bundleDays, 1),
    windowDays: num(d.weeklyWindowDays, DEFAULTS.windowDays, 1),
    week4CloseDay: num(d.week4CloseDay, DEFAULTS.week4CloseDay, 1),
    djgWeeks: dayList(d.djgWeeks, DEFAULTS.djgWeeks, 1),
    pgicOnlyDays: dayList(d.pgicOnlyDays, DEFAULTS.pgicOnlyDays, 1),
    pushHour: num(d.weeklyPushHour, DEFAULTS.pushHour, 0) % 24,
    socialContactProbeEnabled: d.socialContactProbeEnabled === true,
    pilotBundleDays: dayList(d.pilotBundleDays, DEFAULTS.pilotBundleDays, 0),
    pilotWindowDays: num(d.pilotWindowDays, DEFAULTS.pilotWindowDays, 1),
    reminderHours: num(d.djgW2ReminderHours, DEFAULTS.reminderHours, 1),
  };
}

/**
 * @param {object} db admin.firestore()
 * @return {Promise<object>} configFromData() of app_config/phase_b, with
 *     the reminders-v2 switch from app_config/feature_flags (a read error
 *     there counts as off, like every flag)
 */
async function readConfig(db) {
  let flags = null;
  try {
    const f = await db.doc(featureFlags.FLAGS_DOC).get();
    flags = f.exists ? (f.data() || {}) : null;
  } catch (err) {
    console.warn("feature flags read failed; reminders v2 off",
        {err: err && err.message});
  }
  try {
    const snap = await db.doc(CONFIG_DOC).get();
    return configFromData(snap.exists ? snap.data() : {}, flags);
  } catch (err) {
    console.warn("phase_b config read failed; weekly schedule off",
        {err: err && err.message});
    return configFromData({}, null);
  }
}

// ---------------------------------------------------------------------------
// Schedule (pure).  Mirrored in lib/core/scheduling/weekly_schedule.dart;
// test/fixtures/weekly_schedule_table.json feeds both tests.
// ---------------------------------------------------------------------------

/**
 * Schedule mode of a participant: by cohort (T21).  null = not scheduled
 * (Phase A, unregistered, tester handled by the caller).  10/15: a pilot
 * account runs the standard Phase B schedule; MODE_PILOT is never returned.
 * @param {?object} user users/{uid} data
 * @return {?string} "standard" | null
 */
function scheduleModeFor(user) {
  // 1020b §1: every registered cohort (run-in, RCT, pilot) runs the
  // standard schedule; the list lives in study_period.js.
  return studyPeriod.isEnrolled(user) ? MODE_STANDARD : null;
}

/**
 * The bundles of a mode, in push order.
 * @param {object} cfg configFromData() result
 * @param {string} mode "standard" | "pilot"
 * @return {Array<{id: string, index: number, studyWeek: number,
 *     pushDay: number, parts: string[], windowDays: number,
 *     closeRule: string}>}  closeRule: "window" | "week4"
 */
function bundlesFor(cfg, mode) {
  const out = [];
  const common = (withDjg) => {
    const parts = [];
    if (withDjg) parts.push(PART.DJG);
    parts.push(PART.WEEKLY_PR, PART.PGIC);
    if (cfg.socialContactProbeEnabled) parts.push(PART.SOCIAL);
    return parts;
  };
  if (mode === MODE_PILOT) {
    cfg.pilotBundleDays.forEach((day, i) => {
      out.push({
        id: `W${i + 1}`, index: i, studyWeek: studyWeek.studyWeekOf(day),
        bundleWeek: i + 1, pushDay: day, parts: common(i < 3),
        windowDays: cfg.pilotWindowDays, closeRule: "window",
      });
    });
    return out;
  }
  cfg.bundleDays.forEach((day, i) => {
    const week = i + 1;
    out.push({
      id: `W${week}`, index: i, studyWeek: studyWeek.studyWeekOf(day),
      bundleWeek: week, pushDay: day,
      parts: common(cfg.djgWeeks.indexOf(week) >= 0),
      windowDays: cfg.windowDays,
      closeRule: week === 4 ? "week4" : "window",
    });
  });
  cfg.pgicOnlyDays.forEach((day, j) => {
    const week = studyWeek.studyWeekOf(day);
    out.push({
      id: `W${week}`, index: cfg.bundleDays.length + j, studyWeek: week,
      bundleWeek: week, pushDay: day, parts: [PART.PGIC],
      windowDays: cfg.windowDays, closeRule: "window",
    });
  });
  return out;
}

/**
 * @param {object} cfg
 * @param {string} mode
 * @param {string} id bundle id
 * @return {?object} the bundle
 */
function bundleById(cfg, mode, id) {
  for (const b of bundlesFor(cfg, mode)) if (b.id === id) return b;
  return null;
}

/**
 * Week-4 close instant (standard mode): the end of study day
 * `week4CloseDay`, or of the W4 visit day when that is later.  The visit
 * date is the assessor's administration date from T30 (not merged yet:
 * every caller passes null today, so the window closes on day 29).
 * @param {string} w0Key YYYY-MM-DD
 * @param {?string} w4VisitDateKey YYYY-MM-DD or null
 * @param {object} cfg
 * @return {Date} exclusive close instant
 */
function week4CloseFor(w0Key, w4VisitDateKey, cfg) {
  const byDay = studyWeek.hkEndOfDay(
      studyWeek.addDays(w0Key, cfg.week4CloseDay));
  if (!studyWeek.isDateKey(w4VisitDateKey)) return byDay;
  const byVisit = studyWeek.hkEndOfDay(w4VisitDateKey);
  return byVisit > byDay ? byVisit : byDay;
}

/**
 * 1020e 二.2 — week-4 close with reminders v2: the end of the Hong Kong
 * day the assessor recorded the W4 visit (users/{uid}.w4RecordedOn,
 * written by assessor.js on the first W4 entry), never before the end of
 * the opening day (so a visit recorded before day 26 still leaves the
 * opening day) and never after the end of day V2_WEEK4_LATEST_CLOSE_DAY
 * (42).  Nothing recorded: the end of day 42.
 * @param {string} w0Key YYYY-MM-DD
 * @param {?string} recordedOn YYYY-MM-DD or null
 * @param {object} bundle the W4 bundle (its push day is the opening day)
 * @return {Date} exclusive close instant
 */
function week4CloseV2(w0Key, recordedOn, bundle) {
  const latest = studyWeek.hkEndOfDay(
      studyWeek.addDays(w0Key, V2_WEEK4_LATEST_CLOSE_DAY));
  if (!studyWeek.isDateKey(recordedOn)) return latest;
  const earliest = studyWeek.hkEndOfDay(
      studyWeek.addDays(w0Key, bundle.pushDay));
  let close = studyWeek.hkEndOfDay(recordedOn);
  if (close < earliest) close = earliest;
  return close > latest ? latest : close;
}

/**
 * The window of a bundle for one participant.
 *
 * Reminders v2 on (cfg.reminderV2, 1020e 二.1 / 二.2) and the bundle is
 * W1–W4: whole Hong Kong days.  W1–W3 open at 00:00 of the push day (7,
 * 14, 21) and close at the end of the push day + weeklyWindowDays − 1 (day
 * 9, 16, 23 at 23:59:59); W4 opens at 00:00 of day 26 and closes as
 * week4CloseV2.  Otherwise (switch off, or W5–W7) exactly T24: open at
 * weeklyPushHour on the push day, 72 h, W4 by week4CloseFor.
 * @param {object} bundle bundlesFor() element
 * @param {string} w0Key YYYY-MM-DD
 * @param {object} cfg
 * @param {{w4VisitDate: (string|undefined),
 *     week4RecordedOn: (string|undefined)}} opts w4VisitDate: T24's hook
 *     (switch off); week4RecordedOn: users/{uid}.w4RecordedOn (switch on)
 * @return {{open: Date, close: Date, pushDateKey: string}} [open, close)
 */
function windowFor(bundle, w0Key, cfg, opts) {
  const o = opts || {};
  const pushDateKey = studyWeek.addDays(w0Key, bundle.pushDay);
  if (cfg.reminderV2 && isReminderV2Bundle(bundle)) {
    const dayStart = studyWeek.hkInstant(pushDateKey, 0);
    const dayClose = bundle.closeRule === "week4" ?
      week4CloseV2(w0Key, o.week4RecordedOn || null, bundle) :
      studyWeek.hkEndOfDay(
          studyWeek.addDays(pushDateKey, bundle.windowDays - 1));
    return {open: dayStart, close: dayClose, pushDateKey};
  }
  const open = studyWeek.hkInstant(pushDateKey, cfg.pushHour);
  const close = bundle.closeRule === "week4" ?
    week4CloseFor(w0Key, o.w4VisitDate || null, cfg) :
    new Date(open.getTime() + bundle.windowDays * 86400000);
  return {open, close, pushDateKey};
}

/**
 * The bundle whose window contains `now`, or null.
 * @param {object} cfg
 * @param {string} mode
 * @param {string} w0Key
 * @param {Date} now
 * @param {object} opts windowFor opts
 * @return {?{bundle: object, window: object}}
 */
function openBundleAt(cfg, mode, w0Key, now, opts) {
  for (const b of bundlesFor(cfg, mode)) {
    const w = windowFor(b, w0Key, cfg, opts);
    if (now >= w.open && now < w.close) return {bundle: b, window: w};
  }
  return null;
}

// ---------------------------------------------------------------------------
// Reminders v2 (dev-tasks-1020 G(1)) — pure parts
// ---------------------------------------------------------------------------

/**
 * Does reminders v2 cover this bundle?  W1–W3 (the first three bundle
 * days) and W4 (closeRule "week4").  The PGIC-only weeks W5–W7 are left as
 * they are (1020e 二.3; W8 is T35, not built).
 * @param {?object} bundle bundlesFor() element
 * @return {boolean}
 */
function isReminderV2Bundle(bundle) {
  return !!bundle && (bundle.closeRule === "week4" ||
    (bundle.closeRule === "window" && bundle.index < 3));
}

/**
 * The Hong Kong day a window ends on: the day of its last instant.
 * @param {{close: Date}} win windowFor() result
 * @return {string} YYYY-MM-DD
 */
function closingDayKey(win) {
  return studyWeek.hkDateKey(new Date(win.close.getTime() - 1));
}

/**
 * The pushes of reminders v2 for one bundle, in order (1020e 二.1(2),
 * 二.2(2)).  All at V2_PUSH_HOUR (10:00) on their day.  `all`: to every
 * participant in the schedule; otherwise only to one with a part still
 * open.  `email`: the research lead's E1 lists the bundle on that day.
 *   W1–W3  preview the day before the push day (6, 13, 20; all), open on
 *          the push day (7, 14, 21; all), reminder 1 the day before the
 *          last day (8, 15, 22) and reminder 2 on the last day (9, 16, 23,
 *          the e-mail day).
 *   W4     preview day 25 (all), open day 26 (all), one reminder day 28
 *          (the e-mail day).
 * A push is sent only while its window is not closed (W4 may close early
 * when the visit is recorded).
 * @param {object} bundle bundlesFor() element
 * @param {{close: Date, pushDateKey: string}} win windowFor() result
 * @return {Array<{step: string, dateKey: string, copyId: string,
 *     field: string, all: boolean, email: boolean}>}
 */
function v2StepsFor(bundle, win) {
  const day = (n) => studyWeek.addDays(win.pushDateKey, n);
  const step = (name, dateKey, copyId, field, all, email) =>
    ({step: name, dateKey, copyId, field, all, email});
  if (bundle.closeRule === "week4") {
    return [
      step("preview", day(-1), "W4-pre", "previewSentAt", true, false),
      step("open", day(0), "W4-open", "pushedAt", true, false),
      step("remind1", day(2), "W4-rem", "remind1SentAt", false, true),
    ];
  }
  const last = closingDayKey(win);
  return [
    step("preview", day(-1), "W-pre", "previewSentAt", true, false),
    step("open", day(0), "W-open", "pushedAt", true, false),
    step("remind1", studyWeek.addDays(last, -1), "W-rem1", "remind1SentAt",
        false, false),
    step("remind2", last, "W-rem2", "remind2SentAt", false, true),
  ];
}

/**
 * The day the research lead's e-mail lists a bundle (1020e 二.1(3),
 * 二.2(3)): day 9 / 16 / 23 for W1–W3, day 28 for W4.
 * @param {object} bundle
 * @param {object} win windowFor() result
 * @return {string} YYYY-MM-DD
 */
function emailDayKeyFor(bundle, win) {
  return v2StepsFor(bundle, win).filter((s) => s.email)[0].dateKey;
}

/**
 * windowFor() options for one participant.  Reminders v2 on: the day the
 * assessor recorded W4 (users/{uid}.w4RecordedOn, App-readable, written by
 * assessor.js) closes week 4 (week4CloseV2).  Off: none, exactly T24.
 * @param {?object} user users/{uid} data
 * @param {object} cfg readConfig() result
 * @return {(object|undefined)}
 */
function windowOptsFor(user, cfg) {
  if (!cfg.reminderV2) return undefined;
  const d = user ? user.w4RecordedOn : null;
  return studyWeek.isDateKey(d) ? {week4RecordedOn: d} : {};
}

/**
 * @param {object} db admin.firestore()
 * @return {Promise<boolean>} weeklyReminderV2Enabled is literally true
 */
function reminderV2On(db) {
  return featureFlags.isFeatureEnabled(db, REMINDER_V2_FLAG);
}

/**
 * Sessions counted for the Weekly PR referent of a bundle: from the start
 * of the first day of its study week (pilot: the previous push, or W0
 * midnight for the first bundle) to the push instant.
 * @param {object} bundle
 * @param {string} w0Key
 * @param {object} cfg
 * @param {string} mode
 * @return {{start: Date, end: Date}}
 */
function referentRangeFor(bundle, w0Key, cfg, mode) {
  const end = windowFor(bundle, w0Key, cfg).open;
  if (mode === MODE_PILOT) {
    if (bundle.index === 0) {
      return {start: studyWeek.hkInstant(w0Key, 0), end};
    }
    const prev = bundlesFor(cfg, mode)[bundle.index - 1];
    return {start: windowFor(prev, w0Key, cfg).open, end};
  }
  const firstDay = 7 * (bundle.studyWeek - 1) + 1;
  return {start: studyWeek.hkInstant(studyWeek.addDays(w0Key, firstDay), 0),
    end};
}

/**
 * Is this part record final from the participant's side?
 * @param {string} part PART.*
 * @param {?object} data record data (null = no doc)
 * @return {boolean}
 */
function partSubmitted(part, data) {
  if (!data) return false;
  switch (part) {
    case PART.DJG:
    case PART.SOCIAL:
      return data.status === "submitted";
    case PART.WEEKLY_PR:
      return ["completed", "skipped", "no_referent"].indexOf(data.status) >= 0;
    case PART.PGIC:
      return typeof data.value === "number";
    default:
      return false;
  }
}

// ---------------------------------------------------------------------------
// Stamping (server-written fields on records)
// ---------------------------------------------------------------------------

/**
 * Was a submission outside its window?  1020e: stamped with reminders v2
 * only.  null when there is no submission time.
 * @param {?Date} submittedAt
 * @param {{open: Date, close: Date}} win
 * @return {?boolean}
 */
function outsideWindowOf(submittedAt, win) {
  if (!submittedAt) return null;
  return submittedAt < win.open || submittedAt >= win.close;
}

/**
 * The server-written fields of a part record.  With `v2` (reminders v2 on)
 * also `outsideWindow` (outsideWindowOf); off, exactly the T24 fields.
 * @param {{bundle: object, window: object, w0Key: string, mode: string,
 *     pushedAt: ?Date, submittedAt: ?Date, missed: boolean, now: Date,
 *     v2: (boolean|undefined)}} p
 * @return {object}
 */
function partStamp(p) {
  const out = {
    bundle: p.bundle.id,
    studyWeek: p.bundle.studyWeek,
    studyDay: p.bundle.pushDay,
    submittedStudyDay: p.submittedAt ?
      studyWeek.studyDayAt(p.w0Key, p.submittedAt) : null,
    pushedAt: p.pushedAt || null,
    windowStart: p.window.open,
    windowEnd: p.window.close,
    missed: p.missed === true,
    scheduleMode: p.mode,
    stampedAt: p.now,
  };
  if (p.v2 === true) {
    out.outsideWindow = p.missed === true ? null :
      outsideWindowOf(p.submittedAt, p.window);
  }
  return out;
}

/**
 * @param {?object} rec part record data
 * @return {?Date} when the participant submitted it, if they did
 */
function submittedAtOf(rec) {
  return studyWeek.toDate(rec.submittedAt) ||
    studyWeek.toDate(rec.answeredAt) || studyWeek.toDate(rec.respondedAt);
}

/**
 * Firestore trigger body for weekly_pr / pgic / social_contact_probes /
 * djg_responses: stamp the study-week fields on a record that carries
 * `bundle` (W1…W7) and is not stamped yet.  Reusable by T35 for the W8
 * bundle.  Idempotent: a stamped record returns null.
 *
 * Reminders v2 on (1020e): the stamp carries `outsideWindow`; a record
 * stamped before it was submitted (an in-progress DJG or probe) gets
 * `submittedStudyDay` and `outsideWindow` once, on the write that brings
 * its submission time.  The window is the v2 one (W4: users/{uid}
 * .w4RecordedOn).
 * @param {object} db admin.firestore()
 * @param {string} uid
 * @param {string} collection users/{uid}/<collection>
 * @param {string} docId
 * @param {?object} after record data after the write
 * @param {{now: (Date|undefined)}} opts
 * @return {Promise<?object>} fields written, or null
 */
async function stampPartRecord(db, uid, collection, docId, after, opts) {
  const o = opts || {};
  if (!after) return null;
  const stamped = after.studyWeek !== undefined;
  // Stamped already: only a v2 record still owing its submission stamp
  // goes on (checked below, after the switch is read).
  if (stamped && (typeof after.outsideWindow === "boolean" ||
      after.missed === true || !submittedAtOf(after))) {
    return null;
  }
  const bundleId = typeof after.bundle === "string" ? after.bundle :
    (collection === DJG_COLLECTION ? docId : null);
  if (!bundleId || !/^W\d+$/.test(bundleId)) return null;
  const now = o.now || new Date();
  const cfg = await readConfig(db);
  if (stamped && !cfg.reminderV2) return null;
  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.exists ? userSnap.data() : null;
  const mode = scheduleModeFor(user);
  const w0Key = studyWeek.w0DateKey(user);
  if (!mode || !w0Key) return null;
  const bundle = bundleById(cfg, mode, bundleId);
  if (!bundle) return null;
  const win = windowFor(bundle, w0Key, cfg, windowOptsFor(user, cfg));
  const submittedAt = submittedAtOf(after);
  const ref = db.collection("users").doc(uid).collection(collection)
      .doc(docId);
  if (stamped) {
    const late = {
      submittedStudyDay: studyWeek.studyDayAt(w0Key, submittedAt),
      outsideWindow: outsideWindowOf(submittedAt, win),
      stampedAt: now,
    };
    await ref.set(late, {merge: true});
    return late;
  }
  const statusSnap = await db.collection(STATUS_COLLECTION).doc(uid).get();
  const st = statusSnap.exists ? (statusSnap.data() || {}) : {};
  const bst = (st.bundles || {})[bundleId] || {};
  const out = partStamp({
    bundle, window: win, w0Key, mode,
    pushedAt: studyWeek.toDate(bst.pushedAt),
    submittedAt, missed: after.status === "missed", now,
    v2: cfg.reminderV2,
  });
  await ref.set(out, {merge: true});
  return out;
}

/**
 * Firestore trigger body for users/{uid}/brief_pr/{id}: stamp studyWeek /
 * studyDay by the session end (T25 `sessionEndedAt`; older records fall
 * back to respondedAt, then createdAt, then promptedAt).  Only with the
 * switch on; idempotent.
 * @param {object} db
 * @param {string} uid
 * @param {string} docId
 * @param {?object} after
 * @param {{now: (Date|undefined), cfg: (object|undefined)}} opts
 * @return {Promise<?object>}
 */
async function stampBriefPr(db, uid, docId, after, opts) {
  const o = opts || {};
  if (!after || after.studyWeek !== undefined) return null;
  const cfg = o.cfg || await readConfig(db);
  if (!cfg.enabled) return null;
  const basis = ["sessionEndedAt", "respondedAt", "createdAt", "promptedAt"]
      .find((k) => studyWeek.toDate(after[k]) !== null);
  if (!basis) return null;
  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.exists ? userSnap.data() : null;
  const pos = studyWeek.studyPositionAt(studyWeek.w0DateKey(user),
      studyWeek.toDate(after[basis]));
  if (!pos) return null;
  const out = {
    studyWeek: pos.studyWeek, studyDay: pos.studyDay,
    studyWeekBasis: basis, stampedAt: o.now || new Date(),
  };
  await db.collection("users").doc(uid).collection(BRIEF_PR_COLLECTION)
      .doc(docId).set(out, {merge: true});
  return out;
}

// ---------------------------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------------------------

/**
 * @param {string} text
 * @return {boolean}
 */
function isPlaceholder(text) {
  return typeof text !== "string" || text.length === 0 ||
    text.indexOf(PLACEHOLDER_MARK) >= 0;
}

/**
 * Research ID from research_id_map (read only; T12 / T19 issue them).
 * @param {object} db
 * @param {string} uid
 * @return {Promise<?string>}
 */
async function lookupResearchId(db, uid) {
  try {
    const snap = await db.collection("research_id_map").doc(uid).get();
    const rid = snap.exists ? snap.get("researchId") : null;
    return typeof rid === "string" && rid.length > 0 ? rid : null;
  } catch (err) {
    return null;
  }
}

/**
 * One notification to every device of the participant.
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
      console.warn(`weeklyBundle ${kind} send failed for ${userDoc.id}: ` +
        `${err.code || err.message}`);
    }
  }
  return {tokens: tokens.length, delivered};
}

/**
 * Status of every part of a bundle for one participant.
 * @param {object} userRef users/{uid}
 * @param {object} bundle
 * @return {Promise<Object<string, {submitted: boolean, data: ?object}>>}
 */
async function partStates(userRef, bundle) {
  const out = {};
  for (const part of bundle.parts) {
    const snap = await userRef.collection(PART_COLLECTION[part])
        .doc(bundle.id).get();
    const data = snap.exists ? (snap.data() || {}) : null;
    out[part] = {submitted: partSubmitted(part, data), data};
  }
  return out;
}

/**
 * Write the missed record of every part not submitted (one document per
 * part, stamped, status "missed").  Reusable by T35.
 * @param {object} userRef users/{uid}
 * @param {{bundle: object, window: object, w0Key: string, mode: string,
 *     pushedAt: ?Date, now: Date, states: object,
 *     v2: (boolean|undefined)}} p v2: reminders v2 stamp (outsideWindow)
 * @return {Promise<string[]>} parts marked missed
 */
async function markMissedParts(userRef, p) {
  const missed = [];
  for (const part of p.bundle.parts) {
    const s = p.states[part];
    if (s.submitted) continue;
    const stamp = partStamp({
      bundle: p.bundle, window: p.window, w0Key: p.w0Key, mode: p.mode,
      pushedAt: p.pushedAt, submittedAt: null, missed: true, now: p.now,
      v2: p.v2,
    });
    const extra = {status: "missed", missedAt: p.now};
    if (part === PART.DJG) extra.timepoint = p.bundle.id;
    await userRef.collection(PART_COLLECTION[part]).doc(p.bundle.id)
        .set(Object.assign({}, stamp, extra), {merge: true});
    missed.push(part);
  }
  return missed;
}

/**
 * Hourly job: per-person push when a bundle opens, T18's one reminder,
 * the missed marks after the window.  Returns at once with the switch
 * off.  Phase B and pilot participants only (cohort), testers excluded,
 * no arm check.  With weeklyReminderV2Enabled (1020e 二.1 / 二.2) W1–W4
 * use the v2 windows and the 10:00 pushes of v2StepsFor instead (file
 * header); the missed marks follow the v2 windows.
 * @param {object} db admin.firestore()
 * @param {{send: function(object): Promise<string>}} messaging
 * @param {{now: (Date|undefined), log: (function|undefined),
 *     copy: (object|undefined), quiet: (object|undefined),
 *     reminderV2: (boolean|undefined)}} opts
 *     copy overrides the draft text (tests only; keys push, reminder and
 *     the push_copy weekly ids); quiet overrides the quiet-hours config;
 *     reminderV2 overrides the switch (tests only)
 * @return {Promise<object>} counts per outcome
 */
async function dispatchWeeklyBundles(db, messaging, opts) {
  const o = opts || {};
  const now = o.now || new Date();
  const log = o.log || console.log;
  const copy = Object.assign({push: PUSH_BODY, reminder: REMINDER_BODY},
      o.copy || {});
  const read = await readConfig(db);
  const cfg = o.reminderV2 === undefined ? read :
    Object.assign({}, read, {reminderV2: o.reminderV2 === true});
  const counts = {enabled: cfg.enabled};
  const bump = (k) => {
    counts[k] = (counts[k] || 0) + 1;
  };
  if (!cfg.enabled) return counts;
  const quietCfg = o.quiet || await quietHours.readQuietHoursConfig(db);
  if (cfg.reminderV2) counts.reminderV2 = true;
  const todayKey = studyWeek.hkDateKey(now);

  const users = await db.collection("users").get();
  for (const userDoc of users.docs) {
    const u = userDoc.data() || {};
    // A tester is skipped, unless it switched its own arm in 測試員工具
    // (functions/tester_arm.js): then it runs like a pilot participant.
    if (u.isTester === true && !testerArm.isSwitchedTester(u)) continue;
    const mode = scheduleModeFor(u);
    if (!mode) continue;
    const w0Key = studyWeek.w0DateKey(u);
    if (!w0Key) continue;
    const statusRef = db.collection(STATUS_COLLECTION).doc(userDoc.id);
    try {
      const statusSnap = await statusRef.get();
      const st = statusSnap.exists ? (statusSnap.data() || {}) : {};
      const bundles = st.bundles || {};
      const quiet = quietHours.inQuietHours(u, now, quietCfg);
      for (const b of bundlesFor(cfg, mode)) {
        const win = windowFor(b, w0Key, cfg, windowOptsFor(u, cfg));
        const bst = bundles[b.id] || {};
        const useV2 = cfg.reminderV2 && isReminderV2Bundle(b);
        const base = {
          uid: userDoc.id, scheduleMode: mode, w0Date: w0Key,
          updatedAt: now,
        };
        const bundleFields = {
          studyWeek: b.studyWeek, studyDay: b.pushDay,
          windowStart: win.open, windowEnd: win.close,
        };
        const pushedAt = studyWeek.toDate(bst.pushedAt);

        if (useV2 && now < win.close) {
          // 1020e: the v2 push of today, if any (the preview comes the day
          // before the window opens).
          const step = v2StepsFor(b, win)
              .find((s) => s.dateKey === todayKey);
          if (!step || studyWeek.hkHour(now) < V2_PUSH_HOUR) continue;
          if (bst[step.field]) continue;
          if (step.step !== "preview" && now < win.open) continue;
          let open = null;
          if (!step.all) {
            const states = await partStates(userDoc.ref, b);
            open = b.parts.filter((p) => !states[p].submitted);
            if (open.length === 0) continue;
          }
          if (quiet) {
            bump("quiet_hours");
            continue;
          }
          const body = typeof copy[step.copyId] === "string" ?
            copy[step.copyId] : pushCopy.weeklyText(step.copyId, b.bundleWeek);
          if (isPlaceholder(body)) {
            bump("blocked_placeholder");
            continue;
          }
          const kind = step.step === "open" ? "weekly_bundle_push" :
            (step.step === "preview" ? "weekly_bundle_preview" :
              "weekly_bundle_reminder");
          const res = await sendToDevices(messaging, userDoc, body, kind);
          const patch = {};
          patch[b.id] = Object.assign({}, bundleFields);
          patch[b.id][step.field] = now;
          if (step.step === "open") patch[b.id].pushCopyId = step.copyId;
          const rid = st.researchId || await lookupResearchId(db, userDoc.id);
          await statusRef.set(Object.assign({}, base,
              {researchId: rid || null, bundles: patch}), {merge: true});
          const params = {bundle: b.id, studyWeek: b.studyWeek,
            studyDay: b.pushDay, step: step.step, copyId: step.copyId,
            dateKey: todayKey, tokens: res.tokens, delivered: res.delivered};
          if (open) params.parts = open;
          await userDoc.ref.collection("events").add({
            name: `${kind}_sent`,
            params,
            source: "cf_weeklyBundleDispatch",
            timestamp: now,
          });
          bump(step.step === "open" ? "pushed" :
            (step.step === "preview" ? "previewed" : "reminded"));
          continue;
        }

        if (now < win.open) continue;

        if (now >= win.close) {
          if (bst.missedAt ||
              now.getTime() > win.close.getTime() + MISSED_LOOKBACK_MS) {
            continue;
          }
          const states = await partStates(userDoc.ref, b);
          const missed = await markMissedParts(userDoc.ref, {
            bundle: b, window: win, w0Key, mode, pushedAt, now, states,
            v2: useV2,
          });
          const patch = {};
          patch[b.id] = Object.assign({}, bundleFields,
              {missedAt: now, missedParts: missed});
          await statusRef.set(Object.assign({}, base, {bundles: patch}),
              {merge: true});
          await userDoc.ref.collection("events").add({
            name: "weekly_bundle_missed",
            params: {bundle: b.id, studyWeek: b.studyWeek, parts: missed},
            source: "cf_weeklyBundleDispatch",
            timestamp: now,
          });
          bump(missed.length > 0 ? "missed" : "closed_complete");
          continue;
        }

        if (!pushedAt) {
          if (quiet) {
            bump("quiet_hours");
            continue;
          }
          if (isPlaceholder(copy.push)) {
            bump("blocked_placeholder");
            continue;
          }
          const res = await sendToDevices(messaging, userDoc, copy.push,
              "weekly_bundle_push");
          const patch = {};
          patch[b.id] = Object.assign({}, bundleFields, {pushedAt: now});
          const rid = st.researchId || await lookupResearchId(db, userDoc.id);
          await statusRef.set(Object.assign({}, base,
              {researchId: rid || null, bundles: patch}), {merge: true});
          await userDoc.ref.collection("events").add({
            name: "weekly_bundle_push_sent",
            params: {bundle: b.id, studyWeek: b.studyWeek, studyDay: b.pushDay,
              tokens: res.tokens, delivered: res.delivered},
            source: "cf_weeklyBundleDispatch",
            timestamp: now,
          });
          bump("pushed");
          continue;
        }

        if (bst.reminderSentAt) continue;
        const due = pushedAt.getTime() + cfg.reminderHours * 3600 * 1000 -
          REMINDER_SLACK_MS;
        if (now.getTime() < due) continue;
        const states = await partStates(userDoc.ref, b);
        const open = b.parts.filter((p) => !states[p].submitted);
        if (open.length === 0) continue;
        if (quiet) {
          bump("quiet_hours");
          continue;
        }
        if (isPlaceholder(copy.reminder)) {
          bump("blocked_placeholder");
          continue;
        }
        const res = await sendToDevices(messaging, userDoc, copy.reminder,
            "weekly_bundle_reminder");
        const patch = {};
        patch[b.id] = {reminderSentAt: now};
        await statusRef.set(Object.assign({}, base, {bundles: patch}),
            {merge: true});
        await userDoc.ref.collection("events").add({
          name: "weekly_bundle_reminder_sent",
          params: {bundle: b.id, studyWeek: b.studyWeek, parts: open,
            tokens: res.tokens, delivered: res.delivered},
          source: "cf_weeklyBundleDispatch",
          timestamp: now,
        });
        bump("reminded");
      }
    } catch (err) {
      bump("error");
      log(`weeklyBundle ${userDoc.id} failed: ${err.message}`);
    }
  }
  log(`dispatchWeeklyBundles: ${JSON.stringify(counts)}`);
  return counts;
}

// ---------------------------------------------------------------------------
// The old Sunday weekly reminder (weeklySurveyReminder)
// ---------------------------------------------------------------------------

/**
 * With the switch on, the Sunday weekly reminder is no longer a topic
 * broadcast: it goes per person, and not to Phase B / pilot participants
 * (they have the study-week schedule), nor to testers, nor — with T21's
 * gate on — to unregistered accounts.  In practice that leaves nobody
 * once the gate is on; the function exists so the old Phase A path can
 * still be reasoned about.
 * @param {object} user users/{uid} data
 * @param {{gateOn: boolean}} p
 * @return {boolean} send the legacy weekly reminder to this account
 */
function legacyWeeklyReminderTarget(user, p) {
  const u = user || {};
  if (u.isTester === true) return false;
  if (scheduleModeFor(u)) return false;
  if (p && p.gateOn === true) return false;
  return true;
}

module.exports = {
  CONFIG_DOC, STATUS_COLLECTION, SOCIAL_COLLECTION, DJG_COLLECTION,
  WEEKLY_PR_COLLECTION, PGIC_COLLECTION, BRIEF_PR_COLLECTION, PART,
  PART_COLLECTION, MODE_STANDARD, MODE_PILOT, DEFAULTS, SERVER_ONLY_FIELDS,
  MISSED_LOOKBACK_MS, PLACEHOLDER_MARK, PUSH_TITLE, PUSH_BODY, REMINDER_BODY,
  configFromData, readConfig, scheduleModeFor, bundlesFor, bundleById,
  week4CloseFor, windowFor, openBundleAt, referentRangeFor, partSubmitted,
  partStamp, stampPartRecord, stampBriefPr, isPlaceholder, lookupResearchId,
  sendToDevices, partStates, markMissedParts, dispatchWeeklyBundles,
  legacyWeeklyReminderTarget,
  // 1020 G(1) / 1020e 二.1–二.2 reminders v2
  REMINDER_V2_FLAG, V2_PUSH_HOUR, V2_WEEK4_LATEST_CLOSE_DAY,
  isReminderV2Bundle, closingDayKey, week4CloseV2, v2StepsFor,
  emailDayKeyFor, windowOptsFor, reminderV2On, outsideWindowOf,
};
