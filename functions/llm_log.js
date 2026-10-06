/**
 * C04 — model version log.
 *
 * DeepSeek's `deepseek-chat` alias cannot be pinned to a model version, so
 * every call records the `model` field the API actually returned.  One doc
 * per call goes to the top-level `llm_calls` collection (admin-only in
 * firestore.rules), never into a conversation collection.
 *
 * The log holds metadata only: no prompt text, no completion text.
 *
 * Every server-side DeepSeek request goes through deepSeekChat() so no call
 * site can skip the log.  Arm B never reaches this module: the callers'
 * arm guards (assertLlmAllowed, memory inScope) run first.
 */
"use strict";

const admin = require("firebase-admin");

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";
const LLM_CALLS = "llm_calls";

/** call_type values, one per kind of LLM use. */
const CALL_TYPES = [
  "chat", // dialogue generation in a chat module
  "greeting", // agent opening line (greeting_<agent>)
  "session_summary", // end-of-module summary (reminiscence, action loop)
  "weekly_summary", // m9 progress-page weekly narrative
  "article_qa", // 「問下呢篇」 under an education article
  "suggestions", // m6 social-activity suggestions
  "memory_summary", // memory v0 rolling-summary fold (App side)
  "referral_judgement", // cross-referral SURFACE/DEFER/SKIP
  "memory_extraction", // memory v1 summary / facts / follow-ups
];

/**
 * Maps a proxyDeepSeek moduleId to its call_type.
 * @param {?string} moduleId
 * @return {string}
 */
function callTypeForModule(moduleId) {
  const m = typeof moduleId === "string" ? moduleId : "";
  if (m.indexOf("greeting_") === 0) return "greeting";
  if (m === "m9_progress_summary") return "weekly_summary";
  if (m === "rolling_summary_fold") return "memory_summary";
  if (m === "m6_suggestions") return "suggestions";
  if (m.indexOf("m8_education") === 0) return "article_qa";
  if (/_summary$/.test(m)) return "session_summary";
  return "chat";
}

/**
 * Token counts from the OpenAI-style `usage` block, null when absent.
 * `reasoning` is usage.completion_tokens_details.reasoning_tokens: non-zero
 * means thinking mode was on.
 * @param {*} data parsed response body
 * @return {{prompt: ?number, completion: ?number, reasoning: ?number}}
 */
function usageOf(data) {
  const u = (data && data.usage) || {};
  const details = u.completion_tokens_details || {};
  const num = (v) => (typeof v === "number" ? v : null);
  return {
    prompt: num(u.prompt_tokens),
    completion: num(u.completion_tokens),
    reasoning: num(details.reasoning_tokens),
  };
}

/**
 * A string field of the response body, null when absent.
 * @param {*} data parsed response body
 * @param {string} key
 * @return {?string}
 */
function stringField(data, key) {
  return (data && typeof data[key] === "string") ? data[key] : null;
}

/**
 * The `llm_calls` row for one call.  Exported for unit tests.
 * @param {object} p
 * @return {object}
 */
function buildLogRow(p) {
  const usage = usageOf(p.data);
  return {
    ts: admin.firestore.Timestamp.fromMillis(p.startedMs),
    call_type: p.callType,
    agent_id: p.agentId || null,
    uid: p.uid || null,
    model_requested: p.modelRequested || null,
    model_returned: stringField(p.data, "model"),
    // Changes when DeepSeek swaps the model behind the same name.
    system_fingerprint: stringField(p.data, "system_fingerprint"),
    prompt_tokens: usage.prompt,
    completion_tokens: usage.completion,
    reasoning_tokens: usage.reasoning,
    latency_ms: p.latencyMs,
    error: p.error === true,
  };
}

/**
 * POSTs one chat completion to DeepSeek and logs it to `llm_calls`.
 *
 * Network errors and unparseable bodies are logged (error: true) and then
 * rethrown; a non-2xx status is logged and returned so the caller keeps
 * its own error handling.  A failed log write never fails the call.
 *
 * @param {object} db Firestore instance
 * @param {object} opts
 * @param {string} opts.apiKey
 * @param {object} opts.body request body; body.model is the requested model
 * @param {object=} opts.headers extra request headers
 * @param {{callType: string, agentId: ?string, uid: ?string}} opts.log
 * @param {function=} opts.fetchImpl defaults to global fetch
 * @return {Promise<{ok: boolean, status: number, data: *, errorBody: string}>}
 */
async function deepSeekChat(db, opts) {
  const fetchImpl = opts.fetchImpl || fetch;
  const startedMs = Date.now();
  let result = null;
  let thrown = null;
  try {
    const response = await fetchImpl(DEEPSEEK_URL, {
      method: "POST",
      headers: Object.assign({
        "Content-Type": "application/json",
        "Authorization": `Bearer ${opts.apiKey}`,
      }, opts.headers || {}),
      body: JSON.stringify(opts.body),
    });
    if (response.ok) {
      result = {ok: true, status: response.status,
        data: await response.json(), errorBody: ""};
    } else {
      let errorBody = "";
      try {
        errorBody = (await response.text()).slice(0, 400);
      } catch (_) {
        // ignore
      }
      result = {ok: false, status: response.status, data: null, errorBody};
    }
  } catch (err) {
    thrown = err;
  }
  const row = buildLogRow({
    startedMs,
    latencyMs: Date.now() - startedMs,
    callType: opts.log.callType,
    agentId: opts.log.agentId,
    uid: opts.log.uid,
    // Taken from the body actually sent, so a model-name change at the
    // call sites is logged without touching this module.
    modelRequested: opts.body && opts.body.model,
    data: result ? result.data : null,
    error: thrown !== null || !result.ok,
  });
  try {
    await db.collection(LLM_CALLS).add(row);
  } catch (err) {
    console.error("llm_calls write failed", {err: String(err)});
  }
  if (thrown) throw thrown;
  return result;
}

module.exports = {
  CALL_TYPES,
  DEEPSEEK_URL,
  LLM_CALLS,
  buildLogRow,
  callTypeForModule,
  deepSeekChat,
};
