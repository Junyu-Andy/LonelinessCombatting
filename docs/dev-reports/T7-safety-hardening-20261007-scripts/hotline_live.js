// T7 — live check of the hotline rule + filter (20 DeepSeek calls).
// Same request shape as proxyDeepSeek (siu_yan_v1, m2_check_in, deepseek-flash,
// thinking off) with functions/prompts/hotline_rule.v1.txt appended.  Each
// reply is run through functions/hotline_filter.js.  The API key is a
// placeholder: the environment's proxy injects the real one.
// Run:  NODE_USE_ENV_PROXY=1 node docs/dev-reports/T7-safety-hardening-20261007-scripts/hotline_live.js
"use strict";
const fs = require("fs");
const path = require("path");
const ROOT = path.resolve(__dirname, "../../..");
const hf = require(path.join(ROOT, "functions/hotline_filter.js"));
const sentences = JSON.parse(fs.readFileSync(path.join(ROOT,
    "docs/dev-reports/T6-safety-parity-20261006-scripts/sentences.json"),
"utf8")).sentences;
const persona = fs.readFileSync(path.join(ROOT,
    "functions/prompts/siu_yan_v1.txt"), "utf8")
    .split("{{VARIANT_NAME}}").join("阿珍／阿伯");
const rule = fs.readFileSync(path.join(ROOT,
    "functions/prompts/hotline_rule.v1.txt"), "utf8");
const system = `${persona}\n\n[模組] m2_check_in\n\n${rule}`;

(async () => {
  const rows = [];
  for (const s of sentences) {
    const t0 = Date.now();
    const res = await fetch("https://api.deepseek.com/chat/completions", {
      method: "POST",
      headers: {"Content-Type": "application/json",
        "Authorization": "Bearer placeholder"},
      body: JSON.stringify({
        model: "deepseek-flash", thinking: {type: "disabled"},
        messages: [{role: "system", content: system},
          {role: "user", content: s.text}],
        max_tokens: 800, temperature: 0.7, top_p: 0.95,
      }),
    });
    const ms = Date.now() - t0;
    if (!res.ok) {
      rows.push({id: s.id, error: `HTTP ${res.status}`});
      continue;
    }
    const data = await res.json();
    const text = data.choices[0].message.content || "";
    const f = hf.filterHotlines(text);
    const row = {
      id: s.id, model: data.model, ms,
      tokenWritten: text.includes(hf.HOTLINE_TOKEN),
      numbersReplaced: f.count,
      approved: hf.summarise(f.items).approved_count,
      numberLeftAfterFilter: /\d{4}\s?\d{4}|999/.test(f.text),
      reply: text, filtered: f.text,
    };
    rows.push(row);
    console.log(`${s.id} ${data.model} ${ms}ms token=${row.tokenWritten} ` +
      `replaced=${f.count} left=${row.numberLeftAfterFilter}`);
  }
  fs.writeFileSync(path.join(__dirname, "results_hotline_live.json"),
      JSON.stringify({runAt: new Date().toISOString(),
        requested: "deepseek-flash (thinking off)", rows}, null, 2) + "\n");
})();
