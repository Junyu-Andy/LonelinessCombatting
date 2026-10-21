/**
 * 1021 (decisions-log 10/21 104–107; 小讀本 spec T-R6) — 通通's article /
 * 小讀本 Q&A uses deepseek-v4-pro; nothing else changes model.
 *   - only agent tung_tung with the App's article header in the context
 *     block counts; 小欣, 阿珍／阿伯 and 通通's own chat keep the default;
 *   - the headers match the App's (tung_tung_page.dart, reader_qa_prompt.dart);
 *   - the proxy uses it for the model and the llm_calls call type.
 *
 * Run: cd functions && node test/article_qa_test.js
 */
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const qa = require("../article_qa");

const zh = "[文章內容 — 所有回答只可以根據呢段]";
const en = "[Article context — ground all answers in this text]";

assert.strictEqual(qa.ARTICLE_QA_MODEL, "deepseek-v4-pro");
assert.ok(qa.isArticleQa("tung_tung", `${zh}\nTITLE: 孤單係咩\n正文`));
assert.ok(qa.isArticleQa("tung_tung", `${en}\nTITLE: x\nbody`));
assert.ok(qa.isArticleQa("tung_tung",
    `${zh}\n（呢段係「讀少少」入面嘅小讀本。…）\n正文\n\n[模組] tung_tung_chat`));
assert.ok(!qa.isArticleQa("tung_tung", "[onboarding 時話過嘅興趣]\n- 飲茶"));
assert.ok(!qa.isArticleQa("tung_tung", null));
assert.ok(!qa.isArticleQa("tung_tung", undefined));
assert.ok(!qa.isArticleQa("siu_yan", `${zh}\n正文`));
assert.ok(!qa.isArticleQa("ah_jan_ah_bak", `${zh}\n正文`));
assert.ok(!qa.isArticleQa(null, `${zh}\n正文`));

// The App sends exactly these headers.
const repo = path.join(__dirname, "..", "..");
const dart = (f) => fs.readFileSync(path.join(repo, f), "utf8");
const page = dart(
    "lib/features/curious_companion/presentation/pages/tung_tung_page.dart");
const reader = dart("lib/features/education/data/reader_qa_prompt.dart");
for (const m of [zh, en]) {
  assert.ok(page.includes(`'${m}'`), `tung_tung_page.dart lacks ${m}`);
  assert.ok(reader.includes(`'${m}\\n'`), `reader_qa_prompt.dart lacks ${m}`);
}

// The proxy picks the model and the call type with it.
const index = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
assert.ok(index.includes("const articleQaCall = " +
    "articleQa.isArticleQa(agentId, payload.contextSuffix);"));
assert.ok(index.includes(
    "model: articleQaCall ? articleQa.ARTICLE_QA_MODEL : DEEPSEEK_MODEL,"));
assert.ok(index.includes("callType: articleQaCall ? \"article_qa\" :"));

console.log("article_qa_test: all passed");
