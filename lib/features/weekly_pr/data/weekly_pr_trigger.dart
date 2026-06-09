/// Weekly PR trigger helper — figures out which agents the user used
/// this week and whether the weekly PR has already been submitted.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'weekly_pr_response.dart';

class WeeklyPrAgentUsage {
  final String agentId;
  final String displayName;
  final int sessionCount;

  /// Earliest session-start this week for this agent — the deterministic
  /// tie-break when two agents have the same session count (C2).
  final DateTime firstUseAt;

  const WeeklyPrAgentUsage({
    required this.agentId,
    required this.displayName,
    required this.sessionCount,
    required this.firstUseAt,
  });
}

class WeeklyPrTrigger {
  WeeklyPrTrigger({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _displayNames = {
    'siu_yan': '小欣',
    'ah_jan_ah_bak': '阿珍／阿伯',
    'tung_tung': '通通',
  };

  static const _sessionStartEvents = {
    'm2_check_in_started',
    'm3_session_started',
    'm3_session_start',
    'tung_tung_chat_started',
    'm5_reflective_session_start',
  };

  /// Returns agents used in the last 7 days, sorted by descending session
  /// count then earliest first-use (the C2 deterministic tie-break). Counts
  /// any analytics event whose name is in [_sessionStartEvents] or which
  /// carries an `agentId` field.
  Future<List<WeeklyPrAgentUsage>> agentsUsedThisWeek(String uid) async {
    try {
      final since = DateTime.now().subtract(const Duration(days: 7));
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('events')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      final counts = <String, int>{};
      final firstUse = <String, DateTime>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['name'] as String?;
        final params = data['params'];
        String? agentId;
        if (params is Map) {
          agentId = params['agentId'] as String?;
        }
        if (agentId == null && name != null) {
          if (name.startsWith('m2_')) {
            agentId = 'siu_yan';
          } else if (name.startsWith('m3_') ||
              name.startsWith('m5_reflective')) {
            agentId = 'ah_jan_ah_bak';
          } else if (name.startsWith('tung_tung_')) {
            agentId = 'tung_tung';
          }
        }
        if (agentId == null) continue;
        if (name != null &&
            !_sessionStartEvents.contains(name) &&
            !name.contains('started') &&
            !name.contains('session_start')) {
          // Only count session-start markers, not every turn.
          continue;
        }
        counts.update(agentId, (v) => v + 1, ifAbsent: () => 1);
        final ts = data['timestamp'];
        final when = ts is Timestamp ? ts.toDate() : DateTime.now();
        firstUse.update(
          agentId,
          (cur) => when.isBefore(cur) ? when : cur,
          ifAbsent: () => when,
        );
      }
      final list = counts.entries
          .map((e) => WeeklyPrAgentUsage(
                agentId: e.key,
                displayName: _displayNames[e.key] ?? e.key,
                sessionCount: e.value,
                firstUseAt: firstUse[e.key] ?? DateTime.now(),
              ))
          .toList();
      list.sort((a, b) {
        final byCount = b.sessionCount.compareTo(a.sessionCount);
        if (byCount != 0) return byCount;
        return a.firstUseAt.compareTo(b.firstUseAt); // earlier first-use wins
      });
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// C2 — the single companion the Weekly PR is anchored to: the one used
  /// most this week (deterministic tie-break = earliest first-use). Null
  /// when no companion was used.
  Future<WeeklyPrAgentUsage?> mostUsedAgentThisWeek(String uid) async {
    final list = await agentsUsedThisWeek(uid);
    return list.isEmpty ? null : list.first;
  }

  /// Returns true iff a weekly_pr doc with this weekIso already exists.
  Future<bool> hasSubmittedThisWeek(String uid, String weekIso) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('weekly_pr')
          .where('weekIso', isEqualTo: weekIso)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Writes a no_referent record when no agents were used this week.
  Future<void> writeNoReferent(String uid, String arm) async {
    try {
      final now = DateTime.now();
      final resp = WeeklyPrResponse(
        weekIso: WeeklyPrResponse.currentWeekIso(),
        agentId: '_none',
        agentDisplayName: '—',
        sessionCountThisWeek: 0,
        items: const {},
        status: 'no_referent',
        promptedAt: now,
        respondedAt: now,
        arm: arm,
      );
      await _db
          .collection('users')
          .doc(uid)
          .collection('weekly_pr')
          .add(resp.toFirestore());
    } catch (_) {}
  }
}
