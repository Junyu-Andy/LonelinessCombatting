/**
 * T40 — functions/usage_events.js, the pure stamp: uploadedLate from the
 * gap between the phone's clock and the server's receipt, Hong Kong day,
 * study day, research ID, idempotence.
 *
 * Run: cd functions && node test/usage_events_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const UE = require("../usage_events");

const tests = [];
const test = (name, fn) => tests.push({name, fn});

const NOW = new Date("2026-10-20T04:00:00Z"); // 12:00 HKT
const USER = {w0Date: "2026-10-15", cohort: "pilot", arm: "B"};

function row(clientAt, receivedAt, extra) {
  return Object.assign({
    type: "foreground",
    clientAt: new Date(clientAt),
    receivedAt: new Date(receivedAt),
    appVersion: "1.0.0", buildNumber: "3", platform: "android",
    schemaVersion: 1,
  }, extra || {});
}

test("online row: not late, HK day, study day, research ID", () => {
  const s = UE.stampFor(
      row("2026-10-20T03:59:58Z", "2026-10-20T04:00:00Z"),
      {user: USER, researchId: "PILOT-03", now: NOW});
  assert.strictEqual(s.uploadedLate, false);
  assert.strictEqual(s.lateByMs, 2000);
  assert.strictEqual(s.clockSkew, false);
  assert.strictEqual(s.dayKey, "2026-10-20");
  assert.strictEqual(s.studyDay, 5);
  assert.strictEqual(s.researchId, "PILOT-03");
  assert.strictEqual(s.stampedAt, NOW);
});

test("offline row uploaded 40 min later: uploadedLate, clientAt kept", () => {
  const r = row("2026-10-20T03:20:00Z", "2026-10-20T04:00:00Z");
  const s = UE.stampFor(r, {user: USER, researchId: "PILOT-01", now: NOW});
  assert.strictEqual(s.uploadedLate, true);
  assert.strictEqual(s.lateByMs, 40 * 60 * 1000);
  assert.strictEqual(r.clientAt.toISOString(), "2026-10-20T03:20:00.000Z");
  assert.ok(!("clientAt" in s), "the stamp never rewrites clientAt");
});

test("boundary: exactly 5 min is not late; 5 min + 1 ms is", () => {
  const base = Date.parse("2026-10-20T04:00:00Z");
  const at = (ms) => new Date(base - ms).toISOString();
  const recv = "2026-10-20T04:00:00Z";
  assert.strictEqual(UE.stampFor(row(at(UE.LATE_AFTER_MS), recv),
      {user: USER, now: NOW}).uploadedLate, false);
  assert.strictEqual(UE.stampFor(row(at(UE.LATE_AFTER_MS + 1), recv),
      {user: USER, now: NOW}).uploadedLate, true);
});

test("Hong Kong day: 23:30 HKT is that day, 00:30 HKT the next", () => {
  const a = UE.stampFor(row("2026-10-20T15:30:00Z", "2026-10-20T15:30:01Z"),
      {user: USER, now: NOW});
  const b = UE.stampFor(row("2026-10-20T16:30:00Z", "2026-10-20T16:30:01Z"),
      {user: USER, now: NOW});
  assert.strictEqual(a.dayKey, "2026-10-20");
  assert.strictEqual(a.studyDay, 5);
  assert.strictEqual(b.dayKey, "2026-10-21");
  assert.strictEqual(b.studyDay, 6);
});

test("phone clock ahead of the server by > 5 min: clockSkew, not late", () => {
  const s = UE.stampFor(row("2026-10-20T04:10:00Z", "2026-10-20T04:00:00Z"),
      {user: USER, now: NOW});
  assert.strictEqual(s.uploadedLate, false);
  assert.strictEqual(s.clockSkew, true);
  assert.strictEqual(s.lateByMs, -10 * 60 * 1000);
});

test("no W0 (unregistered user doc) → studyDay null; no map → null id", () => {
  const s = UE.stampFor(row("2026-10-20T03:59:58Z", "2026-10-20T04:00:00Z"),
      {user: {}, researchId: null, now: NOW});
  assert.strictEqual(s.studyDay, null);
  assert.strictEqual(s.researchId, null);
  assert.strictEqual(s.dayKey, "2026-10-20");
});

test("receivedAt missing (write not yet committed): now stands in", () => {
  const r = row("2026-10-20T03:00:00Z", "2026-10-20T04:00:00Z");
  delete r.receivedAt;
  const s = UE.stampFor(r, {user: USER, now: NOW});
  assert.strictEqual(s.uploadedLate, true);
  assert.strictEqual(s.lateByMs, 60 * 60 * 1000);
});

test("already stamped, bad type, no clientAt → null (left alone)", () => {
  const ctx = {user: USER, now: NOW};
  assert.strictEqual(UE.stampFor(row("2026-10-20T03:59:58Z",
      "2026-10-20T04:00:00Z", {stampedAt: NOW}), ctx), null);
  assert.strictEqual(UE.stampFor(row("2026-10-20T03:59:58Z",
      "2026-10-20T04:00:00Z", {type: "screen_view"}), ctx), null);
  const r = row("2026-10-20T03:59:58Z", "2026-10-20T04:00:00Z");
  delete r.clientAt;
  assert.strictEqual(UE.stampFor(r, ctx), null);
  assert.strictEqual(UE.stampFor(null, ctx), null);
});

test("1020c: the four reader rows are stamped like the lifecycle rows", () => {
  assert.deepStrictEqual(UE.READER_TYPES, ["reader_open", "reader_section",
    "reader_cta", "reader_close"]);
  assert.deepStrictEqual(UE.LIFECYCLE_TYPES, ["foreground", "background"]);
  for (const type of UE.READER_TYPES) {
    const s = UE.stampFor(row("2026-10-20T03:59:58Z", "2026-10-20T04:00:00Z",
        {type, unitId: "u2_why_it_matters"}),
    {user: USER, researchId: "PILOT-03", now: NOW});
    assert.ok(s, type);
    assert.strictEqual(s.researchId, "PILOT-03", type);
    assert.strictEqual(s.studyDay, 5, type);
    assert.strictEqual(s.dayKey, "2026-10-20", type);
  }
});

test("1020m / 1020n: small-action rows are stamped like the others", () => {
  assert.deepStrictEqual(UE.HOME_SMALL_ACTION_TYPES, [
    "home_small_action_shown", "home_small_action_open",
    "home_small_action_later", "home_small_action_done",
    "home_small_action_postpone", "home_small_action_more",
    "home_small_action_list"]);
  for (const type of UE.HOME_SMALL_ACTION_TYPES) {
    assert.ok(UE.TYPES.indexOf(type) >= 0, type);
    assert.ok(UE.LIFECYCLE_TYPES.indexOf(type) < 0, type);
    const s = UE.stampFor(row("2026-10-20T03:59:58Z", "2026-10-20T04:00:00Z",
        {type, planId: "Xy7Qk2LmN0pRs3TuVw9a"}),
    {user: USER, researchId: "PB-007", now: NOW});
    assert.ok(s, type);
    assert.strictEqual(s.researchId, "PB-007", type);
    assert.strictEqual(s.studyDay, 5, type);
    assert.strictEqual(s.dayKey, "2026-10-20", type);
  }
});

test("the stamp holds exactly the server fields the rules deny clients", () => {
  const s = UE.stampFor(row("2026-10-20T03:59:58Z", "2026-10-20T04:00:00Z"),
      {user: USER, researchId: "PB-001", now: NOW});
  assert.deepStrictEqual(Object.keys(s).sort(),
      UE.SERVER_FIELDS.slice().sort());
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
    console.log(`${failed} usage_events test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} usage_events tests passed`);
})();
