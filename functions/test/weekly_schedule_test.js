/**
 * T24 — weekly schedule, pure parts (functions/weekly_schedule.js):
 * config, bundles, windows, the week-4 close rule, the pilot compression,
 * the legacy-reminder filter.  Shared table:
 * test/fixtures/weekly_schedule_table.json (also read by
 * test/weekly_schedule_test.dart).  Prints the Mon–Sun date table used in
 * docs/dev-reports/T24-weekly-schedule-20261014.md.
 *
 * Run: cd functions && node test/weekly_schedule_test.js
 */
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const ws = require("../weekly_schedule");
const sw = require("../study_week");

const tests = [];
const test = (name, fn) => tests.push({name, fn});

const TABLE = JSON.parse(fs.readFileSync(
    path.join(__dirname, "..", "..", "test", "fixtures",
        "weekly_schedule_table.json"), "utf8"));
const CFG = ws.configFromData(Object.assign({weeklyScheduleV2Enabled: true},
    TABLE.config));

const iso = (d) => d.toISOString();
const fx = (s) => new Date(s).toISOString();

test("config: defaults, literal-true switches, bad lists ignored", () => {
  const d = ws.configFromData(undefined);
  assert.strictEqual(d.enabled, false);
  assert.deepStrictEqual(d.bundleDays, [7, 14, 21, 26]);
  assert.strictEqual(d.windowDays, 3);
  assert.strictEqual(d.week4CloseDay, 29);
  assert.deepStrictEqual(d.djgWeeks, [1, 2, 3]);
  assert.deepStrictEqual(d.pgicOnlyDays, [35, 42, 49]);
  assert.strictEqual(d.pushHour, 20);
  assert.strictEqual(d.socialContactProbeEnabled, false);
  assert.deepStrictEqual(d.pilotBundleDays, [1, 3, 5, 7]);
  assert.strictEqual(d.pilotWindowDays, 1);
  assert.strictEqual(d.reminderHours, 24);
  assert.strictEqual(ws.configFromData({weeklyScheduleV2Enabled: "true"})
      .enabled, false);
  assert.strictEqual(ws.configFromData({weeklyScheduleV2Enabled: true})
      .enabled, true);
  // Not strictly increasing / non-numeric → default.
  assert.deepStrictEqual(ws.configFromData({weeklyBundleDays: [7, 7, 21]})
      .bundleDays, [7, 14, 21, 26]);
  assert.deepStrictEqual(ws.configFromData({weeklyBundleDays: ["7"]})
      .bundleDays, [7, 14, 21, 26]);
  assert.deepStrictEqual(ws.configFromData({pgicOnlyDays: [35.9, 42]})
      .pgicOnlyDays, [35, 42]);
  assert.strictEqual(ws.configFromData({weeklyPushHour: 26}).pushHour, 2);
  assert.strictEqual(ws.configFromData({djgW2ReminderHours: 12})
      .reminderHours, 12);
});

test("schedule mode by cohort", () => {
  assert.strictEqual(ws.scheduleModeFor({cohort: "phase_b"}), "standard");
  assert.strictEqual(ws.scheduleModeFor({cohort: "pilot"}), "pilot");
  assert.strictEqual(ws.scheduleModeFor({cohort: "phase_a"}), null);
  assert.strictEqual(ws.scheduleModeFor({armAssignmentMode: "randomise"}),
      null);
  assert.strictEqual(ws.scheduleModeFor(null), null);
});

test("shared table: standard bundles, parts and windows", () => {
  const w0 = TABLE.standard.w0;
  const bundles = ws.bundlesFor(CFG, "standard");
  assert.strictEqual(bundles.length, TABLE.standard.bundles.length);
  TABLE.standard.bundles.forEach((e, i) => {
    const b = bundles[i];
    assert.strictEqual(b.id, e.id);
    assert.strictEqual(b.studyWeek, e.studyWeek);
    assert.strictEqual(b.pushDay, e.pushDay);
    assert.deepStrictEqual(b.parts, e.parts, e.id);
    const w = ws.windowFor(b, w0, CFG);
    assert.strictEqual(iso(w.open), fx(e.open), `${e.id} open`);
    assert.strictEqual(iso(w.close), fx(e.close), `${e.id} close`);
  });
  const social = ws.configFromData(Object.assign({}, TABLE.config,
      {socialContactProbeEnabled: true}));
  assert.deepStrictEqual(ws.bundlesFor(social, "standard")[0].parts,
      TABLE.standard.socialPartsW1);
  // W5–W7 never carry the probe or the DJG.
  for (const b of ws.bundlesFor(social, "standard").slice(4)) {
    assert.deepStrictEqual(b.parts, ["pgic"], b.id);
  }
});

test("shared table: week-4 close (day 27 / day 31 / no visit)", () => {
  const w0 = TABLE.standard.w0;
  for (const c of TABLE.standard.week4Close) {
    assert.strictEqual(iso(ws.week4CloseFor(w0, c.w4VisitDate, CFG)),
        fx(c.close), c.case);
    const w4 = ws.bundlesFor(CFG, "standard")[3];
    assert.strictEqual(iso(ws.windowFor(w4, w0, CFG,
        {w4VisitDate: c.w4VisitDate}).close), fx(c.close), c.case);
  }
});

test("shared table: pilot bundles (days 1, 3, 5, 7; DJG in first three)",
    () => {
      const w0 = TABLE.pilot.w0;
      const bundles = ws.bundlesFor(CFG, "pilot");
      assert.strictEqual(bundles.length, 4);
      TABLE.pilot.bundles.forEach((e, i) => {
        const b = bundles[i];
        assert.strictEqual(b.id, e.id);
        assert.strictEqual(b.pushDay, e.pushDay);
        assert.deepStrictEqual(b.parts, e.parts, e.id);
        const w = ws.windowFor(b, w0, CFG);
        assert.strictEqual(iso(w.open), fx(e.open), `${e.id} open`);
        assert.strictEqual(iso(w.close), fx(e.close), `${e.id} close`);
      });
      // Pilot windows never overlap (1 day < 2-day spacing).
      for (let i = 1; i < bundles.length; i++) {
        assert.ok(ws.windowFor(bundles[i - 1], w0, CFG).close <=
          ws.windowFor(bundles[i], w0, CFG).open);
      }
    });

test("shared table: Weekly PR referent range of W2", () => {
  const w0 = TABLE.standard.w0;
  const b = ws.bundlesFor(CFG, "standard")[1];
  const r = ws.referentRangeFor(b, w0, CFG, "standard");
  assert.strictEqual(iso(r.start), fx(TABLE.standard.referentRangeW2.start));
  assert.strictEqual(iso(r.end), fx(TABLE.standard.referentRangeW2.end));
  const p = ws.bundlesFor(CFG, "pilot");
  const r0 = ws.referentRangeFor(p[0], w0, CFG, "pilot");
  assert.strictEqual(iso(r0.start), fx("2026-10-19T00:00:00+08:00"));
  const r1 = ws.referentRangeFor(p[1], w0, CFG, "pilot");
  assert.strictEqual(iso(r1.start), fx("2026-10-20T20:00:00+08:00"));
  assert.strictEqual(iso(r1.end), fx("2026-10-22T20:00:00+08:00"));
});

test("openBundleAt: before / inside / at close / between bundles", () => {
  const w0 = "2026-10-19";
  const at = (s) => new Date(s);
  assert.strictEqual(ws.openBundleAt(CFG, "standard", w0,
      at("2026-10-26T19:59:00+08:00")), null);
  assert.strictEqual(ws.openBundleAt(CFG, "standard", w0,
      at("2026-10-26T20:00:00+08:00")).bundle.id, "W1");
  assert.strictEqual(ws.openBundleAt(CFG, "standard", w0,
      at("2026-10-29T19:59:59+08:00")).bundle.id, "W1");
  assert.strictEqual(ws.openBundleAt(CFG, "standard", w0,
      at("2026-10-29T20:00:00+08:00")), null);
  assert.strictEqual(ws.openBundleAt(CFG, "standard", w0,
      at("2026-11-17T23:59:00+08:00")).bundle.id, "W4");
  assert.strictEqual(ws.openBundleAt(CFG, "standard", w0,
      at("2026-11-18T00:00:00+08:00")), null);
  assert.strictEqual(ws.openBundleAt(CFG, "standard", w0,
      at("2026-12-08T09:00:00+08:00")).bundle.id, "W7");
  assert.strictEqual(ws.openBundleAt(CFG, "pilot", w0,
      at("2026-10-22T21:00:00+08:00")).bundle.id, "W2");
});

test("date table: W0 on every weekday, 8 weeks — same study days, " +
    "windows 3 × 24 h, W4 closes end of day 29, DJG only W1–W3", () => {
  const lines = ["| W0（星期） | 周 | 推送日 | 推送时刻（香港） | 关闭时刻（香港） | 部分 |",
    "|---|---|---|---|---|---|"];
  const hkStr = (d) => d.toLocaleString("sv-SE", {timeZone: "Asia/Hong_Kong"})
      .slice(0, 16);
  const weekdays = ["日", "一", "二", "三", "四", "五", "六"];
  for (const w0 of TABLE.w0Weekdays) {
    const wd = weekdays[new Date(`${w0}T12:00:00+08:00`).getUTCDay()];
    for (const b of ws.bundlesFor(CFG, "standard")) {
      const w = ws.windowFor(b, w0, CFG);
      assert.strictEqual(sw.studyDayAt(w0, w.open), b.pushDay);
      assert.strictEqual(sw.hkDateKey(w.open), sw.addDays(w0, b.pushDay));
      if (b.closeRule === "week4") {
        assert.strictEqual(iso(w.close),
            iso(sw.hkEndOfDay(sw.addDays(w0, 29))));
      } else {
        assert.strictEqual(w.close - w.open, 3 * 86400000);
      }
      assert.strictEqual(b.parts.indexOf("djg") >= 0, b.studyWeek <= 3);
      // Nothing is pushed in week 8 (T35 owns W8).
      assert.ok(b.pushDay <= 56 - 7);
      lines.push(`| ${w0}（${wd}） | W${b.bundleWeek} | 第 ${b.pushDay} 天 | ` +
        `${hkStr(w.open)} | ${hkStr(w.close)}${b.closeRule === "week4" ?
          "（第 29 天结束）" : ""} | ${b.parts.join(" → ")} |`);
    }
  }
  console.log(lines.join("\n"));
});

test("partSubmitted per part type", () => {
  assert.strictEqual(ws.partSubmitted("djg", {status: "submitted"}), true);
  assert.strictEqual(ws.partSubmitted("djg", {status: "in_progress"}), false);
  assert.strictEqual(ws.partSubmitted("weekly_pr", {status: "no_referent"}),
      true);
  assert.strictEqual(ws.partSubmitted("weekly_pr", {status: "missed"}), false);
  assert.strictEqual(ws.partSubmitted("pgic", {value: 4}), true);
  assert.strictEqual(ws.partSubmitted("pgic", {status: "missed"}), false);
  assert.strictEqual(ws.partSubmitted("social_contact", null), false);
});

test("placeholder copy is never sendable", () => {
  assert.strictEqual(ws.isPlaceholder(ws.PUSH_BODY), true);
  assert.strictEqual(ws.isPlaceholder(ws.REMINDER_BODY), true);
  assert.strictEqual(ws.isPlaceholder("今個禮拜嘅問卷"), false);
  assert.strictEqual(ws.isPlaceholder(""), true);
});

test("legacy Sunday reminder (switch on): never Phase B / pilot / tester; " +
    "nobody once the gate is on", () => {
  const t = ws.legacyWeeklyReminderTarget;
  assert.strictEqual(t({cohort: "phase_b"}, {gateOn: false}), false);
  assert.strictEqual(t({cohort: "pilot"}, {gateOn: false}), false);
  assert.strictEqual(t({isTester: true}, {gateOn: false}), false);
  assert.strictEqual(t({cohort: "phase_a"}, {gateOn: false}), true);
  assert.strictEqual(t({}, {gateOn: false}), true);
  assert.strictEqual(t({}, {gateOn: true}), false);
});

test("stamp fields are exactly the server-only list the rules refuse", () => {
  const b = ws.bundlesFor(CFG, "standard")[1];
  const w = ws.windowFor(b, "2026-10-19", CFG);
  const st = ws.partStamp({bundle: b, window: w, w0Key: "2026-10-19",
    mode: "standard", pushedAt: w.open,
    submittedAt: new Date("2026-11-03T09:00:00+08:00"), missed: false,
    now: new Date()});
  assert.strictEqual(st.studyWeek, 2);
  assert.strictEqual(st.studyDay, 14);
  assert.strictEqual(st.submittedStudyDay, 15);
  assert.strictEqual(st.missed, false);
  assert.strictEqual(st.scheduleMode, "standard");
  for (const k of Object.keys(st)) {
    if (k === "bundle") continue;
    assert.ok(ws.SERVER_ONLY_FIELDS.indexOf(k) >= 0, k);
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
      console.log(`not ok - ${t.name}\n${err.stack}`);
    }
  }
  if (failed) {
    console.log(`${failed} weekly_schedule test(s) failed`);
    process.exit(1);
  }
  console.log(`all ${tests.length} weekly_schedule tests passed`);
})();
