/**
 * 1020d §6 — 小篇章 trigger logic against the Firestore emulator.
 *
 *   A. handleChapterWrite called directly with the real Firestore, a fake
 *      model and a fake FCM sender: Hybrid ready (+ archive, push); rule
 *      arm and switch off get no model call (llm_denied_log row like the
 *      proxy); two deliveries of the same event at once → one run;
 *      re-request → version 2.
 *   B. The exported trigger onReminiscenceChapterWritten end to end, with
 *      DeepSeek stubbed (global fetch): the Pro draft goes out with
 *      thinking on, the Flash check with thinking off, both logged in
 *      llm_calls (chapter_draft / chapter_check); a rule-arm chapter
 *      makes no request at all.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/reminiscence_chapter_emulator_test.js"
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

const DRAFT = "我細個住喺潮州鄉下。屋企後面有條河。\n\n我同阿哥成日去河邊捉魚。";
const bodies = [];
global.fetch = async (url, init) => {
  const body = JSON.parse(init.body);
  bodies.push({url, body, headers: init.headers});
  const isCheck = body.model === "deepseek-flash";
  return {
    ok: true,
    status: 200,
    json: async () => ({
      model: body.model,
      system_fingerprint: "fp_test",
      choices: [{message: {role: "assistant",
        content: isCheck ? "{\"ok\": true, \"issues\": []}" : DRAFT},
      finish_reason: "stop"}],
      usage: {prompt_tokens: 900, completion_tokens: 300,
        completion_tokens_details: {reasoning_tokens: isCheck ? 0 : 200}},
    }),
    text: async () => "",
  };
};

const fns = require("../index");
const admin = require("firebase-admin");
const rc = require("../reminiscence_chapter");
const studyPeriod = require("../study_period");
const db = admin.firestore();

const NOW = Date.parse("2026-10-20T04:00:00Z"); // 12:00 HKT
const INPUT = {
  themeZh: "童年同屋企",
  items: [
    {questionIndex: 1, question: "講下你細個住嘅地方，係點樣嘅？",
      answer: "細個住喺潮州鄉下，屋企後面有條河", skipped: false,
      followups: [{q: "去河邊玩嗰陣，通常同邊個一齊去？", a: "同阿哥去捉魚"}],
      reply: "同阿哥一齊捉魚。"},
  ],
  extras: [],
};

const chRef = (uid) => db.doc(`users/${uid}/reminiscence_chapters/week_1`);

async function reset() {
  for (const c of ["users", "app_config", "llm_denied_log", "llm_calls"]) {
    await db.recursiveDelete(db.collection(c));
  }
  studyPeriod.resetGateCache();
  await db.doc("app_config/feature_flags").set({reminiscenceV2Enabled: true});
}

async function seedUser(uid, user, request) {
  await db.doc(`users/${uid}`).set(user);
  await db.doc(`users/${uid}/fcm_tokens/d1`).set({token: `tok-${uid}`});
  await chRef(uid).set(Object.assign({weekIndex: 1, source: "hybrid",
    status: "requested", requestId: "req-1",
    requestedAt: admin.firestore.FieldValue.serverTimestamp(),
    input: INPUT}, request || {}));
  return (await chRef(uid).get()).data();
}

function fakeModel() {
  const calls = [];
  const fn = async (req) => {
    calls.push(req);
    // Slow enough that two concurrent deliveries overlap.
    await new Promise((r) => setTimeout(r, 30));
    return {text: req.step === "check" ? "{\"ok\": true, \"issues\": []}" :
      DRAFT, model: req.model, usage: {prompt: 1, completion: 1,
      reasoning: 0}, latencyMs: 30, finishReason: "stop"};
  };
  fn.calls = calls;
  return fn;
}

function fakeMessaging() {
  const sent = [];
  return {sent, send: async (m) => {
    sent.push(m);
    return "id";
  }};
}

const deps = (model, messaging) => ({db, model, messaging,
  stripPII: (t) => t, now: () => NOW});

async function partA() {
  await reset();
  // Hybrid participant.
  const after = await seedUser("hy", {arm: "A", cohort: "phase_b",
    armAssignmentMode: "randomise"});
  const model = fakeModel();
  const fcm = fakeMessaging();
  const out = await rc.handleChapterWrite(deps(model, fcm),
      {uid: "hy", docId: "week_1", after});
  assert.strictEqual(out.action, "ready");
  const ch = (await chRef("hy").get()).data();
  assert.strictEqual(ch.status, "ready");
  assert.strictEqual(ch.finalText, DRAFT);
  assert.strictEqual(ch.version, 1);
  assert.deepStrictEqual(ch.flags, []);
  assert.deepStrictEqual(ch.deletedSentences, []);
  assert.ok(ch.generatedAt && ch.generatedAt.toDate);
  assert.strictEqual(ch.failReason, undefined);
  const run = (await chRef("hy").collection("runs").doc("req-1").get())
      .data();
  assert.strictEqual(run.state, "ready");
  assert.strictEqual(run.rounds.length, 1);
  assert.strictEqual(run.rounds[0].draft.text, DRAFT);
  assert.strictEqual(run.rounds[0].draft.model, "deepseek-v4-pro");
  assert.strictEqual(run.rounds[0].check.attempts[0].model, "deepseek-flash");
  assert.strictEqual(run.promptVersions.check,
      "reminiscence_chapter_check_v1@2026-10");
  assert.strictEqual(run.push.status, "sent");
  assert.strictEqual(fcm.sent.length, 1);
  assert.strictEqual(fcm.sent[0].notification.body,
      "你嘅第 1 章整理好喇，得閒入嚟睇下。");
  console.log("ok  A1 Hybrid → ready v1, archive in runs/req-1, push sent");

  // Two deliveries of the same event at once → one run.
  await chRef("hy").update({status: "requested", requestId: "req-2"});
  const again = (await chRef("hy").get()).data();
  const model2 = fakeModel();
  const results = await Promise.all([
    rc.handleChapterWrite(deps(model2, fakeMessaging()),
        {uid: "hy", docId: "week_1", after: again}),
    rc.handleChapterWrite(deps(model2, fakeMessaging()),
        {uid: "hy", docId: "week_1", after: again}),
  ]);
  const actions = results.map((r) => r.action).sort();
  assert.deepStrictEqual(actions, ["duplicate", "ready"], actions.join());
  assert.strictEqual(model2.calls.length, 2, "one draft + one check");
  assert.strictEqual((await chRef("hy").get()).get("version"), 2);
  console.log("ok  A2 same event twice at once → one run; re-request → v2");

  // Rule arm with a hybrid request → failed, denied, no model call.
  const afterB = await seedUser("rb", {arm: "B", cohort: "phase_b",
    armAssignmentMode: "randomise"});
  const modelB = fakeModel();
  const outB = await rc.handleChapterWrite(deps(modelB, fakeMessaging()),
      {uid: "rb", docId: "week_1", after: afterB});
  assert.strictEqual(outB.action, "not_hybrid");
  assert.strictEqual(modelB.calls.length, 0);
  const chB = (await chRef("rb").get()).data();
  assert.strictEqual(chB.status, "failed");
  assert.strictEqual(chB.failReason, "not_hybrid");
  const denied = await db.collection("llm_denied_log")
      .where("uid", "==", "rb").get();
  assert.strictEqual(denied.size, 1);
  assert.strictEqual(denied.docs[0].get("endpoint"), "reminiscenceChapter");
  assert.strictEqual(denied.docs[0].get("reason"), undefined);
  assert.ok(!(await chRef("rb").collection("runs").get()).size,
      "no run for the rule arm");
  console.log("ok  A3 rule arm: failed not_hybrid, llm_denied_log, no call");

  // A rule-arm chapter (source rule) → nothing at all.
  const ruleDoc = {weekIndex: 2, source: "rule", status: "ready",
    ruleText: "細個住嘅地方\n…", version: 1, requestId: "r", input: INPUT};
  const outR = await rc.handleChapterWrite(deps(modelB, fakeMessaging()),
      {uid: "rb", docId: "week_2", after: ruleDoc});
  assert.strictEqual(outR.action, "ignored");
  assert.strictEqual(modelB.calls.length, 0);
  console.log("ok  A4 rule chapter ignored");

  // Switch off → failed disabled.
  await db.doc("app_config/feature_flags").set(
      {reminiscenceV2Enabled: false});
  const afterOff = await seedUser("off", {arm: "A", cohort: "phase_b"});
  const modelOff = fakeModel();
  const outOff = await rc.handleChapterWrite(deps(modelOff, fakeMessaging()),
      {uid: "off", docId: "week_1", after: afterOff});
  assert.strictEqual(outOff.action, "disabled");
  assert.strictEqual(modelOff.calls.length, 0);
  assert.strictEqual((await chRef("off").get()).get("failReason"),
      "disabled");
  console.log("ok  A5 switch off → failed disabled, no call");
}

async function partB() {
  await reset();
  bodies.length = 0;
  const after = await seedUser("tr", {arm: "A", cohort: "phase_b",
    armAssignmentMode: "randomise", quietHoursEnabled: false});
  await db.recursiveDelete(db.collection("users/tr/fcm_tokens"));
  await fns.onReminiscenceChapterWritten.run({
    params: {uid: "tr", docId: "week_1"},
    data: {before: {exists: false}, after: {exists: true,
      data: () => after}},
  });
  const ch = (await chRef("tr").get()).data();
  assert.strictEqual(ch.status, "ready", JSON.stringify(ch.failReason));
  assert.strictEqual(ch.finalText, DRAFT);
  assert.strictEqual(bodies.length, 2);
  const [draft, check] = bodies.map((b) => b.body);
  assert.strictEqual(draft.model, "deepseek-v4-pro");
  assert.deepStrictEqual(draft.thinking, {type: "enabled"});
  assert.ok(draft.max_tokens >= 8000);
  assert.ok(draft.messages[0].content.startsWith("## 小篇章初稿"));
  assert.strictEqual(check.model, "deepseek-flash");
  assert.deepStrictEqual(check.thinking, {type: "disabled"});
  assert.deepStrictEqual(check.response_format, {type: "json_object"});
  assert.ok(bodies[0].headers["X-Session-Code"], "pseudonymous tag");
  assert.ok(!JSON.stringify(bodies).includes("\"tr\""), "uid never sent");
  const calls = await db.collection("llm_calls").where("uid", "==", "tr")
      .get();
  const types = calls.docs.map((d) => d.get("call_type")).sort();
  assert.deepStrictEqual(types, ["chapter_check", "chapter_draft"]);
  const draftRow = calls.docs.find((d) =>
    d.get("call_type") === "chapter_draft").data();
  assert.strictEqual(draftRow.model_requested, "deepseek-v4-pro");
  assert.strictEqual(draftRow.reasoning_tokens, 200);
  assert.strictEqual(draftRow.agent_id, "ah_jan_ah_bak");
  const run = (await chRef("tr").collection("runs").doc("req-1").get())
      .data();
  assert.strictEqual(run.push.status, "no_tokens");
  console.log("ok  B1 trigger end to end: Pro thinking on, Flash thinking " +
      "off, llm_calls rows, ready");

  // The trigger with a rule-arm chapter: no request at all.
  bodies.length = 0;
  await fns.onReminiscenceChapterWritten.run({
    params: {uid: "tr", docId: "week_2"},
    data: {before: {exists: false}, after: {exists: true,
      data: () => ({weekIndex: 2, source: "rule", status: "ready",
        ruleText: "x", version: 1})}},
  });
  assert.strictEqual(bodies.length, 0);
  // Its own 'ready' write coming back: no request either.
  await fns.onReminiscenceChapterWritten.run({
    params: {uid: "tr", docId: "week_1"},
    data: {before: {exists: true}, after: {exists: true,
      data: () => ch}},
  });
  assert.strictEqual(bodies.length, 0);
  console.log("ok  B2 trigger: rule chapter and the server's own write → " +
      "no request");
}

(async () => {
  await partA();
  await partB();
  console.log("reminiscence_chapter_emulator_test: all passed");
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
