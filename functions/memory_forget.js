/**
 * 「唔好記住」: spotting a request not to remember (T10, decision 0024).
 *
 * Rules + keywords only, no model. Only the elder's own turns are read.
 * A hit keeps the whole session out of every memory layer (no extraction
 * call at all), and memory.js deletes earlier items that look related
 * (relatedTo below).
 *
 * Boundaries (see decision 0024 and the T10 report):
 *   - Covered: asking the companion not to remember / record / keep it,
 *     「當我冇講過」, asking it not to tell others, to forget or delete it.
 *   - Not a request: 「唔好記性」「記性唔好」(bad memory), 「唔好記錯」
 *     (don't misremember), 「唔使記掛」(don't worry about me), 「唔記得」
 *     (I forget), 「唔好同我講笑／講大話」, 「提醒」. These words are removed
 *     before matching. 「咪」 is not used: 「你咪記住佢囉」 means the
 *     opposite.
 *   - Reported speech (「個女叫我唔好話畀人知」) still counts: deleting a
 *     little too much is the safe side.
 *   - Negated requests (「唔係叫你唔好記住」) are not handled; they count.
 */

"use strict";

const FORGET_LEXICON_VERSION = "forget-v1-2026-10";

/** Lookalikes that are NOT requests; stripped before matching. */
const NOT_REQUESTS = [
  "唔好記性", "記性唔好", "記性差", "唔好記錯", "唔好記掛", "唔使記掛",
  "唔駛記掛", "唔洗記掛", "不用記掛", "唔記得", "記唔住", "講笑", "講大話",
  "提醒",
];

/**
 * Request patterns, checked on the text with spaces removed.
 * Each entry: [label, RegExp].
 */
const PATTERNS = [
  // Don't remember / record / write down.
  ["dont_remember", new RegExp(
      "(唔好|不要|別|别|勿)(幫我)?(再)?(記住|記低|記錄|記落|記入|記喺|" +
      "記返|記得呢|记住|记低|记录|记下|記下)")],
  ["no_need_to_remember", new RegExp(
      "(唔使|唔駛|唔洗|不用|不必|毋須|無須|冇需要)(你)?(幫我)?(記|记)")],
  // Pretend I never said it.
  ["never_said", new RegExp(
      "(當|当|就當|就当)(我)?(冇|無|沒|没|未)(講|讲|說|说)(過|过)?")],
  ["never_heard", new RegExp("(當|当)(你)?(冇|無|沒|没)(聽|听)(過|过|到)")],
  // Don't tell anyone.
  ["dont_tell", new RegExp(
      "(唔好|不要|別|别)(同|話|话|講|讲|說|说)(畀|俾|比|給|给)?" +
      "[^，。！？,.!?]{0,8}(知|聽|听|講|讲|說|说)")],
  ["dont_spread", new RegExp("(唔好|不要)(講|讲|話|话|傳|传)出去")],
  ["keep_secret", new RegExp(
      "(幫我|帮我|要)(保密|守秘密)|你知我知|你知就得|你知就算|係秘密嚟|" +
      "係我哋嘅秘密")],
  // Forget / delete it.
  ["forget_it", new RegExp(
      "(忘記|忘咗|忘了|刪咗|删咗|刪除|删除|刪走|删走)(佢|它|呢件事|呢樣|" +
      "嗰件事|我講嘅|我頭先講)|(唔好|不要)(再)?提(返|起)?(呢|嗰|佢)")],
  // English.
  ["english", new RegExp(
      "(don'?t|do not|never) (remember|record|save|keep|tell anyone|" +
      "mention)|forget (it|that|what i said|this)|keep (it|this) " +
      "(a )?secret|off the record", "i")],
];

/**
 * @param {string} text one user turn
 * @return {?{label: string, phrase: string}} the request found, or null
 */
function detectForget(text) {
  let s = String(text || "");
  const english = s.toLowerCase();
  s = s.replace(/\s+/g, "");
  for (const w of NOT_REQUESTS) s = s.split(w).join("");
  for (const [label, re] of PATTERNS) {
    const m = (label === "english" ? english : s).match(re);
    if (m) return {label, phrase: m[0]};
  }
  return null;
}

// ---------------------------------------------------------------------------
// Which stored items does a request refer to? (earlier sessions)
// ---------------------------------------------------------------------------

/** Two-character pieces too common to tie an item to a request. */
const STOP_BIGRAMS = new Set([
  "唔好", "好記", "記住", "記低", "呢件", "件事", "嗰件", "呢樣", "我哋",
  "佢哋", "你哋", "係咪", "唔係", "咁樣", "嘅事", "有啲", "啲嘢", "嘢呀",
  "一個", "個人", "時候", "而家", "今日", "尋日", "聽日", "講過", "話畀",
  "畀人", "人知", "其他", "知道", "唔使", "冇講", "當我", "我冇", "陪伴",
  "伴者", "用戶", "佢話", "佢講", "提到", "表示", "自己", "我個", "我屋",
  "屋企", "多謝", "唔該", "係呀", "好呀", "呀我",
]);

/**
 * @param {string} s
 * @return {Set<string>} CJK / alphanumeric bigrams, punctuation removed
 */
function bigrams(s) {
  const t = String(s || "").toLowerCase()
      .replace(/[\s\p{P}\p{S}]/gu, "");
  const out = new Set();
  for (let i = 0; i + 2 <= t.length; i++) {
    const g = t.slice(i, i + 2);
    if (!STOP_BIGRAMS.has(g)) out.add(g);
  }
  return out;
}

/**
 * What the request is about: the request turn without the request words,
 * plus up to two user turns before it in the same session.
 * @param {Array<{fromUser: boolean, text: string}>} turns
 * @param {number} index of the request turn
 * @param {string} phrase the matched request words
 * @return {Set<string>}
 */
function subjectBigrams(turns, index, phrase) {
  const parts = [String(turns[index].text || "").split(phrase).join("")];
  let n = 0;
  for (let i = index - 1; i >= 0 && n < 2; i--) {
    if (turns[i].fromUser) {
      parts.push(turns[i].text);
      n++;
    }
  }
  const out = new Set();
  for (const p of parts) for (const g of bigrams(p)) out.add(g);
  return out;
}

/**
 * True when an item shares at least `min` distinct bigrams with the
 * request's subject.
 * @param {string} itemText value / quote / summary / description
 * @param {Set<string>} subject from subjectBigrams
 * @param {number=} min default 2
 * @return {boolean}
 */
function relatedTo(itemText, subject, min) {
  const need = min || 2;
  let n = 0;
  for (const g of bigrams(itemText)) {
    if (subject.has(g) && ++n >= need) return true;
  }
  return false;
}

module.exports = {
  FORGET_LEXICON_VERSION,
  detectForget,
  subjectBigrams,
  relatedTo,
  bigrams,
};
