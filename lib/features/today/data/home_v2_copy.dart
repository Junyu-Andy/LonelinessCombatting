/// 1020 D / G (2) — the fixed words of page 1 「睇今日」 in the two-page
/// layout (`app_config/feature_flags.homeLayoutV2Enabled`): the
/// 「今日要做嘅事」 rows, the 「去搵人傾」 button and the questionnaire row
/// (W4 / W5, 1020b §4 5.5).
///
/// Drafts (1020b common rule 4), verbatim from `docs/spec/copy/home-v2.md`
/// (test/final_copy_test.dart).  D1–D4 are the development window's
/// wording for lines 1020 D names but 1020b §4 has no text for; W4 / W5
/// are 1020b §4 5.5.  Both arms identical.
library;

class HomeV2Copy {
  HomeV2Copy._();

  static const String version = '1020-D-1020b-5.5-20261020-draft';

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

  /// W5 — open: `問卷開咗，仲有 {N} 日。`
  static const String w5Template = '問卷開咗，仲有 {N} 日。';

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// `10月26日（星期日）`.
  static String dateLabel(DateTime d) =>
      '${d.month}月${d.day}日（星期${_weekdays[d.weekday - 1]}）';

  static String w4(DateTime opensOn) =>
      w4Template.replaceFirst('{10月26日（星期日）}', dateLabel(opensOn));

  static String w5(int daysLeft) =>
      w5Template.replaceFirst('{N}', '$daysLeft');
}
