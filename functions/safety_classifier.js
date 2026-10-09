/**
 * T8 — safety-classifier relay (SPEC C13, decision 0025; both arms confirmed
 * by decision 0033).
 *
 * `classifySafety` (index.js) hands participant text to a separate safety
 * classifier (the research team's LoRA model) and returns only a risk
 * level and a score.  Both arms use it — so it is NOT a chat-model call:
 *
 *   - it never goes through proxyDeepSeek and never calls DeepSeek;
 *   - it does not call or loosen assertLlmAllowed (that guard still keeps
 *     Arm B away from every chat-model endpoint);
 *   - the model's answer is reduced to {level, score, modelVersion}; any
 *     text the model sends back is dropped and never reaches the App;
 *   - nothing here changes the conversation.
 *
 * Off unless `meta/safety_config.classifierEnabled` is true and
 * `classifierUrl` is set (safety_config.js).  Every relayed call — and
 * every call refused because the switch is off — writes one
 * `safety_classifier_calls` row (writer "server"), without the text and
 * without the arm.
 *
 * ES2018 (no `??` / `?.`).
 */
"use strict";

const LEVELS = [
  "none", "low", "moderate_review", "moderate_interrupt", "acute",
];
const SOURCES = ["user_input", "form"];

/**
 * A short identifier string, or null.
 * @param {*} v Raw value.
 * @param {number} max Longest allowed length.
 * @return {?string} The value, or null.
 */
function shortString(v, max) {
  return typeof v === "string" && v.length > 0 && v.length <= max ? v : null;
}

/**
 * The model's JSON → {level, score, modelVersion}, or null when it is not
 * a valid answer.  Everything else in the body is ignored.
 * @param {*} body Parsed response body.
 * @return {?{level: string, score: ?number, modelVersion: ?string}}
 */
function parseModelResponse(body) {
  if (!body || typeof body !== "object") return null;
  if (LEVELS.indexOf(body.level) < 0) return null;
  const score = typeof body.score === "number" && isFinite(body.score) &&
    body.score >= 0 && body.score <= 1 ? body.score : null;
  const version = shortString(body.model_version, 64) ||
    shortString(body.modelVersion, 64);
  return {level: body.level, score: score, modelVersion: version};
}

/**
 * POST {text} to the model; never throws.
 * @param {!Object} opts url, text, timeoutMs, token (optional), fetchImpl.
 * @return {Promise<!Object>} {status, level, score, modelVersion,
 *   latencyMs}; status is ok / timeout / error.
 */
async function callModel(opts) {
  const fetchImpl = opts.fetchImpl || fetch;
  const started = Date.now();
  const controller = new AbortController();
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, opts.timeoutMs);
  const headers = {"Content-Type": "application/json"};
  if (opts.token) headers["Authorization"] = `Bearer ${opts.token}`;
  const out = {status: "error", level: null, score: null,
    modelVersion: null, latencyMs: 0};
  try {
    const res = await fetchImpl(opts.url, {
      method: "POST",
      headers: headers,
      body: JSON.stringify({text: opts.text}),
      signal: controller.signal,
    });
    if (res.ok) {
      const parsed = parseModelResponse(await res.json());
      if (parsed) {
        out.status = "ok";
        out.level = parsed.level;
        out.score = parsed.score;
        out.modelVersion = parsed.modelVersion;
      }
    }
  } catch (err) {
    if (timedOut) out.status = "timeout";
  } finally {
    clearTimeout(timer);
  }
  if (timedOut) out.status = "timeout";
  out.latencyMs = Date.now() - started;
  return out;
}

/**
 * The whole `classifySafety` handler, minus onCall (testable directly).
 * @param {!Object} deps db, cfg (safetyConfig result), stripPII, fetchImpl,
 *   token, serverTimestamp.
 * @param {string} uid Caller.
 * @param {!Object} data Callable payload: text, inputPoint, source, turnId.
 * @return {Promise<!Object>} {status, level, score, modelVersion}.
 */
async function classify(deps, uid, data) {
  const cfg = deps.cfg;
  const text = typeof data.text === "string" ? data.text : "";
  const cut = text.length > cfg.classifierMaxChars;
  const row = {
    uid: uid,
    writer: "server",
    input_point: shortString(data.inputPoint, 64),
    source: SOURCES.indexOf(data.source) >= 0 ? data.source : null,
    turn_id: shortString(data.turnId, 64),
    text_length: text.length,
    truncated: cut,
    timeout_ms: cfg.classifierTimeoutMs,
  };
  let result;
  if (!cfg.classifierEnabled || !cfg.classifierUrl) {
    result = {status: "disabled", level: null, score: null,
      modelVersion: null, latencyMs: 0};
  } else if (!text.trim()) {
    result = {status: "error", level: null, score: null,
      modelVersion: null, latencyMs: 0};
  } else {
    const sent = deps.stripPII(cut ? text.slice(0, cfg.classifierMaxChars) :
      text);
    result = await callModel({
      url: cfg.classifierUrl,
      text: sent,
      timeoutMs: cfg.classifierTimeoutMs,
      token: deps.token,
      fetchImpl: deps.fetchImpl,
    });
  }
  row.status = result.status;
  row.level = result.level;
  row.score = result.score;
  row.model_version = result.modelVersion;
  row.latency_ms = result.latencyMs;
  row.ts = deps.serverTimestamp();
  try {
    await deps.db.collection("safety_classifier_calls").add(row);
  } catch (err) {
    console.error("safety_classifier_calls write failed:", err.message);
  }
  return {
    status: result.status,
    level: result.level,
    score: result.score,
    modelVersion: result.modelVersion,
  };
}

module.exports = {LEVELS, parseModelResponse, callModel, classify};
