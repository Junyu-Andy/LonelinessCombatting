/// Phase A baseline runtime parameters (Dev spec v1 2026-09, §M-7 / §M-1 /
/// §M-2 / §M-4 / §P-1 / §8).
///
/// Every value the PI may still change before participant 1 is enrolled
/// lives here with the spec default, so the decision lands as a config
/// edit rather than a code change.  Two layers:
///
///   1. Compile-time defaults (this file) — always available, used in
///      tests and when Firestore is unreachable.
///   2. Optional remote override — `app_config/phase_a` Firestore document
///      (read-only for clients; written by the research team from the
///      console).  Any key present there replaces the default on the next
///      app start.  Missing keys keep the default.
///
/// Call [PhaseAConfig.load] once at startup; read via [PhaseAConfig.current].
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PhaseAConfig {
  const PhaseAConfig({
    this.sessionIdleTimeoutMin = 10,
    this.briefPRMinTurns = 2,
    this.briefPRItemCount = 4,
    this.weeklyPrPushHour = 20,
    this.weeklyPrCloseWeekday = DateTime.tuesday,
    this.w2DayOffset = 14,
    this.w2WindowDays = 3,
    this.week1NudgeDays = const [3, 6],
  });

  /// M-7 — agent session ends after this many minutes without a user
  /// message (`endReason = timeout`).
  final int sessionIdleTimeoutMin;

  /// M-1 — Brief PR is shown only when the session had at least this many
  /// user turns (fallback turns excluded).
  final int briefPRMinTurns;

  /// M-1 — 4 (with insensitivity item) or 3.  PI decision pending; 4 is the
  /// spec default.
  final int briefPRItemCount;

  /// M-2 — Sunday hour (HKT, 24 h) at which the Weekly PR window opens and
  /// the FCM doorbell fires.
  final int weeklyPrPushHour;

  /// M-2 — weekday (Dart constant, Monday = 1) whose 23:59 closes the
  /// Weekly PR window.  Tuesday per spec.
  final int weeklyPrCloseWeekday;

  /// M-4 — days after enrolment for the Week 2 push (DJG-ES + Agent
  /// Differentiation).
  final int w2DayOffset;

  /// M-4 — window (days) during which the Week 2 battery stays open.
  final int w2WindowDays;

  /// P-1 — enrolment days on which the "you haven't tried {agent}" nudge
  /// may show.
  final List<int> week1NudgeDays;

  static PhaseAConfig _current = const PhaseAConfig();

  /// The active configuration (defaults until [load] merges an override).
  static PhaseAConfig get current => _current;

  /// Test / tooling hook.
  @visibleForTesting
  static set current(PhaseAConfig value) => _current = value;

  /// Firestore document holding overrides.  Read-only for clients.
  static const String remotePath = 'app_config/phase_a';

  /// Merge overrides from Firestore.  Never throws; on any failure the
  /// defaults stay in force.
  static Future<PhaseAConfig> load({bool available = true}) async {
    if (!available) return _current;
    try {
      // Bounded: a cold start on a flaky network must not wait on this read;
      // the defaults are always safe and the next launch retries.
      final snap = await FirebaseFirestore.instance
          .doc(remotePath)
          .get()
          .timeout(const Duration(seconds: 3));
      final data = snap.data();
      if (data != null) _current = fromMap(data, base: _current);
    } catch (e) {
      if (kDebugMode) debugPrint('[PhaseAConfig] remote load skipped: $e');
    }
    return _current;
  }

  /// Pure merge used by [load] and tests.
  static PhaseAConfig fromMap(Map<String, dynamic> map,
      {PhaseAConfig base = const PhaseAConfig()}) {
    int i(String k, int d) => (map[k] as num?)?.toInt() ?? d;
    final nudgeRaw = map['week1NudgeDays'];
    final nudge = nudgeRaw is List
        ? nudgeRaw.whereType<num>().map((e) => e.toInt()).toList()
        : base.week1NudgeDays;
    return PhaseAConfig(
      sessionIdleTimeoutMin: i('sessionIdleTimeoutMin', base.sessionIdleTimeoutMin),
      briefPRMinTurns: i('briefPRMinTurns', base.briefPRMinTurns),
      briefPRItemCount: i('briefPRItemCount', base.briefPRItemCount).clamp(3, 4),
      weeklyPrPushHour: i('weeklyPrPushHour', base.weeklyPrPushHour),
      weeklyPrCloseWeekday: i('weeklyPrCloseWeekday', base.weeklyPrCloseWeekday),
      w2DayOffset: i('w2DayOffset', base.w2DayOffset),
      w2WindowDays: i('w2WindowDays', base.w2WindowDays),
      week1NudgeDays: nudge,
    );
  }

  Map<String, dynamic> toMap() => {
        'sessionIdleTimeoutMin': sessionIdleTimeoutMin,
        'briefPRMinTurns': briefPRMinTurns,
        'briefPRItemCount': briefPRItemCount,
        'weeklyPrPushHour': weeklyPrPushHour,
        'weeklyPrCloseWeekday': weeklyPrCloseWeekday,
        'w2DayOffset': w2DayOffset,
        'w2WindowDays': w2WindowDays,
        'week1NudgeDays': week1NudgeDays,
      };
}
