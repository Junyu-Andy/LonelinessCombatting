/**
 * T7 hotline outbound filter — pure unit test (no emulator, no network).
 *
 * Run:  cd functions && node test/hotline_filter_test.js
 *
 * Cases come from test/fixtures/hotline_filter_cases.json, the same file
 * the Dart test (test/hotline_filter_test.dart) reads, so the server and
 * App filters are held to one list.
 */
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const hf = require("../hotline_filter");

const cases = JSON.parse(fs.readFileSync(path.join(
    __dirname, "..", "..", "test", "fixtures",
    "hotline_filter_cases.json"), "utf8"));

let n = 0;
for (const c of cases.phones) {
  const r = hf.filterHotlines(c.text);
  assert.strictEqual(r.count, c.count, `count for "${c.text}": ${r.text}`);
  assert.strictEqual(r.text.split(hf.HOTLINE_TOKEN).length - 1, c.count,
      `token count for "${c.text}"`);
  // No digit run of 8 (phone-length) survives.
  assert.ok(!/[0-9０-９]{4}[\s\-\u3000－]?[0-9０-９]{4}/
      .test(r.text), `number left in "${r.text}"`);
  n++;
}
for (const c of cases.nonPhones) {
  const r = hf.filterHotlines(c.text);
  assert.strictEqual(r.count, 0, `false positive in "${c.text}": ${r.text}`);
  assert.strictEqual(r.text, c.text);
  for (const k of c.keep) assert.ok(r.text.includes(k), `lost ${k}`);
  n++;
}

// Approved vs unapproved numbers (crisis_resources.json).
const mixed = hf.filterHotlines(
    "撒瑪利亞會 2896 0000，撒瑪利亞防止自殺會 2389 2222，同 999");
assert.strictEqual(mixed.count, 3);
const sum = hf.summarise(mixed.items);
assert.strictEqual(sum.approved_count, 2, "2896 0000 and 999 are approved");
assert.strictEqual(sum.unapproved_count, 1, "2389 2222 is not on the list");
assert.deepStrictEqual(sum.kinds, {hk8: 2, emergency: 1});
// The log summary never carries the number itself.
assert.ok(!JSON.stringify(sum).match(/2896|2389|999/));

// +852 prefix is stripped before the approved-list lookup.
assert.strictEqual(hf.summarise(
    hf.filterHotlines("+852 2382 0000").items).approved_count, 1);

// Empty / non-string input is passed through.
assert.deepStrictEqual(hf.filterHotlines(""), {text: "", count: 0, items: []});
assert.deepStrictEqual(hf.filterHotlines(null),
    {text: "", count: 0, items: []});

// The token the App renders must be the one the prompt rule asks for.
const rule = fs.readFileSync(path.join(__dirname, "..", "prompts",
    `${hf.PROMPT_RULE_KEY}.txt`), "utf8");
assert.ok(rule.includes(hf.HOTLINE_TOKEN), "prompt rule names the token");
assert.ok(/v1 \(rev 2026-10\)/.test(rule.split("\n")[0]), "rule header");

console.log(`hotline_filter_test: ${n} fixture cases + extras OK`);
