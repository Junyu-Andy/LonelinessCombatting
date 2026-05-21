/// Banner-based trigger orchestration.
///
/// In lieu of a Cloud Functions / FCM scheduler (deferred), the app
/// asks this service "what should I surface on home?" each time the
/// home tab rebuilds.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/auth/data/user_profile.dart';
import '../../features/weekly_pr/data/weekly_pr_response.dart';
import '../../features/weekly_pr/data/weekly_pr_trigger.dart';

class PendingPrompts {
  final bool pgic;
  final bool weeklyPr;
  final bool agentDiffW2;
  final bool agentDiffW4;
  final List<WeeklyPrAgentUsage> weeklyPrAgents;

  const PendingPrompts({
    required this.pgic,
    required this.weeklyPr,
    required this.agentDiffW2,
    required this.agentDiffW4,
    required this.weeklyPrAgents,
  });

  bool get any => pgic || weeklyPr || agentDiffW2 || agentDiffW4;
}

class PendingPromptsService {
  PendingPromptsService({
    FirebaseFirestore? db,
    WeeklyPrTrigger? weeklyPrTrigger,
  })  : _db = db ?? FirebaseFirestore.instance,
        _weeklyTrigger = weeklyPrTrigger ?? WeeklyPrTrigger();

  final FirebaseFirestore _db;
  final WeeklyPrTrigger _weeklyTrigger;

  Future<PendingPrompts> shouldShowOnHomeNow(
    String uid,
    UserProfile? profile,
  ) async {
    final now = DateTime.now();
    final isSundayEvening =
        now.weekday == DateTime.sunday && now.hour >= 20 && now.hour <= 23;

    bool pgic = false;
    bool weeklyPr = false;
    List<WeeklyPrAgentUsage> agents = const [];

    if (isSundayEvening) {
      pgic = await _noPgicThisWeek(uid);
      final weekIso = WeeklyPrResponse.currentWeekIso();
      final hasWeekly = await _weeklyTrigger.hasSubmittedThisWeek(uid, weekIso);
      if (!hasWeekly) {
        agents = await _weeklyTrigger.agentsUsedThisWeek(uid);
        weeklyPr = agents.isNotEmpty;
      }
    }

    bool agentDiffW2 = false;
    bool agentDiffW4 = false;
    final createdAt = profile?.createdAt;
    if (createdAt != null) {
      final daysSince = now.difference(createdAt).inDays;
      if (daysSince >= 14 && !await _hasAgentDiff(uid, 'week2')) {
        agentDiffW2 = true;
      }
      if (daysSince >= 28 && !await _hasAgentDiff(uid, 'week4')) {
        agentDiffW4 = true;
      }
    }

    return PendingPrompts(
      pgic: pgic,
      weeklyPr: weeklyPr,
      agentDiffW2: agentDiffW2,
      agentDiffW4: agentDiffW4,
      weeklyPrAgents: agents,
    );
  }

  Future<bool> _noPgicThisWeek(String uid) async {
    try {
      final now = DateTime.now();
      // Week starts Monday.
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeek = DateTime(monday.year, monday.month, monday.day);
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('pgic')
          .where('answeredAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
          .limit(1)
          .get();
      return snap.docs.isEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _hasAgentDiff(String uid, String timepoint) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('agent_diff')
          .where('timepoint', isEqualTo: timepoint)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
