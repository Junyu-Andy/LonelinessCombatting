/**
 * dev-tasks-1020 batch 4 — the push texts and the e-mail subject in
 * functions/push_copy.js match docs/spec/copy/push-and-email-1020.md word
 * for word, and match the hand-offs (1020b §4 5.3, 5.5; 1020e 二.1(4),
 * 二.2(2)).  Pure, no emulator.
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

// The hand-offs, verbatim: P1 / P2 from 1020b §4 5.3 (10/19 draft); the
// weekly texts from 1020e 二.1(4) (week 1 shown; 第N週 follows the week)
// and 二.2(2).
const HANDOFF = {
  "P1": "小欣想問下你尋日過得點。",
  "P2": "今日仲未同小欣傾，得閒入嚟講兩句。",
};
const HANDOFF_WEEK1 = {
  "W-pre": "聽日第一週問卷就開，記得聽日得閒入嚟答呀。",
  "W-open": "第一週問卷開咗，快啲入嚟答啦。",
  "W-rem1": "第一週問卷聽日截止，開咗一日喇，得閒入嚟答埋佢。",
  "W-rem2": "今日係第一週問卷最後一日，記得今日一定要答埋佢。",
};
const HANDOFF_WEEK4 = {
  "W4-pre": "聽日第四週問卷就開，記得聽日得閒入嚟答呀。",
  "W4-open": "第四週嘅問卷開咗，記得喺見面之前答埋佢。",
  "W4-rem": "第四週嘅問卷仲未答完，得閒入嚟答埋佢；見面嗰日都可以補。",
};

test("every push text matches the copy file", () => {
  assert.deepStrictEqual(Object.keys(pc.TEXT).sort(), Object.keys(
      Object.assign({}, HANDOFF, HANDOFF_WEEK1, HANDOFF_WEEK4)).sort());
  for (const id of Object.keys(pc.TEXT)) {
    assert.strictEqual(pc.TEXT[id], specText(id), id);
  }
});

test("every push text is the hand-off verbatim; 第N週 follows the week",
    () => {
      for (const id of Object.keys(HANDOFF)) {
        assert.strictEqual(pc.TEXT[id], HANDOFF[id], id);
      }
      for (const id of Object.keys(HANDOFF_WEEK1)) {
        assert.strictEqual(pc.weeklyText(id, 1), HANDOFF_WEEK1[id], id);
        assert.ok(pc.weeklyText(id, 2).indexOf("第二週") >= 0, id);
        assert.ok(pc.weeklyText(id, 3).indexOf("第三週") >= 0, id);
        assert.ok(pc.weeklyText(id, 3).indexOf("{N}") < 0, id);
      }
      for (const id of Object.keys(HANDOFF_WEEK4)) {
        assert.strictEqual(pc.weeklyText(id, 4), HANDOFF_WEEK4[id], id);
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
    const text = pc.testKindText(pc.TEST_PUSH_KINDS[k]);
    assert.ok(text && text.indexOf("{N}") < 0, k);
  }
  assert.strictEqual(pc.testKindText(pc.TEST_PUSH_KINDS.weekly_open),
      HANDOFF_WEEK1["W-open"]);
});

console.log(`\n${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
