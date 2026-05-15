import '../../reminiscence/data/m3_session_store.dart';
import '../../reminiscence/data/reminiscence_themes.dart';

/// Per-week M3 session state surfaced to the My Story tab.
class M3WeekState {
  final ReminiscenceTheme theme;
  final MyStorySessionStatus status;
  final String? summarySnippet;
  final DateTime? completedAt;

  const M3WeekState({
    required this.theme,
    required this.status,
    this.summarySnippet,
    this.completedAt,
  });

  bool get isCompleted => status == MyStorySessionStatus.completed;
}

/// Local UI status alias — kept distinct from [M3SessionStatus] so the
/// My Story rendering layer can evolve without churning the store
/// schema.
enum MyStorySessionStatus { notStarted, inProgress, completed }

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
          M3WeekState(theme: t, status: MyStorySessionStatus.notStarted),
      ],
      currentWeekIndex: 1,
    );
  }
}

/// Reads M3 progress from the new single-doc schema at
/// `users/{uid}/memory/m3_reminiscence/sessions/week_{n}`.
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
    final store = M3SessionStore(available: available);
    final docs = await store.readAll(
      uid: uid,
      weekIndexes: [for (final t in allThemes) t.weekIndex],
    );

    final weeks = <M3WeekState>[];
    for (final theme in allThemes) {
      final doc = docs[theme.weekIndex];
      final status = _mapStatus(doc?.status);
      final summary = doc?.callbackSummary;
      weeks.add(M3WeekState(
        theme: theme,
        status: status,
        summarySnippet: summary == null
            ? null
            : (summary.length > 60 ? '${summary.substring(0, 60)}…' : summary),
        completedAt: doc?.completedAt,
      ));
    }

    // Current week = onboarding week + elapsed weeks, clamped to total.
    final start = userCreatedAt ?? referenceDate;
    final daysIn = referenceDate.difference(start).inDays;
    final computed = (daysIn ~/ 7) + 1;
    final clamped = computed.clamp(1, allThemes.length).toInt();

    return MyStoryProgress(weeks: weeks, currentWeekIndex: clamped);
  }

  MyStorySessionStatus _mapStatus(M3SessionStatus? raw) {
    switch (raw) {
      case M3SessionStatus.completed:
        return MyStorySessionStatus.completed;
      case M3SessionStatus.inProgress:
        return MyStorySessionStatus.inProgress;
      case M3SessionStatus.notStarted:
      case null:
        return MyStorySessionStatus.notStarted;
    }
  }
}
