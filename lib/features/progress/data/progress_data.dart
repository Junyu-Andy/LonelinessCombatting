import 'package:cloud_firestore/cloud_firestore.dart';

/// One week of dashboard inputs for M9. Read by [ProgressRepository] in
/// a single fan-out, then handed to the view.
class WeeklyProgress {
  /// One mood reading per check-in submitted in the past 7 days, oldest
  /// first. Always in 1..5.
  final List<int> moodScores;

  /// Count of check-ins where a non-zero contact proxy was reported.
  final int contactDays;

  /// Action plans authored in the last 7 days.
  final int plansAuthored;

  /// Action plans where the user marked an outcome (happened / partial /
  /// didn't) in the last 7 days. Used as the completion-rate numerator.
  final int plansFollowedUp;

  /// Reminiscence weekly summaries written in the last 7 days.
  final int reminiscenceSessions;

  const WeeklyProgress({
    required this.moodScores,
    required this.contactDays,
    required this.plansAuthored,
    required this.plansFollowedUp,
    required this.reminiscenceSessions,
  });

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
    final moods = recentEvents
        .where((d) => d.data()['name'] == 'check_in_submitted')
        .map((d) => ((d.data()['params'] as Map?)?['mood'] as int?) ?? 3)
        .toList();
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

    return WeeklyProgress(
      moodScores: moods,
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
