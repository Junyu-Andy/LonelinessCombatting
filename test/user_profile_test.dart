import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile arm + consent round-trip', () {
    test('serialises and deserialises arm code', () {
      final profile = UserProfile(
        uid: 'u1',
        email: 'a@b.com',
        displayName: '阿明',
        arm: ArmAssignment.a,
      );
      final round = UserProfile.fromMap('u1', profile.toMap());
      expect(round.arm, ArmAssignment.a);
    });

    test('handles missing arm gracefully (legacy accounts)', () {
      final round = UserProfile.fromMap('u2', {
        'email': 'a@b.com',
        'displayName': '阿明',
      });
      expect(round.arm, isNull);
    });

    test('tiered consent flags round-trip independently', () {
      final profile = UserProfile(
        uid: 'u1',
        email: 'a@b.com',
        displayName: '阿明',
        consent: ConsentFlags(
          functionalData: true,
          transcriptRetention: false,
          acceptedAt: DateTime.utc(2026, 5, 14),
        ),
      );
      final round = UserProfile.fromMap('u1', profile.toMap());
      expect(round.consent.functionalData, true);
      expect(round.consent.transcriptRetention, false);
      expect(round.consent.acceptedAt, DateTime.utc(2026, 5, 14));
    });

    test('copyWith preserves arm + consent when not specified', () {
      final original = UserProfile(
        uid: 'u1',
        email: 'a@b.com',
        displayName: '阿明',
        arm: ArmAssignment.b,
        consent: const ConsentFlags(functionalData: true),
      );
      final copy = original.copyWith(displayName: '阿華');
      expect(copy.arm, ArmAssignment.b);
      expect(copy.consent.functionalData, true);
    });
  });
}
