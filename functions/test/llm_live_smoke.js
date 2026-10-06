/**
 * C04 live smoke test — ONE real DeepSeek call through deepSeekChat, to
 * check that the model name the API actually returns lands in the log row.
 *
 * Not part of CI (CI has no API key; the file name does not end in
 * _test.js, so tool/ci_backend_tests.sh skips it).  Sends one synthetic
 * sentence with max_tokens 5.  No participant data.
 *
 * Run manually, from functions/:
 *   DEEPSEEK_API_KEY=<key> node test/llm_live_smoke.js
 * Behind the agent proxy that injects the key (Claude Code cloud sessions),
 * any placeholder key works, but Node's fetch must use the proxy:
 *   NODE_USE_ENV_PROXY=1 DEEPSEEK_API_KEY=placeholder \
 *     node test/llm_live_smoke.js
 *
 * With FIRESTORE_EMULATOR_HOST set (inside `firebase emulators:exec`), the
 * row is written to the emulator's llm_calls and read back; otherwise it is
 * captured in memory.  Prints the row, never the key.
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const {deepSeekChat} = require("../llm_log");

function memoryDb() {
  const rows = [];
  return {
    rows,
    collection: () => ({add: async (row) => rows.push(row)}),
  };
}

(async () => {
  const apiKey = process.env.DEEPSEEK_API_KEY;
  if (!apiKey) {
    console.error("DEEPSEEK_API_KEY not set (a placeholder is fine behind " +
      "the key-injecting proxy).");
    process.exit(2);
  }
  let db;
  let readBack;
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    admin.initializeApp({projectId: "loneliness-pilot-dev"});
    db = admin.firestore();
    const before = Date.now();
    readBack = async () => {
      const snap = await db.collection("llm_calls")
          .where("uid", "==", "smoke_test").get();
      return snap.docs.map((d) => d.data())
          .filter((r) => r.ts.toMillis() >= before - 1000);
    };
  } else {
    db = memoryDb();
    readBack = async () => db.rows;
  }

  const body = {
    // As index.js sends it (decision 0017).
    model: "deepseek-flash",
    thinking: {type: "disabled"},
    messages: [{role: "user", content: "Reply with the single word: ok"}],
    max_tokens: 5,
    temperature: 0,
  };
  const res = await deepSeekChat(db, {
    apiKey,
    log: {callType: "chat", agentId: null, uid: "smoke_test"},
    body,
    timeoutMs: 30000,
    // This script's first Firestore write is cold (the functions read
    // Firestore before calling DeepSeek, so theirs is warm); allow for it.
    logTimeoutMs: 15000,
  });
  const rows = await readBack();
  console.log("HTTP status:", res.status);
  console.log("log row:", JSON.stringify(rows[rows.length - 1], null, 2));

  assert.strictEqual(res.ok, true, `DeepSeek returned ${res.status}`);
  assert.strictEqual(rows.length, 1, "expected exactly one log row");
  const row = rows[0];
  assert.strictEqual(row.error, false);
  assert.strictEqual(row.model_requested, body.model);
  assert.ok(typeof row.model_returned === "string" && row.model_returned,
      "model_returned missing");
  assert.strictEqual(row.model_returned, res.data.model);
  assert.ok(row.prompt_tokens > 0 && row.completion_tokens > 0, "tokens");
  assert.strictEqual(row.system_fingerprint,
      res.data.system_fingerprint || null);
  console.log(`\nOK: requested ${row.model_requested}, ` +
    `returned ${row.model_returned}, ` +
    `fingerprint ${row.system_fingerprint}, ` +
    `reasoning_tokens ${row.reasoning_tokens}`);
  process.exit(0);
})().catch((err) => {
  console.error("FAIL", err.message);
  process.exit(1);
});
