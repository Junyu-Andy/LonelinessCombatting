// T6 — 词库检测：直接从 lib/core/safety/distress_detector.dart 源码读出词表，
// 按 DistressDetector.analyze 的同一顺序（acute → 绝望族[按 hopelessnessTier]
// → moderate_interrupt → moderate_review → low）做小写子串匹配，首个命中即返回。
// 不在这里手抄词表，避免和线上版本不一致。仅供本次评估使用，不进 lib/ 或 functions/。
"use strict";
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "../../..");
const SRC = path.join(ROOT, "lib/core/safety/distress_detector.dart");

function stringsIn(block) {
  const out = [];
  const re = /'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"/g;
  // Drop line comments first so quoted words in comments are not read as terms.
  const code = block.split("\n").map((l) => l.replace(/\/\/.*$/, "")).join("\n");
  let m;
  while ((m = re.exec(code)) !== null) out.push((m[1] !== undefined ? m[1] : m[2]).replace(/\\'/g, "'"));
  return out;
}

function parseGroups(src, constName) {
  const start = src.indexOf(`static const ${constName} = <_TermGroup>[`);
  if (start < 0) throw new Error(`missing ${constName}`);
  const end = src.indexOf("\n  ];", start);
  const body = src.slice(start, end);
  const groups = [];
  const re = /_TermGroup\(DistressLevel\.(\w+), DistressCategory\.(\w+), \[([\s\S]*?)\]\),/g;
  let m;
  while ((m = re.exec(body)) !== null) groups.push({level: m[1], category: m[2], terms: stringsIn(m[3])});
  return groups;
}

function load() {
  const src = fs.readFileSync(SRC, "utf8");
  const version = /wordlistVersion = '([^']+)'/.exec(src)[1];
  const hopeTier = /hopelessnessTier = DistressLevel\.(\w+);/.exec(src)[1];
  const hopeBody = /_hopelessnessTerms = \[([\s\S]*?)\];/.exec(src)[1];
  const hope = {level: hopeTier, category: "distress", terms: stringsIn(hopeBody)};
  const acute = parseGroups(src, "_acuteGroups");
  const mi = parseGroups(src, "_moderateInterruptGroups");
  const mr = parseGroups(src, "_moderateReviewGroups");
  const low = parseGroups(src, "_lowGroups");
  const ordered = [
    ...(hopeTier === "acute" ? [hope] : []), ...acute,
    ...(hopeTier === "moderateInterrupt" ? [hope] : []), ...mi,
    ...(hopeTier === "moderateReview" ? [hope] : []), ...mr,
    ...(hopeTier === "low" ? [hope] : []), ...low,
  ];
  return {version, hopeTier, ordered};
}

const TIER_CODE = {acute: "acute", moderateInterrupt: "moderate_interrupt",
  moderateReview: "moderate_review", low: "low"};

function analyze(lex, text) {
  if (!text || !text.trim()) return {tier: "none", term: null, category: null};
  const lower = text.toLowerCase();
  for (const g of lex.ordered) {
    for (const t of g.terms) {
      if (lower.includes(t.toLowerCase())) return {tier: TIER_CODE[g.level], term: t, category: g.category};
    }
  }
  return {tier: "none", term: null, category: null};
}

module.exports = {load, analyze};

if (require.main === module) {
  const lex = load();
  const counts = {};
  for (const g of lex.ordered) counts[g.level] = (counts[g.level] || 0) + g.terms.length;
  console.log(`wordlistVersion=${lex.version} hopelessnessTier=${lex.hopeTier}`);
  console.log("terms per tier:", JSON.stringify(counts));
  const {sentences} = JSON.parse(fs.readFileSync(path.join(__dirname, "sentences.json"), "utf8"));
  const rows = sentences.map((s) => ({...s, lexicon: analyze(lex, s.text)}));
  for (const r of rows) console.log(`${r.id}\t${r.intended}\t${r.lexicon.tier}\t${r.lexicon.term || "-"}\t${r.text}`);
  fs.writeFileSync(path.join(__dirname, "results_lexicon.json"),
      JSON.stringify({wordlistVersion: lex.version, hopelessnessTier: lex.hopeTier, termsPerTier: counts, rows}, null, 2) + "\n");
}
