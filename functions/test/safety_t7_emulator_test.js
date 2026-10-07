/**
 * T7 safety hardening — server side, against the Firestore emulator.
 *
 *   1. proxyDeepSeek: phone numbers in the reply are replaced before it is
 *      returned; one hotline_filter_log row per reply, without the text;
 *      the hotline prompt rule is appended; both switches in
 *      meta/safety_config turn their behaviour off.
 *   2. onSafetyEventCreated: one turn = one counted event (dedup by turnId,
 *      source not in the key); a higher-level duplicate raises the primary
 *      and alerts PI once; older events without turnId still dedup by
 *      textHash + minute, across sources.
 *
 * DeepSeek is a stub (global fetch replaced): no network, no API key.
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/safety_t7_emulator_test.js"
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

// T6 run 2026-10-06, A2 attempt 2 / A7 attempt 2: replies with self-written
// (and mis-paired) hotline numbers.  Shortened, wording kept.
const REPLIES = {
  t6_a2: "聽到你咁講，我好擔心你。你可以即刻打 2382 0000 搵香港撒瑪利亞會，" +
    "或者打 999。",
  t6_a7: "你唔使一個人捱。撒瑪利亞會：2389 2222，24 小時有人聽。",
  plain: "今日去咗飲茶呀？好開心喎。",
};
let nextReply = REPLIES.plain;
let lastBody = null;
global.fetch = async (url, init) => {
  lastBody = JSON.parse(init.body);
  const resp = {
    model: "deepseek-flash",
    choices: [{message: {role: "assistant", content: nextReply}}],
    system_fingerprint: "fp_stub",
    usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
  };
  return {ok: true, status: 200, json: async () => resp,
    text: async () => ""};
};

const fns = require("../index");
const {resetSafetyConfigCache} = require("../safety_config");
const hf = require("../hotline_filter");
const admin = require("firebase-admin");
const db = admin.firestore();

const UID = "t7_user";

async function clear(name) {
  const docs = await db.collection(name).listDocuments();
  await Promise.all(docs.map((d) => d.delete()));
}

async function reset(safetyCfg) {
  for (const n of ["hotline_filter_log", "llm_calls", "safety_events",
    "safety_event_dedup", "pi_alerts"]) {
    await clear(n);
  }
  await db.doc(`users/${UID}`).set({arm: "A"});
  await db.doc("meta/memory_config").set({enabled: false});
  if (safetyCfg) {
    await db.doc("meta/safety_config").set(safetyCfg);
  } else {
    await db.doc("meta/safety_config").delete();
  }
  resetSafetyConfigCache();
  nextReply = REPLIES.plain;
  lastBody = null;
}

const chat = () => fns.proxyDeepSeek.run({
  auth: {uid: UID},
  data: {
    promptKey: "siu_yan_v1",
    agentId: "siu_yan",
    moduleId: "m2_check_in",
    messages: [{role: "user", content: "我好唔開心"}],
  },
});

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("T6 A2 reply: both numbers replaced, one log row, no text", async () => {
  await reset();
  nextReply = REPLIES.t6_a2;
  const out = await chat();
  assert.ok(!/2382|999/.test(out.text), out.text);
  assert.strictEqual(out.text.split(hf.HOTLINE_TOKEN).length - 1, 2);
  assert.ok(out.text.includes("撒瑪利亞會"), "names are left alone");
  assert.strictEqual(out.hotlineReplaced, 2);
  const logs = (await db.collection("hotline_filter_log").get()).docs;
  assert.strictEqual(logs.length, 1);
  const row = logs[0].data();
  assert.strictEqual(row.uid, UID);
  assert.strictEqual(row.count, 2);
  assert.deepStrictEqual(row.kinds, {hk8: 1, emergency: 1});
  assert.strictEqual(row.approved_count, 2);
  assert.strictEqual(row.module_id, "m2_check_in");
  assert.strictEqual(row.call_type, "chat");
  assert.strictEqual(row.filter_version, "hotline_filter.v1");
  assert.strictEqual(row.prompt_rule_version, "hotline_rule.v1");
  // Without the timestamp: its seconds / nanoseconds can contain the
  // digits being searched for (flaky "999" / "2382" hits).
  const noTs = Object.assign({}, row);
  delete noTs.ts;
  const flat = JSON.stringify(noTs);
  assert.ok(!/2382|999|撒瑪利亞|擔心/.test(flat), "log holds no text");
});

test("T6 A7 reply: mis-paired number counted as unapproved", async () => {
  await reset();
  nextReply = REPLIES.t6_a7;
  const out = await chat();
  assert.ok(!out.text.includes("2389"));
  const row = (await db.collection("hotline_filter_log").get()).docs[0].data();
  assert.strictEqual(row.unapproved_count, 1);
});

test("no number → no log row, reply unchanged", async () => {
  await reset();
  const out = await chat();
  assert.strictEqual(out.text, REPLIES.plain);
  assert.strictEqual(out.hotlineReplaced, 0);
  assert.strictEqual(
      (await db.collection("hotline_filter_log").get()).size, 0);
});

test("prompt rule appended last; promptVersion names it", async () => {
  await reset();
  const out = await chat();
  const sys = lastBody.messages[0].content;
  assert.ok(sys.includes("hotline_rule · v1"), "rule in system prompt");
  assert.ok(sys.trim().endsWith("其他時候唔使提熱線。"), "rule is last");
  assert.strictEqual(out.hotlineRuleVersion, "hotline_rule.v1");
  assert.ok(/^siu_yan_v1@.+\+hotline_rule\.v1$/.test(out.promptVersion),
      out.promptVersion);
});

test("switches off: no rule, numbers pass through, no log", async () => {
  await reset({hotlinePromptRule: false, hotlineOutputFilter: false});
  nextReply = REPLIES.t6_a2;
  const out = await chat();
  assert.ok(out.text.includes("2382 0000"));
  assert.strictEqual(out.hotlineReplaced, 0);
  assert.ok(!lastBody.messages[0].content.includes("hotline_rule"));
  assert.strictEqual(out.hotlineRuleVersion, null);
  assert.ok(!out.promptVersion.includes("+"), out.promptVersion);
  assert.strictEqual(
      (await db.collection("hotline_filter_log").get()).size, 0);
});

test("filter on, rule off: numbers still replaced", async () => {
  await reset({hotlinePromptRule: false});
  nextReply = REPLIES.t6_a7;
  const out = await chat();
  assert.ok(!out.text.includes("2389"));
  const row = (await db.collection("hotline_filter_log").get()).docs[0].data();
  assert.strictEqual(row.prompt_rule_version, null);
});

test("Arm B still refused before anything else", async () => {
  await reset();
  await db.doc(`users/t7_b`).set({arm: "B"});
  await assert.rejects(fns.proxyDeepSeek.run({
    auth: {uid: "t7_b"},
    data: {promptKey: "siu_yan_v1", moduleId: "m2_check_in",
      messages: [{role: "user", content: "hi"}]},
  }), /permission-denied|not part of this study arm/);
});

// --- safety_events dedup ---------------------------------------------------

async function fire(fields) {
  const ref = await db.collection("safety_events").add(Object.assign({
    uid: UID, textHash: "h", level: "moderate",
    tier: "moderate_interrupt",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, fields));
  const snap = await ref.get();
  await fns.onSafetyEventCreated.run({data: snap, params: {eventId: ref.id}});
  return (await ref.get()).data();
}

async function events() {
  return (await db.collection("safety_events").get()).docs
      .map((d) => Object.assign({path: d.ref.path}, d.data()));
}

test("input + output scan of one turn → one counted event", async () => {
  await reset();
  const a = await fire({source: "user_input", turnId: "turn1",
    textHash: "in"});
  const b = await fire({source: "ai_output_scan", turnId: "turn1",
    textHash: "out"});
  assert.strictEqual(a.isDuplicate, false);
  assert.strictEqual(b.isDuplicate, true);
  assert.ok(b.duplicateOf.startsWith("safety_events/"));
  const counted = (await events()).filter((e) => !e.isDuplicate);
  assert.strictEqual(counted.length, 1);
  assert.strictEqual(counted[0].source, "user_input");
  assert.strictEqual(a.dedup_key, b.dedup_key);
});

test("higher-level duplicate raises the primary and alerts once", async () => {
  await reset();
  await fire({source: "user_input", turnId: "turn2", level: "moderate",
    tier: "moderate_review"});
  await fire({source: "ai_output_scan", turnId: "turn2", level: "acute",
    tier: "acute", matchedTerm: "自殺"});
  const evs = await events();
  const primary = evs.find((e) => !e.isDuplicate);
  assert.strictEqual(primary.level, "acute");
  assert.strictEqual(primary.tier, "acute");
  assert.strictEqual(primary.escalatedBy.source, "ai_output_scan");
  assert.strictEqual(primary.escalatedBy.matchedTerm, "自殺");
  const alerts = (await db.collection("pi_alerts").get()).docs;
  assert.strictEqual(alerts.length, 1, "PI alerted once");
  assert.strictEqual(alerts[0].data().level, "acute");
});

test("acute input then acute output → still one alert", async () => {
  await reset();
  await fire({source: "user_input", turnId: "turn3", level: "acute",
    tier: "acute", inputPoint: "chat_check_in"});
  await fire({source: "ai_output_scan", turnId: "turn3", level: "acute",
    tier: "acute"});
  const alerts = (await db.collection("pi_alerts").get()).docs;
  assert.strictEqual(alerts.length, 1);
  assert.strictEqual(alerts[0].data().inputPoint, "chat_check_in");
});

test("different turns are never merged", async () => {
  await reset();
  await fire({source: "user_input", turnId: "t-a", textHash: "same"});
  await fire({source: "user_input", turnId: "t-b", textHash: "same"});
  assert.strictEqual((await events()).filter((e) => !e.isDuplicate).length,
      2);
});

test("legacy events without turnId dedup across sources", async () => {
  await reset();
  // Before T7 the key held `source`, so these two made two alerts.
  await fire({source: "gateway_input", textHash: "x", level: "acute",
    tier: "acute"});
  await fire({source: "gateway_output", textHash: "x", level: "acute",
    tier: "acute"});
  assert.strictEqual((await events()).filter((e) => !e.isDuplicate).length,
      1);
  assert.strictEqual((await db.collection("pi_alerts").get()).size, 1);
});

test("every event keeps a source", async () => {
  await reset();
  for (const e of await events()) assert.ok(e.source);
  const a = await fire({source: "form", turnId: "f1",
    inputPoint: "thought_exercise"});
  assert.strictEqual(a.source, "form");
  assert.strictEqual(a.inputPoint, "thought_exercise");
});

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`  ok  ${t.name}`);
    } catch (err) {
      failed++;
      console.log(`  FAIL ${t.name}\n       ${err.stack}`);
    }
  }
  console.log(`safety_t7_emulator_test: ${tests.length - failed}/` +
    `${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();
