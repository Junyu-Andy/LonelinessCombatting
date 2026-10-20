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
 * T10 (decision 0024, switches in meta/memory_config, see t10Flags):
 * the elder's own words are screened with the App's safety lexicon
 * (safety_lexicon.json) before extraction; sensitive summaries are not
 * kept; a 「唔好記住」 request (memory_forget.js) keeps the session out
 * and deletes related items; deleting an item deletes its session's
 * summary; tool/delete_memory.js sets memoryWithdrawnAt, which stops
 * memory for good, Phase B Arm A included.
 *
 * T49e-4 (clearRawOutputOnDelete, a fix: on unless false): whenever a
 * fact, follow-up or summary is deleted (the page, 「唔好記住」), the
 * model's verbatim output kept in mem_extractions/{session}.raw_output
 * for the session it came from is replaced by RAW_OUTPUT_CLEARED. The
 * audit fields (status, attempts, prompt_version, counts, dropped,
 * finished_at, excluded_safety_turns) stay. raw_output is still saved
 * at extraction time for debugging failures.
 *
 * T31 (decision 0035, meta/memory_config.layersEnabled, default off):
 * every item belongs to the shared layer (all three companions) or the
 * private layer (only the companion who heard it). Facts in
 * SHARED_LAYER_CATEGORIES that are not sensitive are shared; everything
 * else — sensitive facts, health, events, feelings, stories, grief,
 * every summary and every follow-up — is private. The server writes
 * `layer` and `sourceAgent`; items written before T31 get their layer
 * from the same rule when read (itemLayer). Injection logs count shared
 * and private items separately (the memory dose).
 *
 * Retrieval memory (RAG) is out of scope for v1.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const safetyLexicon = require("./safety_lexicon");
const forget = require("./memory_forget");
const studyPeriod = require("./study_period");

const AGENTS = ["siu_yan", "ah_jan_ah_bak", "tung_tung"];

/** Chat surfaces that receive the memory block. */
// 10/19: m6_suggestions (今日嘅小邀請) only reaches here when the App's
// suggestionsUseProfileEnabled switch is on — off, it sends no agentId.
// 1020e 二.7 (2): the Hybrid action plan's two calls (m7_action_loop_
// summary / _followup) likewise, only with the App's
// actionPlanMemoryEnabled switch on (off: no agentId → nothing here).
const INJECT_MODULES = new RegExp(
    "^(m2_check_in|reflective_dialogue|tung_tung_chat|m3_reminiscence_w\\d+" +
    "|greeting_(siu_yan|ah_jan_ah_bak|tung_tung)|m6_suggestions" +
    "|m7_action_loop_(summary|followup))$");

/**
 * 1020e 二.7 (2): surfaces that get the memory block but are not a chat,
 * so a due follow-up is neither shown nor marked asked there (it stays
 * 小欣's to ask in a real chat).  Same reasoning as 1020c for
 * m6_suggestions, which the sessionStart line below already covers.
 */
const NO_FOLLOWUP_MODULES =
    /^(m6_suggestions|m7_action_loop_(summary|followup))$/;

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

/**
 * T31 (decision 0035): categories in the shared layer when layersEnabled
 * is on — 稱呼, 家人和身邊的人, 居住情況和日常作息, 喜好和興趣. Every other
 * category (health, event and the v3 categories feeling / story / grief)
 * is private, and so is anything classified sensitive.
 */
const SHARED_LAYER_CATEGORIES = new Set([
  "name", "family", "living", "routine", "hobby", "preference",
]);

/**
 * Extra categories of extraction prompt v3 (T31), all private:
 * 心事和情緒, 回憶故事, 哀傷內容.
 */
const V3_EXTRA_CATEGORIES = [
  "feeling", // 心事和情緒
  "story", // 回憶故事
  "grief", // 哀傷內容
];

/** Categories that are always sensitive, whatever the model says. */
const SENSITIVE_CATEGORIES = new Set(["health"]);

/** Keyword rule layered on the model's own sensitive flag. */
const SENSITIVE_TERMS = [
  "病", "醫", "藥", "痛", "癌", "覆診", "手術", "入院", "過身", "去世", "死",
  "離婚", "嗌交", "吵架", "唔啱", "反面", "錢", "債", "借", "遺囑", "抑鬱",
  "焦慮", "失眠", "孤獨", "寂寞",
  // T10 (decision 0024): the summary is now kept only when none of these
  // match, so the list also covers health, loss and mood words the model
  // wrote into summaries in the T10 runs. Adding a word only ever makes
  // more items wait for confirmation (facts) or drops a summary.
  "中風", "輪椅", "拐杖", "治療", "眼矇", "睇唔清", "白內障", "耳聾",
  "聽唔清", "瞓唔着", "瞓唔著", "瞓唔到", "跌親", "骨折", "血壓", "糖尿",
  "心臟", "腦退化", "失智", "認知障礙", "腳唔好", "行唔到", "過咗身",
  "過世", "離世", "走咗", "骨灰", "喪禮", "拜祭", "忌日", "喊", "唔開心",
  "好攰", "蝕", "欠",
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
  // T10: confirmed sensitive facts keep this many places even when the
  // 20 ordinary places are full (sensitiveFactQuota).
  sensitiveFacts: 5,
  summaryDays: 3,
  summaryChars: 150,
  followupExpireDays: 7,
  maxAttempts: 3,
  revisionReview: 3, // this many revisions of one fact → researcher review
};

/**
 * Companion names: a "name" fact must be the user's own form of address
 * (T16: 「陪伴者叫阿珍」 was stored as the user's name and shared).
 */
const COMPANION_NAMES = ["陪伴者", "小欣", "阿珍", "阿伯", "通通"];

/** Extraction prompt files (functions/prompts/<name>.txt). */
const EXTRACTION_PROMPTS = [
  "memory_extraction.v1", "memory_extraction.v2", "memory_extraction.v3",
];
const DEFAULT_EXTRACTION_PROMPT = "memory_extraction.v2";
/** T33: v2 carries the final text S2 (docs/spec/copy/short-texts.md). */
const FORGET_ACK_PROMPT = "memory_forget_ack.v2";
/** A prompt file still holding this is a draft and is never used. */
const DRAFT_MARK = "【待研究側定稿】";

/** Category order when facts must be trimmed. */
const CATEGORY_PRIORITY = [
  "name", "family", "living", "routine", "hobby", "event", "story",
  "preference", "feeling", "grief", "health",
];

/**
 * The categories an extraction prompt may use. v1 and v2 keep the
 * original eight, so their prompt text and validation are unchanged.
 * @param {string} promptName
 * @return {Array<string>}
 */
function categoriesFor(promptName) {
  return promptName === "memory_extraction.v3" ?
    CATEGORIES.concat(V3_EXTRA_CATEGORIES) : CATEGORIES;
}

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

/**
 * T31: the layer a fact belongs to. Sensitive content is private even in
 * a shared category.
 * @param {string} category
 * @param {string} sensitivity normal | sensitive
 * @return {string} shared | private
 */
function layerFor(category, sensitivity) {
  if ((sensitivity || "normal") !== "normal") return "private";
  return SHARED_LAYER_CATEGORIES.has(category) ? "shared" : "private";
}

/**
 * T31: the layer of a stored item. Summaries and follow-ups are always
 * private. A fact without `layer` (written before T31) gets it from
 * layerFor; a stored layer never makes a sensitive fact shared.
 * @param {object} item a mem_* doc
 * @param {string} kind fact | summary | followup
 * @return {string} shared | private
 */
function itemLayer(item, kind) {
  if (kind !== "fact") return "private";
  if ((item.sensitivity || "normal") !== "normal") return "private";
  if (item.layer === "shared" || item.layer === "private") return item.layer;
  return layerFor(item.category, item.sensitivity);
}

/**
 * T31: the companion who heard an item (`sourceAgent`, or `agent_id` for
 * items written before T31).
 * @param {object} item
 * @return {string}
 */
function itemSource(item) {
  return item.sourceAgent || item.agent_id;
}

/**
 * T31: may this agent use the item? Its own items always; another
 * agent's only when the item is in the shared layer and sharing is on
 * (policy B — sharedContextUse consent off, decision 0020 — shares
 * nothing). With layers on, policies A and C both mean "the layer rule".
 * @param {object} item
 * @param {string} kind fact | summary | followup
 * @param {string} agentId
 * @param {string} policy A | B | C
 * @return {boolean}
 */
function visibleInLayers(item, kind, agentId, policy) {
  if (itemSource(item) === agentId) return true;
  if (policy === "B") return false;
  return itemLayer(item, kind) === "shared";
}

// ---------------------------------------------------------------------------
// Extraction: prompt + validation
// ---------------------------------------------------------------------------

const _promptFiles = {};

/**
 * A prompt file from functions/prompts/, read once and cached.
 * @param {string} name e.g. memory_extraction.v2
 * @return {string} the file without its final newline
 */
function loadPromptFile(name) {
  if (_promptFiles[name] === undefined) {
    _promptFiles[name] = fs.readFileSync(
        path.join(__dirname, "prompts", `${name}.txt`), "utf8")
        .replace(/\n$/, "");
  }
  return _promptFiles[name];
}

/**
 * @param {{turns: Array<{fromUser: boolean, text: string}>,
 *   activeFacts: Array<object>, todayKey: string,
 *   promptName: (string|undefined)}} args promptName defaults to
 *   DEFAULT_EXTRACTION_PROMPT
 * @return {{system: string, user: string}}
 */
function buildExtractionPrompt({turns, activeFacts, todayKey, promptName}) {
  const name = EXTRACTION_PROMPTS.includes(promptName) ?
    promptName : DEFAULT_EXTRACTION_PROMPT;
  const system = loadPromptFile(name)
      .split("{{TODAY}}").join(todayKey)
      .split("{{WEEKDAY}}").join(weekdayZh(todayKey))
      .split("{{CATEGORIES}}").join(categoriesFor(name).join(", "));

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
 * T10 options in ctx (all off when absent, so old callers are unchanged):
 *   strictFacts      a "name" fact naming a companion is dropped; an
 *                    update must target a fact of the same category,
 *                    otherwise it is kept as an add (activeFactCategories)
 *   excludeSafety    no summary when the session had turns the App
 *                    lexicon flags (safetyTurns > 0) or the model set
 *                    safety_concern; with safety_concern, sensitive facts
 *                    and follow-ups are dropped too; a summary the App
 *                    lexicon flags is dropped
 *   omitSensitiveSummary  a summary classified sensitive is not kept
 *   categories       allowed categories (default CATEGORIES; v3 adds more,
 *                    see categoriesFor)
 *
 * @param {object} raw parsed JSON from the model
 * @param {{turns: Array<{fromUser: boolean, text: string}>,
 *   activeFactIds: Set<string>, todayKey: string,
 *   activeFactCategories: (Map<string, string>|undefined),
 *   strictFacts: (boolean|undefined), excludeSafety: (boolean|undefined),
 *   safetyTurns: (number|undefined),
 *   omitSensitiveSummary: (boolean|undefined),
 *   categories: (Array<string>|undefined)}} ctx
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
  const safetyConcern = ctx.excludeSafety === true &&
    raw.safety_concern === true;

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
    if (!(ctx.categories || CATEGORIES).includes(f.category)) {
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
    if (safetyConcern && sensitivity !== "normal") {
      dropped.push({kind: "fact", reason: "safety_concern", item: {}});
      continue;
    }
    if (ctx.strictFacts === true && f.category === "name" &&
        COMPANION_NAMES.some((n) => `${f.key}${f.value}`.includes(n))) {
      dropped.push({kind: "fact", reason: "companion_name", item: f});
      continue;
    }
    let replaces = f.op === "update" && ctx.activeFactIds.has(f.fact_id) ?
      f.fact_id : null;
    // T4: 「我喺香港出世」 replaced the user's name. Only like for like.
    if (replaces && ctx.strictFacts === true && ctx.activeFactCategories &&
        ctx.activeFactCategories.get(replaces) !== f.category) {
      replaces = null;
    }
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
    const fuSensitivity = classifySensitivity("event",
        APPOINTMENT_TERMS.reduce((t, w) => t.split(w).join(""), text),
        false);
    if (safetyConcern && fuSensitivity !== "normal") {
      dropped.push({kind: "followup", reason: "safety_concern", item: {}});
      continue;
    }
    outFollowups.push({
      description: u.description.trim().slice(0, 120),
      due_date: u.due_date,
      quote: u.quote.trim().slice(0, 200),
      sensitivity: fuSensitivity,
    });
  }

  // T4 #6: a dated plan was stored twice, as a follow-up and as a fact
  // whose value ("下個禮拜四……") goes stale. Keep only the follow-up.
  if (ctx.strictFacts === true) {
    const fuQuotes = outFollowups.map((u) => normalize(u.quote));
    for (let i = outFacts.length - 1; i >= 0; i--) {
      const q = normalize(outFacts[i].quote);
      // Same words: one quote holds the other and is not much longer.
      const same = (u) => (u.includes(q) || q.includes(u)) &&
        Math.min(u.length, q.length) >= 0.6 * Math.max(u.length, q.length);
      if (fuQuotes.some(same)) {
        dropped.push({kind: "fact", reason: "plan_is_followup",
          item: outFacts[i]});
        outFacts.splice(i, 1);
      }
    }
  }

  let cleanSummary = hitsSafety(summary) ? "" :
    summary.trim().slice(0, LIMITS.summaryChars);
  let summaryDrop = null;
  if (cleanSummary && ctx.excludeSafety === true) {
    if ((ctx.safetyTurns || 0) > 0) summaryDrop = "safety_turns";
    else if (safetyConcern) summaryDrop = "safety_concern";
    else if (safetyLexicon.isEscalation(cleanSummary)) {
      summaryDrop = "safety_lexicon";
    }
  }
  if (cleanSummary && !summaryDrop && ctx.omitSensitiveSummary === true &&
      classifySensitivity("event", cleanSummary, false) !== "normal") {
    summaryDrop = "sensitive";
  }
  if (summaryDrop) {
    dropped.push({kind: "summary", reason: summaryDrop, item: {}});
    cleanSummary = "";
  }
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
 * T49a: the researcher's intake (source_session_id "intake") writes one
 * copy of a fact per companion.  When another companion's copy is visible
 * too (shared visibility, or the shared layer once layersEnabled is on),
 * the same line would show two or three times; keep one, preferring the
 * companion's own copy.  Facts from conversations are left as they are.
 * @param {Array<object>} facts sorted, visible facts
 * @param {string} agentId
 * @param {boolean} layers
 * @return {Array<object>}
 */
function onceEachIntakeFact(facts, agentId, layers) {
  const own = (f) => (layers ? itemSource(f) : f.agent_id) === agentId;
  const at = new Map();
  const out = [];
  for (const f of facts) {
    if (f.source_session_id !== "intake") {
      out.push(f);
      continue;
    }
    const k = [f.category, f.key, f.value].join("\u0000");
    if (!at.has(k)) {
      at.set(k, out.length);
      out.push(f);
    } else if (own(f) && !own(out[at.get(k)])) {
      out[at.get(k)] = f;
    }
  }
  return out;
}

/**
 * Pick what goes into the block, in priority order, within LIMITS.
 * @param {{facts: Array<object>, summaries: Array<object>,
 *   followups: Array<object>}} mem loaded docs (with id)
 * @param {{agentId: string, policy: string, todayKey: string,
 *   sessionStart: boolean, sensitiveQuota: (boolean|undefined),
 *   omitSensitiveSummary: (boolean|undefined),
 *   layers: (boolean|undefined)}} opts T10:
 *   sensitiveQuota gives confirmed sensitive facts LIMITS.sensitiveFacts
 *   places of their own; omitSensitiveSummary leaves out summaries
 *   classified sensitive (written before the fix). T31: layers filters
 *   by layer (visibleInLayers) instead of the old policy rule
 * @return {{followups: Array<object>, facts: Array<object>,
 *   sensitiveFacts: Array<object>, summaryDays: Array<object>}}
 */
function selectForInjection(mem, opts) {
  const {agentId, policy, todayKey, sessionStart} = opts;
  const layers = opts.layers === true;
  const expireBefore = addDays(todayKey, -LIMITS.followupExpireDays);

  const followups = !sessionStart ? [] : mem.followups
      .filter((f) => (layers ? itemSource(f) : f.agent_id) === agentId &&
        f.status === "pending")
      .filter((f) => f.due_date <= todayKey && f.due_date >= expireBefore)
      .filter((f) => (f.sensitivity || "normal") === "normal")
      .sort((a, b) => b.due_date.localeCompare(a.due_date))
      .slice(0, LIMITS.followups);

  const usable = onceEachIntakeFact(mem.facts
      .filter((f) => f.status === "active" && !f.needs_review)
      .filter((f) => (layers ? visibleInLayers(f, "fact", agentId, policy) :
        visibleTo(f, agentId, policy)))
      .sort((a, b) => {
        const pa = CATEGORY_PRIORITY.indexOf(a.category);
        const pb = CATEGORY_PRIORITY.indexOf(b.category);
        if (pa !== pb) return pa - pb;
        return (b.updated_ms || 0) - (a.updated_ms || 0);
      }), agentId, layers);
  const facts = usable.filter((f) => f.sensitivity === "normal")
      .slice(0, LIMITS.facts);
  const sensitivePlaces = Math.max(0, LIMITS.facts - facts.length,
      opts.sensitiveQuota === true ? LIMITS.sensitiveFacts : 0);
  const sensitiveFacts = usable.filter((f) => f.sensitivity === "sensitive")
      .slice(0, sensitivePlaces);

  // Same-day sessions read as one daily entry; only the last few days go in.
  const byDay = new Map();
  // Summaries are agent-private except under policy A.
  for (const s of mem.summaries
      .filter((x) => (layers ?
        visibleInLayers(x, "summary", agentId, policy) :
        visibleTo(x, agentId, policy === "A" ? "A" : "B")))
      .filter((x) => x.summary)
      .filter((x) => opts.omitSensitiveSummary !== true ||
        (x.sensitivity || "normal") === "normal")
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

/**
 * T31 memory dose: how many injected items came from each layer, and from
 * which companion. Counts only what made it into the block after
 * trimming (ids from renderMemoryBlock); a day of summaries counts each
 * summary.
 * @param {object} sel from selectForInjection
 * @param {Array<string>} ids renderMemoryBlock(sel).ids
 * @param {string} agentId the agent the prompt is for
 * @return {{layer_counts: {shared: number, private: number},
 *   source_agents: {shared: object, private: object}}}
 */
function injectionDose(sel, ids, agentId) {
  const meta = new Map();
  const note = (x, kind) => meta.set(x.id,
      {layer: itemLayer(x, kind), source: itemSource(x) || agentId});
  sel.followups.forEach((x) => note(x, "followup"));
  sel.facts.forEach((x) => note(x, "fact"));
  sel.sensitiveFacts.forEach((x) => note(x, "fact"));
  for (const d of sel.summaryDays) {
    for (const id of d.ids) {
      meta.set(id, {layer: "private", source: agentId});
    }
  }
  const out = {
    layer_counts: {shared: 0, private: 0},
    source_agents: {shared: {}, private: {}},
  };
  for (const id of ids) {
    const m = meta.get(id);
    if (!m) continue;
    out.layer_counts[m.layer]++;
    const by = out.source_agents[m.layer];
    by[m.source] = (by[m.source] || 0) + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Firestore I/O
// ---------------------------------------------------------------------------

/**
 * T10 switches in meta/memory_config (decision 0024). Fixes are on unless
 * the field is explicitly false; the elder-facing confirmation reply is
 * off unless explicitly true.
 * @param {object} d meta/memory_config data
 * @return {object}
 */
function t10Flags(d) {
  return {
    excludeSafetyTurns: d.excludeSafetyTurns !== false,
    omitSensitiveSummary: d.omitSensitiveSummary !== false,
    honourForgetRequests: d.honourForgetRequests !== false,
    forgetAckReply: d.forgetAckReply === true,
    deleteSummaryWithItem: d.deleteSummaryWithItem !== false,
    // T49e-4: deleting an item also clears its session's raw_output.
    clearRawOutputOnDelete: d.clearRawOutputOnDelete !== false,
    honourMemoryWithdrawal: d.honourMemoryWithdrawal !== false,
    sensitiveFactQuota: d.sensitiveFactQuota !== false,
    strictFactValidation: d.strictFactValidation !== false,
    // T31 (decision 0035): shared / private layers. Off unless true.
    layersEnabled: d.layersEnabled === true,
    extractionPrompt: EXTRACTION_PROMPTS.includes(d.extractionPrompt) ?
      d.extractionPrompt : DEFAULT_EXTRACTION_PROMPT,
  };
}

/**
 * @param {object} db admin.firestore()
 * @return {Promise<{enabled: boolean, policy: string}>}
 */
async function loadConfig(db) {
  const [snap, appSnap] = await Promise.all([
    db.doc("meta/memory_config").get(),
    db.doc("app_config/phase_a").get(),
  ]);
  const d = snap.exists ? snap.data() : {};
  const app = appSnap.exists ? appSnap.data() : {};
  const policy = ["A", "B", "C"].includes(d.policy) ? d.policy : "C";
  return {
    enabled: d.enabled === true,
    policy,
    phaseBArmA: d.phaseBArmA === true,
    // C20 / decision 0020: same key the App reads (PhaseAConfig); on
    // unless explicitly false.
    enforceSharedContextConsent: app.enforceSharedContextConsent !== false,
    ...t10Flags(d),
  };
}

/**
 * The sharing policy for one user. With app_config/phase_a
 * .enforceSharedContextConsent on (the default), a user whose
 * consent.sharedContextUse is not true gets policy B: each agent sees
 * only its own items (decision 0020). Otherwise the configured policy.
 * @param {{policy: string, enforceSharedContextConsent: boolean}} cfg
 * @param {object} user profile doc data
 * @return {string} A | B | C
 */
function effectivePolicy(cfg, user) {
  if (!cfg.enforceSharedContextConsent) return cfg.policy;
  const consent = (user && user.consent) || {};
  return consent.sharedContextUse === true ? cfg.policy : "B";
}

/**
 * Who memory v1 applies to, given the config and a profile doc's data:
 *   - never Arm B;
 *   - Phase B Arm A (assigned while randomising) when cfg.phaseBArmA —
 *     mandatory, no opt-out; T21: so is a pilot-run account the
 *     researcher set to Arm A (mode pilot_designated); accounts assigned
 *     in force_a mode keep memory v0;
 *   - a tester account (isTester true) in Arm A, like Phase B Arm A —
 *     the tester arm switch (functions/tester_arm.js); Arm B never;
 *   - anyone else who opted in (testers on a MEMORY_V1 build).
 * The kill switch (cfg.enabled) overrides everything. With
 * cfg.honourMemoryWithdrawal (T10, default on), a user whose memory was
 * withdrawn or deleted by tool/delete_memory.js (memoryWithdrawnAt set,
 * server-only field) is out of scope too, Phase B Arm A included.
 * @param {{enabled: boolean, phaseBArmA: boolean,
 *   honourMemoryWithdrawal: (boolean|undefined)}} cfg
 * @param {object} user profile doc data
 * @return {boolean}
 */
function inScope(cfg, user) {
  if (!cfg.enabled || !user) return false;
  if (user.arm === "B") return false;
  if (cfg.honourMemoryWithdrawal !== false && user.memoryWithdrawnAt) {
    return false;
  }
  if (cfg.phaseBArmA && user.arm === "A" &&
      studyPeriod.PHASE_B_MODES.indexOf(user.armAssignmentMode) >= 0) {
    return true;
  }
  // Tester self-switch (functions/tester_arm.js): a tester account in
  // Arm A gets memory exactly like Phase B Arm A, whatever its mode.
  if (cfg.phaseBArmA && user.arm === "A" && user.isTester === true) {
    return true;
  }
  return user.memory_enabled === true;
}

/**
 * @param {object} db
 * @param {string} uid
 * @return {Promise<?{policy: string, cfg: object}>}
 */
async function memoryActive(db, uid) {
  const cfg = await loadConfig(db);
  if (!cfg.enabled) return null;
  const user = await db.collection("users").doc(uid).get();
  if (!user.exists || !inScope(cfg, user.data())) return null;
  return {policy: effectivePolicy(cfg, user.data()), cfg};
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
 * forgetAckReply (default off): when the user's latest message asks the
 * companion not to remember, a one-line instruction to confirm it with
 * S2. A file still holding DRAFT_MARK is never used.
 * @param {Array<object>} messages the chat so far
 * @return {string} "" or the instruction
 */
function forgetAck(messages) {
  const users = (messages || []).filter((m) => m && m.role === "user");
  const last = users.length ? users[users.length - 1] : null;
  if (!last || !forget.detectForget(String(last.content || ""))) return "";
  let text = "";
  try {
    text = loadPromptFile(FORGET_ACK_PROMPT);
  } catch (_) {
    return "";
  }
  return text.includes(DRAFT_MARK) ? "" : text;
}

/**
 * Build the memory block for one proxyDeepSeek call, mark an injected
 * follow-up as asked, and log the injection. Returns "" when memory is
 * off for this user/module. Never throws: memory must not break a chat.
 *
 * T31: with layersEnabled the selection follows the layers and the log
 * also records the dose (layer_counts, source_agents) and session_id.
 *
 * @param {object} db
 * @param {{uid: string, agentId: ?string, moduleId: string,
 *   messages: Array<object>, now: (Date|undefined),
 *   sessionId: (?string|undefined)}} args sessionId: the App's session
 *   id when it sends one (T25), else null in the log
 * @return {Promise<string>}
 */
async function injectMemory(db,
    {uid, agentId, moduleId, messages, now, sessionId}) {
  try {
    if (!uid || !AGENTS.includes(agentId)) return "";
    if (!INJECT_MODULES.test(moduleId)) return "";
    const active = await memoryActive(db, uid);
    if (!active) return "";

    const todayKey = hkDateKey(now || new Date());
    const userTurns = messages.filter((m) => m.role === "user").length;
    // Follow-ups go in on the first user turn of a real chat only: a
    // pre-generated greeting may never be seen, so it must not use one up.
    // 1020c: nor may 今日嘅小邀請 (m6_suggestions) — it is not a chat, and
    // marking the follow-up asked there would stop 小欣 asking it.
    const sessionStart = userTurns <= 1 &&
      !moduleId.startsWith("greeting_") && moduleId !== "m6_suggestions";
    const mem = await loadMemory(db, uid);
    const sel = selectForInjection(mem, {
      agentId, policy: active.policy, todayKey,
      // 1020e: nor the action plan's two calls (NO_FOLLOWUP_MODULES).
      sessionStart: sessionStart && !NO_FOLLOWUP_MODULES.test(moduleId),
      sensitiveQuota: active.cfg.sensitiveFactQuota,
      omitSensitiveSummary: active.cfg.omitSensitiveSummary,
      layers: active.cfg.layersEnabled,
    });
    const block = renderMemoryBlock(sel);
    const ack = active.cfg.forgetAckReply ? forgetAck(messages) : "";
    if (!block.text) return ack;

    const u = db.collection("users").doc(uid);
    const batch = db.batch();
    const shownFollowups = sel.followups.slice(0, block.layers.followup);
    for (const f of shownFollowups) {
      batch.update(u.collection("mem_followups").doc(f.id), {
        status: "asked",
        asked_at: new Date(),
      });
    }
    const log = {
      agent_id: agentId,
      module_id: moduleId,
      memory_ids: block.ids,
      layers: block.layers,
      policy: active.policy,
      chars: block.text.length,
      created_at: new Date(),
    };
    if (active.cfg.layersEnabled) {
      Object.assign(log, injectionDose(sel, block.ids, agentId), {
        layers_enabled: true,
        session_id: typeof sessionId === "string" && sessionId ?
          sessionId.slice(0, 128) : null,
      });
    }
    batch.set(u.collection("mem_injections").doc(), log);
    await batch.commit();
    return ack ? `${block.text}\n${ack}` : block.text;
  } catch (err) {
    console.error("memory injection failed", {uid, agentId, err: String(err)});
    return "";
  }
}

/**
 * T10: what may go to the extractor. A user turn the App lexicon flags
 * (moderate or acute, the same rule that keeps it out of the App's
 * buffer) is removed with the companion's replies to it. A request not
 * to remember is reported, not removed: the caller drops the session.
 * @param {Array<{fromUser: boolean, text: string}>} turns
 * @param {{excludeSafety: boolean, forget: boolean}} opts
 * @return {{turns: Array<object>, safetyTurns: number,
 *   forget: ?{index: number, label: string, phrase: string}}}
 */
function screenTurns(turns, opts) {
  const out = [];
  let safetyTurns = 0;
  let skipReplies = false;
  let found = null;
  for (const t of turns) {
    if (!t.fromUser) {
      if (!skipReplies) out.push(t);
      continue;
    }
    skipReplies = false;
    if (opts.excludeSafety && safetyLexicon.isEscalation(t.text)) {
      safetyTurns++;
      skipReplies = true;
      continue;
    }
    if (opts.forget && !found) {
      const hit = forget.detectForget(t.text);
      if (hit) {
        found = {index: out.length, label: hit.label, phrase: hit.phrase};
      }
    }
    out.push(t);
  }
  return {turns: out, safetyTurns, forget: found};
}

/**
 * Atomically move an agent's short-term buffer into a pending
 * mem_extractions doc. Returns its id, or null when there is nothing to
 * extract. A second concurrent claim sees an empty buffer, so one session
 * is extracted once (MEM-3). With excludeSafetyTurns (T10), turns the
 * App lexicon flags are never copied into mem_extractions.
 *
 * @param {object} db
 * @param {string} uid
 * @param {string} agentId
 * @return {Promise<?string>}
 */
async function claimBuffer(db, uid, agentId) {
  const cfg = await loadConfig(db);
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
    const screened = screenTurns(turns,
        {excludeSafety: cfg.excludeSafetyTurns, forget: false});
    tx.set(extRef, {
      agent_id: agentId,
      turns: screened.turns,
      screened_safety_turns: screened.safetyTurns,
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
  const todayKey = hkDateKey(now || new Date());
  let rawText = "";
  try {
    // The extractor sees what this agent may see: policy C, or B when
    // sharedContextUse consent is enforced and off (decision 0020).
    const [cfg, userSnap] = await Promise.all([loadConfig(db), u.get()]);
    const policy = effectivePolicy({...cfg, policy: "C"},
        userSnap.exists ? userSnap.data() : null);

    // T10: screen the elder's words before anything reaches the model.
    const screened = screenTurns(data.turns || [], {
      excludeSafety: cfg.excludeSafetyTurns,
      forget: cfg.honourForgetRequests,
    });
    const turns = screened.turns;
    const safetyTurns = screened.safetyTurns +
      (data.screened_safety_turns || 0);
    if (screened.forget) {
      const deleted = await forgetRelated(db, uid, turns, screened.forget,
          cfg.deleteSummaryWithItem, cfg.clearRawOutputOnDelete);
      await extRef.update({
        status: "done",
        outcome: "forget_request",
        forget: {label: screened.forget.label, deleted,
          lexicon: forget.FORGET_LEXICON_VERSION},
        attempts: (data.attempts || 0) + 1,
        excluded_safety_turns: safetyTurns,
        counts: {facts: 0, followups: 0, summary: 0},
        turns: [],
        finished_at: now || new Date(),
      });
      return "done";
    }
    if (!turns.some((t) => t.fromUser)) {
      await extRef.update({
        status: "done",
        outcome: "nothing_left",
        attempts: (data.attempts || 0) + 1,
        excluded_safety_turns: safetyTurns,
        counts: {facts: 0, followups: 0, summary: 0},
        turns: [],
        finished_at: now || new Date(),
      });
      return "done";
    }

    // T31: with layers on, the extractor sees what injection would show
    // this agent: its own facts and the shared layer.
    const layers = cfg.layersEnabled;
    const canSee = (f) => (layers ?
      visibleInLayers(f, "fact", agentId, policy) :
      visibleTo(f, agentId, policy));
    const existing = await u.collection("mem_facts")
        .where("status", "==", "active").get();
    const activeFacts = existing.docs
        .map((d) => ({id: d.id, ...d.data()}))
        .filter(canSee);
    const prompt = buildExtractionPrompt({turns, activeFacts, todayKey,
      promptName: cfg.extractionPrompt});
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
      activeFactCategories:
        new Map(activeFacts.map((f) => [f.id, f.category])),
      strictFacts: cfg.strictFactValidation,
      excludeSafety: cfg.excludeSafetyTurns,
      safetyTurns,
      omitSensitiveSummary: cfg.omitSensitiveSummary,
      categories: categoriesFor(cfg.extractionPrompt),
    });
    if (!v.ok) throw new Error(`schema:${v.error}`);
    // T31: layer and source companion, written by the server only.
    const layerFields = (layer) => (layers ?
      {layer, sourceAgent: agentId} : {});

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
        ...layerFields("private"),
      });
    }

    for (const f of v.facts) {
      // An "add" for a key the agent can already see is an update of it.
      let old = f.replaces ? byId.get(f.replaces) : null;
      if (!old) {
        old = existing.docs.find((d) =>
          d.get("category") === f.category && d.get("key") === f.key &&
          canSee({id: d.id, ...d.data()})) || null;
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
        ...layerFields(layerFor(f.category, f.sensitivity)),
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
        ...layerFields("private"),
      });
    }

    batch.update(extRef, {
      status: "done",
      attempts: (data.attempts || 0) + 1,
      prompt_version: cfg.extractionPrompt,
      excluded_safety_turns: safetyTurns,
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

/**
 * 「唔好記住」 (T10): delete stored items, from any companion and any
 * earlier session, that look like what the request is about (shared
 * two-character pieces, memory_forget.relatedTo). With
 * deleteSummaryWithItem, the summary of a deleted item's session goes too.
 * T49e-4: with clearRaw, the raw_output of every session a deleted item
 * came from is cleared (clearRawOutputs). The current session never
 * called the model, so it has no raw_output to clear.
 * @param {object} db
 * @param {string} uid
 * @param {Array<{fromUser: boolean, text: string}>} turns screened turns
 * @param {{index: number, phrase: string}} hit from screenTurns
 * @param {boolean} withSummary
 * @param {boolean=} clearRaw clearRawOutputOnDelete
 * @return {Promise<{facts: number, followups: number, summaries: number,
 *   raw_outputs: number}>}
 */
async function forgetRelated(db, uid, turns, hit, withSummary, clearRaw) {
  const u = db.collection("users").doc(uid);
  const subject = forget.subjectBigrams(turns, hit.index, hit.phrase);
  const [facts, followups, summaries] = await Promise.all([
    u.collection("mem_facts").get(),
    u.collection("mem_followups").get(),
    u.collection("mem_summaries").get(),
  ]);
  const refs = new Map();
  const sessions = new Set();
  let nFacts = 0;
  let nFollowups = 0;
  for (const d of facts.docs) {
    const x = d.data();
    if (forget.relatedTo(`${x.key} ${x.value} ${x.quote}`, subject)) {
      refs.set(d.ref.path, d.ref);
      nFacts++;
      if (x.source_session_id) sessions.add(x.source_session_id);
    }
  }
  for (const d of followups.docs) {
    const x = d.data();
    if (forget.relatedTo(`${x.description} ${x.quote}`, subject)) {
      refs.set(d.ref.path, d.ref);
      nFollowups++;
      if (x.source_session_id) sessions.add(x.source_session_id);
    }
  }
  const summarySessions = [];
  for (const d of summaries.docs) {
    const x = d.data();
    if (forget.relatedTo(x.summary, subject) ||
        (withSummary && (sessions.has(d.id) ||
          sessions.has(x.source_session_id)))) {
      refs.set(d.ref.path, d.ref);
      // A summary's id is its extraction's id.
      summarySessions.push(d.id, x.source_session_id);
    }
  }
  const all = [...refs.values()];
  for (let i = 0; i < all.length; i += 400) {
    const batch = db.batch();
    for (const r of all.slice(i, i + 400)) batch.delete(r);
    await batch.commit();
  }
  const rawOutputs = clearRaw ?
    await clearRawOutputs(db, uid, [...sessions, ...summarySessions]) : 0;
  return {facts: nFacts, followups: nFollowups,
    summaries: all.length - nFacts - nFollowups, raw_outputs: rawOutputs};
}

/** T49e-4: what raw_output becomes once an item of its session is gone. */
const RAW_OUTPUT_CLEARED = "[cleared after deletion 2026-10-18]";

/**
 * T49e-4: replace the model's verbatim output kept in
 * mem_extractions/{id}.raw_output with RAW_OUTPUT_CLEARED and stamp
 * raw_output_cleared_at. Only that field changes; every audit field stays.
 * Skips sessions with no extraction doc (e.g. "intake", or already wiped
 * by tool/delete_memory.js), with no raw_output, or already cleared.
 * Never creates a doc. The caller checks clearRawOutputOnDelete.
 * @param {object} db
 * @param {string} uid
 * @param {Array<string>} sessionIds extraction ids (duplicates are fine)
 * @param {Date=} now
 * @return {Promise<number>} how many extraction docs were cleared
 */
async function clearRawOutputs(db, uid, sessionIds, now) {
  const ids = [...new Set(sessionIds)].filter((id) =>
    typeof id === "string" && id && !id.includes("/"));
  if (!ids.length) return 0;
  const col = db.collection("users").doc(uid).collection("mem_extractions");
  const snaps = await Promise.all(ids.map((id) => col.doc(id).get()));
  const todo = snaps.filter((s) => {
    const raw = s.exists ? s.get("raw_output") : null;
    return typeof raw === "string" && raw !== "" &&
      raw !== RAW_OUTPUT_CLEARED;
  });
  const stamp = now || new Date();
  const done = await Promise.all(todo.map((s) => s.ref.update({
    raw_output: RAW_OUTPUT_CLEARED,
    raw_output_cleared_at: stamp,
  }).then(() => 1, (err) => {
    // Deleted meanwhile (e.g. tool/delete_memory.js): nothing to clear.
    if (err && err.code === 5) return 0;
    throw err;
  })));
  return done.reduce((a, b) => a + b, 0);
}

/**
 * T49e-4: a summary was deleted on the 「我記得嘅嘢」 page (or by any
 * other path). Clear the raw_output of its extraction (same id). Nothing
 * else is deleted: decision 0024 deletes only that summary.
 * Called by the memorySummaryDeleted trigger in index.js.
 * @param {object} db
 * @param {string} uid
 * @param {string} summaryId the deleted summary's doc id
 * @param {object=} summary the deleted doc's data
 * @param {Date=} now
 * @return {Promise<number>} how many extraction docs were cleared
 */
async function clearRawOutputForSummary(db, uid, summaryId, summary, now) {
  const cfg = await loadConfig(db);
  if (!cfg.clearRawOutputOnDelete) return 0;
  return clearRawOutputs(db, uid,
      [summaryId, summary ? summary.source_session_id : null], now);
}

/** T31: shortest deleted wording that also deletes summaries quoting it. */
const LAYER_DELETE_MIN_CHARS = 4;

/**
 * T31: matchers for "the same thing" as a deleted item, in both layers.
 * @param {object} item the deleted fact or follow-up
 * @return {{fact: function(object): boolean,
 *   followup: function(object): boolean,
 *   summary: function(object): boolean}}
 */
function sameThing(item) {
  const words = normalize(typeof item.value === "string" ? item.value :
    item.description);
  const key = typeof item.key === "string" ? normalize(item.key) : "";
  const sameWords = (t) => words.length >= 2 && normalize(t) === words;
  return {
    fact: (x) => sameWords(x.value) || (key.length >= 2 &&
      x.category === item.category && normalize(x.key) === key),
    followup: (x) => sameWords(x.description),
    summary: (x) => words.length >= LAYER_DELETE_MIN_CHARS &&
      normalize(x.summary).includes(words),
  };
}

/**
 * T10 deleteSummaryWithItem: when a fact or follow-up is deleted (the
 * 「我記得嘅嘢」 page), the same content goes everywhere else too, so it
 * cannot come back another way:
 *   - the summary of the session the item came from;
 *   - other facts / follow-ups with exactly the same wording (the model
 *     sometimes stores one sentence twice, e.g. as "event" and "living").
 * T31 (layersEnabled): "the same thing" in either layer, from any
 * companion, also covers (sameThing):
 *   - facts / follow-ups whose wording matches once spaces and
 *     punctuation are ignored;
 *   - facts of the same category with the same key (each companion keeps
 *     its own private copy of what it heard, e.g. health「膝頭」);
 *   - summaries containing the deleted wording (at least
 *     LAYER_DELETE_MIN_CHARS characters, so a bare name does not wipe
 *     every summary that mentions it).
 * T49e-4 (clearRawOutputOnDelete, independent of deleteSummaryWithItem):
 * the raw_output of the item's session, and of the session of every doc
 * deleted with it, is cleared (clearRawOutputs).
 * Called by the onDocumentDeleted triggers in index.js.
 * @param {object} db
 * @param {string} uid
 * @param {object} item the deleted doc's data
 * @param {Date=} now
 * @return {Promise<number>} how many docs were deleted
 */
async function deleteSummaryForItem(db, uid, item, now) {
  if (!item) return 0;
  const cfg = await loadConfig(db);
  if (!cfg.deleteSummaryWithItem && !cfg.clearRawOutputOnDelete) return 0;
  const u = db.collection("users").doc(uid);
  const reads = [];
  const sessionId = item.source_session_id;
  const docsOf = (q) => q.docs;
  if (cfg.deleteSummaryWithItem) {
    if (sessionId) {
      reads.push(u.collection("mem_summaries").doc(sessionId).get()
          .then((d) => (d.exists ? [d] : [])));
      reads.push(u.collection("mem_summaries")
          .where("source_session_id", "==", sessionId).get().then(docsOf));
    }
    if (typeof item.value === "string" && item.value) {
      reads.push(u.collection("mem_facts").where("value", "==", item.value)
          .get().then(docsOf));
    }
    if (typeof item.description === "string" && item.description) {
      reads.push(u.collection("mem_followups")
          .where("description", "==", item.description).get().then(docsOf));
    }
    if (cfg.layersEnabled) {
      reads.push(Promise.all([
        u.collection("mem_facts").get(),
        u.collection("mem_followups").get(),
        u.collection("mem_summaries").get(),
      ]).then(([facts, followups, summaries]) => {
        const match = sameThing(item);
        return [
          ...facts.docs.filter((d) => match.fact(d.data())),
          ...followups.docs.filter((d) => match.followup(d.data())),
          ...summaries.docs.filter((d) => match.summary(d.data())),
        ];
      }));
    }
  }
  const docs = new Map();
  for (const list of await Promise.all(reads)) {
    for (const d of list) docs.set(d.ref.path, d);
  }
  if (docs.size) {
    const batch = db.batch();
    for (const d of docs.values()) batch.delete(d.ref);
    await batch.commit();
  }
  if (cfg.clearRawOutputOnDelete) {
    // T49e-4: the item's own session, and the session of everything that
    // went with it (a summary's id is its extraction's id).
    const sessions = [sessionId];
    for (const d of docs.values()) {
      sessions.push(d.get("source_session_id"));
      if (d.ref.parent.id === "mem_summaries") sessions.push(d.id);
    }
    await clearRawOutputs(db, uid, sessions, now);
  }
  return docs.size;
}

module.exports = {
  AGENTS,
  CATEGORIES,
  LIMITS,
  INJECT_MODULES,
  NO_FOLLOWUP_MODULES,
  hkDateKey,
  addDays,
  normalize,
  hitsSafety,
  classifySensitivity,
  visibilityFor,
  layerFor,
  itemLayer,
  itemSource,
  visibleInLayers,
  injectionDose,
  sameThing,
  categoriesFor,
  SHARED_LAYER_CATEGORIES,
  V3_EXTRA_CATEGORIES,
  buildExtractionPrompt,
  validateExtraction,
  visibleTo,
  selectForInjection,
  renderMemoryBlock,
  loadConfig,
  inScope,
  effectivePolicy,
  memoryActive,
  loadMemory,
  injectMemory,
  claimBuffer,
  processExtraction,
  screenTurns,
  forgetAck,
  FORGET_ACK_PROMPT,
  forgetRelated,
  deleteSummaryForItem,
  clearRawOutputs,
  clearRawOutputForSummary,
  RAW_OUTPUT_CLEARED,
  t10Flags,
  COMPANION_NAMES,
};
