// T35 (handover 1021-W8 五 (6)) — screenshots of the W8 questionnaire at the
// largest App text (特大 1.30) on a 360 × 800 phone: the opening page, the
// first question of each of the five parts, the DJG-ES q4 line and the two
// LSNS-6 lead lines, the completion page with 「填呢份」「唔填喇」, the AIMHS
// first question and the home card.  Both arms see exactly these pages.
// Not part of CI (test/w8_questionnaire_test.dart checks the words, the
// flow and that nothing is cut at 1.30).
//
//   flutter test test_manual/w8_shots_1021_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1021-w8-shots/*.png.  Needs the WenQuanYi Zen Hei
// font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc); without SHOTS
// nothing is drawn.  Synthetic data in memory; nothing is written.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/today/presentation/widgets/today_todo_rows.dart';
import 'package:app_demo/features/w8/data/w8_items.dart';
import 'package:app_demo/features/w8/data/w8_store.dart';
import 'package:app_demo/features/w8/presentation/w8_flow_page.dart';
import 'package:app_demo/features/w8/presentation/w8_home_row.dart';
import 'package:app_demo/features/w8/presentation/w8_part_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1021-w8-shots';

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
          ..addFont(
              Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
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
  uid: 'u1',
  email: 'synthetic@example.com',
  displayName: '測試',
  arm: ArmAssignment.b,
  cohort: 'rct',
  w0Date: '2026-10-15',
);

/// Opens [page] on top of a plain first page (so the back arrow shows, as
/// in the App).
Future<void> _open(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh'), profile: _profile),
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

Future<void> _shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_dir/$name.png'));
}

/// The part page of [spec], opened at question [index] (the earlier ones
/// answered, kept in memory only).
Widget _partAt(W8PartSpec spec, int index, {(int, int)? part}) {
  final answers = <String, Object>{
    for (final it in spec.items.take(index)) it.id: spec.options.first.value,
  };
  return W8PartPage(
    spec: spec,
    part: part,
    store: MemoryW8Store({
      if (index > 0)
        spec.part: W8Saved(
            status: W8Status.inProgress, answers: answers, hasStarted: true),
    }),
  );
}

void main() {
  final parts = W8Items.parts;

  testWidgets('W8 screenshots at 1.30 on 360 × 800', (tester) async {
    if (!_shots) return;
    await tester.runAsync(_loadFonts);

    await _open(tester, W8FlowPage(store: MemoryW8Store()));
    await _shot(tester, '01_intro');

    for (var i = 0; i < parts.length; i++) {
      await _open(tester, _partAt(parts[i], 0, part: (i + 1, parts.length)));
      await _shot(tester, '0${i + 2}_part${i + 1}_q1_${parts[i].part.name}');
    }

    // The DJG-ES q4 line and the LSNS-6 q4 line (the q1 line is on the
    // part-5 first question above).
    await _open(tester, _partAt(W8Items.djg, 3, part: (1, 5)));
    await _shot(tester, '07_djg_q4_line');
    await _open(tester, _partAt(W8Items.lsns6, 3, part: (5, 5)));
    await _shot(tester, '08_lsns6_q4_line');

    await _open(
        tester,
        W8FlowPage(
            store: MemoryW8Store({
          for (final p in parts)
            p.part: const W8Saved(status: W8Status.submitted),
        })));
    await _shot(tester, '09_completion');

    await _open(tester, _partAt(W8Items.aimhs, 0));
    await _shot(tester, '10_aimhs_q1');

    // The home card in 「今日要做嘅事」 (day 57 for W0 10/15).
    await _open(
        tester,
        Scaffold(
          body: SafeArea(
            child: ListView(children: [
              const TodoSectionTitle(),
              W8TodoRow(
                storeFor: (_) => MemoryW8Store(),
                clock: () => DateTime(2026, 12, 11, 10, 30),
                phaseB: true,
              ),
            ]),
          ),
        ));
    await tester.pumpAndSettle();
    expect(find.text(W8Texts.title), findsOneWidget);
    await _shot(tester, '11_home_card');
  });
}
