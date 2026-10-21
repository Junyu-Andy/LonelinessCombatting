/**
 * 1021 (decisions-log 10/21 items 104–107; 小讀本 spec T-R6) — 通通's
 * study Q&A uses deepseek-v4-pro.  That is 「問下通通」 on the 15 short
 * articles (讀少少) and the 「?」 on a 小讀本: both open 通通 with the text as
 * context.  Every other call keeps the default model.
 *
 * Recognised by the article header the App puts in the context block
 * (tung_tung_page.dart; reader_qa_prompt.dart): the same line 通通's prompt
 * keys its article mode on.  The App's request does not change.  Only the
 * Hybrid arm reaches proxyDeepSeek (assertLlmAllowed), so only it gets
 * here.  Thinking stays off, as on every chat call (decision 0017).
 */
"use strict";

const ARTICLE_QA_MODEL = "deepseek-v4-pro";

/** The App's article headers (zh, and the en tester view). */
const ARTICLE_QA_MARKERS = [
  "[文章內容 — 所有回答只可以根據呢段]",
  "[Article context — ground all answers in this text]",
];

/**
 * True for 通通 with an article / 小讀本 in the context block.
 * @param {?string} agentId
 * @param {*} contextSuffix payload.contextSuffix
 * @return {boolean}
 */
function isArticleQa(agentId, contextSuffix) {
  if (agentId !== "tung_tung" || typeof contextSuffix !== "string") {
    return false;
  }
  return ARTICLE_QA_MARKERS.some((m) => contextSuffix.indexOf(m) !== -1);
}

module.exports = {ARTICLE_QA_MODEL, ARTICLE_QA_MARKERS, isArticleQa};
