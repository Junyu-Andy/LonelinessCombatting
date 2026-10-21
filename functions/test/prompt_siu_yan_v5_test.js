/**
 * 10/21 (decisions-log 10/21 第 134 条) — 小欣 prompt v5.  Pure: reads the
 * prompt files, no Firestore.
 *
 *   - siu_yan.v5.txt = siu_yan.v4.txt with the header bumped to v5 and v4
 *     lines 17–22 (小欣 may offer 「望一望心入面」 in the chat with the
 *     locked 「…stuck…」 sentence) replaced by ONE line: do not offer it,
 *     the App shows the invite card; nothing else changed.
 *   - The registry maps the new key siu_yan_v5 → siu_yan.v5; siu_yan_v4
 *     still loads v4 (older builds).
 *   - v4 stays byte-identical (CLAUDE.md: never overwrite a prompt).
 *
 * Run:  cd functions && node test/prompt_siu_yan_v5_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const reg = require("../prompt_registry");

const PROMPTS = path.join(__dirname, "..", "prompts");
const read = (f) => fs.readFileSync(path.join(PROMPTS, f), "utf8");
const sha = (f) => crypto.createHash("sha256").update(
    fs.readFileSync(path.join(PROMPTS, f))).digest("hex");

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

const V4 = "siu_yan.v4.txt";
const V5 = "siu_yan.v5.txt";
const NEW_LINE = "唔好喺對話中主動提議「望一望心入面」或者其他練習，" +
    "系統會喺適當時候自己彈出邀請卡。如果用戶自己問起，可以話佢知喺" +
    "「做啲嘢」入面搵到，你唔使喺對話中帶佢做。";

test("v4 untouched (hash as pinned in build_info.g.dart)", () => {
  assert.strictEqual(sha(V4),
      "fe5029cf79b8d872ac935d3432482b6756f08f691c99c65fc43a319b912ef5d4");
});

test("registry: siu_yan_v5 → v5 (siu_yan_v5@2026-10); v4 still v4", () => {
  assert.strictEqual(reg.promptFileFor("siu_yan_v5"), "siu_yan.v5");
  assert.strictEqual(reg.promptFileFor("siu_yan_v4"), "siu_yan.v4");
  assert.strictEqual(reg.loadPrompt("siu_yan_v5"), read(V5));
  assert.strictEqual(reg.loadPrompt("siu_yan_v4"), read(V4));
  assert.strictEqual(reg.promptVersionFor("siu_yan_v5"), "siu_yan_v5@2026-10");
  assert.strictEqual(reg.promptVersionFor("siu_yan_v4"), "siu_yan_v4@2026-10");
});

test("v5 = v4 with the header and lines 17–22 replaced by one line", () => {
  const v4 = read(V4).split("\n");
  const v5 = read(V5).split("\n");
  assert.strictEqual(v5[0],
      "## 小欣 — Daily Companion · PPR-Caring · v5 (rev 2026-10)");
  assert.ok(v4[16].startsWith("- 你係**唯一**有權喺對話中提議「望一望心入面」"));
  assert.ok(v4[21].includes("你**唔再喺對話中參與**個練習"));
  assert.strictEqual(v5[16], NEW_LINE);
  const rebuilt = [v4[0]].concat(v5.slice(1, 16), v4.slice(16, 22),
      v5.slice(17));
  assert.strictEqual(rebuilt.join("\n"), v4.join("\n"));
});

test("v5 never tells 小欣 to offer the exercise or say the stuck line", () => {
  const v5 = read(V5);
  assert.ok(!v5.includes("stuck"));
  assert.ok(!v5.includes("提議時機"));
  assert.ok(!v5.includes("鎖定句式"));
  assert.ok(!v5.includes("要唔要做個小練習"));
  // The tone slot and the check-in / mood sections are still there.
  assert.ok(v5.includes("{{TONE_RULE}}"));
  assert.ok(v5.includes("# 每日 check-in（App 對話形式）"));
  assert.ok(v5.includes("# 從首頁心情入嚟（開場）"));
});

console.log(`\n${passed} passed, ${failures.length} failed.`);
if (failures.length) process.exit(1);
