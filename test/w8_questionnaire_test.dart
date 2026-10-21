// T35 — the W8 questionnaire in the App (handover 1021-W8; decision 0036).
//   - every elder-visible word: docs/spec/copy/w8-questionnaire.md and
//     docs/spec/instruments/{djg_es,ucla3,ci,lsns6,aimhs}.md against the
//     code, word for word; the W8 PGIC is the W1–W7 PGIC page's wording;
//   - the flow: 5 parts in order with 「第 N 部分，共 5 部分」, the lead
//     lines, leave and resume at the question, skip = `skipped`, the
//     completion page, AIMHS optional (filled or 「唔填喇」);
//   - the home card: days 56–70 until done; not on day 55 or 71; only a
//     Phase B build and a registered account; both arms the same;
//   - at the largest App text (1.30) on a 360 × 800 phone nothing is cut;
//   - the W8 never uses lib/features/phase_b_probes/;
//   - the App-version report and the dashboard lines.
// Fake stores only: no Firebase, no model.
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/version/app_build_recorder.dart';
import 'package:app_demo/core/version/build_info.dart';
import 'package:app_demo/features/assessment/data/djg_w2.dart';
import 'package:app_demo/features/assessment/presentation/pages/pgic_page.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/ops_dashboard/data/ops_dashboard_service.dart';
import 'package:app_demo/features/w8/data/w8_items.dart';
import 'package:app_demo/features/w8/data/w8_schedule.dart';
import 'package:app_demo/features/w8/data/w8_store.dart';
import 'package:app_demo/features/w8/presentation/w8_flow_page.dart';
import 'package:app_demo/features/w8/presentation/w8_home_row.dart';
import 'package:app_demo/features/w8/presentation/w8_part_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Spec tables
// ---------------------------------------------------------------------------

List<List<String>> _rows(String text, RegExp first) => [
      for (final line in text.split('\n'))
        if (first.hasMatch(line))
          line
              .split('|')
              .map((c) => c.trim())
              .where((c) => c.isNotEmpty)
              .toList(),
    ];

String _section3(String path) =>
    File(path).readAsStringSync().split('## 3.')[1].split('## 4.')[0];

/// (id, subscale, text) rows of an instrument spec.
List<List<String>> _items(String file) =>
    _rows(_section3('docs/spec/instruments/$file'), RegExp(r'^\| q\d \|'));

/// (value, label) rows of an instrument spec's options table.
List<List<String>> _options(String file) =>
    _rows(_section3('docs/spec/instruments/$file'), RegExp(r'^\| \d \|'));

Map<String, String> _copy() {
  final doc = File('docs/spec/copy/w8-questionnaire.md').readAsStringSync();
  final table = doc.split('## 1.')[1].split('## 2.')[0];
  return {
    for (final r in _rows(table, RegExp(r'^\| W8-'))) r[0]: r[2],
  };
}

void _expectItems(W8PartSpec spec, String file) {
  final rows = _items(file);
  expect([for (final it in spec.items) it.id], [for (final r in rows) r[0]],
      reason: file);
  expect([for (final it in spec.items) it.text], [for (final r in rows) r[2]],
      reason: file);
}

void _expectOptions(W8PartSpec spec, String file) {
  final rows = _options(file);
  expect([for (final o in spec.options) '${o.value}'],
      [for (final r in rows) r[0]],
      reason: file);
  expect([for (final o in spec.options) o.label], [for (final r in rows) r[1]],
      reason: file);
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

UserProfile _profile(ArmAssignment arm,
        {String? cohort = 'rct', String? w0 = '2026-10-15'}) =>
    UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: arm,
      cohort: cohort,
      w0Date: w0,
    );

Widget _app(Widget home, {UserProfile? profile, double scale = 1.0}) =>
    AppSettingsScope(
      settings: AppSettings(locale: const Locale('zh'), profile: profile),
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
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    );

Future<void> _phone(WidgetTester tester, {Size size = const Size(412, 1600)})
    async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, Object value) =>
    _tap(tester, find.byKey(ValueKey('w8_option_$value')));

Future<void> _skip(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('w8_skip')));

Future<void> _submit(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('w8_submit')));

/// The phone's back (gesture or key): leave the page.
Future<void> _back(WidgetTester tester) async {
  await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
  await tester.pumpAndSettle();
}

String _question(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('w8_question'))).data!;

void main() {
  group('words: spec and code, word for word', () {
    test('copy spec: title, intro, part names, completion, buttons, push',
        () {
      final c = _copy();
      expect(c['W8-push'], W8Texts.push);
      expect(c['W8-title'], W8Texts.title);
      expect(c['W8-home-sub'], W8Texts.homeSubtitle);
      expect(c['W8-intro'], W8Texts.intro);
      expect([for (var i = 1; i <= 5; i++) c['W8-part$i']], W8Texts.partNames);
      expect([for (final p in W8Items.parts) p.title], W8Texts.partNames);
      expect(c['W8-done'], W8Texts.done);
      expect(c['W8-fill'], W8Texts.fill);
      expect(c['W8-decline'], W8Texts.decline);
      expect(c['W8-djg-instr'], W8Items.djg.instruction);
      expect(c['W8-djg-q4'], W8Items.djg.items[3].lead);
      expect(c['W8-ucla-instr'], W8Items.ucla3.instruction);
      expect(c['W8-pgic-item'], W8Items.pgic.items.single.text);
      expect(c['W8-pgic-hint'], W8Items.pgic.hint);
      expect(c['W8-ci-instr'], W8Items.ci.instruction);
      expect(c['W8-lsns-instr'], W8Items.lsns6.instruction);
      expect(c['W8-lsns-q1'], W8Items.lsns6.items[0].lead);
      expect(c['W8-lsns-q4'], W8Items.lsns6.items[3].lead);
      expect(c['W8-aimhs-title'], W8Items.aimhs.title);
      expect(c['W8-aimhs-intro'], W8Items.aimhs.instruction);
      expect(c.length, 23, reason: 'every row is checked');
    });

    test('the handover wording as given (spot checks)', () {
      expect(W8Texts.title, '最後一份問卷');
      expect(W8Texts.intro, '今次一共有 5 部分，大約 8 分鐘，可以隨時停，下次由停低嗰度繼續。');
      expect(W8Texts.partNames,
          ['最近嘅感受', '孤單嘅感覺', '同開始用嗰時比較', '會唔會繼續用', '身邊嘅親人同朋友']);
      expect(W8Texts.done, '全部做完喇，多謝你！仲有一份可以選擇唔填嘅短問卷。');
      expect([W8Texts.fill, W8Texts.decline], ['填呢份', '唔填喇']);
      expect(W8Texts.push, '最後一份問卷開咗，請喺一個禮拜內入嚟答埋佢。多謝你！');
      expect(W8Items.djg.items[3].lead, '跟住三句講你身邊嘅人。');
      expect(W8Items.lsns6.items[0].lead, '先講親人，即係同你有血緣、婚姻或者收養關係嘅人。');
      expect(W8Items.lsns6.items[3].lead, '跟住講朋友，包括住喺你附近嘅朋友。');
      // Lead lines only where the handover puts them.
      final leads = [
        for (final s in [...W8Items.parts, W8Items.aimhs])
          for (final it in s.items)
            if (it.lead != null) '${s.part.name}.${it.id}',
      ];
      expect(leads, ['djg.q4', 'lsns6.q1', 'lsns6.q4']);
    });

    test('instrument specs: items and options', () {
      _expectItems(W8Items.djg, 'djg_es.md');
      _expectItems(W8Items.ucla3, 'ucla3.md');
      _expectOptions(W8Items.ucla3, 'ucla3.md');
      _expectItems(W8Items.ci, 'ci.md');
      _expectOptions(W8Items.ci, 'ci.md');
      _expectItems(W8Items.lsns6, 'lsns6.md');
      _expectOptions(W8Items.lsns6, 'lsns6.md');
      _expectItems(W8Items.aimhs, 'aimhs.md');
      _expectOptions(W8Items.aimhs, 'aimhs.md');
      // LSNS-6 subscales: family q1–q3, friends q4–q6.
      expect([for (final r in _items('lsns6.md')) r[1]],
          ['family', 'family', 'family', 'friends', 'friends', 'friends']);
    });

    test('DJG-ES is the W1–W3 DJG-ES: same items, same answers', () {
      expect([for (final it in W8Items.djg.items) it.text],
          [for (final it in DjgW2Items.items) it.text]);
      expect([for (final o in W8Items.djg.options) (o.value, o.label)],
          DjgW2Items.options);
    });

    test('PGIC: the copy spec table and the code', () {
      final doc =
          File('docs/spec/copy/w8-questionnaire.md').readAsStringSync();
      final rows =
          _rows(doc.split('## 2.')[1].split('## 3.')[0], RegExp(r'^\| \d \|'));
      expect([for (final o in W8Items.pgic.options) '${o.value}'],
          [for (final r in rows) r[0]]);
      expect([for (final o in W8Items.pgic.options) o.label],
          [for (final r in rows) r[1]]);
    });

    testWidgets('PGIC: the W1–W7 PGIC page shows exactly the W8 wording',
        (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(const PgicPage(preview: true)));
      await tester.pumpAndSettle();
      expect(find.text(W8Items.pgic.items.single.text), findsOneWidget);
      expect(find.text(W8Items.pgic.hint!), findsOneWidget);
      for (final o in W8Items.pgic.options) {
        expect(find.text(o.label), findsOneWidget, reason: o.label);
      }
      expect(find.text(W8Items.pgic.title), findsOneWidget);
    });
  });

  group('the flow', () {
    testWidgets('5 parts in order, headers, lead lines, leave and resume, '
        'skip, completion, AIMHS filled', (tester) async {
      await _phone(tester);
      final store = MemoryW8Store();
      await tester.pumpWidget(_app(W8FlowPage(store: store)));
      await tester.pumpAndSettle();

      expect(find.text(W8Texts.title), findsOneWidget);
      expect(find.text(W8Texts.intro), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(find.text('第 ${i + 1} 部分：${W8Texts.partNames[i]}'),
            findsOneWidget);
      }
      expect(find.text('未開始'), findsNWidgets(5));
      await _tap(tester, find.text('開始'));

      // Part 1 — DJG-ES.
      expect(find.text('第 1 部分，共 5 部分'), findsOneWidget);
      expect(find.text('第 1 題（共 6 題）'), findsOneWidget);
      expect(find.text(W8Items.djg.instruction!), findsOneWidget);
      expect(find.byKey(const ValueKey('w8_lead')), findsNothing);
      for (var i = 0; i < 3; i++) {
        await _choose(tester, 'yes');
      }
      expect(_question(tester), W8Items.djg.items[3].text);
      expect(find.text('跟住三句講你身邊嘅人。'), findsOneWidget);
      await _skip(tester);
      expect(find.byKey(const ValueKey('w8_lead')), findsNothing);
      await _choose(tester, 'no');
      await _choose(tester, 'mostly');
      expect(find.text('答完喇，多謝你！撳「提交」就完成。'), findsOneWidget);
      await _submit(tester);

      // Part 2 — UCLA-3: answer one, then leave.
      expect(find.text('第 2 部分，共 5 部分'), findsOneWidget);
      expect(find.text(W8Items.ucla3.instruction!), findsOneWidget);
      expect(find.text('很少'), findsOneWidget);
      await _choose(tester, 2);
      expect(find.text('第 2 題（共 3 題）'), findsOneWidget);
      await _back(tester);
      expect(find.text(W8Texts.intro), findsOneWidget);
      expect(find.text('未做完'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      await _tap(tester, find.text('繼續'));
      // Resumes at the question it stopped on.
      expect(find.text('第 2 部分，共 5 部分'), findsOneWidget);
      expect(find.text('第 2 題（共 3 題）'), findsOneWidget);
      expect(_question(tester), W8Items.ucla3.items[1].text);
      await _choose(tester, 3);
      await _choose(tester, 1);
      await _submit(tester);

      // Part 3 — PGIC with its hint.
      expect(find.text('第 3 部分，共 5 部分'), findsOneWidget);
      expect(_question(tester), W8Items.pgic.items.single.text);
      expect(find.byKey(const ValueKey('w8_hint')), findsOneWidget);
      await _choose(tester, 4);
      await _submit(tester);

      // Part 4 — CI: 「提交」 with questions never reached → skipped.
      expect(find.text('第 4 部分，共 5 部分'), findsOneWidget);
      expect(find.text('1 非常不同意'), findsOneWidget);
      await _choose(tester, 5);
      await _back(tester);
      await _tap(tester, find.text('繼續'));
      await _choose(tester, 4);
      await _skip(tester);
      await _submit(tester);

      // Part 5 — LSNS-6 with both lead lines.
      expect(find.text('第 5 部分，共 5 部分'), findsOneWidget);
      expect(find.text(W8Items.lsns6.instruction!), findsOneWidget);
      expect(find.text(W8Texts.lsnsQ1Lead), findsOneWidget);
      await _choose(tester, 0);
      expect(find.byKey(const ValueKey('w8_lead')), findsNothing);
      await _choose(tester, 1);
      await _choose(tester, 2);
      expect(find.text(W8Texts.lsnsQ4Lead), findsOneWidget);
      expect(find.text('九個或以上'), findsOneWidget);
      await _choose(tester, 5);
      await _choose(tester, 3);
      await _choose(tester, 4);
      await _submit(tester);

      // Completion: the five parts done, AIMHS offered.
      expect(find.text(W8Texts.done), findsOneWidget);
      expect(find.text('已完成'), findsNWidgets(5));
      expect(find.text(W8Texts.fill), findsOneWidget);
      expect(find.text(W8Texts.decline), findsOneWidget);
      final s = await store.statuses();
      expect(w8PartsDone(s), isTrue);
      expect(s[W8Part.aimhs], isNull);

      Future<Map<String, Object>> answers(W8Part p) async =>
          (await store.load(p)).answers;
      expect(await answers(W8Part.djg), {'q1': 'yes', 'q2': 'yes',
        'q3': 'yes', 'q4': 'skipped', 'q5': 'no', 'q6': 'mostly'});
      expect(await answers(W8Part.ucla3), {'q1': 2, 'q2': 3, 'q3': 1});
      expect(await answers(W8Part.pgic), {'q1': 4});
      expect(await answers(W8Part.ci), {'q1': 5, 'q2': 4, 'q3': 'skipped'});
      expect(await answers(W8Part.lsns6),
          {'q1': 0, 'q2': 1, 'q3': 2, 'q4': 5, 'q5': 3, 'q6': 4});

      // AIMHS: no part header, its opening line, then done.
      await _tap(tester, find.text(W8Texts.fill));
      expect(find.text(W8Texts.aimhsTitle), findsOneWidget);
      expect(find.textContaining('部分，共'), findsNothing);
      expect(find.text(W8Items.aimhs.instruction!), findsOneWidget);
      for (final v in [1, 2, 3, 4, 5]) {
        await _choose(tester, v);
      }
      await _submit(tester);
      expect(find.text('全部做完喇，多謝你！'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(await answers(W8Part.aimhs),
          {'q1': 1, 'q2': 2, 'q3': 3, 'q4': 4, 'q5': 5});
      expect((await store.statuses())[W8Part.aimhs], W8Status.submitted);
      // No PHQ-9, GAD-7 or alert entry anywhere in the flow.
      expect(find.textContaining('PHQ'), findsNothing);
      expect(find.textContaining('GAD'), findsNothing);
    });

    testWidgets('「唔填喇」: AIMHS declined, W8 still complete, back home',
        (tester) async {
      await _phone(tester);
      final store = MemoryW8Store({
        for (final p in W8Items.parts)
          p.part: const W8Saved(status: W8Status.submitted, hasStarted: true),
      });
      bool? popped;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                      builder: (_) => W8FlowPage(store: store)));
            },
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(W8Texts.done), findsOneWidget);
      await _tap(tester, find.text(W8Texts.decline));
      expect(popped, isTrue);
      final s = await store.statuses();
      expect(s[W8Part.aimhs], W8Status.declined);
      expect(w8PartsDone(s), isTrue);
      expect(w8CardDone(s), isTrue);
    });

    testWidgets('a part already submitted or missed does not reopen',
        (tester) async {
      await _phone(tester);
      final store = MemoryW8Store({
        W8Part.ci: const W8Saved(status: W8Status.missed),
      });
      await tester.pumpWidget(_app(
          W8PartPage(spec: W8Items.ci, store: store, part: (4, 5))));
      await tester.pumpAndSettle();
      expect(find.text('呢份問卷已經完成或者已經截止，唔使再答。'), findsOneWidget);
    });

    testWidgets('both arms: the same pages, word for word', (tester) async {
      await _phone(tester);
      Future<List<String>> texts(ArmAssignment arm) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_app(
            W8FlowPage(key: UniqueKey(), store: MemoryW8Store()),
            profile: _profile(arm)));
        await tester.pumpAndSettle();
        final out = [
          for (final t in tester.widgetList<Text>(find.byType(Text)))
            t.data ?? '',
        ];
        await _tap(tester, find.text('開始'));
        out.addAll([
          for (final t in tester.widgetList<Text>(find.byType(Text)))
            t.data ?? '',
        ]);
        return out;
      }

      expect(await texts(ArmAssignment.a), await texts(ArmAssignment.b));
    });
  });

  group('home card (days 56–70)', () {
    DateTime hk(String key, [int h = 10, int m = 30]) =>
        DateTime.parse('${key}T${'$h'.padLeft(2, '0')}:${'$m'.padLeft(2, '0')}:00');

    Future<bool> shown(WidgetTester tester,
        {required DateTime now,
        UserProfile? profile,
        bool phaseB = true,
        W8Store? store}) async {
      final s = store ?? MemoryW8Store();
      await tester.pumpWidget(_app(
        Scaffold(
          body: W8TodoRow(
            key: UniqueKey(),
            storeFor: (_) => s,
            clock: () => now,
            phaseB: phaseB,
          ),
        ),
        profile: profile ?? _profile(ArmAssignment.a),
      ));
      await tester.pumpAndSettle();
      return find.byKey(const ValueKey('today_todo_w8')).evaluate().isNotEmpty;
    }

    testWidgets('W0 10/15: day 55 no, 56–70 yes (also after the window), '
        '71 no', (tester) async {
      final w0 = DateTime(2026, 10, 15);
      expect(W8Schedule.dateOf(w0, 56), DateTime(2026, 12, 10));
      expect(await shown(tester, now: hk('2026-12-09', 23, 59)), isFalse);
      expect(await shown(tester, now: hk('2026-12-10', 0, 1)), isTrue);
      expect(find.text('最後一份問卷'), findsOneWidget);
      // 10/21 item 131 (1): the card's second line.
      expect(find.text('一共 5 部分，可以分開做。'), findsOneWidget);
      expect(await shown(tester, now: hk('2026-12-17', 23, 59)), isTrue);
      expect(await shown(tester, now: hk('2026-12-18')), isTrue,
          reason: 'day 64: after the window, still taken');
      expect(await shown(tester, now: hk('2026-12-24', 23, 59)), isTrue);
      expect(await shown(tester, now: hk('2026-12-25', 0, 1)), isFalse,
          reason: 'day 71');
    });

    testWidgets('only a Phase B build and a registered account; RCT-, PB-, '
        'PILOT- alike', (tester) async {
      final now = hk('2026-12-11');
      for (final c in ['rct', 'phase_b', 'pilot']) {
        expect(
            await shown(tester,
                now: now, profile: _profile(ArmAssignment.b, cohort: c)),
            isTrue,
            reason: c);
      }
      expect(
          await shown(tester,
              now: now, profile: _profile(ArmAssignment.a, cohort: null)),
          isFalse);
      expect(await shown(tester, now: now, phaseB: false), isFalse);
    });

    testWidgets('hidden once the five parts are done; a started AIMHS keeps '
        'it', (tester) async {
      final now = hk('2026-12-12');
      final done = {
        for (final p in W8Items.parts)
          p.part: const W8Saved(status: W8Status.submitted, hasStarted: true),
      };
      expect(await shown(tester, now: now, store: MemoryW8Store(done)),
          isFalse);
      expect(
          await shown(tester,
              now: now,
              store: MemoryW8Store({
                ...done,
                W8Part.aimhs: const W8Saved(
                    status: W8Status.inProgress, hasStarted: true),
              })),
          isTrue);
      expect(
          await shown(tester,
              now: now,
              store: MemoryW8Store({
                ...done,
                W8Part.aimhs: const W8Saved(status: W8Status.declined),
              })),
          isFalse);
      expect(
          await shown(tester,
              now: now,
              store: MemoryW8Store({
                W8Part.djg: const W8Saved(
                    status: W8Status.submitted, hasStarted: true),
              })),
          isTrue);
    });

    testWidgets('both arms: the same card; tapping opens the questionnaire',
        (tester) async {
      final now = hk('2026-12-10');
      expect(
          await shown(tester,
              now: now, profile: _profile(ArmAssignment.a)),
          isTrue);
      expect(
          await shown(tester,
              now: now, profile: _profile(ArmAssignment.b)),
          isTrue);
      await _tap(tester, find.text('最後一份問卷'));
      expect(find.byType(W8FlowPage), findsOneWidget);
      expect(find.text(W8Texts.intro), findsOneWidget);
    });
  });

  group('largest App text (1.30), 360 × 800', () {
    for (final spec in [...W8Items.parts, W8Items.aimhs]) {
      testWidgets('${spec.part.name}: every question, then 提交, nothing cut',
          (tester) async {
        await _phone(tester, size: const Size(360, 800));
        await tester.pumpWidget(_app(
          W8PartPage(
              spec: spec,
              store: MemoryW8Store(),
              part: spec.part == W8Part.aimhs ? null : (1, 5)),
          scale: AppFontScale.xLarge.multiplier,
        ));
        await tester.pumpAndSettle();
        for (final it in spec.items) {
          expect(_question(tester), it.text);
          for (final o in spec.options) {
            final f = find.byKey(ValueKey('w8_option_${o.value}'));
            await tester.ensureVisible(f);
            await tester.pumpAndSettle();
            expect(find.descendant(of: f, matching: find.text(o.label)),
                findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await _skip(tester);
        }
        expect(find.byKey(const ValueKey('w8_submit')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('flow intro and completion page', (tester) async {
      await _phone(tester, size: const Size(360, 800));
      await tester.pumpWidget(_app(W8FlowPage(store: MemoryW8Store()),
          scale: AppFontScale.xLarge.multiplier));
      await tester.pumpAndSettle();
      expect(find.text(W8Texts.intro), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(_app(
          W8FlowPage(
              key: UniqueKey(),
              store: MemoryW8Store({
            for (final p in W8Items.parts)
              p.part: const W8Saved(status: W8Status.submitted),
          })),
          scale: AppFontScale.xLarge.multiplier));
      await tester.pumpAndSettle();
      expect(find.text(W8Texts.done), findsOneWidget);
      await tester.ensureVisible(find.text(W8Texts.decline));
      expect(tester.takeException(), isNull);
    });
  });

  group('guards', () {
    test('the W8 never uses the phase_b_probes (guess-the-version, '
        'dependence): no file in lib/ imports them', () {
      final users = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.contains('features/phase_b_probes/')) continue;
        if (RegExp(r"^import .*phase_b_probes", multiLine: true)
            .hasMatch(f.readAsStringSync())) {
          users.add(f.path);
        }
      }
      expect(users, isEmpty);
      for (final f in Directory('lib/features/w8').listSync(recursive: true)) {
        if (f is! File) continue;
        // Code only (the doc comments say what is NOT there).
        final src = [
          for (final l in f.readAsLinesSync())
            if (!l.trimLeft().startsWith('//')) l,
        ].join('\n');
        for (final bad in ['Unblinding', 'unblinding_probes',
          'dependency_probes', 'PHQ', 'GAD', 'LlmGateway', 'proxyDeepSeek',
          'Arm.of', 'Arm.isA']) {
          expect(src.contains(bad), isFalse, reason: '${f.path}: $bad');
        }
      }
    });

    test('the store never writes a server field', () {
      for (final part in W8Part.values) {
        for (final status in [
          W8Status.inProgress,
          W8Status.submitted,
          W8Status.declined,
        ]) {
          final p = FirestoreW8Store.payload(part, {'q1': 1},
              status: status, timed: const ['q1'], first: true);
          for (final k in ['studyWeek', 'studyDay', 'submittedStudyDay',
            'outOfWindow', 'windowStart', 'windowEnd', 'acceptUntil',
            'scores', 'missed']) {
            expect(p.containsKey(k), isFalse, reason: '$part $status $k');
          }
          expect(p['bundle'], 'W8');
          expect(p['status'], status);
          expect(p.containsKey('submittedAt'), status == W8Status.submitted);
          expect(p.containsKey('declinedAt'), status == W8Status.declined);
        }
      }
      // PGIC keeps the W1–W7 format.
      final pgic = FirestoreW8Store.payload(W8Part.pgic, {'q1': 4},
          status: W8Status.submitted, timed: const ['q1'], first: false);
      expect(pgic['value'], 4);
      expect(pgic['answeredAt'], isA<FieldValue>());
      expect(pgic.containsKey('answers'), isFalse);
      // Only the questions answered by this write get a time; never an
      // empty map (a merge would wipe the others).
      final noTime = FirestoreW8Store.payload(W8Part.ci, {'q1': 4},
          status: W8Status.submitted, timed: const [], first: false);
      expect(noTime.containsKey('answeredAt'), isFalse);
      final one = FirestoreW8Store.payload(W8Part.ci, {'q1': 4, 'q2': 5},
          status: W8Status.inProgress, timed: const ['q2'], first: false);
      expect((one['answeredAt'] as Map).keys, ['q2']);
      expect(one['answers'], {'q1': 4, 'q2': 5});
    });
  });

  group('开工方式 (4): App version', () {
    test('users/{uid}.appBuild: exactly the fields the rules accept', () {
      final v = AppBuildRecorder.value(platform: 'android', seenAt: 'NOW');
      expect(v.keys.toSet(), {'version', 'build', 'w8', 'platform', 'seenAt'});
      expect(v['version'], BuildInfo.appVersion);
      expect(v['build'], BuildInfo.buildNumber);
      expect(v['w8'], isTrue);
      expect(AppBuildRecorder.value(platform: '', seenAt: 'NOW').keys,
          isNot(contains('platform')));
    });

    test('record: one update of appBuild, failures swallowed', () async {
      final writes = <(String, Map<String, Object>)>[];
      await AppBuildRecorder.record('u1', platform: 'ios',
          write: (uid, data) async => writes.add((uid, data)));
      expect(writes.single.$1, 'u1');
      expect(writes.single.$2.keys, ['appBuild']);
      final b = writes.single.$2['appBuild'] as Map;
      expect(b['seenAt'], isA<FieldValue>());
      await AppBuildRecorder.record('u1',
          platform: 'ios', write: (_, __) async => throw StateError('x'));
    });

    test('dashboard: W8 completion line and App version line', () {
      final p = OpsPerson.fromMap({
        'researchId': 'RCT-01',
        'w8Status': 'done',
        'w8': {
          'status': 'done', 'partsSubmitted': 5, 'parts': 5,
          'completedAt': '2026-12-11T02:00:00.000Z',
          'completedOutOfWindow': true, 'optionalPart': 'declined',
        },
        'appBuild': {'version': '1.0.0', 'build': '3', 'w8': true,
          'platform': 'android', 'seenAt': '2026-11-20T02:00:00.000Z'},
      });
      expect(p.w8.line, startsWith('W8 最後一份問卷：已填（5／5 部分）　完成 12月11日（超窗）'));
      expect(p.w8.line, endsWith('可選 AIMHS：唔填'));
      expect(appBuildLine(p.appBuild),
          startsWith('App 版本：1.0.0（build 3）　android　有 W8 問卷頁'));
      final old = OpsPerson.fromMap(
          {'researchId': 'RCT-02', 'w8Status': 'open'});
      expect(old.appBuild, isNull);
      expect(appBuildLine(old.appBuild), 'App 版本：未有報告（舊版，冇 W8 問卷頁，要裝新版）');
      expect(old.w8.line, 'W8 最後一份問卷：窗口中（0／5 部分）');
      expect(weeklyCellLabel('late'), '過咗窗口（第 70 日前仍可補）');
    });
  });
}
