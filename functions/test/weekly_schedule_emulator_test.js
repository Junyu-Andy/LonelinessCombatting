/**
 * T24 — weekly bundle dispatcher, missed marks, record stamping and the
 * brief_pr week attribution (functions/weekly_schedule.js) against the
 * Firestore emulator, synthetic users only, fake FCM sender.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/weekly_schedule_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

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

// W0 = 2026-10-19 (Monday) = study day 0.  hk(day, hour) = that study day, HKT.
const W0 = "2026-10-19";
function hk(day, hour, minute) {
  const key = sw.addDays(W0, day);
  const hh = String(hour).padStart(2, "0");
  const mm = String(minute || 0).padStart(2, "0");
  return new Date(`${key}T${hh}:${mm}:00+08:00`);
}
const FINAL_COPY = {push: "（測試）每週問卷", reminder: "（測試）提醒"};
const ON = {weeklyScheduleV2Enabled: true};

function fakeMessaging() {
  const sent = [];
  return {sent, send: async (msg) => {
    sent.push(msg);
    return `id-${sent.length}`;
  }};
}

async function reset(phaseB) {
  for (const p of ["users", "app_config", "weekly_status", "research_id_map"]) {
    await db.recursiveDelete(db.collection(p));
  }
  if (phaseB) await db.doc(ws.CONFIG_DOC).set(phaseB);
}

async function seedUser(uid, data) {
  await db.doc(`users/${uid}`).set(Object.assign(
      {createdAt: "2026-09-01T09:00:00.000", w0Date: W0}, data));
  await db.doc(`users/${uid}/fcm_tokens/dev1`).set({token: `tok-${uid}`});
}

async function seedCohort() {
  await seedUser("ua", {arm: "A", cohort: "phase_b"});
  await seedUser("ub", {arm: "B", cohort: "phase_b"});
  await seedUser("up", {arm: "A", cohort: "pilot"});
  await seedUser("upa", {arm: "A", cohort: "phase_a"});
  await seedUser("ut", {arm: "B", cohort: "phase_b", isTester: true});
  await seedUser("ux", {arm: "B"}); // unregistered
  await db.doc("research_id_map/ua").set({researchId: "PB-A01"});
}

const run = (m, now, copy, quiet) => ws.dispatchWeeklyBundles(db, m,
    {now, log: silent, copy: copy === undefined ? FINAL_COPY : copy,
      quiet: quiet || qh.quietHoursConfigFrom({})});
const part = async (uid, col, id) =>
  (await db.doc(`users/${uid}/${col}/${id}`).get());
const status = async (uid) => (await db.doc(`weekly_status/${uid}`).get());

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("switch off (no app_config/phase_b): nothing happens, " +
    "brief_pr is not stamped", async () => {
  await reset(null);
  await seedCohort();
  const m = fakeMessaging();
  const counts = await run(m, hk(7, 20));
  assert.deepStrictEqual(counts, {enabled: false});
  assert.strictEqual(m.sent.length, 0);
  assert.strictEqual((await status("ua")).exists, false);
  const r = await ws.stampBriefPr(db, "ua", "s1",
      {sessionEndedAt: ts(hk(8, 0, 30))});
  assert.strictEqual(r, null);
});

test("placeholder copy: nothing is sent, nothing is marked pushed",
    async () => {
      await reset(ON);
      await seedCohort();
      const m = fakeMessaging();
      const counts = await run(m, hk(7, 20), {});
      // ua, ub (W1) and the pilot account (its W4 is day 7).
      assert.strictEqual(counts.blocked_placeholder, 3);
      assert.strictEqual(m.sent.length, 0);
      assert.strictEqual((await status("ua")).exists, false);
    });

test("quiet hours postpone the push to the next tick", async () => {
  await reset(ON);
  await seedCohort();
  const m = fakeMessaging();
  const quiet = qh.quietHoursConfigFrom(
      {quietHoursStart: "19:30", quietHoursEnd: "21:00"});
  const c1 = await run(m, hk(7, 20), undefined, quiet);
  assert.strictEqual(c1.quiet_hours, 3);
  assert.strictEqual(m.sent.length, 0);
  // Toggle off for ub: it goes out even inside the window.
  await db.doc("users/ub").set({quietHoursEnabled: false}, {merge: true});
  const c2 = await run(m, hk(7, 20), undefined, quiet);
  assert.strictEqual(c2.pushed, 1);
  assert.strictEqual(m.sent[0].token, "tok-ub");
  // 21:00: the window is over, the rest go out.
  const c3 = await run(m, hk(7, 21), undefined, quiet);
  assert.strictEqual(c3.pushed, 2);
});

test("W1 timeline (W0 Monday): day 7 19:00 nothing; 20:00 push per " +
    "person, both arms identical; reminder 24 h; missed at day 10 20:00",
async () => {
  await reset(ON);
  await seedCohort();
  const m = fakeMessaging();

  await run(m, hk(6, 20));
  assert.strictEqual(m.sent.length, 0);
  await run(m, hk(7, 19));
  assert.strictEqual(m.sent.length, 0);

  const c7 = await run(m, hk(7, 20));
  assert.strictEqual(c7.pushed, 3);
  assert.deepStrictEqual(m.sent.map((s) => s.token).sort(),
      ["tok-ua", "tok-ub", "tok-up"]);
  const strip = (s) => JSON.stringify(Object.assign({}, s, {token: ""}));
  assert.strictEqual(strip(m.sent[0]), strip(m.sent[1]));
  assert.strictEqual(m.sent[0].notification.body, FINAL_COPY.push);
  assert.strictEqual(m.sent[0].data.kind, "weekly_bundle_push");
  // Not for Phase A, testers or unregistered accounts.
  for (const u of ["upa", "ut", "ux"]) {
    assert.strictEqual((await status(u)).exists, false, u);
  }
  const sa = (await status("ua")).data();
  assert.strictEqual(sa.researchId, "PB-A01");
  assert.strictEqual(sa.scheduleMode, "standard");
  assert.strictEqual(sa.w0Date, W0);
  assert.ok(sa.bundles.W1.pushedAt);
  assert.strictEqual(sa.bundles.W1.studyWeek, 1);
  assert.strictEqual(sa.bundles.W1.studyDay, 7);
  assert.strictEqual(sa.bundles.W1.windowStart.toDate().toISOString(),
      hk(7, 20).toISOString());
  assert.strictEqual(sa.bundles.W1.windowEnd.toDate().toISOString(),
      hk(10, 20).toISOString());
  // The pilot account got its W4 (day 7), no DJG in it.
  const sp = (await status("up")).data();
  assert.strictEqual(sp.scheduleMode, "pilot");
  assert.ok(sp.bundles.W4.pushedAt);
  assert.strictEqual(sp.bundles.W4.windowEnd.toDate().toISOString(),
      hk(8, 20).toISOString());
  // The research ID never lands under users/{uid}.
  const underUser = await db.collection("users").doc("ua").listCollections();
  for (const c of underUser) {
    const docs = await c.get();
    for (const d of docs.docs) {
      assert.ok(JSON.stringify(d.data()).indexOf("PB-A01") < 0, c.id);
    }
  }
  // Same day, next hour: no second push.
  await run(m, hk(7, 21));
  assert.strictEqual(m.sent.length, 3);

  // ua finishes all three parts on day 8 morning (as the App would).
  await db.doc("users/ua/djg_responses/W1").set({timepoint: "W1",
    bundle: "W1", status: "submitted", submittedAt: ts(hk(8, 9)),
    answers: {q1: "yes", q2: "no", q3: "no", q4: "yes", q5: "yes", q6: "no"}});
  await db.doc("users/ua/weekly_pr/W1").set({bundle: "W1",
    status: "completed", respondedAt: ts(hk(8, 9, 5)), items: {u1: 5}});
  await db.doc("users/ua/pgic/W1").set({bundle: "W1", value: 3,
    answeredAt: ts(hk(8, 9, 10))});
  // ub only starts the DJG.
  await db.doc("users/ub/djg_responses/W1").set({timepoint: "W1",
    bundle: "W1", status: "in_progress", answers: {q1: "yes"}});

  // Day 8 19:00: < 24 h.
  await run(m, hk(8, 19));
  assert.strictEqual(m.sent.length, 3);
  // Day 8 20:00: reminder for ub only (ua finished; the pilot account's
  // 1-day W4 window closes at this very tick → missed, not reminded).
  const c8 = await run(m, hk(8, 20));
  assert.strictEqual(c8.reminded, 1);
  assert.strictEqual(c8.missed, 1);
  assert.strictEqual(m.sent[3].token, "tok-ub");
  assert.strictEqual(m.sent[3].notification.body, FINAL_COPY.reminder);
  assert.strictEqual(m.sent[3].data.kind, "weekly_bundle_reminder");
  assert.strictEqual((await part("up", "pgic", "W4")).data().status,
      "missed");
  // Only once.
  await run(m, hk(9, 10));
  assert.strictEqual(m.sent.length, 4);

  // Day 10 19:59: still open, nothing missed.
  await run(m, hk(10, 19, 59));
  assert.strictEqual((await part("ub", "weekly_pr", "W1")).exists, false);
  // Day 10 20:00: window closed → ub's three parts are missed, ua none.
  const c10 = await run(m, hk(10, 20));
  assert.strictEqual(c10.missed, 1);
  assert.strictEqual(c10.closed_complete, 1);
  const d = (await part("ub", "djg_responses", "W1")).data();
  assert.strictEqual(d.status, "missed");
  assert.strictEqual(d.missed, true);
  assert.strictEqual(d.timepoint, "W1");
  assert.strictEqual(d.studyWeek, 1);
  assert.strictEqual(d.studyDay, 7);
  assert.strictEqual(d.submittedStudyDay, null);
  assert.strictEqual(d.scheduleMode, "standard");
  assert.strictEqual(d.windowStart.toDate().toISOString(),
      hk(7, 20).toISOString());
  assert.strictEqual(d.windowEnd.toDate().toISOString(),
      hk(10, 20).toISOString());
  assert.ok(d.pushedAt);
  assert.deepStrictEqual(d.answers, {q1: "yes"}); // kept
  const wp = (await part("ub", "weekly_pr", "W1")).data();
  assert.strictEqual(wp.status, "missed");
  assert.strictEqual(wp.bundle, "W1");
  const pg = (await part("ub", "pgic", "W1")).data();
  assert.strictEqual(pg.status, "missed");
  assert.strictEqual(pg.missed, true);
  const sb = (await status("ub")).data();
  assert.deepStrictEqual(sb.bundles.W1.missedParts.sort(),
      ["djg", "pgic", "weekly_pr"]);
  // ua: nothing marked missed; its records untouched by the dispatcher.
  assert.strictEqual((await part("ua", "weekly_pr", "W1")).data().status,
      "completed");
  assert.strictEqual((await status("ua")).data().bundles.W1.missedParts
      .length, 0);
  // Missed only once; nothing more happens later in the week.
  const c11 = await run(m, hk(11, 10));
  assert.strictEqual(c11.missed, undefined);
  assert.strictEqual(m.sent.length, 4);
  // Events per person.
  const ev = await db.collection("users").doc("ub").collection("events")
      .get();
  assert.deepStrictEqual(ev.docs.map((e) => e.data().name).sort(),
      ["weekly_bundle_missed", "weekly_bundle_push_sent",
        "weekly_bundle_reminder_sent"]);
});

test("week 4 (day 26 open, closes end of day 29) and PGIC-only week 5",
    async () => {
      await reset(ON);
      await seedUser("ua", {arm: "A", cohort: "phase_b"});
      const m = fakeMessaging();
      await run(m, hk(26, 20));
      assert.strictEqual(m.sent.length, 1);
      const s26 = (await status("ua")).data().bundles.W4;
      assert.strictEqual(s26.windowEnd.toDate().toISOString(),
          hk(30, 0).toISOString()); // 2026-11-18 00:00 HKT
      // Day 29 23:00: still open.
      const c29 = await run(m, hk(29, 23));
      assert.strictEqual(c29.missed, undefined);
      // Day 30 08:00: W4 missed (Weekly PR + PGIC, no DJG in W4).
      const c30 = await run(m, hk(30, 8));
      assert.strictEqual(c30.missed, 1);
      assert.strictEqual((await part("ua", "djg_responses", "W4")).exists,
          false);
      assert.strictEqual((await part("ua", "weekly_pr", "W4")).data().status,
          "missed");
      assert.strictEqual((await part("ua", "pgic", "W4")).data().studyWeek, 4);
      // Day 35 20:00: PGIC only.
      await run(m, hk(35, 20));
      assert.strictEqual(m.sent.length, 2);
      await run(m, hk(38, 20));
      assert.strictEqual((await part("ua", "pgic", "W5")).data().status,
          "missed");
      assert.strictEqual((await part("ua", "weekly_pr", "W5")).exists, false);
      assert.strictEqual((await part("ua", "djg_responses", "W5")).exists,
          false);
    });

test("pilot account: days 1, 3, 5, 7; DJG in the first three; 1-day " +
    "window; the Phase B account is untouched by the pilot days", async () => {
  await reset(ON);
  await seedUser("up", {arm: "B", cohort: "pilot"});
  await seedUser("ua", {arm: "A", cohort: "phase_b"});
  const m = fakeMessaging();
  for (const day of [1, 3, 5, 7]) {
    const c = await run(m, hk(day, 20));
    assert.strictEqual(c.pushed, day === 7 ? 2 : 1, `day ${day}`);
  }
  assert.strictEqual(m.sent.filter((s) => s.token === "tok-up").length, 4);
  assert.strictEqual(m.sent.filter((s) => s.token === "tok-ua").length, 1);
  // Close each pilot window one day later → missed parts show the shape.
  await run(m, hk(8, 20));
  const sp = (await status("up")).data().bundles;
  const all3 = ["djg", "pgic", "weekly_pr"];
  assert.deepStrictEqual(sp.W1.missedParts.sort(), all3);
  assert.deepStrictEqual(sp.W3.missedParts.sort(), all3);
  assert.deepStrictEqual(sp.W4.missedParts.sort(), ["pgic", "weekly_pr"]);
  assert.strictEqual((await part("up", "djg_responses", "W4")).exists, false);
  const d3 = (await part("up", "djg_responses", "W3")).data();
  assert.strictEqual(d3.scheduleMode, "pilot");
  assert.strictEqual(d3.studyDay, 5);
  assert.strictEqual(d3.studyWeek, 1);
  assert.strictEqual(d3.windowEnd.toDate().toISOString(),
      hk(6, 20).toISOString());
  // The Phase B account's W1 is still open on day 8.
  assert.strictEqual((await status("ua")).data().bundles.W1.missedAt,
      undefined);
});

test("stampPartRecord: weekly_pr / pgic / probe / DJG records get the " +
    "study-week fields once; a record without `bundle` is left alone",
async () => {
  await reset(ON);
  await seedUser("ua", {arm: "A", cohort: "phase_b"});
  const m = fakeMessaging();
  await run(m, hk(14, 20)); // W2 pushed → pushedAt known
  const wpRef = db.doc("users/ua/weekly_pr/W2");
  await wpRef.set({bundle: "W2", status: "completed", items: {u1: 6},
    respondedAt: ts(hk(15, 9))});
  const out = await ws.stampPartRecord(db, "ua", "weekly_pr", "W2",
      (await wpRef.get()).data(), {now: hk(15, 9, 1)});
  assert.strictEqual(out.studyWeek, 2);
  assert.strictEqual(out.studyDay, 14);
  assert.strictEqual(out.submittedStudyDay, 15);
  assert.strictEqual(out.missed, false);
  assert.strictEqual(out.scheduleMode, "standard");
  assert.strictEqual(out.pushedAt.toISOString(), hk(14, 20).toISOString());
  const stored = (await wpRef.get()).data();
  assert.strictEqual(stored.studyWeek, 2);
  assert.strictEqual(stored.windowEnd.toDate().toISOString(),
      hk(17, 20).toISOString());
  // Second call (the trigger's own write): no-op.
  assert.strictEqual(await ws.stampPartRecord(db, "ua", "weekly_pr", "W2",
      stored), null);
  // PGIC answered on day 17 at 19:00 — submittedStudyDay 17.
  await db.doc("users/ua/pgic/W2").set({bundle: "W2", value: 4,
    answeredAt: ts(hk(17, 19))});
  const pg = await ws.stampPartRecord(db, "ua", "pgic", "W2",
      (await db.doc("users/ua/pgic/W2").get()).data());
  assert.strictEqual(pg.submittedStudyDay, 17);
  // Probe.
  await db.doc("users/ua/social_contact_probes/W2").set({bundle: "W2",
    status: "submitted", answers: {q1: 1, q2: 3}, submittedAt: ts(hk(15, 10))});
  const sc = await ws.stampPartRecord(db, "ua", "social_contact_probes", "W2",
      (await db.doc("users/ua/social_contact_probes/W2").get()).data());
  assert.strictEqual(sc.studyWeek, 2);
  // DJG: the doc id is the bundle even without a `bundle` field.
  const dj = await ws.stampPartRecord(db, "ua", "djg_responses", "W2",
      {timepoint: "W2", status: "submitted", submittedAt: ts(hk(14, 21)),
        answers: {}});
  assert.strictEqual(dj.studyWeek, 2);
  assert.strictEqual(dj.submittedStudyDay, 14);
  // Legacy Sunday-window record (no bundle): untouched.
  assert.strictEqual(await ws.stampPartRecord(db, "ua", "weekly_pr", "abc",
      {weekIso: "2026-W44", status: "completed"}), null);
  // Unknown bundle id: untouched.
  assert.strictEqual(await ws.stampPartRecord(db, "ua", "pgic", "W9",
      {bundle: "W9", value: 1}), null);
});

test("brief_pr: week by session end — a session from day 7 23:00 to " +
    "day 8 00:30 belongs to week 2 (T25 records); older records fall back",
async () => {
  await reset(ON);
  await seedUser("ua", {arm: "A", cohort: "phase_b"});
  const ref = db.doc("users/ua/brief_pr/s1");
  await ref.set({schemaVersion: 3, agentId: "siu_yan", status: "completed",
    sessionStartedAt: ts(hk(7, 23)), sessionEndedAt: ts(hk(8, 0, 30)),
    respondedAt: ts(hk(8, 0, 32))});
  const out = await ws.stampBriefPr(db, "ua", "s1", (await ref.get()).data());
  assert.strictEqual(out.studyWeek, 2);
  assert.strictEqual(out.studyDay, 8);
  assert.strictEqual(out.studyWeekBasis, "sessionEndedAt");
  const stored = (await ref.get()).data();
  assert.strictEqual(stored.studyWeek, 2);
  assert.strictEqual(stored.sessionEndedAt.toDate().toISOString(),
      hk(8, 0, 30).toISOString()); // rest of the record untouched
  // Idempotent.
  assert.strictEqual(await ws.stampBriefPr(db, "ua", "s1", stored), null);
  // Same session end on day 7 23:59 → week 1.
  await db.doc("users/ua/brief_pr/s2").set({schemaVersion: 3,
    sessionEndedAt: ts(hk(7, 23, 59))});
  const o2 = await ws.stampBriefPr(db, "ua", "s2",
      (await db.doc("users/ua/brief_pr/s2").get()).data());
  assert.deepStrictEqual([o2.studyWeek, o2.studyDay], [1, 7]);
  // schemaVersion 2 record: respondedAt is the basis.
  const o3 = await ws.stampBriefPr(db, "ua", "s3",
      {schemaVersion: 2, respondedAt: ts(hk(15, 12))});
  assert.deepStrictEqual([o3.studyWeek, o3.studyDay, o3.studyWeekBasis],
      [3, 15, "respondedAt"]);
  // No time at all → nothing written.
  assert.strictEqual(await ws.stampBriefPr(db, "ua", "s4", {status: "x"}),
      null);
  // Unregistered account without W0 → createdAt is the W0 fallback.
  await db.doc("users/ux").set({createdAt: `${W0}T09:00:00.000`});
  const o5 = await ws.stampBriefPr(db, "ux", "s5",
      {sessionEndedAt: ts(hk(3, 12))});
  assert.deepStrictEqual([o5.studyWeek, o5.studyDay], [1, 3]);
});

test("T18 stands down: both switches on → djgW2Dispatch sends nothing; " +
    "scoring accepts W1–W3 with the schedule on, only W2 without", async () => {
  await reset({weeklyScheduleV2Enabled: true, djgW2InAppEnabled: true});
  await seedUser("ua", {arm: "A", cohort: "phase_b"});
  const m = fakeMessaging();
  // T18 counts W0 as day 1, so its day 14 is study day 13.
  const c = await djg.dispatchDjgW2(db, m, {now: hk(13, 10), log: silent,
    copy: {push: "x", reminder: "y"}});
  assert.strictEqual(c.supersededByWeeklyScheduleV2, true);
  assert.strictEqual(m.sent.length, 0);
  assert.strictEqual((await part("ua", "djg_responses", "W2")).exists, false);
  const answers = {q1: "yes", q2: "yes", q3: "yes", q4: "no", q5: "no",
    q6: "no"};
  const s1 = await djg.scoreSubmission(db, "ua", "W1",
      {status: "submitted", answers, submittedAt: ts(hk(8, 9))});
  assert.deepStrictEqual(s1.scores, {emotional: 3, social: 3, total: 6});
  assert.strictEqual(s1.outsideWindow, undefined); // weekly_schedule's job
  const s3 = await djg.scoreSubmission(db, "ua", "W3",
      {status: "submitted", answers, submittedAt: ts(hk(22, 9))});
  assert.strictEqual(s3.scores.total, 6);
  // Schedule off → only W2 (T18 behaviour, window fields included).
  await db.doc(ws.CONFIG_DOC).set({djgW2InAppEnabled: true});
  assert.strictEqual(await djg.scoreSubmission(db, "ua", "W1",
      {status: "submitted", answers, submittedAt: ts(hk(8, 9))}), null);
  const s2 = await djg.scoreSubmission(db, "ua", "W2",
      {status: "submitted", answers, submittedAt: ts(hk(14, 9))});
  assert.strictEqual(typeof s2.outsideWindow, "boolean");
});

test("switch off mid-week: windows long closed are not stamped missed " +
    "(7-day lookback)", async () => {
  await reset(ON);
  await seedUser("ua", {arm: "A", cohort: "phase_b"});
  const m = fakeMessaging();
  // First run on day 20: W1 closed on day 10 (> 7 days ago) → untouched;
  // W2 closed on day 17 (3 days ago) → missed.
  const c = await run(m, hk(20, 10));
  assert.strictEqual(c.missed, 1);
  assert.strictEqual((await part("ua", "pgic", "W1")).exists, false);
  assert.strictEqual((await status("ua")).data().bundles.W1, undefined);
  assert.strictEqual((await part("ua", "pgic", "W2")).data().status,
      "missed");
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
    console.log(`${failed} weekly_schedule emulator test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} weekly_schedule emulator tests passed`);
  process.exit(0);
})();
