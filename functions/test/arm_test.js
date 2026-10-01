/**
 * Server-side arm assignment — pure logic.  Strata cases mirror the Dart
 * suite (test/sprint4_spec_alignment_test.dart) so client and server agree.
 *
 * Run:  cd functions && node test/arm_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const {strataCell, chooseArm} = require("../arm");

let passed = 0;
const failures = [];
function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`PASS  ${name}`);
  } catch (err) {
    failures.push(name);
    console.log(`FAIL  ${name}\n      ${err.message}`);
  }
}

test("strata cells match the client helper", () => {
  assert.strictEqual(strataCell({uclaScore: 30, ageGroup: "60-64"}), 0);
  assert.strictEqual(strataCell({uclaScore: 30, ageGroup: "70-74"}), 1);
  assert.strictEqual(strataCell({uclaScore: 60, ageGroup: "60-64"}), 2);
  assert.strictEqual(strataCell({uclaScore: 60, ageGroup: "75+"}), 3);
});

test("median split: 44 is low, 45 is high", () => {
  assert.strictEqual(strataCell({uclaScore: 44, ageGroup: "65-69"}), 0);
  assert.strictEqual(strataCell({uclaScore: 45, ageGroup: "65-69"}), 2);
});

test("missing baseline falls into the low / younger cell", () => {
  assert.strictEqual(strataCell({}), 0);
  assert.strictEqual(strataCell({uclaScore: null, ageGroup: "70-74"}), 1);
});

test("phase A mode always assigns A", () => {
  const rng = () => 0.9;
  assert.strictEqual(chooseArm({aCount: 5, bCount: 0}, {randomise: false, rng}),
      "A");
});

test("randomise mode balances within the cell", () => {
  const rng = () => 0.1;
  assert.strictEqual(chooseArm({aCount: 3, bCount: 1}, {randomise: true, rng}),
      "B");
  assert.strictEqual(chooseArm({aCount: 1, bCount: 3}, {randomise: true, rng}),
      "A");
});

test("a tie is decided by the coin", () => {
  const tie = {aCount: 2, bCount: 2};
  assert.strictEqual(chooseArm(tie, {randomise: true, rng: () => 0.2}), "A");
  assert.strictEqual(chooseArm(tie, {randomise: true, rng: () => 0.7}), "B");
});

console.log(`\n${passed} passed, ${failures.length} failed.`);
if (failures.length) process.exit(1);
