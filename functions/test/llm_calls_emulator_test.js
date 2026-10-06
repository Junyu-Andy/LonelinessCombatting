/**
 * C04 model log — every server-side LLM call writes one `llm_calls` row.
 *
 * Runs the real Cloud Function handlers (proxyDeepSeek, referralJudgement,
 * memoryEndSession, memorySweep) against the Firestore emulator.  DeepSeek
 * is a stub: global fetch is replaced, so no network or API key is needed.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/llm_calls_emulator_test.js"
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

// The model index.js requests (decision 0017), read from its source so this
// test follows a future rename.
const DEEPSEEK_MODEL = require("fs")
    .readFileSync(require("path").join(__dirname, "..", "index.js"), "utf8")
    .match(/const DEEPSEEK_MODEL = "([^"]+)";/)[1];

// --- DeepSeek stub ---------------------------------------------------------
// Mirrors the live API as seen on 2026-10-06: it answers with model
// "deepseek-flash" and a system_fingerprint.
const STUB_MODEL = "deepseek-flash";
const REPLY = "STUB_REPLY_好開心同你傾偈";
const USER_TEXT = "STUB_USER_今日去咗飲茶";
let fetchCalls = [];
let nextStatus = 200;
global.fetch = async (url, init) => {
  const body = JSON.parse(init.body);
  fetchCalls.push({url, body, hasSignal: !!init.signal});
  let content = REPLY;
  if (body.response_format) {
    // referralJudgement and memory extraction both ask for JSON.
    const sys = body.messages[0].content;
    content = /summary|facts|followups/.test(sys) ?
      JSON.stringify({summary: "", facts: [], followups: []}) :
      JSON.stringify({decision: "SKIP", suggestion: ""});
  }
  const resp = {
    model: STUB_MODEL,
    choices: [{message: {role: "assistant", content}}],
    system_fingerprint: "fp_stub_flash",
    usage: {prompt_tokens: 321, completion_tokens: 21, total_tokens: 342,
      completion_tokens_details: {reasoning_tokens: 0}},
  };
  return {
    ok: nextStatus === 200,
    status: nextStatus,
    json: async () => resp,
    text: async () => "upstream error",
  };
};

const fns = require("../index");
const admin = require("firebase-admin");
const db = admin.firestore();

const UID_A = "llm_a";
const UID_B = "llm_b";

async function wipe(ref) {
  const cols = await ref.listCollections();
  for (const c of cols) {
    const docs = await c.listDocuments();
    for (const d of docs) await wipe(d);
    await Promise.all(docs.map((d) => d.delete()));
  }
}

async function reset() {
  for (const name of ["llm_calls", "users"]) {
    const docs = await db.collection(name).listDocuments();
    for (const d of docs) await wipe(d);
    await Promise.all(docs.map((d) => d.delete()));
  }
  await db.doc("meta/memory_config").set({enabled: true, policy: "C"});
  await db.doc(`users/${UID_A}`).set({arm: "A", memory_enabled: true});
  await db.doc(`users/${UID_B}`).set({arm: "B", memory_enabled: true});
  fetchCalls = [];
  nextStatus = 200;
}

async function rows() {
  const snap = await db.collection("llm_calls").get();
  return snap.docs.map((d) => d.data());
}

async function seedBuffer(uid, agentId, idle) {
  const old = admin.firestore.Timestamp.fromMillis(
      Date.now() - 60 * 60 * 1000);
  await db.doc(`users/${uid}/agent_contexts/${agentId}`).set({
    shortTermBuffer: [
      {fromUser: true, text: USER_TEXT, timestamp: new Date().toISOString()},
      {fromUser: false, text: REPLY, timestamp: new Date().toISOString()},
    ],
    lastUpdated: idle ? old : admin.firestore.Timestamp.now(),
  });
}

const chat = (uid, moduleId, agentId) => fns.proxyDeepSeek.run({
  auth: {uid},
  data: {
    promptKey: `${agentId}_v1`,
    agentId,
    moduleId,
    messages: [{role: "user", content: USER_TEXT}],
  },
});

const FIELDS = [
  "agent_id", "call_type", "completion_tokens", "error",
  "http_status", "latency_ms", "model_requested", "model_returned",
  "prompt_tokens", "reasoning_tokens", "system_fingerprint", "ts",
  "uid",
];

function assertRow(row, want) {
  assert.deepStrictEqual(Object.keys(row).sort(), FIELDS);
  for (const [k, v] of Object.entries(want)) {
    assert.strictEqual(row[k], v, `${k}: ${row[k]} != ${v}`);
  }
  assert.strictEqual(row.uid, want.uid || UID_A);
  assert.strictEqual(row.model_requested, DEEPSEEK_MODEL);
  assert.ok(row.ts instanceof admin.firestore.Timestamp, "ts is a Timestamp");
  assert.ok(Math.abs(row.ts.toMillis() - Date.now()) < 60000, "ts is now");
  assert.ok(typeof row.latency_ms === "number" && row.latency_ms >= 0);
  const flat = JSON.stringify(row);
  assert.ok(!flat.includes("STUB_REPLY"), "completion text in log");
  assert.ok(!flat.includes("STUB_USER"), "prompt text in log");
}

const okRow = {
  model_returned: STUB_MODEL, prompt_tokens: 321, completion_tokens: 21,
  system_fingerprint: "fp_stub_flash", reasoning_tokens: 0, http_status: 200,
  error: false,
};

const tests = [];
const test = (name, fn) => tests.push({name, fn});

const GENERATION_CASES = [
  ["m2_check_in", "siu_yan", "chat"],
  ["tung_tung_chat", "tung_tung", "chat"],
  ["reflective_dialogue", "ah_jan_ah_bak", "chat"],
  ["greeting_siu_yan", "siu_yan", "greeting"],
  ["m3_reminiscence_w1_summary", "ah_jan_ah_bak", "session_summary"],
  ["m7_action_loop_summary", "siu_yan", "session_summary"],
  ["m9_progress_summary", "siu_yan", "weekly_summary"],
  ["m8_education_sleep", "siu_yan", "article_qa"],
  ["m6_suggestions", "siu_yan", "suggestions"],
  ["rolling_summary_fold", "tung_tung", "memory_summary"],
];

for (const [moduleId, agentId, callType] of GENERATION_CASES) {
  test(`proxyDeepSeek ${moduleId} → ${callType}`, async () => {
    await reset();
    const out = await chat(UID_A, moduleId, agentId);
    assert.strictEqual(out.text, REPLY);
    assert.strictEqual(out.model, STUB_MODEL);
    const r = await rows();
    assert.strictEqual(r.length, 1);
    assertRow(r[0], Object.assign(
        {call_type: callType, agent_id: agentId}, okRow));
  });
}

test("referralJudgement → referral_judgement", async () => {
  await reset();
  const out = await fns.referralJudgement.run({
    auth: {uid: UID_A},
    data: {sourceAgentId: "siu_yan", targetAgentId: "tung_tung",
      matchedText: USER_TEXT,
      recentTurns: [{role: "user", content: USER_TEXT}]},
  });
  assert.strictEqual(out.decision, "SKIP");
  const r = await rows();
  assert.strictEqual(r.length, 1);
  assertRow(r[0], Object.assign(
      {call_type: "referral_judgement", agent_id: "siu_yan"}, okRow));
});

test("memoryEndSession → memory_extraction", async () => {
  await reset();
  await seedBuffer(UID_A, "tung_tung", false);
  const out = await fns.memoryEndSession.run({
    auth: {uid: UID_A}, data: {agentId: "tung_tung"},
  });
  assert.strictEqual(out.status, "done");
  const r = await rows();
  assert.strictEqual(r.length, 1);
  assertRow(r[0], Object.assign(
      {call_type: "memory_extraction", agent_id: "tung_tung"}, okRow));
});

test("memorySweep → memory_extraction (Arm A only)", async () => {
  await reset();
  await seedBuffer(UID_A, "siu_yan", true);
  await seedBuffer(UID_B, "siu_yan", true);
  await fns.memorySweep.run({});
  const r = await rows();
  assert.strictEqual(r.length, 1);
  assertRow(r[0], Object.assign(
      {call_type: "memory_extraction", agent_id: "siu_yan"}, okRow));
});

test("upstream error is logged with error: true", async () => {
  await reset();
  nextStatus = 500;
  await assert.rejects(chat(UID_A, "m2_check_in", "siu_yan"),
      (e) => e.code === "internal");
  const r = await rows();
  assert.strictEqual(r.length, 1);
  assertRow(r[0], {call_type: "chat", agent_id: "siu_yan", error: true,
    model_returned: null, prompt_tokens: null, completion_tokens: null,
    system_fingerprint: null, reasoning_tokens: null, http_status: 500});
});

test("every request: DEEPSEEK_MODEL, thinking off, a timeout signal",
    async () => {
      await reset();
      await seedBuffer(UID_A, "tung_tung", false);
      await chat(UID_A, "m2_check_in", "siu_yan");
      await fns.referralJudgement.run({
        auth: {uid: UID_A},
        data: {sourceAgentId: "siu_yan", targetAgentId: "tung_tung"},
      });
      await fns.memoryEndSession.run({
        auth: {uid: UID_A}, data: {agentId: "tung_tung"},
      });
      assert.strictEqual(fetchCalls.length, 3);
      for (const c of fetchCalls) {
        assert.strictEqual(c.body.model, DEEPSEEK_MODEL);
        assert.deepStrictEqual(c.body.thinking, {type: "disabled"});
        assert.ok(c.hasSignal, "request has no timeout signal");
      }
    });

test("Arm B: no LLM call, no llm_calls row, from any entry point",
    async () => {
      await reset();
      await seedBuffer(UID_B, "tung_tung", false);
      for (const [moduleId, agentId] of GENERATION_CASES) {
        await assert.rejects(chat(UID_B, moduleId, agentId),
            (e) => e.code === "permission-denied");
      }
      await assert.rejects(fns.referralJudgement.run({
        auth: {uid: UID_B},
        data: {sourceAgentId: "siu_yan", targetAgentId: "tung_tung"},
      }), (e) => e.code === "permission-denied");
      const mem = await fns.memoryEndSession.run({
        auth: {uid: UID_B}, data: {agentId: "tung_tung"},
      });
      assert.strictEqual(mem.status, "inactive");
      await fns.memorySweep.run({});
      assert.strictEqual(fetchCalls.length, 0, "DeepSeek was called");
      assert.strictEqual((await rows()).length, 0);
    });

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`PASS  ${t.name}`);
    } catch (err) {
      failed++;
      console.log(`FAIL  ${t.name}\n      ${err.stack}`);
    }
  }
  console.log(`\n${tests.length - failed} passed, ${failed} failed.`);
  process.exit(failed ? 1 : 0);
})();
