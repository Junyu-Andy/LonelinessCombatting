/**
 * 1020o 第三节 (decision 0066) — the elder's own 安靜時段, end to end on the
 * Firestore emulator with a fake FCM sender.  Synthetic accounts only:
 *   qh   users/{uid}.quietHoursStart "20:00", quietHoursEnd "06:00"
 *   def  no own values (the global window, default 22:00–08:00)
 * Checks: the 19:00 plan reminder and P2 still go to qh; a plan reminder
 * at 20:30 waits until 06:00 for qh (and goes at once for def); P1 at
 * 08:30 reaches both; the 小篇章 push follows qh's window; def behaves
 * exactly as before (held 22:00–08:00).
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/quiet_hours_1020o_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();

const reminders = require("../reminders");
const daily = require("../daily_checkin_push");
const chapter = require("../reminiscence_chapter");

const silent = () => {};
// Hong Kong wall clock on 2026-10-21 (day 22 = the next morning).
const hk = (h, m, day) => new Date(
    `2026-10-${day || 21}T${String(h).padStart(2, "0")}:` +
    `${String(m || 0).padStart(2, "0")}:00+08:00`);

function fakeMessaging() {
  const sent = [];
  return {
    sent,
    send: async (msg) => {
      sent.push(msg);
      return `id-${sent.length}`;
    },
    to: (uid) => sent.filter((m) => m.token === `tok-${uid}`),
    clear: () => {
      sent.length = 0;
    },
  };
}

async function reset() {
  for (const p of ["users", "app_config"]) {
    await db.recursiveDelete(db.collection(p));
  }
  // The global window is not set: the default 22:00–08:00.
  await db.doc("app_config/reminders").set({m7FollowupPushEnabled: true});
}

async function seedUser(uid, extra) {
  await db.doc(`users/${uid}`).set(Object.assign(
      {arm: uid === "qh" ? "A" : "B", cohort: "rct", w0Date: "2026-10-19"},
      extra || {}));
  await db.doc(`users/${uid}/fcm_tokens/dev1`).set({token: `tok-${uid}`});
}

async function seedReminder(uid, id, fireAt) {
  await db.doc(`users/${uid}/action_plans/p_${id}`)
      .set({action: "去公園行下", outcome: null});
  await db.doc(`users/${uid}/reminders/${id}`).set({
    kind: "m7_followup", fireAt, linkedDocId: `p_${id}`, delivered: false,
    titleZh: "件事點呀？", bodyZh: "你之前計劃做：去公園行下。",
  });
}

const rem = async (uid, id) =>
  (await db.doc(`users/${uid}/reminders/${id}`).get()).data();

const dispatchAt = (m, at) =>
  reminders.dispatchDueReminders(db, m, {now: at, log: silent});

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("plan reminders: 19:00 sent; 20:30 held until 06:00 for 20:00–06:00; " +
    "the default account exactly as before", async () => {
  await reset();
  await seedUser("qh", {quietHoursStart: "20:00", quietHoursEnd: "06:00"});
  await seedUser("def");
  for (const uid of ["qh", "def"]) {
    await seedReminder(uid, "r1900", "2026-10-21T19:00:00.000");
    await seedReminder(uid, "r2030", "2026-10-21T20:30:00.000");
    await seedReminder(uid, "r2215", "2026-10-21T22:15:00.000");
  }
  const m = fakeMessaging();

  await dispatchAt(m, hk(19, 0));
  assert.strictEqual(m.to("qh").length, 1, "19:00 is outside 20:00–06:00");
  assert.strictEqual((await rem("qh", "r1900")).dispatchStatus, "sent");
  assert.strictEqual((await rem("def", "r1900")).dispatchStatus, "sent");

  m.clear();
  await dispatchAt(m, hk(20, 30));
  assert.strictEqual(m.to("qh").length, 0, "20:30 is inside 20:00–06:00");
  const held = await rem("qh", "r2030");
  assert.strictEqual(held.delivered, false);
  assert.strictEqual(held.dispatchStatus, undefined, "left for later");
  assert.strictEqual(m.to("def").length, 1, "default: 20:30 goes out");
  assert.strictEqual((await rem("def", "r2030")).dispatchStatus, "sent");

  // The rest of the night: nothing for either (22:15 is in both windows).
  for (const at of [hk(22, 15), hk(22, 45), hk(5, 45, 22)]) {
    m.clear();
    await dispatchAt(m, at);
    assert.strictEqual(m.sent.length, 0, at.toISOString());
  }
  assert.strictEqual((await rem("qh", "r2030")).dispatchStatus, undefined);

  // 06:00: qh's window has ended — both of its held reminders go; the
  // default account still waits (its window ends at 08:00).
  m.clear();
  await dispatchAt(m, hk(6, 0, 22));
  assert.strictEqual(m.to("qh").length, 2);
  assert.strictEqual((await rem("qh", "r2030")).dispatchStatus, "sent");
  assert.strictEqual((await rem("qh", "r2215")).dispatchStatus, "sent");
  assert.strictEqual(m.to("def").length, 0);
  assert.strictEqual((await rem("def", "r2215")).dispatchStatus, undefined);

  m.clear();
  await dispatchAt(m, hk(7, 45, 22));
  assert.strictEqual(m.to("def").length, 0, "default: still quiet at 07:45");
  m.clear();
  await dispatchAt(m, hk(8, 0, 22));
  assert.strictEqual(m.to("def").length, 1, "default: 08:00 as before");
  assert.strictEqual((await rem("def", "r2215")).dispatchStatus, "sent");
});

test("a 20:00–08:00 window: a reminder at 20:00 is still sent at 08:00 " +
    "(its age counts from the end of the window)", async () => {
  await reset();
  await seedUser("qh", {quietHoursStart: "20:00", quietHoursEnd: "08:00"});
  await seedReminder("qh", "r2000", "2026-10-21T20:00:00.000");
  const m = fakeMessaging();
  await dispatchAt(m, hk(20, 0));
  assert.strictEqual(m.sent.length, 0);
  await dispatchAt(m, new Date(hk(8, 0, 22).getTime() + 30 * 1000));
  assert.strictEqual(m.to("qh").length, 1);
  assert.strictEqual((await rem("qh", "r2000")).dispatchStatus, "sent");
});

test("P2 at 19:00 and P1 at 08:30 reach the 20:00–06:00 account", async () => {
  await reset();
  await seedUser("qh", {quietHoursStart: "20:00", quietHoursEnd: "06:00"});
  await seedUser("def");
  const m = fakeMessaging();
  const p2 = await daily.runEveningPush(db, m,
      {now: hk(19, 0), log: silent, flagOn: true});
  assert.strictEqual(p2.pushed, 2, JSON.stringify(p2));
  assert.strictEqual(p2.quiet_hours, undefined);
  m.clear();
  const p1 = await daily.sendMorningPush(db, m,
      {now: hk(8, 30, 22), log: silent, flagOn: true});
  assert.strictEqual(p1.pushed, 2, JSON.stringify(p1));
  // A P2 run inside qh's window (not a real slot) is held for qh only.
  m.clear();
  await db.recursiveDelete(db.collection("users").doc("qh")
      .collection("events"));
  await db.recursiveDelete(db.collection("users").doc("def")
      .collection("events"));
  const late = await daily.runEveningPush(db, m,
      {now: hk(21, 0), log: silent, flagOn: true});
  assert.strictEqual(late.quiet_hours, 1);
  assert.strictEqual(m.to("def").length, 1);
  assert.strictEqual(m.to("qh").length, 0);
});

test("小篇章 ready push follows the account's own window", async () => {
  await reset();
  await seedUser("qh", {quietHoursStart: "20:00", quietHoursEnd: "06:00"});
  await seedUser("def");
  const cfg = {pushEnabled: true, pushBody: "你嘅第 {N} 章整理好喇，得閒入嚟睇下。"};
  const push = async (uid, at) => {
    const m = fakeMessaging();
    const snap = await db.doc(`users/${uid}`).get();
    return chapter.pushReady({db, messaging: m, now: () => at.getTime()},
        snap, 2, cfg);
  };
  assert.strictEqual((await push("qh", hk(20, 30))).status, "quiet_hours");
  assert.strictEqual((await push("def", hk(20, 30))).status, "sent");
  assert.strictEqual((await push("qh", hk(6, 30, 22))).status, "sent");
  assert.strictEqual((await push("def", hk(6, 30, 22))).status,
      "quiet_hours");
});

test("a global window in app_config/reminders still applies to accounts " +
    "without own values; own values win", async () => {
  await reset();
  await db.doc("app_config/reminders").set({m7FollowupPushEnabled: true,
    quietHoursStart: "21:00", quietHoursEnd: "07:00"});
  await seedUser("qh", {quietHoursStart: "23:00", quietHoursEnd: "06:00"});
  await seedUser("def");
  for (const uid of ["qh", "def"]) {
    await seedReminder(uid, "r2130", "2026-10-21T21:30:00.000");
  }
  const m = fakeMessaging();
  await dispatchAt(m, hk(21, 30));
  assert.strictEqual(m.to("qh").length, 1, "own start 23:00");
  assert.strictEqual(m.to("def").length, 0, "global start 21:00");
  m.clear();
  await dispatchAt(m, hk(7, 0, 22));
  assert.strictEqual(m.to("def").length, 1, "global end 07:00");
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
    console.log(`${failed} quiet_hours_1020o emulator test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} quiet_hours_1020o emulator tests passed`);
  process.exit(0);
})();
