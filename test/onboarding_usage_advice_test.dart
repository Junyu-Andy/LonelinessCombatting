// T33 — S5 usage advice as an extra last onboarding screen, behind
// app_config/usage_copy.onboardingUsageAdviceEnabled (default off).
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/config/usage_copy.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/onboarding/presentation/pages/agent_onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = UserProfile(uid: 'u', email: 'e', displayName: 'd');
final _advice = find.byKey(const Key('onboarding_usage_advice'));

Future<AppSettings> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final settings = AppSettings(locale: const Locale('zh'), profile: _profile);
  await tester.pumpWidget(AppSettingsScope(
    settings: settings,
    child: AuthServiceScope(
      authService: AuthService(available: false),
      child: const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: [Locale('zh'), Locale('en')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AgentOnboardingPage(),
      ),
    ),
  ));
  await tester.pump();
  return settings;
}

/// Welcome → Siu Yan → Ah Jan (pick 阿珍) → Tung Tung.
Future<void> _toTungTung(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    if (i == 2) {
      await tester.tap(find.text('阿珍（同輩女性）'));
      await tester.pump();
    }
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
  }
}

void main() {
  tearDown(() => UsageCopy.current = const UsageCopy());

  test('switch: default off; only a literal true turns it on', () {
    expect(const UsageCopy().onboardingUsageAdviceEnabled, isFalse);
    expect(UsageCopy.fromMap(const {}).onboardingUsageAdviceEnabled, isFalse);
    expect(
      UsageCopy.fromMap(const {'onboardingUsageAdviceEnabled': 'true'})
          .onboardingUsageAdviceEnabled,
      isFalse,
    );
    expect(
      UsageCopy.fromMap(const {'onboardingUsageAdviceEnabled': true})
          .onboardingUsageAdviceEnabled,
      isTrue,
    );
  });

  testWidgets('off: four screens, Tung Tung is last, no advice',
      (tester) async {
    await _pump(tester);
    await _toTungTung(tester);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('撳「完成」就可以開始同夥伴傾偈。'), findsOneWidget);
    expect(_advice, findsNothing);
  });

  testWidgets('on: S5 screen after Tung Tung, then 完成', (tester) async {
    UsageCopy.current = const UsageCopy({}, true);
    await _pump(tester);
    await _toTungTung(tester);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('撳「完成」就可以開始同夥伴傾偈。'), findsNothing);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(_advice, findsOneWidget);
    expect(find.text(UsageCopy.onboardingUsageAdviceS5), findsOneWidget);
    expect(find.text('撳「完成」就可以開始同夥伴傾偈。'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });
}
