/**
 * T47 — researcher-recorded intake (functions/researcher_intake.js).
 * Run from functions/:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "node test/researcher_intake_emulator_test.js"
 */
"use strict";

const assert = require("assert");
const admin = require("firebase-admin");
const ri = require("../researcher_intake");

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

const ANSWERS = {
  mainGoals: ["companionship", "share_memories"],
  importantPeople: [{name: "阿女", relationship: "女", share: true},
    {name: "", relationship: "x"}, {name: "黃太", relationship: "鄰居"}],
  interests: ["yum_cha", "mahjong"],
  interestsOther: "聽粵曲",
  avoidTopics: "唔好提我先生",
  inputMode: "voice",
  researcherNote: "老人家健談，咩都想講", // 10/16 研究員備註
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

test("normaliseAnswers: caps, ids, empty rows", () => {
  const a = ri.normaliseAnswers(ANSWERS);
  assert.deepStrictEqual(a.mainGoals, ["companionship", "share_memories"]);
  assert.deepStrictEqual(a.people, [
    {name: "阿女", relationship: "女", share: true},
    {name: "黃太", relationship: "鄰居", share: false}]);
  assert.deepStrictEqual(a.interests, ["yum_cha", "mahjong"]);
  assert.strictEqual(a.interestsOther, "聽粵曲");
  assert.strictEqual(a.avoidTopics, "唔好提我先生");
  assert.strictEqual(a.inputMode, "voice");
  const empty = ri.normaliseAnswers({});
  assert.deepStrictEqual(empty, {mainGoals: [], people: [], interests: [],
    interestsOther: null, avoidTopics: null, inputMode: "unsure",
    researcherNote: null});
  const bad = (x) => {
    try {
      ri.normaliseAnswers(x);
    } catch (e) {
      return e.intakeCode;
    }
    return "no error";
  };
  // 10/16: no selection caps; only technical ceilings remain.
  assert.strictEqual(bad({mainGoals: ["companionship", "learning",
    "curious"]}), "no error");
  assert.strictEqual(bad({mainGoals: ["companionship", "learning", "curious",
    "share_memories", "reconnect_others", "emotional_outlet",
    "companionship"]}), "too_many_goals");
  assert.strictEqual(bad({mainGoals: ["winning"]}), "invalid_goal");
  assert.strictEqual(bad({importantPeople: [{}, {}, {}, {}]}), "no error");
  assert.strictEqual(bad({importantPeople: new Array(21).fill({})}),
      "too_many_people");
  assert.strictEqual(bad({interests: ["yum_cha", "x"]}), "invalid_interest");
  assert.strictEqual(bad({interests: ["yum_cha", "radio", "news", "tv_drama"]}),
      "no error");
  assert.strictEqual(bad({avoidTopics: "x".repeat(201)}), "avoid_too_long");
  assert.strictEqual(bad({researcherNote: "x".repeat(201)}), "note_too_long");
  assert.strictEqual(bad({inputMode: "shout"}), "invalid_input_mode");
});

test("recordIntake: writes the intake doc, the profile fields and an audit " +
    "row; old six-part answers keep their extra fields", async () => {
  await reset();
  await enrolled("u1");
  // An older App-side answer set with fields the short form no longer has.
  await db.doc(ri.intakeDocPath("u1")).set({mainGoals: ["learning"],
    typicalMorning: "飲茶", onMind: "secret", createdAt: "2026-10-01T00:00:00Z",
    completedParts: [1, 2], allCompleted: false});
  const r = await ri.recordIntake(db, K1, {uid: "u1", answers: ANSWERS},
      {now: NOW});
  assert.strictEqual(r.researchId, "PILOT-01");
  assert.strictEqual(r.people, 2);
  const d = (await db.doc(ri.intakeDocPath("u1")).get()).data();
  assert.deepStrictEqual(d.mainGoals, ["companionship", "share_memories"]);
  assert.strictEqual(d.typicalMorning, "飲茶"); // untouched
  assert.strictEqual(d.onMind, "secret"); // untouched, never read
  assert.strictEqual(d.createdAt, "2026-10-01T00:00:00Z");
  assert.strictEqual(d.allCompleted, true);
  assert.deepStrictEqual(d.completedParts, [1, 2, 3, 4, 5, 6]);
  assert.strictEqual(d.source, "researcher");
  assert.strictEqual(d.recordedBy, "keran");
  assert.deepStrictEqual(d.activities, ["yum_cha", "mahjong"]);
  assert.strictEqual(d.activitiesOther, "聽粵曲");
  assert.strictEqual(d.researcherNote, "老人家健談，咩都想講");
  assert.deepStrictEqual(d.importantPeople[0],
      {name: "阿女", relationship: "女", extra: null, share: true});
  const u = (await db.doc("users/u1").get()).data();
  assert.strictEqual(u.hasCompletedIntake, true);
  assert.deepStrictEqual(u.interests, ["yum_cha", "mahjong"]);
  assert.deepStrictEqual(u.closeContacts, [
    {name: "阿女", relation: "女", phone: null, share: true},
    {name: "黃太", relation: "鄰居", phone: null, share: false}]);
  assert.strictEqual(u.avoidTopics, "唔好提我先生");
  assert.strictEqual(u.inputMode, "voice");
  assert.strictEqual(u.arm, "B"); // untouched
  assert.strictEqual(u.researcherNote, undefined); // intake doc only
  const audit = await db.collection(ri.AUDIT_COLLECTION).get();
  assert.strictEqual(audit.size, 1);
  const row = audit.docs[0].data();
  assert.strictEqual(row.uid, "u1");
  assert.strictEqual(row.researchId, "PILOT-01");
  assert.strictEqual(row.by, "keran");
  assert.strictEqual(row.replaced, true);
  assert.deepStrictEqual(row.fields, {goals: 2, people: 2, interests: 2,
    avoidTopics: true, researcherNote: true});
  assert.strictEqual(JSON.stringify(row).indexOf("阿女"), -1); // no text
  // Second recording: a fresh audit row, profile replaced not appended.
  await ri.recordIntake(db, K1, {uid: "u1",
    answers: {mainGoals: ["curious"], interests: ["news"]}}, {now: NOW});
  const u2 = (await db.doc("users/u1").get()).data();
  assert.deepStrictEqual(u2.interests, ["news"]);
  assert.deepStrictEqual(u2.closeContacts, []);
  assert.strictEqual(u2.avoidTopics, null);
  assert.strictEqual((await db.collection(ri.AUDIT_COLLECTION).get()).size, 2);
});

test("recordIntake: refused for blinded / participant callers, unknown, " +
    "unenrolled, tester and own accounts", async () => {
  await reset();
  await enrolled("u1");
  await db.doc("users/u2").set({displayName: "x"}); // not enrolled
  await db.doc("users/ut").set({displayName: "t", isTester: true});
  await db.doc("research_id_map/ut").set({researchId: "PILOT-09"});
  const call = (caller, uid) => ri.recordIntake(db, caller,
      {uid, answers: ANSWERS}, {now: NOW});
  assert.strictEqual(await code(call(BLINDED, "u1")),
      "not_unblinded_researcher");
  assert.strictEqual(await code(call(ELDER, "u1")),
      "not_unblinded_researcher");
  assert.strictEqual(await code(call(K1, "")), "account_not_found");
  assert.strictEqual(await code(call(K1, "ghost")), "account_not_found");
  assert.strictEqual(await code(call(K1, "u2")), "not_enrolled");
  assert.strictEqual(await code(call(K1, "ut")), "tester_account");
  assert.strictEqual(await code(call(K1, "keran")), "own_account");
  assert.strictEqual((await db.collection(ri.AUDIT_COLLECTION).get()).size, 0);
  assert.strictEqual((await db.doc("users/u1").get()).get("hasCompletedIntake"),
      false);
});

test("T48 intakeFactsFor: routing per companion, only shared people, " +
    "nothing for empty answers", () => {
  const a = ri.normaliseAnswers(ANSWERS);
  const facts = ri.intakeFactsFor(a);
  const by = (agent) => facts.filter((f) => f.agent_id === agent)
      .map((f) => `${f.category}:${f.key}`);
  assert.deepStrictEqual(by("siu_yan"), ["preference:嚟呢度主要想",
    "hobby:平時鍾意", "family:重要嘅人", "preference:唔想主動提起",
    "preference:研究員觀察"]);
  assert.deepStrictEqual(by("tung_tung"), ["preference:嚟呢度主要想",
    "hobby:平時鍾意", "preference:唔想主動提起", "preference:研究員觀察"]);
  assert.deepStrictEqual(by("ah_jan_ah_bak"), ["preference:嚟呢度主要想",
    "preference:唔想主動提起", "preference:研究員觀察"]);
  const note = facts.filter((f) => f.key === "研究員觀察");
  assert.strictEqual(note.length, 3);
  assert.strictEqual(note[0].value, "老人家健談，咩都想講"); // verbatim
  const people = facts.find((f) => f.key === "重要嘅人");
  assert.strictEqual(people.value, "阿女（女）"); // 黃太 not shared
  const hobby = facts.find((f) => f.key === "平時鍾意");
  assert.strictEqual(hobby.value, "飲茶／一盅兩件、打牌／打麻雀、聽粵曲");
  assert.deepStrictEqual(ri.intakeFactsFor(ri.normaliseAnswers({})), []);
});

test("T48 recordIntake: Hybrid arm gets the facts (superseded on " +
    "re-record, conversation facts untouched); rule arm gets none",
async () => {
  await reset();
  await enrolled("u1", {arm: "A"});
  const col = db.collection("users/u1/mem_facts");
  await col.add({agent_id: "siu_yan", category: "name", key: "稱呼",
    value: "陳太", status: "active", source_session_id: "sess-1"});
  const r = await ri.recordIntake(db, K1, {uid: "u1", answers: ANSWERS},
      {now: NOW});
  assert.strictEqual(r.memoryFacts, 12);
  const active = (await col.where("status", "==", "active").get()).docs
      .map((d) => d.data());
  assert.strictEqual(active.length, 13); // 12 intake + the conversation one
  const intake = active.filter((f) => f.source_session_id === "intake");
  assert.strictEqual(intake.length, 12);
  for (const f of intake) {
    assert.strictEqual(f.visibility, "agent");
    assert.strictEqual(f.layer, "private");
    assert.strictEqual(f.sourceAgent, f.agent_id);
    assert.strictEqual(f.sensitivity, "normal");
  }
  // Re-record with fewer answers: old intake facts superseded.
  const r2 = await ri.recordIntake(db, K1, {uid: "u1",
    answers: {mainGoals: ["curious"]}}, {now: NOW});
  assert.strictEqual(r2.memoryFacts, 3);
  const after = (await col.get()).docs.map((d) => d.data());
  assert.strictEqual(after.filter((f) => f.status === "active").length, 4);
  assert.strictEqual(after.filter((f) => f.status === "superseded").length,
      12);
  assert.strictEqual(after.find((f) => f.source_session_id === "sess-1")
      .status, "active");
  // Rule arm: nothing.
  await enrolled("u9", {arm: "B"});
  await db.doc("research_id_map/u9").set({researchId: "PILOT-02"});
  const rb = await ri.recordIntake(db, K1, {uid: "u9", answers: ANSWERS},
      {now: NOW});
  assert.strictEqual(rb.memoryFacts, 0);
  assert.strictEqual((await db.collection("users/u9/mem_facts").get()).size,
      0);
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
  console.log(`all ${tests.length} researcher_intake tests passed`);
  process.exit(0);
})();
