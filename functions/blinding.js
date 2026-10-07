/**
 * T12 blinding (SPEC:C19, decision 0021).
 *
 * Two pieces:
 *
 * 1. Research IDs.  Every randomised participant gets one stable,
 *    random research ID (e.g. "P7K3QX2").  The server writes it — at arm
 *    assignment, or as a backfill when the export first meets the
 *    participant — into two lookup collections that only the unblinded
 *    role can read (firestore.rules):
 *      research_id_map/{uid}       → {researchId}
 *      research_ids/{researchId}   → {uid}
 *    The ID is never written to users/{uid}, so the app never sees it.
 *
 * 2. The v2 blinded export.  An allowlist: only outcome questionnaires
 *    common to both arms, plus a few neutral participant fields, are
 *    exported.  Every row carries researchId + a groupCode (Group_X /
 *    Group_Y) whose mapping is fixed for the whole trial
 *    (export_blind_keys/stable_v2), so files from different weeks join.
 *    Process data (turns, sessions, events, llm_*, mem_*, ...) is held
 *    back until unblinding — see HELD_BACK below.
 *
 * Switch: meta/blinding_config.enabled (default false).  Off = assignArm
 * writes no research ID and blindedDataExport runs the old export
 * unchanged.
 */

"use strict";

const crypto = require("crypto");

const CONFIG_DOC = "meta/blinding_config";
const STABLE_KEY_DOC = "export_blind_keys/stable_v2";
const EXPORT_PREFIX = "exports_v2";
const EXPORT_VERSION = 2;

// Crockford base32: no I, L, O, U — easy to read aloud and copy by hand.
const RID_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const RID_LENGTH = 6;
const RID_PATTERN = /^P[0-9A-HJKMNP-TV-Z]{6}$/;
const RID_MAX_TRIES = 8;

/**
 * @param {object} db admin.firestore()
 * @return {Promise<{enabled: boolean, includeUsageSummary: boolean,
 *     includeBriefPr: boolean}>}
 */
async function readBlindingConfig(db) {
  const snap = await db.doc(CONFIG_DOC).get();
  return configFromSnap(snap);
}

/**
 * @param {object} snap DocumentSnapshot of meta/blinding_config
 * @return {{enabled: boolean, includeUsageSummary: boolean,
 *     includeBriefPr: boolean}}
 */
function configFromSnap(snap) {
  const data = (snap && snap.exists && snap.data()) || {};
  return {
    enabled: data.enabled === true,
    includeUsageSummary: data.includeUsageSummary === true,
    includeBriefPr: data.includeBriefPr === true,
  };
}

/**
 * @param {function(number): number} randomInt returns 0..n-1
 * @return {string} e.g. "P7K3QX2"
 */
function newResearchId(randomInt) {
  let s = "P";
  for (let i = 0; i < RID_LENGTH; i++) {
    s += RID_ALPHABET[randomInt(RID_ALPHABET.length)];
  }
  return s;
}

const defaultRandomInt = (n) => crypto.randomInt(n);

/**
 * Transaction read phase: find the participant's research ID, or pick a
 * free one.  Call before any tx write, then pass the result to
 * [writeResearchIdTx].
 *
 * @param {object} tx Firestore transaction
 * @param {object} db admin.firestore()
 * @param {string} uid
 * @param {(function(number): number)=} randomInt defaults to crypto
 * @return {Promise<{researchId: string, isNew: boolean}>}
 */
async function planResearchIdTx(tx, db, uid, randomInt) {
  randomInt = randomInt || defaultRandomInt;
  const mapRef = db.collection("research_id_map").doc(uid);
  const existing = await tx.get(mapRef);
  if (existing.exists && RID_PATTERN.test(existing.get("researchId"))) {
    return {researchId: existing.get("researchId"), isNew: false};
  }
  for (let i = 0; i < RID_MAX_TRIES; i++) {
    const candidate = newResearchId(randomInt);
    const taken = await tx.get(db.collection("research_ids").doc(candidate));
    if (!taken.exists) return {researchId: candidate, isNew: true};
  }
  throw new Error("research_id_exhausted");
}

/**
 * Transaction write phase for [planResearchIdTx].
 * @param {object} tx
 * @param {object} db
 * @param {string} uid
 * @param {{researchId: string, isNew: boolean}} plan
 * @param {string} via "assign_arm" | "export_backfill"
 */
function writeResearchIdTx(tx, db, uid, plan, via) {
  if (!plan.isNew) return;
  const now = new Date();
  tx.create(db.collection("research_ids").doc(plan.researchId),
      {uid, createdAt: now, via});
  tx.set(db.collection("research_id_map").doc(uid),
      {researchId: plan.researchId, createdAt: now, via});
}

/**
 * Return the participant's research ID, creating it if needed.
 * Idempotent and safe under concurrency (one transaction).
 *
 * @param {object} db
 * @param {string} uid
 * @param {{randomInt: (function(number): number|undefined),
 *     via: (string|undefined)}} opts
 * @return {Promise<string>}
 */
async function ensureResearchId(db, uid, opts = {}) {
  return db.runTransaction(async (tx) => {
    const plan = await planResearchIdTx(tx, db, uid, opts.randomInt);
    writeResearchIdTx(tx, db, uid, plan, opts.via || "export_backfill");
    return plan.researchId;
  });
}

/**
 * The fixed A/B → Group_X/Group_Y mapping for the whole trial.  Created
 * once, never rotated (the old weekly rotation made Group_X mean a
 * different arm from one week's files to the next).
 *
 * @param {object} db
 * @param {function(): number} rng
 * @return {Promise<{A: string, B: string}>}
 */
async function stableArmMapping(db, rng) {
  const ref = db.doc(STABLE_KEY_DOC);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists && snap.get("mapping")) return snap.get("mapping");
    const mapping = rng() < 0.5 ?
      {A: "Group_X", B: "Group_Y"} :
      {A: "Group_Y", B: "Group_X"};
    tx.create(ref, {mapping, createdAt: new Date()});
    return mapping;
  });
}

// ---------------------------------------------------------------------------
// What the v2 export contains.
// ---------------------------------------------------------------------------

// Participant fields.  Everything else on users/{uid} stays out (PII, free
// text, arm bookkeeping, memory flags).
const PARTICIPANT_FIELDS = [
  "strataCell", "ageGroup", "baselineUclaScore", "hasCompletedIntake",
];

// Brief PR pops up after every rule-arm submission but only after 2+ turns
// in the Hybrid arm (decision 0015, brief_pr_gate.dart), so the number of
// rows per person points at the arm.  Exported only with includeBriefPr.
const OPTIONAL_COLLECTIONS = ["brief_pr"];

// users/{uid}/<collection> → exported fields.  Outcome measures that both
// arms answer.  Dropped on purpose: brief_pr.sessionRef (session ids),
// weekly_pr.sessionCountThisWeek/referentRule (usage-derived),
// agent_diff.freeResponse (free text), daily_mood.source_surface,
// every `arm` (replaced by groupCode).
// Never here: ada_responses and day7_open_responses (T17, decision 0026)
// are Phase A only and stay out of the Phase B blinded export.
const OUTCOME_COLLECTIONS = {
  brief_pr: [
    "schemaVersion", "agentId", "understanding", "validation", "caring",
    "insensitivity", "isAnchorPrompt", "status", "promptedAt",
    "respondedAt",
  ],
  weekly_pr: [
    "weekIso", "agentId", "items", "status", "promptedAt", "respondedAt",
  ],
  pgic: ["value", "isoWeek", "weekIso", "answeredAt"],
  djg_es: [
    "timepoint", "itemsVersion", "answers", "score", "status", "answeredAt",
  ],
  // T18 (decision 0027): W2 DJG, 6 items.  Raw answers + server scores;
  // nothing in it differs by arm.
  djg_responses: [
    "timepoint", "itemsVersion", "answers", "status", "scores",
    "scoringVersion", "outsideWindow", "w0Date", "windowStartDate",
    "windowEndDate", "pushSentAt", "reminderSentAt", "startedAt",
    "submittedAt", "missedAt",
  ],
  agent_diff: [
    "wave", "timepoint", "usageFreq", "personality", "function", "answeredAt",
  ],
  daily_mood: [
    "mood", "date_iso", "is_primary", "entry_seq_today", "prompted_at",
    "responded_at",
  ],
  loneliness_probes: ["score", "isoWeek", "answeredAt"],
};

// safety_events: only events raised by what the participant typed.  The
// AI-output scan exists only in the Hybrid arm, so those rows (and the
// `source` field, whose values differ by arm) never leave.
const SAFETY_USER_SOURCES = [
  "gateway_input", "m3_turn", "rule_turn", "user_input", "form",
];
const SAFETY_FIELDS = [
  "level", "tier", "category", "lexiconVersion", "agentId", "createdAt",
];

// Held back until unblinding.  Listed so the manifest says so explicitly.
const HELD_BACK = [
  "turns", "sessions", "events", "llm_turn_features", "llm_calls",
  "thought_exercise", "action_plans", "reminders", "response_feedback",
  "tester_feedback", "ppr_responses", "check_in_responses",
  "agent_contexts", "agent_greetings", "shared_context", "memory",
  "mem_extractions", "mem_facts", "mem_summaries", "mem_followups",
  "mem_injections", "cross_module_callbacks", "onboarding",
  "pi_alerts", "te_audit_queue", "safety_event_dedup", "stt_usage",
];

/**
 * Firestore values → plain JSON.  Timestamps become ISO strings.
 * @param {*} v
 * @return {*}
 */
function plain(v) {
  if (v === null || v === undefined) return null;
  if (v instanceof Date) return v.toISOString();
  if (typeof v.toDate === "function") return v.toDate().toISOString();
  // A DocumentReference carries the raw uid in its path: never export it.
  if (typeof v.path === "string" && v.firestore) return null;
  if (Array.isArray(v)) return v.map(plain);
  if (typeof v === "object") {
    const out = {};
    for (const k of Object.keys(v)) out[k] = plain(v[k]);
    return out;
  }
  return v;
}

/**
 * @param {object} data
 * @param {Array<string>} fields
 * @return {object}
 */
function pick(data, fields) {
  const out = {};
  for (const f of fields) {
    if (Object.prototype.hasOwnProperty.call(data, f)) out[f] = plain(data[f]);
  }
  return out;
}

/**
 * Is this profile a randomised (Phase B) participant?  Phase A / pilot
 * accounts are all Arm A, so letting them in would give the mapping away
 * (decision 0011 cohort; armAssignmentMode until cohort exists).
 * Testers are left out too.
 * @param {object} u users/{uid} data
 * @return {boolean}
 */
function isBlindedParticipant(u) {
  if (u.arm !== "A" && u.arm !== "B") return false;
  if (u.isTester === true) return false;
  if (typeof u.cohort === "string") return u.cohort === "phase_b";
  return u.armAssignmentMode === "randomise";
}

/**
 * ISO week label (e.g. "2026-W41") for a Date, UTC+8.
 * @param {Date} d
 * @return {string}
 */
function isoWeekHk(d) {
  const t = new Date(d.getTime() + 8 * 3600 * 1000);
  const day = (t.getUTCDay() + 6) % 7; // Mon=0
  t.setUTCDate(t.getUTCDate() - day + 3); // Thursday of this week
  const firstThu = new Date(Date.UTC(t.getUTCFullYear(), 0, 4));
  const week = 1 + Math.round(
      ((t - firstThu) / 86400000 - 3 + ((firstThu.getUTCDay() + 6) % 7)) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

/**
 * Build the v2 blinded export in memory.
 *
 * @param {object} db admin.firestore()
 * @param {{dateKey: string, includeUsageSummary: boolean,
 *     includeBriefPr: boolean,
 *     rng: (function(): number|undefined),
 *     randomInt: (function(number): number|undefined)}} opts
 * @return {Promise<{files: Object<string, Array<object>>,
 *     manifest: object}>}
 */
async function buildBlindedExport(db, opts) {
  const rng = opts.rng || Math.random;
  const mapping = await stableArmMapping(db, rng);
  const files = {participants: []};
  const outcomes = Object.keys(OUTCOME_COLLECTIONS).filter((n) =>
    opts.includeBriefPr || OPTIONAL_COLLECTIONS.indexOf(n) < 0);
  for (const name of outcomes) files[name] = [];
  files.safety_events = [];
  if (opts.includeUsageSummary) files.usage_weekly = [];

  const excluded = {notRandomised: 0, tester: 0};
  const ridByUid = {};
  const groupByUid = {};

  const usersSnap = await db.collection("users").get();
  for (const userDoc of usersSnap.docs) {
    const u = userDoc.data();
    if (!isBlindedParticipant(u)) {
      if (u.isTester === true) excluded.tester++;
      else excluded.notRandomised++;
      continue;
    }
    const researchId = await ensureResearchId(db, userDoc.id, {
      randomInt: opts.randomInt, via: "export_backfill",
    });
    const groupCode = mapping[u.arm];
    ridByUid[userDoc.id] = researchId;
    groupByUid[userDoc.id] = groupCode;

    const created = plain(u.createdAt);
    files.participants.push(Object.assign({researchId, groupCode},
        pick(u, PARTICIPANT_FIELDS),
        {enrolledDate: typeof created === "string" ?
          created.slice(0, 10) : null}));

    for (const name of outcomes) {
      const sub = await userDoc.ref.collection(name).get();
      for (const d of sub.docs) {
        files[name].push(Object.assign({researchId, groupCode},
            pick(d.data(), OUTCOME_COLLECTIONS[name])));
      }
    }

    if (opts.includeUsageSummary) {
      const sessions = await userDoc.ref.collection("sessions").get();
      const byWeek = {};
      for (const s of sessions.docs) {
        const started = s.get("startedAt");
        if (!started || typeof started.toDate !== "function") continue;
        const at = started.toDate();
        const week = isoWeekHk(at);
        const day = new Date(at.getTime() + 8 * 3600 * 1000)
            .toISOString().slice(0, 10);
        if (!byWeek[week]) byWeek[week] = {sessions: 0, days: {}};
        byWeek[week].sessions++;
        byWeek[week].days[day] = true;
      }
      for (const week of Object.keys(byWeek).sort()) {
        files.usage_weekly.push({researchId, groupCode, isoWeek: week,
          sessionCount: byWeek[week].sessions,
          activeDays: Object.keys(byWeek[week].days).length});
      }
    }
  }

  let safetyDropped = 0;
  const safety = await db.collection("safety_events").get();
  for (const d of safety.docs) {
    const e = d.data();
    const researchId = ridByUid[e.uid];
    if (!researchId) continue; // not a blinded participant
    if (SAFETY_USER_SOURCES.indexOf(e.source) < 0) {
      safetyDropped++;
      continue;
    }
    files.safety_events.push(Object.assign(
        {researchId, groupCode: groupByUid[e.uid]},
        pick(e, SAFETY_FIELDS)));
  }

  const rowCounts = {};
  for (const name of Object.keys(files)) rowCounts[name] = files[name].length;
  const manifest = {
    exportVersion: EXPORT_VERSION,
    dateKey: opts.dateKey,
    rowCounts,
    excludedParticipants: excluded,
    safetyEventsNotFromUserInput: safetyDropped,
    heldBackUntilUnblinding: opts.includeBriefPr ? HELD_BACK :
      HELD_BACK.concat(OPTIONAL_COLLECTIONS),
    note: "Group_X/Group_Y mapping is fixed for the trial; " +
      "researchId is stable across weeks.",
  };
  return {files, manifest};
}

/**
 * Write a built export to Cloud Storage under exports_v2/{dateKey}/.
 * @param {object} bucket admin.storage().bucket()
 * @param {{files: object, manifest: object}} built
 * @param {string} dateKey
 * @return {Promise<number>} files written
 */
async function writeBlindedExport(bucket, built, dateKey) {
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

module.exports = {
  CONFIG_DOC, STABLE_KEY_DOC, EXPORT_PREFIX, RID_PATTERN,
  OUTCOME_COLLECTIONS, OPTIONAL_COLLECTIONS, PARTICIPANT_FIELDS,
  SAFETY_USER_SOURCES, HELD_BACK,
  readBlindingConfig, configFromSnap, newResearchId, planResearchIdTx,
  writeResearchIdTx, ensureResearchId, stableArmMapping,
  isBlindedParticipant, isoWeekHk, plain, buildBlindedExport,
  writeBlindedExport,
};
