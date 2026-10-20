import 'package:app_demo/features/progress/data/progress_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeeklyProgress', () {
    test('empty constant has zeros', () {
      const e = WeeklyProgress.empty;
      expect(e.moodScores, isEmpty);
      expect(e.contactDays, 0);
      expect(e.plansAuthored, 0);
      expect(e.plansFollowedUp, 0);
      expect(e.reminiscenceSessions, 0);
    });

    test('holds the right shape', () {
      const p = WeeklyProgress(
        moodScores: [3, 4, 5],
        contactDays: 2,
        plansAuthored: 4,
        plansFollowedUp: 3,
        reminiscenceSessions: 1,
      );
      expect(p.moodScores.length, 3);
      expect(p.plansAuthored, 4);
    });
  });

  // 1020e 二.11 (moodRowV2Enabled): the chart reads daily_mood.
  group('lastMoodPerDay', () {
    final days = ProgressRepository.lastSevenDays(DateTime(2026, 10, 20, 9));
    final isos = [
      for (final d in days)
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}',
    ];

    test('the last 7 days, oldest first, today last', () {
      expect(isos.first, '2026-10-14');
      expect(isos.last, '2026-10-20');
      expect(isos, hasLength(7));
    });

    test('the last entry of each day; a day without one is null (never 3)',
        () {
      final rows = [
        {'date_iso': '2026-10-15', 'mood': 4, 'entry_seq_today': 1},
        {'date_iso': '2026-10-15', 'mood': 2, 'entry_seq_today': 2},
        {'date_iso': '2026-10-17', 'mood': 5, 'entry_seq_today': 1},
        {'date_iso': '2026-10-20', 'mood': 1, 'entry_seq_today': 3},
        {'date_iso': '2026-10-20', 'mood': 3, 'entry_seq_today': 1},
        // Out of range / malformed rows are ignored.
        {'date_iso': '2026-10-01', 'mood': 5, 'entry_seq_today': 1},
        {'date_iso': '2026-10-18', 'mood': 9, 'entry_seq_today': 1},
        {'date_iso': '2026-10-19'},
      ];
      expect(ProgressRepository.lastMoodPerDay(rows, isos),
          [null, 2, null, 5, null, null, 1]);
    });

    test('same sequence number: the later responded_at wins', () {
      final rows = [
        {
          'date_iso': '2026-10-16',
          'mood': 2,
          'entry_seq_today': 1,
          'responded_at': DateTime(2026, 10, 16, 9),
        },
        {
          'date_iso': '2026-10-16',
          'mood': 4,
          'entry_seq_today': 1,
          'responded_at': DateTime(2026, 10, 16, 21),
        },
      ];
      expect(ProgressRepository.lastMoodPerDay(rows, isos)[2], 4);
    });

    test('the counts and the summary average skip blank days', () {
      const p = WeeklyProgress(
        moodScores: [3, 3],
        contactDays: 0,
        plansAuthored: 0,
        plansFollowedUp: 0,
        reminiscenceSessions: 0,
        moodFromDailyMood: true,
        dailyMoods: [null, 2, null, 4],
        checkInCount: 2,
      );
      expect(p.checkIns, 2);
      expect(p.moodsForSummary, [2, 4]);
      const old = WeeklyProgress(
        moodScores: [3, 5],
        contactDays: 0,
        plansAuthored: 0,
        plansFollowedUp: 0,
        reminiscenceSessions: 0,
      );
      expect(old.checkIns, 2);
      expect(old.moodsForSummary, [3, 5]);
    });
  });
}
