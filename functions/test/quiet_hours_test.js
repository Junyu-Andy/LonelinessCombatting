"use strict";
// 10/14 — 安靜時段: users/{uid}.quietHoursEnabled + app_config/reminders window.
const assert = require("assert");
const qh = require("../quiet_hours");

let n = 0;
/**
 * @param {string} name
 * @param {function(): void} fn
 */
function t(name, fn) {
  fn(); n++; console.log(`ok - ${name}`);
}
// Build a Date at a Hong Kong wall-clock time.
const hk = (h, m) => new Date(Date.UTC(2026, 9, 20, h - 8, m || 0));

t("defaults are 22:00–08:00", () => {
  const c = qh.quietHoursConfigFrom({});
  assert.strictEqual(c.start, "22:00");
  assert.strictEqual(c.end, "08:00");
});
t("bad config falls back to defaults", () => {
  const c = qh.quietHoursConfigFrom(
      {quietHoursStart: "25:99", quietHoursEnd: 7});
  assert.strictEqual(c.start, "22:00");
  assert.strictEqual(c.end, "08:00");
});
t("missing field = on; inside the night window blocks", () => {
  const c = qh.quietHoursConfigFrom({});
  assert.strictEqual(qh.inQuietHours({}, hk(23, 30), c), true);
  assert.strictEqual(qh.inQuietHours({}, hk(3, 0), c), true);
  assert.strictEqual(qh.inQuietHours({}, hk(7, 59), c), true);
});
t("boundaries: start inclusive, end exclusive", () => {
  const c = qh.quietHoursConfigFrom({});
  assert.strictEqual(qh.inQuietHours({}, hk(22, 0), c), true);
  assert.strictEqual(qh.inQuietHours({}, hk(8, 0), c), false);
  assert.strictEqual(qh.inQuietHours({}, hk(21, 59), c), false);
});
t("daytime never blocks with the default window", () => {
  const c = qh.quietHoursConfigFrom({});
  for (let h = 8; h < 22; h++) {
    assert.strictEqual(
        qh.inQuietHours({}, hk(h, 15), c), false, `hour ${h}`);
  }
});
t("toggle off = never blocks", () => {
  const c = qh.quietHoursConfigFrom({});
  assert.strictEqual(
      qh.inQuietHours({quietHoursEnabled: false}, hk(23, 0), c), false);
});
t("toggle true behaves like missing", () => {
  const c = qh.quietHoursConfigFrom({});
  assert.strictEqual(
      qh.inQuietHours({quietHoursEnabled: true}, hk(23, 0), c), true);
});
t("same-day window (13:00–15:00) and zero-length window", () => {
  const c = qh.quietHoursConfigFrom(
      {quietHoursStart: "13:00", quietHoursEnd: "15:00"});
  assert.strictEqual(qh.inQuietHours({}, hk(14, 0), c), true);
  assert.strictEqual(qh.inQuietHours({}, hk(16, 0), c), false);
  const z = qh.quietHoursConfigFrom(
      {quietHoursStart: "09:00", quietHoursEnd: "09:00"});
  assert.strictEqual(qh.inQuietHours({}, hk(9, 0), z), false);
});
t("reminders.readConfig-style data carries the window", () => {
  const reminders = require("../reminders");
  assert.ok(typeof reminders.classify === "function");
});
console.log(`quiet_hours_test: ${n}/${n} passed`);
