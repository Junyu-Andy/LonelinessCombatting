/// What a participant would receive on a given enrolment day (2026-09-23).
///
/// Pure function of (enrolment date, target date, [PhaseAConfig]) so the
/// tester schedule page, unit tests and the Manual all read the same rules.
/// It mirrors — and must be kept in step with — three places:
///
///   • Cloud Function crons in `functions/index.js`:
///       dailyMoodReminder   Mon–Sat 19:00 HKT, topic broadcast
///       weeklySurveyReminder Sun 20:00 HKT, topic broadcast
///       week2Push           daily 10:00 HKT scan, per-device, once
///   • [PendingPromptsService] (home banners) and [WeeklyPrWindow].
///   • [DailyMoodPrompt] and [Week1NudgeBanner].
///
/// Items marked [ScheduleItem.conditional] depend on what the participant
/// has already done (answered, used an agent); the simulator lists them
/// with the condition rather than guessing.
library;

import '../config/phase_a_config.dart';
import 'enrolment_day.dart';

enum ScheduleChannel { push, inApp, record }

class ScheduleItem {
  final ScheduleChannel channel;

  /// Local time the item becomes relevant (HH:MM), or null for "on first
  /// app open".
  final String? at;
  final String titleZh;
  final String detailZh;
  final bool conditional;

  const ScheduleItem({
    required this.channel,
    this.at,
    required this.titleZh,
    required this.detailZh,
    this.conditional = false,
  });
}

class ScheduleSimulator {
  ScheduleSimulator._();

  static const _weekdayZh = ['一', '二', '三', '四', '五', '六', '日'];

  static String weekdayZh(DateTime d) => '星期${_weekdayZh[d.weekday - 1]}';

  static List<ScheduleItem> forDate({
    required DateTime enrolledAt,
    required DateTime date,
    PhaseAConfig? config,
  }) {
    final c = config ?? PhaseAConfig.current;
    final day = enrolmentDay(enrolledAt, date);
    if (day < 1) return const [];
    final items = <ScheduleItem>[];
    final wd = date.weekday;

    // ---- pushes (Cloud Function crons) ----
    if (c.w2DayOffset == day) {
      items.add(const ScheduleItem(
        channel: ScheduleChannel.push,
        at: '10:00',
        titleZh: '第 2 週問卷推送',
        detailZh: '逐部機推送（fcm_tokens）；只推一次。iOS 未配置 APNs，收唔到。',
        conditional: true,
      ));
    }
    if (wd != DateTime.sunday) {
      items.add(const ScheduleItem(
        channel: ScheduleChannel.push,
        at: '19:00',
        titleZh: '每日心情提醒',
        detailZh: '「今日過得點？」全體廣播（topic all）。今日休息時照樣會推（廣播冇分人）。',
      ));
    } else {
      items.add(ScheduleItem(
        channel: ScheduleChannel.push,
        at: '${c.weeklyPrPushHour.toString().padLeft(2, '0')}:00',
        titleZh: '每週問卷提醒',
        detailZh: '「今個禮拜過得點？」全體廣播；同時寫 weekly_pr_pushed 事件。'
            '（推送時間寫死喺 CF cron，改 config 唔會改推送時間）',
      ));
    }

    // ---- in-app ----
    items.add(const ScheduleItem(
      channel: ScheduleChannel.inApp,
      titleZh: '每日心情一問',
      detailZh: '當日第一次開首頁彈出；當日已記過心情就唔彈。',
      conditional: true,
    ));

    if (c.week1NudgeDays.contains(day)) {
      items.add(const ScheduleItem(
        channel: ScheduleChannel.inApp,
        titleZh: '首週提示「你仲未同 X 傾過」',
        detailZh: '三個 companion 之中有未用過嘅先出；可關閉。',
        conditional: true,
      ));
    }

    // Weekly PR window: Sun pushHour → close weekday 23:59.
    if (wd == DateTime.sunday) {
      items.add(ScheduleItem(
        channel: ScheduleChannel.inApp,
        at: '${c.weeklyPrPushHour.toString().padLeft(2, '0')}:00',
        titleZh: '週評卡片（PGIC → 12 題 PR）',
        detailZh: '由今晚開始首頁出卡片，評緊今個禮拜（星期一至今晚）。'
            '冇同 companion 傾過嘅話只問 PGIC。',
        conditional: true,
      ));
    } else if (wd >= DateTime.monday && wd <= c.weeklyPrCloseWeekday) {
      items.add(const ScheduleItem(
        channel: ScheduleChannel.inApp,
        titleZh: '週評卡片（仲開緊）',
        detailZh: '評緊上個禮拜；未答先出，星期二 23:59 關。',
        conditional: true,
      ));
    } else if (wd == c.weeklyPrCloseWeekday + 1) {
      items.add(const ScheduleItem(
        channel: ScheduleChannel.record,
        titleZh: '記錄「上週未答」',
        detailZh: '上個禮拜嘅週評冇交，開首頁時寫 weekly_pr/missed_<週> + weekly_pr_missed。',
        conditional: true,
      ));
    }

    if (day >= c.w2DayOffset && day < c.w2DayOffset + c.w2WindowDays) {
      items.add(ScheduleItem(
        channel: ScheduleChannel.inApp,
        titleZh: '第 2 週問卷卡片（DJG-ES → 夥伴評估）',
        detailZh: '入組第 ${c.w2DayOffset}–${c.w2DayOffset + c.w2WindowDays - 1} 天出；'
            '做完就唔再出。',
        conditional: true,
      ));
    }
    if (day >= 28) {
      items.add(const ScheduleItem(
        channel: ScheduleChannel.inApp,
        titleZh: '第 4 週夥伴評估卡片',
        detailZh: '入組第 28 天起，做完為止。',
        conditional: true,
      ));
    }
    return items;
  }
}
