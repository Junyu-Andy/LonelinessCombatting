// 1020 E (batch 3) — the mood row on page 1 behind `moodRowV2Enabled`:
//   - the state table: not answered (M1 + faces + M2) / skipped (M4) /
//     answered (M5, M3 briefly, M6, M7) / answered again, same (M7 stays) /
//     answered again, different (M8 replaces M7);
//   - records: one daily_mood row per pick (first primary, the rest
//     supplementary, with a time); a skip logs one event;
//   - no pop-ups (no sheet, no snackbar, no dialog) in either arm;
//   - M7 / M8 rules (tapped, check-in done, next open);
//   - M7 / M8 open 小欣's chat, not the check-in: rule arm O1–O5 / C1 /
//     C2 then SY / SN with ZERO LLM calls; Hybrid an LLM opener with the
//     mood (and the change) in `[開場·心情]`, prompt siu_yan_v4;
//   - 1020b §2 (1): homeMoodOpensCheckInEnabled cannot take effect.
//
// Two-arm cases need a Phase B build:
//   flutter test --dart-define=PHASE_B=true test/mood_row_v2_test.dart
// (tool/ci_flutter_tests.sh "phase B arm gating").  In the default build
// everybody is Hybrid and the rule-arm cases are skipped.
import 'dart:io';

import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/context/data/check_in_chat_copy.dart';
import 'package:app_demo/features/context/data/siu_yan_rule_chat_pool.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_a.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_b.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/thought_exercise/presentation/naming_thought_card.dart';
import 'package:app_demo/features/today/data/mood_row_copy.dart';
import 'package:app_demo/features/today/data/mood_row_store.dart';
import 'package:app_demo/features/today/presentation/widgets/daily_mood_prompt.dart';
import 'package:app_demo/features/today/presentation/widgets/greeting_hero.dart';
import 'package:app_demo/features/today/presentation/widgets/mood_row_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_v2_harness.dart';

const _hero = Scaffold(body: SingleChildScrollView(child: GreetingHero()));

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await settle(tester);
}

Future<void> _pick(WidgetTester tester, int rank) =>
    _tap(tester, ValueKey('mood_row_face_$rank'));

/// Lets M3 「記低咗」 time out (2 s).
Future<void> _afterM3(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
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
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    RemoteFeatureFlags.current = const RemoteFeatureFlags(
      moodRowV2Enabled: true,
      checkInChatV2Enabled: true,
    );
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

  group('copy and entries (pure)', () {
    test('M5 reads face, word and time', () {
      expect(MoodRowCopy.m5(4, DateTime(2026, 10, 20, 9, 12)),
          '今日心情：🙂 幾好（09:12）');
      expect(MoodRowCopy.m5(1, DateTime(2026, 10, 20, 21, 5)),
          '今日心情：😔 好唔開心（21:05）');
      expect(MoodRowCopy.m5(5, DateTime(2026, 10, 20, 7, 0)),
          '今日心情：😊 好開心（07:00）');
    });

    test('M7 openers by mood: 5 → O1 … 1 → O5; low ones are O4, O5', () {
      expect([for (var m = 5; m >= 1; m--) MoodChatEntry(mood: m).openerId],
          ['O1', 'O2', 'O3', 'O4', 'O5']);
      expect([for (var m = 5; m >= 1; m--) MoodChatEntry(mood: m).lowOpener],
          [false, false, false, true, true]);
      expect(const MoodChatEntry(mood: 4).promptId, 'M7');
      expect(const MoodChatEntry(mood: 4).direction, isNull);
    });

    test('M8: better → C1, worse → C2 (low); same mood is not a change', () {
      const up = MoodChatEntry(mood: 4, previousMood: 2);
      const down = MoodChatEntry(mood: 4, previousMood: 5);
      expect((up.promptId, up.openerId, up.direction, up.lowOpener),
          ('M8', 'C1', 'up', false));
      expect((down.promptId, down.openerId, down.direction, down.lowOpener),
          ('M8', 'C2', 'down', true));
      const same = MoodChatEntry(mood: 3, previousMood: 3);
      expect((same.changed, same.openerId), (false, 'O3'));
    });

    test('Hybrid context block: the mood, and for M8 the change — never '
        'anything the elder wrote', () {
      expect(const MoodChatEntry(mood: 2).contextBlock,
          '[開場·心情]\n入口：M7（想同小欣講詳細啲？）\n用戶而家揀嘅心情：唔係幾好（2/5）');
      expect(
          const MoodChatEntry(mood: 2, previousMood: 4).contextBlock,
          '[開場·心情]\n入口：M8（心情好似唔同咗，想同小欣講下發生咩事？）\n'
          '用戶而家揀嘅心情：唔係幾好（2/5）\n之前揀嘅心情：幾好（4/5）\n變化：差咗');
    });

    test('1020b §2 (1): with moodRowV2Enabled the old "mood opens the '
        'check-in" path is closed whatever its field says', () {
      for (final row in [false, true]) {
        for (final old in [false, true]) {
          final f = RemoteFeatureFlags.fromMap({
            'moodRowV2Enabled': row,
            'homeMoodOpensCheckInEnabled': old,
          });
          expect(f.homeMoodOpensCheckInActive, old && !row,
              reason: 'row $row old $old');
        }
      }
    });
  });

  group('state table (both arms the same)', () {
    for (final arm in testableArms) {
      final tag = arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';

      testWidgets('$tag: not answered → M1, five faces, M2; no M7',
          (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, _hero);
        expect(find.byType(MoodRowV2), findsOneWidget);
        expect(find.text(MoodRowCopy.m1), findsOneWidget);
        expect(find.text(MoodRowCopy.m2), findsOneWidget);
        for (var r = 1; r <= 5; r++) {
          expect(find.byKey(ValueKey('mood_row_face_$r')), findsOneWidget);
        }
        // 1020e 二.12: the check-in Q1 words under the faces.
        for (final w in ['好唔開心', '唔係幾好', '一般般', '幾好', '好開心']) {
          expect(find.text(w), findsOneWidget, reason: w);
        }
        for (final old in ['好差', '麻麻地', '好好']) {
          expect(find.text(old), findsNothing, reason: old);
        }
        expect(find.text(MoodRowCopy.m7), findsNothing);
        // The old pad's line is gone.
        expect(find.textContaining('今日感覺點？'), findsNothing);
        expect(run.llm.calls, isEmpty);
      });

      testWidgets('$tag: 遲啲先答 → M4 for the day (also after a reopen), '
          'one skip event, no row; tap M4 opens the faces', (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, _hero);
        await _tap(tester, const ValueKey('mood_row_later'));
        expect(find.text(MoodRowCopy.m4), findsOneWidget);
        expect(find.byKey(const ValueKey('mood_row_face_3')), findsNothing);
        expect(run.moodStore.marks[MoodRowStore.skippedKey], '2026-10-20');
        expect(run.moodStore.entries, isEmpty);
        final skips = run.analytics.named('mood_checkin');
        expect(skips, [
          {'skipped': true, 'source': 'home_mood_row'},
        ]);

        // Reopen (a new page, same phone): still M4, not opened by itself.
        await tester.pumpWidget(const SizedBox());
        await pumpHome(tester, run, _hero);
        expect(find.text(MoodRowCopy.m4), findsOneWidget);
        expect(find.byKey(const ValueKey('mood_row_face_3')), findsNothing);

        await _tap(tester, const ValueKey('mood_row_unanswered'));
        expect(find.byKey(const ValueKey('mood_row_face_3')), findsOneWidget);
        expect(find.text(MoodRowCopy.m2), findsNothing);
        await _pick(tester, 3);
        expect(find.text(MoodRowCopy.m5(3, run.now)), findsOneWidget);

        // The next day: M1 again.
        run.now = DateTime(2026, 10, 21, 9, 0);
        await tester.pumpWidget(const SizedBox());
        await pumpHome(tester, run, _hero);
        expect(find.text(MoodRowCopy.m1), findsOneWidget);
        expect(find.text(MoodRowCopy.m2), findsOneWidget);
      });

      testWidgets('$tag: answered → M5 with the time, M3 briefly, M6, M7; '
          'one primary daily_mood row', (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, _hero);
        await _pick(tester, 4);
        expect(find.text('今日心情：🙂 幾好（09:30）'), findsOneWidget);
        expect(find.text(MoodRowCopy.m3), findsOneWidget);
        expect(find.text(MoodRowCopy.m7), findsOneWidget);
        await _afterM3(tester);
        expect(find.text(MoodRowCopy.m3), findsNothing);
        expect(find.text(MoodRowCopy.m6), findsOneWidget);
        expect(find.text(MoodRowCopy.m8), findsNothing);

        final row = run.moodStore.entries.single;
        expect((row.mood, row.dateIso, row.isPrimary, row.supplementary,
                row.entrySeqToday, row.sourceSurface, row.arm),
            (4, '2026-10-20', true, false, 1, 'home_mood_row',
                run.rule ? 'B' : 'A'));
        expect(row.respondedAt, run.now);
        expect(run.analytics.named('daily_mood_submitted'), [
          {'mood': 4},
        ]);
        expect(run.analytics.named('mood_checkin').single['supplementary'],
            isFalse);
        // No pop-ups at all (E (1)): no snackbar, no dialog, no sheet.
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(CheckInArmA), findsNothing);
        expect(run.llm.calls, isEmpty);
      });

      testWidgets('$tag: answered again, same → M5 new time, M7 stays; '
          'second row supplementary', (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, _hero);
        await _pick(tester, 4);
        await _afterM3(tester);
        run.now = DateTime(2026, 10, 20, 15, 5);
        await _tap(tester, const ValueKey('mood_row_change'));
        expect(find.byKey(const ValueKey('mood_row_face_4')), findsOneWidget);
        await _pick(tester, 4);
        expect(find.text('今日心情：🙂 幾好（15:05）'), findsOneWidget);
        expect(find.text(MoodRowCopy.m7), findsOneWidget);
        expect(find.text(MoodRowCopy.m8), findsNothing);
        expect(run.moodStore.entries, hasLength(2));
        final second = run.moodStore.entries[1];
        expect((second.isPrimary, second.supplementary, second.entrySeqToday),
            (false, true, 2));
        expect(run.analytics.named('daily_mood_supplementary'), [
          {'mood': 4, 'source_surface': 'home_mood_row'},
        ]);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
      });

      testWidgets('$tag: answered again, different → M8 replaces M7; M8 '
          'gone after the App goes to the background; M7 does not come '
          'back that day', (tester) async {
        final run = HomeRun(arm);
        await pumpHome(tester, run, _hero);
        await _pick(tester, 4);
        await _afterM3(tester);
        await _tap(tester, const ValueKey('mood_row_change'));
        await _pick(tester, 2);
        await _afterM3(tester);
        expect(find.text(MoodRowCopy.m5(2, run.now)), findsOneWidget);
        expect(find.text(MoodRowCopy.m8), findsOneWidget);
        expect(find.text(MoodRowCopy.m7), findsNothing);
        expect(run.moodStore.entries.map((e) => e.isPrimary), [true, false]);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(AlertDialog), findsNothing, reason: 'no dialog');

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await settle(tester);
        expect(find.text(MoodRowCopy.m8), findsNothing);
        expect(find.text(MoodRowCopy.m7), findsNothing);
        expect(find.text(MoodRowCopy.m5(2, run.now)), findsOneWidget);
      });

      testWidgets('$tag: a row already there today → M5 with its time, M7',
          (tester) async {
        final run = HomeRun(arm);
        run.seedMood(5, DateTime(2026, 10, 20, 8, 7));
        await pumpHome(tester, run, _hero);
        expect(find.text('今日心情：😊 好開心（08:07）'), findsOneWidget);
        expect(find.text(MoodRowCopy.m7), findsOneWidget);
        expect(find.text(MoodRowCopy.m1), findsNothing);
      });

      testWidgets('$tag: M7 hidden once today\'s check-in is done',
          (tester) async {
        final run = HomeRun(arm)..checkedIn = true;
        run.seedMood(3, DateTime(2026, 10, 20, 8, 0));
        await pumpHome(tester, run, _hero);
        expect(find.text(MoodRowCopy.m5(3, DateTime(2026, 10, 20, 8, 0))),
            findsOneWidget);
        expect(find.text(MoodRowCopy.m7), findsNothing);
      });

      testWidgets('$tag: without the chat window switch, no M7 / M8',
          (tester) async {
        RemoteFeatureFlags.current =
            const RemoteFeatureFlags(moodRowV2Enabled: true);
        final run = HomeRun(arm);
        await pumpHome(tester, run, _hero);
        await _pick(tester, 4);
        await _afterM3(tester);
        await _tap(tester, const ValueKey('mood_row_change'));
        await _pick(tester, 1);
        expect(find.text(MoodRowCopy.m7), findsNothing);
        expect(find.text(MoodRowCopy.m8), findsNothing);
      });

      testWidgets('$tag: M7 tapped → 小欣 chat (M7 entry); back → M7 gone '
          'for the day', (tester) async {
        final run = HomeRun(arm)..realChat = false;
        await pumpHome(tester, run, _hero);
        await _pick(tester, 5);
        await _tap(tester, const ValueKey('mood_row_m7'));
        expect(find.text('chat M7'), findsOneWidget);
        expect(run.moodChats.single.mood, 5);
        expect(run.analytics.named('mood_row_chat_opened').single, {
          'prompt': 'M7',
          'mood': 5,
          'opener_id': 'O1',
          'copy_version': MoodRowCopy.version,
        });
        run.navKey.currentState!.pop();
        await settle(tester);
        expect(find.text(MoodRowCopy.m7), findsNothing);
        expect(run.moodStore.marks[MoodRowStore.m7DoneKey], '2026-10-20');
        await tester.pumpWidget(const SizedBox());
        await pumpHome(tester, run, _hero);
        expect(find.text(MoodRowCopy.m7), findsNothing);
      });

      testWidgets('$tag: M8 tapped → 小欣 chat with the change; gone after',
          (tester) async {
        final run = HomeRun(arm)..realChat = false;
        await pumpHome(tester, run, _hero);
        await _pick(tester, 2);
        await _afterM3(tester);
        await _tap(tester, const ValueKey('mood_row_change'));
        await _pick(tester, 4);
        await _tap(tester, const ValueKey('mood_row_m8'));
        expect(find.text('chat M8'), findsOneWidget);
        final e = run.moodChats.single;
        expect((e.mood, e.previousMood, e.openerId), (4, 2, 'C1'));
        expect(run.analytics.named('mood_row_chat_opened').single['direction'],
            'up');
        run.navKey.currentState!.pop();
        await settle(tester);
        expect(find.text(MoodRowCopy.m8), findsNothing);
        expect(find.text(MoodRowCopy.m7), findsNothing);
      });
    }
  });

  group('1020b §2 (1): the old path is unreachable', () {
    testWidgets('moodRowV2Enabled + homeMoodOpensCheckInEnabled: a pick '
        'opens nothing (no check-in page, no chat), the row just records',
        (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags(
        moodRowV2Enabled: true,
        checkInChatV2Enabled: true,
        homeMoodOpensCheckInEnabled: true,
      );
      for (final arm in testableArms) {
        MoodRowV2.resetForTest();
        final run = HomeRun(arm);
        await pumpHome(tester, run, _hero);
        await _pick(tester, 3);
        expect(find.byType(CheckInArmA), findsNothing);
        expect(find.byType(CheckInArmB), findsNothing);
        expect(find.byType(SiuYanChatPage), findsNothing);
        expect(find.byType(GreetingHero), findsOneWidget);
        expect(find.text(MoodRowCopy.m5(3, run.now)), findsOneWidget);
        expect(run.moodStore.entries, hasLength(1));
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('switch off: the old pad (and its line) is back',
        (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags();
      final run = HomeRun(testableArms.first);
      await pumpHome(tester, run, _hero);
      expect(find.byType(MoodRowV2), findsNothing);
      expect(find.text('今日感覺點？（隨時可以再記）'), findsOneWidget);
    });
  });

  group('M7 / M8 open 小欣 chat with an opener (not the check-in)', () {
    Future<HomeRun> open(WidgetTester tester, ArmAssignment arm,
        MoodChatEntry entry) async {
      final run = HomeRun(arm);
      await pumpHome(tester, run, const Scaffold(body: Text('home')));
      run.navKey.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => run.chatPage(entry: entry)));
      await settle(tester);
      return run;
    }

    void noCheckIn() {
      expect(says(CheckInChatCopy.q0Morning), findsNothing);
      expect(says(CheckInChatCopy.q1), findsNothing);
      expect(says(CheckInChatCopy.sy0), findsNothing);
    }

    for (var mood = 5; mood >= 1; mood--) {
      final entry = MoodChatEntry(mood: mood);
      testWidgets('rule arm M7, mood $mood → ${entry.openerId}, zero LLM',
          (tester) async {
        final run = await open(tester, ArmAssignment.b, entry);
        expect(says(entry.openerText), findsOneWidget);
        noCheckIn();
        // Chatting on: SY, or SN after O4 / O5.
        await _type(tester, '今朝去咗飲茶');
        final pool = entry.lowOpener
            ? SiuYanRuleChatPool.low
            : SiuYanRuleChatPool.general;
        expect(says(pool.first.zh), findsOneWidget);
        expect(run.llm.calls, isEmpty, reason: 'rule arm: zero LLM calls');
        expect(run.analytics.named('rule_template_reply').first, {
          'agent_id': 'siu_yan',
          'module_id': 'siu_yan_chat',
          'template_id': entry.openerId,
          'pool_version': MoodRowCopy.version,
          'theme': 'mood_opener',
        });
        expect(run.checkIns.docs, isEmpty, reason: 'no check-in record');
      }, skip: !ruleTestable);
    }

    for (final (entry, low) in [
      (const MoodChatEntry(mood: 4, previousMood: 2), false),
      (const MoodChatEntry(mood: 2, previousMood: 4), true),
    ]) {
      testWidgets('rule arm M8 ${entry.direction} → ${entry.openerId}, then '
          '${low ? 'SN' : 'SY'}; zero LLM', (tester) async {
        final run = await open(tester, ArmAssignment.b, entry);
        expect(says(entry.openerText), findsOneWidget);
        noCheckIn();
        await _type(tester, '頭先個女打電話嚟');
        expect(
            says((low ? SiuYanRuleChatPool.low : SiuYanRuleChatPool.general)
                .first
                .zh),
            findsOneWidget);
        expect(run.llm.calls, isEmpty);
      }, skip: !ruleTestable);
    }

    testWidgets('rule arm: three messages after an opener make a valid '
        'free-chat session (one Brief PR invitation), zero LLM',
        (tester) async {
      final run =
          await open(tester, ArmAssignment.b, const MoodChatEntry(mood: 3));
      await _type(tester, '一');
      await _type(tester, '二');
      await _type(tester, '三');
      await tester.tap(find.text('今日傾到呢度'));
      await settle(tester);
      expect(briefStore.records, hasLength(1));
      expect(briefStore.records.values.single.sessionType, 'free_chat');
      expect(run.llm.calls, isEmpty);
    }, skip: !ruleTestable);

    testWidgets('Hybrid M7: the LLM opens (siu_yan_v5, [開場·心情] with the '
        'mood), no check-in', (tester) async {
      final run =
          await open(tester, ArmAssignment.a, const MoodChatEntry(mood: 2));
      expect(says(FakeLlm.moodOpener), findsOneWidget);
      expect(says(MoodRowCopy.openers['O4']!), findsNothing);
      noCheckIn();
      final c = run.llm.pageCalls.single;
      expect(c.moduleId, 'greeting_siu_yan');
      expect(c.promptKey, 'siu_yan_v5');
      expect(c.suffix, contains('[開場·心情]'));
      expect(c.suffix, contains('用戶而家揀嘅心情：唔係幾好（2/5）'));
      expect(c.suffix, isNot(contains('之前揀嘅心情')));
      // Chatting on: the LLM chat, same prompt version.
      await _type(tester, '今朝膝頭好痛');
      expect(says(FakeLlm.chat), findsOneWidget);
      expect(run.llm.pageCalls.last.promptKey, 'siu_yan_v5');
      expect(run.llm.pageCalls.last.moduleId, 'm2_check_in');
    }, skip: !hybridTestable);

    testWidgets('Hybrid M8: the change is in the block', (tester) async {
      final run = await open(tester, ArmAssignment.a,
          const MoodChatEntry(mood: 5, previousMood: 3));
      expect(says(FakeLlm.moodOpener), findsOneWidget);
      final c = run.llm.pageCalls.single;
      expect(c.suffix, contains('用戶而家揀嘅心情：好開心（5/5）'));
      expect(c.suffix, contains('之前揀嘅心情：一般般（3/5）'));
      expect(c.suffix, contains('變化：好咗'));
    }, skip: !hybridTestable);

    testWidgets('Hybrid, model down: the 5.2 line instead', (tester) async {
      final run = HomeRun(ArmAssignment.a);
      await pumpHome(tester, run, const Scaffold(body: Text('home')));
      run.llm.fail = true;
      run.navKey.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => run.chatPage(
              entry: const MoodChatEntry(mood: 3, previousMood: 5))));
      await settle(tester);
      expect(says(MoodRowCopy.openers['C2']!), findsOneWidget);
      noCheckIn();
    }, skip: !hybridTestable);

    testWidgets('10/21 (decisions-log 134): Hybrid says 冇人會記得我 → only '
        'the invite card; 小欣 v5 does not offer the exercise or say stuck',
        (tester) async {
      final run =
          await open(tester, ArmAssignment.a, const MoodChatEntry(mood: 2));
      expect(find.byType(NamingThoughtCard), findsNothing);
      await _type(tester, '冇人會記得我');
      expect(find.byType(NamingThoughtCard), findsOneWidget);
      expect(says('你頭先講咗一句：「冇人會記得我」。'), findsOneWidget);
      // 小欣's reply (the model's text) is shown as is; nothing on the
      // page says stuck, and the only invite is the card.
      expect(says(FakeLlm.chat), findsOneWidget);
      expect(find.textContaining('stuck', findRichText: true), findsNothing);
      expect(find.textContaining('要唔要做個小練習', findRichText: true),
          findsOneWidget);
      // The call used v5, whose text never asks for the offer.
      expect(run.llm.pageCalls.last.promptKey, 'siu_yan_v5');
      final v5 = File('functions/prompts/siu_yan.v5.txt').readAsStringSync();
      expect(v5, isNot(contains('stuck')));
      expect(v5, isNot(contains('要唔要做個小練習')));
      expect(v5, contains('唔好喺對話中主動提議「望一望心入面」或者其他練習'));
    }, skip: !hybridTestable);

    testWidgets('mood row on: the check-in replies also send siu_yan_v5 '
        '(off: v3, batch 2 test)', (tester) async {
      final run = HomeRun(ArmAssignment.a);
      await pumpHome(tester, run, const Scaffold(body: Text('home')));
      run.navKey.currentState!
          .push(MaterialPageRoute<void>(builder: (_) => run.chatPage()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('check_in_answer_Q1_good')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('check_in_answer_Q2_none')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('check_in_answer_Q3_none')));
      await settle(tester);
      expect(run.llm.pageCalls.single.promptKey, 'siu_yan_v5');
      expect(SiuYanChatPage.activePromptKey, 'siu_yan_v5');
      // Batch 2 (1020e 二.8): Q4 唔講住 calls the model with
      // [簽到·唔講住] — under v4 too.
      await tester.tap(find.byKey(const ValueKey('check_in_skip')));
      await settle(tester);
      final skip = run.llm.pageCalls.last;
      expect(skip.suffix, contains('[簽到·唔講住]'));
      expect(skip.promptKey, 'siu_yan_v5');
      expect(skip.moduleId, 'm2_check_in');
      expect(says(CheckInChatCopy.q5), findsOneWidget);
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(checkInChatV2Enabled: true);
      expect(SiuYanChatPage.activePromptKey, 'siu_yan_v3');
    }, skip: !hybridTestable);

    testWidgets('end to end: page-1 row → M7 → the real chat window opens '
        'with the opener', (tester) async {
      for (final arm in testableArms) {
        MoodRowV2.resetForTest();
        ChatSessionRecorder.resetProcessStateForTest();
        final run = HomeRun(arm);
        await pumpHome(tester, run, _hero);
        await _pick(tester, 1);
        await _tap(tester, const ValueKey('mood_row_m7'));
        expect(find.byType(SiuYanChatPage), findsOneWidget);
        expect(
            says(run.rule ? MoodRowCopy.openers['O5']! : FakeLlm.moodOpener),
            findsOneWidget);
        if (run.rule) expect(run.llm.calls, isEmpty);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
