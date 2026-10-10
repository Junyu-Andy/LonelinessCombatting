// Decision 0023 — Arm B check-in / reminiscence pages with the template-
// reply flag off (default build: pages unchanged) and on:
//   flutter test --dart-define=RULE_TEMPLATE_REPLIES=true \
//     --dart-define=RULE_TEMPLATE_REPLIES_ALLOW_PLACEHOLDER=true \
//     test/rule_reply_pages_test.dart
import 'package:app_demo/features/crisis/presentation/pages/emergency_support_page.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_b.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_shared.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_pool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rule_reply_harness.dart';

final _on = RuleReplyPool.enabled;
const _bubble = ValueKey('rule_reply_bubble');

String _text(String id) =>
    RuleReplyPool.entries.firstWhere((e) => e.id == id).zh;

/// Mood face → first entry of its group: 😊 好好 (rank 5) → X1-1 …
/// 😔 好差 (rank 1) → X5-1.
List<(String, String)> _faces(String agent) => [
      ('😊', '${agent}1-1'),
      ('🙂', '${agent}2-1'),
      ('😐', '${agent}3-1'),
      ('🙁', '${agent}4-1'),
      ('😔', '${agent}5-1'),
    ];

Future<NoLlmClient> _open(WidgetTester tester, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final client = NoLlmClient();
  await tester.pumpWidget(ruleReplyHarness(page, client));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return client;
}

Future<void> _fillCheckIn(
  WidgetTester tester,
  String note, {
  String face = '😔',
}) async {
  await tester.tap(find.text(face));
  await tester.tap(find.text('少少'));
  await tester.tap(find.text('麻麻'));
  await tester.tap(find.text('一啲小事'));
  await tester.enterText(find.byType(TextField), note);
  await tester.pump();
  await tester.tap(find.text('儲存今日 Check-in'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _saveMemory(
  WidgetTester tester,
  String body, {
  String? face,
}) async {
  await tester.enterText(find.byType(TextField), body);
  if (face != null) await tester.tap(find.text(face));
  await tester.pump();
  await tester.tap(find.text('儲存呢段回憶'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  final week1 = ReminiscenceTheme.byIndex(1);

  group('flag off (default) — pages unchanged', () {
    testWidgets('check-in B: fixed line, no bubble', (tester) async {
      final client = await _open(tester, const CheckInArmB());
      await _fillCheckIn(tester, '今日去咗飲茶');
      expect(find.text('收到喇。聽日再見。'), findsOneWidget);
      expect(find.byKey(_bubble), findsNothing);
      expect(client.calls, 0);
    }, skip: _on);

    testWidgets('reminiscence B: no mood picker, closes itself', (
      tester,
    ) async {
      await _open(tester, ReminiscenceArmBPage(theme: week1));
      expect(find.byType(MoodFacePicker), findsNothing);
      expect(find.textContaining('占位'), findsNothing);
      await _saveMemory(tester, '細個住喺深水埗');
      expect(find.byType(ReminiscenceArmBPage), findsNothing);
      expect(find.byKey(_bubble), findsNothing);
    }, skip: _on);
  });

  group('flag on', () {
    testWidgets('check-in B: safe note → mood-band template bubble', (
      tester,
    ) async {
      final store = InMemoryRuleReplyHistoryStore();
      final client = await _open(tester, CheckInArmB(replyHistory: store));
      await _fillCheckIn(tester, '今日去咗飲茶');
      expect(find.byKey(_bubble), findsOneWidget);
      expect(
        find.textContaining(_text('X5-1'), findRichText: true),
        findsOneWidget,
      );
      expect(find.text('收到喇。聽日再見。'), findsNothing);
      expect(await store.recent(uid: null, agentId: 'siu_yan'), ['X5-1']);
      expect(client.calls, 0);
    }, skip: !_on);

    // T33 — each of the five faces picks its own group (X1 … X5).
    for (final (face, id) in _faces('X')) {
      testWidgets('check-in B: $face → $id', (tester) async {
        await _open(
          tester,
          CheckInArmB(replyHistory: InMemoryRuleReplyHistoryStore()),
        );
        await _fillCheckIn(tester, '今日去咗飲茶', face: face);
        expect(
          find.textContaining(_text(id), findRichText: true),
          findsOneWidget,
        );
      }, skip: !_on);
    }

    testWidgets('check-in B: grief note → no template (check-in has no Z5)', (
      tester,
    ) async {
      final store = InMemoryRuleReplyHistoryStore();
      await _open(tester, CheckInArmB(replyHistory: store));
      await _fillCheckIn(tester, '老伴走咗之後好難過');
      expect(find.byKey(_bubble, skipOffstage: false), findsNothing);
      expect(await store.recent(uid: null, agentId: 'siu_yan'), isEmpty);
    }, skip: !_on);

    testWidgets('check-in B: acute note → crisis page, no template', (
      tester,
    ) async {
      final store = InMemoryRuleReplyHistoryStore();
      await _open(tester, CheckInArmB(replyHistory: store));
      await _fillCheckIn(tester, '我真係想死');
      expect(find.byType(EmergencySupportPage), findsOneWidget);
      expect(find.byKey(_bubble, skipOffstage: false), findsNothing);
      expect(await store.recent(uid: null, agentId: 'siu_yan'), isEmpty);
    }, skip: !_on);

    testWidgets('check-in B: moderate note → no template', (tester) async {
      final store = InMemoryRuleReplyHistoryStore();
      await _open(tester, CheckInArmB(replyHistory: store));
      await _fillCheckIn(tester, '冇人理我');
      expect(find.byKey(_bubble, skipOffstage: false), findsNothing);
      expect(await store.recent(uid: null, agentId: 'siu_yan'), isEmpty);
    }, skip: !_on);

    testWidgets('reminiscence B: optional mood, bubble, then 完成 closes', (
      tester,
    ) async {
      final store = InMemoryRuleReplyHistoryStore();
      final client = await _open(
        tester,
        ReminiscenceArmBPage(theme: week1, replyHistory: store),
      );
      expect(find.byType(MoodFacePicker), findsOneWidget);
      await _saveMemory(tester, '細個住喺深水埗', face: '😊');
      expect(
        find.textContaining(_text('Z1-1'), findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(MoodFacePicker), findsNothing);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byType(ReminiscenceArmBPage), findsNothing);
      expect(client.calls, 0);
    }, skip: !_on);

    for (final (face, id) in _faces('Z')) {
      testWidgets('reminiscence B: $face → $id', (tester) async {
        await _open(
          tester,
          ReminiscenceArmBPage(
            theme: week1,
            replyHistory: InMemoryRuleReplyHistoryStore(),
          ),
        );
        await _saveMemory(tester, '細個住喺深水埗', face: face);
        expect(
          find.textContaining(_text(id), findRichText: true),
          findsOneWidget,
        );
      }, skip: !_on);
    }

    testWidgets('reminiscence B: grief (moderate_review) → Z5, any mood', (
      tester,
    ) async {
      final store = InMemoryRuleReplyHistoryStore();
      final client = await _open(
        tester,
        ReminiscenceArmBPage(theme: week1, replyHistory: store),
      );
      await _saveMemory(tester, '老伴走咗之後好難過', face: '😊');
      expect(
        find.textContaining(_text('Z5-1'), findRichText: true),
        findsOneWidget,
      );
      expect(await store.recent(uid: null, agentId: 'ah_jan_ah_bak'), [
        'Z5-1',
      ]);
      expect(client.calls, 0);
    }, skip: !_on);

    testWidgets('reminiscence B: moderate_interrupt → no template', (
      tester,
    ) async {
      final store = InMemoryRuleReplyHistoryStore();
      await _open(
        tester,
        ReminiscenceArmBPage(theme: week1, replyHistory: store),
      );
      await _saveMemory(tester, '冇人理我');
      expect(find.byKey(_bubble, skipOffstage: false), findsNothing);
      expect(await store.recent(uid: null, agentId: 'ah_jan_ah_bak'), isEmpty);
    }, skip: !_on);

    testWidgets('reminiscence B: no mood picked → G-1', (
      tester,
    ) async {
      final store = InMemoryRuleReplyHistoryStore();
      await _open(
        tester,
        ReminiscenceArmBPage(theme: week1, replyHistory: store),
      );
      await _saveMemory(tester, '細個住喺深水埗');
      expect(
        find.textContaining(_text('G-1'), findRichText: true),
        findsOneWidget,
      );
    }, skip: !_on);

    testWidgets('reminiscence B: acute → crisis page, no template', (
      tester,
    ) async {
      final store = InMemoryRuleReplyHistoryStore();
      await _open(
        tester,
        ReminiscenceArmBPage(theme: week1, replyHistory: store),
      );
      await _saveMemory(tester, '我真係想死');
      expect(find.byType(EmergencySupportPage), findsOneWidget);
      expect(find.byKey(_bubble, skipOffstage: false), findsNothing);
      expect(await store.recent(uid: null, agentId: 'ah_jan_ah_bak'), isEmpty);
    }, skip: !_on);
  });
}
