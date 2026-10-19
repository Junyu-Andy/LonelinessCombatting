/**
 * 1020d §2 (3) — 阿珍／阿伯 prompt v3 for reminiscence v2 (App switch
 * reminiscenceV2Enabled).  Pure: reads the prompt files, no Firestore.
 *
 *   - ah_jan_ah_bak.v3.txt = ah_jan_ah_bak.v2.txt with the header bumped to
 *     v3 and ONE new section 「每題之後」; nothing else changed.
 *   - The registry maps the new key ah_jan_ah_bak_v3 → ah_jan_ah_bak.v3;
 *     the key every other 阿珍／阿伯 call sends (ah_jan_ah_bak_v1) still
 *     loads v2.
 *   - v2 stays byte-identical (CLAUDE.md: never overwrite a prompt).
 *   - The section names the three markers the App puts on the first line
 *     of the context suffix, and the fields under them (the contract with
 *     the App side).
 *
 * Run:  cd functions && node test/prompt_ah_jan_ah_bak_v3_test.js
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

const V2 = "ah_jan_ah_bak.v2.txt";
const V3 = "ah_jan_ah_bak.v3.txt";
const SECTION = "# 每題之後（回憶 v2：App 逐題問）";
const NEXT = "# 負面認知處理（最關鍵 — spec §2.2）";

function section() {
  const v3 = read(V3);
  return v3.slice(v3.indexOf(SECTION), v3.indexOf(NEXT));
}

test("v2 untouched (hash as pinned in build_info.g.dart)", () => {
  assert.strictEqual(sha(V2),
      "3e93815b7f6174e8dd34369756b57877586cd5ab87e50ad988a91e2d5c06eb74");
});

test("registry: ah_jan_ah_bak_v3 → v3; ah_jan_ah_bak_v1 still → v2", () => {
  assert.strictEqual(reg.promptFileFor("ah_jan_ah_bak_v3"),
      "ah_jan_ah_bak.v3");
  assert.strictEqual(reg.promptFileFor("ah_jan_ah_bak_v1"),
      "ah_jan_ah_bak.v2");
  assert.strictEqual(reg.loadPrompt("ah_jan_ah_bak_v3"), read(V3));
  assert.strictEqual(reg.loadPrompt("ah_jan_ah_bak_v1"), read(V2));
  assert.strictEqual(reg.promptVersionFor("ah_jan_ah_bak_v3"),
      "ah_jan_ah_bak_v3@2026-10");
  assert.strictEqual(reg.promptVersionFor("ah_jan_ah_bak_v1"),
      "ah_jan_ah_bak_v2@2026-10");
  // The other keys are as before.
  assert.strictEqual(reg.promptFileFor("siu_yan_v1"), "siu_yan.v2");
  assert.strictEqual(reg.promptFileFor("siu_yan_v3"), "siu_yan.v3");
  assert.strictEqual(reg.promptFileFor("tung_tung_v1"), "tung_tung.v3");
});

test("v3 = v2 + header + the 每題之後 section only", () => {
  const v2 = read(V2).split("\n");
  const v3 = read(V3).split("\n");
  assert.strictEqual(v3[0], "## {{VARIANT_NAME}} — Reflective " +
      "Peer-Listener · PPR-Understanding · v3 (rev 2026-10)");
  const start = v3.indexOf(SECTION);
  assert.ok(start > 0, "section present");
  const end = v3.indexOf(NEXT);
  assert.ok(end > start, "section sits right before 負面認知處理");
  // The section comes after the 12 rules.
  assert.ok(v3.indexOf("# 12 條 reminiscence 行為規矩") < start);
  const rebuilt = [v2[0]].concat(v3.slice(1, start), v3.slice(end));
  assert.strictEqual(rebuilt.join("\n"), v2.join("\n"));
});

test("the section names the three markers and the block fields", () => {
  const s = section();
  for (const marker of ["`[回憶·追問]`", "`[回憶·回應]`",
    "`[回憶·再講多啲]`"]) {
    assert.ok(s.includes(marker), marker);
  }
  for (const field of ["`本週主題：…`", "`題目：…`", "`老人答：…`",
    "`追問：…`", "`老人再答：…`"]) {
    assert.ok(s.includes(field), field);
  }
  assert.ok(s.includes("第一行"), "marker is the first line of the block");
});

test("the section carries 1020d §2 (3) (a)–(e)", () => {
  const s = section();
  // (a) specific, one at a time, about what was just said
  assert.ok(s.includes("(a) **追問要具體，一次一條。**"));
  assert.ok(s.includes("時間、地方、人、當時見到或者聽到啲乜"));
  assert.ok(s.includes("針對老人啱啱講嘅內容"));
  // (b) the reply asks nothing, at most two sentences
  assert.ok(s.includes("(b) **回應唔提問，最多兩句。**"));
  // (c) never assume Hong Kong; places and eras only from the elder
  assert.ok(s.includes("(c) **唔好假設老人喺香港長大。**"));
  assert.ok(s.includes("地方、年代、生活方式，全部照老人自己講嘅"));
  assert.ok(s.includes("優先過上面第 3、10 條"));
  // (d) bereavement / trauma: acknowledge only
  assert.ok(s.includes("(d) **離世、創傷：只承認。**"));
  assert.ok(s.includes("唔好追問細節"));
  assert.ok(s.includes("「最難受係咩」「最難係咩」"));
  assert.ok(s.includes("都用一句承認代替追問"));
  // (e) everything else as before
  assert.ok(s.includes("(e) 其餘照上面 12 條規矩"));
  // The App asks the questions; the model never does.
  assert.ok(s.includes("唔好自己出題"));
  // Same identity rule as v2: no banned self-description added.
  for (const w of ["AI", "模型", "機械人"]) {
    assert.ok(!s.includes(w), w);
  }
});

test("slots filled exactly once, as v2", () => {
  const filled = reg.fillSlots(read(V3), {encouragementStyle: "gentle",
    variantName: "阿伯"});
  assert.ok(!filled.includes("{{TONE_RULE}}"));
  assert.ok(!filled.includes("{{VARIANT_NAME}}"));
  assert.strictEqual(filled.split(reg.TONE_RULES.gentle).length, 2);
  assert.ok(filled.startsWith("## 阿伯 — Reflective Peer-Listener"));
});

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length) process.exit(1);
