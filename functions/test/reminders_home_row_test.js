/**
 * 1020m 第二节 — functions/reminders.js, the pure part of page 1's
 * small-action row check: homeRowCheck() and fireAtOnDay().
 *
 * Run: cd functions && node test/reminders_home_row_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const reminders = require("../reminders");

const tests = [];
const test = (name, fn) => tests.push({name, fn});

const at = (s) => reminders.parseFireAt(s);

test("fireAtOnDay keeps the Hong Kong clock time, App string format", () => {
  assert.strictEqual(
      reminders.fireAtOnDay(at("2026-10-21T18:05:30.250"), "2026-10-22"),
      "2026-10-22T18:05:30.250");
  // Just after midnight HK = the previous UTC day.
  assert.strictEqual(
      reminders.fireAtOnDay(at("2026-10-21T00:30:00.000"), "2026-11-01"),
      "2026-11-01T00:30:00.000");
  // A UTC string (Z) is read as UTC, written back as HK wall time.
  assert.strictEqual(
      reminders.fireAtOnDay(at("2026-10-21T01:30:00.000Z"), "2026-10-22"),
      "2026-10-22T09:30:00.000");
});

test("a plan the row never touched: nothing", () => {
  assert.deepStrictEqual(
      reminders.homeRowCheck({action: "x"}, at("2026-10-21T09:30:00.000")),
      {});
  assert.deepStrictEqual(
      reminders.homeRowCheck(null, at("2026-10-21T09:30:00.000")), {});
});

test("first 改日: the plan's new day is later → move there", () => {
  const plan = {homeRowStatus: "later", homeRowAnsweredDate: "2026-10-21",
    homeRowLaterCount: 1, homeRowDueDate: "2026-10-22"};
  assert.deepStrictEqual(
      reminders.homeRowCheck(plan, at("2026-10-21T09:30:00.000")),
      {moveTo: "2026-10-22T09:30:00.000"});
  // Already moved by the App: send on the new day.
  assert.deepStrictEqual(
      reminders.homeRowCheck(plan, at("2026-10-22T09:30:00.000")), {});
});

test("second 改日 (or any row answer that day) → skip", () => {
  const plan = {homeRowStatus: "later", homeRowAnsweredDate: "2026-10-22",
    homeRowLaterCount: 2, homeRowDueDate: "2026-10-22"};
  assert.deepStrictEqual(
      reminders.homeRowCheck(plan, at("2026-10-22T09:30:00.000")),
      {skip: true});
  // Answered before the reminder's day: not this day's answer.
  assert.deepStrictEqual(reminders.homeRowCheck(
      {homeRowAnsweredDate: "2026-10-20"}, at("2026-10-22T09:30:00.000")),
  {});
});

test("malformed day strings are ignored", () => {
  assert.deepStrictEqual(reminders.homeRowCheck(
      {homeRowDueDate: "tomorrow", homeRowAnsweredDate: 20261022},
      at("2026-10-22T09:30:00.000")), {});
});

test("skipped_home_answered is terminal; moved_home_later is not", () => {
  const now = new Date("2026-10-22T03:00:00Z");
  const base = {kind: "m7_followup", fireAt: "2026-10-22T09:30:00.000",
    delivered: false};
  assert.strictEqual(reminders.classify(Object.assign({}, base,
      {dispatchStatus: "skipped_home_answered"}), {now, staleHours: 12}),
  "skip");
  assert.strictEqual(reminders.classify(Object.assign({}, base,
      {movedBy: "server_home_row"}), {now, staleHours: 12}), "due");
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
    console.log(`${failed} reminders_home_row test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} reminders_home_row tests passed`);
})();
