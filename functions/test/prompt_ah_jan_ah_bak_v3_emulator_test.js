/**
 * 1020d §2 — proxyDeepSeek with reminiscence v2's prompt key
 * `ah_jan_ah_bak_v3`: the Hybrid arm gets ah_jan_ah_bak.v3.txt (with the
 * App's marker block appended), the rule arm is refused before any prompt
 * is resolved (no DeepSeek call, a `llm_denied_log` row), and
 * `ah_jan_ah_bak_v1` still loads v2.
 *
 * DeepSeek is a stub (global fetch is replaced).
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/prompt_ah_jan_ah_bak_v3_emulator_test.js"
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

const UID_A = "ajab_v3_a";
const UID_B = "ajab_v3_b";
const BLOCK = "[回憶·追問]\n本週主題：童年同屋企\n" +
  "題目：講下你細個住嘅地方，係點樣嘅？\n老人答：細個住喺潮州鄉下";

const call = (uid, promptKey) => fns.proxyDeepSeek.run({
  auth: {uid: uid},
  data: {
    promptKey: promptKey,
    agentId: "ah_jan_ah_bak",
    variantName: "阿珍",
    moduleId: "m3_reminiscence_w1",
    contextSuffix: BLOCK,
    messages: [{role: "user", content: "細個住喺潮州鄉下"}],
  },
});

function systemText() {
  return lastBody.messages.find((m) => m.role === "system").content;
}

async function main() {
  await db.doc(`users/${UID_A}`).set({arm: "A"});
  await db.doc(`users/${UID_B}`).set({arm: "B"});

  const out = await call(UID_A, "ah_jan_ah_bak_v3");
  assert.ok(/^ah_jan_ah_bak_v3@2026-10(\+|$)/.test(out.promptVersion),
      out.promptVersion);
  let sys = systemText();
  assert.ok(sys.startsWith("## 阿珍 — Reflective Peer-Listener · " +
      "PPR-Understanding · v3"));
  assert.ok(sys.includes("# 每題之後（回憶 v2：App 逐題問）"), "v3 section");
  assert.ok(sys.includes(BLOCK), "the App's marker block is appended");
  assert.ok(!sys.includes("{{TONE_RULE}}"), "tone slot filled");
  assert.strictEqual(lastBody.model, "deepseek-flash");
  assert.deepStrictEqual(lastBody.thinking, {type: "disabled"});
  console.log("ok  ah_jan_ah_bak_v3 → ah_jan_ah_bak.v3.txt, " +
      "ah_jan_ah_bak_v3@2026-10");

  await call(UID_A, "ah_jan_ah_bak_v1");
  sys = systemText();
  assert.ok(sys.includes("· v2 (rev 2026-10)"));
  assert.ok(!sys.includes("# 每題之後"));
  console.log("ok  ah_jan_ah_bak_v1 still → ah_jan_ah_bak.v2.txt " +
      "(switch-off path)");

  // Rule arm: refused before any prompt is resolved; nothing sent.
  const before = fetchCalls;
  await assert.rejects(call(UID_B, "ah_jan_ah_bak_v3"),
      (err) => err.code === "permission-denied");
  assert.strictEqual(fetchCalls, before, "no DeepSeek call for the rule arm");
  const denied = await db.collection("llm_denied_log")
      .where("uid", "==", UID_B).get();
  assert.ok(denied.size >= 1, "llm_denied_log row");
  assert.strictEqual(denied.docs[0].get("endpoint"), "proxyDeepSeek");
  console.log("ok  rule arm refused with ah_jan_ah_bak_v3, logged, " +
      "no prompt sent");

  console.log("prompt_ah_jan_ah_bak_v3_emulator_test: all passed");
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
