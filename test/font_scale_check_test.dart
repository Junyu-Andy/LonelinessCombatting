// 10/19 — 自己 → 字體大小: a pick changes the whole App at once, so there is
// no preview line; instead the card asks once whether the new size is too
// big (or too small), with a button back to the previous level.  Optional:
// 「啱啱好」 just closes it.  Synthetic account, no Firebase.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppSettings> _pump(WidgetTester tester, AppFontScale start) async {
  tester.view.physicalSize = const Size(1080, 8000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettings(locale: const Locale('zh'), fontScale: start)
    ..profile = const UserProfile(
        uid: 'u1', email: 'u1@example.invalid', displayName: '黃太');
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
  return settings;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no preview line, no question before a pick', (tester) async {
    await _pump(tester, AppFontScale.standard);
    expect(find.textContaining('預覽'), findsNothing);
    expect(find.byKey(const Key('font_scale_check')), findsNothing);
  });

  testWidgets('bigger → 會唔會太大？; 返回 restores the old level',
      (tester) async {
    final settings = await _pump(tester, AppFontScale.standard);
    await _tap(tester, 'font_scale_xLarge');
    expect(settings.fontScale, AppFontScale.xLarge);
    expect(find.text('字大咗。會唔會太大？'), findsOneWidget);
    expect(find.text('太大，返回「標準」'), findsOneWidget);
    await _tap(tester, 'font_scale_undo');
    expect(settings.fontScale, AppFontScale.standard);
    expect(find.byKey(const Key('font_scale_check')), findsNothing);
  });

  testWidgets('smaller → 會唔會太細？; 啱啱好 keeps it and closes',
      (tester) async {
    final settings = await _pump(tester, AppFontScale.large);
    await _tap(tester, 'font_scale_slightlyLarge');
    expect(find.text('字細咗。會唔會太細？'), findsOneWidget);
    expect(find.text('太細，返回「大」'), findsOneWidget);
    await _tap(tester, 'font_scale_keep');
    expect(settings.fontScale, AppFontScale.slightlyLarge);
    expect(find.byKey(const Key('font_scale_check')), findsNothing);
  });

  testWidgets('tapping the level already on asks nothing', (tester) async {
    await _pump(tester, AppFontScale.large);
    await _tap(tester, 'font_scale_large');
    expect(find.byKey(const Key('font_scale_check')), findsNothing);
  });
}
