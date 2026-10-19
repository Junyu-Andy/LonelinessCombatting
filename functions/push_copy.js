/**
 * dev-tasks-1020 F(5), G(1)(3) — the push texts and the e-mail subject of
 * batch 4, in one place (1020b §4: 5.3 P1 / P2, 5.5 W1–W3, W1-4–W3-4,
 * E1).  Both arms get the same words; nothing here is ever produced by an
 * LLM.
 *
 * DRAFT: the research lead signs the wording off on the PR screenshots
 * (common rule 4).  docs/spec/copy/push-and-email-1020.md holds the same
 * table and functions/test/push_copy_test.js checks the two word for word,
 * so a change means editing both.
 *
 * Switches (read by the callers, not here):
 *   P1, P2           app_config/feature_flags.checkInChatV2Enabled
 *                    (functions/daily_checkin_push.js)
 *   W1…W3-4, E1      app_config/feature_flags.weeklyReminderV2Enabled
 *                    (functions/weekly_schedule.js, weekly_email.js)
 */

"use strict";

const COPY_VERSION = "1020b-s4-20261019-draft";
const PUSH_TITLE = "陪住";

/** Elder-facing push bodies, by the 1020b §4 id. */
const TEXT = {
  "P1": "小欣想問下你尋日過得點。",
  "P2": "今日仲未同小欣傾，得閒入嚟講兩句。",
  "W1": "上個禮拜嘅問卷開咗，得閒入嚟分享下你嘅感受。",
  "W2": "上個禮拜嘅問卷聽日截止，記得入嚟答埋佢。",
  "W3": "今日係上個禮拜問卷嘅最後一日，盡快答埋佢啦。",
  "W1-4": "今個禮拜嘅問卷開咗，得閒入嚟分享下你嘅感受。",
  "W2-4": "今個禮拜嘅問卷聽日截止，記得入嚟答埋佢。",
  "W3-4": "今日係今個禮拜問卷嘅最後一日，盡快答埋佢啦。",
};

/** E1: the subject of the research lead's e-mail (never sent to elders). */
const E1_SUBJECT = "陪住：今日截止嘅每週問卷未完成名單";

/**
 * sendTestPush kinds that send one of the texts above to the tester's own
 * devices (index.js).  The App's tester page has fixed buttons; these
 * kinds are for a later App build or a manual call.
 */
const TEST_PUSH_KINDS = {
  checkin_p1: "P1",
  checkin_p2: "P2",
  weekly_w1: "W1",
  weekly_w2: "W2",
  weekly_w3: "W3",
  weekly_w1_4: "W1-4",
  weekly_w2_4: "W2-4",
  weekly_w3_4: "W3-4",
};

module.exports = {COPY_VERSION, PUSH_TITLE, TEXT, E1_SUBJECT, TEST_PUSH_KINDS};
