/**
 * Action Loop reminder delivery (functions/reminders.js) against the
 * Firestore emulator, with a fake FCM sender.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/reminders_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const reminders = require("../reminders");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();

// 2026-10-08 10:00 HKT.
const NOW = new Date("2026-10-08T02:00:00Z");
const silent = () => {};

function fakeMessaging({fail = () => false} = {}) {
  const sent = [];
  return {
    sent,
    send: async (msg) => {
      if (fail(msg.token)) {
        const e = new Error("boom");
        e.code = "messaging/internal-error";
        throw e;
      }
      sent.push(msg);
      return `id-${sent.length}`;
    },
  };
}

async function reset({enabled}) {
  for (const path of ["users", "app_config"]) {
    await db.recursiveDelete(db.collection(path));
  }
  if (enabled !== undefined) {
    await db.doc("app_config/reminders").set({m7FollowupPushEnabled: enabled});
  }
}

async function seedUser(uid, {arm = "A", tokens = ["tok1"], quiet} = {}) {
  const user = {arm};
  if (quiet) user.quietTodayActivatedAt = quiet;
  await db.doc(`users/${uid}`).set(user);
  for (const [i, token] of tokens.entries()) {
    await db.doc(`users/${uid}/fcm_tokens/d${i}`).set({token});
  }
}

async function seedReminder(uid, id, {fireAt, planId = "p1", outcome,
  planExists = true}) {
  if (planExists) {
    await db.doc(`users/${uid}/action_plans/${planId}`)
        .set({action: "去公園行下", outcome: outcome || null});
  }
  // Same shape as ReminderRequest.toMap() in the app.
  await db.doc(`users/${uid}/reminders/${id}`).set({
    kind: "m7_followup",
    fireAt,
    titleZh: "件事點呀？",
    titleEn: "How did it go?",
    bodyZh: "你之前計劃做：去公園行下。",
    bodyEn: "Your plan: 去公園行下.",
    linkedDocId: planId,
    delivered: false,
  });
}

const rem = async (uid, id) =>
  (await db.doc(`users/${uid}/reminders/${id}`).get()).data();

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("switch off (no config doc) → nothing is sent or touched", async () => {
  await reset({});
  await seedUser("u1");
  await seedReminder("u1", "r1", {fireAt: "2026-10-08T09:30:00.000"});
  const m = fakeMessaging();
  const r = await reminders.dispatchDueReminders(db, m,
      {now: NOW, log: silent});
  assert.strictEqual(r.enabled, false);
  assert.strictEqual(m.sent.length, 0);
  assert.strictEqual((await rem("u1", "r1")).dispatchStatus, undefined);
});

test("due reminder is sent once, to both arms, without the plan text",
    async () => {
      await reset({enabled: true});
      await seedUser("ua", {arm: "A"});
      await seedUser("ub", {arm: "B", tokens: ["t1", "t2"]});
      // Local HK time strings, as the app writes them.
      await seedReminder("ua", "r1", {fireAt: "2026-10-08T09:30:00.000"});
      await seedReminder("ub", "r1", {fireAt: "2026-10-08T09:59:00.000"});
      const m = fakeMessaging();
      const r = await reminders.dispatchDueReminders(db, m,
          {now: NOW, log: silent});
      assert.strictEqual(r.sent, 2);
      assert.strictEqual(m.sent.length, 3);
      for (const msg of m.sent) {
        assert.deepStrictEqual(msg.notification,
            {title: "陪住", body: "你今日有個小計劃，得閒打開睇下。"});
        assert.ok(!JSON.stringify(msg).includes("公園"));
        assert.strictEqual(msg.data.kind, "m7_followup");
      }
      const a = await rem("ua", "r1");
      assert.strictEqual(a.delivered, true);
      assert.strictEqual(a.dispatchStatus, "sent");
      const ev = await db.collection("users/ub/events").get();
      assert.strictEqual(ev.docs[0].get("name"), "m7_reminder_sent");
      assert.strictEqual(ev.docs[0].get("params").delivered, 2);
      // Second run: nothing new.
      const again = await reminders.dispatchDueReminders(db, m,
          {now: NOW, log: silent});
      assert.strictEqual(again.sent, undefined);
      assert.strictEqual(m.sent.length, 3);
    });

test("fireAt without offset is HK time: 10:30 HKT is not yet due",
    async () => {
      await reset({enabled: true});
      await seedUser("u1");
      // Read as UTC this would be 10:30Z, also future; the parse check
      // below pins the +08:00 reading.
      await seedReminder("u1", "r1", {fireAt: "2026-10-08T10:30:00.000"});
      const m = fakeMessaging();
      await reminders.dispatchDueReminders(db, m, {now: NOW, log: silent});
      assert.strictEqual(m.sent.length, 0);
      assert.strictEqual((await rem("u1", "r1")).delivered, false);
      assert.strictEqual(
          reminders.parseFireAt("2026-10-08T10:00:00.000").toISOString(),
          "2026-10-08T02:00:00.000Z");
    });

test("overdue ≤ 12 h (overnight) is sent; overdue > 12 h is skipped",
    async () => {
      await reset({enabled: true});
      await seedUser("u1");
      await seedReminder("u1", "r1", {fireAt: "2026-10-07T23:00:00.000"});
      await seedReminder("u1", "r2", {fireAt: "2026-10-07T21:30:00.000",
        planId: "p2"});
      const m = fakeMessaging();
      const r = await reminders.dispatchDueReminders(db, m,
          {now: NOW, log: silent});
      assert.strictEqual(r.sent, 1);
      assert.strictEqual(r.skipped_stale, 1);
      assert.strictEqual((await rem("u1", "r2")).dispatchStatus,
          "skipped_stale");
      assert.strictEqual((await rem("u1", "r2")).delivered, false);
    });

test("今日休息 today → skipped; followed-up or deleted plan → skipped",
    async () => {
      await reset({enabled: true});
      await seedUser("uq", {quiet: "2026-10-08T08:15:00.000"});
      await seedReminder("uq", "r1", {fireAt: "2026-10-08T09:00:00.000"});
      await seedUser("uf");
      await seedReminder("uf", "r1", {fireAt: "2026-10-08T09:00:00.000",
        outcome: "happened"});
      await seedUser("ud");
      await seedReminder("ud", "r1", {fireAt: "2026-10-08T09:00:00.000",
        planExists: false});
      await seedUser("uy", {quiet: "2026-10-07T08:15:00.000"});
      await seedReminder("uy", "r1", {fireAt: "2026-10-08T09:00:00.000"});
      const m = fakeMessaging();
      const r = await reminders.dispatchDueReminders(db, m,
          {now: NOW, log: silent});
      assert.strictEqual(r.skipped_quiet_today, 1);
      assert.strictEqual(r.skipped_followed_up, 1);
      assert.strictEqual(r.skipped_plan_missing, 1);
      assert.strictEqual(r.sent, 1); // uy: 今日休息 was yesterday
      assert.strictEqual(m.sent.length, 1);
    });

test("send failure retries on later runs, then gives up after 3", async () => {
  await reset({enabled: true});
  await seedUser("u1");
  await seedReminder("u1", "r1", {fireAt: "2026-10-08T09:30:00.000"});
  const m = fakeMessaging({fail: () => true});
  for (const status of ["retry", "retry", "failed"]) {
    await reminders.dispatchDueReminders(db, m, {now: NOW, log: silent});
    const d = await rem("u1", "r1");
    assert.strictEqual(d.dispatchStatus, status);
    assert.strictEqual(d.delivered, false);
  }
  assert.strictEqual((await rem("u1", "r1")).dispatchAttempts, 3);
  // Terminal: a fourth run does not try again.
  const r = await reminders.dispatchDueReminders(db, m,
      {now: NOW, log: silent});
  assert.strictEqual(r.failed, undefined);
});

test("transient failure then success on the next run", async () => {
  await reset({enabled: true});
  await seedUser("u1");
  await seedReminder("u1", "r1", {fireAt: "2026-10-08T09:30:00.000"});
  let down = true;
  const m = fakeMessaging({fail: () => down});
  await reminders.dispatchDueReminders(db, m, {now: NOW, log: silent});
  down = false;
  await reminders.dispatchDueReminders(db, m, {now: NOW, log: silent});
  const d = await rem("u1", "r1");
  assert.strictEqual(d.dispatchStatus, "sent");
  assert.strictEqual(d.dispatchAttempts, 2);
});

test("no device token → retried, then no_tokens", async () => {
  await reset({enabled: true});
  await seedUser("u1", {tokens: []});
  await seedReminder("u1", "r1", {fireAt: "2026-10-08T09:30:00.000"});
  const m = fakeMessaging();
  for (let i = 0; i < 3; i++) {
    await reminders.dispatchDueReminders(db, m, {now: NOW, log: silent});
  }
  assert.strictEqual((await rem("u1", "r1")).dispatchStatus, "no_tokens");
});

test("a reminder claimed as 'sending' by a crashed run is not resent",
    async () => {
      await reset({enabled: true});
      await seedUser("u1");
      await seedReminder("u1", "r1", {fireAt: "2026-10-08T09:30:00.000"});
      await db.doc("users/u1/reminders/r1")
          .update({dispatchStatus: "sending"});
      const m = fakeMessaging();
      await reminders.dispatchDueReminders(db, m, {now: NOW, log: silent});
      assert.strictEqual(m.sent.length, 0);
    });

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`  ✓ ${t.name}`);
    } catch (err) {
      failed++;
      console.error(`  ✗ ${t.name}\n    ${err.stack}`);
    }
  }
  console.log(failed ? `${failed} failed` : `${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();
