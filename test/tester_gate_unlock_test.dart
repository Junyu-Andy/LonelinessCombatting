// 10/19 — tester tools without a PIN build: an isTester account (admin-only
// field) with app_config/feature_flags.testerToolsEnabled unlocks by tapping
// the version line 7×.  Participants never unlock and see no hint.
// Synthetic accounts, no Firebase.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/testing/tester_gate.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/settings/presentation/pages/support_about_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _profile({required bool tester}) => UserProfile(
      uid: 't1',
      email: 't1@example.invalid',
      displayName: 'T1',
      isTester: tester,
    );

Future<void> _pump(WidgetTester tester, {required bool isTester}) async {
  final settings = AppSettings(locale: const Locale('zh'))
    ..profile = _profile(tester: isTester);
  await tester.pumpWidget(AppSettingsScope(
    settings: settings,
    child: const MaterialApp(
      locale: Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: SupportAboutPage(version: '1.0.0+4'),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapVersion7(WidgetTester tester) async {
  final version = find.textContaining('版本 ');
  for (var i = 0; i < 7; i++) {
    await tester.tap(version);
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(TesterGate.resetForTest);
  tearDown(() {
    TesterGate.resetForTest();
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
  });

  group('canUnlockAsTester', () {
    test('needs both the tester account and the server switch', () {
      expect(
          TesterGate.canUnlockAsTester(isTester: true, testerToolsEnabled: true),
          isTrue);
      expect(
          TesterGate.canUnlockAsTester(
              isTester: true, testerToolsEnabled: false),
          isFalse);
      expect(
          TesterGate.canUnlockAsTester(
              isTester: false, testerToolsEnabled: true),
          isFalse);
    });

    test('flag parses only a literal true', () {
      expect(
          RemoteFeatureFlags.fromMap({'testerToolsEnabled': true})
              .testerToolsEnabled,
          isTrue);
      expect(
          RemoteFeatureFlags.fromMap({'testerToolsEnabled': 'true'})
              .testerToolsEnabled,
          isFalse);
      expect(RemoteFeatureFlags.fromMap(const {}).testerToolsEnabled, isFalse);
    });
  });

  testWidgets('tester + switch on: 7 taps unlock without a PIN',
      (tester) async {
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(testerToolsEnabled: true);
    await _pump(tester, isTester: true);
    await _tapVersion7(tester);
    expect(TesterGate.unlocked.value, isTrue);
    expect(find.byType(AlertDialog), findsNothing, reason: 'no PIN dialog');
    expect(find.textContaining('已解鎖'), findsOneWidget);
  });

  testWidgets('tester + switch off: stays locked and says what is missing',
      (tester) async {
    await _pump(tester, isTester: true);
    await _tapVersion7(tester);
    expect(TesterGate.unlocked.value, isFalse);
    expect(find.textContaining('testerToolsEnabled'), findsOneWidget);
  });

  testWidgets('participant: stays locked, no dialog, no hint', (tester) async {
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(testerToolsEnabled: true);
    await _pump(tester, isTester: false);
    await _tapVersion7(tester);
    expect(TesterGate.unlocked.value, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });
}
