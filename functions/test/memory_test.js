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

test("C20: sharedContextUse only counts when the switch is on", () => {
  const off = {policy: "C", enforceSharedContextConsent: false};
  const on = {policy: "C", enforceSharedContextConsent: true};
  assert.strictEqual(m.effectivePolicy(off, {}), "C");
  assert.strictEqual(m.effectivePolicy(on, {}), "B");
  assert.strictEqual(m.effectivePolicy(on,
      {consent: {sharedContextUse: false}}), "B");
  assert.strictEqual(m.effectivePolicy(on,
      {consent: {sharedContextUse: true}}), "C");
  assert.strictEqual(m.effectivePolicy({policy: "A",
    enforceSharedContextConsent: true}, null), "B");
});

// ------------------------------------------------- T10 (decision 0024)
const forgetLib = require("../memory_forget");

test("T10 flags: fixes on unless false, confirmation reply off", () => {
  const d = m.t10Flags({});
  for (const k of ["excludeSafetyTurns", "omitSensitiveSummary",
    "honourForgetRequests", "deleteSummaryWithItem",
    "honourMemoryWithdrawal", "sensitiveFactQuota",
    "strictFactValidation"]) {
    assert.strictEqual(d[k], true, k);
    assert.strictEqual(m.t10Flags({[k]: false})[k], false, k);
  }
  assert.strictEqual(d.forgetAckReply, false);
  assert.strictEqual(m.t10Flags({forgetAckReply: true}).forgetAckReply, true);
  assert.strictEqual(d.extractionPrompt, "memory_extraction.v2");
  assert.strictEqual(m.t10Flags({extractionPrompt: "memory_extraction.v1"})
      .extractionPrompt, "memory_extraction.v1");
  assert.strictEqual(m.t10Flags({extractionPrompt: "x"}).extractionPrompt,
      "memory_extraction.v2");
});

test("T10 prompts: v1 file is the old prompt, v2 adds the new rules", () => {
  const v1 = m.buildExtractionPrompt({turns, activeFacts: [],
    todayKey: TODAY, promptName: "memory_extraction.v1"}).system;
  assert.ok(v1.includes("今日係 2026-09-29（星期二，香港時間）"));
  assert.ok(v1.includes(m.CATEGORIES.join(", ")));
  assert.ok(!v1.includes("safety_concern"));
  assert.ok(!v1.includes("{{"));
  const v2 = m.buildExtractionPrompt({turns, activeFacts: [],
    todayKey: TODAY}).system;
  for (const w of ["safety_concern", "假設", "講笑", "陪伴者嘅名",
    "唔好記住", "summary 只寫中性"]) {
    assert.ok(v2.includes(w), w);
  }
  assert.ok(!v2.includes("{{"));
});

test("T10 screening: flagged turns and the replies to them are removed", () => {
  const t = [
    {fromUser: true, text: "我今日去咗飲茶"},
    {fromUser: false, text: "好呀"},
    {fromUser: true, text: "有時諗住不如死咗算"},
    {fromUser: false, text: "我好擔心你"},
    {fromUser: false, text: "你可以同我講多啲"},
    {fromUser: true, text: "老伴走咗之後好難過"},
    {fromUser: true, text: "我好孤獨"},
    {fromUser: false, text: "我陪住你"},
  ];
  const r = m.screenTurns(t, {excludeSafety: true, forget: true});
  assert.strictEqual(r.safetyTurns, 2);
  assert.deepStrictEqual(r.turns.map((x) => x.text),
      ["我今日去咗飲茶", "好呀", "我好孤獨", "我陪住你"]);
  assert.strictEqual(r.forget, null);
  const off = m.screenTurns(t, {excludeSafety: false, forget: false});
  assert.strictEqual(off.turns.length, t.length);
});

test("T10 screening: a request not to remember is reported", () => {
  const t = [
    {fromUser: true, text: "我借咗五萬蚊俾個仔"},
    {fromUser: false, text: "唔該你同我講"},
    {fromUser: true, text: "你唔好記住呢件事呀"},
  ];
  const r = m.screenTurns(t, {excludeSafety: true, forget: true});
  assert.ok(r.forget);
  assert.strictEqual(r.forget.index, 2);
  assert.strictEqual(r.forget.label, "dont_remember");
  assert.strictEqual(m.screenTurns(t, {excludeSafety: true, forget: false})
      .forget, null);
});

test("T10 forget phrases: common Cantonese requests, not lookalikes", () => {
  const yes = ["唔好記住呢件事", "呢樣你唔好記低呀", "唔使記住喇",
    "當我冇講過", "就當我無講過啦", "唔好話畀其他人知", "唔好話俾美玲知",
    "唔好同其他人講", "你唔好講出去", "幫我保密", "你知我知就得",
    "忘記佢啦", "唔好再提呢件事", "不要記住", "Please don't remember this",
    "forget what I said", "你當冇聽過啦", "唔好記錄落去"];
  const no = ["我唔好記性", "我記性唔好", "你唔好記錯呀", "唔使記掛我",
    "我唔記得咗", "你唔好同我講笑", "記得提醒我食藥", "你咪記住佢囉",
    "我叫個女記住買餸", "今日好開心", "唔好提醒我", "當時冇講到"];
  for (const t of yes) assert.ok(forgetLib.detectForget(t), `miss: ${t}`);
  for (const t of no) assert.strictEqual(forgetLib.detectForget(t), null, t);
});

test("T10 forget: related items share two pieces with the request", () => {
  const t = [
    {fromUser: true, text: "我買股票蝕咗三萬蚊"},
    {fromUser: true, text: "唔好記住我股票蝕錢嘅事"},
  ];
  const subj = forgetLib.subjectBigrams(t, 1, "唔好記住");
  assert.ok(forgetLib.relatedTo("股票蝕咗三萬", subj));
  assert.ok(!forgetLib.relatedTo("鍾意飲早茶", subj));
  assert.ok(!forgetLib.relatedTo("唔好記住呢件事", subj), "stop words only");
});

test("T10 validation: safety turns or safety_concern → no summary", () => {
  const raw = extraction({summary: "陳太講起飲早茶。"});
  const base = {...ctx, excludeSafety: true};
  assert.strictEqual(m.validateExtraction(raw, base).summary, "陳太講起飲早茶。");
  const a = m.validateExtraction(raw, {...base, safetyTurns: 1});
  assert.strictEqual(a.summary, "");
  assert.ok(a.dropped.some((d) => d.reason === "safety_turns"));
  const b = m.validateExtraction(extraction({summary: "陳太講起飲早茶。",
    safety_concern: true,
    facts: [
      {op: "add", category: "health", key: "瞓", value: "瞓唔着",
        quote: "下個禮拜四帶我去睇醫生"},
      {op: "add", category: "name", key: "稱呼", value: "陳太",
        quote: "叫我陳太"}]}), base);
  assert.strictEqual(b.summary, "");
  assert.deepStrictEqual(b.facts.map((f) => f.category), ["name"]);
  // The App lexicon also runs on the summary the model wrote.
  const c = m.validateExtraction(extraction({summary: "佢覺得自己係個負擔"}),
      base);
  assert.strictEqual(c.summary, "");
  // Off: as before.
  assert.strictEqual(m.validateExtraction(extraction({summary: "x",
    safety_concern: true}), {...ctx, safetyTurns: 1}).summary, "x");
});

test("T10 validation: a sensitive summary is not kept", () => {
  const raw = extraction({summary: "陳太話膝頭痛，下星期去睇醫生。"});
  assert.strictEqual(m.validateExtraction(raw,
      {...ctx, omitSensitiveSummary: true}).summary, "");
  assert.ok(m.validateExtraction(raw, ctx).summary.length > 0);
});

test("T10 validation: companion names and cross-category updates", () => {
  const raw = extraction({facts: [
    {op: "add", category: "name", key: "陪伴者", value: "陪伴者叫阿珍",
      quote: "叫我陳太"},
    {op: "update", fact_id: "f_old", category: "event", key: "出世",
      value: "喺香港出世", quote: "叫我陳太"},
  ]});
  const strict = {...ctx, strictFacts: true,
    activeFactCategories: new Map([["f_old", "name"]])};
  const v = m.validateExtraction(raw, strict);
  assert.strictEqual(v.facts.length, 1);
  assert.strictEqual(v.facts[0].replaces, null, "event can't replace name");
  assert.ok(v.dropped.some((d) => d.reason === "companion_name"));
  const loose = m.validateExtraction(raw, ctx);
  assert.strictEqual(loose.facts.length, 2);
  assert.strictEqual(loose.facts[1].replaces, "f_old");
});

test("T10 validation: a dated plan is kept as a follow-up only", () => {
  const raw = extraction({
    facts: [{op: "add", category: "event", key: "睇醫生",
      value: "下個禮拜四睇醫生", quote: "下個禮拜四帶我去睇醫生"},
    {op: "add", category: "hobby", key: "飲早茶", value: "鍾意飲早茶",
      quote: "我鍾意飲早茶"}],
    followups: [{description: "睇醫生", due_date: "2026-10-08",
      quote: "阿玲下個禮拜四帶我去睇醫生"}],
  });
  const v = m.validateExtraction(raw, {...ctx, strictFacts: true});
  assert.deepStrictEqual(v.facts.map((f) => f.key), ["飲早茶"]);
  assert.strictEqual(v.followups.length, 1);
  assert.ok(v.dropped.some((d) => d.reason === "plan_is_followup"));
  assert.strictEqual(m.validateExtraction(raw, ctx).facts.length, 2);
});

test("T10 sensitivity: health, loss and mood words in summaries", () => {
  for (const t of ["腳唔好行唔到山", "夜晚瞓唔着", "照顧中風嘅老公",
    "而家眼矇睇唔清", "豆豆上個禮拜走咗"]) {
    assert.strictEqual(m.classifySensitivity("event", t, false), "sensitive",
        t);
  }
  assert.strictEqual(m.classifySensitivity("event", "去公園影花", false),
      "normal");
});

test("T10 injection: confirmed sensitive facts keep their own places", () => {
  const many = {facts: [], summaries: [], followups: []};
  for (let i = 0; i < 25; i++) {
    many.facts.push(fact(`f${i}`, "siu_yan", "family"));
  }
  for (let i = 0; i < 7; i++) {
    many.facts.push(fact(`s${i}`, "siu_yan", "health", "sensitive"));
  }
  const opts = {agentId: "siu_yan", policy: "C", todayKey: TODAY,
    sessionStart: false};
  assert.strictEqual(m.selectForInjection(many, opts).sensitiveFacts.length, 0);
  const q = m.selectForInjection(many, {...opts, sensitiveQuota: true});
  assert.strictEqual(q.facts.length, 20);
  assert.strictEqual(q.sensitiveFacts.length, m.LIMITS.sensitiveFacts);
});

test("T10 injection: sensitive summaries are left out", () => {
  const mm = {facts: [], followups: [], summaries: [
    {id: "a", agent_id: "siu_yan", summary: "飲茶", day_key: "2026-09-28",
      sensitivity: "normal"},
    {id: "b", agent_id: "siu_yan", summary: "膝頭痛", day_key: "2026-09-27",
      sensitivity: "sensitive"},
  ]};
  const opts = {agentId: "siu_yan", policy: "C", todayKey: TODAY,
    sessionStart: false};
  assert.strictEqual(m.selectForInjection(mm, opts).summaryDays.length, 2);
  const s = m.selectForInjection(mm, {...opts, omitSensitiveSummary: true});
  assert.deepStrictEqual(s.summaryDays.map((d) => d.ids[0]), ["a"]);
});

test("T10 scope: withdrawal stops memory, Phase B Arm A included", () => {
  const cfg = {enabled: true, phaseBArmA: true};
  const w = {arm: "A", armAssignmentMode: "randomise",
    memoryWithdrawnAt: new Date()};
  assert.ok(!m.inScope(cfg, w));
  assert.ok(!m.inScope(cfg, {memory_enabled: true,
    memoryWithdrawnAt: new Date()}));
  assert.ok(m.inScope({...cfg, honourMemoryWithdrawal: false}, w));
  // memory_enabled false is every App profile's default: not a withdrawal.
  assert.ok(m.inScope(cfg, {arm: "A", armAssignmentMode: "randomise",
    memory_enabled: false}));
});

test("T10 confirmation reply: off by default and never a draft", () => {
  const msgs = [{role: "user", content: "你唔好記住呢件事呀"}];
  // The shipped file still holds the draft mark, so nothing is added.
  assert.strictEqual(m.forgetAck(msgs), "");
  assert.strictEqual(m.forgetAck([{role: "user", content: "你好"}]), "");
});

console.log(`\n${passed} passed, ${failures.length} failed.`);
if (failures.length) process.exit(1);
