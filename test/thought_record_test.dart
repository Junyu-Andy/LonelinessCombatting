import 'package:app_demo/features/cognitive_restructure/data/thought_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThoughtRecord round-trip', () {
    test('serialises core fields and parses them back', () {
      final r = ThoughtRecord(
        thought: '打畀阿女只會煩到佢',
        thoughtType: 'mindReading',
        evidenceFor: '佢上次無覆我',
        evidenceAgainst: '佢平時都有主動搵我',
        alternative: '佢可能淨係忙',
        experiment: '聽朝先傳個短訊',
        armCode: 'A',
        createdAt: DateTime.utc(2026, 5, 14),
      );
      final round = ThoughtRecord.fromMap('r1', r.toMap());
      expect(round.id, 'r1');
      expect(round.thought, '打畀阿女只會煩到佢');
      expect(round.thoughtType, 'mindReading');
      expect(round.experiment, '聽朝先傳個短訊');
      expect(round.armCode, 'A');
      expect(round.linkedActionPlanId, isNull);
    });

    test('handles missing optional fields', () {
      final round = ThoughtRecord.fromMap('r2', {
        'thought': 't',
        'evidenceFor': 'f',
        'evidenceAgainst': 'a',
        'arm': 'B',
      });
      expect(round.alternative, isNull);
      expect(round.experiment, isNull);
      expect(round.thoughtType, isNull);
      expect(round.armCode, 'B');
    });
  });
}
