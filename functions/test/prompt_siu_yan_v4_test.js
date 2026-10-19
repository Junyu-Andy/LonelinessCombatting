/**
 * 1020 E (batch 3) — 小欣 prompt v4 for the mood-row opener
 * (App switch moodRowV2Enabled).  Pure: reads the prompt files, no
 * Firestore.
 *
 *   - siu_yan.v4.txt = siu_yan.v3.txt with the header bumped to v4 and ONE
 *     new section 「從首頁心情入嚟（開場）」; nothing else changed.
 *   - The registry maps the new key siu_yan_v4 → siu_yan.v4; siu_yan_v3
 *     still loads v3 and siu_yan_v1 still loads v2.
 *   - v2 and v3 stay byte-identical (CLAUDE.md: never overwrite a prompt).
 *
 * Run:  cd functions && node test/prompt_siu_yan_v4_test.js
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

const V3 = "siu_yan.v3.txt";
const V4 = "siu_yan.v4.txt";
const SECTION = "# 從首頁心情入嚟（開場）";

test("v2 and v3 untouched (hashes as pinned in build_info.g.dart)", () => {
  assert.strictEqual(sha("siu_yan.v2.txt"),
      "e8dd1172b91a10affe6f24db65c0672c58fa7ba8d4a508b5582daefd4ad7a827");
  assert.strictEqual(sha(V3),
      "ee31cf5109f1599f03ad388a9670d90a256782491b926c666f01099a0458a491");
});

test("registry: siu_yan_v4 → v4; siu_yan_v3 → v3; siu_yan_v1 → v2", () => {
  assert.strictEqual(reg.promptFileFor("siu_yan_v4"), "siu_yan.v4");
  assert.strictEqual(reg.promptFileFor("siu_yan_v3"), "siu_yan.v3");
  assert.strictEqual(reg.promptFileFor("siu_yan_v1"), "siu_yan.v2");
  assert.strictEqual(reg.loadPrompt("siu_yan_v4"), read(V4));
  assert.strictEqual(reg.loadPrompt("siu_yan_v3"), read(V3));
  assert.strictEqual(reg.promptVersionFor("siu_yan_v4"), "siu_yan_v4@2026-10");
  assert.strictEqual(reg.promptVersionFor("siu_yan_v3"), "siu_yan_v3@2026-10");
});

test("v4 = v3 + header + the mood-opener section only", () => {
  const v3 = read(V3).split("\n");
  const v4 = read(V4).split("\n");
  assert.strictEqual(v4[0],
      "## 小欣 — Daily Companion · PPR-Caring · v4 (rev 2026-10)");
  const start = v4.indexOf(SECTION);
  assert.ok(start > 0, "section present");
  const end = v4.indexOf("# Cross-referral 候選（每對話最多一次）");
  assert.ok(end > start, "section sits before Cross-referral");
  assert.ok(start > v4.indexOf("# 每日 check-in（App 對話形式）"),
      "after the check-in section");
  // Removing the header line and the section gives v3 back exactly.
  const rebuilt = [v3[0]].concat(v4.slice(1, start), v4.slice(end));
  assert.strictEqual(rebuilt.join("\n"), v3.join("\n"));
});

test("the section: marker, one open question, gentle when low, no advice",
    () => {
      const v4 = read(V4);
      const section = v4.slice(v4.indexOf(SECTION),
          v4.indexOf("# Cross-referral"));
      assert.ok(section.includes("[開場·心情]"), "marker");
      // The App strings it must match (lib/.../mood_row_copy.dart M7, M8).
      assert.ok(section.includes("想同小欣講詳細啲？"), "M7");
      assert.ok(section.includes("心情好似唔同咗，想同小欣講下發生咩事？"), "M8");
      assert.ok(section.includes("發生咗咩事"), "asks what happened");
      assert.ok(section.includes("只可以問一條"), "one question only");
      assert.ok(section.includes("唔好俾建議"), "no advice");
      assert.ok(section.includes("唔好問 check-in 嘅問題"), "not the check-in");
      assert.ok(section.includes("好咗定差咗"), "M8 change named");
      for (const w of ["AI", "模型", "機械人"]) {
        assert.ok(!section.includes(w), w);
      }
    });

test("tone slot filled exactly once, as v3", () => {
  const filled = reg.fillSlots(read(V4), {encouragementStyle: "direct"});
  assert.ok(!filled.includes("{{TONE_RULE}}"));
  assert.strictEqual(filled.split(reg.TONE_RULES.direct).length, 2);
});

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length) process.exit(1);
