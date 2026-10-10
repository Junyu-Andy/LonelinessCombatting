/**
 * T31 memory layers (decision 0034) against the Firestore emulator:
 * extraction writes layer + sourceAgent, injection filters by layer and
 * logs the dose, 「唔好記住」 and deletion cover both layers, and the
 * switch off leaves everything as before. The model is a stub.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/memory_layers_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const m = require("../memory");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();

const NOW = new Date("2026-10-10T04:00:00Z"); // 12:00 HKT
const TODAY = "2026-10-10";
const UID = "t31";
const user = () => db.collection("users").doc(UID);

async function reset({layers = true, consent = true, arm = "A"} = {}) {
  for (const c of await user().listCollections()) {
    const docs = await c.listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
  await db.doc("meta/memory_config").set({enabled: true, policy: "C",
    phaseBArmA: true, layersEnabled: layers});
  await user().set({arm, armAssignmentMode: "randomise",
    consent: {sharedContextUse: consent}});
}

async function extractWith(agentId, lines, modelOut) {
  await user().collection("agent_contexts").doc(agentId).set({
    shortTermBuffer: lines.map(([fromUser, text], i) => ({fromUser, text,
      timestamp: new Date(NOW.getTime() - (lines.length - i) * 60000)
          .toISOString()})),
  });
  const id = await m.claimBuffer(db, UID, agentId);
  const prompts = [];
  const status = await m.processExtraction(db, UID, id, async (p) => {
    prompts.push(p);
    return JSON.stringify(modelOut);
  }, NOW);
  return {id, status, prompts};
}

const docsOf = async (col) =>
  (await user().collection(col).get()).docs.map((d) => ({id: d.id,
    ...d.data()}));

const inject = (agentId, content = "你好") => m.injectMemory(db, {
  uid: UID, agentId,
  moduleId: agentId === "tung_tung" ? "tung_tung_chat" : "m2_check_in",
  messages: [{role: "user", content}], now: NOW, sessionId: "sess-1"});

/** 小欣 hears one of everything. */
const SIU_YAN_TURNS = [
  [true, "大家都叫我陳太。我個女叫阿欣。"],
  [true, "我自己一個住喺深水埗，朝早會去公園行下。"],
  [true, "我鍾意飲早茶。"],
  [true, "最近成日掛住老伴，心入面有啲唔舒服。"],
  [true, "後生嗰陣我喺製衣廠做咗廿年。"],
  [true, "聽日要去社區中心攞嘢。"],
];
const SIU_YAN_OUT = {
  summary: "陳太講起飲早茶同埋舊時喺製衣廠做嘢。",
  facts: [
    {op: "add", category: "name", key: "稱呼", value: "陳太",
      quote: "大家都叫我陳太"},
    {op: "add", category: "family", key: "個女", value: "個女叫阿欣",
      quote: "我個女叫阿欣"},
    {op: "add", category: "living", key: "居住", value: "自己住深水埗",
      quote: "我自己一個住喺深水埗"},
    {op: "add", category: "routine", key: "晨運", value: "朝早去公園行",
      quote: "朝早會去公園行下"},
    {op: "add", category: "hobby", key: "飲茶", value: "鍾意飲早茶",
      quote: "我鍾意飲早茶"},
    {op: "add", category: "feeling", key: "掛住老伴",
      value: "最近成日掛住老伴", quote: "最近成日掛住老伴",
      sensitive: true},
    {op: "add", category: "story", key: "製衣廠",
      value: "後生喺製衣廠做咗廿年", quote: "後生嗰陣我喺製衣廠做咗廿年"},
  ],
  followups: [{description: "去社區中心攞嘢", due_date: "2026-10-11",
    quote: "聽日要去社區中心攞嘢"}],
};

async function siuYanSession() {
  await db.doc("meta/memory_config").set(
      {extractionPrompt: "memory_extraction.v3"}, {merge: true});
  const r = await extractWith("siu_yan", SIU_YAN_TURNS, SIU_YAN_OUT);
  assert.strictEqual(r.status, "done");
  return r;
}

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("extraction writes layer and sourceAgent on every item", async () => {
  await reset();
  await siuYanSession();
  const facts = Object.fromEntries((await docsOf("mem_facts"))
      .map((f) => [f.key, f]));
  for (const k of ["稱呼", "個女", "居住", "晨運", "飲茶"]) {
    assert.strictEqual(facts[k].layer, "shared", k);
  }
  for (const k of ["掛住老伴", "製衣廠"]) {
    assert.strictEqual(facts[k].layer, "private", k);
  }
  for (const f of Object.values(facts)) {
    assert.strictEqual(f.sourceAgent, "siu_yan");
  }
  const [s] = await docsOf("mem_summaries");
  assert.strictEqual(s.layer, "private");
  assert.strictEqual(s.sourceAgent, "siu_yan");
  const [fu] = await docsOf("mem_followups");
  assert.strictEqual(fu.layer, "private");
  assert.strictEqual(fu.sourceAgent, "siu_yan");
});

test("1. shared facts reach 阿珍 and 通通; private ones do not", async () => {
  await reset();
  await siuYanSession();
  // Confirm the sensitive one, so only the layer can keep it out.
  for (const f of await docsOf("mem_facts")) {
    if (f.status === "pending_confirmation") {
      await user().collection("mem_facts").doc(f.id)
          .update({status: "active"});
    }
  }
  for (const agent of ["ah_jan_ah_bak", "tung_tung"]) {
    const block = await inject(agent);
    for (const w of ["陳太", "阿欣", "深水埗", "公園", "早茶"]) {
      assert.ok(block.includes(w), `${agent} should know ${w}`);
    }
    for (const w of ["老伴", "製衣廠", "社區中心", "之前傾過"]) {
      assert.ok(!block.includes(w), `${agent} must not know ${w}`);
    }
  }
  const own = await inject("siu_yan");
  for (const w of ["陳太", "老伴", "製衣廠", "之前傾過"]) {
    assert.ok(own.includes(w), `小欣 should know ${w}`);
  }
});

test("1b. 阿珍's extractor sees 小欣's shared facts, not the private",
    async () => {
      await reset();
      await siuYanSession();
      const r = await extractWith("ah_jan_ah_bak", [[true, "今日好天。"]],
          {summary: "", facts: [], followups: []});
      const seen = r.prompts[0].user;
      assert.ok(seen.includes("陳太") && seen.includes("早茶"));
      assert.ok(!seen.includes("製衣廠"), "private story");
    });

test("2. a shared-category fact judged sensitive is not shared", async () => {
  await reset();
  await extractWith("siu_yan", [[true, "我同個仔嗌交，已經冇嚟往。"]], {
    summary: "", followups: [], facts: [{op: "add", category: "family",
      key: "個仔", value: "同個仔嗌交冇嚟往", quote: "我同個仔嗌交"}]});
  const [f] = await docsOf("mem_facts");
  assert.strictEqual(f.sensitivity, "sensitive");
  assert.strictEqual(f.layer, "private");
  await user().collection("mem_facts").doc(f.id).update({status: "active"});
  assert.ok(!(await inject("tung_tung")).includes("個仔"));
  assert.ok((await inject("siu_yan")).includes("個仔"));
});

test("3. only the companion who heard it raises the follow-up", async () => {
  await reset();
  await extractWith("ah_jan_ah_bak", [[true, "今日下晝去飲宴。"]], {
    summary: "", facts: [], followups: [{description: "去飲宴",
      due_date: TODAY, quote: "今日下晝去飲宴"}]});
  assert.ok(!(await inject("siu_yan")).includes("飲宴"));
  assert.ok(!(await inject("tung_tung")).includes("飲宴"));
  const [fu0] = await docsOf("mem_followups");
  assert.strictEqual(fu0.status, "pending", "untouched by the others");
  assert.ok((await inject("ah_jan_ah_bak")).includes("飲宴"));
  const [fu] = await docsOf("mem_followups");
  assert.strictEqual(fu.status, "asked");
});

test("4. sharedContextUse consent off: nothing is shared", async () => {
  await reset({consent: false});
  await siuYanSession();
  const block = await inject("tung_tung");
  assert.strictEqual(block, "");
  assert.ok((await inject("siu_yan")).includes("陳太"));
});

test("5. 「唔好記住」: no new item in either layer, old ones gone",
    async () => {
      await reset();
      await user().collection("mem_facts").doc("old_shared").set({
        agent_id: "tung_tung", sourceAgent: "tung_tung", layer: "shared",
        category: "routine", key: "麻雀", value: "逢禮拜三同老友打麻雀",
        quote: "逢禮拜三同老友打麻雀", status: "active",
        sensitivity: "normal"});
      await user().collection("mem_facts").doc("old_private").set({
        agent_id: "siu_yan", category: "event", key: "輸錢",
        value: "打麻雀輸咗錢", quote: "打麻雀輸咗錢", status: "active",
        sensitivity: "sensitive"});
      const r = await extractWith("ah_jan_ah_bak", [
        [true, "我叫陳太，鍾意打麻雀。"],
        [true, "打麻雀輸咗錢嘅事，你唔好記住呀。"],
      ], SIU_YAN_OUT);
      assert.strictEqual(r.prompts.length, 0, "no model call");
      const facts = (await docsOf("mem_facts")).map((f) => f.id);
      assert.deepStrictEqual(facts, [], `left: ${facts}`);
      assert.strictEqual((await docsOf("mem_summaries")).length, 0);
      assert.strictEqual((await docsOf("mem_followups")).length, 0);
    });

test("6. deleting one item removes it from both layers and summaries",
    async () => {
      await reset();
      await siuYanSession();
      // 通通 heard the same story and keeps its own private copy.
      await extractWith("tung_tung", [[true, "我以前喺製衣廠做嘢。"]], {
        summary: "", followups: [], facts: [{op: "add", category: "story",
          key: "製衣廠", value: "以前喺製衣廠做", quote: "以前喺製衣廠做"}]});
      // A summary from 阿珍 quoting the shared fact word for word.
      await user().collection("mem_summaries").doc("aj").set({
        agent_id: "ah_jan_ah_bak", summary: "陳太話佢鍾意飲早茶。",
        day_key: TODAY, sensitivity: "normal"});
      const all = await docsOf("mem_facts");
      const story = all.find((f) => f.sourceAgent === "siu_yan" &&
        f.key === "製衣廠");
      await user().collection("mem_facts").doc(story.id).delete();
      await m.deleteSummaryForItem(db, UID, story);
      const left = await docsOf("mem_facts");
      assert.ok(!left.some((f) => f.key === "製衣廠"), "both copies gone");
      assert.ok(left.some((f) => f.key === "飲茶"), "unrelated kept");
      const sums = await docsOf("mem_summaries");
      assert.deepStrictEqual(sums.map((s) => s.id), ["aj"],
          "小欣's session summary gone");

      const tea = left.find((f) => f.key === "飲茶");
      await user().collection("mem_facts").doc(tea.id).delete();
      await m.deleteSummaryForItem(db, UID, tea);
      assert.strictEqual((await docsOf("mem_summaries")).length, 0,
          "summary quoting 鍾意飲早茶 gone");
    });

test("7. the injection log counts shared and private as injected",
    async () => {
      await reset();
      await siuYanSession();
      await inject("tung_tung");
      await inject("siu_yan");
      const logs = await docsOf("mem_injections");
      const tung = logs.find((l) => l.agent_id === "tung_tung");
      assert.deepStrictEqual(tung.layer_counts, {shared: 5, private: 0});
      assert.deepStrictEqual(tung.source_agents,
          {shared: {siu_yan: 5}, private: {}});
      assert.strictEqual(tung.session_id, "sess-1");
      assert.strictEqual(tung.memory_ids.length, 5);
      const siu = logs.find((l) => l.agent_id === "siu_yan");
      // 5 shared facts; private: the story, the follow-up (due tomorrow,
      // so not yet), the summary. The feeling waits for confirmation.
      assert.deepStrictEqual(siu.layer_counts, {shared: 5, private: 2});
      assert.strictEqual(siu.memory_ids.length, 7);
      assert.deepStrictEqual(siu.source_agents.private, {siu_yan: 2});
    });

test("8a. switch off: same as before (no layer fields, policy C)",
    async () => {
      await reset({layers: false});
      await siuYanSession();
      for (const f of await docsOf("mem_facts")) {
        assert.strictEqual(f.layer, undefined);
        assert.strictEqual(f.sourceAgent, undefined);
      }
      const block = await inject("tung_tung");
      assert.ok(block.includes("陳太") && block.includes("阿欣"));
      assert.ok(!block.includes("早茶") && !block.includes("公園"),
          "routine / hobby stay private under the old rule");
      const [log] = await docsOf("mem_injections");
      assert.strictEqual(log.layer_counts, undefined);
      assert.strictEqual(log.session_id, undefined);
      // v3 categories are rejected by the default prompt v2.
      await db.doc("meta/memory_config").set(
          {extractionPrompt: "memory_extraction.v2"}, {merge: true});
      const r = await extractWith("siu_yan", [[true, "後生嗰陣我喺製衣廠做"]],
          {summary: "", followups: [], facts: [SIU_YAN_OUT.facts[6]]});
      assert.strictEqual(r.status, "failed");
    });

test("8b. rule arm: no memory read or write with layers on", async () => {
  await reset({arm: "B"});
  // memoryEndSession and memorySweep (index.js) extract only when
  // memoryActive / inScope say yes; a stray item must not be injected.
  await user().collection("mem_facts").doc("x").set({agent_id: "siu_yan",
    category: "name", key: "稱呼", value: "陳太", status: "active",
    sensitivity: "normal", layer: "shared"});
  assert.strictEqual(await m.memoryActive(db, UID), null);
  assert.strictEqual(await inject("tung_tung"), "");
  assert.strictEqual((await docsOf("mem_injections")).length, 0);
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
