// 10/19 — 測試員工具 → 每週問卷測試: every bundle W1…W7 can be opened at
// once as a no-save preview, and (Phase B build) the in-app clock can jump
// to a bundle's day so the real home card shows.  Synthetic tester account,
// no Firebase.  The simulate test runs in the Phase B suite
// (tool/ci_flutter_tests.sh).  10/20 item 98: with reminders v2 on, W5–W7
// push at 10:00 like W1–W4.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/time/app_clock.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/settings/presentation/pages/tester_weekly_bundle_page.dart';
import 'package:app_demo/features/w8/data/w8_store.dart';
import 'package:app_demo/features/w8/presentation/w8_flow_page.dart';
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
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
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

  testWidgets('T35: the W8 card previews the W8 flow (nothing saved)',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('tester_weekly_W8')), findsOneWidget);
    await tester.ensureVisible(
        find.byKey(const Key('tester_weekly_preview_W8')));
    await tester.tap(find.byKey(const Key('tester_weekly_preview_W8')));
    await tester.pumpAndSettle();
    final flow = tester.widget<W8FlowPage>(find.byType(W8FlowPage));
    expect(flow.store, isA<MemoryW8Store>(), reason: 'nothing is saved');
    expect(find.text('今次一共有 5 部分，大約 8 分鐘，可以隨時停，下次由停低嗰度繼續。'),
        findsOneWidget);
  });

  testWidgets('T35: 模擬 W8 jumps the clock to day 56 at the push hour + 30',
      (tester) async {
    await _pump(tester);
    await tester.ensureVisible(
        find.byKey(const Key('tester_weekly_simulate_W8')));
    await tester.tap(find.byKey(const Key('tester_weekly_simulate_W8')));
    await tester.pumpAndSettle();
    // W0 2026-10-12 → day 56 = 12/7; weeklyPushHour default 10.
    expect(AppClock.now().difference(DateTime(2026, 12, 7, 10, 30))
        .inMinutes.abs(), lessThan(2));
  }, skip: !FeatureFlags.phaseB);

  testWidgets('default (Phase A) build: 模擬 is off and says why',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('tester_weekly_simulate_blocked')),
        findsOneWidget);
    final btn = tester.widget<OutlinedButton>(
        find.byKey(const Key('tester_weekly_simulate_W1')));
    expect(btn.onPressed, isNull);
  }, skip: FeatureFlags.phaseB);

  testWidgets('Phase B: 模擬 W1 jumps the clock to day 7 10:30 and goes home',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('tester_weekly_simulate_blocked')),
        findsNothing);
    await tester.tap(find.byKey(const Key('tester_weekly_simulate_W1')));
    await tester.pumpAndSettle();
    expect(AppClock.instance.isSimulated, isTrue);
    final now = AppClock.now();
    // W0 2026-10-12 + 7 days = 10/19, push at the default weeklyPushHour
    // (10 since 10/20 item 98), +30 min.
    expect(now.difference(DateTime(2026, 10, 19, 10, 30)).inMinutes.abs(),
        lessThan(2));
    expect(find.byType(TesterWeeklyBundlePage), findsNothing,
        reason: 'back to the first route (屋企)');
  }, skip: !FeatureFlags.phaseB);

  testWidgets('10/20 item 98, reminders v2 on: W5–W7 show 10:00 like W1–W4 '
      '(weeklyPushHour not read); 模擬 W5 goes to day 35 10:30',
      (tester) async {
    PhaseBConfig.current =
        const PhaseBConfig(weeklyScheduleV2Enabled: true, weeklyPushHour: 20);
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(weeklyReminderV2Enabled: true);
    await _pump(tester);
    // W0 2026-10-12: day 35 = 11/16, day 42 = 11/23, day 49 = 11/30.
    expect(find.text('W5 · 第 35 天 · 11月16日 10:00 開'), findsOneWidget);
    expect(find.text('W6 · 第 42 天 · 11月23日 10:00 開'), findsOneWidget);
    expect(find.text('W7 · 第 49 天 · 11月30日 10:00 開'), findsOneWidget);
    expect(find.text('W1 · 第 7 天 · 10月19日 10:00 開'), findsOneWidget);
    for (var i = 1; i <= 7; i++) {
      expect(
          find.descendant(
              of: find.byKey(Key('tester_weekly_W$i')),
              matching: find.textContaining('20:00')),
          findsNothing,
          reason: 'W$i');
    }
    // T35: W8 is pushed at weeklyPushHour (handover 1021-W8 一 (6)).
    expect(find.text('W8 · 最後一份問卷 · 第 56 天 · 12月7日 20:00 推送'),
        findsOneWidget);
    if (!FeatureFlags.phaseB) return;
    await tester.ensureVisible(
        find.byKey(const Key('tester_weekly_simulate_W5')));
    await tester.tap(find.byKey(const Key('tester_weekly_simulate_W5')));
    await tester.pumpAndSettle();
    expect(AppClock.now().difference(DateTime(2026, 11, 16, 10, 30))
        .inMinutes.abs(), lessThan(2));
  });
}
