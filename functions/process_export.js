/**
 * T30 (registry C19 / C20; dev-tasks-1010 §四 T30 §4) — process data vs
 * outcome data before the data lock.
 *
 * Process-data export, for the unblinded researcher (Junyu): Brief PR,
 * Weekly PR, usage, session-level data and safety events with their
 * source, every row with the research ID and the REAL arm.  Written to
 * Cloud Storage under exports_process/{dateKey}/ — a prefix only the
 * server and the `unblinded` role read (storage rules are not in this
 * repo; the T30 report lists the console steps).  Never here: an outcome
 * value — the assessor's W4 entries (`outcome_entries`), the in-App DJG
 * (`djg_responses`, `djg_es`), PGIC, the loneliness / social-contact
 * probes, daily mood — and never conversation text.
 *
 * Switches (meta/blinding_config, server only):
 *   processExportEnabled   default false — write the process export in
 *                          the weekly blindedDataExport run.
 *   outcomeExportPaused    default false — stop writing exports_v2 (the
 *                          outcome-value export) until the data lock; the
 *                          code stays for tool/analysis_export.js.
 *
 * Fields follow the allowlists below; a field not listed is not exported
 * (same principle as functions/blinding.js).  T25 (PR #67) Brief PR v3
 * fields and sessions.isValid / usage_weekly.validSessionCount are in.
 *
 * T49c: `event_counts` — per participant, how many `users/{uid}/events`
 * rows carry each name in COUNTED_EVENTS (only counts, never the event's
 * params), and the manifest's `eventCountsByArm` sums them per arm.  The
 * App writes `s1a_fixed_reply` only while
 * `app_config/feature_flags.s1aEventLogEnabled` is on, so a 0 before the
 * switch was turned on means "not recorded", not "never shown".
 *
 * 1020d §6: `reminiscence_chapters` — one row per weekly 小篇章 (both
 * arms; `source` hybrid / rule): week, status, version, editRatio, how
 * many flags and deleted sentences, failReason, whether the elder saved
 * an edit, and the request / generation / save times.  Never the chapter
 * text, the elder's input, the edit or the check archive (runs/).  The
 * chapter ratings (reminiscence_chapter_ratings) are NOT here: they are
 * scores, possibly an exploratory outcome (1020d §10 (2), Junyu to
 * decide), so they go only into the post-lock analysis export
 * (tool/analysis_export.js).
 */

"use strict";

const blinding = require("./blinding");

const EXPORT_PREFIX = "exports_process";
const EXPORT_VERSION = 1;
const LOG_COLLECTION = "process_export_log";

// users/{uid}/<collection> → exported fields.  No text, no refs.
const PROCESS_COLLECTIONS = {
  brief_pr: [
    // T25 (schemaVersion 3) and the older popup rows (2) share these.
    "schemaVersion", "scheduleVersion", "sessionId", "agentId",
    "sessionType", "endReason", "sessionEndedAt", "lastReplyAt",
    "invitedAt", "invitedDayKey", "inviteChannel", "everShown", "shownAt",
    "ratedAt", "finalStatus", "dueNotInvitedReason",
    "understanding", "validation", "caring", "insensitivity",
    "isAnchorPrompt", "status", "promptedAt", "respondedAt",
    "studyWeek", "studyDay",
  ],
  weekly_pr: [
    "weekIso", "agentId", "items", "status", "promptedAt", "respondedAt",
    "sessionCountThisWeek", "referentRule", "studyWeek", "studyDay",
  ],
  sessions: [
    "sessionId", "agentId", "moduleId", "theme", "startedAt", "endedAt",
    "endReason", "userTurnCount", "fallbackCount", "lastActivityAt",
    "scheduleVersion", "sessionType", "userMessageCount", "replyCount",
    "lastReplyAt", "isValid", "moodRecorded", "summarySaved",
    "isRuleSubmission", "ruleSubmissionCompleted",
    "briefPrInvitedTodayAlready", "briefPrSkippedByCap", "briefPrInvited",
    "briefPrStatus",
    // 1020e 一.(9): the home page the session was started from (page1 /
    // page2 / null), for expired invitations by start page (1020 §1 (4)).
    "entrySurface",
  ],
};

// safety_events: every source (the unblinded researcher may see the AI
// reply scan), plus the T34 analysis bucket; never the text hash's
// origin, the matched term or the wording.
const SAFETY_FIELDS = [
  "source", "level", "tier", "category", "lexiconVersion", "agentId",
  "inputPoint", "createdAt", "instrument", "item", "crisisPageShown",
  "isDuplicate", "escalatedBy",
  // 1020e 二.9: the researcher's 「誤觸」 mark (no text; not who marked).
  "falseAlarm", "markedAt",
];

const SOURCE_GROUP = {
  user_input: "participant_input", form: "participant_input",
  gateway_input: "participant_input", rule_turn: "participant_input",
  m3_turn: "participant_input", ai_output_scan: "ai_reply_scan",
  gateway_output: "ai_reply_scan", questionnaire: "questionnaire",
  assessor_entry: "assessor_entry",
};

// T49c — users/{uid}/events names counted per participant (count only).
const COUNTED_EVENTS = ["s1a_fixed_reply"];

// 1020d — users/{uid}/reminiscence_chapters, metadata only (see top).
const CHAPTER_COLLECTION = "reminiscence_chapters";

/**
 * One chapter doc → its export row (no text).
 * @param {object} d chapter doc data
 * @return {object}
 */
function chapterRow(d) {
  const x = d || {};
  return {
    weekIndex: Number.isInteger(x.weekIndex) ? x.weekIndex : null,
    source: typeof x.source === "string" ? x.source : null,
    status: typeof x.status === "string" ? x.status : null,
    version: Number.isInteger(x.version) ? x.version : null,
    editRatio: typeof x.editRatio === "number" ? x.editRatio : null,
    flagsCount: Array.isArray(x.flags) ? x.flags.length : 0,
    deletedCount: Array.isArray(x.deletedSentences) ?
      x.deletedSentences.length : 0,
    failReason: typeof x.failReason === "string" ? x.failReason : null,
    edited: typeof x.editedText === "string",
    requestedAt: blinding.plain(x.requestedAt),
    generatedAt: blinding.plain(x.generatedAt),
    savedAt: blinding.plain(x.savedAt),
  };
}

/** Outcome collections that must never appear in this export. */
const OUTCOME_COLLECTIONS = [
  "outcome_entries", "djg_responses", "djg_es", "pgic", "loneliness_probes",
  "daily_mood", "ucla3_responses",
];

/**
 * @param {?object} snap meta/blinding_config
 * @return {{processExportEnabled: boolean, outcomeExportPaused: boolean}}
 */
function switchesFromSnap(snap) {
  const d = (snap && snap.exists && snap.data()) || {};
  return {
    processExportEnabled: d.processExportEnabled === true,
    outcomeExportPaused: d.outcomeExportPaused === true,
  };
}

/**
 * Build the process export in memory.  Phase B participants only (cohort
 * phase_b = run-in or rct, not testers; blinding.isBlindedParticipant),
 * research ID instead of uid, real arm.
 * @param {object} db admin.firestore()
 * @param {{dateKey: string}} opts
 * @return {Promise<{files: Object<string, Array<object>>, manifest: object}>}
 */
async function buildProcessExport(db, opts) {
  const files = {participants: [], usage_weekly: [], safety_events: [],
    event_counts: [], reminiscence_chapters: []};
  for (const name of Object.keys(PROCESS_COLLECTIONS)) files[name] = [];
  const eventCountsByArm = {};
  for (const name of COUNTED_EVENTS) eventCountsByArm[name] = {A: 0, B: 0};
  const ridByUid = {};
  const armByUid = {};
  const excluded = {notPhaseB: 0, tester: 0};

  const users = await db.collection("users").get();
  for (const userDoc of users.docs) {
    const u = userDoc.data();
    if (!blinding.isBlindedParticipant(u)) {
      if (u.isTester === true) excluded.tester++;
      else excluded.notPhaseB++;
      continue;
    }
    const map = await db.collection("research_id_map").doc(userDoc.id).get();
    const researchId = map.exists ? map.get("researchId") : null;
    if (!researchId) continue; // not registered through enrollParticipant
    ridByUid[userDoc.id] = researchId;
    armByUid[userDoc.id] = u.arm;
    files.participants.push({researchId, arm: u.arm,
      strataCell: u.strataCell == null ? null : u.strataCell,
      w0Date: u.w0Date || null,
      cohort: u.cohort || null});

    for (const name of Object.keys(PROCESS_COLLECTIONS)) {
      const sub = await userDoc.ref.collection(name).get();
      for (const d of sub.docs) {
        files[name].push(Object.assign({researchId, arm: u.arm},
            blinding.pick(d.data(), PROCESS_COLLECTIONS[name])));
      }
    }
    // 1020d — chapter metadata; the text, input and archive stay behind.
    const chapters = await userDoc.ref.collection(CHAPTER_COLLECTION).get();
    for (const d of chapters.docs) {
      files.reminiscence_chapters.push(Object.assign({researchId,
        arm: u.arm}, chapterRow(d.data())));
    }
    // T49c — event counts by name; the rows' params are never read.
    for (const name of COUNTED_EVENTS) {
      const agg = await userDoc.ref.collection("events")
          .where("name", "==", name).count().get();
      const count = agg.data().count;
      files.event_counts.push({researchId, arm: u.arm, name, count});
      if (eventCountsByArm[name][u.arm] !== undefined) {
        eventCountsByArm[name][u.arm] += count;
      }
    }
    // Usage per ISO week: sessions, valid sessions (T25), active days.
    const byWeek = {};
    for (const s of files.sessions.filter((r) => r.researchId === researchId)) {
      // 1014e §2.1: attributed by the session's end, else its start.
      const at = blinding.sessionWeekAnchor(s.endedAt, s.startedAt);
      if (!at) continue;
      const week = blinding.isoWeekHk(at);
      const day = new Date(at.getTime() + 8 * 3600 * 1000).toISOString()
          .slice(0, 10);
      if (!byWeek[week]) byWeek[week] = {sessions: 0, valid: 0, days: {}};
      byWeek[week].sessions++;
      if (s.isValid === true) byWeek[week].valid++;
      byWeek[week].days[day] = true;
    }
    for (const week of Object.keys(byWeek).sort()) {
      files.usage_weekly.push({researchId, arm: u.arm, isoWeek: week,
        weekBasis: blinding.USAGE_WEEK_BASIS,
        sessionCount: byWeek[week].sessions,
        validSessionCount: byWeek[week].valid,
        activeDays: Object.keys(byWeek[week].days).length});
    }
  }

  const safety = await db.collection("safety_events").get();
  for (const d of safety.docs) {
    const e = d.data();
    const researchId = ridByUid[e.uid];
    if (!researchId) continue;
    files.safety_events.push(Object.assign(
        {researchId, arm: armByUid[e.uid],
          sourceGroup: SOURCE_GROUP[e.source] || "other"},
        blinding.pick(e, SAFETY_FIELDS)));
  }

  const rowCounts = {};
  for (const name of Object.keys(files)) rowCounts[name] = files[name].length;
  return {files, manifest: {
    exportVersion: EXPORT_VERSION, kind: "process", dateKey: opts.dateKey,
    rowCounts, excludedParticipants: excluded, eventCountsByArm,
    neverHere: OUTCOME_COLLECTIONS.concat(["turns", "conversation text"]),
    note: "Process data for the unblinded researcher: research ID and " +
      "real arm; no outcome values before the data lock.",
  }};
}

/**
 * Write to Cloud Storage under exports_process/{dateKey}/.
 * @param {object} bucket
 * @param {{files: object, manifest: object}} built
 * @param {string} dateKey
 * @return {Promise<number>} files written
 */
async function writeProcessExport(bucket, built, dateKey) {
  const writes = [];
  for (const name of Object.keys(built.files)) {
    const rows = built.files[name];
    if (rows.length === 0) continue;
    writes.push(bucket.file(`${EXPORT_PREFIX}/${dateKey}/${name}.ndjson`)
        .save(rows.map((r) => JSON.stringify(r)).join("\n"), {
          resumable: false, contentType: "application/x-ndjson",
        }));
  }
  writes.push(bucket.file(`${EXPORT_PREFIX}/${dateKey}/manifest.json`)
      .save(JSON.stringify(built.manifest, null, 2), {
        resumable: false, contentType: "application/json",
      }));
  await Promise.all(writes);
  return writes.length;
}

/**
 * Does any row carry an outcome value or text?  Used by the tests and by
 * the export itself as a last check (throws).
 * @param {{files: object}} built
 * @return {Array<string>} offending "file.field" names
 */
function leakCheck(built) {
  const bad = [];
  const forbidden = new RegExp("^(text|message|content|reply|prompt|quote|" +
    "summary|value|score|scores|answers|mood|matchedTerm|snippet|" +
    "finalText|ruleText|editedText|input|rounds|deletedSentences)$", "i");
  for (const name of Object.keys(built.files)) {
    if (OUTCOME_COLLECTIONS.indexOf(name) >= 0) bad.push(name);
    for (const row of built.files[name]) {
      for (const k of Object.keys(row)) {
        if (forbidden.test(k)) bad.push(`${name}.${k}`);
      }
    }
  }
  return Array.from(new Set(bad));
}

module.exports = {
  EXPORT_PREFIX, EXPORT_VERSION, LOG_COLLECTION, PROCESS_COLLECTIONS,
  SAFETY_FIELDS, SOURCE_GROUP, COUNTED_EVENTS, OUTCOME_COLLECTIONS,
  CHAPTER_COLLECTION, chapterRow, switchesFromSnap,
  buildProcessExport, writeProcessExport, leakCheck,
};
