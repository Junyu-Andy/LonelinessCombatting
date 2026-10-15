/**
 * T47 — the researcher records the (shortened) intake for an elder
 * (dev-tasks-1015-intake §2.1).  Five answers, asked out loud at the W0
 * visit, written by the `unblinded` researcher through a callable:
 *
 *   users/{uid}/onboarding/intake   the IntakeResponse document the App's
 *                                   own questionnaire used to write
 *                                   (merge: an older six-part answer set
 *                                   keeps its extra fields)
 *   users/{uid}                     hasCompletedIntake, interests,
 *                                   closeContacts, avoidTopics, inputMode
 *   intake_audit_log/{id}           who recorded what for whom (server
 *                                   only; no answer text)
 *
 * Only the caller's role is checked (`unblinded`); the App-side switch
 * `app_config/feature_flags.researcherIntakeEnabled` decides whether the
 * elder still sees a questionnaire, not whether the researcher may record.
 * Both arms identical; no LLM anywhere here.
 */

"use strict";

const intakeDocPath = (uid) => `users/${uid}/onboarding/intake`;
const AUDIT_COLLECTION = "intake_audit_log";
const UNBLINDED_ROLE = "unblinded";

/** Q1 — IntakeOptions.mainGoal* ids (lib/features/onboarding/data). */
const MAIN_GOALS = ["companionship", "emotional_outlet", "reconnect_others",
  "learning", "share_memories", "curious"];
const MAX_GOALS = 2;
/** Q2 — up to three people, a name (what the elder calls them) + relation. */
const MAX_PEOPLE = 3;
const MAX_NAME = 20;
/** Q3 — InterestLabels ids (lib/features/onboarding/data/interest_labels). */
const INTERESTS = ["yum_cha", "cooking", "wet_market", "buffet", "tv_drama",
  "radio", "reading", "mahjong", "gardening", "chatting", "hiking",
  "park_walk", "tai_chi", "swimming", "cantonese_opera", "museums",
  "elderly_centre", "religious", "visit_friends", "volunteering",
  "meditation", "prayer", "news"];
const MAX_INTERESTS = 3;
const MAX_OTHER = 40;
/** Q4 — free text, may be empty. */
const MAX_AVOID = 200;
/** Q5 — IntakeOptions.input* ids. */
const INPUT_MODES = ["typing", "voice", "both", "unsure"];

/**
 * @param {string} code
 * @return {Error}
 */
function intakeError(code) {
  const e = new Error(code);
  e.intakeCode = code;
  return e;
}

const str = (v) => (typeof v === "string" ? v.trim() : "");

/**
 * Validate and normalise the five answers.  Throws intakeError.
 * @param {object} raw request data
 * @return {{mainGoals: string[], people: Array<{name: string,
 *     relationship: string}>, interests: string[], interestsOther: ?string,
 *     avoidTopics: ?string, inputMode: string}}
 */
function normaliseAnswers(raw) {
  const d = raw || {};
  const goals = Array.isArray(d.mainGoals) ? d.mainGoals.map(str) : [];
  if (goals.length > MAX_GOALS) throw intakeError("too_many_goals");
  for (const g of goals) {
    if (MAIN_GOALS.indexOf(g) < 0) throw intakeError("invalid_goal");
  }
  const peopleRaw = Array.isArray(d.importantPeople) ? d.importantPeople : [];
  if (peopleRaw.length > MAX_PEOPLE) throw intakeError("too_many_people");
  const people = [];
  for (const p of peopleRaw) {
    const name = str(p && p.name);
    const rel = str(p && p.relationship);
    if (!name) continue; // an empty row is simply skipped
    if (name.length > MAX_NAME || rel.length > MAX_NAME) {
      throw intakeError("name_too_long");
    }
    people.push({name, relationship: rel});
  }
  const interests = Array.isArray(d.interests) ? d.interests.map(str) : [];
  if (interests.length > MAX_INTERESTS) throw intakeError("too_many_interests");
  for (const i of interests) {
    if (INTERESTS.indexOf(i) < 0) throw intakeError("invalid_interest");
  }
  const other = str(d.interestsOther);
  if (other.length > MAX_OTHER) throw intakeError("other_too_long");
  const avoid = str(d.avoidTopics);
  if (avoid.length > MAX_AVOID) throw intakeError("avoid_too_long");
  const mode = str(d.inputMode) || "unsure";
  if (INPUT_MODES.indexOf(mode) < 0) throw intakeError("invalid_input_mode");
  return {mainGoals: goals, people, interests,
    interestsOther: other || null, avoidTopics: avoid || null,
    inputMode: mode};
}

/**
 * Resolve the elder's uid from a research ID (research_ids/{id}.uid).
 * The callable wrapper resolves an email through Auth before calling.
 * @param {object} db
 * @param {string} researchId
 * @return {Promise<string>} uid or ""
 */
async function uidForResearchId(db, researchId) {
  const rid = str(researchId).toUpperCase();
  if (!rid) return "";
  const snap = await db.collection("research_ids").doc(rid).get();
  return snap.exists ? (snap.get("uid") || "") : "";
}

/**
 * Record the intake.  Pure of Auth: the wrapper passes `uid` already
 * resolved (email → Auth, or research ID → research_ids).
 * @param {object} db
 * @param {{uid: string, email: ?string, role: ?string}} caller
 * @param {{uid: string, answers: object}} input
 * @param {{now: (Date|undefined)}=} opts
 * @return {Promise<{uid: string, researchId: ?string, recordedAt: string,
 *     interests: string[], people: number}>}
 */
async function recordIntake(db, caller, input, opts) {
  const now = (opts && opts.now) || new Date();
  if (!caller || caller.role !== UNBLINDED_ROLE) {
    throw intakeError("not_unblinded_researcher");
  }
  const uid = str(input && input.uid);
  if (!uid) throw intakeError("account_not_found");
  if (uid === caller.uid) throw intakeError("own_account");
  const a = normaliseAnswers(input.answers);

  const userRef = db.collection("users").doc(uid);
  const intakeRef = db.doc(intakeDocPath(uid));
  const mapRef = db.collection("research_id_map").doc(uid);
  const [user, map] = await Promise.all([userRef.get(), mapRef.get()]);
  if (!user.exists) throw intakeError("account_not_found");
  const u = user.data() || {};
  if (u.isTester === true) throw intakeError("tester_account");
  const researchId = map.exists ? (map.get("researchId") || null) : null;
  if (!researchId) throw intakeError("not_enrolled");

  const iso = now.toISOString();
  const intake = {
    mainGoals: a.mainGoals,
    importantPeople: a.people.map((p) =>
      ({name: p.name, relationship: p.relationship, extra: null})),
    activities: a.interests,
    activitiesOther: a.interestsOther,
    avoidTopics: a.avoidTopics,
    inputMode: a.inputMode,
    updatedAt: iso,
    completedParts: [1, 2, 3, 4, 5, 6],
    allCompleted: true,
    // T47 provenance
    source: "researcher",
    recordedBy: caller.uid,
    recordedByEmail: caller.email || null,
    recordedAt: iso,
    schemaVersion: 2,
  };
  const existing = await intakeRef.get();
  if (!existing.exists) intake.createdAt = iso;

  const batch = db.batch();
  batch.set(intakeRef, intake, {merge: true});
  batch.set(userRef, {
    hasCompletedIntake: true,
    interests: a.interests,
    closeContacts: a.people.map((p) =>
      ({name: p.name, relation: p.relationship || null, phone: null})),
    avoidTopics: a.avoidTopics,
    inputMode: a.inputMode,
    intakeRecordedAt: now,
  }, {merge: true});
  batch.create(db.collection(AUDIT_COLLECTION).doc(), {
    at: now, by: caller.uid, byEmail: caller.email || null,
    uid, researchId,
    fields: {goals: a.mainGoals.length, people: a.people.length,
      interests: a.interests.length, avoidTopics: a.avoidTopics !== null},
    replaced: existing.exists,
  });
  await batch.commit();
  return {uid, researchId, recordedAt: iso, interests: a.interests,
    people: a.people.length};
}

module.exports = {
  intakeDocPath, AUDIT_COLLECTION, MAIN_GOALS, INTERESTS, INPUT_MODES,
  MAX_GOALS, MAX_PEOPLE, MAX_INTERESTS, intakeError, normaliseAnswers,
  uidForResearchId, recordIntake,
};
