/**
 * Memory v1 — pure-logic tests (validation, classification, sharing
 * policy, injection budget).  No Firestore, no network.
 *
 * Run:  cd functions && node test/memory_test.js
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const m = require("../memory");

let passed = 0;
const failures = [];
function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`PASS  ${name}`);
  } catch (err) {
    failures.push(name);
    console.log(`FAIL  ${name}\n      ${err.message}`);
  }
}

const TODAY = "2026-09-29"; // a Tuesday
const turns = [
  {fromUser: false, text: "你好呀，今日點？"},
  {fromUser: true, text: "我個女阿玲下個禮拜四帶我去睇醫生。"},
  {fromUser: true, text: "我鍾意飲早茶，通常去樓下嗰間。"},
  {fromUser: true, text: "大家都叫我陳太。"},
];
const ctx = {turns, todayKey: TODAY, activeFactIds: new Set(["f_old"])};

// ---------------------------------------------------------------- dates
test("hkDateKey uses Hong Kong time", () => {
  // 2026-09-29 17:30 UTC is already 2026-09-30 in Hong Kong.
  assert.strictEqual(m.hkDateKey(new Date("2026-09-29T17:30:00Z")),
      "2026-09-30");
});

test("addDays crosses month boundaries", () => {
  assert.strictEqual(m.addDays("2026-09-29", 3), "2026-10-02");
  assert.strictEqual(m.addDays("2026-03-01", -1), "2026-02-28");
});

// ------------------------------------------------------- classification
test("basic-fact categories are shared, others agent-private", () => {
  assert.strictEqual(m.visibilityFor("name", "normal"), "shared");
  assert.strictEqual(m.visibilityFor("family", "normal"), "shared");
  assert.strictEqual(m.visibilityFor("hobby", "normal"), "agent");
});

test("sensitive content is never shared", () => {
  assert.strictEqual(m.visibilityFor("family", "sensitive"), "agent");
});

test("health is always sensitive; keywords make others sensitive", () => {
  assert.strictEqual(m.classifySensitivity("health", "腳骨痛", false),
      "sensitive");
  assert.strictEqual(m.classifySensitivity("family", "同個仔嗌交", false),
      "sensitive");
  assert.strictEqual(m.classifySensitivity("hobby", "飲早茶", false),
      "normal");
  assert.strictEqual(m.classifySensitivity("hobby", "飲早茶", true),
      "sensitive");
});

test("safety terms classify as safety", () => {
  assert.strictEqual(m.classifySensitivity("event", "有時想死", false),
      "safety");
});

// ----------------------------------------------------------- validation
function extraction(over) {
  return Object.assign({
    summary: "陳太講起女兒阿玲會陪佢睇醫生，又講佢鍾意飲早茶。",
    facts: [
      {op: "add", category: "name", key: "稱呼", value: "陳太",
        quote: "大家都叫我陳太", sensitive: false},
      {op: "add", category: "hobby", key: "飲早茶", value: "鍾意去樓下飲早茶",
        quote: "我鍾意飲早茶", sensitive: false},
    ],
    followups: [
      {description: "阿玲陪佢睇醫生", due_date: "2026-10-08",
        quote: "下個禮拜四帶我去睇醫生"},
    ],
  }, over);
}

test("accepts a well-formed extraction", () => {
  const v = m.validateExtraction(extraction(), ctx);
  assert.ok(v.ok, v.error);
  assert.strictEqual(v.facts.length, 2);
  assert.strictEqual(v.facts[0].visibility, "shared");
  assert.strictEqual(v.facts[1].visibility, "agent");
  assert.strictEqual(v.followups.length, 1);
  assert.strictEqual(v.followups[0].sensitivity, "normal",
      "a doctor's appointment can be followed up");
});

test("a follow-up naming a diagnosis stays sensitive", () => {
  const t = [...turns, {fromUser: true, text: "下個月做手術切個瘤"}];
  const v = m.validateExtraction(extraction({followups: [
    {description: "做手術", due_date: "2026-10-20", quote: "下個月做手術"},
  ]}), {...ctx, turns: t});
  assert.strictEqual(v.followups[0].sensitivity, "sensitive");
});

test("rejects schema violations outright", () => {
  assert.ok(!m.validateExtraction(null, ctx).ok);
  assert.ok(!m.validateExtraction({facts: []}, ctx).ok, "missing summary");
  assert.ok(!m.validateExtraction(extraction({facts: "x"}), ctx).ok);
  assert.ok(!m.validateExtraction(extraction({facts: [{op: "add",
    category: "pets", key: "k", value: "v", quote: "陳太"}]}), ctx).ok,
  "unknown category");
  assert.ok(!m.validateExtraction(extraction({followups: [{
    description: "x", due_date: "下星期四", quote: "睇醫生"}]}), ctx).ok,
  "unconverted date");
});

test("drops a fact whose quote is not the user's own words", () => {
  const v = m.validateExtraction(extraction({facts: [
    {op: "add", category: "family", key: "兒子", value: "有個仔叫阿強",
      quote: "我個仔阿強"},
  ]}), ctx);
  assert.ok(v.ok);
  assert.strictEqual(v.facts.length, 0);
  assert.strictEqual(v.dropped[0].reason, "quote_not_found");
});

test("a quote from the companion's lines does not count", () => {
  const v = m.validateExtraction(extraction({facts: [
    {op: "add", category: "routine", key: "問候", value: "今日點",
      quote: "今日點"},
  ]}), ctx);
  assert.strictEqual(v.facts.length, 0);
});

test("quote matching ignores spacing and punctuation", () => {
  const v = m.validateExtraction(extraction({facts: [
    {op: "add", category: "name", key: "稱呼", value: "陳太",
      quote: "大家 都叫我，陳太"},
  ]}), ctx);
  assert.strictEqual(v.facts.length, 1);
});

test("follow-ups outside the date window are dropped", () => {
  const v = m.validateExtraction(extraction({followups: [
    {description: "睇醫生", due_date: "2025-01-01",
      quote: "帶我去睇醫生"},
  ]}), ctx);
  assert.ok(v.ok);
  assert.strictEqual(v.followups.length, 0);
});

test("update only replaces a fact id the extractor was shown", () => {
  const v = m.validateExtraction(extraction({facts: [
    {op: "update", fact_id: "f_old", category: "name", key: "稱呼",
      value: "陳太", quote: "叫我陳太", correction: true},
    {op: "update", fact_id: "someone_elses", category: "hobby",
      key: "飲早茶", value: "早茶", quote: "我鍾意飲早茶"},
  ]}), ctx);
  assert.strictEqual(v.facts[0].replaces, "f_old");
  assert.strictEqual(v.facts[0].correction, true);
  assert.strictEqual(v.facts[1].replaces, null);
});

test("safety content never survives validation", () => {
  const t = [...turns, {fromUser: true, text: "有時我真係想死"}];
  const v = m.validateExtraction(extraction({
    summary: "佢話有時想死",
    facts: [{op: "add", category: "event", key: "情緒", value: "有時想死",
      quote: "有時我真係想死"}],
  }), {...ctx, turns: t});
  assert.ok(v.ok);
  assert.strictEqual(v.facts.length, 0);
  assert.strictEqual(v.summary, "");
});

test("extraction prompt carries today's date and weekday", () => {
  const p = m.buildExtractionPrompt({turns, activeFacts: [], todayKey: TODAY});
  assert.ok(p.system.includes("2026-09-29（星期二"));
  assert.ok(p.user.includes("用戶：我鍾意飲早茶"));
});

// ---------------------------------------------------- sharing / injection
const fact = (id, agent, category, sensitivity = "normal", extra = {}) =>
  Object.assign({id, agent_id: agent, category, key: id, value: id,
    sensitivity, visibility: m.visibilityFor(category, sensitivity),
    status: "active"}, extra);

const mem = {
  facts: [
    fact("name_by_siu", "siu_yan", "name"),
    fact("hobby_by_siu", "siu_yan", "hobby"),
    fact("family_conflict_by_siu", "siu_yan", "family", "sensitive"),
    fact("hobby_by_tung", "tung_tung", "hobby"),
    fact("flagged", "tung_tung", "routine", "normal", {needs_review: true}),
  ],
  summaries: [
    {id: "s1", agent_id: "siu_yan", day_key: "2026-09-28", summary: "A",
      ended_ms: 1, sensitivity: "normal"},
    {id: "s2", agent_id: "siu_yan", day_key: "2026-09-28", summary: "B",
      ended_ms: 2, sensitivity: "normal"},
    {id: "s3", agent_id: "tung_tung", day_key: "2026-09-28", summary: "T",
      ended_ms: 3, sensitivity: "normal"},
  ],
  followups: [
    {id: "due", agent_id: "tung_tung", status: "pending",
      due_date: "2026-09-29", description: "睇醫生"},
    {id: "future", agent_id: "tung_tung", status: "pending",
      due_date: "2026-10-05", description: "飲喜酒"},
    {id: "stale", agent_id: "tung_tung", status: "pending",
      due_date: "2026-09-01", description: "舊事"},
    {id: "other_agent", agent_id: "siu_yan", status: "pending",
      due_date: "2026-09-29", description: "小欣嘅事"},
  ],
};

const ids = (sel) => [
  ...sel.followups, ...sel.facts, ...sel.sensitiveFacts,
].map((x) => x.id).concat(sel.summaryDays.flatMap((d) => d.ids));

test("policy C: another agent's private items never reach this agent", () => {
  const sel = m.selectForInjection(mem, {agentId: "tung_tung", policy: "C",
    todayKey: TODAY, sessionStart: true});
  const got = ids(sel);
  assert.ok(got.includes("name_by_siu"), "shared basic fact");
  assert.ok(!got.includes("hobby_by_siu"), "agent-private fact");
  assert.ok(!got.includes("family_conflict_by_siu"), "sensitive fact");
  assert.ok(!got.includes("s1") && !got.includes("s2"), "other summaries");
  assert.ok(!got.includes("other_agent"), "other agent's follow-up");
  assert.ok(got.includes("hobby_by_tung") && got.includes("s3"));
});

test("policy B isolates; policy A shares all but sensitive", () => {
  const b = ids(m.selectForInjection(mem, {agentId: "tung_tung",
    policy: "B", todayKey: TODAY, sessionStart: false}));
  assert.ok(!b.includes("name_by_siu"));
  const a = ids(m.selectForInjection(mem, {agentId: "tung_tung",
    policy: "A", todayKey: TODAY, sessionStart: false}));
  assert.ok(a.includes("hobby_by_siu") && a.includes("s1"));
  assert.ok(!a.includes("family_conflict_by_siu"));
});

test("facts flagged for researcher review are not injected", () => {
  const got = ids(m.selectForInjection(mem, {agentId: "tung_tung",
    policy: "C", todayKey: TODAY, sessionStart: false}));
  assert.ok(!got.includes("flagged"));
});

test("only one due follow-up, only at session start, not stale/future", () => {
  const start = m.selectForInjection(mem, {agentId: "tung_tung",
    policy: "C", todayKey: TODAY, sessionStart: true});
  assert.deepStrictEqual(start.followups.map((f) => f.id), ["due"]);
  const later = m.selectForInjection(mem, {agentId: "tung_tung",
    policy: "C", todayKey: TODAY, sessionStart: false});
  assert.strictEqual(later.followups.length, 0);
});

test("same-day sessions merge into one daily summary line", () => {
  const sel = m.selectForInjection(mem, {agentId: "siu_yan", policy: "C",
    todayKey: TODAY, sessionStart: false});
  assert.strictEqual(sel.summaryDays.length, 1);
  const block = m.renderMemoryBlock(sel);
  assert.ok(block.text.includes("- 2026-09-28：A；B"));
});

test("the block stays under the cap however much memory exists", () => {
  const many = {
    facts: Array.from({length: 60}, (_, i) =>
      fact(`f${i}`, "siu_yan", "hobby", "normal",
          {value: "好長嘅內容".repeat(20)})),
    summaries: Array.from({length: 40}, (_, i) => ({id: `s${i}`,
      agent_id: "siu_yan", day_key: m.addDays(TODAY, -i), summary:
      "摘要".repeat(75), ended_ms: i, sensitivity: "normal"})),
    followups: [],
  };
  const sel = m.selectForInjection(many, {agentId: "siu_yan", policy: "C",
    todayKey: TODAY, sessionStart: false});
  assert.ok(sel.facts.length <= m.LIMITS.facts);
  assert.ok(sel.summaryDays.length <= m.LIMITS.summaryDays);
  const block = m.renderMemoryBlock(sel);
  assert.ok(block.text.length <= m.LIMITS.maxChars,
      `block ${block.text.length} chars`);
  assert.ok(block.layers.fact > 0, "facts kept before summaries");
});

test("empty memory renders nothing", () => {
  const sel = m.selectForInjection({facts: [], summaries: [], followups: []},
      {agentId: "siu_yan", policy: "C", todayKey: TODAY,
        sessionStart: true});
  assert.strictEqual(m.renderMemoryBlock(sel).text, "");
});

test("only chat surfaces get memory", () => {
  for (const id of ["m2_check_in", "reflective_dialogue", "tung_tung_chat",
    "m3_reminiscence_w2", "greeting_tung_tung"]) {
    assert.ok(m.INJECT_MODULES.test(id), id);
  }
  for (const id of ["rolling_summary_fold", "m3_reminiscence_w2_summary",
    "m6_suggestions", "brief_pr", "m9_progress_summary"]) {
    assert.ok(!m.INJECT_MODULES.test(id), id);
  }
});

// ------------------------------------------------------------------ scope
test("scope: Phase B Arm A is in without opting in; Phase A Arm A is not",
    () => {
      const cfg = {enabled: true, phaseBArmA: true};
      assert.ok(m.inScope(cfg, {arm: "A", armAssignmentMode: "randomise"}));
      assert.ok(!m.inScope(cfg, {arm: "A", armAssignmentMode: "force_a"}));
      assert.ok(!m.inScope(cfg, {arm: "A"}), "pre-server-assignment user");
    });

test("scope: Arm B never, even opted in or randomised", () => {
  const cfg = {enabled: true, phaseBArmA: true};
  assert.ok(!m.inScope(cfg, {arm: "B", armAssignmentMode: "randomise"}));
  assert.ok(!m.inScope(cfg, {arm: "B", memory_enabled: true}));
});

test("scope: testers opt in; phaseBArmA off leaves only opt-ins", () => {
  assert.ok(m.inScope({enabled: true, phaseBArmA: false},
      {arm: "A", memory_enabled: true}));
  assert.ok(!m.inScope({enabled: true, phaseBArmA: false},
      {arm: "A", armAssignmentMode: "randomise"}));
});

test("scope: the kill switch overrides everything", () => {
  const off = {enabled: false, phaseBArmA: true};
  assert.ok(!m.inScope(off, {arm: "A", armAssignmentMode: "randomise"}));
  assert.ok(!m.inScope(off, {arm: "A", memory_enabled: true}));
});

console.log(`\n${passed} passed, ${failures.length} failed.`);
if (failures.length) process.exit(1);
