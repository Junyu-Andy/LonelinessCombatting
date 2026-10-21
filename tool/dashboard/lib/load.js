/**
 * tool/dashboard/lib/load.js — reads for each dashboard page, through
 * guarded_db only (field masks, no writes), and the rules from
 * functions/ (the same code the App's researcher pages run):
 *
 *   study day / week        functions/study_week.js
 *   day rows, follow-up     functions/ops_dashboard.js (pure functions
 *                           only: its loaders write ops_daily and read
 *                           whole documents, so they are not used here)
 *   questionnaire bundles,  functions/weekly_schedule.js (bundlesFor,
 *   windows, part done      windowFor, partSubmitted)
 *   check-in done           functions/daily_checkin_push.rowCompletes
 *
 * Day rows: the finished days the server already stored in
 * ops_daily/{uid}/days (opsDailyRollup, 02:10) are read as they are; the
 * missing days and today are computed from raw rows, read only from the
 * earliest missing day on — like ops_dashboard.personDayRows, minus the
 * write.
 */
'use strict';

const studyWeek = require('../../../functions/study_week');
const ops = require('../../../functions/ops_dashboard');
const weeklySchedule = require('../../../functions/weekly_schedule');
const checkIn = require('../../../functions/daily_checkin_push');
const studyPeriod = require('../../../functions/study_period');

const MS_PER_DAY = 86400000;
/** Same scan depth as the server's last-open lookup. */
const LAST_USE_SCAN = 60;
const CHECK_IN_EVENT = 'check_in_submitted';
const PARALLEL = 6;

function toDate(v) {
  return studyWeek.toDate(v);
}

function iso(d) {
  return d ? d.toISOString() : null;
}

/** Run fn over items, at most n at a time, keeping the order. */
async function mapLimit(items, n, fn) {
  const out = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i], i);
    }
  }
  const workers = [];
  for (let k = 0; k < Math.min(n, items.length); k++) workers.push(worker());
  await Promise.all(workers);
  return out;
}

/** RCT / PB / PILOT from the research ID prefix (enrollments can't tell
 * RCT- from PB-: both are studyPeriod "B"). */
function cohortOf(researchId) {
  const p = studyPeriod.periodForResearchId(researchId);
  return p ? p.prefix.replace(/-$/, '') : null;
}

/**
 * Registered participants (testers cannot be registered).
 * @return {Promise<Array<object>>}
 */
async function participants(g) {
  const rows = await g.query('enrollments').get();
  const out = [];
  for (const r of rows) {
    const e = r.data;
    if (typeof e.w0Date !== 'string' || !e.researchId) continue;
    const enrolledAt = toDate(e.enrolledAt);
    out.push({
      uid: r.id,
      researchId: e.researchId,
      studyPeriod: e.studyPeriod || null,
      cohort: cohortOf(e.researchId),
      arm: e.arm || null,
      w0Date: e.w0Date,
      enrolledDate: enrolledAt ? studyWeek.hkDateKey(enrolledAt) : null,
    });
  }
  out.sort((a, b) => a.researchId.localeCompare(b.researchId));
  return out;
}

/** users/{uid} meta by uid: isTester, w4RecordedOn (and arm, used for
 * tester rows only). */
async function usersMeta(g) {
  const rows = await g.query('users').get();
  const out = {};
  for (const r of rows) out[r.id] = r.data;
  return out;
}

async function weeklyStatusAll(g) {
  const rows = await g.query('weekly_status').get();
  const out = {};
  for (const r of rows) out[r.id] = r.data.bundles || {};
  return out;
}

async function alertsAll(g) {
  const rows = await g.query('pi_alerts').get();
  return rows.map((r) => Object.assign({id: r.id}, r.data));
}

async function scheduleConfig(g) {
  const [phaseB, flags] = await Promise.all([
    g.config('app_config/phase_b'),
    g.config('app_config/feature_flags'),
  ]);
  return weeklySchedule.configFromData(phaseB, flags);
}

/**
 * Day rows 1..today for one person, without writing anything.
 * @return {Promise<{days: Array<object>, hasUsageEvents: boolean,
 *     usageSince: Array<object>}>}
 */
async function dayRows(g, person, now) {
  const todayKey = studyWeek.hkDateKey(now);
  const todayDay = studyWeek.studyDayOf(person.w0Date, todayKey);
  if (todayDay < 1) return {days: [], hasUsageEvents: false, usageSince: []};
  const uid = {uid: person.uid};
  const [storedRows, anyUsage] = await Promise.all([
    g.query('ops_daily/{uid}/days', uid).get(),
    g.query('users/{uid}/usage_events', uid).limit(1).get(),
  ]);
  const stored = {};
  for (const r of storedRows) stored[r.id] = r.data;
  const hasUsageEvents = anyUsage.length > 0;
  const keys = [];
  for (let d = 1; d <= todayDay; d++) {
    keys.push(studyWeek.addDays(person.w0Date, d));
  }
  const toCompute = keys.filter((k) => k === todayKey || !stored[k]);
  // One day of slack so a stretch or a session crossing midnight is seen.
  const since = new Date(studyWeek.hkInstant(toCompute[0], 0).getTime() -
    MS_PER_DAY);
  const [usage, sessions, invited, prompted] = await Promise.all([
    hasUsageEvents ? g.query('users/{uid}/usage_events', uid)
        .where('clientAt', '>=', since).get() : [],
    g.query('users/{uid}/sessions', uid).where('startedAt', '>=', since).get(),
    g.query('users/{uid}/brief_pr', uid).where('invitedAt', '>=', since).get(),
    g.query('users/{uid}/brief_pr', uid).where('promptedAt', '>=', since)
        .get(),
  ]);
  const usageSince = usage.map((r) => ({type: r.data.type,
    clientAt: toDate(r.data.clientAt)})).filter((e) => e.clientAt);
  const briefById = {};
  for (const r of invited.concat(prompted)) briefById[r.id] = r.data;
  const briefPr = Object.keys(briefById).map((id) => {
    const d = briefById[id];
    let finalStatus = d.finalStatus || null;
    if (!finalStatus && (d.status === 'completed' || d.status === 'skipped')) {
      finalStatus = d.status;
    }
    return {invitedAt: toDate(d.invitedAt) || toDate(d.promptedAt),
      finalStatus};
  });
  const rows = ops.dayRowsFor({
    w0Key: person.w0Date, todayKey, now, usageEvents: usageSince,
    sessions: sessions.map((r) => ({
      agentId: r.data.agentId || null,
      startedAt: toDate(r.data.startedAt),
      endedAt: toDate(r.data.endedAt),
      isValid: r.data.isValid === true,
    })),
    briefPr, hasUsageEvents, days: toCompute,
  });
  const computed = {};
  for (const r of rows) computed[r.dayKey] = r;
  const days = keys.map((k) => {
    const d = computed[k] || stored[k];
    return Object.assign({}, d, {dayKey: k,
      studyDay: studyWeek.studyDayOf(person.w0Date, k)});
  });
  return {days, hasUsageEvents, usageSince};
}

/** Newest foreground (or, with no usage events, newest session start). */
async function lastOpen(g, uid, usageSince) {
  let last = null;
  for (const e of usageSince) {
    if (e.type === 'foreground' && (!last || e.clientAt > last)) {
      last = e.clientAt;
    }
  }
  const sessions = await g.query('users/{uid}/sessions', {uid})
      .orderBy('startedAt', 'desc').limit(1).get();
  const lastSession = sessions.length ? toDate(sessions[0].data.startedAt) :
    null;
  if (!last) {
    const scan = await g.query('users/{uid}/usage_events', {uid})
        .orderBy('clientAt', 'desc').limit(LAST_USE_SCAN).get();
    for (const r of scan) {
      if (r.data.type !== 'foreground') continue;
      last = toDate(r.data.clientAt);
      break;
    }
  }
  if (lastSession && (!last || lastSession > last)) last = lastSession;
  return last;
}

/** Hong Kong dates (from sinceKey on) with a finished check-in. */
async function checkInDoneDays(g, uid, sinceKey) {
  let q = g.query('users/{uid}/check_in_responses', {uid});
  if (sinceKey) q = q.where('date_iso', '>=', sinceKey);
  const [rows, events] = await Promise.all([
    q.get(),
    g.query('users/{uid}/events', {uid}).where('name', '==', CHECK_IN_EVENT)
        .get(),
  ]);
  const done = new Set();
  for (const r of rows) {
    if (checkIn.rowCompletes(r.data, r.data.date_iso)) done.add(r.data.date_iso);
  }
  for (const r of events) {
    const at = toDate(r.data.timestamp);
    if (!at) continue;
    const k = studyWeek.hkDateKey(at);
    if (!sinceKey || k >= sinceKey) done.add(k);
  }
  return done;
}

/** Part records of one person, masked: {collection: {Wn: data}}. */
async function partRecords(g, uid, parts) {
  const out = {};
  await Promise.all(parts.map(async (part) => {
    const coll = weeklySchedule.PART_COLLECTION[part];
    const rows = await g.query(`users/{uid}/${coll}`, {uid}).get();
    out[part] = {};
    for (const r of rows) out[part][r.id] = r.data;
  }));
  return out;
}

/**
 * Done or not from the masked part record (never the answer), by the
 * server's rule, weekly_schedule.partSubmitted: DJG-ES / S12 submitted,
 * Weekly PR completed / skipped / no_referent.  PGIC: the server checks
 * that the answer `value` is a number; the dashboard never reads it.
 * The App writes `value` and `answeredAt` in the same write
 * (pgic_page.dart) and the missed mark writes neither, so `answeredAt`
 * gives the same result.
 */
function partDone(part, data) {
  if (!data) return false;
  if (part === weeklySchedule.PART.PGIC) return !!toDate(data.answeredAt);
  return weeklySchedule.partSubmitted(part, data);
}

module.exports = {
  MS_PER_DAY, PARALLEL, CHECK_IN_EVENT,
  toDate, iso, mapLimit, cohortOf, participants, usersMeta, weeklyStatusAll,
  alertsAll, scheduleConfig, dayRows, lastOpen, checkInDoneDays,
  partRecords, partDone,
};
