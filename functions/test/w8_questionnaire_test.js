/**
 * T35 — the W8 questionnaire, pure parts (functions/w8_questionnaire.js;
 * handover 1021-W8, decision 0036).  No Firestore, no clock: every
 * instant is passed in.
 *
 *   - the dates of one person per W0 weekday (Monday to Sunday) and the
 *     handover's examples (W0 10/15 → day 56 = 12/10, …);
 *   - the window [day 56 00:00, day 64 00:00) and the late period to the
 *     end of day 70;
 *   - the three pushes (days 56, 58, 60), who is targeted;
 *   - the summary, the dashboard cell, the scores;
 *   - the e-mail: research ID and study day only;
 *   - the push text and the copy spec word for word;
 *   - no model anywhere in the module.
 *
 * Run:  cd functions && node test/w8_questionnaire_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const w8 = require("../w8_questionnaire");
const sw = require("../study_week");
const sp = require("../study_period");

const tests = [];
const test = (name, fn) => tests.push({name, fn});
const hk = (key, h, m, s) => new Date(`${key}T${String(h).padStart(2, "0")}:` +
  `${String(m || 0).padStart(2, "0")}:${String(s || 0).padStart(2, "0")}` +
  "+08:00");

test("one person per W0 weekday: day 56 / 58 / 60 / 63 / 70", () => {
  // 2026-10-19 is a Monday.
  const expect = [
    ["2026-10-19", "Mon", "2026-12-14", "2026-12-16", "2026-12-18",
      "2026-12-21", "2026-12-28"],
    ["2026-10-20", "Tue", "2026-12-15", "2026-12-17", "2026-12-19",
      "2026-12-22", "2026-12-29"],
    ["2026-10-21", "Wed", "2026-12-16", "2026-12-18", "2026-12-20",
      "2026-12-23", "2026-12-30"],
    ["2026-10-22", "Thu", "2026-12-17", "2026-12-19", "2026-12-21",
      "2026-12-24", "2026-12-31"],
    ["2026-10-23", "Fri", "2026-12-18", "2026-12-20", "2026-12-22",
      "2026-12-25", "2027-01-01"],
    ["2026-10-24", "Sat", "2026-12-19", "2026-12-21", "2026-12-23",
      "2026-12-26", "2027-01-02"],
    ["2026-10-25", "Sun", "2026-12-20", "2026-12-22", "2026-12-24",
      "2026-12-27", "2027-01-03"],
  ];
  for (const [w0, wd, d56, d58, d60, d63, d70] of expect) {
    const d = w8.datesFor(w0);
    assert.deepStrictEqual([d.openKey, d.remind1Key, d.remind2Key,
      d.closeKey, d.lastCardKey], [d56, d58, d60, d63, d70], w0);
    assert.strictEqual(d.emailKey, d60);
    // Day 56 is eight weeks on: the same weekday as W0.
    const weekday = (k) => new Date(`${k}T00:00:00Z`).getUTCDay();
    assert.strictEqual(weekday(d56), weekday(w0), wd);
    assert.strictEqual(sw.studyDayOf(w0, d56), 56);
    assert.strictEqual(sw.studyWeekOf(56), 8);
  }
});

test("handover examples: W0 10/15 → 12/10; 10/19 → 12/14; 10/21 → 12/16",
    () => {
      assert.strictEqual(w8.datesFor("2026-10-15").openKey, "2026-12-10");
      assert.strictEqual(w8.datesFor("2026-10-19").openKey, "2026-12-14");
      assert.strictEqual(w8.datesFor("2026-10-21").openKey, "2026-12-16");
    });

test("window: day 56 00:00 to the end of day 63; late to the end of day 70",
    () => {
      const d = w8.datesFor("2026-10-15");
      assert.strictEqual(d.windowStart.toISOString(),
          hk("2026-12-10", 0).toISOString());
      assert.strictEqual(d.windowEnd.toISOString(),
          hk("2026-12-18", 0).toISOString());
      assert.strictEqual(d.acceptUntil.toISOString(),
          hk("2026-12-25", 0).toISOString());
      const out = (at) => w8.outOfWindowAt(at, d);
      assert.strictEqual(out(hk("2026-12-09", 23, 59, 59)), true);
      assert.strictEqual(out(hk("2026-12-10", 0)), false);
      assert.strictEqual(out(hk("2026-12-17", 23, 59, 59)), false);
      assert.strictEqual(out(hk("2026-12-18", 0)), true);
      assert.strictEqual(out(hk("2026-12-24", 23, 59)), true);
    });

test("pushes: day 56 to all, day 58 and 60 to whoever is not done", () => {
  const s = w8.stepsFor("2026-10-19");
  assert.deepStrictEqual(s.map((x) => [x.step, x.day, x.dateKey, x.field,
    x.kind, x.all]), [
    ["open", 56, "2026-12-14", "pushedAt", "w8_open", true],
    ["remind1", 58, "2026-12-16", "remind1SentAt", "w8_reminder", false],
    ["remind2", 60, "2026-12-18", "remind2SentAt", "w8_reminder", false],
  ]);
  assert.ok(s.every((x) => x.day !== 62), "no day-62 reminder");
});

test("targets: RCT-, PB-, PILOT- registered non-testers only", () => {
  const base = {w0Date: "2026-10-19"};
  for (const cohort of sp.ENROLLED_COHORTS) {
    assert.strictEqual(w8.isTarget(Object.assign({cohort}, base)), true,
        cohort);
  }
  assert.strictEqual(w8.isTarget(Object.assign({cohort: sp.COHORT_RCT,
    isTester: true}, base)), false, "tester");
  assert.strictEqual(w8.isTarget(Object.assign({cohort: sp.COHORT_PILOT,
    isTester: true, armAssignedBy: "tester_switch"}, base)), false,
  "switched tester");
  assert.strictEqual(w8.isTarget(base), false, "not registered");
  assert.strictEqual(w8.isTarget({cohort: "phase_a", w0Date: "2026-10-19"}),
      false);
  assert.strictEqual(w8.isTarget(null), false);
});

test("summary: completion only, five parts; AIMHS does not count", () => {
  const d = w8.datesFor("2026-10-15");
  const sub = (at) => ({status: "submitted", submittedAt: at});
  const none = w8.summarize({}, d);
  assert.strictEqual(none.status, "not_started");
  assert.strictEqual(none.partsSubmitted, 0);
  const some = w8.summarize({djg: sub(hk("2026-12-10", 11)),
    ucla3: {status: "in_progress"}}, d);
  assert.strictEqual(some.status, "in_progress");
  assert.strictEqual(some.partsSubmitted, 1);
  assert.strictEqual(some.completedAt, null);
  const all = {};
  for (const p of w8.PARTS) all[p.id] = sub(hk("2026-12-11", 9));
  all.lsns6 = sub(hk("2026-12-11", 9, 8));
  const done = w8.summarize(all, d);
  assert.strictEqual(done.status, "completed");
  assert.strictEqual(done.completedAt.toISOString(),
      hk("2026-12-11", 9, 8).toISOString());
  assert.strictEqual(done.completedOutOfWindow, false);
  assert.strictEqual(done.aimhs, null, "AIMHS not filled: still complete");
  all.aimhs = {status: "declined"};
  assert.strictEqual(w8.summarize(all, d).aimhs, "declined");
  all.ci = sub(hk("2026-12-19", 10));
  const late = w8.summarize(all, d);
  assert.strictEqual(late.completedOutOfWindow, true);
  // PGIC's existing format: answeredAt is the submission time too.
  const pg = Object.assign({}, all, {pgic: {status: "submitted",
    answeredAt: hk("2026-12-20", 8)}});
  assert.strictEqual(w8.summarize(pg, d).completedAt.toISOString(),
      hk("2026-12-20", 8).toISOString());
  assert.ok(!JSON.stringify(done).includes("answers"));
});

test("dashboard cell", () => {
  assert.strictEqual(w8.cellFor(null, 55), "not_yet");
  assert.strictEqual(w8.cellFor(null, 56), "open");
  assert.strictEqual(w8.cellFor({status: "not_started"}, 63), "open");
  assert.strictEqual(w8.cellFor({status: "in_progress"}, 60), "in_progress");
  assert.strictEqual(w8.cellFor({status: "not_started"}, 64), "late");
  assert.strictEqual(w8.cellFor({status: "in_progress"}, 66), "in_progress");
  assert.strictEqual(w8.cellFor({completedAt: new Date()}, 70), "done");
  assert.strictEqual(w8.cellFor({}, 71), "missed");
  assert.strictEqual(w8.cellFor({closedAt: new Date()}, 71), "missed");
  assert.strictEqual(w8.cellFor({completedAt: new Date(),
    closedAt: new Date()}, 80), "done");
});

test("scores: DJG-ES as T18, UCLA-3 total, LSNS-6 family / friends / total",
    () => {
      const djg = w8.PARTS[0];
      assert.strictEqual(djg.id, "djg");
      assert.deepStrictEqual(djg.score({q1: "yes", q2: "mostly", q3: "no",
        q4: "yes", q5: "no", q6: "mostly"}), {emotional: 2, social: 2,
        total: 4});
      assert.deepStrictEqual(djg.score({q1: "skipped", q2: "no", q3: "no",
        q4: "no", q5: "no", q6: "no"}), {emotional: null, social: 3,
        total: null});
      assert.deepStrictEqual(w8.scoreUcla3({q1: 1, q2: 3, q3: 2}),
          {total: 6});
      assert.deepStrictEqual(w8.scoreUcla3({q1: 1, q2: "skipped", q3: 2}),
          {total: null});
      assert.deepStrictEqual(w8.scoreLsns6({q1: 0, q2: 1, q3: 5, q4: 2,
        q5: 3, q6: 4}), {family: 6, friends: 9, total: 15});
      assert.deepStrictEqual(w8.scoreLsns6({q1: 0, q2: 1, q3: 5, q4: 2,
        q5: "skipped", q6: 4}), {family: 6, friends: null, total: null});
      const ids = (id) => w8.ALL_PARTS.find((p) => p.id === id);
      assert.strictEqual(ids("ci").score, undefined, "CI: raw only");
      assert.strictEqual(ids("aimhs").score, undefined,
          "AIMHS: raw only, item 1 reversed at analysis");
    });

test("parts: order and collections", () => {
  assert.deepStrictEqual(w8.PARTS.map((p) => [p.id, p.collection]), [
    ["djg", "djg_responses"], ["ucla3", "ucla3_responses"], ["pgic", "pgic"],
    ["ci", "ci_responses"], ["lsns6", "lsns6_responses"]]);
  assert.strictEqual(w8.AIMHS.collection, "aimhs_responses");
  assert.strictEqual(w8.partByCollection("weekly_pr"), null);
});

test("e-mail: research ID and study day only; no arm, cohort or answer",
    () => {
      const rows = [{researchId: "PILOT-02", studyDay: 60},
        {researchId: "RCT-07", studyDay: 60}, {researchId: null,
          studyDay: 60}];
      const m = w8.buildEmail(rows, hk("2026-12-14", 10), 10);
      assert.strictEqual(m.subject, "陪住：最後一份問卷（W8）未完成名單");
      const lines = m.text.split("\n");
      assert.ok(lines[0].startsWith("2026-12-14（星期一）10:00"));
      assert.deepStrictEqual(lines.filter((l) => l.includes(" ｜ 第 ")), [
        "PILOT-02 ｜ 第 60 天", "RCT-07 ｜ 第 60 天", "（研究编号缺失） ｜ 第 60 天"]);
      assert.ok(m.text.includes("共 3 人。"));
      for (const bad of ["Hybrid", "规则组", "A 组", "B 组", "arm",
        "phase_b", "\"rct\"", "pilot", "yes", "mostly"]) {
        assert.ok(!m.text.includes(bad), bad);
      }
    });

test("push text: the handover's words, and the copy spec, word for word",
    () => {
      assert.strictEqual(w8.PUSH_BODY,
          "最後一份問卷開咗，請喺一個禮拜內入嚟答埋佢。多謝你！");
      assert.strictEqual(w8.PUSH_TITLE, "陪住");
      const spec = fs.readFileSync(path.resolve(__dirname,
          "../../docs/spec/copy/w8-questionnaire.md"), "utf8");
      const row = spec.split("\n").find((l) => l.startsWith("| W8-push |"));
      assert.ok(row, "W8-push row in the spec");
      assert.strictEqual(row.split("|")[3].trim(), w8.PUSH_BODY);
    });

test("no model, no LLM path anywhere in the module (both arms identical)",
    () => {
      const src = fs.readFileSync(path.resolve(__dirname,
          "../w8_questionnaire.js"), "utf8");
      for (const bad of ["deepseek", "DeepSeek", "llm_log", "proxyDeepSeek",
        "deepSeekChat", "\"arm\"", ".arm ", "u.arm", "fetch("]) {
        assert.ok(!src.includes(bad), bad);
      }
    });

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`ok - ${t.name}`);
    } catch (err) {
      failed++;
      console.log(`FAIL - ${t.name}\n      ${err.stack}`);
    }
  }
  console.log(`\n${tests.length - failed} passed, ${failed} failed.`);
  process.exit(failed ? 1 : 0);
})();
