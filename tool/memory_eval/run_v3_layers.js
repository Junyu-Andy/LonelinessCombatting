/**
 * T31: run extraction prompt v3 once over the 30 T4 synthetic dialogues
 * and list which layer every fact lands in (shared / private).
 *
 * Uses the server's own code (functions/memory.js): screenTurns, the v3
 * prompt, validateExtraction with the v3 categories and the T10 options,
 * layerFor. No Firestore: each dialogue starts with no existing facts.
 * Sessions the server would not send to the model (「唔好記住」, only
 * flagged turns) are skipped without a call, as in production.
 *
 *   NODE_USE_ENV_PROXY=1 node tool/memory_eval/run_v3_layers.js --run=t31_v3_run1
 *   node tool/memory_eval/run_v3_layers.js --run=t31_v3_run1 --mode=replay
 *
 * Request body = callDeepSeekJsonFor in functions/index.js. Every live
 * call is counted in results/ledger_t31.json (at most 3 per dialogue).
 * The API key is a placeholder; the session proxy injects the real one.
 */
"use strict";
/* eslint-disable require-jsdoc */

const fs = require("fs");
const path = require("path");
const m = require("../../functions/memory");

const HERE = __dirname;
const arg = (k, d) => {
  const hit = process.argv.find((a) => a.startsWith(`--${k}=`));
  return hit ? hit.slice(k.length + 3) : d;
};
const RUN = arg("run", "t31_v3_run1");
const MODE = arg("mode", "live");
const PROMPT = "memory_extraction.v3";
const MAX_CALLS = 3;
const OUT = path.join(HERE, "results", RUN);
const LEDGER = path.join(HERE, "results", "ledger_t31.json");

if (MODE === "live" && process.env.NODE_USE_ENV_PROXY !== "1") {
  console.error("live mode needs NODE_USE_ENV_PROXY=1");
  process.exit(1);
}

const ledger = fs.existsSync(LEDGER) ?
  JSON.parse(fs.readFileSync(LEDGER, "utf8")) : {calls: {}};
const saveLedger = () => fs.writeFileSync(LEDGER,
    JSON.stringify(ledger, null, 2) + "\n");

async function callModel(id, prompt) {
  const used = ledger.calls[id] || 0;
  if (used >= MAX_CALLS) throw new Error(`call cap reached for ${id}`);
  ledger.calls[id] = used + 1;
  saveLedger();
  const t0 = Date.now();
  const res = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: {"Content-Type": "application/json",
      "Authorization": `Bearer ${process.env.DEEPSEEK_API_KEY ||
        "placeholder"}`},
    body: JSON.stringify({
      model: "deepseek-flash",
      thinking: {type: "disabled"},
      messages: [
        {role: "system", content: prompt.system},
        {role: "user", content: prompt.user},
      ],
      response_format: {type: "json_object"},
      temperature: 0.2,
      max_tokens: 1500,
    }),
  });
  const body = await res.json();
  return {
    text: (body.choices && body.choices[0].message.content) || "",
    call: {dialogue: id, http_status: res.status, returned_model: body.model,
      system_fingerprint: body.system_fingerprint || null,
      usage: body.usage || null, latency_ms: Date.now() - t0,
      at: new Date().toISOString()},
  };
}

(async () => {
  const replay = MODE === "replay" ? JSON.parse(fs.readFileSync(
      path.join(OUT, "raw.json"), "utf8")).dialogues : [];
  const files = fs.readdirSync(path.join(HERE, "dialogues")).sort();
  const results = [];
  const calls = [];
  for (const f of files) {
    const d = JSON.parse(fs.readFileSync(path.join(HERE, "dialogues", f)));
    const todayKey = d.hkt_time.slice(0, 10);
    const turns = d.turns.map((t) => ({fromUser: t.role === "user",
      text: t.text}));
    const screened = m.screenTurns(turns, {excludeSafety: true, forget: true});
    const row = {id: d.id, agent: d.agent, tags: d.tags};
    if (screened.forget || !screened.turns.some((t) => t.fromUser)) {
      row.skipped = screened.forget ? "forget_request" : "nothing_left";
      results.push(row);
      continue;
    }
    const prompt = m.buildExtractionPrompt({turns: screened.turns,
      activeFacts: [], todayKey, promptName: PROMPT});
    let raw;
    if (MODE === "replay") {
      raw = replay.find((r) => r.id === d.id).raw_output;
    } else {
      const out = await callModel(d.id, prompt);
      raw = out.text;
      calls.push(out.call);
    }
    row.raw_output = raw;
    let parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      row.error = "invalid_json";
    }
    if (parsed) {
      const v = m.validateExtraction(parsed, {turns: screened.turns,
        todayKey, activeFactIds: new Set(), activeFactCategories: new Map(),
        strictFacts: true, excludeSafety: true,
        safetyTurns: screened.safetyTurns, omitSensitiveSummary: true,
        categories: m.categoriesFor(PROMPT)});
      if (!v.ok) {
        row.error = v.error;
      } else {
        row.facts = v.facts.map((x) => ({category: x.category, key: x.key,
          value: x.value, sensitivity: x.sensitivity,
          layer: m.layerFor(x.category, x.sensitivity)}));
        row.followups = v.followups.map((x) => ({description: x.description,
          due_date: x.due_date, layer: "private"}));
        row.summary = v.summary;
        row.dropped = v.dropped.map((x) => `${x.kind}:${x.reason}`);
      }
    }
    results.push(row);
    console.log(`${d.id} ${row.error || `${(row.facts || []).length} facts`}`);
  }

  fs.mkdirSync(OUT, {recursive: true});
  if (MODE === "live") {
    fs.writeFileSync(path.join(OUT, "raw.json"), JSON.stringify(
        {prompt: PROMPT, calls, dialogues: results}, null, 2) + "\n");
  }

  // Markdown table for the report.
  const lines = [`# ${RUN}：抽取 prompt v3 的分层结果`, "",
    "层由服务器按类目和敏感判断决定（`functions/memory.js` `layerFor`），" +
    "不是模型决定的。敏感的条目要老人在「我記得嘅嘢」确认后才会用。", "",
    "| 对话 | 陪伴者 | 类目 | 标题：内容 | 敏感 | 层 |", "|---|---|---|---|---|---|"];
  const count = {shared: 0, private: 0};
  const byCat = {};
  for (const r of results) {
    if (r.skipped || r.error) {
      lines.push(`| ${r.id} | ${r.agent} | — | ` +
        `${r.skipped ? `没有调用模型（${r.skipped}）` : `出错：${r.error}`}` +
        " | — | — |");
      continue;
    }
    if (!r.facts.length) {
      lines.push(`| ${r.id} | ${r.agent} | — | 没有事实 | — | — |`);
    }
    for (const x of r.facts) {
      count[x.layer]++;
      byCat[x.category] = byCat[x.category] || {shared: 0, private: 0};
      byCat[x.category][x.layer]++;
      lines.push(`| ${r.id} | ${r.agent} | ${x.category} | ` +
        `${x.key}：${x.value} | ${x.sensitivity === "normal" ? "" : "是"} | ` +
        `${x.layer === "shared" ? "共享" : "私有"} |`);
    }
    for (const x of r.followups) {
      lines.push(`| ${r.id} | ${r.agent} | 待跟进 | ${x.description}` +
        `（${x.due_date}） |  | 私有 |`);
    }
  }
  lines.push("", `合计事实：共享 ${count.shared} 条，私有 ${count.private} 条。`,
      "", "| 类目 | 共享 | 私有 |", "|---|---|---|");
  for (const [c, n] of Object.entries(byCat).sort()) {
    lines.push(`| ${c} | ${n.shared} | ${n.private} |`);
  }
  fs.writeFileSync(path.join(OUT, "layers.md"), lines.join("\n") + "\n");
  console.log(`calls: ${calls.length}; shared ${count.shared}, ` +
    `private ${count.private}`);
})();
