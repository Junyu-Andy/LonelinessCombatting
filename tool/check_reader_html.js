#!/usr/bin/env node
/**
 * 1020c §3 — 小讀本检查：assets/readers/ 里每个文件都要过，不过就报错退出（CI 也跑）。
 *
 *   node tool/check_reader_html.js [目录，默认 assets/readers]
 *
 * 检查（1020c 第三节 (1)–(6)，另加几条让 App 能正常显示的）：
 *   (1) 没有外部资源：src / href 等以 http://、https://、// 开头，@import、url( 指向外部。
 *       另：图片、样式、脚本都要写在文件里（data: 或内嵌），不能引用别的文件；
 *       链接只能是 peizhu://cta/small_action、plan、thought 三个，或页内 #。
 *   (2) 没有 fetch(、XMLHttpRequest、WebSocket、localStorage、<form、<input、
 *       <textarea、tel:（另加 sessionStorage、indexedDB、sendBeacon、EventSource、
 *       <iframe、<object、<embed、<base）。
 *   (3) 没有电话号码样式的数字串：连续 8 位数字，或「xxxx xxxx」（中间空格或连字号）。
 *       .html、.txt 和 manifest 的标题都查。
 *   (4) 正文没有「AI」「模型」「機械人」「版本」「組」（也查简体「机械人」「组」）。
 *       注释、<script>、<style> 里的不算；alt、title、aria-label 算正文。
 *   (5) .html 有 data-section（编号格式同 App：小写字母、数字、_、-）；有同名 .txt；
 *       manifest.json 里有这个 id；manifest 里每个 id 都有 .html 和 .txt。
 *       另：页面要用到 var(--fs)，否则 App 的字号对它不起作用。
 *   (6) 每个文件小于 1 MB。
 *
 * 只用 Node 自带模块。写法保持 ES2018（不用 ?.、??）。
 */
"use strict";

const fs = require("fs");
const path = require("path");

const MAX_BYTES = 1024 * 1024;
// Same pattern as lib/core/usage/usage_event_recorder.dart kReaderIdPattern
// and firestore.rules (usage_events).
const ID_RE = /^[a-z0-9][a-z0-9_-]{0,47}$/;
const CTA_CODES = ["small_action", "plan", "thought"];

const FORBIDDEN_WORDS = ["模型", "機械人", "机械人", "版本", "組", "组"];
const AI_RE = /(^|[^A-Za-z])AI(?![A-Za-z])/;
const PHONE_RE = /(^|[^0-9０-９])([0-9０-９]{4}[ \u00a0\u3000\-－]?[0-9０-９]{4})(?![0-9０-９])/;

const NETWORK_APIS = [
  {re: /\bfetch\s*\(/, what: "fetch("},
  {re: /XMLHttpRequest/, what: "XMLHttpRequest"},
  {re: /WebSocket/, what: "WebSocket"},
  {re: /localStorage/, what: "localStorage"},
  {re: /sessionStorage/, what: "sessionStorage"},
  {re: /indexedDB/i, what: "indexedDB"},
  {re: /sendBeacon/, what: "sendBeacon"},
  {re: /EventSource/, what: "EventSource"},
  {re: /<form\b/i, what: "<form"},
  {re: /<input\b/i, what: "<input"},
  {re: /<textarea\b/i, what: "<textarea"},
  {re: /<iframe\b/i, what: "<iframe"},
  {re: /<object\b/i, what: "<object"},
  {re: /<embed\b/i, what: "<embed"},
  {re: /<base\b/i, what: "<base"},
  {re: /\btel:/i, what: "tel:"},
];

const EXTERNAL_ATTR_RE = new RegExp(
    "\\b(src|href|srcset|poster|action|formaction|data|background|" +
    "xlink:href|cite|longdesc|manifest|ping)\\s*=\\s*[\"']?\\s*" +
    "(https?:)?//", "i");
const EXTERNAL_IMPORT_RE = /@import\s+(url\(\s*)?["']?\s*(https?:)?\/\//i;
const EXTERNAL_URL_RE = /url\(\s*["']?\s*(https?:)?\/\//i;

/**
 * @param {string} html
 * @return {string} the text an elder sees or hears: no comments, scripts,
 *     styles or tags; alt / title / aria-label values kept.
 */
function visibleText(html) {
  let s = html.replace(/<!--[\s\S]*?-->/g, " ");
  s = s.replace(/<script\b[\s\S]*?<\/script\s*>/gi, " ");
  s = s.replace(/<style\b[\s\S]*?<\/style\s*>/gi, " ");
  const attrs = [];
  s.replace(/\b(alt|title|aria-label)\s*=\s*"([^"]*)"/gi, function(m, k, v) {
    attrs.push(v);
    return m;
  });
  s.replace(/\b(alt|title|aria-label)\s*=\s*'([^']*)'/gi, function(m, k, v) {
    attrs.push(v);
    return m;
  });
  s = s.replace(/<[^>]*>/g, " ");
  return s + "\n" + attrs.join("\n");
}

/**
 * @param {string} s
 * @return {string} s without data: URIs, CSS hex colours and SVG geometry
 *     attributes (their long digit runs are not phone numbers).
 */
function withoutNumberNoise(s) {
  return s
      .replace(/data:[^"')\s]+/gi, " ")
      .replace(/#[0-9a-f]{3,8}\b/gi, " ")
      .replace(/\s(d|points|viewBox|transform)\s*=\s*"[^"]*"/gi, " ")
      .replace(/\s(d|points|viewBox|transform)\s*=\s*'[^']*'/gi, " ");
}

/**
 * @param {string} text
 * @return {Array<string>} forbidden words found.
 */
function forbiddenWordsIn(text) {
  const found = [];
  if (AI_RE.test(text)) found.push("AI");
  for (const w of FORBIDDEN_WORDS) {
    if (text.indexOf(w) >= 0) found.push(w);
  }
  return found;
}

/**
 * @param {string} s
 * @return {?string} the first phone-like digit run, or null.
 */
function phoneIn(s) {
  const m = PHONE_RE.exec(s);
  return m ? m[2] : null;
}

/**
 * @param {string} html
 * @return {Array<{code: string, message: string}>}
 */
function checkHtml(html) {
  const out = [];
  const add = (code, message) => out.push({code: code, message: message});

  // (1) external resources
  let m = EXTERNAL_ATTR_RE.exec(html);
  if (m) add("external_resource", `外部资源：${m[1]}= 指向外部网址`);
  if (EXTERNAL_IMPORT_RE.test(html)) add("external_resource", "外部资源：@import");
  if (EXTERNAL_URL_RE.test(html)) add("external_resource", "外部资源：url( 指向外部网址");
  if (/@import\b/i.test(html) && !EXTERNAL_IMPORT_RE.test(html)) {
    add("local_resource", "不要用 @import：样式要直接写在文件里");
  }
  // resources must be inline (no base URL in the App, CSP allows data: only)
  const resRe = /<(img|script|link|source|video|audio|track)\b[^>]*?\b(src|href)\s*=\s*["']?\s*([^"'\s>]*)/gi;
  while ((m = resRe.exec(html)) !== null) {
    const v = m[3];
    if (v && !/^data:/i.test(v) && !/^(https?:)?\/\//i.test(v)) {
      add("local_resource", `<${m[1]} ${m[2]}="${v}">：图片、样式、脚本要写在文件里（data:），不能引用别的文件`);
    }
  }
  // links: only the three CTAs or in-page #
  const aRe = /<a\b[^>]*?\bhref\s*=\s*["']?\s*([^"'\s>]*)/gi;
  while ((m = aRe.exec(html)) !== null) {
    const v = m[1];
    if (/^(https?:)?\/\//i.test(v) || /^tel:/i.test(v)) continue; // (1)/(2)
    if (v.charAt(0) === "#") continue;
    const cta = /^peizhu:\/\/cta\/([a-z_]+)\/?$/.exec(v);
    if (!cta || CTA_CODES.indexOf(cta[1]) < 0) {
      add("bad_link", `链接 "${v}"：只可以用 peizhu://cta/small_action、plan、thought`);
    }
  }

  // (2) network / storage / input APIs
  for (const api of NETWORK_APIS) {
    if (api.re.test(html)) add("network_api", `不可以用 ${api.what}`);
  }

  // (3) phone numbers
  const phone = phoneIn(withoutNumberNoise(html));
  if (phone) add("phone_number", `疑似电话号码：${phone}`);

  // (4) forbidden words in the visible text
  const words = forbiddenWordsIn(visibleText(html));
  if (words.length) add("forbidden_word", `正文不可以出现：${words.join("、")}`);

  // (5) sections
  const ids = [];
  const secRe = /data-section\s*=\s*["']([^"']*)["']/gi;
  while ((m = secRe.exec(html)) !== null) ids.push(m[1].trim());
  if (!ids.length) add("no_section", "没有 data-section（App 靠它记录读到哪一节）");
  const seen = {};
  for (const id of ids) {
    if (!ID_RE.test(id)) {
      add("bad_section_id", `data-section="${id}"：只可以用小写字母、数字、_、-（最长 48）`);
    } else if (seen[id]) {
      add("duplicate_section", `data-section="${id}" 重复`);
    }
    seen[id] = true;
  }
  if (!/var\(\s*--fs\b/.test(html)) {
    add("no_fs", "没有用到 var(--fs)：App 的字號对这一篇不起作用");
  }
  return out;
}

/**
 * @param {string} text the .txt file
 * @return {Array<{code: string, message: string}>}
 */
function checkTxt(text) {
  const out = [];
  const phone = phoneIn(text);
  if (phone) out.push({code: "phone_number", message: `疑似电话号码：${phone}`});
  const words = forbiddenWordsIn(text);
  if (words.length) {
    out.push({code: "forbidden_word", message: `正文不可以出现：${words.join("、")}`});
  }
  if (/\btel:/i.test(text)) out.push({code: "network_api", message: "不可以用 tel:"});
  return out;
}

/**
 * @param {string} dir
 * @return {{units: number, problems: Array<{file: string, code: string,
 *     message: string}>}}
 */
function checkReaderDir(dir) {
  const problems = [];
  const add = (file, code, message) =>
    problems.push({file: file, code: code, message: message});

  if (!fs.existsSync(dir)) {
    add(dir, "manifest_invalid", "目录不存在");
    return {units: 0, problems: problems};
  }
  const files = fs.readdirSync(dir).filter((f) => !f.startsWith("."));
  const html = {};
  const txt = {};
  let manifestText = null;

  for (const f of files) {
    const full = path.join(dir, f);
    const stat = fs.statSync(full);
    if (stat.isDirectory()) {
      add(f, "unknown_file", "不要放子目录（App 只打包这一层）");
      continue;
    }
    if (stat.size >= MAX_BYTES) add(f, "too_large", `文件太大：${stat.size} 字节（要小于 1 MB）`);
    if (f === "manifest.json") {
      manifestText = fs.readFileSync(full, "utf8");
      continue;
    }
    const ext = path.extname(f);
    const stem = f.slice(0, f.length - ext.length);
    if (ext !== ".html" && ext !== ".txt") {
      add(f, "unknown_file", "只可以放 <id>.html、<id>.txt 和 manifest.json");
      continue;
    }
    if (!ID_RE.test(stem)) {
      add(f, "bad_file_name", "文件名只可以用小写字母、数字、_、-（最长 48）");
    }
    if (ext === ".html") html[stem] = fs.readFileSync(full, "utf8");
    else txt[stem] = fs.readFileSync(full, "utf8");
  }

  // manifest.json
  const manifestIds = {};
  let units = 0;
  if (manifestText === null) {
    add("manifest.json", "manifest_invalid", "没有 manifest.json");
  } else {
    let list = null;
    try {
      list = JSON.parse(manifestText);
    } catch (e) {
      add("manifest.json", "manifest_invalid", `不是有效的 JSON：${e.message}`);
    }
    if (list !== null && !Array.isArray(list)) {
      add("manifest.json", "manifest_invalid", "要是一个列表 [ … ]");
      list = null;
    }
    (list || []).forEach((e, i) => {
      const where = `第 ${i + 1} 项`;
      if (!e || typeof e !== "object" || Array.isArray(e)) {
        add("manifest.json", "manifest_entry", `${where}：要是 {"id", "titleZh", "minutes", "order"}`);
        return;
      }
      if (typeof e.id !== "string" || !ID_RE.test(e.id)) {
        add("manifest.json", "manifest_entry", `${where}：id 只可以用小写字母、数字、_、-（最长 48）`);
        return;
      }
      if (manifestIds[e.id]) {
        add("manifest.json", "manifest_entry", `${where}：id "${e.id}" 重复`);
        return;
      }
      manifestIds[e.id] = true;
      units++;
      if (typeof e.titleZh !== "string" || !e.titleZh.trim()) {
        add("manifest.json", "manifest_entry", `${where}（${e.id}）：没有 titleZh`);
      } else {
        const words = forbiddenWordsIn(e.titleZh);
        if (words.length) {
          add("manifest.json", "forbidden_word", `${where}（${e.id}）标题不可以出现：${words.join("、")}`);
        }
        const phone = phoneIn(e.titleZh);
        if (phone) add("manifest.json", "phone_number", `${where}（${e.id}）标题疑似电话号码：${phone}`);
      }
      if (!Number.isInteger(e.minutes) || e.minutes <= 0) {
        add("manifest.json", "manifest_entry", `${where}（${e.id}）：minutes 要是正整数`);
      }
      if (!Number.isInteger(e.order)) {
        add("manifest.json", "manifest_entry", `${where}（${e.id}）：order 要是整数`);
      }
      if (html[e.id] === undefined) add("manifest.json", "missing_files", `${e.id}：没有 ${e.id}.html`);
      if (txt[e.id] === undefined) add("manifest.json", "missing_files", `${e.id}：没有 ${e.id}.txt`);
    });
  }

  for (const id of Object.keys(html).sort()) {
    const f = `${id}.html`;
    for (const p of checkHtml(html[id])) add(f, p.code, p.message);
    if (txt[id] === undefined) add(f, "no_txt", `没有同名的 ${id}.txt`);
    if (!manifestIds[id]) add(f, "not_in_manifest", `manifest.json 里没有 "${id}"`);
  }
  for (const id of Object.keys(txt).sort()) {
    const f = `${id}.txt`;
    for (const p of checkTxt(txt[id])) add(f, p.code, p.message);
    if (html[id] === undefined) add(f, "no_html", `没有同名的 ${id}.html`);
  }
  return {units: units, problems: problems};
}

module.exports = {checkReaderDir, checkHtml, checkTxt, visibleText, ID_RE};

if (require.main === module) {
  const dir = process.argv[2] ||
      path.join(__dirname, "..", "assets", "readers");
  const r = checkReaderDir(dir);
  if (r.problems.length) {
    console.error(`小讀本检查不通过（${dir}）：`);
    for (const p of r.problems) {
      console.error(`  ${p.file}：${p.message}  [${p.code}]`);
    }
    process.exit(1);
  }
  console.log(`小讀本检查通过：${r.units} 个单元（${dir}）`);
}
