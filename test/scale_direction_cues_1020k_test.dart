// 1020k (decisions-log 10/20 items 77–79) — the lines before the reverse
// items and the Weekly PR pages, switch `scaleDirectionCuesEnabled`:
//   - Brief PR question 4 (one-question flow and the old popup): the line
//     「最後一題反過嚟問：佢有冇令你唔舒服？」, 「唔舒服」 bold in the accent
//     colour; questions 1–3 nothing;
//   - Weekly PR: u/v/c items on pages 1–2 (5 + 4, shuffled), i1–i3 always
//     on page 3 (shuffled) under 「呢一頁三句講唔好嘅感覺……」; the record
//     gets `itemOrder`; ten runs through the page;
//   - DJG-ES question 4: 「跟住三句講你身邊嘅人。」, not bold;
//   - switch off: exactly as before;
//   - largest App text (1.30) on a 360-wide phone: nothing overflows, the
//     line never overlaps the question or a button.
// Both arms get the same pages (no arm check anywhere).  Synthetic data
// only; nothing is written.
import 'dart:math';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/session/session_rules.dart';
import 'package:app_demo/core/survey/direction_cue.dart';
import 'package:app_demo/features/assessment/data/djg_w2.dart';
import 'package:app_demo/features/assessment/presentation/pages/djg_w2_page.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_record.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_scheduler.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/presentation/pages/brief_pr_flow_page.dart';
import 'package:app_demo/features/brief_pr/presentation/pages/brief_pr_page.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_layout.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_response.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_trigger.dart';
import 'package:app_demo/features/weekly_pr/presentation/pages/weekly_pr_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _positive = {'u1', 'u2', 'u3', 'v1', 'v2', 'v3', 'c1', 'c2', 'c3'};
const _reverse = {'i1', 'i2', 'i3'};
const _allIds = [..._positive, ..._reverse];

/// The App's largest text level (特大); nothing goes above it.
final _maxScale = AppFontScale.xLarge.multiplier;

void _flag(bool on) {
  RemoteFeatureFlags.current =
      RemoteFeatureFlags(scaleDirectionCuesEnabled: on);
  addTearDown(RemoteFeatureFlags.resetForTest);
}

/// [home] behind a launcher button so the page can pop; App theme, zh.
Widget _app(Widget home, {double textScale = 1.0}) => AppSettingsScope(
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
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<Object?>(builder: (_) => home)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, Widget home,
    {Size size = const Size(900, 2400), double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(home, textScale: textScale));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

final _agent = WeeklyPrAgentUsage(
  agentId: 'siu_yan',
  displayName: '小欣',
  sessionCount: 3,
  firstUseAt: DateTime(2026, 10, 20),
  referentRule: 'max_sessions',
);

final _t0 = DateTime(2026, 10, 20, 15, 20);

BriefPrRecord _record() => BriefPrRecord(
      uid: 'synthetic',
      sessionId: 's1',
      agentId: 'tung_tung',
      agentDisplayName: '通通',
      sessionType: 'free_chat',
      endReason: SessionEndReason.closeButton,
      sessionEndedAt: _t0,
      lastReplyAt: _t0,
      invitedAt: _t0,
      invitedDayKey: '2026-10-20',
      inviteChannel: BriefPrInviteChannel.listPage,
    );

Future<BriefPrFlowPage> _flowPage() async {
  final store = InMemoryBriefPrStore();
  final scheduler = BriefPrScheduler(
      store: store,
      rules: const SessionRules(v2: true, idleTimeoutMin: 30),
      clock: () => _t0);
  await store.put(_record());
  return BriefPrFlowPage(record: store.records['synthetic/s1']!, scheduler: scheduler);
}

class _FakeDjgStore implements DjgW2Store {
  @override
  Future<DjgW2Saved> load() async => const DjgW2Saved();

  @override
  Future<void> save(Map<String, String> answers,
      {required bool submit, required bool first}) async {}
}

/// The spans of the line's RichText, flattened.
List<TextSpan> _spans(WidgetTester tester, Key key) {
  final rich = tester.widget<RichText>(
      find.descendant(of: find.byKey(key), matching: find.byType(RichText)));
  final out = <TextSpan>[];
  rich.text.visitChildren((s) {
    if (s is TextSpan && s.text != null) out.add(s);
    return true;
  });
  return out;
}

String _plain(WidgetTester tester, Key key) => tester
    .widget<RichText>(
        find.descendant(of: find.byKey(key), matching: find.byType(RichText)))
    .text
    .toPlainText();

/// Ids of the Weekly PR items built on the current page, top to bottom.
List<String> _pageIds(WidgetTester tester) {
  Finder card(String id) => find.byKey(ValueKey('weekly_pr_item_$id'));
  final ids = [
    for (final id in _allIds)
      if (card(id).evaluate().isNotEmpty) id,
  ];
  ids.sort((a, b) =>
      tester.getTopLeft(card(a)).dy.compareTo(tester.getTopLeft(card(b)).dy));
  return ids;
}

/// Answers every item on the current page (4 each), scrolling down as a
/// small screen needs; returns the ids in display order.
Future<List<String>> _answerPage(WidgetTester tester) async {
  final done = <String>[];
  while (true) {
    final next = [
      for (final id in _pageIds(tester))
        if (!done.contains(id)) id,
    ];
    if (next.isEmpty) return done;
    final four = find.descendant(
        of: find.byKey(ValueKey('weekly_pr_item_${next.first}')),
        matching: find.text('4'));
    await tester.ensureVisible(four);
    await tester.pumpAndSettle();
    await tester.tap(four);
    await tester.pump();
    done.add(next.first);
  }
}

/// One run through the Weekly PR page: the ids on each page, and whether
/// the page-3 line was on each page.
Future<({List<List<String>> pages, List<bool> cue})> _runWeekly(
    WidgetTester tester) async {
  await _open(tester, WeeklyPrPage(agent: _agent, preview: true));
  final pages = <List<String>>[];
  final cue = <bool>[];
  for (var p = 0; p < 3; p++) {
    expect(find.text('第 ${p + 1} / 3 頁'), findsOneWidget);
    cue.add(find.byKey(const Key('weekly_pr_reverse_cue')).evaluate().isNotEmpty);
    pages.add(await _answerPage(tester));
    await tester.tap(find.text(p == 2 ? '提交' : '下一頁'));
    await tester.pumpAndSettle();
  }
  // Submitted and closed (preview: nothing written).
  expect(find.text('open'), findsOneWidget);
  return (pages: pages, cue: cue);
}

void main() {
  group('the three lines (Junyu final wording)', () {
    test('text and emphasis', () {
      expect(DirectionCues.briefPrQ4, '最後一題反過嚟問：佢有冇令你唔舒服？');
      expect(DirectionCues.briefPrQ4Emphasis, '唔舒服');
      expect(DirectionCues.weeklyPrReversePage, '呢一頁三句講唔好嘅感覺，同意即係有呢種感覺。');
      expect(DirectionCues.weeklyPrReversePageEmphasis, '唔好');
      expect(DirectionCues.djgQ4, '跟住三句講你身邊嘅人。');
      // Each emphasis occurs exactly once in its line.
      expect('唔舒服'.allMatches(DirectionCues.briefPrQ4).length, 1);
      expect('唔好'.allMatches(DirectionCues.weeklyPrReversePage).length, 1);
    });

    test('switch is off unless literally true', () {
      expect(const RemoteFeatureFlags().scaleDirectionCuesEnabled, isFalse);
      expect(RemoteFeatureFlags.fromMap(const {'scaleDirectionCuesEnabled': 'true'})
          .scaleDirectionCuesEnabled, isFalse);
      expect(RemoteFeatureFlags.fromMap(const {'scaleDirectionCuesEnabled': true})
          .scaleDirectionCuesEnabled, isTrue);
    });
  });

  group('Weekly PR layout (pure)', () {
    test('switch on: 1000 shuffles — i1–i3 always page 3, never a positive there',
        () {
      final rng = Random(20261020);
      final seenFirst = <String>{};
      final seenPage3First = <String>{};
      for (var run = 0; run < 1000; run++) {
        final pages = WeeklyPrLayout.pages(reverseLast: true, random: rng);
        expect([for (final p in pages) p.length], [5, 4, 3]);
        expect({for (final it in pages[2]) it.id}, _reverse);
        expect({for (final p in pages.take(2)) for (final it in p) it.id}, _positive);
        expect(WeeklyPrLayout.order(pages).toSet(), _allIds.toSet());
        seenFirst.add(pages[0].first.id);
        seenPage3First.add(pages[2].first.id);
      }
      // Shuffled within the pages: every positive item opened page 1 at
      // some point, every reverse item opened page 3.
      expect(seenFirst, _positive);
      expect(seenPage3First, _reverse);
    });

    test('switch off: as before — all twelve shuffled, four per page', () {
      final rng = Random(7);
      var positiveOnPage3 = false;
      var reverseOnPage1 = false;
      for (var run = 0; run < 200; run++) {
        final pages = WeeklyPrLayout.pages(reverseLast: false, random: rng);
        expect([for (final p in pages) p.length], [4, 4, 4]);
        expect(WeeklyPrLayout.order(pages).toSet(), _allIds.toSet());
        positiveOnPage3 |= pages[2].any((it) => _positive.contains(it.id));
        reverseOnPage1 |= pages[0].any((it) => _reverse.contains(it.id));
        expect(WeeklyPrLayout.isReversePage(pages[2]), isFalse);
      }
      expect(positiveOnPage3, isTrue);
      expect(reverseOnPage1, isTrue);
    });

    test('the record: itemOrder only when given; items, fields unchanged', () {
      WeeklyPrResponse resp(List<String>? order) => WeeklyPrResponse(
            weekIso: '2026-W43',
            agentId: 'siu_yan',
            agentDisplayName: '小欣',
            sessionCountThisWeek: 3,
            items: const {'u1': 5, 'i1': 2},
            status: 'completed',
            promptedAt: _t0,
            respondedAt: _t0,
            arm: 'A',
            referentRule: 'max_sessions',
            itemOrder: order,
          );
      final off = resp(null).toFirestore();
      expect(off.containsKey('itemOrder'), isFalse);
      final order = WeeklyPrLayout.order(
          WeeklyPrLayout.pages(reverseLast: true, random: Random(1)));
      final on = resp(order).toFirestore();
      expect(on['itemOrder'], order);
      expect(on['items'], off['items']);
      expect(on.keys.toSet().difference(off.keys.toSet()), {'itemOrder'});
    });
  });

  group('Weekly PR page', () {
    testWidgets('switch on: ten runs — i1–i3 every time on page 3, never a positive',
        (tester) async {
      _flag(true);
      for (var run = 1; run <= 10; run++) {
        final r = await _runWeekly(tester);
        // ignore: avoid_print
        print('Weekly PR run $run: '
            'p1=${r.pages[0].join(',')} p2=${r.pages[1].join(',')} '
            'p3=${r.pages[2].join(',')}');
        expect(r.pages[0], hasLength(5), reason: 'run $run');
        expect(r.pages[1], hasLength(4), reason: 'run $run');
        expect(r.pages[2].toSet(), _reverse, reason: 'run $run');
        expect({...r.pages[0], ...r.pages[1]}, _positive, reason: 'run $run');
        expect(r.cue, [false, false, true], reason: 'run $run');
      }
    });

    testWidgets('switch on: page 3 line above the items, 「唔好」 bold accent',
        (tester) async {
      _flag(true);
      await _open(tester, WeeklyPrPage(agent: _agent, preview: true));
      for (var p = 0; p < 2; p++) {
        await _answerPage(tester);
        await tester.tap(find.text('下一頁'));
        await tester.pumpAndSettle();
      }
      const key = Key('weekly_pr_reverse_cue');
      expect(_plain(tester, key), DirectionCues.weeklyPrReversePage);
      final cueBottom = tester.getBottomLeft(find.byKey(key)).dy;
      for (final id in _reverse) {
        expect(tester.getTopLeft(find.byKey(ValueKey('weekly_pr_item_$id'))).dy,
            greaterThan(cueBottom), reason: id);
      }
      final theme = Theme.of(tester.element(find.byKey(key)));
      final em = _spans(tester, key).singleWhere((s) => s.text == '唔好');
      expect(em.style?.fontWeight, FontWeight.w900);
      expect(em.style?.color, theme.colorScheme.primary);
      expect(em.style?.color, isNot(Colors.red));
      expect(em.style?.backgroundColor, isNotNull);
    });

    testWidgets('switch off: four per page, no line, as before', (tester) async {
      _flag(false);
      final r = await _runWeekly(tester);
      expect([for (final p in r.pages) p.length], [4, 4, 4]);
      expect(r.cue, [false, false, false]);
    });
  });

  group('Brief PR question 4', () {
    testWidgets('one-question flow, switch on: the line on question 4 only',
        (tester) async {
      _flag(true);
      await _open(tester, await _flowPage());
      const key = Key('brief_pr_q4_cue');
      for (var q = 1; q <= 3; q++) {
        expect(find.text('$q/4'), findsOneWidget);
        expect(find.byKey(key), findsNothing, reason: 'question $q');
        expect(find.text(DirectionCues.briefPrQ4), findsNothing);
        await tester.tap(find.byKey(const Key('brief_pr_option_4')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('brief_pr_next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('4/4'), findsOneWidget);
      expect(_plain(tester, key), DirectionCues.briefPrQ4);
      // Between the page stem 「今次傾偈：通通」 (unchanged) and the question.
      final stem = find.byKey(const Key('brief_pr_stem'));
      expect(tester.widget<Text>(stem).data, '今次傾偈：通通');
      final cueRect = tester.getRect(find.byKey(key));
      expect(cueRect.top, greaterThanOrEqualTo(tester.getRect(stem).bottom));
      expect(tester.getRect(find.byKey(const Key('brief_pr_item_text'))).top,
          greaterThanOrEqualTo(cueRect.bottom));
      // The question itself is unchanged.
      expect(tester.widget<Text>(find.byKey(const Key('brief_pr_item_text'))).data,
          '佢嘅反應有冇令你覺得唔舒服、或者唔顧你感受？');
      final theme = Theme.of(tester.element(find.byKey(key)));
      final spans = _spans(tester, key);
      final em = spans.singleWhere((s) => s.text == '唔舒服');
      expect(em.style?.fontWeight, FontWeight.w900);
      expect(em.style?.color, theme.colorScheme.primary);
      expect(em.style?.color, isNot(Colors.red));
      expect(em.style?.backgroundColor, isNotNull);
      // Same size as the body text: the line's base style is 18.
      final rich = tester.widget<RichText>(
          find.descendant(of: find.byKey(key), matching: find.byType(RichText)));
      expect(rich.text.style?.fontSize, 18);
      for (final s in spans.where((s) => s.text != '唔舒服')) {
        expect(s.style?.fontWeight, isNull, reason: s.text);
      }
    });

    testWidgets('one-question flow, switch off: no line', (tester) async {
      _flag(false);
      await _open(tester, await _flowPage());
      for (var q = 1; q <= 3; q++) {
        await tester.tap(find.byKey(const Key('brief_pr_option_4')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('brief_pr_next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('4/4'), findsOneWidget);
      expect(find.byKey(const Key('brief_pr_q4_cue')), findsNothing);
    });

    for (final on in [true, false]) {
      testWidgets('old popup, switch ${on ? 'on' : 'off'}', (tester) async {
        _flag(on);
        await _open(
            tester,
            const BriefPrPage(
              agentId: 'siu_yan',
              agentDisplayName: '小欣',
              isAnchorPrompt: true,
              itemCount: 4,
            ));
        const q4 = '佢嘅反應有冇令你覺得唔舒服、或者唔顧你感受？';
        expect(find.text(q4), findsOneWidget);
        final cue = find.byKey(const Key('brief_pr_q4_cue'));
        if (!on) {
          expect(cue, findsNothing);
          return;
        }
        expect(cue, findsOneWidget);
        expect(_plain(tester, const Key('brief_pr_q4_cue')), DirectionCues.briefPrQ4);
        // Right above question 4, below question 3.
        expect(tester.getRect(cue).bottom,
            lessThanOrEqualTo(tester.getRect(find.text(q4)).top));
        expect(tester.getRect(cue).top,
            greaterThan(tester.getRect(find.text('你覺得佢有幾關心你？')).bottom));
      });
    }
  });

  group('DJG-ES (in-app, W1–W3 and W8)', () {
    Future<void> toItem(WidgetTester tester, int n) async {
      for (var i = 1; i < n; i++) {
        await tester.tap(find.text('是'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('switch on: the plain line on question 4 only', (tester) async {
      _flag(true);
      await _open(tester, DjgW2Page(store: _FakeDjgStore()));
      const key = Key('djg_q4_cue');
      for (var q = 1; q <= 6; q++) {
        expect(find.text('第 $q 題（共 6 題）'), findsOneWidget);
        final item = DjgW2Items.items[q - 1];
        expect(find.text(item.text), findsOneWidget);
        if (q == 4) {
          expect(item.id, 'q4');
          expect(find.byKey(key), findsOneWidget);
          final text = tester.widget<Text>(
              find.descendant(of: find.byKey(key), matching: find.byType(Text)));
          expect(text.data, DirectionCues.djgQ4);
          // Not bold: the body weight, no bold span.
          expect(text.style?.fontWeight, FontWeight.w500);
          expect(text.textSpan, isNull);
          expect(tester.getRect(find.byKey(key)).bottom,
              lessThanOrEqualTo(tester.getRect(find.text(item.text)).top));
        } else {
          expect(find.byKey(key), findsNothing, reason: 'question $q');
          expect(find.text(DirectionCues.djgQ4), findsNothing);
        }
        if (q < 6) {
          await tester.tap(find.text('是'));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('switch off: no line on question 4', (tester) async {
      _flag(false);
      await _open(tester, DjgW2Page(store: _FakeDjgStore()));
      await toItem(tester, 4);
      expect(find.text('第 4 題（共 6 題）'), findsOneWidget);
      expect(find.byKey(const Key('djg_q4_cue')), findsNothing);
    });
  });

  group('largest App text (1.30), 360 × 800 phone', () {
    const phone = Size(360, 800);

    void noOverlap(WidgetTester tester, Finder a, Finder b, String what) {
      final ra = tester.getRect(a);
      final rb = tester.getRect(b);
      expect(ra.overlaps(rb), isFalse, reason: what);
    }

    void fitsWidth(WidgetTester tester, Finder f) {
      final r = tester.getRect(f);
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(phone.width));
      final p = tester.renderObject<RenderParagraph>(
          find.descendant(of: f, matching: find.byType(RichText)));
      expect(p.didExceedMaxLines, isFalse);
    }

    testWidgets('Brief PR question 4', (tester) async {
      _flag(true);
      await _open(tester, await _flowPage(), size: phone, textScale: _maxScale);
      Future<void> tapKey(String k) async {
        await tester.ensureVisible(find.byKey(Key(k)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(k)));
        await tester.pumpAndSettle();
      }

      for (var q = 1; q <= 3; q++) {
        await tapKey('brief_pr_option_4');
        await tapKey('brief_pr_next');
      }
      expect(tester.takeException(), isNull);
      final cue = find.byKey(const Key('brief_pr_q4_cue'));
      fitsWidth(tester, cue);
      noOverlap(tester, cue, find.byKey(const Key('brief_pr_stem')), 'stem');
      noOverlap(tester, cue, find.byKey(const Key('brief_pr_item_text')), 'question');
      for (final k in ['brief_pr_option_1', 'brief_pr_option_7', 'brief_pr_next',
          'brief_pr_abandon']) {
        await tester.ensureVisible(find.byKey(Key(k)));
        await tester.pumpAndSettle();
        noOverlap(tester, cue, find.byKey(Key(k)), k);
      }
      // The buttons still work.
      await tapKey('brief_pr_option_2');
      await tapKey('brief_pr_next');
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('Weekly PR page 3', (tester) async {
      _flag(true);
      await _open(tester, WeeklyPrPage(agent: _agent, preview: true),
          size: phone, textScale: _maxScale);
      for (var p = 0; p < 2; p++) {
        expect(await _answerPage(tester), hasLength(p == 0 ? 5 : 4));
        await tester.tap(find.text('下一頁'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.text('第 3 / 3 頁'), findsOneWidget);
      final cue = find.byKey(const Key('weekly_pr_reverse_cue'));
      fitsWidth(tester, cue);
      // On screen when page 3 opens, under the page number.
      expect(tester.getRect(cue).bottom,
          lessThan(tester.getTopLeft(find.text('提交')).dy));
      for (final b in ['上一頁', '提交', '今個禮拜跳過']) {
        expect(find.text(b), findsOneWidget);
        noOverlap(tester, cue, find.text(b), b);
      }
      for (final id in _pageIds(tester)) {
        noOverlap(tester, cue, find.byKey(ValueKey('weekly_pr_item_$id')), id);
      }
      expect((await _answerPage(tester)).toSet(), _reverse);
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('DJG-ES question 4', (tester) async {
      _flag(true);
      await _open(tester, DjgW2Page(store: _FakeDjgStore()),
          size: phone, textScale: _maxScale);
      for (var i = 1; i < 4; i++) {
        await tester.ensureVisible(find.text('是'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('是'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      final cue = find.byKey(const Key('djg_q4_cue'));
      fitsWidth(tester, cue);
      noOverlap(tester, cue, find.text('當我遇到問題時，有許多人可以倚靠。'), 'question');
      for (final b in ['是', '上一題', '跳過呢題']) {
        await tester.ensureVisible(find.text(b).first);
        await tester.pumpAndSettle();
        noOverlap(tester, cue, find.text(b).first, b);
      }
    });
  });
}
