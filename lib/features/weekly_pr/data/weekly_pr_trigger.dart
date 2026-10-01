/// Weekly PR trigger helper — figures out which agents the user used
/// this week and whether the weekly PR has already been submitted.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/session/chat_session_recorder.dart';
import '../../analytics/data/analytics_service.dart';
import 'weekly_pr_response.dart';
import 'weekly_pr_window.dart';

class WeeklyPrAgentUsage {
  final String agentId;
  final String displayName;
  final int sessionCount;

  /// Earliest session-start this week for this agent — the deterministic
  /// tie-break when two agents have the same session count (C2).
  final DateTime firstUseAt;

  /// M-2 — user turns this week (second tie-break) and the rule that
  /// selected this agent.  Null when produced by the legacy events path.
  final int? userTurnCount;
  final String? referentRule;

  const WeeklyPrAgentUsage({
    required this.agentId,
    required this.displayName,
    required this.sessionCount,
    required this.firstUseAt,
    this.userTurnCount,
    this.referentRule,
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

  /// Returns agents used in the current ISO week (Monday 00:00 → now),
  /// sorted by descending session count then earliest first-use (the C2
  /// deterministic tie-break). Counts any analytics event whose name is
  /// in [_sessionStartEvents] or which carries an `agentId` field.
  ///
  /// ISO-week window ON PURPOSE: the submit-dedup is per ISO week, so a
  /// rolling now−7d window let last Sunday's already-surveyed sessions
  /// flip which agent this Sunday's Weekly PR anchors to.
  Future<List<WeeklyPrAgentUsage>> agentsUsedThisWeek(String uid) async {
    try {
      final now = DateTime.now();
      final since = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
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
  /// when no companion was used.  Legacy events-based path; the Phase A
  /// baseline uses [referentForRatedWeek].
  Future<WeeklyPrAgentUsage?> mostUsedAgentThisWeek(String uid) async {
    final list = await agentsUsedThisWeek(uid);
    return list.isEmpty ? null : list.first;
  }

  /// M-2 (Phase A baseline) — referent from `users/{uid}/sessions` (agent
  /// sessions, Monday 00:00 → Sunday pushHour of the rated week): most
  /// sessions → tie: most user turns → tie: most recent.  Returns the
  /// choice with `referentRule` populated; `agent == null` + rule `none`
  /// when the week had no agent session.
  Future<ReferentChoice> referentForRatedWeek(
    String uid,
    DateTime ratedMonday,
  ) async {
    final (start, end) = WeeklyPrWindow.referentRange(ratedMonday);
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('startedAt', isLessThan: Timestamp.fromDate(end))
          .get();
      final sessions = <String, int>{};
      final turns = <String, int>{};
      final last = <String, DateTime>{};
      for (final d in snap.docs) {
        final data = d.data();
        if (data['kind'] != 'agent') continue;
        final agentId = data['agentId'];
        if (agentId is! String) continue;
        sessions.update(agentId, (v) => v + 1, ifAbsent: () => 1);
        turns.update(agentId, (v) => v + ((data['userTurnCount'] as num?)?.toInt() ?? 0),
            ifAbsent: () => (data['userTurnCount'] as num?)?.toInt() ?? 0);
        final ts = data['startedAt'];
        final when = ts is Timestamp ? ts.toDate() : start;
        last.update(agentId, (cur) => when.isAfter(cur) ? when : cur, ifAbsent: () => when);
      }
      final usage = [
        for (final e in sessions.entries)
          AgentWeekUsage(
            agentId: e.key,
            sessionCount: e.value,
            userTurnCount: turns[e.key] ?? 0,
            lastUsedAt: last[e.key] ?? start,
          ),
      ];
      return chooseReferent(usage);
    } catch (_) {
      return const ReferentChoice(null, ReferentRule.none);
    }
  }

  /// Convenience: [referentForRatedWeek] as the page's usage model.
  Future<WeeklyPrAgentUsage?> referentUsageForRatedWeek(
    String uid,
    DateTime ratedMonday,
  ) async {
    final choice = await referentForRatedWeek(uid, ratedMonday);
    final a = choice.agent;
    if (a == null) return null;
    return WeeklyPrAgentUsage(
      agentId: a.agentId,
      displayName: _displayNames[a.agentId] ?? a.agentId,
      sessionCount: a.sessionCount,
      firstUseAt: a.lastUsedAt,
      userTurnCount: a.userTurnCount,
      referentRule: choice.rule,
    );
  }

  /// M-2 — after the window closes with no weekly_pr doc for that week,
  /// write one `missed_{weekIso}` record (idempotent) and emit
  /// `weekly_pr_missed`.  Skipped for weeks before enrolment.
  Future<void> recordMissedIfNeeded({
    required String uid,
    required String arm,
    required DateTime ratedMonday,
    required DateTime? enrolledAt,
    AnalyticsService? analytics,
  }) async {
    final weekIso = WeeklyPrWindow.ratedWeekIso(ratedMonday);
    if (enrolledAt != null &&
        enrolledAt.isAfter(ratedMonday.add(const Duration(days: 6)))) {
      return;
    }
    try {
      if (await hasSubmittedThisWeek(uid, weekIso)) return;
      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('weekly_pr')
          .doc('missed_$weekIso');
      if ((await ref.get()).exists) return;
      final now = DateTime.now();
      await ref.set(WeeklyPrResponse(
        weekIso: weekIso,
        agentId: '_none',
        agentDisplayName: '—',
        sessionCountThisWeek: 0,
        items: const {},
        status: 'missed',
        promptedAt: now,
        respondedAt: now,
        arm: arm,
        referentRule: null,
      ).toFirestore());
      unawaited(analytics?.logEvent(PhaseAEvents.weeklyPrMissed, {'weekIso': weekIso}) ??
          Future<void>.value());
    } catch (_) {}
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

  /// Writes a no_referent record when no agents were used this week
  /// (M-2: the 12 items are missing-by-design; only PGIC was asked).
  Future<void> writeNoReferent(String uid, String arm, {String? weekIso}) async {
    try {
      final now = DateTime.now();
      final resp = WeeklyPrResponse(
        weekIso: weekIso ?? WeeklyPrResponse.currentWeekIso(),
        agentId: '_none',
        agentDisplayName: '—',
        sessionCountThisWeek: 0,
        items: const {},
        status: 'no_referent',
        promptedAt: now,
        respondedAt: now,
        arm: arm,
        referentRule: ReferentRule.none,
      );
      await _db
          .collection('users')
          .doc(uid)
          .collection('weekly_pr')
          .add(resp.toFirestore());
    } catch (_) {}
  }
}
