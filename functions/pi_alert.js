/**
 * Safety alerts to the research team (T19 decision 0029 §五; rewritten in
 * T34, registry v9 C12 / C19 / C20, dev-tasks-1010b §三 T34 as corrected
 * by dev-tasks-1014 §三).
 *
 * One master switch: `meta/alert_config.enabled` (server-only document;
 * missing document or anything but literal `true` = OFF).
 *
 *   OFF  — exactly the T19 behaviour: `buildPiAlert` (v2 row: uid,
 *          research ID, level, dedup key, tester flag, event path) and the
 *          short `buildPiEmail` to the secret `PI_EMAIL`; acute only; no
 *          acknowledgement, no escalation.
 *   ON   — the T34 alert: `buildAlertRow` (v3 row with the fields below),
 *          `buildAlertEmail` (zh + en, fixed field order) to
 *          `alert_config.primaryEmail`; the unblinded researcher
 *          acknowledges in the dashboard (`acknowledge`); an alert nobody
 *          acknowledged within `escalateAfterHours` (default 12) is sent
 *          once more to `alert_config.backupEmail` (`escalateDue`, run by
 *          the scheduled function every 15 minutes).
 *
 * E-mail fields (both modes never carry the arm, the matched term, the
 * text hash, the uid or anything the participant typed):
 *   研究编号 Research ID · 研究期 Study period · 陪伴者 Companion ·
 *   来源 Source · 级别和类别 Level and category · 词库版本 Lexicon
 *   version · LoRA 是否参与判定 Classifier involved · 研究第几天 Study
 *   day · 是否显示危机页 Crisis page shown · 事件编号 Event ID · 告警编号
 *   Alert ID · 时间 Time (HKT).
 *
 * Recipients are never in code: they live in `meta/alert_config` and the
 * launch checklist tells the lead to fill them in the console.  Before
 * every send each address is looked up in Firebase Auth; an account whose
 * custom claim `role` is `blinded` (the W4 assessors) is dropped and an
 * `alert_audit_log` row says so.  An address with no App account is fine
 * (the backup recipient may have none).
 *
 * Tester accounts (`users/{uid}.isTester == true`): alert row, no e-mail,
 * no escalation — as before.
 *
 * Who is blinded has changed since 0029: the lead (Junyu) is `unblinded`
 * (dev-tasks-1010 共同规则 8) and the blinded people are the assessors,
 * who are never recipients.  The decision record superseding 0029 §五 is
 * drafted in docs/dev-reports/T34-safety-alert-email-20261014.md.
 */

"use strict";

const studyPeriod = require("./study_period");
const studyWeek = require("./study_week");

const CONFIG_DOC = "meta/alert_config";
const ALERTS = "pi_alerts";
const AUDIT_LOG = "alert_audit_log";
const DEFAULT_ESCALATE_HOURS = 12;
const BLINDED_ROLE = "blinded";
const UNBLINDED_ROLE = "unblinded";

/**
 * `safety_events.source` → the four analysis buckets (registry C20).
 * `participant_input` and `ai_reply_scan` are raised by the App through
 * SafetyService (lib/core/safety/safety_check.dart); `questionnaire` and
 * `assessor_entry` only by the server (functions/questionnaire_safety.js).
 */
const SOURCE_GROUPS = {
  user_input: "participant_input",
  form: "participant_input",
  gateway_input: "participant_input",
  rule_turn: "participant_input",
  m3_turn: "participant_input",
  ai_output_scan: "ai_reply_scan",
  gateway_output: "ai_reply_scan",
  questionnaire: "questionnaire",
  assessor_entry: "assessor_entry",
};

/** Sources only the server may write; they alert whatever the level. */
const SERVER_ONLY_SOURCES = ["questionnaire", "assessor_entry"];

const SOURCE_DISPLAY = {
  participant_input: {zh: "老人输入", en: "Participant input"},
  ai_reply_scan: {zh: "AI 回复扫描", en: "AI reply scan"},
  questionnaire: {zh: "问卷", en: "Questionnaire"},
  assessor_entry: {zh: "评估员录入", en: "Assessor entry"},
};

const PERIOD_DISPLAY = {
  B: "Phase B",
  PILOT: "试跑 Pilot run",
};

const TIER_DISPLAY = {
  acute: {zh: "急性", en: "acute"},
  moderate_interrupt: {zh: "中度（打断）", en: "moderate_interrupt"},
  moderate_review: {zh: "中度（回顾）", en: "moderate_review"},
  moderate: {zh: "中度", en: "moderate"},
  low: {zh: "低", en: "low"},
  none: {zh: "无", en: "none"},
};

const COMPANION_DISPLAY = {
  siu_yan: "小欣 Siu Yan (siu_yan)",
  ah_jan_ah_bak: "阿珍/阿伯 Ah Jan / Ah Bak (ah_jan_ah_bak)",
  ah_jan: "阿珍 Ah Jan (ah_jan)",
  ah_bak: "阿伯 Ah Bak (ah_bak)",
  tung_tung: "通通 Tung Tung (tung_tung)",
};

const UNKNOWN = "未知 Unknown";
const YES = "是 Yes";
const NO = "否 No";
const NONE = "—";

// ---------------------------------------------------------------------------
// T19 (decision 0029) builders — the switch-off path.  Unchanged.
// ---------------------------------------------------------------------------

/**
 * @param {{uid: string, researchId: ?string, level: string,
 *     dedupKey: string, isTester: boolean, eventPath: string}} p
 * @param {*} createdAt server timestamp sentinel
 * @return {object} the pi_alerts document (alertVersion 2)
 */
function buildPiAlert(p, createdAt) {
  return {
    uid: p.uid,
    researchId: p.researchId || null,
    level: p.level,
    dedupKey: p.dedupKey,
    isTester: p.isTester === true,
    eventPath: p.eventPath,
    alertVersion: 2,
    createdAt,
  };
}

/**
 * @param {Date} d
 * @return {string} "YYYY-MM-DD HH:MM" Hong Kong time
 */
function hkTime(d) {
  return new Date(d.getTime() + 8 * 3600 * 1000).toISOString()
      .slice(0, 16).replace("T", " ");
}

/**
 * The T19 e-mail (switch off).  `forcedLevel` is set only for a
 * questionnaire / assessor-entry event below acute, which alerts whatever
 * its level (T34): the first line then names the level instead of
 * claiming an acute event.
 * @param {{researchId: ?string, alertId: string, at: Date,
 *     forcedLevel: ?string}} p
 * @return {{subject: string, text: string}}
 */
function buildPiEmail(p) {
  const first = p.forcedLevel && p.forcedLevel !== "acute" ?
    `A safety event (level: ${p.forcedLevel}) from a questionnaire ` +
      "source was recorded; it alerts whatever its level." :
    "An acute distress event was detected.";
  return {
    subject: "[LonelinessCombatting] Acute distress alert",
    text: [
      first,
      `Research ID: ${p.researchId || "not registered yet"}`,
      `Time (HKT): ${hkTime(p.at)}`,
      `Alert ID: pi_alerts/${p.alertId}`,
      "",
      "Follow the study safety protocol.",
      "Screen, companion and source are left out on purpose so this " +
        "email reveals nothing about the study arm. The unblinded " +
        "researcher can look them up from the Alert ID.",
      "Do NOT reply to this automated message.",
    ].join("\n"),
  };
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/**
 * @param {?object} data meta/alert_config data (or null)
 * @return {{enabled: boolean, primaryEmail: ?string, backupEmail: ?string,
 *     escalateAfterHours: number}}
 */
function configFromData(data) {
  const d = data || {};
  const email = (v) => (typeof v === "string" && v.trim() ? v.trim() : null);
  const hours = typeof d.escalateAfterHours === "number" &&
    isFinite(d.escalateAfterHours) && d.escalateAfterHours > 0 ?
    d.escalateAfterHours : DEFAULT_ESCALATE_HOURS;
  return {
    enabled: d.enabled === true,
    primaryEmail: email(d.primaryEmail),
    backupEmail: email(d.backupEmail),
    escalateAfterHours: hours,
  };
}

/**
 * Read `meta/alert_config`.  Alerts are rare, so no cache: the lead's
 * console edit takes effect at the next event.  A read error counts as
 * OFF (the T19 behaviour), and is logged.
 * @param {object} db admin.firestore()
 * @return {Promise<{enabled: boolean, primaryEmail: ?string,
 *     backupEmail: ?string, escalateAfterHours: number}>}
 */
async function readAlertConfig(db) {
  try {
    const snap = await db.doc(CONFIG_DOC).get();
    return configFromData(snap.exists ? snap.data() : null);
  } catch (err) {
    console.error("alert_config read failed; treating as off:",
        err && err.message);
    return configFromData(null);
  }
}

// ---------------------------------------------------------------------------
// Field helpers (pure)
// ---------------------------------------------------------------------------

/**
 * @param {?string} source raw `safety_events.source`
 * @return {?string} one of the four analysis buckets, or null
 */
function sourceGroupFor(source) {
  return Object.prototype.hasOwnProperty.call(SOURCE_GROUPS, source) ?
    SOURCE_GROUPS[source] : null;
}

/**
 * Whether an event alerts whatever its level: a questionnaire /
 * assessor-entry event with `alwaysAlert: true`.  The rules refuse
 * `alwaysAlert` and these sources from clients, so only the server
 * (questionnaire_safety.js) can produce one.
 * @param {object} data event data
 * @return {boolean}
 */
function alwaysAlerts(data) {
  return !!data && data.alwaysAlert === true &&
    SERVER_ONLY_SOURCES.indexOf(data.source) >= 0;
}

/**
 * @param {?string} researchId
 * @return {?string} "B" | "PILOT" | null (unknown prefix or no ID)
 */
function periodCodeFor(researchId) {
  const p = studyPeriod.periodForResearchId(researchId);
  return p ? p.studyPeriod : null;
}

/**
 * YYYY-MM-DD in Hong Kong (same as djg_w2.hkDateKey).
 * @param {Date} d
 * @return {string}
 */
function hkDateKey(d) {
  return d.toLocaleDateString("en-CA", {timeZone: "Asia/Hong_Kong"});
}

/**
 * Study day, W0 = day 0, Hong Kong calendar days, from the W0 date the
 * researcher entered at registration (`users/{uid}.w0Date`, written by
 * T19 / T21 for Phase B and the pilot run).  No fallback to createdAt:
 * an account without w0Date is not registered, so the day is unknown.
 * T24 brings the shared study-week function; this helper is then replaced
 * by it (same answer expected).
 * @param {?object} user users/{uid} data
 * @param {Date} at when the event happened
 * @return {?number} whole days (may be negative), or null when unknown
 */
function studyDay(user, at) {
  // T24: the shared study-week function (functions/study_week.js).  Only
  // the registered W0 date counts here — no createdAt fallback, so an
  // unregistered account still reads "unknown" in the e-mail.
  return studyWeek.studyDayAt(user ? user.w0Date : null, at);
}

/**
 * Did the safety classifier (LoRA) take part in the verdict?  The App
 * writes `detector` only when the classifier path ran (T8): `classifier`
 * or `both` = its verdict counted; `lexicon` (or no field) = lexicon only.
 * `classifierStatus` without `detector` is an older row: the classifier
 * was asked, so "yes".  Anything else is unknown.
 * @param {object} data event data
 * @return {string} "yes" | "no" | "unknown"
 */
function classifierInvolved(data) {
  const d = data || {};
  if (d.detector === "classifier" || d.detector === "both") return "yes";
  if (d.detector === "lexicon") return "no";
  if (d.detector === undefined || d.detector === null) {
    return d.classifierStatus ? "yes" : "no";
  }
  return "unknown";
}

const YES_NO = {yes: YES, no: NO, unknown: UNKNOWN};

/**
 * @param {?string} agentId
 * @return {string}
 */
function companionDisplay(agentId) {
  if (!agentId) return NONE;
  return COMPANION_DISPLAY[agentId] || agentId;
}

/**
 * @param {?string} tier
 * @param {?string} level
 * @return {string} e.g. "急性 acute"
 */
function levelDisplay(tier, level) {
  const code = tier || level || null;
  if (!code) return UNKNOWN;
  const t = TIER_DISPLAY[code];
  return t ? `${t.zh} ${t.en}` : code;
}

/**
 * @param {?string} group analysis bucket
 * @return {string}
 */
function sourceDisplay(group) {
  const s = group && SOURCE_DISPLAY[group];
  return s ? `${s.zh} ${s.en}` : UNKNOWN;
}

/**
 * @param {?string} code "B" | "PILOT" | null
 * @return {string}
 */
function periodDisplay(code) {
  return (code && PERIOD_DISPLAY[code]) || UNKNOWN;
}

// ---------------------------------------------------------------------------
// The v3 alert row and the e-mail
// ---------------------------------------------------------------------------

/**
 * The `pi_alerts` document, switch ON (alertVersion 3).  Carries every
 * field the e-mail shows plus the acknowledgement / escalation state, so
 * the escalation e-mail is built from the row alone and is identical.
 * Never: arm, matchedTerm, textHash, inputPoint (chat_reflective etc.
 * exist in one arm only).
 * @param {{event: object, eventPath: string, uid: string,
 *     researchId: ?string, user: ?object, isTester: boolean,
 *     dedupKey: string, level: string, at: Date}} p
 * @param {*} createdAt server timestamp sentinel
 * @return {object}
 */
function buildAlertRow(p, createdAt) {
  const e = p.event || {};
  const group = sourceGroupFor(e.source);
  return {
    uid: p.uid,
    researchId: p.researchId || null,
    studyPeriod: periodCodeFor(p.researchId),
    studyDay: studyDay(p.user, p.at),
    agentId: e.agentId || null,
    source: e.source || null,
    sourceGroup: group,
    level: p.level,
    tier: e.tier || null,
    category: e.category || null,
    lexiconVersion: e.lexiconVersion || null,
    classifierInvolved: classifierInvolved(e),
    crisisPageShown: typeof e.crisisPageShown === "boolean" ?
      e.crisisPageShown : null,
    instrument: e.instrument || null,
    item: e.item === undefined ? null : e.item,
    alwaysAlert: alwaysAlerts(e),
    dedupKey: p.dedupKey,
    isTester: p.isTester === true,
    eventPath: p.eventPath,
    alertVersion: 3,
    createdAt,
    emailSentAt: null,
    emailSentTo: [],
    acknowledgedAt: null,
    acknowledgedBy: null,
    escalationPending: false,
    escalatedAt: null,
    escalatedTo: null,
  };
}

/**
 * The fixed field list, in order, as [label, value].  Labels are
 * "中文 English"; values carry both languages where there is a word to
 * translate.  Built from a v3 alert row (not the event), so the primary
 * and the escalation e-mail show the same thing.
 * @param {object} row pi_alerts data (v3)
 * @param {{alertId: string, at: Date}} ctx
 * @return {Array<Array<string>>}
 */
function emailFields(row, ctx) {
  const r = row || {};
  let level = levelDisplay(r.tier, r.level);
  if (r.category) level += ` / ${r.category}`;
  if (r.instrument) {
    level += ` / ${r.instrument}` + (r.item === null || r.item === undefined ?
      "" : ` 第 ${r.item} 题 item ${r.item}`);
  }
  const crisis = r.crisisPageShown === true ? YES :
    (r.crisisPageShown === false ? NO : UNKNOWN);
  return [
    ["研究编号 Research ID", r.researchId || "未登记 Not registered yet"],
    ["研究期 Study period", periodDisplay(r.studyPeriod)],
    ["陪伴者 Companion", companionDisplay(r.agentId)],
    ["来源 Source", sourceDisplay(r.sourceGroup)],
    ["级别和类别 Level and category", level],
    ["词库版本 Lexicon version", r.lexiconVersion || NONE],
    ["LoRA 是否参与判定 Classifier involved",
      YES_NO[r.classifierInvolved] || UNKNOWN],
    ["研究第几天 Study day",
      typeof r.studyDay === "number" ? String(r.studyDay) : UNKNOWN],
    ["是否显示危机页 Crisis page shown", crisis],
    ["事件编号 Event ID", r.eventPath || UNKNOWN],
    ["告警编号 Alert ID", `${ALERTS}/${ctx.alertId}`],
    ["时间（香港） Time (HKT)", hkTime(ctx.at)],
  ];
}

/**
 * The T34 e-mail, zh + en in one message.  `escalation` adds one header
 * line; the fields are the same.
 * @param {object} row pi_alerts data (v3)
 * @param {{alertId: string, at: Date, escalation: boolean,
 *     escalateAfterHours: number}} ctx
 * @return {{subject: string, text: string}}
 */
function buildAlertEmail(row, ctx) {
  const fields = emailFields(row, ctx);
  const level = levelDisplay(row.tier, row.level);
  const hours = ctx.escalateAfterHours || DEFAULT_ESCALATE_HOURS;
  const rid = row.researchId || "未登记 unregistered";
  const subject = (ctx.escalation ? "【转后备 Escalated】" : "") +
    `[陪住] 安全告警 Safety alert · ${level} · ${rid}`;
  const lines = ["陪住 安全告警 / Safety alert", ""];
  if (ctx.escalation) {
    lines.push(`【转后备】这条告警发出后 ${hours} 小时内没有人确认处理，` +
      "现在发给后备收件人。");
    lines.push(`Escalated: nobody acknowledged this alert within ${hours} ` +
      "hours, so it is now sent to the backup recipient.");
    lines.push("");
  }
  for (const [label, value] of fields) lines.push(`${label}: ${value}`);
  lines.push("");
  lines.push("请按研究安全流程处理，并在研究员后台点「確認處理」。" +
    `${hours} 小时内没有人确认，系统会把同一封邮件发给后备收件人。`);
  lines.push("Follow the study safety protocol and press 確認處理 " +
    "(acknowledge) in the researcher dashboard. If nobody acknowledges " +
    `within ${hours} hours, the same e-mail goes to the backup recipient.`);
  lines.push("本邮件不含组别、老人原话或命中的词；细节凭事件编号到后台查。");
  lines.push("This e-mail carries no study arm, no participant wording and " +
    "no matched term; look the event up by its ID.");
  lines.push("自动邮件，请勿回复。 Automated message; do not reply.");
  return {subject, text: lines.join("\n")};
}

// ---------------------------------------------------------------------------
// Recipients
// ---------------------------------------------------------------------------

/**
 * Resolve recipients against Firebase Auth.  Drops an address whose
 * account carries `role: blinded`.  An address with no account is kept
 * (the backup recipient may have none); a lookup error also keeps it
 * (a safety alert must not be lost to a transient Auth error) and is
 * reported in `notes`.
 * @param {{getUserByEmail: function(string): Promise<object>}} auth
 *     admin.auth() or a test double
 * @param {Array<?string>} emails candidates (duplicates / blanks ignored)
 * @return {Promise<{to: Array<string>,
 *     dropped: Array<{email: string, reason: string}>,
 *     notes: Array<{email: string, note: string}>}>}
 */
async function resolveRecipients(auth, emails) {
  if (authOverride) auth = authOverride;
  const to = [];
  const dropped = [];
  const notes = [];
  const seen = {};
  for (const raw of emails || []) {
    const email = typeof raw === "string" ? raw.trim().toLowerCase() : "";
    if (!email || seen[email]) continue;
    seen[email] = true;
    let role = null;
    try {
      const user = await auth.getUserByEmail(email);
      role = user && user.customClaims ? user.customClaims.role : null;
    } catch (err) {
      const code = err && (err.code || err.errorInfo && err.errorInfo.code);
      if (code === "auth/user-not-found") {
        notes.push({email, note: "no_app_account"});
      } else {
        notes.push({email, note: "lookup_failed"});
      }
    }
    if (role === BLINDED_ROLE) {
      dropped.push({email, reason: "blinded_role"});
      continue;
    }
    to.push(email);
  }
  return {to, dropped, notes};
}

// ---------------------------------------------------------------------------
// Mail transport (nodemailer; a test may replace it)
// ---------------------------------------------------------------------------

let mailerOverride = null;
let authOverride = null;

/**
 * Tests: replace Firebase Auth for the recipient role check.
 * `obj.getUserByEmail(email)` resolves to `{customClaims: {role}}` or
 * rejects with `{code: "auth/user-not-found"}`.  Pass null to restore.
 * @param {?{getUserByEmail: function(string): Promise<object>}} obj
 */
function setAuthForTests(obj) {
  authOverride = obj;
}

/**
 * Tests: replace the transport.  `fn({from, to, subject, text})` is
 * awaited in place of nodemailer.  Pass null to restore.
 * @param {?function} fn
 */
function setMailerForTests(fn) {
  mailerOverride = fn;
}

/**
 * @param {{host: string, user: string, pass: string}} smtp
 * @param {{to: (Array<string>|string), subject: string, text: string}} mail
 * @return {Promise<void>}
 */
async function sendMail(smtp, mail) {
  const msg = {
    from: smtp.user,
    to: Array.isArray(mail.to) ? mail.to.join(", ") : mail.to,
    subject: mail.subject,
    text: mail.text,
  };
  if (mailerOverride) {
    await mailerOverride(msg);
    return;
  }
  const nodemailer = require("nodemailer");
  const transporter = nodemailer.createTransport({
    host: smtp.host,
    port: 587,
    secure: false,
    auth: {user: smtp.user, pass: smtp.pass},
  });
  await transporter.sendMail(msg);
}

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------

/**
 * One `alert_audit_log` row (server-only collection).  Never throws.
 * @param {object} db
 * @param {object} row {type, alertId, ...}
 * @param {*} at server timestamp sentinel
 * @return {Promise<void>}
 */
async function audit(db, row, at) {
  try {
    await db.collection(AUDIT_LOG).add(Object.assign({at}, row));
  } catch (err) {
    console.error("alert_audit_log write failed:", err && err.message);
  }
}

// ---------------------------------------------------------------------------
// Acknowledge (callable body)
// ---------------------------------------------------------------------------

/**
 * Error with a callable code (index.js maps it to HttpsError).
 * @param {string} code
 * @param {string} message
 * @return {Error}
 */
function ackError(code, message) {
  const e = new Error(message);
  e.ackCode = code;
  return e;
}

/**
 * Mark an alert as handled.  Only `role: unblinded` may; records who and
 * when on the alert and in the audit log.  Acknowledging twice is not an
 * error: the first record stands.
 * @param {object} db
 * @param {{alertId: string}} data
 * @param {{uid: string, token: ?object}} auth request.auth
 * @param {{now: Date, serverTimestamp: function(): *}} deps
 * @return {Promise<{ok: boolean, alreadyAcknowledged: boolean,
 *     acknowledgedBy: ?string}>}
 */
async function acknowledge(db, data, auth, deps) {
  if (!auth || !auth.uid) throw ackError("unauthenticated", "sign_in");
  const role = auth.token ? auth.token.role : null;
  if (role !== UNBLINDED_ROLE) {
    throw ackError("permission-denied", "unblinded_role_required");
  }
  const alertId = data && typeof data.alertId === "string" ?
    data.alertId.trim() : "";
  if (!alertId || alertId.indexOf("/") >= 0) {
    throw ackError("invalid-argument", "alert_id_required");
  }
  const ref = db.collection(ALERTS).doc(alertId);
  const email = auth.token && auth.token.email ? auth.token.email : null;
  const stamp = deps.serverTimestamp();
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw ackError("not-found", "alert_not_found");
    const d = snap.data() || {};
    if (d.acknowledgedAt) {
      return {ok: true, alreadyAcknowledged: true,
        acknowledgedBy: d.acknowledgedBy || null};
    }
    tx.update(ref, {
      acknowledgedAt: stamp,
      acknowledgedBy: auth.uid,
      acknowledgedByEmail: email,
      escalationPending: false,
    });
    return {ok: true, alreadyAcknowledged: false, acknowledgedBy: auth.uid};
  });
  if (!result.alreadyAcknowledged) {
    await audit(db, {type: "acknowledged", alertId, by: auth.uid,
      byEmail: email}, stamp);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Escalation (scheduled body)
// ---------------------------------------------------------------------------

/**
 * @param {*} v Timestamp | Date | null
 * @return {?Date}
 */
function toDate(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v.toDate === "function") return v.toDate();
  return null;
}

/**
 * Send every due alert once more, to the backup recipient.  Due = the
 * primary e-mail went out at least `escalateAfterHours` ago, nobody
 * acknowledged, not escalated yet.  A transaction claims each alert so
 * two overlapping runs cannot both send.  Tester alerts never get here
 * (no e-mail, so `escalationPending` stays false).
 * @param {object} db
 * @param {{now: Date, smtp: ?{host: string, user: string, pass: string},
 *     auth: object, serverTimestamp: function(): *,
 *     config: ?object}} deps
 * @return {Promise<{skipped: ?string, due: number, escalated: number,
 *     noBackup: number, failed: number}>}
 */
/**
 * 10/14 fix — the patch written on a pi_alerts row when the primary e-mail
 * could not go out (no recipient after the role check, or an SMTP error):
 * the row is queued for the backup at once, so escalateDue() sends it at
 * the next sweep instead of after escalateAfterHours.
 * @param {*} stamp server timestamp sentinel
 * @param {string} reason "no_recipients" | "email_failed"
 * @return {object}
 */
function primaryFailedPatch(stamp, reason) {
  return {
    primaryFailedAt: stamp,
    primaryFailedReason: reason,
    escalationPending: true,
  };
}

/**
 * Is this pending row due for the backup?  Normally: the primary e-mail
 * went out before `cutoff`.  When the primary never went out
 * (`primaryFailedAt` set), it is due immediately.
 * @param {object} d alert row data
 * @param {number} cutoff ms since epoch
 * @return {boolean}
 */
function escalationDue(d, cutoff) {
  if (d.acknowledgedAt || d.escalatedAt || d.isTester === true) return false;
  if (d.escalationPending !== true) return false;
  if (d.primaryFailedAt) return true;
  const sentAt = toDate(d.emailSentAt);
  return !!sentAt && sentAt.getTime() <= cutoff;
}

async function escalateDue(db, deps) {
  const out = {skipped: null, due: 0, escalated: 0, noBackup: 0, failed: 0};
  const cfg = deps.config || await readAlertConfig(db);
  if (!cfg.enabled) {
    out.skipped = "disabled";
    return out;
  }
  const now = deps.now || new Date();
  const cutoff = now.getTime() - cfg.escalateAfterHours * 3600 * 1000;
  const pending = await db.collection(ALERTS)
      .where("escalationPending", "==", true).get();
  for (const doc of pending.docs) {
    const d = doc.data() || {};
    if (!escalationDue(d, cutoff)) continue;
    out.due++;
    const stamp = deps.serverTimestamp();

    // Who gets it.  Resolved before the claim so a dropped (blinded)
    // address is logged even when nothing is sent.
    let to = [];
    let dropped = [];
    if (cfg.backupEmail) {
      const r = await resolveRecipients(deps.auth, [cfg.backupEmail]);
      to = r.to;
      dropped = r.dropped;
    }
    for (const x of dropped) {
      await audit(db, {type: "recipient_dropped", alertId: doc.id,
        email: x.email, reason: x.reason, stage: "escalation"}, stamp);
    }

    // Claim once.
    const claimed = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const f = fresh.data() || {};
      if (f.acknowledgedAt || f.escalatedAt ||
          f.escalationPending !== true) {
        return false;
      }
      tx.update(doc.ref, {
        escalationPending: false,
        escalatedAt: stamp,
        escalatedTo: to,
        escalationSkipped: to.length ? null :
          (cfg.backupEmail ? "backup_dropped" : "no_backup_email"),
      });
      return true;
    });
    if (!claimed) continue;

    if (!to.length) {
      out.noBackup++;
      await audit(db, {type: "escalation_skipped", alertId: doc.id,
        reason: cfg.backupEmail ? "backup_dropped" : "no_backup_email"},
      stamp);
      continue;
    }
    if (!deps.smtp) {
      out.failed++;
      await audit(db, {type: "escalation_email_failed", alertId: doc.id,
        reason: "smtp_not_configured", to}, stamp);
      continue;
    }
    const mail = buildAlertEmail(d, {alertId: doc.id, at: now,
      escalation: true, escalateAfterHours: cfg.escalateAfterHours});
    try {
      await sendMail(deps.smtp, {to, subject: mail.subject, text: mail.text});
      out.escalated++;
      await audit(db, {type: "escalated", alertId: doc.id, to,
        afterHours: cfg.escalateAfterHours}, stamp);
    } catch (err) {
      out.failed++;
      console.error("escalation e-mail failed:", err && err.message);
      await doc.ref.update({escalationEmailError: String(err && err.message)});
      await audit(db, {type: "escalation_email_failed", alertId: doc.id,
        reason: String(err && err.message), to}, stamp);
    }
  }
  return out;
}

module.exports = {
  primaryFailedPatch, escalationDue,
  CONFIG_DOC, ALERTS, AUDIT_LOG, DEFAULT_ESCALATE_HOURS, BLINDED_ROLE,
  UNBLINDED_ROLE, SOURCE_GROUPS, SERVER_ONLY_SOURCES, SOURCE_DISPLAY,
  // T19 (switch off)
  buildPiAlert, buildPiEmail, hkTime,
  // T34
  configFromData, readAlertConfig, sourceGroupFor, alwaysAlerts,
  periodCodeFor, hkDateKey, studyDay, classifierInvolved, buildAlertRow,
  emailFields, buildAlertEmail, resolveRecipients, setMailerForTests,
  setAuthForTests,
  sendMail, audit, acknowledge, escalateDue,
};
