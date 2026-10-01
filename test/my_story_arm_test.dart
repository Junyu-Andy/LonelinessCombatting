// The open-ended reflective chat is LLM-only, so My Story hides its entry
// for Arm B. Arm-specific cases need a Phase B build:
//   flutter test --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
//     test/my_story_arm_test.dart
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/my_story/presentation/pages/my_story_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _forced = String.fromEnvironment('FORCE_ARM');

Widget _page() => AppSettingsScope(
      settings: AppSettings(locale: const Locale('zh')),
      child: AuthServiceScope(
        authService: AuthService(available: false),
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: MyStoryPage()),
        ),
      ),
    );

void main() {
  testWidgets('Arm A sees the reflective chat entry', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();
    expect(find.text('反思傾偈'), findsOneWidget);
  }, skip: FeatureFlags.phaseB && _forced != 'A');

  testWidgets('Arm B does not see the reflective chat entry', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();
    expect(find.text('反思傾偈'), findsNothing);
  }, skip: !(FeatureFlags.phaseB && _forced == 'B'));
}
