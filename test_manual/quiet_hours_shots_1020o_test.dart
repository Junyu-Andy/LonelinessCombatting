// 1020o 第三节 — screenshots of 自己 → 我的設定 → 「安靜時段」 for Junyu (style
// only; the wording is from the task): the page, the 「由」 picker open (and
// the 「到」 picker once), on a 360 × 800 phone at 標準 (×1.06) and 特大
// (×1.30) and an 820 × 1180 iPad at ×1.06, normal and high contrast.  Not
// part of CI.
//
//   flutter test test_manual/quiet_hours_shots_1020o_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1020o-shots/quiethours/*.png.  Needs the
// WenQuanYi Zen Hei font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc)
// for the Chinese text; without SHOTS nothing is drawn.  Synthetic
// profile; nothing is written anywhere (in-memory store).
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/settings/data/quiet_hours_store.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1020o-shots/quiethours';

Future<void> _loadFonts() async {
  final cjk = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!cjk.existsSync()) fail('needs ${cjk.path}');
  final bytes = ByteData.sublistView(cjk.readAsBytesSync());
  for (final family in ['NotoSerifHK', 'NotoSansHK']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons =
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

/// The App theme, with the button labels given the Chinese test font: the
/// App's button styles name no font (the phone's own font is used), which
/// the test renderer draws as boxes.  Drawing only; nothing else changes.
ThemeData _shotTheme(ThemeData t) {
  ButtonStyle? withFont(ButtonStyle? s) {
    final ts = s?.textStyle?.resolve(const {});
    if (s == null || ts == null) return s;
    return s.copyWith(
        textStyle:
            WidgetStatePropertyAll(ts.copyWith(fontFamily: 'NotoSansHK')));
  }

  return t.copyWith(
    filledButtonTheme:
        FilledButtonThemeData(style: withFont(t.filledButtonTheme.style)),
    elevatedButtonTheme:
        ElevatedButtonThemeData(style: withFont(t.elevatedButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: withFont(t.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: withFont(t.textButtonTheme.style)),
  );
}

const _profile = UserProfile(
  uid: 'synthetic-shots',
  email: 'shots@test.invalid',
  displayName: '陳婆婆',
  arm: ArmAssignment.b,
  cohort: 'rct',
);

Future<void> _open(WidgetTester tester,
    {required Size size,
    required double dpr,
    required double scale,
    required bool highContrast}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = AppSettings(locale: const Locale('zh'), profile: _profile)
    ..highContrast = highContrast;
  await tester.pumpWidget(AppSettingsScope(
    settings: settings,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _shotTheme(highContrast ? AppTheme.highContrast : AppTheme.light),
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: MySettingsPage(quietHoursStore: InMemoryQuietHoursStore()),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_dir/$name.png'));
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  const configs = [
    ('phone_360_x106', Size(360, 800), 2.0, 1.06),
    ('phone_360_x130', Size(360, 800), 2.0, 1.30),
    ('ipad_820_x106', Size(820, 1180), 1.5, 1.06),
  ];
  for (final (name, size, dpr, scale) in configs) {
    for (final hc in [false, true]) {
      final tag = '${name}_${hc ? 'contrast' : 'normal'}';
      testWidgets('我的設定 → 安靜時段, $tag', (tester) async {
        if (!_shots) return;
        await tester.runAsync(_loadFonts);
        await _open(tester,
            size: size, dpr: dpr, scale: scale, highContrast: hc);
        expect(find.text('安靜時段'), findsOneWidget);
        await _shot(tester, '1_page_$tag');
        await _tapVisible(tester, find.byKey(const Key('quiet_hours_start')));
        expect(find.byKey(const Key('quiet_hours_sheet')), findsOneWidget);
        await _shot(tester, '2_start_picker_$tag');
        if (name == 'phone_360_x130' && !hc) {
          await _tapVisible(
              tester, find.byKey(const Key('quiet_hours_option_21:00')));
          await _tapVisible(tester, find.byKey(const Key('quiet_hours_end')));
          await _shot(tester, '3_end_picker_after_21_$tag');
          await _tapVisible(
              tester, find.byKey(const Key('quiet_hours_option_07:00')));
          await _shot(tester, '4_page_after_21_07_$tag');
        }
      });
    }
  }
}
