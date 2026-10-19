// 10/16 — the 通通 slide of 「介紹三個夥伴」 asks for interests only when
// nobody has recorded them: not while the researcher records the intake
// (`researcherIntakeEnabled`, Q2 writes `interests`), and not when the
// profile already carries interests (the elder answered the short intake
// page just before).  In both cases 完成 keeps the stored interests.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/onboarding/presentation/pages/agent_onboarding_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _p(List<String> interests) => UserProfile(
      uid: 'u',
      email: 'e',
      displayName: 'd',
      consent: const ConsentFlags(functionalData: true),
      ahJanAhBakVariant: AgentGenderVariant.feminine, // pairing pre-set
      interests: interests,
    );

Future<AppSettings> _open(WidgetTester tester,
    {required bool researcherIntakeOn, required List<String> interests}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final settings = AppSettings()..profile = _p(interests);
  await tester.pumpWidget(AnalyticsScope(
    analytics: AnalyticsService(firebaseReady: false),
    child: AuthServiceScope(
      authService: AuthService(available: false),
      child: AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: AgentOnboardingPage(researcherIntakeOn: researcherIntakeOn),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  // Welcome → 小欣 → pairing (pre-set) → 通通.
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
  }
  return settings;
}

void main() {
  testWidgets('researcher records the intake: the 通通 slide asks nothing; '
      '完成 keeps the recorded interests', (tester) async {
    final settings =
        await _open(tester, researcherIntakeOn: true, interests: ['news']);
    expect(find.text('通通'), findsWidgets);
    expect(find.text('你鍾意啲咩？'), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(settings.profile!.interests, ['news']);
    expect(settings.profile!.onboardingCompletedAt, isNotNull);
  });

  testWidgets('switch off but interests already on the profile (short '
      'intake page): no chips, interests kept', (tester) async {
    final settings = await _open(tester,
        researcherIntakeOn: false, interests: ['mahjong', 'hiking']);
    expect(find.text('你鍾意啲咩？'), findsNothing);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(settings.profile!.interests, ['mahjong', 'hiking']);
  });

  testWidgets('switch off and nothing recorded: the chips are asked as '
      'before', (tester) async {
    final settings =
        await _open(tester, researcherIntakeOn: false, interests: const []);
    expect(find.text('你鍾意啲咩？'), findsOneWidget);
    expect(find.byType(FilterChip), findsWidgets);
    await tester.tap(find.widgetWithText(FilterChip, '行山'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(settings.profile!.interests, ['hiking']);
  });
}
