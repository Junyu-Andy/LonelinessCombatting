// 1020f 第一节 — the measures' wording, both arms the same, no switch:
//   - PGIC: the approved questionnaire package (B.5) word for word, values
//     unchanged (1 = 好咗好多 … 7 = 差咗好多); title = its part name;
//   - Weekly PR: the 12 items start 「呢個禮拜」 (was 「頭先」); title = its
//     part name;
//   - Brief PR: the package's B.3 questions and anchors, in the
//     one-question-per-screen page and the old popup alike; keys unchanged;
//   - daily mood: one set of words for the selector and the chart legend.
// Synthetic data only; no Firebase.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/features/assessment/presentation/pages/pgic_page.dart';
import 'package:app_demo/features/brief_pr/presentation/pages/brief_pr_flow_page.dart';
import 'package:app_demo/features/brief_pr/presentation/pages/brief_pr_page.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_shared.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_response.dart';
import 'package:app_demo/theme/app_mood_encoding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _moodWords = ['好唔開心', '唔係幾好', '一般般', '幾好', '好開心'];

Widget _app(Widget home) => AppSettingsScope(
      settings: AppSettings(locale: const Locale('zh')),
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('PGIC: package B.5 stem and seven options, part-name title',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(const PgicPage(preview: true)));
    await tester.pumpAndSettle();
    expect(find.text('同你開始用呢個 app 之前比較，你嘅孤獨感而家點？'), findsOneWidget);
    expect(find.text('同開始用嗰時比較'), findsOneWidget);
    expect(find.text('每週感受變化'), findsNothing);
    final options = ['好咗好多', '好咗', '好咗少少', '冇變', '差咗少少', '差咗', '差咗好多'];
    final ys = [
      for (final o in options) tester.getCenter(find.text(o)).dy,
    ];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]), reason: '${options[i]} after ${options[i - 1]}');
    }
  });

  test('Weekly PR: all 12 items start 「呢個禮拜」, nothing else changed', () {
    expect(WeeklyPrItems.items, hasLength(12));
    for (final it in WeeklyPrItems.items) {
      expect(it.text, startsWith('呢個禮拜 ${WeeklyPrItems.kAgent} '), reason: it.id);
      expect(it.text, isNot(contains('頭先')), reason: it.id);
    }
    expect(WeeklyPrItems.render(WeeklyPrItems.items.first.text, '小欣'),
        '呢個禮拜 小欣 都明白我嘅感受。');
  });

  test('Brief PR: package B.3 questions and anchors, keys unchanged', () {
    expect([for (final i in briefPrItems) i.key],
        ['understanding', 'validation', 'caring', 'insensitivity']);
    expect([for (final i in briefPrItems) i.stem('小欣')], [
      '啱啱嘅傾偈，你覺得佢有幾明白你？',
      '佢有幾認同、接受你嘅諗法同感受？',
      '你覺得佢有幾關心你？',
      '佢嘅反應有冇令你覺得唔舒服、或者唔顧你感受？',
    ]);
    expect([for (final i in briefPrItems) [i.low, i.mid, i.high]], [
      ['完全唔明白', '一半半', '非常明白'],
      ['完全唔認同', '一半半', '非常認同'],
      ['完全唔關心', '一半半', '非常關心'],
      ['完全冇', '有少少', '非常'],
    ]);
    expect(BriefPrFlowPage.stemFor('小欣'), '今次傾偈：小欣');
  });

  testWidgets('old Brief PR popup: the same questions and anchors',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(const BriefPrPage(
      agentId: 'siu_yan',
      agentDisplayName: '小欣',
      isAnchorPrompt: true,
      itemCount: 4,
    )));
    await tester.pumpAndSettle();
    for (final i in briefPrItems) {
      expect(find.text(i.stem('小欣')), findsOneWidget, reason: i.key);
    }
    for (final a in ['完全唔明白', '非常明白', '完全唔認同', '非常認同', '完全唔關心',
        '非常關心', '完全冇', '有少少', '非常']) {
      expect(find.text(a), findsOneWidget, reason: a);
    }
    expect(find.text('一半半'), findsNWidgets(3));
    for (final old in ['小欣 明白我。', '小欣 尊重我。', '小欣 關心我。', '完全唔係咁', '完全係咁', '好係咁']) {
      expect(find.text(old), findsNothing, reason: old);
    }
    // The page still names the companion.
    expect(find.textContaining('小欣'), findsWidgets);
  });

  test('daily mood: selector and chart legend use the same five words', () {
    expect([for (final f in MoodFace.values) f.label(false)], _moodWords);
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    expect([for (var s = 1; s <= 5; s++) AppMoodEncoding.forScore(s, scheme).labelZh],
        _moodWords);
    expect([for (final f in MoodFace.values) f.numericScore], [1, 2, 3, 4, 5]);
  });
}
