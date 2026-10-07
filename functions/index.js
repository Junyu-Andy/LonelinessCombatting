const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {
  onDocumentCreated, onDocumentDeleted, onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {computeLlmFlags} = require("./llm_flags");
const arm = require("./arm");
const memory = require("./memory");
const llmLog = require("./llm_log");
const reminders = require("./reminders");
const hotline = require("./hotline_filter");
const {safetyConfig} = require("./safety_config");
const featureFlags = require("./feature_flags");
const blinding = require("./blinding");
const djgW2 = require("./djg_w2");

admin.initializeApp();

const DEEPSEEK_API_KEY = defineSecret("DEEPSEEK_API_KEY");
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");
const PI_EMAIL = defineSecret("PI_EMAIL");

// `deepseek-chat` is a legacy alias; on 2026-10-06 DeepSeek resolved it to
// `deepseek-flash` (DeepSeek-V4.1-Flash) with thinking off.  Naming the model
// directly would turn thinking on by default: reasoning tokens then eat
// max_tokens (the 200-token JSON calls came back empty) and temperature /
// top_p stop applying.  So every call sends both fields below, which keeps
// the exact behaviour the alias had.  Decision record 0017.
const DEEPSEEK_MODEL = "deepseek-flash";
const DEEPSEEK_THINKING = {type: "disabled"};

// ---------------------------------------------------------------------------
// Prompt resolution (Dev Req §3.2, §8 – prompts live server-side so the
// client cannot tamper with them).
//
// Files under functions/prompts/{key}.txt are loaded once at cold-start
// and cached in-memory. The Ah Jan / Ah Bak prompt contains a
// `{{VARIANT_NAME}}` placeholder which we substitute per request.
// ---------------------------------------------------------------------------

const PROMPT_DIR = path.join(__dirname, "prompts");
const _promptCache = {};

// Prompt registry (memory-and-entry-spec 3.10): the key the app sends →
// the versioned file the server loads.  Installed apps keep sending the
// old key, so the swap happens here.  Old files are never overwritten.
//   tung_tung_v1 → tung_tung.v2: no "幫你查" invitation (decision 0019).
const PROMPT_FILES = {
  tung_tung_v1: "tung_tung.v2",
};

function promptFileFor(key) {
  return Object.prototype.hasOwnProperty.call(PROMPT_FILES, key) ?
    PROMPT_FILES[key] : key;
}

function loadPrompt(key) {
  if (_promptCache[key] !== undefined) return _promptCache[key];
  try {
    const file = path.join(PROMPT_DIR, `${promptFileFor(key)}.txt`);
    _promptCache[key] = fs.readFileSync(file, "utf8");
  } catch (err) {
    _promptCache[key] = null;
  }
  return _promptCache[key];
}

let _safetyCache = null;
function loadSafetyAcks() {
  if (_safetyCache !== null) return _safetyCache;
  try {
    const file = path.join(PROMPT_DIR, "safety_acknowledgements.json");
    _safetyCache = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (err) {
    _safetyCache = {};
  }
  return _safetyCache;
}

// L-2 — prompt version label derived from the prompt file header, e.g.
// "## 小欣 — … · v1 (rev 2026-06)" → "siu_yan_v1@2026-06".  Cached with the
// prompt text; null for raw systemPrompt callers (no server-side file).
const _promptVersionCache = {};
function promptVersionFor(key) {
  if (!key) return null;
  if (_promptVersionCache[key] !== undefined) return _promptVersionCache[key];
  const text = loadPrompt(key);
  let label = null;
  if (text) {
    const m = text.split("\n")[0].match(/v(\d+)\s*\(rev\s*([0-9-]+)\)/);
    if (m) label = `${key.replace(/[._]v\d+$/, "")}_v${m[1]}@${m[2]}`;
  }
  _promptVersionCache[key] = label;
  return label;
}

// S-4 — crisis resources (hotline names / numbers) are a single JSON that
// the client bundles as an asset AND the acknowledgement callable reads, so
// the template's hotline always matches the crisis page.
let _crisisCache = null;
function loadCrisisResources() {
  if (_crisisCache !== null) return _crisisCache;
  try {
    const file = path.join(PROMPT_DIR, "crisis_resources.json");
    _crisisCache = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (err) {
    _crisisCache = {resources: []};
  }
  return _crisisCache;
}

// Fills {{HOTLINE_NAME}} / {{HOTLINE_NUMBER}} from the resource flagged
// `acuteTemplateReference` (must be item 1 or 2 per HREC §8.1).
function fillHotline(text, locale) {
  if (!text) return text;
  const res = (loadCrisisResources().resources || [])
      .find((r) => r.acuteTemplateReference) || {};
  const name = locale === "en" ? (res.nameEn || "") : (res.nameZh || "");
  return text
      .split("{{HOTLINE_NAME}}").join(name)
      .split("{{HOTLINE_NUMBER}}").join(res.number || "");
}

function resolvePrompt(payload) {
  const promptKey = payload.promptKey;
  const rawPrompt = payload.systemPrompt;
  if (!promptKey && rawPrompt) return rawPrompt;
  if (!promptKey) return null;
  const template = loadPrompt(promptKey);
  if (!template) return rawPrompt || null;
  let out = template;
  // Default variant: feminine (阿珍).  An earlier auto-formatter
  // mangled this to "阿Jan" — do not regress.  The two real variants
  // are 阿珍 (feminine, sage green) and 阿伯 (masculine, teal-blue);
  // both are AI-disclosed peer-aged listeners.
  const variantName = payload.variantName || "阿珍／阿伯";
  out = out.split("{{VARIANT_NAME}}").join(variantName);
  const contextSuffix = payload.contextSuffix;
  if (contextSuffix && typeof contextSuffix === "string") {
    // P-2 (2026-09): the suffix carries the rolling summary + named
    // entities + mood snippet, i.e. participant-derived text — it goes
    // through the same identifier scrub as the chat messages.
    out = `${out}\n\n${stripPII(contextSuffix)}`;
  }
  return out;
}

// ---------------------------------------------------------------------------
// HREC data-minimisation (Phase A Proposal §2.5).
//
// Before any text is transmitted to the DeepSeek endpoint, strip direct
// identifiers and replace any embedded Firebase UID with a per-call coded
// session identifier.  The DeepSeek server in mainland China must never
// receive participants' names, phone numbers, addresses, IP or HKU
// account info — only pseudonymised conversation content.
//
// Rules:
//   - HK phone numbers: 8-digit (optionally +852) → "[PHONE]"
//   - Email addresses: → "[EMAIL]"
//   - HK ID numbers (A123456(7)): → "[ID]"
//   - Postal address keywords + numbers: → "[ADDRESS]"  (best-effort,
//     since HK addresses are highly varied; we strip floor/flat numbers
//     and street-suffix patterns)
//   - Close-contact names from the user profile (if surfaced in turns):
//     handled at the agent_context layer, not here — names users
//     deliberately type to AGENTS as part of life-story are not stripped
//     (that would break the intervention's core feature).  This function
//     strips only the unambiguous PII markers above.
// ---------------------------------------------------------------------------

const PII_PATTERNS = [
  // HK phone (8-digit, optionally prefixed)
  [/(\+?852[-\s]?)?[2-9]\d{3}[-\s]?\d{4}\b/g, "[PHONE]"],
  // Email
  [/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g, "[EMAIL]"],
  // HK ID-like patterns: letter(s) + 6 digits + (check digit)
  [/\b[A-Z]{1,2}\d{6}\(?\d?\)?\b/g, "[ID]"],
  // Floor/flat numbers in HK addresses (very rough)
  [/\b\d{1,3}\/?[FfRr]\b/g, "[ADDRESS]"],
];

function stripPII(text) {
  if (!text || typeof text !== "string") return text;
  let out = text;
  for (const [pat, replacement] of PII_PATTERNS) {
    out = out.replace(pat, replacement);
  }
  return out;
}

function sessionCodeFor(uid) {
  // 16-char salted hash so the LLM still has a stable per-user token to
  // (in principle) reason about turn linkage, without ever seeing the
  // Firebase UID.  Salt rotates per cold-start so even the coded ID is
  // not stable across deploys.
  if (!uid) return "anon";
  return crypto
    .createHash("sha256")
    .update(`${_sessionSalt}|${uid}`, "utf8")
    .digest("hex")
    .slice(0, 16);
}
const _sessionSalt = crypto.randomBytes(8).toString("hex");

// ---------------------------------------------------------------------------
// B.2 — deterministic system-prompt hash (Sprint 1.3).
//
// The hash is computed AFTER full variable substitution so that semantically
// identical prompts (same persona, same variant) always produce the same
// digest, regardless of cold-start order.  Normalisation steps:
//   1. Resolve all {{...}} placeholders.
//   2. Collapse any run of whitespace to a single space.
//   3. Trim leading/trailing whitespace.
//   4. SHA-256 of the UTF-8 byte string — hex-encoded (64 chars).
//
// Arm B callers that skip proxyDeepSeek write `systemPromptHash: null` on
// their turn docs to keep the schema symmetric.
// ---------------------------------------------------------------------------
function computePromptHash(resolvedPrompt) {
  if (!resolvedPrompt) return null;
  const normalized = resolvedPrompt.trim().replace(/\s+/g, " ");
  return crypto.createHash("sha256").update(normalized, "utf8").digest("hex");
}

// ---------------------------------------------------------------------------
// Sprint 1.B — per-agent decoding temperature (Demo Sprint Plan §1B).
//
// Each companion gets a distinct sampling temperature so the three voices
// feel meaningfully different (arm-A reproducibility: the value is a pure
// function of agentId, written into the request the analyst can replay):
//   • 阿珍／阿伯 (ah_jan_ah_bak) 0.5 — steady, grounded reminiscence peer.
//   • 小欣      (siu_yan)       0.7 — warm daily check-in confidante.
//   • 通通      (tung_tung)     0.85 — lively, curious companion.
// Anything else (referral judgement, unknown agent) keeps the 0.7 default.
// These are STARTING values to be micro-tuned in agent_prompt_bench.py.
// ---------------------------------------------------------------------------
const _AGENT_TEMPERATURE = {
  ah_jan_ah_bak: 0.5,
  siu_yan: 0.7,
  tung_tung: 0.85,
};
const _DEFAULT_TEMPERATURE = 0.7;

function temperatureFor(agentId) {
  if (agentId && Object.prototype.hasOwnProperty.call(
      _AGENT_TEMPERATURE, agentId)) {
    return _AGENT_TEMPERATURE[agentId];
  }
  return _DEFAULT_TEMPERATURE;
}

// ---------------------------------------------------------------------------
// Phase B arm guard.  Arm B (rule-based) participants must never reach an
// LLM, whatever the client does — a routing bug or a stale build must not
// leak Hybrid behaviour into the control arm.  The arm is write-once in
// firestore.rules, so a non-null value is safe to cache per instance.
// A missing arm (Phase A pilot, failed signup assignment) is allowed: the
// Phase A client renders Arm A for everyone.
// ---------------------------------------------------------------------------
const _armCache = new Map();

/**
 * The participant's stored arm ('A' | 'B'), or null when unassigned.
 * @param {string} uid Firebase auth uid.
 * @return {Promise<?string>} Arm code or null.
 */
async function armFor(uid) {
  if (_armCache.has(uid)) return _armCache.get(uid);
  const snap = await admin.firestore().collection("users").doc(uid).get();
  const arm = snap.exists ? (snap.get("arm") || null) : null;
  if (arm) _armCache.set(uid, arm);
  return arm;
}

/**
 * Throws permission-denied for Arm B participants.
 * @param {string} uid Firebase auth uid.
 */
async function assertLlmAllowed(uid) {
  if (await armFor(uid) === "B") {
    throw new HttpsError(
        "permission-denied", "LLM features are not part of this study arm");
  }
}

// T7 — safety switches live in safety_config.js (`meta/safety_config`).
/**
 * One `hotline_filter_log` row per reply in which numbers were replaced.
 * Never stores the reply or the numbers — only how many, of which kind,
 * and whether each was one of the approved crisis numbers.
 * @param {!admin.firestore.Firestore} db Firestore handle.
 * @param {!Object} row uid / agentId / moduleId / items / ruleVersion.
 * @return {Promise<void>} Resolves when written (errors are logged).
 */
async function logHotlineFilter(db, row) {
  try {
    const sum = hotline.summarise(row.items);
    await db.collection("hotline_filter_log").add({
      ts: admin.firestore.FieldValue.serverTimestamp(),
      uid: row.uid || null,
      agent_id: row.agentId || null,
      module_id: row.moduleId || null,
      call_type: llmLog.callTypeForModule(row.moduleId),
      count: row.items.length,
      kinds: sum.kinds,
      approved_count: sum.approved_count,
      unapproved_count: sum.unapproved_count,
      filter_version: hotline.FILTER_VERSION,
      prompt_rule_version: row.ruleVersion || null,
    });
  } catch (err) {
    console.error("hotline_filter_log write failed:", err.message);
  }
}

// ---------------------------------------------------------------------------
// proxyDeepSeek — main LLM entry point. Now supports promptKey resolution
// in addition to the legacy systemPrompt path.
//   payload.promptKey       — resolves prompt file in functions/prompts/
//   payload.variantName     — fills the {{VARIANT_NAME}} placeholder
//   payload.contextSuffix   — extra prompt text appended after the persona
//   payload.systemPrompt    — legacy: raw prompt text (still honoured)
//   payload.agentId         — tagged on the response for analytics
//   payload.messages        — required, OpenAI-style chat history
// ---------------------------------------------------------------------------

exports.proxyDeepSeek = onCall(
  {
    secrets: [DEEPSEEK_API_KEY],
    region: "asia-east2",
    enforceAppCheck: false,
    maxInstances: 10,
    // Bumped 30 → 55s.  DeepSeek-V3 typical latency 4–12s; longer
    // generations (weekly summary, repair regen) can spike to 25s+.
    timeoutSeconds: 55,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    await assertLlmAllowed(request.auth.uid);

    const payload = request.data || {};
    const messages = payload.messages;
    const moduleId = payload.moduleId || "unknown";
    const agentId = payload.agentId || null;

    if (!Array.isArray(messages) || messages.length === 0) {
      throw new HttpsError("invalid-argument", "bad payload: messages");
    }

    let systemPrompt = resolvePrompt(payload);
    if (!systemPrompt) {
      throw new HttpsError(
        "invalid-argument",
        "bad payload: no systemPrompt or promptKey",
      );
    }

    // Hash the persona + client suffix only, so per-turn memory content
    // doesn't fragment prompt-hash analyses.
    const systemPromptHash = computePromptHash(systemPrompt);

    // Memory v1: assembled and policy-filtered here, never on the client.
    // Returns "" unless the kill switch is on and the user is in scope
    // (Phase B Arm A, or an opted-in tester).
    const memoryBlock = await memory.injectMemory(admin.firestore(), {
      uid: request.auth.uid,
      agentId,
      moduleId,
      messages,
    });
    if (memoryBlock) {
      systemPrompt = `${systemPrompt}\n\n${stripPII(memoryBlock)}`;
    }

    // T7 — "never write a phone number" rule, last so it wins.  Appended
    // after the hash for the same reason as the memory block.
    const safetyCfg = await safetyConfig(admin.firestore());
    let hotlineRuleVersion = null;
    if (safetyCfg.hotlinePromptRule) {
      const rule = loadPrompt(hotline.PROMPT_RULE_KEY);
      if (rule) {
        systemPrompt = `${systemPrompt}\n\n${rule}`;
        hotlineRuleVersion = hotline.PROMPT_RULE_KEY;
      }
    }

    // HREC data minimisation: strip identifiers from every outgoing
    // user/assistant message and replace the auth uid with a coded
    // session id.  No raw uid, email, phone, address, HKID leaves the
    // function.
    const scrubbed = messages.map((m) => ({
      role: m.role,
      content: stripPII(m.content || ""),
    }));
    const codedSession = sessionCodeFor(request.auth && request.auth.uid);

    // C04: deepSeekChat logs model / tokens / latency to llm_calls.
    const response = await llmLog.deepSeekChat(admin.firestore(), {
      apiKey: DEEPSEEK_API_KEY.value(),
      // No HKU email / IP in headers; pseudonymous session tag only.
      headers: {"X-Session-Code": codedSession},
      // Under the 55 s function timeout, so a hung call is still logged.
      timeoutMs: 50000,
      log: {
        callType: llmLog.callTypeForModule(moduleId),
        agentId,
        uid: request.auth.uid,
      },
      body: {
        model: DEEPSEEK_MODEL,
        thinking: DEEPSEEK_THINKING,
        messages: [
          {role: "system", content: systemPrompt},
          ...scrubbed,
        ],
        // Bumped 320 → 800.  Older Cantonese phrasing is denser; 320
        // tokens often cut sentences mid-clause and made replies feel
        // curt.  Weekly summary surfaces (m9_weekly_narrative) need
        // more headroom; per-turn caps via the system prompt remain
        // the policy lever for "1-2 sentence" agents.
        max_tokens: 800,
        temperature: temperatureFor(agentId),
        top_p: 0.95,
      },
    });

    if (!response.ok) {
      // Surface the upstream body so the client log can see exactly why
      // (auth, quota, model-not-found, etc.) instead of just "deepseek
      // 500".  Body is bounded so we don't spam the log with HTML.
      const body = response.errorBody;
      console.error("deepseek call failed",
          {status: response.status, body, agentId, moduleId});
      throw new HttpsError(
          "internal", `deepseek ${response.status}: ${body}`);
    }

    const data = response.data;
    const rawText = data.choices &&
      data.choices[0] &&
      data.choices[0].message &&
      data.choices[0].message.content;

    // T7 — hotline outbound filter: no number the model wrote reaches the
    // participant; each becomes the crisis-page token the App renders as a
    // link.  Logged without text.
    let text = rawText;
    let hotlineReplaced = 0;
    if (safetyCfg.hotlineOutputFilter && rawText) {
      const filtered = hotline.filterHotlines(rawText);
      if (filtered.count > 0) {
        text = filtered.text;
        hotlineReplaced = filtered.count;
        await logHotlineFilter(admin.firestore(), {
          uid: request.auth.uid,
          agentId,
          moduleId,
          items: filtered.items,
          ruleVersion: hotlineRuleVersion,
        });
      }
    }

    // B.1 — compute the 5 mechanism flags (Phase A spec May 2026).
    //   1. specific_content_engagement
    //   2. cross_session_memory
    //   3. honest_unfamiliarity
    //   4. mixed_content_routing
    //   5. generative_summary
    // Pure regex pipeline on the (userInput, assistantOutput, agentContext,
    // moduleId) tuple.  Determinism is the contract: same inputs → same
    // flag bundle.  Only Arm A reaches this CF (assertLlmAllowed above);
    // Arm B never calls an LLM.
    const lastUser = [...messages].reverse().find((m) => m.role === "user");
    const llmFlags = computeLlmFlags({
      userInput: lastUser ? (lastUser.content || "") : "",
      assistantOutput: text || "",
      agentContext: payload.agentContext || null,
      moduleId: moduleId,
    });

    return {
      text: text || "",
      moduleId: moduleId,
      agentId: agentId,
      systemPromptHash: systemPromptHash,
      llmFlags: llmFlags,
      // L-2 — provenance echoed back for the client's per-turn log.
      model: (data && data.model) || null,
      temperature: temperatureFor(agentId),
      promptVersion: withRuleVersion(
          promptVersionFor(payload.promptKey || null), hotlineRuleVersion),
      // T7 — how many phone numbers were replaced, and the rule in force.
      hotlineReplaced: hotlineReplaced,
      hotlineRuleVersion: hotlineRuleVersion,
    };
  },
);

/**
 * Spec 3.10: promptVersion is built from every prompt file in use, so the
 * hotline rule joins the persona label ("siu_yan_v1@2026-06+hotline_rule.v1").
 * @param {?string} personaVersion From promptVersionFor; null for raw prompts.
 * @param {?string} ruleVersion Hotline rule key, or null when switched off.
 * @return {?string} Combined label.
 */
function withRuleVersion(personaVersion, ruleVersion) {
  if (!personaVersion || !ruleVersion) return personaVersion;
  return `${personaVersion}+${ruleVersion}`;
}

// ---------------------------------------------------------------------------
// safetyAcknowledgement – returns the templated per-agent safety text.
// ---------------------------------------------------------------------------

exports.safetyAcknowledgement = onCall(
  {region: "asia-east2", enforceAppCheck: false, maxInstances: 5},
  async (request) => {
    const payload = request.data || {};
    const agentId = payload.agentId;
    const level = payload.level || "moderate";
    const locale = payload.locale === "en" ? "en" : "zh";
    const acks = loadSafetyAcks();
    const forAgent = acks[agentId];
    if (!forAgent) return {text: ""};
    const forLevel = forAgent[level] || forAgent.moderate || null;
    if (!forLevel) return {text: ""};
    return {text: fillHotline(forLevel[locale] || forLevel.zh || "", locale)};
  },
);

// ---------------------------------------------------------------------------
// referralJudgement – Cross-referral Layer 2 (Dev Req §5.2).
// ---------------------------------------------------------------------------

exports.referralJudgement = onCall(
  {
    secrets: [DEEPSEEK_API_KEY],
    region: "asia-east2",
    enforceAppCheck: false,
    maxInstances: 10,
    timeoutSeconds: 20,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    await assertLlmAllowed(request.auth.uid);
    const payload = request.data || {};
    const sourceAgentId = payload.sourceAgentId;
    const targetAgentId = payload.targetAgentId;
    const matchedText = payload.matchedText || "";
    const recentTurns = Array.isArray(payload.recentTurns) ?
      payload.recentTurns :
      [];
    const locale = payload.locale === "en" ? "en" : "zh";

    if (!sourceAgentId || !targetAgentId) {
      throw new HttpsError(
        "invalid-argument",
        "bad payload: agent ids required",
      );
    }

    const sourcePrompt = resolvePrompt({
      promptKey: `${sourceAgentId}_v1`,
      variantName: payload.variantName,
    });
    if (!sourcePrompt) {
      throw new HttpsError("internal", "source persona prompt missing");
    }

    const judgementPrompt = locale === "en" ?
      `A cross-referral candidacy flag has been raised for ${targetAgentId}.
The matched user content was: "${matchedText}"

Considering the full conversation, decide one of:
SURFACE: user is wrapping up or wants this content addressed more deeply.
DEFER: user is mid-thought or the matter is already being addressed.
SKIP: the content is incidental.

Constraints:
- At most one referral per conversation.
- Do not surface if the user explicitly said they want to keep talking
  to you, or if a referral was offered in the past 5 turns.

Reply in this exact JSON shape:
{"decision":"SURFACE|DEFER|SKIP","suggestion":"<the referral phrasing in
your own agent voice if SURFACE, else empty>"}` :
      `而家有個 cross-referral 候選 raise 咗，target 係 ${targetAgentId}。
觸發內容係：「${matchedText}」

睇翻段對話，答以下其中一個：
SURFACE: 用戶有 wrap up 跡象或者想呢段內容俾人接住傾深啲。
DEFER: 用戶仲喺諗緊或者你哋已經喺處理緊。
SKIP: 內容係順帶一句，唔重要。

限制：
- 一段對話最多一次 referral。
- 用戶明確話「想繼續同你」唔好 surface。
- 過去 5 turn 內已經 offer 過 referral 唔好再 surface。

請用呢個 JSON 格式答：
{"decision":"SURFACE|DEFER|SKIP","suggestion":"<如果 SURFACE 用你本人嘅
agent 聲音寫邀請；其他情況留空>"}`;

    // P-2 (2026-09): same identifier scrub as proxyDeepSeek — the recent
    // turns and the matched phrase are participant text leaving the region.
    const messages = [];
    recentTurns.slice(-10).forEach((t) => {
      if (t && t.role && t.content) {
        messages.push({role: t.role, content: stripPII(t.content)});
      }
    });
    messages.push({role: "user", content: stripPII(judgementPrompt)});

    const response = await llmLog.deepSeekChat(admin.firestore(), {
      apiKey: DEEPSEEK_API_KEY.value(),
      timeoutMs: 17000, // function timeout is 20 s
      log: {
        callType: "referral_judgement",
        agentId: sourceAgentId,
        uid: request.auth.uid,
      },
      body: {
        model: DEEPSEEK_MODEL,
        thinking: DEEPSEEK_THINKING,
        messages: [
          {role: "system", content: sourcePrompt},
          ...messages,
        ],
        max_tokens: 200,
        temperature: 0.3,
        response_format: {type: "json_object"},
      },
    });

    if (!response.ok) {
      throw new HttpsError("internal", `deepseek ${response.status}`);
    }
    const data = response.data;
    const text = data.choices &&
      data.choices[0] &&
      data.choices[0].message &&
      data.choices[0].message.content;
    let parsed = {decision: "SKIP", suggestion: ""};
    try {
      parsed = JSON.parse(text || "{}");
    } catch (err) {
      parsed = {decision: "SKIP", suggestion: ""};
    }
    if (!["SURFACE", "DEFER", "SKIP"].includes(parsed.decision)) {
      parsed.decision = "SKIP";
    }
    return parsed;
  },
);

// ---------------------------------------------------------------------------
// webSearch – Tung Tung's grounded lookup (Dev Req §6.1).
// Using Brave Search API (replaces Google Custom Search JSON API).
// ---------------------------------------------------------------------------

const SEARCH_API_KEY = defineSecret("SEARCH_API_KEY");

const _searchSafetyDeny = [
  /\b(diagnose|diagnosis|prescribe|cure|dosage)\b/i,
  /(處方|劑量|診斷指引|醫療建議)/,
  /\b(buy now|sell now|invest in)\b/i,
  /(股票推介|理財建議|投資建議)/,
  /\b(self.?harm|suicide method)\b/i,
  /(自殺方法|自殘方法)/,
];

function passesSafetyFilter(text) {
  if (!text || typeof text !== "string") return false;
  for (const pat of _searchSafetyDeny) {
    if (pat.test(text)) return false;
  }
  return true;
}

exports.webSearch = onCall(
  {
    secrets: [SEARCH_API_KEY],
    region: "asia-east2",
    enforceAppCheck: false,
    maxInstances: 5,
    timeoutSeconds: 20,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    // Phase B: off unless app_config/feature_flags.webSearchEnabled is
    // true (decision 0019).  Checked before anything is sent to Brave.
    await featureFlags.assertFeatureEnabled(
        admin.firestore(), "webSearchEnabled");
    await assertLlmAllowed(request.auth.uid);
    const payload = request.data || {};
    const query = (payload.query || "").trim();
    if (!query) {
      throw new HttpsError("invalid-argument", "empty query");
    }

    let apiKey = "";
    let apiKeyErr = null;
    try {
      apiKey = SEARCH_API_KEY.value();
    } catch (err) {
      apiKeyErr = err;
    }

    if (!apiKey) {
      console.warn("webSearch unavailable: search_api_key_unset",
        {apiKeyErr: apiKeyErr && apiKeyErr.message});
      return {results: [], unavailable: true, reason: "search_api_key_unset"};
    }

    const url = new URL("https://api.search.brave.com/res/v1/web/search");
    url.searchParams.set("q", query);
    url.searchParams.set("count", "5");
    url.searchParams.set("safesearch", "strict");

    const response = await fetch(url.toString(), {
      headers: {
        "Accept": "application/json",
        "Accept-Encoding": "gzip",
        "X-Subscription-Token": apiKey,
      },
    });

    if (!response.ok) {
      throw new HttpsError("internal", `search ${response.status}`);
    }

    const data = await response.json();
    const items = Array.isArray(data.web && data.web.results)
      ? data.web.results : [];
    const results = items
      .map((it) => ({
        title: it.title || "",
        snippet: it.description || "",
        link: it.url || "",
      }))
      .filter((r) => passesSafetyFilter(`${r.title} ${r.snippet}`));
    return {results: results, unavailable: false};
  },
);

// ---------------------------------------------------------------------------
// transcribeAudio — Cantonese voice-to-text via Google Cloud Speech-to-Text
// v2 (NOT Whisper: OpenAI is unavailable in HK and rewrites Cantonese into
// written Mandarin, losing 嘅/唔/咗/佢/冇). Auth is ADC (the Firebase project
// IS the GCP project) — no API key / secret. Audio arrives base64-inline in
// the callable; it is NOT stored.
//
// Two-tier model with auto-fallback (see TASK_stt_vertical_slice):
//   A: asia-southeast1 / chirp_2  (must set apiEndpoint or v2 hits global)
//   B: global / long
//
// Request:  { audioBase64, mimeType, languageCode?, model? }
// Response: { transcript, confidence, model, region, latencyMs }
// Slice limit: 60s / 10MB sync recognize; larger → error (batch is later).
// ---------------------------------------------------------------------------
const STT_TIERS = [
  {
    location: "asia-southeast1",
    model: "chirp_2",
    apiEndpoint: "asia-southeast1-speech.googleapis.com",
  },
  {location: "global", model: "long", apiEndpoint: undefined},
];

exports.transcribeAudio = onCall(
  {
    region: "asia-east2",
    enforceAppCheck: false,
    maxInstances: 5,
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    // Phase B: off unless app_config/feature_flags.voiceInputEnabled is
    // true (decision 0019).  Important: switch back on once HREC approves
    // the STT amendment.
    await featureFlags.assertFeatureEnabled(
        admin.firestore(), "voiceInputEnabled");

    const payload = request.data || {};
    const audioBase64 = payload.audioBase64;
    const languageCode = payload.languageCode || "yue-Hant-HK";
    const forcedModel = payload.model || null;

    if (typeof audioBase64 !== "string" || audioBase64.length === 0) {
      throw new HttpsError("invalid-argument", "audioBase64 required");
    }

    const content = Buffer.from(audioBase64, "base64");
    if (content.length > 10 * 1024 * 1024) {
      throw new HttpsError(
        "invalid-argument",
        "audio too large for sync recognize",
      );
    }

    // Lazy require so cold starts of other functions aren't slowed by it.
    const {SpeechClient} = require("@google-cloud/speech").v2;
    const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;

    let lastErr;
    const tiers = forcedModel ?
      STT_TIERS.filter((t) => t.model === forcedModel) :
      STT_TIERS;

    for (const tier of tiers) {
      const t0 = Date.now();
      try {
        const client = new SpeechClient(
          tier.apiEndpoint ? {apiEndpoint: tier.apiEndpoint} : {},
        );
        const [resp] = await client.recognize({
          recognizer:
            `projects/${projectId}/locations/${tier.location}/recognizers/_`,
          config: {
            autoDecodingConfig: {},
            languageCodes: [languageCode],
            model: tier.model,
            features: {enableAutomaticPunctuation: true},
          },
          content,
        });

        const results = resp.results || [];
        const transcript = results
          .map((r) => (r.alternatives && r.alternatives[0] &&
            r.alternatives[0].transcript) || "")
          .join("")
          .trim();
        const confidence =
          (results[0] && results[0].alternatives &&
            results[0].alternatives[0] &&
            results[0].alternatives[0].confidence) || null;
        const latencyMs = Date.now() - t0;

        // Best-effort cost/usage log (audio seconds ≈ latency is not the
        // duration, so we log payload bytes as a proxy for now).
        try {
          await admin.firestore().collection("stt_usage").add({
            uid: request.auth.uid,
            model: tier.model,
            region: tier.location,
            bytes: content.length,
            latencyMs,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (logErr) {
          // non-fatal
        }

        return {
          transcript,
          confidence,
          model: tier.model,
          region: tier.location,
          latencyMs,
        };
      } catch (e) {
        console.warn(
          `stt tier ${tier.location}/${tier.model} failed: ${e.message}`,
        );
        lastErr = e;
      }
    }
    throw new HttpsError(
      "internal",
      `all stt tiers failed: ${lastErr && lastErr.message}`,
    );
  },
);

// ---------------------------------------------------------------------------
// B.7 — safety_events onCreate trigger (Sprint 1.2; dedup rewritten T7).
//
// Fires when the client writes a new doc to `safety_events/{eventId}`.
// Responsibilities:
//   1. Compute dedup_key.  T7 (decision 0018): one conversational turn is
//      ONE counted event, whichever scans (user_input / ai_output_scan)
//      fired.  The key therefore never contains `source`:
//        - with `turnId` (every client since T7): sha256(uid|turn|turnId);
//        - without (older clients): sha256(uid|textHash|minuteBucket).
//      The pre-T7 key included `source`, so a turn whose input and output
//      both matched produced two alerts — the opposite of what this
//      comment used to promise.
//   2. Claim `safety_event_dedup/{dedup_key}` in a transaction.  The first
//      event of the turn is the primary (`isDuplicate: false`).  A later
//      event of the same turn is marked `isDuplicate: true` +
//      `duplicateOf`; if its level is higher (e.g. the AI reply scan hit
//      acute after a moderate input), the primary is raised to that level
//      and records `escalatedBy`, so counting `isDuplicate == false` rows
//      gives one row per turn at the turn's highest level.
//   3. Make sure `source` is present (rules already require it).
//   4. For acute events (or a duplicate that escalated the turn to acute):
//      write `pi_alerts` and email PI (if SMTP secrets are configured).
// ---------------------------------------------------------------------------

const _LEVEL_RANK = {none: 0, low: 1, moderate: 2, acute: 3};
const _TIER_RANK = {
  none: 0, low: 1, moderate_review: 2, moderate_interrupt: 3, acute: 4,
};

/**
 * Severity rank of an event (tier when present, else the legacy level).
 * @param {?string} level Legacy 4-band level.
 * @param {?string} tier S-1 tier code.
 * @return {number} Higher is more severe.
 */
function severityRank(level, tier) {
  if (tier && Object.prototype.hasOwnProperty.call(_TIER_RANK, tier)) {
    return _TIER_RANK[tier];
  }
  const r = _LEVEL_RANK[level];
  // Legacy `moderate` sits between review and interrupt; treat it as
  // interrupt (the fail-safe side, like DistressLevel.parse).
  return r === 2 ? 3 : (r === 3 ? 4 : (r || 0));
}

/**
 * dedup key for an event; see the block comment above.
 * @param {!Object} data Event fields.
 * @param {number} minuteBucket Floor(createTime / 60 s).
 * @return {string} hex sha256.
 */
function safetyDedupKey(data, minuteBucket) {
  const uid = data.uid || "";
  const input = data.turnId ?
    `${uid}|turn|${data.turnId}` :
    `${uid}|${data.textHash || ""}|${minuteBucket}`;
  return crypto.createHash("sha256").update(input, "utf8").digest("hex");
}

exports.onSafetyEventCreated = onDocumentCreated(
  {
    document: "safety_events/{eventId}",
    region: "asia-east2",
    secrets: [SMTP_HOST, SMTP_USER, SMTP_PASS, PI_EMAIL],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (!data) return;

    const db = admin.firestore();
    const uid = data.uid || "";
    const source = data.source || "unknown";
    const textHash = data.textHash || "";
    let level = data.level || "none";
    const tier = data.tier || null;
    const rank = severityRank(level, tier);

    // minuteBucket: floor to 1-minute window using the doc's server timestamp.
    const createSeconds = snap.createTime ?
      snap.createTime.seconds :
      Math.floor(Date.now() / 1000);
    const minuteBucket = Math.floor(createSeconds / 60);
    const dedupKey = safetyDedupKey(data, minuteBucket);

    // Claim the dedup slot.  An existing slot means another scan of the
    // same turn got there first: this event is a duplicate, and may raise
    // the turn's level.
    const dedupRef = db.collection("safety_event_dedup").doc(dedupKey);
    let primaryPath = null;
    let primaryRank = 0;
    try {
      await db.runTransaction(async (tx) => {
        const existing = await tx.get(dedupRef);
        if (existing.exists) {
          primaryPath = existing.get("eventRef") || null;
          primaryRank = existing.get("rank") || 0;
          if (rank > primaryRank) {
            tx.update(dedupRef, {rank, level, tier});
          }
          return;
        }
        tx.create(dedupRef, {
          uid,
          source,
          textHash,
          turnId: data.turnId || null,
          minuteBucket,
          rank,
          level,
          tier,
          eventRef: snap.ref.path,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (err) {
      // Unexpected error: log and fall through so the alert still fires.
      console.error("safety_event dedup tx error:", err);
    }

    const patch = {dedup_key: dedupKey, isDuplicate: primaryPath !== null};
    if (!data.source) patch.source = source;
    if (primaryPath !== null) patch.duplicateOf = primaryPath;
    await snap.ref.update(patch);

    if (primaryPath !== null) {
      if (rank <= primaryRank) {
        console.log(`safety_event dedup hit for key=${dedupKey.slice(0, 8)}`);
        return;
      }
      // Same turn, higher level: raise the primary so the counted row
      // carries the turn's highest level.
      try {
        await db.doc(primaryPath).update({
          level,
          tier,
          escalatedBy: {
            source,
            eventPath: snap.ref.path,
            matchedTerm: data.matchedTerm || null,
            category: data.category || null,
          },
        });
      } catch (err) {
        console.error("safety_event escalation update failed:", err.message);
      }
      // Alert only if the turn just became acute; an acute primary
      // already alerted.
      if (level !== "acute" || primaryRank >= _TIER_RANK.acute) return;
      level = "acute";
    }

    // Only acute events page PI immediately.
    if (level !== "acute") return;

    // T4 — tester suppression. During Day-6 adversarial testing 4–5
    // colleagues deliberately type distress phrases; without this the PI
    // mailbox would be flooded. Tester acute events are STILL recorded
    // (safety_events + a tagged pi_alert for the audit trail) but never
    // trigger the PI email. The flag lives on the user doc.
    let isTester = false;
    try {
      const userSnap = await db.collection("users").doc(uid).get();
      isTester = userSnap.exists && userSnap.data().isTester === true;
    } catch (err) {
      console.error("isTester lookup failed:", err.message);
    }

    const agentId = data.agentId || "unknown";
    const alertPayload = {
      uid,
      source,
      inputPoint: data.inputPoint || null,
      level,
      agentId,
      dedupKey,
      isTester,
      eventPath: snap.ref.path,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Always write to pi_alerts — PI dashboard reads from here (Sprint 3).
    // Tester rows are tagged so the dashboard can filter them out.
    await db.collection("pi_alerts").add(alertPayload);

    if (isTester) {
      console.log(`tester acute event ${snap.ref.path}: PI email suppressed`);
      return;
    }

    // Email PI if SMTP secrets are configured.
    let smtpHost = "";
    let smtpUser = "";
    let smtpPass = "";
    let piEmail = "";
    try {
      smtpHost = SMTP_HOST.value();
      smtpUser = SMTP_USER.value();
      smtpPass = SMTP_PASS.value();
      piEmail = PI_EMAIL.value();
    } catch (_) { /* secrets not configured */ }

    if (!smtpHost || !smtpUser || !smtpPass || !piEmail) {
      console.log("SMTP not configured; pi_alert written to Firestore only");
      return;
    }

    const nodemailer = require("nodemailer");
    const transporter = nodemailer.createTransport({
      host: smtpHost,
      port: 587,
      secure: false,
      auth: {user: smtpUser, pass: smtpPass},
    });
    await transporter.sendMail({
      from: smtpUser,
      to: piEmail,
      subject: `[LonelinessCombatting] Acute distress alert — ${agentId}`,
      text: [
        "An acute distress event was detected.",
        `Agent: ${agentId}`,
        `Source: ${source}`,
        `Input point: ${data.inputPoint || "unknown"}`,
        `Event path: ${snap.ref.path}`,
        "",
        "Review the safety_events collection in the Firebase Console.",
        "Do NOT reply to this automated message.",
      ].join("\n"),
    });
    console.log(`Acute alert email sent to PI for event ${snap.ref.path}`);
  },
);

// ---------------------------------------------------------------------------
// B.5 — Thought Exercise audit queue trigger (Sprint 2.2).
//
// Fires when a new ThoughtExerciseEntry lands at
// `users/{uid}/thought_exercise/{entryId}`.  Writes a corresponding audit
// document to `te_audit_queue/{auditId}` for the researcher dashboard
// (B.13 in Sprint 3) to surface and classify against 6 audit dimensions.
//
// Race-condition fix (sprint-plan R7):
//   agentInvitationText and originTurnRef are read from the entry doc
//   itself — they were cached there at entry-create time by the Siu Yan
//   offer pathway in the Dart layer.  We do NOT read
//   agent_contexts.siu_yan.shortTermBuffer here, because by the time the
//   trigger fires the buffer may have rotated.
//
// The audit doc holds 6 placeholder dimensions (filled by the researcher
// during review):
//   1. invitation_appropriateness   (1-5)
//   2. content_clinical_drift       (boolean)
//   3. mechanism_alignment          (1-5)
//   4. cultural_fit                 (1-5)
//   5. safety_concern               (none|low|medium|high)
//   6. researcher_notes             (free text)
// ---------------------------------------------------------------------------

exports.onThoughtExerciseCreated = onDocumentCreated(
  {
    document: "users/{uid}/thought_exercise/{entryId}",
    region: "asia-east2",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const entry = snap.data();
    if (!entry) return;

    const {uid, entryId} = event.params;
    const db = admin.firestore();

    // Phase A: 100% audit of every Thought Exercise event (Phase A
    // Proposal §5.5).  This is the protocol's most safety-sensitive
    // audit; the boundary between self-help and clinical cognitive
    // restructuring is empirically characterised here.
    //
    // Sampling rate is controlled by the TE_AUDIT_SAMPLE_RATE env var
    // (default 1.0 = 100%).  Phase B may lower this to 0.20 once the
    // boundary is established in Phase A.  Deterministic sampling via
    // sha256(entryId) so audits are reproducible.
    const sampleRate = Number(process.env.TE_AUDIT_SAMPLE_RATE || "1.0");
    const sampleBucket = parseInt(
      crypto.createHash("sha256")
        .update(entryId, "utf8")
        .digest("hex")
        .slice(0, 4),
      16,
    ) / 0xFFFF;
    const sampled = sampleBucket < sampleRate;

    // Always write the audit doc but mark non-sampled ones so the dashboard
    // can hide them by default while keeping a complete index.
    //
    // Audit fields are the 6 dimensions from Phase A Proposal §5.5:
    //   c1 situation_framing      — self-help vs forced-narrative
    //   c2 emotion_register       — self-monitoring vs escalating affect
    //   c3 thought_naming         — gentle vs clinical labelling
    //   c4 reason_field           — self-help register vs reinforcing pathology
    //   c5 alternative_field      — self-help vs therapeutic restructuring
    //   c6 affect_at_exit         — stable/improved / dampened / escalated
    // Overall classification: within_self_help (0–1 crossed) | ambiguous (2) |
    // boundary_crossed (≥3).
    await db.collection("te_audit_queue").add({
      entryRef: snap.ref.path,
      uid,
      entryId,
      // Cached at entry-create-time — no race with buffer rotation.
      agentId: entry.agentId || null,
      agentInvitationText: entry.agentInvitationText || null,
      originTurnRef: entry.originTurnRef || null,
      entryPathway: entry.entryPathway || "me_tile",
      // Thumbnail for queue UI; full content lives in the entryRef doc.
      thoughtPreview: (entry.thought || "").slice(0, 80),
      sampled,
      status: "pending",
      audit: {
        c1_situation_framing: null,
        c2_emotion_register: null,
        c3_thought_naming: null,
        c4_reason_field: null,
        c5_alternative_field: null,
        c6_affect_at_exit: null,
        overall_classification: null,
        researcher_notes: null,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(
      `te_audit_queue: queued ${snap.ref.path} (sampled=${sampled})`,
    );
  },
);

// ---------------------------------------------------------------------------
// C.1 — Weekly loneliness probe (Sprint 3.3).
//
// Cron: every Sunday 09:00 HKT (Asia/Hong_Kong; no DST so the wall time is
// stable year-round, but we set the tz explicitly to lock the contract).
//
// Phase A gate: writes to a per-user `pending_loneliness_probes/{uid}` doc
// that the client polls on app open.  An FCM push is sent only when the
// `weeklyProbeEnabled` feature flag is true on the user's profile —
// in Phase A this flag is false for every user (kill switch is the default
// state), so the cron emits the doc but the user never sees the probe.
//
// The probe itself: 1-item slider (UCLA-3 short form / single-item
// loneliness scale), captured client-side and written to
// `users/{uid}/loneliness_probes/{auto-id}`.
// ---------------------------------------------------------------------------

exports.weeklyLonelinessProbe = onSchedule(
  {
    schedule: "0 9 * * SUN",
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 1,
  },
  async (_event) => {
    const db = admin.firestore();
    const usersSnap = await db.collection("users").get();
    const writes = [];
    const now = admin.firestore.FieldValue.serverTimestamp();
    const todayKey = new Date()
        .toLocaleDateString("en-CA", {timeZone: "Asia/Hong_Kong"});
    for (const userDoc of usersSnap.docs) {
      const data = userDoc.data() || {};
      const enabled = data.weeklyProbeEnabled === true;
      if (!enabled) continue;
      // B.10 — respect 今日休息.  If the user activated quiet-today
      // (HK local day matches today), skip enqueueing the probe.
      const quietRaw = data.quietTodayActivatedAt;
      if (quietRaw) {
        const quietDate = typeof quietRaw === "string" ?
          quietRaw.slice(0, 10) :
          (quietRaw.toDate ? quietRaw.toDate()
              .toLocaleDateString("en-CA", {timeZone: "Asia/Hong_Kong"}) :
              null);
        if (quietDate === todayKey) continue;
      }
      writes.push(
        db.collection("pending_loneliness_probes").doc(userDoc.id).set({
          uid: userDoc.id,
          dueAt: now,
          status: "pending",
        }, {merge: true}),
      );
    }
    await Promise.all(writes);
    console.log(`weeklyLonelinessProbe: enqueued ${writes.length} probes`);
  },
);

// ---------------------------------------------------------------------------
// C.4 — Analyst-blind data export (Sprint 3.5).
//
// Cron: every Sunday 02:00 HKT — runs before C.1 so the weekly snapshot
// captures the week just past, not the new week's first events.
//
// Writes one NDJSON file per collection into the project's default Cloud
// Storage bucket under `exports/{YYYY-MM-DD}/{collection}.ndjson`.  Each
// row strips identifiers and rewrites `arm` → blinded `groupCode`
// (`Group_X` for one arm, `Group_Y` for the other).  The X/Y → A/B
// mapping is rotated weekly via a separate `export_blind_keys` doc
// readable only by the PI role.
//
// Collections exported (whitelist — anything not listed is NOT exported):
//   users (profile minus PII)
//   users/{uid}/events
//   users/{uid}/ppr_responses
//   users/{uid}/llm_turn_features
//   users/{uid}/thought_exercise
//   users/{uid}/loneliness_probes
//   safety_events (uid hashed)
//   pi_alerts (uid hashed)
// ---------------------------------------------------------------------------

const _EXPORT_BLINDED_COLLECTIONS = [
  "users",
  "events",
  "ppr_responses",
  "llm_turn_features",
  "thought_exercise",
  "loneliness_probes",
  // Phase A baseline (2026-09) — L-1 / M-1…M-4 / M-6 surfaces.  `turns`
  // carries no transcript except `te.offerText` (the audited TE
  // invitation, which quotes the participant's own sentence).
  "turns",
  "sessions",
  "brief_pr",
  "weekly_pr",
  "pgic",
  "djg_es",
  "djg_responses",
  "agent_diff",
  "daily_mood",
  "response_feedback",
  "safety_events",
  "pi_alerts",
];

function hashUid(uid, salt) {
  return crypto
    .createHash("sha256")
    .update(`${salt}|${uid}`, "utf8")
    .digest("hex")
    .slice(0, 16);
}

/**
 * Strip PII fields and rewrite arm → blinded group code.  The mapping
 * (Group_X → A or B) is randomised weekly and stored in
 * `export_blind_keys/{date}` so only the PI can de-blind.
 */
function blindRow(row, {armMapping, salt, includeUid}) {
  const out = {};
  for (const [k, v] of Object.entries(row)) {
    if (k === "email" ||
        k === "displayName" ||
        k === "emergencyContactName" ||
        k === "emergencyContactPhone" ||
        k === "closeContacts") {
      continue; // strip PII
    }
    if (k === "uid") {
      if (includeUid) out["uidHash"] = hashUid(v, salt);
      continue;
    }
    if (k === "arm" && typeof v === "string") {
      out["groupCode"] = armMapping[v] || null;
      continue;
    }
    out[k] = v;
  }
  return out;
}

exports.blindedDataExport = onSchedule(
  {
    schedule: "0 2 * * SUN",
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 1,
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (_event) => {
    const db = admin.firestore();
    const dateKey = new Date()
      .toLocaleDateString("en-CA", {timeZone: "Asia/Hong_Kong"}); // YYYY-MM-DD

    // T12 (decision 0021): with meta/blinding_config.enabled the v2 export
    // (research IDs, fixed group mapping, outcome allowlist) replaces the
    // legacy one below.  Off by default.
    const blindingConfig = await blinding.readBlindingConfig(db);
    if (blindingConfig.enabled) {
      const built = await blinding.buildBlindedExport(db, {
        dateKey, includeUsageSummary: blindingConfig.includeUsageSummary,
        includeBriefPr: blindingConfig.includeBriefPr,
      });
      const n = await blinding.writeBlindedExport(
          admin.storage().bucket(), built, dateKey);
      console.log(`blindedDataExport v2: wrote ${n} files for ${dateKey}`);
      return;
    }

    // Legacy export (switch off).  Known leaks: T2 report 3.3.
    // Generate this week's blind mapping (X/Y → A/B) and salt.  Stored
    // in a separate collection that the working analyst cannot read; only
    // the PI's service account.
    const shuffleA = Math.random() < 0.5;
    const armMapping = shuffleA
      ? {"A": "Group_X", "B": "Group_Y"}
      : {"A": "Group_Y", "B": "Group_X"};
    const salt = crypto.randomBytes(16).toString("hex");
    await db.collection("export_blind_keys").doc(dateKey).set({
      mapping: armMapping,
      salt: salt,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Stream every user; for each, read whitelisted sub-collections.
    const usersSnap = await db.collection("users").get();
    const ndjsonByCollection = {};
    for (const name of _EXPORT_BLINDED_COLLECTIONS) {
      ndjsonByCollection[name] = [];
    }

    for (const userDoc of usersSnap.docs) {
      const userRow = userDoc.data();
      userRow.uid = userDoc.id;
      ndjsonByCollection.users.push(
        JSON.stringify(blindRow(userRow, {
          armMapping, salt, includeUid: true,
        })),
      );
      for (const subName of [
        "events", "ppr_responses", "llm_turn_features",
        "thought_exercise", "loneliness_probes",
        "turns", "sessions", "brief_pr", "weekly_pr", "pgic", "djg_es",
        "djg_responses", "agent_diff", "daily_mood", "response_feedback",
      ]) {
        const sub = await userDoc.ref.collection(subName).get();
        for (const d of sub.docs) {
          const row = d.data();
          row.uid = userDoc.id; // include for cross-collection joins
          ndjsonByCollection[subName].push(
            JSON.stringify(blindRow(row, {
              armMapping, salt, includeUid: true,
            })),
          );
        }
      }
    }

    // Top-level admin collections — hash uid even when present.
    for (const name of ["safety_events", "pi_alerts"]) {
      const snap = await db.collection(name).get();
      for (const d of snap.docs) {
        const row = d.data();
        ndjsonByCollection[name].push(
          JSON.stringify(blindRow(row, {
            armMapping, salt, includeUid: true,
          })),
        );
      }
    }

    const bucket = admin.storage().bucket();
    const writes = [];
    for (const [name, lines] of Object.entries(ndjsonByCollection)) {
      if (lines.length === 0) continue;
      const file = bucket.file(`exports/${dateKey}/${name}.ndjson`);
      writes.push(file.save(lines.join("\n"), {
        resumable: false,
        contentType: "application/x-ndjson",
        metadata: {
          metadata: {
            dateKey: dateKey,
            collection: name,
            rowCount: String(lines.length),
            mappingSecret: "see-export_blind_keys-collection",
          },
        },
      }));
    }
    await Promise.all(writes);
    console.log(`blindedDataExport: wrote ${writes.length} files for ${dateKey}`);
  },
);

// ---------------------------------------------------------------------------
// T2 — FCM "doorbell" reminders (Dev TestWeek).
//
// Design: the notification is ONLY a doorbell. Tapping it opens the app; the
// in-app `PendingPromptsBanner` owns all routing. No deep links in v1.
//
// Delivery is to the broadcast topic "all" (FcmService subscribes every
// signed-in device), so no per-token fan-out is needed. iOS/APNs is out of
// scope (T10 / Phase A).
//
// Frequency contract: ≤1/day. The daily mood reminder runs Mon–Sat 19:00
// HKT; Sunday's single push is the weekly-survey reminder at 20:00 HKT
// (when the Weekly PR banner is live), so the two never collide.
//
// Copy is gentle Cantonese, "想答先答" — never nagging, never guilt-tripping.
// ---------------------------------------------------------------------------

async function sendDoorbell(title, body, analyticsLabel) {
  // No explicit channelId: a missing channel suppresses the notification on
  // Android 8+. Relying on the firebase_messaging plugin's default channel
  // is the foolproof v1 doorbell. data.kind is for client-side analytics.
  const message = {
    topic: "all",
    notification: {title, body},
    android: {priority: "normal"},
    data: {kind: analyticsLabel},
  };
  try {
    const id = await admin.messaging().send(message);
    console.log(`doorbell sent (${analyticsLabel}): ${id}`);
  } catch (err) {
    console.error(`doorbell send failed (${analyticsLabel}):`, err.message);
  }
}

// ---------------------------------------------------------------------------
// Memory v1 write path (functions/memory.js).  memoryEndSession runs when
// the user leaves a chat; memorySweep catches sessions that never got a
// clean exit (30 min without a new turn, app killed) and retries failed
// extractions.  Both no-op unless memory v1 is on for the user.
// ---------------------------------------------------------------------------

/**
 * One strict-JSON DeepSeek call for memory extraction, logged to llm_calls
 * (C04) under the given participant and agent.
 * @param {string} uid
 * @param {?string} agentId
 * @return {function({system: string, user: string}): Promise<string>}
 *   resolves to the raw JSON text
 */
function callDeepSeekJsonFor(uid, agentId) {
  return async (prompt) => {
    const response = await llmLog.deepSeekChat(admin.firestore(), {
      apiKey: DEEPSEEK_API_KEY.value(),
      // memoryEndSession allows 60 s, including the Firestore reads and
      // writes around this call.
      timeoutMs: 45000,
      log: {callType: "memory_extraction", agentId, uid},
      body: {
        model: DEEPSEEK_MODEL,
        thinking: DEEPSEEK_THINKING,
        messages: [
          {role: "system", content: prompt.system},
          {role: "user", content: stripPII(prompt.user)},
        ],
        response_format: {type: "json_object"},
        temperature: 0.2,
        max_tokens: 1500,
      },
    });
    if (!response.ok) {
      const body = response.errorBody.slice(0, 300);
      throw new Error(`deepseek ${response.status}: ${body}`);
    }
    const data = response.data;
    return (data.choices && data.choices[0] && data.choices[0].message &&
      data.choices[0].message.content) || "";
  };
}

exports.memoryEndSession = onCall(
  {
    secrets: [DEEPSEEK_API_KEY],
    region: "asia-east2",
    enforceAppCheck: false,
    maxInstances: 10,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const agentId = (request.data || {}).agentId;
    if (!memory.AGENTS.includes(agentId)) {
      throw new HttpsError("invalid-argument", "unknown agentId");
    }
    const db = admin.firestore();
    const uid = request.auth.uid;
    if (!await memory.memoryActive(db, uid)) return {status: "inactive"};
    const id = await memory.claimBuffer(db, uid, agentId);
    if (!id) return {status: "empty"};
    const status = await memory.processExtraction(
        db, uid, id, callDeepSeekJsonFor(uid, agentId));
    return {status};
  },
);

exports.memorySweep = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    secrets: [DEEPSEEK_API_KEY],
    timeoutSeconds: 300,
    retryCount: 0,
  },
  async (_event) => {
    const db = admin.firestore();
    const cfg = await memory.loadConfig(db);
    if (!cfg.enabled) return;
    const idleBefore = Date.now() - 30 * 60 * 1000;
    const staleBefore = Date.now() - 10 * 60 * 1000;
    // In scope: opted-in testers, plus Phase B Arm A when that is on.
    const queries = [db.collection("users")
        .where("memory_enabled", "==", true).get()];
    if (cfg.phaseBArmA) {
      queries.push(db.collection("users")
          .where("arm", "==", "A")
          .where("armAssignmentMode", "==", "randomise").get());
    }
    const byId = new Map();
    for (const snap of await Promise.all(queries)) {
      for (const d of snap.docs) byId.set(d.id, d);
    }
    for (const user of byId.values()) {
      const uid = user.id;
      // Same scope rule as memoryEndSession: never Arm B, never a user
      // whose memory was withdrawn (T10).
      if (!memory.inScope(cfg, user.data())) continue;
      try {
        for (const agentId of memory.AGENTS) {
          const ctx = await user.ref.collection("agent_contexts")
              .doc(agentId).get();
          const buffer = ctx.exists ? (ctx.get("shortTermBuffer") || []) : [];
          const last = ctx.exists ? ctx.get("lastUpdated") : null;
          const lastMs = last && last.toMillis ? last.toMillis() : 0;
          if (buffer.length === 0 || lastMs > idleBefore) continue;
          const id = await memory.claimBuffer(db, uid, agentId);
          if (id) {
            await memory.processExtraction(
                db, uid, id, callDeepSeekJsonFor(uid, agentId));
          }
        }
        // Retry failures; pick up pending ones a crashed run left behind.
        const open = await user.ref.collection("mem_extractions")
            .where("status", "in", ["failed", "pending"]).get();
        for (const ext of open.docs) {
          const created = ext.get("created_at");
          const createdMs = created && created.toMillis ?
            created.toMillis() : 0;
          if ((ext.get("attempts") || 0) >= memory.LIMITS.maxAttempts) {
            continue;
          }
          if (ext.get("status") === "pending" && createdMs > staleBefore) {
            continue;
          }
          await memory.processExtraction(db, uid, ext.id,
              callDeepSeekJsonFor(uid, ext.get("agent_id") || null));
        }
      } catch (err) {
        console.error("memorySweep user failed", {uid, err: String(err)});
      }
    }
  },
);

// T10 (decision 0024, deleteSummaryWithItem): deleting a fact or a
// follow-up on the 「我記得嘅嘢」 page also deletes the summary of the
// session it came from and any item with exactly the same wording, so
// the content cannot come back that way.
for (const [name, col] of [["memoryFactDeleted", "mem_facts"],
  ["memoryFollowupDeleted", "mem_followups"]]) {
  exports[name] = onDocumentDeleted(
      {document: `users/{uid}/${col}/{itemId}`, region: "asia-east2"},
      async (event) => {
        const item = event.data ? event.data.data() : null;
        try {
          await memory.deleteSummaryForItem(admin.firestore(),
              event.params.uid, item);
        } catch (err) {
          console.error("summary delete after item delete failed",
              {uid: event.params.uid, err: String(err)});
        }
      });
}

exports.dailyMoodReminder = onSchedule(
  {
    schedule: "0 19 * * 1-6", // Mon–Sat 19:00 (Sunday handled by weekly)
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 0,
  },
  async (_event) => {
    await sendDoorbell(
      "陪住",
      "今日過得點？得閒入嚟同我哋講兩句，想講先講，唔講都冇所謂。",
      "daily_mood_reminder",
    );
  },
);

exports.weeklySurveyReminder = onSchedule(
  {
    schedule: "0 20 * * 0", // Sunday 20:00, when the Weekly PR banner is live
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 0,
  },
  async (_event) => {
    await sendDoorbell(
      "陪住",
      "今個禮拜過得點？得閒入嚟答幾條，想答先答，唔想都冇問題。",
      "weekly_survey_reminder",
    );
    // Phase A L-1 — `weekly_pr_pushed` per participant.  The doorbell is a
    // topic broadcast, so per-device receipt is unknown; this records that
    // the push was issued for the account (testers excluded).
    try {
      const db = admin.firestore();
      const usersSnap = await db.collection("users").get();
      const weekIso = isoWeekLabel(new Date());
      const writes = [];
      for (const userDoc of usersSnap.docs) {
        const data = userDoc.data() || {};
        if (data.isTester === true) continue;
        writes.push(userDoc.ref.collection("events").add({
          name: "weekly_pr_pushed",
          params: {weekIso, channel: "fcm_topic_all"},
          source: "cf_weeklySurveyReminder",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        }));
      }
      await Promise.all(writes);
      console.log(`weekly_pr_pushed recorded for ${writes.length} users`);
    } catch (err) {
      console.error("weekly_pr_pushed record failed:", err.message);
    }
  },
);

// ISO-8601 week label (e.g. 2026-W37) in HKT, matching the client's
// WeeklyPrResponse.currentWeekIso for the Sunday that opens the window.
function isoWeekLabel(date) {
  const hk = new Date(date.toLocaleString("en-US", {timeZone: "Asia/Hong_Kong"}));
  const d = new Date(Date.UTC(hk.getFullYear(), hk.getMonth(), hk.getDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

// ---------------------------------------------------------------------------
// M-4 (Phase A baseline 2026-09) — Week 2 push.
//
// Daily 10:00 HKT: for every non-tester user whose enrolment day index is
// inside [w2DayOffset, w2DayOffset + w2WindowDays) and who has not yet
// received the push, send a per-device notification (fcm_tokens) and mark
// `w2PushSentAt` on the user doc + a `w2_push_sent` event.  Parameters
// come from `app_config/phase_a` (same doc the client reads) with the spec
// defaults (14 / 3) as fallback.  The in-app banner owns the actual DJG-ES
// + Agent Differentiation routing; this is only the doorbell.
// ---------------------------------------------------------------------------

async function phaseAConfig(db) {
  const defaults = {w2DayOffset: 14, w2WindowDays: 3};
  try {
    const snap = await db.doc("app_config/phase_a").get();
    return {...defaults, ...(snap.exists ? snap.data() : {})};
  } catch (err) {
    return defaults;
  }
}

function hkDateKey(d) {
  return d.toLocaleDateString("en-CA", {timeZone: "Asia/Hong_Kong"});
}

function daysBetweenHk(fromIso, toIso) {
  const a = new Date(`${fromIso}T00:00:00Z`);
  const b = new Date(`${toIso}T00:00:00Z`);
  return Math.round((b - a) / 86400000);
}

// ---------------------------------------------------------------------------
// assignArm — server-side RCT arm assignment (functions/arm.js).  The app
// calls this right after creating the profile (and again on login while the
// profile has no arm).  Idempotent; returns the stored arm on repeat calls.
// ---------------------------------------------------------------------------
exports.assignArm = onCall(
  {region: "asia-east2", enforceAppCheck: false, maxInstances: 10},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    try {
      return await arm.assignArm(admin.firestore(), request.auth.uid);
    } catch (err) {
      if (String(err && err.message) === "profile_missing") {
        throw new HttpsError("failed-precondition", "profile_missing");
      }
      console.error("assignArm failed", {err: String(err)});
      throw new HttpsError("internal", "assignment_failed");
    }
  },
);

exports.week2Push = onSchedule(
  {
    schedule: "0 10 * * *",
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 0,
  },
  async (_event) => {
    const db = admin.firestore();
    const cfg = await phaseAConfig(db);
    // T18 (decision 0027): with the in-app W2 DJG on, djgW2Dispatch owns
    // the Week 2 push for Phase B participants — one push, not two.
    const djgCfg = await djgW2.readConfig(db);
    const today = hkDateKey(new Date());
    const usersSnap = await db.collection("users").get();
    let sent = 0;
    for (const userDoc of usersSnap.docs) {
      const data = userDoc.data() || {};
      if (data.isTester === true) continue;
      if (data.w2PushSentAt) continue;
      if (djgW2.week2PushShouldSkip(djgCfg, data)) continue;
      const createdRaw = data.createdAt;
      if (!createdRaw) continue;
      const createdIso = typeof createdRaw === "string" ?
        createdRaw.slice(0, 10) :
        (createdRaw.toDate ? hkDateKey(createdRaw.toDate()) : null);
      if (!createdIso) continue;
      // 1-based enrolment day (day 1 = signup date), same as the client's
      // enrolmentDay(): 「入組第 14 天」 == day 14.
      const day = daysBetweenHk(createdIso, today) + 1;
      if (day < cfg.w2DayOffset || day >= cfg.w2DayOffset + cfg.w2WindowDays) {
        continue;
      }
      const tokensSnap = await userDoc.ref.collection("fcm_tokens").get();
      const tokens = tokensSnap.docs
          .map((t) => (t.data() || {}).token)
          .filter((t) => typeof t === "string" && t.length > 0);
      let delivered = 0;
      for (const token of tokens) {
        try {
          await admin.messaging().send({
            token,
            notification: {
              title: "陪住",
              body: "入嚟兩個禮拜喇，有幾條短問題想問下你。得閒先答，唔急。",
            },
            android: {priority: "normal"},
            data: {kind: "w2_push"},
          });
          delivered++;
        } catch (err) {
          console.warn(`week2Push token send failed for ${userDoc.id}: ${err.message}`);
        }
      }
      await userDoc.ref.set({
        w2PushSentAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      await userDoc.ref.collection("events").add({
        name: "w2_push_sent",
        params: {enrolmentDay: day, tokens: tokens.length, delivered},
        source: "cf_week2Push",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      sent++;
    }
    console.log(`week2Push: ${sent} users notified`);
  },
);

// ---------------------------------------------------------------------------
// T18 — Week 2 DJG in the App, 6 items (SPEC:C15, decision 0027).  Phase B
// only, both arms identical, no LLM.  Off unless
// app_config/phase_b.djgW2InAppEnabled === true (functions/djg_w2.js).
//   djgW2Dispatch: hourly 08:00–21:00 HKT — the day-14 push (at
//     djgW2PushHour), one reminder 24 h later if not submitted, and the
//     missed mark once the window has closed.
//   onDjgResponseWritten: scores a submitted response server-side.
// ---------------------------------------------------------------------------
exports.djgW2Dispatch = onSchedule(
  {
    schedule: "0 8-21 * * *",
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 0,
  },
  async (_event) => {
    await djgW2.dispatchDjgW2(admin.firestore(), admin.messaging());
  },
);

exports.onDjgResponseWritten = onDocumentWritten(
  {
    document: "users/{uid}/djg_responses/{timepoint}",
    region: "asia-east2",
  },
  async (event) => {
    const after = event.data && event.data.after && event.data.after.exists ?
      event.data.after.data() : null;
    await djgW2.scoreSubmission(admin.firestore(), event.params.uid,
        event.params.timepoint, after);
  },
);

// ---------------------------------------------------------------------------
// Action Loop follow-up reminders (SPEC:C07, decision 0022).  The app queues
// them at users/{uid}/reminders; this sends the due ones to the
// participant's own devices.  Every 15 min, 08:00–21:45 HKT, so nothing
// goes out at night.  Both arms, no LLM.  Off unless
// app_config/reminders.m7FollowupPushEnabled === true (functions/reminders.js).
// ---------------------------------------------------------------------------
exports.dispatchReminders = onSchedule(
  {
    schedule: "*/15 8-21 * * *",
    timeZone: "Asia/Hong_Kong",
    region: "asia-east2",
    retryCount: 0,
  },
  async (_event) => {
    await reminders.dispatchDueReminders(admin.firestore(), admin.messaging());
  },
);

// ---------------------------------------------------------------------------
// Tester-only: send one of the real doorbells to the caller's own devices
// (2026-09-23).  Lets a tester verify delivery, copy and the
// notification_opened event without waiting for the cron.
//
// Guard: caller must be signed in AND `users/{uid}.isTester == true`.
// `delaySeconds` (0–45) gives the tester time to put the app in the
// background — Android does not display a system notification for FCM
// messages received while the app is in the foreground.
// iOS devices will not receive anything until APNs is configured.
// ---------------------------------------------------------------------------

const _TEST_PUSH_COPY = {
  daily_mood_reminder: "今日過得點？得閒入嚟同我哋講兩句，想講先講，唔講都冇所謂。",
  weekly_survey_reminder: "今個禮拜過得點？得閒入嚟答幾條，想答先答，唔想都冇問題。",
  w2_push: "入嚟兩個禮拜喇，有幾條短問題想問下你。得閒先答，唔急。",
};

exports.sendTestPush = onCall(
  {region: "asia-east2", enforceAppCheck: false, maxInstances: 3, timeoutSeconds: 60},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;
    const db = admin.firestore();
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists || userSnap.data().isTester !== true) {
      throw new HttpsError("permission-denied", "tester accounts only");
    }
    const payload = request.data || {};
    const kind = payload.kind;
    if (!Object.prototype.hasOwnProperty.call(_TEST_PUSH_COPY, kind)) {
      throw new HttpsError("invalid-argument", "unknown kind");
    }
    const delay = Math.max(0, Math.min(45, Number(payload.delaySeconds) || 0));
    if (delay > 0) await new Promise((r) => setTimeout(r, delay * 1000));

    const tokensSnap = await userSnap.ref.collection("fcm_tokens").get();
    const tokens = tokensSnap.docs
        .map((t) => (t.data() || {}).token)
        .filter((t) => typeof t === "string" && t.length > 0);
    let delivered = 0;
    const errors = [];
    for (const token of tokens) {
      try {
        await admin.messaging().send({
          token,
          notification: {title: "陪住（測試）", body: _TEST_PUSH_COPY[kind]},
          android: {priority: "high"},
          data: {kind, test: "1"},
        });
        delivered++;
      } catch (err) {
        errors.push(err.code || err.message);
      }
    }
    await userSnap.ref.collection("events").add({
      name: "test_push_sent",
      params: {kind, tokens: tokens.length, delivered, delay},
      source: "cf_sendTestPush",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {tokens: tokens.length, delivered, errors};
  },
);
