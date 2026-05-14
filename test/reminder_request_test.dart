import 'package:app_demo/core/reminders/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReminderRequest', () {
    test('serialises core fields', () {
      final r = ReminderRequest(
        kind: 'm7_followup',
        fireAt: DateTime.utc(2026, 5, 15, 9),
        titleZh: '件事點呀？',
        titleEn: 'How did it go?',
        bodyZh: '你之前計劃做：打畀阿May',
        bodyEn: 'Your plan: call May',
        linkedDocId: 'plan_abc',
      );
      final m = r.toMap();
      expect(m['kind'], 'm7_followup');
      expect(m['fireAt'], '2026-05-15T09:00:00.000Z');
      expect(m['linkedDocId'], 'plan_abc');
      expect(m['delivered'], false);
      // createdAt is a FieldValue.serverTimestamp; we don't assert its
      // exact shape, just that it's present so the repo write succeeds.
      expect(m.containsKey('createdAt'), true);
    });
  });
}
