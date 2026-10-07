/**
 * Memory v1 acceptance checks (T4, 2026-10-06) that need no real model:
 *   - Rule-based arm: zero extraction, zero injection, zero model calls,
 *     through the real callables (memoryEndSession, memorySweep,
 *     proxyDeepSeek).
 *   - Policy C ("basic facts shared, the rest private") on the actual
 *     system prompt proxyDeepSeek would send, with a policy-A positive
 *     control so the check cannot pass by being blind.
 *   - Deleted items are no longer injected.
 *   - The extraction prompt uses the Hong Kong date, also when the UTC
 *     date is still the day before.
 * The DeepSeek endpoint is stubbed: nothing leaves the machine.
 * The model-dependent part (30 dialogues) is tool/memory_eval/.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/memory_acceptance_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
const PROJECT = process.env.GCLOUD_PROJECT || "loneliness-pilot-dev";
if (!process.env.DEEPSEEK_API_KEY) process.env.DEEPSEEK_API_KEY = "stub";

// Every DeepSeek request is answered locally and recorded.
const calls = [];
const extractionReply = {summary: "", facts: [], followups: []};
global.fetch = async (url, init) => {
  const body = JSON.parse(init.body);
  const json = !!body.response_format;
  calls.push({url: String(url), json, system: body.messages[0].content,
    all: JSON.stringify(body.messages)});
  const content = json ? JSON.stringify(extractionReply) : "（stub）";
  return new Response(JSON.stringify({model: "stub",
    choices: [{message: {content}}]}), {status: 200});
};

const fft = require("firebase-functions-test")({projectId: PROJECT});
const fns = require("../index");
const m = require("../memory");
const admin = require("firebase-admin");
const db = admin.firestore();

const endSession = fft.wrap(fns.memoryEndSession);
const sweep = fft.wrap(fns.memorySweep);
const proxy = fft.wrap(fns.proxyDeepSeek);

const SURFACE = {
  siu_yan: ["m2_check_in", "siu_yan_v1"],
  ah_jan_ah_bak: ["reflective_dialogue", "ah_jan_ah_bak_v1"],
  tung_tung: ["tung_tung_chat", "tung_tung_v1"],
};
const MEM = ["mem_facts", "mem_summaries", "mem_followups",
  "mem_injections", "mem_extractions"];

async function wipe(uid) {
  const u = db.collection("users").doc(uid);
  for (const c of await u.listCollections()) {
    const docs = await c.listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
}

async function systemPromptFor(uid, agentId) {
  calls.length = 0;
  const [moduleId, promptKey] = SURFACE[agentId];
  await proxy({data: {agentId, moduleId, promptKey,
    messages: [{role: "user", content: "你好"}]}, auth: {uid}});
  const chat = calls.filter((c) => !c.json);
  assert.strictEqual(chat.length, 1, "one chat call");
  return chat[0].system;
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("rule-based arm: no extraction, no injection, no model call",
    async () => {
      await db.doc("meta/memory_config").set({enabled: true, policy: "C",
        phaseBArmA: true});
      for (const optIn of [true, false]) {
        const uid = `armB_${optIn}`;
        await wipe(uid);
        const u = db.collection("users").doc(uid);
        await u.set({arm: "B", armAssignmentMode: "randomise",
          memory_enabled: optIn});
        // Worst case: a stale client left a buffer and an item behind.
        const old = new Date(Date.now() - 2 * 3600 * 1000);
        for (const a of Object.keys(SURFACE)) {
          await u.collection("agent_contexts").doc(a).set({
            shortTermBuffer: [{fromUser: true, text: "叫我陳太（組B標記）",
              timestamp: old.toISOString()}],
            lastUpdated: old,
          });
        }
        await u.collection("mem_facts").doc("seeded").set({
          agent_id: "siu_yan", category: "name", key: "稱呼", value: "陳太",
          quote: "叫我陳太", status: "active", visibility: "shared",
          sensitivity: "normal"});
        calls.length = 0;
        for (const a of Object.keys(SURFACE)) {
          const r = await endSession({data: {agentId: a}, auth: {uid}});
          assert.strictEqual(r.status, "inactive");
          await assert.rejects(
              proxy({data: {agentId: a, moduleId: SURFACE[a][0],
                promptKey: SURFACE[a][1],
                messages: [{role: "user", content: "你好"}]}, auth: {uid}}),
              (e) => e.code === "permission-denied");
          assert.strictEqual(await m.injectMemory(db, {uid, agentId: a,
            moduleId: SURFACE[a][0],
            messages: [{role: "user", content: "你好"}]}), "");
        }
        await sweep({});
        // The sweep may serve other emulator users; none of the calls may
        // carry this Arm B user's words.
        assert.strictEqual(calls.filter((c) => c.all.includes("組B標記"))
            .length, 0, "no DeepSeek call for Arm B");
        assert.strictEqual(calls.filter((c) => !c.json).length, 0,
            "no chat call for Arm B");
        for (const c of MEM) {
          const n = (await u.collection(c).get()).size;
          assert.strictEqual(n, c === "mem_facts" ? 1 : 0, c);
        }
        const ctx = await u.collection("agent_contexts").doc("siu_yan").get();
        assert.strictEqual(ctx.get("shortTermBuffer").length, 1,
            "buffer not claimed");
      }
    });

async function seedMixed(uid) {
  await wipe(uid);
  const u = db.collection("users").doc(uid);
  // Decision 0020: accounts are migrated to sharedContextUse: true.
  await u.set({arm: "A", armAssignmentMode: "randomise",
    memory_enabled: false, consent: {sharedContextUse: true}});
  const today = m.hkDateKey(new Date());
  const add = (col, id, data) => u.collection(col).doc(id).set(
      Object.assign({created_at: new Date(), updated_at: new Date(),
        ended_at: new Date()}, data));
  // Each agent: one shared basic fact, one private fact, one confirmed
  // sensitive fact (in a shared category), one summary, one due follow-up.
  const tag = {siu_yan: "甲", ah_jan_ah_bak: "乙", tung_tung: "丙"};
  for (const a of Object.keys(SURFACE)) {
    const t = tag[a];
    await add("mem_facts", `${a}_shared`, {agent_id: a, category: "family",
      key: `家人${t}`, value: `共享家人${t}${t}`, status: "active",
      visibility: "shared", sensitivity: "normal"});
    await add("mem_facts", `${a}_private`, {agent_id: a, category: "hobby",
      key: `興趣${t}`, value: `私有興趣${t}${t}`, status: "active",
      visibility: "agent", sensitivity: "normal"});
    await add("mem_facts", `${a}_sensitive`, {agent_id: a, category: "family",
      key: `敏感${t}`, value: `敏感家事${t}${t}`, status: "active",
      visibility: "agent", sensitivity: "sensitive"});
    await add("mem_summaries", `${a}_sum`, {agent_id: a,
      summary: `私有摘要${t}${t}`, day_key: today, visibility: "agent",
      sensitivity: "normal"});
    await add("mem_followups", `${a}_fu`, {agent_id: a,
      description: `私有跟進${t}${t}`, due_date: today, status: "pending",
      sensitivity: "normal"});
  }
  return tag;
}

test("policy C: other agents' private memory never reaches the prompt",
    async () => {
      await db.doc("meta/memory_config").set({enabled: true, policy: "C",
        phaseBArmA: true});
      const uid = "leak_c";
      const tag = await seedMixed(uid);
      for (const a of Object.keys(SURFACE)) {
        const sys = await systemPromptFor(uid, a);
        for (const b of Object.keys(SURFACE)) {
          const t = tag[b];
          assert.ok(sys.includes(`共享家人${t}${t}`), `${a} sees ${b} shared`);
          for (const priv of [`私有興趣${t}${t}`, `敏感家事${t}${t}`,
            `私有摘要${t}${t}`, `私有跟進${t}${t}`]) {
            assert.strictEqual(sys.includes(priv), a === b,
                `${a} / ${priv}`);
          }
        }
      }
    });

test("positive control: policy A does share normal private items",
    async () => {
      await db.doc("meta/memory_config").set({enabled: true, policy: "A",
        phaseBArmA: true});
      const uid = "leak_a";
      const tag = await seedMixed(uid);
      const sys = await systemPromptFor(uid, "siu_yan");
      assert.ok(sys.includes(`私有興趣${tag.tung_tung}${tag.tung_tung}`));
      assert.ok(!sys.includes(`敏感家事${tag.tung_tung}${tag.tung_tung}`),
          "sensitive stays private even under A");
      await db.doc("meta/memory_config").set({policy: "C"}, {merge: true});
    });

test("a deleted fact, summary or follow-up is no longer injected",
    async () => {
      await db.doc("meta/memory_config").set({enabled: true, policy: "C",
        phaseBArmA: true});
      const uid = "del";
      const tag = await seedMixed(uid);
      const u = db.collection("users").doc(uid);
      const t = tag.siu_yan;
      let sys = await systemPromptFor(uid, "ah_jan_ah_bak");
      assert.ok(sys.includes(`共享家人${t}${t}`));
      await u.collection("mem_facts").doc("siu_yan_shared").delete();
      await u.collection("mem_facts").doc("siu_yan_private").delete();
      await u.collection("mem_summaries").doc("siu_yan_sum").delete();
      await u.collection("mem_followups").doc("siu_yan_fu").delete();
      for (const a of Object.keys(SURFACE)) {
        sys = await systemPromptFor(uid, a);
        for (const gone of [`共享家人${t}${t}`, `私有興趣${t}${t}`,
          `私有摘要${t}${t}`, `私有跟進${t}${t}`]) {
          assert.ok(!sys.includes(gone), `${a} still sees ${gone}`);
        }
      }
    });

test("extraction prompt uses the Hong Kong date at 01:30 HKT", async () => {
  await db.doc("meta/memory_config").set({enabled: true, policy: "C",
    phaseBArmA: true});
  const uid = "tz";
  await wipe(uid);
  const u = db.collection("users").doc(uid);
  await u.set({arm: "A", armAssignmentMode: "randomise",
    consent: {sharedContextUse: true}});
  const now = new Date("2026-10-06T17:30:00Z"); // 2026-10-07 01:30 HKT
  await u.collection("agent_contexts").doc("siu_yan").set({
    shortTermBuffer: [{fromUser: true, text: "聽日去街市",
      timestamp: now.toISOString()}]});
  let prompt = null;
  const id = await m.claimBuffer(db, uid, "siu_yan");
  await m.processExtraction(db, uid, id, async (p) => {
    prompt = p;
    return JSON.stringify({summary: "去街市", facts: [], followups: [
      {description: "去街市", due_date: "2026-10-08", quote: "聽日去街市"}]});
  }, now);
  assert.ok(prompt.system.includes("今日係 2026-10-07（星期三，香港時間）"),
      "HK date and weekday");
  const sum = (await u.collection("mem_summaries").get()).docs[0];
  assert.strictEqual(sum.get("day_key"), "2026-10-07");
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
