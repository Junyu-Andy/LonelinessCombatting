#!/usr/bin/env node
/**
 * tool/memory_eval/make_rater_csv.js — the sheet for a second, independent
 * rater (T10, 2026-10-07). One row per stored memory item (fact,
 * follow-up, summary) of the given runs. The rating columns are empty and
 * the first rater's labels are NOT included, so the second rating is blind.
 *
 *   node tool/memory_eval/make_rater_csv.js --runs=t10_run3,t10_run4 \
 *     --out=tool/memory_eval/second_rater_t10.csv
 *
 * row_key joins back to adjudication/<run>.json and results/<run>/appendix.md
 * (same "<dialogue>|<kind>|<text>" key score.js uses).
 */
"use strict";
/* eslint-disable require-jsdoc, max-len */

const fs = require("fs");
const path = require("path");

const arg = (n, d) => {
  const hit = process.argv.find((a) => a.startsWith(`--${n}=`));
  return hit ? hit.slice(n.length + 3) : d;
};
const runs = arg("runs", "t10_run3,t10_run4").split(",");
const out = arg("out", path.join(__dirname, "second_rater_t10.csv"));

const cell = (v) => {
  const s = v === undefined || v === null ? "" : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, "\"\"")}"` : s;
};
const header = ["row_no", "run", "dialogue", "dialogue_file", "persona",
  "agent", "layer", "content", "quote", "category", "sensitivity", "status",
  "visibility", "due_date", "row_key",
  "rating（correct/unlisted_true/wrong/wrong_date/fabricated/forbidden_stored；摘要用 ok/fabricated/sensitive/forbidden_stored）",
  "fabricated_type（hypothetical_joke/misattributed/invented）", "note"];
const rows = [header.map(cell).join(",")];
let n = 0;
for (const run of runs) {
  const raw = JSON.parse(fs.readFileSync(path.join(__dirname, "results", run, "raw.json"), "utf8"));
  for (const r of raw.extraction) {
    const base = [run, r.id, `tool/memory_eval/dialogues/${r.id}.json`, r.persona];
    for (const f of r.facts) {
      rows.push([++n, ...base, f.agent_id, "fact", `${f.key}：${f.value}`, f.quote,
        f.category, f.sensitivity, f.status, f.visibility, "",
        `${r.id}|fact|${f.key} ${f.value}`, "", "", ""].map(cell).join(","));
    }
    for (const u of r.followups) {
      rows.push([++n, ...base, u.agent_id, "followup", u.description, u.quote,
        "", u.sensitivity, u.status, "agent", u.due_date,
        `${r.id}|followup|${u.description}@${u.due_date}`, "", "", ""].map(cell).join(","));
    }
    for (const s of r.summaries) {
      rows.push([++n, ...base, s.agent_id, "summary", s.summary, "",
        "", s.sensitivity, "", "agent", "",
        `${r.id}|summary|${s.summary}`, "", "", ""].map(cell).join(","));
    }
  }
}
// BOM so Excel opens the Chinese text correctly.
fs.writeFileSync(out, "﻿" + rows.join("\n") + "\n");
console.log(`wrote ${n} rows to ${path.relative(process.cwd(), out)}`);
