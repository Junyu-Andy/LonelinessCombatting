/**
 * T19 (decision 0029) — what an acute safety alert tells the PI.
 *
 * The PI (Junyu) is the blinded assessor.  The alert row (`pi_alerts`) and
 * the email to PI_EMAIL therefore carry nothing that differs by arm:
 * no `source` (gateway_* / ai_output_scan are Hybrid-only, rule_turn is
 * rule-arm-only), no `inputPoint` (chat_reflective, system_generated,
 * article_qa … exist in one arm only) and no `agentId`.  Every acute
 * event in either arm still produces one alert and one email, with the
 * same fields.  The details stay in `safety_events` for the unblinded
 * researcher, found by the event path / alert ID.
 */

"use strict";

/**
 * @param {{uid: string, researchId: ?string, level: string,
 *     dedupKey: string, isTester: boolean, eventPath: string}} p
 * @param {*} createdAt server timestamp sentinel
 * @return {object} the pi_alerts document
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
 * @param {{researchId: ?string, alertId: string, at: Date}} p
 * @return {{subject: string, text: string}}
 */
function buildPiEmail(p) {
  return {
    subject: "[LonelinessCombatting] Acute distress alert",
    text: [
      "An acute distress event was detected.",
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

module.exports = {buildPiAlert, buildPiEmail, hkTime};
