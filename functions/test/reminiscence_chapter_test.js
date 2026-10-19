/**
 * 1020d §6 — 小篇章 pipeline (functions/reminiscence_chapter.js) with a
 * fake model client and an in-memory Firestore.  No network, no emulator.
 *
 *   - helpers: config, request bodies (Pro thinking on / Flash thinking
 *     off), check parsing, sentences, quote matching, deletion;
 *   - pipeline: clean first draft; one rewrite; still flagged after two
 *     rounds → sentence deleted; malformed JSON (retry once, then "not
 *     ok"); time budget; a failed rewrite; the archive of every round;
 *   - trigger work: rule arm / switch off / non-Hybrid get no model call;
 *     idempotency per requestId; version bump; superseded request; push
 *     and quiet hours; empty input; hotline filter.
 *
 * Run:  cd functions && node test/reminiscence_chapter_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const rc = require("../reminiscence_chapter");
const studyPeriod = require("../study_period");
const {resetSafetyConfigCache} = require("../safety_config");

let passed = 0;
const failures = [];
const queue = [];
function test(name, fn) {
  queue.push({name, fn});
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

const NOW = Date.parse("2026-10-20T04:00:00Z"); // 12:00 HKT
const QUIET_NOW = Date.parse("2026-10-20T15:00:00Z"); // 23:00 HKT

function fakeDb() {
  const store = new Map();
  const DELETE = {__delete: true};
  const fieldValue = {
    serverTimestamp: () => ({__serverTs: true}),
    delete: () => DELETE,
  };
  let auto = 0;
  const value = (v) => (v && v.__serverTs ? new Date(NOW) : v);
  function write(path, data, merge) {
    const next = merge ? Object.assign({}, store.get(path) || {}) : {};
    for (const k of Object.keys(data)) {
      if (data[k] && data[k].__delete) delete next[k];
      else next[k] = value(data[k]);
    }
    store.set(path, next);
  }
  function snap(path) {
    const d = store.get(path);
    return {
      exists: d !== undefined,
      id: path.split("/").pop(),
      ref: docRef(path),
      data: () => (d === undefined ? undefined :
        JSON.parse(JSON.stringify(d))),
      get: (k) => (d === undefined ? undefined : d[k]),
    };
  }
  function docRef(path) {
    return {
      path,
      id: path.split("/").pop(),
      get: async () => snap(path),
      set: async (d, o) => write(path, d, !!(o && o.merge)),
      update: async (d) => {
        if (!store.has(path)) throw new Error(`NOT_FOUND ${path}`);
        write(path, d, true);
      },
      collection: (n) => colRef(`${path}/${n}`),
    };
  }
  function colRef(path) {
    const depth = path.split("/").length + 1;
    return {
      path,
      doc: (id) => docRef(`${path}/${id || `auto${++auto}`}`),
      add: async (d) => {
        const p = `${path}/auto${++auto}`;
        write(p, d, false);
        return docRef(p);
      },
      get: async () => {
        const docs = [...store.keys()].filter((p) =>
          p.startsWith(`${path}/`) && p.split("/").length === depth)
            .map(snap);
        return {docs, size: docs.length, empty: docs.length === 0};
      },
    };
  }
  return {
    store,
    fieldValue,
    doc: docRef,
    collection: colRef,
    data: (path) => store.get(path),
    rows: (col) => [...store.keys()].filter((p) => p.startsWith(`${col}/`))
        .map((p) => store.get(p)),
    runTransaction: async (fn) => {
      const writes = [];
      const tx = {
        get: async (ref) => snap(ref.path),
        set: (ref, d, o) => writes.push(() => write(ref.path, d,
            !!(o && o.merge))),
        update: (ref, d) => writes.push(() => {
          if (!store.has(ref.path)) throw new Error("NOT_FOUND");
          write(ref.path, d, true);
        }),
        create: (ref, d) => writes.push(() => {
          if (store.has(ref.path)) throw new Error("ALREADY_EXISTS");
          write(ref.path, d, false);
        }),
      };
      const out = await fn(tx);
      writes.forEach((w) => w());
      return out;
    },
  };
}

// A scripted model: each entry {step, text} (or {step, error}) answers the
// next call, and the call's step must match.
function scriptModel(script, hooks) {
  const calls = [];
  const fn = async (req) => {
    calls.push(req);
    const next = script.shift();
    assert.ok(next, `unexpected model call #${calls.length} (${req.step})`);
    assert.strictEqual(req.step, next.step,
        `call #${calls.length}: step ${req.step}, script ${next.step}`);
    if (hooks && hooks.onCall) await hooks.onCall(req, calls.length);
    if (next.error) throw next.error;
    return {text: next.text, model: req.model,
      usage: {prompt: 100 + calls.length, completion: 50,
        reasoning: req.thinking ? 30 : 0},
      latencyMs: 1000 * calls.length, finishReason: "stop"};
  };
  fn.calls = calls;
  fn.left = () => script.length;
  return fn;
}

const DRAFT_1 = "我細個住喺潮州鄉下。屋企後面有條河。\n\n" +
  "我同阿哥成日去河邊捉魚。我七歲就識游水。";
const OK = JSON.stringify({ok: true, issues: []});
const issues = (list) => JSON.stringify({ok: false, issues: list});

const INPUT = {
  themeZh: "童年同屋企",
  items: [
    {questionIndex: 0, question: "講下你細個住嘅地方，係點樣嘅？",
      answer: "細個住喺潮州鄉下，屋企後面有條河", skipped: false,
      followups: [{q: "去河邊玩嗰陣，通常同邊個一齊去？", a: "同阿哥去捉魚"}],
      reply: "同阿哥一齊捉魚，聽落好開心。"},
    {questionIndex: 1, question: "喺嗰度，有冇一日發生嘅事，你到而家都記得好清楚？",
      answer: null, skipped: true, followups: [], reply: null},
  ],
  extras: [{text: "阿哥而家喺加拿大，電話 91234567", reply: null}],
};

function chapterDoc(extra) {
  return Object.assign({weekIndex: 1, source: "hybrid", status: "requested",
    requestId: "req-1", requestedAt: new Date(NOW), input: INPUT}, extra);
}

async function seed(db, opts) {
  const o = opts || {};
  studyPeriod.resetGateCache();
  resetSafetyConfigCache();
  await db.doc("app_config/feature_flags").set({
    reminiscenceV2Enabled: o.flag === undefined ? true : o.flag,
    enrollmentGateEnabled: o.gate === true});
  if (o.user !== null) {
    await db.doc("users/u1").set(o.user || {arm: "A", cohort: "phase_b",
      armAssignmentMode: "randomise"});
  }
  await db.doc("users/u1/fcm_tokens/d1").set({token: "tok-1"});
  await db.doc("users/u1/fcm_tokens/d2").set({token: "tok-2"});
  await db.doc("users/u1/reminiscence_chapters/week_1").set(
      chapterDoc(o.doc));
}

function fakeMessaging() {
  const sent = [];
  return {sent, send: async (msg) => {
    sent.push(msg);
    return `id-${sent.length}`;
  }};
}

function deps(db, model, extra) {
  return Object.assign({db, model, messaging: fakeMessaging(),
    stripPII: (t) => t.replace(/\b[2-9]\d{7}\b/g, "[PHONE]"),
    now: () => NOW, fieldValue: db.fieldValue,
    cfg: rc.configFrom(null)}, extra);
}

const EV = {uid: "u1", docId: "week_1"};
const ev = (db) => Object.assign({}, EV,
    {after: db.data("users/u1/reminiscence_chapters/week_1")});
const CH = "users/u1/reminiscence_chapters/week_1";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

test("config: defaults, overrides, clamps", () => {
  const d = rc.configFrom(null);
  assert.strictEqual(d.draftModel, "deepseek-v4-pro");
  assert.strictEqual(d.draftThinking, true);
  assert.strictEqual(d.checkModel, "deepseek-flash");
  assert.strictEqual(d.maxRewriteRounds, 2);
  assert.strictEqual(d.pushBody, "你嘅第 {N} 章整理好喇，得閒入嚟睇下。");
  const o = rc.configFrom({draftModel: "deepseek-v5-pro",
    checkModel: "Bad Name!", maxRewriteRounds: 5, draftThinking: false,
    draftReasoningEffort: "max", totalBudgetMs: 10});
  assert.strictEqual(o.draftModel, "deepseek-v5-pro");
  assert.strictEqual(o.checkModel, "deepseek-flash", "invalid name ignored");
  assert.strictEqual(o.maxRewriteRounds, 2, "never more than 2 rounds");
  assert.strictEqual(o.draftThinking, false);
  assert.strictEqual(o.draftReasoningEffort, "max");
  assert.strictEqual(o.totalBudgetMs, rc.DEFAULTS.totalBudgetMs);
});

test("request bodies: Pro draft thinking on; Flash check thinking off",
    () => {
      const cfg = rc.configFrom(null);
      const draft = rc.buildRequestBody({step: "draft", model: cfg.draftModel,
        thinking: cfg.draftThinking, system: "S", user: "U",
        maxTokens: cfg.draftMaxTokens, temperature: 0.5, json: false});
      assert.strictEqual(draft.model, "deepseek-v4-pro");
      assert.deepStrictEqual(draft.thinking, {type: "enabled"});
      assert.ok(!("temperature" in draft), "thinking ignores temperature");
      assert.ok(!("response_format" in draft));
      assert.ok(!("reasoning_effort" in draft), "API default effort");
      const check = rc.buildRequestBody({step: "check",
        model: cfg.checkModel, thinking: true, system: "S", user: "U",
        maxTokens: cfg.checkMaxTokens, temperature: 0.1, json: true});
      assert.strictEqual(check.model, "deepseek-flash");
      assert.deepStrictEqual(check.thinking, {type: "disabled"},
          "the check is always thinking off");
      assert.strictEqual(check.temperature, 0.1);
      assert.deepStrictEqual(check.response_format, {type: "json_object"});
      const effort = rc.buildRequestBody({step: "rewrite", model: "m",
        thinking: true, reasoningEffort: "high", system: "S", user: "U",
        maxTokens: 10});
      assert.strictEqual(effort.reasoning_effort, "high");
    });

test("parseCheck: valid, fenced, malformed, inconsistent", () => {
  assert.deepStrictEqual(rc.parseCheck(OK), {ok: true, issues: []});
  const p = rc.parseCheck("```json\n" + issues([{type: "无出处",
    quote: "我七歲就識游水。", suggestion: "刪走"}]) + "\n```");
  assert.strictEqual(p.ok, false);
  assert.strictEqual(p.issues[0].type, "无出处");
  assert.strictEqual(rc.parseCheck("not json"), null);
  assert.strictEqual(rc.parseCheck("[]"), null);
  assert.strictEqual(rc.parseCheck("{\"ok\": \"yes\", \"issues\": []}"), null);
  assert.strictEqual(rc.parseCheck("{\"ok\": false, \"issues\": []}"), null,
      "not ok with nothing to act on is unusable");
  const odd = rc.parseCheck(JSON.stringify({ok: true, issues: [{type: "怪",
    quote: "x"}]}));
  assert.strictEqual(odd.ok, false, "issues are authoritative");
  assert.strictEqual(odd.issues[0].type, "其他");
  assert.strictEqual(odd.issues[0].suggestion, "");
});

test("screenIssues: 太口语 needs colloquial grammar outside 「」", () => {
  const cfg = rc.configFrom(null);
  const parsed = {ok: false, issues: [
    {type: "太口语", quote: "屋企後面有一條河。", suggestion: "家"},
    {type: "太口语", quote: "我同阿嫲最親，佢成日湊我。", suggestion: ""},
    {type: "太口语", quote: "阿媽常說「做人唔好嘥嘢」。", suggestion: ""},
    {type: "太书面", quote: "屋企後面有一條河。", suggestion: ""},
    {type: "无出处", quote: "我七歲。", suggestion: ""},
  ]};
  const out = rc.screenIssues(parsed, cfg);
  assert.deepStrictEqual(out.result.issues.map((i) => i.quote), [
    "我同阿嫲最親，佢成日湊我。", "屋企後面有一條河。", "我七歲。"]);
  assert.strictEqual(out.result.ok, false);
  assert.deepStrictEqual(out.dropped.map((i) => i.quote),
      ["屋企後面有一條河。", "阿媽常說「做人唔好嘥嘢」。"]);
  const onlyWords = rc.screenIssues({ok: false, issues: [
    {type: "太口语", quote: "下晝得閒就同阿哥去河邊捉蝦。", suggestion: ""}]},
  cfg);
  assert.strictEqual(onlyWords.result.ok, true, "all dropped → ok");
  const off = rc.screenIssues(parsed, rc.configFrom({colloquialFilter: false}));
  assert.strictEqual(off.result.issues.length, 5);
});

test("pipeline: a check with only word-level 太口语 passes, dropped issues " +
    "archived", async () => {
  const model = scriptModel([{step: "draft", text: DRAFT_1},
    {step: "check", text: issues([{type: "太口语",
      quote: "屋企後面有條河。", suggestion: "家後面有條河。"}])}]);
  const out = await rc.runPipeline({model, now: clock,
    cfg: rc.configFrom(null)}, CONV);
  assert.strictEqual(out.stoppedBy, "passed");
  assert.strictEqual(model.calls.length, 2);
  assert.strictEqual(out.rounds[0].check.attempts[0].droppedIssues[0].quote,
      "屋企後面有條河。");
});

test("splitSentences keeps quotes whole", () => {
  assert.deepStrictEqual(rc.splitSentences(
      "阿媽成日講「食得係福。你要記住。」我記得。好開心！"),
  ["阿媽成日講「食得係福。你要記住。」", "我記得。", "好開心！"]);
  assert.deepStrictEqual(rc.splitSentences("冇句號嘅尾"), ["冇句號嘅尾"]);
  assert.deepStrictEqual(rc.paragraphs("一。二。\n\n三。\n"),
      [["一。", "二。"], ["三。"]]);
});

test("matchQuote: contains, punctuation, spans, similar, none", () => {
  const ss = ["我細個住喺潮州鄉下。", "屋企後面有條河。", "我七歲就識游水。"]
      .map((t, i) => ({key: String(i), norm: rc.norm(t)}));
  assert.deepStrictEqual(rc.matchQuote(ss, "我七歲就識游水。").keys, ["2"]);
  assert.deepStrictEqual(rc.matchQuote(ss, " 我七歲就識游水 ").keys, ["2"],
      "spaces / punctuation ignored");
  assert.deepStrictEqual(rc.matchQuote(ss, "七歲").keys, ["2"], "clause");
  assert.deepStrictEqual(rc.matchQuote(ss,
      "屋企後面有條河。我七歲就識游水。").keys, ["1", "2"], "spans two");
  const sim = rc.matchQuote(ss, "我七岁就识游水。");
  assert.deepStrictEqual(sim.keys, ["2"], "simplified characters");
  assert.strictEqual(sim.how, "similar");
  assert.deepStrictEqual(rc.matchQuote(ss, "完全唔同嘅一句話").keys, []);
  assert.deepStrictEqual(rc.matchQuote(ss, "。。").keys, []);
});

test("deleteFlagged: deletes 无出处 / 细节错, flags the rest", () => {
  const check = {ok: false, issues: [
    {type: "无出处", quote: "我七歲就識游水。", suggestion: "刪走"},
    {type: "语气不当", quote: "我七歲就識游水。", suggestion: "x"},
    {type: "太书面", quote: "屋企後面有條河。", suggestion: "x"},
    {type: "细节错", quote: "冇呢句", suggestion: "x"},
  ]};
  const out = rc.deleteFlagged(DRAFT_1, check);
  assert.strictEqual(out.text,
      "我細個住喺潮州鄉下。屋企後面有條河。\n\n我同阿哥成日去河邊捉魚。");
  assert.deepStrictEqual(out.deleted.map((d) => d.sentence),
      ["我七歲就識游水。"]);
  assert.deepStrictEqual(out.unmatched, [{type: "细节错", quote: "冇呢句"}]);
  // 语气不当 on the deleted sentence is resolved; 太书面 stays.
  assert.deepStrictEqual(out.flags, ["细节错", "太书面"]);
  const whole = rc.deleteFlagged("一句。\n\n二句。", {ok: false, issues: [
    {type: "无出处", quote: "二句。", suggestion: ""}]});
  assert.strictEqual(whole.text, "一句。", "empty paragraph dropped");
  assert.deepStrictEqual(rc.deleteFlagged(DRAFT_1, null).flags, ["核对失败"]);
});

test("input: sorted, numbered from 1, skipped, follow-ups, extras, scrubbed, " +
    "no companion replies", () => {
  const n = rc.normaliseInput(INPUT, (t) => t.replace(/9\d{7}/g, "[PHONE]"));
  assert.strictEqual(n.answered, 3);
  const text = rc.conversationText(n);
  assert.ok(text.startsWith("【本週主題】童年同屋企"));
  assert.ok(text.includes("第 1 題：講下你細個住嘅地方，係點樣嘅？\n" +
      "老人答：細個住喺潮州鄉下，屋企後面有條河\n" +
      "追問：去河邊玩嗰陣，通常同邊個一齊去？\n老人再答：同阿哥去捉魚"));
  assert.ok(text.includes("第 2 題：喺嗰度"));
  assert.ok(text.includes("（冇答：老人揀咗「唔想講」）"));
  assert.ok(text.includes("【再講多啲】\n老人講：阿哥而家喺加拿大，電話 [PHONE]"));
  assert.ok(!text.includes("聽落好開心"), "companion reply left out");
  // 1-based indices are kept as they are.
  const one = rc.normaliseInput({items: [{questionIndex: 7, question: "q7",
    answer: "a"}, {questionIndex: 8, question: "q8", answer: "b"}]});
  assert.deepStrictEqual(one.items.map((i) => i.number), [7, 8]);
  assert.strictEqual(rc.normaliseInput({items: "x"}), null);
  assert.strictEqual(rc.normaliseInput({items: [{questionIndex: 1,
    skipped: true, answer: "ignored"}]}).answered, 0);
});

// ---------------------------------------------------------------------------
// Pipeline
// ---------------------------------------------------------------------------

const CONV = {conversation: rc.conversationText(rc.normaliseInput(INPUT))};
const clock = () => NOW;

test("pipeline: clean first draft → 1 draft + 1 check", async () => {
  const model = scriptModel([{step: "draft", text: DRAFT_1},
    {step: "check", text: OK}]);
  const out = await rc.runPipeline({model, now: clock,
    cfg: rc.configFrom(null)}, CONV);
  assert.strictEqual(out.text, DRAFT_1.replace(/\n\n/g, "\n\n"));
  assert.strictEqual(out.stoppedBy, "passed");
  assert.deepStrictEqual(out.flags, []);
  assert.strictEqual(out.rounds.length, 1);
  assert.strictEqual(model.calls.length, 2);
  const [d, c] = model.calls;
  assert.strictEqual(d.model, "deepseek-v4-pro");
  assert.strictEqual(d.thinking, true);
  assert.ok(d.system.startsWith("## 小篇章初稿"));
  assert.ok(d.user.includes("老人答：細個住喺潮州鄉下"));
  assert.strictEqual(c.model, "deepseek-flash");
  assert.strictEqual(c.thinking, false);
  assert.strictEqual(c.json, true);
  assert.ok(c.system.startsWith("## 小篇章核對"));
  assert.ok(c.user.includes("【初稿】\n" + DRAFT_1));
});

test("pipeline: one rewrite, then ok", async () => {
  const issue = {type: "语气不当", quote: "我七歲就識游水。",
    suggestion: "刪去年紀"};
  const fixed = "我細個住喺潮州鄉下。屋企後面有條河。\n\n我同阿哥成日去河邊捉魚。";
  const model = scriptModel([{step: "draft", text: DRAFT_1},
    {step: "check", text: issues([issue])},
    {step: "rewrite", text: fixed}, {step: "check", text: OK}]);
  const out = await rc.runPipeline({model, now: clock,
    cfg: rc.configFrom(null)}, CONV);
  assert.strictEqual(out.text, fixed);
  assert.strictEqual(out.stoppedBy, "passed");
  assert.strictEqual(out.rounds.length, 2);
  const rw = model.calls[2];
  assert.strictEqual(rw.model, "deepseek-v4-pro");
  assert.ok(rw.user.includes("【上一稿】\n" + DRAFT_1));
  assert.ok(rw.user.includes("【核對意見】"));
  assert.ok(rw.user.includes("\"quote\":\"我七歲就識游水。\""));
  assert.ok(rw.user.includes("老人答：細個住喺潮州鄉下"),
      "rewrite sees the conversation too");
  assert.ok(rw.user.includes("\"suggestion\":\"刪去年紀\""));
  assert.deepStrictEqual(out.deleted, []);
});

test("rewrite message: style issues go back without Flash's suggestion",
    () => {
      const msg = rc.rewriteMessage("CONV", "上一稿。", {ok: false, issues: [
        {type: "太口语", quote: "屋企有條河。", suggestion: "家裏有條河。"},
        {type: "太书面", quote: "歲月如歌。", suggestion: "x"},
        {type: "细节错", quote: "阿哥。", suggestion: "係阿姐"}]});
      assert.ok(!msg.includes("家裏有條河"));
      assert.ok(msg.includes("{\"type\":\"太口语\",\"quote\":\"屋企有條河。\"}"));
      assert.ok(msg.includes("\"suggestion\":\"係阿姐\""));
      assert.ok(rc.rewriteMessage("CONV", "上一稿。", null)
          .includes("核對冇結果"));
    });

test("pipeline: still flagged after 2 rounds → the sentence is deleted",
    async () => {
      const bad = {type: "无出处", quote: "我七歲就識游水。", suggestion: "刪走"};
      const style = {type: "太书面", quote: "屋企後面有條河。", suggestion: "x"};
      const model = scriptModel([
        {step: "draft", text: DRAFT_1}, {step: "check", text: issues([bad])},
        {step: "rewrite", text: DRAFT_1}, {step: "check", text: issues([bad])},
        {step: "rewrite", text: DRAFT_1},
        {step: "check", text: issues([bad, style])}]);
      const out = await rc.runPipeline({model, now: clock,
        cfg: rc.configFrom(null)}, CONV);
      assert.strictEqual(model.calls.length, 6, "draft + 2 rewrites, 3 checks");
      assert.strictEqual(model.left(), 0);
      assert.strictEqual(out.stoppedBy, "max_rounds");
      assert.ok(!out.text.includes("七歲"));
      assert.strictEqual(out.text,
          "我細個住喺潮州鄉下。屋企後面有條河。\n\n我同阿哥成日去河邊捉魚。");
      assert.deepStrictEqual(out.deleted.map((x) => x.sentence),
          ["我七歲就識游水。"]);
      assert.deepStrictEqual(out.flags, ["太书面"]);
      assert.strictEqual(out.rounds.length, 3);
      assert.deepStrictEqual(out.rounds.map((r) => r.kind),
          ["draft", "rewrite", "rewrite"]);
    });

test("pipeline: malformed JSON → retry once → treated as not ok → rewrite",
    async () => {
      const model = scriptModel([{step: "draft", text: DRAFT_1},
        {step: "check", text: "好似冇問題"}, {step: "check", text: "{bad"},
        {step: "rewrite", text: DRAFT_1}, {step: "check", text: OK}]);
      const out = await rc.runPipeline({model, now: clock,
        cfg: rc.configFrom(null)}, CONV);
      assert.strictEqual(model.calls.length, 5);
      const r0 = out.rounds[0].check;
      assert.strictEqual(r0.usable, false);
      assert.strictEqual(r0.ok, false);
      assert.strictEqual(r0.attempts.length, 2, "one retry");
      assert.strictEqual(r0.attempts[0].raw, "好似冇問題", "raw kept");
      assert.ok(model.calls[3].user.includes("核對冇結果"));
      assert.strictEqual(out.stoppedBy, "passed");
      assert.deepStrictEqual(out.flags, []);
    });

test("pipeline: malformed on the last round → delivered, flag 核对失败",
    async () => {
      const model = scriptModel([{step: "draft", text: DRAFT_1},
        {step: "check", text: "x"}, {step: "check", text: "x"},
        {step: "rewrite", text: DRAFT_1}, {step: "check", text: "x"},
        {step: "check", text: "x"}, {step: "rewrite", text: DRAFT_1},
        {step: "check", text: "x"}, {step: "check", text: "x"}]);
      const out = await rc.runPipeline({model, now: clock,
        cfg: rc.configFrom(null)}, CONV);
      assert.strictEqual(out.text, DRAFT_1);
      assert.deepStrictEqual(out.flags, ["核对失败"]);
      assert.strictEqual(out.stoppedBy, "max_rounds");
    });

test("pipeline: a check that errors counts like malformed", async () => {
  const model = scriptModel([{step: "draft", text: DRAFT_1},
    {step: "check", error: new Error("deepseek 503")},
    {step: "check", text: OK}]);
  const out = await rc.runPipeline({model, now: clock,
    cfg: rc.configFrom(null)}, CONV);
  assert.strictEqual(out.stoppedBy, "passed");
  assert.strictEqual(out.rounds[0].check.attempts[0].error, "deepseek 503");
});

test("pipeline: no new round without time for it", async () => {
  let t = NOW;
  const model = scriptModel([{step: "draft", text: DRAFT_1},
    {step: "check", text: issues([{type: "太书面", quote: "屋企後面有條河。",
      suggestion: "x"}])}], {onCall: () => {
    t += 220000;
  }});
  const out = await rc.runPipeline({model, now: () => t,
    cfg: rc.configFrom(null)}, CONV);
  assert.strictEqual(out.stoppedBy, "budget");
  assert.strictEqual(model.calls.length, 2);
  assert.deepStrictEqual(out.flags, ["太书面"]);
  // Each call's timeout is cut to what is left of the budget.
  assert.ok(model.calls[1].timeoutMs <= 480000 - 220000);
});

test("pipeline: a failed rewrite delivers the last checked draft",
    async () => {
      const bad = {type: "无出处", quote: "我七歲就識游水。", suggestion: "刪走"};
      const model = scriptModel([{step: "draft", text: DRAFT_1},
        {step: "check", text: issues([bad])},
        {step: "rewrite", error: new Error("deepseek 500")}]);
      const out = await rc.runPipeline({model, now: clock,
        cfg: rc.configFrom(null)}, CONV);
      assert.strictEqual(out.stoppedBy, "error");
      assert.strictEqual(out.roundError, "deepseek 500");
      assert.ok(!out.text.includes("七歲"), "delete step still applied");
    });

test("pipeline: the first draft failing throws", async () => {
  const model = scriptModel([{step: "draft",
    error: new Error("deepseek 500")}]);
  await assert.rejects(rc.runPipeline({model, now: clock,
    cfg: rc.configFrom(null)}, CONV), /deepseek 500/);
  const empty = scriptModel([{step: "draft", text: "  "},
    {step: "draft", text: ""}, {step: "draft", text: ""}]);
  await assert.rejects(rc.runPipeline({model: empty, now: clock,
    cfg: rc.configFrom(null)}, CONV), (e) => e.code === "empty_draft");
  assert.strictEqual(empty.calls.length, 3, "two retries, then give up");
});

test("pipeline: an empty draft (answer left in the reasoning) is retried",
    async () => {
      const model = scriptModel([{step: "draft", text: ""},
        {step: "draft", text: DRAFT_1}, {step: "check", text: OK}]);
      const out = await rc.runPipeline({model, now: clock,
        cfg: rc.configFrom(null)}, CONV);
      assert.strictEqual(out.text, DRAFT_1);
      assert.strictEqual(out.rounds[0].draft.emptyAttempts, 1);
      const none = scriptModel([{step: "draft", text: ""}]);
      await assert.rejects(rc.runPipeline({model: none, now: clock,
        cfg: rc.configFrom({draftRetries: 0})}, CONV),
      (e) => e.code === "empty_draft");
    });

test("pipeline: archive of every round", async () => {
  const issue = {type: "语气不当", quote: "我七歲就識游水。", suggestion: "x"};
  const model = scriptModel([{step: "draft", text: DRAFT_1},
    {step: "check", text: issues([issue])}, {step: "rewrite", text: "改好。"},
    {step: "check", text: OK}]);
  const out = await rc.runPipeline({model, now: clock,
    cfg: rc.configFrom(null)}, CONV);
  assert.deepStrictEqual(out.promptVersions, {
    draft: "reminiscence_chapter_draft_v1@2026-10",
    check: "reminiscence_chapter_check_v1@2026-10"});
  const [r0, r1] = out.rounds;
  assert.strictEqual(r0.round, 0);
  assert.strictEqual(r0.draft.text, DRAFT_1);
  assert.strictEqual(r0.draft.model, "deepseek-v4-pro");
  assert.strictEqual(r0.draft.latencyMs, 1000);
  assert.deepStrictEqual(r0.draft.usage,
      {prompt: 101, completion: 50, reasoning: 30});
  assert.deepStrictEqual(r0.check.issues, [issue]);
  assert.strictEqual(r0.check.attempts[0].model, "deepseek-flash");
  assert.strictEqual(r0.check.attempts[0].latencyMs, 2000);
  assert.strictEqual(r1.kind, "rewrite");
  assert.strictEqual(r1.draft.text, "改好。");
  assert.strictEqual(r1.check.ok, true);
  // Nothing undefined (Firestore refuses it).
  assert.ok(!JSON.stringify(out.rounds).includes("undefined"));
  const walk = (v) => {
    if (v === undefined) throw new Error("undefined in archive");
    if (v && typeof v === "object") Object.values(v).forEach(walk);
  };
  walk(out.rounds);
});

// ---------------------------------------------------------------------------
// Trigger work (in-memory Firestore)
// ---------------------------------------------------------------------------

const happyScript = () => [{step: "draft", text: DRAFT_1},
  {step: "check", text: issues([{type: "无出处", quote: "我七歲就識游水。",
    suggestion: "刪走"}])},
  {step: "rewrite", text: "我細個住喺潮州鄉下。屋企後面有條河。\n\n" +
    "我同阿哥成日去河邊捉魚。"},
  {step: "check", text: OK}];

test("rule-arm chapter: ignored before any read, no model call", async () => {
  const model = scriptModel([]);
  const out = await rc.handleChapterWrite({db: null, model},
      {uid: "u1", docId: "week_1", after: {weekIndex: 1, source: "rule",
        status: "ready", ruleText: "…", version: 1}});
  assert.strictEqual(out.action, "ignored");
  assert.strictEqual(model.calls.length, 0);
  for (const after of [null, chapterDoc({status: "ready"}),
    chapterDoc({status: "generating"}), chapterDoc({source: "rule",
      status: "requested"})]) {
    assert.strictEqual((await rc.handleChapterWrite({db: null, model},
        {uid: "u1", docId: "week_1", after})).action, "ignored");
  }
});

test("switch off → failed 'disabled', no model call", async () => {
  const db = fakeDb();
  await seed(db, {flag: false});
  const model = scriptModel([]);
  const out = await rc.handleChapterWrite(deps(db, model), ev(db));
  assert.strictEqual(out.action, "disabled");
  assert.strictEqual(model.calls.length, 0);
  const d = db.data(CH);
  assert.strictEqual(d.status, "failed");
  assert.strictEqual(d.failReason, "disabled");
  assert.strictEqual(db.rows("llm_denied_log").length, 0);
});

test("rule-arm account with a hybrid request → failed 'not_hybrid', " +
    "llm_denied_log like the proxy, no model call", async () => {
  const db = fakeDb();
  await seed(db, {user: {arm: "B", cohort: "phase_b"}});
  const model = scriptModel([]);
  const out = await rc.handleChapterWrite(deps(db, model), ev(db));
  assert.strictEqual(out.action, "not_hybrid");
  assert.strictEqual(model.calls.length, 0);
  assert.strictEqual(db.data(CH).status, "failed");
  assert.strictEqual(db.data(CH).failReason, "not_hybrid");
  const rows = db.rows("llm_denied_log");
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].uid, "u1");
  assert.strictEqual(rows[0].endpoint, "reminiscenceChapter");
  assert.ok(!("reason" in rows[0]), "rule-arm rows carry no reason (T19)");
  assert.ok(!("arm" in rows[0]));
  // The same event again: nothing more.
  await rc.handleChapterWrite(deps(db, model), Object.assign({}, EV,
      {after: chapterDoc()}));
  assert.strictEqual(db.rows("llm_denied_log").length, 1);
  assert.strictEqual(model.calls.length, 0);
});

test("no arm / no user doc → 'not_hybrid' (reason no_arm)", async () => {
  for (const user of [{cohort: "pilot"}, null]) {
    const db = fakeDb();
    await seed(db, {user});
    const model = scriptModel([]);
    const out = await rc.handleChapterWrite(deps(db, model), ev(db));
    assert.strictEqual(out.action, "not_hybrid");
    assert.strictEqual(db.rows("llm_denied_log")[0].reason, "no_arm");
    assert.strictEqual(model.calls.length, 0);
  }
});

test("enrolment gate: unenrolled arm A refused; tester arm A allowed",
    async () => {
      let db = fakeDb();
      await seed(db, {gate: true, user: {arm: "A"}});
      let model = scriptModel([]);
      let out = await rc.handleChapterWrite(deps(db, model), ev(db));
      assert.strictEqual(out.action, "not_enrolled");
      assert.strictEqual(db.data(CH).failReason, "not_enrolled");
      assert.strictEqual(db.rows("llm_denied_log")[0].reason, "not_enrolled");
      assert.strictEqual(model.calls.length, 0);

      db = fakeDb();
      await seed(db, {gate: true, user: {arm: "A", isTester: true}});
      model = scriptModel(happyScript());
      out = await rc.handleChapterWrite(deps(db, model), ev(db));
      assert.strictEqual(out.action, "ready");
      // A tester switched to the rule arm is refused like a participant.
      db = fakeDb();
      await seed(db, {gate: true, user: {arm: "B", isTester: true}});
      model = scriptModel([]);
      out = await rc.handleChapterWrite(deps(db, model), ev(db));
      assert.strictEqual(out.action, "not_hybrid");
    });

test("Hybrid: ready, version 1, deleted sentence, archive, push",
    async () => {
      const db = fakeDb();
      await seed(db);
      const model = scriptModel(happyScript());
      const d = deps(db, model);
      const out = await rc.handleChapterWrite(d, ev(db));
      assert.strictEqual(out.action, "ready");
      assert.strictEqual(out.version, 1);
      const ch = db.data(CH);
      assert.strictEqual(ch.status, "ready");
      assert.strictEqual(ch.version, 1);
      assert.strictEqual(ch.finalText,
          "我細個住喺潮州鄉下。屋企後面有條河。\n\n我同阿哥成日去河邊捉魚。");
      assert.deepStrictEqual(ch.flags, []);
      assert.deepStrictEqual(ch.deletedSentences, []);
      assert.ok(ch.generatedAt instanceof Date);
      assert.ok(!("failReason" in ch));
      // Client fields untouched.
      assert.strictEqual(ch.requestId, "req-1");
      assert.deepStrictEqual(ch.input, INPUT);
      // PII scrubbed before the model saw it.
      assert.ok(model.calls[0].user.includes("電話 [PHONE]"));
      assert.ok(!model.calls[0].user.includes("91234567"));
      // Archive.
      const run = db.data(`${CH}/runs/req-1`);
      assert.strictEqual(run.state, "ready");
      assert.strictEqual(run.version, 1);
      assert.strictEqual(run.rounds.length, 2);
      assert.strictEqual(run.rounds[0].draft.text, DRAFT_1);
      assert.strictEqual(run.rounds[0].check.issues[0].type, "无出处");
      assert.strictEqual(run.config.draftModel, "deepseek-v4-pro");
      assert.strictEqual(run.config.checkModel, "deepseek-flash");
      assert.strictEqual(run.promptVersions.draft,
          "reminiscence_chapter_draft_v1@2026-10");
      assert.strictEqual(run.stoppedBy, "passed");
      assert.ok(run.startedAt instanceof Date);
      assert.ok(run.finishedAt instanceof Date);
      // Push to both devices, draft copy.
      assert.strictEqual(d.messaging.sent.length, 2);
      assert.strictEqual(d.messaging.sent[0].notification.body,
          "你嘅第 1 章整理好喇，得閒入嚟睇下。");
      assert.strictEqual(d.messaging.sent[0].data.kind,
          "reminiscence_chapter_ready");
      assert.strictEqual(run.push.status, "sent");
      assert.strictEqual(run.push.delivered, 2);
    });

test("idempotent per requestId; a new requestId bumps the version",
    async () => {
      const db = fakeDb();
      await seed(db);
      const model = scriptModel(happyScript());
      const event = ev(db); // the 'requested' snapshot
      assert.strictEqual((await rc.handleChapterWrite(deps(db, model),
          event)).action, "ready");
      // The same event delivered again (at-least-once): no second run.
      assert.strictEqual((await rc.handleChapterWrite(deps(db, model),
          event)).action, "duplicate");
      assert.strictEqual(model.calls.length, 4);
      assert.strictEqual(db.data(CH).version, 1);
      // Even with the doc put back to 'requested' with the same id.
      await db.doc(CH).update({status: "requested"});
      assert.strictEqual((await rc.handleChapterWrite(deps(db, model),
          ev(db))).action, "duplicate");
      assert.strictEqual(model.calls.length, 4);
      // Re-request: new requestId → generate again, version 2.
      await db.doc(CH).update({status: "requested", requestId: "req-2"});
      const model2 = scriptModel(happyScript());
      const out = await rc.handleChapterWrite(deps(db, model2), ev(db));
      assert.strictEqual(out.action, "ready");
      assert.strictEqual(db.data(CH).version, 2);
      assert.ok(db.data(`${CH}/runs/req-2`));
    });

test("a newer request supersedes a running one", async () => {
  const db = fakeDb();
  await seed(db);
  const model = scriptModel(happyScript(), {onCall: async (req, n) => {
    if (n === 1) {
      await db.doc(CH).update({status: "requested", requestId: "req-9"});
    }
  }});
  const out = await rc.handleChapterWrite(deps(db, model), Object.assign({},
      EV, {after: chapterDoc()}));
  assert.strictEqual(out.action, "superseded");
  const ch = db.data(CH);
  assert.strictEqual(ch.requestId, "req-9");
  assert.strictEqual(ch.status, "requested", "left for the newer request");
  assert.ok(!("finalText" in ch));
  assert.strictEqual(db.data(`${CH}/runs/req-1`).state, "superseded");
});

test("quiet hours: ready, no push", async () => {
  const db = fakeDb();
  await seed(db);
  const d = deps(db, scriptModel(happyScript()), {now: () => QUIET_NOW});
  const out = await rc.handleChapterWrite(d, ev(db));
  assert.strictEqual(out.action, "ready");
  assert.strictEqual(out.push, "quiet_hours");
  assert.strictEqual(d.messaging.sent.length, 0);
  // Quiet hours switched off by the elder → pushed.
  const db2 = fakeDb();
  await seed(db2, {user: {arm: "A", cohort: "phase_b",
    quietHoursEnabled: false}});
  const d2 = deps(db2, scriptModel(happyScript()), {now: () => QUIET_NOW});
  assert.strictEqual((await rc.handleChapterWrite(d2, ev(db2))).push, "sent");
});

test("push switched off / placeholder copy: no push", async () => {
  const db = fakeDb();
  await seed(db);
  const d = deps(db, scriptModel(happyScript()),
      {cfg: rc.configFrom({pushEnabled: false})});
  assert.strictEqual((await rc.handleChapterWrite(d, ev(db))).push,
      "disabled");
  const db2 = fakeDb();
  await seed(db2);
  const d2 = deps(db2, scriptModel(happyScript()),
      {cfg: rc.configFrom({pushBody: "【占位】第 {N} 章"})});
  assert.strictEqual((await rc.handleChapterWrite(d2, ev(db2))).push,
      "blocked_placeholder");
  assert.strictEqual(d2.messaging.sent.length, 0);
});

test("empty input → failed 'empty_input', no model call", async () => {
  const db = fakeDb();
  await seed(db, {doc: {input: {themeZh: "童年同屋企", items: [
    {questionIndex: 1, question: "q", answer: null, skipped: true,
      followups: []}], extras: []}}});
  const model = scriptModel([]);
  const out = await rc.handleChapterWrite(deps(db, model), ev(db));
  assert.strictEqual(out.action, "empty_input");
  assert.strictEqual(db.data(CH).status, "failed");
  assert.strictEqual(db.data(CH).failReason, "empty_input");
  assert.strictEqual(model.calls.length, 0);
  assert.strictEqual(db.data(`${CH}/runs/req-1`).state, "failed");
});

test("model error on the first draft → failed 'llm_error'", async () => {
  const db = fakeDb();
  await seed(db);
  const model = scriptModel([{step: "draft",
    error: new Error("deepseek 500")}]);
  const out = await rc.handleChapterWrite(deps(db, model), ev(db));
  assert.strictEqual(out.action, "llm_error");
  assert.strictEqual(db.data(CH).status, "failed");
  assert.strictEqual(db.data(CH).failReason, "llm_error");
  assert.strictEqual(db.data(`${CH}/runs/req-1`).error, "deepseek 500");
});

test("bad doc id / missing requestId: no work", async () => {
  const db = fakeDb();
  await seed(db);
  const model = scriptModel([]);
  assert.strictEqual((await rc.handleChapterWrite(deps(db, model),
      {uid: "u1", docId: "week_x", after: chapterDoc()})).action,
  "bad_request");
  assert.strictEqual((await rc.handleChapterWrite(deps(db, model),
      Object.assign({}, EV, {after: chapterDoc({requestId: null})})))
      .action, "bad_request");
  assert.strictEqual(model.calls.length, 0);
});

test("hotline output filter: a number in the final text is replaced",
    async () => {
      const db = fakeDb();
      await seed(db);
      const model = scriptModel([
        {step: "draft", text: "阿哥喺加拿大。佢個電話係 9123 4567。"},
        {step: "check", text: OK}]);
      await rc.handleChapterWrite(deps(db, model), ev(db));
      const ch = db.data(CH);
      assert.ok(!/9123/.test(ch.finalText), ch.finalText);
      assert.strictEqual(db.rows("hotline_filter_log").length, 1);
      assert.strictEqual(db.rows("hotline_filter_log")[0].module_id,
          "m3_reminiscence_chapter");
    });

// ---------------------------------------------------------------------------

(async () => {
  for (const t of queue) {
    try {
      await t.fn();
      passed++;
      console.log(`PASS  ${t.name}`);
    } catch (err) {
      failures.push(t.name);
      console.log(`FAIL  ${t.name}\n      ${err && err.stack}`);
    }
  }
  console.log(`\n${passed} passed, ${failures.length} failed`);
  if (failures.length) process.exit(1);
})();
