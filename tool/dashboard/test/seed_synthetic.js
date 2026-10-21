#!/usr/bin/env node
/**
 * tool/dashboard/test/seed_synthetic.js — synthetic participants for the
 * dashboard's emulator test and for `start.sh --demo`.  EMULATOR ONLY:
 * refuses to run without FIRESTORE_EMULATOR_HOST.
 *
 * Every answer, free text, allocation field and text-like field carries
 * the marker SENTINEL (or the number SENTINEL_NUM): the test checks that
 * neither ever reaches the dashboard — not even its memory (field
 * masks), let alone a page or a CSV.
 *
 * Mood values (decision 0072: shown on the person page) are 1–5
 * (moodValues); seed(db, admin, {moodBase}) adds moodBase to each, so the
 * emulator test can trace them: on the person page, nowhere else.
 *
 * "Today" is NOW = 2026-11-20 10:00 Hong Kong.  Weekly questionnaires
 * (S12 on: W1–W3 have 4 parts, W4 3, W5–W7 PGIC only):
 *   RCT-001 A day 30  opens daily; W1–W3 done, W4 open 0/3; ops_daily
 *                     stored for days 1–28 (day 29 missing → computed);
 *                     acknowledged alert
 *   RCT-002 B day 16  last opened day 12 → WhatsApp; W1 done; W2 closes
 *                     today with PGIC missing (3/4) → (c); unacknowledged
 *                     acute alert
 *   RCT-003 A day 12  last opened day 5 → phone; W1 Weekly PR only (1/4)
 *   RCT-004 B day 40  follow-up period; W1, W2 done, W3 missed; W4 visit
 *                     recorded day 30 (W4 closed, missed); W4 paper
 *   RCT-005 A day 35  W1, W3 done, W2 missed, W4 2/3, W5 open
 *   RCT-006 B day 33  W1–W3 done, W4 missed
 *   RCT-007 B day 45  W2, W6 done, the rest missed
 *   RCT-008 A day 50  W1–W5 done, W6 missed, W7 open
 *   PILOT-01 A day 9  W1 closes today, nothing done → (c); not in the
 *                     completion rates (pilot)
 *   tester            isTester, unacknowledged alert (hidden by default)
 */
'use strict';

const studyWeek = require('../../../functions/study_week');
const ops = require('../../../functions/ops_dashboard');

const NOW = new Date('2026-11-20T02:00:00Z');
const TODAY = '2026-11-20';
const SENTINEL = 'SENTINEL_987654';
const SENTINEL_NUM = 987654;
const COMPANIONS = ['siu_yan', 'ah_jan_ah_bak', 'tung_tung'];

const PEOPLE = [
  {rid: 'RCT-001', uid: 'uidRct001', arm: 'A', day: 30, period: 'B',
    cohort: 'rct', lastOpened: 30, done: ['W1', 'W2', 'W3'],
    storedThrough: 28},
  {rid: 'RCT-002', uid: 'uidRct002', arm: 'B', day: 16, period: 'B',
    cohort: 'rct', lastOpened: 12, done: ['W1'], partial: ['W2']},
  {rid: 'RCT-003', uid: 'uidRct003', arm: 'A', day: 12, period: 'B',
    cohort: 'rct', lastOpened: 5, done: [], wprOnly: ['W1']},
  {rid: 'RCT-004', uid: 'uidRct004', arm: 'B', day: 40, period: 'B',
    cohort: 'rct', lastOpened: 39, done: ['W1', 'W2'], w4Paper: true},
  {rid: 'RCT-005', uid: 'uidRct005', arm: 'A', day: 35, period: 'B',
    cohort: 'rct', lastOpened: 35, done: ['W1', 'W3'], partial: ['W4'],
    w4Paper: true},
  {rid: 'RCT-006', uid: 'uidRct006', arm: 'B', day: 33, period: 'B',
    cohort: 'rct', lastOpened: 33, done: ['W1', 'W2', 'W3'], w4Paper: true},
  {rid: 'RCT-007', uid: 'uidRct007', arm: 'B', day: 45, period: 'B',
    cohort: 'rct', lastOpened: 44, done: ['W2', 'W6'], w4Paper: true},
  {rid: 'RCT-008', uid: 'uidRct008', arm: 'A', day: 50, period: 'B',
    cohort: 'rct', lastOpened: 50, done: ['W1', 'W2', 'W3', 'W4', 'W5'],
    w4Paper: true},
  {rid: 'PILOT-01', uid: 'uidPilot01', arm: 'A', day: 9, period: 'PILOT',
    cohort: 'pilot', lastOpened: 9, done: []},
];
const TESTER_UID = 'uidTester1';
/** Push days of the standard schedule (weekly_schedule DEFAULTS). */
const BUNDLE_DAYS = [['W1', 7], ['W2', 14], ['W3', 21], ['W4', 26],
  ['W5', 35], ['W6', 42], ['W7', 49]];
/** The W4 visit day of the people with W4 paper entries. */
const W4_VISIT_DAY = 30;

/**
 * Mood values of person [i] (index in PEOPLE) on study day [d]: the
 * day's first entry, and on days 3, 10, 17, … a second one.  1–5.
 * @return {Array<number>}
 */
function moodValues(i, d) {
  const first = ((d + 2 * i) % 5) + 1;
  return d % 7 === 3 ? [first, ((d + i + 2) % 5) + 1] : [first];
}

function hkAt(dayKey, hour, minute) {
  return new Date(studyWeek.hkInstant(dayKey, hour).getTime() +
    (minute || 0) * 60000);
}

async function seed(db, admin, opts) {
  const moodBase = (opts && opts.moodBase) || 0;
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('seed_synthetic: emulator only (FIRESTORE_EMULATOR_HOST)');
  }
  const ts = (d) => admin.firestore.Timestamp.fromDate(d);
  const writes = [];
  const set = (path, data) => writes.push([path, data]);

  set('app_config/phase_b', {weeklyScheduleV2Enabled: true,
    socialContactProbeEnabled: true});
  set('app_config/feature_flags', {weeklyReminderV2Enabled: true,
    opsDashboardEnabled: true});
  // Allocation data the dashboard must never read.
  set('randomization_state/rct', {next: SENTINEL_NUM, note: SENTINEL});
  set('randomization_sequences/v2', {arms: [SENTINEL], sha: SENTINEL});
  set('arm_assignment_log/x1', {arm: 'A', note: SENTINEL});
  set('pilot_assignment_log/x1', {arm: 'B', note: SENTINEL});
  set('research_id_map/uidRct001', {researchId: 'RCT-001', note: SENTINEL});

  for (const [pi, p] of PEOPLE.entries()) {
    const w0 = studyWeek.addDays(TODAY, -p.day);
    p.w0 = w0;
    set(`enrollments/${p.uid}`, {
      uid: p.uid, researchId: p.rid, studyPeriod: p.period, arm: p.arm,
      w0Date: w0, enrolledAt: ts(hkAt(w0, 11)), enrolledBy: 'staff',
      w0DjgEmotional: SENTINEL_NUM, stratum: SENTINEL,
      sequencePosition: SENTINEL_NUM, sequenceSha256: SENTINEL,
      sequenceVersion: SENTINEL, allocatedArm: SENTINEL,
    });
    const user = {
      isTester: false, cohort: p.cohort, w0Date: w0, arm: p.arm,
      strataCell: SENTINEL, baselineUclaScore: SENTINEL_NUM,
      displayName: SENTINEL,
    };
    // assessor.js writes the W4 visit day; it closes W4 (reminders v2).
    if (p.w4Paper) user.w4RecordedOn = studyWeek.addDays(w0, W4_VISIT_DAY);
    set(`users/${p.uid}`, user);

    const usage = [];
    const sessions = [];
    const brief = [];
    for (let d = 1; d <= p.day; d++) {
      const key = studyWeek.addDays(w0, d);
      const opened = d <= p.lastOpened &&
        (p.rid !== 'RCT-003' || d <= 5) && (d % 6 !== 0 || d === p.lastOpened);
      if (!opened) continue;
      const fg = hkAt(key, 9);
      const bg = hkAt(key, 9, 25);
      usage.push({type: 'foreground', clientAt: fg});
      usage.push({type: 'background', clientAt: bg});
      const agent = COMPANIONS[d % 3];
      const start = hkAt(key, 9, 5);
      const end = hkAt(key, 9, 20);
      sessions.push({sessionId: `s${d}`, agentId: agent,
        sessionType: d % 2 ? 'free_chat' : 'check_in', startedAt: start,
        endedAt: end, endReason: 'user_left', userMessageCount: 4,
        isValid: d % 5 !== 0, briefPrStatus: 'completed'});
      if (d % 2 === 0) {
        brief.push({id: `b${d}`, sessionId: `s${d}`, agentId: agent,
          invitedAt: hkAt(key, 9, 21), finalStatus: d % 4 ? 'completed' :
            'skipped', understanding: 6, validation: 5, caring: 6,
          insensitivity: 2, studyDay: d, freeText: SENTINEL});
      }
      // Check-in (chat v2) every other day; mood every day opened.
      if (d % 2 === 1) {
        set(`users/${p.uid}/check_in_responses/c${d}`, {date_iso: key,
          flow: 'chat_v2', completed: true, stopped_by_safety: false,
          answers: {q1: SENTINEL_NUM, q3b: SENTINEL}});
      }
      // MoodRecorder's fields; a second entry the same day sorts before
      // the first by id, so the person page must order them itself.
      const moods = moodValues(pi, d);
      set(`users/${p.uid}/daily_mood/m${d}`, {date_iso: key,
        mood: moodBase + moods[0], is_primary: true, supplementary: false,
        entry_seq_today: 1, prompted_at: ts(hkAt(key, 9, 1)),
        responded_at: ts(hkAt(key, 9, 2)), source_surface: 'home_hero',
        arm: p.arm, note: SENTINEL});
      if (moods.length > 1) {
        set(`users/${p.uid}/daily_mood/a${d}`, {date_iso: key,
          mood: moodBase + moods[1], is_primary: false, supplementary: true,
          entry_seq_today: 2, prompted_at: ts(hkAt(key, 20)),
          responded_at: ts(hkAt(key, 20, 1)), source_surface: 'check_in',
          arm: p.arm, note: SENTINEL});
      }
    }
    // An old Hybrid check-in marker (event row) with answer codes.
    if (p.arm === 'A' && p.day >= 2) {
      const key = studyWeek.addDays(w0, p.day >= 4 ? p.day - 2 : 2);
      set(`users/${p.uid}/events/e1`, {name: 'check_in_submitted',
        timestamp: ts(hkAt(key, 20)), params: {mood: SENTINEL_NUM,
          text: SENTINEL}});
    }
    usage.forEach((u, i) => set(`users/${p.uid}/usage_events/u${i}`,
        {type: u.type, clientAt: ts(u.clientAt)}));
    sessions.forEach((s) => set(`users/${p.uid}/sessions/${s.sessionId}`,
        Object.assign({}, s, {startedAt: ts(s.startedAt),
          endedAt: ts(s.endedAt), transcript: SENTINEL})));
    brief.forEach((b) => set(`users/${p.uid}/brief_pr/${b.id}`,
        Object.assign({}, b, {invitedAt: ts(b.invitedAt)})));

    // Stored day rows (the server's 02:10 rollup), with a gap at
    // storedThrough + 1 that the dashboard must compute itself.
    if (p.storedThrough) {
      const keys = [];
      for (let d = 1; d <= p.storedThrough; d++) {
        keys.push(studyWeek.addDays(w0, d));
      }
      const rows = ops.dayRowsFor({w0Key: w0, todayKey: TODAY, now: NOW,
        usageEvents: usage, sessions, briefPr: brief.map((b) => ({
          invitedAt: b.invitedAt, finalStatus: b.finalStatus})),
        hasUsageEvents: true, days: keys});
      for (const r of rows) {
        set(`ops_daily/${p.uid}/days/${r.dayKey}`, Object.assign({}, r,
            {uid: p.uid, storedAt: ts(NOW)}));
      }
    }

    // Weekly questionnaires: status per bundle, part records.  done: every
    // part; partial: all but PGIC; wprOnly: Weekly PR only.  W5–W7 have
    // PGIC only.
    const bundles = {};
    const has = (list, w) => (list || []).indexOf(w) >= 0;
    for (const [w, day] of BUNDLE_DAYS) {
      if (p.day < day) continue;
      bundles[w] = {pushedAt: ts(hkAt(studyWeek.addDays(w0, day), 10))};
      const done = has(p.done, w);
      const partial = has(p.partial, w);
      const pgicOnly = day >= 35;
      if (!pgicOnly && (done || partial || has(p.wprOnly, w))) {
        set(`users/${p.uid}/weekly_pr/${w}`, {status: 'completed',
          items: [SENTINEL_NUM], agentId: 'siu_yan', bundle: w});
      }
      if (!pgicOnly && (done || partial)) {
        if (w !== 'W4') {
          set(`users/${p.uid}/djg_responses/${w}`, {status: 'submitted',
            answers: {q1: SENTINEL_NUM}, scores: {total: SENTINEL_NUM}});
        }
        set(`users/${p.uid}/social_contact_probes/${w}`, {status: 'submitted',
          answers: {q1: SENTINEL_NUM, q2: SENTINEL}, bundle: w});
      }
      if (done) {
        set(`users/${p.uid}/pgic/${w}`, {value: SENTINEL_NUM, bundle: w,
          answeredAt: ts(hkAt(studyWeek.addDays(w0, day), 12))});
      }
    }
    set(`weekly_status/${p.uid}`, {researchId: p.rid, bundles,
      w4VisitDate: null});
    if (p.w4Paper) {
      for (const inst of ['DJG-ES', 'PHQ-9']) {
        set(`outcome_entries/${p.rid}_W4_${inst}`, {researchId: p.rid,
          timepoint: 'W4', instrument: inst, answers: {q1: SENTINEL_NUM},
          scores: {total: SENTINEL_NUM}, missingItems: [SENTINEL]});
      }
    }
  }

  // Safety events and alerts.
  const p2 = PEOPLE[1];
  const p1 = PEOPLE[0];
  set('safety_events/ev1', {uid: p2.uid, level: 'acute', category: 'self_harm',
    source: 'user_input', createdAt: ts(hkAt(studyWeek.addDays(TODAY, -1), 21)),
    matchedTerm: SENTINEL, textHash: SENTINEL, agentId: 'siu_yan'});
  set('pi_alerts/al1', {uid: p2.uid, level: 'acute', category: 'self_harm',
    source: 'user_input', sourceGroup: 'participant_input',
    createdAt: ts(hkAt(studyWeek.addDays(TODAY, -1), 21)), studyDay: 15,
    eventPath: 'safety_events/ev1', isTester: false,
    escalationPending: true});
  set('safety_events/ev2', {uid: p1.uid, level: 'acute', category: 'self_harm',
    source: 'user_input', createdAt: ts(hkAt(studyWeek.addDays(TODAY, -5), 15)),
    matchedTerm: SENTINEL, falseAlarm: true, markedAt: ts(NOW)});
  set('pi_alerts/al2', {uid: p1.uid, level: 'acute', category: 'self_harm',
    source: 'user_input', sourceGroup: 'participant_input',
    createdAt: ts(hkAt(studyWeek.addDays(TODAY, -5), 15)), studyDay: 25,
    eventPath: 'safety_events/ev2', isTester: false,
    acknowledgedAt: ts(hkAt(studyWeek.addDays(TODAY, -5), 16)),
    acknowledgedBy: 'staffUid', acknowledgedByEmail: SENTINEL,
    falseAlarm: true});
  set(`users/${TESTER_UID}`, {isTester: true, arm: 'B', cohort: 'pilot',
    displayName: SENTINEL});
  set(`users/${TESTER_UID}/sessions/t1`, {agentId: 'tung_tung', isValid: true,
    startedAt: ts(hkAt(TODAY, 8)), endedAt: ts(hkAt(TODAY, 8, 10))});
  set('safety_events/ev3', {uid: TESTER_UID, level: 'acute',
    category: 'self_harm', source: 'user_input', createdAt: ts(NOW),
    matchedTerm: SENTINEL});
  set('pi_alerts/al3', {uid: TESTER_UID, level: 'acute', category: 'self_harm',
    source: 'user_input', sourceGroup: 'participant_input',
    createdAt: ts(NOW), eventPath: 'safety_events/ev3', isTester: true});

  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    for (const [path, data] of writes.slice(i, i + 400)) {
      batch.set(db.doc(path), data);
    }
    await batch.commit();
  }
  return {writes: writes.length};
}

module.exports = {NOW, TODAY, SENTINEL, SENTINEL_NUM, PEOPLE, TESTER_UID,
  W4_VISIT_DAY, moodValues, seed};

if (require.main === module) {
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT ||
    'loneliness-pilot-dev'});
  seed(admin.firestore(), admin).then((r) => {
    console.log(`合成数据已写入模拟器：${r.writes} 份文档（今天 = ${TODAY}）。`);
    process.exit(0);
  }).catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}
