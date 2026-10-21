#!/usr/bin/env node
/**
 * 1020c §3 — 小讀本检查：assets/readers/ 里每个文件都要过，不过就报错退出（CI 也跑）。
 *
 *   node tool/check_reader_html.js [目录，默认 assets/readers]
 *
 * 结果按单元列出：哪个单元通过、哪个不通过、为什么（1021：tool/add_readers.sh
 * 用同一套检查，只把通过的单元放进 assets/readers/）。
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
 * <id>.explain.json（1021）：可以放，随 App 打包，但 App 这次不读。要求：是有效的
 * JSON、小于 1 MB、有同名的 .html。里面的电话号码、不准用的字、外部网址只作「提示」，
 * 不算不通过（App 这次不显示它）。
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
// 1021 T-R4 (3): chat_siu_yan added.  Same list as ReaderCta in
// lib/features/education/data/reader_html.dart and firestore.rules.
const CTA_CODES = ["small_action", "plan", "thought", "chat_siu_yan"];
// 1021 T-R1 (2): the icon names the App draws (reader_icons.dart); another
// name is allowed but the App shows its default book icon (a note).
const KNOWN_ICONS = ["help_outline", "self_improvement", "tune",
  "favorite_border", "science", "stairs", "family_restroom", "psychology",
  "videocam", "directions_walk", "local_florist", "location_city",
  "support_agent", "smartphone"];
const ICON_RE = /^[a-z0-9_]{1,64}$/;
const EXPLAIN_SUFFIX = ".explain.json";

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
 * Which of the six 1020c §三 checks a problem code belongs to (0 = one of
 * the extra checks; null = not about one unit).
 */
const RULES = {
  external_resource: 1,
  open_target_missing: 5,
  local_resource: 1,
  bad_link: 1,
  network_api: 2,
  phone_number: 3,
  forbidden_word: 4,
  no_section: 5,
  bad_section_id: 5,
  duplicate_section: 5,
  no_txt: 5,
  no_html: 5,
  not_in_manifest: 5,
  missing_files: 5,
  manifest_entry: 5,
  too_large: 6,
  no_fs: 0,
  explain_invalid: 0,
  manifest_invalid: null,
  unknown_file: null,
  bad_file_name: null,
};

const EXTRA_NAMES = {
  no_fs: "另加：字號要用 var(--fs)",
  explain_invalid: "另加：explain.json",
};

const RULE_NAMES = {
  0: "另加",
  1: "第 1 项 外部资源、链接",
  2: "第 2 项 联网、存储、表单",
  3: "第 3 项 电话号码",
  4: "第 4 项 不准用的字",
  5: "第 5 项 data-section、.txt、manifest 对得上",
  6: "第 6 项 每个文件小于 1 MB",
};

/**
 * @param {string} code
 * @return {string} e.g. "第 1 项 外部资源", or "" for a folder-level problem.
 */
function ruleLabel(code) {
  const r = RULES[code];
  if (r === undefined || r === null) return "";
  if (r === 0) return EXTRA_NAMES[code] || RULE_NAMES[0];
  return RULE_NAMES[r];
}

/**
 * @param {string} html
 * @return {string} the text an elder sees or hears: no comments, scripts,
 *     styles or tags; alt / title / aria-label values and the text in
 *     <script type="application/json"> data blocks kept.
 */
function visibleText(html) {
  let s = html.replace(/<!--[\s\S]*?-->/g, " ");
  // 1021: <script type="application/json"> holds text the page shows
  // (panels filled in by its script): that counts as visible text.
  s = s.replace(/<script\b[^>]*\btype\s*=\s*["']application\/json["'][^>]*>([\s\S]*?)<\/script\s*>/gi,
      function(m, body) {
        return " " + body + " ";
      });
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
 * 1021: journal page ranges in a reference list, written
 * 「年;卷(期):页码」 (e.g. "2015;63(10):2014-2022"), are not phone numbers.
 * Only that exact shape is skipped; any other 8-digit run still counts.
 * @param {string} s
 * @return {string}
 */
function withoutCitationPages(s) {
  return s.replace(/(\b(?:19|20)\d{2};\s*\d{1,4}(?:\(\d{1,4}\))?:\s*)[0-9]{1,6}\s*[-–]\s*[0-9]{1,6}/g,
      "$1 ");
}

/**
 * @param {string} s
 * @return {string} s without data: URIs, CSS hex colours and SVG geometry
 *     attributes (their long digit runs are not phone numbers).
 */
function withoutNumberNoise(s) {
  return withoutCitationPages(s)
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

const ALLOWED_LINKS_TEXT = "peizhu://cta/small_action、plan、thought、" +
    "chat_siu_yan，peizhu://reader/open?id=<篇 id>，或页内 #";

/**
 * A peizhu:// link the App handles (lib/features/education/data/
 * reader_html.dart decideReaderNavigation), or null.
 *   cta      peizhu://cta/<one of CTA_CODES>      → an App page
 *   open     peizhu://reader/open?id=<unit id>     → that unit, same page
 *   explain  peizhu://explain?card=<…>             → never shown this time
 *            (the page shows these only with data-explain="on", which the
 *            App does not set)
 * @param {string} href
 * @return {?{kind: string, code: (string|undefined), id: (string|undefined)}}
 */
function classifyPeizhuLink(href) {
  let m = /^peizhu:\/\/cta\/([a-z_]+)\/?$/.exec(href);
  if (m) return CTA_CODES.indexOf(m[1]) >= 0 ? {kind: "cta", code: m[1]} : null;
  m = /^peizhu:\/\/reader\/open\?id=([^&#]*)$/.exec(href);
  if (m) return ID_RE.test(m[1]) ? {kind: "open", id: m[1]} : null;
  if (/^peizhu:\/\/explain\?card=[A-Za-z0-9_.\-]+$/.test(href)) return {kind: "explain"};
  return null;
}

/**
 * @param {string} html
 * @return {Array<string>} the unit ids its peizhu://reader/open links name
 */
function openTargetsIn(html) {
  const out = [];
  const re = /peizhu:\/\/reader\/open\?id=([a-z0-9_-]+)/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    if (out.indexOf(m[1]) < 0) out.push(m[1]);
  }
  return out;
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
  // links: in-page #, or one of the peizhu:// links the App handles
  // (1021: every peizhu:// link must be handled — a tap never opens a
  // browser and never does nothing).
  const aRe = /<a\b([^>]*?)\bhref\s*=\s*["']?\s*([^"'\s>]*)([^>]*)>/gi;
  while ((m = aRe.exec(html)) !== null) {
    const v = m[2];
    if (/^(https?:)?\/\//i.test(v) || /^tel:/i.test(v)) continue; // (1)/(2)
    if (v.charAt(0) === "#") continue;
    const link = classifyPeizhuLink(v);
    if (!link) {
      add("bad_link", `链接 "${v}"：只可以用 ${ALLOWED_LINKS_TEXT}`);
    } else if (link.kind === "explain" && !/\bclass\s*=\s*["'][^"']*\bask\b/i.test(m[1] + m[3])) {
      add("bad_link", `链接 "${v}"：peizhu://explain 只可以放在 class="ask" 的按钮上（App 这次不显示它们）`);
    }
  }
  // peizhu:// anywhere else in the file (e.g. built in a script).
  const anyRe = /peizhu:\/\/[^\s"'<>)\\]*/g;
  while ((m = anyRe.exec(html)) !== null) {
    if (!classifyPeizhuLink(m[0])) {
      add("bad_link", `"${m[0]}"：App 不认识这个 peizhu:// 链接`);
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
  const phone = phoneIn(withoutCitationPages(text));
  if (phone) out.push({code: "phone_number", message: `疑似电话号码：${phone}`});
  const words = forbiddenWordsIn(text);
  if (words.length) {
    out.push({code: "forbidden_word", message: `正文不可以出现：${words.join("、")}`});
  }
  if (/\btel:/i.test(text)) out.push({code: "network_api", message: "不可以用 tel:"});
  return out;
}

/**
 * `<id>.explain.json` — packaged, not read by the App yet (1021).
 * @param {string} text
 * @return {{problems: Array<{code: string, message: string}>,
 *     notes: Array<string>}} problems fail the unit; notes do not.
 */
function checkExplain(text) {
  const problems = [];
  const notes = [];
  let value;
  try {
    value = JSON.parse(text);
  } catch (e) {
    problems.push({code: "explain_invalid", message: `不是有效的 JSON：${e.message}`});
    return {problems: problems, notes: notes};
  }
  if (value === null || typeof value !== "object") {
    problems.push({code: "explain_invalid", message: "要是 { … } 或 [ … ]"});
    return {problems: problems, notes: notes};
  }
  const later = "（App 这次不显示它；以后显示前要改）";
  const phone = phoneIn(text);
  if (phone) notes.push(`疑似电话号码：${phone}${later}`);
  const words = forbiddenWordsIn(text);
  if (words.length) notes.push(`有不准用的字：${words.join("、")}${later}`);
  if (/(https?:)?\/\/[a-z0-9]/i.test(text) || /\btel:/i.test(text)) {
    notes.push(`有网址或 tel:${later}`);
  }
  return {problems: problems, notes: notes};
}

/**
 * Which unit a file in the readers folder belongs to.
 * @param {string} f a file name (no folder)
 * @return {?{id: string, kind: string}} kind "html" | "txt" | "explain";
 *     null for manifest.json or a name that is not a unit file.
 */
function unitFileOf(f) {
  let stem = null;
  let kind = null;
  if (f.length > EXPLAIN_SUFFIX.length && f.slice(-EXPLAIN_SUFFIX.length) === EXPLAIN_SUFFIX) {
    stem = f.slice(0, -EXPLAIN_SUFFIX.length);
    kind = "explain";
  } else if (/\.html$/.test(f)) {
    stem = f.slice(0, -5);
    kind = "html";
  } else if (/\.txt$/.test(f)) {
    stem = f.slice(0, -4);
    kind = "txt";
  }
  if (stem === null || !ID_RE.test(stem)) return null;
  return {id: stem, kind: kind};
}

/**
 * Check a readers folder unit by unit.
 *
 * @param {string} dir
 * @return {{
 *   ok: boolean,
 *   manifestCount: number,
 *   manifestEntries: Array<object>,
 *   units: Array<{id: string, titleZh: ?string, inManifest: boolean,
 *     files: Array<string>, ok: boolean,
 *     problems: Array<{file: string, code: string, message: string}>,
 *     notes: Array<{file: string, message: string}>}>,
 *   general: Array<{file: string, code: string, message: string}>,
 * }} units in manifest order, then the rest by id.  `general` holds the
 *     problems that are not about one unit (manifest.json unreadable, a
 *     file that is not a unit file).  ok = no problem anywhere.
 */
function checkReaderDirByUnit(dir) {
  const general = [];
  const units = {};
  const unit = (id) => {
    if (!units[id]) {
      units[id] = {id: id, titleZh: null, inManifest: false, files: [],
        ok: true, problems: [], notes: []};
    }
    return units[id];
  };
  const addGeneral = (file, code, message) =>
    general.push({file: file, code: code, message: message});
  const addUnit = (id, file, code, message) =>
    unit(id).problems.push({file: file, code: code, message: message});

  if (!fs.existsSync(dir)) {
    addGeneral(dir, "manifest_invalid", "目录不存在");
    return {ok: false, manifestCount: 0, manifestEntries: [], units: [], general: general};
  }
  const files = fs.readdirSync(dir).filter((f) => !f.startsWith(".")).sort();
  const html = {};
  const txt = {};
  const explain = {};
  let manifestText = null;

  for (const f of files) {
    const full = path.join(dir, f);
    const stat = fs.lstatSync(full);
    if (stat.isDirectory()) {
      addGeneral(f, "unknown_file", "不要放子目录（App 只打包这一层）");
      continue;
    }
    if (!stat.isFile()) {
      addGeneral(f, "unknown_file", "只可以放普通文件（不要放快捷方式、链接）");
      continue;
    }
    const uf = unitFileOf(f);
    if (stat.size >= MAX_BYTES) {
      const msg = `文件太大：${stat.size} 字节（要小于 1 MB）`;
      if (uf) addUnit(uf.id, f, "too_large", msg);
      else addGeneral(f, "too_large", msg);
    }
    if (f === "manifest.json") {
      manifestText = fs.readFileSync(full, "utf8");
      continue;
    }
    if (!uf) {
      if (/\.(html|txt|json)$/i.test(f)) {
        addGeneral(f, "bad_file_name", "文件名只可以用小写字母、数字、_、-（最长 48），" +
            "后缀 .html、.txt、.explain.json");
      } else {
        addGeneral(f, "unknown_file",
            "只可以放 <id>.html、<id>.txt、<id>.explain.json 和 manifest.json");
      }
      continue;
    }
    unit(uf.id).files.push(f);
    const text = fs.readFileSync(full, "utf8");
    if (uf.kind === "html") html[uf.id] = text;
    else if (uf.kind === "txt") txt[uf.id] = text;
    else explain[uf.id] = text;
  }

  // manifest.json
  const manifestEntries = [];
  const partTitles = {};
  if (manifestText === null) {
    addGeneral("manifest.json", "manifest_invalid", "没有 manifest.json");
  } else {
    let list = null;
    try {
      list = JSON.parse(manifestText);
    } catch (e) {
      addGeneral("manifest.json", "manifest_invalid", `不是有效的 JSON：${e.message}`);
    }
    if (list !== null && !Array.isArray(list)) {
      addGeneral("manifest.json", "manifest_invalid", "要是一个列表 [ … ]");
      list = null;
    }
    (list || []).forEach((e, i) => {
      const where = `第 ${i + 1} 项`;
      if (!e || typeof e !== "object" || Array.isArray(e)) {
        addGeneral("manifest.json", "manifest_entry", `${where}：要是 {"id", "titleZh", "minutes", "order"}`);
        return;
      }
      if (typeof e.id !== "string" || !ID_RE.test(e.id)) {
        addGeneral("manifest.json", "manifest_entry", `${where}：id 只可以用小写字母、数字、_、-（最长 48）`);
        return;
      }
      const u = unit(e.id);
      if (u.inManifest) {
        addUnit(e.id, "manifest.json", "manifest_entry", `${where}：id "${e.id}" 重复`);
        return;
      }
      u.inManifest = true;
      manifestEntries.push(e);
      if (typeof e.titleZh !== "string" || !e.titleZh.trim()) {
        addUnit(e.id, "manifest.json", "manifest_entry", `${where}（${e.id}）：没有 titleZh`);
      } else {
        u.titleZh = e.titleZh.trim();
        const words = forbiddenWordsIn(e.titleZh);
        if (words.length) {
          addUnit(e.id, "manifest.json", "forbidden_word", `${where}（${e.id}）标题不可以出现：${words.join("、")}`);
        }
        const phone = phoneIn(e.titleZh);
        if (phone) addUnit(e.id, "manifest.json", "phone_number", `${where}（${e.id}）标题疑似电话号码：${phone}`);
      }
      if (!Number.isInteger(e.minutes) || e.minutes <= 0) {
        addUnit(e.id, "manifest.json", "manifest_entry", `${where}（${e.id}）：minutes 要是正整数`);
      }
      if (!Number.isInteger(e.order)) {
        addUnit(e.id, "manifest.json", "manifest_entry", `${where}（${e.id}）：order 要是整数`);
      }
      // 1021 T-R1: part, partTitleZh, icon (optional).
      if (e.part !== undefined && (!Number.isInteger(e.part) || e.part < 1)) {
        addUnit(e.id, "manifest.json", "manifest_entry", `${where}（${e.id}）：part 要是 1 或以上的整数`);
      }
      if (e.partTitleZh !== undefined) {
        if (typeof e.partTitleZh !== "string" || !e.partTitleZh.trim()) {
          addUnit(e.id, "manifest.json", "manifest_entry", `${where}（${e.id}）：partTitleZh 要是文字`);
        } else {
          const pw = forbiddenWordsIn(e.partTitleZh);
          if (pw.length) {
            addUnit(e.id, "manifest.json", "forbidden_word", `${where}（${e.id}）部分标题不可以出现：${pw.join("、")}`);
          }
          const pp = phoneIn(e.partTitleZh);
          if (pp) addUnit(e.id, "manifest.json", "phone_number", `${where}（${e.id}）部分标题疑似电话号码：${pp}`);
          if (Number.isInteger(e.part)) {
            if (partTitles[e.part] === undefined) partTitles[e.part] = e.partTitleZh.trim();
            else if (partTitles[e.part] !== e.partTitleZh.trim()) {
              addUnit(e.id, "manifest.json", "manifest_entry", `${where}（${e.id}）：第 ${e.part} 部分的 partTitleZh 和前面的不一样`);
            }
          }
        }
      }
      if (e.icon !== undefined) {
        if (typeof e.icon !== "string" || !ICON_RE.test(e.icon)) {
          addUnit(e.id, "manifest.json", "manifest_entry", `${where}（${e.id}）：icon 要是 Material Icons 名称（小写字母、数字、_）`);
        } else if (KNOWN_ICONS.indexOf(e.icon) < 0) {
          unit(e.id).notes.push({file: "manifest.json", message: `icon "${e.icon}" App 没有，会显示默认的书本图标`});
        }
      }
      if (html[e.id] === undefined) addUnit(e.id, "manifest.json", "missing_files", `${e.id}：没有 ${e.id}.html`);
      if (txt[e.id] === undefined) addUnit(e.id, "manifest.json", "missing_files", `${e.id}：没有 ${e.id}.txt`);
    });
  }

  for (const id of Object.keys(html).sort()) {
    const f = `${id}.html`;
    for (const p of checkHtml(html[id])) addUnit(id, f, p.code, p.message);
    for (const t of openTargetsIn(html[id])) {
      if (!units[t] || !units[t].inManifest || html[t] === undefined) {
        addUnit(id, f, "open_target_missing", `peizhu://reader/open?id=${t}：这一篇不在 manifest.json 里或没有 .html（撳了会打不开）`);
      }
    }
    if (txt[id] === undefined) addUnit(id, f, "no_txt", `没有同名的 ${id}.txt`);
    if (!unit(id).inManifest) addUnit(id, f, "not_in_manifest", `manifest.json 里没有 "${id}"`);
  }
  for (const id of Object.keys(txt).sort()) {
    const f = `${id}.txt`;
    for (const p of checkTxt(txt[id])) addUnit(id, f, p.code, p.message);
    if (html[id] === undefined) addUnit(id, f, "no_html", `没有同名的 ${id}.html`);
  }
  for (const id of Object.keys(explain).sort()) {
    const f = `${id}${EXPLAIN_SUFFIX}`;
    const r = checkExplain(explain[id]);
    for (const p of r.problems) addUnit(id, f, p.code, p.message);
    for (const n of r.notes) unit(id).notes.push({file: f, message: n});
    if (html[id] === undefined) addUnit(id, f, "no_html", `没有同名的 ${id}.html`);
  }

  // Manifest order first (as the App lists them), then the rest by id.
  const order = {};
  manifestEntries.forEach((e) => {
    order[e.id] = Number.isInteger(e.order) ? e.order : Number.MAX_SAFE_INTEGER;
  });
  const list = Object.keys(units).map((id) => units[id]);
  list.forEach((u) => {
    u.ok = u.problems.length === 0;
  });
  list.sort((a, b) => {
    const ia = a.inManifest ? 0 : 1;
    const ib = b.inManifest ? 0 : 1;
    if (ia !== ib) return ia - ib;
    if (a.inManifest && order[a.id] !== order[b.id]) return order[a.id] - order[b.id];
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
  });
  return {
    ok: general.length === 0 && list.every((u) => u.ok),
    manifestCount: manifestEntries.length,
    manifestEntries: manifestEntries,
    units: list,
    general: general,
  };
}

/**
 * The whole folder as one list of problems (the 1020c shape).
 * @param {string} dir
 * @return {{units: number, problems: Array<{file: string, code: string,
 *     message: string}>}}
 */
function checkReaderDir(dir) {
  const r = checkReaderDirByUnit(dir);
  let problems = r.general.slice();
  for (const u of r.units) problems = problems.concat(u.problems);
  return {units: r.manifestCount, problems: problems};
}

/**
 * Lines describing one problem, for people.
 * @param {{file: string, code: string, message: string}} p
 * @return {string}
 */
function describeProblem(p) {
  const label = ruleLabel(p.code);
  return `${p.file}：${p.message}  [${p.code}]${label ? `（${label}）` : ""}`;
}

/**
 * @param {object} r a checkReaderDirByUnit result
 * @return {{out: Array<string>, err: Array<string>}} the report lines.
 */
function formatReport(r) {
  const out = [];
  const err = [];
  for (const u of r.units) {
    const title = u.titleZh ? `  「${u.titleZh}」` : "";
    if (u.ok) {
      out.push(`  通过    ${u.id}${title}`);
    } else {
      err.push(`  不通过  ${u.id}${title}`);
      for (const p of u.problems) err.push(`          ${describeProblem(p)}`);
    }
    for (const n of u.notes) out.push(`          提示（不影响通过）：${n.file}：${n.message}`);
  }
  if (r.general.length) {
    err.push("  不属于某一个单元的问题：");
    for (const p of r.general) err.push(`          ${describeProblem(p)}`);
  }
  return {out: out, err: err};
}

module.exports = {
  checkReaderDir, checkReaderDirByUnit, checkHtml, checkTxt, checkExplain,
  visibleText, unitFileOf, ruleLabel, describeProblem, formatReport,
  classifyPeizhuLink, openTargetsIn,
  ID_RE, MAX_BYTES, EXPLAIN_SUFFIX, RULES, CTA_CODES, KNOWN_ICONS,
};

if (require.main === module) {
  const dir = process.argv[2] ||
      path.join(__dirname, "..", "assets", "readers");
  const r = checkReaderDirByUnit(dir);
  const lines = formatReport(r);
  if (!r.ok) {
    const passed = r.units.filter((u) => u.ok).length;
    console.error(`小讀本检查不通过（${dir}）：`);
    for (const l of lines.out) console.error(l);
    for (const l of lines.err) console.error(l);
    console.error(`小讀本检查不通过：${passed} 个单元通过，${r.units.length - passed} 个不通过` +
        (r.general.length ? `，另有 ${r.general.length} 个不属于单元的问题` : ""));
    process.exit(1);
  }
  for (const l of lines.out) console.log(l);
  console.log(`小讀本检查通过：${r.manifestCount} 个单元（${dir}）`);
}
