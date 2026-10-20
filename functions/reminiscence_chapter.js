/**
 * 1020d §6 (1)–(4), (7) — 小篇章 (the weekly reminiscence chapter), server
 * side.  Hybrid arm only; the rule arm builds its chapter in the App from
 * the elder's own words and never reaches an LLM.
 *
 * Request / result doc: users/{uid}/reminiscence_chapters/week_{N}
 * (contract with the App side, see docs/dev-reports/
 * reminiscence-v2-server-20261020.md):
 *   client: weekIndex, source ('hybrid' | 'rule'), status ('requested' for
 *           hybrid, 'ready' for rule), requestId, requestedAt, input
 *           {themeZh, items: [{questionIndex, question, answer, skipped,
 *           followups: [{q, a}], reply}], extras: [{text, reply}]},
 *           rule only ruleText / version, later editedText / editRatio /
 *           savedAt.
 *   server: status 'generating' → 'ready' | 'failed', finalText, version
 *           (+1 per generation), flags, deletedSentences, generatedAt,
 *           failReason.  The archive of every round lives in the
 *           server-only subcollection .../week_{N}/runs/{requestId}.
 *
 * Gates, in this order, before any LLM call (handleChapterWrite):
 *   1. only a doc with source 'hybrid' and status 'requested' is work —
 *      anything else (a rule-arm chapter, the server's own writes, the
 *      elder's edits) returns at once, without a read;
 *   2. app_config/feature_flags.reminiscenceV2Enabled must be literally
 *      true, else status 'failed', failReason 'disabled';
 *   3. users/{uid} is read fresh and checked like assertLlmAllowed in
 *      index.js (study_period.llmRefusal: rule arm, enrolment gate with
 *      the tester exemption), and the arm must be 'A'.  Otherwise status
 *      'failed', failReason 'not_hybrid' (or 'not_enrolled' for the
 *      enrolment gate) and one llm_denied_log row, as the proxy writes;
 *   4. idempotent per requestId: a transaction moves the doc to
 *      'generating' and creates runs/{requestId}; a second event for the
 *      same requestId finds the run and stops.
 *
 * Pipeline (runPipeline): draft with the Pro model, thinking on
 * (prompts/reminiscence_chapter_draft.v1.txt); check with Flash, thinking
 * off (prompts/reminiscence_chapter_check.v1.txt), strict JSON
 * {ok, issues: [{type, quote, suggestion}]}; malformed JSON is retried
 * once, then counts as "not ok"; not ok → Pro rewrites from the issues,
 * Flash checks again, at most maxRewriteRounds (2) times; then sentences
 * still flagged 无出处 / 细节错 are deleted (matched on `quote`, see
 * deleteFlagged) and the rest is delivered with `flags`.
 *
 * Models and limits: meta/reminiscence_config overrides DEFAULTS (server
 * only; clients cannot read meta/*).  Every call goes through
 * llm_log.deepSeekChat (one llm_calls row each, call_type chapter_draft /
 * chapter_check).  Participant text is scrubbed with index.js stripPII
 * before it leaves.  The hotline output filter (meta/safety_config
 * .hotlineOutputFilter) runs on the final text.
 *
 * Push (Hybrid only): 「你嘅第 N 章整理好喇，得閒入嚟睇下。」 (draft copy)
 * to the elder's devices via weekly_schedule.sendToDevices, skipped in
 * quiet hours / 今日休息 — the App shows the ready state anyway.
 */
"use strict";

const admin = require("firebase-admin");
const featureFlags = require("./feature_flags");
const studyPeriod = require("./study_period");
const quietHours = require("./quiet_hours");
const reminders = require("./reminders");
const weeklySchedule = require("./weekly_schedule");
const promptRegistry = require("./prompt_registry");
const llmLog = require("./llm_log");
const hotline = require("./hotline_filter");
const {safetyConfig} = require("./safety_config");

const CHAPTERS = "reminiscence_chapters";
const RUNS = "runs";
const FLAG = "reminiscenceV2Enabled";
const CONFIG_DOC = "meta/reminiscence_config";
const DENIED_LOG = "llm_denied_log";
const ENDPOINT = "reminiscenceChapter";
const AGENT_ID = "ah_jan_ah_bak";
const MODULE_ID = "m3_reminiscence_chapter";
const DOC_ID = /^week_([1-9][0-9]?)$/;

const DRAFT_PROMPT = "reminiscence_chapter_draft.v1";
const CHECK_PROMPT = "reminiscence_chapter_check.v1";

const THINKING_ON = {type: "enabled"};
const THINKING_OFF = {type: "disabled"};

/** Issue types the check may return (1020d §6 (2)(b)), in report order. */
const ISSUE_TYPES = ["无出处", "细节错", "语气不当", "太书面", "太口语", "私隐",
  "敏感"];
/** Style issues: sent back for a rewrite without Flash's suggestion. */
const STYLE_TYPES = ["太书面", "太口语"];
/** Still flagged after the last round → the sentence is deleted. */
const DELETE_TYPES = ["无出处", "细节错"];
/** Flag when the last check gave nothing usable (malformed twice). */
const FLAG_CHECK_FAILED = "核对失败";
/** An issue type outside ISSUE_TYPES is kept under this name. */
const OTHER_TYPE = "其他";

const DEFAULTS = {
  draftModel: "deepseek-v4-pro",
  draftThinking: true,
  // null → not sent, the API default ("high" on 2026-10-19).
  draftReasoningEffort: null,
  // Reasoning tokens count against max_tokens in thinking mode.
  draftMaxTokens: 16000,
  draftTimeoutMs: 180000,
  checkModel: "deepseek-flash",
  checkMaxTokens: 3000,
  checkTimeoutMs: 60000,
  checkTemperature: 0.1,
  maxRewriteRounds: 2,
  checkRetries: 1,
  // An empty Pro answer (everything left in the reasoning) is retried;
  // 10/19 dry run: 5 of 23 short-conversation drafts came back empty.
  draftRetries: 2,
  // Drop a 太口语 issue whose quote has no colloquial grammar character
  // outside 「」 (see screenIssues).
  colloquialFilter: true,
  // The trigger runs for at most 540 s; stop starting new rounds early.
  totalBudgetMs: 480000,
  pushEnabled: true,
  // Draft copy (1020d §6 (1)); {N} = the chapter number.  A value that
  // still carries 【占位】 is never sent.
  pushBody: "你嘅第 {N} 章整理好喇，得閒入嚟睇下。",
};

const MODEL_NAME = /^[a-z0-9][a-z0-9._-]{1,63}$/;
const EFFORTS = ["low", "high", "max"];

// Input limits: a request is the elder's own text, but it still leaves
// the region, so it is bounded.
const MAX_ITEMS = 20;
const MAX_FOLLOWUPS = 4;
const MAX_EXTRAS = 20;
const MAX_FIELD_CHARS = 2000;

/**
 * @param {*} v
 * @param {number} lo
 * @param {number} hi
 * @param {number} dflt
 * @return {number}
 */
function intIn(v, lo, hi, dflt) {
  return (typeof v === "number" && Number.isInteger(v) && v >= lo &&
    v <= hi) ? v : dflt;
}

/**
 * meta/reminiscence_config data → the effective config.  Anything missing
 * or of the wrong type falls back to DEFAULTS.
 * @param {?object} data
 * @return {object}
 */
function configFrom(data) {
  const d = data || {};
  const model = (v, dflt) => (typeof v === "string" && MODEL_NAME.test(v)) ?
    v : dflt;
  return {
    draftModel: model(d.draftModel, DEFAULTS.draftModel),
    draftThinking: typeof d.draftThinking === "boolean" ?
      d.draftThinking : DEFAULTS.draftThinking,
    draftReasoningEffort: EFFORTS.indexOf(d.draftReasoningEffort) >= 0 ?
      d.draftReasoningEffort : DEFAULTS.draftReasoningEffort,
    draftMaxTokens: intIn(d.draftMaxTokens, 500, 64000,
        DEFAULTS.draftMaxTokens),
    draftTimeoutMs: intIn(d.draftTimeoutMs, 10000, 400000,
        DEFAULTS.draftTimeoutMs),
    checkModel: model(d.checkModel, DEFAULTS.checkModel),
    checkMaxTokens: intIn(d.checkMaxTokens, 200, 16000,
        DEFAULTS.checkMaxTokens),
    checkTimeoutMs: intIn(d.checkTimeoutMs, 5000, 200000,
        DEFAULTS.checkTimeoutMs),
    checkTemperature: (typeof d.checkTemperature === "number" &&
      d.checkTemperature >= 0 && d.checkTemperature <= 1) ?
      d.checkTemperature : DEFAULTS.checkTemperature,
    // 1020d §6 (2)(c): at most 2 rewrite rounds.
    maxRewriteRounds: intIn(d.maxRewriteRounds, 0, 2,
        DEFAULTS.maxRewriteRounds),
    checkRetries: intIn(d.checkRetries, 0, 2, DEFAULTS.checkRetries),
    draftRetries: intIn(d.draftRetries, 0, 3, DEFAULTS.draftRetries),
    colloquialFilter: typeof d.colloquialFilter === "boolean" ?
      d.colloquialFilter : DEFAULTS.colloquialFilter,
    totalBudgetMs: intIn(d.totalBudgetMs, 60000, 520000,
        DEFAULTS.totalBudgetMs),
    pushEnabled: typeof d.pushEnabled === "boolean" ?
      d.pushEnabled : DEFAULTS.pushEnabled,
    pushBody: (typeof d.pushBody === "string" && d.pushBody.trim()) ?
      d.pushBody : DEFAULTS.pushBody,
  };
}

/**
 * @param {object} db
 * @return {Promise<object>} the effective config (read errors → DEFAULTS)
 */
async function readConfig(db) {
  try {
    const snap = await db.doc(CONFIG_DOC).get();
    return configFrom(snap.exists ? snap.data() : null);
  } catch (err) {
    console.warn("reminiscence config read failed; using defaults",
        {err: err && err.message});
    return configFrom(null);
  }
}

// ---------------------------------------------------------------------------
// Input → the conversation text the models see
// ---------------------------------------------------------------------------

/**
 * @param {*} v
 * @param {function(string): string} scrub
 * @return {string} trimmed, bounded, scrubbed; "" when not a string
 */
function clean(v, scrub) {
  if (typeof v !== "string") return "";
  const t = v.trim().slice(0, MAX_FIELD_CHARS);
  return t ? scrub(t) : "";
}

/**
 * The request's `input`, validated and scrubbed.  Returns null when the
 * shape is wrong.
 * @param {*} input
 * @param {function(string): string} scrub stripPII
 * @return {?{themeZh: string, items: Array<object>, extras: Array<object>,
 *     answered: number}}
 */
function normaliseInput(input, scrub) {
  if (!input || typeof input !== "object" || !Array.isArray(input.items)) {
    return null;
  }
  const s = typeof scrub === "function" ? scrub : (t) => t;
  const raw = input.items.slice(0, MAX_ITEMS).filter((it) =>
    it && typeof it === "object");
  const base = raw.some((it) => it.questionIndex === 0) ? 1 : 0;
  let answered = 0;
  const items = raw.map((it, i) => {
    const qi = Number.isInteger(it.questionIndex) ? it.questionIndex : i;
    const answer = it.skipped === true ? "" : clean(it.answer, s);
    if (answer) answered++;
    const followups = (Array.isArray(it.followups) ? it.followups : [])
        .slice(0, MAX_FOLLOWUPS)
        .filter((f) => f && typeof f === "object")
        .map((f) => ({q: clean(f.q, s), a: clean(f.a, s)}))
        .filter((f) => f.q || f.a);
    for (const f of followups) if (f.a) answered++;
    return {number: qi + base, question: clean(it.question, s),
      skipped: it.skipped === true, answer, followups};
  }).sort((a, b) => a.number - b.number);
  const extras = (Array.isArray(input.extras) ? input.extras : [])
      .slice(0, MAX_EXTRAS)
      .map((x) => clean(x && x.text, s))
      .filter((t) => t)
      .map((t) => ({text: t}));
  answered += extras.length;
  return {themeZh: clean(input.themeZh, s), items, extras, answered};
}

/**
 * The conversation as the draft and the check see it.  Only the elder's
 * own words count as sources (老人答 / 老人再答 / 老人講); the companion's
 * replies are left out on purpose.
 * @param {{themeZh: string, items: Array<object>, extras: Array<object>}} n
 * @return {string}
 */
function conversationText(n) {
  const lines = [`【本週主題】${n.themeZh || "（未有）"}`, "", "【對話】"];
  for (const it of n.items) {
    lines.push(`第 ${it.number} 題：${it.question || "（題目缺）"}`);
    if (it.skipped) {
      lines.push("（冇答：老人揀咗「唔想講」）");
    } else if (it.answer) {
      lines.push(`老人答：${it.answer}`);
    } else {
      lines.push("（冇答）");
    }
    for (const f of it.followups) {
      if (f.q) lines.push(`追問：${f.q}`);
      lines.push(f.a ? `老人再答：${f.a}` : "（追問冇答）");
    }
    lines.push("");
  }
  if (n.extras.length) {
    lines.push("【再講多啲】");
    for (const x of n.extras) lines.push(`老人講：${x.text}`);
    lines.push("");
  }
  return lines.join("\n").trim();
}

// ---------------------------------------------------------------------------
// Model client
// ---------------------------------------------------------------------------

/**
 * The DeepSeek request body for one pipeline step.  Exported for the tests
 * (functions/test/deepseek_request_test.js): drafts follow the config's
 * thinking switch (on by default); the check is always thinking off.
 * @param {{step: string, model: string, thinking: boolean, system: string,
 *     user: string, maxTokens: number, temperature: (number|undefined),
 *     json: boolean, reasoningEffort: (?string|undefined)}} req
 * @return {object}
 */
function buildRequestBody(req) {
  const thinking = req.step !== "check" && req.thinking === true;
  const body = {
    model: req.model,
    thinking: thinking ? THINKING_ON : THINKING_OFF,
    messages: [
      {role: "system", content: req.system},
      {role: "user", content: req.user},
    ],
    max_tokens: req.maxTokens,
  };
  // Thinking mode ignores temperature (decision 0017), so only send it
  // with thinking off.
  if (!thinking && typeof req.temperature === "number") {
    body.temperature = req.temperature;
  }
  if (thinking && req.reasoningEffort) {
    body.reasoning_effort = req.reasoningEffort;
  }
  if (req.json) body.response_format = {type: "json_object"};
  return body;
}

/**
 * The real model client: one DeepSeek call per step through
 * llm_log.deepSeekChat (llm_calls row).  Throws on a non-2xx status.
 * @param {object} db
 * @param {{apiKey: string, uid: string, headers: (object|undefined),
 *     fetchImpl: (function|undefined)}} o
 * @return {function(object): Promise<{text: string, model: ?string,
 *     usage: object, latencyMs: number, finishReason: ?string}>}
 */
function deepSeekModel(db, o) {
  return async (req) => {
    const started = Date.now();
    const res = await llmLog.deepSeekChat(db, {
      apiKey: o.apiKey,
      headers: o.headers,
      fetchImpl: o.fetchImpl,
      timeoutMs: req.timeoutMs,
      log: {
        callType: req.step === "check" ? "chapter_check" : "chapter_draft",
        agentId: AGENT_ID,
        uid: o.uid,
      },
      body: buildRequestBody(req),
    });
    const latencyMs = Date.now() - started;
    if (!res.ok) {
      const err = new Error(`deepseek ${res.status}`);
      err.status = res.status;
      throw err;
    }
    const data = res.data || {};
    const choice = (data.choices && data.choices[0]) || {};
    const msg = choice.message || {};
    const u = data.usage || {};
    const details = u.completion_tokens_details || {};
    const num = (v) => (typeof v === "number" ? v : null);
    return {
      text: typeof msg.content === "string" ? msg.content : "",
      model: typeof data.model === "string" ? data.model : null,
      usage: {prompt: num(u.prompt_tokens),
        completion: num(u.completion_tokens),
        reasoning: num(details.reasoning_tokens)},
      latencyMs,
      finishReason: typeof choice.finish_reason === "string" ?
        choice.finish_reason : null,
    };
  };
}

// ---------------------------------------------------------------------------
// Check result parsing
// ---------------------------------------------------------------------------

/**
 * Flash's JSON → {ok, issues}, or null when it is not usable (bad JSON,
 * wrong shape, or "not ok" with no issue to act on).  The issues are
 * authoritative: any issue makes the check "not ok".
 * @param {string} text
 * @return {?{ok: boolean, issues: Array<{type: string, quote: string,
 *     suggestion: string}>}}
 */
function parseCheck(text) {
  if (typeof text !== "string") return null;
  let t = text.trim();
  // Tolerate a ```json fence around the object.
  const fence = /^```(?:json)?\s*([\s\S]*?)\s*```$/i.exec(t);
  if (fence) t = fence[1];
  let parsed;
  try {
    parsed = JSON.parse(t);
  } catch (err) {
    return null;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }
  if (typeof parsed.ok !== "boolean" || !Array.isArray(parsed.issues)) {
    return null;
  }
  const issues = [];
  for (const raw of parsed.issues) {
    if (!raw || typeof raw !== "object") return null;
    if (typeof raw.quote !== "string") return null;
    const type = typeof raw.type === "string" &&
      ISSUE_TYPES.indexOf(raw.type.trim()) >= 0 ? raw.type.trim() : OTHER_TYPE;
    issues.push({type, quote: raw.quote.slice(0, 600),
      suggestion: typeof raw.suggestion === "string" ?
        raw.suggestion.slice(0, 600) : ""});
  }
  if (parsed.ok === false && issues.length === 0) return null;
  return {ok: parsed.ok === true && issues.length === 0, issues};
}

/**
 * Colloquial Cantonese GRAMMAR characters (not vocabulary).  The style
 * rule (1020d §6 (3)) keeps the elder's Cantonese words; only a sentence
 * built on these is 太口语.
 */
const COLLOQUIAL_GRAMMAR = ["喺", "嘅", "咗", "佢", "哋", "冇", "嗰", "呢", "啲",
  "唔", "嚟", "咁", "噉"];

/**
 * @param {string} quote
 * @return {string} the quote without the parts inside 「」 / 『』
 */
function outsideQuotes(quote) {
  return String(quote || "").replace(/「[^」]*」/g, "")
      .replace(/『[^』]*』/g, "");
}

/**
 * Code-side guard on Flash's style judgement: a 太口语 issue whose quote
 * has no colloquial grammar character outside quotation marks is dropped
 * (the 10/19 dry run: Flash flagged sentences for keeping words such as
 * 屋企 / 返學 / 食, which the style rule asks to keep).  The dropped issues
 * stay in the archive.
 * @param {{ok: boolean, issues: Array<object>}} parsed
 * @param {{colloquialFilter: boolean}} cfg
 * @return {{result: {ok: boolean, issues: Array<object>},
 *     dropped: Array<object>}}
 */
function screenIssues(parsed, cfg) {
  if (!cfg || cfg.colloquialFilter === false) {
    return {result: parsed, dropped: []};
  }
  const kept = [];
  const dropped = [];
  for (const issue of parsed.issues) {
    const rest = outsideQuotes(issue.quote);
    if (issue.type === "太口语" &&
        !COLLOQUIAL_GRAMMAR.some((ch) => rest.indexOf(ch) >= 0)) {
      dropped.push(issue);
    } else {
      kept.push(issue);
    }
  }
  return {result: {ok: kept.length === 0, issues: kept}, dropped};
}

// ---------------------------------------------------------------------------
// Sentences, and deleting the ones still flagged
// ---------------------------------------------------------------------------

const OPEN_MARKS = "「『“‘（(";
const CLOSE_MARKS = "」』”’）)";
const END_MARKS = "。！？!?";

/**
 * Split one paragraph into sentences.  A sentence ends at 。！？!? outside
 * quotes, or at a closing quote right after one of them; trailing marks
 * and closing quotes stay with the sentence.
 * @param {string} text
 * @return {Array<string>}
 */
function splitSentences(text) {
  const out = [];
  let buf = "";
  let depth = 0;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    buf += ch;
    let end = false;
    if (OPEN_MARKS.indexOf(ch) >= 0) {
      depth++;
    } else if (CLOSE_MARKS.indexOf(ch) >= 0) {
      depth = Math.max(0, depth - 1);
      end = depth === 0 && i > 0 && END_MARKS.indexOf(text[i - 1]) >= 0;
    } else if (END_MARKS.indexOf(ch) >= 0) {
      end = depth === 0;
    }
    if (!end) continue;
    while (i + 1 < text.length && (END_MARKS.indexOf(text[i + 1]) >= 0 ||
      (CLOSE_MARKS.indexOf(text[i + 1]) >= 0 && depth > 0))) {
      i++;
      buf += text[i];
      if (CLOSE_MARKS.indexOf(text[i]) >= 0) depth = Math.max(0, depth - 1);
    }
    out.push(buf);
    buf = "";
  }
  if (buf.trim()) out.push(buf);
  return out.map((s) => s.trim()).filter((s) => s);
}

/**
 * @param {string} text
 * @return {Array<Array<string>>} paragraphs → sentences
 */
function paragraphs(text) {
  return String(text || "").replace(/\r\n/g, "\n").split(/\n\s*\n/)
      .map((p) => splitSentences(p.replace(/\s*\n\s*/g, "")))
      .filter((p) => p.length);
}

/**
 * Letters and digits only (any script): no whitespace, no punctuation.
 * @param {string} s
 * @return {string}
 */
function norm(s) {
  return String(s || "").normalize("NFKC")
      .replace(/[^\p{L}\p{N}]/gu, "");
}

/**
 * @param {string} s normalised
 * @return {Array<string>} character bigrams
 */
function bigrams(s) {
  const out = [];
  for (let i = 0; i + 1 < s.length; i++) out.push(s.slice(i, i + 2));
  return out;
}

/**
 * Dice coefficient on character bigrams (0..1).
 * @param {string} a normalised
 * @param {string} b normalised
 * @return {number}
 */
function dice(a, b) {
  const x = bigrams(a);
  const y = bigrams(b);
  if (!x.length || !y.length) return a && a === b ? 1 : 0;
  const counts = {};
  for (const g of y) counts[g] = (counts[g] || 0) + 1;
  let hit = 0;
  for (const g of x) {
    if (counts[g] > 0) {
      hit++;
      counts[g]--;
    }
  }
  return (2 * hit) / (x.length + y.length);
}

/**
 * Dice coefficient on single characters (0..1): survives several changed
 * characters, e.g. a quote in simplified characters (岁 / 歲).
 * @param {string} a normalised
 * @param {string} b normalised
 * @return {number}
 */
function charDice(a, b) {
  if (!a.length || !b.length) return 0;
  const counts = {};
  for (const ch of b) counts[ch] = (counts[ch] || 0) + 1;
  let hit = 0;
  for (const ch of a) {
    if (counts[ch] > 0) {
      hit++;
      counts[ch]--;
    }
  }
  return (2 * hit) / (a.length + b.length);
}

/** Below this similarity a quote is not taken as naming a sentence. */
const FUZZY_MIN = 0.6;
/** Same, on single characters; only for quotes of 4+ characters. */
const CHAR_FUZZY_MIN = 0.7;
/** A sentence counts as "inside" a multi-sentence quote from this length. */
const CONTAINED_MIN_CHARS = 4;

/**
 * Which sentences one issue's quote names.  In order: the quote is inside
 * a sentence (punctuation and spaces ignored); the quote spans several
 * whole sentences; else the single most similar sentence when it is close
 * enough (bigram Dice ≥ FUZZY_MIN, or single-character Dice ≥
 * CHAR_FUZZY_MIN for quotes of 4+ characters — catches changed
 * characters, e.g. a quote in simplified characters of a traditional
 * draft).
 * @param {Array<{key: string, norm: string}>} sentences
 * @param {string} quote
 * @return {{keys: Array<string>, how: ?string}}
 */
function matchQuote(sentences, quote) {
  const q = norm(quote);
  if (!q) return {keys: [], how: null};
  const inside = sentences.filter((s) => s.norm && s.norm.indexOf(q) >= 0);
  if (inside.length) return {keys: inside.map((s) => s.key), how: "contains"};
  const spanned = sentences.filter((s) =>
    s.norm.length >= CONTAINED_MIN_CHARS && q.indexOf(s.norm) >= 0);
  if (spanned.length) {
    return {keys: spanned.map((s) => s.key), how: "spans"};
  }
  let best = null;
  let bestScore = 0;
  for (const s of sentences) {
    const bi = dice(q, s.norm);
    const uni = q.length >= CONTAINED_MIN_CHARS ? charDice(q, s.norm) : 0;
    // Both scaled so that 1 = "close enough".
    const score = Math.max(bi / FUZZY_MIN, uni / CHAR_FUZZY_MIN);
    if (score > bestScore) {
      best = s;
      bestScore = score;
    }
  }
  if (best && bestScore >= 1) {
    return {keys: [best.key], how: "similar"};
  }
  return {keys: [], how: null};
}

/**
 * 1020d §6 (2)(d): after the last round, delete every sentence still
 * flagged 无出处 or 细节错; the other issues stay and become `flags`.  An
 * issue of any type whose sentence was deleted anyway is resolved.  A
 * delete-type quote that names no sentence is kept as a flag.
 * @param {string} text the last draft
 * @param {?{ok: boolean, issues: Array<object>}} check its check, or null
 *     when the check gave nothing usable
 * @return {{text: string, deleted: Array<{sentence: string, type: string,
 *     quote: string, how: string}>, unmatched: Array<{type: string,
 *     quote: string}>, flags: Array<string>}}
 */
function deleteFlagged(text, check) {
  const paras = paragraphs(text);
  const sentences = [];
  paras.forEach((p, pi) => p.forEach((s, si) => {
    sentences.push({key: `${pi}:${si}`, text: s, norm: norm(s)});
  }));
  const flagSet = {};
  if (!check) {
    return {text: paras.map((p) => p.join("")).join("\n\n"), deleted: [],
      unmatched: [], flags: [FLAG_CHECK_FAILED]};
  }
  const doomed = {};
  const deleted = [];
  const unmatched = [];
  for (const issue of check.issues) {
    if (DELETE_TYPES.indexOf(issue.type) < 0) continue;
    const m = matchQuote(sentences, issue.quote);
    if (!m.keys.length) {
      unmatched.push({type: issue.type, quote: issue.quote});
      flagSet[issue.type] = true;
      continue;
    }
    for (const key of m.keys) {
      if (doomed[key]) continue;
      doomed[key] = true;
      const s = sentences.find((x) => x.key === key);
      deleted.push({sentence: s.text, type: issue.type, quote: issue.quote,
        how: m.how});
    }
  }
  for (const issue of check.issues) {
    if (DELETE_TYPES.indexOf(issue.type) >= 0) continue;
    const m = matchQuote(sentences, issue.quote);
    if (m.keys.length && m.keys.every((k) => doomed[k])) continue;
    flagSet[issue.type] = true;
  }
  const kept = paras.map((p, pi) => p.filter((s, si) => !doomed[`${pi}:${si}`]))
      .filter((p) => p.length)
      .map((p) => p.join(""));
  const order = ISSUE_TYPES.concat([OTHER_TYPE, FLAG_CHECK_FAILED]);
  return {
    text: kept.join("\n\n"),
    deleted,
    unmatched,
    flags: order.filter((t) => flagSet[t]),
  };
}

// ---------------------------------------------------------------------------
// The pipeline (pure apart from the model calls)
// ---------------------------------------------------------------------------

/**
 * @param {string} key prompt file key
 * @return {string}
 */
function promptText(key) {
  const t = promptRegistry.loadPrompt(key);
  if (!t) throw new Error(`prompt missing: ${key}`);
  return t;
}

/**
 * @param {string} conversation
 * @param {string} previous
 * @param {?{issues: Array<object>}} check null = the check was unusable
 * @return {string}
 */
function rewriteMessage(conversation, previous, check) {
  // Style issues go back without Flash's suggestion: in the 10/19 dry run
  // its 太口语 suggestions swapped the elder's Cantonese words for
  // Mandarin ones (屋企 → 家裏, 食 → 吃) and Pro copied them.  Pro fixes
  // style from its own 語體 rules.
  const opinion = check ?
    JSON.stringify({issues: check.issues.map((i) =>
      STYLE_TYPES.indexOf(i.type) >= 0 ? {type: i.type, quote: i.quote} :
        {type: i.type, quote: i.quote, suggestion: i.suggestion})},
    null, 0) :
    "（核對冇結果。請你自己再逐句對照【對話】，刪走或者改正冇出處、細節唔啱嘅句子。）";
  return `${conversation}\n\n【上一稿】\n${previous}\n\n【核對意見】\n` +
    `${opinion}\n\n請按【核對意見】改寫【上一稿】，只輸出改好嘅全文。`;
}

/**
 * @param {string} conversation
 * @param {string} draft
 * @return {string}
 */
function checkMessage(conversation, draft) {
  return `${conversation}\n\n【初稿】\n${draft}\n\n` +
    "請逐句核對【初稿】，只輸出 json。";
}

/**
 * @param {object} r model result
 * @return {object} archive form of one call
 */
function callRecord(r) {
  const u = r.usage || {};
  const num = (v) => (typeof v === "number" ? v : null);
  // Firestore refuses `undefined`: every field is a value or null.
  return {model: typeof r.model === "string" ? r.model : null,
    latencyMs: num(r.latencyMs),
    usage: {prompt: num(u.prompt), completion: num(u.completion),
      reasoning: num(u.reasoning)},
    finishReason: typeof r.finishReason === "string" ? r.finishReason : null};
}

/**
 * Run draft → check → (rewrite → check) ≤ maxRewriteRounds → delete.
 * @param {{model: function(object): Promise<object>, now: function(): number,
 *     cfg: object}} deps now() in ms
 * @param {{conversation: string}} input
 * @return {Promise<object>} {text, flags, deleted, unmatched, rounds,
 *     stoppedBy, promptVersions}
 */
async function runPipeline(deps, input) {
  const cfg = deps.cfg || configFrom(null);
  const now = deps.now || (() => Date.now());
  const deadline = now() + cfg.totalBudgetMs;
  const draftSystem = promptText(DRAFT_PROMPT);
  const checkSystem = promptText(CHECK_PROMPT);
  const remaining = () => deadline - now();
  const slot = (wanted) => Math.max(1000, Math.min(wanted, remaining() - 2000));

  // In thinking mode the Pro model now and then puts the whole answer in
  // its reasoning and returns empty content (seen in the 10/19 dry run);
  // an empty draft is asked for again, up to draftRetries times.
  const callDraft = async (step, user) => {
    let emptyAttempts = 0;
    for (;;) {
      const r = await deps.model({step, model: cfg.draftModel,
        thinking: cfg.draftThinking,
        reasoningEffort: cfg.draftReasoningEffort,
        system: draftSystem, user, maxTokens: cfg.draftMaxTokens,
        timeoutMs: slot(cfg.draftTimeoutMs), json: false});
      const text = String(r.text || "").trim();
      if (text) {
        return Object.assign({text}, callRecord(r), {emptyAttempts});
      }
      emptyAttempts++;
      if (emptyAttempts > cfg.draftRetries || remaining() < 30000) {
        const err = new Error("empty_draft");
        err.code = "empty_draft";
        err.call = callRecord(r);
        throw err;
      }
    }
  };

  const callCheck = async (draftText) => {
    const attempts = [];
    for (let a = 0; a <= cfg.checkRetries; a++) {
      if (a > 0 && remaining() < 10000) break;
      let r = null;
      let parsed = null;
      let error = null;
      try {
        r = await deps.model({step: "check", model: cfg.checkModel,
          thinking: false, system: checkSystem,
          user: checkMessage(input.conversation, draftText),
          maxTokens: cfg.checkMaxTokens, temperature: cfg.checkTemperature,
          timeoutMs: slot(cfg.checkTimeoutMs), json: true});
        parsed = parseCheck(r.text);
      } catch (err) {
        error = String((err && err.message) || err).slice(0, 200);
      }
      const rec = r ? callRecord(r) : {model: null, latencyMs: null,
        usage: null, finishReason: null};
      rec.usable = parsed !== null;
      if (error) rec.error = error;
      if (r && parsed === null) rec.raw = String(r.text || "").slice(0, 2000);
      let screened = null;
      if (parsed) {
        screened = screenIssues(parsed, cfg);
        if (screened.dropped.length) rec.droppedIssues = screened.dropped;
      }
      attempts.push(rec);
      if (screened) return {result: screened.result, attempts};
    }
    return {result: null, attempts};
  };

  const rounds = [];
  const first = await callDraft("draft", input.conversation);
  let current = first;
  let checked = await callCheck(current.text);
  rounds.push({round: 0, kind: "draft", draft: first,
    check: {ok: checked.result ? checked.result.ok : false,
      usable: checked.result !== null,
      issues: checked.result ? checked.result.issues : [],
      attempts: checked.attempts}});
  let stoppedBy = checked.result && checked.result.ok ? "passed" : null;
  let roundError = null;

  for (let r = 1; !stoppedBy && r <= cfg.maxRewriteRounds; r++) {
    // A rewrite round needs a Pro call and a Flash call; do not start one
    // that cannot finish inside the trigger's time.
    if (remaining() < 60000) {
      stoppedBy = "budget";
      break;
    }
    let next;
    let nextCheck;
    try {
      next = await callDraft("rewrite", rewriteMessage(input.conversation,
          current.text, checked.result));
      nextCheck = await callCheck(next.text);
    } catch (err) {
      roundError = String((err && err.message) || err).slice(0, 200);
      stoppedBy = "error";
      break;
    }
    current = next;
    checked = nextCheck;
    rounds.push({round: r, kind: "rewrite", draft: next,
      check: {ok: checked.result ? checked.result.ok : false,
        usable: checked.result !== null,
        issues: checked.result ? checked.result.issues : [],
        attempts: checked.attempts}});
    if (checked.result && checked.result.ok) stoppedBy = "passed";
  }
  if (!stoppedBy) stoppedBy = "max_rounds";

  const cut = deleteFlagged(current.text, checked.result);
  return {
    text: cut.text,
    flags: cut.flags,
    deleted: cut.deleted,
    unmatched: cut.unmatched,
    rounds,
    stoppedBy,
    roundError,
    promptVersions: {
      draft: promptRegistry.promptVersionFor(DRAFT_PROMPT),
      check: promptRegistry.promptVersionFor(CHECK_PROMPT),
    },
  };
}

// ---------------------------------------------------------------------------
// The trigger's work (Firestore)
// ---------------------------------------------------------------------------

/**
 * Cheap pre-filter: is this write a Hybrid chapter request?  Everything
 * else — a rule-arm chapter, the server's own writes, the elder's edits,
 * a delete — needs no work and no read.
 * @param {?object} after the doc after the write
 * @return {boolean}
 */
function isHybridRequest(after) {
  return !!after && after.source === "hybrid" &&
    after.status === "requested";
}

/**
 * @param {?object} user users/{uid} data
 * @param {boolean} gateOn enrolment gate
 * @return {?string} null = Hybrid and allowed; else the refusal:
 *     "rule_arm" | "not_enrolled" | "no_arm"
 */
function refusalFor(user, gateOn) {
  // Same rule as index.js assertLlmAllowed (study_period.llmRefusal:
  // rule arm; enrolment gate with the tester exemption) …
  const r = studyPeriod.llmRefusal({gateOn, user});
  if (r) return r;
  // … and the chapter is Hybrid-only, so the arm must be A (a missing
  // arm sees the rule-arm App, decision 0004).
  if (!user || user.arm !== "A") return "no_arm";
  return null;
}

/**
 * @param {object} fv FieldValue-like {serverTimestamp(), delete()}
 * @return {object}
 */
function fieldValues(fv) {
  return fv || {
    serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
    delete: () => admin.firestore.FieldValue.delete(),
  };
}

/**
 * Mark the request failed, once, if it is still this request.
 * @param {object} db
 * @param {object} fv
 * @param {object} ref chapter doc ref
 * @param {string} requestId
 * @param {string} reason failReason
 * @param {?object} denied llm_denied_log row to add in the same
 *     transaction (doc id derived from the request → written once)
 * @return {Promise<boolean>} written
 */
async function failRequest(db, fv, ref, requestId, reason, denied) {
  return db.runTransaction(async (tx) => {
    const cur = await tx.get(ref);
    const d = cur.exists ? cur.data() : null;
    if (!d || d.requestId !== requestId ||
        (d.status !== "requested" && d.status !== "generating")) {
      return false;
    }
    tx.update(ref, {status: "failed", failReason: reason,
      failedAt: fv.serverTimestamp()});
    if (denied) {
      tx.set(db.collection(DENIED_LOG).doc(denied.id), denied.row);
    }
    return true;
  });
}

/**
 * Hong Kong quiet hours / 今日休息 / switch / copy → push or not.
 * @param {object} deps
 * @param {object} userSnap users/{uid}
 * @param {number} weekIndex
 * @param {object} cfg
 * @return {Promise<object>} {status, tokens?, delivered?}
 */
async function pushReady(deps, userSnap, weekIndex, cfg) {
  if (!cfg.pushEnabled) return {status: "disabled"};
  if (!deps.messaging) return {status: "no_messaging"};
  const body = cfg.pushBody.split("{N}").join(String(weekIndex));
  if (body.indexOf("【占位】") >= 0) return {status: "blocked_placeholder"};
  const user = userSnap.exists ? (userSnap.data() || {}) : {};
  const at = new Date(deps.now ? deps.now() : Date.now());
  const qcfg = await quietHours.readQuietHoursConfig(deps.db);
  if (quietHours.inQuietHours(user, at, qcfg)) return {status: "quiet_hours"};
  if (reminders.isQuietToday(user.quietTodayActivatedAt, at)) {
    return {status: "quiet_today"};
  }
  const sent = await weeklySchedule.sendToDevices(deps.messaging, userSnap,
      body, "reminiscence_chapter_ready");
  return {status: sent.tokens === 0 ? "no_tokens" :
    (sent.delivered > 0 ? "sent" : "failed"),
  tokens: sent.tokens, delivered: sent.delivered};
}

/**
 * One hotline_filter_log row when numbers were replaced (no text).
 * @param {object} db
 * @param {object} fv
 * @param {string} uid
 * @param {Array<object>} items
 */
async function logHotline(db, fv, uid, items) {
  try {
    const sum = hotline.summarise(items);
    await db.collection("hotline_filter_log").add({
      ts: fv.serverTimestamp(), uid, agent_id: AGENT_ID,
      module_id: MODULE_ID, call_type: "chapter_draft", count: items.length,
      kinds: sum.kinds, approved_count: sum.approved_count,
      unapproved_count: sum.unapproved_count,
      filter_version: hotline.FILTER_VERSION, prompt_rule_version: null,
    });
  } catch (err) {
    console.error("hotline_filter_log write failed:", err.message);
  }
}

/**
 * Handle one write of users/{uid}/reminiscence_chapters/{docId}.
 * @param {{db: object, model: function(object): Promise<object>,
 *     messaging: (object|undefined), stripPII: function(string): string,
 *     now: (function(): number|undefined), fieldValue: (object|undefined),
 *     cfg: (object|undefined)}} deps model is only called for a Hybrid
 *     participant whose request passed every gate
 * @param {{uid: string, docId: string, after: ?object}} ev
 * @return {Promise<{action: string}>} what happened (tests, logs)
 */
async function handleChapterWrite(deps, ev) {
  const after = ev.after;
  if (!isHybridRequest(after)) return {action: "ignored"};
  const db = deps.db;
  const fv = fieldValues(deps.fieldValue);
  const m = DOC_ID.exec(ev.docId || "");
  const ref = db.collection("users").doc(ev.uid).collection(CHAPTERS)
      .doc(ev.docId);
  const requestId = after.requestId;
  if (!m || typeof requestId !== "string" || !requestId ||
      requestId.length > 128 || requestId.indexOf("/") >= 0) {
    if (typeof requestId === "string" && requestId) {
      await failRequest(db, fv, ref, requestId, "bad_request", null);
    }
    return {action: "bad_request"};
  }
  const weekIndex = Number(m[1]);

  // Gate 2: the switch.  Off → failed, no LLM.
  if (!(await featureFlags.isFeatureEnabled(db, FLAG))) {
    await failRequest(db, fv, ref, requestId, "disabled", null);
    return {action: "disabled"};
  }

  // Gate 3: Hybrid only, read fresh (no cache), like assertLlmAllowed.
  const userRef = db.collection("users").doc(ev.uid);
  const userSnap = await userRef.get();
  const user = userSnap.exists ? userSnap.data() : null;
  const gateOn = await studyPeriod.enrollmentGateOn(db);
  const refusal = refusalFor(user, gateOn);
  if (refusal) {
    const row = {uid: ev.uid, endpoint: ENDPOINT, ts: fv.serverTimestamp()};
    // Rule-arm rows as the proxy writes them (no reason, no arm field).
    if (refusal !== "rule_arm") row.reason = refusal;
    const failReason = refusal === "not_enrolled" ? "not_enrolled" :
      "not_hybrid";
    await failRequest(db, fv, ref, requestId, failReason,
        {id: `${ENDPOINT}_${ev.uid}_${weekIndex}_${requestId}`, row});
    return {action: failReason};
  }

  // Gate 4: claim this requestId once.
  const runRef = ref.collection(RUNS).doc(requestId);
  const claimed = await db.runTransaction(async (tx) => {
    const cur = await tx.get(ref);
    const d = cur.exists ? cur.data() : null;
    if (!d || d.status !== "requested" || d.requestId !== requestId ||
        d.source !== "hybrid") {
      return false;
    }
    const run = await tx.get(runRef);
    if (run.exists) return false;
    tx.update(ref, {status: "generating", generationStartedAt:
      fv.serverTimestamp(), failReason: fv.delete()});
    tx.set(runRef, {requestId, weekIndex, state: "running",
      startedAt: fv.serverTimestamp()});
    return true;
  });
  if (!claimed) return {action: "duplicate"};

  try {
    return await generateClaimed(deps, {db, fv, ref, runRef, requestId,
      weekIndex, uid: ev.uid, after, userSnap});
  } catch (err) {
    // Anything unexpected after the claim: never leave the doc in
    // 'generating'.
    console.error("chapter generation crashed",
        {uid: ev.uid, weekIndex, err: String(err && err.message)});
    try {
      await failRequest(db, fv, ref, requestId, "internal_error", null);
      await runRef.set({state: "failed", failReason: "internal_error",
        error: String((err && err.message) || err).slice(0, 300),
        finishedAt: fv.serverTimestamp()}, {merge: true});
    } catch (err2) {
      console.error("chapter failure write failed", err2 && err2.message);
    }
    return {action: "internal_error"};
  }
}

/**
 * The work after a successful claim: input → pipeline → final write →
 * push.  Every failure path marks the request failed with a reason.
 * @param {object} deps as handleChapterWrite
 * @param {{db: object, fv: object, ref: object, runRef: object,
 *     requestId: string, weekIndex: number, uid: string, after: object,
 *     userSnap: object}} c
 * @return {Promise<object>} {action, version?, push?}
 */
async function generateClaimed(deps, c) {
  const {db, fv, ref, runRef, requestId, weekIndex, after, userSnap} = c;
  const ev = {uid: c.uid};
  const cfg = deps.cfg || await readConfig(db);
  const now = deps.now || (() => Date.now());
  const startedMs = now();
  const archiveBase = {
    config: {draftModel: cfg.draftModel, draftThinking: cfg.draftThinking,
      draftReasoningEffort: cfg.draftReasoningEffort,
      checkModel: cfg.checkModel, maxRewriteRounds: cfg.maxRewriteRounds,
      draftRetries: cfg.draftRetries, checkRetries: cfg.checkRetries,
      colloquialFilter: cfg.colloquialFilter},
    promptVersions: {
      draft: promptRegistry.promptVersionFor(DRAFT_PROMPT),
      check: promptRegistry.promptVersionFor(CHECK_PROMPT),
    },
  };

  const input = normaliseInput(after.input, deps.stripPII);
  if (!input || input.answered === 0) {
    const reason = input ? "empty_input" : "bad_input";
    await failRequest(db, fv, ref, requestId, reason, null);
    await runRef.set(Object.assign({}, archiveBase, {state: "failed",
      failReason: reason, rounds: [], finishedAt: fv.serverTimestamp(),
      totalMs: now() - startedMs}), {merge: true});
    return {action: reason};
  }

  let result;
  try {
    result = await runPipeline({model: deps.model, now, cfg},
        {conversation: conversationText(input)});
  } catch (err) {
    const reason = err && err.code === "empty_draft" ? "empty_draft" :
      (err && (err.name === "TimeoutError" || err.name === "AbortError") ?
        "timeout" : "llm_error");
    console.error("chapter generation failed",
        {uid: ev.uid, weekIndex, reason, err: String(err && err.message)});
    await failRequest(db, fv, ref, requestId, reason, null);
    await runRef.set(Object.assign({}, archiveBase, {state: "failed",
      failReason: reason,
      error: String((err && err.message) || err).slice(0, 300),
      rounds: [], finishedAt: fv.serverTimestamp(),
      totalMs: now() - startedMs}), {merge: true});
    return {action: reason};
  }

  let finalText = result.text;
  let hotlineReplaced = 0;
  const safety = await safetyConfig(db);
  if (safety.hotlineOutputFilter && finalText) {
    const filtered = hotline.filterHotlines(finalText);
    if (filtered.count > 0) {
      finalText = filtered.text;
      hotlineReplaced = filtered.count;
      await logHotline(db, fv, ev.uid, filtered.items);
    }
  }

  const archive = Object.assign({}, archiveBase, {
    rounds: result.rounds,
    stoppedBy: result.stoppedBy,
    roundError: result.roundError,
    deleted: result.deleted,
    unmatched: result.unmatched,
    flags: result.flags,
    hotlineReplaced,
    finalChars: finalText.length,
    totalMs: now() - startedMs,
    finishedAt: fv.serverTimestamp(),
  });

  if (!finalText) {
    await failRequest(db, fv, ref, requestId, "nothing_left", null);
    await runRef.set(Object.assign(archive, {state: "failed",
      failReason: "nothing_left"}), {merge: true});
    return {action: "nothing_left"};
  }

  const outcome = await db.runTransaction(async (tx) => {
    const cur = await tx.get(ref);
    const d = cur.exists ? cur.data() : null;
    if (!d || d.requestId !== requestId) {
      tx.set(runRef, Object.assign({}, archive, {state: "superseded"}),
          {merge: true});
      return {state: "superseded"};
    }
    const version = (Number.isInteger(d.version) ? d.version : 0) + 1;
    tx.update(ref, {
      status: "ready",
      finalText,
      version,
      generatedAt: fv.serverTimestamp(),
      flags: result.flags,
      deletedSentences: result.deleted.map((x) => x.sentence),
      failReason: fv.delete(),
    });
    tx.set(runRef, Object.assign({}, archive, {state: "ready", version}),
        {merge: true});
    return {state: "ready", version};
  });
  if (outcome.state !== "ready") return {action: "superseded"};

  let push;
  try {
    push = await pushReady(Object.assign({}, deps, {db}), userSnap,
        weekIndex, cfg);
  } catch (err) {
    push = {status: "error", error: String(err && err.message).slice(0, 200)};
  }
  try {
    await runRef.set({push: Object.assign({at: fv.serverTimestamp()}, push)},
        {merge: true});
  } catch (err) {
    console.error("chapter push record failed", err && err.message);
  }
  return {action: "ready", version: outcome.version, push: push.status};
}

module.exports = {
  CHAPTERS, RUNS, FLAG, CONFIG_DOC, ENDPOINT, AGENT_ID, MODULE_ID,
  DRAFT_PROMPT, CHECK_PROMPT, THINKING_ON, THINKING_OFF, ISSUE_TYPES,
  DELETE_TYPES, STYLE_TYPES, FLAG_CHECK_FAILED, OTHER_TYPE, DEFAULTS,
  configFrom, readConfig, normaliseInput, conversationText,
  buildRequestBody, deepSeekModel, parseCheck, splitSentences, paragraphs,
  COLLOQUIAL_GRAMMAR, outsideQuotes, screenIssues,
  norm, dice, charDice, matchQuote, deleteFlagged, rewriteMessage, checkMessage,
  runPipeline, isHybridRequest, refusalFor, handleChapterWrite, pushReady,
};
