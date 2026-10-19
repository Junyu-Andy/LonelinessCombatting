/**
 * 1020 F (batch 2) — 小欣 prompt v3 for the chat check-in
 * (App switch checkInChatV2Enabled).  Pure: reads the prompt files, no
 * Firestore.
 *
 *   - siu_yan.v3.txt = siu_yan.v2.txt with the header bumped to v3 and ONE
 *     new section 「每日 check-in（App 對話形式）」; nothing else changed.
 *   - The registry maps the new key siu_yan_v3 → siu_yan.v3; the key every
 *     other 小欣 call sends (siu_yan_v1) still loads v2.
 *   - v2 stays byte-identical (CLAUDE.md: never overwrite a prompt).
 *
 * Run:  cd functions && node test/prompt_siu_yan_v3_test.js
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

const V2 = "siu_yan.v2.txt";
const V3 = "siu_yan.v3.txt";
const SECTION = "# 每日 check-in（App 對話形式）";

test("v2 untouched (hash as pinned in build_info.g.dart)", () => {
  assert.strictEqual(sha(V2),
      "e8dd1172b91a10affe6f24db65c0672c58fa7ba8d4a508b5582daefd4ad7a827");
});

test("registry: siu_yan_v3 → v3; siu_yan_v1 still → v2", () => {
  assert.strictEqual(reg.promptFileFor("siu_yan_v3"), "siu_yan.v3");
  assert.strictEqual(reg.promptFileFor("siu_yan_v1"), "siu_yan.v2");
  assert.strictEqual(reg.loadPrompt("siu_yan_v3"), read(V3));
  assert.strictEqual(reg.loadPrompt("siu_yan_v1"), read(V2));
  assert.strictEqual(reg.promptVersionFor("siu_yan_v3"), "siu_yan_v3@2026-10");
  assert.strictEqual(reg.promptVersionFor("siu_yan_v1"), "siu_yan_v2@2026-10");
});

test("v3 = v2 + header + the check-in section only", () => {
  const v2 = read(V2).split("\n");
  const v3 = read(V3).split("\n");
  assert.strictEqual(v3[0],
      "## 小欣 — Daily Companion · PPR-Caring · v3 (rev 2026-10)");
  const start = v3.indexOf(SECTION);
  assert.ok(start > 0, "section present");
  const end = v3.indexOf("# Cross-referral 候選（每對話最多一次）");
  assert.ok(end > start, "section sits before Cross-referral");
  // Removing the header line and the section gives v2 back exactly.
  const rebuilt = [v2[0]].concat(v3.slice(1, start), v3.slice(end));
  // The section block is followed by one blank line of its own.
  const v2Text = v2.join("\n");
  const rebuiltText = rebuilt.join("\n");
  assert.strictEqual(rebuiltText, v2Text);
});

test("the section covers reply 1, reply 2, the opener, today's answers",
    () => {
      const v3 = read(V3);
      const section = v3.slice(v3.indexOf(SECTION),
          v3.indexOf("# Cross-referral"));
      for (const marker of ["[簽到·回應一]", "[簽到·回應二]",
        "[開場·check-in 已做]", "[今日 check-in]"]) {
        assert.ok(section.includes(marker), marker);
      }
      assert.ok(section.includes("唔好重複問"), "never asks the questions");
      assert.ok(section.includes("最多提一兩個"), "reply 2: at most one or two");
      assert.ok(section.includes("唔好催促"), "reply 2: no pushing");
      assert.ok(section.includes("唔好俾建議"), "reply 1: no advice");
      assert.ok(section.includes("唔使俾建議"), "唔講住: no advice");
      assert.ok(section.includes("Q1 揀「唔想答」"), "Q1 prefer-not");
      // The App strings it must match (lib/.../siu_yan_chat_page.dart).
      assert.ok(section.includes("尋日成日整體過得點？"));
      assert.ok(section.includes("今日有咩打算？"));
      // Same identity rule as v2: no banned self-description added.
      for (const w of ["AI", "模型", "機械人"]) {
        assert.ok(!section.includes(w), w);
      }
    });

test("tone slot filled exactly once, as v2", () => {
  const filled = reg.fillSlots(read(V3), {encouragementStyle: "gentle"});
  assert.ok(!filled.includes("{{TONE_RULE}}"));
  assert.strictEqual(filled.split(reg.TONE_RULES.gentle).length, 2);
});

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length) process.exit(1);
