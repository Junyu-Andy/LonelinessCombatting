import 'package:cloud_firestore/cloud_firestore.dart';

import '../../reminiscence/data/reminiscence_themes.dart';

/// Per-week M3 session state surfaced to the My Story tab.
class M3WeekState {
  final ReminiscenceTheme theme;
  final M3SessionStatus status;
  final String? summarySnippet;
  final DateTime? completedAt;

  const M3WeekState({
    required this.theme,
    required this.status,
    this.summarySnippet,
    this.completedAt,
  });

  bool get isCompleted => status == M3SessionStatus.completed;
}

enum M3SessionStatus { notStarted, inProgress, completed }

class MyStoryProgress {
  final List<M3WeekState> weeks;
  final int currentWeekIndex; // 1..totalWeeks

  const MyStoryProgress({
    required this.weeks,
    required this.currentWeekIndex,
  });

  int get totalWeeks => weeks.length;

  M3WeekState get currentWeek =>
      weeks.firstWhere((w) => w.theme.weekIndex == currentWeekIndex,
          orElse: () => weeks.first);

  List<M3WeekState> get completedWeeks =>
      weeks.where((w) => w.isCompleted).toList();

  static MyStoryProgress empty() {
    return MyStoryProgress(
      weeks: [
        for (final t in ReminiscenceTheme.all)
          M3WeekState(theme: t, status: M3SessionStatus.notStarted),
      ],
      currentWeekIndex: 1,
    );
  }
}

/// Reads M3 progress from Firestore. The existing M3 schema stores each
/// week as `users/{uid}/memory/m3_reminiscence_w{n}/entries/{entryId}`;
/// presence of *any* entry counts as completed (mirrors what the
/// reminiscence landing page already uses for its tick marks).
class MyStoryProgressReader {
  MyStoryProgressReader({required this.available});
  final bool available;

  Future<MyStoryProgress> read({
    required String uid,
    required DateTime referenceDate,
    DateTime? userCreatedAt,
  }) async {
    if (!available) return MyStoryProgress.empty();

    final allThemes = ReminiscenceTheme.all;
    final futures = allThemes.map((t) => _readWeek(uid, t.weekIndex));
    final perWeek = await Future.wait(futures);

    final weeks = <M3WeekState>[];
    for (var i = 0; i < allThemes.length; i++) {
      final theme = allThemes[i];
      final hit = perWeek[i];
      weeks.add(M3WeekState(
        theme: theme,
        status: hit == null
            ? M3SessionStatus.notStarted
            : M3SessionStatus.completed,
        summarySnippet: hit?.summarySnippet,
        completedAt: hit?.completedAt,
      ));
    }

    // Current week = onboarding week + elapsed weeks, clamped to total.
    final start = userCreatedAt ?? referenceDate;
    final daysIn = referenceDate.difference(start).inDays;
    final computed = (daysIn ~/ 7) + 1;
    final clamped = computed.clamp(1, allThemes.length).toInt();

    return MyStoryProgress(weeks: weeks, currentWeekIndex: clamped);
  }

  Future<_WeekHit?> _readWeek(String uid, int weekIndex) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('memory')
          .doc('m3_reminiscence_w$weekIndex')
          .collection('entries')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final data = snap.docs.first.data();
      final raw = data['createdAt'];
      DateTime? when;
      if (raw is Timestamp) {
        when = raw.toDate();
      } else if (raw is String) {
        when = DateTime.tryParse(raw);
      }
      final snippet = (data['summary'] as String?) ??
          (data['endSummary'] as String?) ??
          (data['text'] as String?);
      return _WeekHit(
        completedAt: when,
        summarySnippet: snippet == null
            ? null
            : (snippet.length > 60 ? '${snippet.substring(0, 60)}…' : snippet),
      );
    } catch (_) {
      return null;
    }
  }
}

class _WeekHit {
  final DateTime? completedAt;
  final String? summarySnippet;
  const _WeekHit({this.completedAt, this.summarySnippet});
}
