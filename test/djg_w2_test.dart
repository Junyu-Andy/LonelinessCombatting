// T18 — Phase B in-app W2 DJG, 6 items (decision 0027).
//
// Default (Phase A) build: the gate stays closed even with the switch on.
// tool/ci_flutter_tests.sh also runs this file with PHASE_B=true, where
// the gate opens.
import 'dart:io';

import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/features/assessment/data/djg_w2.dart';
import 'package:app_demo/features/assessment/presentation/pages/djg_w2_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Save {
  final Map<String, String> answers;
  final bool submit;
  final bool first;
  _Save(this.answers, this.submit, this.first);
}

class _FakeStore implements DjgW2Store {
  _FakeStore([this.saved = const DjgW2Saved()]);
  final DjgW2Saved saved;
  final saves = <_Save>[];

  @override
  Future<DjgW2Saved> load() async => saved;

  @override
  Future<void> save(Map<String, String> answers, {required bool submit, required bool first}) async {
    saves.add(_Save(Map.of(answers), submit, first));
  }
}

Future<void> _pump(WidgetTester tester, DjgW2Store store, {List<Object?>? popped}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final r = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => DjgW2Page(store: store)),
              );
              popped?.add(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('items and answers — questionnaire package §3, verbatim', () {
    test('six items, in order, with subscales', () {
      expect(DjgW2Items.items.map((i) => i.text).toList(), [
        '我有一種空虛的感覺。',
        '我想念身邊有人陪伴。',
        '我經常覺得自己被人排斥。',
        '當我遇到問題時，有許多人可以倚靠。',
        '我有許多可以完全信任的人。',
        '有足夠多我感到親近的人。',
      ]);
      expect(DjgW2Items.items.map((i) => i.subscale).toList(),
          ['emotional', 'emotional', 'emotional', 'social', 'social', 'social']);
      expect(DjgW2Items.items.map((i) => i.id).toList(), ['q1', 'q2', 'q3', 'q4', 'q5', 'q6']);
    });

    test('three answers 是 / 大致是 / 不是', () {
      expect(DjgW2Items.options, [('yes', '是'), ('mostly', '大致是'), ('no', '不是')]);
    });
  });

  group('config and gate', () {
    test('defaults: off, day 14, 7-day window, 10:00, 24 h', () {
      const c = PhaseBConfig();
      expect(c.djgW2InAppEnabled, false);
      expect(c.djgW2DayOffset, 14);
      expect(c.djgW2WindowDays, 7);
      expect(c.djgW2PushHour, 10);
      expect(c.djgW2ReminderHours, 24);
    });

    test('only literal true switches on; bad numbers keep defaults', () {
      expect(PhaseBConfig.fromMap({'djgW2InAppEnabled': 'true'}).djgW2InAppEnabled, false);
      final c = PhaseBConfig.fromMap(
          {'djgW2InAppEnabled': true, 'djgW2DayOffset': 0, 'djgW2WindowDays': 3});
      expect(c.djgW2InAppEnabled, true);
      expect(c.djgW2DayOffset, 14);
      expect(c.djgW2WindowDays, 3);
    });

    test('gate needs a Phase B build AND the switch', () {
      const on = PhaseBConfig(djgW2InAppEnabled: true);
      const off = PhaseBConfig();
      expect(DjgW2Gate.activeFor(on, phaseB: true), true);
      expect(DjgW2Gate.activeFor(on, phaseB: false), false);
      expect(DjgW2Gate.activeFor(off, phaseB: true), false);
    });

    test('this build: gate follows PHASE_B (Phase A build never shows it)', () {
      final saved = PhaseBConfig.current;
      addTearDown(() => PhaseBConfig.current = saved);
      PhaseBConfig.current = const PhaseBConfig(djgW2InAppEnabled: true);
      expect(DjgW2Gate.active, FeatureFlags.phaseB);
      PhaseBConfig.current = const PhaseBConfig();
      expect(DjgW2Gate.active, false);
    });
  });

  group('window (W0 = day 1)', () {
    final w0 = DateTime(2026, 10, 1, 18, 30);
    DateTime day(int n, [int hour = 9]) => DateTime(2026, 10, n, hour);
    const cfg = PhaseBConfig();

    test('day 13 closed, 14 open, 20 open, 21 closed', () {
      expect(DjgW2Window.day(w0, day(13)), 13);
      expect(DjgW2Window.isOpen(w0, day(13, 23), cfg), false);
      expect(DjgW2Window.isOpen(w0, day(14, 0), cfg), true);
      expect(DjgW2Window.isOpen(w0, day(20, 23), cfg), true);
      expect(DjgW2Window.isOpen(w0, day(21, 0), cfg), false);
    });

    test('configurable', () {
      const c = PhaseBConfig(djgW2DayOffset: 15, djgW2WindowDays: 2);
      expect(DjgW2Window.isOpen(w0, day(14), c), false);
      expect(DjgW2Window.isOpen(w0, day(16), c), true);
      expect(DjgW2Window.isOpen(w0, day(17), c), false);
    });
  });

  group('page — one item per screen', () {
    testWidgets('answer, go back, skip, submit', (tester) async {
      final store = _FakeStore();
      final popped = <Object?>[];
      await _pump(tester, store, popped: popped);

      expect(find.text('第 1 題（共 6 題）'), findsOneWidget);
      expect(find.text('我有一種空虛的感覺。'), findsOneWidget);
      expect(find.text('是'), findsOneWidget);
      expect(find.text('大致是'), findsOneWidget);
      expect(find.text('不是'), findsOneWidget);

      await tester.tap(find.text('是'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 題（共 6 題）'), findsOneWidget);
      expect(store.saves.single.answers, {'q1': 'yes'});
      expect(store.saves.single.first, true);
      expect(store.saves.single.submit, false);

      // Back to item 1: the earlier answer is still there; change it.
      await tester.tap(find.text('上一題'));
      await tester.pumpAndSettle();
      expect(find.text('我有一種空虛的感覺。'), findsOneWidget);
      await tester.tap(find.text('大致是'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('跳過呢題')); // q2
      await tester.pumpAndSettle();
      for (final label in ['不是', '是', '大致是', '不是']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(find.text('提交'), findsOneWidget);
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();

      final last = store.saves.last;
      expect(last.submit, true);
      expect(last.answers, {
        'q1': 'mostly', 'q2': 'skipped', 'q3': 'no',
        'q4': 'yes', 'q5': 'mostly', 'q6': 'no',
      });
      expect(store.saves.where((s) => s.first).length, 1);
      expect(popped, [true]);
    });

    testWidgets('resumes at the first unanswered item', (tester) async {
      final store = _FakeStore(const DjgW2Saved(
          status: 'in_progress', answers: {'q1': 'yes', 'q2': 'no'}, hasStarted: true));
      await _pump(tester, store);
      expect(find.text('第 3 題（共 6 題）'), findsOneWidget);
      await tester.tap(find.text('是'));
      await tester.pumpAndSettle();
      expect(store.saves.single.first, false);
      expect(store.saves.single.answers, {'q1': 'yes', 'q2': 'no', 'q3': 'yes'});
    });

    testWidgets('server-created pending doc: first save adds the start time', (tester) async {
      final store = _FakeStore(const DjgW2Saved(
          status: 'pending', answers: {'q1': 'yes', 'q2': 'no', 'q3': 'no', 'q4': 'no',
            'q5': 'no', 'q6': 'no'}));
      await _pump(tester, store);
      // Pending (server-created) doc with no start time: first save adds it.
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      expect(store.saves.single.first, true);
      expect(store.saves.single.submit, true);
    });

    testWidgets('submitted or missed: nothing to answer', (tester) async {
      await _pump(tester, _FakeStore(const DjgW2Saved(status: 'missed')));
      expect(find.text('是'), findsNothing);
      expect(find.textContaining('唔使再答'), findsOneWidget);
    });
  });

  test('page and data never look at the arm (both arms identical)', () {
    for (final f in [
      'lib/features/assessment/data/djg_w2.dart',
      'lib/features/assessment/presentation/pages/djg_w2_page.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains('arm_scope'), false, reason: f);
      expect(RegExp(r'\bArm\.').hasMatch(src), false, reason: f);
      expect(src.contains('ArmGate'), false, reason: f);
    }
  });
}
