/**
 * T35 — the W8 questionnaire against the Firestore emulator (handover
 * 1021-W8 五; decision 0036).  Synthetic accounts only, a simulated
 * clock, a fake FCM sender and a fake mailer: no real push, no real
 * e-mail, no production data.
 *
 *   1. One person per W0 weekday (Monday 2026-10-19 … Sunday 10-25), plus
 *      a second Monday and a second Sunday; RCT-, PB- and PILOT-; both
 *      arms.  The dispatcher runs every hour of every day from study day
 *      55 to day 72 of the latest W0.  Day 56 10:00: one push to everyone;
 *      day 58 and day 60 10:00: only to whoever has not finished the five
 *      parts; nothing else, no day-62 reminder.  The app_config/reminders
 *      quiet window (here 09:00–11:00) does not apply (handover 一 (6)).
 *   2. A tester, a tester that switched its own arm and an unregistered
 *      account get nothing.
 *   3. Server stamps: studyWeek 8, studyDay 56, submittedStudyDay,
 *      outOfWindow (an answer at 23:59 on day 63 is inside; one at 00:00
 *      on day 64 is outside), scores; the whole status in weekly_status.
 *   4. From day 71 the parts not submitted get a `missed` record; AIMHS
 *      (optional) never; a declined AIMHS still counts as complete.
 *   5. Day 60 10:00: one e-mail per day with the research IDs and the
 *      study day of whoever is not done — nothing else.
 *   6. Both arms: the same pushes at the same study day and hour; zero
 *      model calls (no fetch, no llm_calls row).
 *   7. weeklyPushHour moves the push hour; the dashboard cell and
 *      tool/w8_dates.js read the same state.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/w8_questionnaire_emulator_test.js"
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

// Zero model calls: any outgoing request fails the test.
const outgoing = [];
global.fetch = async (url) => {
  outgoing.push(String(url));
  throw new Error(`unexpected fetch ${url}`);
};

require("../index"); // initialises firebase-admin
const admin = require("firebase-admin");
const w8 = require("../w8_questionnaire");
const sw = require("../study_week");
const sp = require("../study_period");
const piAlert = require("../pi_alert");
const ops = require("../ops_dashboard");
const dates = require("../../tool/w8_dates");

const db = admin.firestore();
const ts = (d) => admin.firestore.Timestamp.fromDate(d);
const silent = () => {};

const PRIMARY = "lead@test.invalid";
const SMTP = {host: "smtp.test.invalid", user: "sender@test.invalid",
  pass: "x", piEmail: ""};
const mails = [];
piAlert.setMailerForTests(async (msg) => {
  mails.push(msg);
});
piAlert.setAuthForTests({
  getUserByEmail: async (addr) => {
    if (addr === PRIMARY) return {customClaims: {role: "unblinded"}};
    const e = new Error("not found");
    e.code = "auth/user-not-found";
    throw e;
  },
});

// The HK instant `hour:min:sec` of study day `day` for W0 `w0`.
function at(w0, day, hour, min, sec) {
  const key = sw.addDays(w0, day);
  const p = (n) => String(n || 0).padStart(2, "0");
  return new Date(`${key}T${p(hour)}:${p(min)}:${p(sec)}+08:00`);
}

// The synthetic people.  `do`: what they answer and when (study day,
// hour, minute, second).
const MON = "2026-10-19";
const PEOPLE = [
  {uid: "mon_a", rid: "RCT-41", arm: "A", cohort: sp.COHORT_RCT, w0: MON,
    do: {parts: 5, day: 57, h: 15, aimhs: "submitted"}},
  {uid: "mon_b", rid: "RCT-48", arm: "B", cohort: sp.COHORT_RCT, w0: MON,
    do: {parts: 5, day: 57, h: 15, aimhs: "declined"}},
  {uid: "tue", rid: "RCT-42", arm: "B", cohort: sp.COHORT_RCT,
    w0: "2026-10-20", do: null},
  {uid: "wed", rid: "PB-43", arm: "A", cohort: sp.COHORT_RUN_IN,
    w0: "2026-10-21", do: null},
  {uid: "thu", rid: "PB-44", arm: "B", cohort: sp.COHORT_RUN_IN,
    w0: "2026-10-22", do: {parts: 3, day: 56, h: 11}},
  {uid: "fri", rid: "PILOT-45", arm: "A", cohort: sp.COHORT_PILOT,
    w0: "2026-10-23", do: {parts: 3, day: 56, h: 11}},
  {uid: "sat", rid: "PILOT-46", arm: "B", cohort: sp.COHORT_PILOT,
    w0: "2026-10-24", do: {parts: 5, day: 63, h: 23, m: 59, s: 30}},
  {uid: "sun", rid: "RCT-47", arm: "A", cohort: sp.COHORT_RCT,
    w0: "2026-10-25", do: {parts: 5, day: 64, h: 0}},
  {uid: "sun2", rid: "RCT-49", arm: "B", cohort: sp.COHORT_RCT,
    w0: "2026-10-25", do: {parts: 5, day: 60, h: 9}},
];
const NOBODY = [
  {uid: "tester", arm: "B", cohort: sp.COHORT_RCT, isTester: true, w0: MON},
  {uid: "sw", arm: "A", cohort: sp.COHORT_PILOT, isTester: true,
    armAssignedBy: "tester_switch", w0: MON},
  {uid: "unreg", arm: "B", w0: MON},
];

function fakeMessaging() {
  const sent = [];
  return {sent, send: async (msg) => {
    sent.push(msg);
    return `id-${sent.length}`;
  }};
}

async function reset() {
  for (const p of ["users", "app_config", "weekly_status", "research_id_map",
    "alert_audit_log", "meta", "llm_calls"]) {
    await db.recursiveDelete(db.collection(p));
  }
  mails.length = 0;
  await db.doc("meta/alert_config").set({enabled: true,
    primaryEmail: PRIMARY});
  // A global quiet window over 10:00: W8 must ignore it.
  await db.doc("app_config/reminders").set({quietHoursStart: "09:00",
    quietHoursEnd: "11:00"});
}

async function seed(p) {
  const data = {createdAt: "2026-09-01T09:00:00.000", arm: p.arm,
    w0Date: p.w0, armAssignmentMode: "randomise"};
  if (p.cohort) data.cohort = p.cohort;
  if (p.isTester) data.isTester = true;
  if (p.armAssignedBy) data.armAssignedBy = p.armAssignedBy;
  await db.doc(`users/${p.uid}`).set(data);
  await db.doc(`users/${p.uid}/fcm_tokens/dev1`).set({token: `tok-${p.uid}`});
  if (p.rid) await db.doc(`research_id_map/${p.uid}`).set({researchId: p.rid});
}

const ANSWERS = {
  djg: {q1: "yes", q2: "mostly", q3: "no", q4: "no", q5: "skipped",
    q6: "yes"},
  ucla3: {q1: 2, q2: 3, q3: 1},
  ci: {q1: 4, q2: 5, q3: "skipped"},
  lsns6: {q1: 2, q2: 1, q3: 0, q4: 5, q5: 3, q6: 4},
  aimhs: {q1: 1, q2: 2, q3: 3, q4: 4, q5: 5},
};

// The App's records of the first n of the five parts (plus AIMHS when
// `aimhs` says so), then what the trigger does.
async function answer(uid, n, when, aimhs) {
  const specs = w8.PARTS.slice(0, n);
  if (aimhs) specs.push(w8.AIMHS);
  for (const p of specs) {
    const ref = db.doc(`users/${uid}/${p.collection}/W8`);
    const before = (await ref.get()).data() || null;
    let rec;
    if (p.id === "aimhs" && aimhs === "declined") {
      rec = {timepoint: "W8", bundle: "W8", itemsVersion: "aimhs_w8_v1",
        answers: {}, status: "declined", declinedAt: ts(when)};
    } else if (p.id === "pgic") {
      rec = {bundle: "W8", itemsVersion: "pgic_w8_v1", value: 3,
        answeredAt: ts(when), status: "submitted", submittedAt: ts(when)};
    } else {
      const answeredAt = {};
      for (const k of Object.keys(ANSWERS[p.id])) answeredAt[k] = ts(when);
      rec = {timepoint: "W8", bundle: "W8", itemsVersion: "x",
        answers: ANSWERS[p.id], answeredAt, status: "submitted",
        startedAt: ts(when), submittedAt: ts(when)};
    }
    await ref.set(rec, {merge: true});
    const after = (await ref.get()).data();
    await w8.stampW8Part(db, uid, p.collection, "W8", before, after,
        {now: when});
  }
}

const rec = async (uid, col) =>
  (await db.doc(`users/${uid}/${col}/W8`).get()).data() || null;
const status = async (uid) => {
  const s = await db.doc(`weekly_status/${uid}`).get();
  return s.exists ? ((s.get("bundles") || {}).W8 || null) : null;
};

const tests = [];
const test = (name, fn) => tests.push({name, fn});

let m;

test("hourly simulation: days 55–72 for every W0 weekday", async () => {
  await reset();
  for (const p of PEOPLE.concat(NOBODY)) await seed(p);
  m = fakeMessaging();
  const actions = [];
  for (const p of PEOPLE) {
    if (!p.do) continue;
    actions.push({when: at(p.w0, p.do.day, p.do.h, p.do.m, p.do.s),
      run: async (when) => answer(p.uid, p.do.parts, when, p.do.aimhs)});
  }
  actions.sort((a, b) => a.when - b.when);
  const from = sw.addDays(MON, 55);
  const to = sw.addDays("2026-10-25", 72);
  for (let key = from; key <= to; key = sw.addDays(key, 1)) {
    for (let h = 0; h < 24; h++) {
      const now = new Date(`${key}T${String(h).padStart(2, "0")}:00:00+08:00`);
      while (actions.length && actions[0].when <= now) {
        const a = actions.shift();
        await a.run(a.when);
      }
      await w8.dispatchW8(db, m, {now, log: silent});
      await w8.sendIncompleteEmail(db, {now, smtp: SMTP, auth: null});
    }
  }
  assert.strictEqual(actions.length, 0);
});

test("pushes: day 56 to all, day 58 / 60 only to the not-done, at 10:00",
    async () => {
      const byToken = {};
      for (const msg of m.sent) {
        const uid = msg.token.replace(/^tok-/, "");
        (byToken[uid] = byToken[uid] || []).push(msg);
      }
      for (const msg of m.sent) {
        assert.strictEqual(msg.notification.title, "陪住");
        assert.strictEqual(msg.notification.body,
            "最後一份問卷開咗，請喺一個禮拜內入嚟答埋佢。多謝你！");
      }
      const expected = {
        mon_a: [[56, "w8_open"]], mon_b: [[56, "w8_open"]],
        tue: [[56, "w8_open"], [58, "w8_reminder"], [60, "w8_reminder"]],
        wed: [[56, "w8_open"], [58, "w8_reminder"], [60, "w8_reminder"]],
        thu: [[56, "w8_open"], [58, "w8_reminder"], [60, "w8_reminder"]],
        fri: [[56, "w8_open"], [58, "w8_reminder"], [60, "w8_reminder"]],
        sat: [[56, "w8_open"], [58, "w8_reminder"], [60, "w8_reminder"]],
        sun: [[56, "w8_open"], [58, "w8_reminder"], [60, "w8_reminder"]],
        sun2: [[56, "w8_open"], [58, "w8_reminder"]],
      };
      for (const p of PEOPLE) {
        const ev = await db.collection(`users/${p.uid}/events`)
            .where("source", "==", "cf_w8Dispatch").get();
        const sent = ev.docs.map((d) => d.data())
            .filter((e) => /_sent$/.test(e.name))
            .map((e) => {
              const when = e.timestamp.toDate();
              assert.strictEqual(sw.hkHour(when), 10, `${p.uid} at 10:00`);
              assert.strictEqual(when.getUTCMinutes(), 0);
              return [sw.studyDayAt(p.w0, when), e.name.replace(/_sent$/, "")];
            })
            .sort((a, b) => a[0] - b[0]);
        assert.deepStrictEqual(sent, expected[p.uid], p.uid);
        assert.deepStrictEqual((byToken[p.uid] || []).map((x) => x.data.kind),
            expected[p.uid].map((x) => x[1]), `${p.uid} FCM`);
      }
      for (const p of NOBODY) {
        assert.strictEqual(byToken[p.uid], undefined, `${p.uid}: no push`);
        assert.strictEqual(await status(p.uid), null, `${p.uid}: no status`);
      }
      assert.strictEqual(m.sent.length, 2 + 6 * 3 + 2);
    });

test("both arms: same pushes on the same study day and hour", async () => {
  const seq = async (p) => {
    const ev = await db.collection(`users/${p.uid}/events`)
        .where("source", "==", "cf_w8Dispatch").get();
    return ev.docs.map((d) => d.data()).filter((e) => /_sent$/.test(e.name))
        .map((e) => `${sw.studyDayAt(p.w0, e.timestamp.toDate())}@` +
          `${sw.hkHour(e.timestamp.toDate())}:${e.name}`).sort();
  };
  const by = (uid) => PEOPLE.find((p) => p.uid === uid);
  for (const [a, b] of [["mon_a", "mon_b"], ["wed", "tue"], ["fri", "thu"]]) {
    assert.strictEqual(by(a).arm, "A");
    assert.strictEqual(by(b).arm, "B");
    assert.deepStrictEqual(await seq(by(a)), await seq(by(b)), `${a}/${b}`);
  }
});

test("stamps: studyWeek 8, studyDay 56, outOfWindow by the window, scores",
    async () => {
      const mon = await rec("mon_a", "djg_responses");
      assert.strictEqual(mon.studyWeek, 8);
      assert.strictEqual(mon.studyDay, 56);
      assert.strictEqual(mon.submittedStudyDay, 57);
      assert.strictEqual(mon.outOfWindow, false);
      assert.deepStrictEqual(mon.scores, {emotional: 2, social: null,
        total: null});
      assert.strictEqual((await rec("mon_a", "ucla3_responses")).scores.total,
          6);
      assert.deepStrictEqual((await rec("mon_a", "lsns6_responses")).scores,
          {family: 3, friends: 12, total: 15});
      assert.strictEqual((await rec("mon_a", "ci_responses")).scores,
          undefined);
      assert.strictEqual((await rec("mon_a", "aimhs_responses")).scores,
          undefined);
      // 23:59:30 on day 63: inside.  00:00 on day 64: outside.
      for (const p of w8.PARTS) {
        const s = await rec("sat", p.collection);
        assert.strictEqual(s.outOfWindow, false, `sat ${p.id}`);
        assert.strictEqual(s.submittedStudyDay, 63);
        const u = await rec("sun", p.collection);
        assert.strictEqual(u.outOfWindow, true, `sun ${p.id}`);
        assert.strictEqual(u.submittedStudyDay, 64);
        assert.strictEqual(u.studyWeek, 8);
      }
      const sat = await status("sat");
      assert.strictEqual(sat.status, "completed");
      assert.strictEqual(sat.completedOutOfWindow, false);
      const sun = await status("sun");
      assert.strictEqual(sun.status, "completed");
      assert.strictEqual(sun.completedOutOfWindow, true);
      // Idempotent: stamping again writes nothing.
      const after = await rec("sun", "ci_responses");
      assert.strictEqual(await w8.stampW8Part(db, "sun", "ci_responses", "W8",
          after, after, {now: new Date()}), null);
    });

test("a draft is stamped once, the submission later", async () => {
  const w0 = "2026-10-22";
  const when = at(w0, 57, 9);
  const ref = db.doc("users/thu/aimhs_responses/W8");
  await ref.set({timepoint: "W8", bundle: "W8", itemsVersion: "x",
    answers: {q1: 2}, answeredAt: {q1: ts(when)}, status: "in_progress"});
  const draft = (await ref.get()).data();
  const s1 = await w8.stampW8Part(db, "thu", "aimhs_responses", "W8", null,
      draft, {now: when});
  assert.strictEqual(s1.studyWeek, 8);
  assert.strictEqual(s1.outOfWindow, undefined);
  assert.strictEqual((await status("thu")).aimhs, "in_progress");
  const later = at(w0, 58, 9);
  await ref.set({answers: {q1: 2, q2: 3, q3: "skipped", q4: 1, q5: 5},
    status: "submitted", submittedAt: ts(later)}, {merge: true});
  const s2 = await w8.stampW8Part(db, "thu", "aimhs_responses", "W8", draft,
      (await ref.get()).data(), {now: later});
  assert.strictEqual(s2.outOfWindow, false);
  assert.strictEqual(s2.submittedStudyDay, 58);
  assert.strictEqual(s2.studyWeek, undefined, "base stamp written once");
  assert.strictEqual((await status("thu")).aimhs, "submitted");
  assert.strictEqual((await status("thu")).status, "in_progress",
      "AIMHS never completes W8");
});

test("from day 71: missed records for the parts not submitted; AIMHS " +
    "never; final status", async () => {
  for (const uid of ["tue", "wed"]) {
    for (const p of w8.PARTS) {
      const r = await rec(uid, p.collection);
      assert.strictEqual(r.status, "missed", `${uid} ${p.id}`);
      assert.strictEqual(r.missed, true);
      assert.strictEqual(r.studyWeek, 8);
    }
    assert.strictEqual(await rec(uid, "aimhs_responses"), null);
    const s = await status(uid);
    assert.ok(s.closedAt);
    assert.strictEqual(s.status, "not_started");
    assert.deepStrictEqual(s.missedParts,
        ["djg", "ucla3", "pgic", "ci", "lsns6"]);
  }
  for (const uid of ["thu", "fri"]) {
    assert.deepStrictEqual((await status(uid)).missedParts, ["ci", "lsns6"]);
    assert.strictEqual((await rec(uid, "djg_responses")).status, "submitted");
  }
  for (const uid of ["mon_a", "mon_b", "sat", "sun", "sun2"]) {
    const s = await status(uid);
    assert.strictEqual(s.status, "completed", uid);
    assert.deepStrictEqual(s.missedParts, [], uid);
    assert.ok(s.completedAt);
  }
  // A declined AIMHS: W8 complete all the same.
  assert.strictEqual((await status("mon_b")).aimhs, "declined");
  assert.strictEqual((await status("mon_a")).aimhs, "submitted");
});

test("day-60 e-mail: research ID and study day of the not-done, once a day",
    async () => {
      const lines = mails.map((x) => x.text.split("\n")
          .filter((l) => l.includes(" ｜ 第 ")));
      assert.deepStrictEqual(lines, [
        ["RCT-42 ｜ 第 60 天"],
        ["PB-43 ｜ 第 60 天"],
        ["PB-44 ｜ 第 60 天"],
        ["PILOT-45 ｜ 第 60 天"],
        ["PILOT-46 ｜ 第 60 天"],
        ["RCT-47 ｜ 第 60 天"],
      ]);
      for (const x of mails) {
        assert.strictEqual(x.to, PRIMARY);
        assert.strictEqual(x.subject, w8.EMAIL_SUBJECT);
        assert.ok(x.text.split("\n")[0].includes("10:00"));
        for (const bad of ["Hybrid", "規則", "规则组", "Group_", "phase_b",
          "rct\"", "\"pilot", "mon_", "tok-", "yes", "mostly"]) {
          assert.ok(!x.text.includes(bad), bad);
        }
        for (const p of PEOPLE) {
          if (x.text.includes(p.uid + " ")) assert.fail(`uid ${p.uid}`);
        }
      }
      // One audit row per day that had someone, none on the Monday (both
      // Monday people were done).
      const audit = await db.collection("alert_audit_log")
          .where("type", "==", "w8_incomplete_email").get();
      assert.strictEqual(audit.size, 6);
      for (const d of audit.docs) assert.strictEqual(d.get("status"), "sent");
      assert.ok(!(await db.doc(`alert_audit_log/${w8.AUDIT_PREFIX}` +
        "2026-12-18").get()).exists, "Monday's day 60: nobody, no e-mail");
    });

test("zero model calls: no request left, no llm_calls row", async () => {
  assert.deepStrictEqual(outgoing, []);
  assert.strictEqual((await db.collection("llm_calls").get()).size, 0);
});

test("dashboard cell and tool/w8_dates.js read the same state", async () => {
  const day = (uid, k) => sw.studyDayOf(PEOPLE.find((p) => p.uid === uid).w0,
      k);
  const end = "2027-01-06";
  assert.strictEqual(ops.w8DetailFor(await status("mon_a"),
      day("mon_a", end)).status, "done");
  assert.strictEqual(ops.w8DetailFor(await status("tue"),
      day("tue", end)).status, "missed");
  const sun = ops.w8DetailFor(await status("sun"), day("sun", end));
  assert.deepStrictEqual([sun.status, sun.partsSubmitted, sun.parts,
    sun.completedOutOfWindow, sun.optionalPart], ["done", 5, 5, true, null]);
  assert.ok(!JSON.stringify(sun).includes("answers"));
  // The App build of two people.
  await db.doc("users/mon_a").set({appBuild: {version: "1.0.0", build: "3",
    w8: true, platform: "android", seenAt: ts(new Date())}}, {merge: true});
  const rows = await dates.collect(db, {now: at(MON, 50, 12)});
  assert.deepStrictEqual(rows.map((r) => [r.researchId, r.d56]), [
    ["RCT-41", "2026-12-14"], ["RCT-48", "2026-12-14"],
    ["RCT-42", "2026-12-15"], ["PB-43", "2026-12-16"],
    ["PB-44", "2026-12-17"], ["PILOT-45", "2026-12-18"],
    ["PILOT-46", "2026-12-19"], ["RCT-47", "2026-12-20"],
    ["RCT-49", "2026-12-20"]]);
  const r41 = rows[0];
  assert.deepStrictEqual([r41.w0, r41.d58, r41.d60, r41.d63, r41.d70],
      ["2026-10-19", "2026-12-16", "2026-12-18", "2026-12-21",
        "2026-12-28"]);
  assert.strictEqual(r41.hasW8Build, true);
  assert.strictEqual(rows[1].hasW8Build, false);
  const text = dates.format(rows, {});
  assert.ok(text.includes("共 9 人；App 还没有报告 W8 版本的 8 人"));
  for (const bad of ["tester", "unreg", "\"A\"", "Hybrid", "rct",
    "phase_b"]) {
    assert.ok(!text.includes(bad), bad);
  }
});

test("weeklyPushHour moves the push hour (here 09:00)", async () => {
  await reset();
  await db.doc("app_config/phase_b").set({weeklyPushHour: 9});
  const p = PEOPLE[0];
  await seed(p);
  const mm = fakeMessaging();
  for (const h of [8, 9, 10]) {
    await w8.dispatchW8(db, mm, {now: at(p.w0, 56, h), log: silent});
    assert.strictEqual(mm.sent.length, h < 9 ? 0 : 1, `hour ${h}`);
  }
  assert.ok((await status(p.uid)).pushedAt.toDate().getTime() ===
    at(p.w0, 56, 9).getTime());
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`PASS  ${t.name}`);
    } catch (err) {
      failed++;
      console.log(`FAIL  ${t.name}\n      ${err.stack}`);
    }
  }
  console.log(`\n${tests.length - failed} passed, ${failed} failed.`);
  process.exit(failed ? 1 : 0);
})();
