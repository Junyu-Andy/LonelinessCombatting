import 'package:app_demo/features/action_loop/data/action_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActionPlan round-trip', () {
    test('serialises core fields to a map and parses them back', () {
      final plan = ActionPlan(
        action: '打畀阿May',
        whenText: '聽朝',
        whereText: '屋企',
        whoWith: '阿May',
        fallback: '下午再試',
        armCode: 'A',
        createdAt: DateTime.utc(2026, 5, 14, 9),
      );
      final map = plan.toMap();
      final round = ActionPlan.fromMap('p1', map);
      expect(round.id, 'p1');
      expect(round.action, '打畀阿May');
      expect(round.whenText, '聽朝');
      expect(round.armCode, 'A');
      expect(round.outcome, isNull);
    });

    test('parses outcome enum', () {
      final plan = ActionPlan(
        action: 'a',
        whenText: 'w',
        whereText: 'w',
        whoWith: 'w',
        fallback: 'f',
        armCode: 'B',
        createdAt: DateTime.utc(2026, 5, 14),
        outcome: FollowUpOutcome.partial,
      );
      final round = ActionPlan.fromMap('p2', plan.toMap());
      expect(round.outcome, FollowUpOutcome.partial);
    });

    test('FollowUpOutcomeX.tryParse handles unknown / null', () {
      expect(FollowUpOutcomeX.tryParse(null), isNull);
      expect(FollowUpOutcomeX.tryParse('bogus'), isNull);
      expect(FollowUpOutcomeX.tryParse('happened'),
          FollowUpOutcome.happened);
    });
  });
}
