// 1020k 四 (1)(4) — draft screenshots of the three lines for Junyu (style
// only; the wording is final): largest App text (特大 1.30) on a 360 × 800
// phone, switch `scaleDirectionCuesEnabled` on.  Not part of CI.
//
//   flutter test test_manual/scale_direction_cues_shots_1020k_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1020k-shots/*.png.  Needs the WenQuanYi Zen Hei
// font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc) for the Chinese text;
// without SHOTS nothing is drawn.  Synthetic data; nothing is written.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/session/session_rules.dart';
import 'package:app_demo/features/assessment/data/djg_w2.dart';
import 'package:app_demo/features/assessment/presentation/pages/djg_w2_page.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_record.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_scheduler.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/presentation/pages/brief_pr_flow_page.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_trigger.dart';
import 'package:app_demo/features/weekly_pr/presentation/pages/weekly_pr_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1020k-shots';
const _ids = ['u1', 'u2', 'u3', 'v1', 'v2', 'v3', 'c1', 'c2', 'c3', 'i1', 'i2', 'i3'];

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

Future<void> _shot(WidgetTester tester, String name) async {
  // Back to the top: the screen as the elder first sees it.
  final scrollable = find.byType(Scrollable).last;
  await tester.drag(scrollable, const Offset(0, 3000));
  await tester.pumpAndSettle();
  // Decode the avatar images so they are drawn.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dir/$name.png'));
}

void main() {
  setUp(() {
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(scaleDirectionCuesEnabled: true);
  });
  tearDown(RemoteFeatureFlags.resetForTest);

  testWidgets('Brief PR question 4', (tester) async {
    if (!_shots) return;
    await tester.runAsync(_loadFonts);
    final t0 = DateTime(2026, 10, 20, 15, 20);
    final store = InMemoryBriefPrStore();
    await store.put(BriefPrRecord(
      uid: 'synthetic',
      sessionId: 's1',
      agentId: 'siu_yan',
      agentDisplayName: '小欣',
      sessionType: 'free_chat',
      endReason: SessionEndReason.closeButton,
      sessionEndedAt: t0,
      lastReplyAt: t0,
      invitedAt: t0,
      invitedDayKey: '2026-10-20',
      inviteChannel: BriefPrInviteChannel.listPage,
    ));
    await _open(
        tester,
        BriefPrFlowPage(
          record: store.records['synthetic/s1']!,
          scheduler: BriefPrScheduler(
              store: store,
              rules: const SessionRules(v2: true, idleTimeoutMin: 30),
              clock: () => t0),
        ));
    for (var q = 1; q <= 3; q++) {
      await _tapVisible(tester, find.byKey(const Key('brief_pr_option_4')));
      await _tapVisible(tester, find.byKey(const Key('brief_pr_next')));
    }
    expect(find.byKey(const Key('brief_pr_q4_cue')), findsOneWidget);
    await _shot(tester, 'brief_pr_q4_360_x130');
  });

  testWidgets('Weekly PR page 3', (tester) async {
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
    for (var p = 0; p < 2; p++) {
      final done = <String>{};
      while (true) {
        Finder card(String id) => find.byKey(ValueKey('weekly_pr_item_$id'));
        final next = _ids
            .where((id) => !done.contains(id) && card(id).evaluate().isNotEmpty)
            .toList()
          ..sort((a, b) => tester
              .getTopLeft(card(a))
              .dy
              .compareTo(tester.getTopLeft(card(b)).dy));
        if (next.isEmpty) break;
        final id = next.first;
        await _tapVisible(
            tester,
            find.descendant(
                of: find.byKey(ValueKey('weekly_pr_item_$id')),
                matching: find.text('4')));
        done.add(id);
      }
      await tester.tap(find.text('下一頁'));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('weekly_pr_reverse_cue')), findsOneWidget);
    await _shot(tester, 'weekly_pr_page3_360_x130');
  });

  testWidgets('DJG-ES question 4', (tester) async {
    if (!_shots) return;
    await tester.runAsync(_loadFonts);
    await _open(tester, DjgW2Page(store: _FakeDjgStore()));
    for (var q = 1; q <= 3; q++) {
      await _tapVisible(tester, find.text('是'));
    }
    expect(find.byKey(const Key('djg_q4_cue')), findsOneWidget);
    await _shot(tester, 'djg_q4_360_x130');
  });
}

class _FakeDjgStore implements DjgW2Store {
  @override
  Future<DjgW2Saved> load() async => const DjgW2Saved();

  @override
  Future<void> save(Map<String, String> answers,
      {required bool submit, required bool first}) async {}
}
