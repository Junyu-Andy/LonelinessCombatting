const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

admin.initializeApp();

const DEEPSEEK_API_KEY = defineSecret("DEEPSEEK_API_KEY");
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");
const PI_EMAIL = defineSecret("PI_EMAIL");

// ---------------------------------------------------------------------------
// Prompt resolution (Dev Req §3.2, §8 — prompts live server-side so the
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
  const variantName = payload.variantName || "阿珍／阿伯";
  out = out.split("{{VARIANT_NAME}}").join(variantName);
  const contextSuffix = payload.contextSuffix;
  if (contextSuffix && typeof contextSuffix === "string") {
    out = `${out}\n\n${contextSuffix}`;
  }
  return out;
}

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
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          messages: [
            {role: "system", content: systemPrompt},
            ...messages,
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

    return {
      text: text || "",
      moduleId: moduleId,
      agentId: agentId,
      systemPromptHash: systemPromptHash,
    };
  },
);

// ---------------------------------------------------------------------------
// safetyAcknowledgement — returns the templated per-agent safety text for
// a (agentId, level, locale) tuple. Per Dev Req §9 these strings stay on
// the server so the safety team can revise copy without a mobile release.
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
// referralJudgement — Cross-referral Layer 2 (Dev Req §5.2).
//
// Sprint 5 wires the keyword pre-filter on the client; this function
// asks DeepSeek to decide SURFACE / DEFER / SKIP given the current
// agent's persona and the candidate target.
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

睇翻成段對話，揀以下其中一個：
SURFACE: 用戶有 wrap up 跡象或者想呢段內容俾人接住傾深啲。
DEFER: 用戶仲喺諗緊或者你哋已經喺處理緊。
SKIP: 內容係順帶提一句，唔重要。

限制：
- 一段對話最多一次 referral。
- 用戶明確話「想繼續同你傾」嗰陣唔好 surface。
- 過去 5 turn 內已經 offer 過 referral 唔好再 surface。

請用呢個 JSON 格式答：
{"decision":"SURFACE|DEFER|SKIP","suggestion":"<如果 SURFACE 用你本人嘅
agent 聲音寫嗰句邀請；其他情況留空>"}`;

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
// webSearch — Tung Tung's grounded lookup (Dev Req §6.1).
//
// The actual search backend is pluggable. Sprint 4 ships with a stub
// that returns an empty result set when SEARCH_API_KEY is not set. To
// enable real search:
//   1. Sign up for Google Programmable Search Engine (or alternative).
//   2. firebase functions:secrets:set SEARCH_API_KEY=...
//   3. firebase functions:secrets:set SEARCH_CX=...
//   4. firebase deploy --only functions:webSearch
// ---------------------------------------------------------------------------

const SEARCH_API_KEY = defineSecret("SEARCH_API_KEY");
const SEARCH_CX = defineSecret("SEARCH_CX");

const _searchSafetyDeny = [
  // Health-advice (Dev Req §6.3). Stick to phrases that strongly
  // imply prescribing or diagnosing — earlier drafts matched single
  // characters like 藥 which swallowed all benign Chinese health
  // content.
  /\b(diagnose|diagnosis|prescribe|cure|dosage)\b/i,
  /(處方|劑量|診斷指引|醫療建議)/,
  // Financial-advice
  /\b(buy now|sell now|invest in)\b/i,
  /(股票推介|理財建議|投資建議)/,
  // Self-harm
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
    secrets: [SEARCH_API_KEY, SEARCH_CX],
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
    let cx = "";
    let apiKeyErr = null;
    let cxErr = null;
    try {
      apiKey = SEARCH_API_KEY.value();
    } catch (err) {
      apiKeyErr = err;
    }
    try {
      cx = SEARCH_CX.value();
    } catch (err) {
      cxErr = err;
    }
    if (!apiKey || !cx) {
      const reason = !apiKey && !cx ?
        "both_secrets_unset" :
        !apiKey ? "search_api_key_unset" : "search_cx_unset";
      console.warn("webSearch unavailable:", reason,
          {apiKeyErr: apiKeyErr && apiKeyErr.message,
            cxErr: cxErr && cxErr.message});
      return {results: [], unavailable: true, reason: reason};
    }

    const url = new URL("https://www.googleapis.com/customsearch/v1");
    url.searchParams.set("key", apiKey);
    url.searchParams.set("cx", cx);
    url.searchParams.set("q", query);
    url.searchParams.set("num", "5");
    url.searchParams.set("safe", "active");

    const response = await fetch(url.toString());
    if (!response.ok) {
      throw new HttpsError("internal", `search ${response.status}`);
    }
    const data = await response.json();
    const items = Array.isArray(data.items) ? data.items : [];
    const results = items
      .map((it) => ({
        title: it.title || "",
        snippet: it.snippet || "",
        link: it.link || "",
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
