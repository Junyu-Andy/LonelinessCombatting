// T25 (C14 / C16) — widget tests: invitation card copy (S10a / S10b
// verbatim, 阿珍 vs 阿伯), 48×48 touch targets at a large text scale, the
// one-question-per-screen flow ("1/4", next / submit, back, abandon),
// duplicate submission blocked, S9 close button label, and the card host
// rendering nothing while the switch is off.  In-memory store, fake clock.
import 'package:app_demo/core/session/session_rules.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_record.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_scheduler.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/presentation/pages/brief_pr_flow_page.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/brief_pr_card_host.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/brief_pr_invite_card.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_button.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rules = SessionRules(v2: true, idleTimeoutMin: 30);
final t0 = DateTime(2026, 10, 14, 15, 20); // Wednesday afternoon

BriefPrRecord record({
  String agent = 'tung_tung',
  String name = '通通',
  String endReason = SessionEndReason.closeButton,
  DateTime? endedAt,
}) =>
    BriefPrRecord(
      uid: 'u1',
      sessionId: 's1',
      agentId: agent,
      agentDisplayName: name,
      sessionType: 'free_chat',
      endReason: endReason,
      sessionEndedAt: endedAt ?? t0,
      lastReplyAt: endedAt ?? t0,
      invitedAt: endedAt ?? t0,
      invitedDayKey: '2026-10-14',
      inviteChannel: SessionEndReason.isCatchUp(endReason)
          ? BriefPrInviteChannel.catchUp
          : BriefPrInviteChannel.listPage,
    );

Widget wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: ListView(children: [child])),
      ),
    );

void main() {
  group('S10a / S10b copy', () {
    test('text is verbatim from short-texts.md', () {
      expect(
          BriefPrInviteCard.text(
              channel: BriefPrInviteChannel.listPage,
              agentName: '小欣',
              sessionEndedAt: t0,
              now: t0),
          '頭先同小欣傾完，想問你四條簡單問題，大概半分鐘。');
      expect(
          BriefPrInviteCard.text(
              channel: BriefPrInviteChannel.catchUp,
              agentName: '阿伯',
              sessionEndedAt: DateTime(2026, 10, 14, 9, 0),
              now: DateTime(2026, 10, 14, 10, 0)),
          '你頭先同阿伯傾過偈，想問返你嗰次嘅感覺，大概半分鐘。');
      expect(
          BriefPrInviteCard.text(
              channel: BriefPrInviteChannel.catchUp,
              agentName: '阿珍',
              sessionEndedAt: t0,
              now: t0.add(const Duration(hours: 1))),
          '你頭先同阿珍傾過偈，想問返你嗰次嘅感覺，大概半分鐘。');
      expect(BriefPrInviteCard.acceptLabel, '好呀');
      expect(BriefPrInviteCard.skipLabel, '今次唔評');
      expect(SessionCloseButton.label, '今日傾到呢度');
      // 1014e §2.8: the first-use note and the questionnaire buttons are
      // final; no 【占位】 anywhere on these screens.
      expect(SessionCloseButton.firstUseNote,
          '撳「今日傾到呢度」就係今次傾完。想再傾隨時返嚟。');
      expect(BriefPrFlowPage.nextLabel, '下一題');
      expect(BriefPrFlowPage.backLabel, '上一題');
      expect(BriefPrFlowPage.abandonLabel, '唔評住');
      for (final s in [
        SessionCloseButton.firstUseNote, BriefPrFlowPage.nextLabel,
        BriefPrFlowPage.backLabel, BriefPrFlowPage.abandonLabel,
        BriefPrScheduler.timePhraseFixed,
      ]) {
        expect(s, isNot(contains('【占位】')));
      }
    });

    testWidgets('card shows the copy and both buttons; nothing else blocks',
        (tester) async {
      var accepted = 0, skipped = 0;
      await tester.pumpWidget(wrap(BriefPrInviteCard(
        record: record(),
        channel: BriefPrInviteChannel.listPage,
        now: t0,
        onAccept: () => accepted++,
        onSkip: () => skipped++,
      )));
      expect(find.text('頭先同通通傾完，想問你四條簡單問題，大概半分鐘。'), findsOneWidget);
      await tester.tap(find.text('好呀'));
      await tester.tap(find.text('今次唔評'));
      expect(accepted, 1);
      expect(skipped, 1);
    });

    testWidgets('both buttons are ≥ 48×48 at text scale 1.0 and 2.0',
        (tester) async {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(wrap(
          BriefPrInviteCard(
            record: record(endReason: SessionEndReason.timeout),
            channel: BriefPrInviteChannel.catchUp,
            now: t0.add(const Duration(minutes: 30)),
            onAccept: () {},
            onSkip: () {},
          ),
          textScale: scale,
        ));
        for (final k in ['brief_pr_accept', 'brief_pr_skip']) {
          final size = tester.getSize(find.byKey(Key(k)));
          expect(size.width, greaterThanOrEqualTo(48), reason: '$k @ $scale');
          expect(size.height, greaterThanOrEqualTo(48), reason: '$k @ $scale');
        }
      }
    });
  });

  group('flow page', () {
    late InMemoryBriefPrStore store;
    late BriefPrScheduler scheduler;
    late DateTime now;

    setUp(() async {
      now = t0;
      store = InMemoryBriefPrStore();
      scheduler = BriefPrScheduler(store: store, rules: rules, clock: () => now);
      await store.put(record());
    });

    void tallScreen(WidgetTester tester) {
      // The 7 option rows + buttons do not fit the 800×600 default surface.
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> open(WidgetTester tester) async {
      tallScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: BriefPrFlowPage(record: store.records['u1/s1']!, scheduler: scheduler),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('scale row fits a small phone with large text (no overflow)',
        (tester) async {
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: BriefPrFlowPage(record: store.records['u1/s1']!, scheduler: scheduler),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('brief_pr_option_7')));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const Key('brief_pr_next'))).onPressed,
          isNotNull);
    });

    testWidgets('one question per screen with N/4, next until the last, then 完成',
        (tester) async {
      await open(tester);
      expect(find.text('1/4'), findsOneWidget);
      expect(find.text(BriefPrFlowPage.stem), findsOneWidget);
      expect(find.text('通通 明白我。'), findsOneWidget);
      // Full-text anchors under the scale.
      expect(find.text('完全唔係咁'), findsOneWidget);
      expect(find.text('一半半'), findsOneWidget);
      expect(find.text('完全係咁'), findsOneWidget);
      // 10/19: the seven points sit side by side in one row, 1 → 7 left to
      // right, with the anchors underneath.
      final y1 = tester.getCenter(find.byKey(const Key('brief_pr_option_1'))).dy;
      for (var v = 2; v <= 7; v++) {
        final c = tester.getCenter(find.byKey(Key('brief_pr_option_$v')));
        expect(c.dy, y1, reason: 'option $v on the same row');
        expect(c.dx,
            greaterThan(tester.getCenter(find.byKey(Key('brief_pr_option_${v - 1}'))).dx));
      }
      expect(tester.getCenter(find.text('完全唔係咁')).dy, greaterThan(y1));
      // Next is disabled until an option is tapped.
      expect(tester.widget<FilledButton>(find.byKey(const Key('brief_pr_next'))).onPressed,
          isNull);
      expect(find.text(BriefPrFlowPage.nextLabel), findsOneWidget);
      await tester.tap(find.byKey(const Key('brief_pr_option_6')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('brief_pr_next')));
      await tester.pumpAndSettle();
      expect(find.text('2/4'), findsOneWidget);
      expect(find.text('通通 尊重我。'), findsOneWidget);
      // Back returns to the previous question with the answer kept.
      await tester.tap(find.byKey(const Key('brief_pr_back')));
      await tester.pumpAndSettle();
      expect(find.text('1/4'), findsOneWidget);
      await tester.tap(find.byKey(const Key('brief_pr_next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('brief_pr_option_5')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('brief_pr_next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('brief_pr_option_4')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('brief_pr_next')));
      await tester.pumpAndSettle();
      expect(find.text('4/4'), findsOneWidget);
      expect(find.text('通通 嘅回應好似搞錯重點，或者唔在乎。'), findsOneWidget);
      expect(find.text('有少少'), findsOneWidget);
      expect(find.text(BriefPrFlowPage.submitLabel), findsOneWidget);
      await tester.tap(find.byKey(const Key('brief_pr_option_2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('brief_pr_next')));
      await tester.pumpAndSettle();
      final r = store.records['u1/s1']!;
      expect(r.finalStatus, BriefPrStatus.completed);
      expect(r.items, {'understanding': 6, 'validation': 5, 'caring': 4, 'insensitivity': 2});
    });

    testWidgets('abandon after one answer → partially_completed', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('brief_pr_option_3')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('brief_pr_next')));
      await tester.pumpAndSettle();
      expect(find.text(BriefPrFlowPage.abandonLabel), findsOneWidget);
      await tester.tap(find.byKey(const Key('brief_pr_abandon')));
      await tester.pumpAndSettle();
      final r = store.records['u1/s1']!;
      expect(r.finalStatus, BriefPrStatus.partiallyCompleted);
      expect(r.items, {'understanding': 3});
    });

    testWidgets('abandon with no answer → skipped; a second flow on the same '
        'record cannot overwrite it', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('brief_pr_abandon')));
      await tester.pumpAndSettle();
      expect(store.records['u1/s1']!.finalStatus, BriefPrStatus.skipped);
      final puts = store.putCount;
      // Stale card re-opened (e.g. from a second tab) and fully answered.
      await tester.pumpWidget(MaterialApp(
        home: BriefPrFlowPage(record: record(), scheduler: scheduler),
      ));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('brief_pr_option_7')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('brief_pr_next')));
        await tester.pumpAndSettle();
      }
      expect(store.putCount, puts);
      expect(store.records['u1/s1']!.finalStatus, BriefPrStatus.skipped);
      expect(store.records.length, 1);
    });
  });

  group('card host', () {
    testWidgets('shows the pending card, marks it shown, skip → skipped',
        (tester) async {
      final store = InMemoryBriefPrStore();
      var now = t0.add(const Duration(minutes: 5));
      final scheduler = BriefPrScheduler(
          store: store, rules: rules, clock: () => now, processStartedAt: t0);
      await store.put(record(agent: 'ah_jan_ah_bak', name: '阿伯'));
      await tester.pumpWidget(wrap(BriefPrCardHost(
          scheduler: scheduler, uid: 'u1', clock: () => now)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('brief_pr_invite_card')), findsOneWidget);
      expect(find.text('頭先同阿伯傾完，想問你四條簡單問題，大概半分鐘。'), findsOneWidget);
      expect(store.records['u1/s1']!.everShown, isTrue);
      expect(store.records['u1/s1']!.inviteChannel, BriefPrInviteChannel.listPage);
      await tester.tap(find.byKey(const Key('brief_pr_skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('brief_pr_invite_card')), findsNothing);
      expect(store.records['u1/s1']!.finalStatus, BriefPrStatus.skipped);
    });

    testWidgets('timeout session → catch-up copy (S10b)', (tester) async {
      final store = InMemoryBriefPrStore();
      final now = t0.add(const Duration(minutes: 50));
      final scheduler = BriefPrScheduler(
          store: store, rules: rules, clock: () => now, processStartedAt: t0);
      await store.put(record(endReason: SessionEndReason.timeout));
      await tester.pumpWidget(wrap(BriefPrCardHost(
          scheduler: scheduler, uid: 'u1', clock: () => now)));
      await tester.pumpAndSettle();
      expect(find.text('你頭先同通通傾過偈，想問返你嗰次嘅感覺，大概半分鐘。'),
          findsOneWidget);
    });

    testWidgets('expired or no pending record → renders nothing', (tester) async {
      final store = InMemoryBriefPrStore();
      final now = t0.add(const Duration(hours: 2, minutes: 1));
      final scheduler = BriefPrScheduler(store: store, rules: rules, clock: () => now);
      await store.put(record(endReason: SessionEndReason.timeout));
      await tester.pumpWidget(wrap(BriefPrCardHost(
          scheduler: scheduler, uid: 'u1', clock: () => now)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('brief_pr_invite_card')), findsNothing);
      expect(store.records['u1/s1']!.finalStatus, BriefPrStatus.expired);
    });

    testWidgets('switch off (default config): host renders nothing even with '
        'a pending record', (tester) async {
      // No scheduler injected → BriefPrV2.enabled reads PhaseBConfig
      // defaults (switch off) and the host stays empty.
      await tester.pumpWidget(wrap(const BriefPrCardHost(uid: 'u1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('brief_pr_invite_card')), findsNothing);
    });
  });

  group('S9 close button', () {
    testWidgets('label verbatim, ≥ 48 px tall, first-use note shown once',
        (tester) async {
      // T46: the note's marker lives in shared_preferences; start empty.
      SharedPreferences.setMockInitialValues({});
      SessionCloseHint.resetForTest();
      await SessionCloseHint.restore();
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            leading: SessionCloseButton(onPressed: () => taps++),
            leadingWidth: SessionCloseButton.leadingWidth,
            title: const Text('通通'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('今日傾到呢度'), findsOneWidget);
      expect(find.text(SessionCloseButton.firstUseNote), findsOneWidget);
      final size = tester.getSize(find.byKey(const Key('session_close_button')));
      expect(size.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(const Key('session_close_button')));
      expect(taps, 1);
      // Second page in the same process: no note again.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            leading: SessionCloseButton(onPressed: () {}),
            leadingWidth: SessionCloseButton.leadingWidth,
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text(SessionCloseButton.firstUseNote), findsNothing);
    });
  });
}
