/**
 * T18 — W2 DJG scoring, window and switch logic (functions/djg_w2.js).
 * Pure functions, no emulator.  Prints the scoring table used in
 * docs/dev-reports/T18-djg-w2-20261007.md.
 *
 * Run: cd functions && node test/djg_w2_test.js
 */
"use strict";

const assert = require("assert");
const djg = require("../djg_w2");

const tests = [];
const test = (name, fn) => tests.push({name, fn});

const all = (v) => ({q1: v, q2: v, q3: v, q4: v, q5: v, q6: v});

// [case, answers, expected {emotional, social, total}]
const SCORING_CASES = [
  ["全部「是」", all("yes"), {emotional: 3, social: 0, total: 3}],
  ["全部「不是」", all("no"), {emotional: 0, social: 3, total: 3}],
  ["全部「大致是」", all("mostly"), {emotional: 3, social: 3, total: 6}],
  ["情感全「是」+ 社交全「不是」（最孤独）",
    {q1: "yes", q2: "yes", q3: "yes", q4: "no", q5: "no", q6: "no"},
    {emotional: 3, social: 3, total: 6}],
  ["情感全「不是」+ 社交全「是」（最不孤独）",
    {q1: "no", q2: "no", q3: "no", q4: "yes", q5: "yes", q6: "yes"},
    {emotional: 0, social: 0, total: 0}],
  ["第 2 题跳过，其余「是」", Object.assign(all("yes"), {q2: "skipped"}),
    {emotional: null, social: 0, total: null}],
  ["第 5 题跳过，其余「不是」", Object.assign(all("no"), {q5: "skipped"}),
    {emotional: 0, social: null, total: null}],
  ["第 1 题没答（缺键），其余「大致是」",
    {q2: "mostly", q3: "mostly", q4: "mostly", q5: "mostly", q6: "mostly"},
    {emotional: null, social: 3, total: null}],
  ["全部跳过", all("skipped"), {emotional: null, social: null, total: null}],
  ["混合：是/大致是/不是 + 不是/大致是/是",
    {q1: "yes", q2: "mostly", q3: "no", q4: "no", q5: "mostly", q6: "yes"},
    {emotional: 2, social: 2, total: 4}],
  ["非法值当缺失", Object.assign(all("yes"), {q4: 1}),
    {emotional: 3, social: null, total: null}],
];

test("scoring table (questionnaire package §3)", () => {
  const rows = [];
  for (const [name, answers, expected] of SCORING_CASES) {
    const got = djg.scoreAnswers(answers);
    assert.deepStrictEqual(got, expected, name);
    const f = (v) => (v === null ? "缺失" : String(v));
    rows.push(`| ${name} | ${f(expected.emotional)} / ${f(expected.social)}` +
      ` / ${f(expected.total)} | ${f(got.emotional)} / ${f(got.social)} / ` +
      `${f(got.total)} | 一致 |`);
  }
  console.log("| 情况 | 预期 情感/社交/总分 | 实际 | 结果 |");
  console.log("|---|---|---|---|");
  for (const r of rows) console.log(r);
});

test("scoreAnswers tolerates null", () => {
  assert.deepStrictEqual(djg.scoreAnswers(null),
      {emotional: null, social: null, total: null});
});

test("config: defaults, only literal true switches on, bad numbers ignored",
    () => {
      assert.deepStrictEqual(djg.configFromData(undefined), djg.DEFAULTS);
      assert.strictEqual(
          djg.configFromData({djgW2InAppEnabled: "true"}).enabled, false);
      assert.strictEqual(
          djg.configFromData({djgW2InAppEnabled: true}).enabled, true);
      const c = djg.configFromData({djgW2DayOffset: 0, djgW2WindowDays: "7",
        djgW2PushHour: 9, djgW2ReminderHours: 12});
      assert.strictEqual(c.dayOffset, 14);
      assert.strictEqual(c.windowDays, 7);
      assert.strictEqual(c.pushHour, 9);
      assert.strictEqual(c.reminderHours, 12);
    });

test("window: day 13 before, 14 and 20 open, 21 after (W0 = day 1)", () => {
  const cfg = djg.configFromData({});
  const w0 = "2026-10-01";
  const at = (day) => djg.windowState(w0, djg.addDays(w0, day - 1), cfg);
  assert.strictEqual(at(13).state, "before");
  assert.strictEqual(at(14).state, "open");
  assert.strictEqual(at(20).state, "open");
  assert.strictEqual(at(21).state, "after");
  assert.strictEqual(at(14).day, 14);
  assert.strictEqual(at(14).startKey, "2026-10-14");
  assert.strictEqual(at(14).endKey, "2026-10-20");
  // Configurable.
  const short = djg.configFromData({djgW2DayOffset: 15, djgW2WindowDays: 3});
  assert.strictEqual(djg.windowState(w0, "2026-10-14", short).state,
      "before");
  assert.strictEqual(djg.windowState(w0, "2026-10-17", short).state, "open");
  assert.strictEqual(djg.windowState(w0, "2026-10-18", short).state,
      "after");
});

test("W0 date: createdAt string, Timestamp-like, Date; HK calendar day",
    () => {
      assert.strictEqual(djg.w0DateKey({createdAt: "2026-10-01T23:30:00"}),
          "2026-10-01");
      // 2026-10-01 17:00 UTC = 2026-10-02 01:00 HKT.
      const d = new Date("2026-10-01T17:00:00Z");
      assert.strictEqual(djg.w0DateKey({createdAt: {toDate: () => d}}),
          "2026-10-02");
      assert.strictEqual(djg.w0DateKey({createdAt: d}), "2026-10-02");
      assert.strictEqual(djg.w0DateKey({}), null);
      assert.strictEqual(djg.w0DateKey({createdAt: "soon"}), null);
    });

test("W0 date: the registered w0Date wins over createdAt (T19)", () => {
  assert.strictEqual(djg.w0DateKey({w0Date: "2026-10-05",
    createdAt: "2026-10-01T09:00:00"}), "2026-10-05");
  // Malformed registered date → fall back to createdAt.
  assert.strictEqual(djg.w0DateKey({w0Date: "5/10/2026",
    createdAt: "2026-10-01T09:00:00"}), "2026-10-01");
  assert.strictEqual(djg.w0DateKey({w0Date: "2026-10-05"}), "2026-10-05");
});

test("Phase B participant and week2Push hand-over", () => {
  const on = djg.configFromData({djgW2InAppEnabled: true});
  const off = djg.configFromData({});
  const b = {arm: "B", cohort: "phase_b"};
  const legacyB = {arm: "A", armAssignmentMode: "randomise"};
  const phaseA = {arm: "A", cohort: "phase_a"};
  const forced = {arm: "A", armAssignmentMode: "force_a"};
  assert.strictEqual(djg.isPhaseBParticipant(b), true);
  assert.strictEqual(djg.isPhaseBParticipant(legacyB), true);
  assert.strictEqual(djg.isPhaseBParticipant(phaseA), false);
  assert.strictEqual(djg.isPhaseBParticipant(forced), false);
  assert.strictEqual(djg.isPhaseBParticipant({arm: null}), false);
  assert.strictEqual(djg.week2PushShouldSkip(on, b), true);
  assert.strictEqual(djg.week2PushShouldSkip(on, phaseA), false);
  assert.strictEqual(djg.week2PushShouldSkip(off, b), false);
});

test("placeholder copy is never sendable", () => {
  assert.strictEqual(djg.isPlaceholder(djg.PUSH_BODY), true);
  assert.strictEqual(djg.isPlaceholder(djg.REMINDER_BODY), true);
  assert.strictEqual(djg.isPlaceholder(""), true);
  assert.strictEqual(djg.isPlaceholder("第 2 週問卷開咗"), false);
});

test("hkHour", () => {
  assert.strictEqual(djg.hkHour(new Date("2026-10-14T02:00:00Z")), 10);
  assert.strictEqual(djg.hkHour(new Date("2026-10-14T16:30:00Z")), 0);
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`ok - ${t.name}`);
    } catch (err) {
      failed++;
      console.error(`not ok - ${t.name}\n${err.stack}`);
    }
  }
  if (failed) {
    console.error(`${failed} djg W2 test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} djg W2 tests passed`);
})();
