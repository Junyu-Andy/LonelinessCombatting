/**
 * T7 — hotline outbound filter (Hybrid arm only; SPEC C12, decision 0018).
 *
 * The AI must never write a phone number to a participant: on 2026-10-06
 * (T6 report) DeepSeek wrote hotline numbers of its own, twice pairing the
 * wrong organisation with the number.  Approved numbers live only on the
 * crisis page (crisis_resources.json, PI-verified).
 *
 * Two layers, both switchable in `meta/safety_config` (missing = on):
 *   - hotlinePromptRule:   append prompts/hotline_rule.v<N>.txt to the
 *                          system prompt (tells the model to write the
 *                          crisis-page token instead of a number);
 *   - hotlineOutputFilter: before proxyDeepSeek returns, replace every
 *                          phone number in the reply with HOTLINE_TOKEN and
 *                          log one `hotline_filter_log` row (no text).
 *
 * The App renders HOTLINE_TOKEN as a tappable link to the crisis page
 * (lib/core/safety/hotline_filter.dart — same patterns, same test cases in
 * test/fixtures/hotline_filter_cases.json).
 *
 * Pure module: no Firebase imports, so the unit test runs without the
 * emulator.  ES2018 (no `??` / `?.`).
 */
"use strict";

const fs = require("fs");
const path = require("path");

const FILTER_VERSION = "hotline_filter.v1";
const PROMPT_RULE_KEY = "hotline_rule.v1";

// Shown to the participant in place of a number; the App turns it into a
// link labelled with the existing crisis-line string (safetyPillAcute).
const HOTLINE_TOKEN = "【緊急熱線】";

const DIGIT = "[0-9\\uFF10-\\uFF19]";
// One separator between digit groups: ASCII / NBSP / ideographic space and
// the hyphen / dash family, ASCII or full-width.  Up to two in a row.
const SEP = "[ \\t\\u00A0\\u3000\\-\\u2010\\u2011\\u2013\\u2014\\uFF0D]";
const SEPS = `${SEP}{0,2}`;
// +852 / (852) / 852 / ＋８５２, with an optional separator after it.
const PREFIX = "(?:[+\\uFF0B]\\s?)?(?:[(\\uFF08]\\s?)?" +
  "(?:852|\\uFF18\\uFF15\\uFF12)(?:\\s?[)\\uFF09])?" + SEPS;
// Not inside a longer number, an amount ($ / ＄) or a decimal.  Full-width
// punctuation (，：) is ordinary Chinese text before a number, so allowed.
const LEFT = "(?<![0-9\\uFF10-\\uFF19$\\uFF04.,])";
// Not followed by more digits, a decimal part, or a unit that makes it a
// quantity, date or time (元 蚊 年 月 日 號 歲 個 人 點 % :).
const RIGHT = "(?![0-9\\uFF10-\\uFF19]|[.\\uFF0E,][0-9\\uFF10-\\uFF19]|" +
  "\\s?[%\\uFF05\\u5143\\u868A\\u5E74\\u6708\\u65E5\\u865F\\u53F7" +
  "\\u6B72\\u5C81\\u500B\\u4E2A\\u4EBA\\u9EDE\\u70B9:\\uFF1A])";

// Order matters: longer patterns first so a +852 number is one hit.
const PATTERNS = [
  // HK 8-digit (fixed line 2/3, mobile 4–9), optional +852 prefix,
  // grouped 4-4 or written solid.
  ["hk8", new RegExp(
      `${LEFT}(?:${PREFIX})?[2-9\\uFF12-\\uFF19]${DIGIT}{3}${SEPS}${DIGIT}{4}` +
      RIGHT, "g")],
  // HK toll-free 800 xxx xxx.
  ["hk_tollfree", new RegExp(
      `${LEFT}(?:${PREFIX})?(?:800|\\uFF18\\uFF10\\uFF10)${SEPS}${DIGIT}{3}` +
      `${SEPS}${DIGIT}{3}${RIGHT}`, "g")],
  // Mainland mobile 1[3-9]x xxxx xxxx (the model sometimes writes these).
  ["cn_mobile", new RegExp(
      `${LEFT}(?:[+\\uFF0B]?86${SEPS})?1[3-9]${DIGIT}${SEPS}${DIGIT}{4}` +
      `${SEPS}${DIGIT}{4}${RIGHT}`, "g")],
  // 999 on its own (not $999, 999蚊, 1999).
  ["emergency", new RegExp(
      `${LEFT}(?:999|\\uFF19\\uFF19\\uFF19)${RIGHT}`, "g")],
  // 3–5 digit service numbers (1823, 18288 …) only right after a calling
  // word, so years and counts are left alone.
  ["short_service", new RegExp(
      "(?<=(?:\\u6253|\\u64A5|\\u64A5\\u6253|\\u81F4\\u96FB|\\u96FB\\u8A71|" +
      "\\u71B1\\u7DDA|\\u70ED\\u7EBF|call|dial|phone|hotline)" +
      "[\\s:\\uFF1A]{0,2})" +
      `1${DIGIT}{2,4}${RIGHT}`, "gi")],
];

/**
 * Full-width digits → ASCII; everything that is not a digit dropped.
 * @param {string} s Matched text.
 * @return {string} ASCII digits only.
 */
function digitsOf(s) {
  return String(s)
      .replace(/[\uFF10-\uFF19]/g,
          (c) => String.fromCharCode(c.charCodeAt(0) - 0xFF10 + 48))
      .replace(/[^0-9]/g, "");
}

/**
 * Two 4-digit halves that are both years (2020-2026): a range, not a phone.
 * @param {string} match Matched text.
 * @return {boolean} True for a year range.
 */
function isYearRange(match) {
  const parts = match.split(new RegExp(SEP + "+")).filter(Boolean);
  if (parts.length !== 2) return false;
  return parts.every((p) => {
    const d = digitsOf(p);
    return d.length === 4 && +d >= 1900 && +d <= 2099;
  });
}

/**
 * 8 solid digits forming a valid YYYYMMDD: a compact date, not a phone.
 * @param {string} match Matched text.
 * @return {boolean} True for a compact date.
 */
function isCompactDate(match) {
  if (!/^[0-9\uFF10-\uFF19]{8}$/.test(match)) return false;
  const d = digitsOf(match);
  const y = +d.slice(0, 4);
  const m = +d.slice(4, 6);
  const day = +d.slice(6, 8);
  return y >= 1900 && y <= 2099 && m >= 1 && m <= 12 && day >= 1 && day <= 31;
}

let _approved = null;
/**
 * Approved crisis numbers (digits only), from crisis_resources.json.
 * @return {!Set<string>} Digit strings.
 */
function approvedNumbers() {
  if (_approved) return _approved;
  try {
    const file = path.join(__dirname, "prompts", "crisis_resources.json");
    const res = JSON.parse(fs.readFileSync(file, "utf8")).resources || [];
    _approved = new Set(res.map((r) => digitsOf(r.number || "")));
  } catch (err) {
    _approved = new Set();
  }
  return _approved;
}

/**
 * Replace every phone number in [text] with HOTLINE_TOKEN.
 * @param {string} text Model reply.
 * @return {{text: string, count: number,
 *   items: Array<{kind: string, approved: boolean}>}} Filtered text, number
 *   of replacements, and per-number kind / whether it was an approved
 *   crisis number.  Never contains the number itself.
 */
function filterHotlines(text) {
  if (!text || typeof text !== "string") {
    return {text: text || "", count: 0, items: []};
  }
  const items = [];
  let out = text;
  for (const [kind, re] of PATTERNS) {
    re.lastIndex = 0;
    out = out.replace(re, (m) => {
      if (kind === "hk8" && (isYearRange(m) || isCompactDate(m))) return m;
      let d = digitsOf(m);
      if (d.length > 8 && d.startsWith("852")) d = d.slice(3);
      items.push({kind, approved: approvedNumbers().has(d)});
      return HOTLINE_TOKEN;
    });
  }
  return {text: out, count: items.length, items};
}

/**
 * Turn the per-number items into the `hotline_filter_log` row fields.
 * @param {Array<{kind: string, approved: boolean}>} items From filterHotlines.
 * @return {Object} kinds / approved_count / unapproved_count.
 */
function summarise(items) {
  const kinds = {};
  let approved = 0;
  for (const it of items) {
    kinds[it.kind] = (kinds[it.kind] || 0) + 1;
    if (it.approved) approved++;
  }
  return {
    kinds,
    approved_count: approved,
    unapproved_count: items.length - approved,
  };
}

module.exports = {
  FILTER_VERSION,
  PROMPT_RULE_KEY,
  HOTLINE_TOKEN,
  filterHotlines,
  summarise,
  digitsOf,
};
