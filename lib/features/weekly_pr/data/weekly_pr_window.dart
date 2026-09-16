/// M-2 — Weekly PR window + referent rules (Phase A baseline 2026-09).
///
/// Pure functions (unit-tested) so the banner / trigger / Cloud Function
/// can agree on "which week is being rated" without touching Firestore.
///
/// Window: opens Sunday [PhaseAConfig.weeklyPrPushHour]:00 (HKT, the app's
/// wall clock) and closes at 23:59 on [PhaseAConfig.weeklyPrCloseWeekday]
/// (Tuesday).  The *rated week* is the ISO week whose Sunday opened the
/// window, i.e. Monday 00:00 → Sunday pushHour:00 of that week; sessions
/// between Sunday pushHour and midnight belong to the next rated week.
library;

import '../../../core/config/phase_a_config.dart';
import 'weekly_pr_response.dart';

class WeeklyPrWindow {
  WeeklyPrWindow._();

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Monday 00:00 of the ISO week containing [d].
  static DateTime mondayOf(DateTime d) =>
      _midnight(d).subtract(Duration(days: d.weekday - DateTime.monday));

  /// True while the Weekly PR entry is live on the home page.
  static bool isOpen(DateTime now, {PhaseAConfig? config}) {
    final c = config ?? PhaseAConfig.current;
    if (now.weekday == DateTime.sunday) return now.hour >= c.weeklyPrPushHour;
    // Monday … close weekday (inclusive, all day).
    return now.weekday >= DateTime.monday && now.weekday <= c.weeklyPrCloseWeekday;
  }

  /// Monday 00:00 of the week being rated by a window that is open at
  /// [now] — or, when the window is closed, of the week whose window most
  /// recently closed (used for the missed record).
  static DateTime ratedWeekMonday(DateTime now, {PhaseAConfig? config}) {
    final c = config ?? PhaseAConfig.current;
    if (now.weekday == DateTime.sunday && now.hour >= c.weeklyPrPushHour) {
      return mondayOf(now);
    }
    // Any other moment refers to the week that ended on the most recent
    // Sunday (Mon/Tue inside the window; Wed–Sun-before-push after it).
    return mondayOf(now).subtract(const Duration(days: 7));
  }

  /// `[start, end)` of the referent-counting range for the rated week:
  /// Monday 00:00 → Sunday pushHour:00.
  static (DateTime, DateTime) referentRange(DateTime ratedMonday,
      {PhaseAConfig? config}) {
    final c = config ?? PhaseAConfig.current;
    final sunday = ratedMonday.add(const Duration(days: 6));
    return (ratedMonday, DateTime(sunday.year, sunday.month, sunday.day, c.weeklyPrPushHour));
  }

  /// ISO week label for the rated week.
  static String ratedWeekIso(DateTime ratedMonday) =>
      WeeklyPrResponse.currentWeekIso(ratedMonday);

  /// The window for [ratedMonday] has closed before [now].
  static bool hasClosed(DateTime ratedMonday, DateTime now, {PhaseAConfig? config}) {
    final c = config ?? PhaseAConfig.current;
    final closeDay = ratedMonday.add(Duration(days: 7 + (c.weeklyPrCloseWeekday - DateTime.monday)));
    final closeAt = DateTime(closeDay.year, closeDay.month, closeDay.day, 23, 59, 59);
    return now.isAfter(closeAt);
  }
}

/// Referent-selection rule that picked the companion (spec M-2).
class ReferentRule {
  ReferentRule._();
  static const maxSessions = 'max_sessions';
  static const tieTurns = 'tie_turns';
  static const tieRecency = 'tie_recency';
  static const none = 'none';
}

/// Per-agent usage inside the referent range.
class AgentWeekUsage {
  final String agentId;
  final int sessionCount;
  final int userTurnCount;
  final DateTime lastUsedAt;

  const AgentWeekUsage({
    required this.agentId,
    required this.sessionCount,
    required this.userTurnCount,
    required this.lastUsedAt,
  });
}

class ReferentChoice {
  final AgentWeekUsage? agent;
  final String rule;
  const ReferentChoice(this.agent, this.rule);
}

/// Deterministic referent: most agent sessions → tie: most user turns →
/// tie: most recently used.  Pure; unit-tested.
ReferentChoice chooseReferent(List<AgentWeekUsage> usage) {
  if (usage.isEmpty) return const ReferentChoice(null, ReferentRule.none);
  final sorted = List<AgentWeekUsage>.from(usage)
    ..sort((a, b) {
      final s = b.sessionCount.compareTo(a.sessionCount);
      if (s != 0) return s;
      final t = b.userTurnCount.compareTo(a.userTurnCount);
      if (t != 0) return t;
      return b.lastUsedAt.compareTo(a.lastUsedAt);
    });
  final top = sorted.first;
  if (sorted.length == 1) return ReferentChoice(top, ReferentRule.maxSessions);
  final second = sorted[1];
  if (top.sessionCount != second.sessionCount) {
    return ReferentChoice(top, ReferentRule.maxSessions);
  }
  if (top.userTurnCount != second.userTurnCount) {
    return ReferentChoice(top, ReferentRule.tieTurns);
  }
  return ReferentChoice(top, ReferentRule.tieRecency);
}
