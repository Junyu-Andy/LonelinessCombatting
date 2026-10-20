#!/usr/bin/env node
/**
 * tool/analysis_export.js — T30 (registry C20; dev-tasks-1010 §四 T30 §5.3).
 * The data lock and the analysis export.
 *
 *   --lock      writes meta/data_lock {lockedAt, lockedBy, note}.  Needs
 *               --operator, --confirm AND --confirm-lock (two confirmations)
 *               and refuses when a lock already exists.
 *   (export)    refuses without meta/data_lock.  Writes one NDJSON file per
 *               table below into --out=<dir> (default analysis-export/<stamp>)
 *               plus manifest.json: every Phase B participant (cohort
 *               phase_b = run-in or rct, not pilot, not testers;
 *               functions/study_period.js PHASE_B_COHORTS), research ID instead of
 *               uid, the real arm, NO conversation text (every table is an
 *               allowlist of columns; `turns` carries only metadata).
 *   --synthetic reads NOTHING from Firestore: generates 72 fake
 *               participants (two arms, two strata, with missingness) with
 *               exactly the same tables and columns, every row labelled
 *               dataset = "synthetic", for the analysis code registered on
 *               OSF before the lock.  --n=<count> and --seed=<text> change
 *               the size and the pseudo-random draw.
 *
 * Every real run (lock or export) writes one row in analysis_export_log
 * (server only; time, operator, mode, row counts, lock time).  A synthetic
 * run touches no Firestore project; its manifest is the record.
 *
 * Target: the Firestore emulator by default (FIRESTORE_EMULATOR_HOST).  A
 * real project needs --project=<id> --production-confirm=<same id>
 * (tool/firestore_target.js).
 *
 * Usage
 *   NODE_PATH=functions/node_modules node tool/analysis_export.js --lock \
 *     --operator=junyu@… --confirm --confirm-lock [--note="…"]
 *   NODE_PATH=functions/node_modules node tool/analysis_export.js \
 *     --operator=junyu@… [--out=analysis-export/2026-12-20]
 *   node tool/analysis_export.js --synthetic [--n=72] [--seed=osf-dry-run] \
 *     [--out=analysis-export/synthetic]
 */

'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const {parseArgs, checkTarget} = require('./firestore_target');
const instruments = require('../functions/outcome_instruments');
const studyPeriod = require('../functions/study_period');

const LOCK_DOC = 'meta/data_lock';
const LOG_COLLECTION = 'analysis_export_log';
const EXPORT_VERSION = 1;

/**
 * Tables and their columns.  Both the real export and the synthetic one
 * emit exactly these keys (missing → null), so the schema is identical by
 * construction.  Column `dataset` is "real" or "synthetic".
 */
const TABLES = {
  // dev-tasks-1020 §C(5): allocatedArm (the arm drawn at registration),
  // receivedArm (the arm the App delivers now = `arm`), sequenceVersion
  // (v1 = the PB- sequence, v2 = RCT-), runIn (PB-01…04) and analysisSet
  // ("rct" for RCT-, "run_in" for PB-).
  participants: ['dataset', 'researchId', 'arm', 'stratum', 'strataCell',
    'w0Date', 'companionVariantAtRegistration', 'enrolledAt', 'ageGroup',
    'baselineUclaScore', 'withdrawn', 'allocatedArm', 'receivedArm',
    'sequenceVersion', 'runIn', 'analysisSet'],
  allocation_records: ['dataset', 'researchId', 'studyPeriod', 'stratum',
    'arm', 'sequencePosition', 'allocatedAt', 'withdrawnAt',
    'sequenceVersion', 'runIn', 'analysisSet'],
  outcome_entries: ['dataset', 'researchId', 'arm', 'instrument',
    'instrumentVersion', 'timepoint', 'assessmentDate', 'mode', 'enteredAt',
    'answers', 'missingItems', 'scores', 'scoringVersion', 'studyDay',
    'outOfWindow', 'correctedAt'],
  djg_responses: ['dataset', 'researchId', 'arm', 'timepoint',
    'itemsVersion', 'answers', 'status', 'scores', 'scoringVersion',
    'outsideWindow', 'outOfWindow', 'windowStartDate', 'windowEndDate',
    'pushSentAt', 'reminderSentAt', 'startedAt', 'submittedAt', 'missedAt',
    'studyWeek', 'studyDay'],
  pgic: ['dataset', 'researchId', 'arm', 'value', 'isoWeek', 'weekIso',
    'studyWeek', 'studyDay', 'answeredAt', 'outOfWindow'],
  ucla3_responses: ['dataset', 'researchId', 'arm', 'timepoint',
    'studyWeek', 'studyDay', 'answers', 'scores', 'status', 'submittedAt',
    'outOfWindow'],
  weekly_pr: ['dataset', 'researchId', 'arm', 'weekIso', 'agentId', 'items',
    'status', 'promptedAt', 'respondedAt', 'studyWeek', 'studyDay'],
  brief_pr: ['dataset', 'researchId', 'arm', 'schemaVersion',
    'scheduleVersion', 'sessionId', 'agentId', 'sessionType', 'endReason',
    'sessionEndedAt', 'invitedAt', 'inviteChannel', 'everShown', 'ratedAt',
    'finalStatus', 'dueNotInvitedReason', 'understanding', 'validation',
    'caring', 'insensitivity', 'status', 'promptedAt', 'respondedAt',
    'studyWeek', 'studyDay'],
  daily_mood: ['dataset', 'researchId', 'arm', 'mood', 'date_iso',
    'is_primary', 'prompted_at', 'responded_at'],
  loneliness_probes: ['dataset', 'researchId', 'arm', 'score', 'isoWeek',
    'answeredAt'],
  sessions: ['dataset', 'researchId', 'arm', 'sessionId', 'agentId',
    'moduleId', 'sessionType', 'startedAt', 'endedAt', 'endReason',
    'userTurnCount', 'userMessageCount', 'replyCount', 'fallbackCount',
    'isValid', 'scheduleVersion', 'isRuleSubmission',
    'ruleSubmissionCompleted', 'briefPrInvited', 'briefPrStatus'],
  // Metadata only: never the wording of either side.
  turns: ['dataset', 'researchId', 'arm', 'sessionId', 'agentId',
    'moduleId', 'ts', 'llmStatus', 'promptVersion', 'latencyMs',
    'inputCharCount', 'safetyLevel', 'safetyTurnId'],
  events: ['dataset', 'researchId', 'arm', 'name', 'ts'],
  safety_events: ['dataset', 'researchId', 'arm', 'source', 'sourceGroup',
    'level', 'tier', 'category', 'lexiconVersion', 'agentId', 'inputPoint',
    'createdAt', 'instrument', 'item', 'rawValue', 'crisisPageShown',
    'isDuplicate', 'falseAlarm', 'markedAt'],
  llm_calls: ['dataset', 'researchId', 'arm', 'ts', 'call_type', 'agent',
    'model_requested', 'model_returned', 'prompt_tokens',
    'completion_tokens', 'total_tokens', 'http_status', 'latency_ms',
    'error', 'session_id'],
  usage_weekly: ['dataset', 'researchId', 'arm', 'isoWeek', 'sessionCount',
    'validSessionCount', 'activeDays'],
  memory_counts: ['dataset', 'researchId', 'arm', 'facts', 'summaries',
    'followups'],
};

const SOURCE_GROUP = {
  user_input: 'participant_input', form: 'participant_input',
  gateway_input: 'participant_input', rule_turn: 'participant_input',
  m3_turn: 'participant_input', ai_output_scan: 'ai_reply_scan',
  gateway_output: 'ai_reply_scan', questionnaire: 'questionnaire',
  assessor_entry: 'assessor_entry',
};

/** Firestore values → plain JSON (Timestamps → ISO; refs → null). */
function plain(v) {
  if (v === null || v === undefined) return null;
  if (v instanceof Date) return v.toISOString();
  if (typeof v.toDate === 'function') return v.toDate().toISOString();
  if (typeof v.path === 'string' && v.firestore) return null;
  if (Array.isArray(v)) return v.map(plain);
  if (typeof v === 'object') {
    const out = {};
    for (const k of Object.keys(v)) out[k] = plain(v[k]);
    return out;
  }
  return v;
}

/** Project [obj] onto the table's columns, in order; missing → null. */
function row(table, obj) {
  const out = {};
  for (const c of TABLES[table]) {
    out[c] = obj[c] === undefined ? null : plain(obj[c]);
  }
  return out;
}

function emptyFiles() {
  const files = {};
  for (const t of Object.keys(TABLES)) files[t] = [];
  return files;
}

function isoWeekHk(d) {
  const t = new Date(d.getTime() + 8 * 3600 * 1000);
  const day = (t.getUTCDay() + 6) % 7;
  t.setUTCDate(t.getUTCDate() - day + 3);
  const firstThu = new Date(Date.UTC(t.getUTCFullYear(), 0, 4));
  const week = 1 + Math.round(
      ((t - firstThu) / 86400000 - 3 + ((firstThu.getUTCDay() + 6) % 7)) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

// ---------------------------------------------------------------------------
// Real export
// ---------------------------------------------------------------------------

async function readLock(db) {
  const snap = await db.doc(LOCK_DOC).get();
  return snap.exists ? snap.data() : null;
}

async function lock(db, p) {
  const existing = await readLock(db);
  if (existing) {
    const e = new Error('already_locked');
    e.lock = plain(existing);
    throw e;
  }
  const at = p.now || new Date();
  const doc = {lockedAt: at, lockedBy: p.operator, note: p.note || null,
    tool: 'tool/analysis_export.js'};
  await db.doc(LOCK_DOC).create(doc);
  await db.collection(LOG_COLLECTION).add({at, by: p.operator, mode: 'lock',
    note: p.note || null});
  return doc;
}

function isPhaseB(u) {
  if (u.isTester === true) return false;
  if (u.arm !== 'A' && u.arm !== 'B') return false;
  // 1020b §1: run-in (PB-) and RCT- (functions/study_period.js lists).
  if (typeof u.cohort === 'string') return studyPeriod.isPhaseBCohort(u);
  return u.armAssignmentMode === 'randomise';
}

/**
 * dev-tasks-1020 §C(5) / 1020b §1(1): the analysis set comes from the
 * cohort (rct → "rct", phase_b → "run_in", pilot → "pilot").  A withdrawal
 * record has no cohort; its research-ID prefix gives the same answer.
 * @param {?string} cohort
 * @param {?string=} researchId fallback when there is no cohort
 * @return {?string}
 */
function analysisSetOf(cohort, researchId) {
  if (typeof cohort === 'string') return studyPeriod.analysisSetForCohort(cohort);
  const p = studyPeriod.periodForResearchId(researchId);
  return p ? studyPeriod.analysisSetForCohort(p.cohort) : null;
}

/**
 * The sequence an enrolment drew from: stored since §C; a Phase B
 * enrolment from before has none and drew from the first sequence, v1.
 * @param {object} e enrollments/{uid} (or allocation_records) data
 * @return {?string}
 */
function sequenceVersionOf(e) {
  if (typeof e.sequenceVersion === 'string') return e.sequenceVersion;
  return e.studyPeriod === 'B' || e.sequencePosition != null ? 'v1' : null;
}

/**
 * The arm drawn at registration.  Stored as allocatedArm since §C; before
 * that, enrollments.arm is still the drawn arm unless the arm was corrected
 * (correctedAt) — then it is not known here (the allocation log is not
 * read) and the column stays empty for a manual check.
 * @param {object} e enrollments/{uid} data
 * @return {?string}
 */
function allocatedArmOf(e) {
  if (e.allocatedArm === 'A' || e.allocatedArm === 'B') return e.allocatedArm;
  if (e.correctedAt) return null;
  return e.arm === 'A' || e.arm === 'B' ? e.arm : null;
}

/**
 * Collect the real export in memory.  Throws `not_locked` without the lock.
 */
async function collectReal(db, opts) {
  const lockDoc = await readLock(db);
  if (!lockDoc) throw new Error('not_locked');
  const files = emptyFiles();
  const base = {dataset: 'real'};
  const ridByUid = {};
  const armByUid = {};

  const users = await db.collection('users').get();
  for (const userDoc of users.docs) {
    const u = userDoc.data();
    if (!isPhaseB(u)) continue;
    const enrol = await db.collection('enrollments').doc(userDoc.id).get();
    const map = await db.collection('research_id_map').doc(userDoc.id).get();
    const researchId = enrol.exists ? enrol.get('researchId') :
      map.exists ? map.get('researchId') : null;
    if (!researchId) continue;
    ridByUid[userDoc.id] = researchId;
    armByUid[userDoc.id] = u.arm;
    const e = enrol.exists ? enrol.data() : {};
    const tag = Object.assign({}, base, {researchId, arm: u.arm});
    files.participants.push(row('participants', Object.assign({}, tag, {
      stratum: e.stratum || (u.strataCell === 1 ? 'high' :
        u.strataCell === 0 ? 'low' : null),
      strataCell: u.strataCell, w0Date: u.w0Date || e.w0Date || null,
      companionVariantAtRegistration: e.companionVariant || null,
      enrolledAt: e.enrolledAt || null, ageGroup: u.ageGroup || null,
      baselineUclaScore: u.baselineUclaScore == null ? null :
        u.baselineUclaScore,
      withdrawn: false,
      allocatedArm: allocatedArmOf(e), receivedArm: u.arm,
      sequenceVersion: sequenceVersionOf(e),
      runIn: analysisSetOf(u.cohort, researchId) === 'run_in',
      analysisSet: analysisSetOf(u.cohort, researchId),
    })));

    for (const t of ['djg_responses', 'pgic', 'ucla3_responses', 'weekly_pr',
      'brief_pr', 'daily_mood', 'loneliness_probes', 'sessions', 'events']) {
      const sub = await userDoc.ref.collection(t).get();
      for (const d of sub.docs) {
        const data = d.data();
        if (t === 'events') data.ts = data.ts || data.at || data.timestamp;
        if (t === 'sessions' && !data.sessionId) data.sessionId = d.id;
        files[t].push(row(t, Object.assign({}, tag, data)));
      }
    }
    const turns = await userDoc.ref.collection('turns').get();
    for (const d of turns.docs) {
      const x = d.data();
      const llm = x.llm || {};
      files.turns.push(row('turns', Object.assign({}, tag, {
        sessionId: x.sessionId || null, agentId: x.agentId || null,
        moduleId: x.moduleId || null, ts: x.ts || x.createdAt || null,
        llmStatus: llm.status || x.llmStatus || null,
        promptVersion: llm.promptVersion || null,
        latencyMs: llm.latencyMs == null ? null : llm.latencyMs,
        inputCharCount: x.input && x.input.charCount != null ?
          x.input.charCount : null,
        safetyLevel: (x.safety && x.safety.level) || x.safetyLevel || null,
        safetyTurnId: x.safetyTurnId || null,
      })));
    }
    const byWeek = {};
    for (const s of files.sessions.filter((r) => r.researchId === researchId)) {
      if (typeof s.startedAt !== 'string') continue;
      const at = new Date(s.startedAt);
      const week = isoWeekHk(at);
      const day = new Date(at.getTime() + 8 * 3600 * 1000).toISOString()
          .slice(0, 10);
      if (!byWeek[week]) byWeek[week] = {sessions: 0, valid: 0, days: {}};
      byWeek[week].sessions++;
      if (s.isValid === true) byWeek[week].valid++;
      byWeek[week].days[day] = true;
    }
    for (const week of Object.keys(byWeek).sort()) {
      files.usage_weekly.push(row('usage_weekly', Object.assign({}, tag, {
        isoWeek: week, sessionCount: byWeek[week].sessions,
        validSessionCount: byWeek[week].valid,
        activeDays: Object.keys(byWeek[week].days).length})));
    }
    const counts = {};
    for (const [k, col] of [['facts', 'mem_facts'],
      ['summaries', 'mem_summaries'], ['followups', 'mem_followups']]) {
      counts[k] = (await userDoc.ref.collection(col).get()).size;
    }
    files.memory_counts.push(row('memory_counts', Object.assign({}, tag,
        counts)));
  }

  const entries = await db.collection('outcome_entries').get();
  for (const d of entries.docs) {
    const x = d.data();
    const rid = ridByUid[x.uid] || x.researchId;
    if (!rid || !armByUid[x.uid]) continue;
    files.outcome_entries.push(row('outcome_entries', Object.assign({}, base,
        x, {researchId: rid, arm: armByUid[x.uid]})));
  }
  const records = await db.collection('allocation_records').get();
  for (const d of records.docs) {
    const x = d.data();
    files.allocation_records.push(row('allocation_records',
        Object.assign({}, base, x, {sequenceVersion: sequenceVersionOf(x),
          runIn: analysisSetOf(null, x.researchId) === 'run_in',
          analysisSet: analysisSetOf(null, x.researchId)})));
  }
  const safety = await db.collection('safety_events').get();
  for (const d of safety.docs) {
    const x = d.data();
    if (!ridByUid[x.uid]) continue;
    files.safety_events.push(row('safety_events', Object.assign({}, base, x,
        {researchId: ridByUid[x.uid], arm: armByUid[x.uid],
          sourceGroup: SOURCE_GROUP[x.source] || 'other'})));
  }
  const calls = await db.collection('llm_calls').get();
  for (const d of calls.docs) {
    const x = d.data();
    if (!ridByUid[x.uid]) continue;
    files.llm_calls.push(row('llm_calls', Object.assign({}, base, x,
        {researchId: ridByUid[x.uid], arm: armByUid[x.uid]})));
  }
  return {files, manifest: manifestFor(files, {dataset: 'real',
    dataLock: plain(lockDoc), operator: opts && opts.operator})};
}

function manifestFor(files, extra) {
  const rowCounts = {};
  for (const t of Object.keys(files)) rowCounts[t] = files[t].length;
  return Object.assign({exportVersion: EXPORT_VERSION, rowCounts,
    columns: TABLES, generatedAt: new Date().toISOString(),
    note: 'Phase B participants only; research ID instead of uid; real ' +
      'arm; no conversation text (turns = metadata).'}, extra);
}

// ---------------------------------------------------------------------------
// Synthetic export (reads nothing)
// ---------------------------------------------------------------------------

function rng(seed) {
  let counter = 0;
  return () => {
    const h = crypto.createHash('sha256').update(`${seed}|${counter++}`)
        .digest();
    return h.readUInt32BE(0) / 0x100000000;
  };
}

function addDays(key, n) {
  const d = new Date(`${key}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

function generateSynthetic(opts) {
  const n = (opts && opts.n) || 72;
  const rand = rng((opts && opts.seed) || 'synthetic-default-seed');
  const pick = (arr) => arr[Math.floor(rand() * arr.length)];
  const files = emptyFiles();
  const base = {dataset: 'synthetic'};
  const w0Base = '2026-11-01';
  for (let i = 0; i < n; i++) {
    // 10/20: shaped like the randomised analysis set (RCT-, sequence v2).
    const researchId = `RCT-S${String(i + 1).padStart(3, '0')}`;
    const arm = i % 2 === 0 ? 'A' : 'B';
    const stratum = i % 4 < 2 ? 'low' : 'high';
    const w0Date = addDays(w0Base, Math.floor(i / 4) * 3);
    const tag = Object.assign({}, base, {researchId, arm});
    const withdrawn = rand() < 0.08;
    files.participants.push(row('participants', Object.assign({}, tag, {
      stratum, strataCell: stratum === 'low' ? 0 : 1, w0Date,
      companionVariantAtRegistration: pick(['feminine', 'masculine']),
      enrolledAt: `${w0Date}T03:00:00.000Z`,
      ageGroup: pick(['65-69', '70-74', '75-79', '80+']),
      baselineUclaScore: 30 + Math.floor(rand() * 40), withdrawn,
      allocatedArm: arm, receivedArm: arm, sequenceVersion: 'v2',
      runIn: false, analysisSet: 'rct'})));
    if (withdrawn) {
      files.allocation_records.push(row('allocation_records',
          Object.assign({}, base, {researchId, studyPeriod: 'B', stratum,
            arm, sequencePosition: i + 1,
            allocatedAt: `${w0Date}T03:00:00.000Z`,
            withdrawnAt: `${addDays(w0Date, 20)}T03:00:00.000Z`,
            sequenceVersion: 'v2', runIn: false, analysisSet: 'rct'})));
    }
    const djgAnswers = () => {
      const a = {};
      for (const it of instruments.DJG_ES.items) {
        a[it.id] = rand() < 0.06 ? 'skipped' : pick(['yes', 'mostly', 'no']);
      }
      return a;
    };
    // W2 in-App DJG (missing when withdrawn early or ~12%).
    if (!withdrawn && rand() > 0.12) {
      const a = djgAnswers();
      files.djg_responses.push(row('djg_responses', Object.assign({}, tag, {
        timepoint: 'W2', itemsVersion: instruments.DJG_ES.version, answers: a,
        status: 'submitted', scores: instruments.DJG_ES.score(a),
        scoringVersion: instruments.DJG_ES.scoringVersion,
        outsideWindow: rand() < 0.1, windowStartDate: addDays(w0Date, 14),
        windowEndDate: addDays(w0Date, 20),
        pushSentAt: `${addDays(w0Date, 14)}T02:00:00.000Z`,
        startedAt: `${addDays(w0Date, 15)}T05:00:00.000Z`,
        submittedAt: `${addDays(w0Date, 15)}T05:04:00.000Z`,
        studyWeek: 2, studyDay: 15})));
    }
    // W4 paper DJG-ES by the assessor (~15% missing).
    if (!withdrawn && rand() > 0.15) {
      const a = djgAnswers();
      const day = 25 + Math.floor(rand() * 9);
      const missing = Object.keys(a).filter((k) => a[k] === 'skipped');
      files.outcome_entries.push(row('outcome_entries', Object.assign({}, tag,
          {instrument: 'DJG-ES', instrumentVersion: instruments.DJG_ES.version,
            timepoint: 'W4', assessmentDate: addDays(w0Date, day),
            mode: pick(['in_person', 'phone', 'video']),
            enteredAt: `${addDays(w0Date, day)}T08:00:00.000Z`, answers: a,
            missingItems: missing, scores: instruments.DJG_ES.score(a),
            scoringVersion: instruments.DJG_ES.scoringVersion, studyDay: day,
            outOfWindow: day > 31, correctedAt: null})));
    }
    for (const wk of [5, 6, 7, 8]) {
      if (withdrawn || rand() < 0.2) continue;
      files.pgic.push(row('pgic', Object.assign({}, tag, {
        value: 1 + Math.floor(rand() * 7), weekIso: isoWeekHk(
            new Date(`${addDays(w0Date, wk * 7)}T00:00:00Z`)),
        studyWeek: wk, studyDay: wk * 7,
        answeredAt: `${addDays(w0Date, wk * 7)}T06:00:00.000Z`,
        outOfWindow: false})));
    }
    if (!withdrawn && rand() > 0.2) {
      const a = {q1: 1 + Math.floor(rand() * 3), q2: 1 + Math.floor(rand() * 3),
        q3: 1 + Math.floor(rand() * 3)};
      files.ucla3_responses.push(row('ucla3_responses', Object.assign({}, tag,
          {timepoint: 'W8', studyWeek: 8, studyDay: 56, answers: a,
            scores: {total: a.q1 + a.q2 + a.q3}, status: 'submitted',
            submittedAt: `${addDays(w0Date, 56)}T06:00:00.000Z`,
            outOfWindow: false})));
    }
    const weeks = withdrawn ? 3 : 8;
    for (let wk = 1; wk <= weeks; wk++) {
      const sessions = 1 + Math.floor(rand() * 6);
      let valid = 0;
      const days = {};
      for (let s = 0; s < sessions; s++) {
        const day = (wk - 1) * 7 + Math.floor(rand() * 7);
        const started = `${addDays(w0Date, day)}T${String(8 + Math.floor(
            rand() * 12)).padStart(2, '0')}:00:00.000Z`;
        const isValid = rand() < 0.7;
        if (isValid) valid++;
        days[day] = true;
        const sessionId = `${researchId}-s${wk}-${s}`;
        const agentId = pick(['siu_yan', 'ah_jan_ah_bak', 'tung_tung']);
        files.sessions.push(row('sessions', Object.assign({}, tag, {
          sessionId, agentId, moduleId: pick(['check_in', 'reminiscence',
            'free_chat']), sessionType: pick(['free_chat', 'check_in',
            'reminiscence']), startedAt: started,
          endedAt: started.replace('T', 'T').slice(0, 11) +
            String(20 + Math.floor(rand() * 3)) + ':00:00.000Z',
          endReason: pick(['user_close', 'timeout', 'back']),
          userTurnCount: 1 + Math.floor(rand() * 6),
          userMessageCount: 1 + Math.floor(rand() * 6),
          replyCount: 1 + Math.floor(rand() * 6), fallbackCount: 0, isValid,
          scheduleVersion: 2, isRuleSubmission: arm === 'B',
          ruleSubmissionCompleted: arm === 'B' ? rand() < 0.9 : null,
          briefPrInvited: isValid && rand() < 0.5, briefPrStatus: null})));
        files.turns.push(row('turns', Object.assign({}, tag, {sessionId,
          agentId, moduleId: 'free_chat', ts: started,
          llmStatus: arm === 'A' ? 'ok' : 'rule_based',
          promptVersion: arm === 'A' ? 'siu_yan_v1@2026-06' : null,
          latencyMs: arm === 'A' ? 800 + Math.floor(rand() * 2000) : null,
          inputCharCount: 5 + Math.floor(rand() * 60),
          safetyLevel: 'none', safetyTurnId: `${sessionId}-t0`})));
        files.events.push(row('events', Object.assign({}, tag, {
          name: 'chat_open', ts: started})));
        if (arm === 'A') {
          files.llm_calls.push(row('llm_calls', Object.assign({}, tag, {
            ts: started, call_type: 'chat', agent: agentId,
            model_requested: 'deepseek-flash', model_returned:
              'deepseek-flash', prompt_tokens: 500 + Math.floor(rand() * 900),
            completion_tokens: 50 + Math.floor(rand() * 200),
            total_tokens: null, http_status: 200,
            latency_ms: 800 + Math.floor(rand() * 2000), error: false,
            session_id: sessionId})));
        }
        if (isValid && rand() < 0.5) {
          const rated = rand() < 0.75;
          files.brief_pr.push(row('brief_pr', Object.assign({}, tag, {
            schemaVersion: 3, scheduleVersion: 2, sessionId, agentId,
            sessionType: 'free_chat', endReason: 'user_close',
            sessionEndedAt: started, invitedAt: started,
            inviteChannel: pick(['list_page', 'catch_up']), everShown: true,
            ratedAt: rated ? started : null,
            finalStatus: rated ? 'completed' : pick(['skipped', 'expired']),
            dueNotInvitedReason: null,
            understanding: rated ? 1 + Math.floor(rand() * 7) : null,
            validation: rated ? 1 + Math.floor(rand() * 7) : null,
            caring: rated ? 1 + Math.floor(rand() * 7) : null,
            insensitivity: rated ? 1 + Math.floor(rand() * 7) : null,
            status: null, promptedAt: null, respondedAt: null,
            studyWeek: wk, studyDay: day})));
        }
        if (rand() < 0.04) {
          const src = pick(['user_input', 'form', 'rule_turn']);
          files.safety_events.push(row('safety_events', Object.assign({}, tag,
              {source: src, sourceGroup: SOURCE_GROUP[src],
                level: pick(['moderate', 'acute']), tier: pick([
                  'moderate_review', 'moderate_interrupt', 'acute']),
                category: pick(['hopeless', 'ideation']),
                lexiconVersion: 'v5-2026-09', agentId, inputPoint: 'chat',
                createdAt: started, instrument: null, item: null,
                rawValue: null, crisisPageShown: rand() < 0.3,
                isDuplicate: false, falseAlarm: false, markedAt: null})));
        }
      }
      const isoWeek = isoWeekHk(new Date(`${addDays(w0Date, (wk - 1) * 7)}` +
        'T00:00:00Z'));
      files.usage_weekly.push(row('usage_weekly', Object.assign({}, tag, {
        isoWeek, sessionCount: sessions, validSessionCount: valid,
        activeDays: Object.keys(days).length})));
      if (rand() < 0.6) {
        files.weekly_pr.push(row('weekly_pr', Object.assign({}, tag, {
          weekIso: isoWeek, agentId: pick(['siu_yan', 'ah_jan_ah_bak',
            'tung_tung']), items: {u: 1 + Math.floor(rand() * 7),
            v: 1 + Math.floor(rand() * 7)}, status: 'completed',
          promptedAt: `${addDays(w0Date, wk * 7)}T10:00:00.000Z`,
          respondedAt: `${addDays(w0Date, wk * 7)}T10:05:00.000Z`,
          studyWeek: wk, studyDay: wk * 7})));
      }
      for (let d = 0; d < 7; d++) {
        if (rand() < 0.4) continue;
        const date = addDays(w0Date, (wk - 1) * 7 + d);
        files.daily_mood.push(row('daily_mood', Object.assign({}, tag, {
          mood: 1 + Math.floor(rand() * 5), date_iso: date, is_primary: true,
          prompted_at: `${date}T11:00:00.000Z`,
          responded_at: `${date}T11:02:00.000Z`})));
      }
      if (rand() < 0.5) {
        files.loneliness_probes.push(row('loneliness_probes', Object.assign({},
            tag, {score: Math.floor(rand() * 11), isoWeek,
              answeredAt: `${addDays(w0Date, wk * 7)}T09:00:00.000Z`})));
      }
    }
    files.memory_counts.push(row('memory_counts', Object.assign({}, tag, {
      facts: arm === 'A' ? Math.floor(rand() * 30) : 0,
      summaries: arm === 'A' ? Math.floor(rand() * 20) : 0,
      followups: arm === 'A' ? Math.floor(rand() * 8) : 0})));
  }
  return {files, manifest: manifestFor(files, {dataset: 'synthetic',
    synthetic: true, participants: n,
    note: 'SYNTHETIC — generated by tool/analysis_export.js --synthetic; ' +
      'no real data was read.  Same tables and columns as the real export.'})};
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

function writeOut(dir, built) {
  fs.mkdirSync(dir, {recursive: true});
  const prefix = built.manifest.dataset === 'synthetic' ? 'synthetic_' : '';
  const written = [];
  for (const t of Object.keys(built.files)) {
    const f = path.join(dir, `${prefix}${t}.ndjson`);
    fs.writeFileSync(f, built.files[t].map((r) => JSON.stringify(r))
        .join('\n'));
    written.push(f);
  }
  const m = path.join(dir, `${prefix}manifest.json`);
  fs.writeFileSync(m, JSON.stringify(built.manifest, null, 2));
  written.push(m);
  return written;
}

/** Column sets per table, for the schema-equality test. */
function schemaOf(built) {
  const out = {};
  for (const t of Object.keys(built.files)) {
    out[t] = built.files[t].length ? Object.keys(built.files[t][0]) :
      TABLES[t].slice();
  }
  return out;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '');
  if (args.synthetic === true) {
    const built = generateSynthetic({n: args.n ? Number(args.n) : 72,
      seed: typeof args.seed === 'string' ? args.seed : undefined});
    const dir = typeof args.out === 'string' ? args.out :
      path.join('analysis-export', `synthetic-${stamp}`);
    const files = writeOut(dir, built);
    console.log(`SYNTHETIC export: ${files.length} files in ${dir} ` +
      `(${built.manifest.participants} fake participants). No Firestore ` +
      'was read.');
    return;
  }
  const t = checkTarget(process.env, args);
  if (!t.ok) {
    console.error(`analysis_export: ${t.reason}`);
    process.exit(2);
  }
  const operator = typeof args.operator === 'string' ? args.operator : '';
  if (!operator) {
    console.error('Need --operator=<your e-mail>.');
    process.exit(2);
  }
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: t.projectId});
  const db = admin.firestore();
  if (args.lock === true) {
    if (args.confirm !== true || args['confirm-lock'] !== true) {
      const existing = await readLock(db);
      console.log(`Target: ${t.reason}. ` + (existing ?
        `ALREADY LOCKED at ${plain(existing.lockedAt)} by ` +
        `${existing.lockedBy}.` :
        'Not locked yet. Locking is final: after it the outcome export ' +
        'is allowed and no further participant data should change.'));
      console.log('To lock, re-run with BOTH --confirm and --confirm-lock.');
      return;
    }
    try {
      const doc = await lock(db, {operator,
        note: typeof args.note === 'string' ? args.note : null});
      console.log(`Locked (${t.reason}) at ${doc.lockedAt.toISOString()} ` +
        `by ${operator}. Logged in ${LOG_COLLECTION}.`);
    } catch (e) {
      console.error(e.message === 'already_locked' ?
        `Already locked: ${JSON.stringify(e.lock)}` : e.message);
      process.exit(1);
    }
    return;
  }
  let built;
  try {
    built = await collectReal(db, {operator});
  } catch (e) {
    if (e.message === 'not_locked') {
      console.error('Refusing: no data lock (meta/data_lock). Run --lock ' +
        'first.');
      process.exit(1);
    }
    throw e;
  }
  const dir = typeof args.out === 'string' ? args.out :
    path.join('analysis-export', stamp);
  const files = writeOut(dir, built);
  await db.collection(LOG_COLLECTION).add({
    at: new Date(), by: operator, mode: 'export',
    rowCounts: built.manifest.rowCounts,
    dataLockAt: built.manifest.dataLock.lockedAt, outDir: path.basename(dir),
  });
  console.log(`Exported ${files.length} files to ${dir} (${t.reason}); ` +
    `run logged in ${LOG_COLLECTION}.`);
  for (const [k, v] of Object.entries(built.manifest.rowCounts)) {
    console.log(`  ${k}  ${v}`);
  }
}

module.exports = {TABLES, LOCK_DOC, LOG_COLLECTION, SOURCE_GROUP, row,
  plain, lock, readLock, collectReal, generateSynthetic, writeOut, schemaOf,
  isPhaseB};

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
