/**
 * T39 — functions/ops_dashboard.js, the pure parts: foreground minutes
 * (60-minute cap per stretch), day rows on the usage basis and on the
 * legacy basis, the follow-up stage, the due list, the weekly cell, the
 * CSV (no outcome column), and the source never touching an outcome
 * collection.
 *
 * Run: cd functions && node test/ops_dashboard_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const O = require("../ops_dashboard");

const tests = [];
const test = (name, fn) => tests.push({name, fn});

const at = (s) => new Date(s);
const NOW = at("2026-10-25T04:00:00Z"); // 2026-10-25 12:00 HKT
const W0 = "2026-10-15";
const days = (from, to) => {
  const out = [];
  for (let d = from; d <= to; d++) {
    const dt = new Date(`${W0}T00:00:00Z`);
    dt.setUTCDate(dt.getUTCDate() + d);
    out.push(dt.toISOString().slice(0, 10));
  }
  return out;
};

test("foreground minutes: 3 h stretch counts 60; short stretch exact; " +
    "open stretch ends now; credited to the day it started", () => {
  const ev = [
    {type: "foreground", clientAt: at("2026-10-20T01:00:00Z")}, // 09:00 HKT
    {type: "background", clientAt: at("2026-10-20T04:00:00Z")}, // 3 h → 60
    {type: "foreground", clientAt: at("2026-10-20T05:00:00Z")},
    {type: "background", clientAt: at("2026-10-20T05:12:30Z")}, // 12.5
    {type: "foreground", clientAt: at("2026-10-21T15:50:00Z")}, // 23:50 HKT
    {type: "background", clientAt: at("2026-10-21T16:10:00Z")}, // next day
    {type: "foreground", clientAt: at("2026-10-25T03:30:00Z")}, // open → now
  ];
  const m = O.foregroundMinutesByDay(ev, NOW);
  assert.strictEqual(m["2026-10-20"], 73);
  assert.strictEqual(m["2026-10-21"], 20);
  assert.strictEqual(m["2026-10-25"], 30);
});

test("foreground followed by another foreground (killed): the stretch " +
    "ends at the next foreground", () => {
  const ev = [
    {type: "foreground", clientAt: at("2026-10-20T01:00:00Z")},
    {type: "foreground", clientAt: at("2026-10-20T01:05:00Z")},
    {type: "background", clientAt: at("2026-10-20T01:07:00Z")},
  ];
  assert.strictEqual(O.foregroundMinutesByDay(ev, NOW)["2026-10-20"], 7);
});

test("day rows on the usage basis: opened, first open HH:mm, minutes, " +
    "valid sessions per companion by end day, Brief PR by invite day", () => {
  const rows = O.dayRowsFor({
    w0Key: W0, todayKey: "2026-10-25", now: NOW, hasUsageEvents: true,
    days: days(1, 10),
    usageEvents: [
      {type: "foreground", clientAt: at("2026-10-16T00:05:00Z")}, // d1 08:05
      {type: "background", clientAt: at("2026-10-16T00:20:00Z")},
      {type: "foreground", clientAt: at("2026-10-16T11:00:00Z")}, // d1 19:00
      {type: "background", clientAt: at("2026-10-16T11:10:00Z")},
      {type: "foreground", clientAt: at("2026-10-18T02:00:00Z")}, // d3
      {type: "background", clientAt: at("2026-10-18T02:01:00Z")},
    ],
    sessions: [
      {agentId: "siu_yan", startedAt: at("2026-10-16T00:06:00Z"),
        endedAt: at("2026-10-16T00:15:00Z"), isValid: true},
      {agentId: "tung_tung", startedAt: at("2026-10-16T11:01:00Z"),
        endedAt: at("2026-10-16T11:09:00Z"), isValid: true},
      {agentId: "tung_tung", startedAt: at("2026-10-16T11:01:00Z"),
        endedAt: at("2026-10-16T11:09:00Z"), isValid: false},
      {agentId: "ah_jan_ah_bak", startedAt: at("2026-10-18T02:00:00Z"),
        endedAt: null, isValid: true},
    ],
    briefPr: [
      {invitedAt: at("2026-10-16T00:15:00Z"), finalStatus: "completed"},
      {invitedAt: at("2026-10-16T11:09:00Z"), finalStatus: "skipped"},
      {invitedAt: null, finalStatus: "due_not_invited"},
    ],
  });
  assert.strictEqual(rows.length, 10);
  const d1 = rows[0];
  assert.deepStrictEqual(d1, {dayKey: "2026-10-16", studyDay: 1,
    basis: "usage", opened: true, firstOpenAt: "08:05",
    foregroundMinutes: 25,
    validSessions: {siu_yan: 1, ah_jan_ah_bak: 0, tung_tung: 1},
    briefPrInvited: 2, briefPrCompleted: 1});
  assert.strictEqual(rows[1].opened, false);
  assert.strictEqual(rows[1].firstOpenAt, null);
  assert.strictEqual(rows[1].foregroundMinutes, 0);
  assert.strictEqual(rows[2].opened, true);
  assert.strictEqual(rows[2].validSessions.ah_jan_ah_bak, 1,
      "endedAt missing → startedAt day");
  assert.strictEqual(rows[9].studyDay, 10);
});

test("legacy basis (no usage events ever): opened from session starts, " +
    "first open = first session, minutes unavailable", () => {
  const rows = O.dayRowsFor({
    w0Key: W0, todayKey: "2026-10-25", now: NOW, hasUsageEvents: false,
    days: days(1, 3), usageEvents: [],
    sessions: [{agentId: "siu_yan", startedAt: at("2026-10-17T01:30:00Z"),
      endedAt: at("2026-10-17T01:40:00Z"), isValid: true}],
    briefPr: [],
  });
  assert.strictEqual(rows[0].opened, false);
  assert.strictEqual(rows[1].opened, true);
  assert.strictEqual(rows[1].basis, "legacy");
  assert.strictEqual(rows[1].firstOpenAt, "09:30");
  assert.strictEqual(rows[1].foregroundMinutes, null);
  assert.strictEqual(rows[1].validSessions.siu_yan, 1);
});

function rowsOpened(openedDays, todayDay) {
  const out = [];
  for (let d = 1; d <= todayDay; d++) {
    out.push({studyDay: d, opened: openedDays.indexOf(d) >= 0});
  }
  return out;
}

test("follow-up: opened today → 0 / none", () => {
  assert.deepStrictEqual(O.followUpFor(rowsOpened([1, 2, 10], 10), 10),
      {consecutiveUnopenedDays: 0, stage: "none", openedToday: true});
});

test("follow-up: 4 days unopened → whatsapp (acceptance 6)", () => {
  assert.deepStrictEqual(O.followUpFor(rowsOpened([1, 6], 10), 10),
      {consecutiveUnopenedDays: 4, stage: "whatsapp", openedToday: false});
});

test("follow-up: 7 days unopened → phone (acceptance 7); 2 days → none; " +
    "3 and 5 → whatsapp; 6 → phone", () => {
  assert.strictEqual(O.followUpFor(rowsOpened([3], 10), 10).stage, "phone");
  assert.strictEqual(O.followUpFor(rowsOpened([3], 10), 10)
      .consecutiveUnopenedDays, 7);
  assert.strictEqual(O.followUpFor(rowsOpened([8], 10), 10).stage, "none");
  assert.strictEqual(O.followUpFor(rowsOpened([7], 10), 10).stage,
      "whatsapp");
  assert.strictEqual(O.followUpFor(rowsOpened([5], 10), 10).stage,
      "whatsapp");
  assert.strictEqual(O.followUpFor(rowsOpened([4], 10), 10).stage, "phone");
});

test("follow-up: never opened since day 0 → every day counts (day 0 " +
    "never counts as opened)", () => {
  assert.deepStrictEqual(O.followUpFor(rowsOpened([], 5), 5),
      {consecutiveUnopenedDays: 5, stage: "whatsapp", openedToday: false});
  assert.deepStrictEqual(O.followUpFor(rowsOpened([], 1), 1),
      {consecutiveUnopenedDays: 1, stage: "none", openedToday: false});
});

test("follow-up: from day 29 'follow_up_period', count still shown " +
    "(acceptance 8); day 28 still staged; day 0 none", () => {
  const r = O.followUpFor(rowsOpened([29], 35), 35);
  assert.strictEqual(r.stage, "follow_up_period");
  assert.strictEqual(r.consecutiveUnopenedDays, 6);
  assert.strictEqual(O.followUpFor(rowsOpened([20], 28), 28).stage, "phone");
  assert.deepStrictEqual(O.followUpFor([], 0),
      {consecutiveUnopenedDays: 0, stage: "none", openedToday: false});
});

test("due list: whatsapp / phone only, most days first, no arm", () => {
  const list = O.dueListFor([
    {researchId: "PB-002", studyPeriod: "B", arm: "A",
      consecutiveUnopenedDays: 4, stage: "whatsapp"},
    {researchId: "PB-001", studyPeriod: "B", arm: "B",
      consecutiveUnopenedDays: 0, stage: "none"},
    {researchId: "PILOT-03", studyPeriod: "PILOT", arm: "B",
      consecutiveUnopenedDays: 7, stage: "phone"},
    {researchId: "PB-009", studyPeriod: "B", arm: "A",
      consecutiveUnopenedDays: 9, stage: "follow_up_period"},
  ]);
  assert.deepStrictEqual(list, [
    {researchId: "PILOT-03", studyPeriod: "PILOT",
      consecutiveUnopenedDays: 7, stage: "phone"},
    {researchId: "PB-002", studyPeriod: "B",
      consecutiveUnopenedDays: 4, stage: "whatsapp"},
  ]);
  for (const r of list) assert.ok(!("arm" in r));
});

test("1020d chapter counts: ready with flags, failed; nothing else", () => {
  assert.deepStrictEqual(O.chapterCounts([
    {status: "ready", flags: ["太书面"]},
    {status: "ready", flags: []},
    {status: "ready"},
    {status: "failed", failReason: "llm_error"},
    {status: "generating", flags: ["无出处"]},
    {source: "rule", status: "ready", version: 1},
    null,
  ]), {flagged: 1, failed: 1});
  assert.deepStrictEqual(O.chapterCounts([]), {flagged: 0, failed: 0});
});

test("weekly cell: done / skipped / missed / open / not_yet", () => {
  assert.strictEqual(O.weeklyCellFor({status: "completed"}, null), "done");
  assert.strictEqual(O.weeklyCellFor({status: "skipped"}, null), "skipped");
  assert.strictEqual(O.weeklyCellFor({status: "no_referent"}, null),
      "skipped");
  assert.strictEqual(O.weeklyCellFor(null, {pushedAt: NOW, missedAt: NOW}),
      "missed");
  assert.strictEqual(O.weeklyCellFor(null, {pushedAt: NOW}), "open");
  assert.strictEqual(O.weeklyCellFor(null, null), "not_yet");
  assert.strictEqual(O.weeklyCellFor({status: "in_progress"}, {pushedAt: NOW}),
      "open");
});

const OUTCOME_WORDS =
  /djg|ucla|phq|gad|pgic|social_contact|continuance|aimhs|score/i;

test("CSV: one row per person-day, the fixed columns, no outcome column " +
    "(acceptance 11)", () => {
  const person = {researchId: "PILOT-01", studyPeriod: "PILOT", arm: "A"};
  const day = {dayKey: "2026-10-16", studyDay: 1, basis: "usage",
    opened: true, firstOpenAt: "08:05", foregroundMinutes: 25,
    validSessions: {siu_yan: 1, ah_jan_ah_bak: 0, tung_tung: 2},
    briefPrInvited: 2, briefPrCompleted: 1};
  const legacyDay = Object.assign({}, day, {dayKey: "2026-10-17", studyDay: 2,
    basis: "legacy", foregroundMinutes: null, firstOpenAt: null,
    opened: false});
  const text = O.csvFor([{person, days: [day, legacyDay]}]);
  const lines = text.trim().split("\n");
  assert.strictEqual(lines[0], O.CSV_COLUMNS.join(","));
  assert.strictEqual(lines[1],
      "PILOT-01,PILOT,A,1,2026-10-16,1,08:05,25,1,0,2,2,1,usage");
  assert.strictEqual(lines[2],
      "PILOT-01,PILOT,A,2,2026-10-17,0,,,1,0,2,2,1,legacy");
  assert.ok(!OUTCOME_WORDS.test(lines[0]), "no outcome column");
});

test("the module never reads an outcome collection", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "ops_dashboard.js"),
      "utf8");
  // Strip the declaration of the forbidden list itself and the comments.
  const code = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "")
      .replace(/const OUTCOME_COLLECTIONS = \[[\s\S]*?\];/, "");
  for (const c of O.OUTCOME_COLLECTIONS) {
    assert.ok(code.indexOf(`"${c}"`) < 0, `reads ${c}`);
  }
  assert.ok(code.indexOf("\"turns\"") < 0, "reads conversation turns");
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
    console.log(`${failed} ops_dashboard test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} ops_dashboard tests passed`);
})();
