/**
 * Prompt registry (memory-and-entry-spec 3.10, decision 0019, T49b): the
 * app still sends `<persona>_v1`; the server loads siu_yan.v2.txt,
 * ah_jan_ah_bak.v2.txt and tung_tung.v3.txt and reports their versions.
 * T49b: the {{TONE_RULE}} slot follows users/{uid}.encouragementStyle.
 *
 * DeepSeek is a stub (global fetch is replaced).
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/prompt_registry_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const fs = require("fs");
const path = require("path");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ||
  "loneliness-pilot-dev";
process.env.DEEPSEEK_API_KEY = "test-key";

let lastBody = null;
global.fetch = async (url, init) => {
  lastBody = JSON.parse(init.body);
  return {
    ok: true,
    status: 200,
    json: async () => ({
      model: "deepseek-flash",
      choices: [{message: {role: "assistant", content: "STUB"}}],
      usage: {prompt_tokens: 1, completion_tokens: 1, total_tokens: 2},
    }),
    text: async () => "",
  };
};

const fns = require("../index");
const admin = require("firebase-admin");
const db = admin.firestore();

const UID = "prompt_registry_a";
const PROMPTS = path.join(__dirname, "..", "prompts");

const chat = (agentId, extra) => fns.proxyDeepSeek.run({
  auth: {uid: UID},
  data: Object.assign({
    promptKey: `${agentId}_v1`,
    agentId,
    moduleId: "tung_tung_chat",
    messages: [{role: "user", content: "今日天氣點呀？"}],
  }, extra || {}),
});

function systemText() {
  return lastBody.messages.find((m) => m.role === "system").content;
}

const TONE = {
  direct: "呢位用戶鍾意人直接講。重點放第一句，少鋪墊。",
  gentle: "呢位用戶鍾意人溫和啲講。句子短啲、慢啲，留餘地。",
  none: "（用戶冇特別偏好，照以下規矩嘅默認語氣。）",
};

async function main() {
  await db.doc(`users/${UID}`).set({arm: "A"});

  // v1 / v2 stay on disk untouched; each version is a separate file.
  const v1 = fs.readFileSync(path.join(PROMPTS, "tung_tung_v1.txt"), "utf8");
  const v2 = fs.readFileSync(path.join(PROMPTS, "tung_tung.v2.txt"), "utf8");
  const v3 = fs.readFileSync(path.join(PROMPTS, "tung_tung.v3.txt"), "utf8");
  assert.ok(v1.includes("要唔要我幫你查下"));
  assert.ok(!v2.includes("要唔要我幫你查下"));
  assert.ok(!v2.includes("要唔要一齊查下"));
  assert.ok(v2.includes("[SEARCH_RESULTS]"), "search-results rule kept");
  assert.ok(v3.includes("[SEARCH_RESULTS]"), "search-results rule kept (v3)");
  assert.ok(v2.includes("有時幫佢搵資料") && !v3.includes("有時幫佢搵資料"));

  const out = await chat("tung_tung");
  // T7 (decision 0018) appends the hotline rule file to every persona
  // label while meta/safety_config.hotlinePromptRule is on (default).
  assert.strictEqual(out.promptVersion,
      "tung_tung_v3@2026-10+hotline_rule.v1");
  let sys = systemText();
  assert.ok(sys.includes("唔好主動提出幫佢上網查"), "v2 rule kept");
  assert.ok(sys.includes("## 模式 B — 興趣閒聊\n"), "server loads v3");
  assert.ok(!sys.includes("要唔要我幫你查下"), "v1 invitation gone");
  console.log("ok  tung_tung_v1 key → tung_tung.v3.txt, tung_tung_v3@2026-10");

  const siu = await chat("siu_yan");
  assert.ok(/^siu_yan_v2@2026-10\+/.test(siu.promptVersion),
      siu.promptVersion);
  const jan = await chat("ah_jan_ah_bak", {variantName: "阿伯"});
  assert.ok(/^ah_jan_ah_bak_v2@2026-10\+/.test(jan.promptVersion),
      jan.promptVersion);
  sys = systemText();
  assert.ok(sys.startsWith("## 阿伯 — "), "variant filled");
  assert.ok(!sys.includes("AI 機械人"), "identity wording v2");
  console.log("ok  siu_yan_v1 → siu_yan.v2, ah_jan_ah_bak_v1 → .v2");

  // T49b — the tone slot follows users/{uid}.encouragementStyle.
  const cases = [
    ["direct", TONE.direct], ["gentle", TONE.gentle],
    ["either", TONE.none], [null, TONE.none],
  ];
  for (const [style, line] of cases) {
    const user = {arm: "A"};
    if (style !== null) user.encouragementStyle = style;
    await db.doc(`users/${UID}`).set(user);
    for (const agent of ["siu_yan", "ah_jan_ah_bak", "tung_tung"]) {
      await chat(agent);
      sys = systemText();
      assert.ok(!sys.includes("{{TONE_RULE}}"), `${agent}/${style}: filled`);
      assert.ok(sys.includes(`# 語氣（由入組資料決定）\n\n${line}`),
          `${agent}/${style}: tone line`);
      for (const other of Object.values(TONE)) {
        if (other !== line) assert.ok(!sys.includes(other), agent);
      }
    }
    console.log(`ok  encouragementStyle ${style} → its tone line, 3 personas`);
  }

  // The client cannot pick the tone: a payload field is ignored.
  await db.doc(`users/${UID}`).set({arm: "A", encouragementStyle: "gentle"});
  await chat("siu_yan", {encouragementStyle: "direct"});
  sys = systemText();
  assert.ok(sys.includes(TONE.gentle) && !sys.includes(TONE.direct));
  console.log("ok  tone read from the profile, not from the payload");

  // Rule arm: refused before any prompt is resolved (no DeepSeek call).
  await db.doc("users/prompt_registry_b").set({
    arm: "B", encouragementStyle: "direct"});
  lastBody = null;
  await assert.rejects(fns.proxyDeepSeek.run({
    auth: {uid: "prompt_registry_b"},
    data: {promptKey: "siu_yan_v1", agentId: "siu_yan", moduleId: "m2",
      messages: [{role: "user", content: "hi"}]},
  }), (err) => err.code === "permission-denied");
  assert.strictEqual(lastBody, null, "no LLM call for the rule arm");
  console.log("ok  rule arm still refused, no prompt sent");

  console.log("prompt_registry_emulator_test: all passed");
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
