#!/usr/bin/env node
/**
 * tool/memory_profiles/analyze.js — turn results/<run>/<profile>.json into
 * the numbers in docs/dev-reports/T16-memory-profiles-20261007.md.
 *
 *   node tool/memory_profiles/analyze.js --run=full
 * Writes results/<run>/summary.json and prints the tables (markdown).
 */
"use strict";
/* eslint-disable require-jsdoc, max-len */

const fs = require("fs");
const path = require("path");
const {CONTRADICTIONS, PROFILES, dayKey} = require("./profiles.js");

const RUN = (process.argv.find((a) => a.startsWith("--run=")) || "--run=full").slice(6);
const DIR = path.join(__dirname, "results", RUN);
const MAX_CHARS = 2000;

const q = (arr, p) => {
  if (!arr.length) return null;
  const s = arr.slice().sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor(p * s.length))];
};
const sum = (arr, f) => arr.reduce((a, x) => a + (f ? f(x) : x), 0);
const has = (t, groups) => groups.every((g) => g.some((k) => String(t || "").includes(k)));

/** Least squares: prompt = a_agent + kb·blockChars + kh·historyChars. */
function fitTokens(rows) {
  const agents = [...new Set(rows.map((r) => r.agent))];
  const X = rows.map((r) => [...agents.map((a) => (a === r.agent ? 1 : 0)), r.block, r.hist]);
  const y = rows.map((r) => r.prompt);
  const n = X[0].length;
  const A = Array.from({length: n}, () => new Array(n + 1).fill(0));
  X.forEach((x, i) => {
    for (let j = 0; j < n; j++) {
      for (let k = 0; k < n; k++) A[j][k] += x[j] * x[k];
      A[j][n] += x[j] * y[i];
    }
  });
  for (let c = 0; c < n; c++) { // Gauss-Jordan
    let p = c;
    for (let r = c + 1; r < n; r++) if (Math.abs(A[r][c]) > Math.abs(A[p][c])) p = r;
    [A[c], A[p]] = [A[p], A[c]];
    for (let r = 0; r < n; r++) {
      if (r === c || !A[c][c]) continue;
      const f = A[r][c] / A[c][c];
      for (let k = c; k <= n; k++) A[r][k] -= f * A[c][k];
    }
  }
  const b = A.map((row, i) => row[n] / row[i]);
  const base = Object.fromEntries(agents.map((a, i) => [a, Math.round(b[i])]));
  return {base, perBlockChar: b[agents.length], perHistoryChar: b[agents.length + 1]};
}

const out = {run: RUN, profiles: {}};
const chatRows = [];
const data = [];
for (const p of PROFILES) {
  const f = path.join(DIR, `${p.id}.json`);
  if (!fs.existsSync(f)) continue;
  const r = JSON.parse(fs.readFileSync(f, "utf8"));
  data.push({p, r});
  for (const s of r.sessions) {
    let hist = 0;
    s.transcript.forEach((t, i) => {
      hist += t.user.length;
      const c = r.calls.find((x) => x.kind === "chat" && x.session === s.index && x.turn === i && x.prompt);
      if (c) {
        chatRows.push({agent: s.agent, prompt: c.prompt, hist,
          block: i === 0 ? s.inject_start.chars : s.inject_later.chars});
      }
      hist += (t.reply || "").length;
    });
  }
}
const fit = fitTokens(chatRows);
out.token_fit = Object.assign({rows: chatRows.length}, fit);

for (const {p, r} of data) {
  const S = r.sessions;
  const end = S.length ? S[S.length - 1] : null;
  const calls = r.calls;
  const kinds = {};
  for (const c of calls) {
    const k = kinds[c.kind] = kinds[c.kind] || {calls: 0, input_hit: 0, input_miss: 0, output: 0, lat: [], errors: 0};
    k.calls++;
    k.input_hit += c.hit || 0;
    k.input_miss += c.miss || 0;
    k.output += c.completion || 0;
    k.lat.push(c.latency_ms);
    if (c.http !== 200) k.errors++;
  }
  for (const k of Object.values(kinds)) {
    k.latency_p50 = q(k.lat, 0.5);
    k.latency_p95 = q(k.lat, 0.95);
    k.latency_max = Math.max(...k.lat);
    delete k.lat;
  }
  const product = ["chat", "extraction"].map((k) => kinds[k] || {input_hit: 0, input_miss: 0, output: 0, calls: 0});
  const totals = {calls: sum(product, (k) => k.calls), input_hit: sum(product, (k) => k.input_hit),
    input_miss: sum(product, (k) => k.input_miss), output: sum(product, (k) => k.output)};
  totals.total = totals.input_hit + totals.input_miss + totals.output;

  // Weekly trajectory: state after the last session of each week.
  const weeks = [0, 1, 2, 3].map((w) => {
    const inWeek = S.filter((s) => Math.floor(s.day / 7) === w);
    const upTo = S.filter((s) => Math.floor(s.day / 7) <= w);
    const last = upTo[upTo.length - 1];
    const blocks = inWeek.map((s) => s.inject_start.chars);
    return {week: w + 1, sessions: inWeek.length,
      user_turns: sum(inWeek, (s) => s.turns),
      state: last ? last.state_after : null,
      block_chars_avg: blocks.length ? Math.round(sum(blocks) / blocks.length) : 0,
      block_chars_max: blocks.length ? Math.max(...blocks) : 0,
      over_budget_sessions: inWeek.filter((s) => s.inject_start.chars_untrimmed > MAX_CHARS).length,
      block_tokens_avg: blocks.length ? Math.round(fit.perBlockChar * sum(blocks) / blocks.length) : 0};
  });

  // Injection: over budget, what was cut, layer caps.
  const over = S.filter((s) => s.inject_start.chars_untrimmed > MAX_CHARS || s.inject_later.chars_untrimmed > MAX_CHARS);
  const cutLayers = {};
  for (const s of over) for (const c of s.inject_start.cut) cutLayers[c.layer] = (cutLayers[c.layer] || 0) + 1;
  const cutExamples = over.length ? over[over.length - 1].inject_start.cut.slice(0, 6) : [];
  const factCap = S.filter((s) => s.inject_start.facts_usable_normal > 20).length;
  const emptyBlock = S.filter((s) => s.inject_start.chars === 0).length;
  const blocksAll = S.map((s) => s.inject_start.chars);

  // Extraction.
  const ext = {sessions: S.length,
    done: S.filter((s) => s.extraction.status === "done").length,
    failed: S.filter((s) => s.extraction.status !== "done").map((s) => ({s: s.index, status: s.extraction.status, error: s.extraction.error})),
    retries: sum(S, (s) => s.extraction.retries || 0),
    with_summary: S.filter((s) => s.summary).length,
    dropped: S.reduce((a, s) => {
      for (const d of s.extraction.dropped || []) a[`${d.kind}:${d.reason}`] = (a[`${d.kind}:${d.reason}`] || 0) + 1;
      return a;
    }, {}),
    e2e_p50: q(S.map((s) => s.extraction.e2e_ms), 0.5),
    e2e_p95: q(S.map((s) => s.extraction.e2e_ms), 0.95),
    facts_per_session: S.length ? +(sum(S, (s) => s.new_facts.length) / S.length).toFixed(1) : 0};

  // Planted lines.
  const planted = S.flatMap((s) => s.planted.map((x) => Object.assign({session: s.index, turns: s.turns}, x)));
  const captured = (x) => !!(x.fact || x.followup);
  const inBuf = planted.filter((x) => x.in_buffer && x.kind !== "dont_store");
  const outBuf = planted.filter((x) => !x.in_buffer && x.kind !== "dont_store");
  const plantedStats = {total: planted.length,
    in_buffer: inBuf.length, in_buffer_captured: inBuf.filter(captured).length,
    in_buffer_in_summary: inBuf.filter((x) => x.in_summary).length,
    out_of_buffer: outBuf.length, out_of_buffer_captured: outBuf.filter(captured).length,
    out_of_buffer_in_summary: outBuf.filter((x) => x.in_summary).length,
    lost_examples: outBuf.filter((x) => !captured(x) && !x.in_summary).map((x) => `${x.id}（第${x.pos + 1}/${x.turns}句）`)};

  // Follow-ups.
  const fuPlanted = planted.filter((x) => x.kind === "followup");
  const selected = S.flatMap((s) => s.inject_start.followups_selected.map((f) => Object.assign({session: s.index, date: s.date, agent: s.agent}, f)));
  const fuFinal = r.final.followups;
  const lastDate = end ? end.date : dayKey(27);
  const followups = {planted: fuPlanted.length,
    created: fuPlanted.filter((x) => x.followup).length,
    due_correct: fuPlanted.filter((x) => x.followup && x.followup.due === x.followup.expected_due).length,
    due_wrong: fuPlanted.filter((x) => x.followup && x.followup.due !== x.followup.expected_due).map((x) => `${x.id}: ${x.followup.due}（应为 ${x.followup.expected_due}）`),
    created_total: fuFinal.length,
    injected: selected.length,
    final_asked: fuFinal.filter((f) => f.status === "asked").length,
    final_pending_lapsed: fuFinal.filter((f) => f.status === "pending" && f.due < shift(lastDate, -7)).length,
    final_pending_future: fuFinal.filter((f) => f.status === "pending" && f.due > lastDate).length,
    final_pending_sensitive: fuFinal.filter((f) => f.status === "pending" && f.sensitivity !== "normal").length,
    selected_list: selected.map((f) => `${f.date} ${f.agent}: ${f.description}（${f.due}）`)};
  // Same planted event asked more than once.
  const dupAsk = [];
  for (const x of fuPlanted) {
    const hits = selected.filter((f) => has(f.description, x.match));
    if (hits.length > 1) dupAsk.push(`${x.id} ×${hits.length}`);
  }
  followups.asked_more_than_once = dupAsk;

  // Staleness, contradictions, do-not-store, PII.
  const staleSummary = S.filter((s) => s.inject_start.summary_days_used.some((d) => d < shift(s.date, -7)));
  const relWords = /聽日|後日|下個禮拜|下星期|下個月|今日|琴日|今朝|今晚|呢排|最近/;
  const activeFacts = r.final.facts.filter((f) => f.status === "active");
  const staleFacts = activeFacts.filter((f) => relWords.test(`${f.key}${f.value}`));
  const contradictions = (CONTRADICTIONS[p.id] || []).map((c) => {
    const live = r.final.facts.filter((f) => ["active", "pending_confirmation"].includes(f.status));
    const a = live.filter((f) => has(`${f.key} ${f.value}`, c.aMatch));
    const b = live.filter((f) => has(`${f.key} ${f.value}`, c.bMatch));
    return {note: c.note, both_live: a.length > 0 && b.length > 0,
      a: a.map((f) => `${f.key}：${f.value}`).slice(0, 2), b: b.map((f) => `${f.key}：${f.value}`).slice(0, 2)};
  });
  const dontStore = planted.filter((x) => x.kind === "dont_store").map((x) => {
    const live = r.final.facts.filter((f) => ["active", "pending_confirmation"].includes(f.status) && has(`${f.key} ${f.value}`, x.match));
    const sums = r.final.summaries.filter((s) => has(s.summary, x.match));
    return {id: x.id, facts_live: live.map((f) => `${f.key}：${f.value}（${f.status}）`), summaries: sums.length};
  });
  const piiPatterns = /9123|4567|6987|6543|123456|忠孝街|\[PHONE\]|\[ID\]/;
  const pii = [...r.final.facts.map((f) => `${f.key}：${f.value}`), ...r.final.summaries.map((s) => s.summary),
    ...r.final.followups.map((f) => f.description)].filter((t) => piiPatterns.test(t));
  // Summary chars injected for agents rarely used: any session whose agent
  // had summaries but none loaded (orderBy ended_at limit 30).
  const summaryMissing = S.filter((s) => s.inject_start.summary_days_available === 0 &&
    S.some((o) => o.index < s.index && o.agent === s.agent && o.summary)).map((s) => `${s.date} ${s.agent}`);

  out.profiles[p.id] = {label: p.label, sessions: S.length, stopped: r.stopped,
    user_turns: sum(S, (s) => s.turns), confirmations: r.confirmations,
    kinds, totals, weeks,
    injection: {block_chars_avg: blocksAll.length ? Math.round(sum(blocksAll) / blocksAll.length) : 0,
      block_chars_max: blocksAll.length ? Math.max(...blocksAll) : 0,
      block_tokens_avg: Math.round(fit.perBlockChar * (blocksAll.length ? sum(blocksAll) / blocksAll.length : 0)),
      block_tokens_max: Math.round(fit.perBlockChar * (blocksAll.length ? Math.max(...blocksAll) : 0)),
      untrimmed_max: Math.max(0, ...S.map((s) => s.inject_start.chars_untrimmed)),
      sessions_over_budget: over.length, cut_layers: cutLayers, cut_examples: cutExamples,
      sessions_fact_cap_hit: factCap, sessions_empty_block: emptyBlock,
      // Tokens of memory sent over the whole period (every turn re-sends it).
      memory_chars_sent: sum(S, (s) => s.inject_start.chars + s.inject_later.chars * (s.turns - 1)),
      memory_tokens_sent_est: Math.round(fit.perBlockChar * sum(S, (s) => s.inject_start.chars + s.inject_later.chars * (s.turns - 1)))},
    extraction: ext, planted: plantedStats, followups,
    problems: {stale_summary_sessions: staleSummary.length,
      stale_summary_example: staleSummary.length ? `${staleSummary[0].date} 注入了 ${staleSummary[0].inject_start.summary_days_used.join("、")} 的摘要` : null,
      stale_relative_date_facts: staleFacts.map((f) => `${f.key}：${f.value}`),
      needs_review_facts: r.final.facts.filter((f) => f.needs_review).map((f) => `${f.key}：${f.value}`),
      contradictions, dont_store: dontStore, pii, summary_missing_for_agent: summaryMissing},
    final_counts: end ? end.state_after : null};
}

function shift(date, days) {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * 86400000).toISOString().slice(0, 10);
}

fs.writeFileSync(path.join(DIR, "summary.json"), JSON.stringify(out, null, 1) + "\n");

// --- print -------------------------------------------------------------------
console.log(`token fit (${chatRows.length} chat calls): base`, fit.base,
    `per block char ${fit.perBlockChar.toFixed(3)}, per history char ${fit.perHistoryChar.toFixed(3)}`);
for (const [id, x] of Object.entries(out.profiles)) {
  console.log(`\n### ${id} ${x.label}: ${x.sessions} sessions, ${x.user_turns} turns${x.stopped ? " STOPPED " + x.stopped : ""}`);
  console.log("| 周 | 会话 | 有效事实 | 待确认 | 被取代 | 摘要条数 | 摘要平均字数 | 待跟进 | 已问 | 记忆块平均字 | 最大 | 约 token | 超预算会话 |");
  console.log("|---|---|---|---|---|---|---|---|---|---|---|---|---|");
  for (const w of x.weeks) {
    const s = w.state || {};
    console.log(`| ${w.week} | ${w.sessions} | ${s.facts_active} | ${s.facts_pending_confirmation} | ${s.facts_superseded} | ${s.summaries} | ${s.summary_chars_avg} | ${s.followups_pending} | ${s.followups_asked} | ${w.block_chars_avg} | ${w.block_chars_max} | ${w.block_tokens_avg} | ${w.over_budget_sessions} |`);
  }
  console.log(JSON.stringify({kinds: x.kinds, totals: x.totals}, null, 0));
  console.log(JSON.stringify({injection: x.injection, extraction: x.extraction, planted: x.planted}, null, 0));
  console.log(JSON.stringify({followups: x.followups, problems: x.problems}, null, 0));
}
