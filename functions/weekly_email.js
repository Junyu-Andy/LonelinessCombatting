/**
 * dev-tasks-1020 G(3) — the research lead's e-mail E1: which research IDs
 * still have an incomplete weekly questionnaire on its last reminder day.
 *
 * Switch: app_config/feature_flags.weeklyReminderV2Enabled (the same as
 * the reminders v2, weekly_schedule.js), and the study-week schedule
 * (app_config/phase_b.weeklyScheduleV2Enabled) must be on.  Off: nothing.
 *
 * When: 10:00 Hong Kong time every day (index.js weeklyIncompleteEmail).
 * 1020e: a participant is listed on the last day of W1–W3 (day 9, 16, 23)
 * or on day 28 for W4 — weekly_schedule.emailDayKeyFor — when the v2
 * window is still open (W4 may already be closed by the recorded visit),
 * not marked missed, and at least one part is not submitted.  W5–W7 (PGIC
 * only) are never listed: since 10/20 item 98 they run on the v2 windows
 * too, but emailDayKeyFor gives them no e-mail day.  W8 (T35) is not
 * built.
 *
 * Who: PILOT-, PB- (run-in) and RCT- participants alike — the research ID
 * prefix tells them apart.  Testers are never listed (switched testers
 * included: they have no research ID), as tester safety alerts are never
 * e-mailed (pi_alert.js).
 *
 * What: subject E1 (push_copy.js); one line per person: research ID,
 * today's study day, the questionnaire's week.  Never the arm, the cohort
 * label, any answer or which parts are open.  Nobody incomplete → no
 * e-mail.
 *
 * To: meta/alert_config.primaryEmail, through the safety-alert code
 * (pi_alert.resolveRecipients drops a `blinded` address; pi_alert.sendMail
 * with the SMTP secrets).  No primaryEmail: the PI_EMAIL secret, logged,
 * as the alert does.  Once per day: alert_audit_log/weekly_incomplete_
 * <date> is claimed first and records status, count and recipients (no
 * research IDs).
 *
 * Test e-mail: writing `send: true` on meta/weekly_email_test (console)
 * sends one e-mail with three synthetic IDs and a 【测试】 subject to the
 * same recipients, whatever the switch (it reaches no participant and
 * reads no participant data).  The trigger then writes `send: false`,
 * `lastSentAt` and `lastResult`.
 */

"use strict";

const piAlert = require("./pi_alert");
const studyWeek = require("./study_week");
const weeklySchedule = require("./weekly_schedule");
const pushCopy = require("./push_copy");

const TEST_DOC = "meta/weekly_email_test";
const AUDIT_PREFIX = "weekly_incomplete_";
const WEEKDAY_ZH = ["日", "一", "二", "三", "四", "五", "六"];

/** Synthetic rows of the test e-mail (never a real research ID format
 * collision: every ID carries TEST). */
const TEST_ROWS = [
  {researchId: "PILOT-TEST01", studyDay: 9, questionnaireWeek: 1},
  {researchId: "PB-TEST02", studyDay: 16, questionnaireWeek: 2},
  {researchId: "RCT-TEST03", studyDay: 28, questionnaireWeek: 4},
];

/**
 * Participants whose weekly questionnaire has its last reminder day today
 * and is not complete.  Read only.
 * @param {object} db admin.firestore()
 * @param {Date} now
 * @param {?object} config weekly_schedule.readConfig() result (read here
 *     when absent); the v2 windows are used whatever its reminderV2 says
 * @return {Promise<Array<{researchId: ?string, studyDay: number,
 *     questionnaireWeek: number, bundle: string}>>} sorted by research ID
 */
async function incompleteClosingToday(db, now, config) {
  const read = config || await weeklySchedule.readConfig(db);
  const cfg = Object.assign({}, read, {reminderV2: true});
  if (!cfg.enabled) return [];
  const todayKey = studyWeek.hkDateKey(now);
  const rows = [];
  const users = await db.collection("users").get();
  for (const userDoc of users.docs) {
    const u = userDoc.data() || {};
    if (u.isTester === true) continue;
    const mode = weeklySchedule.scheduleModeFor(u);
    const w0Key = studyWeek.w0DateKey(u);
    if (!mode || !w0Key) continue;
    const statusSnap = await db.collection(weeklySchedule.STATUS_COLLECTION)
        .doc(userDoc.id).get();
    const st = statusSnap.exists ? (statusSnap.data() || {}) : {};
    const bundles = st.bundles || {};
    for (const b of weeklySchedule.bundlesFor(cfg, mode)) {
      if (!weeklySchedule.isReminderV2Bundle(b)) continue;
      const win = weeklySchedule.windowFor(b, w0Key, cfg,
          weeklySchedule.windowOptsFor(u, cfg));
      if (now < win.open || now >= win.close) continue;
      if ((bundles[b.id] || {}).missedAt) continue;
      if (weeklySchedule.emailDayKeyFor(b, win) !== todayKey) continue;
      const states = await weeklySchedule.partStates(userDoc.ref, b);
      if (b.parts.every((p) => states[p].submitted)) continue;
      const rid = st.researchId ||
        await weeklySchedule.lookupResearchId(db, userDoc.id);
      rows.push({
        researchId: rid || null,
        studyDay: studyWeek.studyDayOf(w0Key, todayKey),
        questionnaireWeek: b.bundleWeek,
        bundle: b.id,
      });
    }
  }
  rows.sort((a, b) => String(a.researchId || "~")
      .localeCompare(String(b.researchId || "~")));
  return rows;
}

/**
 * E1.  Only research ID, study day and questionnaire week per line.
 * @param {Array<{researchId: ?string, studyDay: number,
 *     questionnaireWeek: number}>} rows
 * @param {Date} now
 * @param {{test: (boolean|undefined)}} opts test = synthetic test e-mail
 * @return {{subject: string, text: string}}
 */
function buildEmail(rows, now, opts) {
  const test = !!(opts && opts.test);
  const dateKey = studyWeek.hkDateKey(now);
  const weekday = WEEKDAY_ZH[new Date(now.getTime() + 8 * 3600 * 1000)
      .getUTCDay()];
  const lines = [];
  if (test) {
    lines.push("【测试】这是一封测试邮件，下面三个编号是虚构的，" +
      "不是参与者。正式邮件的格式和这封一样。", "");
  }
  lines.push(`${dateKey}（星期${weekday}）10:00，` +
    "以下研究编号的每周问卷还没有完成" +
    "（第 1–3 周：今天 23:59 截止；第 4 周：开放第三天，" +
    "W4 面访记录后或第 42 天截止）：", "");
  lines.push("研究编号 ｜ 研究第几天 ｜ 第几周问卷");
  for (const r of rows) {
    lines.push(`${r.researchId || "（研究编号缺失）"} ｜ ` +
      `第 ${r.studyDay} 天 ｜ 第 ${r.questionnaireWeek} 周`);
  }
  lines.push("", `共 ${rows.length} 人。`, "",
      "本邮件不含组别、cohort 和任何答案。PILOT-、PB-（run-in）、" +
      "RCT- 由编号前缀区分。",
      "自动邮件，请勿回复。");
  return {
    subject: (test ? "【测试】" : "") + pushCopy.E1_SUBJECT,
    text: lines.join("\n"),
  };
}

/**
 * Resolve the recipients the safety alert would use.
 * @param {object} db
 * @param {object} auth admin.auth() or a test double
 * @param {{piEmail: string}} smtp
 * @param {*} stamp
 * @param {string} auditId
 * @return {Promise<Array<string>>}
 */
async function recipients(db, auth, smtp, stamp, auditId) {
  const cfg = await piAlert.readAlertConfig(db);
  const candidates = [cfg.primaryEmail];
  if (!cfg.primaryEmail) {
    candidates.push(smtp.piEmail);
    await piAlert.audit(db, {type: "primary_missing_fallback_secret",
      alertId: auditId}, stamp);
  }
  const r = await piAlert.resolveRecipients(auth, candidates);
  for (const x of r.dropped) {
    await piAlert.audit(db, {type: "recipient_dropped", alertId: auditId,
      email: x.email, reason: x.reason, stage: "weekly_incomplete"}, stamp);
  }
  return r.to;
}

/**
 * The 10:00 job.  Claims today's audit row, collects the list, sends E1
 * when it is not empty.
 * @param {object} db admin.firestore()
 * @param {{now: (Date|undefined), smtp: ?{host: string, user: string,
 *     pass: string, piEmail: string}, auth: object,
 *     serverTimestamp: (function(): *|undefined),
 *     flagOn: (boolean|undefined)}} deps flagOn overrides the switch
 *     (tests only)
 * @return {Promise<{status: string, count: number}>} status: disabled |
 *     already_done | none | sent | no_smtp | no_recipients | failed
 */
async function sendDailyIncompleteEmail(db, deps) {
  const d = deps || {};
  const now = d.now || new Date();
  const stamp = d.serverTimestamp ? d.serverTimestamp() : now;
  const cfg = await weeklySchedule.readConfig(db);
  const on = d.flagOn !== undefined ? d.flagOn === true : cfg.reminderV2;
  if (!on) return {status: "disabled", count: 0};
  const dateKey = studyWeek.hkDateKey(now);
  const auditId = AUDIT_PREFIX + dateKey;
  const ref = db.collection(piAlert.AUDIT_LOG).doc(auditId);
  // Once a day: a finished run stays finished; a failed one may run again.
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const s = snap.exists ? (snap.data() || {}).status : null;
    if (s && s !== "failed" && s !== "no_smtp" && s !== "no_recipients") {
      return false;
    }
    tx.set(ref, {type: "weekly_incomplete_email", dateKey,
      status: "running", at: stamp}, {merge: true});
    return true;
  });
  if (!claimed) return {status: "already_done", count: 0};

  const finish = async (status, extra) => {
    await ref.set(Object.assign({status, finishedAt: stamp}, extra || {}),
        {merge: true});
    return Object.assign({status}, extra || {});
  };
  const rows = await incompleteClosingToday(db, now, cfg);
  if (rows.length === 0) return finish("none", {count: 0});
  if (!d.smtp) return finish("no_smtp", {count: rows.length});
  const to = await recipients(db, d.auth, d.smtp, stamp, auditId);
  if (to.length === 0) return finish("no_recipients", {count: rows.length});
  const mail = buildEmail(rows, now);
  try {
    await piAlert.sendMail(d.smtp, {to, subject: mail.subject,
      text: mail.text});
  } catch (err) {
    console.error("weekly incomplete e-mail failed:", err && err.message);
    return finish("failed", {count: rows.length, to,
      error: String(err && err.message)});
  }
  return finish("sent", {count: rows.length, to});
}

/**
 * The console test: meta/weekly_email_test `send` turned true.  Sends the
 * synthetic E1 to the real recipients, then resets the request.
 * @param {object} db
 * @param {?object} before document data before the write
 * @param {?object} after document data after the write
 * @param {{now: (Date|undefined), smtp: ?object, auth: object}} deps
 * @return {Promise<?string>} result, or null when nothing was requested
 */
async function handleTestRequest(db, before, after, deps) {
  if (!after || after.send !== true) return null;
  if (before && before.send === true) return null;
  const d = deps || {};
  const now = d.now || new Date();
  let result;
  if (!d.smtp) {
    result = "no_smtp";
  } else {
    const to = await recipients(db, d.auth, d.smtp, now, "weekly_email_test");
    if (to.length === 0) {
      result = "no_recipients";
    } else {
      const mail = buildEmail(TEST_ROWS, now, {test: true});
      try {
        await piAlert.sendMail(d.smtp, {to, subject: mail.subject,
          text: mail.text});
        result = "sent";
      } catch (err) {
        result = `failed: ${String(err && err.message).slice(0, 200)}`;
      }
    }
  }
  await db.doc(TEST_DOC).set({send: false, lastSentAt: now,
    lastResult: result}, {merge: true});
  await piAlert.audit(db, {type: "weekly_email_test", result}, now);
  return result;
}

module.exports = {
  TEST_DOC, AUDIT_PREFIX, TEST_ROWS, incompleteClosingToday, buildEmail,
  sendDailyIncompleteEmail, handleTestRequest,
};
