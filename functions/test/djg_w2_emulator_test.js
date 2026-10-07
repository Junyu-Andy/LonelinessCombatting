/**
 * T18 — W2 DJG push / reminder / missed mark and server scoring
 * (functions/djg_w2.js) against the Firestore emulator, synthetic users
 * only, fake FCM sender.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/djg_w2_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const djg = require("../djg_w2");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const silent = () => {};

// W0 = 2026-10-01 (day 1).  hk(day, hour) = that enrolment day, HKT.
const W0 = "2026-10-01";
function hk(day, hour, minute) {
  const key = djg.addDays(W0, day - 1);
  const hh = String(hour).padStart(2, "0");
  const mm = String(minute || 0).padStart(2, "0");
  return new Date(`${key}T${hh}:${mm}:00+08:00`);
}
const FINAL_COPY = {push: "（測試）第 2 週問卷", reminder: "（測試）提醒"};

function fakeMessaging() {
  const sent = [];
  return {sent, send: async (msg) => {
    sent.push(msg);
    return `id-${sent.length}`;
  }};
}

async function reset(phaseB) {
  for (const p of ["users", "app_config"]) {
    await db.recursiveDelete(db.collection(p));
  }
  if (phaseB) await db.doc(djg.CONFIG_DOC).set(phaseB);
}

async function seedUser(uid, data) {
  await db.doc(`users/${uid}`).set(Object.assign(
      {createdAt: `${W0}T09:00:00.000`}, data));
  await db.doc(`users/${uid}/fcm_tokens/dev1`).set({token: `tok-${uid}`});
}

async function seedCohort() {
  await seedUser("ua", {arm: "A", cohort: "phase_b"});
  await seedUser("ub", {arm: "B", cohort: "phase_b"});
  await seedUser("upa", {arm: "A", cohort: "phase_a"});
  await seedUser("ut", {arm: "B", cohort: "phase_b", isTester: true});
}

const docOf = async (uid) =>
  (await db.doc(`users/${uid}/djg_responses/W2`).get());

const run = (messaging, now, copy) => djg.dispatchDjgW2(db, messaging,
    {now, log: silent, copy: copy === undefined ? FINAL_COPY : copy});

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("switch off (no app_config/phase_b): nothing happens", async () => {
  await reset(null);
  await seedCohort();
  const m = fakeMessaging();
  const counts = await run(m, hk(14, 10));
  assert.deepStrictEqual(counts, {enabled: false});
  assert.strictEqual(m.sent.length, 0);
  assert.strictEqual((await docOf("ua")).exists, false);
});

test("placeholder copy: nothing is sent", async () => {
  await reset({djgW2InAppEnabled: true});
  await seedCohort();
  const m = fakeMessaging();
  const counts = await run(m, hk(14, 10), {});
  assert.strictEqual(counts.blocked_placeholder, 2);
  assert.strictEqual(m.sent.length, 0);
  assert.strictEqual((await docOf("ua")).exists, false);
});

test("full timeline: day 13, 14, 15, 20, 21 — both arms identical",
    async () => {
      await reset({djgW2InAppEnabled: true});
      await seedCohort();
      const m = fakeMessaging();

      // Day 13: before the window.
      await run(m, hk(13, 10));
      assert.strictEqual(m.sent.length, 0);
      // Day 14 09:00: before the push hour.
      await run(m, hk(14, 9));
      assert.strictEqual(m.sent.length, 0);
      // Day 14 10:00: one push each to ua and ub only.
      const c14 = await run(m, hk(14, 10));
      assert.strictEqual(c14.pushed, 2);
      assert.deepStrictEqual(m.sent.map((s) => s.token).sort(),
          ["tok-ua", "tok-ub"]);
      const strip = (s) => JSON.stringify(Object.assign({}, s, {token: ""}));
      assert.strictEqual(strip(m.sent[0]), strip(m.sent[1]));
      assert.strictEqual(m.sent[0].notification.body, FINAL_COPY.push);
      assert.strictEqual(m.sent[0].data.kind, "djg_w2_push");
      const a = (await docOf("ua")).data();
      assert.strictEqual(a.status, "pending");
      assert.strictEqual(a.timepoint, "W2");
      assert.strictEqual(a.windowStartDate, "2026-10-14");
      assert.strictEqual(a.windowEndDate, "2026-10-20");
      assert.ok(a.pushSentAt);
      assert.strictEqual((await docOf("upa")).exists, false);
      assert.strictEqual((await docOf("ut")).exists, false);
      // Same day, next hour: no second push.
      await run(m, hk(14, 11));
      assert.strictEqual(m.sent.length, 2);

      // ub submits on day 14 evening (as the App would).
      await db.doc("users/ub/djg_responses/W2").set({
        status: "submitted", answers: {q1: "yes", q2: "yes", q3: "no",
          q4: "no", q5: "mostly", q6: "yes"},
        submittedAt: admin.firestore.Timestamp.fromDate(hk(14, 20)),
      }, {merge: true});

      // Day 15 09:00: < 24 h since the push.
      await run(m, hk(15, 9));
      assert.strictEqual(m.sent.length, 2);
      // Day 15 10:00: reminder for ua only (ub already submitted).
      const c15 = await run(m, hk(15, 10));
      assert.strictEqual(c15.reminded, 1);
      assert.strictEqual(m.sent.length, 3);
      assert.strictEqual(m.sent[2].token, "tok-ua");
      assert.strictEqual(m.sent[2].notification.body, FINAL_COPY.reminder);
      assert.ok((await docOf("ua")).get("reminderSentAt"));
      // Day 20: still open, no more pushes (one reminder only).
      await run(m, hk(20, 10));
      assert.strictEqual(m.sent.length, 3);
      assert.strictEqual((await docOf("ua")).get("status"), "pending");

      // Day 21: window closed → missed for ua, no push.
      const c21 = await run(m, hk(21, 10));
      assert.strictEqual(c21.missed, 1);
      assert.strictEqual(m.sent.length, 3);
      assert.strictEqual((await docOf("ua")).get("status"), "missed");
      assert.strictEqual((await docOf("ub")).get("status"), "submitted");
      // Missed is final: later runs leave it alone.
      await run(m, hk(22, 10));
      assert.strictEqual(m.sent.length, 3);
      const ev = await db.collection("users/ua/events")
          .where("name", "==", "djg_w2_missed").get();
      assert.strictEqual(ev.size, 1);
    });

test("in-progress at day 21 is also missed; answers kept", async () => {
  await reset({djgW2InAppEnabled: true});
  await seedUser("ua", {arm: "A", cohort: "phase_b"});
  await db.doc("users/ua/djg_responses/W2").set({status: "in_progress",
    answers: {q1: "yes"}, timepoint: "W2"});
  await run(fakeMessaging(), hk(21, 10));
  const d = (await docOf("ua")).data();
  assert.strictEqual(d.status, "missed");
  assert.deepStrictEqual(d.answers, {q1: "yes"});
});

test("window long gone when the switch is turned on: no missed mark",
    async () => {
      await reset({djgW2InAppEnabled: true});
      await seedUser("ua", {arm: "A", cohort: "phase_b"});
      const last = 20 + djg.MISSED_LOOKBACK_DAYS;
      await run(fakeMessaging(), hk(last + 1, 10));
      assert.strictEqual((await docOf("ua")).exists, false);
      await run(fakeMessaging(), hk(last, 10));
      assert.strictEqual((await docOf("ua")).get("status"), "missed");
    });

test("legacy randomised account (no cohort) counts as Phase B", async () => {
  await reset({djgW2InAppEnabled: true});
  await seedUser("ux", {arm: "B", armAssignmentMode: "randomise"});
  await seedUser("uy", {arm: "A", armAssignmentMode: "force_a"});
  const m = fakeMessaging();
  await run(m, hk(14, 10));
  assert.deepStrictEqual(m.sent.map((s) => s.token), ["tok-ux"]);
});

test("server scoring: in window, idempotent, late submission flagged",
    async () => {
      await reset({djgW2InAppEnabled: true});
      await seedUser("ua", {arm: "A", cohort: "phase_b"});
      const data = {status: "submitted", timepoint: "W2",
        answers: {q1: "yes", q2: "mostly", q3: "no", q4: "no",
          q5: "skipped", q6: "yes"},
        submittedAt: admin.firestore.Timestamp.fromDate(hk(16, 15))};
      await db.doc("users/ua/djg_responses/W2").set(data);
      const out = await djg.scoreSubmission(db, "ua", "W2", data,
          {now: hk(16, 15)});
      assert.deepStrictEqual(out.scores,
          {emotional: 2, social: null, total: null});
      const d = (await docOf("ua")).data();
      assert.deepStrictEqual(d.scores, out.scores);
      assert.strictEqual(d.outsideWindow, false);
      assert.strictEqual(d.scoringVersion, djg.SCORING_VERSION);
      assert.deepStrictEqual(d.answers, data.answers); // raw kept
      // The trigger fires again on its own write: no-op.
      assert.strictEqual(await djg.scoreSubmission(db, "ua", "W2", d), null);
      // Not submitted → nothing.
      assert.strictEqual(await djg.scoreSubmission(db, "ua", "W2",
          {status: "in_progress"}), null);
      // Late (day 22) → outsideWindow true.
      const late = Object.assign({}, data, {submittedAt:
        admin.firestore.Timestamp.fromDate(hk(22, 9))});
      const out2 = await djg.scoreSubmission(db, "ua", "W2", late);
      assert.strictEqual(out2.outsideWindow, true);
    });

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`ok - ${t.name}`);
    } catch (err) {
      failed++;
      console.error(`not ok - ${t.name}\n${err.stack}`);
    }
  }
  if (failed) {
    console.error(`${failed} djg W2 emulator test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} djg W2 emulator tests passed`);
  process.exit(0);
})();
