/**
 * Memory module v1 (spec: 陪住 记忆模块 技术交付文档 v0).
 *
 * Server-side memory for opted-in users only. Everything here is gated by
 *   meta/memory_config.enabled   — global kill switch (default off)
 *   users/{uid}.memory_enabled   — per-user opt-in
 * so Phase A/B participants (no opt-in UI in their builds, kill switch off
 * on the study project) never touch it. The existing per-agent rolling
 * summary ("memory v0") is left untouched for them.
 *
 * Layers stored under users/{uid}/:
 *   mem_summaries/{extractionId}  one per ended session, agent-private
 *   mem_facts/{factId}            structured profile, shared or agent-private
 *   mem_followups/{id}            dated items the agent may ask about once
 *   mem_injections/{id}           audit log: which items went into a prompt
 *   mem_extractions/{id}          claimed transcript + raw LLM output + status
 * Clients may read and delete the first three (the "我記得嘅嘢" page) and
 * nothing else; every write comes from this module (firestore.rules).
 *
 * Write path: session end (callable) or the 30-minute idle sweep claims the
 * agent's short-term buffer into a mem_extractions doc, asks the model for
 * strict JSON, validates it, then writes all layers in ONE batch. Any
 * failure writes nothing and leaves the extraction retryable.
 *
 * Read path: proxyDeepSeek calls injectMemory(), which filters by the
 * sharing policy on the server (never by prompt), caps the block length,
 * and logs the injection.
 *
 * Retrieval memory (RAG) is out of scope for v1.
 */

"use strict";

const AGENTS = ["siu_yan", "ah_jan_ah_bak", "tung_tung"];

/** Chat surfaces that receive the memory block. */
const INJECT_MODULES = new RegExp(
    "^(m2_check_in|reflective_dialogue|tung_tung_chat|m3_reminiscence_w\\d+" +
    "|greeting_(siu_yan|ah_jan_ah_bak|tung_tung))$");

/** Fixed category list the extractor must use. */
const CATEGORIES = [
  "name", // 稱呼
  "family", // 家人（姓名、關係）
  "living", // 居住情況
  "hobby", // 興趣
  "routine", // 日常
  "event", // 重要事件
  "health", // 健康
  "preference", // 其他喜好
];

/** "Basic facts" shared with every agent under policy C. */
const SHARED_CATEGORIES = new Set(["name", "family", "living"]);

/** Categories that are always sensitive, whatever the model says. */
const SENSITIVE_CATEGORIES = new Set(["health"]);

/** Keyword rule layered on the model's own sensitive flag. */
const SENSITIVE_TERMS = [
  "病", "醫", "藥", "痛", "癌", "覆診", "手術", "入院", "過身", "去世", "死",
  "離婚", "嗌交", "吵架", "唔啱", "反面", "錢", "債", "借", "遺囑", "抑鬱",
  "焦慮", "失眠", "孤獨", "寂寞",
];

/**
 * Safety terms: content matching these never enters any layer. Turns that
 * tripped the client lexicon are already excluded from the buffer; this is
 * a server-side backstop.
 */
const SAFETY_TERMS = [
  "自殺", "自杀", "想死", "死咗算", "唔想再生", "結束自己", "结束自己", "跳樓",
  "跳楼", "燒炭", "烧炭", "自殘", "自残", "suicide", "kill myself",
  "end my life", "self-harm",
];

/**
 * Appointment words the user volunteers with a date ("下個禮拜四睇醫生")
 * don't make a follow-up sensitive: asking how it went is the point of
 * the layer (spec: 「你上次話睇醫生，結果點呀？」). Diagnoses (癌, 手術,
 * 病 …) still do. Pending PI sign-off.
 */
const APPOINTMENT_TERMS = ["睇醫生", "覆診", "醫生", "診所", "醫"];

const LIMITS = {
  maxChars: 2000, // ≈1,500 tokens of Chinese
  followups: 1,
  facts: 20,
  summaryDays: 3,
  summaryChars: 150,
  followupExpireDays: 7,
  maxAttempts: 3,
  revisionReview: 3, // this many revisions of one fact → researcher review
};

/** Category order when facts must be trimmed. */
const CATEGORY_PRIORITY = [
  "name", "family", "living", "routine", "hobby", "event", "preference",
  "health",
];

// ---------------------------------------------------------------------------
// Time helpers (Hong Kong)
// ---------------------------------------------------------------------------

/**
 * @param {Date} d
 * @return {string} YYYY-MM-DD in Asia/Hong_Kong.
 */
function hkDateKey(d) {
  return d.toLocaleDateString("en-CA", {timeZone: "Asia/Hong_Kong"});
}

/**
 * @param {string} key YYYY-MM-DD
 * @param {number} days
 * @return {string} key shifted by days.
 */
function addDays(key, days) {
  const t = Date.parse(`${key}T00:00:00Z`) + days * 86400000;
  return new Date(t).toISOString().slice(0, 10);
}

const WEEKDAYS_ZH = ["日", "一", "二", "三", "四", "五", "六"];

/**
 * @param {string} key YYYY-MM-DD
 * @return {string} e.g. 星期四
 */
function weekdayZh(key) {
  return `星期${WEEKDAYS_ZH[new Date(`${key}T00:00:00Z`).getUTCDay()]}`;
}

// ---------------------------------------------------------------------------
// Classification rules (rules first; the model only proposes a category)
// ---------------------------------------------------------------------------

/**
 * Strip whitespace and punctuation so quote matching survives spacing.
 * @param {string} s
 * @return {string}
 */
function normalize(s) {
  return String(s || "")
      .toLowerCase()
      .replace(/[\s\p{P}\p{S}]/gu, "");
}

/**
 * @param {string} text
 * @return {boolean}
 */
function hitsSafety(text) {
  const t = String(text || "").toLowerCase();
  return SAFETY_TERMS.some((w) => t.includes(w));
}

/**
 * @param {string} category
 * @param {string} text value + quote
 * @param {boolean} modelSaysSensitive
 * @return {string} normal | sensitive | safety
 */
function classifySensitivity(category, text, modelSaysSensitive) {
  if (hitsSafety(text)) return "safety";
  if (SENSITIVE_CATEGORIES.has(category)) return "sensitive";
  if (modelSaysSensitive) return "sensitive";
  if (SENSITIVE_TERMS.some((w) => String(text || "").includes(w))) {
    return "sensitive";
  }
  return "normal";
}

/**
 * Sensitive content is never shared across agents.
 * @param {string} category
 * @param {string} sensitivity
 * @return {string} shared | agent
 */
function visibilityFor(category, sensitivity) {
  if (sensitivity !== "normal") return "agent";
  return SHARED_CATEGORIES.has(category) ? "shared" : "agent";
}

// ---------------------------------------------------------------------------
// Extraction: prompt + validation
// ---------------------------------------------------------------------------

/**
 * @param {{turns: Array<{fromUser: boolean, text: string}>,
 *   activeFacts: Array<object>, todayKey: string}} args
 * @return {{system: string, user: string}}
 */
function buildExtractionPrompt({turns, activeFacts, todayKey}) {
  const system = `你負責由一段長者同 AI 陪伴者嘅對話入面，抽取值得記住嘅資料。
只可以抽取「用戶」自己明確講過嘅內容，唔好推測、唔好補充。
每一條事實同待跟進事項，都要附上 quote：用戶原句入面連續嘅一段字，一字不改。
用繁體書面中文寫 value / summary / description，人名同重要粵語詞保留原文。
唔好記錄電話、地址、身份證號碼。涉及自殺、自殘嘅內容一律唔好抽取。

今日係 ${todayKey}（${weekdayZh(todayKey)}，香港時間）。
「聽日」「下個禮拜四」「月尾」呢類相對日期，要換算成 YYYY-MM-DD。
冇講明日期嘅事，唔好當待跟進事項。

category 只可以用：${CATEGORIES.join(", ")}。
facts 入面每條要標 op：
- add：新事實
- update：修正或更新現有事實，要填 fact_id（用下面「現有事實」嘅 id）；
  如果用戶係糾正之前講錯嘅嘢，correction 填 true
- no_change：唔使輸出（省略）
健康、家庭矛盾、財務、情緒困擾等內容，sensitive 填 true。

只輸出一個 JSON 物件，格式：
{"summary": "≤150字，第三身描述今次傾咗咩",
 "facts": [{"op": "add|update", "fact_id": "", "category": "",
   "key": "簡短標題", "value": "", "quote": "", "sensitive": false,
   "correction": false}],
 "followups": [{"description": "", "due_date": "YYYY-MM-DD", "quote": ""}]}`;

  const factLines = activeFacts.length === 0 ? "（暫時冇）" :
    activeFacts.map((f) =>
      `- id=${f.id} [${f.category}] ${f.key}：${f.value}`).join("\n");
  const transcript = turns
      .map((t) => `${t.fromUser ? "用戶" : "陪伴者"}：${t.text}`)
      .join("\n");
  const user = `[現有事實]\n${factLines}\n\n[今次對話]\n${transcript}`;
  return {system, user};
}

/**
 * Validate the model's JSON against the schema and the transcript.
 * Schema errors reject the whole extraction (nothing is written); items
 * whose quote is not in the user's own words are dropped individually.
 *
 * @param {object} raw parsed JSON from the model
 * @param {{turns: Array<{fromUser: boolean, text: string}>,
 *   activeFactIds: Set<string>, todayKey: string}} ctx
 * @return {object} {ok, error} on rejection; {ok, summary, facts,
 *   followups, dropped} otherwise
 */
function validateExtraction(raw, ctx) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return {ok: false, error: "not_an_object"};
  }
  const {summary} = raw;
  const facts = raw.facts === undefined ? [] : raw.facts;
  const followups = raw.followups === undefined ? [] : raw.followups;
  if (typeof summary !== "string") return {ok: false, error: "summary"};
  if (!Array.isArray(facts)) return {ok: false, error: "facts"};
  if (!Array.isArray(followups)) return {ok: false, error: "followups"};

  const userText = normalize(
      ctx.turns.filter((t) => t.fromUser).map((t) => t.text).join("\n"));
  const quoted = (q) => {
    const n = normalize(q);
    return n.length >= 2 && userText.includes(n);
  };

  const outFacts = [];
  const outFollowups = [];
  const dropped = [];

  for (const f of facts) {
    if (!f || typeof f !== "object") return {ok: false, error: "fact_shape"};
    if (!["add", "update"].includes(f.op)) {
      if (f.op === "no_change") continue;
      return {ok: false, error: "fact_op"};
    }
    for (const k of ["category", "key", "value", "quote"]) {
      if (typeof f[k] !== "string" || !f[k].trim()) {
        return {ok: false, error: `fact_${k}`};
      }
    }
    if (!CATEGORIES.includes(f.category)) {
      return {ok: false, error: "fact_category"};
    }
    if (!quoted(f.quote)) {
      dropped.push({kind: "fact", reason: "quote_not_found", item: f});
      continue;
    }
    const sensitivity = classifySensitivity(
        f.category, `${f.value} ${f.quote}`, f.sensitive === true);
    if (sensitivity === "safety") {
      dropped.push({kind: "fact", reason: "safety", item: {op: f.op}});
      continue;
    }
    const replaces = f.op === "update" && ctx.activeFactIds.has(f.fact_id) ?
      f.fact_id : null;
    outFacts.push({
      category: f.category,
      key: f.key.trim().slice(0, 40),
      value: f.value.trim().slice(0, 200),
      quote: f.quote.trim().slice(0, 200),
      sensitivity,
      visibility: visibilityFor(f.category, sensitivity),
      replaces,
      correction: f.correction === true,
    });
  }

  const minDue = addDays(ctx.todayKey, -1);
  const maxDue = addDays(ctx.todayKey, 365);
  for (const u of followups) {
    if (!u || typeof u !== "object") {
      return {ok: false, error: "followup_shape"};
    }
    if (typeof u.description !== "string" || !u.description.trim()) {
      return {ok: false, error: "followup_description"};
    }
    if (typeof u.due_date !== "string" ||
        !/^\d{4}-\d{2}-\d{2}$/.test(u.due_date) ||
        Number.isNaN(Date.parse(`${u.due_date}T00:00:00Z`))) {
      return {ok: false, error: "followup_due_date"};
    }
    if (u.due_date < minDue || u.due_date > maxDue) {
      dropped.push({kind: "followup", reason: "due_out_of_range", item: u});
      continue;
    }
    if (typeof u.quote !== "string" || !quoted(u.quote)) {
      dropped.push({kind: "followup", reason: "quote_not_found", item: u});
      continue;
    }
    const text = `${u.description} ${u.quote}`;
    if (hitsSafety(text)) {
      dropped.push({kind: "followup", reason: "safety", item: {}});
      continue;
    }
    outFollowups.push({
      description: u.description.trim().slice(0, 120),
      due_date: u.due_date,
      quote: u.quote.trim().slice(0, 200),
      sensitivity: classifySensitivity("event",
          APPOINTMENT_TERMS.reduce((t, w) => t.split(w).join(""), text),
          false),
    });
  }

  const cleanSummary = hitsSafety(summary) ? "" :
    summary.trim().slice(0, LIMITS.summaryChars);
  return {
    ok: true,
    summary: cleanSummary,
    facts: outFacts,
    followups: outFollowups,
    dropped,
  };
}

// ---------------------------------------------------------------------------
// Injection: selection + block assembly (pure)
// ---------------------------------------------------------------------------

/**
 * Items an agent may see under a sharing policy. Sensitive items stay with
 * the agent they were told to, whatever the policy.
 *   A — everything shared
 *   B — each agent sees only its own
 *   C — (default) shared-visibility facts from any agent + own items
 * Summaries and follow-ups are agent-private under B and C.
 *
 * @param {object} item a mem_* doc with agent_id / visibility / sensitivity
 * @param {string} agentId the agent the prompt is for
 * @param {string} policy A | B | C
 * @return {boolean}
 */
function visibleTo(item, agentId, policy) {
  if (item.agent_id === agentId) return true;
  if ((item.sensitivity || "normal") !== "normal") return false;
  if (policy === "A") return true;
  if (policy === "B") return false;
  return item.visibility === "shared";
}

/**
 * Pick what goes into the block, in priority order, within LIMITS.
 * @param {{facts: Array<object>, summaries: Array<object>,
 *   followups: Array<object>}} mem loaded docs (with id)
 * @param {{agentId: string, policy: string, todayKey: string,
 *   sessionStart: boolean}} opts
 * @return {{followups: Array<object>, facts: Array<object>,
 *   sensitiveFacts: Array<object>, summaryDays: Array<object>}}
 */
function selectForInjection(mem, opts) {
  const {agentId, policy, todayKey, sessionStart} = opts;
  const expireBefore = addDays(todayKey, -LIMITS.followupExpireDays);

  const followups = !sessionStart ? [] : mem.followups
      .filter((f) => f.agent_id === agentId && f.status === "pending")
      .filter((f) => f.due_date <= todayKey && f.due_date >= expireBefore)
      .filter((f) => (f.sensitivity || "normal") === "normal")
      .sort((a, b) => b.due_date.localeCompare(a.due_date))
      .slice(0, LIMITS.followups);

  const usable = mem.facts
      .filter((f) => f.status === "active" && !f.needs_review)
      .filter((f) => visibleTo(f, agentId, policy))
      .sort((a, b) => {
        const pa = CATEGORY_PRIORITY.indexOf(a.category);
        const pb = CATEGORY_PRIORITY.indexOf(b.category);
        if (pa !== pb) return pa - pb;
        return (b.updated_ms || 0) - (a.updated_ms || 0);
      });
  const facts = usable.filter((f) => f.sensitivity === "normal")
      .slice(0, LIMITS.facts);
  const sensitiveFacts = usable.filter((f) => f.sensitivity === "sensitive")
      .slice(0, Math.max(0, LIMITS.facts - facts.length));

  // Same-day sessions read as one daily entry; only the last few days go in.
  const byDay = new Map();
  // Summaries are agent-private except under policy A.
  for (const s of mem.summaries
      .filter((x) => visibleTo(x, agentId, policy === "A" ? "A" : "B"))
      .filter((x) => x.summary)
      .sort((a, b) => (a.ended_ms || 0) - (b.ended_ms || 0))) {
    const day = byDay.get(s.day_key) || {day: s.day_key, ids: [], texts: []};
    day.ids.push(s.id);
    day.texts.push(s.summary);
    byDay.set(s.day_key, day);
  }
  const summaryDays = [...byDay.values()]
      .sort((a, b) => b.day.localeCompare(a.day))
      .slice(0, LIMITS.summaryDays);

  return {followups, facts, sensitiveFacts, summaryDays};
}

const USAGE_RULES = `[記憶使用規則]
1. 提起記憶時要留餘地，例如「我記得你好似講過……係唔係呀？」
2. 一輪最多自然咁提起一樣記憶，唔好一次過列出。
3. 「敏感」嗰部分，只可以喺對方自己提起相關話題時先用，唔好主動引出。
4. 對方話你記錯，就道歉、接受新講法，唔好爭辯。
5. 唔肯定就唔好提；絕對唔好作對方冇講過嘅嘢。
6. 唔好講「另一位陪伴者話我知」之類嘅說話。`;

/**
 * Render the selection into the prompt block, trimming lowest priority
 * sections first so the block never exceeds LIMITS.maxChars.
 * @param {object} sel from selectForInjection
 * @return {{text: string, ids: Array<string>,
 *   layers: {followup: number, fact: number, sensitive: number,
 *   summary: number}}}
 */
function renderMemoryBlock(sel) {
  const f = sel.followups.map((x) => ({
    id: x.id, line: `- ${x.description}（${x.due_date}）`}));
  const facts = sel.facts.map((x) => ({
    id: x.id, line: `- ${x.key}：${x.value}`}));
  const sens = sel.sensitiveFacts.map((x) => ({
    id: x.id, line: `- ${x.key}：${x.value}`}));
  const sums = sel.summaryDays.map((d) => ({
    ids: d.ids, line: `- ${d.day}：${d.texts.join("；")}`}));

  const build = (nFollow, nFacts, nSens, nSums) => {
    const parts = [];
    const ids = [];
    if (nFollow > 0) {
      parts.push("[到期要關心嘅事]（開場可以自然咁問一次，問過就算）");
      for (const x of f.slice(0, nFollow)) {
        parts.push(x.line); ids.push(x.id);
      }
    }
    if (nFacts > 0) {
      parts.push("[關於對方嘅資料]");
      for (const x of facts.slice(0, nFacts)) {
        parts.push(x.line); ids.push(x.id);
      }
    }
    if (nSums > 0) {
      parts.push("[之前傾過]");
      for (const x of sums.slice(0, nSums)) {
        parts.push(x.line); ids.push(...x.ids);
      }
    }
    if (nSens > 0) {
      parts.push("[敏感]（只喺對方自己提起先可以用）");
      for (const x of sens.slice(0, nSens)) {
        parts.push(x.line); ids.push(x.id);
      }
    }
    if (parts.length === 0) return {text: "", ids};
    const text =
      `<memory>\n${parts.join("\n")}\n</memory>\n${USAGE_RULES}`;
    return {text, ids};
  };

  // Trim order (lowest priority first): sensitive → summaries → facts.
  let nF = f.length;
  let nFa = facts.length;
  let nS = sens.length;
  let nSu = sums.length;
  let out = build(nF, nFa, nS, nSu);
  while (out.text.length > LIMITS.maxChars) {
    if (nS > 0) nS--;
    else if (nSu > 0) nSu--;
    else if (nFa > 0) nFa--;
    else if (nF > 0) nF--;
    else break;
    out = build(nF, nFa, nS, nSu);
  }
  return {
    text: out.text,
    ids: out.ids,
    layers: {followup: nF, fact: nFa, sensitive: nS, summary: nSu},
  };
}

// ---------------------------------------------------------------------------
// Firestore I/O
// ---------------------------------------------------------------------------

/**
 * @param {object} db admin.firestore()
 * @return {Promise<{enabled: boolean, policy: string}>}
 */
async function loadConfig(db) {
  const snap = await db.doc("meta/memory_config").get();
  const d = snap.exists ? snap.data() : {};
  const policy = ["A", "B", "C"].includes(d.policy) ? d.policy : "C";
  return {
    enabled: d.enabled === true,
    policy,
    phaseBArmA: d.phaseBArmA === true,
  };
}

/**
 * Who memory v1 applies to, given the config and a profile doc's data:
 *   - never Arm B;
 *   - Phase B Arm A (assigned while randomising) when cfg.phaseBArmA —
 *     mandatory, no opt-out; Phase A pilot users (assigned in force_a
 *     mode) keep memory v0;
 *   - anyone else who opted in (testers on a MEMORY_V1 build).
 * The kill switch (cfg.enabled) overrides everything.
 * @param {{enabled: boolean, phaseBArmA: boolean}} cfg
 * @param {object} user profile doc data
 * @return {boolean}
 */
function inScope(cfg, user) {
  if (!cfg.enabled || !user) return false;
  if (user.arm === "B") return false;
  if (cfg.phaseBArmA && user.arm === "A" &&
      user.armAssignmentMode === "randomise") {
    return true;
  }
  return user.memory_enabled === true;
}

/**
 * @param {object} db
 * @param {string} uid
 * @return {Promise<?{policy: string}>}
 */
async function memoryActive(db, uid) {
  const cfg = await loadConfig(db);
  if (!cfg.enabled) return null;
  const user = await db.collection("users").doc(uid).get();
  if (!user.exists || !inScope(cfg, user.data())) return null;
  return {policy: cfg.policy};
}

/**
 * @param {*} ts Firestore Timestamp | Date | undefined
 * @return {number}
 */
function millis(ts) {
  if (!ts) return 0;
  if (typeof ts.toMillis === "function") return ts.toMillis();
  if (ts instanceof Date) return ts.getTime();
  return 0;
}

/**
 * @param {object} db
 * @param {string} uid
 * @return {Promise<{facts: Array<object>, summaries: Array<object>,
 *   followups: Array<object>}>}
 */
async function loadMemory(db, uid) {
  const u = db.collection("users").doc(uid);
  const [facts, summaries, followups] = await Promise.all([
    u.collection("mem_facts").where("status", "==", "active").get(),
    u.collection("mem_summaries").orderBy("ended_at", "desc").limit(30).get(),
    u.collection("mem_followups").where("status", "==", "pending").get(),
  ]);
  const rows = (snap) => snap.docs.map((d) => ({
    id: d.id, ...d.data(),
    updated_ms: millis(d.get("updated_at")),
    ended_ms: millis(d.get("ended_at")),
  }));
  return {
    facts: rows(facts),
    summaries: rows(summaries),
    followups: rows(followups),
  };
}

/**
 * Build the memory block for one proxyDeepSeek call, mark an injected
 * follow-up as asked, and log the injection. Returns "" when memory is
 * off for this user/module. Never throws: memory must not break a chat.
 *
 * @param {object} db
 * @param {{uid: string, agentId: ?string, moduleId: string,
 *   messages: Array<object>, now: (Date|undefined)}} args
 * @return {Promise<string>}
 */
async function injectMemory(db, {uid, agentId, moduleId, messages, now}) {
  try {
    if (!uid || !AGENTS.includes(agentId)) return "";
    if (!INJECT_MODULES.test(moduleId)) return "";
    const active = await memoryActive(db, uid);
    if (!active) return "";

    const todayKey = hkDateKey(now || new Date());
    const userTurns = messages.filter((m) => m.role === "user").length;
    // Follow-ups go in on the first user turn of a real chat only: a
    // pre-generated greeting may never be seen, so it must not use one up.
    const sessionStart = userTurns <= 1 && !moduleId.startsWith("greeting_");
    const mem = await loadMemory(db, uid);
    const sel = selectForInjection(mem, {
      agentId, policy: active.policy, todayKey, sessionStart,
    });
    const block = renderMemoryBlock(sel);
    if (!block.text) return "";

    const u = db.collection("users").doc(uid);
    const batch = db.batch();
    const shownFollowups = sel.followups.slice(0, block.layers.followup);
    for (const f of shownFollowups) {
      batch.update(u.collection("mem_followups").doc(f.id), {
        status: "asked",
        asked_at: new Date(),
      });
    }
    batch.set(u.collection("mem_injections").doc(), {
      agent_id: agentId,
      module_id: moduleId,
      memory_ids: block.ids,
      layers: block.layers,
      policy: active.policy,
      chars: block.text.length,
      created_at: new Date(),
    });
    await batch.commit();
    return block.text;
  } catch (err) {
    console.error("memory injection failed", {uid, agentId, err: String(err)});
    return "";
  }
}

/**
 * Atomically move an agent's short-term buffer into a pending
 * mem_extractions doc. Returns its id, or null when there is nothing to
 * extract. A second concurrent claim sees an empty buffer, so one session
 * is extracted once (MEM-3).
 *
 * @param {object} db
 * @param {string} uid
 * @param {string} agentId
 * @return {Promise<?string>}
 */
async function claimBuffer(db, uid, agentId) {
  const u = db.collection("users").doc(uid);
  const ctxRef = u.collection("agent_contexts").doc(agentId);
  const extRef = u.collection("mem_extractions").doc();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ctxRef);
    const buffer = snap.exists ? (snap.get("shortTermBuffer") || []) : [];
    const turns = buffer
        .filter((t) => t && typeof t.text === "string" && t.text.trim())
        .map((t) => ({
          fromUser: t.fromUser === true,
          text: t.text,
          timestamp: t.timestamp || null,
        }));
    if (!turns.some((t) => t.fromUser)) return null;
    tx.set(extRef, {
      agent_id: agentId,
      turns,
      status: "pending",
      attempts: 0,
      created_at: new Date(),
    });
    tx.set(ctxRef, {shortTermBuffer: [], lastUpdated: new Date()},
        {merge: true});
    return extRef.id;
  });
}

/**
 * Run one extraction: model call → validation → one batch write.
 * @param {object} db
 * @param {string} uid
 * @param {string} extractionId
 * @param {function({system: string, user: string}): Promise<string>} callModel
 *   returns the raw JSON text
 * @param {Date=} now
 * @return {Promise<string>} final status: done | failed | skipped
 */
async function processExtraction(db, uid, extractionId, callModel, now) {
  const u = db.collection("users").doc(uid);
  const extRef = u.collection("mem_extractions").doc(extractionId);
  const ext = await extRef.get();
  if (!ext.exists) return "skipped";
  const data = ext.data();
  if (data.status === "done") return "done";
  if ((data.attempts || 0) >= LIMITS.maxAttempts) return "failed";

  const agentId = data.agent_id;
  const turns = data.turns || [];
  const todayKey = hkDateKey(now || new Date());
  let rawText = "";
  try {
    const existing = await u.collection("mem_facts")
        .where("status", "==", "active").get();
    const activeFacts = existing.docs
        .map((d) => ({id: d.id, ...d.data()}))
        .filter((f) => visibleTo(f, agentId, "C"));
    const prompt = buildExtractionPrompt({turns, activeFacts, todayKey});
    rawText = await callModel(prompt);
    let parsed;
    try {
      parsed = JSON.parse(rawText);
    } catch (_) {
      throw new Error("invalid_json");
    }
    const v = validateExtraction(parsed, {
      turns, todayKey,
      activeFactIds: new Set(activeFacts.map((f) => f.id)),
    });
    if (!v.ok) throw new Error(`schema:${v.error}`);

    const byId = new Map(existing.docs.map((d) => [d.id, d]));
    const stamp = now || new Date();
    const times = turns.map((t) => Date.parse(t.timestamp || ""))
        .filter((t) => !Number.isNaN(t));
    const batch = db.batch();

    const endedAt = times.length ? new Date(Math.max(...times)) : stamp;
    if (v.summary) {
      batch.set(u.collection("mem_summaries").doc(extractionId), {
        agent_id: agentId,
        summary: v.summary,
        turn_count: turns.filter((t) => t.fromUser).length,
        started_at: times.length ? new Date(Math.min(...times)) : stamp,
        ended_at: endedAt,
        // The day the conversation happened, not the day it was extracted.
        day_key: hkDateKey(endedAt),
        visibility: "agent",
        sensitivity: classifySensitivity("event", v.summary, false),
        source_session_id: extractionId,
      });
    }

    for (const f of v.facts) {
      // An "add" for a key the agent can already see is an update of it.
      let old = f.replaces ? byId.get(f.replaces) : null;
      if (!old) {
        old = existing.docs.find((d) =>
          d.get("category") === f.category && d.get("key") === f.key &&
          visibleTo({id: d.id, ...d.data()}, agentId, "C")) || null;
      }
      const revisions = old ? (old.get("revision_count") || 0) + 1 : 0;
      const ref = u.collection("mem_facts").doc();
      batch.set(ref, {
        agent_id: agentId,
        category: f.category,
        key: f.key,
        value: f.value,
        quote: f.quote,
        visibility: f.visibility,
        sensitivity: f.sensitivity,
        // Sensitive items wait for the user's go-ahead on the
        // "我記得嘅嘢" page before any agent may use them.
        status: f.sensitivity === "sensitive" ?
          "pending_confirmation" : "active",
        user_corrected: f.correction,
        revision_count: revisions,
        needs_review: revisions >= LIMITS.revisionReview,
        confidence: null,
        replaces: old ? old.id : null,
        source_session_id: extractionId,
        created_at: stamp,
        updated_at: stamp,
      });
      if (old) {
        batch.update(old.ref, {
          status: "superseded",
          superseded_by: ref.id,
          updated_at: stamp,
        });
      }
    }

    for (const fu of v.followups) {
      batch.set(u.collection("mem_followups").doc(), {
        agent_id: agentId,
        description: fu.description,
        due_date: fu.due_date,
        quote: fu.quote,
        sensitivity: fu.sensitivity,
        status: "pending",
        asked_at: null,
        source_session_id: extractionId,
        created_at: stamp,
      });
    }

    batch.update(extRef, {
      status: "done",
      attempts: (data.attempts || 0) + 1,
      raw_output: rawText.slice(0, 20000),
      dropped: v.dropped.map((d) => ({kind: d.kind, reason: d.reason})),
      counts: {
        facts: v.facts.length,
        followups: v.followups.length,
        summary: v.summary ? 1 : 0,
      },
      // The verbatim transcript has served its purpose.
      turns: [],
      finished_at: stamp,
    });
    await batch.commit();
    return "done";
  } catch (err) {
    await extRef.update({
      status: "failed",
      attempts: (data.attempts || 0) + 1,
      error: String(err && err.message || err).slice(0, 500),
      raw_output: String(rawText || "").slice(0, 20000),
    });
    return "failed";
  }
}

module.exports = {
  AGENTS,
  CATEGORIES,
  LIMITS,
  INJECT_MODULES,
  hkDateKey,
  addDays,
  normalize,
  hitsSafety,
  classifySensitivity,
  visibilityFor,
  buildExtractionPrompt,
  validateExtraction,
  visibleTo,
  selectForInjection,
  renderMemoryBlock,
  loadConfig,
  inScope,
  memoryActive,
  loadMemory,
  injectMemory,
  claimBuffer,
  processExtraction,
};
