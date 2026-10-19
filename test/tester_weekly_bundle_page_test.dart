// 10/19 — 測試員工具 → 每週問卷測試: every bundle W1…W7 can be opened at
// once as a no-save preview, and (Phase B build) the in-app clock can jump
// to a bundle's day so the real home card shows.  Synthetic tester account,
// no Firebase.  The simulate test runs in the Phase B suite
// (tool/ci_flutter_tests.sh).
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/time/app_clock.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/settings/presentation/pages/tester_weekly_bundle_page.dart';
import 'package:app_demo/features/weekly_bundle/presentation/weekly_bundle_flow_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _tester() => UserProfile(
      uid: 't1',
      email: 't1@example.invalid',
      displayName: 'T1',
      isTester: true,
      cohort: 'pilot',
      w0Date: '2026-10-12',
    );

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettings(locale: const Locale('zh'))..profile = _tester();
  await tester.pumpWidget(AppSettingsScope(
    settings: settings,
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // A home route underneath, as in the App (屋企 → 自己 → tester page).
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const TesterWeeklyBundlePage())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => PhaseBConfig.current =
      const PhaseBConfig(weeklyScheduleV2Enabled: true));
  tearDown(() {
    PhaseBConfig.current = const PhaseBConfig();
    AppClock.instance.clear();
  });

  testWidgets('lists W1…W7; 直接打開 opens the real flow as a preview',
      (tester) async {
    await _pump(tester);
    for (final id in ['W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7']) {
      expect(find.byKey(Key('tester_weekly_$id')), findsOneWidget, reason: id);
    }
    // W1: DJG-ES → Weekly PR → PGIC (social probe switch off here).
    expect(find.text('最近嘅感受 → 今個禮拜同夥伴傾偈嘅感覺 → 同開始用嗰時比較'),
        findsWidgets);

    await tester.tap(find.byKey(const Key('tester_weekly_preview_W1')));
    await tester.pumpAndSettle();
    final flow = tester.widget<WeeklyBundleFlowPage>(
        find.byType(WeeklyBundleFlowPage));
    expect(flow.preview, isTrue, reason: 'nothing is saved');
    expect(flow.bundle.id, 'W1');
    expect(find.textContaining('今次一共有 3 部分'), findsOneWidget);
  });

  testWidgets('default (Phase A) build: 模擬 is off and says why',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('tester_weekly_simulate_blocked')),
        findsOneWidget);
    final btn = tester.widget<OutlinedButton>(
        find.byKey(const Key('tester_weekly_simulate_W1')));
    expect(btn.onPressed, isNull);
  }, skip: FeatureFlags.phaseB);

  testWidgets('Phase B: 模擬 W1 jumps the clock to day 7 20:30 and goes home',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('tester_weekly_simulate_blocked')),
        findsNothing);
    await tester.tap(find.byKey(const Key('tester_weekly_simulate_W1')));
    await tester.pumpAndSettle();
    expect(AppClock.instance.isSimulated, isTrue);
    final now = AppClock.now();
    // W0 2026-10-12 + 7 days = 10/19, push 20:00, +30 min.
    expect(now.difference(DateTime(2026, 10, 19, 20, 30)).inMinutes.abs(),
        lessThan(2));
    expect(find.byType(TesterWeeklyBundlePage), findsNothing,
        reason: 'back to the first route (屋企)');
  }, skip: !FeatureFlags.phaseB);
}
