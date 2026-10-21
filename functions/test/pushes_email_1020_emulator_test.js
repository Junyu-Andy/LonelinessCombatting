/**
 * dev-tasks-1020 batch 4 (F(5), G(1)(3)) as changed by 1020e (一.(8),
 * 二.1–二.4) against the Firestore emulator, with a simulated clock,
 * synthetic accounts only, a fake FCM sender and a captured mailer (no
 * real push, no real e-mail):
 *
 *   1. weeks 1–3 (weeklyReminderV2Enabled): window day 7 00:00 → end of
 *      day 9; 10:00 pushes — preview day 6 and open day 7 to all, day 8 and
 *      day 9 only to those not done (three people done on day 7, 8, 9, one
 *      never); 第N週 follows the week; the day-9 10:00 e-mail lists only
 *      research ID, study day and week; outsideWindow and missed stamps;
 *   2. week 4: opens day 26 00:00, preview day 25, open day 26, reminder
 *      day 28 (not done), e-mail day 28; closes at the end of the day the
 *      assessor records W4 (users/{uid}.w4RecordedOn, written by
 *      assessor.submitEntry) — early, late, before opening, or never (end
 *      of day 42);
 *   3. P1 at 08:30 skips whoever already did today's check-in; P2 at 19:00
 *      on weekly push days too; a crisis-stopped chat check-in counts as
 *      done unless marked falseAlarm;
 *   4. switches off → today's behaviour (19:00 broadcast Mon–Sat only, no
 *      08:30, T24 weekly windows / copy / 24-hour reminder, no e-mail);
 *      (weeks 5–7, 10/20 item 98: pgic_whole_days_emulator_test.js)
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
const assessor = require("../assessor");

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
const KERAN = {uid: "keranAssessor000000000000001", email: ASSESSOR,
  role: "blinded"};
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
    "research_ids", "enrollments", "outcome_entries", "alert_audit_log",
    "meta"]) {
    await db.recursiveDelete(db.collection(p));
  }
  if (flags) await db.doc("app_config/feature_flags").set(flags);
  if (phaseB !== null) {
    // weeklyPushHour 20: the switch-off cases below were written for the
    // T24 path at 20:00 (default 10 since item 98); with reminders v2 on
    // the hour is not read.
    await db.doc(ws.CONFIG_DOC).set(phaseB ||
      {weeklyScheduleV2Enabled: true, weeklyPushHour: 20});
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
    await db.doc(`research_ids/${researchId}`).set({uid,
      via: "enrollment"});
    await db.doc(`enrollments/${uid}`).set({uid, researchId,
      studyPeriod: researchId.indexOf("PILOT-") === 0 ? "PILOT" : "B",
      w0Date: data.w0Date || W0});
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
  await seedUser("t1", {arm: "B", cohort: sp.COHORT_RCT, isTester: true});
  await seedUser("t2", {arm: "A", cohort: sp.COHORT_PILOT, isTester: true,
    armAssignedBy: "tester_switch"});
  await seedUser("x1", {arm: "B"});
}

// Every part of a bundle submitted (social probe off → DJG on W1–W3,
// Weekly PR, PGIC), then stamped as the triggers would.
async function complete(uid, bundleId, at) {
  const u = db.doc(`users/${uid}`);
  const when = ts(at);
  if (["W1", "W2", "W3"].indexOf(bundleId) >= 0) {
    await u.collection("djg_responses").doc(bundleId).set({
      timepoint: bundleId, bundle: bundleId, status: "submitted",
      submittedAt: when}, {merge: true});
    await stamp(uid, "djg_responses", bundleId, at);
  }
  await u.collection("weekly_pr").doc(bundleId).set({bundle: bundleId,
    status: "completed", respondedAt: when}, {merge: true});
  await stamp(uid, "weekly_pr", bundleId, at);
  await u.collection("pgic").doc(bundleId).set({bundle: bundleId, value: 6,
    answeredAt: when}, {merge: true});
  await stamp(uid, "pgic", bundleId, at);
}

async function stamp(uid, col, id, at) {
  const snap = await db.doc(`users/${uid}/${col}/${id}`).get();
  return ws.stampPartRecord(db, uid, col, id, snap.data(), {now: at});
}

const part = async (uid, col, id) =>
  (await db.doc(`users/${uid}/${col}/${id}`).get()).data();
const status = async (uid) =>
  ((await db.doc(`weekly_status/${uid}`).get()).data() || {}).bundles || {};

const dispatch = (m, now) => ws.dispatchWeeklyBundles(db, m,
    {now, log: silent, quiet: qh.quietHoursConfigFrom({})});
const runEmail = (now, extra) => email.sendDailyIncompleteEmail(db,
    Object.assign({now, smtp: SMTP, auth: null}, extra || {}));
const ALL_ON = {checkInChatV2Enabled: true, weeklyReminderV2Enabled: true,
  assessorViewEnabled: true};
const emailRows = (m) => m.text.split("\n").filter((l) => /^[A-Z]+-/.test(l));

// What E1 must never carry: arms, cohort labels, answers, uids.
function assertNoForbidden(text) {
  for (const bad of ["arm", "Arm", "Hybrid", "規則", "规则组", "组别：",
    sp.COHORT_RCT + "\"", sp.COHORT_RUN_IN, `${sp.COHORT_PILOT} `,
    "completed", "value", "r1", "r2", "r3", "r4", "t1", "t2", "x1"]) {
    assert.ok(text.indexOf(bad) < 0, `e-mail must not contain ${bad}`);
  }
}

// The assessor records one W4 paper instrument at `at` (assessor.js).
async function recordW4(researchId, at) {
  return assessor.submitEntry(db, KERAN, {researchId, instrument: "DJG-ES",
    timepoint: "W4", assessmentDate: sw.hkDateKey(at), mode: "in_person",
    answers: {q1: "yes", q2: "mostly", q3: "no", q4: "yes", q5: "mostly",
      q6: "no"}, confirmed: true}, {now: at});
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

// ---------------------------------------------------------------------------
// 1. Weeks 1–3
// ---------------------------------------------------------------------------

test("weeks 1–3: preview day 6 and open day 7 to all at 10:00; day 8 / " +
    "day 9 only to those not done (done on day 7, 8, 9, never); both " +
    "arms, all three prefixes alike", async () => {
  await reset(ALL_ON);
  await seedPeople();
  const m = fakeMessaging();
  const everyone = ["r1", "r2", "r3", "r4", "t2"];
  const wk1 = (id) => pc.weeklyText(id, 1);

  // Day 5: nothing.  Day 6: nothing before 10:00, then the preview.
  await dispatch(m, hk(5, 10));
  await dispatch(m, hk(6, 9));
  assert.strictEqual(m.sent.length, 0);
  const c6 = await dispatch(m, hk(6, 10));
  assert.strictEqual(c6.reminderV2, true);
  assert.strictEqual(c6.previewed, 5);
  assert.deepStrictEqual(m.uids(), everyone);
  for (const uid of everyone) {
    assert.deepStrictEqual(m.to(uid), ["聽日第一週問卷就開，記得聽日得閒入嚟答呀。"]);
  }
  m.clear();
  await dispatch(m, hk(6, 11));
  await dispatch(m, hk(6, 20));
  assert.strictEqual(m.sent.length, 0, "preview once; nothing at 20:00");

  // Day 7 (window open since 00:00): nothing before 10:00, then W-open.
  await dispatch(m, hk(7, 9));
  assert.strictEqual(m.sent.length, 0);
  await dispatch(m, hk(7, 10));
  assert.deepStrictEqual(m.uids(), everyone);
  assert.deepStrictEqual(m.to("r1"), [wk1("W-open")]);
  assert.deepStrictEqual(m.to("r1"), ["第一週問卷開咗，快啲入嚟答啦。"]);
  const st1 = (await status("r1")).W1;
  assert.strictEqual(st1.pushCopyId, "W-open");
  assert.ok(st1.previewSentAt && st1.pushedAt);
  assert.strictEqual(st1.windowStart.toDate().toISOString(),
      hk(7, 0).toISOString());
  assert.strictEqual(st1.windowEnd.toDate().toISOString(),
      hk(10, 0).toISOString());
  m.clear();
  await dispatch(m, hk(7, 20));
  assert.strictEqual(m.sent.length, 0, "no 20:00 push any more");

  // r1 completes on the first day (day 7).
  await complete("r1", "W1", hk(7, 11));
  // Day 8: reminder 1 to the four not done.
  await dispatch(m, hk(8, 9));
  assert.strictEqual(m.sent.length, 0);
  await dispatch(m, hk(8, 10));
  assert.deepStrictEqual(m.uids(), ["r2", "r3", "r4", "t2"]);
  assert.deepStrictEqual(m.to("r2"),
      ["第一週問卷聽日截止，開咗一日喇，得閒入嚟答埋佢。"]);
  m.clear();
  await dispatch(m, hk(8, 21));
  assert.strictEqual(m.sent.length, 0, "reminder 1 once only");

  // r2 completes on the second day; r3 does the DJG only.
  await complete("r2", "W1", hk(8, 15));
  await db.doc("users/r3/djg_responses/W1").set({timepoint: "W1",
    bundle: "W1", status: "submitted", submittedAt: ts(hk(8, 16))});
  await stamp("r3", "djg_responses", "W1", hk(8, 16));

  // Day 9, 10:00: the e-mail lists r3 and r4 only (testers never).
  const e = await runEmail(hk(9, 10));
  assert.strictEqual(e.status, "sent");
  assert.strictEqual(e.count, 2);
  assert.strictEqual(mails.length, 1);
  assert.strictEqual(mails[0].subject, pc.E1_SUBJECT);
  assert.strictEqual(mails[0].to, PRIMARY);
  assert.deepStrictEqual(emailRows(mails[0]), [
    "PILOT-03 ｜ 第 9 天 ｜ 第 1 周",
    "RCT-04 ｜ 第 9 天 ｜ 第 1 周",
  ]);
  assertNoForbidden(mails[0].text);
  assert.strictEqual((await runEmail(hk(9, 10, 5))).status, "already_done");
  assert.strictEqual(mails.length, 1);
  // Reminder 2 at 10:00 to r3, r4, t2.
  m.clear();
  await dispatch(m, hk(9, 10));
  assert.deepStrictEqual(m.uids(), ["r3", "r4", "t2"]);
  assert.deepStrictEqual(m.to("r4"),
      ["今日係第一週問卷最後一日，記得今日一定要答埋佢。"]);
  // r3 completes on the third day.
  await complete("r3", "W1", hk(9, 15));

  // r4: Weekly PR at 23:30 on day 9 (inside), PGIC synced after midnight
  // (outside); the DJG never.
  await db.doc("users/r4/weekly_pr/W1").set({bundle: "W1",
    status: "completed", respondedAt: ts(hk(9, 23, 30))});
  await stamp("r4", "weekly_pr", "W1", hk(9, 23, 31));
  await db.doc("users/r4/pgic/W1").set({bundle: "W1", value: 3,
    answeredAt: ts(hk(10, 0, 30))});
  await stamp("r4", "pgic", "W1", hk(10, 0, 31));
  assert.strictEqual((await part("r4", "weekly_pr", "W1")).outsideWindow,
      false);
  assert.strictEqual((await part("r4", "pgic", "W1")).outsideWindow, true);
  assert.strictEqual((await part("r1", "pgic", "W1")).outsideWindow, false);
  assert.strictEqual((await part("r1", "pgic", "W1")).submittedStudyDay, 7);
  // r3's DJG was stamped in progress? No: submitted on day 8 → false.
  assert.strictEqual((await part("r3", "djg_responses", "W1")).outsideWindow,
      false);

  // Day 10, 08:00: the window closed at the end of day 9 → missed marks
  // for what is still open (r4's DJG, everything of t2).
  m.clear();
  await dispatch(m, hk(10, 8));
  assert.strictEqual(m.sent.length, 0);
  const missed = await part("r4", "djg_responses", "W1");
  assert.strictEqual(missed.status, "missed");
  assert.strictEqual(missed.missed, true);
  assert.strictEqual(missed.outsideWindow, null);
  assert.strictEqual(missed.windowEnd.toDate().toISOString(),
      hk(10, 0).toISOString());
  assert.strictEqual((await part("r4", "pgic", "W1")).value, 3,
      "a late submission is kept, not overwritten as missed");
  assert.deepStrictEqual((await status("r4")).W1.missedParts, ["djg"]);
  assert.strictEqual((await status("r1")).W1.missedParts.length, 0);

  // Week 2: the same, with 第二週.
  m.clear();
  await dispatch(m, hk(13, 10));
  assert.deepStrictEqual(m.to("r1"), ["聽日第二週問卷就開，記得聽日得閒入嚟答呀。"]);
});

test("in-progress record stamped first gets its outsideWindow on submit",
    async () => {
      await reset(ALL_ON);
      await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
      const ref = db.doc("users/r1/social_contact_probes/W2");
      await ref.set({bundle: "W2", status: "in_progress", answers: {q1: 1}});
      const first = await stamp("r1", "social_contact_probes", "W2",
          hk(14, 9));
      assert.strictEqual(first.outsideWindow, null);
      assert.strictEqual(first.submittedStudyDay, null);
      assert.strictEqual(await stamp("r1", "social_contact_probes", "W2",
          hk(14, 9, 1)), null, "nothing to add yet");
      await ref.set({status: "submitted", answers: {q1: 1, q2: 2},
        submittedAt: ts(hk(16, 23))}, {merge: true});
      const late = await stamp("r1", "social_contact_probes", "W2",
          hk(16, 23, 1));
      assert.strictEqual(late.outsideWindow, false);
      assert.strictEqual(late.submittedStudyDay, 16);
      assert.strictEqual(await stamp("r1", "social_contact_probes", "W2",
          hk(16, 23, 2)), null, "once");
    });

test("e-mail: nobody incomplete → none; blinded primary → nobody; switch " +
    "off → nothing", async () => {
  await reset(ALL_ON);
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  await complete("r1", "W1", hk(7, 21));
  assert.strictEqual((await runEmail(hk(9, 10))).status, "none");
  assert.strictEqual(mails.length, 0);

  await reset(ALL_ON);
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  await db.doc("meta/alert_config").set({enabled: true,
    primaryEmail: ASSESSOR});
  assert.strictEqual((await runEmail(hk(9, 10))).status, "no_recipients");
  assert.strictEqual(mails.length, 0);
  assert.strictEqual((await db.collection("alert_audit_log")
      .where("type", "==", "recipient_dropped").get()).size, 1);

  await reset({checkInChatV2Enabled: true});
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  assert.strictEqual((await runEmail(hk(9, 10))).status, "disabled");
  assert.strictEqual(mails.length, 0);
});

// ---------------------------------------------------------------------------
// 2. Week 4
// ---------------------------------------------------------------------------

test("week 4: preview 25, open 26, reminder 28, e-mail 28; closes when " +
    "the assessor records W4 (before opening, early, late) or at the end " +
    "of day 42", async () => {
  await reset(ALL_ON);
  // n: never recorded; e: recorded day 27; l: recorded day 31; b: recorded
  // day 25, before W4 opens.
  await seedUser("n", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-11");
  await seedUser("e", {arm: "B", cohort: sp.COHORT_RCT}, "RCT-12");
  await seedUser("l", {arm: "A", cohort: sp.COHORT_RUN_IN}, "PB-13");
  await seedUser("b", {arm: "B", cohort: sp.COHORT_PILOT,
    armAssignmentMode: sp.PILOT_MODE}, "PILOT-14");
  for (const uid of ["n", "e", "l", "b"]) {
    for (const id of ["W1", "W2", "W3"]) await complete(uid, id, hk(7, 21));
  }
  const m = fakeMessaging();

  // Day 25: b's visit is recorded in the morning; previews at 10:00.
  await recordW4("PILOT-14", hk(25, 9));
  assert.strictEqual((await db.doc("users/b").get()).get("w4RecordedOn"),
      dayKey(25));
  await dispatch(m, hk(25, 10));
  assert.deepStrictEqual(m.uids(), ["b", "e", "l", "n"]);
  assert.deepStrictEqual(m.to("n"),
      ["聽日第四週問卷就開，記得聽日得閒入嚟答呀。"]);
  m.clear();

  // Day 26: open push to all four (b's window still has day 26).
  await dispatch(m, hk(26, 10));
  assert.deepStrictEqual(m.uids(), ["b", "e", "l", "n"]);
  assert.deepStrictEqual(m.to("e"), ["第四週嘅問卷開咗，記得喺見面之前答埋佢。"]);
  assert.strictEqual((await status("b")).W4.windowEnd.toDate().toISOString(),
      hk(27, 0).toISOString());
  assert.strictEqual((await status("n")).W4.windowEnd.toDate().toISOString(),
      hk(43, 0).toISOString());
  m.clear();

  // Day 27: b closed at the end of day 26 → missed.  e's visit recorded
  // at 11:00 (a second instrument later the same day changes nothing).
  await dispatch(m, hk(27, 8));
  assert.strictEqual((await part("b", "pgic", "W4")).status, "missed");
  await recordW4("RCT-12", hk(27, 11));
  assert.strictEqual((await db.doc("users/e").get()).get("w4RecordedOn"),
      dayKey(27));
  // A second W4 instrument entered on day 29 does not move it.
  await assessor.submitEntry(db, KERAN, {researchId: "RCT-12",
    instrument: "PHQ-9", timepoint: "W4", assessmentDate: dayKey(27),
    mode: "in_person", answers: {q1: 0, q2: 0, q3: 0, q4: 0, q5: 0, q6: 0,
      q7: 0, q8: 0, q9: 0}, confirmed: true}, {now: hk(29, 9)});
  assert.strictEqual((await db.doc("users/e").get()).get("w4RecordedOn"),
      dayKey(27));
  // e answers the PGIC at 20:00 on day 27 — still inside.
  await db.doc("users/e/pgic/W4").set({bundle: "W4", value: 5,
    answeredAt: ts(hk(27, 20))});
  await stamp("e", "pgic", "W4", hk(27, 20, 1));
  assert.strictEqual((await part("e", "pgic", "W4")).outsideWindow, false);

  // Day 28: e closed at the end of day 27 → missed Weekly PR; 10:00
  // e-mail lists n and l; reminder to n and l only.
  await dispatch(m, hk(28, 8));
  assert.strictEqual((await part("e", "weekly_pr", "W4")).status, "missed");
  assert.strictEqual((await part("e", "pgic", "W4")).value, 5);
  await runEmail(hk(28, 10));
  assert.strictEqual(mails.length, 1);
  assert.deepStrictEqual(emailRows(mails[0]), [
    "PB-13 ｜ 第 28 天 ｜ 第 4 周",
    "RCT-11 ｜ 第 28 天 ｜ 第 4 周",
  ]);
  await dispatch(m, hk(28, 10));
  assert.deepStrictEqual(m.uids(), ["l", "n"]);
  assert.deepStrictEqual(m.to("l"),
      ["第四週嘅問卷仲未答完，得閒入嚟答埋佢；見面嗰日都可以補。"]);
  m.clear();

  // Days 29–30: no more week-4 pushes.  l's visit recorded on day 31; l
  // can still answer that day ("見面嗰日都可以補").
  for (const d of [29, 30]) await dispatch(m, hk(d, 10));
  assert.strictEqual(m.sent.length, 0);
  await recordW4("PB-13", hk(31, 10));
  await db.doc("users/l/weekly_pr/W4").set({bundle: "W4",
    status: "completed", respondedAt: ts(hk(31, 21))});
  await stamp("l", "weekly_pr", "W4", hk(31, 21, 1));
  assert.strictEqual((await part("l", "weekly_pr", "W4")).outsideWindow,
      false);
  await dispatch(m, hk(32, 8));
  assert.strictEqual((await part("l", "pgic", "W4")).status, "missed");
  assert.strictEqual((await status("l")).W4.windowEnd.toDate().toISOString(),
      hk(32, 0).toISOString());

  // n: never recorded → open to the end of day 42, missed on day 43.
  await dispatch(m, hk(42, 8));
  assert.strictEqual((await part("n", "pgic", "W4")), undefined);
  await dispatch(m, hk(43, 8));
  assert.strictEqual((await part("n", "pgic", "W4")).status, "missed");
  assert.strictEqual((await part("n", "pgic", "W4")).windowEnd.toDate()
      .toISOString(), hk(43, 0).toISOString());
  // The e-mail never listed b or e.
  assert.ok(mails.every((x) => x.text.indexOf("RCT-12") < 0 &&
    x.text.indexOf("PILOT-14") < 0));
});

test("w4RecordedOn is written whatever the switch; with it off the W4 " +
    "window is T24's (day 26 20:00 → end of day 29)", async () => {
  await reset({assessorViewEnabled: true});
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  await recordW4("RCT-01", hk(27, 11));
  assert.strictEqual((await db.doc("users/r1").get()).get("w4RecordedOn"),
      dayKey(27));
  const m = fakeMessaging();
  await dispatch(m, hk(26, 10));
  assert.strictEqual(m.sent.length, 0, "no 10:00 push with the switch off");
  await dispatch(m, hk(26, 20));
  assert.deepStrictEqual(m.to("r1"), [ws.PUSH_BODY]);
  await dispatch(m, hk(29, 21));
  assert.strictEqual((await part("r1", "pgic", "W4")), undefined,
      "still open on day 29");
  await dispatch(m, hk(30, 8));
  assert.strictEqual((await part("r1", "pgic", "W4")).status, "missed");
  assert.strictEqual("outsideWindow" in (await part("r1", "pgic", "W4")),
      false);
});

// Weeks 5–7 (PGIC only): since 10/20 item 98 whole days like weeks 1–3 —
// functions/test/pgic_whole_days_emulator_test.js.

test("weekly switch off: exactly T24 (20:00 S14, 24-hour reminder, " +
    "72-hour window, no preview, no e-mail)", async () => {
  await reset({checkInChatV2Enabled: true});
  await seedUser("r1", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-01");
  const m = fakeMessaging();
  await dispatch(m, hk(6, 10));
  await dispatch(m, hk(7, 10));
  assert.strictEqual(m.sent.length, 0);
  const c = await dispatch(m, hk(7, 20));
  assert.strictEqual(c.reminderV2, undefined);
  assert.deepStrictEqual(m.to("r1"), [ws.PUSH_BODY]);
  const ev = (await db.collection("users/r1/events")
      .where("name", "==", "weekly_bundle_push_sent").get()).docs[0].data();
  assert.strictEqual(ev.params.copyId, undefined);
  m.clear();
  await dispatch(m, hk(8, 20));
  assert.deepStrictEqual(m.to("r1"), [ws.REMINDER_BODY]);
  await dispatch(m, hk(10, 8));
  assert.strictEqual((await part("r1", "pgic", "W1")), undefined,
      "still open on day 10 morning");
  await dispatch(m, hk(10, 20));
  const missed = await part("r1", "pgic", "W1");
  assert.strictEqual(missed.status, "missed");
  assert.strictEqual("outsideWindow" in missed, false);
  assert.strictEqual((await runEmail(hk(9, 10))).status, "disabled");
});

// ---------------------------------------------------------------------------
// 3. P1 and P2
// ---------------------------------------------------------------------------

test("P1 08:30: registered participants, both arms, per person; not " +
    "testers or unregistered; skips whoever already did today's check-in; " +
    "once a day; quiet hours respected", async () => {
  await reset(ALL_ON);
  await seedPeople();
  // r2 (rule arm) did the old form at 07:50; r3 the chat at 08:10; r4 is
  // only known by the check_in_submitted event.
  await db.collection("users/r2/check_in_responses").add({arm: "B", mood: 4,
    date_iso: dayKey(3), note: ""});
  await db.collection("users/r3/check_in_responses").add({arm: "A",
    flow: "chat_v2", date_iso: dayKey(3), completed: true});
  await db.collection("users/r4/events").add({name: "check_in_submitted",
    params: {mood: 3}, timestamp: ts(hk(3, 8, 5))});
  const m = fakeMessaging();
  const quiet = qh.quietHoursConfigFrom({});
  const c = await daily.sendMorningPush(db, m,
      {now: hk(3, 8, 30), log: silent, quiet});
  assert.strictEqual(c.pushed, 2);
  assert.strictEqual(c.done_form_v1, 1);
  assert.strictEqual(c.done_chat_v2, 1);
  assert.strictEqual(c.done_event, 1);
  assert.deepStrictEqual(m.uids(), ["r1", "t2"]);
  assert.deepStrictEqual(m.to("r1"), [pc.TEXT.P1]);
  assert.ok(m.sent.every((x) => x.notification.title === "陪住"));
  assert.ok(m.sent.every((x) => !x.topic), "never a topic broadcast");
  m.clear();
  const again = await daily.sendMorningPush(db, m,
      {now: hk(3, 8, 31), log: silent, quiet});
  assert.strictEqual(again.already_sent, 2);
  assert.strictEqual(m.sent.length, 0);
  // Next day nobody has checked in yet → all five (both arms).
  await daily.sendMorningPush(db, m, {now: hk(4, 8, 30), log: silent, quiet});
  assert.deepStrictEqual(m.uids(), ["r1", "r2", "r3", "r4", "t2"]);
  m.clear();
  const late = qh.quietHoursConfigFrom({quietHoursStart: "22:00",
    quietHoursEnd: "09:00"});
  const q = await daily.sendMorningPush(db, m,
      {now: hk(5, 8, 30), log: silent, quiet: late});
  assert.strictEqual(q.quiet_hours, 5);
  assert.strictEqual(m.sent.length, 0);
});

test("P2 19:00: only to those who have not done today's check-in (old " +
    "form, chat_v2, event; Hong Kong date); crisis-stopped counts as done " +
    "unless falseAlarm", async () => {
  await reset(ALL_ON);
  const today = dayKey(3);
  const yesterday = dayKey(2);
  const people = {
    // done today
    v2done: {arm: "A"}, formDone: {arm: "B"}, eventDone: {arm: "A"},
    safetyStop: {arm: "B"},
    // not done today
    v2open: {arm: "A"}, formYesterday: {arm: "B"}, nothing: {arm: "B"},
    eventLateYesterday: {arm: "A"}, falseAlarm: {arm: "B"},
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
  await db.collection("users/eventLateYesterday/events").add({
    name: "check_in_submitted", params: {mood: 3},
    timestamp: ts(hk(2, 23, 30))});
  // Marked a false alarm by the research lead (batch 2's action).
  await rows("falseAlarm").add({arm: "B", flow: "chat_v2", date_iso: today,
    completed: false, stopped_by_safety: true, falseAlarm: true,
    markedBy: "junyuUid", markedAt: ts(hk(3, 12))});

  const m = fakeMessaging();
  let doorbell = 0;
  const c = await daily.runEveningPush(db, m, {now: hk(3, 19), log: silent,
    quiet: qh.quietHoursConfigFrom({}), legacyDoorbell: async () => {
      doorbell++;
    }});
  assert.strictEqual(doorbell, 0, "no broadcast with the switch on");
  assert.deepStrictEqual(m.uids(), ["eventLateYesterday", "falseAlarm",
    "formYesterday", "nothing", "v2open"]);
  assert.deepStrictEqual(m.to("falseAlarm"), [pc.TEXT.P2]);
  assert.strictEqual(c.done_chat_v2, 2);
  assert.strictEqual(c.done_form_v1, 1);
  assert.strictEqual(c.done_event, 1);
  m.clear();
  await daily.runEveningPush(db, m, {now: hk(3, 19, 1), log: silent,
    quiet: qh.quietHoursConfigFrom({})});
  assert.strictEqual(m.sent.length, 0, "once a day");
});

test("P2 also on weekly-questionnaire push days and on Sunday", async () => {
  await reset(ALL_ON);
  await seedUser("a", {arm: "A", cohort: sp.COHORT_RCT});
  await seedUser("b", {arm: "B", cohort: sp.COHORT_RCT});
  const m = fakeMessaging();
  // Day 6 = Sunday 2026-10-25, the preview day: 10:00 preview, 19:00 P2.
  assert.strictEqual(daily.hkWeekday(hk(6, 19)), 0);
  await dispatch(m, hk(6, 10));
  m.clear();
  await daily.runEveningPush(db, m, {now: hk(6, 19), log: silent,
    quiet: qh.quietHoursConfigFrom({})});
  assert.deepStrictEqual(m.uids(), ["a", "b"]);
  // Day 7 (opening) and day 8 (reminder): P2 still goes.
  for (const d of [7, 8]) {
    await dispatch(m, hk(d, 10));
    m.clear();
    await daily.runEveningPush(db, m, {now: hk(d, 19), log: silent,
      quiet: qh.quietHoursConfigFrom({})});
    assert.deepStrictEqual(m.uids(), ["a", "b"], `day ${d}`);
    assert.deepStrictEqual(m.to("b"), [pc.TEXT.P2]);
  }
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
  assert.deepStrictEqual(emailRows(mails[0]), [
    "PILOT-TEST01 ｜ 第 9 天 ｜ 第 1 周",
    "PB-TEST02 ｜ 第 16 天 ｜ 第 2 周",
    "RCT-TEST03 ｜ 第 28 天 ｜ 第 4 周",
  ]);
  assertNoForbidden(mails[0].text);
  const doc = (await db.doc(email.TEST_DOC).get()).data();
  assert.strictEqual(doc.send, false);
  assert.strictEqual(doc.lastResult, "sent");
  assert.strictEqual(await email.handleTestRequest(db, {send: true},
      {send: false}, {smtp: SMTP}), null);
  assert.strictEqual(mails.length, 1);
});

test("sendTestPush: old buttons map to P1 / the week-1 opening push when " +
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
  assert.strictEqual(out.copyId, "W-open");
  out = await call("weekly4_rem");
  assert.strictEqual(out.copyId, "W4-rem");
  out = await call("checkin_p2");
  assert.strictEqual(out.copyId, "P2");
  await assert.rejects(call("nope"), /unknown kind/);
  const ev = (await db.collection("users/tt/events")
      .where("name", "==", "test_push_sent").get()).docs
      .map((d) => d.data().params.copyId || null).sort();
  assert.deepStrictEqual(ev, [null, null, "P1", "P2", "W-open", "W4-rem"]
      .sort());
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
