// 1020m 第二节 / 1020n 第三节、第五节 — screenshots of page 1's
// small-action row for Junyu (「今日要做嘅事」: 今日想做啲咩小行動？ /
// 今日計劃：{…} with 做咗 and 改日 / the ticked row; 1020n: plan texts on at
// most two lines, the day plans are made (聽日計劃 × 2 + 仲有冇其他計劃？),
// three plans for today (two lines + 仲有 1 個計劃)).  Page 1 with homeLayoutV2Enabled + moodRowV2Enabled +
// checkInChatV2Enabled on, as in production.  Not part of CI.
//
//   flutter test --dart-define=PHASE_B=true --dart-define=SHOTS=true \
//     --update-goldens test_manual/home_small_action_shots_1020m_test.dart
//
// Writes docs/dev-reports/1020m-shots/smallaction/*.png (1020n:
// docs/dev-reports/1020n-shots/*.png): phone 360 × 800
// (App text 1.06 and 1.30 = 特大, the largest) and iPad 820 × 1180 (1.06);
// the rule arm on the small phone too (both arms see the same row).  Needs
// the WenQuanYi Zen Hei font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc)
// for the Chinese text; without SHOTS nothing is drawn.  Synthetic data
// only; nothing is written anywhere else.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/app/main_shell.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/core/session/session_entry_surface.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/today/presentation/widgets/daily_mood_prompt.dart';
import 'package:app_demo/features/today/presentation/widgets/home_small_action_row.dart';
import 'package:app_demo/features/today/presentation/widgets/mood_row_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/home_v2_harness.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1020m-shots/smallaction';
const _dirN = '../docs/dev-reports/1020n-shots';

/// 1020n: plan texts of 30+ characters.
const _longs = [
  '星期六朝早同阿明、阿芳同埋舊同事一齊去公園行一個鐘，之後去茶樓飲早茶',
  '打電話畀住喺元朗嘅表姐，問下佢最近身體點，約佢下個月一齊去飲茶',
  '去社區中心問下有冇長者書法班，報名之後同隔籬屋陳太一齊去上堂',
];

const _long = '星期六朝早同阿明、阿芳同埋舊同事一齊去公園行一個鐘，之後去茶樓飲早茶';
const _short = '同阿明去公園行下';

Future<void> _loadFonts() async {
  final cjk = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!cjk.existsSync()) fail('needs ${cjk.path}');
  final bytes = ByteData.sublistView(cjk.readAsBytesSync());
  for (final family in ['WQY', 'NotoSerifHK', 'NotoSansHK']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  if (emoji.existsSync()) {
    await (FontLoader('Emoji')
          ..addFont(Future.value(ByteData.sublistView(emoji.readAsBytesSync()))))
        .load();
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

/// The App theme with the test's Chinese font on the text and the buttons
/// (the App's button styles name no font; the test renderer would draw
/// boxes).  Drawing only.
ThemeData _shotTheme() {
  final base = AppTheme.light;
  TextTheme t(TextTheme x) =>
      x.apply(fontFamily: 'NotoSansHK', fontFamilyFallback: const ['Emoji']);
  ButtonStyle? b(ButtonStyle? st) {
    final ts = st?.textStyle?.resolve(<WidgetState>{}) ?? const TextStyle();
    return (st ?? const ButtonStyle()).copyWith(
      textStyle: WidgetStatePropertyAll(ts.copyWith(
          fontFamily: 'NotoSansHK', fontFamilyFallback: const ['Emoji'])),
    );
  }

  return base.copyWith(
    textTheme: t(base.textTheme),
    primaryTextTheme: t(base.primaryTextTheme),
    filledButtonTheme:
        FilledButtonThemeData(style: b(base.filledButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(style: b(base.textButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: b(base.outlinedButtonTheme.style)),
    elevatedButtonTheme:
        ElevatedButtonThemeData(style: b(base.elevatedButtonTheme.style)),
  );
}

typedef _Device = ({String tag, Size size, double text, bool scrollToTodo});

final List<_Device> _devices = [
  (
    tag: 'phone360_text106',
    size: const Size(360, 800),
    text: AppFontScale.standard.multiplier,
    scrollToTodo: true,
  ),
  (
    tag: 'phone360_text130',
    size: const Size(360, 800),
    text: AppFontScale.xLarge.multiplier,
    scrollToTodo: true,
  ),
  (
    tag: 'ipad820_text106',
    size: const Size(820, 1180),
    text: AppFontScale.standard.multiplier,
    scrollToTodo: false,
  ),
];

Future<void> _pump(WidgetTester tester, HomeRun run, _Device d) async {
  await tester.runAsync(_loadFonts);
  tester.view.physicalSize = d.size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await pumpHome(tester, run, const MainShell(),
      size: null, theme: _shotTheme(), textScale: d.text);
}

/// Phones: 「今日要做嘅事」 at the top of the screen.  iPad: as it opens.
Future<void> _toTodo(WidgetTester tester, _Device d) async {
  await tester.drag(
      find.byKey(const ValueKey('today_v2')), const Offset(0, 3000));
  await tester.pumpAndSettle();
  if (!d.scrollToTodo) return;
  final title = find.byKey(const ValueKey('today_todo_title'));
  unawaited(Scrollable.ensureVisible(tester.element(title)));
  await tester.pumpAndSettle();
}

/// Scrolls page 1 until [f] is built and on screen.
Future<void> _reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 120,
      scrollable: find
          .descendant(
              of: find.byKey(const ValueKey('today_v2')),
              matching: find.byType(Scrollable))
          .first);
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name,
    {String dir = _dir}) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$dir/$name.png'));
}

/// A plan saved yesterday at 11:00: today is its day.
void _seed(HomeRun run, String action) => run.smallActions.addPlan('p1',
    action: action,
    createdAt: DateTime(2026, 10, 19, 11),
    arm: run.rule ? 'B' : 'A');

void main() {
  late BriefPrStore savedStore;

  setUpAll(SessionCloseHint.claimFirstUse);

  setUp(() {
    savedStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
    PhaseBConfig.current = const PhaseBConfig(
      sessionBriefPrV2Enabled: true,
      weeklyScheduleV2Enabled: true,
    );
    RemoteFeatureFlags.current = const RemoteFeatureFlags(
      homeLayoutV2Enabled: true,
      moodRowV2Enabled: true,
      checkInChatV2Enabled: true,
    );
    MoodRowV2.resetForTest();
    DailyMoodPrompt.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
    SessionEntrySurface.resetForTest();
    HomeSmallActionRow.resetShownLog();
  });

  tearDown(() {
    BriefPrV2.store = savedStore;
    RemoteFeatureFlags.resetForTest();
    MoodRowV2.resetForTest();
  });

  for (final arm in testableArms) {
    final tag = arm == ArmAssignment.a ? 'hybrid' : 'rule';
    // Both arms see the same row; the rule arm on the small phone only.
    final devices = arm == ArmAssignment.a ? _devices : [_devices.first];

    for (final d in devices) {
      testWidgets('no plan ${d.tag} $tag', (tester) async {
        if (!_shots) return;
        final run = HomeRun(arm);
        await _pump(tester, run, d);
        await _reveal(tester, find.byKey(HomeSmallActionRow.askKey));
        await _toTodo(tester, d);
        await _shot(tester, '01_no_plan_${d.tag}_$tag');
      });

      testWidgets('plan, long text ${d.tag} $tag', (tester) async {
        if (!_shots) return;
        final run = HomeRun(arm);
        _seed(run, _long);
        await _pump(tester, run, d);
        await _reveal(tester, find.byKey(HomeSmallActionRow.planKey('p1')));
        await _toTodo(tester, d);
        await _shot(tester, '02_plan_long_${d.tag}_$tag');
      });

      testWidgets('ticked ${d.tag} $tag', (tester) async {
        if (!_shots) return;
        final run = HomeRun(arm);
        _seed(run, _short);
        await _pump(tester, run, d);
        final done = find.byKey(HomeSmallActionRow.doneButtonKey('p1'));
        await _reveal(tester, done);
        await tester.tap(done);
        await settle(tester);
        await _reveal(tester, find.byKey(HomeSmallActionRow.doneKey('p1')));
        await _toTodo(tester, d);
        await _shot(tester, '03_ticked_${d.tag}_$tag');
      });

      // 1020n — phones only (the brief: small phone at 1.06 and 1.30).
      if (d.tag.startsWith('phone')) {
        testWidgets('1020n next day, two plans ${d.tag} $tag', (tester) async {
          if (!_shots) return;
          final run = HomeRun(arm);
          for (final (i, text) in _longs.take(2).indexed) {
            run.smallActions.addPlan('n${i + 1}',
                action: text,
                createdAt: DateTime(2026, 10, 20, 8, i),
                arm: run.rule ? 'B' : 'A');
          }
          await _pump(tester, run, d);
          await _reveal(tester, find.byKey(HomeSmallActionRow.moreKey));
          await _toTodo(tester, d);
          await _shot(tester, '01_next_day_two_plans_${d.tag}_$tag',
              dir: _dirN);
        });

        testWidgets('1020n today, three plans ${d.tag} $tag', (tester) async {
          if (!_shots) return;
          final run = HomeRun(arm);
          for (final (i, text) in _longs.indexed) {
            run.smallActions.addPlan('p${i + 1}',
                action: text,
                createdAt: DateTime(2026, 10, 19, 9 + i),
                arm: run.rule ? 'B' : 'A');
          }
          await _pump(tester, run, d);
          await _reveal(tester, find.byKey(HomeSmallActionRow.overflowKey));
          await _toTodo(tester, d);
          if (d.text > 1.1) {
            // Largest text: the plan lines at the top, so 「仲有 1 個計劃」
            // is on screen too.
            unawaited(Scrollable.ensureVisible(
                tester.element(find.byKey(HomeSmallActionRow.planKey('p1')))));
            await tester.pumpAndSettle();
          }
          await _shot(tester, '02_today_three_plans_${d.tag}_$tag',
              dir: _dirN);
        });
      }
    }
  }
}
