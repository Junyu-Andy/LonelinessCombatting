#!/usr/bin/env node
/**
 * tool/memory_eval/run_eval.js — memory v1 acceptance run (T4, 2026-10-06).
 *
 * Runs the REAL server code (functions/index.js: memoryEndSession,
 * memorySweep, proxyDeepSeek; functions/memory.js) in-process against the
 * Firestore emulator, using the 30 synthetic dialogues in dialogues/.
 *
 *   --mode=stub  the extraction model is an oracle built from gold/ (no
 *                network). Use this to check the harness and the scorer.
 *   --mode=live  the extraction call goes to DeepSeek through the real
 *                callDeepSeekJson in index.js. Needs NODE_USE_ENV_PROXY=1.
 *                Chat replies (proxyDeepSeek) are never sent: the request is
 *                captured (to read the system prompt) and answered locally.
 *
 * "Today" is fixed: every dialogue happens on 2026-10-07 (星期三) Hong Kong
 * time, at the clock time in its file. Three dialogues are set between
 * 00:00 and 08:00 HKT, when the UTC date is still 2026-10-06.
 *
 * Safety: refuses to run unless FIRESTORE_EMULATOR_HOST is set, and forces
 * a demo-* project id (the emulator never talks to a real project).
 * The DeepSeek key is a placeholder; the session proxy supplies the real one.
 *
 * Usage (repo root):
 *   firebase emulators:exec --only firestore --project demo-t4memeval \
 *     "node tool/memory_eval/run_eval.js --mode=stub --run=stub"
 *   NODE_USE_ENV_PROXY=1 firebase emulators:exec --only firestore \
 *     --project demo-t4memeval \
 *     "node tool/memory_eval/run_eval.js --mode=live --run=run1"
 * Then: node tool/memory_eval/score.js --run=run1
 */
"use strict";
/* eslint-disable require-jsdoc, max-len */

const fs = require("fs");
const path = require("path");
const {spawnSync} = require("child_process");

const ROOT = path.resolve(__dirname, "../..");
const FN = path.join(ROOT, "functions");
const HERE = __dirname;
const PROJECT = "demo-t4memeval";
const MAX_CALLS_PER_DIALOGUE = 3; // across ALL runs (results/ledger.json)

function arg(name, dflt) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : dflt;
}
const MODE = arg("mode", "stub");
const RUN = arg("run", MODE);
const ONLY = arg("only", ""); // comma list of persona ids, for debugging

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
process.env.GCLOUD_PROJECT = PROJECT;
process.env.GOOGLE_CLOUD_PROJECT = PROJECT;
if (!process.env.DEEPSEEK_API_KEY) process.env.DEEPSEEK_API_KEY = "placeholder";
if (MODE === "live" && process.env.NODE_USE_ENV_PROXY !== "1") {
  console.error("live mode needs NODE_USE_ENV_PROXY=1 (Node fetch ignores the proxy otherwise).");
  process.exit(1);
}

const req = (m) => require(path.join(FN, "node_modules", m));
const fft = req("firebase-functions-test")({projectId: PROJECT});
const admin = req("firebase-admin");

// --- fixed clock: patch memory.js so the callable path uses our "now" -----
const memory = require(path.join(FN, "memory.js"));
const CLOCK = {now: null};
const origProcess = memory.processExtraction;
const origInject = memory.injectMemory;
memory.processExtraction = (db, uid, id, callModel, now) =>
  origProcess(db, uid, id, callModel, now || CLOCK.now || undefined);
memory.injectMemory = (db, a) =>
  origInject(db, Object.assign({}, a, {now: a.now || CLOCK.now || undefined}));

// --- data -----------------------------------------------------------------
const ids = fs.readdirSync(path.join(HERE, "dialogues"))
    .filter((f) => f.endsWith(".json")).sort();
const DIALOGUES = ids.map((f) => JSON.parse(
    fs.readFileSync(path.join(HERE, "dialogues", f), "utf8")));
const GOLD = Object.fromEntries(ids.map((f) => {
  const g = JSON.parse(fs.readFileSync(path.join(HERE, "gold", f), "utf8"));
  return [g.id, g];
}));
const hkt = (local) => new Date(`${local}:00+08:00`);

// --- call ledger (enforces ≤3 extraction calls per dialogue, all runs) ----
const RESULTS = path.join(HERE, "results");
const LEDGER = path.join(RESULTS, "ledger.json");
const ledger = fs.existsSync(LEDGER) ?
  JSON.parse(fs.readFileSync(LEDGER, "utf8")) : {calls: {}};
const saveLedger = () => fs.writeFileSync(LEDGER,
    JSON.stringify(ledger, null, 2) + "\n");

// --- fetch interception -----------------------------------------------------
const realFetch = global.fetch;
const CTX = {dialogue: null, phase: "setup", calls: [], chat: [],
  denied: []};

function stubResponse(obj, model) {
  return new Response(JSON.stringify({
    id: "stub", model: model || "stub",
    choices: [{index: 0, message: {role: "assistant",
      content: typeof obj === "string" ? obj : JSON.stringify(obj)}}],
    usage: {prompt_tokens: 0, completion_tokens: 0, total_tokens: 0},
  }), {status: 200, headers: {"Content-Type": "application/json"}});
}

/** Oracle extraction from gold (stub mode only). */
function oracle(dlg) {
  const g = GOLD[dlg.id];
  const userText = dlg.turns.filter((t) => t.role === "user")
      .map((t) => t.text).join("\n");
  const quoteFor = (groups) => {
    for (const grp of groups) {
      for (const k of grp) if (k.length >= 2 && userText.includes(k)) return k;
    }
    return userText.slice(0, 4);
  };
  const cat = (d) => /稱呼/.test(d) ? "name" : /居住/.test(d) ? "living" :
    /健康/.test(d) ? "health" : /興趣/.test(d) ? "hobby" : "event";
  return {
    summary: `（oracle）${dlg.id}`,
    facts: g.facts.filter((f) => f.required).map((f) => ({
      op: "add", fact_id: "", category: cat(f.desc), key: f.desc.slice(0, 10),
      value: `${f.desc} ${f.match.map((grp) => grp[0]).join(" ")}`,
      quote: quoteFor(f.match), sensitive: f.sensitive === true,
      correction: false})),
    followups: g.followups.filter((u) => u.required).map((u) => ({
      description: `${u.desc} ${u.match.map((grp) => grp[0]).join(" ")}`,
      due_date: u.due || u.due_range[0], quote: quoteFor(u.match)})),
  };
}

global.fetch = async (url, init) => {
  const u = String(url);
  if (!u.startsWith("https://api.deepseek.com/")) return realFetch(url, init);
  const body = JSON.parse(init.body);
  const isExtraction = body.response_format &&
    body.response_format.type === "json_object";
  if (CTX.phase === "deny") {
    CTX.denied.push({url: u, extraction: !!isExtraction});
    return stubResponse({summary: "", facts: [], followups: []});
  }
  if (!isExtraction) {
    // Chat completion from proxyDeepSeek: capture the prompt, never send.
    CTX.chat.push({system: body.messages[0].content, model: body.model});
    return stubResponse("（測試：唔發送）");
  }
  // Attribute the call by its transcript, not by timing: a sweep retry may
  // pick up another dialogue's failed extraction.
  const userMsg = body.messages[1] ? String(body.messages[1].content) : "";
  const dlg = DIALOGUES.find((d) => {
    const first = d.turns.find((t) => t.role === "user");
    return first && userMsg.includes(first.text);
  });
  if (!dlg) throw new Error("extraction call for an unknown transcript");
  if (MODE === "stub") {
    CTX.calls.push({dialogue: dlg.id, mode: "stub", requested_model: body.model});
    return stubResponse(oracle(dlg));
  }
  const used = ledger.calls[dlg.id] || 0;
  if (used >= MAX_CALLS_PER_DIALOGUE) {
    CTX.calls.push({dialogue: dlg.id, mode: "refused_cap"});
    return new Response("call cap reached", {status: 429});
  }
  ledger.calls[dlg.id] = used + 1;
  saveLedger();
  const t0 = Date.now();
  let res;
  let err = null;
  try {
    res = await realFetch(url, init);
  } catch (e) {
    err = String(e);
  }
  // headers_ms: until the response headers arrive (run1/run2 recorded only
  // this, under the name latency_ms). latency_ms: until the body is read.
  const headersMs = Date.now() - t0;
  const rec = {dialogue: dlg.id, run: RUN, mode: "live",
    requested_model: body.model, request_temperature: body.temperature,
    headers_ms: headersMs, at: new Date().toISOString()};
  if (err) {
    CTX.calls.push(Object.assign(rec, {error: err}));
    throw new Error(err);
  }
  const text = await res.text();
  rec.latency_ms = Date.now() - t0;
  rec.http_status = res.status;
  try {
    const j = JSON.parse(text);
    rec.returned_model = j.model;
    rec.system_fingerprint = j.system_fingerprint || null;
    rec.usage = j.usage || null;
  } catch (_) {
    rec.body = text.slice(0, 300);
  }
  CTX.calls.push(rec);
  return new Response(text, {status: res.status,
    headers: {"Content-Type": "application/json"}});
};

const fns = require(path.join(FN, "index.js"));
const db = admin.firestore();
const endSession = fft.wrap(fns.memoryEndSession);
const proxy = fft.wrap(fns.proxyDeepSeek);
const sweep = fft.wrap(fns.memorySweep);

const AGENT_SURFACE = {
  siu_yan: {moduleId: "m2_check_in", promptKey: "siu_yan_v1"},
  ah_jan_ah_bak: {moduleId: "reflective_dialogue",
    promptKey: "ah_jan_ah_bak_v1"},
  tung_tung: {moduleId: "tung_tung_chat", promptKey: "tung_tung_v1"},
};
const AGENTS = Object.keys(AGENT_SURFACE);
const MEM_COLS = ["mem_facts", "mem_summaries", "mem_followups",
  "mem_injections", "mem_extractions"];

async function clearEmulator() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const r = await realFetch(`http://${host}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
      {method: "DELETE"});
  if (!r.ok) throw new Error(`clear emulator: ${r.status}`);
}

async function docs(uid, col) {
  const s = await db.collection("users").doc(uid).collection(col).get();
  return s.docs.map((d) => Object.assign({id: d.id}, d.data()));
}

function plain(v) {
  // Firestore Timestamps → ISO strings for the results file.
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

async function seedBuffer(uid, agentId, dlg, end) {
  const n = dlg.turns.length;
  await db.collection("users").doc(uid).collection("agent_contexts")
      .doc(agentId).set({
        shortTermBuffer: dlg.turns.map((t, i) => ({
          fromUser: t.role === "user",
          text: t.text,
          timestamp: new Date(end.getTime() - (n - 1 - i) * 60000)
              .toISOString(),
        })),
        lastUpdated: end,
      }, {merge: true});
}

function memBlock(system) {
  const i = system.indexOf("<memory>");
  if (i < 0) return "";
  const j = system.indexOf("</memory>", i);
  return system.slice(i, j + "</memory>".length);
}

async function chatPrompt(uid, agentId, now) {
  CLOCK.now = now;
  CTX.chat = [];
  const s = AGENT_SURFACE[agentId];
  const seen = new Set((await docs(uid, "mem_injections")).map((d) => d.id));
  await proxy({data: {agentId, moduleId: s.moduleId, promptKey: s.promptKey,
    messages: [{role: "user", content: "你好"}]}, auth: {uid}});
  const sys = CTX.chat.length ? CTX.chat[0].system : "";
  // Only the log entry this call wrote (none when the block was empty).
  const inj = (await docs(uid, "mem_injections")).filter((d) => !seen.has(d.id));
  return {block: memBlock(sys), injection: inj[0] ? plain(inj[0]) : null,
    chatCalls: CTX.chat.length};
}

// ---------------------------------------------------------------------------
// 1. Rule-based arm: zero extraction, zero injection, zero model calls.
// ---------------------------------------------------------------------------
async function ruleArmCheck() {
  await clearEmulator();
  await db.doc("meta/memory_config").set({enabled: true, policy: "C",
    phaseBArmA: true});
  const out = {cases: []};
  const variants = [
    {uid: "armB_optin", memory_enabled: true},
    {uid: "armB_plain", memory_enabled: false},
  ];
  const sample = DIALOGUES[0];
  CTX.phase = "deny";
  CTX.denied = [];
  for (const v of variants) {
    const uref = db.collection("users").doc(v.uid);
    await uref.set({arm: "B", armAssignmentMode: "randomise", strataCell: 0,
      memory_enabled: v.memory_enabled});
    // Worst case: a buffer and a memory item exist anyway (e.g. written by
    // a stale client). Old enough for the sweep to pick up.
    const old = new Date(Date.now() - 2 * 3600 * 1000);
    await seedBuffer(v.uid, "siu_yan", sample, old);
    await uref.collection("mem_facts").doc("seeded").set({agent_id: "siu_yan",
      category: "name", key: "稱呼", value: "測試稱呼", quote: "測試",
      status: "active", visibility: "shared", sensitivity: "normal"});
    const c = {uid: v.uid, memory_enabled: v.memory_enabled};
    c.endSession = {};
    for (const a of AGENTS) {
      c.endSession[a] = (await endSession({data: {agentId: a},
        auth: {uid: v.uid}})).status;
    }
    await sweep({});
    c.proxy = {};
    for (const a of AGENTS) {
      try {
        await proxy({data: {agentId: a, moduleId: AGENT_SURFACE[a].moduleId,
          promptKey: AGENT_SURFACE[a].promptKey,
          messages: [{role: "user", content: "你好"}]}, auth: {uid: v.uid}});
        c.proxy[a] = "ALLOWED";
      } catch (e) {
        c.proxy[a] = e.code || String(e);
      }
    }
    c.injectDirect = {};
    for (const a of AGENTS) {
      c.injectDirect[a] = (await memory.injectMemory(db, {uid: v.uid,
        agentId: a, moduleId: AGENT_SURFACE[a].moduleId,
        messages: [{role: "user", content: "你好"}], now: new Date()})).length;
    }
    c.counts = {};
    for (const col of MEM_COLS) {
      c.counts[col] = (await docs(v.uid, col)).length;
    }
    const ctx = await uref.collection("agent_contexts").doc("siu_yan").get();
    c.bufferLeft = (ctx.get("shortTermBuffer") || []).length;
    out.cases.push(c);
  }
  out.modelCalls = CTX.denied.length;
  CTX.phase = "setup";
  return out;
}

// ---------------------------------------------------------------------------
// 2. Hybrid arm: extraction per dialogue, in persona order.
// ---------------------------------------------------------------------------
async function extractAll() {
  await clearEmulator();
  await db.doc("meta/memory_config").set({enabled: true, policy: "C",
    phaseBArmA: true});
  const personas = [...new Set(DIALOGUES.map((d) => d.persona))]
      .filter((p) => !ONLY || ONLY.split(",").includes(p));
  const perDialogue = [];
  for (const p of personas) {
    const uid = `eval_${p}`;
    await db.collection("users").doc(uid).set({arm: "A",
      armAssignmentMode: "randomise", strataCell: 0, memory_enabled: false});
    for (const dlg of DIALOGUES.filter((d) => d.persona === p)) {
      const now = hkt(dlg.hkt_time);
      CLOCK.now = now;
      CTX.dialogue = dlg;
      CTX.phase = "extract";
      const firstCall = CTX.calls.length;
      const before = new Set((await docs(uid, "mem_extractions"))
          .map((e) => e.id));
      await seedBuffer(uid, dlg.agent, dlg, now);
      const t0 = Date.now();
      let status;
      try {
        status = (await endSession({data: {agentId: dlg.agent},
          auth: {uid}})).status;
      } catch (e) {
        status = `error:${e.message}`;
      }
      const e2e = [Date.now() - t0];
      // Retry like memorySweep would, within the call cap.
      let tries = 1;
      while (status === "failed" && tries < MAX_CALLS_PER_DIALOGUE &&
             (MODE === "stub" || (ledger.calls[dlg.id] || 0) < MAX_CALLS_PER_DIALOGUE)) {
        const t1 = Date.now();
        await sweep({});
        e2e.push(Date.now() - t1);
        tries++;
        const ext = (await docs(uid, "mem_extractions"))
            .filter((x) => !before.has(x.id));
        status = ext.length ? ext[0].status : "missing";
      }
      CTX.dialogue = null;
      CTX.phase = "setup";
      const ext = (await docs(uid, "mem_extractions"))
          .filter((x) => !before.has(x.id));
      const extId = ext[0] ? ext[0].id : null;
      const facts = (await docs(uid, "mem_facts"))
          .filter((f) => f.source_session_id === extId);
      const followups = (await docs(uid, "mem_followups"))
          .filter((f) => f.source_session_id === extId);
      const summaries = (await docs(uid, "mem_summaries"))
          .filter((f) => f.source_session_id === extId);
      perDialogue.push(plain({
        id: dlg.id, persona: p, uid, agent: dlg.agent, now: now.toISOString(),
        status, attempts: tries, e2e_ms: e2e,
        calls: CTX.calls.slice(firstCall),
        extraction: ext[0] ? {id: ext[0].id, status: ext[0].status,
          attempts: ext[0].attempts, error: ext[0].error || null,
          dropped: ext[0].dropped || [], counts: ext[0].counts || null,
          raw_output: ext[0].raw_output || ""} : null,
        facts, followups, summaries,
      }));
      console.log(`${dlg.id} ${status} facts=${facts.length} followups=${followups.length}`);
    }
  }
  // Final state of every fact (superseded / active) per persona.
  const finalFacts = {};
  for (const p of personas) {
    finalFacts[p] = plain(await docs(`eval_${p}`, "mem_facts"));
  }
  return {personas, perDialogue, finalFacts};
}

// ---------------------------------------------------------------------------
// 3. Cross-agent leakage under policy C, on the real proxyDeepSeek prompt.
// ---------------------------------------------------------------------------
async function leakCheck(personas) {
  const passes = [
    {name: "today_unconfirmed", now: hkt("2026-10-07T20:00"), confirm: false},
    {name: "today_confirmed", now: hkt("2026-10-07T20:30"), confirm: true},
    // Nine days on, most follow-ups are due: checks they stay with their agent.
    {name: "oct16_confirmed", now: hkt("2026-10-16T10:00"), confirm: true},
    // Positive control: under policy A (everything shared) the same checks
    // must find "leaks", otherwise the detector is blind.
    {name: "control_policyA", now: hkt("2026-10-16T11:00"), confirm: true,
      policy: "A"},
  ];
  const out = [];
  for (const pass of passes) {
    await db.doc("meta/memory_config").set({policy: pass.policy || "C"},
        {merge: true});
    for (const p of personas) {
      const uid = `eval_${p}`;
      if (pass.confirm) {
        // As if the participant tapped 「好，記住」 on every pending item.
        for (const f of await docs(uid, "mem_facts")) {
          if (f.status === "pending_confirmation") {
            await db.collection("users").doc(uid).collection("mem_facts")
                .doc(f.id).update({status: "active"});
          }
        }
      }
      const facts = await docs(uid, "mem_facts");
      const sums = await docs(uid, "mem_summaries");
      const fus = await docs(uid, "mem_followups");
      const byId = new Map();
      for (const f of facts) byId.set(f.id, Object.assign({col: "fact"}, f));
      for (const s of sums) byId.set(s.id, Object.assign({col: "summary"}, s));
      for (const f of fus) byId.set(f.id, Object.assign({col: "followup"}, f));
      for (const agentId of AGENTS) {
        const r = await chatPrompt(uid, agentId, pass.now);
        const injected = r.injection ? r.injection.memory_ids : [];
        const idLeaks = [];
        for (const id of r.block ? injected : []) {
          const it = byId.get(id);
          if (!it) continue;
          const shareable = it.col === "fact" && it.visibility === "shared" &&
            (it.sensitivity || "normal") === "normal";
          if (it.agent_id !== agentId && !shareable) {
            idLeaks.push({id, col: it.col, owner: it.agent_id,
              text: it.value || it.summary || it.description});
          }
        }
        // Text check: another agent's private wording verbatim in the block.
        const visibleTexts = [...byId.values()].filter((it) =>
          it.agent_id === agentId ||
          (it.col === "fact" && it.visibility === "shared" &&
            (it.sensitivity || "normal") === "normal"))
            .map((it) => it.value || it.summary || it.description || "");
        const textLeaks = [];
        for (const it of byId.values()) {
          if (it.agent_id === agentId) continue;
          if (it.col === "fact" && it.visibility === "shared" &&
              (it.sensitivity || "normal") === "normal") continue;
          const t = it.value || it.summary || it.description || "";
          if (t.length < 4) continue;
          if (visibleTexts.some((v) => v.includes(t))) continue;
          if (r.block.includes(t)) {
            textLeaks.push({id: it.id, col: it.col, owner: it.agent_id, text: t});
          }
        }
        out.push({pass: pass.name, control: !!pass.policy,
          persona: p, agent: agentId,
          chars: r.block.length, layers: r.injection ? r.injection.layers : null,
          injected_ids: injected, idLeaks, textLeaks, block: r.block});
      }
    }
  }
  await db.doc("meta/memory_config").set({policy: "C"}, {merge: true});
  return out;
}

// ---------------------------------------------------------------------------
// 4. Deletion: one item at a time (the 「我記得嘅嘢」 page), then everything
//    (tool/delete_memory.js --confirm).
// ---------------------------------------------------------------------------
async function deletionCheck(personas) {
  const now = hkt("2026-10-07T21:00");
  const out = {single: [], full: []};
  for (const p of personas) {
    const uid = `eval_${p}`;
    const uref = db.collection("users").doc(uid);
    // Snapshot what each agent gets before deleting.
    const before = {};
    for (const a of AGENTS) before[a] = await chatPrompt(uid, a, now);
    // Delete every injected fact and summary of the persona's first
    // dialogue's agent, one doc at a time, as the page does.
    const targets = [];
    for (const a of AGENTS) {
      for (const id of (before[a].injection || {}).memory_ids || []) {
        if (!targets.includes(id)) targets.push(id);
      }
    }
    const facts = await docs(uid, "mem_facts");
    const sums = await docs(uid, "mem_summaries");
    const pick = [];
    // At most 3 facts (one shared, others private) and 1 summary per persona.
    const injFacts = facts.filter((f) => targets.includes(f.id));
    const shared = injFacts.find((f) => f.visibility === "shared");
    if (shared) pick.push({col: "mem_facts", doc: shared});
    for (const f of injFacts.filter((x) => x.visibility !== "shared").slice(0, 2)) {
      pick.push({col: "mem_facts", doc: f});
    }
    const injSum = sums.find((s) => targets.includes(s.id));
    if (injSum) pick.push({col: "mem_summaries", doc: injSum});
    for (const t of pick) await uref.collection(t.col).doc(t.doc.id).delete();
    for (const a of AGENTS) {
      const r = await chatPrompt(uid, a, now);
      const ids = (r.injection || {}).memory_ids || [];
      for (const t of pick) {
        const text = t.doc.value || t.doc.summary || "";
        const residual = [];
        // Key words of a deleted fact still reachable through a summary?
        if (t.col === "mem_facts" && r.block) {
          const q = (t.doc.quote || "").replace(/[\s\p{P}]/gu, "");
          for (let i = 0; i + 4 <= q.length; i++) {
            const g = q.slice(i, i + 4);
            if (r.block.replace(/[\s\p{P}]/gu, "").includes(g)) {
              residual.push(g);
            }
          }
        }
        out.single.push({persona: p, agent: a, col: t.col, id: t.doc.id,
          owner: t.doc.agent_id, text,
          idStillInjected: ids.includes(t.doc.id),
          textStillInBlock: text.length >= 4 && r.block.includes(text),
          residualQuoteGrams: [...new Set(residual)]});
      }
    }
    // Full deletion with the real script, against the emulator only.
    const res = spawnSync(process.execPath,
        [path.join(ROOT, "tool/delete_memory.js"), `--uid=${uid}`, "--confirm"],
        {env: Object.assign({}, process.env, {
          NODE_PATH: path.join(FN, "node_modules"),
          GCLOUD_PROJECT: PROJECT}), encoding: "utf8"});
    const counts = {};
    for (const col of MEM_COLS) counts[col] = (await docs(uid, col)).length;
    const blocks = {};
    for (const a of AGENTS) {
      blocks[a] = (await chatPrompt(uid, a, now)).block.length;
    }
    // chatPrompt above logs nothing when the block is empty, so the
    // injection log stays empty too.
    const user = (await uref.get()).data();
    out.full.push({persona: p, exit: res.status,
      stdout: (res.stdout || "").trim().slice(-300),
      stderr: (res.stderr || "").trim().slice(-300),
      countsAfter: counts, blockCharsAfter: blocks,
      memory_enabled: user.memory_enabled,
      memoryDeletedAt: user.memoryDeletedAt ? "set" : null});
  }
  return out;
}

(async () => {
  fs.mkdirSync(path.join(RESULTS, RUN), {recursive: true});
  const started = new Date().toISOString();
  const ruleArm = await ruleArmCheck();
  console.log("rule arm:", JSON.stringify(ruleArm.cases.map((c) => c.counts)),
      "model calls:", ruleArm.modelCalls);
  const ex = await extractAll();
  const leaks = await leakCheck(ex.personas);
  const deletion = await deletionCheck(ex.personas);
  const out = {run: RUN, mode: MODE, started, finished: new Date().toISOString(),
    today_hkt: "2026-10-07", policy: "C", node: process.version,
    ruleArm, extraction: ex.perDialogue, finalFacts: ex.finalFacts,
    leaks, deletion};
  fs.writeFileSync(path.join(RESULTS, RUN, "raw.json"),
      JSON.stringify(out, null, 2) + "\n");
  console.log(`wrote results/${RUN}/raw.json`);
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
