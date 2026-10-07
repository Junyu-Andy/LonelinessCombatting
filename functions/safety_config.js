/**
 * T7 — safety switches, `meta/safety_config` (decision 0018).
 *
 * Written by the research team from the console; clients cannot read or
 * write `meta/`.  A missing doc or key means ON: both behaviours were
 * decided (SPEC C12), the switch exists only so they can be turned off.
 *
 *   hotlinePromptRule   — append prompts/hotline_rule.v<N>.txt to every
 *                         proxyDeepSeek system prompt.
 *   hotlineOutputFilter — replace phone numbers in the reply before it is
 *                         returned, and log each reply that had any.
 *
 * T8 (decision 0025, proposed) — the safety-classifier relay
 * (`classifySafety`).  Unlike the two above, these are OFF unless set:
 *
 *   classifierEnabled   — true to relay text to the classifier.  Default
 *                         false; the App has its own switch too
 *                         (`app_config/phase_a.safetyClassifierEnabled`).
 *   classifierUrl       — the model's HTTP address (kept here, not in the
 *                         App, so it never leaves the server).
 *   classifierTimeoutMs — server wait for the model, default 1200 ms
 *                         (the App gives up at 1500 ms).
 *   classifierMaxChars  — longer text is cut to this length, default 1000.
 *
 * Cached per instance for a minute so a flip takes effect quickly without
 * a read on every call.  ES2018 (no `??` / `?.`).
 */
"use strict";

const TTL_MS = 60 * 1000;
let _cached = null;
let _cachedAt = 0;

/**
 * A whole number in [lo, hi], or [dflt] when [v] is not a number.
 * @param {*} v Raw value.
 * @param {number} dflt Default.
 * @param {number} lo Lowest allowed.
 * @param {number} hi Highest allowed.
 * @return {number} Clamped value.
 */
function clampInt(v, dflt, lo, hi) {
  if (typeof v !== "number" || !isFinite(v)) return dflt;
  return Math.min(hi, Math.max(lo, Math.round(v)));
}

/**
 * Current safety switches.
 * @param {!Object} db Firestore handle.
 * @return {Promise<!Object>} Switches: the T7 two default to on, the T8
 *   classifier ones to off.
 */
async function safetyConfig(db) {
  if (_cached && Date.now() - _cachedAt < TTL_MS) return _cached;
  let data = {};
  try {
    const snap = await db.doc("meta/safety_config").get();
    data = snap.exists ? (snap.data() || {}) : {};
  } catch (err) {
    console.error("safety_config read failed; using defaults:", err.message);
  }
  _cached = {
    hotlinePromptRule: data.hotlinePromptRule !== false,
    hotlineOutputFilter: data.hotlineOutputFilter !== false,
    classifierEnabled: data.classifierEnabled === true,
    classifierUrl: typeof data.classifierUrl === "string" &&
      data.classifierUrl ? data.classifierUrl : null,
    classifierTimeoutMs: clampInt(data.classifierTimeoutMs, 1200, 200, 5000),
    classifierMaxChars: clampInt(data.classifierMaxChars, 1000, 50, 8000),
  };
  _cachedAt = Date.now();
  return _cached;
}

/** Test hook: forget the cached switches. */
function resetSafetyConfigCache() {
  _cached = null;
  _cachedAt = 0;
}

module.exports = {safetyConfig, resetSafetyConfigCache};
