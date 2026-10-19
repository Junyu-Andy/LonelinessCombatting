/**
 * Every DeepSeek request names `deepseek-flash` and turns thinking off
 * (decision record 0017).
 *
 * Run:  cd functions && node test/deepseek_request_test.js
 *
 * Static check on the source, so it needs no network, key or emulator.
 * `deepseek-flash` thinks by default; a call site that forgets
 * `thinking: DEEPSEEK_THINKING` would spend its max_tokens on reasoning and
 * return an empty reply, which no other test would catch.
 *
 * Since C04 every request goes through llm_log.js deepSeekChat(), which
 * owns the only copy of the DeepSeek URL; index.js passes it a body.
 */
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const read = (f) => fs.readFileSync(path.join(root, f), "utf8");
const index = read("index.js");
const llmLog = read("llm_log.js");

assert.ok(index.includes("const DEEPSEEK_MODEL = \"deepseek-flash\";"),
    "DEEPSEEK_MODEL should be deepseek-flash");
assert.ok(index.includes("const DEEPSEEK_THINKING = {type: \"disabled\"};"),
    "DEEPSEEK_THINKING should disable thinking");

// One URL, in the logging wrapper; none left in index.js.
const url = "api.deepseek.com";
const count = (src) => src.split(url).length - 1;
assert.strictEqual(count(index), 0,
    "index.js calls DeepSeek directly instead of llmLog.deepSeekChat");
assert.strictEqual(count(llmLog), 1,
    `llm_log.js should hold exactly one DeepSeek URL, found ${count(llmLog)}`);

// Each llmLog.deepSeekChat( call: its body must use both constants.
const calls = index.split("llmLog.deepSeekChat(").slice(1);
assert.ok(calls.length >= 3,
    `expected >= 3 deepSeekChat calls, found ${calls.length}`);
calls.forEach((rest, i) => {
  const body = rest.slice(rest.indexOf("body: {"), rest.indexOf("messages:"));
  assert.ok(body.startsWith("body: {"), `call ${i + 1}: no body`);
  assert.ok(body.includes("model: DEEPSEEK_MODEL,"),
      `call ${i + 1}: model is not DEEPSEEK_MODEL`);
  assert.ok(body.includes("thinking: DEEPSEEK_THINKING,"),
      `call ${i + 1}: thinking is not DEEPSEEK_THINKING`);
});

// 1020d §6: the 小篇章 module (functions/reminiscence_chapter.js) also
// goes through deepSeekChat.  Its draft is the one place that turns
// thinking ON (deepseek-v4-pro); its check is deepseek-flash, thinking off
// whatever the config says.
const chapterSrc = read("reminiscence_chapter.js");
assert.strictEqual(count(chapterSrc), 0,
    "reminiscence_chapter.js calls DeepSeek directly");
assert.ok(chapterSrc.includes("llmLog.deepSeekChat("),
    "reminiscence_chapter.js must call llmLog.deepSeekChat");
assert.ok(chapterSrc.includes("const THINKING_OFF = {type: \"disabled\"};"));
const chapter = require("../reminiscence_chapter");
const chapterBody = (step, thinking) => chapter.buildRequestBody({step,
  model: step === "check" ? chapter.DEFAULTS.checkModel :
    chapter.DEFAULTS.draftModel,
  thinking, system: "s", user: "u", maxTokens: 10, temperature: 0.1,
  json: step === "check"});
assert.strictEqual(chapterBody("check", true).model, "deepseek-flash");
assert.deepStrictEqual(chapterBody("check", true).thinking,
    {type: "disabled"}, "the chapter check never thinks");
assert.strictEqual(chapterBody("draft", true).model, "deepseek-v4-pro");
assert.deepStrictEqual(chapterBody("draft", true).thinking,
    {type: "enabled"}, "the chapter draft thinks (1020d §6 (2)(a))");
assert.deepStrictEqual(chapterBody("rewrite", false).thinking,
    {type: "disabled"}, "config can switch the draft's thinking off");

// No server code still asks for the legacy alias.
fs.readdirSync(root)
    .filter((f) => f.endsWith(".js"))
    .forEach((f) => {
      const code = read(f).split("\n")
          .filter((l) => !l.trim().startsWith("//"));
      assert.ok(!code.join("\n").includes("\"deepseek-chat\""),
          `${f} still requests "deepseek-chat"`);
    });

console.log(`deepseek_request_test: ${calls.length} DeepSeek calls OK`);
