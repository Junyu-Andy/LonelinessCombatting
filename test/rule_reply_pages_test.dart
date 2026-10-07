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

Future<NoLlmClient> _open(WidgetTester tester, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final client = NoLlmClient();
  await tester.pumpWidget(ruleReplyHarness(page, client));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return client;
}

Future<void> _fillCheckIn(WidgetTester tester, String note) async {
  await tester.tap(find.text('😔'));
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
        find.textContaining('【占位】小欣·簽到·心情差·第1條', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('收到喇。聽日再見。'), findsNothing);
      expect(await store.recent(uid: null, agentId: 'siu_yan'), [
        'sy_ci_low_1',
      ]);
      expect(client.calls, 0);
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
        find.textContaining('【占位】阿珍·回憶第1週·心情好·第1條', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(MoodFacePicker), findsNothing);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byType(ReminiscenceArmBPage), findsNothing);
      expect(client.calls, 0);
    }, skip: !_on);

    testWidgets('reminiscence B: no mood picked → "none" sub-pool', (
      tester,
    ) async {
      final store = InMemoryRuleReplyHistoryStore();
      await _open(
        tester,
        ReminiscenceArmBPage(theme: week1, replyHistory: store),
      );
      await _saveMemory(tester, '細個住喺深水埗');
      expect(
        find.textContaining('【占位】阿珍·回憶第1週·心情未選·第1條', findRichText: true),
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
