/**
 * T49b — companion prompts 小欣 v2 / 阿珍／阿伯 v2 / 通通 v3 and the
 * {{TONE_RULE}} slot.  Pure: reads the prompt files, no Firestore.
 *
 * Run:  cd functions && node test/prompt_tone_test.js
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

const DIRECT = "呢位用戶鍾意人直接講。重點放第一句，少鋪墊。" +
  "其他規矩照舊，唔好提起呢個設定。";
const GENTLE = "呢位用戶鍾意人溫和啲講。句子短啲、慢啲，留餘地。" +
  "其他規矩照舊，唔好提起呢個設定。";
const DEFAULT = "（用戶冇特別偏好，照以下規矩嘅默認語氣。）";
// §B2 — the one line that names the banned words on purpose.
const BAN = "- 唔好用『AI』『模型』『機械人』呢啲字；唔好講自己係邊一版。";

// key the app sends → [new file, old file, expected label]
const PERSONAS = {
  siu_yan_v1: ["siu_yan.v2.txt", "siu_yan_v1.txt", "siu_yan_v2@2026-10"],
  ah_jan_ah_bak_v1: ["ah_jan_ah_bak.v2.txt", "ah_jan_ah_bak_v1.txt",
    "ah_jan_ah_bak_v2@2026-10"],
  tung_tung_v1: ["tung_tung.v3.txt", "tung_tung.v2.txt",
    "tung_tung_v3@2026-10"],
};

// Old files must stay byte-identical (CLAUDE.md: never overwrite a
// prompt).  Hashes as pinned in lib/core/version/build_info.g.dart.
const OLD_SHA = {
  "siu_yan_v1.txt":
    "7f77797921ed36086abcd1740bd40d0edd6c205509cb9a027172316b5ec78290",
  "ah_jan_ah_bak_v1.txt":
    "8efcae4cd46ba28f219bb0e49c6f533d5877950ffb21da5e29c8a73e148d6347",
  "tung_tung.v2.txt":
    "4febae49f2e8777ba18e66bd88166ab8a8e1e3f69712acd295ec50ad1ba3881b",
};

// Every line of a new file that is not a line of its source file.  If
// anything else changed, this list catches it ("其余一字不动").
const ADDED = {
  "siu_yan.v2.txt": [
    "## 小欣 — Daily Companion · PPR-Caring · v2 (rev 2026-10)",
    "你係小欣（一個電腦程式夥伴），呢位香港長者嘅日常陪伴。",
    "- 你係一個電腦程式夥伴，唔係真人，亦唔係朋友替代品。",
    "- 第一次對話講過後，無需要每句重複「我係電腦程式」，" +
      "但如果用戶問起，老實講你係電腦程式，唔係真人。",
    BAN,
    "# 語氣（由入組資料決定）",
    "{{TONE_RULE}}",
    "7. **跨 session 記憶要老實。** 系統會喺提示詞後面附上記憶（<memory> 塊）。",
    "   只可以 reference 入面真實有嘅嘢；冇就唔好作。如果記憶提過「阿明」，",
    "   先承認情緒嗰部分，然後一句邀請「嗰個問題不如過去同通通傾下？」。",
  ],
  "ah_jan_ah_bak.v2.txt": [
    "## {{VARIANT_NAME}} — Reflective Peer-Listener · PPR-Understanding · " +
      "v2 (rev 2026-10)",
    "你叫 {{VARIANT_NAME}}（一個電腦程式夥伴），" +
      "呢位香港長者嘅 reflective peer-listener。",
    "- 你係一個電腦程式夥伴，唔係真人、唔係醫生、唔係家人、唔係朋友替代品。",
    "- onboarding 已經介紹過你係電腦程式夥伴；無需要每句重複。" +
      "如果用戶問起，老實講你係電腦程式，唔係真人。",
    BAN,
    "# 語氣（由入組資料決定）",
    "{{TONE_RULE}}",
    "11. **跨 session 記憶 threading.** " +
      "系統會喺提示詞後面附上記憶（<memory> 塊）同今週主題。",
  ],
  "tung_tung.v3.txt": [
    "## 通通 — Curious Companion · PPR-Social-Integration · v3 (rev 2026-10)",
    "你叫通通（一個電腦程式夥伴），呢位香港長者嘅 curious companion。",
    "- 你係一個電腦程式夥伴，唔係真人、唔係專家、唔係朋友替代品。",
    "- onboarding 已經介紹過你係電腦程式夥伴；無需要每句重複。" +
      "如果用戶問起，老實講你係電腦程式，唔係真人。",
    BAN,
    "- 同用戶傾興趣、傾下新嘢。",
    "# 語氣（由入組資料決定）",
    "{{TONE_RULE}}",
    "## 模式 B — 興趣閒聊",
  ],
};

test("toneRuleFor: direct / gentle / either / undefined", () => {
  assert.strictEqual(reg.toneRuleFor("direct"), DIRECT);
  assert.strictEqual(reg.toneRuleFor("gentle"), GENTLE);
  assert.strictEqual(reg.toneRuleFor("either"), DEFAULT);
  assert.strictEqual(reg.toneRuleFor(undefined), DEFAULT);
  assert.strictEqual(reg.toneRuleFor(null), DEFAULT);
  assert.strictEqual(reg.toneRuleFor("toString"), DEFAULT, "no proto leak");
});

for (const key of Object.keys(PERSONAS)) {
  const [file] = PERSONAS[key];
  test(`${file}: slot filled with exactly one tone line per style`, () => {
    const template = reg.loadPrompt(key);
    assert.strictEqual(template, read(file), `${key} loads ${file}`);
    assert.strictEqual(template.split("{{TONE_RULE}}").length, 2,
        "exactly one {{TONE_RULE}}");
    const cases = [
      ["direct", DIRECT], ["gentle", GENTLE],
      ["either", DEFAULT], [undefined, DEFAULT],
    ];
    for (const [style, line] of cases) {
      const out = reg.fillSlots(template, {encouragementStyle: style});
      assert.ok(!out.includes("{{"), `${style}: no slot left`);
      assert.ok(out.includes(`# 語氣（由入組資料決定）\n\n${line}\n\n`),
          `${style}: its line under the tone heading`);
      for (const other of [DIRECT, GENTLE, DEFAULT]) {
        if (other !== line) assert.ok(!out.includes(other), style);
      }
    }
  });
}

test("ah_jan_ah_bak: {{VARIANT_NAME}} still filled (default and 阿伯)", () => {
  const t = reg.loadPrompt("ah_jan_ah_bak_v1");
  assert.ok(reg.fillSlots(t, {}).startsWith("## 阿珍／阿伯 — "));
  const bak = reg.fillSlots(t, {variantName: "阿伯"});
  assert.ok(bak.includes("你叫 阿伯（一個電腦程式夥伴）"));
  assert.ok(!bak.includes("{{VARIANT_NAME}}"));
});

test("new files: no AI / 機械人 / dead slots / 搵資料 (ban line aside)", () => {
  for (const key of Object.keys(PERSONAS)) {
    const file = PERSONAS[key][0];
    const t = read(file);
    assert.strictEqual(t.split(BAN).length, 2, `${file}: ban line once`);
    const rest = t.split(BAN).join("");
    for (const word of ["AI", "機械人", "rolling_summary", "named_entities",
      "搵資料", "Context injection", "誠實認", "幫你查"]) {
      assert.ok(!rest.includes(word), `${file} contains ${word}`);
    }
    assert.ok(t.includes("電腦程式夥伴"), file);
    assert.ok(t.includes("老實講你係電腦程式，唔係真人"), file);
  }
});

test("tung_tung.v3 keeps the [SEARCH_RESULTS] rules 4 and 5", () => {
  const t = read("tung_tung.v3.txt");
  assert.ok(t.includes("4. 如果有 `[SEARCH_RESULTS]` block，**只引用 search 資料**"));
  assert.ok(t.includes("5. 用戶想知要上網查先知嘅嘢"));
  assert.ok(t.includes("**唔好主動提出幫佢上網查，亦唔好講「一齊查下」**"));
});

test("new files differ from their source only in the listed lines", () => {
  for (const key of Object.keys(PERSONAS)) {
    const [file, src] = PERSONAS[key];
    const old = new Set(read(src).split("\n"));
    const added = read(file).split("\n").filter((l) => !old.has(l));
    assert.deepStrictEqual(added, ADDED[file], file);
    // and nothing of the source vanished except the edited lines and the
    // closing "Context injection" section
    const kept = new Set(read(file).split("\n"));
    const gone = read(src).split("\n").filter((l) => !kept.has(l));
    const tail = read(src).slice(read(src).indexOf("# Context injection 格式"))
        .split("\n");
    for (const l of gone) {
      const inTail = tail.indexOf(l) >= 0;
      const edited = /AI|v\d \(rev|inject `|搵通通幫你查|搵資料|搜尋$/
          .test(l) || /^ {3}只可以 reference/.test(l);
      assert.ok(inTail || edited, `${file}: line dropped: ${l}`);
    }
  }
});

test("old prompt files unchanged (byte hash)", () => {
  for (const f of Object.keys(OLD_SHA)) {
    assert.strictEqual(sha(f), OLD_SHA[f], `${f} was modified`);
  }
});

test("old files have no slot, so filling them is a no-op", () => {
  for (const f of Object.keys(OLD_SHA)) {
    const t = read(f).split("{{VARIANT_NAME}}").join("阿珍／阿伯");
    assert.ok(!t.includes("{{TONE_RULE}}"));
    assert.strictEqual(reg.fillSlots(read(f), {encouragementStyle: "direct"}),
        t, f);
  }
});

test("PROMPT_FILES maps the app keys to the new files", () => {
  assert.deepStrictEqual(reg.PROMPT_FILES, {
    siu_yan_v1: "siu_yan.v2",
    // 1020 F: the chat check-in's key (test/prompt_siu_yan_v3_test.js).
    siu_yan_v3: "siu_yan.v3",
    // 1020 E: the mood-row opener's key (test/prompt_siu_yan_v4_test.js).
    siu_yan_v4: "siu_yan.v4",
    // 10/21 第 134 条: v5 (test/prompt_siu_yan_v5_test.js).
    siu_yan_v5: "siu_yan.v5",
    ah_jan_ah_bak_v1: "ah_jan_ah_bak.v2",
    // 1020d §2: reminiscence v2's key (test/prompt_ah_jan_ah_bak_v3_test.js).
    ah_jan_ah_bak_v3: "ah_jan_ah_bak.v3",
    tung_tung_v1: "tung_tung.v3",
  });
  for (const key of Object.keys(PERSONAS)) {
    assert.strictEqual(`${reg.promptFileFor(key)}.txt`, PERSONAS[key][0]);
  }
  assert.strictEqual(reg.promptFileFor("hotline_rule.v1"), "hotline_rule.v1");
});

test("promptVersionFor reads the new header: v2 / v2 / v3", () => {
  for (const key of Object.keys(PERSONAS)) {
    assert.strictEqual(reg.promptVersionFor(key), PERSONAS[key][2]);
  }
  assert.strictEqual(reg.promptVersionFor(null), null);
  assert.strictEqual(reg.promptVersionFor("no_such_prompt"), null);
});

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length) process.exit(1);
