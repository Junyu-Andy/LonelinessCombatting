// 1020d — docs/spec/copy/reminiscence-v2.md and the App's one shared
// script (lib/features/reminiscence/data/reminiscence_v2_copy.dart) match
// word for word; plus the pure helpers both arms share (fixed-line
// rotation, rule-arm chapter layout, chapter request payload, edit ratio).
// Pure Dart: runs in every build.
import 'dart:io';

import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_button.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_copy.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_models.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<String>> _rows(String file) => File('docs/spec/copy/$file')
    .readAsLinesSync()
    .where((l) => l.startsWith('| '))
    .map((l) => l
        .substring(1, l.length - 1)
        .split('|')
        .map((c) => c.trim())
        .toList())
    .toList();

ReminiscenceMessage _m(ReminiscenceMessageKind kind, String text,
        {int? q, String? copyId, String? safety}) =>
    ReminiscenceMessage(
      id: 'x',
      kind: kind,
      text: text,
      at: DateTime(2026, 10, 21),
      questionIndex: q,
      copyId: copyId,
      safety: safety,
    );

void main() {
  final rows = {for (final r in _rows('reminiscence-v2.md')) r[0]: r};

  group('reminiscence-v2.md = reminiscence_v2_copy.dart, word for word', () {
    test('openers (three bubbles; week 1 and weeks 2–4)', () {
      for (var i = 0; i < 3; i++) {
        expect(ReminiscenceV2Copy.week1Opener[i], rows['O1-${i + 1}']![2]);
        expect(ReminiscenceV2Copy.laterOpener[i], rows['O2-${i + 1}']![2]);
      }
      expect(ReminiscenceV2Copy.openerFor(1, name: '阿伯').first,
          startsWith('你好，我係阿伯。'));
      expect(ReminiscenceV2Copy.openerFor(3, name: '阿珍'), [
        '歡迎返嚟。今個禮拜我哋講一生人嘅朋友，一樣係幾條問題，慢慢嚟。',
        '講完我會幫你整理成第3章。',
        '如果冇問題，我哋就開始。',
      ]);
    });

    test('32 questions, themes and short titles', () {
      var n = 0;
      for (final w in ReminiscenceV2Copy.weeks) {
        expect(w.questions, hasLength(8));
        expect(w.shortTitles, hasLength(8));
        // Same theme titles as the landing page.
        expect(w.themeZh, ReminiscenceTheme.byIndex(w.weekIndex).titleZh);
        for (var q = 1; q <= 8; q++) {
          final r = rows['W${w.weekIndex}-Q$q']!;
          expect(w.themeZh, r[1]);
          expect(w.question(q), r[2], reason: 'W${w.weekIndex}-Q$q');
          expect(w.shortTitle(q), r[3]);
          n++;
        }
      }
      expect(n, 32);
    });

    test('fixed lines and the closing line', () {
      expect(ReminiscenceV2Copy.generalLines,
          [rows['G1']![2], rows['G2']![2], rows['G3']![2]]);
      expect(ReminiscenceV2Copy.q7Line, rows['Q7']![2]);
      expect(ReminiscenceV2Copy.skipLine, rows['SKIP']![2]);
      expect(ReminiscenceV2Copy.closingLine, rows['CLOSE']![2]);
      expect(ReminiscenceV2Copy.extraLine, rows['EXTRA']![2]);
    });

    test('buttons and short texts', () {
      expect(ReminiscenceV2Copy.skipLabel, rows['B-SKIP']![2]);
      expect(ReminiscenceV2Copy.finishWeekLabel, rows['B-FINISH']![2]);
      expect(ReminiscenceV2Copy.moreLabel, rows['B-MORE']![2]);
      expect(ReminiscenceV2Copy.regenerateLabel, rows['B-REGEN']![2]);
      expect(ReminiscenceV2Copy.editLabel, rows['B-EDIT']![2]);
      expect(ReminiscenceV2Copy.saveLabel, rows['B-SAVE']![2]);
      expect(ReminiscenceV2Copy.savedLabel, rows['B-SAVED']![2]);
      expect(ReminiscenceV2Copy.leaveLabel, rows['B-LEAVE']![2]);
      expect(SessionCloseButton.leaveLabel, rows['B-LEAVE2']![2]);
      expect(SessionCloseButton.leaveFirstUseNote, rows['N-LEAVE']![2]);
      expect(ReminiscenceV2Copy.inputHint, rows['T-HINT']![2]);
      expect(ReminiscenceV2Copy.generating, rows['T-GEN']![2]);
      expect(ReminiscenceV2Copy.failed, rows['T-FAIL']![2]);
      expect(ReminiscenceV2Copy.emptyChapter, rows['T-EMPTY']![2]);
      expect(ReminiscenceV2Copy.extraSectionTitle, rows['T-EXTRA']![2]);
      expect(ReminiscenceV2Copy.chaptersPageTitle, rows['T-CHAPTERS']![2]);
      expect(ReminiscenceV2Copy.chaptersEmpty, rows['T-CHAPTERS-EMPTY']![2]);
      for (final w in [1, 2, 3, 4]) {
        final theme = ReminiscenceV2Copy.week(w).themeZh;
        expect(ReminiscenceV2Copy.chapterTitle(w),
            rows['T-TITLE']![2].replaceAll('{n}', '$w').replaceAll('{theme}', theme));
        expect(ReminiscenceV2Copy.chapterReady(w),
            rows['T-READY']![2].replaceAll('{n}', '$w'));
      }
    });

    // 1020o 第四节, 第一节: the landing bubble, the four theme lines (by
    // week index) and the 自己 page entry.
    test('landing page and the 自己 entry', () {
      expect(ReminiscenceV2Copy.landingIntro, rows['L-INTRO']![2]);
      expect(ReminiscenceV2Copy.chaptersEntrySubtitle, rows['L-ME']![2]);
      expect(ReminiscenceV2Copy.themeLines.keys, [1, 2, 3, 4]);
      for (final w in [1, 2, 3, 4]) {
        expect(ReminiscenceV2Copy.themeLines[w], rows['L-THEME-$w']![2]);
        expect(rows['L-THEME-$w']![1],
            contains('「${ReminiscenceTheme.byIndex(w).titleZh}」'));
      }
    });

    // 1020o (4a): the line under each week's scene picture.
    test('scene lines', () {
      expect(ReminiscenceV2Copy.sceneLines.keys, [1, 2, 3, 4]);
      for (final w in [1, 2, 3, 4]) {
        expect(ReminiscenceV2Copy.sceneLines[w], rows['SCENE-$w']![2]);
        expect(rows['SCENE-$w']![1], contains('scene_$w.jpg'));
      }
    });

    test('the three rating items and the rating buttons', () {
      final items = ReminiscenceV2Copy.ratingItems;
      expect(items, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final r = rows['R${i + 1}']!;
        expect(items[i].key, r[1]);
        expect(items[i].question, r[2]);
        expect(items[i].low, r[3]);
        expect(items[i].high, r[4]);
      }
      expect(ReminiscenceV2Copy.ratingStem, rows['R-STEM']![2]);
      expect(ReminiscenceV2Copy.ratingNext, rows['R-NEXT']![2]);
      expect(ReminiscenceV2Copy.ratingDone, rows['R-DONE']![2]);
      expect(ReminiscenceV2Copy.ratingSkip, rows['R-SKIP']![2]);
    });
  });

  group('pure helpers (both arms)', () {
    test('general lines rotate, never one of the last two', () {
      final msgs = <ReminiscenceMessage>[];
      final seq = <String>[];
      for (var i = 0; i < 7; i++) {
        final (id, text) = ReminiscenceV2Logic.nextGeneralLine(msgs);
        seq.add(id);
        expect(text, ReminiscenceV2Copy.generalLines[int.parse(id[1]) - 1]);
        msgs.add(_m(ReminiscenceMessageKind.fixedLine, text, copyId: id));
        // Other fixed lines in between do not count.
        msgs.add(_m(ReminiscenceMessageKind.fixedLine, 'x', copyId: 'SKIP'));
      }
      expect(seq, ['G1', 'G2', 'G3', 'G1', 'G2', 'G3', 'G1']);
      for (var i = 2; i < seq.length; i++) {
        expect(seq.sublist(i - 2, i), isNot(contains(seq[i])));
      }
    });

    test('rule chapter: short title + verbatim words; 唔想講 and flagged '
        'answers left out; extras last', () {
      final msgs = [
        _m(ReminiscenceMessageKind.answer, '我喺順德鄉下大，屋前有條河。', q: 1),
        _m(ReminiscenceMessageKind.skip, '唔想講', q: 2),
        _m(ReminiscenceMessageKind.answer, '阿嫲同我最親', q: 3),
        _m(ReminiscenceMessageKind.answer, '我真係想死', q: 4,
            safety: 'acute'),
        _m(ReminiscenceMessageKind.answer, '  ', q: 5),
        _m(ReminiscenceMessageKind.answer, '佢成日帶我去街市', q: 8),
        _m(ReminiscenceMessageKind.extra, '仲有隻狗叫旺財'),
      ];
      expect(
          ReminiscenceV2Logic.ruleChapterText(1, msgs),
          '細個住嘅地方\n我喺順德鄉下大，屋前有條河。\n\n'
          '屋企人\n阿嫲同我最親\n\n'
          '細個對我嘅影響\n佢成日帶我去街市\n\n'
          '再講多啲\n仲有隻狗叫旺財');
    });

    test('chapter request input: every question, skipped flags, follow-ups, '
        'reply, extras', () {
      final msgs = [
        _m(ReminiscenceMessageKind.question, 'Q1', q: 1),
        _m(ReminiscenceMessageKind.answer, '深水埗', q: 1),
        _m(ReminiscenceMessageKind.followup, '邊條街？', q: 1),
        _m(ReminiscenceMessageKind.followupAnswer, '北河街', q: 1),
        _m(ReminiscenceMessageKind.reply, '北河街好熱鬧。', q: 1),
        _m(ReminiscenceMessageKind.question, 'Q2', q: 2),
        _m(ReminiscenceMessageKind.skip, '唔想講', q: 2),
        _m(ReminiscenceMessageKind.question, 'Q3', q: 3),
        _m(ReminiscenceMessageKind.answer, '阿媽', q: 3),
        _m(ReminiscenceMessageKind.followup, '阿媽做咩㗎？', q: 3),
        _m(ReminiscenceMessageKind.skip, '唔想講', q: 3),
        _m(ReminiscenceMessageKind.extra, '補充一句'),
        _m(ReminiscenceMessageKind.extraReply, '多謝你'),
      ];
      final input = ReminiscenceV2Logic.chapterInput(1, msgs);
      expect(input['themeZh'], '童年同屋企');
      final items = input['items'] as List;
      expect(items, hasLength(8));
      expect(items[0], {
        'questionIndex': 1,
        'question': ReminiscenceV2Copy.week(1).question(1),
        'answer': '深水埗',
        'skipped': false,
        'followups': [
          {'q': '邊條街？', 'a': '北河街'}
        ],
        'reply': '北河街好熱鬧。',
      });
      expect(items[1]['skipped'], isTrue);
      expect(items[1]['answer'], isNull);
      expect(items[2]['skipped'], isFalse, reason: 'answered; follow-up skipped');
      expect(items[2]['followups'], [
        {'q': '阿媽做咩㗎？', 'a': null}
      ]);
      expect(items[2]['reply'], isNull);
      expect(items[7]['answer'], isNull);
      expect(items[7]['skipped'], isFalse, reason: 'not reached');
      expect(input['extras'], [
        {'text': '補充一句', 'reply': '多謝你'}
      ]);
    });

    test('edit ratio = Levenshtein (code points) / original length', () {
      expect(ReminiscenceV2Logic.editRatio('我細個住深水埗', '我細個住深水埗'), 0);
      // Three characters changed out of 7.
      expect(ReminiscenceV2Logic.editRatio('我細個住深水埗', '我細個住長沙灣'),
          closeTo(3 / 7, 1e-9));
      expect(ReminiscenceV2Logic.editRatio('abcd', 'abc'), 0.25);
      expect(ReminiscenceV2Logic.editRatio('ab', 'abcdef'), 2.0);
      expect(ReminiscenceV2Logic.editRatio('', ''), 0);
      expect(ReminiscenceV2Logic.editRatio('', 'x'), 1);
      expect(ReminiscenceV2Logic.levenshtein('kitten'.runes.toList(),
          'sitting'.runes.toList()), 3);
    });

    test('week state round trip; consent off keeps no words on the server',
        () {
      final s = ReminiscenceWeekState(weekIndex: 2, arm: 'A')
        ..currentQuestion = 3
        ..followupsAsked[1] = 1
        ..messages.add(_m(ReminiscenceMessageKind.answer, '做裁縫', q: 1));
      final on = s.toMap(includeMessages: true);
      expect(on['messages'], hasLength(1));
      expect(on['transcriptRetained'], isTrue);
      expect(on['followupsAsked'], {'1': 1});
      final off = s.toMap(includeMessages: false);
      expect(off['messages'], isEmpty);
      expect(off['transcriptRetained'], isFalse);
      final back = ReminiscenceWeekState.fromMap(on, weekIndex: 2, arm: 'A');
      expect(back.currentQuestion, 3);
      expect(back.followupsAsked, {1: 1});
      expect(back.messages.single.text, '做裁縫');
      expect(back.messages.single.toMap()['role'], 'user');
      expect(back.messages.single.toMap()['kind'], 'answer');
    });
  });
}
