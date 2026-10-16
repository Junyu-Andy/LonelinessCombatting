/**
 * T47 (revised 10/16) — the researcher records the intake for an elder
 * (dev-tasks-1015-intake §2.1, revision of 10/16: every field kept, no
 * selection caps; part A asked out loud by the researcher, part B —
 * 重要嘅人 / 想重新聯絡嘅人 — typed by the elder in the App).  Written by
 * the `unblinded` researcher through a callable:
 *
 *   users/{uid}/onboarding/intake   the IntakeResponse document (merge:
 *                                   the elder's part B and an older
 *                                   six-part answer set keep their fields)
 *   users/{uid}                     hasCompletedIntake, interests,
 *                                   avoidTopics, inputMode, preferredTimes,
 *                                   encouragementStyle
 *                                   (closeContacts: the elder's own part B
 *                                   — the researcher never writes it)
 *   intake_audit_log/{id}           who recorded what for whom (server
 *                                   only; no answer text)
 *
 * T48 + 10/16: for a Hybrid-arm account the whole merged intake document
 * (part A + part B) is turned into memory facts (`users/{uid}/mem_facts`,
 * one copy per companion that may know it, source "intake") so the server
 * memory block — the only memory path for Phase B Arm A — carries them.
 * Re-recording supersedes the previous intake facts.  Arm B never gets
 * facts (no LLM).
 *
 * Only the caller's role is checked (`unblinded`); the App-side switch
 * `app_config/feature_flags.researcherIntakeEnabled` decides what the
 * elder still sees, not whether the researcher may record.
 * Both arms identical; no LLM anywhere here.
 */

"use strict";

const intakeDocPath = (uid) => `users/${uid}/onboarding/intake`;
const AUDIT_COLLECTION = "intake_audit_log";
const UNBLINDED_ROLE = "unblinded";

// ---------------------------------------------------------------------------
// Option ids (lib/features/onboarding/data/intake_response.dart
// IntakeOptions, lib/features/onboarding/data/interest_labels.dart) and the
// Cantonese labels the memory lines use (the retired six-part page's
// wording, kept verbatim).
// ---------------------------------------------------------------------------

const GOAL_LABELS = {
  companionship: "想有人陪下傾偈",
  emotional_outlet: "想搵個地方抒發下心情",
  reconnect_others: "想同人重新連繫",
  learning: "想學下新嘢",
  share_memories: "想分享下人生回憶",
  curious: "對世界仲好有好奇心",
  other: "其他",
};
const TIMING_LABELS = {
  mornings: "早上", afternoons: "下晝", evenings: "夜晚", nights: "夜深",
  weekends: "週末", after_meals_alone: "自己食完飯之後", festivals: "節日",
  varies: "冇固定時間", other: "其他",
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
const TOPIC_LABELS = {
  hk_history: "香港舊時嘅嘢香港歷史", food: "飲食煮餸",
  family_stories: "屋企人嘅故事", nature: "種植動植物",
  music_film: "你嗰個年代嘅音樂戲曲電影", health: "健康養生",
  current_events: "時事新聞", religion: "宗教信仰人生價值", travel: "旅行",
  sports: "運動", other: "其他",
};
const CHAPTER_LABELS = {
  childhood: "細個嘅時候", school: "讀書嘅日子",
  first_job: "出嚟做嘢返工嘅日子", marriage: "拍拖結婚",
  raising_kids: "湊仔女嘅日子", moves: "搬屋移民搬區",
  hk_milestones: "香港大事", hobbies_developed: "呢啲年發展嘅興趣或者技能",
  travel: "旅行經驗", present_focus: "我寧願講返而家唔太想再諗以前",
};
const TIME_LABELS = {
  morning: "朝早", midday: "晏晝", afternoon: "下晝", evening: "夜晚",
  before_bed: "瞓覺之前", no_routine: "冇固定時間",
};
const ENCOURAGEMENT = {
  direct: "直接啲", gentle: "溫和啲", either: "冇所謂",
};
const INPUT_MODES = ["typing", "voice", "both", "unsure"];

const MAIN_GOALS = Object.keys(GOAL_LABELS);
const INTERESTS = Object.keys(INTEREST_LABELS);

// Technical ceilings only (10/16 Junyu: no selection caps).  Lists are
// capped at "every option"; free text at a sane length; people at 20.
const MAX_SHORT = 40; // mainGoalOther, interestsOther, topicsOther,
//                       formerOccupation, hometown, petName
const MAX_DAY = 120; // typicalMorning / Afternoon / Evening
const MAX_LONG = 300; // onMind
const MAX_AVOID = 200;
const MAX_NOTE = 200;
const MAX_NAME = 20;
const MAX_PEOPLE = 20;

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
 * A list of option ids: strings, trimmed, de-duplicated, each in `labels`.
 * @param {*} v
 * @param {object} labels
 * @param {string} badCode
 * @return {string[]}
 */
function idList(v, labels, badCode) {
  const out = [];
  for (const raw of (Array.isArray(v) ? v : [])) {
    const id = str(raw);
    if (!id) continue;
    if (!Object.prototype.hasOwnProperty.call(labels, id)) {
      throw intakeError(badCode);
    }
    if (out.indexOf(id) < 0) out.push(id);
  }
  return out;
}

/**
 * Free text, trimmed, "" → null, length-checked.
 * @param {*} v
 * @param {number} max
 * @param {string} longCode
 * @return {?string}
 */
function text(v, max, longCode) {
  const t = str(v);
  if (t.length > max) throw intakeError(longCode);
  return t || null;
}

/**
 * People rows (part B when the elder typed them; the researcher's form no
 * longer has them, but the shape is validated the same way).
 * @param {*} v
 * @return {Array<{name: string, relationship: string, extra: ?string,
 *     share: boolean}>}
 */
function peopleList(v) {
  const rows = Array.isArray(v) ? v : [];
  if (rows.length > MAX_PEOPLE) throw intakeError("too_many_people");
  const out = [];
  for (const p of rows) {
    const name = str(p && p.name);
    const rel = str(p && p.relationship);
    const extra = str(p && p.extra);
    if (!name) continue; // an empty row is simply skipped
    if (name.length > MAX_NAME || rel.length > MAX_NAME ||
        extra.length > MAX_SHORT) {
      throw intakeError("name_too_long");
    }
    out.push({name, relationship: rel, extra: extra || null,
      share: p.share === true});
  }
  return out;
}

/**
 * Validate and normalise the researcher's answers (part A + C; part B is
 * accepted too so an older client or a test may still send it).  Every
 * field optional.  Throws intakeError.
 * @param {object} raw request data
 * @return {object} normalised answers (see the keys below)
 */
function normaliseAnswers(raw) {
  const d = raw || {};
  const mode = str(d.inputMode) || "unsure";
  if (INPUT_MODES.indexOf(mode) < 0) throw intakeError("invalid_input_mode");
  const style = str(d.encouragementStyle) || null;
  if (style && !Object.prototype.hasOwnProperty.call(ENCOURAGEMENT, style)) {
    throw intakeError("invalid_encouragement_style");
  }
  return {
    // A
    mainGoals: idList(d.mainGoals, GOAL_LABELS, "invalid_goal"),
    mainGoalOther: text(d.mainGoalOther, MAX_SHORT, "other_too_long"),
    lonelinessTimings: idList(d.lonelinessTimings, TIMING_LABELS,
        "invalid_timing"),
    typicalMorning: text(d.typicalMorning, MAX_DAY, "day_too_long"),
    typicalAfternoon: text(d.typicalAfternoon, MAX_DAY, "day_too_long"),
    typicalEvening: text(d.typicalEvening, MAX_DAY, "day_too_long"),
    onMind: text(d.onMind, MAX_LONG, "on_mind_too_long"),
    interests: idList(d.interests, INTEREST_LABELS, "invalid_interest"),
    interestsOther: text(d.interestsOther, MAX_SHORT, "other_too_long"),
    topics: idList(d.topics, TOPIC_LABELS, "invalid_topic"),
    topicsOther: text(d.topicsOther, MAX_SHORT, "other_too_long"),
    lifeChapters: idList(d.lifeChapters, CHAPTER_LABELS, "invalid_chapter"),
    avoidTopics: text(d.avoidTopics, MAX_AVOID, "avoid_too_long"),
    inputMode: mode,
    preferredTimes: idList(d.preferredTimes, TIME_LABELS, "invalid_time"),
    // C
    formerOccupation: text(d.formerOccupation, MAX_SHORT, "other_too_long"),
    hometown: text(d.hometown, MAX_SHORT, "other_too_long"),
    petName: text(d.petName, MAX_SHORT, "other_too_long"),
    encouragementStyle: style,
    // researcher's own note (10/16)
    researcherNote: text(d.researcherNote, MAX_NOTE, "note_too_long"),
    // B (normally the elder's; accepted here for completeness)
    people: peopleList(d.importantPeople),
    reconnectPeople: peopleList(d.reconnectPeople),
  };
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
 *     interests: string[], people: number, memoryFacts: number}>}
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
  const userSnap = await userRef.get();
  if (!userSnap.exists) throw intakeError("account_not_found");
  const u = userSnap.data() || {};
  const map = await db.collection("research_id_map").doc(uid).get();
  if (u.isTester === true) throw intakeError("tester_account");
  const researchId = map.exists ? (map.get("researchId") || null) : null;
  if (!researchId) throw intakeError("not_enrolled");

  const iso = now.toISOString();
  const intake = {
    mainGoals: a.mainGoals,
    mainGoalOther: a.mainGoalOther,
    lonelinessTimings: a.lonelinessTimings,
    typicalMorning: a.typicalMorning,
    typicalAfternoon: a.typicalAfternoon,
    typicalEvening: a.typicalEvening,
    onMind: a.onMind,
    activities: a.interests,
    activitiesOther: a.interestsOther,
    topics: a.topics,
    topicsOther: a.topicsOther,
    lifeChapters: a.lifeChapters,
    avoidTopics: a.avoidTopics,
    inputMode: a.inputMode,
    preferredTimes: a.preferredTimes,
    formerOccupation: a.formerOccupation,
    hometown: a.hometown,
    petName: a.petName,
    encouragementStyle: a.encouragementStyle,
    researcherNote: a.researcherNote,
    updatedAt: iso,
    // Researcher parts done; the elder's part B (2) is marked by the App.
    completedParts: [1, 3, 4, 5, 6],
    // T47 provenance
    source: "researcher",
    recordedBy: caller.uid,
    recordedByEmail: caller.email || null,
    recordedAt: iso,
    schemaVersion: 3,
  };
  // Part B comes from the elder's App.  Only when the caller sends rows
  // (a test, or a client that still has them) do they replace the stored
  // ones — otherwise the elder's stay as they are.
  if (a.people.length) {
    intake.importantPeople = a.people;
  }
  if (a.reconnectPeople.length) {
    intake.reconnectPeople = a.reconnectPeople;
  }
  const existing = await intakeRef.get();
  if (!existing.exists) intake.createdAt = iso;

  const profile = {
    hasCompletedIntake: true,
    interests: a.interests,
    avoidTopics: a.avoidTopics,
    inputMode: a.inputMode,
    preferredTimes: a.preferredTimes,
    encouragementStyle: a.encouragementStyle,
    intakeRecordedAt: now,
  };
  if (a.people.length) {
    profile.closeContacts = a.people.map((p) =>
      ({name: p.name, relation: p.relationship || null, phone: null,
        share: p.share}));
  }
  const batch = db.batch();
  batch.set(intakeRef, intake, {merge: true});
  batch.set(userRef, profile, {merge: true});
  batch.create(db.collection(AUDIT_COLLECTION).doc(), {
    at: now, by: caller.uid, byEmail: caller.email || null,
    uid, researchId,
    fields: {
      goals: a.mainGoals.length, people: a.people.length,
      interests: a.interests.length, topics: a.topics.length,
      lifeChapters: a.lifeChapters.length,
      typicalDay: [a.typicalMorning, a.typicalAfternoon, a.typicalEvening]
          .filter(Boolean).length,
      onMind: a.onMind !== null, avoidTopics: a.avoidTopics !== null,
      researcherNote: a.researcherNote !== null,
      encouragementStyle: a.encouragementStyle,
    },
    replaced: existing.exists,
  });
  await batch.commit();
  // Facts come from the MERGED document: the elder's part B (people) and
  // the researcher's part A/C together, whichever came first.
  const merged = (await intakeRef.get()).data() || {};
  const facts = u.arm === "A" ?
    await seedMemoryFacts(db, uid, factsInputFromDoc(merged), now) : 0;
  const peopleCount = Array.isArray(merged.importantPeople) ?
    merged.importantPeople.filter((p) => p && str(p.name)).length : 0;
  return {uid, researchId, recordedAt: iso, interests: a.interests,
    people: peopleCount, memoryFacts: facts};
}

// ---------------------------------------------------------------------------
// T48 / 10/16 — intake → memory facts for the Hybrid arm
// ---------------------------------------------------------------------------

const INTAKE_SOURCE = "intake";
const AGENTS = ["siu_yan", "ah_jan_ah_bak", "tung_tung"];

/**
 * The stored intake document (any schema: the retired six-part page, the
 * five-question version, this one) → the shape intakeFactsFor() reads.
 * Lenient: unknown ids are kept as-is so an old answer still shows.
 * @param {object} doc
 * @return {object}
 */
function factsInputFromDoc(doc) {
  const d = doc || {};
  const list = (v) => (Array.isArray(v) ? v.map(str).filter(Boolean) : []);
  const people = (v) => (Array.isArray(v) ? v : []).map((p) => ({
    name: str(p && p.name), relationship: str(p && p.relationship),
    extra: str(p && p.extra) || null,
    share: p && p.share === true,
  })).filter((p) => p.name);
  return {
    mainGoals: list(d.mainGoals), mainGoalOther: str(d.mainGoalOther) || null,
    lonelinessTimings: list(d.lonelinessTimings),
    typicalMorning: str(d.typicalMorning) || null,
    typicalAfternoon: str(d.typicalAfternoon) || null,
    typicalEvening: str(d.typicalEvening) || null,
    onMind: str(d.onMind) || null,
    interests: list(d.activities), interestsOther: str(d.activitiesOther) ||
      null,
    topics: list(d.topics), topicsOther: str(d.topicsOther) || null,
    lifeChapters: list(d.lifeChapters),
    avoidTopics: str(d.avoidTopics) || null,
    inputMode: str(d.inputMode) || "unsure",
    preferredTimes: list(d.preferredTimes),
    formerOccupation: str(d.formerOccupation) || null,
    hometown: str(d.hometown) || null,
    petName: str(d.petName) || null,
    encouragementStyle: str(d.encouragementStyle) || null,
    researcherNote: str(d.researcherNote) || null,
    people: people(d.importantPeople),
    reconnectPeople: people(d.reconnectPeople),
  };
}

const label = (labels) => (id) => labels[id] || id;

/**
 * The facts each companion gets (routing per dev-tasks-1015-intake rev.
 * 10/16 §1; the retired App seeder's routing where it had one):
 *   goals / avoid / note / encouragement / occupation / hometown → all three
 *   loneliness timings, typical day, onMind (sensitive)        → 小欣
 *   interests, topics, pet                                      → 小欣, 通通
 *   people the elder shared                                     → 小欣
 *   life chapters                                               → 阿珍／阿伯
 *   inputMode, preferredTimes                                   → nobody
 * Pure; used by the tests.
 * @param {object} a normaliseAnswers() / factsInputFromDoc() result
 * @return {Array<{agent_id: string, category: string, key: string,
 *     value: string, sensitivity: string}>}
 */
function intakeFactsFor(a) {
  const out = [];
  const push = (agents, category, key, value, sensitivity) => {
    if (!value) return;
    for (const agent of agents) {
      out.push({agent_id: agent, category, key,
        value: value.slice(0, 200), sensitivity: sensitivity || "normal"});
    }
  };
  const join = (ids, labels, other) => {
    const xs = ids.map(label(labels)).filter((x) => x !== "其他");
    if (other) xs.push(other);
    return xs.join("、");
  };
  push(AGENTS, "preference", "嚟呢度主要想",
      join(a.mainGoals, GOAL_LABELS, a.mainGoalOther));
  push(["siu_yan"], "routine", "通常覺得孤單嘅時候",
      join(a.lonelinessTimings, TIMING_LABELS, null));
  const day = [
    a.typicalMorning ? `朝早${a.typicalMorning}` : null,
    a.typicalAfternoon ? `下晝${a.typicalAfternoon}` : null,
    a.typicalEvening ? `夜晚${a.typicalEvening}` : null,
  ].filter(Boolean).join("；");
  push(["siu_yan"], "routine", "平時作息", day);
  // 心事: private + sensitive — only usable when the elder raises it.
  push(["siu_yan"], "feeling", "入組時講過嘅心事", a.onMind, "sensitive");
  push(["siu_yan", "tung_tung"], "hobby", "平時鍾意",
      join(a.interests, INTEREST_LABELS, a.interestsOther));
  push(["siu_yan", "tung_tung"], "hobby", "鍾意傾嘅話題",
      join(a.topics, TOPIC_LABELS, a.topicsOther));
  const shared = a.people.filter((p) => p.share).map((p) =>
    p.relationship ? `${p.name}（${p.relationship}）` : p.name);
  push(["siu_yan"], "family", "重要嘅人", shared.join("、"));
  const reconnect = a.reconnectPeople.map((p) =>
    p.relationship ? `${p.name}（${p.relationship}）` : p.name);
  push(["siu_yan"], "family", "想重新聯絡嘅人", reconnect.join("、"));
  push(["ah_jan_ah_bak"], "preference", "想傾嘅人生階段",
      join(a.lifeChapters, CHAPTER_LABELS, null));
  push(AGENTS, "living", "以前做邊行", a.formerOccupation);
  push(AGENTS, "living", "喺邊度長大", a.hometown);
  push(["siu_yan", "tung_tung"], "family", "寵物", a.petName);
  if (a.encouragementStyle && a.encouragementStyle !== "either") {
    push(AGENTS, "preference", "鍾意人點樣講嘢",
        `${ENCOURAGEMENT[a.encouragementStyle]}（用戶入組時自己揀）`);
  }
  if (a.avoidTopics) {
    push(AGENTS, "preference", "唔想主動提起",
        `${a.avoidTopics}（用戶一開始就講明，唔好主動提）`);
  }
  // 10/16 — the researcher's own observation, verbatim, to all three.
  push(AGENTS, "preference", "研究員觀察", a.researcherNote);
  return out;
}

/**
 * Write the intake facts for a Hybrid-arm account, superseding the ones
 * from an earlier recording.  Never touches facts the companions
 * extracted from conversations (source_session_id ≠ "intake").
 * @param {object} db
 * @param {string} uid
 * @param {object} a normaliseAnswers() / factsInputFromDoc() result
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
      sensitivity: f.sensitivity,
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
  ENCOURAGEMENT, MAX_PEOPLE, intakeError, normaliseAnswers,
  uidForResearchId, recordIntake, intakeFactsFor, factsInputFromDoc,
  seedMemoryFacts, INTAKE_SOURCE,
};
