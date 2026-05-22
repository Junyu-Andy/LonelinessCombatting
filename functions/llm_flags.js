/**
 * B.1 — LLM unique-contribution flag detector (Sprint 2.1, corrected May 2026).
 *
 * Computes the FIVE LLM-unique-contribution flags exactly as specified in
 * Phase A Proposal §1.4 and Product Overview §6 — these are the five
 * affordances that are "absent by construction in the rule-based arm" and
 * that Phase A calibrates for Phase B's cumulative-exposure index.
 *
 * The 5 flags (per spec):
 *
 *   1. specific_content_engagement
 *        Anchoring the response on a named entity, specific word, or
 *        expressed feeling from the user's prior turn.  Rule-based
 *        templates cannot do this — they don't read the user's text.
 *
 *   2. cross_session_memory
 *        Explicit reference, in a later session, to a named entity or
 *        topic introduced in an earlier session.  Requires the
 *        per-agent context store (rolling summary / named-entities map);
 *        Arm B has no equivalent.
 *
 *   3. honest_unfamiliarity
 *        When the user references a place, person, or cultural detail
 *        the agent does not "know", the agent admits the gap rather
 *        than fabricating.  Detectable via explicit unfamiliarity
 *        phrases: 「我未聽過」, 「我唔識」, 「請你話我知」, "I don't know
 *        that", "tell me more about", etc.
 *
 *   4. mixed_content_routing
 *        Detection of conjoined informational + emotional content
 *        within a single user turn, and routing of each component to
 *        the appropriate agent (cross-referral suggestion).  Implemented
 *        as: the response contains a cross-referral phrase AND the user
 *        input contains both an info-marker and an affect-marker.
 *
 *   5. generative_summary
 *        Per-session second-person summaries (M3 end-of-session) and
 *        weekly narrative progress summaries (M9 weekly card).  Marker:
 *        the moduleId is on the summary surface AND the response has
 *        the structural shape of a summary (mentions multiple distinct
 *        timeframes / actions / contacts in 1–2 sentences).
 *
 * Output shape (all booleans + _version):
 *   {
 *     specific_content_engagement: bool,
 *     cross_session_memory: bool,
 *     honest_unfamiliarity: bool,
 *     mixed_content_routing: bool,
 *     generative_summary: bool,
 *     _version: 2,           // bumped when heuristics change
 *   }
 *
 * Phase A Gate #4 requires Cohen's κ ≥ 0.6 per flag against the
 * adjudicated 20% sample; flags failing this are dropped from the
 * cumulative LLM-unique-exposure index in the Phase B mechanism analysis.
 */

"use strict";

// ---------------------------------------------------------------------------
// Flag 1 — specific content engagement
// ---------------------------------------------------------------------------
// A "specific content" anchor in the response is: either a named entity
// from the user's input/context OR a quoted/echoed segment of the user's
// last turn.  We detect both by checking whether any 2-char-or-longer CJK
// noun-like substring of the user input appears verbatim in the response.
const ENTITY_PATTERN =
  /([阿老細]\p{Script=Han}{1,3})|「(\p{Script=Han}{2,8})」|"([A-Za-z][A-Za-z0-9 .'-]{1,30})"/gu;

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

// HK place-name common suffixes — used to detect 3-char place names like
// 深水埗, 旺角區, 將軍澳, 油麻地, 鰂魚涌 even when no [阿老細] prefix is
// present.  Adding these here keeps the heuristic deterministic.
const HK_PLACE_SUFFIXES =
  /\p{Script=Han}{2}[埗角區灣道里村圍村場街路涌坑墟]/gu;

function extractPlaceNames(text) {
  const out = new Set();
  if (!text) return out;
  const matches = text.match(HK_PLACE_SUFFIXES) || [];
  for (const m of matches) out.add(m);
  return out;
}

function flagSpecificContentEngagement(userInput, response, agentContext) {
  const fromInput = extractCandidateEntities(userInput);
  const fromContext = new Set();
  if (agentContext && agentContext.namedEntities) {
    for (const name of Object.keys(agentContext.namedEntities)) {
      if (name && name.length >= 2) fromContext.add(name);
    }
  }
  // Anchor 1: named entity echoed in the response.
  const all = new Set([...fromInput, ...fromContext]);
  for (const ent of all) {
    if (response.includes(ent)) return true;
  }
  // Anchor 2: 3-char HK place name from input appears in response.
  // Specific HK locations are exactly the "specific content" anchor
  // the spec calls out.
  for (const place of extractPlaceNames(userInput)) {
    if (response.includes(place)) return true;
  }
  // Anchor 3: a 4+ char CJK substring of the user input appears verbatim
  // in the response (echoing a longer specific phrase the user said).
  const han = userInput.match(/\p{Script=Han}{4,}/gu) || [];
  for (const segment of han) {
    for (let i = 0; i <= segment.length - 4; i++) {
      const sub = segment.slice(i, i + 4);
      if (response.includes(sub)) return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Flag 2 — cross-session memory threading
// ---------------------------------------------------------------------------
// Token-matched against rolling summary + buffer turns at index ≤ N-2
// (i.e. NOT the most-recent user turn).  A response token that appears in
// the older context but not in the most recent user input is a cross-session
// (or at least cross-turn-pair) memory callback.
function tokenize(text) {
  if (!text) return new Set();
  const tokens = new Set();
  const han = text.match(/\p{Script=Han}{2,}/gu) || [];
  for (const segment of han) {
    for (let i = 0; i <= segment.length - 2; i++) {
      tokens.add(segment.slice(i, i + 2));
    }
  }
  const words = text.toLowerCase().match(/[a-z]{4,}/g) || [];
  for (const w of words) tokens.add(w);
  return tokens;
}

const ENGLISH_STOP = new Set([
  "that", "this", "with", "from", "have", "your", "yours", "what", "when",
  "where", "which", "would", "could", "should", "about", "their", "there",
  "these", "those", "been", "being",
]);

function flagCrossSessionMemory(userInput, response, agentContext) {
  if (!agentContext) return false;
  // "Older" context = rolling summary + buffer turns EXCLUDING the most
  // recent (which is the user input we're already responding to).
  const olderText = [
    agentContext.rollingSummary || "",
    ...((agentContext.shortTermBuffer || [])
      .slice(0, -1)
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
// Flag 3 — honest unfamiliarity
// ---------------------------------------------------------------------------
// The agent admits ignorance instead of fabricating.  Phrases:
//   Chinese:  我未聽過, 我唔識, 我冇聽過, 我未必清楚, 你話我知, 唔好意思我唔知,
//             我並不熟悉, 我並未/未必認識
//   English:  I don't know that, I'm not familiar with, tell me more about,
//             could you tell me about, I haven't heard of
const HONEST_UNFAMILIARITY_PATTERNS = [
  // Chinese (traditional / Cantonese)
  /我未聽過/, /我冇聽過/, /我未必/, /我唔識/, /我並不(熟悉|認識)/,
  /唔好意思.{0,5}(我唔|我未)/, /你話我知/, /你可唔可以(同我講|話我聽)/,
  /我未必清楚/, /我並未認識/, /我未認識/,
  // Simplified
  /我没听过/, /我不熟悉/, /请告诉我/, /我并不认识/,
  // English
  /\bi (don'?t|do not) know\b/i,
  /\bi'?m not familiar with\b/i,
  /\bi haven'?t heard of\b/i,
  /\b(can|could) you tell me (about|more)/i,
  /\btell me more about\b/i,
];

function flagHonestUnfamiliarity(response) {
  return HONEST_UNFAMILIARITY_PATTERNS.some((p) => p.test(response));
}

// ---------------------------------------------------------------------------
// Flag 4 — mixed-content routing
// ---------------------------------------------------------------------------
// User turn contains BOTH an informational/topical marker AND an affect
// marker; response contains a cross-referral phrasing (suggests handoff to
// another agent).  This is the "detect conjoined info + emotion, route
// each to the right agent" affordance.
const INFO_MARKERS = [
  // Things you'd ask Tung Tung about — facts, topics, places
  /點(整|做|買|搵|去)/, /邊度有/, /有冇/, /幾錢/, /喺邊度/,
  /如何/, /怎樣/, /\bhow (do|can) i\b/i, /\bwhere (can|do) i\b/i,
];
const AFFECT_MARKERS = [
  // Emotional content the source agent should hand off to Siu Yan / Ah Jan
  /好[傷孤難失]/, /好(辛苦|攰|擔心|嬲|難過)/, /唔開心/, /好驚/, /好亂/,
  /\b(sad|lonely|worried|scared|anxious|hurt|angry)\b/i,
];
const REFERRAL_MARKERS = [
  // Hybrid cross-referral phrasings — "wanna talk to X?"
  /搵(阿珍|阿伯|小欣|通通)/, /同(阿珍|阿伯|小欣|通通)(傾|講)/,
  /過去(搵|同).{1,6}傾/, /要唔要去(搵|同|傾)/, /搵.{1,3}傾下/,
  /talk to (siu yan|ah jan|ah bak|tung tung)/i,
  /(siu yan|ah jan|ah bak|tung tung) might/i,
];

function flagMixedContentRouting(userInput, response) {
  const hasInfo = INFO_MARKERS.some((p) => p.test(userInput));
  const hasAffect = AFFECT_MARKERS.some((p) => p.test(userInput));
  if (!(hasInfo && hasAffect)) return false;
  return REFERRAL_MARKERS.some((p) => p.test(response));
}

// ---------------------------------------------------------------------------
// Flag 5 — generative summary
// ---------------------------------------------------------------------------
// Per-session end summary (M3) or weekly narrative (M9).  Markers:
//   moduleId in {m3_summary, m9_weekly_narrative} (preferred when client
//     tags it) OR the response has the structural shape of a summary:
//     mentions ≥2 distinct timeframe / activity markers in 1–3 sentences
//     and uses second-person address.
const TIMEFRAME_MARKERS = [
  /今個禮拜/, /上個禮拜/, /呢個星期/, /過去[幾今]?(日|個禮拜|個星期|個月)/,
  /禮拜[一二三四五六日]/, /(本|這|上)週/, /上次/, /嗰日/, /今日/,
  /\bthis week\b/i, /\blast week\b/i, /\bover the past\b/i,
];
const SECOND_PERSON_MARKERS = [
  /\b你\b/, /你嘅/, /你哋/, /\byou\b/i, /\byour\b/i,
];

function flagGenerativeSummary(moduleId, response) {
  const isSummaryModule =
    moduleId === "m3_summary" ||
    moduleId === "m9_weekly_narrative" ||
    moduleId === "weekly_summary";
  if (isSummaryModule) return true;

  // Structural fallback: ≥2 distinct timeframe-or-activity references,
  // AND ≥1 second-person address, AND the response is at least 60 chars.
  if ((response || "").length < 60) return false;
  let timeframeHits = 0;
  for (const p of TIMEFRAME_MARKERS) {
    if (p.test(response)) timeframeHits++;
    if (timeframeHits >= 2) break;
  }
  if (timeframeHits < 2) return false;
  return SECOND_PERSON_MARKERS.some((p) => p.test(response));
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

function computeLlmFlags({userInput, assistantOutput, agentContext, moduleId}) {
  const u = userInput || "";
  const a = assistantOutput || "";
  return {
    specific_content_engagement: flagSpecificContentEngagement(u, a, agentContext),
    cross_session_memory: flagCrossSessionMemory(u, a, agentContext),
    honest_unfamiliarity: flagHonestUnfamiliarity(a),
    mixed_content_routing: flagMixedContentRouting(u, a),
    generative_summary: flagGenerativeSummary(moduleId, a),
    _version: 2,
  };
}

module.exports = {
  computeLlmFlags,
  _internal: {
    flagSpecificContentEngagement,
    flagCrossSessionMemory,
    flagHonestUnfamiliarity,
    flagMixedContentRouting,
    flagGenerativeSummary,
    extractCandidateEntities,
    tokenize,
  },
};
