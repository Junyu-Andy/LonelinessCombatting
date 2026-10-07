/**
 * The App's distress lexicon, on the server (T10, decision 0024).
 *
 * safety_lexicon.json is GENERATED from lib/core/safety/distress_detector.dart
 * (DistressDetector.lexicon) by test/safety_lexicon_export_test.dart, which
 * fails whenever the two differ. analyze() copies DistressDetector.analyze:
 * lower-cased substring match, terms in check order, first hit wins.
 * test/fixtures/safety_lexicon_cases.json is checked on both sides.
 *
 * Used by memory v1 to keep turns the App would flag out of every memory
 * layer. Never edit the word list here: change the Dart lexicon (PI
 * sign-off) and regenerate.
 */

"use strict";

const LEXICON = require("./safety_lexicon.json");

const TERMS = LEXICON.terms.map((t) => ({
  tier: t[0], category: t[1], term: t[2], lower: t[2].toLowerCase(),
}));

/** Tiers the App writes to safety_events and keeps out of memory. */
const ESCALATION_TIERS = new Set([
  "moderate_review", "moderate_interrupt", "acute",
]);

/**
 * @param {string} text
 * @return {{tier: string, term: ?string, category: ?string}}
 */
function analyze(text) {
  const s = String(text || "");
  if (!s.trim()) return {tier: "none", term: null, category: null};
  const lower = s.toLowerCase();
  for (const t of TERMS) {
    if (lower.includes(t.lower)) {
      return {tier: t.tier, term: t.term, category: t.category};
    }
  }
  return {tier: "none", term: null, category: null};
}

/**
 * Same rule as DistressMatch.isEscalation in the App.
 * @param {string} text
 * @return {boolean}
 */
function isEscalation(text) {
  return ESCALATION_TIERS.has(analyze(text).tier);
}

module.exports = {
  WORDLIST_VERSION: LEXICON.wordlistVersion,
  TERMS,
  analyze,
  isEscalation,
};
