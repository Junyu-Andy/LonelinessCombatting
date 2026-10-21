// 1020l §一 (1), §二 (1) — screenshots of page 1 「睇今日」 for Junyu:
// the questionnaire row in its new two-line style (open / not yet open /
// week 4) and the Brief PR invitation card on page 1 and page 2 after a
// 小欣 check-in.  Switches homeLayoutV2Enabled + moodRowV2Enabled +
// checkInChatV2Enabled on.  Not part of CI.
//
//   flutter test --dart-define=PHASE_B=true --dart-define=SHOTS=true \
//     --update-goldens test_manual/home_shots_1020l_test.dart
//
// Writes docs/dev-reports/1020l-shots/home/*.png: phone 360 × 800 (App text
// 1.06 and 1.30 = 特大, the largest) and iPad 820 × 1180 (1.06).  Needs the
// WenQuanYi Zen Hei font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc) for
// the Chinese text; without SHOTS nothing is drawn.  Synthetic data only;
// nothing is written anywhere else.
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
import 'package:app_demo/features/brief_pr/presentation/widgets/brief_pr_invite_card.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/today/presentation/widgets/daily_mood_prompt.dart';
import 'package:app_demo/features/today/presentation/widgets/mood_row_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/home_v2_harness.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1020l-shots/home';

late ThemeData _theme;

Future<void> _loadFonts() async {
  final cjk = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!cjk.existsSync()) fail('needs ${cjk.path}');
  final bytes = ByteData.sublistView(cjk.readAsBytesSync());
  // Text that names no font (the Brief PR card's two button labels set
  // their own style) is drawn as boxes by the test renderer whatever is
  // loaded here — a screenshot limitation; the App shows 好呀 / 今次唔評.
  for (final family in ['WQY', 'NotoSerifHK', 'NotoSansHK']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  if (emoji.existsSync()) {
    await (FontLoader(
          'Emoji',
        )..addFont(Future.value(ByteData.sublistView(emoji.readAsBytesSync()))))
        .load();
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
      textStyle: WidgetStatePropertyAll(
        ts.copyWith(
          fontFamily: 'NotoSansHK',
          fontFamilyFallback: const ['Emoji'],
        ),
      ),
    );
  }

  return base.copyWith(
    textTheme: t(base.textTheme),
    primaryTextTheme: t(base.primaryTextTheme),
    filledButtonTheme: FilledButtonThemeData(
      style: b(base.filledButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(style: b(base.textButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: b(base.outlinedButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: b(base.elevatedButtonTheme.style),
    ),
  );
}

/// A screen size (logical) and the App's text size.
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
  tester.view.physicalSize = d.size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await pumpHome(
    tester,
    run,
    const MainShell(),
    size: null,
    theme: _theme,
    textScale: d.text,
  );
}

/// Phones: 「今日要做嘅事」 at the top of the screen (the rows are what the
/// shot is about).  iPad: the page as it opens.
Future<void> _toTodo(WidgetTester tester, _Device d) async {
  // From the top of page 1 (after a chat the list may be scrolled).
  await tester.drag(
    find.byKey(const ValueKey('today_v2')),
    const Offset(0, 3000),
  );
  await tester.pumpAndSettle();
  if (!d.scrollToTodo) return;
  final title = find.byKey(const ValueKey('today_todo_title'));
  unawaited(Scrollable.ensureVisible(tester.element(title)));
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('$_dir/$name.png'),
  );
}

Future<void> _answer(WidgetTester tester, String q, String code) async {
  await tester.tap(find.byKey(ValueKey('check_in_answer_${q}_$code')));
  await settle(tester);
}

/// Today's check-in from page 1's row, then 「今日傾到呢度」.
Future<void> _checkIn(WidgetTester tester, HomeRun run) async {
  final row = find.byKey(const ValueKey('today_todo_check_in'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await settle(tester);
  await _answer(tester, 'Q1', 'good');
  await _answer(tester, 'Q2', 'none');
  await _answer(tester, 'Q3', 'none');
  await tester.tap(find.byKey(const ValueKey('check_in_skip')));
  await settle(tester);
  await _answer(tester, 'Q5', 'no');
  // The row shows its tick once back on page 1.
  run.checkedIn = true;
  await tester.tap(find.text('今日傾到呢度'));
  await settle(tester);
}

void main() {
  late BriefPrStore savedStore;

  setUpAll(() async {
    SessionCloseHint.claimFirstUse();
    if (_shots) {
      await _loadFonts();
      _theme = _shotTheme();
    }
  });

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
  });

  tearDown(() {
    BriefPrV2.store = savedStore;
    RemoteFeatureFlags.resetForTest();
    MoodRowV2.resetForTest();
  });

  for (final arm in testableArms) {
    final tag = arm == ArmAssignment.a ? 'hybrid' : 'rule';
    // Both arms see the same page; the rule arm on the small phone only.
    final devices = arm == ArmAssignment.a ? _devices : [_devices.first];

    for (final d in devices) {
      testWidgets('questionnaire open ${d.tag} $tag', (tester) async {
        if (!_shots) return;
        // W1 open (10/21 20:00 – 10/24 20:00), first day: 請盡快回答.
        final run = HomeRun(arm, now: DateTime(2026, 10, 22, 9, 30));
        await _pump(tester, run, d);
        expect(
          find.byKey(const ValueKey('today_todo_questionnaire_open')),
          findsOneWidget,
        );
        await _toTodo(tester, d);
        await _shot(tester, '01_questionnaire_open_${d.tag}_$tag');
      });

      testWidgets('questionnaire not open ${d.tag} $tag', (tester) async {
        if (!_shots) return;
        final run = HomeRun(arm); // 10/20: W1 opens 10/21.
        await _pump(tester, run, d);
        expect(
          find.byKey(const ValueKey('today_todo_questionnaire_next')),
          findsOneWidget,
        );
        await _toTodo(tester, d);
        await _shot(tester, '02_questionnaire_next_${d.tag}_$tag');
      });

      testWidgets('card on page 1 after check-in ${d.tag} $tag', (
        tester,
      ) async {
        if (!_shots) return;
        final run = HomeRun(arm, now: DateTime(2026, 10, 22, 9, 30));
        await _pump(tester, run, d);
        await _checkIn(tester, run);
        expect(find.byType(BriefPrInviteCard), findsOneWidget);
        await _toTodo(tester, d);
        await _shot(tester, '03_card_page1_after_check_in_${d.tag}_$tag');
      });
    }

    testWidgets('card on page 2 after check-in $tag', (tester) async {
      if (!_shots) return;
      final d = _devices.first;
      final run = HomeRun(arm, now: DateTime(2026, 10, 22, 9, 30));
      await _pump(tester, run, d);
      await _checkIn(tester, run);
      await tester.tap(find.byKey(const ValueKey('today_go_talk')));
      await settle(tester);
      expect(find.byType(BriefPrInviteCard), findsOneWidget);
      await _shot(tester, '04_card_page2_after_check_in_${d.tag}_$tag');
    });
  }

  testWidgets('questionnaire week 4 (no second line)', (tester) async {
    if (!_shots) return;
    final d = _devices.first;
    final run = HomeRun(testableArms.first, now: DateTime(2026, 11, 11, 9));
    await _pump(tester, run, d);
    await _toTodo(tester, d);
    await _shot(tester, '05_questionnaire_week4_${d.tag}');
  });
}
