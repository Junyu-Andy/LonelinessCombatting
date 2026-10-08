/**
 * T19 (decision 0029) — pure logic: strata, research IDs, W0 dates, the
 * permuted-block generator, and the arm-neutral PI alert / email.
 *
 * Run:  cd functions && node test/randomization_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const R = require("../randomization");
const piAlert = require("../pi_alert");

let passed = 0;
const failures = [];
function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`ok - ${name}`);
  } catch (err) {
    failures.push(name);
    console.log(`FAIL - ${name}\n      ${err.stack}`);
  }
}

test("strata: 0–1 low, 2–3 high, anything else refused", () => {
  assert.strictEqual(R.stratumFor(0), "low");
  assert.strictEqual(R.stratumFor(1), "low");
  assert.strictEqual(R.stratumFor(2), "high");
  assert.strictEqual(R.stratumFor(3), "high");
  for (const bad of [-1, 4, 1.5, "2", null, undefined, NaN]) {
    assert.strictEqual(R.stratumFor(bad), null, String(bad));
  }
});

test("research IDs: trimmed, upper-cased, 2–12 of A–Z 0–9 -", () => {
  assert.strictEqual(R.normaliseResearchId(" b001 "), "B001");
  assert.strictEqual(R.normaliseResearchId("PB-017"), "PB-017");
  for (const bad of ["", "B", "-B01", "B 01", "B001B001B001X", 7, null,
    "abcdefghijklmnopqrstuvwxyz12"]) {
    assert.strictEqual(R.normaliseResearchId(bad), null, String(bad));
  }
});

test("W0 date: real calendar date, not in the future (HK)", () => {
  // 2026-10-07 20:00 UTC = 2026-10-08 04:00 HKT.
  const now = new Date("2026-10-07T20:00:00Z");
  assert.strictEqual(R.validW0Date("2026-10-08", now), "2026-10-08");
  assert.strictEqual(R.validW0Date("2026-10-09", now), null);
  assert.strictEqual(R.validW0Date("2026-02-30", now), null);
  assert.strictEqual(R.validW0Date("8/10/2026", now), null);
  assert.strictEqual(R.hkDateKey(now), "2026-10-08");
});

test("generator: same seed → same sequences; other seed → different", () => {
  const a = R.generateSequences("keran-chosen-seed-0001");
  const b = R.generateSequences("keran-chosen-seed-0001");
  const c = R.generateSequences("keran-chosen-seed-0002");
  assert.deepStrictEqual(a, b);
  assert.notStrictEqual(a.low.sha256, c.low.sha256);
  assert.notStrictEqual(a.low.sha256, a.high.sha256, "strata independent");
});

test("generator: ≥ 60 positions, whole blocks of 2 and 4, each 1:1", () => {
  for (let i = 0; i < 200; i++) {
    const seqs = R.generateSequences(`property-test-seed-${i}`);
    for (const s of R.STRATA) {
      const q = seqs[s];
      assert.ok(q.length >= 60 && q.length <= 63, `${s} ${q.length}`);
      assert.ok(R.sequenceValid(q), `${s} seed ${i}`);
      const a = q.arms.filter((x) => x === "A").length;
      assert.strictEqual(a * 2, q.length, "1:1 overall");
      assert.strictEqual(q.sha256, R.sequenceHash(q.arms));
    }
  }
});

test("generator: both block sizes occur, in roughly equal numbers", () => {
  let two = 0;
  let four = 0;
  for (let i = 0; i < 100; i++) {
    const q = R.generateSequences(`block-mix-seed-${i}`).low;
    two += q.blocks.filter((b) => b === 2).length;
    four += q.blocks.filter((b) => b === 4).length;
  }
  const share = two / (two + four);
  assert.ok(share > 0.45 && share < 0.55, `share of size-2 blocks ${share}`);
});

test("generator: refuses a short seed or fewer than 60 positions", () => {
  assert.throws(() => R.generateSequences("short"), /seed_too_short/);
  assert.throws(() => R.generateSequences("long-enough-seed-01", 40),
      /length_below_minimum/);
});

test("sequenceValid rejects unbalanced or unknown blocks", () => {
  const ok = R.generateSequences("validity-seed-000001").low;
  const bad = {arms: ok.arms.slice(), blocks: ok.blocks.slice()};
  bad.arms[0] = bad.arms[0] === "A" ? "B" : "A";
  assert.strictEqual(R.sequenceValid(bad), false);
  assert.strictEqual(R.sequenceValid({arms: ["A", "B", "A"], blocks: [3]}),
      false);
});

test("PI alert and email are identical for the two arms", () => {
  // Same level, different arm-revealing inputs: the builders take none.
  const base = {uid: "u1", researchId: "B001", level: "acute",
    dedupKey: "k", isTester: false, eventPath: "safety_events/e1"};
  const alert = piAlert.buildPiAlert(base, "TS");
  assert.deepStrictEqual(Object.keys(alert).sort(), ["alertVersion",
    "createdAt", "dedupKey", "eventPath", "isTester", "level",
    "researchId", "uid"]);
  const at = new Date("2026-10-07T02:30:00Z");
  const mail = piAlert.buildPiEmail({researchId: "B001", alertId: "x1", at});
  assert.match(mail.text, /Research ID: B001/);
  assert.match(mail.text, /Time \(HKT\): 2026-10-07 10:30/);
  for (const leak of ["siu_yan", "tung_tung", "ah_jan", "gateway",
    "rule_turn", "ai_output_scan", "chat_", "Agent:", "Source:",
    "Input point:", "Arm", "Hybrid"]) {
    assert.ok(!mail.text.includes(leak) && !mail.subject.includes(leak),
        leak);
  }
  const unregistered = piAlert.buildPiEmail({researchId: null,
    alertId: "x2", at});
  assert.match(unregistered.text, /not registered yet/);
});

console.log(`\n${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
