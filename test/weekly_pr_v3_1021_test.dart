// 10/21 (Junyu, freeze build) — Weekly PR v3 reads 「呢個禮拜 {companion}
// 冇對我指指點點。」 (was 「冇判斷我」); u3 「真係聽到我講嘅嘢」 unchanged; ids,
// fields and scoring unchanged; both arms the same.
//   - docs/spec/instruments/weekly_pr.md §3 and WeeklyPrItems agree word
//     for word, in order;
//   - on the page, at the largest App text (1.30) on a 360 × 800 phone,
//     the v3 card shows the whole sentence, 「指指點點」 in bold, nothing
//     cut and no overflow.
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_response.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_trigger.dart';
import 'package:app_demo/features/weekly_pr/presentation/pages/weekly_pr_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rows of the spec's items table: id, subscale, text.
List<List<String>> _specRows() {
  final doc = File('docs/spec/instruments/weekly_pr.md').readAsStringSync();
  final section = doc.split('## 3.')[1].split('## 4.')[0];
  return [
    for (final line in section.split('\n'))
      if (RegExp(r'^\| [a-z]\d \|').hasMatch(line))
        line
            .split('|')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList(),
  ];
}

Widget _app(Widget home) => AppSettingsScope(
  settings: AppSettings(locale: const Locale('zh')),
  child: MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(AppFontScale.xLarge.multiplier)),
      child: child!,
    ),
    home: home,
  ),
);

void main() {
  test('spec and code: the 12 items word for word, in order; v3 new, u3 '
      'unchanged', () {
    final spec = _specRows();
    expect(spec, hasLength(12));
    expect(
      [for (final it in WeeklyPrItems.items) it.id],
      [for (final r in spec) r[0]],
    );
    for (final (i, it) in WeeklyPrItems.items.indexed) {
      expect(
        it.text,
        spec[i][2].replaceAll('〈AGENT〉', WeeklyPrItems.kAgent),
        reason: it.id,
      );
    }
    String text(String id) =>
        WeeklyPrItems.items.firstWhere((it) => it.id == id).text;
    expect(WeeklyPrItems.render(text('v3'), '小欣'), '呢個禮拜 小欣 冇對我指指點點。');
    expect(WeeklyPrItems.render(text('u3'), '小欣'), '呢個禮拜 小欣 真係聽到我講嘅嘢。');
    for (final it in WeeklyPrItems.items) {
      expect(it.text.contains('判斷'), isFalse, reason: it.id);
    }
  });

  for (final reverseLast in [true, false]) {
    testWidgets('page (scaleDirectionCuesEnabled $reverseLast): v3 at 1.30 on '
        '360 × 800 — whole sentence, 「指指點點」 bold, nothing cut', (tester) async {
      RemoteFeatureFlags.current = RemoteFeatureFlags(
        scaleDirectionCuesEnabled: reverseLast,
      );
      addTearDown(RemoteFeatureFlags.resetForTest);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          WeeklyPrPage(
            agent: WeeklyPrAgentUsage(
              agentId: 'siu_yan',
              displayName: '小欣',
              sessionCount: 3,
              firstUseAt: DateTime(2026, 10, 20),
            ),
            preview: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final v3 = find.byKey(const ValueKey('weekly_pr_item_v3'));
      // Walk the pages: answer each one top to bottom (the list builds
      // lazily, so scrolling down builds the rest) until v3 is built.
      for (var page = 0; ; page++) {
        expect(page, lessThan(3), reason: 'v3 not on any page');
        final done = <String>{};
        var idle = 0;
        while (true) {
          Finder card(String id) => find.byKey(ValueKey('weekly_pr_item_$id'));
          // Top to bottom, as the elder answers.
          final next =
              [
                for (final it in WeeklyPrItems.items)
                  if (!done.contains(it.id) &&
                      card(it.id).evaluate().isNotEmpty)
                    it.id,
              ]..sort(
                (a, b) => tester
                    .getTopLeft(card(a))
                    .dy
                    .compareTo(tester.getTopLeft(card(b)).dy),
              );
          if (next.isEmpty) {
            // Scroll on to build the rest of the page; stop at its end.
            if (++idle > 3) break;
            await tester.drag(
              find.byKey(ValueKey('weekly_pr_page_$page')),
              const Offset(0, -400),
            );
            await tester.pumpAndSettle();
            continue;
          }
          idle = 0;
          final four = find.descendant(
            of: find.byKey(ValueKey('weekly_pr_item_${next.first}')),
            matching: find.text('4'),
          );
          await tester.ensureVisible(four);
          await tester.pumpAndSettle();
          await tester.tap(four);
          await tester.pump();
          done.add(next.first);
          // v3 reached: stop here, with it on screen.
          if (next.first == 'v3') break;
        }
        if (done.contains('v3')) break;
        await tester.tap(find.text('下一頁'));
        await tester.pumpAndSettle();
      }
      if (reverseLast) {
        expect(
          find.text('第 3 / 3 頁'),
          findsNothing,
          reason: 'v3 is a positive item: page 1 or 2',
        );
      }
      await tester.ensureVisible(v3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final rich = find.descendant(
        of: v3,
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('冇對我指指點點'),
        ),
      );
      expect(rich, findsOneWidget);
      final text = tester.widget<RichText>(rich).text;
      expect(text.toPlainText(), '呢個禮拜 小欣 冇對我指指點點。');
      final bold = <String>[];
      text.visitChildren((s) {
        if (s is TextSpan &&
            s.text != null &&
            (s.style?.fontWeight ?? FontWeight.normal).index >=
                FontWeight.w700.index) {
          bold.add(s.text!);
        }
        return true;
      });
      expect(bold, containsAll(['小欣', '指指點點']));
      final paragraph = tester.renderObject<RenderParagraph>(rich);
      expect(paragraph.didExceedMaxLines, isFalse);
      // The card holds the whole sentence inside the screen width.
      final box = tester.getRect(rich);
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(360));
    });
  }
}
