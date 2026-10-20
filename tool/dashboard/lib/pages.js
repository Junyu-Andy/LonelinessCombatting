/**
 * tool/dashboard/lib/pages.js — the five pages of 1020i 第二版 §2.2, built
 * from load.js reads.  Every page result passes leak_guard before it
 * leaves server.js.
 *
 *   base(g)                    reads every page shares (participants,
 *                              users meta, weekly_status, alerts, schedule
 *                              config); server.js caches it
 *   overview(g, now, base, o)  §2.2 (1): one row per registered person
 *   today(g, now, base, ov)    §2.2 (2): who to WhatsApp / phone, which
 *                              questionnaire closes today unfinished,
 *                              unacknowledged alerts — no arm
 *   person(g, rid, now, base)  §2.2 (3): process data of one person
 *   completion(g, now, base)   §2.2 (4): pooled outcome completion,
 *                              Phase B, hidden below 5, never by arm
 *   exportCsv(g, now, base)    §2.2 (5): per person per week, and per
 *                              day (the App's ops CSV columns)
 *
 * Blinding (2.3(1)): the overview's weekly cells are the Weekly PR part
 * only — process data, as in the App's ops dashboard — so no page puts an
 * outcome next to the arm.  Outcome "done or not" appears only in
 * today().weeklyDue (no arm) and completion() (pooled).
 */
'use strict';

const studyWeek = require('../../../functions/study_week');
const ops = require('../../../functions/ops_dashboard');
const weeklySchedule = require('../../../functions/weekly_schedule');
const assessor = require('../../../functions/assessor');
const outcomeInstruments = require('../../../functions/outcome_instruments');
const processExport = require('../../../functions/process_export');
const L = require('./load');

const COMPANIONS = ops.COMPANIONS;
/** W8 (T35) is not built: the column says so. */
const W8_STATUS = 'not_built';
/** In-App outcome parts shown on the completion page (2.2(4)). */
const COMPLETION_PARTS = [
  {label: 'DJG-ES', part: weeklySchedule.PART.DJG},
  {label: 'PGIC', part: weeklySchedule.PART.PGIC},
  {label: 'S12', part: weeklySchedule.PART.SOCIAL},
];
const COMPLETION_BUNDLES = ['W1', 'W2', 'W3'];
/** W4 paper entries are due once the W4 window (days 25–31) is over. */
const W4_DUE_FROM_DAY = assessor.W4_WINDOW.end + 1;

function zeroCompanions() {
  const o = {total: 0};
  for (const c of COMPANIONS) o[c] = 0;
  return o;
}

function addValid(acc, vs) {
  for (const c of COMPANIONS) {
    const n = (vs && vs[c]) || 0;
    acc[c] += n;
    acc.total += n;
  }
}

/** Pure: the overview row from one person's reads. */
function overviewRow(p, x) {
  const todayDay = x.todayDay;
  const week = studyWeek.studyWeekOf(todayDay);
  const follow = ops.followUpFor(x.days, todayDay);
  const all = zeroCompanions();
  const thisWeek = zeroCompanions();
  let invited = 0;
  let completed = 0;
  for (const d of x.days) {
    addValid(all, d.validSessions);
    if (studyWeek.studyWeekOf(d.studyDay) === week) {
      addValid(thisWeek, d.validSessions);
    }
    invited += d.briefPrInvited || 0;
    completed += d.briefPrCompleted || 0;
  }
  const weekStartDay = week >= 1 ? (week - 1) * 7 + 1 : null;
  const daysSoFar = weekStartDay ? todayDay - weekStartDay + 1 : 0;
  const weeklyPr = {};
  for (const w of L.WEEKLY_PR_WEEKS) {
    weeklyPr[w] = ops.weeklyCellFor(x.weeklyPrDocs[w] || null,
        x.bundles[w] || null);
  }
  return {
    researchId: p.researchId,
    cohort: p.cohort,
    arm: p.arm,
    enrolledDate: p.enrolledDate,
    w0Date: p.w0Date,
    studyDay: todayDay,
    studyWeek: week,
    lastOpenAt: L.iso(x.lastOpen),
    openedToday: follow.openedToday,
    consecutiveUnopenedDays: follow.consecutiveUnopenedDays,
    stage: follow.stage,
    legacyBasis: !x.hasUsageEvents,
    validSessions: {thisWeek, all},
    briefPr: {invited, completed},
    checkIn: {daysThisWeek: x.checkInDaysThisWeek, daysSoFar},
    weeklyPr,
    w8: W8_STATUS,
    pendingAlerts: x.pendingAlerts,
  };
}

/** Unacknowledged alerts of non-testers (or everyone with testers on). */
function pendingAlertsFor(alerts, meta, withTesters) {
  return alerts.filter((a) => !a.acknowledgedAt &&
    (withTesters || (a.isTester !== true &&
      !(meta[a.uid] && meta[a.uid].isTester === true))));
}

function alertRow(a, ridByUid) {
  const created = L.toDate(a.createdAt);
  return {
    alertId: a.id,
    researchId: ridByUid[a.uid] || null,
    level: a.level || null,
    category: a.category || null,
    source: a.source || null,
    sourceGroup: a.sourceGroup || null,
    createdAt: L.iso(created),
    studyDay: typeof a.studyDay === 'number' ? a.studyDay : null,
    acknowledgedAt: L.iso(L.toDate(a.acknowledgedAt)),
    escalatedAt: L.iso(L.toDate(a.escalatedAt)),
    falseAlarm: a.falseAlarm === true,
    isTester: a.isTester === true,
  };
}

async function loadOverviewPerson(g, p, ctx, dayRowsRead) {
  const now = ctx.now;
  const todayKey = studyWeek.hkDateKey(now);
  const todayDay = studyWeek.studyDayOf(p.w0Date, todayKey);
  const week = studyWeek.studyWeekOf(todayDay);
  const weekStartKey = week >= 1 ?
    studyWeek.addDays(p.w0Date, (week - 1) * 7 + 1) : null;
  const dr = dayRowsRead || await L.dayRows(g, p, now);
  const [lastOpen, checkInDays, weeklyPrRows] = await Promise.all([
    L.lastOpen(g, p.uid, dr.usageSince),
    weekStartKey ? L.checkInDoneDays(g, p.uid, weekStartKey) : new Set(),
    g.query('users/{uid}/weekly_pr', {uid: p.uid}).get(),
  ]);
  const weeklyPrDocs = {};
  for (const r of weeklyPrRows) weeklyPrDocs[r.id] = r.data;
  let checkInDaysThisWeek = 0;
  for (const k of checkInDays) {
    if (weekStartKey && k >= weekStartKey && k <= todayKey) {
      checkInDaysThisWeek++;
    }
  }
  return overviewRow(p, {
    todayDay, days: dr.days, hasUsageEvents: dr.hasUsageEvents, lastOpen,
    checkInDaysThisWeek, weeklyPrDocs, bundles: ctx.bundles[p.uid] || {},
    pendingAlerts: ctx.pending.filter((a) => a.uid === p.uid).length,
  });
}

/** Tester rows (2.2(1) checkbox): no registration, so no study day. */
async function loadTesters(g, meta, pending) {
  const uids = Object.keys(meta).filter((u) => meta[u].isTester === true)
      .sort();
  return L.mapLimit(uids, L.PARALLEL, async (uid) => {
    const [lastOpen, valid] = await Promise.all([
      L.lastOpen(g, uid, []),
      g.query('users/{uid}/sessions', {uid}).where('isValid', '==', true)
          .get(),
    ]);
    const all = zeroCompanions();
    for (const r of valid) {
      if (all[r.data.agentId] !== undefined) all[r.data.agentId]++;
      all.total++;
    }
    return {
      testerId: uid.slice(0, 6),
      arm: meta[uid].arm || null,
      lastOpenAt: L.iso(lastOpen),
      validSessions: {all},
      pendingAlerts: pending.filter((a) => a.uid === uid).length,
    };
  });
}

/** The reads every page shares. */
async function base(g) {
  const [people, meta, bundles, alerts, cfg] = await Promise.all([
    L.participants(g), L.usersMeta(g), L.weeklyStatusAll(g), L.alertsAll(g),
    L.scheduleConfig(g),
  ]);
  return {people, meta, bundles, alerts, cfg};
}

/** §2.2 (1). */
async function overview(g, now, b, opts) {
  const withTesters = !!(opts && opts.testers);
  const pending = pendingAlertsFor(b.alerts, b.meta, withTesters);
  const ctx = {now, bundles: b.bundles, pending};
  const rows = await L.mapLimit(b.people, L.PARALLEL,
      (p) => loadOverviewPerson(g, p, ctx));
  const out = {
    today: studyWeek.hkDateKey(now),
    generatedAt: now.toISOString(),
    people: rows,
  };
  if (withTesters) out.testers = await loadTesters(g, b.meta, pending);
  return out;
}

/** §2.2 (2)(c): last reminder day of W1–W4 today, still unfinished —
 * the rule of the 10:00 e-mail (weekly_email.incompleteClosingToday). */
async function weeklyDue(g, people, meta, bundles, cfgRead, now) {
  const cfg = Object.assign({}, cfgRead, {reminderV2: true});
  if (!cfg.enabled) return [];
  const todayKey = studyWeek.hkDateKey(now);
  const out = [];
  for (const p of people) {
    const user = meta[p.uid] || {};
    const st = bundles[p.uid] || {};
    for (const b of weeklySchedule.bundlesFor(cfg,
        weeklySchedule.MODE_STANDARD)) {
      if (!weeklySchedule.isReminderV2Bundle(b)) continue;
      const win = weeklySchedule.windowFor(b, p.w0Date, cfg,
          weeklySchedule.windowOptsFor(user, cfg));
      if (now < win.open || now >= win.close) continue;
      if ((st[b.id] || {}).missedAt) continue;
      if (weeklySchedule.emailDayKeyFor(b, win) !== todayKey) continue;
      const recs = await L.partRecords(g, p.uid, b.parts);
      if (b.parts.every((part) => L.partDone(part, recs[part][b.id]))) {
        continue;
      }
      out.push({researchId: p.researchId,
        studyDay: studyWeek.studyDayOf(p.w0Date, todayKey),
        questionnaireWeek: b.bundleWeek, bundle: b.id});
    }
  }
  return out;
}

/** §2.2 (2); [ov] is overview()'s result (the follow-up stages). */
async function today(g, now, b, ov) {
  const rows = ov.people;
  const follow = ops.dueListFor(rows.map((r) => ({researchId: r.researchId,
    studyPeriod: r.cohort, stage: r.stage,
    consecutiveUnopenedDays: r.consecutiveUnopenedDays})));
  const ridByUid = {};
  for (const p of b.people) ridByUid[p.uid] = p.researchId;
  const pending = pendingAlertsFor(b.alerts, b.meta, false)
      .map((a) => alertRow(a, ridByUid))
      .sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));
  return {
    today: studyWeek.hkDateKey(now),
    generatedAt: now.toISOString(),
    whatsapp: follow.filter((f) => f.stage === 'whatsapp')
        .map((f) => ({researchId: f.researchId,
          consecutiveUnopenedDays: f.consecutiveUnopenedDays})),
    phone: follow.filter((f) => f.stage === 'phone')
        .map((f) => ({researchId: f.researchId,
          consecutiveUnopenedDays: f.consecutiveUnopenedDays})),
    weeklyDue: await weeklyDue(g, b.people, b.meta, b.bundles, b.cfg, now),
    alerts: pending,
  };
}

/** §2.2 (3): one person, process data only. */
async function person(g, researchId, now, b) {
  const p = b.people.find((x) => x.researchId === researchId);
  if (!p) return null;
  const uid = {uid: p.uid};
  const pending = pendingAlertsFor(b.alerts, b.meta, true);
  const dr = await L.dayRows(g, p, now);
  const [row, checkInDays, moodRows, sessions, brief, safety] =
    await Promise.all([
      loadOverviewPerson(g, p, {now, bundles: b.bundles, pending}, dr),
      L.checkInDoneDays(g, p.uid, null),
      g.query('users/{uid}/daily_mood', uid).get(),
      g.query('users/{uid}/sessions', uid).get(),
      g.query('users/{uid}/brief_pr', uid).get(),
      g.query('safety_events').where('uid', '==', p.uid).get(),
    ]);
  const moodDays = new Set(moodRows.map((r) => r.data.date_iso));
  const days = dr.days.map((d) => ({
    dayKey: d.dayKey, studyDay: d.studyDay, basis: d.basis || null,
    opened: d.opened === true, firstOpenAt: d.firstOpenAt || null,
    foregroundMinutes: typeof d.foregroundMinutes === 'number' ?
      d.foregroundMinutes : null,
    validSessions: validOf(d.validSessions),
    briefPrInvited: d.briefPrInvited || 0,
    briefPrCompleted: d.briefPrCompleted || 0,
    checkInDone: checkInDays.has(d.dayKey),
    moodRecorded: moodDays.has(d.dayKey),
  })).reverse();
  const sessionRows = sessions.map((r) => {
    const s = r.data;
    const start = L.toDate(s.startedAt);
    const end = L.toDate(s.endedAt);
    return {
      startedAt: L.iso(start),
      studyDay: start ? studyWeek.studyDayAt(p.w0Date, start) : null,
      agentId: s.agentId || null,
      sessionType: s.sessionType || null,
      durationMinutes: start && end ?
        Math.max(0, Math.round((end - start) / 60000)) : null,
      userMessageCount: typeof s.userMessageCount === 'number' ?
        s.userMessageCount : (typeof s.userTurnCount === 'number' ?
          s.userTurnCount : null),
      isValid: s.isValid === true,
      endReason: s.endReason || null,
      briefPrStatus: s.briefPrStatus || null,
      checkInCompleted: s.checkInCompleted === true,
    };
  }).filter((s) => s.startedAt)
      .sort((a, b) => b.startedAt.localeCompare(a.startedAt));
  const briefRows = brief.map((r) => {
    const b = r.data;
    const at = L.toDate(b.invitedAt) || L.toDate(b.promptedAt);
    return {
      invitedAt: L.iso(at),
      studyDay: typeof b.studyDay === 'number' ? b.studyDay :
        (at ? studyWeek.studyDayAt(p.w0Date, at) : null),
      agentId: b.agentId || null,
      sessionType: b.sessionType || null,
      finalStatus: b.finalStatus || b.status || null,
      ratedAt: L.iso(L.toDate(b.ratedAt) || L.toDate(b.respondedAt)),
      understanding: num(b.understanding),
      validation: num(b.validation),
      caring: num(b.caring),
      insensitivity: num(b.insensitivity),
    };
  }).sort((a, b) => String(b.invitedAt).localeCompare(String(a.invitedAt)));
  const alertByEvent = {};
  for (const a of b.alerts.filter((x) => x.uid === p.uid)) {
    if (a.eventPath) alertByEvent[a.eventPath] = a;
  }
  const ridByUid = {[p.uid]: p.researchId};
  const safetyRows = safety.map((r) => {
    const e = r.data;
    const a = alertByEvent[`safety_events/${r.id}`] || null;
    return {
      createdAt: L.iso(L.toDate(e.createdAt)),
      level: e.level || null,
      category: e.category || null,
      source: e.source || null,
      sourceGroup: processExport.SOURCE_GROUP[e.source] || 'other',
      falseAlarm: e.falseAlarm === true,
      alert: a ? alertRow(a, ridByUid) : null,
    };
  }).sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  return {
    today: studyWeek.hkDateKey(now),
    generatedAt: now.toISOString(),
    person: row,
    days,
    sessions: sessionRows,
    briefPr: briefRows,
    safety: safetyRows,
  };
}

function num(v) {
  return typeof v === 'number' && isFinite(v) ? v : null;
}

/** Per-companion counts with a total, from a day row's map. */
function validOf(vs) {
  const z = zeroCompanions();
  addValid(z, vs);
  return z;
}

/** §2.2 (4): pooled, Phase B only, hidden below assessor.MIN_N. */
async function completion(g, now, b) {
  const meta = b.meta;
  const cfg = b.cfg;
  const entries = await g.query('outcome_entries')
      .where('timepoint', '==', assessor.TIMEPOINT).get();
  const phaseB = b.people.filter((p) => p.studyPeriod === 'B');
  const todayKey = studyWeek.hkDateKey(now);
  const bundles = weeklySchedule.bundlesFor(cfg, weeklySchedule.MODE_STANDARD);
  const rows = [];
  const recsByUid = {};
  await L.mapLimit(phaseB, L.PARALLEL, async (p) => {
    recsByUid[p.uid] = await L.partRecords(g, p.uid,
        COMPLETION_PARTS.map((c) => c.part));
  });
  for (const c of COMPLETION_PARTS) {
    for (const id of COMPLETION_BUNDLES) {
      const bundle = bundles.find((x) => x.id === id);
      if (!cfg.enabled || !bundle || bundle.parts.indexOf(c.part) < 0) {
        rows.push({instrument: c.label, timepoint: id, notScheduled: true});
        continue;
      }
      let n = 0;
      let done = 0;
      for (const p of phaseB) {
        const win = weeklySchedule.windowFor(bundle, p.w0Date, cfg,
            weeklySchedule.windowOptsFor(meta[p.uid] || {}, cfg));
        if (now < win.close) continue;
        n++;
        if (L.partDone(c.part, recsByUid[p.uid][c.part][id])) done++;
      }
      rows.push(assessor.summaryRow(c.label, id, n, done));
    }
  }
  const entered = {};
  for (const r of entries) {
    const e = r.data;
    if (!entered[e.researchId]) entered[e.researchId] = {};
    entered[e.researchId][e.instrument] = true;
  }
  const dueW4 = phaseB.filter((p) =>
    studyWeek.studyDayOf(p.w0Date, todayKey) >= W4_DUE_FROM_DAY);
  for (const inst of Object.keys(outcomeInstruments.INSTRUMENTS)) {
    const done = dueW4.filter((p) => entered[p.researchId] &&
      entered[p.researchId][inst]).length;
    rows.push(Object.assign(assessor.summaryRow(inst, 'W4', dueW4.length,
        done), {paper: true}));
  }
  rows.push({instrument: 'W8', timepoint: 'W8', notBuilt: true});
  return {
    today: todayKey,
    generatedAt: now.toISOString(),
    minN: assessor.MIN_N,
    w4DueFromDay: W4_DUE_FROM_DAY,
    rows,
  };
}

const WEEKLY_CSV_COLUMNS = ['researchId', 'cohort', 'arm', 'studyWeek',
  'fromDay', 'toDay', 'daysCounted', 'openedDays', 'foregroundMinutes',
  'validSessions_siu_yan', 'validSessions_ah_jan_ah_bak',
  'validSessions_tung_tung', 'validSessions_total', 'briefPrInvited',
  'briefPrCompleted', 'checkInDays', 'moodDays', 'basis'];

function csvCell(v) {
  if (v === null || v === undefined) return '';
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** Pure: per-week rows of one person from the per-day rows. */
function weeklyRowsFor(p, days, checkInDays, moodDays) {
  const byWeek = {};
  for (const d of days) {
    const w = studyWeek.studyWeekOf(d.studyDay);
    if (!byWeek[w]) {
      byWeek[w] = {studyWeek: w, fromDay: d.studyDay, toDay: d.studyDay,
        daysCounted: 0, openedDays: 0, foregroundMinutes: null,
        valid: zeroCompanions(), briefPrInvited: 0, briefPrCompleted: 0,
        checkInDays: 0, moodDays: 0, basis: d.basis || null};
    }
    const r = byWeek[w];
    r.fromDay = Math.min(r.fromDay, d.studyDay);
    r.toDay = Math.max(r.toDay, d.studyDay);
    r.daysCounted++;
    if (d.opened) r.openedDays++;
    if (typeof d.foregroundMinutes === 'number') {
      r.foregroundMinutes = (r.foregroundMinutes || 0) + d.foregroundMinutes;
    }
    addValid(r.valid, d.validSessions);
    r.briefPrInvited += d.briefPrInvited || 0;
    r.briefPrCompleted += d.briefPrCompleted || 0;
    if (checkInDays.has(d.dayKey)) r.checkInDays++;
    if (moodDays.has(d.dayKey)) r.moodDays++;
    if (d.basis === 'legacy') r.basis = 'legacy';
  }
  return Object.keys(byWeek).map(Number).sort((a, b) => a - b).map((w) => {
    const r = byWeek[w];
    return [p.researchId, p.cohort, p.arm, r.studyWeek, r.fromDay, r.toDay,
      r.daysCounted, r.openedDays, r.foregroundMinutes, r.valid.siu_yan,
      r.valid.ah_jan_ah_bak, r.valid.tung_tung, r.valid.total,
      r.briefPrInvited, r.briefPrCompleted, r.checkInDays, r.moodDays,
      r.basis];
  });
}

/** §2.2 (5): {weekly, daily} CSV text, process data only. */
async function exportCsv(g, now, b) {
  const people = b.people;
  const entries = await L.mapLimit(people, L.PARALLEL, async (p) => {
    const [dr, checkInDays, moodRows] = await Promise.all([
      L.dayRows(g, p, now),
      L.checkInDoneDays(g, p.uid, null),
      g.query('users/{uid}/daily_mood', {uid: p.uid}).get(),
    ]);
    const moodDays = new Set(moodRows.map((r) => r.data.date_iso));
    return {p, days: dr.days, checkInDays, moodDays};
  });
  const weekly = [WEEKLY_CSV_COLUMNS.join(',')];
  for (const e of entries) {
    for (const row of weeklyRowsFor(e.p, e.days, e.checkInDays, e.moodDays)) {
      weekly.push(row.map(csvCell).join(','));
    }
  }
  const daily = ops.csvFor(entries.map((e) => ({
    person: {researchId: e.p.researchId, studyPeriod: e.p.cohort,
      arm: e.p.arm},
    days: e.days.map((d) => Object.assign({}, d, {
      validSessions: validOf(d.validSessions),
    })),
  })));
  return {
    weekly: weekly.join('\n') + '\n',
    daily,
    people: people.length,
  };
}

module.exports = {
  W8_STATUS, COMPLETION_PARTS, COMPLETION_BUNDLES, W4_DUE_FROM_DAY,
  WEEKLY_CSV_COLUMNS,
  overviewRow, pendingAlertsFor, alertRow, weeklyRowsFor, validOf,
  base, overview, today, person, completion, exportCsv,
};
