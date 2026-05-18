/**
 * B.1 — LLM mechanism-of-change flag detector (Sprint 2.1).
 *
 * Computes 5 binary flags from the (userInput, assistantOutput, agentContext)
 * tuple to instrument what the LLM uniquely contributed over the rule-based
 * Arm B baseline.  Pure regex pipeline — no spaCy, no extra model calls.
 * Determinism is essential: same input → same flags, regardless of cold-start.
 *
 * The 5 flags (per H5 mechanism analysis, Dev Req §B.1 default reading):
 *   1. personalization_specific
 *        Response references a named entity that appeared in the user's input
 *        OR in the prior shortTermBuffer / namedEntities map.  Distinguishes
 *        "I hear you, that sounds hard" (Arm B style) from "I hear that
 *        seeing 阿明 last Sunday meant a lot" (Arm A LLM contribution).
 *
 *   2. memory_callback
 *        Response references content from the rolling summary or from turns
 *        more than 1 turn back in the buffer.  Heuristic: response contains
 *        a noun-phrase (≥2 chars, Chinese/English) that appears in the
 *        rolling summary OR in buffer turns at index ≤ N-2 but NOT in the
 *        most recent user turn.
 *
 *   3. empathic_reflection
 *        Response uses an empathic acknowledgement structure.  Regex matches
 *        common HK Cantonese + English empathic openers: 「我聽到」, 「明白」,
 *        「我感受到」, 「呢樣野好難」, "I hear", "that sounds", "it makes
 *        sense that", etc.
 *
 *   4. open_question
 *        Response ends with an open-ended question (not yes/no).  Heuristic:
 *        last sentence ends with "?" / "？" AND contains an interrogative
 *        marker that yields open answers (點解, 點樣, 邊度, 乜嘢, what, how,
 *        why, when, where) rather than yes/no (係咪, 有冇, is, do, are).
 *
 *   5. adaptive_register
 *        Response register matches the user's emotional register.  Heuristic:
 *        if user input contains distress-low keywords (孤獨, sad, alone, etc.)
 *        the response must use a softening particle (啦, 啊, 喎) OR an
 *        explicit acknowledgement; if user input is neutral the response
 *        must NOT use crisis-register phrases ("please reach out", "I'm
 *        worried about you").  Avoids over-pathologizing benign turns.
 *
 * Output shape:
 * {
 *   personalization_specific: boolean,
 *   memory_callback: boolean,
 *   empathic_reflection: boolean,
 *   open_question: boolean,
 *   adaptive_register: boolean,
 *   _version: 1,                 // bump when heuristics change
 * }
 *
 * Tested against a golden fixture of 5 hand-crafted M3 turns
 * (see test fixture in functions/test/llm_flags_golden.json — TODO).
 */

"use strict";

// ---------------------------------------------------------------------------
// Flag 3 — empathic reflection
// ---------------------------------------------------------------------------
const EMPATHIC_PATTERNS = [
  // Chinese (Trad/Cantonese)
  /我聽到/, /我聽倒/, /明白你/, /我明白/, /我感受到/, /我可以感受/,
  /呢樣[嘢野]好難/, /真係好難/, /唔容易/, /好辛苦/, /好心痛/,
  /多謝你[同分]/, /多謝你願意/, /好欣賞你/, /我陪住你/,
  // Simplified
  /我听到/, /明白你/, /我感受到/, /这样很难/, /真的很难/,
  // English
  /\bi hear (you|that)\b/i,
  /\bthat sounds\b/i,
  /\bit makes sense (that|you)\b/i,
  /\bi can imagine\b/i,
  /\bthank you for sharing\b/i,
  /\bthat must (be|have been)\b/i,
];

function flagEmpathicReflection(response) {
  return EMPATHIC_PATTERNS.some((p) => p.test(response));
}

// ---------------------------------------------------------------------------
// Flag 4 — open question
// ---------------------------------------------------------------------------
const OPEN_MARKERS = [
  // Chinese — open
  /點解/, /點樣/, /邊度/, /邊個/, /乜嘢/, /咩/, /幾時/, /如何/, /怎樣/,
  /什麼/, /什么/, /为何/, /为什么/,
  // English — open
  /\bwhat\b/i, /\bhow\b/i, /\bwhy\b/i, /\bwhen\b/i, /\bwhere\b/i,
  /\btell me/i, /\bdescribe\b/i,
];
const YES_NO_MARKERS = [
  /係咪/, /有冇/, /可唔可以/, /想唔想/, /得唔得/, /是不是/, /有没有/,
  /\bis\b/i, /\bare\b/i, /\bdo\b/i, /\bdoes\b/i, /\bdid\b/i, /\bwould\b/i,
  /\bcan\b/i, /\bcould\b/i, /\bwill\b/i,
];

function flagOpenQuestion(response) {
  const trimmed = response.trim();
  if (!/[?？]\s*$/.test(trimmed)) return false;
  // Look at the final sentence (after the last 。.!?！？).
  const parts = trimmed.split(/[。.!?！？]/).filter((s) => s.trim().length > 0);
  if (parts.length === 0) return false;
  const last = parts[parts.length - 1];
  const hasOpen = OPEN_MARKERS.some((p) => p.test(last));
  if (!hasOpen) return false;
  // A yes-no marker leading the sentence demotes it.
  const head = last.trim().slice(0, 15);
  const startsYesNo = YES_NO_MARKERS.some((p) => p.test(head));
  return !startsYesNo;
}

// ---------------------------------------------------------------------------
// Flag 5 — adaptive register
// ---------------------------------------------------------------------------
const LOW_DISTRESS_MARKERS = [
  /孤獨/, /孤單/, /一個人/, /冇人陪/, /空虛/, /唔開心/, /失落/,
  /孤独/, /孤单/, /一个人/, /没人陪/, /空虚/, /不开心/,
  /\b(lonely|alone|sad|empty|isolated|down)\b/i,
];
const CRISIS_REGISTER_PHRASES = [
  /請即刻搵/, /即刻撥/, /請致電/, /建議你即刻/,
  /請即刻打/, /即刻打\s*999/, /我好擔心你/, /我好擔心你/,
  /请即刻找/, /马上拨打/, /我很担心你/,
  /\bplease (reach out|call|seek help)\b/i,
  /\bi'?m worried about you\b/i,
  /\bcall (911|999|the (crisis|hotline|helpline))\b/i,
];
const SOFTENING_PARTICLES = [
  /[呀啊啦喎喔嘞嘅]/, // Cantonese final particles
  /\b(perhaps|maybe|gently|softly)\b/i,
];
const ACKNOWLEDGEMENT_MARKERS = EMPATHIC_PATTERNS; // re-use

function flagAdaptiveRegister(userInput, response) {
  const userIsLow = LOW_DISTRESS_MARKERS.some((p) => p.test(userInput));
  if (userIsLow) {
    const hasSoftener =
      SOFTENING_PARTICLES.some((p) => p.test(response)) ||
      ACKNOWLEDGEMENT_MARKERS.some((p) => p.test(response));
    return hasSoftener;
  }
  // Neutral user input: response must not slip into crisis register.
  const hasCrisis = CRISIS_REGISTER_PHRASES.some((p) => p.test(response));
  return !hasCrisis;
}

// ---------------------------------------------------------------------------
// Flag 1 — personalization specific
// ---------------------------------------------------------------------------
// A "named entity" candidate in the input: a 2–6 char CJK noun phrase that
// follows a relationship marker (阿/老/細) OR a quoted segment.  Crude but
// determinism + recall is what we need; precision is bounded by 2-char min.
const ENTITY_PATTERN = /([阿老細]\p{Script=Han}{1,3})|「(\p{Script=Han}{2,8})」|"([A-Za-z][A-Za-z0-9 .'-]{1,30})"/gu;

function extractCandidateEntities(text) {
  const out = new Set();
  if (!text) return out;
  let m;
  ENTITY_PATTERN.lastIndex = 0;
  while ((m = ENTITY_PATTERN.exec(text)) !== null) {
    const ent = m[1] || m[2] || m[3];
    if (ent && ent.length >= 2) out.add(ent.trim());
  }
  return out;
}

function flagPersonalizationSpecific(userInput, response, agentContext) {
  const fromInput = extractCandidateEntities(userInput);
  const fromContext = new Set();
  if (agentContext && agentContext.namedEntities) {
    for (const name of Object.keys(agentContext.namedEntities)) {
      if (name && name.length >= 2) fromContext.add(name);
    }
  }
  const all = new Set([...fromInput, ...fromContext]);
  if (all.size === 0) return false;
  for (const ent of all) {
    if (response.includes(ent)) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Flag 2 — memory callback
// ---------------------------------------------------------------------------
// Tokenise rolling summary + older buffer turns into 2-char (CJK) and
// whole-word (Latin) tokens, then check whether response contains a token
// that appears in the OLDER context but NOT in the most recent user turn.
function tokenize(text) {
  if (!text) return new Set();
  const tokens = new Set();
  // 2-char CJK bigrams.
  const han = text.match(/\p{Script=Han}{2,}/gu) || [];
  for (const segment of han) {
    for (let i = 0; i <= segment.length - 2; i++) {
      tokens.add(segment.slice(i, i + 2));
    }
  }
  // Latin words (length ≥ 4 to avoid stop-words).
  const words = text.toLowerCase().match(/[a-z]{4,}/g) || [];
  for (const w of words) tokens.add(w);
  return tokens;
}

const ENGLISH_STOP = new Set([
  "that", "this", "with", "from", "have", "your", "yours", "what", "when",
  "where", "which", "would", "could", "should", "about", "their", "there",
  "these", "those", "been", "being",
]);

function flagMemoryCallback(userInput, response, agentContext) {
  if (!agentContext) return false;
  const olderText = [
    agentContext.rollingSummary || "",
    ...((agentContext.shortTermBuffer || [])
      .slice(0, -1) // exclude most recent turn
      .map((t) => t.text || "")),
  ].join(" ");
  if (!olderText.trim()) return false;

  const olderTokens = tokenize(olderText);
  const recentTokens = tokenize(userInput);
  const responseTokens = tokenize(response);

  for (const tok of responseTokens) {
    if (ENGLISH_STOP.has(tok)) continue;
    if (olderTokens.has(tok) && !recentTokens.has(tok)) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

function computeLlmFlags({userInput, assistantOutput, agentContext}) {
  const u = userInput || "";
  const a = assistantOutput || "";
  return {
    personalization_specific: flagPersonalizationSpecific(u, a, agentContext),
    memory_callback: flagMemoryCallback(u, a, agentContext),
    empathic_reflection: flagEmpathicReflection(a),
    open_question: flagOpenQuestion(a),
    adaptive_register: flagAdaptiveRegister(u, a),
    _version: 1,
  };
}

module.exports = {
  computeLlmFlags,
  // exported for unit tests
  _internal: {
    flagPersonalizationSpecific,
    flagMemoryCallback,
    flagEmpathicReflection,
    flagOpenQuestion,
    flagAdaptiveRegister,
    extractCandidateEntities,
    tokenize,
  },
};
