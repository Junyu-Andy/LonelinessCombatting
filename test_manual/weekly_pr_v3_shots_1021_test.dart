// 10/21 (decisions-log 117) — Weekly PR v3 now reads 「呢個禮拜 小欣
// 冇對我指指點點。」.  Screenshot of the page that has v3, largest App text
// (特大 1.30) on a 360 × 800 phone, switch `scaleDirectionCuesEnabled` on
// (production), v3 not yet answered and on screen.  Both arms see the same
// page.  Not part of CI (test/weekly_pr_v3_1021_test.dart checks the text,
// the bold word and that nothing is cut).
//
//   flutter test test_manual/weekly_pr_v3_shots_1021_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1021-shots/weekly_pr_v3_360_x130.png.  Needs the
// WenQuanYi Zen Hei font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc);
// without SHOTS nothing is drawn.  Synthetic data; nothing is written.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_response.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_trigger.dart';
import 'package:app_demo/features/weekly_pr/presentation/pages/weekly_pr_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1021-shots';

Future<void> _loadFonts() async {
  final cjk = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!cjk.existsSync()) fail('needs ${cjk.path}');
  final bytes = ByteData.sublistView(cjk.readAsBytesSync());
  for (final family in ['NotoSerifHK', 'NotoSansHK']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

/// The App theme, with the button labels given the Chinese test font: the
/// App's button styles name no font (the phone's own font is used), which
/// the test renderer draws as boxes.  Drawing only; nothing else changes.
ThemeData _shotTheme() {
  final t = AppTheme.light;
  ButtonStyle? withFont(ButtonStyle? s) {
    final ts = s?.textStyle?.resolve(const {});
    if (s == null || ts == null) return s;
    return s.copyWith(
        textStyle: WidgetStatePropertyAll(ts.copyWith(fontFamily: 'NotoSansHK')));
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

Future<void> _open(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh')),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _shotTheme(),
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(AppFontScale.xLarge.multiplier)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<Object?>(builder: (_) => page)),
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

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(scaleDirectionCuesEnabled: true);
  });
  tearDown(RemoteFeatureFlags.resetForTest);

  testWidgets('Weekly PR, the page with v3', (tester) async {
    if (!_shots) return;
    await tester.runAsync(_loadFonts);
    await _open(
        tester,
        WeeklyPrPage(
          agent: WeeklyPrAgentUsage(
            agentId: 'siu_yan',
            displayName: '小欣',
            sessionCount: 3,
            firstUseAt: DateTime(2026, 10, 20),
          ),
          preview: true,
        ));
    Finder card(String id) => find.byKey(ValueKey('weekly_pr_item_$id'));
    // Answer the pages before v3's, top to bottom; stop at v3.
    var reached = false;
    for (var page = 0; page < 3 && !reached; page++) {
      final done = <String>{};
      var idle = 0;
      while (true) {
        final next = [
          for (final it in WeeklyPrItems.items)
            if (!done.contains(it.id) && card(it.id).evaluate().isNotEmpty)
              it.id,
        ]..sort((a, b) => tester
            .getTopLeft(card(a))
            .dy
            .compareTo(tester.getTopLeft(card(b)).dy));
        if (next.isEmpty) {
          if (++idle > 3) break;
          await tester.drag(find.byKey(ValueKey('weekly_pr_page_$page')),
              const Offset(0, -400));
          await tester.pumpAndSettle();
          continue;
        }
        idle = 0;
        if (next.first == 'v3') {
          reached = true;
          break;
        }
        await _tapVisible(tester,
            find.descendant(of: card(next.first), matching: find.text('4')));
        done.add(next.first);
      }
      if (!reached) {
        await tester.tap(find.text('下一頁'));
        await tester.pumpAndSettle();
      }
    }
    expect(reached, isTrue);
    // v3 in the middle of the screen.
    await tester.ensureVisible(card('v3'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(card('v3'), findsOneWidget);
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_dir/weekly_pr_v3_360_x130.png'));
  });
}
