/**
 * Prompt registry (memory-and-entry-spec 3.10, decision 0019): the app
 * still sends `tung_tung_v1`; the server loads tung_tung.v2.txt and
 * reports promptVersion tung_tung_v2@2026-10.  Other personas unchanged.
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

const chat = (agentId) => fns.proxyDeepSeek.run({
  auth: {uid: UID},
  data: {
    promptKey: `${agentId}_v1`,
    agentId,
    moduleId: "tung_tung_chat",
    messages: [{role: "user", content: "今日天氣點呀？"}],
  },
});

function systemText() {
  return lastBody.messages.find((m) => m.role === "system").content;
}

async function main() {
  await db.doc(`users/${UID}`).set({arm: "A"});

  // v1 stays on disk untouched; v2 is a separate file.
  const v1 = fs.readFileSync(path.join(PROMPTS, "tung_tung_v1.txt"), "utf8");
  const v2 = fs.readFileSync(path.join(PROMPTS, "tung_tung.v2.txt"), "utf8");
  assert.ok(v1.includes("要唔要我幫你查下"));
  assert.ok(!v2.includes("要唔要我幫你查下"));
  assert.ok(!v2.includes("要唔要一齊查下"));
  assert.ok(v2.includes("[SEARCH_RESULTS]"), "search-results rule kept");

  const out = await chat("tung_tung");
  assert.strictEqual(out.promptVersion, "tung_tung_v2@2026-10");
  const sys = systemText();
  assert.ok(sys.includes("唔好主動提出幫佢上網查"), "server loads v2");
  assert.ok(!sys.includes("要唔要我幫你查下"), "v1 invitation gone");
  console.log("ok  tung_tung_v1 key → tung_tung.v2.txt, tung_tung_v2@2026-10");

  const siu = await chat("siu_yan");
  assert.ok(/^siu_yan_v1@/.test(siu.promptVersion), siu.promptVersion);
  console.log("ok  other personas still load their v1 file");

  console.log("prompt_registry_emulator_test: all passed");
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
