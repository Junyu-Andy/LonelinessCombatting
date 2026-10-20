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
///   W5–W7  PGIC only, [PhaseBConfig.pgicOnlyDays] (35, 42, 49).
/// Pilot (cohort `pilot`): the SAME standard schedule (10/15: the pilot run
///   follows Phase B day for day).  [WeeklyScheduleMode.pilot] (days 1, 3,
///   5, 7, 1-day windows) is kept only for the shared table test; no cohort
///   maps to it any more.
///
/// Every window is `[open, close)`: open = push instant, close exclusive.
library;

import '../config/phase_b_config.dart';
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

  const WeeklyBundle({
    required this.id,
    required this.index,
    required this.studyWeek,
    required this.bundleWeek,
    required this.pushDay,
    required this.parts,
    required this.windowDays,
    required this.closeRule,
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

  /// Week-4 close: the end of study day [PhaseBConfig.week4CloseDay], or
  /// of the W4 visit day when that is later.  The visit date is the
  /// assessor's administration date from T30 (not merged yet: callers
  /// pass null today, so the window closes on day 29).
  static DateTime week4CloseFor(DateTime w0, DateTime? w4VisitDate, PhaseBConfig cfg) {
    final byDay = _endOfDay(dateOfStudyDay(w0, cfg.week4CloseDay));
    if (w4VisitDate == null) return byDay;
    final byVisit = _endOfDay(w4VisitDate);
    return byVisit.isAfter(byDay) ? byVisit : byDay;
  }

  /// `[open, close)` of [bundle] for a participant whose W0 is [w0].
  static WeeklyWindow windowFor(WeeklyBundle bundle, DateTime w0, PhaseBConfig cfg,
      {DateTime? w4VisitDate}) {
    final pushDate = dateOfStudyDay(w0, bundle.pushDay);
    final open = DateTime(pushDate.year, pushDate.month, pushDate.day, cfg.weeklyPushHour);
    final close = bundle.closeRule == WeeklyCloseRule.week4
        ? week4CloseFor(w0, w4VisitDate, cfg)
        : open.add(Duration(hours: 24 * bundle.windowDays));
    return WeeklyWindow(open, close);
  }

  /// The bundle whose window contains [now], or null.
  static ({WeeklyBundle bundle, WeeklyWindow window})? openBundleAt(
    PhaseBConfig cfg,
    WeeklyScheduleMode mode,
    DateTime w0,
    DateTime now, {
    DateTime? w4VisitDate,
  }) {
    for (final b in bundlesFor(cfg, mode)) {
      final w = windowFor(b, w0, cfg, w4VisitDate: w4VisitDate);
      if (w.contains(now)) return (bundle: b, window: w);
    }
    return null;
  }

  /// Sessions counted for the Weekly PR referent of [bundle]: from the
  /// start of the first day of its study week (pilot: the previous push,
  /// or W0 midnight for the first bundle) to the push instant.
  static (DateTime, DateTime) referentRangeFor(
      WeeklyBundle bundle, DateTime w0, PhaseBConfig cfg, WeeklyScheduleMode mode) {
    final end = windowFor(bundle, w0, cfg).open;
    if (mode == WeeklyScheduleMode.pilot) {
      if (bundle.index == 0) return (DateTime(w0.year, w0.month, w0.day), end);
      final prev = bundlesFor(cfg, mode)[bundle.index - 1];
      return (windowFor(prev, w0, cfg).open, end);
    }
    final firstDay = 7 * (bundle.studyWeek - 1) + 1;
    return (dateOfStudyDay(w0, firstDay), end);
  }
}
