#!/usr/bin/env node
/**
 * tool/memory_profiles/run_profiles.js — memory usage profiles (T16).
 *
 * Simulates four weeks of use for one synthetic profile (profiles.js) on the
 * Firestore emulator, through the REAL server code, in the same way as
 * tool/memory_eval/run_eval.js (T4):
 *   - companion replies:  functions/index.js proxyDeepSeek → DeepSeek (real)
 *     (memory injection = memory.injectMemory inside it)
 *   - extraction/summary: functions/index.js memoryEndSession → DeepSeek (real)
 * Only the elder's side is scripted: planted lines are fixed text from
 * profiles.js; the other elder lines of a session come from ONE extra
 * DeepSeek call per session (call kind "elder_script", not part of the
 * product and reported separately).
 *
 * "Now" is a fixed simulated clock (memory.js already takes a `now`);
 * day 0 = 2026-10-07 HKT.
 *
 * The App keeps at most 20 messages in the memory buffer
 * (lib/core/agent_context/agent_context_service.dart, bufferCap = 20) and
 * calls memoryEndSession when the user leaves the chat page; we do the same.
 *
 * Usage (repo root, emulator already running):
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 NODE_USE_ENV_PROXY=1 \
 *     node tool/memory_profiles/run_profiles.js --profile=P1_light \
 *     --run=pilot [--sessions=2] [--max-calls=100]
 */
"use strict";
/* eslint-disable require-jsdoc, max-len */

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "../..");
const FN = path.join(ROOT, "functions");
const PROJECT = "demo-t16memprof";

function arg(name, dflt) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : dflt;
}
const PROFILE_ID = arg("profile", "P1_light");
const RUN = arg("run", "pilot");
const MAX_SESSIONS = Number(arg("sessions", "0")) || Infinity;
const MAX_CALLS = Number(arg("max-calls", "100"));

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — start the emulator first.");
  process.exit(1);
}
if (process.env.NODE_USE_ENV_PROXY !== "1") {
  console.error("needs NODE_USE_ENV_PROXY=1 (Node fetch ignores the proxy otherwise).");
  process.exit(1);
}
process.env.GCLOUD_PROJECT = PROJECT;
process.env.GOOGLE_CLOUD_PROJECT = PROJECT;
// Placeholder only; the session proxy swaps in the real key.
if (!process.env.DEEPSEEK_API_KEY) process.env.DEEPSEEK_API_KEY = "placeholder";

const req = (m) => require(path.join(FN, "node_modules", m));
const fft = req("firebase-functions-test")({projectId: PROJECT});
const admin = req("firebase-admin");
const {PROFILES, dayKey, weekday} = require("./profiles.js");
const PROFILE = PROFILES.find((p) => p.id === PROFILE_ID);
if (!PROFILE) throw new Error(`unknown profile ${PROFILE_ID}`);

// --- fixed clock (same patch as T4) -----------------------------------------
const memory = require(path.join(FN, "memory.js"));
const CLOCK = {now: null};
const origProcess = memory.processExtraction;
const origInject = memory.injectMemory;
memory.processExtraction = (db, uid, id, callModel, now) =>
  origProcess(db, uid, id, callModel, now || CLOCK.now || undefined);
memory.injectMemory = (db, a) =>
  origInject(db, Object.assign({}, a, {now: a.now || CLOCK.now || undefined}));

// --- DeepSeek call recorder + budget -----------------------------------------
const realFetch = global.fetch;
const CALLS = [];
const CTX = {tag: null};
let budgetUsed = 0;

async function deepseek(url, init, kind) {
  if (budgetUsed >= MAX_CALLS) throw new Error(`call budget ${MAX_CALLS} reached`);
  budgetUsed++;
  const t0 = Date.now();
  const res = await realFetch(url, init);
  const text = await res.text();
  const rec = Object.assign({kind, http: res.status, latency_ms: Date.now() - t0},
      CTX.tag || {});
  try {
    const j = JSON.parse(text);
    const u = j.usage || {};
    rec.model = j.model;
    rec.prompt = u.prompt_tokens;
    rec.completion = u.completion_tokens;
    rec.hit = u.prompt_cache_hit_tokens;
    rec.miss = u.prompt_cache_miss_tokens;
  } catch (_) {
    rec.body = text.slice(0, 200);
  }
  CALLS.push(rec);
  return new Response(text, {status: res.status,
    headers: {"Content-Type": "application/json"}});
}

global.fetch = async (url, init) => {
  const u = String(url);
  if (!u.startsWith("https://api.deepseek.com/")) return realFetch(url, init);
  const body = JSON.parse(init.body);
  const kind = body.response_format ? "extraction" : "chat";
  return deepseek(url, init, kind);
};

const fns = require(path.join(FN, "index.js"));
const db = admin.firestore();
const endSession = fft.wrap(fns.memoryEndSession);
const proxy = fft.wrap(fns.proxyDeepSeek);

const SURFACE = {
  siu_yan: {moduleId: "m2_check_in", promptKey: "siu_yan_v1"},
  ah_jan_ah_bak: {moduleId: "reflective_dialogue",
    promptKey: "ah_jan_ah_bak_v1", variantName: "阿珍"},
  tung_tung: {moduleId: "tung_tung_chat", promptKey: "tung_tung_v1"},
};
const NAME = {siu_yan: "小欣", ah_jan_ah_bak: "阿珍", tung_tung: "通通"};
const BUFFER_CAP = 20;
const hkt = (date, time) => new Date(`${date}T${time}:00+08:00`);

// --- elder lines: one model call per session ----------------------------------
const GENERIC = ["係呀。", "哦，咁樣。", "我都係咁諗。", "唔知呢，你點睇？",
  "好呀。", "今日都幾好天。", "嗯，慢慢嚟。", "冇乜特別，照舊啫。"];

async function elderLines(s, storySoFar) {
  const fixed = s.planted.map((x) => `第${x.pos + 1}句（固定，照抄）：${x.text}`);
  const system = "你幫手寫劇本：一位香港長者同手機App入面嘅AI陪伴者傾偈，只寫長者嗰邊講嘅說話。" +
    "用地道廣東話口語，繁體字，每句5至40字，有長有短，有時只係應一聲。" +
    "唔好寫陪伴者講嘅嘢。唔好加入背景冇提過嘅新人物、新病或者新地址。" +
    "只輸出JSON：{\"lines\": [\"...\"]}";
  const user = [
    `長者背景：${s.background}`,
    `今日：${s.date}（${["日", "一", "二", "三", "四", "五", "六"][weekday(s.day)]}），${s.time}，同「${NAME[s.agent]}」傾。`,
    storySoFar.length ? `之前講過（可以偶然提返，唔好重複照抄）：\n${storySoFar.slice(-10).join("\n")}` : "",
    `今次可以傾嘅閒話：${s.topics.join("、")}`,
    `一共要${s.turns}句。${fixed.length ? "以下幾句已經定咗，原句照抄喺嗰個位置：\n" + fixed.join("\n") : ""}`,
  ].filter(Boolean).join("\n\n");
  CTX.tag = {session: s.index};
  let lines = [];
  for (let attempt = 0; attempt < 2 && lines.length === 0; attempt++) {
    try {
      const r = await deepseek("https://api.deepseek.com/chat/completions", {
        method: "POST",
        headers: {"Content-Type": "application/json",
          "Authorization": `Bearer ${process.env.DEEPSEEK_API_KEY}`},
        body: JSON.stringify({model: "deepseek-flash", thinking: {type: "disabled"},
          messages: [{role: "system", content: system}, {role: "user", content: user}],
          response_format: {type: "json_object"}, temperature: 0.9,
          max_tokens: 2500}),
      }, "elder_script");
      const j = JSON.parse(await r.text());
      const parsed = JSON.parse(j.choices[0].message.content);
      if (Array.isArray(parsed.lines)) {
        lines = parsed.lines.filter((x) => typeof x === "string" && x.trim());
      }
    } catch (e) {
      console.error(`elder script s${s.index} failed: ${e.message}`);
      if (/budget/.test(e.message)) throw e;
    }
  }
  CTX.tag = null;
  const generated = lines.length;
  while (lines.length < s.turns) lines.push(GENERIC[lines.length % GENERIC.length]);
  lines = lines.slice(0, s.turns);
  for (const x of s.planted) lines[x.pos] = x.text; // planted text is exact
  return {lines, generated};
}

// --- memory state helpers ----------------------------------------------------
async function docs(col) {
  const snap = await db.collection("users").doc(PROFILE.uid).collection(col).get();
  return snap.docs.map((d) => Object.assign({id: d.id}, d.data()));
}
function plain(v) {
  return JSON.parse(JSON.stringify(v, (k, x) => {
    if (x && typeof x === "object" && typeof x.toDate === "function") {
      return x.toDate().toISOString();
    }
    if (x && x._seconds !== undefined && x._nanoseconds !== undefined) {
      return new Date(x._seconds * 1000).toISOString();
    }
    return x;
  }));
}

async function snapshot(todayKey) {
  const facts = await docs("mem_facts");
  const sums = await docs("mem_summaries");
  const fus = await docs("mem_followups");
  const count = (a, f) => a.filter(f).length;
  const expireBefore = memory.addDays(todayKey, -memory.LIMITS.followupExpireDays);
  return {
    facts_active: count(facts, (f) => f.status === "active"),
    facts_active_sensitive: count(facts, (f) => f.status === "active" && f.sensitivity === "sensitive"),
    facts_pending_confirmation: count(facts, (f) => f.status === "pending_confirmation"),
    facts_superseded: count(facts, (f) => f.status === "superseded"),
    facts_needs_review: count(facts, (f) => f.needs_review === true && f.status === "active"),
    facts_total: facts.length,
    summaries: sums.length,
    summary_chars_total: sums.reduce((a, s) => a + (s.summary || "").length, 0),
    summary_chars_avg: sums.length ? Math.round(sums.reduce((a, s) => a + (s.summary || "").length, 0) / sums.length) : 0,
    followups_pending: count(fus, (f) => f.status === "pending"),
    followups_asked: count(fus, (f) => f.status === "asked"),
    followups_lapsed: count(fus, (f) => f.status === "pending" && f.due_date < expireBefore),
  };
}

/**
 * Recompute what injectMemory selects for this agent (pure functions from
 * memory.js), with and without the 2,000-character cap, so we can see what
 * the cap and the per-layer limits cut.
 */
async function injectionPlan(agentId, todayKey, sessionStart) {
  const mem = await memory.loadMemory(db, PROFILE.uid);
  const sel = memory.selectForInjection(mem, {agentId, policy: "C", todayKey, sessionStart});
  const block = memory.renderMemoryBlock(sel);
  const keep = memory.LIMITS.maxChars;
  memory.LIMITS.maxChars = 1e9;
  const full = memory.renderMemoryBlock(sel);
  memory.LIMITS.maxChars = keep;
  const usable = mem.facts.filter((f) => f.status === "active" && !f.needs_review &&
    memory.visibleTo(f, agentId, "C"));
  const days = new Set(mem.summaries.filter((x) => x.agent_id === agentId && x.summary)
      .map((x) => x.day_key));
  const expireBefore = memory.addDays(todayKey, -memory.LIMITS.followupExpireDays);
  const dueFollowups = mem.followups.filter((f) => f.agent_id === agentId &&
    f.status === "pending" && f.due_date <= todayKey && f.due_date >= expireBefore);
  const cutIds = full.ids.filter((id) => !block.ids.includes(id));
  return {
    chars: block.text.length,
    chars_untrimmed: full.text.length,
    layers: block.layers,
    layers_untrimmed: full.layers,
    trimmed: cutIds.length > 0,
    cut: cutIds.map((id) => {
      const f = mem.facts.find((x) => x.id === id);
      if (f) return {layer: f.sensitivity === "sensitive" ? "sensitive" : "fact", text: `${f.key}：${f.value}`};
      const s = mem.summaries.find((x) => x.id === id);
      if (s) return {layer: "summary", text: `${s.day_key}：${s.summary}`};
      return {layer: "followup", id};
    }),
    // Caps before the character limit.
    facts_usable_normal: usable.filter((f) => f.sensitivity === "normal").length,
    facts_usable_sensitive: usable.filter((f) => f.sensitivity === "sensitive").length,
    summary_days_available: days.size,
    summary_days_used: sel.summaryDays.map((d) => d.day),
    followups_due: dueFollowups.length,
    followups_selected: sel.followups.map((f) => ({id: f.id, description: f.description, due: f.due_date})),
    text: block.text,
  };
}

function hitGroups(text, match) {
  const t = String(text || "");
  return match.every((grp) => grp.some((k) => t.includes(k)));
}

// --- one session --------------------------------------------------------------
async function runSession(s, storySoFar) {
  const uid = PROFILE.uid;
  const sv = SURFACE[s.agent];
  const start = hkt(s.date, s.time);
  CLOCK.now = start;
  const todayKey = memory.hkDateKey(start);
  const planStart = await injectionPlan(s.agent, todayKey, true);
  const planLater = await injectionPlan(s.agent, todayKey, false);
  delete planLater.text;

  const {lines, generated} = await elderLines(Object.assign({}, s,
      {background: PROFILE.background, topics: PROFILE.topics}), storySoFar);
  const msgs = [];
  const turns = [];
  for (let i = 0; i < lines.length; i++) {
    CLOCK.now = new Date(start.getTime() + i * 90000);
    msgs.push({role: "user", content: lines[i]});
    CTX.tag = {session: s.index, turn: i};
    let text = "";
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const r = await proxy({data: Object.assign({agentId: s.agent,
          messages: msgs.slice()}, sv), auth: {uid}});
        text = r.text || "";
        break;
      } catch (e) {
        if (/budget/.test(String(e.message))) throw e;
        console.error(`chat s${s.index} t${i} failed: ${e.message}`);
        await new Promise((r) => setTimeout(r, 3000));
      }
    }
    CTX.tag = null;
    msgs.push({role: "assistant", content: text || "（冇回覆）"});
    turns.push({user: lines[i], reply: text});
  }

  // Leave the page: App buffer (last 20 messages) → memoryEndSession.
  const end = new Date(start.getTime() + lines.length * 90000);
  CLOCK.now = end;
  const buffer = msgs.slice(-BUFFER_CAP).map((m, i, arr) => ({
    fromUser: m.role === "user", text: m.content,
    timestamp: new Date(end.getTime() - (arr.length - 1 - i) * 45000).toISOString(),
  }));
  await db.collection("users").doc(uid).collection("agent_contexts").doc(s.agent)
      .set({shortTermBuffer: buffer, lastUpdated: end}, {merge: true});
  const before = new Set((await docs("mem_extractions")).map((e) => e.id));
  CTX.tag = {session: s.index, turn: "end"};
  const t0 = Date.now();
  let status;
  try {
    status = (await endSession({data: {agentId: s.agent}, auth: {uid}})).status;
  } catch (e) {
    status = `error:${e.message}`;
  }
  const e2e = Date.now() - t0;
  let ext = (await docs("mem_extractions")).find((x) => !before.has(x.id));
  // Retry a failed extraction the way memorySweep would (same
  // processExtraction, same request body as index.js callDeepSeekJsonFor).
  // memorySweep itself is not called: it would also touch the other
  // profiles running in parallel processes.
  let retries = 0;
  while (ext && ext.status === "failed" && (ext.attempts || 0) < memory.LIMITS.maxAttempts) {
    retries++;
    await memory.processExtraction(db, uid, ext.id, retryModel(s.agent), end);
    ext = (await docs("mem_extractions")).find((x) => x.id === ext.id);
  }
  CTX.tag = null;
  const extId = ext ? ext.id : null;
  const newFacts = (await docs("mem_facts")).filter((f) => f.source_session_id === extId);
  const newFus = (await docs("mem_followups")).filter((f) => f.source_session_id === extId);
  const newSum = (await docs("mem_summaries")).filter((f) => f.source_session_id === extId);

  const inWindow = (pos) => pos >= lines.length - BUFFER_CAP / 2;
  const planted = s.planted.map((x) => {
    const fact = newFacts.find((f) => hitGroups(`${f.key} ${f.value} ${f.quote}`, x.match));
    const fu = newFus.find((f) => hitGroups(`${f.description} ${f.quote}`, x.match));
    const sum = newSum.find((f) => hitGroups(f.summary, x.match));
    return {id: x.id, kind: x.kind, pos: x.pos, in_buffer: inWindow(x.pos),
      fact: fact ? {status: fact.status, sensitivity: fact.sensitivity,
        visibility: fact.visibility, text: `${fact.key}：${fact.value}`} : null,
      followup: fu ? {due: fu.due_date, expected_due: x.due || null,
        sensitivity: fu.sensitivity, text: fu.description} : null,
      in_summary: !!sum};
  });

  return plain({
    index: s.index, day: s.day, date: s.date, time: s.time, agent: s.agent,
    turns: lines.length, elder_lines_generated: generated,
    inject_start: planStart, inject_later: planLater,
    extraction: ext ? {status: ext.status, attempts: ext.attempts, retries,
      error: ext.error || null, dropped: ext.dropped || [], counts: ext.counts || null,
      e2e_ms: e2e, call_status: status} : {status},
    new_facts: newFacts.map((f) => ({key: f.key, value: f.value, category: f.category,
      status: f.status, sensitivity: f.sensitivity, visibility: f.visibility,
      replaces: f.replaces})),
    new_followups: newFus.map((f) => ({description: f.description, due: f.due_date,
      sensitivity: f.sensitivity})),
    summary: newSum[0] ? newSum[0].summary : "",
    planted,
    state_after: await snapshot(todayKey),
    transcript: turns,
  });
}

function retryModel(agentId) {
  return async (prompt) => {
    const r = await global.fetch("https://api.deepseek.com/chat/completions", {
      method: "POST",
      headers: {"Content-Type": "application/json",
        "Authorization": `Bearer ${process.env.DEEPSEEK_API_KEY}`},
      body: JSON.stringify({model: "deepseek-flash", thinking: {type: "disabled"},
        messages: [{role: "system", content: prompt.system},
          {role: "user", content: prompt.user}],
        response_format: {type: "json_object"}, temperature: 0.2, max_tokens: 1500}),
    });
    const j = JSON.parse(await r.text());
    return (j.choices && j.choices[0] && j.choices[0].message.content) || "";
  };
}

async function confirmPending() {
  const ref = db.collection("users").doc(PROFILE.uid).collection("mem_facts");
  const pend = await ref.where("status", "==", "pending_confirmation").get();
  for (const d of pend.docs) await d.ref.update({status: "active"});
  return pend.size;
}

(async () => {
  const outDir = path.join(__dirname, "results", RUN);
  fs.mkdirSync(outDir, {recursive: true});
  const uref = db.collection("users").doc(PROFILE.uid);
  await db.recursiveDelete(uref);
  await db.doc("meta/memory_config").set({enabled: true, policy: "C", phaseBArmA: true});
  await uref.set({arm: "A", armAssignmentMode: "randomise", strataCell: 0,
    memory_enabled: false});
  const started = new Date().toISOString();
  const sessions = [];
  const confirmations = [];
  const storySoFar = [];
  const todo = PROFILE.sessions.slice(0, MAX_SESSIONS);
  let stopped = null;
  for (let d = 0; d < 28; d++) {
    for (const s of todo.filter((x) => x.day === d)) {
      try {
        const r = await runSession(s, storySoFar);
        sessions.push(r);
        console.log(`${PROFILE.id} s${s.index} ${s.date} ${s.agent} turns=${r.turns} ` +
          `ext=${r.extraction.status} block=${r.inject_start.chars}/${r.inject_start.chars_untrimmed} ` +
          `facts=${r.state_after.facts_active} calls=${CALLS.length}`);
      } catch (e) {
        stopped = String(e.message || e);
        console.error(`stopped at s${s.index}: ${stopped}`);
        break;
      }
      for (const x of s.planted) storySoFar.push(x.text);
    }
    if (stopped) break;
    if (PROFILE.confirmWeekday !== null && weekday(d) === PROFILE.confirmWeekday) {
      const n = await confirmPending();
      confirmations.push({date: dayKey(d), confirmed: n});
    }
    if (todo.every((x) => x.day <= d)) break;
  }
  const llmCalls = (await db.collection("llm_calls").where("uid", "==", PROFILE.uid).get())
      .docs.map((x) => plain(x.data()));
  const out = {profile: PROFILE.id, label: PROFILE.label, run: RUN, started,
    finished: new Date().toISOString(), stopped, confirmations, sessions,
    calls: CALLS,
    llm_calls_summary: {rows: llmCalls.length,
      prompt_tokens: llmCalls.reduce((a, x) => a + (x.prompt_tokens || 0), 0),
      completion_tokens: llmCalls.reduce((a, x) => a + (x.completion_tokens || 0), 0),
      by_type: llmCalls.reduce((a, x) => (a[x.call_type] = (a[x.call_type] || 0) + 1, a), {})},
    final: {facts: plain(await docs("mem_facts")).map((f) => ({key: f.key, value: f.value,
      category: f.category, status: f.status, sensitivity: f.sensitivity,
      visibility: f.visibility, agent: f.agent_id, revision_count: f.revision_count,
      needs_review: f.needs_review})),
    summaries: plain(await docs("mem_summaries")).map((s) => ({day: s.day_key,
      agent: s.agent_id, summary: s.summary, sensitivity: s.sensitivity})),
    followups: plain(await docs("mem_followups")).map((f) => ({agent: f.agent_id,
      description: f.description, due: f.due_date, status: f.status,
      sensitivity: f.sensitivity}))},
  };
  fs.writeFileSync(path.join(outDir, `${PROFILE.id}.json`), JSON.stringify(out, null, 1) + "\n");
  console.log(`wrote results/${RUN}/${PROFILE.id}.json calls=${CALLS.length}`);
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
