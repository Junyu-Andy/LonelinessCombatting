/**
 * T17b — pure parts of functions/ada.js (decision 0030): config parse,
 * reminder time, Phase A test, day-7 status.
 *   cd functions && node test/ada_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const ada = require("../ada");

const cases = [];
const test = (name, fn) => cases.push({name, fn});

test("defaults: both parts off, window 7–9, 10:00, 24 h", () => {
  const c = ada.configFromData({});
  assert.strictEqual(c.adaEnabled, false);
  assert.strictEqual(c.openEnabled, false);
  assert.deepStrictEqual([c.dayFrom, c.dayTo], [7, 9]);
  assert.strictEqual(c.reminderTime, "10:00");
  assert.strictEqual(c.reminderHours, 24);
  assert.deepStrictEqual(ada.day7Parts(c), []);
});

test("only literal true turns a part on", () => {
  assert.deepStrictEqual(ada.day7Parts(ada.configFromData(
      {adaEnabled: "true", day7OpenEndedEnabled: 1})), []);
  assert.deepStrictEqual(ada.day7Parts(ada.configFromData(
      {adaEnabled: true, day7OpenEndedEnabled: true})), ["ada", "open"]);
});

test("window follows the day7 timepoint; no day7 timepoint → no ADA part",
    () => {
      const c = ada.configFromData({adaEnabled: true, adaTimepoints: [
        {id: "visit1", form: "short", dayFrom: 1, dayTo: 1},
        {id: "day7", form: "full", dayFrom: 8, dayTo: 12},
      ]});
      assert.deepStrictEqual([c.dayFrom, c.dayTo], [8, 12]);
      assert.deepStrictEqual(ada.day7Parts(c), ["ada"]);
      const none = ada.configFromData({adaEnabled: true,
        day7OpenEndedEnabled: true,
        adaTimepoints: [{id: "visit1", form: "short", dayFrom: 1, dayTo: 1}]});
      assert.deepStrictEqual(ada.day7Parts(none), ["open"]);
    });

test("reminder time: HH:00 between 08 and 21 only", () => {
  assert.strictEqual(ada.parseReminderTime("19:00"), 19);
  assert.strictEqual(ada.parseReminderTime("08:00"), 8);
  assert.strictEqual(ada.parseReminderTime("21:00"), 21);
  for (const bad of ["07:00", "22:00", "19:30", "7:00", "", null, 19]) {
    assert.strictEqual(ada.parseReminderTime(bad), null, String(bad));
  }
  const c = ada.configFromData({adaDay7ReminderDefaultTime: "23:00"});
  assert.strictEqual(c.reminderTime, "10:00");
  assert.strictEqual(ada.pushHourFor({day7ReminderTime: "17:00"}, c), 17);
  assert.strictEqual(ada.pushHourFor({day7ReminderTime: "skipped"}, c), 10);
  assert.strictEqual(ada.pushHourFor(null, c), 10);
});

test("Phase A participant", () => {
  assert.strictEqual(ada.isPhaseAParticipant({cohort: "phase_a"}), true);
  assert.strictEqual(ada.isPhaseAParticipant({cohort: "phase_b",
    arm: "A"}), false);
  assert.strictEqual(ada.isPhaseAParticipant({cohort: "pilot"}), false);
  assert.strictEqual(ada.isPhaseAParticipant({arm: "A"}), true);
  assert.strictEqual(ada.isPhaseAParticipant({arm: "B",
    armAssignmentMode: "randomise"}), false);
});

test("status: not started / in progress / completed / overdue", () => {
  const c = ada.configFromData({adaEnabled: true,
    day7OpenEndedEnabled: true});
  const parts = ada.day7Parts(c);
  const S = ada.STATUS;
  const st = (docs, day) => ada.day7Status(parts, docs, day, c);
  assert.strictEqual(st({ada: null, open: null}, 7).status, S.notStarted);
  assert.strictEqual(st({ada: {status: "in_progress"}, open: null}, 8)
      .status, S.inProgress);
  assert.strictEqual(st({ada: {status: "submitted"}, open: null}, 9)
      .status, S.inProgress);
  const done = st({ada: {status: "submitted", channel: "app"},
    open: {status: "submitted"}}, 9);
  assert.deepStrictEqual(done, {status: S.completed, partial: false,
    channel: "app"});
  const late = st({ada: {status: "submitted"}, open: null}, 10);
  assert.deepStrictEqual(late, {status: S.overdue, partial: true,
    channel: null});
  assert.strictEqual(st({ada: null, open: null}, 10).partial, false);
  const phone = st({ada: {status: "submitted", channel: "phone_by_staff"},
    open: {status: "submitted", channel: "phone_by_staff"}}, 12);
  assert.strictEqual(phone.status, S.completed);
  assert.strictEqual(phone.channel, "phone_by_staff");
});

test("staff role check", () => {
  assert.throws(() => ada.assertStaff(null), /researcher role/);
  assert.throws(() => ada.assertStaff({uid: "x", token: {}}),
      /researcher role/);
  assert.strictEqual(ada.assertStaff({uid: "x", token: {role: "pi"}}), "pi");
  assert.strictEqual(ada.assertStaff({uid: "x",
    token: {role: "researcher"}}), "researcher");
});

test("free texts found for the safety scan", () => {
  assert.deepStrictEqual(ada.freeTexts("ada_responses",
      {freeText: " 小欣好好 "}), {ada_free_text: "小欣好好"});
  assert.deepStrictEqual(ada.freeTexts("day7_open_responses",
      {answers: {q1: {text: "a"}, q2: {text: null}, q3: {text: " "}}}),
  {"day7_open_ended:q1": "a"});
});

test("draft push copy is a placeholder (server sends nothing)", () => {
  const djg = require("../djg_w2");
  assert.strictEqual(djg.isPlaceholder(ada.PUSH_BODY), true);
  assert.strictEqual(djg.isPlaceholder(ada.REMINDER_BODY), true);
});

let failed = 0;
for (const c of cases) {
  try {
    c.fn();
    console.log(`ok - ${c.name}`);
  } catch (err) {
    failed++;
    console.error(`not ok - ${c.name}\n${err.stack}`);
  }
}
if (failed) process.exit(1);
console.log(`all ${cases.length} ada unit tests passed`);
