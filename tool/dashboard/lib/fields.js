/**
 * tool/dashboard/lib/fields.js — what the local ops dashboard may read
 * (decision 0072, which supersedes 0061; dev-tasks 1020i 第二版 §2).
 *
 * READ_ALLOW: path template → the only fields Firestore sends back (a
 * field mask on every query, applied by guarded_db.js; there is no other
 * way to read).  A collection not listed cannot be read at all.  Outcome
 * collections list only what "done or not" needs — never an answer.
 *
 * DENIED_COLLECTIONS: allocation data (dev-tasks rule 6, 10/20 第 65 条
 * (6)).  Never in READ_ALLOW; guarded_db refuses them even if someone
 * adds one by mistake, and the tests check both.
 *
 * FORBIDDEN_OUTPUT_KEYS: answer / allocation / text field names that must
 * never appear in anything the dashboard sends to the browser or writes
 * to a CSV (leak_guard.js).
 *
 * The one exception (decision 0072, decisions-log 10/20 第 66 条): the
 * daily mood value `mood` is read from users/{uid}/daily_mood
 * (READ_EXCEPTIONS) and may leave only on the person page, at the paths
 * in OUTPUT_ALLOW.person, and only as a number.  Everywhere else — the
 * overview, today, completion, the CSVs — `mood` is still blocked.
 */
'use strict';

const processExport = require('../../../functions/process_export');

const DAY_ROW_FIELDS = ['dayKey', 'studyDay', 'basis', 'opened',
  'firstOpenAt', 'foregroundMinutes', 'validSessions', 'briefPrInvited',
  'briefPrCompleted'];

const SESSION_FIELDS = ['sessionId', 'agentId', 'sessionType', 'startedAt',
  'endedAt', 'endReason', 'userMessageCount', 'userTurnCount', 'isValid',
  'briefPrStatus', 'checkInCompleted'];

// Brief PR scores are process data (10/9 第 17 条 (1); process_export).
const BRIEF_PR_FIELDS = ['sessionId', 'agentId', 'sessionType', 'invitedAt',
  'promptedAt', 'ratedAt', 'respondedAt', 'finalStatus', 'status',
  'understanding', 'validation', 'caring', 'insensitivity', 'studyWeek',
  'studyDay'];

const ALERT_FIELDS = ['uid', 'level', 'category', 'source', 'sourceGroup',
  'createdAt', 'studyDay', 'acknowledgedAt', 'escalatedAt', 'isTester',
  'falseAlarm', 'markedAt', 'eventPath'];

const READ_ALLOW = {
  // Registration record: arm comes from here only (2.3(4)).  Never
  // w0DjgEmotional, stratum or the sequence* / allocatedArm fields.
  'enrollments': ['researchId', 'studyPeriod', 'arm', 'w0Date',
    'enrolledAt'],
  // isTester to hide testers; w4RecordedOn for the W4 window; arm only for
  // tester rows (testers have no registration record).
  'users': ['isTester', 'cohort', 'w4RecordedOn', 'arm'],
  'weekly_status': ['bundles'],
  'pi_alerts': ALERT_FIELDS,
  'safety_events': ['uid'].concat(processExport.SAFETY_FIELDS),
  // W4 paper entries: which instrument was entered, never the answers.
  'outcome_entries': ['researchId', 'instrument', 'timepoint'],
  'ops_daily/{uid}/days': DAY_ROW_FIELDS,
  'users/{uid}/usage_events': ['type', 'clientAt'],
  'users/{uid}/sessions': SESSION_FIELDS,
  'users/{uid}/brief_pr': BRIEF_PR_FIELDS,
  // Never `answers` (Q1 mood and the free-text replies).
  'users/{uid}/check_in_responses': ['date_iso', 'flow', 'completed',
    'stopped_by_safety', 'falseAlarm'],
  // Only the old Hybrid check-in marker; never `params` (answer codes).
  'users/{uid}/events': ['name', 'timestamp'],
  // Decision 0072: the mood value (1–5, MoodRecorder) is shown on the
  // person page; is_primary / entry_seq_today order a day's entries.
  // Never `arm`, `source_surface` or anything else on the entry.
  'users/{uid}/daily_mood': ['date_iso', 'mood', 'is_primary',
    'entry_seq_today'],
  'users/{uid}/weekly_pr': ['status'],
  // Outcome questionnaires: done or not only (decision 0072: shown per
  // week next to the arm), never an answer or a score.
  'users/{uid}/djg_responses': ['status', 'missed'],
  'users/{uid}/social_contact_probes': ['status', 'missed'],
  'users/{uid}/pgic': ['answeredAt', 'missed'],
};

/** users/{uid}/events may only be queried by these names. */
const EVENT_NAMES = ['check_in_submitted'];

/** Config documents read whole (switches and schedule numbers only). */
const CONFIG_DOCS = ['app_config/phase_b', 'app_config/feature_flags'];

const DENIED_COLLECTIONS = ['randomization_sequences', 'randomization_state',
  'sequence_versions', 'arm_assignment_log', 'pilot_assignment_log',
  'allocation_records', 'export_blind_keys', 'research_id_map',
  'correct_arm_log', 'arm_corrections', 'meta'];

const FORBIDDEN_OUTPUT_KEYS = ['answers', 'scores', 'scoringVersion',
  'missingItems', 'value', 'mood', 'w0DjgEmotional', 'stratum',
  'strataCell', 'baselineUclaScore', 'sequencePosition', 'sequenceSha256',
  'sequenceVersion', 'allocatedArm', 'matchedTerm', 'textHash', 'rawValue',
  'finalText', 'editedText', 'ruleText', 'input', 'params',
  'shortTermBuffer', 'raw_output', 'items', 'text', 'before', 'after'];

/** Decision 0072: forbidden-named fields a template may still read. */
const READ_EXCEPTIONS = {'users/{uid}/daily_mood': ['mood']};

/**
 * Decision 0072: where such a field may leave, per page — output paths
 * with array indexes written as [] (leak_guard.findLeaks), number or null
 * only.  The person page's day rows, nothing else.
 */
const OUTPUT_ALLOW = {person: ['$.days[].moods[].mood']};

module.exports = {
  READ_ALLOW, EVENT_NAMES, CONFIG_DOCS, DENIED_COLLECTIONS,
  FORBIDDEN_OUTPUT_KEYS, READ_EXCEPTIONS, OUTPUT_ALLOW, DAY_ROW_FIELDS,
  SESSION_FIELDS, BRIEF_PR_FIELDS, ALERT_FIELDS,
};
