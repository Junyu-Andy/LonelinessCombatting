/**
 * dev-tasks-1018 E1 (a) — the six-step check Junyu asked for before
 * turning `meta/memory_config.layersEnabled` on for Phase B (10/19):
 * layers on, policy C, phaseBArmA on, extraction prompt still v2, model
 * stubbed.  One Hybrid user, then a rule-arm user.  Prints 過／唔過 per
 * step; the report is docs/dev-reports/memory-layers-sixstep-20261018.md.
 *
 * Run from the repo root:
 *   firebase emulators:exec --only firestore --project loneliness-pilot-dev \
 *     "cd functions && node test/memory_layers_sixstep_emulator_test.js"
 */
"use strict";
/* eslint-disable require-jsdoc */

const assert = require("assert");
const admin = require("firebase-admin");
const m = require("../memory");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST not set — run inside the emulator.");
  process.exit(1);
}
admin.initializeApp({projectId: "loneliness-pilot-dev"});
const db = admin.firestore();

const NOW = new Date("2026-10-18T12:00:00Z"); // 20:00 HKT
const UID = "sixstep-a";
const UID_B = "sixstep-b";
const user = (uid) => db.collection("users").doc(uid || UID);

async function reset(uid, arm) {
  for (const c of await user(uid).listCollections()) {
    const docs = await c.listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
  // Exactly the production setting E1 (a) prescribes.
  await db.doc("meta/memory_config").set({enabled: true, policy: "C",
    phaseBArmA: true, layersEnabled: true});
  await user(uid).set({arm, armAssignmentMode: "pilot_designated",
    cohort: "pilot", consent: {sharedContextUse: true}});
}

async function extractWith(uid, agentId, lines, modelOut, calls) {
  await user(uid).collection("agent_contexts").doc(agentId).set({
    shortTermBuffer: lines.map(([fromUser, text], i) => ({fromUser, text,
      timestamp: new Date(NOW.getTime() - (lines.length - i) * 60000)
          .toISOString()})),
    lastUpdated: NOW,
  });
  const id = await m.claimBuffer(db, uid, agentId);
  if (!id) return {id: null, status: "empty"};
  const status = await m.processExtraction(db, uid, id, async (p) => {
    calls.push(p);
    return JSON.stringify(modelOut);
  }, NOW);
  return {id, status};
}

const docsOf = async (col, uid) =>
  (await user(uid).collection(col).get()).docs.map((d) => ({id: d.id,
    ...d.data()}));

const inject = (agentId, uid) => m.injectMemory(db, {
  uid: uid || UID, agentId,
  moduleId: agentId === "tung_tung" ? "tung_tung_chat" :
    agentId === "siu_yan" ? "m2_check_in" : "reflective_dialogue",
  messages: [{role: "user", content: "你好呀"}], now: NOW,
  sessionId: `sess-${agentId}`});

// ① 小欣, three turns: a family member's name and one health matter.
const STEP1_TURNS = [
  [true, "我個女叫阿欣，佢喺銀行做嘢。"],
  [false, "阿欣喺銀行做嘢，幾好呀。"],
  [true, "我上個禮拜去咗睇醫生，話血壓高咗少少。"],
  [false, "血壓高咗少少，要留意下。"],
  [true, "今日落雨，冇出去行。"],
  [false, "落雨就喺屋企休息下啦。"],
];
const STEP1_OUT = {
  summary: "陳太講起個女阿欣喺銀行做嘢，今日落雨冇出街。",
  facts: [
    {op: "add", category: "family", key: "個女", value: "個女叫阿欣，喺銀行做嘢",
      quote: "我個女叫阿欣"},
    {op: "add", category: "health", key: "血壓", value: "上星期睇醫生，血壓高咗少少",
      quote: "血壓高咗少少", sensitive: true},
  ],
  followups: [],
};

const results = [];
const step = (n, name, ok, note) => {
  results.push({n, name, ok, note: note || ""});
  const tail = note ? ` — ${note}` : "";
  console.log(`${ok ? "過" : "唔過"}  ${n} ${name}${tail}`);
};

(async () => {
  const calls = [];
  await reset(UID, "A");

  // ---- ① ----
  let r = await extractWith(UID, "siu_yan", STEP1_TURNS, STEP1_OUT, calls);
  let facts = await docsOf("mem_facts");
  const fam = facts.find((f) => f.category === "family");
  const health = facts.find((f) => f.category === "health");
  const ext = (await docsOf("mem_extractions")).find((e) => e.id === r.id);
  const ok1 = r.status === "done" && fam && fam.layer === "shared" &&
    fam.sourceAgent === "siu_yan" && health && health.layer === "private" &&
    health.sourceAgent === "siu_yan" && health.sensitivity === "sensitive" &&
    health.status === "pending_confirmation" &&
    ext.prompt_version === "memory_extraction.v2";
  step("①", "小欣三輪→ mem_facts：家人 shared、健康 private、" +
      "sourceAgent 小欣、prompt v2", ok1,
  `family.layer=${fam && fam.layer}, health.layer=${health && health.layer}, ` +
  `health.status=${health && health.status}, ` +
  `prompt=${ext && ext.prompt_version}`);
  // The elder confirms the health item on 「我記得嘅嘢」 so the layer rule
  // (not the pending status) is what keeps it from the other two.
  await user().collection("mem_facts").doc(health.id)
      .update({status: "active"});

  // ---- ② ----
  const tung = await inject("tung_tung");
  const ok2 = tung.includes("個女") && !tung.includes("血壓");
  step("②", "通通嘅提示詞：有家人條，冇健康條", ok2,
      `含個女=${tung.includes("個女")}, 含血壓=${tung.includes("血壓")}`);

  // ---- ③ ----
  const ajab = await inject("ah_jan_ah_bak");
  const ok3 = ajab.includes("個女") && !ajab.includes("血壓");
  step("③", "阿珍／阿伯嘅提示詞：有家人條，冇健康條", ok3,
      `含個女=${ajab.includes("個女")}, 含血壓=${ajab.includes("血壓")}`);
  // 小欣 herself still sees her own private item (sanity, not a step).
  const siu = await inject("siu_yan");
  assert.ok(siu.includes("血壓"), "小欣 sees her own health item");

  // ---- ④ ----
  const before = {facts: (await docsOf("mem_facts")).length,
    summaries: (await docsOf("mem_summaries")).length};
  const callsBefore = calls.length;
  r = await extractWith(UID, "siu_yan", [
    [true, "呢件事你唔好記住呀。"],
    [false, "好。"],
    [true, "我個仔阿明下個月結婚。"],
    [false, "恭喜呀。"],
  ], {summary: "個仔結婚", facts: [{op: "add", category: "family",
    key: "個仔", value: "個仔阿明下個月結婚", quote: "我個仔阿明下個月結婚"}],
  followups: []}, calls);
  const after = {facts: (await docsOf("mem_facts")).length,
    summaries: (await docsOf("mem_summaries")).length};
  const ext4 = (await docsOf("mem_extractions")).find((e) => e.id === r.id);
  const ok4 = r.status === "done" && calls.length === callsBefore &&
    after.facts === before.facts && after.summaries === before.summaries &&
    ext4.outcome === "forget_request" && (ext4.turns || []).length === 0;
  step("④", "小欣會話講「唔好記住」再講新事：冇調模型，兩層都冇新條目",
      ok4, `model calls +${calls.length - callsBefore}, ` +
      `facts ${before.facts}→${after.facts}, ` +
      `summaries ${before.summaries}→${after.summaries}, ` +
      `outcome=${ext4 && ext4.outcome}`);

  // ---- ⑤ ----  the page deletes the shared family fact; the trigger
  // (memoryFactDeleted → deleteSummaryForItem) runs next.
  const famDoc = (await docsOf("mem_facts"))
      .find((f) => f.category === "family");
  await user().collection("mem_facts").doc(famDoc.id).delete();
  await m.deleteSummaryForItem(db, UID, famDoc);
  facts = await docsOf("mem_facts");
  const stillFam = facts.filter((f) => f.category === "family");
  const t5 = await inject("tung_tung");
  const a5 = await inject("ah_jan_ah_bak");
  const s5 = await inject("siu_yan");
  const ok5 = stillFam.length === 0 && !t5.includes("個女") &&
    !a5.includes("個女") && !s5.includes("個女");
  step("⑤", "設定頁刪一條 shared 事實：三位名下都冇咗", ok5,
      `剩餘 family 條=${stillFam.length}; 通通含=${t5.includes("個女")}, ` +
      `阿珍含=${a5.includes("個女")}, 小欣含=${s5.includes("個女")}`);

  // ---- ⑥ ----
  const logs = await docsOf("mem_injections");
  const withDose = logs.filter((l) => l.layer_counts &&
    typeof l.layer_counts.shared === "number" &&
    typeof l.layer_counts.private === "number" && l.layers_enabled === true &&
    typeof l.session_id === "string");
  const tungLog = logs.find((l) => l.agent_id === "tung_tung");
  const ok6 = logs.length > 0 && withDose.length === logs.length &&
    tungLog && tungLog.layer_counts.shared >= 1 &&
    tungLog.layer_counts.private === 0 &&
    tungLog.source_agents.shared.siu_yan >= 1;
  const tl = tungLog && tungLog.layer_counts;
  step("⑥", "會話日誌（mem_injections）分開記共享層／私有層條數同會話編號",
      ok6, `${withDose.length}/${logs.length} 條有 layer_counts；通通第一次：` +
      `shared=${tl && tl.shared}, private=${tl && tl.private}`);

  // ---- rule arm ① ----
  await reset(UID_B, "B");
  const callsB = [];
  const active = await m.memoryActive(db, UID_B);
  // memoryEndSession returns "inactive" before claiming; the sweep skips
  // by inScope.  Even a direct claim+process must write nothing usable:
  const injB = await inject("siu_yan", UID_B);
  const factsB = await docsOf("mem_facts", UID_B);
  const logsB = await docsOf("mem_injections", UID_B);
  const okB = active === null && injB === "" && factsB.length === 0 &&
    logsB.length === 0 && callsB.length === 0 &&
    m.inScope(await m.loadConfig(db),
        (await user(UID_B).get()).data()) === false;
  step("規則組①", "規則組用戶：memoryActive 為空、不注入、不寫任何記憶", okB,
      `memoryActive=${active}, inject="${injB}", facts=${factsB.length}, ` +
      `logs=${logsB.length}`);

  const failed = results.filter((x) => !x.ok).length;
  console.log(failed ? `${failed} 步唔過` : "六步加規則組全部過");
  process.exit(failed ? 1 : 0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
