/**
 * Persona prompt registry (Dev Req §3.2, §8; memory-and-entry-spec 3.10).
 *
 * Prompts live server-side so the client cannot tamper with them.  Files
 * under functions/prompts/<file>.txt are loaded once per instance and
 * cached.  The app sends a key (e.g. `siu_yan_v1`); PROMPT_FILES maps it
 * to the versioned file the server loads.  Old files are never
 * overwritten — a new version is a new file plus one line here.
 *
 * Moved out of index.js (T49b) so the pure parts can be unit-tested
 * without Firestore: functions/test/prompt_tone_test.js.
 */
"use strict";

const fs = require("fs");
const path = require("path");

const PROMPT_DIR = path.join(__dirname, "prompts");
const _promptCache = {};

// The key the app sends → the versioned file the server loads.
//   tung_tung_v1 → tung_tung.v2: no "幫你查" invitation (decision 0019).
//   T49b (2026-10-18, 10/16 item 5): 小欣 v2, 阿珍／阿伯 v2, 通通 v3 —
//   identity wording "電腦程式夥伴", the search-era lines and the dead
//   "Context injection" section removed, {{TONE_RULE}} slot added.
//   1020 F (2026-10-19): 小欣 v3 = v2 plus one section, 「每日 check-in
//   （App 對話形式）」 (the two check-in replies and the opener once the
//   check-in is done).  Only the chat window behind the App switch
//   checkInChatV2Enabled sends `siu_yan_v3`; every other 小欣 call still
//   sends `siu_yan_v1` and gets v2.
//   1020d §2 (2026-10-20): 阿珍／阿伯 v3 = v2 plus one section, 「每題之後」
//   (one specific follow-up, then a reply with no question; the three
//   markers [回憶·追問] / [回憶·回應] / [回憶·再講多啲]).  Only the
//   reminiscence v2 page behind the App switch reminiscenceV2Enabled sends
//   `ah_jan_ah_bak_v3`; every other 阿珍／阿伯 call still sends
//   `ah_jan_ah_bak_v1` and gets v2.
const PROMPT_FILES = {
  siu_yan_v1: "siu_yan.v2",
  siu_yan_v3: "siu_yan.v3",
  ah_jan_ah_bak_v1: "ah_jan_ah_bak.v2",
  ah_jan_ah_bak_v3: "ah_jan_ah_bak.v3",
  tung_tung_v1: "tung_tung.v3",
};

/**
 * @param {string} key Prompt key the app sends.
 * @return {string} File name (without .txt) the server loads.
 */
function promptFileFor(key) {
  return Object.prototype.hasOwnProperty.call(PROMPT_FILES, key) ?
    PROMPT_FILES[key] : key;
}

/**
 * @param {string} key Prompt key.
 * @return {?string} The prompt text, or null when there is no such file.
 */
function loadPrompt(key) {
  if (_promptCache[key] !== undefined) return _promptCache[key];
  try {
    const file = path.join(PROMPT_DIR, `${promptFileFor(key)}.txt`);
    _promptCache[key] = fs.readFileSync(file, "utf8");
  } catch (err) {
    _promptCache[key] = null;
  }
  return _promptCache[key];
}

// L-2 — prompt version label derived from the prompt file header, e.g.
// "## 小欣 — … · v2 (rev 2026-10)" → "siu_yan_v2@2026-10".  Cached with the
// prompt text; null for raw systemPrompt callers (no server-side file).
const _promptVersionCache = {};

/**
 * @param {?string} key Prompt key.
 * @return {?string} Version label, or null.
 */
function promptVersionFor(key) {
  if (!key) return null;
  if (_promptVersionCache[key] !== undefined) return _promptVersionCache[key];
  const text = loadPrompt(key);
  let label = null;
  if (text) {
    const m = text.split("\n")[0].match(/v(\d+)\s*\(rev\s*([0-9-]+)\)/);
    if (m) label = `${key.replace(/[._]v\d+$/, "")}_v${m[1]}@${m[2]}`;
  }
  _promptVersionCache[key] = label;
  return label;
}

// T49b (task sheet 1018 §B1) — the tone line, chosen by the participant's
// `users/{uid}.encouragementStyle` (written by researcher_intake.js,
// PR #111).  Hybrid arm only: proxyDeepSeek refuses the rule arm before
// any prompt is resolved.  Prompts without {{TONE_RULE}} are unaffected.
const TONE_RULES = {
  direct: "呢位用戶鍾意人直接講。重點放第一句，少鋪墊。" +
    "其他規矩照舊，唔好提起呢個設定。",
  gentle: "呢位用戶鍾意人溫和啲講。句子短啲、慢啲，留餘地。" +
    "其他規矩照舊，唔好提起呢個設定。",
};
const TONE_RULE_DEFAULT = "（用戶冇特別偏好，照以下規矩嘅默認語氣。）";

/**
 * @param {*} style encouragementStyle: "direct" | "gentle" | "either" |
 *     anything else (missing, null, unknown → default).
 * @return {string} The tone line for the {{TONE_RULE}} slot.
 */
function toneRuleFor(style) {
  if (typeof style === "string" &&
      Object.prototype.hasOwnProperty.call(TONE_RULES, style)) {
    return TONE_RULES[style];
  }
  return TONE_RULE_DEFAULT;
}

/**
 * Fills the per-request slots of a persona template.
 * @param {string} template Prompt text.
 * @param {{variantName: (string|undefined),
 *     encouragementStyle: *}} opts Slot values.
 * @return {string} Filled text.
 */
function fillSlots(template, opts) {
  const o = opts || {};
  // Default variant: feminine (阿珍).  An earlier auto-formatter
  // mangled this to "阿Jan" — do not regress.  The two real variants
  // are 阿珍 (feminine, sage green) and 阿伯 (masculine, teal-blue).
  const variantName = o.variantName || "阿珍／阿伯";
  return template
      .split("{{VARIANT_NAME}}").join(variantName)
      .split("{{TONE_RULE}}").join(toneRuleFor(o.encouragementStyle));
}

module.exports = {
  PROMPT_DIR,
  PROMPT_FILES,
  promptFileFor,
  loadPrompt,
  promptVersionFor,
  TONE_RULES,
  TONE_RULE_DEFAULT,
  toneRuleFor,
  fillSlots,
};
