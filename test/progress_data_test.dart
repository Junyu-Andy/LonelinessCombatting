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
}
