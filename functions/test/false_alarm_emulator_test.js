/**
 * 1020e 二.9 — markSafetyFalseAlarm (functions/false_alarm.js): the
 * dashboard's 「標記誤觸」.  Synthetic data only.
 *
 *   - only role `unblinded`, only with the switch
 *     app_config/feature_flags.safetyFalseAlarmMarkEnabled;
 *   - stamps falseAlarm / markedBy / markedAt on the safety event and the
 *     alert, and on that day's stopped chat check-in row (same Hong Kong
 *     date, same session) — not on other rows, other days, other people;
 *   - a second call changes nothing and reports alreadyMarked.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/false_alarm_emulator_test.js"
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

const fns = require("../index");
const falseAlarm = require("../false_alarm");
const admin = require("firebase-admin");
const db = admin.firestore();
const {Timestamp} = admin.firestore;

const RESEARCHER = {uid: "r1", token: {role: "unblinded", email: "r@x.hk"}};
// 2026-10-21 01:30 UTC = 09:30 Hong Kong.
const AT = Timestamp.fromDate(new Date("2026-10-21T01:30:00Z"));
// 2026-10-20 17:30 UTC = 2026-10-21 01:30 Hong Kong (date by HK, not UTC).
const LATE = Timestamp.fromDate(new Date("2026-10-20T17:30:00Z"));

const call = (auth, data) => fns.markSafetyFalseAlarm.run({
  auth: auth,
  data: data || {alertId: "A1"},
});

async function rejects(p, code, label) {
  await assert.rejects(p, (err) => {
    assert.strictEqual(err.code, code, `${label}: ${err.code} ${err.message}`);
    return true;
  });
}

const row = (uid, id) => db.doc(`users/${uid}/check_in_responses/${id}`);

async function seed() {
  await db.doc("app_config/feature_flags").set(
      {safetyFalseAlarmMarkEnabled: true});
  await db.doc("safety_events/E1").set({uid: "u1", agentId: "siu_yan",
    sessionId: "s1", level: "acute", tier: "acute", source: "user_input",
    inputPoint: "chat_check_in", createdAt: AT});
  await db.doc("pi_alerts/A1").set({uid: "u1", level: "acute",
    eventPath: "safety_events/E1", alertVersion: 3, createdAt: AT});
  // The stopped check-in of that day and session.
  await row("u1", "ci_stop").set({flow: "chat_v2", date_iso: "2026-10-21",
    session_id: "s1", stopped_by_safety: true, completed: false});
  // Same day, not stopped / other session / older form / other day.
  await row("u1", "ci_done").set({flow: "chat_v2", date_iso: "2026-10-21",
    session_id: "s0", stopped_by_safety: false, completed: true});
  await row("u1", "ci_other_session").set({flow: "chat_v2",
    date_iso: "2026-10-21", session_id: "s9", stopped_by_safety: true,
    completed: false});
  await row("u1", "ci_old_form").set({arm: "B", date_iso: "2026-10-21",
    mood: 2});
  await row("u1", "ci_yesterday").set({flow: "chat_v2",
    date_iso: "2026-10-20", session_id: "s1", stopped_by_safety: true,
    completed: false});
  await row("u2", "ci_someone_else").set({flow: "chat_v2",
    date_iso: "2026-10-21", session_id: "s1", stopped_by_safety: true,
    completed: false});
}

async function main() {
  await seed();

  // Role checks.
  await rejects(call(null), "unauthenticated", "no auth");
  await rejects(call({uid: "u1", token: {}}), "permission-denied",
      "participant");
  await rejects(call({uid: "b1", token: {role: "blinded"}}),
      "permission-denied", "blinded assessor");
  await rejects(call({uid: "s1", token: {role: "sequence_uploader"}}),
      "permission-denied", "sequence uploader");
  assert.strictEqual((await db.doc("safety_events/E1").get())
      .get("falseAlarm"), undefined, "nothing written by refused calls");
  console.log("ok  only role unblinded");

  // Switch off → refused.
  await db.doc("app_config/feature_flags").set(
      {safetyFalseAlarmMarkEnabled: "true"});
  await rejects(call(RESEARCHER), "failed-precondition", "switch off");
  await db.doc("app_config/feature_flags").set(
      {safetyFalseAlarmMarkEnabled: true});
  console.log("ok  switch off (not literally true) → refused");

  await rejects(call(RESEARCHER, {}), "invalid-argument", "no alert id");
  await rejects(call(RESEARCHER, {alertId: "a/b"}), "invalid-argument",
      "path id");
  await rejects(call(RESEARCHER, {alertId: "NOPE"}), "not-found",
      "missing alert");
  console.log("ok  bad / missing alert id");

  const out = await call(RESEARCHER);
  assert.deepStrictEqual(
      {ok: out.ok, already: out.alreadyMarked, path: out.eventPath,
        stamped: out.checkInStamped},
      {ok: true, already: false, path: "safety_events/E1", stamped: 1});
  for (const path of ["safety_events/E1", "pi_alerts/A1",
    "users/u1/check_in_responses/ci_stop"]) {
    const d = (await db.doc(path).get()).data();
    assert.strictEqual(d.falseAlarm, true, path);
    assert.strictEqual(d.markedBy, "r1", path);
    assert.ok(d.markedAt && typeof d.markedAt.toDate === "function", path);
  }
  const ev = (await db.doc("safety_events/E1").get()).data();
  assert.strictEqual(ev.level, "acute", "level unchanged");
  const stop = (await row("u1", "ci_stop").get()).data();
  assert.strictEqual(stop.stopped_by_safety, true, "stop kept");
  assert.strictEqual(stop.completed, false, "completed unchanged");
  for (const [uid, id] of [["u1", "ci_done"], ["u1", "ci_other_session"],
    ["u1", "ci_old_form"], ["u1", "ci_yesterday"],
    ["u2", "ci_someone_else"]]) {
    assert.strictEqual((await row(uid, id).get()).get("falseAlarm"),
        undefined, `${uid}/${id} untouched`);
  }
  const audit = await db.collection("alert_audit_log")
      .where("type", "==", "false_alarm_marked").get();
  assert.strictEqual(audit.size, 1);
  assert.strictEqual(audit.docs[0].get("alertId"), "A1");
  assert.strictEqual(audit.docs[0].get("checkInStamped"), 1);
  console.log("ok  event, alert and the stopped check-in row stamped; " +
    "nothing else");

  const markedAt = ev.markedAt.toMillis();
  const again = await call({uid: "r2", token: {role: "unblinded"}});
  assert.strictEqual(again.alreadyMarked, true);
  assert.strictEqual(again.checkInStamped, 0);
  const ev2 = (await db.doc("safety_events/E1").get()).data();
  assert.strictEqual(ev2.markedBy, "r1", "first mark kept");
  assert.strictEqual(ev2.markedAt.toMillis(), markedAt);
  console.log("ok  second call: alreadyMarked, first mark kept");

  // Hong Kong date, not UTC: an event at 01:30 HK on 10/21 matches the
  // 10/21 row even though it is still 10/20 in UTC.
  await db.doc("safety_events/E2").set({uid: "u3", agentId: "siu_yan",
    sessionId: "s3", level: "acute", createdAt: LATE});
  await db.doc("pi_alerts/A2").set({uid: "u3", level: "acute",
    eventPath: "safety_events/E2"});
  await row("u3", "ci_late").set({flow: "chat_v2", date_iso: "2026-10-21",
    session_id: "s3", stopped_by_safety: true, completed: false});
  const late = await call(RESEARCHER, {alertId: "A2"});
  assert.strictEqual(late.checkInStamped, 1);
  assert.strictEqual((await row("u3", "ci_late").get()).get("falseAlarm"),
      true);
  console.log("ok  matched by Hong Kong date");

  // An event from another companion never stamps a check-in row.
  await db.doc("safety_events/E3").set({uid: "u4", agentId: "tung_tung",
    sessionId: "s4", level: "acute", createdAt: AT});
  await db.doc("pi_alerts/A3").set({uid: "u4", level: "acute",
    eventPath: "safety_events/E3"});
  await row("u4", "ci_x").set({flow: "chat_v2", date_iso: "2026-10-21",
    session_id: "s4", stopped_by_safety: true, completed: false});
  const tung = await call(RESEARCHER, {alertId: "A3"});
  assert.strictEqual(tung.checkInStamped, 0);
  assert.strictEqual((await db.doc("safety_events/E3").get())
      .get("falseAlarm"), true, "the event itself is still marked");
  console.log("ok  other companion: event marked, no check-in row");

  // Pure matcher.
  assert.strictEqual(falseAlarm.stoppedCheckInFor(
      {flow: "chat_v2", stopped_by_safety: true, date_iso: "2026-10-21"},
      {agentId: "siu_yan"}, "2026-10-21"), true, "no session ids: by day");
  console.log("false_alarm_emulator_test: all passed");
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
