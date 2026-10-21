/**
 * 1020o 第三节 (decision 0066) — the elder's own 安靜時段.
 *   - windowFor / inQuietHours: own users/{uid}.quietHoursStart / End
 *     first (field by field), else the global app_config/reminders window;
 *     own values outside RANGE move to the nearest edge; malformed ones
 *     are ignored;
 *   - quietEndAfter and reminders.classify: a reminder held overnight
 *     counts its age from the end of the window;
 *   - the range is the same in functions/quiet_hours.js, the App
 *     (lib/core/notifications/quiet_hours_range.dart) and firestore.rules;
 *   - usage_events.js stamps quiet_hours_changed rows.
 *
 * Run: cd functions && node test/quiet_hours_1020o_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const qh = require("../quiet_hours");
const reminders = require("../reminders");
const UE = require("../usage_events");

let n = 0;
function t(name, fn) {
  fn();
  n++;
  console.log(`ok - ${name}`);
}
// A Date at a Hong Kong wall-clock time on 2026-10-21 (day + 1 for after
// midnight).
const hk = (h, m, day) =>
  new Date(Date.UTC(2026, 9, day || 21, h - 8, m || 0));
const GLOBAL = qh.quietHoursConfigFrom({});
const ME = {quietHoursStart: "20:00", quietHoursEnd: "06:00"};

t("the allowed values: start 20:00–23:00, end 06:00–08:00, half hours",
    () => {
      assert.deepStrictEqual(qh.allowedStarts(), ["20:00", "20:30", "21:00",
        "21:30", "22:00", "22:30", "23:00"]);
      assert.deepStrictEqual(qh.allowedEnds(),
          ["06:00", "06:30", "07:00", "07:30", "08:00"]);
    });

t("research pushes (08:30, 10:00, 19:00) are outside every allowed window",
    () => {
      for (const s of qh.allowedStarts()) {
        for (const e of qh.allowedEnds()) {
          const u = {quietHoursStart: s, quietHoursEnd: e};
          for (const [h, m] of [[8, 30], [10, 0], [19, 0]]) {
            assert.strictEqual(qh.inQuietHours(u, hk(h, m), GLOBAL), false,
                `${s}–${e} at ${h}:${m}`);
          }
        }
      }
    });

t("no own values: exactly the global window (default 22:00–08:00)", () => {
  for (const u of [{}, null, undefined, {quietHoursEnabled: false}]) {
    const w = qh.windowFor(u, GLOBAL);
    assert.strictEqual(w.start, "22:00");
    assert.strictEqual(w.end, "08:00");
    assert.strictEqual(w.personalStart, false);
    assert.strictEqual(w.personalEnd, false);
  }
  // Same answer as the old function for every quarter hour of the day.
  for (let m = 0; m < 24 * 60; m += 15) {
    const at = hk(Math.floor(m / 60), m % 60);
    const old = m >= 22 * 60 || m < 8 * 60;
    assert.strictEqual(qh.inQuietHours({}, at, GLOBAL), old, `minute ${m}`);
  }
  // A changed global window is still followed by people without own values.
  const g = qh.quietHoursConfigFrom(
      {quietHoursStart: "21:00", quietHoursEnd: "07:00"});
  assert.strictEqual(qh.inQuietHours({}, hk(21, 30), g), true);
  assert.strictEqual(qh.inQuietHours({}, hk(7, 30), g), false);
});

t("own 20:00–06:00: 19:00 sends, 20:30 holds, 05:59 holds, 06:00 sends",
    () => {
      assert.strictEqual(qh.inQuietHours(ME, hk(19, 0), GLOBAL), false);
      assert.strictEqual(qh.inQuietHours(ME, hk(19, 59), GLOBAL), false);
      assert.strictEqual(qh.inQuietHours(ME, hk(20, 0), GLOBAL), true);
      assert.strictEqual(qh.inQuietHours(ME, hk(20, 30), GLOBAL), true);
      assert.strictEqual(qh.inQuietHours(ME, hk(5, 59, 22), GLOBAL), true);
      assert.strictEqual(qh.inQuietHours(ME, hk(6, 0, 22), GLOBAL), false);
      assert.strictEqual(qh.inQuietHours(ME, hk(7, 0, 22), GLOBAL), false);
    });

t("own values win over a different global window", () => {
  const g = qh.quietHoursConfigFrom(
      {quietHoursStart: "23:00", quietHoursEnd: "09:00"});
  assert.strictEqual(qh.inQuietHours(ME, hk(21, 0), g), true);
  assert.strictEqual(qh.inQuietHours(ME, hk(8, 0), g), false);
});

t("field by field: only 「由」 set → own start, global end", () => {
  const w = qh.windowFor({quietHoursStart: "21:00"}, GLOBAL);
  assert.deepStrictEqual([w.start, w.end, w.personalStart, w.personalEnd],
      ["21:00", "08:00", true, false]);
  const w2 = qh.windowFor({quietHoursEnd: "07:00"}, GLOBAL);
  assert.deepStrictEqual([w2.start, w2.end], ["22:00", "07:00"]);
});

t("own values outside the range move to the nearest edge", () => {
  const cases = [
    [{quietHoursStart: "19:00"}, "20:00", "08:00"],
    [{quietHoursStart: "23:30"}, "23:00", "08:00"],
    [{quietHoursStart: "02:00"}, "20:00", "08:00"],
    [{quietHoursEnd: "05:00"}, "22:00", "06:00"],
    [{quietHoursEnd: "09:00"}, "22:00", "08:00"],
    [{quietHoursEnd: "23:00"}, "22:00", "08:00"],
  ];
  for (const [u, s, e] of cases) {
    const w = qh.windowFor(u, GLOBAL);
    assert.deepStrictEqual([w.start, w.end], [s, e], JSON.stringify(u));
  }
  // Inside the range but not on a half hour: kept as it is.
  assert.strictEqual(qh.windowFor({quietHoursStart: "21:15"}, GLOBAL).start,
      "21:15");
});

t("malformed own values are ignored (global applies)", () => {
  for (const bad of ["7pm", "25:00", "21:60", "9:00", 2100, true, null,
    "", " 21:00"]) {
    const w = qh.windowFor({quietHoursStart: bad, quietHoursEnd: bad},
        GLOBAL);
    assert.deepStrictEqual([w.start, w.end], ["22:00", "08:00"],
        String(bad));
  }
});

t("quietEndAfter: when a push due inside the window may go out", () => {
  assert.strictEqual(qh.quietEndAfter(ME, hk(19, 0), GLOBAL), null);
  assert.strictEqual(qh.quietEndAfter(ME, hk(20, 30), GLOBAL).getTime(),
      hk(6, 0, 22).getTime());
  assert.strictEqual(qh.quietEndAfter(ME, hk(3, 10, 22), GLOBAL).getTime(),
      hk(6, 0, 22).getTime());
  assert.strictEqual(qh.quietEndAfter({}, hk(23, 0), GLOBAL).getTime(),
      hk(8, 0, 22).getTime());
});

t("reminders.classify: a reminder held overnight is not stale at the end",
    () => {
      const r = {kind: reminders.KIND, delivered: false,
        fireAt: "2026-10-21T20:00:00.000"};
      const u = {quietHoursStart: "20:00", quietHoursEnd: "08:00"};
      const at = reminders.parseFireAt(r.fireAt);
      const heldUntil = qh.quietEndAfter(u, at, GLOBAL);
      const morning = new Date(hk(8, 0, 22).getTime() + 20 * 1000);
      // 12 h 0 min 20 s after fireAt: stale without the hold, due with it.
      assert.strictEqual(reminders.classify(r,
          {now: morning, staleHours: 12}), "skipped_stale");
      assert.strictEqual(reminders.classify(r,
          {now: morning, staleHours: 12, heldUntil}), "due");
      // Still turns stale 12 h after the window's end.
      assert.strictEqual(reminders.classify(r, {now: hk(20, 1, 22),
        staleHours: 12, heldUntil}), "skipped_stale");
      // Default people: the old answer (window 10 h < staleHours 12 h).
      const d = {kind: reminders.KIND, delivered: false,
        fireAt: "2026-10-21T22:00:00.000"};
      const held = qh.quietEndAfter({}, reminders.parseFireAt(d.fireAt),
          GLOBAL);
      for (const now of [hk(8, 0, 22), hk(8, 15, 22), hk(9, 45, 22)]) {
        assert.strictEqual(reminders.classify(d, {now, staleHours: 12}),
            reminders.classify(d, {now, staleHours: 12, heldUntil: held}));
      }
    });

t("10/21 (decisions-log 118): the age counts from the end of the first " +
    "安靜時段 entered after fireAt", () => {
  const S = 12;
  const r = (fireAt) => ({kind: reminders.KIND, delivered: false, fireAt});
  const at = (rem) => reminders.parseFireAt(rem.fireAt);
  const verdict = (user, rem, now) => reminders.classify(rem, {now,
    staleHours: S,
    heldUntil: reminders.heldUntilFor(user, at(rem), GLOBAL, S)});
  // The audit case: window starts 20:00, reminder due 19:50.  The 20:00
  // run is inside the window; the next morning at 08:00 it goes out.
  const u = {quietHoursStart: "20:00", quietHoursEnd: "08:00"};
  const late = r("2026-10-21T19:50:00.000");
  assert.strictEqual(qh.inQuietHours(u, hk(20, 0), GLOBAL), true);
  assert.strictEqual(verdict(u, late, hk(8, 0, 22)), "due");
  assert.strictEqual(verdict(u, late, hk(8, 15, 22)), "due");
  // Before the change: 12 h 10 min after fireAt → skipped_stale.
  assert.strictEqual(reminders.classify(late,
      {now: hk(8, 0, 22), staleHours: S}), "skipped_stale");
  // Still turns stale 12 h after the window's end.
  assert.strictEqual(verdict(u, late, hk(20, 1, 22)), "skipped_stale");
  // Due long before the window (could have gone out by day): as before.
  const day = r("2026-10-21T15:00:00.000");
  assert.strictEqual(reminders.heldUntilFor(u, at(day), GLOBAL, S), null);
  assert.strictEqual(verdict(u, day, hk(8, 0, 22)), "skipped_stale");

  // Default 22:00–08:00: every outcome the same as before, for reminders
  // due through the day and night, checked from then until the next night.
  const fires = ["2026-10-21T08:00:00.000", "2026-10-21T10:00:00.000",
    "2026-10-21T15:00:00.000", "2026-10-21T19:50:00.000",
    "2026-10-21T21:45:00.000", "2026-10-21T21:50:00.000",
    "2026-10-21T22:00:00.000", "2026-10-21T23:30:00.000",
    "2026-10-22T03:00:00.000", "2026-10-22T07:55:00.000"];
  for (const f of fires) {
    const rem = r(f);
    const old = qh.quietEndAfter({}, at(rem), GLOBAL);
    for (let m = 0; m <= 40 * 60; m += 15) {
      const now = new Date(hk(8, 0).getTime() + m * 60000);
      assert.strictEqual(verdict({}, rem, now), reminders.classify(rem,
          {now, staleHours: S, heldUntil: old}), `${f} at +${m} min`);
    }
  }
});

t("the range is the same in functions, the App and firestore.rules", () => {
  const root = path.join(__dirname, "..", "..");
  const dart = fs.readFileSync(path.join(root,
      "lib/core/notifications/quiet_hours_range.dart"), "utf8");
  const constant = (name) => {
    const m = new RegExp(`${name} = '([0-9:]+)'`).exec(dart);
    assert.ok(m, name);
    return m[1];
  };
  assert.strictEqual(constant("startEarliest"), qh.RANGE.startEarliest);
  assert.strictEqual(constant("startLatest"), qh.RANGE.startLatest);
  assert.strictEqual(constant("endEarliest"), qh.RANGE.endEarliest);
  assert.strictEqual(constant("endLatest"), qh.RANGE.endLatest);
  assert.strictEqual(constant("defaultStart"), qh.DEFAULT_START);
  assert.strictEqual(constant("defaultEnd"), qh.DEFAULT_END);
  const step = /stepMinutes = (\d+);/.exec(dart);
  assert.strictEqual(Number(step[1]), qh.RANGE.stepMinutes);

  const rules = fs.readFileSync(path.join(root, "firestore.rules"), "utf8");
  const list = (fn) => {
    const m = new RegExp(`function ${fn}\\(\\) \\{\\s*return \\[([^\\]]*)\\]`)
        .exec(rules);
    assert.ok(m, fn);
    return m[1].split(",").map((s) => s.trim().replace(/'/g, ""));
  };
  assert.deepStrictEqual(list("quietStartValues"), qh.allowedStarts());
  assert.deepStrictEqual(list("quietEndValues"), qh.allowedEnds());
});

t("usage_events stamps quiet_hours_changed (not a lifecycle row)", () => {
  assert.deepStrictEqual(UE.QUIET_HOURS_TYPES, ["quiet_hours_changed"]);
  assert.ok(UE.TYPES.indexOf("quiet_hours_changed") >= 0);
  assert.ok(UE.LIFECYCLE_TYPES.indexOf("quiet_hours_changed") < 0);
  const now = new Date("2026-10-20T14:40:00Z");
  const s = UE.stampFor({
    type: "quiet_hours_changed", field: "start", from: "22:00", to: "20:30",
    clientAt: new Date("2026-10-20T14:39:58Z"), receivedAt: now,
    appVersion: "1.0.0", buildNumber: "9", platform: "android",
    schemaVersion: 1,
  }, {user: {w0Date: "2026-10-19", cohort: "rct"}, researchId: "RCT-01",
    now});
  assert.ok(s);
  assert.strictEqual(s.researchId, "RCT-01");
  assert.strictEqual(s.dayKey, "2026-10-20");
  assert.strictEqual(s.studyDay, 1);
  assert.strictEqual(s.uploadedLate, false);
});

console.log(`quiet_hours_1020o_test: ${n}/${n} passed`);
