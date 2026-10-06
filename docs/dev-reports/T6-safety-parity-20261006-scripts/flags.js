// T6 — 5-flag 标记测试。尽量复用线上代码：
//   - 5 个标记：直接 require functions/llm_flags.js 的 computeLlmFlags（不另写逻辑）。
//   - 回复：按 functions/index.js proxyDeepSeek 的请求形状调用 DeepSeek
//     （model deepseek-chat、max_tokens 800、小欣 temperature 0.7、top_p 0.95、
//     system = functions/prompts/siu_yan_v1.txt + "\n\n" + 客户端注入的 "[模組] m2_check_in"）。
//     index.js 依赖 firebase-functions，无法在本机直接 require，所以请求体在这里照抄。
//   - 回复的词库扫描（线上 gateway_output）：复用 lexicon.js。
// 运行：NODE_USE_ENV_PROXY=1 node flags.js   （密钥由环境代理注入，这里用占位值）
"use strict";
const fs = require("fs");
const path = require("path");
const ROOT = path.resolve(__dirname, "../../..");
const {computeLlmFlags} = require(path.join(ROOT, "functions/llm_flags.js"));
const lexicon = require("./lexicon.js");

const RUNS = 3;
const MODULE_ID = "m2_check_in";
const PROMPT_FILE = path.join(ROOT, "functions/prompts/siu_yan_v1.txt");
const lex = lexicon.load();
const systemPrompt = fs.readFileSync(PROMPT_FILE, "utf8")
    .split("{{VARIANT_NAME}}").join("阿珍／阿伯") + `\n\n[模組] ${MODULE_ID}`;

async function callDeepSeek(userText) {
  const t0 = Date.now();
  const res = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: {"Content-Type": "application/json", "Authorization": "Bearer placeholder"},
    body: JSON.stringify({
      model: "deepseek-chat",
      messages: [{role: "system", content: systemPrompt}, {role: "user", content: userText}],
      max_tokens: 800, temperature: 0.7, top_p: 0.95,
    }),
  });
  const latencyMs = Date.now() - t0;
  if (!res.ok) return {error: `HTTP ${res.status}`, latencyMs};
  const data = await res.json();
  return {
    text: (data.choices && data.choices[0] && data.choices[0].message.content) || "",
    model: data.model, usage: data.usage, latencyMs,
  };
}

(async () => {
  const {sentences} = JSON.parse(fs.readFileSync(path.join(__dirname, "sentences.json"), "utf8"));
  const out = [];
  let calls = 0;
  for (const s of sentences) {
    const inputScan = lexicon.analyze(lex, s.text);
    const runs = [];
    for (let i = 0; i < RUNS; i++) {
      const r = await callDeepSeek(s.text);
      calls++;
      const flags = r.error ? null : computeLlmFlags({
        userInput: s.text, assistantOutput: r.text, agentContext: null, moduleId: MODULE_ID,
      });
      runs.push({...r, flags, outputScan: r.error ? null : lexicon.analyze(lex, r.text)});
      process.stdout.write(`${s.id} run${i + 1} ${r.error || r.model} ${r.latencyMs}ms ` +
        `${flags ? Object.entries(flags).filter(([k, v]) => v === true).map(([k]) => k).join(",") || "(none)" : ""}\n`);
    }
    out.push({...s, inputScan, onlineShortCircuit: inputScan.tier === "acute", runs});
  }
  fs.writeFileSync(path.join(__dirname, "results_flags.json"), JSON.stringify({
    runAt: new Date().toISOString(), requestedModel: "deepseek-chat", agent: "siu_yan", moduleId: MODULE_ID,
    promptFile: "functions/prompts/siu_yan_v1.txt", totalCalls: calls, rows: out,
  }, null, 2) + "\n");
  console.log(`total DeepSeek calls: ${calls}`);
})();
