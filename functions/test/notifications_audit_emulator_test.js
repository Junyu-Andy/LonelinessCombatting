/**
 * 10/15 notifications audit (docs/dev-tasks/notifications-audit-1015.md
 * §4 A): what a PILOT / Phase B / unregistered / tester account gets from
 * the server once the Phase B switches are on, day by day.  Pure server
 * side: weeklyBundleDispatch, the legacy Sunday reminder target and T18's
 * djgW2Dispatch, with the clock injected.  Covers A1–A11 and A14; A3, A4,
 * A8, A12, A13 (page texts) are Flutter tests; A15 is a grep.  The report
 * is docs/dev-reports/notifications-audit-20261015.md.
 *
 * Run from functions/:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "node test/notifications_audit_emulator_test.js"
 */
"use strict";

const assert = require("assert");
const admin = require("firebase-admin");
const ws = require("../weekly_schedule");
const sw = require("../study_week");
const djg = require("../djg_w2");
const qh = require("../quiet_hours");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();
const silent = () => {};
const ts = (d) => admin.firestore.Timestamp.fromDate(d);

// PILOT W0 = 2026-10-15 (Thursday); PB W0 = 2026-10-19 (Monday).
const PILOT_W0 = "2026-10-15";
const PB_W0 = "2026-10-19";
/**
 * HKT instant on PILOT study day `day`.
 * @param {number} day
 * @param {number} hour
 * @param {number=} minute
 * @return {Date}
 */
function hk(day, hour, minute) {
  const key = sw.addDays(PILOT_W0, day);
  const hh = String(hour).padStart(2, "0");
  const mm = String(minute || 0).padStart(2, "0");
  return new Date(`${key}T${hh}:${mm}:00+08:00`);
}
const ALL_ON = {
  weeklyScheduleV2Enabled: true,
  socialContactProbeEnabled: true,
  sessionBriefPrV2Enabled: true,
  djgW2InAppEnabled: true,
};
const REAL_COPY = {push: ws.PUSH_BODY, reminder: ws.REMINDER_BODY};

/**
 * @return {{sent: Array<object>, send: function(object): Promise<string>}}
 */
function fakeMessaging() {
  const sent = [];
  return {sent, send: async (msg) => {
    sent.push(msg);
    return `id-${sent.length}`;
  }};
}

/**
 * @param {?object} cfg app_config/phase_b, null = none
 */
async function reset(cfg) {
  for (const p of ["users", "app_config", "weekly_status", "research_id_map"]) {
    await db.recursiveDelete(db.collection(p));
  }
  if (cfg) await db.doc(ws.CONFIG_DOC).set(cfg);
}

/**
 * @param {string} uid
 * @param {object} data
 */
async function seedUser(uid, data) {
  await db.doc(`users/${uid}`).set(Object.assign(
      {createdAt: "2026-10-15T10:00:00.000"}, data));
  await db.doc(`users/${uid}/fcm_tokens/dev1`).set({token: `tok-${uid}`});
}

/**
 * §4 A: PILOT Hybrid, PILOT rule arm, PB (10/19), unregistered, tester.
 * @param {boolean=} withPb false = leave the PB account out (its own
 *     study days fall on PILOT days 11, 18, … and would mix into counts)
 */
async function seedAudit(withPb) {
  await seedUser("ph", {arm: "A", cohort: "pilot", w0Date: PILOT_W0});
  await seedUser("pr", {arm: "B", cohort: "pilot", w0Date: PILOT_W0});
  if (withPb !== false) {
    await seedUser("pb", {arm: "A", cohort: "phase_b", w0Date: PB_W0});
  }
  await seedUser("ux", {arm: "B"});
  await seedUser("ut", {arm: "A", cohort: "pilot", w0Date: PILOT_W0,
    isTester: true});
}

const run = (m, now, quiet) => ws.dispatchWeeklyBundles(db, m,
    {now, log: silent, copy: REAL_COPY,
      quiet: quiet || qh.quietHoursConfigFrom({})});
const part = async (uid, col, id) =>
  (await db.doc(`users/${uid}/${col}/${id}`).get());
const status = async (uid) => (await db.doc(`weekly_status/${uid}`).get());
const tokensOf = (m) => m.sent.map((s) => s.token).sort();

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("A15 (server): the weekly push and reminder carry no placeholder",
    async () => {
      assert.strictEqual(ws.isPlaceholder(ws.PUSH_BODY), false);
      assert.strictEqual(ws.isPlaceholder(ws.REMINDER_BODY), false);
      assert.strictEqual(ws.PUSH_BODY, "今個禮拜嘅問卷開咗，得閒入嚟答幾條。");
      assert.strictEqual(ws.REMINDER_BODY,
          "今個禮拜嘅問卷仲未答完，得閒入嚟答埋佢。");
      assert.strictEqual(ws.PUSH_TITLE, "陪住");
    });

test("A1 + A2: days 1–6 nothing per person; Sunday 10/18 (PILOT day 3) " +
    "no weekly push for PILOT, legacy Sunday reminder only for the " +
    "unregistered account", async () => {
  await reset(ALL_ON);
  await seedAudit();
  const m = fakeMessaging();
  for (let day = 1; day <= 6; day++) {
    for (const hour of [19, 20]) {
      const c = await run(m, hk(day, hour));
      assert.strictEqual(c.pushed, undefined, `day ${day} ${hour}:00`);
      assert.strictEqual(c.missed, undefined, `day ${day} ${hour}:00`);
    }
  }
  assert.strictEqual(m.sent.length, 0);
  for (const uid of ["ph", "pr", "pb", "ux", "ut"]) {
    assert.strictEqual((await status(uid)).exists, false, uid);
  }
  // 2026-10-18 is a Sunday = PILOT day 3.
  assert.strictEqual(hk(3, 20).getUTCDay(), 0);
  const users = {};
  for (const uid of ["ph", "pr", "pb", "ux", "ut"]) {
    users[uid] = (await db.doc(`users/${uid}`).get()).data();
  }
  const t = (uid, gateOn) =>
    ws.legacyWeeklyReminderTarget(users[uid], {gateOn});
  assert.strictEqual(t("ph", false), false);
  assert.strictEqual(t("pr", false), false);
  assert.strictEqual(t("pb", false), false);
  assert.strictEqual(t("ut", false), false);
  assert.strictEqual(t("ux", false), true); // gate off: legacy reminder
  assert.strictEqual(t("ux", true), false); // gate on: nobody
});

test("A3, A14: PILOT day 7 20:00 — both PILOT accounts get the S14 push, " +
    "four parts; PB (day -4), unregistered and tester get nothing",
async () => {
  await reset(ALL_ON);
  await seedAudit();
  const m = fakeMessaging();
  const c = await run(m, hk(7, 19));
  assert.strictEqual(c.pushed, undefined);
  const c7 = await run(m, hk(7, 20));
  assert.strictEqual(c7.pushed, 2);
  assert.deepStrictEqual(tokensOf(m), ["tok-ph", "tok-pr"]);
  for (const s of m.sent) {
    assert.strictEqual(s.notification.title, "陪住");
    assert.strictEqual(s.notification.body, ws.PUSH_BODY);
    assert.strictEqual(s.data.kind, "weekly_bundle_push");
  }
  const b1 = ws.bundlesFor(ws.configFromData(ALL_ON), "standard")[0];
  assert.deepStrictEqual(b1.parts,
      ["djg", "weekly_pr", "pgic", "social_contact"]);
  const sp = (await status("ph")).data();
  assert.strictEqual(sp.scheduleMode, "standard");
  assert.strictEqual(sp.bundles.W1.studyDay, 7);
  assert.strictEqual(sp.bundles.W1.windowEnd.toDate().toISOString(),
      hk(10, 20).toISOString());
  for (const uid of ["pb", "ux", "ut"]) {
    assert.strictEqual((await status(uid)).exists, false, uid);
  }
  // Same evening, next hour: no second push.
  await run(m, hk(7, 21));
  assert.strictEqual(m.sent.length, 2);
});

test("A4, A5: reminder once at day 8 20:00 for the parts still open; " +
    "window closes day 10 20:00 → missed records, no second reminder",
async () => {
  await reset(ALL_ON);
  await seedAudit(false);
  const m = fakeMessaging();
  await run(m, hk(7, 20));
  // ph answers DJG and Weekly PR the same evening, then stops.
  await db.doc("users/ph/djg_responses/W1").set({timepoint: "W1",
    bundle: "W1", status: "submitted", submittedAt: ts(hk(7, 21)),
    answers: {q1: "yes", q2: "no", q3: "no", q4: "yes", q5: "yes", q6: "no"}});
  await db.doc("users/ph/weekly_pr/W1").set({bundle: "W1",
    status: "completed", respondedAt: ts(hk(7, 21, 5)), items: {u1: 5}});
  await run(m, hk(8, 19));
  assert.strictEqual(m.sent.length, 2); // < 24 h
  const c8 = await run(m, hk(8, 20));
  assert.strictEqual(c8.reminded, 2);
  assert.strictEqual(c8.missed, undefined);
  const reminders = m.sent.slice(2);
  assert.deepStrictEqual(reminders.map((s) => s.token).sort(),
      ["tok-ph", "tok-pr"]);
  for (const s of reminders) {
    assert.strictEqual(s.notification.body, ws.REMINDER_BODY);
    assert.strictEqual(s.data.kind, "weekly_bundle_reminder");
  }
  const evPh = await db.collection("users/ph/events")
      .where("name", "==", "weekly_bundle_reminder_sent").get();
  assert.deepStrictEqual(evPh.docs[0].data().params.parts.sort(),
      ["pgic", "social_contact"]);
  // Only once.
  await run(m, hk(9, 10));
  await run(m, hk(9, 20));
  assert.deepStrictEqual(
      m.sent.slice(4).map((s) => `${s.token}:${s.data.kind}`), []);
  // Day 10 19:59 still open.
  const c10a = await run(m, hk(10, 19, 59));
  assert.strictEqual(c10a.missed, undefined);
  // Day 10 20:00: closed.
  const c10 = await run(m, hk(10, 20));
  assert.strictEqual(c10.missed, 2);
  const sph = (await status("ph")).data().bundles.W1;
  assert.deepStrictEqual(sph.missedParts.sort(), ["pgic", "social_contact"]);
  const pg = (await part("ph", "pgic", "W1")).data();
  assert.strictEqual(pg.status, "missed");
  assert.strictEqual(pg.missed, true);
  const sc = (await part("ph", "social_contact_probes", "W1")).data();
  assert.strictEqual(sc.status, "missed");
  // The answered parts are untouched.
  assert.strictEqual((await part("ph", "djg_responses", "W1")).data().status,
      "submitted");
  const spr = (await status("pr")).data().bundles.W1;
  assert.deepStrictEqual(spr.missedParts.sort(),
      ["djg", "pgic", "social_contact", "weekly_pr"]);
  // Nothing more later in the week.
  const c11 = await run(m, hk(11, 20));
  assert.strictEqual(c11.missed, undefined);
  assert.strictEqual(m.sent.length, 4);
  const names = (await db.collection("users/ph/events").get()).docs
      .map((d) => d.data().name).sort();
  assert.deepStrictEqual(names, ["weekly_bundle_missed",
    "weekly_bundle_push_sent", "weekly_bundle_reminder_sent"]);
});

test("A6, A7, A8, A9: W2 (day 14, DJG, no T18 push at 10:00), W3 (21), " +
    "W4 (26, no DJG, closes end of day 29), PGIC only on 35/42/49, " +
    "nothing on day 56 or 63", async () => {
  await reset(ALL_ON);
  await seedAudit(false);
  const m = fakeMessaging();
  const expectBundle = async (day, id, parts, close) => {
    const before = m.sent.length;
    const c = await run(m, hk(day, 20));
    assert.strictEqual(c.pushed, 2, `day ${day}`);
    assert.strictEqual(m.sent.length, before + 2);
    const b = (await status("ph")).data().bundles[id];
    assert.ok(b && b.pushedAt, `${id} pushed`);
    assert.strictEqual(b.windowEnd.toDate().toISOString(),
        close.toISOString(), `${id} close`);
    const bundle = ws.bundlesFor(ws.configFromData(ALL_ON), "standard")
        .find((x) => x.id === id);
    assert.deepStrictEqual(bundle.parts, parts, `${id} parts`);
  };
  // T18 day-14 push at 10:00 stands down (its day 14 = study day 13).
  const t18 = await djg.dispatchDjgW2(db, m, {now: hk(13, 10), log: silent,
    copy: {push: "x", reminder: "y"}});
  assert.strictEqual(t18.supersededByWeeklyScheduleV2, true);
  assert.strictEqual(m.sent.length, 0);
  await expectBundle(7, "W1", ["djg", "weekly_pr", "pgic", "social_contact"],
      hk(10, 20));
  await expectBundle(14, "W2", ["djg", "weekly_pr", "pgic", "social_contact"],
      hk(17, 20));
  await expectBundle(21, "W3", ["djg", "weekly_pr", "pgic", "social_contact"],
      hk(24, 20));
  await expectBundle(26, "W4", ["weekly_pr", "pgic", "social_contact"],
      hk(30, 0));
  const c29 = await run(m, hk(29, 23));
  assert.strictEqual(c29.missed, undefined);
  const c30 = await run(m, hk(30, 8));
  assert.strictEqual(c30.missed, 2);
  assert.strictEqual((await part("ph", "djg_responses", "W4")).exists, false);
  await expectBundle(35, "W5", ["pgic"], hk(38, 20));
  await expectBundle(42, "W6", ["pgic"], hk(45, 20));
  await expectBundle(49, "W7", ["pgic"], hk(52, 20));
  // Day 56 / 63: nothing (W8, T35 not built).
  const before = m.sent.length;
  for (const day of [56, 63]) {
    const c = await run(m, hk(day, 20));
    assert.strictEqual(c.pushed, undefined, `day ${day}`);
  }
  assert.strictEqual(m.sent.length, before);
  // Tester: never.
  assert.strictEqual(m.sent.filter((s) => s.token === "tok-ut").length, 0);
});

test("PB account: pushed on its own study days (W0 10/19 → day 7 = 10/26)",
    async () => {
      await reset(ALL_ON);
      await seedAudit();
      const m = fakeMessaging();
      // PILOT day 11 = PB day 7.
      const c = await run(m, hk(11, 20));
      assert.strictEqual(c.pushed, 1);
      assert.strictEqual(m.sent[0].token, "tok-pb");
      const sb = (await status("pb")).data();
      assert.strictEqual(sb.w0Date, PB_W0);
      assert.strictEqual(sb.bundles.W1.studyDay, 7);
    });

test("catch-up: a bundle whose window is still open goes out at the first " +
    "tick inside the window; a closed window is marked missed, never pushed",
async () => {
  await reset(ALL_ON);
  await seedAudit();
  const m = fakeMessaging();
  // No run at PB day 7 (PILOT day 11); first run PB day 8 10:00 → W1 goes.
  const c = await run(m, hk(12, 10));
  assert.strictEqual(c.pushed, 1);
  assert.strictEqual(m.sent[0].token, "tok-pb");
  // No run again until PB day 22 (PILOT day 26): W2 closed day 17 → missed;
  // W3 (open day 21, closes day 24) → pushed now.
  const c2 = await run(m, hk(26, 10));
  const pb = (await status("pb")).data().bundles;
  assert.ok(pb.W2.missedAt);
  assert.strictEqual(pb.W2.pushedAt, undefined);
  assert.ok(pb.W3.pushedAt);
  assert.ok(c2.pushed >= 1);
});

test("A10, A11: a push due inside quiet hours (22:30) is postponed to the " +
    "next tick (08:00), not dropped; quietHoursEnabled=false sends at 22:30",
async () => {
  await reset(ALL_ON);
  await seedUser("pq", {arm: "A", cohort: "pilot", w0Date: PILOT_W0});
  await seedUser("pn", {arm: "B", cohort: "pilot", w0Date: PILOT_W0,
    quietHoursEnabled: false});
  const m = fakeMessaging();
  // Skip the 20:00 and 21:00 ticks of day 7; first look at 22:30.
  const c = await run(m, hk(7, 22, 30));
  assert.strictEqual(c.quiet_hours, 1);
  assert.strictEqual(c.pushed, 1);
  assert.strictEqual(m.sent[0].token, "tok-pn");
  assert.strictEqual((await status("pq")).exists, false);
  // 07:30 still quiet; 08:00 goes out.
  const c730 = await run(m, hk(8, 7, 30));
  assert.strictEqual(c730.quiet_hours, 1);
  const c8 = await run(m, hk(8, 8));
  assert.strictEqual(c8.pushed, 1);
  assert.strictEqual(m.sent[1].token, "tok-pq");
  assert.strictEqual((await status("pq")).data().bundles.W1.pushedAt
      .toDate().toISOString(), hk(8, 8).toISOString());
  // Reminders come 24 h after the push that actually went out: pn's is due
  // day 8 22:25 (after the last 21:00 tick), pq's day 9 07:55 — so both go
  // out at the day 9 08:00 tick, none at day 8 20:00 / 21:00.
  for (const hour of [20, 21]) {
    const c = await run(m, hk(8, hour));
    assert.strictEqual(c.reminded, undefined, `day 8 ${hour}:00`);
  }
  const c9 = await run(m, hk(9, 8));
  assert.strictEqual(c9.reminded, 2);
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
    console.log(`${failed} notifications audit test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} notifications audit tests passed`);
  process.exit(0);
})();
