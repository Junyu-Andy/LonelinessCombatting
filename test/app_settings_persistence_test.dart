// T37 fix 2 — 顯示設定 (font size, high contrast) and the two 通知 switches
// (安靜時段, 語音讀出內容) persist on the device with shared_preferences and
// come back when AppSettings is rebuilt from storage (= the App reopened).
// No switch: a bug fix.  Options and wording are unchanged.
// 10/20 (dev-tasks-1020 §H): 安靜時段 and 今日休息 left the page (quiet hours
// fixed on); 高對比 moved to 自己 → 我的設定 → 顯示.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nothing stored: the defaults', () async {
    final s = await AppSettings.restore();
    expect(s.fontScale, AppFontScale.standard, reason: '標準');
    expect(s.highContrast, isFalse);
    expect(s.quietHours, isTrue, reason: '安靜時段 defaults on, as before');
    expect(s.voiceReadback, isFalse, reason: '語音讀出內容 defaults off');
  });

  test('set, then rebuild from storage: the same values', () async {
    final s = await AppSettings.restore();
    s.fontScale = AppFontScale.xLarge;
    s.highContrast = true;
    s.quietHours = false;
    s.voiceReadback = true;
    await pumpEventQueue(); // the writes are fire-and-forget

    final reopened = await AppSettings.restore();
    expect(reopened.fontScale, AppFontScale.xLarge, reason: '特大');
    expect(reopened.highContrast, isTrue);
    expect(reopened.quietHours, isFalse);
    expect(reopened.voiceReadback, isTrue);
  });

  test('every font size round-trips', () async {
    for (final scale in AppFontScale.values) {
      (await AppSettings.restore()).fontScale = scale;
      await pumpEventQueue();
      expect((await AppSettings.restore()).fontScale, scale, reason: '$scale');
    }
  });

  test('switching back is stored too', () async {
    final s = await AppSettings.restore();
    s.highContrast = true;
    s.highContrast = false;
    s.quietHours = false;
    s.quietHours = true;
    await pumpEventQueue();
    final reopened = await AppSettings.restore();
    expect(reopened.highContrast, isFalse);
    expect(reopened.quietHours, isTrue);
  });

  test('unknown or wrongly typed stored values fall back to the defaults',
      () async {
    SharedPreferences.setMockInitialValues({
      AppSettings.keyFontScale: 'huge',
      AppSettings.keyHighContrast: 'yes',
      AppSettings.keyQuietHours: 3,
    });
    final s = await AppSettings.restore();
    expect(s.fontScale, AppFontScale.standard);
    expect(s.highContrast, isFalse);
    expect(s.quietHours, isTrue);
  });

  // 1020c (appFontScaleOnlyEnabled): the first run with the switch on keeps
  // the size the elder saw (phone × App, capped), never smaller, as the
  // App's own 字號 — once; after that the phone's size no longer counts.
  test('app-only 字號: settled once to the size the elder saw', () async {
    final s = await AppSettings.restore();
    expect(s.appOnlyScaleSettled, isFalse);
    // Phone text 1.3 × 標準 showed 1.30 (the cap) until now.
    expect(s.appOnlyScaleFor(1.3), AppFontScale.xLarge);
    s.settleAppOnlyScale(1.3);
    expect(s.fontScale, AppFontScale.xLarge);
    expect(s.appOnlyScaleSettled, isTrue);
    // Settled: the phone's size no longer moves it, and it runs once.
    expect(s.appOnlyScaleFor(1.0), AppFontScale.xLarge);
    s.fontScale = AppFontScale.large; // the elder picks a size later
    s.settleAppOnlyScale(2.0);
    expect(s.fontScale, AppFontScale.large);
    await pumpEventQueue();

    final reopened = await AppSettings.restore();
    expect(reopened.appOnlyScaleSettled, isTrue);
    expect(reopened.fontScale, AppFontScale.large);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('display.appOnlyScaleSettled'), isTrue);
  });

  test('app-only 字號: phone at normal size keeps 標準', () async {
    final s = await AppSettings.restore();
    s.settleAppOnlyScale(1.0);
    expect(s.fontScale, AppFontScale.standard);
  });

  test('no store at all (plugin unavailable): defaults, setters still work',
      () {
    final s = AppSettings.fromStore(null);
    expect(s.fontScale, AppFontScale.standard);
    s.fontScale = AppFontScale.large;
    s.voiceReadback = true;
    expect(s.fontScale, AppFontScale.large);
    expect(s.voiceReadback, isTrue);
  });

  test('the stored keys and values are stable (what is on the device)',
      () async {
    final s = await AppSettings.restore();
    s.fontScale = AppFontScale.large;
    s.highContrast = true;
    s.quietHours = false;
    s.voiceReadback = true;
    await pumpEventQueue();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('display.fontScale'), 'large');
    expect(prefs.getBool('display.highContrast'), isTrue);
    expect(prefs.getBool('notifications.quietHours'), isFalse);
    expect(prefs.getBool('notifications.voiceReadback'), isTrue);
  });

  testWidgets('字體大小 on 自己 and 高對比 under 我的設定 write through to '
      'storage; 10/20: no 安靜時段 / 今日休息 / 高對比 on the first level',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = await AppSettings.restore();
    await tester.pumpWidget(AppSettingsScope(
      settings: settings,
      child: AuthServiceScope(
        authService: AuthService(available: false),
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: SettingsPage(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    Finder switchIn(String title) => find.descendant(
          of: find.ancestor(of: find.text(title), matching: find.byType(Card)),
          matching: find.byType(Switch),
        );

    expect(find.text('顯示設定'), findsOneWidget);
    expect(find.text('標準'), findsOneWidget);
    expect(find.text('特大'), findsOneWidget);
    // dev-tasks-1020 §H: none of these on the first level.
    expect(find.text('高對比模式'), findsNothing);
    expect(find.text('安靜時段'), findsNothing);
    expect(find.text('今日休息'), findsNothing);
    expect(find.text('通知'), findsNothing);
    expect(find.text('語音讀出內容'), findsNothing);
    expect(find.byKey(const Key('settings_my_settings')), findsOneWidget);

    await tester.tap(find.text('特大'));
    await tester.pumpAndSettle();
    expect(settings.fontScale, AppFontScale.xLarge);

    // 自己 → 我的設定 → 顯示 → 高對比模式.
    await tester.tap(find.byKey(const Key('settings_my_settings')));
    await tester.pumpAndSettle();
    expect(find.text('顯示'), findsOneWidget);
    expect(tester.widget<Switch>(switchIn('高對比模式')).value, isFalse);
    await tester.tap(switchIn('高對比模式'));
    await tester.pumpAndSettle();
    expect(settings.highContrast, isTrue);
    expect(settings.quietHours, isTrue, reason: 'no switch; stays on');
    expect(settings.voiceReadback, isFalse, reason: 'row hidden, value untouched');

    // "Close and reopen the App".
    final reopened = await AppSettings.restore();
    expect(reopened.fontScale, AppFontScale.xLarge);
    expect(reopened.highContrast, isTrue);
    expect(reopened.quietHours, isTrue);
    expect(reopened.voiceReadback, isFalse);
  });
}
