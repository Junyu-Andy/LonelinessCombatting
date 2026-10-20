// T33 — final copy in the app matches docs/spec/copy/ word for word.
//   - rule-templates.md: all 41 Arm B template replies, their mood group
//     and agent.
//   - short-texts.md: S1a (Tung Tung search-off reply), S3 (reminiscence
//     landing) and S5 (onboarding usage advice).  S2 / S4a are server-side, see
//     functions/test/final_copy_test.js.
//   - check-in-chat.md (1020 F) and home-v2.md (1020 D, E, G (2)): drafts.
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/config/usage_copy.dart';
import 'package:app_demo/core/voice/voice_copy.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/context/data/check_in_chat_copy.dart';
import 'package:app_demo/features/context/data/siu_yan_rule_chat_pool.dart';
import 'package:app_demo/features/curious_companion/data/tung_tung_search_intent.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_landing.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_pool.dart';
import 'package:app_demo/features/today/data/home_v2_copy.dart';
import 'package:app_demo/features/today/data/mood_row_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Table rows of a spec file as trimmed cells (header / rule rows kept;
/// callers match on the first cell).
List<List<String>> _rows(String file) => File('docs/spec/copy/$file')
    .readAsLinesSync()
    .where((l) => l.startsWith('| '))
    .map((l) => l
        .substring(1, l.length - 1)
        .split('|')
        .map((c) => c.trim())
        .toList())
    .toList();

const _moodBand = {
  '好開心': 'very_happy',
  '幾好': 'good',
  '一般般': 'so_so',
  '唔係幾好': 'not_good',
  '好唔開心': 'very_unhappy',
};

void main() {
  final templateRows = _rows('rule-templates.md');
  final idPattern = RegExp(r'^([XZ]\d-\d|G-1)$');
  final spec = {
    for (final r in templateRows)
      if (idPattern.hasMatch(r[0])) r[0]: r,
  };
  // 1020 F (6): the X rows of the main tables are the 5.4 texts (by Q1,
  // 尋日), used by the chat check-in; Z and G-1 are unchanged.
  final pool = {
    for (final e in RuleReplyPool.entries)
      if (!e.id.startsWith('X')) e.id: e,
    for (final e in RuleReplyPool.checkInChatEntries) e.id: e,
  };
  // The 10/10 X texts, kept for the old form (switch off): rows `L-X…`.
  final legacySpec = {
    for (final r in templateRows)
      if (r[0].startsWith('L-X')) r[0].substring(2): r,
  };

  group('rule-templates.md', () {
    test('41 entries, same ids', () {
      expect(spec.length, 41);
      expect(pool.keys.toSet(), spec.keys.toSet());
    });

    test('1020 F (6): X1–X5 are labelled 「按 Q1 尋日整體分档」, 4 per band',
        () {
      final doc = File('docs/spec/copy/rule-templates.md').readAsStringSync();
      expect(doc, contains('## 小欣：check-in 回应一（按 Q1 尋日整體分档）'));
      expect(RuleReplyPool.checkInChatEntries, hasLength(20));
      for (final band in _moodBand.values) {
        expect(RuleReplyPool.checkInChatSubPool(band), hasLength(4),
            reason: band);
      }
    });

    test('old form (switch off): the 10/10 X texts, verbatim, unchanged',
        () {
      expect(legacySpec.length, 20);
      for (final MapEntry(key: id, value: row) in legacySpec.entries) {
        final e = RuleReplyPool.entries.firstWhere((x) => x.id == id);
        expect(e.zh, row[2], reason: id);
        expect(e.band, _moodBand[row[1]], reason: id);
      }
      expect(RuleReplyPool.version, '2026-10-10-final');
    });

    test('every text is verbatim, in the right agent and mood group', () {
      for (final MapEntry(key: id, value: row) in spec.entries) {
        final e = pool[id]!;
        if (id == 'G-1') {
          expect(e.zh, row[1], reason: id);
          expect((e.agent, e.band), ('any', 'none'), reason: id);
          continue;
        }
        expect(e.zh, row[2], reason: id);
        expect(e.band, _moodBand[row[1]], reason: id);
        expect(e.agent, id.startsWith('X') ? 'siu_yan' : 'ah_jan_ah_bak',
            reason: id);
      }
    });

    test('no placeholder left, no uncorrected character', () {
      expect(RuleReplyPool.hasPlaceholders, isFalse);
      // The 「已更正的字」 table: none of the old characters remain.
      for (final old in ['侾', '傳', '諦', '゗', '捣', '鐘意']) {
        for (final e in [
          ...RuleReplyPool.entries,
          ...RuleReplyPool.checkInChatEntries,
        ]) {
          expect(e.zh.contains(old), isFalse, reason: '${e.id} $old');
        }
      }
    });
  });

  group('short-texts.md', () {
    final short = {for (final r in _rows('short-texts.md')) r[0]: r[2]};

    test('S1a: Tung Tung search-off reply', () {
      expect(TungTungSearchIntent.reply(isEn: false), short['S1a']);
      expect(TungTungSearchIntent.reply(isEn: true), short['S1a']);
    });

    // T27 — shown next to the input box after a failed transcription.
    test('S6: voice transcription failed', () {
      expect(VoiceCopy.s6TranscriptionFailed, short['S6']);
    });

    test('S3: reminiscence landing count sentence', () {
      expect(ReminiscenceLandingPage.s3(4), short['S3']);
    });

    testWidgets('S3: shown on the landing page', (tester) async {
      await tester.pumpWidget(
        AppSettingsScope(
          settings: AppSettings(locale: const Locale('zh')),
          child: AuthServiceScope(
            authService: AuthService(available: false),
            child: const MaterialApp(
              locale: Locale('zh'),
              supportedLocales: [Locale('zh'), Locale('en')],
              localizationsDelegates: [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: ReminiscenceLandingPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining(short['S3']!), findsOneWidget);
      expect(find.textContaining('4 個禮拜'), findsNothing);
    });

    test('S5: onboarding usage advice', () {
      expect(UsageCopy.onboardingUsageAdviceS5, short['S5']);
    });
  });

  // 1020 F — the chat check-in and the rule arm's Siu Yan chat (drafts,
  // 1020b §4 5.2b / 5.3).
  group('check-in-chat.md', () {
    final rows = {for (final r in _rows('check-in-chat.md')) r[0]: r};
    List<String> buttons(String cell) => cell.split('／');

    test('questions Q0–Q6 and their buttons, verbatim', () {
      expect(CheckInChatCopy.q0Morning, rows['Q0']![2]);
      expect(CheckInChatCopy.q1, rows['Q1']![2]);
      expect(CheckInChatCopy.q2, rows['Q2']![2]);
      expect(CheckInChatCopy.q3, rows['Q3']![2]);
      expect(CheckInChatCopy.q3b, rows['Q3b']![2]);
      expect(CheckInChatCopy.q4, rows['Q4']![2]);
      expect(CheckInChatCopy.q5, rows['Q5']![2]);
      expect(CheckInChatCopy.q6, rows['Q6']![2]);
      String labels(List<CheckInOption> o) => o.map((x) => x.label).join('／');
      expect(labels(CheckInChatCopy.q1Options), rows['Q1']![3]);
      expect(labels(CheckInChatCopy.q2Options), rows['Q2']![3]);
      expect(labels(CheckInChatCopy.q3Options), rows['Q3']![3]);
      expect(labels(CheckInChatCopy.q5Options), rows['Q5']![3]);
      expect(buttons(rows['Q1']!.last), hasLength(6));
      for (final q in ['Q3b', 'Q4']) {
        expect(rows[q]![3], '输入框；${CheckInChatCopy.skipLabel}');
      }
    });

    test('input box hint: typing only (1020e 二.5)', () {
      expect(CheckInChatCopy.inputHint, rows['HINT']![2]);
      expect(CheckInChatCopy.inputHint.contains('講都得'), isFalse);
    });

    test('rule arm fixed lines XG, R4a, R4b, SY0', () {
      expect(CheckInChatCopy.xg, rows['XG']![2]);
      expect(CheckInChatCopy.r4a, rows['R4a']![2]);
      expect(CheckInChatCopy.r4b, rows['R4b']![2]);
      expect(CheckInChatCopy.sy0, rows['SY0']![2]);
    });

    test('rule arm chat pool SY1–SY6, SN1–SN4', () {
      for (final e in [
        ...SiuYanRuleChatPool.general,
        ...SiuYanRuleChatPool.low,
      ]) {
        expect(e.zh, rows[e.id]![2], reason: e.id);
      }
      expect(SiuYanRuleChatPool.general.map((e) => e.id),
          ['SY1', 'SY2', 'SY3', 'SY4', 'SY5', 'SY6']);
      expect(SiuYanRuleChatPool.low.map((e) => e.id),
          ['SN1', 'SN2', 'SN3', 'SN4']);
    });
  });
  // 1020 D, E, G (2) — page 1 and the mood row (drafts, 1020b §4 5.1, 5.2,
  // 5.5; D1–D4 the development window's).
  group('home-v2.md', () {
    final rows = {for (final r in _rows('home-v2.md')) r[0]: r};

    test('mood row M1–M8, verbatim', () {
      expect(MoodRowCopy.m1, rows['M1']![2]);
      expect(MoodRowCopy.m2, rows['M2']![2]);
      expect(MoodRowCopy.m3, rows['M3']![2]);
      expect(MoodRowCopy.m4, rows['M4']![2]);
      expect(MoodRowCopy.m5Template, rows['M5']![2]);
      expect(MoodRowCopy.m6, rows['M6']![2]);
      expect(MoodRowCopy.m7, rows['M7']![2]);
      expect(MoodRowCopy.m8, rows['M8']![2]);
    });

    test('openers O1–O5, C1, C2, verbatim', () {
      expect(MoodRowCopy.openers.keys,
          ['O1', 'O2', 'O3', 'O4', 'O5', 'C1', 'C2']);
      for (final MapEntry(key: id, value: text)
          in MoodRowCopy.openers.entries) {
        expect(text, rows[id]![2], reason: id);
      }
      // O1–O5 name the same five moods as check-in Q1.
      expect(
          [for (var i = 1; i <= 5; i++) rows['O$i']![1].split('，').last],
          [for (var m = 5; m >= 1; m--) MoodRowCopy.moodWords[m]]);
    });

    test('page 1 D1–D4 and the questionnaire W4, W5, verbatim', () {
      expect(HomeV2Copy.todoTitle, rows['D1']![2]);
      expect(HomeV2Copy.checkInRow, rows['D2']![2]);
      expect(HomeV2Copy.checkInMissed, rows['D3']![2]);
      expect(HomeV2Copy.goTalk, rows['D4']![2]);
      expect(HomeV2Copy.w4Template, rows['W4']![2]);
      expect(HomeV2Copy.w5Template, rows['W5']![2]);
      expect(HomeV2Copy.w5Asap, rows['W5a']![2]);
      expect(HomeV2Copy.w5Tomorrow, rows['W5b']![2]);
      expect(HomeV2Copy.w5Tonight, rows['W5c']![2]);
      expect(HomeV2Copy.w5BeforeVisit, rows['W5d']![2]);
      expect(HomeV2Copy.w4(DateTime(2026, 10, 25)),
          '下次問卷：10月25日（星期日）開，開咗之後三日內答都得。');
      expect(HomeV2Copy.w5(HomeV2Copy.w5Tomorrow), '問卷開咗，聽日截止。');
      // 1020l §二 (1): two lines.
      expect(HomeV2Copy.w5DeadlineTemplate, rows['W5-2']![2]);
      expect(HomeV2Copy.w5Deadline(DateTime(2026, 10, 24)),
          '10月24日（星期六）截止');
      expect(HomeV2Copy.w4Title, '下次問卷');
      expect(HomeV2Copy.w4Subtitle(DateTime(2026, 10, 25)),
          '10月25日（星期日）開，開咗之後三日內答都得。');
    });

    test('1020m 第二节: the small-action row SA1–SA5, verbatim', () {
      expect(HomeV2Copy.smallActionAsk, rows['SA1']![2]);
      expect(HomeV2Copy.smallActionLater, rows['SA2']![2]);
      expect(HomeV2Copy.smallActionPlanTemplate, rows['SA3']![2]);
      expect(HomeV2Copy.smallActionDone, rows['SA4']![2]);
      expect(HomeV2Copy.smallActionPostpone, rows['SA5']![2]);
      expect(HomeV2Copy.smallActionPlan('同阿明飲茶'), '今日計劃：同阿明飲茶');
    });

    test('1020e 二.12: the five face words F1–F5 = check-in Q1 words', () {
      for (var m = 1; m <= 5; m++) {
        expect(MoodRowCopy.faceLabel(m), rows['F$m']![2], reason: 'F$m');
        expect(rows['F$m']![1], startsWith('$m '));
      }
      // Same word for the same score as the check-in Q1 button.
      for (final o in CheckInChatCopy.q1Options) {
        if (o.score == null) continue;
        expect(MoodRowCopy.faceLabel(o.score!), o.label, reason: o.code);
      }
    });
  });
}
