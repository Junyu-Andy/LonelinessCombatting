/**
 * T39 (registry C19 / C20; dev-tasks-1014c T39 as narrowed by
 * dev-tasks-1014d) — the operations dashboard for the unblinded
 * researcher (Junyu), server side.  Page 2 ("per person, per day") and
 * page 1 item 7 (today's follow-up list).
 *
 * What the PI needs (1014d 目的): did each participant open the App each
 * day and when first, did each companion get a valid session that day,
 * and who has gone several days without opening — the follow-up stage.
 * Follow-up itself happens outside the App; the dashboard only says who
 * is due.
 *
 * Boundaries (1014c T39 边界):
 *   - process data only, per person and per arm (10/9 item 17);
 *   - NO outcome value, ever: DJG-ES, UCLA-3, PHQ-9, GAD-7, PGIC, the
 *     social-contact probe, continuance, AIMHS — none of their collections
 *     is read here (see OUTCOME_COLLECTIONS, asserted in the tests);
 *   - no allocation sequence, no conversation text;
 *   - `blinded` (the assessors) has no entry: every callable requires
 *     role `unblinded`;
 *   - every open is written to ops_audit_log (who, when, which view).
 *
 * Day rows (1014d 第 2 页第 3 项), one per study day 1..today:
 *   opened          a `foreground` usage event (T40) on that Hong Kong day
 *                   — or, for an account with NO usage events at all (the
 *                   build before T40), any session started that day
 *                   (basis "legacy", flagged 旧构建口径);
 *   firstOpenAt     HH:mm (HK) of the earliest foreground event, else of
 *                   the earliest session start;
 *   foregroundMinutes  sum of foreground stretches, each capped at
 *                   FOREGROUND_CAP_MIN (60); a stretch runs from a
 *                   foreground event to the next event of that person;
 *                   an open stretch (no later event) ends at `now`.  Null
 *                   on the legacy basis ("不可用");
 *   validSessions   isValid sessions ended that day, per companion
 *                   (siu_yan / ah_jan_ah_bak / tung_tung; T25 C16);
 *   briefPr         invitations and completions that day (T25 v3 rows by
 *                   invitedAt; older popup rows by promptedAt).
 *
 * Follow-up (1014d 第 2 页第 4 项):
 *   consecutiveUnopenedDays = days since the last opened day (day 0, the
 *   registration day, never counts as opened); 0 when opened today.
 *   Stage on study days 1–28: 0–2 "none", 3–5 "whatsapp", ≥ 6 "phone";
 *   from day 29 "follow_up_period" (still shows the count); day ≤ 0 "none".
 *
 * 1020d §6 (2)(d): `chapters` on each person row — how many weekly
 * 小篇章 are ready with unresolved `flags` (issues the check still had
 * after the last rewrite) and how many failed.  Counts only: no chapter
 * text, no flag wording, nothing per arm beyond the row's existing `arm`.
 *
 * T35 (W8, handover 1021-W8 四 (4)): `weekly.W8` and `w8Status` are the
 * real completion status (not_yet / open / in_progress / late / done /
 * missed, w8_questionnaire.cellFor) and `w8` the counts behind it (parts
 * submitted of 5, completed at, completed outside the window, and
 * `optionalPart`: whether the optional AIMHS was filled or declined) —
 * read from the server-written
 * weekly_status/{uid}.bundles.W8, never from an answer.
 *
 * 开工方式 (4): `appBuild` — the App version the person's phone last
 * reported (users/{uid}.appBuild: version, build, w8, platform, seenAt;
 * written by the App on every open, lib/core/version/app_build_recorder.
 * dart).  null = no report yet: a build from before the W8 one.  Only
 * that one field of users/{uid} is read (field mask).
 *
 * Storage: ops_daily/{uid}/days/{dayKey} keeps the finished days (server
 * only).  opsDailyRollup (02:10 HKT) writes yesterday for everyone; a
 * callable fills any missing finished day and computes today on demand,
 * reading raw rows only from the earliest missing day on.  Switch
 * app_config/feature_flags.opsDashboardEnabled (OFF unless literally
 * true) gates the callables and the rollup.
 */
"use strict";

const featureFlags = require("./feature_flags");
const studyWeek = require("./study_week");
const randomization = require("./randomization");
const w8 = require("./w8_questionnaire");

const UNBLINDED_ROLE = "unblinded";
const FLAG = "opsDashboardEnabled";
const DAILY_COLLECTION = "ops_daily";
const DAYS_SUBCOLLECTION = "days";
const AUDIT_COLLECTION = "ops_audit_log";
const USAGE_COLLECTION = "usage_events";
const CHAPTER_COLLECTION = "reminiscence_chapters";

/**
 * How many of a person's newest usage rows are scanned for the last open
 * (1020c: reader_* rows sit between foreground rows).
 */
const LAST_USE_SCAN = 60;

/** A single foreground stretch counts at most this many minutes. */
const FOREGROUND_CAP_MIN = 60;
/** Follow-up stages are computed on study days 1..FOLLOW_UP_LAST_DAY. */
const FOLLOW_UP_LAST_DAY = 28;
const WHATSAPP_FROM_DAYS = 3;
const PHONE_FROM_DAYS = 6;
/** Sessions listed on the person page. */
const RECENT_SESSIONS = 20;
/** Weeks shown in the weekly-questionnaire cells. */
const WEEKS = ["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8"];

const COMPANIONS = ["siu_yan", "ah_jan_ah_bak", "tung_tung"];
const SESSION_TYPES = ["free_chat", "check_in", "reminiscence"];
const BRIEF_PR_STATUSES = ["completed", "partially_completed", "skipped",
  "expired", "due_not_invited"];
const SAFETY_LEVELS = ["acute", "moderate", "low"];

/**
 * Collections that hold an outcome value.  Never read by this module —
 * the tests grep the source for them.
 */
const OUTCOME_COLLECTIONS = ["djg_responses", "djg_es", "pgic",
  "social_contact_probes", "outcome_entries", "ucla3", "phq9", "gad7",
  "continuance", "aimhs", "loneliness_probes",
  // T35: the W8 records (w8_questionnaire.js).
  "ucla3_responses", "ci_responses", "lsns6_responses", "aimhs_responses"];

const MS_PER_DAY = 86400000;

/**
 * @param {string} code
 * @return {Error}
 */
function opsError(code) {
  const e = new Error(code);
  e.opsCode = code;
  return e;
}

/**
 * @param {?object} caller {uid, email, role}
 */
function requireUnblinded(caller) {
  if (!caller || caller.role !== UNBLINDED_ROLE) {
    throw opsError("not_unblinded");
  }
}

/**
 * @param {object} db
 */
async function requireFlag(db) {
  if (!(await featureFlags.isFeatureEnabled(db, FLAG))) {
    throw opsError("disabled");
  }
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

/**
 * 1020d: weekly 小篇章 still flagged after the last rewrite, and failed
 * ones.  Counts only.
 * @param {Array<object>} docs reminiscence_chapters doc data
 * @return {{flagged: number, failed: number}}
 */
function chapterCounts(docs) {
  let flagged = 0;
  let failed = 0;
  for (const d of docs || []) {
    if (!d) continue;
    if (d.status === "failed") failed++;
    else if (d.status === "ready" && Array.isArray(d.flags) &&
      d.flags.length > 0) flagged++;
  }
  return {flagged, failed};
}

/**
 * @param {Date} d
 * @return {string} HH:mm in Hong Kong
 */
function hkHHmm(d) {
  const h = (d.getUTCHours() + 8) % 24;
  const m = d.getUTCMinutes();
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

/**
 * Start of a Hong Kong calendar day as a Date.
 * @param {string} key YYYY-MM-DD
 * @return {Date}
 */
function dayStart(key) {
  return studyWeek.hkInstant(key, 0);
}

/**
 * Foreground minutes per Hong Kong day from a person's usage events.
 * Events are {type, clientAt: Date}; sorted here.  A stretch starts at a
 * foreground event and ends at the next event of any type (the App was
 * killed before a background event → the next foreground), or at `now`
 * for the last event when it is a foreground.  Each stretch is capped at
 * FOREGROUND_CAP_MIN and credited to the day the stretch started.
 * Only foreground / background rows count: the 1020c 小讀本 rows
 * (reader_*) happen inside a foreground stretch and must not end it.
 * @param {Array<{type: string, clientAt: Date}>} events
 * @param {Date} now
 * @return {Object<string, number>} dayKey → minutes (rounded)
 */
function foregroundMinutesByDay(events, now) {
  const sorted = events
      .filter((e) => e.type === "foreground" || e.type === "background")
      .sort((a, b) => a.clientAt - b.clientAt);
  const out = {};
  for (let i = 0; i < sorted.length; i++) {
    const e = sorted[i];
    if (e.type !== "foreground") continue;
    const next = sorted[i + 1];
    let end = next ? next.clientAt : now;
    if (end < e.clientAt) end = e.clientAt;
    const minutes = Math.min(FOREGROUND_CAP_MIN,
        (end - e.clientAt) / 60000);
    const key = studyWeek.hkDateKey(e.clientAt);
    out[key] = (out[key] || 0) + minutes;
  }
  for (const k of Object.keys(out)) out[k] = Math.round(out[k]);
  return out;
}

/**
 * The day rows for one person.  Pure.
 * @param {{w0Key: string, todayKey: string, now: Date,
 *     usageEvents: Array<{type: string, clientAt: Date}>,
 *     sessions: Array<{agentId: string, startedAt: ?Date, endedAt: ?Date,
 *         isValid: boolean}>,
 *     briefPr: Array<{invitedAt: ?Date, finalStatus: ?string}>,
 *     hasUsageEvents: boolean, days: Array<string>}} p
 *     `days` = the dayKeys to compute (study day ≥ 1, ≤ today).
 * @return {Array<object>} one row per requested day, in order
 */
function dayRowsFor(p) {
  const minutes = foregroundMinutesByDay(p.usageEvents, p.now);
  const firstFg = {};
  for (const e of p.usageEvents) {
    if (e.type !== "foreground") continue;
    const k = studyWeek.hkDateKey(e.clientAt);
    if (!firstFg[k] || e.clientAt < firstFg[k]) firstFg[k] = e.clientAt;
  }
  const firstSession = {};
  const valid = {};
  for (const s of p.sessions) {
    if (s.startedAt) {
      const k = studyWeek.hkDateKey(s.startedAt);
      if (!firstSession[k] || s.startedAt < firstSession[k]) {
        firstSession[k] = s.startedAt;
      }
    }
    if (s.isValid === true) {
      const at = s.endedAt || s.startedAt;
      if (!at) continue;
      const k = studyWeek.hkDateKey(at);
      if (!valid[k]) valid[k] = {};
      const agent = COMPANIONS.indexOf(s.agentId) >= 0 ? s.agentId : "other";
      valid[k][agent] = (valid[k][agent] || 0) + 1;
    }
  }
  const invited = {};
  const completed = {};
  for (const b of p.briefPr) {
    if (!b.invitedAt) continue;
    const k = studyWeek.hkDateKey(b.invitedAt);
    invited[k] = (invited[k] || 0) + 1;
    if (b.finalStatus === "completed") completed[k] = (completed[k] || 0) + 1;
  }
  const rows = [];
  for (const key of p.days) {
    const legacy = !p.hasUsageEvents;
    const opened = legacy ? !!firstSession[key] : !!firstFg[key];
    const first = legacy ? firstSession[key] : firstFg[key];
    const vs = {};
    for (const c of COMPANIONS) vs[c] = (valid[key] && valid[key][c]) || 0;
    rows.push({
      dayKey: key,
      studyDay: studyWeek.studyDayOf(p.w0Key, key),
      basis: legacy ? "legacy" : "usage",
      opened,
      firstOpenAt: first ? hkHHmm(first) : null,
      foregroundMinutes: legacy ? null : (minutes[key] || 0),
      validSessions: vs,
      briefPrInvited: invited[key] || 0,
      briefPrCompleted: completed[key] || 0,
    });
  }
  return rows;
}

/**
 * Follow-up stage from the day rows (1014d 第 2 页第 4 项).  Pure.
 * @param {Array<{studyDay: number, opened: boolean}>} dayRows days 1..today
 * @param {number} todayDay study day of today
 * @return {{consecutiveUnopenedDays: number, stage: string,
 *     openedToday: boolean}}
 */
function followUpFor(dayRows, todayDay) {
  let lastOpened = 0; // day 0 never counts as opened
  let openedToday = false;
  for (const r of dayRows) {
    if (r.studyDay < 1 || r.studyDay > todayDay) continue;
    if (r.opened) {
      if (r.studyDay > lastOpened) lastOpened = r.studyDay;
      if (r.studyDay === todayDay) openedToday = true;
    }
  }
  const days = todayDay <= 0 ? 0 : Math.max(0, todayDay - lastOpened);
  let stage;
  if (todayDay <= 0) {
    stage = "none";
  } else if (todayDay > FOLLOW_UP_LAST_DAY) {
    stage = "follow_up_period";
  } else if (days >= PHONE_FROM_DAYS) {
    stage = "phone";
  } else if (days >= WHATSAPP_FROM_DAYS) {
    stage = "whatsapp";
  } else {
    stage = "none";
  }
  return {consecutiveUnopenedDays: days, stage, openedToday};
}

/**
 * Today's follow-up list (page 1 item 7): WhatsApp / phone stages, no arm,
 * most days first.  Pure.
 * @param {Array<object>} people person rows
 * @return {Array<object>}
 */
function dueListFor(people) {
  return people
      .filter((p) => p.stage === "whatsapp" || p.stage === "phone")
      .map((p) => ({researchId: p.researchId, studyPeriod: p.studyPeriod,
        consecutiveUnopenedDays: p.consecutiveUnopenedDays, stage: p.stage}))
      .sort((a, b) => b.consecutiveUnopenedDays - a.consecutiveUnopenedDays ||
        a.researchId.localeCompare(b.researchId));
}

/**
 * Weekly questionnaire cell for one week.  Pure.
 * @param {?object} partDoc users/{uid}/weekly_pr/{Wn} data
 * @param {?object} bundleStatus weekly_status.bundles[Wn]
 * @return {string} done / skipped / open / missed / not_yet
 */
function weeklyCellFor(partDoc, bundleStatus) {
  if (partDoc) {
    if (partDoc.status === "completed") return "done";
    if (partDoc.status === "skipped" || partDoc.status === "no_referent") {
      return "skipped";
    }
  }
  if (bundleStatus && bundleStatus.missedAt) return "missed";
  if (bundleStatus && bundleStatus.pushedAt) return "open";
  return "not_yet";
}

/**
 * T35 — the W8 completion detail for the person row.  Pure.  Counts and
 * times only.
 * @param {?object} w8Status weekly_status.bundles.W8
 * @param {number} studyDay today's study day
 * @return {{status: string, partsSubmitted: number, parts: number,
 *     completedAt: ?string, completedOutOfWindow: ?boolean,
 *     optionalPart: ?string}} optionalPart: the optional AIMHS —
 *     submitted / declined / in_progress / null (a state, never a value)
 */
function w8DetailFor(w8Status, studyDay) {
  const s = w8Status || {};
  const at = studyWeek.toDate(s.completedAt);
  return {
    status: w8.cellFor(s, studyDay),
    partsSubmitted: typeof s.partsSubmitted === "number" ?
      s.partsSubmitted : 0,
    parts: w8.PARTS.length,
    completedAt: at ? at.toISOString() : null,
    completedOutOfWindow: typeof s.completedOutOfWindow === "boolean" ?
      s.completedOutOfWindow : null,
    optionalPart: typeof s.aimhs === "string" ? s.aimhs : null,
  };
}

/**
 * 开工方式 (4) — the App version a phone last reported.  Pure.
 * @param {?object} b users/{uid}.appBuild
 * @return {?{version: ?string, build: ?string, w8: boolean,
 *     platform: ?string, seenAt: ?string}} null = never reported (a build
 *     from before the W8 one)
 */
function appBuildOf(b) {
  if (!b || typeof b !== "object") return null;
  const str = (v) => (typeof v === "string" ? v : null);
  const at = studyWeek.toDate(b.seenAt);
  return {version: str(b.version), build: str(b.build), w8: b.w8 === true,
    platform: str(b.platform), seenAt: at ? at.toISOString() : null};
}

/**
 * @param {object} db
 * @param {string} uid
 * @return {Promise<?object>} users/{uid}.appBuild, read alone (field mask)
 */
async function readAppBuild(db, uid) {
  const [snap] = await db.getAll(db.collection("users").doc(uid),
      {fieldMask: ["appBuild"]});
  return snap && snap.exists ? snap.get("appBuild") : null;
}

const CSV_COLUMNS = ["researchId", "studyPeriod", "arm", "studyDay", "dayKey",
  "opened", "firstOpenAt", "foregroundMinutes", "validSessions_siu_yan",
  "validSessions_ah_jan_ah_bak", "validSessions_tung_tung", "briefPrInvited",
  "briefPrCompleted", "basis"];

/**
 * @param {*} v
 * @return {string}
 */
function csvCell(v) {
  if (v === null || v === undefined) return "";
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, "\"\"")}"` : s;
}

/**
 * Per-person-per-day CSV (1014d CSV 导出).  Pure.
 * @param {Array<{person: object, days: Array<object>}>} entries
 * @return {string}
 */
function csvFor(entries) {
  const lines = [CSV_COLUMNS.join(",")];
  for (const e of entries) {
    for (const d of e.days) {
      lines.push([
        e.person.researchId, e.person.studyPeriod, e.person.arm,
        d.studyDay, d.dayKey, d.opened ? 1 : 0, d.firstOpenAt,
        d.foregroundMinutes, d.validSessions.siu_yan,
        d.validSessions.ah_jan_ah_bak, d.validSessions.tung_tung,
        d.briefPrInvited, d.briefPrCompleted, d.basis,
      ].map(csvCell).join(","));
    }
  }
  return lines.join("\n") + "\n";
}

// ---------------------------------------------------------------------------
// Firestore reads
// ---------------------------------------------------------------------------

/**
 * Every registered participant (enrollments with a research ID and W0).
 * @param {object} db
 * @return {Promise<Array<{uid: string, researchId: string,
 *     studyPeriod: string, arm: ?string, w0Date: string}>>}
 */
async function participants(db) {
  const snap = await db.collection(randomization.ENROLL_COLLECTION).get();
  const out = [];
  for (const d of snap.docs) {
    const e = d.data();
    if (typeof e.w0Date !== "string" || !e.researchId) continue;
    out.push({uid: d.id, researchId: e.researchId,
      studyPeriod: e.studyPeriod || null, arm: e.arm || null,
      w0Date: e.w0Date});
  }
  out.sort((a, b) => a.researchId.localeCompare(b.researchId));
  return out;
}

/**
 * @param {object} db
 * @param {string} uid
 * @param {Date} since
 * @return {Promise<Array<{type: string, clientAt: Date}>>}
 */
async function readUsageEvents(db, uid, since) {
  const snap = await db.collection("users").doc(uid)
      .collection(USAGE_COLLECTION).where("clientAt", ">=", since).get();
  const out = [];
  for (const d of snap.docs) {
    const at = studyWeek.toDate(d.get("clientAt"));
    if (!at) continue;
    out.push({type: d.get("type"), clientAt: at});
  }
  return out;
}

/**
 * @param {object} db
 * @param {string} uid
 * @return {Promise<boolean>}
 */
async function hasAnyUsageEvent(db, uid) {
  const snap = await db.collection("users").doc(uid)
      .collection(USAGE_COLLECTION).limit(1).get();
  return !snap.empty;
}

/**
 * @param {object} d sessions row
 * @return {object}
 */
function sessionOf(d) {
  return {
    sessionId: d.sessionId || null,
    agentId: d.agentId || null,
    sessionType: d.sessionType || null,
    startedAt: studyWeek.toDate(d.startedAt),
    endedAt: studyWeek.toDate(d.endedAt),
    endReason: d.endReason || null,
    userMessageCount: typeof d.userMessageCount === "number" ?
      d.userMessageCount : (typeof d.userTurnCount === "number" ?
        d.userTurnCount : null),
    isValid: d.isValid === true,
    briefPrStatus: d.briefPrStatus || null,
  };
}

/**
 * @param {object} db
 * @param {string} uid
 * @param {?Date} since startedAt lower bound (null = all)
 * @return {Promise<Array<object>>}
 */
async function readSessions(db, uid, since) {
  let q = db.collection("users").doc(uid).collection("sessions");
  if (since) q = q.where("startedAt", ">=", since);
  const snap = await q.get();
  return snap.docs.map((d) => sessionOf(d.data()));
}

/**
 * @param {object} d brief_pr row (v3, or the older popup v2)
 * @return {{invitedAt: ?Date, finalStatus: ?string}}
 */
function briefPrOf(d) {
  const invitedAt = studyWeek.toDate(d.invitedAt) ||
    studyWeek.toDate(d.promptedAt);
  let finalStatus = d.finalStatus || null;
  if (!finalStatus && d.status === "completed") finalStatus = "completed";
  if (!finalStatus && d.status === "skipped") finalStatus = "skipped";
  return {invitedAt, finalStatus};
}

/**
 * @param {object} db
 * @param {string} uid
 * @return {Promise<Array<{invitedAt: ?Date, finalStatus: ?string}>>}
 */
async function readBriefPr(db, uid) {
  const snap = await db.collection("users").doc(uid).collection("brief_pr")
      .get();
  return snap.docs.map((d) => briefPrOf(d.data()));
}

/**
 * The finished days already stored for a person.
 * @param {object} db
 * @param {string} uid
 * @return {Promise<Object<string, object>>} dayKey → row
 */
async function readStoredDays(db, uid) {
  const snap = await db.collection(DAILY_COLLECTION).doc(uid)
      .collection(DAYS_SUBCOLLECTION).get();
  const out = {};
  for (const d of snap.docs) out[d.id] = d.data();
  return out;
}

/**
 * The day rows for one person, days 1..today: stored rows for finished
 * days, the missing finished days computed and stored, today computed.
 * Raw rows are read only from the earliest day that has to be computed.
 * @param {object} db
 * @param {{uid: string, w0Date: string}} person
 * @param {Date} now
 * @return {Promise<{days: Array<object>, hasUsageEvents: boolean}>}
 */
async function personDayRows(db, person, now) {
  const todayKey = studyWeek.hkDateKey(now);
  const todayDay = studyWeek.studyDayOf(person.w0Date, todayKey);
  if (todayDay < 1) return {days: [], hasUsageEvents: false};
  const stored = await readStoredDays(db, person.uid);
  const keys = [];
  for (let d = 1; d <= todayDay; d++) {
    keys.push(studyWeek.addDays(person.w0Date, d));
  }
  const toCompute = keys.filter((k) => k === todayKey || !stored[k]);
  const hasUsageEvents = await hasAnyUsageEvent(db, person.uid);
  const computed = {};
  if (toCompute.length) {
    // One day of slack before the earliest day so a stretch or a session
    // that crosses midnight is seen.
    const since = new Date(dayStart(toCompute[0]).getTime() - MS_PER_DAY);
    const [usageEvents, sessions, briefPr] = await Promise.all([
      hasUsageEvents ? readUsageEvents(db, person.uid, since) : [],
      readSessions(db, person.uid, since),
      readBriefPr(db, person.uid),
    ]);
    const rows = dayRowsFor({w0Key: person.w0Date, todayKey, now,
      usageEvents, sessions, briefPr, hasUsageEvents, days: toCompute});
    for (const r of rows) computed[r.dayKey] = r;
    const batch = db.batch();
    let writes = 0;
    for (const r of rows) {
      if (r.dayKey === todayKey) continue;
      batch.set(db.collection(DAILY_COLLECTION).doc(person.uid)
          .collection(DAYS_SUBCOLLECTION).doc(r.dayKey),
      Object.assign({}, r, {uid: person.uid, storedAt: now}));
      writes++;
    }
    if (writes) await batch.commit();
  }
  const days = keys.map((k) => computed[k] || stored[k]);
  return {days, hasUsageEvents};
}

/**
 * The person row (page 2, one line per person) plus the day rows and the
 * recent sessions.
 * @param {object} db
 * @param {object} person participants() entry
 * @param {Date} now
 * @param {{withDetail: boolean}} opts
 * @return {Promise<{person: object, days: Array<object>,
 *     recentSessions: Array<object>}>}
 */
async function loadPerson(db, person, now, opts) {
  const o = opts || {};
  const todayKey = studyWeek.hkDateKey(now);
  const todayDay = studyWeek.studyDayOf(person.w0Date, todayKey);
  const {days, hasUsageEvents} = await personDayRows(db, person, now);
  const follow = followUpFor(days, todayDay);
  const userRef = db.collection("users").doc(person.uid);

  const [sessions, briefPr, weeklyParts, statusSnap, moodSnap, memSnap,
    sttSnap, voiceFailSnap, safetySnap, alertSnap, lastUsageSnap,
    chapterSnap, appBuild] =
    await Promise.all([
      readSessions(db, person.uid, null),
      readBriefPr(db, person.uid),
      Promise.all(WEEKS.map((w) => userRef.collection("weekly_pr").doc(w)
          .get())),
      db.collection("weekly_status").doc(person.uid).get(),
      userRef.collection("daily_mood").get(),
      person.arm === "A" ? userRef.collection("mem_facts")
          .where("status", "==", "active").get() : null,
      db.collection("stt_usage").where("uid", "==", person.uid).get(),
      userRef.collection("events")
          .where("name", "==", "voice_transcription_failed").get(),
      db.collection("safety_events").where("uid", "==", person.uid).get(),
      db.collection("pi_alerts").where("uid", "==", person.uid).get(),
      // Single-field order only (no composite index needed): the latest
      // rows, the newest foreground among them is the last open.  1020c:
      // a reading session adds reader_* rows after its foreground, so
      // look further back than the 10 rows that were enough before.
      userRef.collection(USAGE_COLLECTION).orderBy("clientAt", "desc")
          .limit(LAST_USE_SCAN).get(),
      userRef.collection(CHAPTER_COLLECTION).get(),
      readAppBuild(db, person.uid),
    ]);

  const byCompanion = {};
  for (const c of COMPANIONS) byCompanion[c] = 0;
  const byType = {};
  for (const t of SESSION_TYPES) byType[t] = 0;
  let validTotal = 0;
  let lastSession = null;
  for (const s of sessions) {
    if (s.startedAt && (!lastSession || s.startedAt > lastSession)) {
      lastSession = s.startedAt;
    }
    if (!s.isValid) continue;
    validTotal++;
    if (byCompanion[s.agentId] !== undefined) byCompanion[s.agentId]++;
    if (byType[s.sessionType] !== undefined) byType[s.sessionType]++;
  }

  const briefCounts = {invited: 0};
  for (const st of BRIEF_PR_STATUSES) briefCounts[st] = 0;
  for (const b of briefPr) {
    if (b.invitedAt) briefCounts.invited++;
    if (b.finalStatus && briefCounts[b.finalStatus] !== undefined) {
      briefCounts[b.finalStatus]++;
    }
  }

  const bundles = statusSnap.exists ? (statusSnap.get("bundles") || {}) : {};
  // T35: W8 from the server's completion status, not from any record.
  const w8Detail = w8DetailFor(bundles.W8, todayDay);
  const weekly = {};
  WEEKS.forEach((w, i) => {
    const part = weeklyParts[i].exists ? weeklyParts[i].data() : null;
    weekly[w] = w === "W8" ? w8Detail.status :
      weeklyCellFor(part, bundles[w]);
  });

  const moodDays = {};
  for (const d of moodSnap.docs) {
    const key = d.get("date_iso");
    if (typeof key === "string") moodDays[key] = true;
  }

  let memory = null;
  if (memSnap) {
    memory = {shared: 0, private: 0};
    for (const d of memSnap.docs) {
      if (d.get("layer") === "shared") memory.shared++;
      else memory.private++;
    }
  }

  // 1020e 二.9: `falseAlarm` = events the researcher marked 誤觸 (they
  // still count under their level).
  const safety = {pendingAck: 0, falseAlarm: 0};
  for (const l of SAFETY_LEVELS) safety[l] = 0;
  for (const d of safetySnap.docs) {
    const l = d.get("level");
    if (safety[l] !== undefined) safety[l]++;
    if (d.get("falseAlarm") === true) safety.falseAlarm++;
  }
  for (const d of alertSnap.docs) {
    if (!d.get("acknowledgedAt")) safety.pendingAck++;
  }

  const chapters = chapterCounts(chapterSnap.docs.map((d) => d.data()));

  let lastUse = lastSession;
  for (const d of lastUsageSnap.docs) {
    if (d.get("type") !== "foreground") continue;
    const at = studyWeek.toDate(d.get("clientAt"));
    if (at && (!lastUse || at > lastUse)) lastUse = at;
    break;
  }

  const row = {
    researchId: person.researchId,
    studyPeriod: person.studyPeriod,
    arm: person.arm,
    w0Date: person.w0Date,
    studyDay: todayDay,
    lastUseAt: lastUse ? lastUse.toISOString() : null,
    openedToday: follow.openedToday,
    consecutiveUnopenedDays: follow.consecutiveUnopenedDays,
    stage: follow.stage,
    legacyBasis: !hasUsageEvents,
    validSessions: {total: validTotal, byCompanion, byType},
    briefPr: briefCounts,
    weekly,
    moodDays: Object.keys(moodDays).length,
    memory,
    voice: {uses: sttSnap.size, failures: voiceFailSnap.size},
    safety,
    chapters,
    w8Status: w8Detail.status,
    w8: w8Detail,
    appBuild: appBuildOf(appBuild),
    debriefStatus: "not_built",
  };

  let recentSessions = [];
  if (o.withDetail) {
    recentSessions = sessions
        .filter((s) => s.startedAt)
        .sort((a, b) => b.startedAt - a.startedAt)
        .slice(0, RECENT_SESSIONS)
        .map((s) => ({
          startedAt: s.startedAt.toISOString(),
          agentId: s.agentId,
          sessionType: s.sessionType,
          userMessageCount: s.userMessageCount,
          durationMinutes: s.endedAt ?
            Math.max(0, Math.round((s.endedAt - s.startedAt) / 60000)) : null,
          endReason: s.endReason,
          isValid: s.isValid,
          briefPrStatus: s.briefPrStatus,
        }));
  }
  return {person: row, days, recentSessions};
}

/**
 * One ops_audit_log row (server only).  Never throws.
 * @param {object} db
 * @param {object} row
 * @param {Date} at
 */
async function audit(db, row, at) {
  try {
    await db.collection(AUDIT_COLLECTION).add(Object.assign({at}, row));
  } catch (err) {
    console.error("ops_audit_log write failed:", err && err.message);
  }
}

// ---------------------------------------------------------------------------
// Entry points (callables / schedule)
// ---------------------------------------------------------------------------

/**
 * Page 2 table + page 1 item 7.
 * @param {object} db
 * @param {object} caller
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{today: string, people: Array<object>,
 *     dueList: Array<object>}>}
 */
async function people(db, caller, opts) {
  requireUnblinded(caller);
  await requireFlag(db);
  const now = (opts && opts.now) || new Date();
  const list = await participants(db);
  const rows = [];
  for (const p of list) {
    rows.push((await loadPerson(db, p, now, {withDetail: false})).person);
  }
  await audit(db, {type: "open_people", by: caller.uid,
    count: rows.length}, now);
  return {today: studyWeek.hkDateKey(now), people: rows,
    dueList: dueListFor(rows)};
}

/**
 * One person: the row, the day grid, the recent sessions.
 * @param {object} db
 * @param {object} caller
 * @param {{researchId: *}} input
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<object>}
 */
async function person(db, caller, input, opts) {
  requireUnblinded(caller);
  await requireFlag(db);
  const now = (opts && opts.now) || new Date();
  const rid = randomization.normaliseResearchId(input && input.researchId);
  if (!rid) throw opsError("invalid_research_id");
  const p = (await participants(db)).find((x) => x.researchId === rid);
  if (!p) throw opsError("unknown_research_id");
  const out = await loadPerson(db, p, now, {withDetail: true});
  await audit(db, {type: "open_person", by: caller.uid, researchId: rid},
      now);
  return Object.assign({today: studyWeek.hkDateKey(now)}, out);
}

/**
 * CSV of per-person-per-day rows: one person, or everyone.
 * @param {object} db
 * @param {object} caller
 * @param {{researchId: *}} input
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{filename: string, csv: string, rows: number}>}
 */
async function csv(db, caller, input, opts) {
  requireUnblinded(caller);
  await requireFlag(db);
  const now = (opts && opts.now) || new Date();
  const rid = input && input.researchId ?
    randomization.normaliseResearchId(input.researchId) : null;
  if (input && input.researchId && !rid) throw opsError("invalid_research_id");
  let list = await participants(db);
  if (rid) {
    list = list.filter((x) => x.researchId === rid);
    if (!list.length) throw opsError("unknown_research_id");
  }
  const entries = [];
  for (const p of list) {
    entries.push(await loadPerson(db, p, now, {withDetail: false}));
  }
  const text = csvFor(entries);
  const today = studyWeek.hkDateKey(now);
  await audit(db, {type: "export_csv", by: caller.uid,
    researchId: rid || null, people: list.length}, now);
  return {filename: `ops_daily_${rid || "all"}_${today}.csv`, csv: text,
    rows: entries.reduce((n, e) => n + e.days.length, 0)};
}

/**
 * Daily rollup: store yesterday (and any missing finished day) for every
 * participant.  Switch off → nothing.
 * @param {object} db
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{people: number, skipped: boolean}>}
 */
async function rollup(db, opts) {
  if (!(await featureFlags.isFeatureEnabled(db, FLAG))) {
    return {people: 0, skipped: true};
  }
  const now = (opts && opts.now) || new Date();
  const list = await participants(db);
  for (const p of list) {
    try {
      await personDayRows(db, p, now);
    } catch (err) {
      console.error("ops rollup failed", {uid: p.uid, err: String(err)});
    }
  }
  return {people: list.length, skipped: false};
}

module.exports = {
  FLAG, DAILY_COLLECTION, DAYS_SUBCOLLECTION, AUDIT_COLLECTION,
  FOREGROUND_CAP_MIN, FOLLOW_UP_LAST_DAY, WHATSAPP_FROM_DAYS, PHONE_FROM_DAYS,
  COMPANIONS, SESSION_TYPES, WEEKS, OUTCOME_COLLECTIONS, CSV_COLUMNS,
  foregroundMinutesByDay, dayRowsFor, followUpFor, dueListFor, weeklyCellFor,
  chapterCounts, w8DetailFor, appBuildOf,
  csvFor, participants, personDayRows, loadPerson,
  people, person, csv, rollup,
};
