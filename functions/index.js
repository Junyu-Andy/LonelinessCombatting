const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {computeLlmFlags} = require("./llm_flags");

admin.initializeApp();

const DEEPSEEK_API_KEY = defineSecret("DEEPSEEK_API_KEY");
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");
const PI_EMAIL = defineSecret("PI_EMAIL");

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

function loadPrompt(key) {
  if (_promptCache[key] !== undefined) return _promptCache[key];
  try {
    const file = path.join(PROMPT_DIR, `${key}.txt`);
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

function resolvePrompt(payload) {
  const promptKey = payload.promptKey;
  const rawPrompt = payload.systemPrompt;
  if (!promptKey && rawPrompt) return rawPrompt;
  if (!promptKey) return null;
  const template = loadPrompt(promptKey);
  if (!template) return rawPrompt || null;
  let out = template;
  const variantName = payload.variantName || "阿Jan／阿伯";
  out = out.split("{{VARIANT_NAME}}").join(variantName);
  const contextSuffix = payload.contextSuffix;
  if (contextSuffix && typeof contextSuffix === "string") {
    out = `${out}\n\n${contextSuffix}`;
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
    enforceAppCheck: true,
    maxInstances: 10,
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }

    const payload = request.data || {};
    const messages = payload.messages;
    const moduleId = payload.moduleId || "unknown";
    const agentId = payload.agentId || null;

    if (!Array.isArray(messages) || messages.length === 0) {
      throw new HttpsError("invalid-argument", "bad payload: messages");
    }

    const systemPrompt = resolvePrompt(payload);
    if (!systemPrompt) {
      throw new HttpsError(
        "invalid-argument",
        "bad payload: no systemPrompt or promptKey",
      );
    }

    const systemPromptHash = computePromptHash(systemPrompt);

    // HREC data minimisation: strip identifiers from every outgoing
    // user/assistant message and replace the auth uid with a coded
    // session id.  No raw uid, email, phone, address, HKID leaves the
    // function.
    const scrubbed = messages.map((m) => ({
      role: m.role,
      content: stripPII(m.content || ""),
    }));
    const codedSession = sessionCodeFor(request.auth && request.auth.uid);

    const response = await fetch(
      "https://api.deepseek.com/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": [
            "Bearer",
            DEEPSEEK_API_KEY.value(),
          ].join(" "),
          // No HKU email / IP in headers; pseudonymous session tag only.
          "X-Session-Code": codedSession,
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          messages: [
            {role: "system", content: systemPrompt},
            ...scrubbed,
          ],
          max_tokens: 320,
          temperature: 0.7,
        }),
      },
    );

    if (!response.ok) {
      throw new HttpsError("internal", `deepseek ${response.status}`);
    }

    const data = await response.json();
    const text = data.choices &&
      data.choices[0] &&
      data.choices[0].message &&
      data.choices[0].message.content;

    // B.1 — compute the 5 mechanism flags (Phase A spec May 2026).
    //   1. specific_content_engagement
    //   2. cross_session_memory
    //   3. honest_unfamiliarity
    //   4. mixed_content_routing
    //   5. generative_summary
    // Pure regex pipeline on the (userInput, assistantOutput, agentContext,
    // moduleId) tuple.  Determinism is the contract: same inputs → same
    // flag bundle.  Both arms go through this CF for safety, but only
    // Arm A clients persist the result.
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
    };
  },
);

// ---------------------------------------------------------------------------
// safetyAcknowledgement – returns the templated per-agent safety text.
// ---------------------------------------------------------------------------

exports.safetyAcknowledgement = onCall(
  {region: "asia-east2", enforceAppCheck: true, maxInstances: 5},
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
    return {text: forLevel[locale] || forLevel.zh || ""};
  },
);

// ---------------------------------------------------------------------------
// referralJudgement – Cross-referral Layer 2 (Dev Req §5.2).
// ---------------------------------------------------------------------------

exports.referralJudgement = onCall(
  {
    secrets: [DEEPSEEK_API_KEY],
    region: "asia-east2",
    enforceAppCheck: true,
    maxInstances: 10,
    timeoutSeconds: 20,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
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

    const messages = [];
    recentTurns.slice(-10).forEach((t) => {
      if (t && t.role && t.content) {
        messages.push({role: t.role, content: t.content});
      }
    });
    messages.push({role: "user", content: judgementPrompt});

    const response = await fetch(
      "https://api.deepseek.com/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": ["Bearer", DEEPSEEK_API_KEY.value()].join(" "),
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          messages: [
            {role: "system", content: sourcePrompt},
            ...messages,
          ],
          max_tokens: 200,
          temperature: 0.3,
          response_format: {type: "json_object"},
        }),
      },
    );

    if (!response.ok) {
      throw new HttpsError("internal", `deepseek ${response.status}`);
    }
    const data = await response.json();
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
    enforceAppCheck: true,
    maxInstances: 5,
    timeoutSeconds: 20,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
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
// B.7 — safety_events onCreate trigger (Sprint 1.2).
//
// Fires when the client writes a new doc to `safety_events/{eventId}`.
// Responsibilities:
//   1. Compute dedup_key = sha256(uid + source + textHash + minuteBucket).
//   2. Attempt to create `safety_event_dedup/{dedup_key}` — if it already
//      exists, a concurrent write from another source beat us this minute;
//      skip the PI alert to avoid flooding.
//   3. Patch the incoming doc with the computed dedup_key.
//   4. For acute events: send email to PI (if SMTP secrets are configured)
//      and write to `pi_alerts` collection.
//
// Dedup window: 1 minute.  All 3 sources (gateway_input, gateway_output,
// m3_turn) for the same user + same text hash within one minute collapse
// to a single alert.
// ---------------------------------------------------------------------------

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
    const level = data.level || "none";

    // minuteBucket: floor to 1-minute window using the doc's server timestamp.
    const createSeconds = snap.createTime ?
      snap.createTime.seconds :
      Math.floor(Date.now() / 1000);
    const minuteBucket = Math.floor(createSeconds / 60);

    const dedupInput = `${uid}|${source}|${textHash}|${minuteBucket}`;
    const dedupKey = crypto
      .createHash("sha256")
      .update(dedupInput, "utf8")
      .digest("hex");

    // Patch the event doc with the computed dedup_key for auditability.
    await snap.ref.update({dedup_key: dedupKey});

    // Attempt to claim the dedup slot.  If it already exists, another source
    // fired within the same minute — skip the PI alert.
    const dedupRef = db.collection("safety_event_dedup").doc(dedupKey);
    try {
      await db.runTransaction(async (tx) => {
        const existing = await tx.get(dedupRef);
        if (existing.exists) {
          throw new Error("duplicate");
        }
        tx.create(dedupRef, {
          uid,
          source,
          textHash,
          minuteBucket,
          eventRef: snap.ref.path,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (err) {
      if (err.message === "duplicate") {
        console.log(`safety_event dedup hit for key=${dedupKey.slice(0, 8)}`);
        return;
      }
      // Unexpected error: log and fall through so the alert still fires.
      console.error("safety_event dedup tx error:", err);
    }

    // Only acute events page PI immediately.
    if (level !== "acute") return;

    const agentId = data.agentId || "unknown";
    const alertPayload = {
      uid,
      source,
      level,
      agentId,
      dedupKey,
      eventPath: snap.ref.path,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Always write to pi_alerts — PI dashboard reads from here (Sprint 3).
    await db.collection("pi_alerts").add(alertPayload);

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
    for (const userDoc of usersSnap.docs) {
      const enabled = userDoc.data()?.weeklyProbeEnabled === true;
      if (!enabled) continue;
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
