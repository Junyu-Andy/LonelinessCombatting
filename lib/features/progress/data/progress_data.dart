import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/feature_flags/remote_feature_flags.dart';
import '../../today/data/mood_recorder.dart';

/// One week of dashboard inputs for M9. Read by [ProgressRepository] in
/// a single fan-out, then handed to the view.
class WeeklyProgress {
  /// One mood reading per check-in submitted in the past 7 days, oldest
  /// first. Always in 1..5.
  final List<int> moodScores;

  /// When each reading in [moodScores] was submitted (same order). May be
  /// empty for legacy callers/tests — the chart then omits date labels.
  final List<DateTime> moodTimes;

  /// Count of check-ins where a non-zero contact proxy was reported.
  final int contactDays;

  /// Action plans authored in the last 7 days.
  final int plansAuthored;

  /// Action plans where the user marked an outcome (happened / partial /
  /// didn't) in the last 7 days. Used as the completion-rate numerator.
  final int plansFollowedUp;

  /// Reminiscence weekly summaries written in the last 7 days.
  final int reminiscenceSessions;

  /// 1020e 二.11 (`moodRowV2Enabled`): the chart reads `daily_mood` — the
  /// last entry of each of the last 7 days ([dailyMoodDays], oldest
  /// first); a day without one is null and stays blank (never 3).
  final bool moodFromDailyMood;
  final List<int?> dailyMoods;
  final List<DateTime> dailyMoodDays;

  /// Check-ins in the last 7 days when the chart no longer counts them
  /// ([moodFromDailyMood]); null = [moodScores] is the check-in list.
  final int? checkInCount;

  const WeeklyProgress({
    required this.moodScores,
    this.moodTimes = const [],
    required this.contactDays,
    required this.plansAuthored,
    required this.plansFollowedUp,
    required this.reminiscenceSessions,
    this.moodFromDailyMood = false,
    this.dailyMoods = const [],
    this.dailyMoodDays = const [],
    this.checkInCount,
  });

  /// How many check-ins (the count tile, the weekly summary).
  int get checkIns => checkInCount ?? moodScores.length;

  /// The mood readings the weekly summary averages.
  List<int> get moodsForSummary =>
      moodFromDailyMood ? dailyMoods.whereType<int>().toList() : moodScores;

  static const empty = WeeklyProgress(
    moodScores: [],
    contactDays: 0,
    plansAuthored: 0,
    plansFollowedUp: 0,
    reminiscenceSessions: 0,
  );
}

class ProgressRepository {
  ProgressRepository({required this.available});
  final bool available;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// 1020e 二.11 — the last `daily_mood` of each day in [dayIsos]
  /// (YYYY-MM-DD, oldest first); null for a day without one.  "Last" =
  /// highest `entry_seq_today`, then latest `responded_at`.
  static List<int?> lastMoodPerDay(
      Iterable<Map<String, dynamic>> rows, List<String> dayIsos) {
    final best = <String, Map<String, dynamic>>{};
    int seq(Map<String, dynamic> r) =>
        (r['entry_seq_today'] as num?)?.toInt() ?? 0;
    DateTime at(Map<String, dynamic> r) {
      final v = r['responded_at'];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return DateTime(2000);
    }

    for (final r in rows) {
      final day = r['date_iso'];
      final mood = r['mood'];
      if (day is! String || mood is! num) continue;
      final m = mood.toInt();
      if (m < 1 || m > 5) continue;
      final cur = best[day];
      if (cur == null ||
          seq(r) > seq(cur) ||
          (seq(r) == seq(cur) && at(r).isAfter(at(cur)))) {
        best[day] = r;
      }
    }
    return [
      for (final d in dayIsos) (best[d]?['mood'] as num?)?.toInt(),
    ];
  }

  /// The last 7 local days ending [now], oldest first.
  static List<DateTime> lastSevenDays(DateTime now) => [
        for (var i = 6; i >= 0; i--)
          DateTime(now.year, now.month, now.day - i),
      ];

  Future<WeeklyProgress> load(String uid) async {
    if (!available) return WeeklyProgress.empty;
    final since = DateTime.now().subtract(const Duration(days: 7));

    final eventsSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('events')
        .where('name', whereIn: ['check_in_submitted', 'social_log_entry'])
        .get();
    final recentEvents = eventsSnap.docs
        .where((d) => _ts(d.data()['timestamp']).isAfter(since))
        .toList();
    // (score, submitted-at) pairs, sorted oldest-first so the chart reads
    // left → right in time (the raw query order is not guaranteed).
    final moodPairs = recentEvents
        .where((d) => d.data()['name'] == 'check_in_submitted')
        .map((d) => (
              ((d.data()['params'] as Map?)?['mood'] as int?) ?? 3,
              _ts(d.data()['timestamp']),
            ))
        .toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    final moods = [for (final p in moodPairs) p.$1];
    final moodTimes = [for (final p in moodPairs) p.$2];
    final contactDays = recentEvents
        .where((d) =>
            d.data()['name'] == 'social_log_entry' &&
            ((d.data()['params'] as Map?)?['hasPerson'] as bool? ?? false))
        .length;

    final plansSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('action_plans')
        .get();
    final plans = plansSnap.docs
        .where((d) => _ts(d.data()['createdAt']).isAfter(since))
        .toList();
    final followed = plans
        .where((d) => (d.data()['outcome'] as String?) != null)
        .length;

    // Reminiscence: scan each weekly session doc (new schema, P2.2)
    // and count weeks completed in the past 7 days.
    var reminiscence = 0;
    for (var w = 1; w <= 4; w++) {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('memory')
          .doc('m3_reminiscence')
          .collection('sessions')
          .doc('week_$w')
          .get();
      if (!snap.exists) continue;
      final data = snap.data() ?? const {};
      if (data['status'] != 'completed') continue;
      if (_ts(data['completed_at']).isAfter(since)) reminiscence += 1;
    }

    // 1020e 二.11 — with the mood row on, the chart is the elder's own
    // mood (daily_mood), one per day; check-ins are only counted.
    if (RemoteFeatureFlags.current.moodRowV2Enabled) {
      final days = lastSevenDays(DateTime.now());
      final isos = [for (final d in days) MoodRecorder.dateIsoFor(d)];
      var daily = List<int?>.filled(days.length, null);
      try {
        final snap = await _db
            .collection('users')
            .doc(uid)
            .collection('daily_mood')
            .where('date_iso', isGreaterThanOrEqualTo: isos.first)
            .get();
        daily = lastMoodPerDay(snap.docs.map((d) => d.data()), isos);
      } catch (_) {}
      return WeeklyProgress(
        moodScores: moods,
        moodTimes: moodTimes,
        contactDays: contactDays,
        plansAuthored: plans.length,
        plansFollowedUp: followed,
        reminiscenceSessions: reminiscence,
        moodFromDailyMood: true,
        dailyMoods: daily,
        dailyMoodDays: days,
        checkInCount: moods.length,
      );
    }

    return WeeklyProgress(
      moodScores: moods,
      moodTimes: moodTimes,
      contactDays: contactDays,
      plansAuthored: plans.length,
      plansFollowedUp: followed,
      reminiscenceSessions: reminiscence,
    );
  }

  DateTime _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
    return DateTime(2000);
  }
}
