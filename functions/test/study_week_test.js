/**
 * T24 — study-week arithmetic (functions/study_week.js) against the shared
 * table test/fixtures/study_week_table.json, which test/study_week_test.dart
 * also reads: the App and the server must agree on every row.
 *
 * Run: cd functions && node test/study_week_test.js
 */
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const sw = require("../study_week");
const piAlert = require("../pi_alert");

const tests = [];
const test = (name, fn) => tests.push({name, fn});

const TABLE = JSON.parse(fs.readFileSync(
    path.join(__dirname, "..", "..", "test", "fixtures",
        "study_week_table.json"), "utf8"));

test("shared table: study day and week of every case", () => {
  for (const c of TABLE.cases) {
    const at = new Date(c.at);
    assert.strictEqual(sw.studyDayAt(c.w0, at), c.day, c.name);
    assert.strictEqual(sw.studyWeekAt(c.w0, at), c.week, c.name);
    assert.deepStrictEqual(sw.studyPositionAt(c.w0, at),
        {studyDay: c.day, studyWeek: c.week}, c.name);
  }
});

test("boundaries: days 0, 1, 7, 8, 28, 29 → weeks 0, 1, 1, 2, 4, 5", () => {
  const expect = {0: 0, 1: 1, 7: 1, 8: 2, 14: 2, 15: 3, 28: 4, 29: 5, 56: 8};
  for (const d of Object.keys(expect)) {
    assert.strictEqual(sw.studyWeekOf(Number(d)), expect[d], `day ${d}`);
  }
  assert.strictEqual(sw.studyWeekOf(-3), 0);
  assert.strictEqual(sw.studyWeekOf(NaN), 0);
});

test("unknown W0 → null, bad instants → null", () => {
  const at = new Date("2026-10-20T02:30:00Z");
  assert.strictEqual(sw.studyDayAt(null, at), null);
  assert.strictEqual(sw.studyDayAt("20261019", at), null);
  assert.strictEqual(sw.studyDayAt("2026-10-19", new Date("x")), null);
  assert.strictEqual(sw.studyWeekAt(undefined, at), null);
});

test("w0DateKey: registered date wins, createdAt is the fallback", () => {
  assert.strictEqual(sw.w0DateKey({w0Date: "2026-10-19",
    createdAt: "2026-09-01T10:00:00"}), "2026-10-19");
  assert.strictEqual(sw.w0DateKey({createdAt: "2026-09-01T10:00:00"}),
      "2026-09-01");
  assert.strictEqual(sw.w0DateKey({createdAt: new Date("2026-09-01T17:00:00Z")}),
      "2026-09-02"); // 01:00 HKT next day
  assert.strictEqual(sw.w0DateKey({}), null);
  assert.strictEqual(sw.w0DateKey(null), null);
});

test("instants: hkInstant / hkEndOfDay / addDays", () => {
  assert.strictEqual(sw.hkInstant("2026-10-26", 20).toISOString(),
      "2026-10-26T12:00:00.000Z");
  assert.strictEqual(sw.hkEndOfDay("2026-11-17").toISOString(),
      "2026-11-17T16:00:00.000Z"); // 2026-11-18 00:00 HKT
  assert.strictEqual(sw.addDays("2026-12-28", 7), "2027-01-04");
  assert.strictEqual(sw.daysBetween("2026-10-19", "2026-11-17"), 29);
});

test("pi_alert.studyDay now uses the shared function (T34 cases)", () => {
  const AT = new Date("2026-10-20T02:30:00Z");
  assert.strictEqual(piAlert.studyDay({w0Date: "2026-10-20"}, AT), 0);
  assert.strictEqual(piAlert.studyDay({w0Date: "2026-10-13"}, AT), 7);
  assert.strictEqual(piAlert.studyDay({w0Date: "2026-10-19"}, AT),
      sw.studyDayAt("2026-10-19", AT));
  // Unregistered account stays "unknown" — no createdAt fallback there.
  assert.strictEqual(piAlert.studyDay({createdAt: "2026-10-01"}, AT), null);
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
    console.log(`${failed} study_week test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} study_week tests passed`);
})();
