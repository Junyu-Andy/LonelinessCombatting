/**
 * dev-tasks-1020 batch 4 (F(5), G(1)(3)) against the Firestore emulator,
 * with a simulated clock, synthetic accounts only, a fake FCM sender and a
 * captured mailer (no real push, no real e-mail):
 *
 *   1. weekly W1–W3: three people complete on day 1, 2 and 3 (and one
 *      never does) → W1 to all, W2 / W3 only to those not done, the 10:00
 *      e-mail on day 3 lists only research ID, study day and week;
 *   2. week 4: W1-4 / W2-4 / W3-4, the closing day moved by a late W4
 *      visit (weekly_status.w4VisitDate);
 *   3. P1 at 08:30 to both arms; P2 at 19:00 skips whoever finished
 *      today's check-in — old form rows, chat_v2 rows, the
 *      check_in_submitted event — and whoever gets a weekly push today;
 *   4. switches off → today's behaviour (19:00 broadcast Mon–Sat only, no
 *      08:30, old weekly copy and 24-hour reminder, no e-mail);
 *   5. the console test e-mail and the sendTestPush mapping.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/pushes_email_1020_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ||
  "loneliness-pilot-dev";
process.env.DEEPSEEK_API_KEY = "test-key";

const fns = require("../index"); // initialises firebase-admin
const admin = require("firebase-admin");
const ws = require("../weekly_schedule");
const sw = require("../study_week");
const sp = require("../study_period");
const qh = require("../quiet_hours");
const piAlert = require("../pi_alert");
const pc = require("../push_copy");
const daily = require("../daily_checkin_push");
const email = require("../weekly_email");

const db = admin.firestore();
const silent = () => {};
const ts = (d) => admin.firestore.Timestamp.fromDate(d);

// W0 = 2026-10-19 (Monday) = study day 0; hk(day, hour) = HKT instant.
const W0 = "2026-10-19";
function hk(day, hour, minute) {
  const key = sw.addDays(W0, day);
  const hh = String(hour).padStart(2, "0");
  const mm = String(minute || 0).padStart(2, "0");
  return new Date(`${key}T${hh}:${mm}:00+08:00`);
}
const dayKey = (day) => sw.addDays(W0, day);

const PRIMARY = "junyu@test.invalid";
const ASSESSOR = "assessor@test.invalid";
const SMTP = {host: "smtp.test.invalid", user: "sender@test.invalid",
  pass: "x", piEmail: "legacy-pi@test.invalid"};
let mails = [];
piAlert.setMailerForTests(async (msg) => {
  mails.push(msg);
});
piAlert.setAuthForTests({
  getUserByEmail: async (addr) => {
    if (addr === PRIMARY) return {customClaims: {role: "unblinded"}};
    if (addr === ASSESSOR) return {customClaims: {role: "blinded"}};
    const e = new Error("not found");
    e.code = "auth/user-not-found";
    throw e;
  },
});

function fakeMessaging() {
  const sent = [];
  return {
    sent,
    send: async (msg) => {
      sent.push(msg);
      return `id-${sent.length}`;
    },
    // uid → bodies, from the fake token "tok-<uid>"
    to: (uid) => sent.filter((m) => m.token === `tok-${uid}`)
        .map((m) => m.notification.body),
    uids: () => sent.map((m) => m.token.slice(4)).sort(),
    clear: () => {
      sent.length = 0;
    },
  };
}

async function reset(flags, phaseB) {
  for (const p of ["users", "app_config", "weekly_status", "research_id_map",
    "alert_audit_log", "meta"]) {
    await db.recursiveDelete(db.collection(p));
  }
  if (flags) await db.doc("app_config/feature_flags").set(flags);
  if (phaseB !== null) {
    await db.doc(ws.CONFIG_DOC).set(phaseB || {weeklyScheduleV2Enabled: true});
  }
  await db.doc("meta/alert_config").set({enabled: true,
    primaryEmail: PRIMARY});
  mails = [];
}

async function seedUser(uid, data, researchId) {
  await db.doc(`users/${uid}`).set(Object.assign(
      {createdAt: "2026-09-01T09:00:00.000", w0Date: W0,
        armAssignmentMode: "randomise"}, data));
  await db.doc(`users/${uid}/fcm_tokens/dev1`).set({token: `tok-${uid}`});
  if (researchId) {
    await db.doc(`research_id_map/${uid}`).set({researchId});
  }
}

// Synthetic people: one per cohort and arm, plus the ones who must never
// get anything (a tester, an unregistered account) and a tester who
// switched arm in 測試員工具 (runs like a pilot participant).
async function seedPeople() {
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  await seedUser("r2", {arm: "B", cohort: sp.COHORT_RUN_IN}, "PB-02");
  await seedUser("r3", {arm: "A", cohort: sp.COHORT_PILOT,
    armAssignmentMode: sp.PILOT_MODE}, "PILOT-03");
  await seedUser("r4", {arm: "B", cohort: sp.COHORT_RCT}, "RCT-04");
  await seedUser("t1", {arm: "B", cohort: sp.COHORT_RCT, isTester: true},
      "RCT-T99");
  await seedUser("t2", {arm: "A", cohort: sp.COHORT_PILOT, isTester: true,
    armAssignedBy: "tester_switch"});
  await seedUser("x1", {arm: "B"});
}

// Every part of a bundle submitted (social probe off → DJG on W1–W3,
// Weekly PR, PGIC).
async function complete(uid, bundleId, at) {
  const u = db.doc(`users/${uid}`);
  const when = ts(at);
  if (["W1", "W2", "W3"].indexOf(bundleId) >= 0) {
    await u.collection("djg_responses").doc(bundleId).set({
      timepoint: bundleId, bundle: bundleId, status: "submitted",
      submittedAt: when});
  }
  await u.collection("weekly_pr").doc(bundleId).set({bundle: bundleId,
    status: "completed", answeredAt: when});
  await u.collection("pgic").doc(bundleId).set({bundle: bundleId, value: 6,
    answeredAt: when});
}

const dispatch = (m, now) => ws.dispatchWeeklyBundles(db, m,
    {now, log: silent, quiet: qh.quietHoursConfigFrom({})});
const runEmail = (now, extra) => email.sendDailyIncompleteEmail(db,
    Object.assign({now, smtp: SMTP, auth: null}, extra || {}));
const ALL_ON = {checkInChatV2Enabled: true, weeklyReminderV2Enabled: true};

// What E1 must never carry: arms, cohort labels, answers, uids.
function assertNoForbidden(text) {
  for (const bad of ["arm", "Arm", "Hybrid", "規則", "规则组", "组别：",
    sp.COHORT_RCT + "\"", sp.COHORT_RUN_IN, `${sp.COHORT_PILOT} `,
    "completed", "value", "r1", "r2", "r3", "r4", "t1", "t2", "x1"]) {
    assert.ok(text.indexOf(bad) < 0, `e-mail must not contain ${bad}`);
  }
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

// ---------------------------------------------------------------------------
// 1. Weekly W1–W3
// ---------------------------------------------------------------------------

test("W1–W3: done on day 1 / 2 / 3 — W1 to all, W2 and W3 only to those " +
    "not done, both arms and all three prefixes alike", async () => {
  await reset(ALL_ON);
  await seedPeople();
  const m = fakeMessaging();

  // Day 1 = study day 7.  Nothing before 20:00.
  await dispatch(m, hk(7, 19));
  assert.strictEqual(m.sent.length, 0);
  const c1 = await dispatch(m, hk(7, 20));
  assert.strictEqual(c1.reminderV2, true);
  assert.deepStrictEqual(m.uids(), ["r1", "r2", "r3", "r4", "t2"]);
  for (const uid of ["r1", "r2", "r3", "r4", "t2"]) {
    assert.deepStrictEqual(m.to(uid), [pc.TEXT.W1], uid);
  }
  const st1 = (await db.doc("weekly_status/r1").get()).data();
  assert.strictEqual(st1.bundles.W1.pushCopyId, "W1");
  const ev = (await db.collection("users/r1/events")
      .where("name", "==", "weekly_bundle_push_sent").get()).docs[0].data();
  assert.strictEqual(ev.params.copyId, "W1");

  // r1 completes on day 1 (21:00 run sends nothing new).
  await complete("r1", "W1", hk(7, 20, 30));
  m.clear();
  await dispatch(m, hk(7, 21));
  assert.strictEqual(m.sent.length, 0);

  // Day 2 = study day 8: nothing before the push hour; W2 at 20:00 to the
  // three not done.  T18's 24-hour reminder text is never used.
  await dispatch(m, hk(8, 10));
  await dispatch(m, hk(8, 19));
  assert.strictEqual(m.sent.length, 0);
  await dispatch(m, hk(8, 20));
  assert.deepStrictEqual(m.uids(), ["r2", "r3", "r4", "t2"]);
  assert.deepStrictEqual(m.to("r2"), [pc.TEXT.W2]);
  assert.ok(m.sent.every((x) => x.notification.body !== ws.REMINDER_BODY));
  m.clear();
  await dispatch(m, hk(8, 21));
  assert.strictEqual(m.sent.length, 0, "W2 once only");

  // r2 completes on day 2; r3 does DJG only (still incomplete).
  await complete("r2", "W1", hk(8, 21, 30));
  await db.doc("users/r3/djg_responses/W1").set({timepoint: "W1",
    bundle: "W1", status: "submitted"});

  // Day 3 = study day 9, 10:00: the e-mail lists r3 and r4 only, plus
  // nothing else (testers never; ID, study day, week only).
  const e = await runEmail(hk(9, 10));
  assert.strictEqual(e.status, "sent");
  assert.strictEqual(e.count, 2);
  assert.strictEqual(mails.length, 1);
  const mail = mails[0];
  assert.strictEqual(mail.subject, pc.E1_SUBJECT);
  assert.strictEqual(mail.to, PRIMARY);
  const rows = mail.text.split("\n").filter((l) => /^[A-Z]+-/.test(l));
  assert.deepStrictEqual(rows, [
    "PILOT-03 ｜ 第 9 天 ｜ 第 1 周",
    "RCT-04 ｜ 第 9 天 ｜ 第 1 周",
  ]);
  assert.ok(mail.text.indexOf("共 2 人。") >= 0);
  assert.ok(mail.text.indexOf("RCT-T99") < 0, "tester never listed");
  assertNoForbidden(mail.text);
  const auditRow = (await db.doc(
      `alert_audit_log/${email.AUDIT_PREFIX}${dayKey(9)}`).get()).data();
  assert.strictEqual(auditRow.status, "sent");
  assert.strictEqual(auditRow.count, 2);
  assert.ok(JSON.stringify(auditRow).indexOf("RCT-04") < 0,
      "the audit row holds no research ID");

  // Same day again: once a day.
  const again = await runEmail(hk(9, 10, 5));
  assert.strictEqual(again.status, "already_done");
  assert.strictEqual(mails.length, 1);

  // r3 completes on day 3 (15:00), so W3 at 20:00 goes to r4 (and the
  // switched tester) only.
  await complete("r3", "W1", hk(9, 15));
  m.clear();
  await dispatch(m, hk(9, 20));
  assert.deepStrictEqual(m.uids(), ["r4", "t2"]);
  assert.deepStrictEqual(m.to("r4"), [pc.TEXT.W3]);
  const st4 = (await db.doc("weekly_status/r4").get()).data().bundles.W1;
  assert.ok(st4.w2PushSentAt && st4.w3PushSentAt);
  assert.strictEqual(st4.reminderSentAt, undefined);

  // Day 10, 10:00: not an e-mail day; window closes at 20:00 (unchanged).
  mails = [];
  assert.strictEqual((await runEmail(hk(10, 10))).status, "none");
  assert.strictEqual(mails.length, 0);
  m.clear();
  await dispatch(m, hk(10, 19));
  assert.strictEqual(m.sent.length, 0, "no push on day 4");
  await dispatch(m, hk(10, 20));
  assert.strictEqual((await db.doc("users/r4/pgic/W1").get()).data().status,
      "missed");
  assert.strictEqual((await db.doc("users/r1/pgic/W1").get()).data().value, 6);
});

test("e-mail: nobody incomplete → no e-mail; blinded primary → nobody; " +
    "switch off → nothing", async () => {
  await reset(ALL_ON);
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  await complete("r1", "W1", hk(7, 21));
  const e = await runEmail(hk(9, 10));
  assert.strictEqual(e.status, "none");
  assert.strictEqual(mails.length, 0);

  await reset(ALL_ON);
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  await db.doc("meta/alert_config").set({enabled: true,
    primaryEmail: ASSESSOR});
  assert.strictEqual((await runEmail(hk(9, 10))).status, "no_recipients");
  assert.strictEqual(mails.length, 0);
  const dropped = (await db.collection("alert_audit_log")
      .where("type", "==", "recipient_dropped").get()).docs;
  assert.strictEqual(dropped.length, 1);

  await reset({checkInChatV2Enabled: true});
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  assert.strictEqual((await runEmail(hk(9, 10))).status, "disabled");
  assert.strictEqual(mails.length, 0);
});

// ---------------------------------------------------------------------------
// 2. Week 4
// ---------------------------------------------------------------------------

test("week 4: W1-4 / W2-4 / W3-4; a late W4 visit moves the closing day, " +
    "the reminders and the e-mail", async () => {
  await reset(ALL_ON);
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  await seedUser("r2", {arm: "B", cohort: sp.COHORT_RCT}, "RCT-02");
  // W1–W3 already marked done / missed, so only W4 is in play.
  for (const uid of ["r1", "r2"]) {
    for (const id of ["W1", "W2", "W3"]) await complete(uid, id, hk(7, 21));
  }
  // r2's W4 visit (paper DJG-ES with the assessor) is on day 31.
  await db.doc("weekly_status/r2").set({w4VisitDate: dayKey(31)});
  const m = fakeMessaging();

  await dispatch(m, hk(26, 20));
  assert.deepStrictEqual(m.to("r1"), [pc.TEXT["W1-4"]]);
  assert.deepStrictEqual(m.to("r2"), [pc.TEXT["W1-4"]]);
  m.clear();

  // Day 27: nothing.  Day 28: W2-4 to r1 only (r2 closes on day 31).
  await dispatch(m, hk(27, 20));
  assert.strictEqual(m.sent.length, 0);
  await dispatch(m, hk(28, 20));
  assert.deepStrictEqual(m.uids(), ["r1"]);
  assert.deepStrictEqual(m.to("r1"), [pc.TEXT["W2-4"]]);
  m.clear();

  // Day 29: e-mail lists r1 (day 29, week 4); W3-4 to r1.
  await runEmail(hk(29, 10));
  assert.strictEqual(mails.length, 1);
  assert.deepStrictEqual(
      mails[0].text.split("\n").filter((l) => /^RCT-/.test(l)),
      ["RCT-01 ｜ 第 29 天 ｜ 第 4 周"]);
  await dispatch(m, hk(29, 20));
  assert.deepStrictEqual(m.uids(), ["r1"]);
  assert.deepStrictEqual(m.to("r1"), [pc.TEXT["W3-4"]]);
  m.clear();

  // Day 30, 08:00: r1's window closed at the end of day 29 → missed; r2's
  // runs to the end of day 31.  W2-4 to r2 at 20:00.
  await dispatch(m, hk(30, 8));
  assert.strictEqual((await db.doc("users/r1/pgic/W4").get()).data().status,
      "missed");
  assert.strictEqual((await db.doc("users/r2/pgic/W4").get()).exists, false);
  await dispatch(m, hk(30, 20));
  assert.deepStrictEqual(m.uids(), ["r2"]);
  assert.deepStrictEqual(m.to("r2"), [pc.TEXT["W2-4"]]);
  m.clear();

  // Day 31: e-mail lists r2 (day 31, week 4); W3-4 to r2.
  mails = [];
  await runEmail(hk(31, 10));
  assert.deepStrictEqual(
      mails[0].text.split("\n").filter((l) => /^RCT-/.test(l)),
      ["RCT-02 ｜ 第 31 天 ｜ 第 4 周"]);
  await dispatch(m, hk(31, 20));
  assert.deepStrictEqual(m.to("r2"), [pc.TEXT["W3-4"]]);
  // No 1–3 texts in week 4.
  for (const id of ["W1", "W2", "W3"]) {
    assert.ok(m.sent.every((x) => x.notification.body !== pc.TEXT[id]));
  }
  m.clear();
  await dispatch(m, hk(32, 8));
  assert.strictEqual((await db.doc("users/r2/pgic/W4").get()).data().status,
      "missed");
  const w = (await db.doc("weekly_status/r2").get()).data().bundles.W4;
  assert.strictEqual(w.windowEnd.toDate().toISOString(),
      sw.hkEndOfDay(dayKey(31)).toISOString());
});

test("week 5–7 (PGIC only) keep the old copy and the 24-hour reminder",
    async () => {
      await reset(ALL_ON);
      await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
      const m = fakeMessaging();
      await dispatch(m, hk(35, 20));
      assert.deepStrictEqual(m.to("r1"), [ws.PUSH_BODY]);
      m.clear();
      await dispatch(m, hk(36, 20));
      assert.deepStrictEqual(m.to("r1"), [ws.REMINDER_BODY]);
      mails = [];
      assert.strictEqual((await runEmail(hk(37, 10))).status, "none");
    });

test("weekly reminders switch off: exactly T24 (S14 copy, 24-hour " +
    "reminder, day-29 close, no e-mail)", async () => {
  await reset({checkInChatV2Enabled: true});
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  await db.doc("weekly_status/r1").set({w4VisitDate: dayKey(31)});
  const m = fakeMessaging();
  const c = await dispatch(m, hk(7, 20));
  assert.strictEqual(c.reminderV2, undefined);
  assert.deepStrictEqual(m.to("r1"), [ws.PUSH_BODY]);
  const ev = (await db.collection("users/r1/events")
      .where("name", "==", "weekly_bundle_push_sent").get()).docs[0].data();
  assert.strictEqual(ev.params.copyId, undefined);
  assert.strictEqual((await db.doc("weekly_status/r1").get()).data()
      .bundles.W1.pushCopyId, undefined);
  m.clear();
  await dispatch(m, hk(8, 20));
  assert.deepStrictEqual(m.to("r1"), [ws.REMINDER_BODY]);
  m.clear();
  await dispatch(m, hk(9, 20));
  assert.strictEqual(m.sent.length, 0, "no day-3 push with the switch off");
  // W4 closes on day 29 whatever the visit date (T24 as before).
  await dispatch(m, hk(30, 8));
  assert.strictEqual((await db.doc("users/r1/pgic/W4").get()).data().status,
      "missed");
  assert.strictEqual((await runEmail(hk(9, 10))).status, "disabled");
});

// ---------------------------------------------------------------------------
// 3. P1 and P2
// ---------------------------------------------------------------------------

test("P1 08:30: every registered participant, both arms, per person; " +
    "not testers or unregistered; once a day; quiet hours respected",
async () => {
  await reset(ALL_ON);
  await seedPeople();
  const m = fakeMessaging();
  const quiet = qh.quietHoursConfigFrom({});
  const c = await daily.sendMorningPush(db, m,
      {now: hk(3, 8, 30), log: silent, quiet});
  assert.strictEqual(c.pushed, 5);
  assert.deepStrictEqual(m.uids(), ["r1", "r2", "r3", "r4", "t2"]);
  for (const uid of ["r1", "r2"]) { // arm A and arm B
    assert.deepStrictEqual(m.to(uid), [pc.TEXT.P1], uid);
  }
  assert.ok(m.sent.every((x) => x.notification.title === "陪住"));
  assert.ok(m.sent.every((x) => !x.topic), "never a topic broadcast");
  const ev = (await db.collection("users/r2/events")
      .where("name", "==", daily.EVENT).get()).docs[0].data();
  assert.deepStrictEqual(
      {slot: ev.params.slot, dateKey: ev.params.dateKey},
      {slot: "P1", dateKey: dayKey(3)});
  m.clear();
  const again = await daily.sendMorningPush(db, m,
      {now: hk(3, 8, 31), log: silent, quiet});
  assert.strictEqual(again.already_sent, 5);
  assert.strictEqual(m.sent.length, 0);
  // Next day it goes again.
  await daily.sendMorningPush(db, m, {now: hk(4, 8, 30), log: silent, quiet});
  assert.strictEqual(m.sent.length, 5);
  // Quiet hours that run past 08:30 → nothing.
  m.clear();
  const late = qh.quietHoursConfigFrom({quietHoursStart: "22:00",
    quietHoursEnd: "09:00"});
  const q = await daily.sendMorningPush(db, m,
      {now: hk(5, 8, 30), log: silent, quiet: late});
  assert.strictEqual(q.quiet_hours, 5);
  assert.strictEqual(m.sent.length, 0);
});

test("P2 19:00: only to those who have not finished today's check-in " +
    "(old form row, chat_v2 row, check_in_submitted event; Hong Kong date)",
async () => {
  await reset(ALL_ON);
  const today = dayKey(3);
  const yesterday = dayKey(2);
  const people = {
    // finished today
    v2done: {arm: "A"}, formDone: {arm: "B"}, eventDone: {arm: "A"},
    safetyStop: {arm: "B"},
    // not finished today
    v2open: {arm: "A"}, formYesterday: {arm: "B"}, nothing: {arm: "B"},
    eventLateYesterday: {arm: "A"},
  };
  for (const uid of Object.keys(people)) {
    await seedUser(uid, Object.assign({cohort: sp.COHORT_RCT},
        people[uid]));
  }
  const rows = (uid) => db.collection(`users/${uid}/check_in_responses`);
  await rows("v2done").add({arm: "A", flow: "chat_v2", schema_version: 2,
    date_iso: today, completed: true});
  await rows("formDone").add({arm: "B", mood: 4, talked: 1, social_day: 2,
    note: "", date_iso: today});
  await db.collection("users/eventDone/events").add({
    name: "check_in_submitted", params: {mood: 4},
    timestamp: ts(hk(3, 9, 15))});
  await rows("safetyStop").add({arm: "B", flow: "chat_v2", date_iso: today,
    completed: false, stopped_by_safety: true});
  await rows("v2open").add({arm: "A", flow: "chat_v2", date_iso: today,
    completed: false});
  await rows("formYesterday").add({arm: "B", mood: 3, date_iso: yesterday});
  // 23:30 yesterday in Hong Kong is 15:30 UTC yesterday: not today.
  await db.collection("users/eventLateYesterday/events").add({
    name: "check_in_submitted", params: {mood: 3},
    timestamp: ts(hk(2, 23, 30))});

  const m = fakeMessaging();
  let doorbell = 0;
  const c = await daily.runEveningPush(db, m, {now: hk(3, 19), log: silent,
    quiet: qh.quietHoursConfigFrom({}), legacyDoorbell: async () => {
      doorbell++;
    }});
  assert.strictEqual(doorbell, 0, "no broadcast with the switch on");
  assert.deepStrictEqual(m.uids(),
      ["eventLateYesterday", "formYesterday", "nothing", "v2open"]);
  assert.deepStrictEqual(m.to("v2open"), [pc.TEXT.P2]);
  assert.strictEqual(c.done_chat_v2, 2);
  assert.strictEqual(c.done_form_v1, 1);
  assert.strictEqual(c.done_event, 1);
  m.clear();
  await daily.runEveningPush(db, m, {now: hk(3, 19, 1), log: silent,
    quiet: qh.quietHoursConfigFrom({})});
  assert.strictEqual(m.sent.length, 0, "once a day");
});

test("P2: Sunday per person, and never on a weekly-questionnaire push day",
    async () => {
      await reset(ALL_ON);
      // a: day 6 = Sunday 2026-10-25, no weekly push → P2.
      await seedUser("a", {arm: "A", cohort: sp.COHORT_RCT});
      // b: W0 a day earlier → Sunday is its study day 7 (W1 at 20:00).
      await seedUser("b", {arm: "B", cohort: sp.COHORT_RCT,
        w0Date: dayKey(-1)});
      const m = fakeMessaging();
      const c = await daily.runEveningPush(db, m, {now: hk(6, 19),
        log: silent, quiet: qh.quietHoursConfigFrom({})});
      assert.strictEqual(daily.hkWeekday(hk(6, 19)), 0);
      assert.deepStrictEqual(m.uids(), ["a"]);
      assert.strictEqual(c.weekly_push_day, 1);

      // b's W1 goes at 20:00 (the only push b gets that evening).
      m.clear();
      await dispatch(m, hk(6, 20));
      assert.deepStrictEqual(m.uids(), ["b"]);
      assert.deepStrictEqual(m.to("b"), [pc.TEXT.W1]);

      // Monday 19:00: a's W1 opens tonight (its day 7); b's W2 goes
      // tonight (its day 8, not done) → no P2 for either.
      m.clear();
      const mon = await daily.runEveningPush(db, m, {now: hk(7, 19),
        log: silent, quiet: qh.quietHoursConfigFrom({})});
      assert.strictEqual(m.sent.length, 0);
      assert.strictEqual(mon.weekly_push_day, 2);
      await dispatch(m, hk(7, 20));
      assert.deepStrictEqual(m.to("a"), [pc.TEXT.W1]);
      assert.deepStrictEqual(m.to("b"), [pc.TEXT.W2]);

      // Tuesday: b finished the questionnaire in the morning → no W3, so
      // P2 again; a is on its day 2, not done → W2 tonight, no P2.
      await complete("b", "W1", hk(8, 9));
      m.clear();
      await daily.runEveningPush(db, m, {now: hk(8, 19), log: silent,
        quiet: qh.quietHoursConfigFrom({})});
      assert.deepStrictEqual(m.uids(), ["b"]);
      assert.deepStrictEqual(m.to("b"), [pc.TEXT.P2]);
    });

// ---------------------------------------------------------------------------
// 4. Switch off: today's behaviour
// ---------------------------------------------------------------------------

test("check-in switch off: no 08:30 push; 19:00 is the old broadcast " +
    "Monday–Saturday and nothing on Sunday", async () => {
  await reset({weeklyReminderV2Enabled: true});
  await seedPeople();
  const m = fakeMessaging();
  const p1 = await daily.sendMorningPush(db, m, {now: hk(0, 8, 30),
    log: silent});
  assert.deepStrictEqual(p1, {enabled: false});
  let doorbell = 0;
  const bell = async () => {
    doorbell++;
  };
  // Monday (W0) … Saturday: the broadcast; Sunday: nothing.
  for (let day = 0; day < 6; day++) {
    const r = await daily.runEveningPush(db, m, {now: hk(day, 19),
      log: silent, legacyDoorbell: bell});
    assert.strictEqual(r.legacy, "broadcast");
  }
  const sun = await daily.runEveningPush(db, m, {now: hk(6, 19),
    log: silent, legacyDoorbell: bell});
  assert.strictEqual(sun.legacy, "sunday_none");
  assert.strictEqual(doorbell, 6);
  assert.strictEqual(m.sent.length, 0, "no per-person push");
});

// ---------------------------------------------------------------------------
// 5. Test e-mail and test push
// ---------------------------------------------------------------------------

test("console test e-mail: 【测试】 subject, three synthetic IDs, request " +
    "reset; works with the switch off", async () => {
  await reset(null);
  await seedPeople();
  const r = await email.handleTestRequest(db, null, {send: true},
      {now: hk(1, 15), smtp: SMTP, auth: null});
  assert.strictEqual(r, "sent");
  assert.strictEqual(mails.length, 1);
  assert.strictEqual(mails[0].subject, "【测试】" + pc.E1_SUBJECT);
  const rows = mails[0].text.split("\n").filter((l) => /^[A-Z]+-/.test(l));
  assert.deepStrictEqual(rows, [
    "PILOT-TEST01 ｜ 第 9 天 ｜ 第 1 周",
    "PB-TEST02 ｜ 第 16 天 ｜ 第 2 周",
    "RCT-TEST03 ｜ 第 29 天 ｜ 第 4 周",
  ]);
  assertNoForbidden(mails[0].text);
  const doc = (await db.doc(email.TEST_DOC).get()).data();
  assert.strictEqual(doc.send, false);
  assert.strictEqual(doc.lastResult, "sent");
  // The trigger's own write (send true → false) does nothing.
  assert.strictEqual(await email.handleTestRequest(db, {send: true},
      {send: false}, {smtp: SMTP}), null);
  assert.strictEqual(mails.length, 1);
});

test("sendTestPush: 每日心情提醒 sends P1 and 每週問卷提醒 sends W1 when " +
    "the switches are on; old texts when off; new kinds accepted",
async () => {
  await reset(null, null);
  await db.doc("users/tt").set({isTester: true}); // no tokens: no send
  const call = (kind) => fns.sendTestPush.run({auth: {uid: "tt"},
    data: {kind}});
  let out = await call("daily_mood_reminder");
  assert.strictEqual(out.copyId, undefined);
  out = await call("weekly_survey_reminder");
  assert.strictEqual(out.copyId, undefined);
  await db.doc("app_config/feature_flags").set(ALL_ON);
  out = await call("daily_mood_reminder");
  assert.strictEqual(out.copyId, "P1");
  out = await call("weekly_survey_reminder");
  assert.strictEqual(out.copyId, "W1");
  out = await call("weekly_w3_4");
  assert.strictEqual(out.copyId, "W3-4");
  await assert.rejects(call("nope"), /unknown kind/);
  const ev = (await db.collection("users/tt/events")
      .where("name", "==", "test_push_sent").get()).docs
      .map((d) => d.data().params.copyId || null).sort();
  assert.deepStrictEqual(ev, [null, null, "P1", "W1", "W3-4"].sort());
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
    console.log(`${failed} pushes_email_1020 emulator test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} pushes_email_1020 emulator tests passed`);
  process.exit(0);
})();
