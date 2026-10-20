/// T24 — the weekly questionnaire schedule (SPEC:C15, C17), pure functions.
///
/// Mirrors functions/weekly_schedule.js exactly; test/fixtures/
/// weekly_schedule_table.json feeds both tests.  Phase B and the pilot;
/// both arms; nothing here reads Firestore or looks at the arm.
///
/// Standard (cohort `phase_b`), study days with W0 = 0:
///   W1–W3  push on [PhaseBConfig.weeklyBundleDays] 0..2 (7, 14, 21) at
///          [PhaseBConfig.weeklyPushHour]; answer window
///          [PhaseBConfig.weeklyWindowDays] × 24 h from the push instant;
///          parts DJG-ES ([PhaseBConfig.djgWeeks]) → Weekly PR → PGIC →
///          social-contact probe ([PhaseBConfig.socialContactProbeEnabled]).
///   W4     opens on day [PhaseBConfig.weeklyBundleDays] 3 (26); closes at
///          the end of day [PhaseBConfig.week4CloseDay] (29) or of the W4
///          visit day, whichever is later ([week4CloseFor]); no DJG.
///   W5–W7  PGIC only, [PhaseBConfig.pgicOnlyDays] (35, 42, 49)
///          ([WeeklyBundle.pgicOnly]).
/// Pilot (cohort `pilot`): the SAME standard schedule (10/15: the pilot run
///   follows Phase B day for day).  [WeeklyScheduleMode.pilot] (days 1, 3,
///   5, 7, 1-day windows) is kept only for the shared table test; no cohort
///   maps to it any more.
///
/// Every window is `[open, close)`: open = push instant, close exclusive.
///
/// 1020e 二.1–二.2 (batch 4) and 10/20 item 98 (decision 0067) — with
/// `app_config/feature_flags.weeklyReminderV2Enabled` on
/// ([RemoteFeatureFlags]; only a literal true turns it on) every bundle
/// W1–W7 uses whole Hong Kong days instead, the same as the server
/// (functions/weekly_schedule.js windowFor, same fixture), and
/// [PhaseBConfig.weeklyPushHour] is not read:
///   W1–W3  open at 00:00 of the push day (7, 14, 21), close at the end of
///          the push day + [PhaseBConfig.weeklyWindowDays] − 1 (day 9, 16,
///          23 at 23:59:59).
///   W4     opens at 00:00 of day 26; closes at the end of the day the W4
///          visit was recorded (`users/{uid}.w4RecordedOn`, server-written
///          by the assessor's entry, `UserProfile.w4RecordedOn`) — never
///          before the end of day 26 — and at the latest at the end of day
///          [week4LatestCloseDayV2] (42).
///   W5–W7  (item 98) like W1–W3: open at 00:00 of the push day (35, 42,
///          49), close at the end of day 37 (44, 51).  The home row then
///          words them by the W1–W3 rule (請盡快回答 → 聽日截止 → 今晚截止,
///          `QuestionnaireRowInfo.openState`).
/// Callers that do not pass `v2` get [RemoteFeatureFlags.current]; with the
/// flag off everything is exactly as before.
library;

import '../config/phase_b_config.dart';
import '../feature_flags/remote_feature_flags.dart';
import '../study/cohorts.dart';
import 'study_week.dart';

enum WeeklyScheduleMode { standard, pilot }

/// The four parts of a weekly bundle, in the fixed order.
enum WeeklyPart { djg, weeklyPr, pgic, socialContact }

extension WeeklyPartCodes on WeeklyPart {
  /// Code used by the server (functions/weekly_schedule.js PART).
  String get code => switch (this) {
        WeeklyPart.djg => 'djg',
        WeeklyPart.weeklyPr => 'weekly_pr',
        WeeklyPart.pgic => 'pgic',
        WeeklyPart.socialContact => 'social_contact',
      };

  /// Firestore subcollection holding this part's record (doc id = bundle).
  String get collection => switch (this) {
        WeeklyPart.djg => 'djg_responses',
        WeeklyPart.weeklyPr => 'weekly_pr',
        WeeklyPart.pgic => 'pgic',
        WeeklyPart.socialContact => 'social_contact_probes',
      };
}

enum WeeklyCloseRule { window, week4 }

class WeeklyBundle {
  /// `W1`…`W7`; the record id of every part.
  final String id;
  final int index;

  /// Study week of the push day ([studyWeekOf]).  For the pilot this is 1
  /// for every bundle; [bundleWeek] carries the W1–W4 label.
  final int studyWeek;
  final int bundleWeek;
  final int pushDay;
  final List<WeeklyPart> parts;
  final int windowDays;
  final WeeklyCloseRule closeRule;

  /// A PGIC-only bundle of weeks 5–7 ([PhaseBConfig.pgicOnlyDays]); server:
  /// `bundle.pgicOnly`.
  final bool pgicOnly;

  const WeeklyBundle({
    required this.id,
    required this.index,
    required this.studyWeek,
    required this.bundleWeek,
    required this.pushDay,
    required this.parts,
    required this.windowDays,
    required this.closeRule,
    this.pgicOnly = false,
  });
}

class WeeklyWindow {
  final DateTime open;
  final DateTime close;
  const WeeklyWindow(this.open, this.close);

  bool contains(DateTime t) => !t.isBefore(open) && t.isBefore(close);
}

class WeeklySchedule {
  WeeklySchedule._();

  /// Schedule mode by cohort (T21); null = not scheduled.  10/15: a pilot
  /// account runs the standard Phase B schedule; 1020b §1: so do the run-in
  /// and RCT- (every registered cohort, lib/core/study/cohorts.dart).
  static WeeklyScheduleMode? modeForCohort(String? cohort) =>
      Cohorts.isEnrolled(cohort) ? WeeklyScheduleMode.standard : null;

  static List<WeeklyPart> _common(PhaseBConfig cfg, bool withDjg) => [
        if (withDjg) WeeklyPart.djg,
        WeeklyPart.weeklyPr,
        WeeklyPart.pgic,
        if (cfg.socialContactProbeEnabled) WeeklyPart.socialContact,
      ];

  /// The bundles of a mode, in push order.
  static List<WeeklyBundle> bundlesFor(PhaseBConfig cfg, WeeklyScheduleMode mode) {
    final out = <WeeklyBundle>[];
    if (mode == WeeklyScheduleMode.pilot) {
      for (var i = 0; i < cfg.pilotBundleDays.length; i++) {
        final day = cfg.pilotBundleDays[i];
        out.add(WeeklyBundle(
          id: 'W${i + 1}',
          index: i,
          studyWeek: studyWeekOf(day),
          bundleWeek: i + 1,
          pushDay: day,
          parts: _common(cfg, i < 3),
          windowDays: cfg.pilotWindowDays,
          closeRule: WeeklyCloseRule.window,
        ));
      }
      return out;
    }
    for (var i = 0; i < cfg.weeklyBundleDays.length; i++) {
      final week = i + 1;
      final day = cfg.weeklyBundleDays[i];
      out.add(WeeklyBundle(
        id: 'W$week',
        index: i,
        studyWeek: studyWeekOf(day),
        bundleWeek: week,
        pushDay: day,
        parts: _common(cfg, cfg.djgWeeks.contains(week)),
        windowDays: cfg.weeklyWindowDays,
        closeRule: week == 4 ? WeeklyCloseRule.week4 : WeeklyCloseRule.window,
      ));
    }
    for (var j = 0; j < cfg.pgicOnlyDays.length; j++) {
      final day = cfg.pgicOnlyDays[j];
      final week = studyWeekOf(day);
      out.add(WeeklyBundle(
        id: 'W$week',
        index: cfg.weeklyBundleDays.length + j,
        studyWeek: week,
        bundleWeek: week,
        pushDay: day,
        parts: const [WeeklyPart.pgic],
        windowDays: cfg.weeklyWindowDays,
        closeRule: WeeklyCloseRule.window,
        pgicOnly: true,
      ));
    }
    return out;
  }

  static WeeklyBundle? bundleById(PhaseBConfig cfg, WeeklyScheduleMode mode, String id) {
    for (final b in bundlesFor(cfg, mode)) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// First instant after calendar day [d] (its 24:00).
  static DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

  /// 1020e 二.2(1): with v2 on, W4 closes at the end of this study day at
  /// the latest (server: V2_WEEK4_LATEST_CLOSE_DAY).
  static const int week4LatestCloseDayV2 = 42;

  /// The flag value used when a caller does not pass `v2`.
  static bool get v2Default =>
      RemoteFeatureFlags.current.weeklyReminderV2Enabled;

  /// 1020e 二.1 / 二.2: every v2 push goes at 10:00 Hong Kong time
  /// (server: V2_PUSH_HOUR).
  static const int v2PushHour = 10;

  /// Is [bundle] one the v2 windows cover?  W1–W3, W4 and, since item 98,
  /// W5–W7 ([WeeklyBundle.pgicOnly]) — every standard bundle (server:
  /// isReminderV2Bundle).
  static bool isV2Bundle(WeeklyBundle bundle) =>
      bundle.closeRule == WeeklyCloseRule.week4 ||
      bundle.pgicOnly ||
      (bundle.closeRule == WeeklyCloseRule.window && bundle.index < 3);

  /// Week-4 close: the end of study day [PhaseBConfig.week4CloseDay], or
  /// of the W4 visit day when that is later.  The visit date is the
  /// assessor's administration date from T30 (not merged yet: callers
  /// pass null today, so the window closes on day 29).  v2 off only.
  static DateTime week4CloseFor(DateTime w0, DateTime? w4VisitDate, PhaseBConfig cfg) {
    final byDay = _endOfDay(dateOfStudyDay(w0, cfg.week4CloseDay));
    if (w4VisitDate == null) return byDay;
    final byVisit = _endOfDay(w4VisitDate);
    return byVisit.isAfter(byDay) ? byVisit : byDay;
  }

  /// 1020e 二.2: week-4 close with v2 on — the end of the day the W4 visit
  /// was recorded ([recordedOn]), never before the end of the opening day,
  /// never after the end of day [week4LatestCloseDayV2]; nothing recorded:
  /// the end of day 42.
  static DateTime week4CloseV2(DateTime w0, DateTime? recordedOn, WeeklyBundle bundle) {
    final latest = _endOfDay(dateOfStudyDay(w0, week4LatestCloseDayV2));
    if (recordedOn == null) return latest;
    final earliest = _endOfDay(dateOfStudyDay(w0, bundle.pushDay));
    var close = _endOfDay(recordedOn);
    if (close.isBefore(earliest)) close = earliest;
    return close.isAfter(latest) ? latest : close;
  }

  /// `[open, close)` of [bundle] for a participant whose W0 is [w0].
  /// v2: whole days (W1–W3, W5–W7: 00:00 of the push day to the end of the
  /// push day + windowDays − 1; W4 [week4CloseV2]); off: T24 (the push
  /// hour, 72 h; W4 [week4CloseFor]).
  /// [v2] defaults to [v2Default]; [week4RecordedOn] is
  /// `users/{uid}.w4RecordedOn` (v2 only), [w4VisitDate] T24's hook (v2
  /// off only).
  static WeeklyWindow windowFor(WeeklyBundle bundle, DateTime w0, PhaseBConfig cfg,
      {DateTime? w4VisitDate, DateTime? week4RecordedOn, bool? v2}) {
    final pushDate = dateOfStudyDay(w0, bundle.pushDay);
    if ((v2 ?? v2Default) && isV2Bundle(bundle)) {
      final open = DateTime(pushDate.year, pushDate.month, pushDate.day);
      final close = bundle.closeRule == WeeklyCloseRule.week4
          ? week4CloseV2(w0, week4RecordedOn, bundle)
          : _endOfDay(dateOfStudyDay(w0, bundle.pushDay + bundle.windowDays - 1));
      return WeeklyWindow(open, close);
    }
    final open = DateTime(pushDate.year, pushDate.month, pushDate.day, cfg.weeklyPushHour);
    final close = bundle.closeRule == WeeklyCloseRule.week4
        ? week4CloseFor(w0, w4VisitDate, cfg)
        : open.add(Duration(hours: 24 * bundle.windowDays));
    return WeeklyWindow(open, close);
  }

  /// Every bundle whose window contains [now], in push order.  With v2 the
  /// W4 window can run to day 42 and overlap W5 / W6, so a caller that
  /// shows one card picks the first one still to do (pending_prompts).
  static List<({WeeklyBundle bundle, WeeklyWindow window})> openBundlesAt(
    PhaseBConfig cfg,
    WeeklyScheduleMode mode,
    DateTime w0,
    DateTime now, {
    DateTime? w4VisitDate,
    DateTime? week4RecordedOn,
    bool? v2,
  }) {
    final out = <({WeeklyBundle bundle, WeeklyWindow window})>[];
    for (final b in bundlesFor(cfg, mode)) {
      final w = windowFor(b, w0, cfg,
          w4VisitDate: w4VisitDate, week4RecordedOn: week4RecordedOn, v2: v2);
      if (w.contains(now)) out.add((bundle: b, window: w));
    }
    return out;
  }

  /// The first bundle whose window contains [now], or null.
  static ({WeeklyBundle bundle, WeeklyWindow window})? openBundleAt(
    PhaseBConfig cfg,
    WeeklyScheduleMode mode,
    DateTime w0,
    DateTime now, {
    DateTime? w4VisitDate,
    DateTime? week4RecordedOn,
    bool? v2,
  }) {
    final all = openBundlesAt(cfg, mode, w0, now,
        w4VisitDate: w4VisitDate, week4RecordedOn: week4RecordedOn, v2: v2);
    return all.isEmpty ? null : all.first;
  }

  /// Sessions counted for the Weekly PR referent of [bundle]: from the
  /// start of the first day of its study week (pilot: the previous push,
  /// or W0 midnight for the first bundle) to the window's opening (T24:
  /// the push instant; v2: 00:00 of the push day).
  static (DateTime, DateTime) referentRangeFor(
      WeeklyBundle bundle, DateTime w0, PhaseBConfig cfg, WeeklyScheduleMode mode,
      {bool? v2}) {
    final end = windowFor(bundle, w0, cfg, v2: v2).open;
    if (mode == WeeklyScheduleMode.pilot) {
      if (bundle.index == 0) return (DateTime(w0.year, w0.month, w0.day), end);
      final prev = bundlesFor(cfg, mode)[bundle.index - 1];
      return (windowFor(prev, w0, cfg, v2: v2).open, end);
    }
    final firstDay = 7 * (bundle.studyWeek - 1) + 1;
    return (dateOfStudyDay(w0, firstDay), end);
  }
}
