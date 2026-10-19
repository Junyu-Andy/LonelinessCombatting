/**
 * dev-tasks-1020 F(5), G(1)(3) as changed by 1020e 二.1–二.2 — the push
 * texts and the e-mail subject of batch 4, in one place.  P1 / P2 and E1
 * are 1020b §4 (5.3, 5.5); the weekly texts are 1020e 二.1(4) and
 * 二.2(2).  Both arms get the same words; nothing here is ever produced by
 * an LLM.
 *
 * DRAFT: the research lead signs the wording off on the PR screenshots
 * (common rule 4).  docs/spec/copy/push-and-email-1020.md holds the same
 * table and functions/test/push_copy_test.js checks the two word for word,
 * so a change means editing both.
 *
 * Weeks 1–3 share one set of texts; `{N}` is the week in Chinese numerals
 * (第一週、第二週、第三週), filled by weeklyText().
 *
 * Switches (read by the callers, not here):
 *   P1, P2           app_config/feature_flags.checkInChatV2Enabled
 *                    (functions/daily_checkin_push.js)
 *   W-…, W4-…, E1    app_config/feature_flags.weeklyReminderV2Enabled
 *                    (functions/weekly_schedule.js, weekly_email.js)
 */

"use strict";

const COPY_VERSION = "1020e-20261020-draft";
const PUSH_TITLE = "陪住";

/** Elder-facing push bodies, by id. */
const TEXT = {
  // 1020b §4 5.3
  "P1": "小欣想問下你尋日過得點。",
  "P2": "今日仲未同小欣傾，得閒入嚟講兩句。",
  // 1020e 二.1(4): weeks 1–3, 10:00 on days 6 / 7 / 8 / 9 (14…, 21…)
  "W-pre": "聽日第{N}週問卷就開，記得聽日得閒入嚟答呀。",
  "W-open": "第{N}週問卷開咗，快啲入嚟答啦。",
  "W-rem1": "第{N}週問卷聽日截止，開咗一日喇，得閒入嚟答埋佢。",
  "W-rem2": "今日係第{N}週問卷最後一日，記得今日一定要答埋佢。",
  // 1020e 二.2(2): week 4, 10:00 on days 25 / 26 / 28
  "W4-pre": "聽日第四週問卷就開，記得聽日得閒入嚟答呀。",
  "W4-open": "第四週嘅問卷開咗，記得喺見面之前答埋佢。",
  "W4-rem": "第四週嘅問卷仲未答完，得閒入嚟答埋佢；見面嗰日都可以補。",
};

const WEEK_NUMERALS = ["", "一", "二", "三", "四", "五", "六", "七", "八"];

/**
 * A weekly text for one bundle week (fills {N}).
 * @param {string} id TEXT key
 * @param {number} week bundle week (1…)
 * @return {string}
 */
function weeklyText(id, week) {
  const n = WEEK_NUMERALS[week] || String(week);
  return String(TEXT[id] || "").split("{N}").join(n);
}

/** E1: the subject of the research lead's e-mail (never sent to elders). */
const E1_SUBJECT = "陪住：今日截止嘅每週問卷未完成名單";

/**
 * sendTestPush kinds that send one of the texts above to the tester's own
 * devices (index.js); weekly texts are shown for week 1.  The App's tester
 * page (tester_schedule_page.dart) has a button for each.
 */
const TEST_PUSH_KINDS = {
  checkin_p1: {id: "P1"},
  checkin_p2: {id: "P2"},
  weekly_pre: {id: "W-pre", week: 1},
  weekly_open: {id: "W-open", week: 1},
  weekly_rem1: {id: "W-rem1", week: 1},
  weekly_rem2: {id: "W-rem2", week: 1},
  weekly4_pre: {id: "W4-pre", week: 4},
  weekly4_open: {id: "W4-open", week: 4},
  weekly4_rem: {id: "W4-rem", week: 4},
};

/**
 * @param {{id: string, week: (number|undefined)}} k a TEST_PUSH_KINDS value
 * @return {string} the text it sends
 */
function testKindText(k) {
  return k.week ? weeklyText(k.id, k.week) : TEXT[k.id];
}

module.exports = {
  COPY_VERSION, PUSH_TITLE, TEXT, E1_SUBJECT, TEST_PUSH_KINDS, weeklyText,
  testKindText,
};
