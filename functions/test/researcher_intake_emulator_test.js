/**
 * T47 (rev. 10/16, T49a 10/18) — researcher-recorded intake
 * (functions/researcher_intake.js).  Run from functions/:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "node test/researcher_intake_emulator_test.js"
 */
"use strict";

const assert = require("assert");
const admin = require("firebase-admin");
const ri = require("../researcher_intake");
const memory = require("../memory");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const NOW = new Date("2026-10-15T06:00:00Z");
const K1 = {uid: "keran", email: "k1@example.org", role: "unblinded"};
const BLINDED = {uid: "ass1", email: "a@example.org", role: "blinded"};
const ELDER = {uid: "u1", email: "e@example.org", role: null};

/** Part A + C as the researcher's form sends them (no people: part B). */
const ANSWERS = {
  mainGoals: ["companionship", "share_memories", "learning"],
  mainGoalOther: "想有人提我食藥",
  lonelinessTimings: ["evenings", "festivals"],
  typicalMorning: "飲茶",
  typicalAfternoon: "",
  typicalEvening: "睇電視",
  onMind: "個仔好耐冇打嚟",
  interests: ["yum_cha", "mahjong", "hiking", "news"],
  interestsOther: "聽粵曲",
  topics: ["food", "hk_history"],
  topicsOther: "馬經",
  lifeChapters: ["childhood", "first_job"],
  avoidTopics: "唔好提我先生",
  inputMode: "voice",
  preferredTimes: ["morning", "before_bed"],
  formerOccupation: "車衣",
  hometown: "潮州",
  petName: "",
  encouragementStyle: "gentle",
  researcherNote: "老人家健談，咩都想講",
};

/** The elder's own part B, as the App writes it. */
const PART_B = {
  importantPeople: [{name: "阿女", relationship: "女", extra: null,
    share: true}, {name: "黃太", relationship: "鄰居", extra: null,
    share: true}],
  reconnectPeople: [{name: "舊同事阿強", relationship: "舊同事", extra: null,
    share: true}, {name: "陳生", relationship: "舊街坊", extra: null,
    share: false}],
  completedParts: [2],
  peopleSource: "elder",
};

/**
 * @param {string} uid
 * @param {object=} extra
 */
async function enrolled(uid, extra) {
  await db.doc(`users/${uid}`).set(Object.assign({displayName: "陳太",
    cohort: "pilot", arm: "B", interests: ["news"],
    hasCompletedIntake: false}, extra || {}));
  await db.doc(`research_id_map/${uid}`).set({researchId: "PILOT-01"});
  await db.doc("research_ids/PILOT-01").set({uid});
}

/**
 * @param {Promise} p
 * @return {Promise<string>}
 */
const code = async (p) => {
  try {
    await p;
  } catch (e) {
    return e.intakeCode || e.message;
  }
  return "no error";
};

/** Reset the emulator collections this test touches. */
async function reset() {
  for (const c of ["users", "research_id_map", "research_ids",
    ri.AUDIT_COLLECTION]) {
    await db.recursiveDelete(db.collection(c));
  }
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("normaliseAnswers: every field, no selection caps, ids checked, " +
    "technical ceilings only", () => {
  const a = ri.normaliseAnswers(ANSWERS);
  assert.deepStrictEqual(a.mainGoals, ["companionship", "share_memories",
    "learning"]);
  assert.strictEqual(a.mainGoalOther, "想有人提我食藥");
  assert.deepStrictEqual(a.lonelinessTimings, ["evenings", "festivals"]);
  assert.strictEqual(a.typicalMorning, "飲茶");
  assert.strictEqual(a.typicalAfternoon, null); // "" → null
  assert.strictEqual(a.onMind, "個仔好耐冇打嚟");
  assert.deepStrictEqual(a.interests, ["yum_cha", "mahjong", "hiking",
    "news"]);
  assert.deepStrictEqual(a.topics, ["food", "hk_history"]);
  assert.deepStrictEqual(a.lifeChapters, ["childhood", "first_job"]);
  assert.deepStrictEqual(a.preferredTimes, ["morning", "before_bed"]);
  assert.strictEqual(a.formerOccupation, "車衣");
  assert.strictEqual(a.petName, null);
  assert.strictEqual(a.encouragementStyle, "gentle");
  assert.strictEqual(a.researcherNote, "老人家健談，咩都想講");
  assert.deepStrictEqual(a.people, []);
  assert.deepStrictEqual(a.reconnectPeople, []);
  const empty = ri.normaliseAnswers({});
  assert.deepStrictEqual(empty.mainGoals, []);
  assert.strictEqual(empty.inputMode, "unsure");
  assert.strictEqual(empty.encouragementStyle, null);
  assert.deepStrictEqual(ri.intakeFactsFor(empty), []);
  const bad = (x) => {
    try {
      ri.normaliseAnswers(x);
    } catch (e) {
      return e.intakeCode;
    }
    return "no error";
  };
  // No caps: every option at once is fine; duplicates collapse.
  assert.strictEqual(bad({mainGoals: ri.MAIN_GOALS}), "no error");
  assert.deepStrictEqual(ri.normaliseAnswers({interests: ["news", "news"]})
      .interests, ["news"]);
  assert.strictEqual(bad({interests: ri.INTERESTS}), "no error");
  assert.strictEqual(bad({mainGoals: ["winning"]}), "invalid_goal");
  assert.strictEqual(bad({lonelinessTimings: ["x"]}), "invalid_timing");
  assert.strictEqual(bad({interests: ["yum_cha", "x"]}), "invalid_interest");
  assert.strictEqual(bad({topics: ["x"]}), "invalid_topic");
  assert.strictEqual(bad({lifeChapters: ["x"]}), "invalid_chapter");
  assert.strictEqual(bad({preferredTimes: ["x"]}), "invalid_time");
  assert.strictEqual(bad({inputMode: "x"}), "invalid_input_mode");
  assert.strictEqual(bad({encouragementStyle: "loud"}),
      "invalid_encouragement_style");
  // T49a (§A2): 10 people per list, the 11th refused.
  assert.strictEqual(ri.MAX_PEOPLE, 10);
  assert.strictEqual(bad({importantPeople: new Array(10).fill({name: "a"})}),
      "no error");
  assert.strictEqual(bad({importantPeople: new Array(11).fill({name: "a"})}),
      "too_many_people");
  assert.strictEqual(bad({reconnectPeople: new Array(11).fill({name: "a"})}),
      "too_many_people");
  assert.strictEqual(bad({importantPeople: [{name: "x".repeat(21)}]}),
      "name_too_long");
  assert.strictEqual(bad({typicalMorning: "x".repeat(121)}), "day_too_long");
  assert.strictEqual(bad({onMind: "x".repeat(301)}), "on_mind_too_long");
  assert.strictEqual(bad({avoidTopics: "x".repeat(201)}), "avoid_too_long");
  assert.strictEqual(bad({researcherNote: "x".repeat(201)}), "note_too_long");
  assert.strictEqual(bad({hometown: "x".repeat(41)}), "other_too_long");
});

test("recordIntake: writes the intake doc (merge over the elder's part B " +
    "and old fields), the profile fields and an audit row", async () => {
  await reset();
  await enrolled("u1", {closeContacts: [{name: "阿女", relation: "女",
    phone: null, share: true}]});
  // The elder typed part B first; an even older six-part field is there.
  await db.doc(ri.intakeDocPath("u1")).set(Object.assign({
    createdAt: "2026-10-01T00:00:00Z", someOldField: "keep"}, PART_B));
  const r = await ri.recordIntake(db, K1, {uid: "u1", answers: ANSWERS},
      {now: NOW});
  assert.strictEqual(r.researchId, "PILOT-01");
  assert.strictEqual(r.people, 2); // the elder's, counted from the merge
  const d = (await db.doc(ri.intakeDocPath("u1")).get()).data();
  assert.deepStrictEqual(d.mainGoals, ["companionship", "share_memories",
    "learning"]);
  assert.strictEqual(d.someOldField, "keep"); // untouched
  assert.strictEqual(d.createdAt, "2026-10-01T00:00:00Z");
  assert.deepStrictEqual(d.importantPeople, PART_B.importantPeople); // B kept
  assert.deepStrictEqual(d.reconnectPeople, PART_B.reconnectPeople);
  assert.strictEqual(d.peopleSource, "elder");
  // T49a: added to the elder's 2, not replacing it.
  assert.deepStrictEqual(d.completedParts, [2, 1, 3, 4, 5, 6]);
  assert.strictEqual(d.source, "researcher");
  assert.strictEqual(d.recordedBy, "keran");
  assert.deepStrictEqual(d.activities, ["yum_cha", "mahjong", "hiking",
    "news"]);
  assert.strictEqual(d.activitiesOther, "聽粵曲");
  assert.deepStrictEqual(d.topics, ["food", "hk_history"]);
  assert.strictEqual(d.onMind, "個仔好耐冇打嚟");
  assert.strictEqual(d.encouragementStyle, "gentle");
  assert.strictEqual(d.researcherNote, "老人家健談，咩都想講");
  assert.strictEqual(d.schemaVersion, 3);
  const u = (await db.doc("users/u1").get()).data();
  assert.strictEqual(u.hasCompletedIntake, true);
  assert.deepStrictEqual(u.interests, ["yum_cha", "mahjong", "hiking",
    "news"]);
  // closeContacts are the elder's: not touched by the researcher.
  assert.deepStrictEqual(u.closeContacts, [{name: "阿女", relation: "女",
    phone: null, share: true}]);
  assert.strictEqual(u.avoidTopics, "唔好提我先生");
  assert.strictEqual(u.inputMode, "voice");
  assert.deepStrictEqual(u.preferredTimes, ["morning", "before_bed"]);
  assert.strictEqual(u.encouragementStyle, "gentle");
  assert.strictEqual(u.researcherNote, undefined); // intake doc only
  assert.strictEqual(u.onMind, undefined); // never on the profile
  assert.strictEqual(u.arm, "B"); // untouched
  const audit = await db.collection(ri.AUDIT_COLLECTION).get();
  assert.strictEqual(audit.size, 1);
  const row = audit.docs[0].data();
  assert.strictEqual(row.uid, "u1");
  assert.strictEqual(row.researchId, "PILOT-01");
  assert.strictEqual(row.by, "keran");
  assert.strictEqual(row.replaced, true);
  assert.deepStrictEqual(row.fields, {goals: 3, people: 0, interests: 4,
    topics: 2, lifeChapters: 2, typicalDay: 2, onMind: true,
    avoidTopics: true, researcherNote: true, encouragementStyle: "gentle"});
  const rowText = JSON.stringify(row);
  for (const t of ["阿女", "個仔", "車衣", "健談"]) {
    assert.strictEqual(rowText.indexOf(t), -1, "no answer text in audit");
  }
  // Second recording: a fresh audit row, researcher fields replaced, the
  // elder's part B still there.
  await ri.recordIntake(db, K1, {uid: "u1",
    answers: {mainGoals: ["curious"], interests: ["news"]}}, {now: NOW});
  const u2 = (await db.doc("users/u1").get()).data();
  assert.deepStrictEqual(u2.interests, ["news"]);
  assert.strictEqual(u2.avoidTopics, null);
  assert.strictEqual(u2.encouragementStyle, null);
  const d2 = (await db.doc(ri.intakeDocPath("u1")).get()).data();
  assert.deepStrictEqual(d2.importantPeople, PART_B.importantPeople);
  assert.strictEqual((await db.collection(ri.AUDIT_COLLECTION).get()).size, 2);
});

test("recordIntake: refused for blinded / participant callers, unknown, " +
    "unenrolled, tester and own accounts", async () => {
  await reset();
  await enrolled("u1");
  await db.doc("users/u2").set({displayName: "x"}); // not enrolled
  await db.doc("users/ut").set({displayName: "t", isTester: true});
  await db.doc("research_id_map/ut").set({researchId: "PILOT-09"});
  await db.doc("users/keran").set({displayName: "k"});
  await db.doc("research_id_map/keran").set({researchId: "PILOT-08"});
  const call = (caller, uid) =>
    ri.recordIntake(db, caller, {uid, answers: ANSWERS}, {now: NOW});
  assert.strictEqual(await code(call(BLINDED, "u1")),
      "not_unblinded_researcher");
  assert.strictEqual(await code(call(ELDER, "u1")),
      "not_unblinded_researcher");
  assert.strictEqual(await code(call(null, "u1")), "not_unblinded_researcher");
  assert.strictEqual(await code(call(K1, "ghost")), "account_not_found");
  assert.strictEqual(await code(call(K1, "u2")), "not_enrolled");
  assert.strictEqual(await code(call(K1, "ut")), "tester_account");
  assert.strictEqual(await code(call(K1, "keran")), "own_account");
  assert.strictEqual((await db.collection(ri.AUDIT_COLLECTION).get()).size, 0);
  assert.strictEqual((await db.doc("users/u1").get()).get("hasCompletedIntake"),
      false);
});

test("intakeFactsFor: routing per companion (§A3, 10/18), only shared " +
    "people, 心事 sensitive, no 唔想提起 / 鼓勵方式, nothing for empty " +
    "answers", () => {
  const a = ri.factsInputFromDoc(Object.assign({
    activities: ANSWERS.interests, activitiesOther: ANSWERS.interestsOther,
  }, ANSWERS, PART_B, {importantPeople: [
    {name: "阿女", relationship: "女", share: true},
    {name: "黃太", relationship: "鄰居", share: false}]}));
  const facts = ri.intakeFactsFor(a);
  const by = (agent) => facts.filter((f) => f.agent_id === agent)
      .map((f) => f.key);
  assert.deepStrictEqual(by("siu_yan"), ["嚟呢度主要想", "通常覺得孤單嘅時候",
    "平時作息", "入組時講過嘅心事", "平時鍾意", "鍾意傾嘅話題", "重要嘅人",
    "想重新聯絡嘅人", "以前做邊行", "喺邊度長大", "研究員觀察"]);
  assert.deepStrictEqual(by("tung_tung"), ["嚟呢度主要想", "平時鍾意",
    "鍾意傾嘅話題", "以前做邊行", "喺邊度長大", "研究員觀察"]);
  assert.deepStrictEqual(by("ah_jan_ah_bak"), ["嚟呢度主要想",
    "想傾嘅人生階段", "以前做邊行", "喺邊度長大", "研究員觀察"]);
  // §A3: avoidTopics is the prompts' ⛔ line, encouragementStyle the tone
  // slot — neither is a fact, under any key.
  for (const f of facts) {
    assert.ok(["唔想主動提起", "鍾意人點樣講嘢"].indexOf(f.key) < 0, f.key);
    assert.strictEqual(f.value.indexOf("唔好提我先生"), -1, f.key);
    assert.strictEqual(f.value.indexOf("溫和"), -1, f.key);
  }
  // §A3 categories (→ layer via memory.layerFor).
  const cat = {};
  for (const f of facts) cat[f.key] = f.category;
  assert.deepStrictEqual(cat, {
    "嚟呢度主要想": "preference", "通常覺得孤單嘅時候": "feeling",
    "平時作息": "routine", "入組時講過嘅心事": "feeling",
    "平時鍾意": "hobby", "鍾意傾嘅話題": "hobby", "重要嘅人": "family",
    "想重新聯絡嘅人": "family", "想傾嘅人生階段": "story",
    "以前做邊行": "living", "喺邊度長大": "living",
    "研究員觀察": "preference",
  });
  const v = (key) => facts.find((f) => f.key === key);
  assert.strictEqual(v("嚟呢度主要想").value,
      "想有人陪下傾偈、想分享下人生回憶、想學下新嘢、想有人提我食藥");
  assert.strictEqual(v("通常覺得孤單嘅時候").value, "夜晚、節日");
  assert.strictEqual(v("平時作息").value, "朝早飲茶；夜晚睇電視");
  assert.strictEqual(v("入組時講過嘅心事").sensitivity, "sensitive");
  assert.strictEqual(v("入組時講過嘅心事").category, "feeling");
  assert.strictEqual(v("平時鍾意").value,
      "飲茶／一盅兩件、打牌／打麻雀、行山、新聞時事、聽粵曲");
  assert.strictEqual(v("鍾意傾嘅話題").value, "飲食煮餸、香港舊時嘅嘢香港歷史、馬經");
  assert.strictEqual(v("重要嘅人").value, "阿女（女）"); // 黃太 not shared
  // 1020e 二.13: 陳生 not shared → left out.
  assert.strictEqual(v("想重新聯絡嘅人").value, "舊同事阿強（舊同事）");
  assert.strictEqual(v("想傾嘅人生階段").value, "細個嘅時候、出嚟做嘢返工嘅日子");
  assert.strictEqual(v("研究員觀察").value, "老人家健談，咩都想講");
  assert.strictEqual(v("平時作息").sensitivity, "normal");
  // No tone fact for any style; pet (family) to 小欣 and 通通 when named.
  for (const style of ["direct", "gentle", "either"]) {
    const b = ri.intakeFactsFor(ri.normaliseAnswers({
      encouragementStyle: style, petName: "波波", avoidTopics: "唔好提錢"}));
    assert.deepStrictEqual(b.map((f) => `${f.agent_id}:${f.key}:${f.category}`),
        ["siu_yan:寵物:family", "tung_tung:寵物:family"]);
  }
  assert.deepStrictEqual(ri.intakeFactsFor(ri.normaliseAnswers({})), []);
});

test("recordIntake: Hybrid arm gets the facts from the MERGED document " +
    "(elder's people + researcher's answers), superseded on re-record, " +
    "conversation facts untouched; rule arm gets none", async () => {
  await reset();
  await enrolled("u1", {arm: "A"});
  await db.doc(ri.intakeDocPath("u1")).set(PART_B);
  const col = db.collection("users/u1/mem_facts");
  await col.add({agent_id: "siu_yan", category: "name", key: "稱呼",
    value: "陳太", status: "active", source_session_id: "sess-1"});
  const r = await ri.recordIntake(db, K1, {uid: "u1", answers: ANSWERS},
      {now: NOW});
  // 11 (小欣) + 6 (通通) + 5 (阿珍／阿伯) — see the routing test.
  assert.strictEqual(r.memoryFacts, 22);
  const active = (await col.where("status", "==", "active").get()).docs
      .map((d) => d.data());
  assert.strictEqual(active.length, 23); // 22 intake + the conversation one
  const intake = active.filter((f) => f.source_session_id === "intake");
  assert.strictEqual(intake.length, 22);
  // T49a: layer / visibility as for conversation facts (memory.layerFor /
  // visibilityFor): family / living / routine / hobby / preference shared,
  // feeling / story private; sensitive always private.
  const SHARED = ["family", "living", "routine", "hobby", "preference"];
  const PRIVATE = ["feeling", "story", "health"];
  for (const c of PRIVATE) {
    assert.strictEqual(memory.layerFor(c, "normal"), "private", c);
  }
  for (const f of intake) {
    assert.strictEqual(f.sourceAgent, f.agent_id);
    assert.strictEqual(f.layer, memory.layerFor(f.category, f.sensitivity));
    assert.strictEqual(f.visibility,
        memory.visibilityFor(f.category, f.sensitivity));
    if (f.sensitivity !== "normal" || PRIVATE.indexOf(f.category) >= 0) {
      assert.strictEqual(f.layer, "private", f.key);
    } else {
      assert.ok(SHARED.indexOf(f.category) >= 0, f.key);
      assert.strictEqual(f.layer, "shared", f.key);
    }
  }
  const layerOf = (key) => intake.find((f) => f.key === key).layer;
  assert.strictEqual(layerOf("通常覺得孤單嘅時候"), "private");
  assert.strictEqual(layerOf("想傾嘅人生階段"), "private");
  assert.strictEqual(layerOf("入組時講過嘅心事"), "private");
  assert.strictEqual(layerOf("平時作息"), "shared");
  assert.strictEqual(layerOf("重要嘅人"), "shared");
  assert.strictEqual(layerOf("以前做邊行"), "shared");
  assert.strictEqual(intake.find((f) => f.key === "以前做邊行").visibility,
      "shared");
  assert.strictEqual(intake.find((f) => f.key === "平時鍾意").visibility,
      "agent");
  const people = intake.find((f) => f.key === "重要嘅人");
  assert.strictEqual(people.value, "阿女（女）、黃太（鄰居）"); // the elder's
  assert.strictEqual(intake.find((f) => f.key === "入組時講過嘅心事")
      .sensitivity, "sensitive");
  // Re-record with fewer answers: old intake facts superseded; the people
  // (still on the merged document) stay.
  const r2 = await ri.recordIntake(db, K1, {uid: "u1",
    answers: {mainGoals: ["curious"]}}, {now: NOW});
  assert.strictEqual(r2.memoryFacts, 5); // 3 goals + 重要嘅人 + 想重新聯絡嘅人
  const after = (await col.get()).docs.map((d) => d.data());
  assert.strictEqual(after.filter((f) => f.status === "active").length, 6);
  assert.strictEqual(after.filter((f) => f.status === "superseded").length,
      22);
  assert.strictEqual(after.find((f) => f.source_session_id === "sess-1")
      .status, "active");
  // Rule arm (§A5): recorded the same, but no memory facts at all.
  await enrolled("u9", {arm: "B"});
  await db.doc("research_id_map/u9").set({researchId: "PILOT-02"});
  const rb = await ri.recordIntake(db, K1, {uid: "u9", answers: ANSWERS},
      {now: NOW});
  assert.strictEqual(rb.memoryFacts, 0);
  assert.strictEqual((await db.collection("users/u9/mem_facts").get()).size,
      0);
  assert.strictEqual((await db.doc(ri.intakeDocPath("u9")).get())
      .get("source"), "researcher");
});

test("§A6 old data: a PILOT-style six-part intake re-recorded by the " +
    "researcher reads without error, new fields empty, old people kept",
async () => {
  await reset();
  // The retired six-part page's document: no schemaVersion, no source, old
  // people rows (extra = how often / what stops them, no `share`),
  // completedParts 1–6, item timestamps.
  const OLD = {
    mainGoals: ["companionship"], mainGoalOther: null,
    lonelinessTimings: ["evenings"],
    importantPeople: [
      {name: "阿女", relationship: "女兒", extra: "每星期"},
      {name: "", relationship: "", extra: null},
    ],
    reconnectPeople: [{name: "舊鄰居", relationship: "朋友",
      extra: "冇電話"}],
    typicalMorning: "飲茶", typicalAfternoon: null, typicalEvening: "睇電視",
    onMind: "膝頭痛", activities: ["yum_cha"], activitiesOther: null,
    topics: ["food"], topicsOther: null,
    lifeChapters: ["childhood", "raising_kids"],
    avoidTopics: null, inputMode: "typing", preferredTimes: ["morning"],
    createdAt: "2026-09-20T02:00:00Z", updatedAt: "2026-09-20T02:20:00Z",
    completedParts: [1, 2, 3, 4, 5, 6], allCompleted: true,
    itemTimestamps: {"1.1": {renderedAt: "2026-09-20T02:00:00Z",
      submittedAt: "2026-09-20T02:01:00Z", skipped: false,
      timeOnItemMs: 60000}},
  };
  for (const [uid, rid] of [["p1", "PILOT-01"], ["p2", "PILOT-02"],
    ["p3", "PILOT-03"]]) {
    await enrolled(uid, {arm: "A"});
    await db.doc(`research_id_map/${uid}`).set({researchId: rid});
    await db.doc(ri.intakeDocPath(uid)).set(OLD);
    // factsInputFromDoc takes the old document as it is.
    const before = ri.factsInputFromDoc(OLD);
    assert.deepStrictEqual(before.people.map((p) => p.name), ["阿女"]);
    assert.strictEqual(before.people[0].share, false); // old rows: no share
    assert.strictEqual(before.formerOccupation, null);
    assert.strictEqual(before.encouragementStyle, null);
    assert.strictEqual(before.researcherNote, null);
    // Re-recorded with only part of the new fields.
    const r = await ri.recordIntake(db, K1, {uid, answers: {
      mainGoals: ["companionship"], hometown: "順德"}}, {now: NOW});
    const d = (await db.doc(ri.intakeDocPath(uid)).get()).data();
    const a = ri.factsInputFromDoc(d);
    // New fields: empty / null, not missing errors.
    assert.strictEqual(a.formerOccupation, null);
    assert.strictEqual(a.petName, null);
    assert.strictEqual(a.encouragementStyle, null);
    assert.strictEqual(a.researcherNote, null);
    assert.strictEqual(a.hometown, "順德");
    // Researcher fields replaced (merge writes every part-A key); the old
    // people and the old bookkeeping stay.
    assert.strictEqual(d.typicalMorning, null);
    assert.deepStrictEqual(d.importantPeople, OLD.importantPeople);
    assert.deepStrictEqual(d.reconnectPeople, OLD.reconnectPeople);
    assert.deepStrictEqual(d.completedParts, [1, 2, 3, 4, 5, 6]);
    assert.strictEqual(d.allCompleted, true);
    assert.deepStrictEqual(d.itemTimestamps, OLD.itemTimestamps);
    assert.strictEqual(d.createdAt, OLD.createdAt);
    assert.strictEqual(d.schemaVersion, 3);
    // Facts: old people rows have no `share` → no 重要嘅人, and (1020e
    // 二.13) no 想重新聯絡嘅人 either.
    const facts = (await db.collection(`users/${uid}/mem_facts`)
        .where("status", "==", "active").get()).docs.map((x) => x.data());
    assert.strictEqual(r.memoryFacts, facts.length);
    const keys = facts.map((f) => `${f.agent_id}:${f.key}`).sort();
    assert.deepStrictEqual(keys, [
      "ah_jan_ah_bak:喺邊度長大", "ah_jan_ah_bak:嚟呢度主要想",
      "siu_yan:喺邊度長大", "siu_yan:嚟呢度主要想",
      "tung_tung:喺邊度長大", "tung_tung:嚟呢度主要想",
    ].sort());
    assert.strictEqual(r.people, 1); // the empty old row is not counted
  }
});

test("uidForResearchId: case-insensitive, unknown → empty", async () => {
  await reset();
  await enrolled("u1");
  assert.strictEqual(await ri.uidForResearchId(db, "pilot-01"), "u1");
  assert.strictEqual(await ri.uidForResearchId(db, "PILOT-99"), "");
  assert.strictEqual(await ri.uidForResearchId(db, ""), "");
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`ok - ${t.name}`);
    } catch (err) {
      failed++;
      console.log(`not ok - ${t.name}\n${err.stack}`);
    }
  }
  if (failed) {
    console.log(`${failed} researcher_intake test(s) failed`);
    process.exit(1);
  }
  process.exit(0);
})();
