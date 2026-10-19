/**
 * dev-tasks-1020 batch 4 — the push texts and the e-mail subject in
 * functions/push_copy.js match docs/spec/copy/push-and-email-1020.md word
 * for word, and match 1020b §4 (5.3, 5.5).  Pure, no emulator.
 *
 * Run:  cd functions && node test/push_copy_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const pc = require("../push_copy");

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

const SPEC = fs.readFileSync(path.join(__dirname, "..", "..", "docs", "spec",
    "copy", "push-and-email-1020.md"), "utf8");

/**
 * @param {string} id e.g. "P1"
 * @return {string} last cell of the table row whose first cell is `id`
 */
function specText(id) {
  for (const line of SPEC.split("\n")) {
    const cells = line.split("|").map((c) => c.trim());
    if (cells[1] === id) return cells[cells.length - 2];
  }
  throw new Error(`${id} not in push-and-email-1020.md`);
}

// 1020b §4, verbatim (the product window's draft of 10/19).
const HANDOFF = {
  "P1": "小欣想問下你尋日過得點。",
  "P2": "今日仲未同小欣傾，得閒入嚟講兩句。",
  "W1": "上個禮拜嘅問卷開咗，得閒入嚟分享下你嘅感受。",
  "W2": "上個禮拜嘅問卷聽日截止，記得入嚟答埋佢。",
  "W3": "今日係上個禮拜問卷嘅最後一日，盡快答埋佢啦。",
  "W1-4": "今個禮拜嘅問卷開咗，得閒入嚟分享下你嘅感受。",
  "W2-4": "今個禮拜嘅問卷聽日截止，記得入嚟答埋佢。",
  "W3-4": "今日係今個禮拜問卷嘅最後一日，盡快答埋佢啦。",
};

test("every push text matches the copy file", () => {
  assert.deepStrictEqual(Object.keys(pc.TEXT).sort(),
      Object.keys(HANDOFF).sort());
  for (const id of Object.keys(pc.TEXT)) {
    assert.strictEqual(pc.TEXT[id], specText(id), id);
  }
});

test("every push text is 1020b §4 verbatim", () => {
  for (const id of Object.keys(HANDOFF)) {
    assert.strictEqual(pc.TEXT[id], HANDOFF[id], id);
  }
});

test("E1 subject matches the copy file and 1020b §4", () => {
  assert.strictEqual(pc.E1_SUBJECT, specText("E1"));
  assert.strictEqual(pc.E1_SUBJECT, "陪住：今日截止嘅每週問卷未完成名單");
});

test("no placeholder mark, title 陪住, test kinds name real texts", () => {
  for (const id of Object.keys(pc.TEXT)) {
    assert.ok(pc.TEXT[id].indexOf("【占位】") < 0, id);
  }
  assert.strictEqual(pc.PUSH_TITLE, "陪住");
  for (const k of Object.keys(pc.TEST_PUSH_KINDS)) {
    assert.ok(pc.TEXT[pc.TEST_PUSH_KINDS[k]], k);
  }
});

console.log(`\n${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
