// 1020m 一 — draft screenshots of 做啲嘢 with the four big cards
// (homeLayoutV2Enabled on), for Junyu to check the style.  Phone 360 × 800 at App text 1.06 and 1.30 (the maximum), iPad
// 820 × 1180 at 1.06.  Not part of CI.
//
//   flutter test test_manual/tools_page_shots_1020m_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1020m-shots/tools/*.png.  Needs the WenQuanYi Zen
// Hei font for the Chinese text.  Synthetic; nothing is written.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/features/me/presentation/pages/me_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1020m-shots/tools';

Future<void> _loadFonts() async {
  final cjk = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!cjk.existsSync()) fail('needs ${cjk.path}');
  final bytes = ByteData.sublistView(cjk.readAsBytesSync());
  for (final family in ['NotoSerifHK', 'NotoSansHK']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

Future<void> _shot(WidgetTester tester, String name,
    {required Size logical, required double scale}) async {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh')),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('做啲嘢')),
        body: const MePage(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_dir/$name.png'));
}

void main() {
  setUp(() => RemoteFeatureFlags.current =
      const RemoteFeatureFlags(homeLayoutV2Enabled: true));
  tearDown(RemoteFeatureFlags.resetForTest);

  testWidgets('做啲嘢 cards', (tester) async {
    if (!_shots) return;
    await tester.runAsync(_loadFonts);
    const phone = Size(360, 800);
    final max = AppFontScale.xLarge.multiplier;
    await _shot(tester, 'tools_phone360_x106',
        logical: phone, scale: 1.06);
    await _shot(tester, 'tools_phone360_x130',
        logical: phone, scale: max);
    await _shot(tester, 'tools_ipad820_x106',
        logical: const Size(820, 1180), scale: 1.06);
  });
}
