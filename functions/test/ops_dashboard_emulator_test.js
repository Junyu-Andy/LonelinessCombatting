/**
 * T39 — the operations dashboard against the Firestore emulator with
 * synthetic data (dev-tasks-1014c T39 验收 + 1014d 验收补充 6–11):
 * 3 PILOT + 10 PB participants, both arms.
 *
 *   - switch off → disabled; `blinded`, participants, legacy names →
 *     not_unblinded; `unblinded` + switch on → the table;
 *   - per-person rows: numbers right for a synthetic day pattern;
 *   - 4 days unopened → whatsapp and on the due list; 7 → phone;
 *     day 30+ unopened → follow_up_period; a legacy-build person (only
 *     sessions, no usage events) → legacy basis, flagged;
 *   - a 3-hour foreground stretch → 60 minutes;
 *   - the response and the CSV carry no outcome value / score key;
 *   - every open writes ops_audit_log; the rollup stores finished days
 *     in ops_daily and the table reads them back unchanged.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/ops_dashboard_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const O = require("../ops_dashboard");
const flags = require("../feature_flags");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();

const JUNYU = {uid: "junyuUnblinded00000000000003", email: "junyu@x.test",
  role: "unblinded"};
const KERAN = {uid: "assessorKeran0000000000000001", role: "blinded"};
const NOW = new Date("2026-10-25T04:00:00Z"); // 2026-10-25 12:00 HKT
const TODAY = "2026-10-25";
const at = (s) => new Date(s);

async function reset() {
  for (const c of ["users", "enrollments", "research_id_map", "research_ids",
    "app_config", "ops_daily", "ops_audit_log", "safety_events",
    "pi_alerts", "stt_usage", "weekly_status"]) {
    const docs = await db.collection(c).listDocuments();
    for (const d of docs) await db.recursiveDelete(d);
  }
}

async function setFlag(on) {
  await db.doc(flags.FLAGS_DOC).set({[O.FLAG]: on}, {merge: true});
}

function dayKey(w0, d) {
  const dt = new Date(`${w0}T00:00:00Z`);
  dt.setUTCDate(dt.getUTCDate() + d);
  return dt.toISOString().slice(0, 10);
}

// Synthetic participant.  `opens` = study days with a foreground event
// (usage basis) or a session start (legacy basis).
async function participant(p) {
  const uid = p.uid;
  const cohort = p.period === "PILOT" ? "pilot" : "phase_b";
  await db.doc(`users/${uid}`).set({uid, arm: p.arm, cohort, w0Date: p.w0,
    displayName: "合成", email: `${uid}@x.test`});
  await db.doc(`enrollments/${uid}`).set({uid, researchId: p.rid,
    studyPeriod: p.period, arm: p.arm, w0Date: p.w0,
    companionVariant: "feminine", enrolledAt: at(`${p.w0}T02:00:00Z`)});
  await db.doc(`research_id_map/${uid}`).set({researchId: p.rid});
  await db.doc(`research_ids/${p.rid}`).set({uid});
  const u = db.collection("users").doc(uid);
  for (const d of p.opens || []) {
    const key = dayKey(p.w0, d);
    if (p.legacy) {
      await u.collection("sessions").add({sessionId: `s${d}`,
        agentId: "siu_yan", moduleId: "m2_check_in", sessionType: "check_in",
        startedAt: at(`${key}T01:30:00Z`), endedAt: at(`${key}T01:40:00Z`),
        endReason: "close_button", userMessageCount: 2, isValid: true,
        scheduleVersion: 2});
    } else {
      const minutes = (p.minutesOn && p.minutesOn[d]) || 5;
      const start = at(`${key}T01:00:00Z`); // 09:00 HKT
      await u.collection("usage_events").add({type: "foreground",
        clientAt: start, receivedAt: start, appVersion: "1.0.0",
        buildNumber: "4", platform: "android", schemaVersion: 1});
      await u.collection("usage_events").add({type: "background",
        clientAt: new Date(start.getTime() + minutes * 60000),
        receivedAt: new Date(start.getTime() + minutes * 60000),
        appVersion: "1.0.0", buildNumber: "4", platform: "android",
        schemaVersion: 1});
      const agents = (p.validOn && p.validOn[d]) || [];
      for (let i = 0; i < agents.length; i++) {
        const agent = agents[i];
        await u.collection("sessions").add({sessionId: `${d}-${agent}-${i}`,
          agentId: agent, moduleId: "m4_tung_tung", sessionType: "free_chat",
          startedAt: at(`${key}T01:01:00Z`), endedAt: at(`${key}T01:20:00Z`),
          endReason: "close_button", userMessageCount: 4, isValid: true,
          scheduleVersion: 2, briefPrStatus: "completed"});
        await u.collection("brief_pr").doc(`${d}-${agent}-${i}`).set({
          schemaVersion: 3, agentId: agent, invitedAt: at(`${key}T01:20:00Z`),
          finalStatus: "completed", understanding: 6, validation: 6,
          caring: 7, insensitivity: 1});
      }
    }
  }
  // Outcome values that must never surface.
  await u.collection("djg_responses").doc("W1").set({status: "submitted",
    scores: {total: 4, emotional: 2, social: 2}, answers: {q1: "yes"}});
  await u.collection("pgic").doc("W1").set({value: 5});
  await u.collection("daily_mood").add({mood: 4, date_iso: dayKey(p.w0, 1)});
  if (p.arm === "A") {
    await u.collection("mem_facts").add({status: "active", layer: "shared",
      text: "鍾意飲茶"});
    await u.collection("mem_facts").add({status: "active", layer: "private",
      text: "膝頭痛"});
  }
  if (p.rid === "PB-002") {
    // 1020e 二.9: an acute event the researcher marked 誤觸.
    await db.collection("safety_events").add({uid, level: "acute",
      source: "user_input", createdAt: NOW, falseAlarm: true});
  }
  if (p.rid === "PB-001") {
    await db.collection("safety_events").add({uid, level: "acute",
      source: "user_input", createdAt: NOW});
    await db.collection("pi_alerts").add({uid, level: "acute",
      acknowledgedAt: null});
    await db.collection("stt_usage").add({uid, bytes: 10});
    await u.collection("events").add({name: "voice_transcription_failed",
      params: {}, timestamp: NOW});
    await u.collection("weekly_pr").doc("W1").set({status: "completed"});
    await db.collection("weekly_status").doc(uid).set({uid,
      bundles: {W1: {pushedAt: NOW}, W2: {pushedAt: NOW, missedAt: NOW}}});
  }
}

const code = async (p) => {
  try {
    await p;
  } catch (e) {
    return e.opsCode || e.message;
  }
  return "no error";
};

const FORBIDDEN_KEYS = new RegExp("score|djg|ucla|phq|gad|pgic|" +
  "social_contact|continuance|aimhs|answers|text|sequence|strat", "i");

function assertNoForbiddenKeys(obj, where) {
  if (Array.isArray(obj)) {
    return obj.forEach((o, i) => assertNoForbiddenKeys(o, `${where}[${i}]`));
  }
  if (obj && typeof obj === "object") {
    for (const k of Object.keys(obj)) {
      assert.ok(!FORBIDDEN_KEYS.test(k), `${where}: key ${k}`);
      assertNoForbiddenKeys(obj[k], `${where}.${k}`);
    }
  }
}

const PEOPLE = [
  // 3 PILOT (W0 = 2026-10-15, today = day 10)
  {uid: "pilot01", rid: "PILOT-01", period: "PILOT", arm: "A",
    w0: "2026-10-15", opens: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    validOn: {10: ["siu_yan", "tung_tung", "tung_tung"]},
    minutesOn: {3: 180}}, // acceptance 10: 3 h → 60
  {uid: "pilot02", rid: "PILOT-02", period: "PILOT", arm: "A",
    w0: "2026-10-15", opens: [1, 2, 6]}, // last day 6 → 4 unopened
  {uid: "pilot03", rid: "PILOT-03", period: "PILOT", arm: "B",
    w0: "2026-10-15", opens: [3]}, // 7 unopened → phone
  // 10 PB
  {uid: "pb001", rid: "PB-001", period: "B", arm: "A", w0: "2026-10-20",
    opens: [1, 5]},
  {uid: "pb002", rid: "PB-002", period: "B", arm: "B", w0: "2026-10-20",
    opens: [2], legacy: true}, // acceptance 9: old build
  {uid: "pb003", rid: "PB-003", period: "B", arm: "A", w0: "2026-09-20",
    opens: [1, 2, 3, 20, 29]}, // today day 35, 6 unopened → follow-up period
  {uid: "pb004", rid: "PB-004", period: "B", arm: "B", w0: "2026-10-24",
    opens: [1]},
  {uid: "pb005", rid: "PB-005", period: "B", arm: "A", w0: "2026-10-25",
    opens: []}, // day 0 today
  {uid: "pb006", rid: "PB-006", period: "B", arm: "B", w0: "2026-10-22",
    opens: []}, // never opened, day 3 → whatsapp
  {uid: "pb007", rid: "PB-007", period: "B", arm: "A", w0: "2026-10-22",
    opens: [1, 2, 3]},
  {uid: "pb008", rid: "PB-008", period: "B", arm: "B", w0: "2026-10-18",
    opens: [1, 7]},
  {uid: "pb009", rid: "PB-009", period: "B", arm: "A", w0: "2026-10-18",
    opens: [1, 2, 3, 4, 5, 6, 7]},
  {uid: "pb010", rid: "PB-010", period: "B", arm: "B", w0: "2026-10-18",
    opens: [2, 4, 6]},
];

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("seed 3 PILOT + 10 PB", async () => {
  await reset();
  for (const p of PEOPLE) await participant(p);
});

test("switch off: people / person / csv refuse; rollup skips", async () => {
  await setFlag(false);
  assert.strictEqual(await code(O.people(db, JUNYU, {now: NOW})), "disabled");
  assert.strictEqual(await code(O.person(db, JUNYU, {researchId: "PB-001"},
      {now: NOW})), "disabled");
  assert.strictEqual(await code(O.csv(db, JUNYU, {}, {now: NOW})),
      "disabled");
  assert.deepStrictEqual(await O.rollup(db, {now: NOW}),
      {people: 0, skipped: true});
  assert.strictEqual((await db.collection(O.AUDIT_COLLECTION).get()).size, 0);
});

test("blinded, participant, legacy names: not_unblinded (acceptance 4)",
    async () => {
      await setFlag(true);
      for (const c of [KERAN, {uid: "p", role: null}, {uid: "o", role: "pi"},
        {uid: "o2", role: "researcher"},
        {uid: "c", role: "sequence_uploader"}]) {
        assert.strictEqual(await code(O.people(db, c, {now: NOW})),
            "not_unblinded", String(c.role));
        assert.strictEqual(await code(O.person(db, c, {researchId: "PB-001"},
            {now: NOW})), "not_unblinded");
        assert.strictEqual(await code(O.csv(db, c, {}, {now: NOW})),
            "not_unblinded");
      }
      assert.strictEqual((await db.collection(O.AUDIT_COLLECTION).get()).size,
          0, "a refused call is not an open");
    });

let table;
test("unblinded: the table, 13 rows, numbers right", async () => {
  table = await O.people(db, JUNYU, {now: NOW});
  assert.strictEqual(table.today, TODAY);
  assert.strictEqual(table.people.length, 13);
  const by = {};
  for (const p of table.people) by[p.researchId] = p;

  const p1 = by["PILOT-01"];
  assert.strictEqual(p1.studyPeriod, "PILOT");
  assert.strictEqual(p1.arm, "A");
  assert.strictEqual(p1.studyDay, 10);
  assert.strictEqual(p1.openedToday, true);
  assert.strictEqual(p1.consecutiveUnopenedDays, 0);
  assert.strictEqual(p1.stage, "none");
  assert.strictEqual(p1.legacyBasis, false);
  assert.deepStrictEqual(p1.validSessions,
      {total: 3, byCompanion: {siu_yan: 1, ah_jan_ah_bak: 0, tung_tung: 2},
        byType: {free_chat: 3, check_in: 0, reminiscence: 0}});
  assert.strictEqual(p1.briefPr.invited, 3);
  assert.strictEqual(p1.briefPr.completed, 3);
  assert.deepStrictEqual(p1.memory, {shared: 1, private: 1});
  assert.strictEqual(p1.moodDays, 1);
  // Last use = the later of the last foreground (09:00) and the last
  // session start (09:01).
  assert.strictEqual(p1.lastUseAt, "2026-10-25T01:01:00.000Z");

  assert.strictEqual(by["PILOT-02"].consecutiveUnopenedDays, 4);
  assert.strictEqual(by["PILOT-02"].stage, "whatsapp"); // acceptance 6
  assert.strictEqual(by["PILOT-03"].consecutiveUnopenedDays, 7);
  assert.strictEqual(by["PILOT-03"].stage, "phone"); // acceptance 7
  assert.strictEqual(by["PILOT-03"].memory, null, "rule arm: 不適用");

  const pb3 = by["PB-003"];
  assert.strictEqual(pb3.studyDay, 35);
  assert.strictEqual(pb3.stage, "follow_up_period"); // acceptance 8
  assert.strictEqual(pb3.consecutiveUnopenedDays, 6);

  const pb2 = by["PB-002"];
  assert.deepStrictEqual(pb2.safety,
      {pendingAck: 0, falseAlarm: 1, acute: 1, moderate: 0, low: 0});
  assert.strictEqual(pb2.legacyBasis, true); // acceptance 9
  assert.strictEqual(pb2.consecutiveUnopenedDays, 3);
  assert.strictEqual(pb2.stage, "whatsapp");

  assert.strictEqual(by["PB-005"].studyDay, 0);
  assert.strictEqual(by["PB-005"].stage, "none");
  assert.strictEqual(by["PB-006"].consecutiveUnopenedDays, 3);
  assert.strictEqual(by["PB-006"].stage, "whatsapp");

  const pb1 = by["PB-001"];
  assert.deepStrictEqual(pb1.safety,
      {pendingAck: 1, falseAlarm: 0, acute: 1, moderate: 0, low: 0});
  assert.deepStrictEqual(pb1.voice, {uses: 1, failures: 1});
  assert.strictEqual(pb1.weekly.W1, "done");
  assert.strictEqual(pb1.weekly.W2, "missed");
  assert.strictEqual(pb1.weekly.W3, "not_yet");
  assert.strictEqual(pb1.weekly.W8, "not_built");

  assertNoForbiddenKeys(table, "people");
});

test("due list: WhatsApp / phone people, most days first, no arm " +
    "(page 1 item 7)", () => {
  const ids = table.dueList.map((d) => `${d.researchId}:${d.stage}:` +
    d.consecutiveUnopenedDays);
  // PB-010 (days 2, 4, 6 of 7) and PB-007 (opened today) are not due;
  // PB-003 is in the follow-up period.
  assert.deepStrictEqual(ids, ["PILOT-03:phone:7", "PILOT-02:whatsapp:4",
    "PB-002:whatsapp:3", "PB-006:whatsapp:3"]);
  for (const d of table.dueList) assert.ok(!("arm" in d));
});

test("person page: day grid, 3 h stretch → 60 min (acceptance 10), legacy " +
    "person shows 不可用, recent sessions without text", async () => {
  const p1 = await O.person(db, JUNYU, {researchId: "PILOT-01"}, {now: NOW});
  assert.strictEqual(p1.days.length, 10);
  const d3 = p1.days[2];
  assert.strictEqual(d3.studyDay, 3);
  assert.strictEqual(d3.foregroundMinutes, 60);
  assert.strictEqual(d3.opened, true);
  assert.strictEqual(d3.firstOpenAt, "09:00");
  assert.strictEqual(p1.days[9].validSessions.tung_tung, 2);
  assert.strictEqual(p1.days[9].briefPrInvited, 3);
  assert.strictEqual(p1.recentSessions.length, 3);
  assert.strictEqual(p1.recentSessions[0].durationMinutes, 19);
  assertNoForbiddenKeys(p1, "person");

  const pb2 = await O.person(db, JUNYU, {researchId: "PB-002"}, {now: NOW});
  assert.strictEqual(pb2.person.legacyBasis, true);
  assert.strictEqual(pb2.days[1].opened, true);
  assert.strictEqual(pb2.days[1].basis, "legacy");
  assert.strictEqual(pb2.days[1].foregroundMinutes, null);
  assert.strictEqual(pb2.days[1].firstOpenAt, "09:30");

  assert.strictEqual(await code(O.person(db, JUNYU, {researchId: "PB-999"},
      {now: NOW})), "unknown_research_id");
  assert.strictEqual(await code(O.person(db, JUNYU, {researchId: ""},
      {now: NOW})), "invalid_research_id");
});

test("CSV: one person and everyone; no outcome column (acceptance 11)",
    async () => {
      const one = await O.csv(db, JUNYU, {researchId: "PILOT-01"}, {now: NOW});
      assert.strictEqual(one.filename, `ops_daily_PILOT-01_${TODAY}.csv`);
      assert.strictEqual(one.rows, 10);
      const lines = one.csv.trim().split("\n");
      assert.strictEqual(lines.length, 11);
      assert.strictEqual(lines[0], O.CSV_COLUMNS.join(","));
      assert.ok(!/djg|ucla|phq|gad|pgic|social|continu|aimhs|score|answer/i
          .test(one.csv), "no outcome column or value in the CSV");
      assert.ok(lines[3].indexOf(",60,") > 0, "day 3 shows 60 minutes");

      const all = await O.csv(db, JUNYU, {}, {now: NOW});
      assert.strictEqual(all.filename, `ops_daily_all_${TODAY}.csv`);
      assert.ok(all.rows > 10);
      assert.ok(all.csv.indexOf("PB-002,B,B,2,2026-10-22,1,09:30,,1,0,0,0,0," +
        "legacy") > 0, "legacy row");
    });

test("every open / export is in ops_audit_log (acceptance 5)", async () => {
  const snap = await db.collection(O.AUDIT_COLLECTION).get();
  const types = snap.docs.map((d) => d.get("type")).sort();
  assert.deepStrictEqual(types, ["export_csv", "export_csv", "open_people",
    "open_person", "open_person"].sort());
  for (const d of snap.docs) {
    assert.strictEqual(d.get("by"), JUNYU.uid);
    assert.ok(d.get("at"));
  }
});

test("rollup stores finished days in ops_daily; the table reads them " +
    "back unchanged; today is not stored", async () => {
  const docs = await db.collection(O.DAILY_COLLECTION).listDocuments();
  for (const d of docs) await db.recursiveDelete(d);
  const r = await O.rollup(db, {now: NOW});
  assert.deepStrictEqual(r, {people: 13, skipped: false});
  const stored = await db.collection(O.DAILY_COLLECTION).doc("pilot01")
      .collection(O.DAYS_SUBCOLLECTION).get();
  assert.strictEqual(stored.size, 9, "days 1–9 stored, today computed");
  assert.ok(!stored.docs.some((d) => d.id === TODAY));
  const d3 = stored.docs.find((d) => d.id === "2026-10-18").data();
  assert.strictEqual(d3.foregroundMinutes, 60);
  // A later table read uses the stored rows (and still computes today).
  const again = await O.person(db, JUNYU, {researchId: "PILOT-01"},
      {now: NOW});
  assert.strictEqual(again.days[2].foregroundMinutes, 60);
  assert.strictEqual(again.days[9].opened, true);
  assert.strictEqual(again.person.stage, "none");
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
  await reset();
  if (failed) {
    console.log(`${failed} ops_dashboard emulator test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} ops_dashboard emulator tests passed`);
})();
