/**
 * T30 (registry C19 / C20; dev-tasks-1010 §四 T30 §3–4 as corrected by
 * dev-tasks-1010b and dev-tasks-1014 §三 T30) — the independent outcome
 * assessor's view, server side.
 *
 * Roles (Auth custom claims, tool/provision_researcher.js):
 *   blinded            the W4 outcome assessors (Keran; backup Mingyan
 *                      Wang).  They get this view and nothing else of the
 *                      dashboard; firestore.rules lets them read NOTHING
 *                      directly — everything below is a role-checked
 *                      callable that returns only what the due list needs.
 *   unblinded          Junyu: registration, process data, pooled completion
 *                      rates (completionSummary, n < 5 hidden).
 *   sequence_uploader  Calvin: functions/sequence_upload.js.
 *
 * Switch: app_config/feature_flags.assessorViewEnabled (OFF unless
 * literally true).  Off, every callable here refuses and the App sends a
 * `blinded` account to the participant App as before.
 * outcomeCompletionSummaryEnabled (same document) gates the pooled rates.
 *
 * What the assessor sees (W4 only — W8 is pushed in the App, T35):
 *   dueList      Phase B AND pilot participants (enrollments.studyPeriod
 *                "B" or "PILOT"; dev-tasks-1014e §2.12 — the three PILOT
 *                elders' W4 is done by Keran too, 1014c §0 item 1):
 *                research ID, the W4 window (day 25–31 from w0Date), today's
 *                study day, whether DJG-ES W4 is entered, out-of-window
 *                flag.  No arm, group code, Brief PR, Weekly PR, usage,
 *                chats, safety events or sequence.
 *   submitEntry  one paper instrument (functions/outcome_instruments.js):
 *                item by item, raw values, missing items, assessment date,
 *                mode (in_person / phone / video), assessor uid, entered-at.
 *                Scores are computed here and never returned.  Stored in
 *                server-only `outcome_entries`; a second submission for the
 *                same research ID / timepoint / instrument is refused —
 *                corrections go through tool/correct_outcome_entry.js with
 *                a reason and a row in `outcome_entry_corrections`.
 *                Out-of-window entries are accepted and marked.
 *                PHQ-9: item 9 ≠ 0 → questionnaire_safety (T34), source
 *                `assessor_entry`.
 *                The W4 assessment date is written to
 *                weekly_status/{uid}.w4VisitDate for T24's week-4 close
 *                (w4VisitDateFor reads it back).
 */

"use strict";

const featureFlags = require("./feature_flags");
const instruments = require("./outcome_instruments");
const qs = require("./questionnaire_safety");
const randomization = require("./randomization");
const djgW2 = require("./djg_w2");

const ASSESSOR_ROLE = "blinded";
const UNBLINDED_ROLE = "unblinded";
const VIEW_FLAG = "assessorViewEnabled";
const SUMMARY_FLAG = "outcomeCompletionSummaryEnabled";
const ENTRIES = "outcome_entries";
const CORRECTIONS = "outcome_entry_corrections";
const WEEKLY_STATUS = "weekly_status";
const TIMEPOINT = "W4";
/**
 * Study periods whose W4 the assessors do (1014e §2.12).  The pooled
 * completion rate (completionSummary) stays Phase B only — the pilot is
 * not part of the trial's outcome denominator (T43 report §5 item 1 left
 * that to the lead; this keeps today's definition).
 */
const ASSESSED_PERIODS = ["B", "PILOT"];
/** W4 window, days after W0 (dev-tasks-1010 §四 T30 §3.2). */
const W4_WINDOW = {start: 25, end: 31};
const MODES = ["in_person", "phone", "video"];
/** The pooled completion rate is hidden below this many participants. */
const MIN_N = 5;
/** Study days (from w0Date) at which each in-App timepoint opens. */
const IN_APP_WINDOWS = {W2: {start: 14, end: 20}};

/**
 * @param {string} code
 * @return {Error}
 */
function assessorError(code) {
  const e = new Error(code);
  e.assessorCode = code;
  return e;
}

/**
 * @param {?object} caller {uid, email, role}
 * @param {string} role
 */
function requireRole(caller, role) {
  if (!caller || caller.role !== role) throw assessorError("not_" + role);
}

/**
 * @param {object} db
 * @param {string} flag
 */
async function requireFlag(db, flag) {
  if (!(await featureFlags.isFeatureEnabled(db, flag))) {
    throw assessorError("disabled");
  }
}

/**
 * Registered participants of the given study periods (testers cannot be
 * registered, so none here).
 * @param {object} db
 * @param {Array<string>} periods enrollments.studyPeriod values
 * @return {Promise<Array<{uid: string, researchId: string, w0Date: string}>>}
 */
async function participantsOf(db, periods) {
  const snap = await db.collection(randomization.ENROLL_COLLECTION)
      .where("studyPeriod", "in", periods).get();
  const out = [];
  for (const d of snap.docs) {
    const e = d.data();
    if (typeof e.w0Date !== "string" || !e.researchId) continue;
    out.push({uid: d.id, researchId: e.researchId, w0Date: e.w0Date});
  }
  out.sort((a, b) => a.w0Date < b.w0Date ? -1 : a.w0Date > b.w0Date ? 1 :
    a.researchId.localeCompare(b.researchId));
  return out;
}

/**
 * Phase B participants only (the pooled completion denominator).
 * @param {object} db
 * @return {Promise<Array<{uid: string, researchId: string, w0Date: string}>>}
 */
function phaseBParticipants(db) {
  return participantsOf(db, ["B"]);
}

/**
 * Everyone the W4 assessors see: Phase B and the pilot (1014e §2.12).
 * @param {object} db
 * @return {Promise<Array<{uid: string, researchId: string, w0Date: string}>>}
 */
function assessedParticipants(db) {
  return participantsOf(db, ASSESSED_PERIODS);
}

/**
 * @param {string} w0Date YYYY-MM-DD
 * @param {string} todayKey
 * @return {{windowStartDate: string, windowEndDate: string,
 *     studyDay: number, windowState: string}} windowState is before /
 *     open / after
 */
function w4Window(w0Date, todayKey) {
  const studyDay = djgW2.daysBetween(w0Date, todayKey);
  const windowState = studyDay < W4_WINDOW.start ? "before" :
    studyDay > W4_WINDOW.end ? "after" : "open";
  return {
    windowStartDate: djgW2.addDays(w0Date, W4_WINDOW.start),
    windowEndDate: djgW2.addDays(w0Date, W4_WINDOW.end),
    studyDay, windowState,
  };
}

/**
 * Submitted entries for one timepoint, by research ID then instrument.
 * @param {object} db
 * @param {string} timepoint
 * @return {Promise<Object<string, Object<string, object>>>}
 */
async function entriesByResearchId(db, timepoint) {
  const snap = await db.collection(ENTRIES)
      .where("timepoint", "==", timepoint).get();
  const out = {};
  for (const d of snap.docs) {
    const e = d.data();
    if (!out[e.researchId]) out[e.researchId] = {};
    out[e.researchId][e.instrument] = {
      assessmentDate: e.assessmentDate || null,
      outOfWindow: e.outOfWindow === true,
    };
  }
  return out;
}

/**
 * The W4 due list.  Only the fields the list needs.
 * @param {object} db admin.firestore()
 * @param {{uid: string, email: ?string, role: ?string}} caller
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{today: string, timepoint: string,
 *     instruments: Array<string>, rows: Array<object>}>}
 */
async function dueList(db, caller, opts) {
  requireRole(caller, ASSESSOR_ROLE);
  await requireFlag(db, VIEW_FLAG);
  const now = (opts && opts.now) || new Date();
  const today = randomization.hkDateKey(now);
  const [people, entered] = await Promise.all([
    assessedParticipants(db), entriesByResearchId(db, TIMEPOINT)]);
  const rows = people.map((p) => {
    const w = w4Window(p.w0Date, today);
    return {
      researchId: p.researchId,
      windowStartDate: w.windowStartDate,
      windowEndDate: w.windowEndDate,
      studyDay: w.studyDay,
      windowState: w.windowState,
      entered: entered[p.researchId] || {},
    };
  });
  // Open windows first, then upcoming, then past.
  const order = {open: 0, before: 1, after: 2};
  rows.sort((a, b) => order[a.windowState] - order[b.windowState] ||
    a.windowStartDate.localeCompare(b.windowStartDate));
  return {today, timepoint: TIMEPOINT, instruments: ["DJG-ES"], rows};
}

/**
 * Store one paper entry.  Never returns a score.
 * @param {object} db
 * @param {{uid: string, email: ?string, role: ?string}} caller
 * @param {{researchId: *, instrument: *, timepoint: *, assessmentDate: *,
 *     mode: *, answers: *, confirmed: *}} input
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{recorded: boolean, researchId: string,
 *     instrument: string, timepoint: string, outOfWindow: boolean,
 *     missingItems: Array<string>}>}
 */
async function submitEntry(db, caller, input, opts) {
  requireRole(caller, ASSESSOR_ROLE);
  await requireFlag(db, VIEW_FLAG);
  const now = (opts && opts.now) || new Date();
  const researchId = randomization.normaliseResearchId(input.researchId);
  if (!researchId) throw assessorError("invalid_research_id");
  const inst = instruments.instrumentFor(input.instrument);
  if (!inst) throw assessorError("unknown_instrument");
  if (input.timepoint !== TIMEPOINT) throw assessorError("invalid_timepoint");
  const assessmentDate = randomization.validW0Date(input.assessmentDate, now);
  if (!assessmentDate) throw assessorError("invalid_assessment_date");
  if (MODES.indexOf(input.mode) < 0) throw assessorError("invalid_mode");
  const v = instruments.validateAnswers(inst, input.answers);
  if (!v) throw assessorError("invalid_answers");
  if (input.confirmed !== true) throw assessorError("not_confirmed");

  const ridSnap = await db.collection("research_ids").doc(researchId).get();
  if (!ridSnap.exists) throw assessorError("unknown_research_id");
  const uid = ridSnap.get("uid");
  const enrol = await db.collection(randomization.ENROLL_COLLECTION)
      .doc(uid).get();
  // 1014e §2.12: Phase B and PILOT entries are accepted; the code name
  // `not_phase_b` is kept for the App's error map.
  if (!enrol.exists ||
      ASSESSED_PERIODS.indexOf(enrol.get("studyPeriod")) < 0) {
    throw assessorError("not_phase_b");
  }
  const w0Date = enrol.get("w0Date");
  const w = w4Window(w0Date, assessmentDate);
  const scores = inst.score(v.answers);

  const entryRef = db.collection(ENTRIES).doc();
  await db.runTransaction(async (tx) => {
    const dup = await tx.get(db.collection(ENTRIES)
        .where("researchId", "==", researchId)
        .where("timepoint", "==", TIMEPOINT)
        .where("instrument", "==", inst.id).limit(1));
    if (!dup.empty) throw assessorError("already_entered");
    tx.create(entryRef, {
      researchId, uid,
      instrument: inst.id, instrumentVersion: inst.version,
      timepoint: TIMEPOINT,
      assessmentDate, mode: input.mode,
      assessorUid: caller.uid, assessorEmail: caller.email || null,
      enteredAt: now,
      answers: v.answers, missingItems: v.missingItems,
      scores, scoringVersion: inst.scoringVersion,
      w0Date, studyDay: w.studyDay,
      windowStartDate: w.windowStartDate, windowEndDate: w.windowEndDate,
      outOfWindow: w.windowState !== "open",
      status: "submitted", correctedAt: null,
    });
    // T24 reads the W4 visit date from here to close the week-4 window.
    tx.set(db.collection(WEEKLY_STATUS).doc(uid), {
      w4VisitDate: assessmentDate, w4EntryAt: now,
      w4EntryInstrument: inst.id,
    }, {merge: true});
  });

  // T34 hook: PHQ-9 item 9 ≠ 0 → safety event, alert whatever the level.
  // The entry is already stored; a failure here must not lose it.
  if (inst.safetyItem) {
    try {
      await qs.recordQuestionnaireSafetyEvent(db, {
        uid, source: "assessor_entry", instrument: inst.id,
        item: inst.safetyItem.item,
        rawValue: v.answers[inst.safetyItem.answerId],
        enteredBy: caller.uid, researchId,
      });
    } catch (err) {
      console.error("assessor entry safety hook failed",
          {entry: entryRef.id, err: String(err && err.message)});
    }
  }
  return {recorded: true, researchId, instrument: inst.id,
    timepoint: TIMEPOINT, outOfWindow: w.windowState !== "open",
    missingItems: v.missingItems};
}

/**
 * For T24: the date the W4 paper assessment was done, or null.
 * @param {object} db
 * @param {string} uid
 * @return {Promise<?string>} YYYY-MM-DD
 */
async function w4VisitDateFor(db, uid) {
  const snap = await db.collection(WEEKLY_STATUS).doc(uid).get();
  const d = snap.exists ? snap.get("w4VisitDate") : null;
  return typeof d === "string" ? d : null;
}

/**
 * Pooled completion per outcome instrument per timepoint — all Phase B
 * participants together, no arm, no person.  Hidden (rate and counts
 * null, `suppressed: true`) when fewer than MIN_N participants have
 * reached the timepoint.  For the unblinded role.
 * @param {object} db
 * @param {{uid: string, role: ?string}} caller
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{today: string, minN: number, rows: Array<object>}>}
 */
async function completionSummary(db, caller, opts) {
  requireRole(caller, UNBLINDED_ROLE);
  await requireFlag(db, SUMMARY_FLAG);
  const now = (opts && opts.now) || new Date();
  const today = randomization.hkDateKey(now);
  const people = await phaseBParticipants(db);
  const rows = [];

  // W4 paper entries, per instrument.
  const entered = await entriesByResearchId(db, TIMEPOINT);
  const dueW4 = people.filter((p) =>
    djgW2.daysBetween(p.w0Date, today) >= W4_WINDOW.start);
  const instIds = Object.keys(instruments.INSTRUMENTS);
  for (const id of instIds) {
    const done = dueW4.filter((p) =>
      entered[p.researchId] && entered[p.researchId][id]).length;
    rows.push(summaryRow(id, TIMEPOINT, dueW4.length, done));
  }

  // In-App W2 DJG (users/{uid}/djg_responses/W2, T18).
  const dueW2 = people.filter((p) =>
    djgW2.daysBetween(p.w0Date, today) >= IN_APP_WINDOWS.W2.start);
  let doneW2 = 0;
  for (const p of dueW2) {
    const s = await db.doc(`users/${p.uid}/djg_responses/W2`).get();
    if (s.exists && s.get("status") === "submitted") doneW2++;
  }
  rows.push(summaryRow("DJG-ES", "W2", dueW2.length, doneW2));
  return {today, minN: MIN_N, rows};
}

/**
 * @param {string} instrument
 * @param {string} timepoint
 * @param {number} n
 * @param {number} completed
 * @return {object}
 */
function summaryRow(instrument, timepoint, n, completed) {
  if (n < MIN_N) {
    return {instrument, timepoint, suppressed: true, n: null,
      completed: null, rate: null};
  }
  return {instrument, timepoint, suppressed: false, n, completed,
    rate: Math.round((completed / n) * 1000) / 1000};
}

/**
 * Admin-only correction (tool/correct_outcome_entry.js).  Changes one
 * item's raw value, the assessment date or the mode; re-scores; logs
 * before / after with the reason.
 * @param {object} db
 * @param {{entryId: string, item: ?string, value: *, assessmentDate: ?string,
 *     mode: ?string, reason: string, operator: string}} p
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{before: object, after: object}>}
 */
async function correctEntry(db, p, opts) {
  const now = (opts && opts.now) || new Date();
  const reason = typeof p.reason === "string" ? p.reason.trim() : "";
  if (reason.length < 10) throw assessorError("reason_required");
  if (!p.operator) throw assessorError("operator_required");
  const ref = db.collection(ENTRIES).doc(p.entryId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw assessorError("entry_not_found");
    const e = snap.data();
    const inst = instruments.instrumentFor(e.instrument);
    if (!inst) throw assessorError("unknown_instrument");
    const before = {};
    const after = {};
    const patch = {};
    if (p.item) {
      const answers = Object.assign({}, e.answers);
      if (!(p.item in answers)) throw assessorError("unknown_item");
      before.answers = {[p.item]: answers[p.item]};
      answers[p.item] = p.value === "skipped" ? inst.missingValue : p.value;
      const v = instruments.validateAnswers(inst, answers);
      if (!v) throw assessorError("invalid_answers");
      after.answers = {[p.item]: v.answers[p.item]};
      patch.answers = v.answers;
      patch.missingItems = v.missingItems;
      patch.scores = inst.score(v.answers);
    }
    if (p.assessmentDate) {
      const d = randomization.validW0Date(p.assessmentDate, now);
      if (!d) throw assessorError("invalid_assessment_date");
      before.assessmentDate = e.assessmentDate;
      after.assessmentDate = d;
      const w = w4Window(e.w0Date, d);
      Object.assign(patch, {assessmentDate: d, studyDay: w.studyDay,
        outOfWindow: w.windowState !== "open"});
      tx.set(db.collection(WEEKLY_STATUS).doc(e.uid),
          {w4VisitDate: d, w4CorrectedAt: now}, {merge: true});
    }
    if (p.mode) {
      if (MODES.indexOf(p.mode) < 0) throw assessorError("invalid_mode");
      before.mode = e.mode;
      after.mode = p.mode;
      patch.mode = p.mode;
    }
    if (Object.keys(patch).length === 0) throw assessorError("nothing_to_do");
    patch.correctedAt = now;
    tx.update(ref, patch);
    tx.create(db.collection(CORRECTIONS).doc(), {
      entryId: p.entryId, researchId: e.researchId, instrument: e.instrument,
      timepoint: e.timepoint, before, after, reason, by: p.operator, at: now,
    });
    return {before, after};
  });
}

module.exports = {
  ASSESSOR_ROLE, UNBLINDED_ROLE, VIEW_FLAG, SUMMARY_FLAG, ENTRIES,
  CORRECTIONS, WEEKLY_STATUS, TIMEPOINT, W4_WINDOW, MODES, MIN_N,
  w4Window, phaseBParticipants, assessedParticipants, participantsOf,
  ASSESSED_PERIODS, dueList, submitEntry, w4VisitDateFor,
  completionSummary, summaryRow, correctEntry,
};
