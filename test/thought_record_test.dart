import 'package:app_demo/features/reflective_dialogue/data/thought_record.dart';
import 'package:flutter_test/flutter_test.dart';

// The legacy M4 cognitive_restructure feature folder was removed in
// Sprint 3 and the thought-record exercise re-emerged under Ah Jan /
// Ah Bak's reflective dialogue as the three-field naming tool. The
// round-trip test was updated to cover the new shape.
void main() {
  group('ThoughtRecord round-trip', () {
    test('serialises core fields and parses them back', () {
      final r = ThoughtRecord(
        thought: '打畀阿女只會煩到佢',
        oneReasonTrue: '佢上次無覆我',
        anotherWayToLook: '佢平時都有主動搵我，可能淨係忙',
        createdAt: DateTime.utc(2026, 5, 14),
        originSurface: 'reflective_dialogue',
      );
      final round = ThoughtRecord.fromMap('r1', r.toMap());
      expect(round.id, 'r1');
      expect(round.thought, '打畀阿女只會煩到佢');
      expect(round.oneReasonTrue, '佢上次無覆我');
      expect(round.anotherWayToLook, '佢平時都有主動搵我，可能淨係忙');
      expect(round.originSurface, 'reflective_dialogue');
    });

    test('handles missing optional fields', () {
      final round = ThoughtRecord.fromMap('r2', {
        'thought': 't',
        'oneReasonTrue': 'f',
        'anotherWayToLook': 'a',
      });
      expect(round.thought, 't');
      expect(round.oneReasonTrue, 'f');
      expect(round.anotherWayToLook, 'a');
      expect(round.originSurface, isNull);
    });
  });
}
