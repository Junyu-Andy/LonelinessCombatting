// 1020l §一 (1) and §二 (1) — Junyu's iPad check of the two-page home.
//
// §一 (1): with `homeLayoutV2Enabled` + `moodRowV2Enabled` (+
// `checkInChatV2Enabled`) on:
//   - page 1 「睇今日」 has no companion tiles (AgentTileRow) — they are on
//     page 2 「搵人傾」 only;
//   - after a 小欣 session (started from page 1's check-in row, or from
//     page 2's 小欣 tile) the Brief PR invitation card is on page 1 AND
//     page 2.
// With the switches off: the old page 1 (companion tiles on page 1) and
// the card on page 2 only — exactly what Junyu saw, so his build had the
// layout switch off when page 1 was built.
// The fix: when the App re-reads the switches after sign-in (AuthGate) and
// a home switch changed, the tabs are rebuilt (MainShell) — page 1 no
// longer stays in the old layout until the App is killed.
//
// §二 (1): the questionnaire row looks like the check-in row: one title
// line, a small second line (the deadline day, or W4's second half), the
// arrow only when it opens something.  Tapping is unchanged.
//
// Both arms: run under PHASE_B=true (and FORCE_ARM=B).  Synthetic data only.
import 'package:app_demo/app/main_shell.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/scheduling/weekly_schedule.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/core/session/session_entry_surface.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/brief_pr_card_host.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/brief_pr_invite_card.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/context/data/check_in_chat_copy.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/talk/presentation/pages/talk_page.dart';
import 'package:app_demo/features/today/data/home_v2_copy.dart';
import 'package:app_demo/features/today/presentation/pages/today_page.dart';
import 'package:app_demo/features/today/presentation/widgets/agent_tile_row.dart';
import 'package:app_demo/features/today/presentation/widgets/daily_mood_prompt.dart';
import 'package:app_demo/features/today/presentation/widgets/mood_row_v2.dart';
import 'package:app_demo/features/today/presentation/widgets/pending_prompts_banner.dart';
import 'package:app_demo/features/today/presentation/widgets/today_todo_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_v2_harness.dart';

const _allOn = RemoteFeatureFlags(
  homeLayoutV2Enabled: true,
  moodRowV2Enabled: true,
  checkInChatV2Enabled: true,
);

/// Layout and mood row off; the 小欣 window on (so a 小欣 session ends the
/// same way and writes the same invitation).
const _layoutOff = RemoteFeatureFlags(checkInChatV2Enabled: true);

const _phaseB = PhaseBConfig(
  sessionBriefPrV2Enabled: true,
  weeklyScheduleV2Enabled: true,
);

/// Inside one tab (the other tabs of the IndexedStack are offstage).
Finder _inPage(Type page, Finder f) => find.descendant(
  of: find.byType(page, skipOffstage: false),
  matching: f,
  skipOffstage: false,
);

Finder _cardOn(Type page) =>
    _inPage(page, find.byType(BriefPrInviteCard, skipOffstage: false));

int _tab(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

Future<void> _answer(WidgetTester tester, String q, String code) async {
  await tester.tap(find.byKey(ValueKey('check_in_answer_${q}_$code')));
  await settle(tester);
}

/// Today's check-in, start to end, in the 小欣 window (both arms the same
/// buttons), then 「今日傾到呢度」.
Future<void> _checkInAndLeave(WidgetTester tester) async {
  expect(find.byType(SiuYanChatPage), findsOneWidget);
  expect(says(CheckInChatCopy.q1), findsOneWidget);
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
}

String _tag(ArmAssignment arm) =>
    arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';

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
    SessionEntrySurface.resetForTest();
  });

  tearDown(() {
    RemoteFeatureFlags.current = savedFlags;
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedBriefStore;
    MoodRowV2.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
  });

  group('§一 (1) switches on: companions only on page 2', () {
    for (final arm in testableArms) {
      testWidgets('${_tag(arm)}: page 1 has no companion tiles; page 2 has '
          'the three', (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, const MainShell());
        expect(
          _inPage(TodayPage, find.byKey(const ValueKey('today_v2'))),
          findsOneWidget,
        );
        expect(_inPage(TodayPage, find.byType(AgentTileRow)), findsNothing);
        expect(_inPage(TodayPage, find.text('想搵邊位傾下？')), findsNothing);
        expect(
          _inPage(TodayPage, find.text('小欣')),
          findsNothing,
          reason: 'no 小欣 tile on page 1 (the row says 同小欣 check-in)',
        );
        expect(
          _inPage(TalkPage, find.byType(AgentTileRow, skipOffstage: false)),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('today_go_talk')));
        await settle(tester);
        expect(_tab(tester), 1);
        expect(find.byType(AgentTileRow), findsOneWidget, reason: 'on screen');
        expect(find.text('小欣'), findsWidgets);
        if (run.rule) expect(run.llm.calls, isEmpty);
      });
    }
  });

  group('§一 (1) switches on: the invitation card on both pages', () {
    for (final arm in testableArms) {
      testWidgets('${_tag(arm)}: check-in from page 1\'s row → the card on '
          'page 1 (on screen) and on page 2', (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, const MainShell());
        expect(_cardOn(TodayPage), findsNothing);
        expect(_cardOn(TalkPage), findsNothing);
        await tester.tap(find.byKey(const ValueKey('today_todo_check_in')));
        await settle(tester);
        await _checkInAndLeave(tester);
        expect(_tab(tester), 0, reason: 'back on page 1');
        expect(briefStore.records, hasLength(1));
        // Page 1: inside 「今日要做嘅事」, under the check-in row, on screen.
        expect(
          find.byType(BriefPrInviteCard),
          findsOneWidget,
          reason: 'visible on page 1 (page 2 is offstage)',
        );
        final card = find.byType(BriefPrInviteCard);
        expect(
          tester.getTopLeft(card).dy >
              tester
                  .getTopLeft(find.byKey(const ValueKey('today_todo_check_in')))
                  .dy,
          isTrue,
        );
        expect(
          tester.getTopLeft(card).dy <
              tester.getTopLeft(find.byKey(const ValueKey('today_go_talk'))).dy,
          isTrue,
        );
        // Page 2 has it too.
        expect(_cardOn(TalkPage), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('today_go_talk')));
        await settle(tester);
        expect(_tab(tester), 1);
        expect(
          find.byType(BriefPrInviteCard),
          findsOneWidget,
          reason: 'visible on page 2',
        );
        if (run.rule) expect(run.llm.calls, isEmpty);
      });

      testWidgets('${_tag(arm)}: check-in from page 2\'s 小欣 tile → the card '
          'on page 2 and, back on page 1, there too', (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, const MainShell());
        await tester.tap(find.byKey(const ValueKey('today_go_talk')));
        await settle(tester);
        await tester.tap(find.text('小欣').last);
        await settle(tester);
        await _checkInAndLeave(tester);
        expect(_tab(tester), 1, reason: 'back on page 2');
        expect(find.byType(BriefPrInviteCard), findsOneWidget);
        await tester.tap(find.text('睇今日').last);
        await settle(tester);
        expect(_tab(tester), 0);
        expect(
          find.byType(BriefPrInviteCard),
          findsOneWidget,
          reason: 'visible on page 1',
        );
        expect(
          _inPage(TodayPage, find.byType(BriefPrCardHost)),
          findsOneWidget,
        );
        if (run.rule) expect(run.llm.calls, isEmpty);
      });
    }
  });

  group('§一 (1) switches off = what Junyu saw', () {
    for (final arm in testableArms) {
      testWidgets('${_tag(arm)}: companions on page 1; after a 小欣 session '
          'the card is on page 2 only', (tester) async {
        RemoteFeatureFlags.current = _layoutOff;
        final run = HomeRun(arm);
        await pumpHome(tester, run, const MainShell());
        // (a) the old page 1: the three companions are on it.
        expect(
          _inPage(TodayPage, find.byKey(const ValueKey('today_v2'))),
          findsNothing,
        );
        expect(_inPage(TodayPage, find.byType(AgentTileRow)), findsOneWidget);
        // (b) page 1 has no card host at all (the old banner switch
        // briefPrHomeBannerEnabled is off for 10/21).
        expect(_inPage(TodayPage, find.byType(BriefPrCardHost)), findsNothing);
        await tester.ensureVisible(_inPage(TodayPage, find.text('小欣')).first);
        await tester.tap(_inPage(TodayPage, find.text('小欣')).first);
        await settle(tester);
        await _checkInAndLeave(tester);
        expect(_tab(tester), 0);
        expect(briefStore.records, hasLength(1));
        expect(_cardOn(TodayPage), findsNothing, reason: 'Junyu (b)');
        expect(_cardOn(TalkPage), findsOneWidget);
        if (run.rule) expect(run.llm.calls, isEmpty);
      });
    }

    testWidgets('all three off: the old page 1 too', (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags();
      final run = HomeRun(testableArms.first);
      await pumpHome(tester, run, const MainShell());
      expect(
        _inPage(TodayPage, find.byKey(const ValueKey('today_v2'))),
        findsNothing,
      );
      expect(_inPage(TodayPage, find.byType(AgentTileRow)), findsOneWidget);
    });
  });

  group(
    '§一 (1) fix: a re-read that changes a home switch rebuilds the tabs',
    () {
      for (final arm in testableArms) {
        testWidgets('${_tag(arm)}: built with the switches off (start-up read '
            'refused / timed out), the sign-in re-read turns them on → page 1 '
            'and page 2 follow at once', (tester) async {
          RemoteFeatureFlags.current = const RemoteFeatureFlags();
          final run = HomeRun(arm);
          await pumpHome(tester, run, const MainShell());
          // Close the old pop-up if the old page 1 showed one.
          if (find.byType(BottomSheet).evaluate().isNotEmpty) {
            await tester.tapAt(const Offset(10, 10));
            await settle(tester);
          }
          expect(_inPage(TodayPage, find.byType(AgentTileRow)), findsOneWidget);
          expect(
            _inPage(
              TalkPage,
              find.byKey(const ValueKey('talk_v2'), skipOffstage: false),
            ),
            findsNothing,
          );

          // What RemoteFeatureFlags.load does after a successful read.
          RemoteFeatureFlags.current = _allOn;
          RemoteFeatureFlags.reads.value++;
          await settle(tester);

          expect(_tab(tester), 0, reason: 'still on page 1');
          expect(
            _inPage(TodayPage, find.byKey(const ValueKey('today_v2'))),
            findsOneWidget,
          );
          expect(_inPage(TodayPage, find.byType(AgentTileRow)), findsNothing);
          expect(_inPage(TodayPage, find.byType(MoodRowV2)), findsOneWidget);
          expect(
            _inPage(
              TalkPage,
              find.byKey(const ValueKey('talk_v2'), skipOffstage: false),
            ),
            findsOneWidget,
          );
          // And the card then shows on page 1 after a check-in.
          await tester.tap(find.byKey(const ValueKey('today_todo_check_in')));
          await settle(tester);
          await _checkInAndLeave(tester);
          expect(find.byType(BriefPrInviteCard), findsOneWidget);
          if (run.rule) expect(run.llm.calls, isEmpty);
        });
      }

      testWidgets('a re-read with the same switches keeps the pages as they '
          'are (no rebuild, the tab stays)', (tester) async {
        final run = HomeRun(testableArms.first);
        await pumpHome(tester, run, const MainShell());
        await tester.tap(find.byKey(const ValueKey('today_go_talk')));
        await settle(tester);
        final before = tester.state(
          find.byType(TodayPage, skipOffstage: false),
        );
        RemoteFeatureFlags.current = _allOn;
        RemoteFeatureFlags.reads.value++;
        await settle(tester);
        expect(
          tester.state(find.byType(TodayPage, skipOffstage: false)),
          same(before),
        );
        expect(_tab(tester), 1);
      });

      test('the key covers the three home switches only', () {
        expect(homeSwitchesKey(_allOn), isNot(homeSwitchesKey(_layoutOff)));
        expect(
          homeSwitchesKey(const RemoteFeatureFlags()),
          isNot(homeSwitchesKey(_layoutOff)),
        );
        expect(
          homeSwitchesKey(_allOn),
          homeSwitchesKey(
            const RemoteFeatureFlags(
              homeLayoutV2Enabled: true,
              moodRowV2Enabled: true,
              checkInChatV2Enabled: true,
              voiceInputEnabled: true,
            ),
          ),
        );
      });
    },
  );

  group('§二 (1) questionnaire row: title + small second line', () {
    final w0 = DateTime(2026, 10, 14);
    const cfg = PhaseBConfig(weeklyScheduleV2Enabled: true);
    Future<QuestionnaireRowInfo> at(DateTime now) async =>
        (await QuestionnaireRowInfo.resolve(
          cfg: cfg,
          mode: WeeklyScheduleMode.standard,
          w0: w0,
          now: now,
          store: FakeWeeklyStore(),
        ))!;

    test('not open (W4): split at its colon, same words', () async {
      final i = await at(DateTime(2026, 10, 20, 10));
      expect(i.title, '下次問卷');
      expect(i.subtitle, '10月21日（星期三）開，開咗之後三日內答都得。');
      expect('${i.title}：${i.subtitle}', i.text);
    });

    test('open (W5): W5 (no full stop) as the title; the deadline day '
        'underneath', () async {
      // The window 10/21 20:00 – 10/24 20:00: last day 10/24.
      for (final (now, title) in [
        (DateTime(2026, 10, 21, 20, 30), '問卷開咗，請盡快回答'),
        (DateTime(2026, 10, 23, 9), '問卷開咗，聽日截止'),
        (DateTime(2026, 10, 24, 8), '問卷開咗，今晚截止'),
      ]) {
        final i = await at(now);
        expect(i.title, title, reason: '$now');
        expect(i.subtitle, '10月24日（星期六）截止', reason: '$now');
      }
    });

    test('week 4 (closes after the visit): no second line', () async {
      final i = await at(DateTime(2026, 11, 11, 9));
      expect(i.title, '問卷開咗，記得喺見面之前答埋佢');
      expect(i.subtitle, isNull);
    });

    test('a window ending at midnight ends the day before', () {
      expect(
        QuestionnaireRowInfo.lastDay(
          WeeklyWindow(DateTime(2026, 10, 21), DateTime(2026, 10, 24)),
        ),
        DateTime(2026, 10, 23),
      );
    });

    for (final arm in testableArms) {
      testWidgets('${_tag(arm)}: open — the same tile as the check-in row, '
          'title, small line, arrow, tappable; no separate card', (
        tester,
      ) async {
        final run = HomeRun(arm, now: DateTime(2026, 10, 22, 21));
        await pumpHome(tester, run, const MainShell());
        final row = find.byKey(const ValueKey('today_todo_questionnaire_open'));
        if (!FeatureFlags.phaseB) {
          // The study-week schedule needs a Phase B build.
          expect(row, findsNothing);
          return;
        }
        expect(row, findsOneWidget);
        final tile = tester.widget<TodoRowTile>(row);
        expect(tile.title, '問卷開咗，請盡快回答');
        expect(tile.subtitle, '10月24日（星期六）截止');
        expect(tile.onTap, isNotNull, reason: 'opens the questionnaire');
        expect(
          find.descendant(
            of: row,
            matching: find.byIcon(Icons.chevron_right_rounded),
          ),
          findsOneWidget,
        );
        // Same widget and size of words as the check-in row.
        final checkIn = tester.widget<TodoRowTile>(
          find.byKey(const ValueKey('today_todo_check_in')),
        );
        expect(checkIn.runtimeType, tile.runtimeType);
        Text textOf(String s) => tester.widget<Text>(
          find.descendant(of: find.byType(TodoRowTile), matching: find.text(s)),
        );
        expect(
          textOf(tile.title).style?.fontSize,
          textOf(HomeV2Copy.checkInRow).style?.fontSize,
        );
        expect(
          textOf(tile.subtitle!).style!.fontSize!,
          lessThan(textOf(tile.title).style!.fontSize!),
        );
        // Not the old big card; not a Card at all.
        expect(find.byKey(const ValueKey('weekly_bundle_card')), findsNothing);
        expect(
          find.descendant(of: row, matching: find.byType(Card)),
          findsNothing,
        );
        expect(
          find.byType(PendingPromptsBanner),
          findsNothing,
          reason: 'no Firebase in tests: the banner is not built',
        );
        if (run.rule) expect(run.llm.calls, isEmpty);
      });

      testWidgets('${_tag(arm)}: not open — two lines, no arrow, not '
          'tappable (as before)', (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, const MainShell());
        final row = find.byKey(const ValueKey('today_todo_questionnaire_next'));
        if (!FeatureFlags.phaseB) {
          expect(row, findsNothing);
          return;
        }
        final tile = tester.widget<TodoRowTile>(row);
        expect(tile.title, '下次問卷');
        expect(tile.subtitle, '10月21日（星期三）開，開咗之後三日內答都得。');
        expect(tile.onTap, isNull);
        expect(
          find.descendant(
            of: row,
            matching: find.byIcon(Icons.chevron_right_rounded),
          ),
          findsNothing,
        );
      });
    }

    testWidgets('layout off: no questionnaire row', (tester) async {
      RemoteFeatureFlags.current = _layoutOff;
      final run = HomeRun(testableArms.first, now: DateTime(2026, 10, 22, 21));
      await pumpHome(tester, run, const MainShell());
      expect(
        find.byType(QuestionnaireTodoRow, skipOffstage: false),
        findsNothing,
      );
    });
  });
}
