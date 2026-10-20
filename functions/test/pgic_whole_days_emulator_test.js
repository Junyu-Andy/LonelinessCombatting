/**
 * 10/20 decisions-log item 98 (decision 0067) — weeks 5–7 (PGIC only) on
 * whole Hong Kong days, like weeks 1–3, against the Firestore emulator:
 * synthetic accounts only, a simulated clock, a fake FCM sender, no real
 * push and no e-mail.
 *
 *   1. weeklyReminderV2Enabled on: study days 34–38, the dispatcher run at
 *      every hour of every day (00:00–23:00, wider than the 08:00–21:00
 *      cron).  W5 opens day 35 00:00; 10:00 day 35 the S14 push to
 *      everyone (both arms, every prefix, a switched tester); 10:00 day 36
 *      the S14 reminder only to whoever has not answered; nothing on days
 *      34 (no preview), 37 (no last-day reminder) and 38; an answer at
 *      23:59 on day 37 is inside; the window closes at the end of day 37
 *      and the missed record follows; never in the research lead's
 *      e-mail; weeklyPushHour (here 20) is not read.
 *   2. Weeks 6 and 7: the same days (42–44, 49–51).
 *   3. A person caught inside a W5 window by the deploy: the push and the
 *      reminder the old path already sent are not sent again.
 *   4. weeklyReminderV2Enabled off: exactly the T24 path, at the default
 *      weeklyPushHour (10 since item 98): 72 hours, 24-hour reminder.
 *
 * Quiet hours are personal (functions/quiet_hours.js, 1020o); one account
 * carries the widest window allowed (20:00–08:00) and still gets its 10:00
 * pushes.  Every instant is passed in (`now`), so the test gives the same
 * result whatever the time of day it runs.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/pgic_whole_days_emulator_test.js"
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

require("../index"); // initialises firebase-admin
const admin = require("firebase-admin");
const ws = require("../weekly_schedule");
const sw = require("../study_week");
const sp = require("../study_period");
const qh = require("../quiet_hours");
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
const iso = (d) => d.toISOString();

const V2_FLAGS = {weeklyReminderV2Enabled: true};
// weeklyPushHour 20 on purpose: with reminders v2 on it must not matter.
const PHASE_B_20 = {weeklyScheduleV2Enabled: true, weeklyPushHour: 20};
const QUIET = qh.quietHoursConfigFrom({});

function fakeMessaging() {
  const sent = [];
  return {
    sent,
    send: async (msg) => {
      sent.push(msg);
      return `id-${sent.length}`;
    },
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
  if (phaseB) await db.doc(ws.CONFIG_DOC).set(phaseB);
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

// Both arms, the three prefixes, a switched tester (runs like a pilot
// participant), the widest personal quiet hours, and two accounts that
// must never get anything (a plain tester, an unregistered account).
async function seedPeople() {
  await seedUser("never", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-31");
  await seedUser("early", {arm: "B", cohort: sp.COHORT_RCT}, "RCT-32");
  await seedUser("late", {arm: "A", cohort: sp.COHORT_RUN_IN}, "PB-33");
  await seedUser("edge", {arm: "B", cohort: sp.COHORT_PILOT,
    armAssignmentMode: sp.PILOT_MODE}, "PILOT-34");
  await seedUser("quiet", {arm: "B", cohort: sp.COHORT_RCT,
    quietHoursStart: "20:00", quietHoursEnd: "08:00"}, "RCT-35");
  await seedUser("sw", {arm: "A", cohort: sp.COHORT_PILOT, isTester: true,
    armAssignedBy: "tester_switch"});
  await seedUser("tester", {arm: "B", cohort: sp.COHORT_RCT, isTester: true});
  await seedUser("unreg", {arm: "B"});
}

// The App's PGIC answer for one bundle, then the trigger's stamp.
async function answer(uid, bundleId, at) {
  await db.doc(`users/${uid}/pgic/${bundleId}`).set({bundle: bundleId,
    value: 5, answeredAt: ts(at)});
  const snap = await db.doc(`users/${uid}/pgic/${bundleId}`).get();
  return ws.stampPartRecord(db, uid, ws.PGIC_COLLECTION, bundleId,
      snap.data(), {now: at});
}

const pgic = async (uid, id) =>
  (await db.doc(`users/${uid}/pgic/${id}`).get()).data();
const status = async (uid) =>
  ((await db.doc(`weekly_status/${uid}`).get()).data() || {}).bundles || {};

/**
 * Runs the dispatcher once per hour from `fromDay` 00:00 to `toDay` 23:00
 * (actions[`day:hour`] first).
 * @param {object} m fakeMessaging()
 * @param {number} fromDay study day
 * @param {number} toDay study day
 * @param {?Object<string, function(): Promise>} actions by "day:hour"
 * @return {Promise<string[]>} every push as "day hh:00 uid body"
 */
async function hourly(m, fromDay, toDay, actions) {
  const log = [];
  for (let day = fromDay; day <= toDay; day++) {
    for (let hour = 0; hour < 24; hour++) {
      const act = (actions || {})[`${day}:${hour}`];
      if (act) await act();
      const before = m.sent.length;
      await ws.dispatchWeeklyBundles(db, m,
          {now: hk(day, hour), log: silent, quiet: QUIET});
      for (const x of m.sent.slice(before)) {
        log.push(`${day} ${String(hour).padStart(2, "0")}:00 ` +
          `${x.token.slice(4)} ${x.notification.body}`);
      }
    }
  }
  return log;
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

// ---------------------------------------------------------------------------
// 1. Week 5, days 34–38, reminders v2 on
// ---------------------------------------------------------------------------

test("W5 with reminders v2: opens day 35 00:00; 10:00 push to all; day 36 " +
    "10:00 only to the unanswered; closes end of day 37; missed after; " +
    "nothing on days 34, 37, 38; both arms alike; not in the e-mail",
async () => {
  await reset(V2_FLAGS, PHASE_B_20);
  await seedPeople();
  const m = fakeMessaging();
  const everyone = ["early", "edge", "late", "never", "quiet", "sw"];
  const P = ws.PUSH_BODY;
  const R = ws.REMINDER_BODY;

  // The windows the server will stamp.
  const cfg = await ws.readConfig(db);
  assert.strictEqual(cfg.reminderV2, true);
  assert.strictEqual(cfg.pushHour, 20, "configured 20, and not read");
  const w5 = ws.bundleById(cfg, "standard", "W5");
  const win = ws.windowFor(w5, W0, cfg, ws.windowOptsFor({}, cfg));
  assert.strictEqual(iso(win.open), iso(hk(35, 0)));
  assert.strictEqual(iso(win.close), iso(hk(38, 0)));

  const actions = {
    // Day 34 23:59 is before the window: an answer then is "outside".
    // Day 35 00:30: early answers before the 10:00 push (still pushed —
    // the opening push goes to everyone, as weeks 1–3).
    "35:1": () => answer("early", "W5", hk(35, 0, 30)),
    // quiet and sw answer on day 35 after the push.
    "35:12": async () => {
      await answer("quiet", "W5", hk(35, 11));
      await answer("sw", "W5", hk(35, 11, 5));
    },
    // late answers on day 36 after the reminder.
    "36:15": () => answer("late", "W5", hk(36, 14, 30)),
    // Day 37 23:00 (after the last cron tick of the last day): nothing
    // missed yet.
    "37:23": async () => {
      assert.strictEqual(await pgic("never", "W5"), undefined,
          "still open on day 37 evening");
      assert.strictEqual(((await status("never")).W5 || {}).missedAt,
          undefined);
    },
    // edge answers at 23:59 on day 37, the last minute of the window; the
    // next run is day 38 00:00, the first instant after the window, which
    // writes never's missed record and leaves edge's answer alone.
    "38:0": () => answer("edge", "W5", hk(37, 23, 59)),
    "38:1": async () => {
      const miss = await pgic("never", "W5");
      assert.strictEqual(miss.status, "missed");
      assert.strictEqual(miss.missed, true);
      assert.strictEqual((await pgic("edge", "W5")).value, 5);
    },
  };

  const log = await hourly(m, 34, 38, actions);
  assert.deepStrictEqual(log, [
    ...everyone.map((u) => `35 10:00 ${u} ${P}`),
    // Not answered by day 36 10:00: edge (answers on day 37), late
    // (answers after the reminder), never.
    `36 10:00 edge ${R}`,
    `36 10:00 late ${R}`,
    `36 10:00 never ${R}`,
  ]);

  // weekly_status: the open push in pushedAt (+ S14-open), the reminder in
  // reminderSentAt (T24's field), the whole-day window.
  const stNever = (await status("never")).W5;
  assert.strictEqual(iso(stNever.pushedAt.toDate()), iso(hk(35, 10)));
  assert.strictEqual(stNever.pushCopyId, ws.S14_OPEN);
  assert.strictEqual(iso(stNever.reminderSentAt.toDate()), iso(hk(36, 10)));
  assert.strictEqual(iso(stNever.windowStart.toDate()), iso(hk(35, 0)));
  assert.strictEqual(iso(stNever.windowEnd.toDate()), iso(hk(38, 0)));
  assert.strictEqual(iso(stNever.missedAt.toDate()), iso(hk(38, 0)));
  assert.deepStrictEqual(stNever.missedParts, ["pgic"]);
  assert.strictEqual(stNever.previewSentAt, undefined);
  assert.strictEqual(stNever.remind1SentAt, undefined);
  assert.strictEqual(stNever.remind2SentAt, undefined);
  const stEarly = (await status("early")).W5;
  assert.strictEqual(stEarly.reminderSentAt, undefined);
  assert.deepStrictEqual(stEarly.missedParts, [], "closed complete");
  // Nobody outside the schedule.
  for (const uid of ["tester", "unreg"]) {
    assert.deepStrictEqual(await status(uid), {}, uid);
  }

  // The records: stamped with the whole-day window; outsideWindow false for
  // every answer inside (00:30 day 35 … 23:59 day 37); the missed one null.
  for (const uid of ["early", "late", "edge", "quiet", "sw"]) {
    const r = await pgic(uid, "W5");
    assert.strictEqual(r.outsideWindow, false, uid);
    assert.strictEqual(r.value, 5, uid);
    assert.strictEqual(iso(r.windowStart.toDate()), iso(hk(35, 0)), uid);
    assert.strictEqual(iso(r.windowEnd.toDate()), iso(hk(38, 0)), uid);
    assert.strictEqual(r.studyWeek, 5, uid);
    assert.strictEqual(r.studyDay, 35, uid);
  }
  assert.strictEqual((await pgic("edge", "W5")).submittedStudyDay, 37);
  const missed = await pgic("never", "W5");
  assert.strictEqual(missed.outsideWindow, null);
  assert.strictEqual(iso(missed.windowEnd.toDate()), iso(hk(38, 0)));

  // Events: the opening push and the reminder, with their copy ids.
  const ev = (await db.collection("users/never/events").get()).docs
      .map((d) => d.data())
      .map((e) => [e.name, e.params.step || null, e.params.copyId || null])
      .sort();
  assert.deepStrictEqual(ev, [
    ["weekly_bundle_missed", null, null],
    ["weekly_bundle_push_sent", "open", "S14-open"],
    ["weekly_bundle_reminder_sent", "remind1", "S14-rem"],
  ]);

  // The research lead's e-mail never lists week 5 (days 35, 36, 37).
  for (const day of [35, 36, 37]) {
    assert.deepStrictEqual(await email.incompleteClosingToday(db,
        hk(day, 10)), [], `day ${day}`);
    const r = await email.sendDailyIncompleteEmail(db, {now: hk(day, 10),
      smtp: null, auth: null});
    assert.strictEqual(r.status, "none", `day ${day}`);
  }
});

test("an answer at 23:59 on day 34 is outside; one at 00:00 on day 38 is " +
    "outside and kept (not overwritten as missed)", async () => {
  await reset(V2_FLAGS, PHASE_B_20);
  await seedUser("a", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-41");
  await seedUser("b", {arm: "B", cohort: sp.COHORT_RCT}, "RCT-42");
  // The App only offers W5 inside its window; a record written early or
  // late (a clock change, an offline sync) is stamped, not refused.
  await answer("a", "W5", hk(34, 23, 59));
  assert.strictEqual((await pgic("a", "W5")).outsideWindow, true);
  await answer("b", "W5", hk(38, 0));
  assert.strictEqual((await pgic("b", "W5")).outsideWindow, true);
  await ws.dispatchWeeklyBundles(db, fakeMessaging(),
      {now: hk(38, 8), log: silent, quiet: QUIET});
  assert.strictEqual((await pgic("b", "W5")).value, 5);
  assert.notStrictEqual((await pgic("b", "W5")).status, "missed");
});

// ---------------------------------------------------------------------------
// 2. Weeks 6 and 7
// ---------------------------------------------------------------------------

test("W6 and W7: the same pattern on days 42–44 and 49–51", async () => {
  await reset(V2_FLAGS, PHASE_B_20);
  // W4 recorded on day 30: its window is long closed by day 41.
  await seedUser("a", {arm: "A", cohort: sp.COHORT_RCT,
    w4RecordedOn: sw.addDays(W0, 30)}, "RCT-51");
  await seedUser("b", {arm: "B", cohort: sp.COHORT_RCT,
    w4RecordedOn: sw.addDays(W0, 30)}, "RCT-52");
  const m = fakeMessaging();
  const P = ws.PUSH_BODY;
  const R = ws.REMINDER_BODY;
  const log6 = await hourly(m, 41, 45, {
    "42:11": () => answer("b", "W6", hk(42, 10, 30)),
  });
  assert.deepStrictEqual(log6, [`42 10:00 a ${P}`, `42 10:00 b ${P}`,
    `43 10:00 a ${R}`]);
  assert.strictEqual((await pgic("a", "W6")).status, "missed");
  assert.strictEqual(iso((await pgic("a", "W6")).windowEnd.toDate()),
      iso(hk(45, 0)));
  const log7 = await hourly(m, 48, 52, {
    "49:11": () => answer("a", "W7", hk(49, 10, 45)),
  });
  assert.deepStrictEqual(log7, [`49 10:00 a ${P}`, `49 10:00 b ${P}`,
    `50 10:00 b ${R}`]);
  assert.strictEqual((await pgic("b", "W7")).status, "missed");
  assert.strictEqual(iso((await status("b")).W7.windowStart.toDate()),
      iso(hk(49, 0)));
});

// ---------------------------------------------------------------------------
// 3. Caught mid-window by the deploy
// ---------------------------------------------------------------------------

test("deploy mid-window: what the old path already sent is not sent " +
    "again; the window now ends with day 37", async () => {
  await reset(V2_FLAGS, {weeklyScheduleV2Enabled: true, weeklyPushHour: 10});
  await seedUser("a", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-61");
  await seedUser("b", {arm: "B", cohort: sp.COHORT_RCT}, "RCT-62");
  // As the old path (T24, production hour 10) left them on day 36 at
  // 10:00: a pushed and reminded; b pushed only.
  await db.doc("weekly_status/a").set({bundles: {W5: {
    pushedAt: ts(hk(35, 10)), reminderSentAt: ts(hk(36, 10)),
    windowStart: ts(hk(35, 10)), windowEnd: ts(hk(38, 10))}}});
  await db.doc("weekly_status/b").set({bundles: {W5: {
    pushedAt: ts(hk(35, 10)),
    windowStart: ts(hk(35, 10)), windowEnd: ts(hk(38, 10))}}});
  const m = fakeMessaging();
  // The new code from day 36 11:00: b still gets its one reminder that
  // day, a nothing more.
  const log = [];
  for (let hour = 11; hour < 24; hour++) {
    await ws.dispatchWeeklyBundles(db, m,
        {now: hk(36, hour), log: silent, quiet: QUIET});
  }
  for (const x of m.sent) {
    log.push(`${x.token.slice(4)} ${x.notification.body}`);
  }
  assert.deepStrictEqual(log, [`b ${ws.REMINDER_BODY}`]);
  m.clear();
  // Day 37: nothing; day 38 00:00: missed (the old window ran to 10:00).
  for (let hour = 0; hour < 24; hour++) {
    await ws.dispatchWeeklyBundles(db, m,
        {now: hk(37, hour), log: silent, quiet: QUIET});
  }
  await ws.dispatchWeeklyBundles(db, m,
      {now: hk(38, 0), log: silent, quiet: QUIET});
  assert.strictEqual(m.sent.length, 0);
  for (const uid of ["a", "b"]) {
    const r = await pgic(uid, "W5");
    assert.strictEqual(r.status, "missed", uid);
    assert.strictEqual(iso(r.windowEnd.toDate()), iso(hk(38, 0)), uid);
    assert.strictEqual(iso((await status(uid)).W5.windowEnd.toDate()),
        iso(hk(38, 0)), uid);
  }
});

// ---------------------------------------------------------------------------
// 4. Reminders v2 off: as before
// ---------------------------------------------------------------------------

test("reminders v2 off: W5 exactly T24 at the default weeklyPushHour (10): " +
    "push day 35 10:00, reminder 24 h later, closes day 38 10:00, no " +
    "outsideWindow", async () => {
  await reset({}, {weeklyScheduleV2Enabled: true}); // no weeklyPushHour
  const cfg = await ws.readConfig(db);
  assert.strictEqual(cfg.reminderV2, false);
  assert.strictEqual(cfg.pushHour, 10, "the new default");
  await seedUser("a", {arm: "A", cohort: sp.COHORT_RCT}, "RCT-71");
  await seedUser("b", {arm: "B", cohort: sp.COHORT_RCT}, "RCT-72");
  const m = fakeMessaging();
  const log = await hourly(m, 34, 37, {
    "35:12": () => answer("b", "W5", hk(35, 11, 30)),
  });
  assert.deepStrictEqual(log, [
    `35 10:00 a ${ws.PUSH_BODY}`,
    `35 10:00 b ${ws.PUSH_BODY}`,
    `36 10:00 a ${ws.REMINDER_BODY}`,
  ]);
  assert.strictEqual(iso((await status("a")).W5.windowStart.toDate()),
      iso(hk(35, 10)));
  assert.strictEqual(iso((await status("a")).W5.windowEnd.toDate()),
      iso(hk(38, 10)));
  assert.strictEqual("outsideWindow" in (await pgic("b", "W5")), false);
  await ws.dispatchWeeklyBundles(db, m,
      {now: hk(38, 9), log: silent, quiet: QUIET});
  assert.strictEqual(await pgic("a", "W5"), undefined, "open until 10:00");
  await ws.dispatchWeeklyBundles(db, m,
      {now: hk(38, 10), log: silent, quiet: QUIET});
  const missed = await pgic("a", "W5");
  assert.strictEqual(missed.status, "missed");
  assert.strictEqual("outsideWindow" in missed, false);
  assert.strictEqual(m.sent.length, 3);
  assert.strictEqual((await email.sendDailyIncompleteEmail(db,
      {now: hk(37, 10), smtp: null, auth: null})).status, "disabled");
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
    console.log(`${failed} pgic_whole_days emulator test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} pgic_whole_days emulator tests passed`);
  process.exit(0);
})();
