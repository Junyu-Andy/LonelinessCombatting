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
 * blocked_placeholder, like T18).  Quiet hours (functions/quiet_hours.js)
 * postpone a push to the next tick.
 */

"use strict";

const studyWeek = require("./study_week");
const quietHours = require("./quiet_hours");

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
 * @return {object} merged config
 */
function configFromData(data) {
  const d = data || {};
  const num = (v, def, min) =>
    (typeof v === "number" && isFinite(v) && v >= min ? Math.floor(v) : def);
  return {
    enabled: d.weeklyScheduleV2Enabled === true,
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
 * @return {Promise<object>} configFromData() of app_config/phase_b
 */
async function readConfig(db) {
  try {
    const snap = await db.doc(CONFIG_DOC).get();
    return configFromData(snap.exists ? snap.data() : {});
  } catch (err) {
    console.warn("phase_b config read failed; weekly schedule off",
        {err: err && err.message});
    return configFromData({});
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
  const u = user || {};
  if (u.cohort === "phase_b") return MODE_STANDARD;
  if (u.cohort === "pilot") return MODE_STANDARD;
  return null;
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
 * The window of a bundle for one participant.
 * @param {object} bundle bundlesFor() element
 * @param {string} w0Key YYYY-MM-DD
 * @param {object} cfg
 * @param {{w4VisitDate: (string|undefined)}} opts
 * @return {{open: Date, close: Date, pushDateKey: string}} [open, close)
 */
function windowFor(bundle, w0Key, cfg, opts) {
  const o = opts || {};
  const pushDateKey = studyWeek.addDays(w0Key, bundle.pushDay);
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
 * The server-written fields of a part record.
 * @param {{bundle: object, window: object, w0Key: string, mode: string,
 *     pushedAt: ?Date, submittedAt: ?Date, missed: boolean, now: Date}} p
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
  return out;
}

/**
 * Firestore trigger body for weekly_pr / pgic / social_contact_probes /
 * djg_responses: stamp the study-week fields on a record that carries
 * `bundle` (W1…W7) and is not stamped yet.  Reusable by T35 for the W8
 * bundle.  Idempotent: a stamped record returns null.
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
  if (!after || after.studyWeek !== undefined) return null;
  const bundleId = typeof after.bundle === "string" ? after.bundle :
    (collection === DJG_COLLECTION ? docId : null);
  if (!bundleId || !/^W\d+$/.test(bundleId)) return null;
  const now = o.now || new Date();
  const cfg = await readConfig(db);
  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.exists ? userSnap.data() : null;
  const mode = scheduleModeFor(user);
  const w0Key = studyWeek.w0DateKey(user);
  if (!mode || !w0Key) return null;
  const bundle = bundleById(cfg, mode, bundleId);
  if (!bundle) return null;
  const statusSnap = await db.collection(STATUS_COLLECTION).doc(uid).get();
  const st = statusSnap.exists ? (statusSnap.data() || {}) : {};
  const bst = (st.bundles || {})[bundleId] || {};
  const win = windowFor(bundle, w0Key, cfg);
  const submittedAt = studyWeek.toDate(after.submittedAt) ||
    studyWeek.toDate(after.answeredAt) || studyWeek.toDate(after.respondedAt);
  const out = partStamp({
    bundle, window: win, w0Key, mode,
    pushedAt: studyWeek.toDate(bst.pushedAt),
    submittedAt, missed: after.status === "missed", now,
  });
  await db.collection("users").doc(uid).collection(collection).doc(docId)
      .set(out, {merge: true});
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
 *     pushedAt: ?Date, now: Date, states: object}} p
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
 * no arm check.
 * @param {object} db admin.firestore()
 * @param {{send: function(object): Promise<string>}} messaging
 * @param {{now: (Date|undefined), log: (function|undefined),
 *     copy: (object|undefined), quiet: (object|undefined)}} opts
 *     copy overrides the draft text (tests only); quiet overrides the
 *     quiet-hours config
 * @return {Promise<object>} counts per outcome
 */
async function dispatchWeeklyBundles(db, messaging, opts) {
  const o = opts || {};
  const now = o.now || new Date();
  const log = o.log || console.log;
  const copy = Object.assign({push: PUSH_BODY, reminder: REMINDER_BODY},
      o.copy || {});
  const cfg = await readConfig(db);
  const counts = {enabled: cfg.enabled};
  const bump = (k) => {
    counts[k] = (counts[k] || 0) + 1;
  };
  if (!cfg.enabled) return counts;
  const quietCfg = o.quiet || await quietHours.readQuietHoursConfig(db);

  const users = await db.collection("users").get();
  for (const userDoc of users.docs) {
    const u = userDoc.data() || {};
    if (u.isTester === true) continue;
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
        const win = windowFor(b, w0Key, cfg);
        if (now < win.open) continue;
        const bst = bundles[b.id] || {};
        const base = {
          uid: userDoc.id, scheduleMode: mode, w0Date: w0Key,
          updatedAt: now,
        };
        const bundleFields = {
          studyWeek: b.studyWeek, studyDay: b.pushDay,
          windowStart: win.open, windowEnd: win.close,
        };
        const pushedAt = studyWeek.toDate(bst.pushedAt);

        if (now >= win.close) {
          if (bst.missedAt ||
              now.getTime() > win.close.getTime() + MISSED_LOOKBACK_MS) {
            continue;
          }
          const states = await partStates(userDoc.ref, b);
          const missed = await markMissedParts(userDoc.ref, {
            bundle: b, window: win, w0Key, mode, pushedAt, now, states,
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
};
