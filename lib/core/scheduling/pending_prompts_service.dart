/// Banner-based trigger orchestration (Phase A baseline 2026-09).
///
/// The scheduled Cloud Functions only ring a doorbell (FCM); the app asks
/// this service "what should I surface on home?" on every home rebuild.
///
///   • M-2 Weekly PR: window opens Sunday [PhaseAConfig.weeklyPrPushHour]
///     and stays on the home page until Tuesday 23:59.  PGIC is asked
///     first; the 12-item PR is anchored to the referent chosen from the
///     rated week's agent sessions (max sessions → tie turns → tie
///     recency).  A week with no agent session still surfaces (PGIC only,
///     `no_referent` record).  Once the window has closed with nothing
///     submitted, a `missed_{weekIso}` record is written.
///   • M-4 Week 2 battery: DJG-ES + Agent Differentiation from enrolment
///     day [PhaseAConfig.w2DayOffset] for [PhaseAConfig.w2WindowDays] days.
///   • Week 4 Agent Differentiation (pre-baseline behaviour kept).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/analytics/data/analytics_service.dart';
import '../../features/auth/data/user_profile.dart';
import '../../features/weekly_pr/data/weekly_pr_trigger.dart';
import '../../features/weekly_pr/data/weekly_pr_window.dart';
import '../config/phase_a_config.dart';

class PendingPrompts {
  final bool pgic;
  final bool weeklyPr;

  /// M-2 — the rated week's ISO label (may differ from the current week on
  /// Mon/Tue).
  final String? weeklyPrWeekIso;

  /// C2 — the single companion the Weekly PR is anchored to. Null when the
  /// rated week had no agent session (PGIC only, `no_referent`).
  final WeeklyPrAgentUsage? weeklyPrAgent;

  /// M-4 — Week 2 battery parts still open.
  final bool djgEsW2;
  final bool agentDiffW2;
  final bool agentDiffW4;

  const PendingPrompts({
    required this.pgic,
    required this.weeklyPr,
    required this.weeklyPrWeekIso,
    required this.weeklyPrAgent,
    required this.djgEsW2,
    required this.agentDiffW2,
    required this.agentDiffW4,
  });

  bool get w2Any => djgEsW2 || agentDiffW2;
  bool get any => pgic || weeklyPr || w2Any || agentDiffW4;
}

class PendingPromptsService {
  PendingPromptsService({
    FirebaseFirestore? db,
    WeeklyPrTrigger? weeklyPrTrigger,
    this.analytics,
  })  : _db = db ?? FirebaseFirestore.instance,
        _weeklyTrigger = weeklyPrTrigger ?? WeeklyPrTrigger(db: db);

  final FirebaseFirestore _db;
  final WeeklyPrTrigger _weeklyTrigger;
  final AnalyticsService? analytics;

  Future<PendingPrompts> shouldShowOnHomeNow(
    String uid,
    UserProfile? profile, {
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    final cfg = PhaseAConfig.current;

    bool pgic = false;
    bool weeklyPr = false;
    String? weekIso;
    WeeklyPrAgentUsage? chosenAgent;

    final ratedMonday = WeeklyPrWindow.ratedWeekMonday(t, config: cfg);
    final ratedIso = WeeklyPrWindow.ratedWeekIso(ratedMonday);
    if (WeeklyPrWindow.isOpen(t, config: cfg)) {
      final hasWeekly = await _weeklyTrigger.hasSubmittedThisWeek(uid, ratedIso);
      pgic = await _noPgicForWeek(uid, ratedMonday);
      if (!hasWeekly) {
        weeklyPr = true;
        weekIso = ratedIso;
        chosenAgent = await _weeklyTrigger.referentUsageForRatedWeek(uid, ratedMonday);
      }
    } else if (WeeklyPrWindow.hasClosed(ratedMonday, t, config: cfg)) {
      // M-2 — window closed with nothing submitted → missed record (once).
      await _weeklyTrigger.recordMissedIfNeeded(
        uid: uid,
        arm: profile?.arm?.code ?? 'A',
        ratedMonday: ratedMonday,
        enrolledAt: profile?.createdAt,
        analytics: analytics,
      );
    }

    bool djgEsW2 = false;
    bool agentDiffW2 = false;
    bool agentDiffW4 = false;
    final createdAt = profile?.createdAt;
    if (createdAt != null) {
      final daysSince = t.difference(createdAt).inDays;
      final inW2Window =
          daysSince >= cfg.w2DayOffset && daysSince < cfg.w2DayOffset + cfg.w2WindowDays;
      if (inW2Window) {
        if (!await _hasDoc(uid, 'djg_es', 'timepoint', 'week2')) djgEsW2 = true;
        if (!await _hasDoc(uid, 'agent_diff', 'timepoint', 'week2')) agentDiffW2 = true;
      }
      if (daysSince >= 28 && !await _hasDoc(uid, 'agent_diff', 'timepoint', 'week4')) {
        agentDiffW4 = true;
      }
    }

    return PendingPrompts(
      pgic: pgic,
      weeklyPr: weeklyPr,
      weeklyPrWeekIso: weekIso,
      weeklyPrAgent: chosenAgent,
      djgEsW2: djgEsW2,
      agentDiffW2: agentDiffW2,
      agentDiffW4: agentDiffW4,
    );
  }

  Future<bool> _noPgicForWeek(String uid, DateTime ratedMonday) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('pgic')
          .where('answeredAt', isGreaterThanOrEqualTo: Timestamp.fromDate(ratedMonday))
          .limit(1)
          .get();
      return snap.docs.isEmpty;
    } catch (_) {
      // Fail closed (= "already answered"): a transient read error must
      // not re-prompt a participant who already completed the PGIC.
      return false;
    }
  }

  Future<bool> _hasDoc(String uid, String collection, String field, String value) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection(collection)
          .where(field, isEqualTo: value)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      // Fail closed (= "exists"): don't re-prompt on read errors.
      return true;
    }
  }
}
