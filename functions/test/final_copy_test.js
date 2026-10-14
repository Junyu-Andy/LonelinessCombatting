/**
 * T33 — server-side final copy matches docs/spec/copy/short-texts.md
 * word for word (S2 forget confirmation, S4a M7 reminder push).
 *
 * Run:  cd functions && node test/final_copy_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const m = require("../memory");
const reminders = require("../reminders");

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

const SPEC = fs.readFileSync(path.join(__dirname, "..", "..",
    "docs", "spec", "copy", "short-texts.md"), "utf8");

/**
 * @param {string} id e.g. "S2"
 * @return {string} text column of that `| Sx | where | text | … |` row
 */
function specText(id) {
  for (const line of SPEC.split("\n")) {
    const cells = line.split("|").map((c) => c.trim());
    if (cells[1] === id) return cells[3];
  }
  throw new Error(`${id} not in short-texts.md`);
}

function prompt(name) {
  return fs.readFileSync(path.join(__dirname, "..", "prompts",
      `${name}.txt`), "utf8");
}

test("S4a: M7 reminder push body is the final text", () => {
  assert.strictEqual(reminders.PUSH_BODY, specText("S4a"));
  assert.strictEqual(reminders.PUSH_TITLE, "陪住");
});

test("S2: forget-ack v2 quotes the final text verbatim", () => {
  assert.strictEqual(m.FORGET_ACK_PROMPT, "memory_forget_ack.v2");
  assert.ok(prompt("memory_forget_ack.v2").includes(`「${specText("S2")}」`));
});

test("S2: v1 is kept unchanged (no overwrite)", () => {
  assert.ok(prompt("memory_forget_ack.v1").includes("【待研究側定稿】"));
});

test("S2: the confirmation is used on a forget request", () => {
  const msgs = [{role: "user", content: "你唔好記住呢件事呀"}];
  assert.ok(m.forgetAck(msgs).includes(specText("S2")));
});

console.log(`\n${passed} passed, ${failures.length} failed.`);
if (failures.length) process.exit(1);
