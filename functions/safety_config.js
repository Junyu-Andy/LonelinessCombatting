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
 * Cached per instance for a minute so a flip takes effect quickly without
 * a read on every call.  ES2018 (no `??` / `?.`).
 */
"use strict";

const TTL_MS = 60 * 1000;
let _cached = null;
let _cachedAt = 0;

/**
 * Current safety switches.
 * @param {!Object} db Firestore handle.
 * @return {Promise<{hotlinePromptRule: boolean,
 *   hotlineOutputFilter: boolean}>} Switches, defaulting to on.
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
