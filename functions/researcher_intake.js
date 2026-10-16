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
 * T48: each important person carries `share` (the elder agreed the
 * companions may know them).  For a Hybrid-arm account the five answers
 * are also written as memory facts (`users/{uid}/mem_facts`, one copy per
 * companion, source "intake") so the server memory block — the only
 * memory path for Phase B Arm A — carries them; the App's own intake
 * seeder only serves memory v0.  Re-recording supersedes the previous
 * intake facts.  Arm B never gets facts (no LLM).
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
/** 10/16 — 研究員備註: free text the elder never sees, handed to all three
 *  companions as one memory line (「研究員觀察：…」).  May be empty. */
const MAX_NOTE = 200;

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
 *     relationship: string, share: boolean}>, interests: string[],
 *     interestsOther: ?string,
 *     avoidTopics: ?string, inputMode: string, researcherNote: ?string}}
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
    people.push({name, relationship: rel, share: p.share === true});
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
  const note = str(d.researcherNote);
  if (note.length > MAX_NOTE) throw intakeError("note_too_long");
  return {mainGoals: goals, people, interests,
    interestsOther: other || null, avoidTopics: avoid || null,
    inputMode: mode, researcherNote: note || null};
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
      ({name: p.name, relationship: p.relationship, extra: null,
        share: p.share})),
    activities: a.interests,
    activitiesOther: a.interestsOther,
    avoidTopics: a.avoidTopics,
    inputMode: a.inputMode,
    researcherNote: a.researcherNote,
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
      ({name: p.name, relation: p.relationship || null, phone: null,
        share: p.share})),
    avoidTopics: a.avoidTopics,
    inputMode: a.inputMode,
    intakeRecordedAt: now,
  }, {merge: true});
  batch.create(db.collection(AUDIT_COLLECTION).doc(), {
    at: now, by: caller.uid, byEmail: caller.email || null,
    uid, researchId,
    fields: {goals: a.mainGoals.length, people: a.people.length,
      interests: a.interests.length, avoidTopics: a.avoidTopics !== null,
      researcherNote: a.researcherNote !== null},
    replaced: existing.exists,
  });
  await batch.commit();
  const facts = u.arm === "A" ? await seedMemoryFacts(db, uid, a, now) : 0;
  return {uid, researchId, recordedAt: iso, interests: a.interests,
    people: a.people.length, memoryFacts: facts};
}

// ---------------------------------------------------------------------------
// T48 — intake → memory facts for the Hybrid arm
// ---------------------------------------------------------------------------

const INTAKE_SOURCE = "intake";
const AGENTS = ["siu_yan", "ah_jan_ah_bak", "tung_tung"];
const GOAL_LABELS = {
  companionship: "想有人陪下傾偈",
  emotional_outlet: "想搵個地方抒發下心情",
  reconnect_others: "想同人重新連繫",
  learning: "想學下新嘢",
  share_memories: "想分享下人生回憶",
  curious: "對世界仲好有好奇心",
};
const INTEREST_LABELS = {
  yum_cha: "飲茶／一盅兩件", cooking: "煮食", wet_market: "逛街市",
  buffet: "食自助餐", tv_drama: "睇電視劇", radio: "聽收音機",
  reading: "看書／睇雜誌", mahjong: "打牌／打麻雀", gardening: "種花種菜",
  chatting: "跟人傾偈", hiking: "行山", park_walk: "公園散步",
  tai_chi: "太極拳", swimming: "游水", cantonese_opera: "粵劇／戲曲",
  museums: "睇展覽／博物館", elderly_centre: "老人中心活動",
  religious: "去教會／廟宇", visit_friends: "探望朋友",
  volunteering: "義工服務", meditation: "靜坐／冥想", prayer: "祈禱／膜拜",
  news: "新聞時事",
};

/**
 * The facts each companion gets from the five answers (same routing as
 * the App's memory-v0 seeder): goals → all three; interests → 小欣, 通通;
 * people the elder agreed to share → 小欣; "don't raise" → all three.
 * Pure; used by the tests.
 * @param {object} a normaliseAnswers() result
 * @return {Array<{agent_id: string, category: string, key: string,
 *     value: string}>}
 */
function intakeFactsFor(a) {
  const out = [];
  const push = (agents, category, key, value) => {
    if (!value) return;
    for (const agent of agents) {
      out.push({agent_id: agent, category, key, value: value.slice(0, 200)});
    }
  };
  const goals = a.mainGoals.map((g) => GOAL_LABELS[g]).filter(Boolean);
  if (goals.length) {
    push(AGENTS, "preference", "嚟呢度主要想", goals.join("、"));
  }
  const interests = a.interests.map((i) => INTEREST_LABELS[i] || i);
  if (a.interestsOther) interests.push(a.interestsOther);
  if (interests.length) {
    push(["siu_yan", "tung_tung"], "hobby", "平時鍾意", interests.join("、"));
  }
  const shared = a.people.filter((p) => p.share).map((p) =>
    p.relationship ? `${p.name}（${p.relationship}）` : p.name);
  if (shared.length) {
    push(["siu_yan"], "family", "重要嘅人", shared.join("、"));
  }
  if (a.avoidTopics) {
    push(AGENTS, "preference", "唔想主動提起",
        `${a.avoidTopics}（用戶一開始就講明，唔好主動提）`);
  }
  // 10/16 — the researcher's own observation, verbatim, to all three.
  if (a.researcherNote) {
    push(AGENTS, "preference", "研究員觀察", a.researcherNote);
  }
  return out;
}

/**
 * Write the intake facts for a Hybrid-arm account, superseding the ones
 * from an earlier recording.  Never touches facts the companions
 * extracted from conversations (source_session_id ≠ "intake").
 * @param {object} db
 * @param {string} uid
 * @param {object} a normaliseAnswers() result
 * @param {Date} now
 * @return {Promise<number>} facts written
 */
async function seedMemoryFacts(db, uid, a, now) {
  const col = db.collection("users").doc(uid).collection("mem_facts");
  const old = await col.where("source_session_id", "==", INTAKE_SOURCE)
      .where("status", "==", "active").get();
  const facts = intakeFactsFor(a);
  const batch = db.batch();
  for (const d of old.docs) {
    batch.update(d.ref, {status: "superseded", updated_at: now});
  }
  for (const f of facts) {
    batch.set(col.doc(), {
      agent_id: f.agent_id,
      category: f.category,
      key: f.key,
      value: f.value,
      quote: "",
      visibility: "agent",
      sensitivity: "normal",
      status: "active",
      user_corrected: false,
      revision_count: 0,
      needs_review: false,
      confidence: null,
      replaces: null,
      source_session_id: INTAKE_SOURCE,
      created_at: now,
      updated_at: now,
      layer: "private",
      sourceAgent: f.agent_id,
    });
  }
  await batch.commit();
  return facts.length;
}

module.exports = {
  intakeDocPath, AUDIT_COLLECTION, MAIN_GOALS, INTERESTS, INPUT_MODES,
  MAX_GOALS, MAX_PEOPLE, MAX_INTERESTS, intakeError, normaliseAnswers,
  uidForResearchId, recordIntake, intakeFactsFor, seedMemoryFacts,
  INTAKE_SOURCE,
};
