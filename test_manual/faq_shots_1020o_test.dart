// 1020o 六 (2) — 常見問題 at the largest App text (特大, 1.30) with all six
// entries open, normal and high contrast, for Junyu to check.  Phone width
// 360; the picture is one tall page so all six answers show at once.  Not
// part of CI.
//
//   flutter test test_manual/faq_shots_1020o_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1020o-shots/faq/*.png.  Needs the WenQuanYi Zen
// Hei font for the Chinese text.  Synthetic; nothing is written elsewhere.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/features/settings/presentation/pages/faq_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1020o-shots/faq';

Future<void> _loadFonts() async {
  final cjk = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!cjk.existsSync()) fail('needs ${cjk.path}');
  final bytes = ByteData.sublistView(cjk.readAsBytesSync());
  for (final family in ['NotoSerifHK', 'NotoSansHK']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (root != null && icons.existsSync()) {
    await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

Future<void> _shot(
  WidgetTester tester,
  String name, {
  required bool highContrast,
}) async {
  tester.view.physicalSize = const Size(360, 3000) * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // A new key per shot: otherwise the tiles keep the previous shot's open
  // state and the taps below close them again.
  await tester.pumpWidget(
    AppSettingsScope(
      key: ValueKey(name),
      settings: AppSettings(locale: const Locale('zh')),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: highContrast ? AppTheme.highContrast : AppTheme.light,
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(AppFontScale.xLarge.multiplier),
          ),
          child: child!,
        ),
        home: const FaqPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  for (final tile in find.byType(ExpansionTile).evaluate().toList()) {
    await tester.tap(
      find.descendant(
        of: find.byWidget(tile.widget),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('$_dir/$name.png'),
  );
}

void main() {
  testWidgets('常見問題, six open, 特大', (tester) async {
    if (!_shots) return;
    await tester.runAsync(_loadFonts);
    await _shot(tester, 'faq_phone360_x130_all_open', highContrast: false);
    await _shot(
      tester,
      'faq_phone360_x130_all_open_high_contrast',
      highContrast: true,
    );
  });
}
