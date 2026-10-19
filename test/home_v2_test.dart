// 1020 D, G (2) (batch 3) — the two-page layout behind
// `homeLayoutV2Enabled`, both arms:
//   - page 1 「睇今日」: greeting, mood row, 「今日要做嘅事」 (check-in row
//     with the 3-day reminder folded in, Brief PR card, questionnaire row,
//     action plan), 「去搵人傾」, recap, crisis card — in that order; the
//     moved-off widgets are not there;
//   - page 2 「搵人傾」: header, Brief PR card, continue card, first-week
//     nudge, the three companions;
//   - 「去搵人傾」 switches the tab; the check-in row opens 小欣 and starts
//     today's check-in;
//   - acceptance: a session started from a page-1 entry shows the
//     invitation card back on page 1, and the next App open shows it again;
//   - 1020b §2 (2): with the layout on, the old banner never adds a
//     second card;
//   - G (2): W4 / W5 by study week;
//   - the 做啲嘢 tool pictures (flag on) / old icons (off).
//
// Two-arm cases need a Phase B build:
//   flutter test --dart-define=PHASE_B=true test/home_v2_test.dart
import 'package:app_demo/app/main_shell.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/scheduling/weekly_schedule.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/features/adherence/presentation/widgets/missed_checkin_banner.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/brief_pr_card_host.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/brief_pr_invite_card.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/context/data/check_in_chat_copy.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/crisis/presentation/widgets/safety_footer_card.dart';
import 'package:app_demo/features/me/presentation/pages/me_page.dart';
import 'package:app_demo/features/me/presentation/widgets/me_list_item.dart';
import 'package:app_demo/features/talk/presentation/pages/talk_page.dart';
import 'package:app_demo/features/today/data/home_v2_copy.dart';
import 'package:app_demo/features/today/data/mood_row_copy.dart';
import 'package:app_demo/features/today/presentation/pages/today_page.dart';
import 'package:app_demo/features/today/presentation/widgets/active_plan_banner.dart';
import 'package:app_demo/features/today/presentation/widgets/agent_tile_row.dart';
import 'package:app_demo/features/today/presentation/widgets/checkin_status_chip.dart';
import 'package:app_demo/features/today/presentation/widgets/continue_chat_card.dart';
import 'package:app_demo/features/today/presentation/widgets/daily_mood_prompt.dart';
import 'package:app_demo/features/today/presentation/widgets/facts_recap_row.dart';
import 'package:app_demo/features/today/presentation/widgets/greeting_hero.dart';
import 'package:app_demo/features/today/presentation/widgets/home_tool_shortcuts.dart';
import 'package:app_demo/features/today/presentation/widgets/mood_row_v2.dart';
import 'package:app_demo/features/today/presentation/widgets/today_todo_rows.dart';
import 'package:app_demo/features/today/presentation/widgets/week1_nudge_banner.dart';
import 'package:app_demo/features/weekly_bundle/data/weekly_bundle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_v2_harness.dart';

const _allOn = RemoteFeatureFlags(
  homeLayoutV2Enabled: true,
  moodRowV2Enabled: true,
  checkInChatV2Enabled: true,
);

const _phaseB = PhaseBConfig(
  sessionBriefPrV2Enabled: true,
  weeklyScheduleV2Enabled: true,
);

/// Inside one tab (the other tabs of the IndexedStack are offstage).
Finder _inPage(Type page, Finder f) => find.descendant(
    of: find.byType(page, skipOffstage: false),
    matching: f,
    skipOffstage: false);

double _top(Finder f) => f.evaluate().isEmpty
    ? double.nan
    : (f.evaluate().first.renderObject! as RenderBox)
        .localToGlobal(Offset.zero)
        .dy;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await settle(tester);
}

Future<void> _answer(WidgetTester tester, String q, String code) async {
  await tester.tap(find.byKey(ValueKey('check_in_answer_${q}_$code')));
  await settle(tester);
}

void main() {
  late RemoteFeatureFlags savedFlags;
  late PhaseBConfig savedConfig;
  late BriefPrStore savedBriefStore;
  late InMemoryBriefPrStore briefStore;

  setUpAll(SessionCloseHint.claimFirstUse);

  setUp(() {
    savedFlags = RemoteFeatureFlags.current;
    savedConfig = PhaseBConfig.current;
    savedBriefStore = BriefPrV2.store;
    briefStore = InMemoryBriefPrStore();
    BriefPrV2.store = briefStore;
    PhaseBConfig.current = _phaseB;
    RemoteFeatureFlags.current = _allOn;
    MoodRowV2.resetForTest();
    DailyMoodPrompt.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
  });

  tearDown(() {
    RemoteFeatureFlags.current = savedFlags;
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedBriefStore;
    MoodRowV2.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
  });

  group('switches (pure)', () {
    test('both new switches: only a literal true turns them on', () {
      for (final v in [null, 'true', 1, false]) {
        final f = RemoteFeatureFlags.fromMap(
            {'homeLayoutV2Enabled': v, 'moodRowV2Enabled': v});
        expect(f.homeLayoutV2Enabled, isFalse, reason: '$v');
        expect(f.moodRowV2Enabled, isFalse, reason: '$v');
      }
      final on = RemoteFeatureFlags.fromMap(
          {'homeLayoutV2Enabled': true, 'moodRowV2Enabled': true});
      expect((on.homeLayoutV2Enabled, on.moodRowV2Enabled), (true, true));
      expect(const RemoteFeatureFlags().homeLayoutV2Enabled, isFalse);
    });

    test('1020b §2 (2): the old Brief PR banner is off whenever the new '
        'layout is on', () {
      for (final layout in [false, true]) {
        for (final banner in [false, true]) {
          final f = RemoteFeatureFlags.fromMap({
            'homeLayoutV2Enabled': layout,
            'briefPrHomeBannerEnabled': banner,
          });
          expect(f.briefPrHomeBannerActive, banner && !layout,
              reason: 'layout $layout banner $banner');
        }
      }
    });

    test('the daily mood pop-up only while both new switches are off', () {
      expect(const RemoteFeatureFlags().dailyMoodPopupActive, isTrue);
      expect(const RemoteFeatureFlags(homeLayoutV2Enabled: true)
          .dailyMoodPopupActive, isFalse);
      expect(const RemoteFeatureFlags(moodRowV2Enabled: true)
          .dailyMoodPopupActive, isFalse);
    });
  });

  group('G (2): questionnaire row (W0 2026-10-14)', () {
    final w0 = DateTime(2026, 10, 14);
    const cfg = PhaseBConfig(weeklyScheduleV2Enabled: true);
    Future<QuestionnaireRowInfo?> at(DateTime now, {bool done = false}) =>
        QuestionnaireRowInfo.resolve(
          cfg: cfg,
          mode: WeeklyScheduleMode.standard,
          w0: w0,
          now: now,
          store: FakeWeeklyStore()..done = done,
        );

    test('before W1 opens: W4 with the opening day', () async {
      final i = (await at(DateTime(2026, 10, 20, 10)))!;
      expect(i.isOpen, isFalse);
      expect(i.text, '下次問卷：10月21日（星期三）開，開咗之後三日內答都得。');
      // Day 7 before 20:00 still says W4 (opens at the push hour).
      expect((await at(DateTime(2026, 10, 21, 19, 59)))!.isOpen, isFalse);
    });

    test('open: W5 with whole days left (3 → 1), never 0', () async {
      expect((await at(DateTime(2026, 10, 21, 20, 30)))!.text,
          '問卷開咗，仲有 3 日。');
      expect((await at(DateTime(2026, 10, 22, 21, 0)))!.text,
          '問卷開咗，仲有 2 日。');
      expect((await at(DateTime(2026, 10, 24, 8, 0)))!.text,
          '問卷開咗，仲有 1 日。');
      expect((await at(DateTime(2026, 10, 24, 19, 59)))!.text,
          '問卷開咗，仲有 1 日。');
    });

    test('open but all done: W4 for the next one', () async {
      expect((await at(DateTime(2026, 10, 22, 9), done: true))!.text,
          '下次問卷：10月28日（星期三）開，開咗之後三日內答都得。');
    });

    test('W4 week (day 26 → end of day 29): 4 days, then 1', () async {
      expect((await at(DateTime(2026, 11, 9, 20, 30)))!.text,
          '問卷開咗，仲有 4 日。');
      expect((await at(DateTime(2026, 11, 12, 9)))!.text, '問卷開咗，仲有 1 日。');
    });

    test('after the last one (W7): nothing', () async {
      expect(await at(DateTime(2026, 12, 10)), isNull);
    });

    test('the date label', () {
      expect(HomeV2Copy.dateLabel(DateTime(2026, 10, 26)), '10月26日（星期一）');
      expect(HomeV2Copy.dateLabel(DateTime(2026, 10, 25)), '10月25日（星期日）');
    });
  });

  group('page 1 and page 2 (MainShell)', () {
    for (final arm in testableArms) {
      final tag = arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';

      testWidgets('$tag: page 1 in D order; the moved-off widgets are gone',
          (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, const MainShell());
        Finder p1(Finder f) => _inPage(TodayPage, f);
        expect(p1(find.byKey(const ValueKey('today_v2'))), findsOneWidget);
        final order = [
          p1(find.byType(GreetingHero)),
          p1(find.byType(MoodRowV2)),
          p1(find.text(HomeV2Copy.todoTitle)),
          p1(find.byType(CheckInTodoRow)),
          p1(find.byType(BriefPrCardHost)),
          // The study-week schedule (and so this row) needs a Phase B build.
          if (FeatureFlags.phaseB) p1(find.byType(QuestionnaireTodoRow)),
          p1(find.byType(ActivePlanBanner)),
          p1(find.byType(GoTalkButton)),
          p1(find.byType(FactsRecapRow)),
          p1(find.byType(SafetyFooterCard)),
        ];
        for (final f in order) {
          expect(f, findsOneWidget, reason: '$f');
        }
        final tops = [for (final f in order) _top(f)];
        for (var i = 1; i < tops.length; i++) {
          expect(tops[i] >= tops[i - 1], isTrue,
              reason: '${order[i]} below ${order[i - 1]}');
        }
        for (final gone in [
          AgentTileRow,
          ContinueChatCard,
          HomeToolShortcuts,
          Week1NudgeBanner,
          MissedCheckInBanner,
          CheckInStatusChip,
        ]) {
          expect(p1(find.byType(gone)), findsNothing, reason: '$gone');
        }
        // No pop-up sheet on the first build of the day.
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text(MoodRowCopy.m1), findsOneWidget);
        expect(p1(find.text(HomeV2Copy.checkInRow)), findsOneWidget);
        // W0 10/14, today 10/20 (day 6): W1 opens on 10/21.
        expect(p1(find.text('下次問卷：10月21日（星期三）開，開咗之後三日內答都得。')),
            FeatureFlags.phaseB ? findsOneWidget : findsNothing);
        expect(p1(find.text(HomeV2Copy.goTalk)), findsOneWidget);
        if (run.rule) expect(run.llm.calls, isEmpty);
      });

      testWidgets('$tag: page 2 in D order; 「去搵人傾」 switches to it',
          (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, const MainShell());
        Finder p2(Finder f) => _inPage(TalkPage, f);
        final stack = find.byType(IndexedStack);
        expect(tester.widget<IndexedStack>(stack).index, 0);
        await tester.tap(find.byKey(const ValueKey('today_go_talk')));
        await settle(tester);
        expect(tester.widget<IndexedStack>(stack).index, 1);
        expect(p2(find.byKey(const ValueKey('talk_v2'))), findsOneWidget);
        final order = [
          p2(find.text('揀一個你想搵嘅人傾下。')),
          p2(find.byType(BriefPrCardHost)),
          p2(find.byType(ContinueChatCard)),
          p2(find.byType(Week1NudgeBanner)),
          p2(find.byType(AgentTileRow)),
        ];
        for (final f in order) {
          expect(f, findsOneWidget, reason: '$f');
        }
        final tops = [for (final f in order) _top(f)];
        for (var i = 1; i < tops.length; i++) {
          expect(tops[i] >= tops[i - 1], isTrue, reason: '${order[i]}');
        }
        if (run.rule) expect(run.llm.calls, isEmpty);
      });
    }

    testWidgets('layout off: page 2 as before (no continue card / nudge)',
        (tester) async {
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(checkInChatV2Enabled: true);
      final run = HomeRun(testableArms.first);
      await pumpHome(tester, run, const Scaffold(body: TalkPage()));
      expect(find.byKey(const ValueKey('talk_v2')), findsNothing);
      expect(find.byType(ContinueChatCard), findsNothing);
      expect(find.byType(Week1NudgeBanner), findsNothing);
      expect(find.byType(AgentTileRow), findsOneWidget);
      expect(find.byType(BriefPrCardHost), findsOneWidget);
    });

    testWidgets('mood row off, layout on: the old pad, still no pop-up',
        (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags(
          homeLayoutV2Enabled: true, checkInChatV2Enabled: true);
      final run = HomeRun(testableArms.first);
      await pumpHome(tester, run, const MainShell());
      expect(find.byType(MoodRowV2), findsNothing);
      expect(find.text('今日感覺點？（隨時可以再記）'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('weekly schedule off: no questionnaire row (the old banner '
        'handles it)', (tester) async {
      PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
      final run = HomeRun(testableArms.first);
      await pumpHome(tester, run, const MainShell());
      expect(find.byType(QuestionnaireTodoRow), findsNothing);
      expect(find.byType(CheckInTodoRow), findsOneWidget);
    });
  });

  group('check-in row (D (3)(a))', () {
    testWidgets('not done: tap → 小欣 and today\'s check-in starts (Q0, Q1)',
        (tester) async {
      for (final arm in testableArms) {
        ChatSessionRecorder.resetProcessStateForTest();
        final run = HomeRun(arm);
        await pumpHome(tester, run, const MainShell());
        final row = find.byKey(const ValueKey('today_todo_check_in'));
        expect(find.descendant(of: row, matching: find.byIcon(
            Icons.radio_button_unchecked_rounded)), findsOneWidget);
        await tester.tap(row);
        await settle(tester);
        expect(find.byType(SiuYanChatPage), findsOneWidget);
        expect(says(CheckInChatCopy.q0Morning), findsOneWidget);
        expect(says(CheckInChatCopy.q1), findsOneWidget);
        if (run.rule) expect(run.llm.calls, isEmpty);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('done: a tick, not tappable; no 3-day line', (tester) async {
      final run = HomeRun(testableArms.first)
        ..checkedIn = true
        ..daysSince = 0;
      await pumpHome(tester, run, const MainShell());
      final row = find.byKey(const ValueKey('today_todo_check_in'));
      expect(find.descendant(
              of: row, matching: find.byIcon(Icons.check_circle_rounded)),
          findsOneWidget);
      expect(tester.widget<TodoRowTile>(row).onTap, isNull);
      expect(find.text(HomeV2Copy.checkInMissed), findsNothing);
    });

    testWidgets('3 days without a check-in: the reminder is in the row, no '
        'separate banner', (tester) async {
      final run = HomeRun(testableArms.first)..daysSince = 3;
      await pumpHome(tester, run, const MainShell());
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('today_todo_check_in')),
              matching: find.text(HomeV2Copy.checkInMissed)),
          findsOneWidget);
      expect(find.byType(MissedCheckInBanner), findsNothing);
      expect(find.text('幾日冇見你'), findsNothing, reason: 'old banner title');
    });

    testWidgets('2 days: no reminder yet', (tester) async {
      final run = HomeRun(testableArms.first)..daysSince = 2;
      await pumpHome(tester, run, const MainShell());
      expect(find.text(HomeV2Copy.checkInMissed), findsNothing);
    });
  });

  group('acceptance: the invitation card comes back on page 1', () {
    for (final arm in testableArms) {
      final tag = arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';

      testWidgets('$tag: check-in from the page-1 row → back on page 1 the '
          'card shows (one card); the next App open shows it again',
          (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, const MainShell());
        expect(find.byType(BriefPrInviteCard), findsNothing);
        await tester.tap(find.byKey(const ValueKey('today_todo_check_in')));
        await settle(tester);
        await _answer(tester, 'Q1', 'good');
        await _answer(tester, 'Q2', 'none');
        await _answer(tester, 'Q3', 'none');
        await tester.tap(find.byKey(const ValueKey('check_in_skip')));
        await settle(tester);
        await _answer(tester, 'Q5', 'no');
        expect(says(CheckInChatCopy.q6), findsOneWidget);
        await tester.tap(find.text('今日傾到呢度'));
        await settle(tester);
        expect(find.byType(SiuYanChatPage), findsNothing);
        expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0,
            reason: 'back on page 1');
        expect(briefStore.records, hasLength(1));
        // The card on page 1 (and the same card on page 2).
        expect(_inPage(TodayPage, find.byType(BriefPrInviteCard)),
            findsOneWidget);
        // (page 2 is offstage in the IndexedStack.)
        expect(
            _inPage(TalkPage,
                find.byType(BriefPrInviteCard, skipOffstage: false)),
            findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('today_todo_check_in')),
                matching: find.byIcon(Icons.check_circle_rounded)),
            findsNothing,
            reason: 'the fake reads checkedIn, still false');
        expect(briefStore.records.values.single.everShown, isTrue);

        // Next App open: a fresh shell; page 1 is the default and shows it.
        await tester.pumpWidget(const SizedBox());
        await pumpHome(tester, run, const MainShell());
        expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
        expect(_inPage(TodayPage, find.byType(BriefPrInviteCard)),
            findsOneWidget);
        if (run.rule) expect(run.llm.calls, isEmpty);
      });

      testWidgets('$tag: chat from M7 on page 1 (3 messages) → card on '
          'page 1', (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, const MainShell());
        await tester.tap(find.byKey(const ValueKey('mood_row_face_4')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('mood_row_m7')));
        await settle(tester);
        expect(find.byType(SiuYanChatPage), findsOneWidget);
        await _type(tester, '今朝去咗公園');
        await _type(tester, '見到舊街坊');
        await _type(tester, '傾咗好耐');
        await tester.tap(find.text('今日傾到呢度'));
        await settle(tester);
        expect(briefStore.records.values.single.sessionType, 'free_chat');
        expect(_inPage(TodayPage, find.byType(BriefPrInviteCard)),
            findsOneWidget);
        if (run.rule) expect(run.llm.calls, isEmpty);
      });
    }

    testWidgets('1020b §2 (2): layout on + old banner switch on → still one '
        'card host and one card on page 1', (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags(
        homeLayoutV2Enabled: true,
        moodRowV2Enabled: true,
        checkInChatV2Enabled: true,
        briefPrHomeBannerEnabled: true,
      );
      final run = HomeRun(testableArms.first);
      await pumpHome(tester, run, const MainShell());
      await tester.tap(find.byKey(const ValueKey('today_todo_check_in')));
      await settle(tester);
      await _answer(tester, 'Q1', 'so_so');
      await _answer(tester, 'Q2', 'none');
      await _answer(tester, 'Q3', 'none');
      await tester.tap(find.byKey(const ValueKey('check_in_skip')));
      await settle(tester);
      await _answer(tester, 'Q5', 'no');
      await tester.tap(find.text('今日傾到呢度'));
      await settle(tester);
      expect(_inPage(TodayPage, find.byType(BriefPrCardHost)), findsOneWidget);
      expect(_inPage(TodayPage, find.byType(BriefPrInviteCard)),
          findsOneWidget);
    });
  });

  group('做啲嘢 tool pictures', () {
    const expected = {
      'me_tool_thought': ('assets/tools/tool_thought.png', 0xFFEFE9F8, '望一望心入面'),
      'me_tool_plan': ('assets/tools/tool_plan.png', 0xFFFCEEE0, '跟進計劃'),
      'me_tool_reading': ('assets/tools/tool_reading.png', 0xFFE3F4EC, '讀少少'),
      'me_tool_small_action': (
        'assets/tools/tool_small_action.png',
        0xFFFBE9E4,
        '一啲社交小行動'
      ),
    };

    for (final arm in testableArms) {
      testWidgets('${arm == ArmAssignment.a ? 'Hybrid' : 'rule arm'}: on → '
          'the four pictures on their tiles, labels unchanged',
          (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, const Scaffold(body: MePage()));
        for (final MapEntry(key: key, value: (asset, colour, label))
            in expected.entries) {
          final item = tester.widget<MeListItem>(find.byKey(ValueKey(key)));
          expect(item.image, asset, reason: key);
          expect(item.tileColor, Color(colour), reason: key);
          expect(item.label, label, reason: key);
          final image = find.descendant(
              of: find.byKey(ValueKey(key)), matching: find.byType(Image));
          expect(image, findsOneWidget);
          // The tile, ~8% margin each side.
          expect(tester.getSize(image).width,
              closeTo(MeListItem.imageTileSize * 0.84, 0.5));
        }
        expect(MeToolArt.all.map((a) => a.$1).toSet(),
            expected.values.map((e) => e.$1).toSet());
      });
    }

    testWidgets('off: the old icons, no pictures', (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags();
      final run = HomeRun(testableArms.first);
      await pumpHome(tester, run, const Scaffold(body: MePage()));
      expect(find.byType(Image), findsNothing);
      for (final key in expected.keys) {
        expect(tester.widget<MeListItem>(find.byKey(ValueKey(key))).image,
            isNull);
      }
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
    });
  });

  test('the four pictures are bundled', () {
    for (final (path, _) in MeToolArt.all) {
      expect(path.startsWith('assets/tools/tool_'), isTrue);
    }
  });

  // Keeps the WeeklyBundle import honest for the store fake.
  test('fake store marks every part', () async {
    final b = WeeklySchedule.bundlesFor(_phaseB, WeeklyScheduleMode.standard)
        .first;
    final s = FakeWeeklyStore()..done = true;
    final st = await s.partStatus(b);
    expect(WeeklyBundleDue(bundle: b, window: WeeklySchedule.windowFor(
            b, DateTime(2026, 10, 14), _phaseB), status: st).allDone,
        isTrue);
  });
}
