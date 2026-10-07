/**
 * Memory v1 — Firestore I/O against the emulator (claim, extract, inject).
 * The model is a stub, so no network is needed.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/memory_emulator_test.js"
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

const NOW = new Date("2026-09-29T04:00:00Z"); // 12:00 HKT
const UID = "u1";
const user = () => db.collection("users").doc(UID);

async function reset({enabled = true, optIn = true, arm = "A"} = {}) {
  const cols = await user().listCollections();
  for (const c of cols) {
    const docs = await c.listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
  await db.doc("meta/memory_config").set({enabled, policy: "C"});
  // Decision 0020: sharing is enforced by default; existing accounts are
  // migrated to sharedContextUse: true.
  await user().set({memory_enabled: optIn, arm,
    consent: {sharedContextUse: true}});
}

async function seedBuffer(agentId, lines) {
  await user().collection("agent_contexts").doc(agentId).set({
    shortTermBuffer: lines.map(([fromUser, text], i) => ({
      fromUser, text,
      timestamp: new Date(NOW.getTime() - (lines.length - i) * 60000)
          .toISOString(),
    })),
  });
}

const GOOD = {
  summary: "陳太講起下星期四會去睇醫生，又講鍾意飲早茶。",
  facts: [
    {op: "add", category: "name", key: "稱呼", value: "陳太",
      quote: "叫我陳太"},
    {op: "add", category: "hobby", key: "飲早茶", value: "鍾意飲早茶",
      quote: "我鍾意飲早茶"},
    {op: "add", category: "health", key: "膝頭", value: "膝頭痛",
      quote: "我膝頭好痛"},
  ],
  followups: [{description: "睇醫生", due_date: "2026-09-29",
    quote: "下個禮拜四睇醫生"}],
};
const stub = (obj) => async () => JSON.stringify(obj);

const tests = [];
const test = (name, fn) => tests.push({name, fn});

test("claim is one-shot: a second claim finds an empty buffer", async () => {
  await reset();
  await seedBuffer("tung_tung", [[true, "你好"]]);
  const [a, b] = await Promise.all([
    m.claimBuffer(db, UID, "tung_tung"),
    m.claimBuffer(db, UID, "tung_tung"),
  ]);
  assert.ok((a === null) !== (b === null), `claims: ${a}, ${b}`);
  const ctx = await user().collection("agent_contexts").doc("tung_tung").get();
  assert.deepStrictEqual(ctx.get("shortTermBuffer"), []);
});

test("extraction writes every layer in one go", async () => {
  await reset();
  await seedBuffer("tung_tung", [
    [false, "今日點呀？"],
    [true, "大家都叫我陳太。我鍾意飲早茶。"],
    [true, "我膝頭好痛，下個禮拜四睇醫生。"],
  ]);
  const id = await m.claimBuffer(db, UID, "tung_tung");
  const status = await m.processExtraction(db, UID, id, stub(GOOD), NOW);
  assert.strictEqual(status, "done");

  const facts = (await user().collection("mem_facts").get()).docs
      .map((d) => d.data());
  const byKey = Object.fromEntries(facts.map((f) => [f.key, f]));
  assert.strictEqual(byKey["稱呼"].visibility, "shared");
  assert.strictEqual(byKey["飲早茶"].visibility, "agent");
  assert.strictEqual(byKey["膝頭"].status, "pending_confirmation");
  assert.strictEqual(byKey["膝頭"].sensitivity, "sensitive");

  const sums = await user().collection("mem_summaries").get();
  assert.strictEqual(sums.size, 1);
  assert.strictEqual(sums.docs[0].get("day_key"), "2026-09-29");
  const fus = await user().collection("mem_followups").get();
  assert.strictEqual(fus.size, 1);

  const ext = await user().collection("mem_extractions").doc(id).get();
  assert.strictEqual(ext.get("status"), "done");
  assert.deepStrictEqual(ext.get("turns"), [], "transcript cleared");
  assert.ok(ext.get("raw_output").includes("陳太"), "raw output kept");
});

test("bad JSON writes nothing and leaves the extraction retryable",
    async () => {
      await reset();
      await seedBuffer("siu_yan", [[true, "叫我陳太"]]);
      const id = await m.claimBuffer(db, UID, "siu_yan");
      const status = await m.processExtraction(db, UID, id,
          async () => "not json", NOW);
      assert.strictEqual(status, "failed");
      assert.strictEqual((await user().collection("mem_facts").get()).size, 0);
      assert.strictEqual(
          (await user().collection("mem_summaries").get()).size, 0);
      const ext = await user().collection("mem_extractions").doc(id).get();
      assert.strictEqual(ext.get("attempts"), 1);
      assert.ok(ext.get("turns").length > 0, "transcript kept for retry");

      const retry = await m.processExtraction(db, UID, id, stub(GOOD), NOW);
      assert.strictEqual(retry, "done");
    });

test("a correction supersedes the old fact instead of deleting it",
    async () => {
      await reset();
      await seedBuffer("siu_yan", [[true, "叫我陳太"]]);
      let id = await m.claimBuffer(db, UID, "siu_yan");
      await m.processExtraction(db, UID, id, stub({summary: "",
        facts: [GOOD.facts[0]], followups: []}), NOW);
      const old = (await user().collection("mem_facts").get()).docs[0];

      await seedBuffer("siu_yan", [[true, "唔係呀，叫我何太先啱"]]);
      id = await m.claimBuffer(db, UID, "siu_yan");
      await m.processExtraction(db, UID, id, stub({summary: "", facts: [
        {op: "update", fact_id: old.id, category: "name", key: "稱呼",
          value: "何太", quote: "叫我何太", correction: true},
      ], followups: []}), NOW);

      const all = (await user().collection("mem_facts").get()).docs;
      const prev = all.find((d) => d.id === old.id);
      const next = all.find((d) => d.id !== old.id);
      assert.strictEqual(prev.get("status"), "superseded");
      assert.strictEqual(prev.get("superseded_by"), next.id);
      assert.strictEqual(next.get("value"), "何太");
      assert.strictEqual(next.get("user_corrected"), true);
      assert.strictEqual(next.get("revision_count"), 1);
    });

test("injection: off without the kill switch or the opt-in", async () => {
  const args = {uid: UID, agentId: "tung_tung", moduleId: "tung_tung_chat",
    messages: [{role: "user", content: "hi"}], now: NOW};
  await reset({enabled: false});
  await user().collection("mem_facts").add({agent_id: "tung_tung",
    category: "name", key: "稱呼", value: "陳太", status: "active",
    visibility: "shared", sensitivity: "normal"});
  assert.strictEqual(await m.injectMemory(db, args), "");
  await db.doc("meta/memory_config").set({enabled: true});
  await user().set({memory_enabled: false}, {merge: true});
  assert.strictEqual(await m.injectMemory(db, args), "");
  await user().set({memory_enabled: true, arm: "B"}, {merge: true});
  assert.strictEqual(await m.injectMemory(db, args), "", "never for Arm B");
  await user().set({arm: "A"}, {merge: true});
  assert.ok((await m.injectMemory(db, args)).includes("陳太"));
});

test("injection logs what it used and asks a follow-up once", async () => {
  await reset();
  await seedBuffer("tung_tung", [
    [true, "大家都叫我陳太。我鍾意飲早茶。"],
    [true, "我膝頭好痛，下個禮拜四睇醫生。"],
  ]);
  const id = await m.claimBuffer(db, UID, "tung_tung");
  await m.processExtraction(db, UID, id, stub(GOOD), NOW);

  const first = await m.injectMemory(db, {uid: UID, agentId: "tung_tung",
    moduleId: "tung_tung_chat", messages: [{role: "user", content: "hi"}],
    now: NOW});
  assert.ok(first.includes("<memory>"));
  assert.ok(first.includes("[到期要關心嘅事]"),
      "due follow-up at session start");
  assert.ok(!first.includes("膝頭"), "unconfirmed sensitive fact withheld");

  const fu = (await user().collection("mem_followups").get()).docs[0];
  assert.strictEqual(fu.get("status"), "asked");

  const second = await m.injectMemory(db, {uid: UID, agentId: "tung_tung",
    moduleId: "tung_tung_chat", messages: [{role: "user", content: "hi"}],
    now: NOW});
  assert.ok(!second.includes("[到期要關心嘅事]"), "not asked twice");

  const logs = await user().collection("mem_injections").get();
  assert.strictEqual(logs.size, 2);
  const log = logs.docs.find((d) => d.get("layers").followup === 1);
  assert.ok(log.get("memory_ids").includes(fu.id));
  assert.strictEqual(log.get("policy"), "C");
});

test("another agent sees only the shared basic fact (policy C)", async () => {
  await reset();
  await seedBuffer("tung_tung", [
    [true, "大家都叫我陳太。我鍾意飲早茶。"],
    [true, "我膝頭好痛，下個禮拜四睇醫生。"],
  ]);
  const id = await m.claimBuffer(db, UID, "tung_tung");
  await m.processExtraction(db, UID, id, stub(GOOD), NOW);
  const block = await m.injectMemory(db, {uid: UID, agentId: "siu_yan",
    moduleId: "m2_check_in", messages: [{role: "user", content: "hi"}],
    now: NOW});
  assert.ok(block.includes("陳太"));
  assert.ok(!block.includes("早茶"), "Tung Tung's private fact");
  assert.ok(!block.includes("[到期要關心嘅事]"), "Tung Tung's follow-up");
  assert.ok(!block.includes("之前傾過"), "Tung Tung's summaries");
});

test("modules outside the chat surfaces get nothing", async () => {
  await reset();
  await user().collection("mem_facts").add({agent_id: "siu_yan",
    category: "name", key: "稱呼", value: "陳太", status: "active",
    visibility: "shared", sensitivity: "normal"});
  const block = await m.injectMemory(db, {uid: UID, agentId: "siu_yan",
    moduleId: "rolling_summary_fold", messages: [], now: NOW});
  assert.strictEqual(block, "");
});

test("Phase B Arm A gets memory without opting in; Phase A Arm A does not",
    async () => {
      await reset();
      await db.doc("meta/memory_config").set({enabled: true,
        phaseBArmA: true});
      await user().collection("mem_facts").add({agent_id: "siu_yan",
        category: "name", key: "稱呼", value: "陳太", status: "active",
        visibility: "shared", sensitivity: "normal"});
      const args = {uid: UID, agentId: "siu_yan", moduleId: "m2_check_in",
        messages: [{role: "user", content: "hi"}], now: NOW};
      await user().set({memory_enabled: false, arm: "A",
        armAssignmentMode: "randomise"});
      assert.ok((await m.injectMemory(db, args)).includes("陳太"));
      await user().set({memory_enabled: false, arm: "A",
        armAssignmentMode: "force_a"});
      assert.strictEqual(await m.injectMemory(db, args), "");
      await user().set({memory_enabled: false, arm: "B",
        armAssignmentMode: "randomise"});
      assert.strictEqual(await m.injectMemory(db, args), "");
    });

test("sharedContextUse consent: enforced + off → only own items (C20)",
    async () => {
      await reset();
      await seedBuffer("tung_tung", [
        [true, "大家都叫我陳太。我鍾意飲早茶。"],
      ]);
      const id = await m.claimBuffer(db, UID, "tung_tung");
      await m.processExtraction(db, UID, id, stub(GOOD), NOW);
      const args = {uid: UID, agentId: "siu_yan", moduleId: "m2_check_in",
        messages: [{role: "user", content: "hi"}], now: NOW};
      const setUser = (shared) => user().set({memory_enabled: true,
        arm: "A", consent: {sharedContextUse: shared}});
      try {
        // Switch explicitly off: consent ignored.
        await db.doc("app_config/phase_a").set(
            {enforceSharedContextConsent: false});
        await setUser(false);
        assert.ok((await m.injectMemory(db, args)).includes("陳太"));
        // Default (no app_config/phase_a) is on: consent off → Tung Tung's
        // shared fact stays with it.
        await db.doc("app_config/phase_a").delete();
        assert.strictEqual(await m.injectMemory(db, args), "");
        const own = await m.injectMemory(db, {...args,
          agentId: "tung_tung", moduleId: "tung_tung_chat"});
        assert.ok(own.includes("陳太"), "own agent still sees it");
        // Switch on, consent on: shared again.
        await setUser(true);
        assert.ok((await m.injectMemory(db, args)).includes("陳太"));
        const logs = (await user().collection("mem_injections").get()).docs
            .map((d) => d.get("policy"));
        assert.ok(logs.includes("B") && logs.includes("C"), String(logs));
      } finally {
        await db.doc("app_config/phase_a").delete();
      }
    });

test("sharedContextUse consent: extractor sees only own facts (C20)",
    async () => {
      await reset();
      await user().collection("mem_facts").add({agent_id: "siu_yan",
        category: "name", key: "稱呼", value: "陳太", status: "active",
        visibility: "shared", sensitivity: "normal"});
      await user().set({memory_enabled: true, arm: "A",
        consent: {sharedContextUse: false}});
      await db.doc("app_config/phase_a").set(
          {enforceSharedContextConsent: true});
      try {
        await seedBuffer("tung_tung", [[true, "我鍾意飲早茶。"]]);
        const id = await m.claimBuffer(db, UID, "tung_tung");
        let prompt = "";
        await m.processExtraction(db, UID, id, async (p) => {
          prompt = JSON.stringify(p);
          return JSON.stringify({summary: "", facts: [], followups: []});
        }, NOW);
        assert.ok(prompt.length > 0);
        assert.ok(!prompt.includes("陳太"), "Siu Yan's fact not shown");
      } finally {
        await db.doc("app_config/phase_a").delete();
      }
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
