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
