import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/arm/arm_scope.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(AppSettings settings, Widget child) => MaterialApp(
      home: AppSettingsScope(settings: settings, child: child),
    );

UserProfile _profileWith(ArmAssignment? arm) => UserProfile(
      uid: 'u',
      email: 'a@b.com',
      displayName: 'A',
      arm: arm,
    );

void main() {
  group('ArmGate', () {
    testWidgets('renders armA branch when profile.arm == A', (tester) async {
      final settings = AppSettings(profile: _profileWith(ArmAssignment.a));
      await tester.pumpWidget(_wrap(
        settings,
        ArmGate(
          armA: (_) => const Text('A-branch'),
          armB: (_) => const Text('B-branch'),
        ),
      ));
      expect(find.text('A-branch'), findsOneWidget);
      expect(find.text('B-branch'), findsNothing);
    });

    testWidgets('renders armB branch when profile.arm == B', (tester) async {
      final settings = AppSettings(profile: _profileWith(ArmAssignment.b));
      await tester.pumpWidget(_wrap(
        settings,
        ArmGate(
          armA: (_) => const Text('A-branch'),
          armB: (_) => const Text('B-branch'),
        ),
      ));
      expect(find.text('B-branch'), findsOneWidget);
    });

    testWidgets('falls back to armB when arm is missing (guest mode)',
        (tester) async {
      final settings = AppSettings(profile: _profileWith(null));
      await tester.pumpWidget(_wrap(
        settings,
        ArmGate(
          armA: (_) => const Text('A-branch'),
          armB: (_) => const Text('B-branch'),
        ),
      ));
      expect(find.text('B-branch'), findsOneWidget);
    });

    testWidgets('falls back to armB when no profile signed in',
        (tester) async {
      final settings = AppSettings();
      await tester.pumpWidget(_wrap(
        settings,
        ArmGate(
          armA: (_) => const Text('A-branch'),
          armB: (_) => const Text('B-branch'),
        ),
      ));
      expect(find.text('B-branch'), findsOneWidget);
    });
  });
}
