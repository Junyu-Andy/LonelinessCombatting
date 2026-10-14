/**
 * T34 — safety events raised by a questionnaire answer (registry v9 C12;
 * dev-tasks-1010b §三 T34 §4, corrected by dev-tasks-1014 §三 T34).
 *
 * Two server-only sources of `safety_events`:
 *
 *   questionnaire    an in-App questionnaire item.  Today NO item calls
 *                    this: the App has no PHQ-9 and W8 does not push one
 *                    (dev-tasks-1014 §三 T34 1).  The entry point and its
 *                    tests exist so a future item can be wired without a
 *                    code-structure change.
 *   assessor_entry   the W4 paper PHQ-9 entered by the assessor: item 9
 *                    (thoughts of death / self-harm) not 0.  T30's entry
 *                    page calls `recordQuestionnaireSafetyEvent` when the
 *                    entry is submitted (PHQ-9 spec file pending).
 *
 * Both alert whatever the level (`alwaysAlert: true`; pi_alert.js
 * `alwaysAlerts`).  The event carries the instrument, the item number and
 * that item's raw value only — never the other answers.  firestore.rules
 * refuses these sources and `alwaysAlert` from any client.
 *
 * Level for "PHQ-9 item 9 ≠ 0" (default, open for the research side to
 * change — see the T34 report 要 Junyu 定的事): every non-zero answer is
 * recorded as tier `acute` (legacy level `acute`), category `ideation`.
 * The alert goes out whatever the level, so the mapping only affects how
 * the row is counted (B12) and shown in the dashboard; `acute` is the
 * fail-safe side.  A caller may pass `level` to override.
 */

"use strict";

const SOURCES = ["questionnaire", "assessor_entry"];
const LEVELS = ["moderate_review", "moderate_interrupt", "acute"];
const LEGACY_LEVEL = {moderate_review: "moderate", moderate_interrupt:
  "moderate", acute: "acute"};
const DEFAULT_CATEGORY = "ideation";

/** PHQ-9 item 9 (0–3): 0 = not at all → no event. */
const PHQ9 = {instrument: "PHQ-9", item: 9};

/**
 * Should this answer raise an event?  Only item 9 of the PHQ-9 is a
 * trigger today; any value other than 0 counts.
 * @param {{instrument: string, item: number, rawValue: *}} a
 * @return {boolean}
 */
function triggers(a) {
  if (!a || a.instrument !== PHQ9.instrument || a.item !== PHQ9.item) {
    return false;
  }
  const v = Number(a.rawValue);
  return Number.isInteger(v) && v !== 0;
}

/**
 * Error with a code the caller can map.
 * @param {string} code
 * @return {Error}
 */
function bad(code) {
  const e = new Error(code);
  e.questionnaireCode = code;
  return e;
}

/**
 * Write one `safety_events` document for a triggering answer.  Returns
 * null (writes nothing) when the answer does not trigger — so T30 can call
 * it for every PHQ-9 entry and let it decide.
 * @param {object} db admin.firestore()
 * @param {{uid: string, source: string, instrument: string, item: number,
 *     rawValue: *, enteredBy: ?string, researchId: ?string,
 *     level: ?string, serverTimestamp: ?function(): *}} p
 * @return {Promise<?{id: string, path: string, level: string,
 *     tier: string}>}
 */
async function recordQuestionnaireSafetyEvent(db, p) {
  if (!p || typeof p.uid !== "string" || !p.uid.trim()) throw bad("uid");
  if (SOURCES.indexOf(p.source) < 0) throw bad("source");
  if (typeof p.instrument !== "string" || !p.instrument) {
    throw bad("instrument");
  }
  if (!Number.isInteger(p.item)) throw bad("item");
  if (!triggers({instrument: p.instrument, item: p.item,
    rawValue: p.rawValue})) {
    return null;
  }
  const tier = p.level && LEVELS.indexOf(p.level) >= 0 ? p.level : "acute";
  const stamp = p.serverTimestamp ? p.serverTimestamp() : new Date();
  const now = Date.now();
  const doc = {
    uid: p.uid.trim(),
    source: p.source,
    instrument: p.instrument,
    item: p.item,
    rawValue: Number(p.rawValue),
    enteredBy: p.enteredBy || null,
    researchId: p.researchId || null,
    level: LEGACY_LEVEL[tier],
    tier,
    category: DEFAULT_CATEGORY,
    alwaysAlert: true,
    // Each entry is its own "turn" so onSafetyEventCreated's dedup never
    // merges two entries (without this it keys on textHash + minute).
    turnId: `q-${p.source}-${p.instrument}-${p.item}-${now}`,
    textHash: null,
    inputPoint: p.source === "assessor_entry" ? "assessor_paper_entry" :
      "in_app_questionnaire",
    createdAt: stamp,
  };
  const ref = await db.collection("safety_events").add(doc);
  return {id: ref.id, path: ref.path, level: doc.level, tier};
}

module.exports = {
  SOURCES, LEVELS, DEFAULT_CATEGORY, PHQ9, triggers,
  recordQuestionnaireSafetyEvent,
};
