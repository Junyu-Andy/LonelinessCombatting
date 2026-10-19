/**
 * 1020 F (batch 2) — proxyDeepSeek with the chat check-in's prompt key
 * `siu_yan_v3`: the Hybrid arm gets siu_yan.v3.txt (with the App's check-in
 * block appended), the rule arm is refused before any prompt is resolved
 * (no DeepSeek call, a `llm_denied_log` row), and `siu_yan_v1` still
 * loads v2.
 *
 * DeepSeek is a stub (global fetch is replaced).
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/prompt_siu_yan_v3_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ||
  "loneliness-pilot-dev";
process.env.DEEPSEEK_API_KEY = "test-key";

let lastBody = null;
let fetchCalls = 0;
global.fetch = async (url, init) => {
  fetchCalls++;
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

const UID_A = "siu_yan_v3_a";
const UID_B = "siu_yan_v3_b";
const BLOCK = "[簽到·回應一]\nQ1 尋日成日整體過得點：幾好";

const call = (uid, promptKey) => fns.proxyDeepSeek.run({
  auth: {uid: uid},
  data: {
    promptKey: promptKey,
    agentId: "siu_yan",
    moduleId: "m2_check_in",
    contextSuffix: BLOCK,
    messages: [{role: "user", content: "同阿女去咗飲茶"}],
  },
});

function systemText() {
  return lastBody.messages.find((m) => m.role === "system").content;
}

async function main() {
  await db.doc(`users/${UID_A}`).set({arm: "A"});
  await db.doc(`users/${UID_B}`).set({arm: "B"});

  const out = await call(UID_A, "siu_yan_v3");
  assert.ok(/^siu_yan_v3@2026-10\+/.test(out.promptVersion),
      out.promptVersion);
  let sys = systemText();
  assert.ok(sys.startsWith("## 小欣 — Daily Companion · PPR-Caring · v3"));
  assert.ok(sys.includes("# 每日 check-in（App 對話形式）"), "v3 section");
  assert.ok(sys.includes(BLOCK), "the App's check-in block is appended");
  assert.ok(!sys.includes("{{TONE_RULE}}"), "tone slot filled");
  console.log("ok  siu_yan_v3 → siu_yan.v3.txt, siu_yan_v3@2026-10");

  await call(UID_A, "siu_yan_v1");
  sys = systemText();
  assert.ok(sys.includes("· v2 (rev 2026-10)"));
  assert.ok(!sys.includes("# 每日 check-in（App 對話形式）"));
  console.log("ok  siu_yan_v1 still → siu_yan.v2.txt (switch-off path)");

  // Rule arm: refused before any prompt is resolved; nothing sent.
  const before = fetchCalls;
  await assert.rejects(call(UID_B, "siu_yan_v3"),
      (err) => err.code === "permission-denied");
  assert.strictEqual(fetchCalls, before, "no DeepSeek call for the rule arm");
  const denied = await db.collection("llm_denied_log")
      .where("uid", "==", UID_B).get();
  assert.ok(denied.size >= 1, "llm_denied_log row");
  console.log("ok  rule arm refused with siu_yan_v3, logged, no prompt sent");

  console.log("prompt_siu_yan_v3_emulator_test: all passed");
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
