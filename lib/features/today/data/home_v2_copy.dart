/// 1020 D / G (2) — the fixed words of page 1 「睇今日」 in the two-page
/// layout (`app_config/feature_flags.homeLayoutV2Enabled`): the
/// 「今日要做嘅事」 rows, the 「去搵人傾」 button and the questionnaire row
/// (W4, 1020b §4 5.5; W5 by day, 1020e 二.1 (5), 二.2 (4); 1020l §二 (1):
/// two lines — title and a small second line, W5-2 the deadline day) and
/// the small-action row (SA1–SA5, 1020m 第二节; SA6–SA8, 1020n 第三节).
///
/// Drafts (1020b common rule 4), verbatim from `docs/spec/copy/home-v2.md`
/// (test/final_copy_test.dart).  D1–D4 are the development window's
/// wording for lines 1020 D names but 1020b §4 has no text for; W4 / W5
/// are 1020b §4 5.5.  Both arms identical.
library;

class HomeV2Copy {
  HomeV2Copy._();

  static const String version = '1020-D-1020b-5.5-1020e-1020l-20261020-draft';

  /// D1 — the heading over the to-do rows (1020 D (3)).
  static const String todoTitle = '今日要做嘅事';

  /// D2 — the check-in row (1020 D (3)(a)); a tick when today's is done.
  static const String checkInRow = '同小欣 check-in';

  /// D3 — under D2 after 3 days without a check-in (the old banner
  /// 「幾日冇見你」 folded into the row; its two lines joined).
  static const String checkInMissed = '幾日冇見你。快速 check-in 一分鐘就完，冇壓力。';

  /// D4 — the big button that switches to page 2 (1020 D (4)).
  static const String goTalk = '去搵人傾';

  /// W4 — not open: `下次問卷：{10月26日（星期日）}開，開咗之後三日內答都得。`
  static const String w4Template = '下次問卷：{10月26日（星期日）}開，開咗之後三日內答都得。';

  /// W5 — open: `問卷開咗，{狀態}。` (1020e: no 「仲有 N 日」 any more).
  static const String w5Template = '問卷開咗，{狀態}。';

  /// W5a — open, weeks 1–3 / 5–7, before the day before the last day
  /// (the window's first day).
  static const String w5Asap = '請盡快回答';

  /// W5b — open, the day before the window's last day.
  static const String w5Tomorrow = '聽日截止';

  /// W5c — open, the window's last day.
  static const String w5Tonight = '今晚截止';

  /// W5d — open, week 4 (closes after the W4 visit): no deadline.
  static const String w5BeforeVisit = '記得喺見面之前答埋佢';

  /// W5-2 — 1020l §二 (1): the small second line of an open questionnaire
  /// row (weeks 1–3, 5–7): the window's last day.  Week 4 (W5d, closes
  /// after the visit) has no second line.  Draft.
  static const String w5DeadlineTemplate = '{10月26日（星期日）}截止';

  /// SA1 — 1020m 第二节 (1): page 1's small-action row when there is no
  /// plan for today (撳: 今日小行動).
  static const String smallActionAsk = '今日想做啲咩小行動？';

  /// SA2 — the small text button on SA1's right (hidden 3 days).
  static const String smallActionLater = '遲啲先';

  /// SA3 — 1020m 第二节 (2): a plan for today, `今日計劃：{計劃內容}` (1020n
  /// 第五节: at most two lines; a longer plan ends in 「…」).
  static const String smallActionPlanTemplate = '今日計劃：{計劃內容}';

  /// SA4 / SA5 — the two buttons under SA3.
  static const String smallActionDone = '做咗';
  static const String smallActionPostpone = '改日';

  /// SA3 with the plan's 做咩 filled in.
  static String smallActionPlan(String action) =>
      smallActionPlanTemplate.replaceFirst('{計劃內容}', action);

  /// SA6 — 1020n 第三节 (1)(a): a plan made today for tomorrow, no buttons
  /// (at most two lines, then 「…」).
  static const String smallActionNextDayTemplate = '聽日計劃：{計劃內容}';

  /// SA7 — 1020n 第三节 (1)(b): under the SA6 lines (撳: 今日小行動).
  static const String smallActionMore = '仲有冇其他計劃？';

  /// SA8 — 1020n 第三节 (4): more than two plans (撳: 我嘅計劃).
  static const String smallActionOverflowTemplate = '仲有 {N} 個計劃';

  /// SA6 with the plan's 做咩 filled in.
  static String smallActionNextDay(String action) =>
      smallActionNextDayTemplate.replaceFirst('{計劃內容}', action);

  /// SA8 with the number of plans not shown.
  static String smallActionOverflow(int n) =>
      smallActionOverflowTemplate.replaceFirst('{N}', '$n');

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// `10月26日（星期日）`.
  static String dateLabel(DateTime d) =>
      '${d.month}月${d.day}日（星期${_weekdays[d.weekday - 1]}）';

  static String w4(DateTime opensOn) =>
      w4Template.replaceFirst('{10月26日（星期日）}', dateLabel(opensOn));

  static String w5(String state) => w5Template.replaceFirst('{狀態}', state);

  /// 1020l §二 (1): the row shows W4 on two lines, split at its colon —
  /// the same words: `下次問卷` on the title line (one short line, so the
  /// date is never broken across lines in big type) …
  static String get w4Title =>
      w4Template.substring(0, w4Template.indexOf('：'));

  /// … and `{10月26日（星期日）}開，開咗之後三日內答都得。` as the small
  /// second line.
  static String w4Subtitle(DateTime opensOn) {
    final full = w4(opensOn);
    return full.substring(full.indexOf('：') + 1);
  }

  /// W5-2 with the date filled in: `10月24日（星期六）截止`.
  static String w5Deadline(DateTime lastDay) =>
      w5DeadlineTemplate.replaceFirst('{10月26日（星期日）}', dateLabel(lastDay));
}
