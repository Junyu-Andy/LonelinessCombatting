// 1020m 第二节 — page 1's small-action row in 「今日要做嘅事」
// (HomeSmallActionRow; decision 0064).  Synthetic accounts only, both arms
// (each Phase B build shows the arms it can), a fake clock for the days.
// No switch of its own: it is part of page 1 (homeLayoutV2Enabled) and
// replaced the old plan follow-up banner there (home_v2_test checks the
// order and that ActivePlanBanner is gone).
import 'dart:async';

import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/usage/usage_event_recorder.dart';
import 'package:app_demo/features/action_loop/data/action_plan.dart';
import 'package:app_demo/features/action_loop/data/home_small_action.dart';
import 'package:app_demo/features/action_loop/presentation/pages/action_loop_landing.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/social_suggestions/presentation/pages/social_suggestions_page.dart';
import 'package:app_demo/features/today/data/home_v2_copy.dart';
import 'package:app_demo/features/today/data/small_action_row_store.dart';
import 'package:app_demo/features/today/presentation/home_v2_scope.dart';
import 'package:app_demo/features/today/presentation/widgets/home_small_action_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_v2_harness.dart';

const _on = RemoteFeatureFlags(
  homeLayoutV2Enabled: true,
  moodRowV2Enabled: true,
  checkInChatV2Enabled: true,
);

final _ask = find.byKey(const ValueKey('today_todo_small_action_ask'));
final _later = find.byKey(const ValueKey('today_todo_small_action_later'));
final _planRow = find.byKey(const ValueKey('today_todo_small_action_plan'));
final _doneRow = find.byKey(const ValueKey('today_todo_small_action_done'));
final _doneBtn =
    find.byKey(const ValueKey('today_todo_small_action_done_button'));
final _postponeBtn =
    find.byKey(const ValueKey('today_todo_small_action_postpone_button'));

/// The row as page 1 shows it (inside 「今日要做嘅事」).
Widget _page() => const Scaffold(
      body: HomeSurfaceScope(
        surface: 'page1',
        child: SingleChildScrollView(child: HomeSmallActionRow()),
      ),
    );

Future<void> _pump(WidgetTester tester, HomeRun run,
    {Size size = const Size(400, 900), double? textScale}) async {
  addTearDown(() => expect(run.llm.calls, isEmpty,
      reason: 'the small-action row never calls a model (either arm)'));
  await pumpHome(tester, run, _page(), size: size, textScale: textScale);
}

/// Back to the App on a later day (paused → resumed), like the elder
/// opening it the next morning.
Future<void> _toDay(WidgetTester tester, HomeRun run, DateTime at) async {
  run.now = at;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await settle(tester);
}

/// A cold start the same day: the row is built again from scratch.
Future<void> _restart(WidgetTester tester, HomeRun run) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(homeHarness(run, home: _page()));
  await settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await settle(tester);
}

List<UsageEvent> _usage(HomeRun run) => [
      for (final e in run.usageSink.events)
        if (e.type.isHomeSmallAction) e,
    ];

List<String> _usageCodes(HomeRun run) => [
      for (final e in _usage(run))
        [
          e.type.code.replaceFirst('home_small_action_', ''),
          if (e.rowState != null) e.rowState!,
          if (e.planId != null) e.planId!,
          if (e.moved != null) 'moved=${e.moved}',
        ].join(':'),
    ];

/// Plans saved the day before at [hour] (their day is 10/20).  Test times
/// stay between 01:00 and 15:00 so the Hong Kong day (what the App keys
/// days by) is the same on a test machine set to UTC or to Hong Kong.
void _seedPlan(HomeRun run, String id,
    {String action = '去公園行下', int hour = 11, bool reminder = true}) {
  run.smallActions.addPlan(id,
      action: action,
      createdAt: DateTime(2026, 10, 19, hour),
      arm: run.rule ? 'B' : 'A',
      withReminder: reminder);
}

/// Every key the row may add to a plan document (no free text).
const _homeKeys = {
  'outcome', 'followUpSource', 'followedUpAt', 'homeRowStatus',
  'homeRowAnsweredDate', 'homeRowAnsweredAt', 'homeRowLaterCount',
  'homeRowDueDate', 'homeRowLog',
};

/// 我嘅計劃 (ActionLoopLandingPage) reading the same plan documents.
class _StoreRepo extends ActionPlanRepository {
  _StoreRepo(this.store) : super(available: true);
  final InMemorySmallActionRowStore store;

  @override
  Stream<List<ActionPlan>> pending(String uid) async* {
    yield [
      for (final e in store.planDocs.entries)
        if (ActionPlan.fromMap(e.key, e.value).isPending)
          ActionPlan.fromMap(e.key, e.value),
    ];
  }
}

void main() {
  late RemoteFeatureFlags savedFlags;

  setUp(() {
    savedFlags = RemoteFeatureFlags.current;
    RemoteFeatureFlags.current = _on;
    HomeSmallActionRow.resetShownLog();
  });

  tearDown(() {
    RemoteFeatureFlags.current = savedFlags;
    ActionPlanRepository.testOverride = null;
  });

  // -------------------------------------------------------------------
  // Pure rules
  // -------------------------------------------------------------------

  group('HomeSmallAction (pure)', () {
    ActionPlan plan(String id,
            {DateTime? createdAt,
            String? due,
            String? answered,
            String? status,
            int laterCount = 0,
            FollowUpOutcome? outcome,
            DateTime? deletedAt}) =>
        ActionPlan(
          id: id,
          action: '飲茶',
          whenText: '上晝',
          whereText: '',
          whoWith: '',
          fallback: '',
          armCode: 'B',
          createdAt: createdAt ?? DateTime(2026, 10, 19, 10),
          outcome: outcome,
          deletedAt: deletedAt,
          homeRowDueDate: due,
          homeRowAnsweredDate: answered,
          homeRowStatus: status,
          homeRowLaterCount: laterCount,
        );
    final today = DateTime(2026, 10, 20, 9, 30);

    test('a plan\'s day = its follow-up reminder\'s day (saved + 24 h), '
        'or the day 改日 moved it to', () {
      expect(HomeSmallAction.dueDateOf(plan('a')), '2026-10-20');
      expect(
          HomeSmallAction.dueDateOf(
              plan('a', createdAt: DateTime(2026, 10, 19, 1, 5))),
          '2026-10-20');
      expect(HomeSmallAction.dueDateOf(plan('a', due: '2026-10-22')),
          '2026-10-22');
      expect(HomeSmallAction.addDays('2026-10-31', 1), '2026-11-01');
      expect(HomeSmallAction.addDays('2026-12-31', 1), '2027-01-01');
    });

    test('遲啲先: hidden on the day and the next two, back on day 4', () {
      const mark = '2026-10-20';
      expect(HomeSmallAction.snoozed(mark, '2026-10-20'), isTrue);
      expect(HomeSmallAction.snoozed(mark, '2026-10-21'), isTrue);
      expect(HomeSmallAction.snoozed(mark, '2026-10-22'), isTrue);
      expect(HomeSmallAction.snoozed(mark, '2026-10-23'), isFalse);
      expect(HomeSmallAction.snoozed(mark, '2026-10-19'), isFalse);
      expect(HomeSmallAction.snoozed(null, '2026-10-20'), isFalse);
    });

    test('resolve: answered today first, then today\'s plan, then ask', () {
      HomeSmallActionView view(List<ActionPlan> ps, {String? mark}) =>
          HomeSmallAction.resolve(ps, today, laterMark: mark).view;
      expect(view([]), HomeSmallActionView.ask);
      expect(view([], mark: '2026-10-19'), HomeSmallActionView.hidden);
      expect(view([plan('a')]), HomeSmallActionView.plan);
      // A plan for today beats 遲啲先.
      expect(view([plan('a')], mark: '2026-10-20'), HomeSmallActionView.plan);
      // Tomorrow's plan (made today) is not today's.
      expect(view([plan('a', createdAt: today)]), HomeSmallActionView.ask);
      // A plan overdue from yesterday is not today's either.
      expect(view([plan('a', createdAt: DateTime(2026, 10, 18, 10))]),
          HomeSmallActionView.ask);
      expect(
          view([plan('a', answered: '2026-10-20', status: 'done',
              outcome: FollowUpOutcome.happened)]),
          HomeSmallActionView.done);
      expect(
          view([plan('a', answered: '2026-10-20', status: 'later',
              due: '2026-10-21', laterCount: 1)]),
          HomeSmallActionView.hidden);
      // One answer a day: another plan for today waits.
      expect(
          view([
            plan('a', answered: '2026-10-20', status: 'later',
                due: '2026-10-21', laterCount: 1),
            plan('b', createdAt: DateTime(2026, 10, 19, 12)),
          ]),
          HomeSmallActionView.hidden);
      // Answered on the 件事點呀 page: a tick (happened) or nothing.
      expect(view([plan('a', outcome: FollowUpOutcome.happened)]),
          HomeSmallActionView.done);
      expect(view([plan('a', outcome: FollowUpOutcome.didNotHappen)]),
          HomeSmallActionView.hidden);
      // Deleted plans never show.
      expect(view([plan('a', deletedAt: today)]), HomeSmallActionView.ask);
      // The oldest of today's plans.
      final s = HomeSmallAction.resolve([
        plan('late', createdAt: DateTime(2026, 10, 19, 15)),
        plan('early', createdAt: DateTime(2026, 10, 19, 8)),
      ], today);
      expect(s.plan!.id, 'early');
    });

    test('改日: the first press moves to tomorrow, the second does not', () {
      final first = HomeSmallAction.postpone(plan('a'), today);
      expect((first.moved, first.movedTo, first.laterCount),
          (true, '2026-10-21', 1));
      final second = HomeSmallAction.postpone(
          plan('a', due: '2026-10-21', laterCount: 1),
          DateTime(2026, 10, 21, 9));
      expect((second.moved, second.movedTo, second.laterCount),
          (false, null, 2));
      expect(HomeSmallAction.postponeUpdate(second, today).keys.toSet(),
          {'homeRowStatus', 'homeRowAnsweredDate', 'homeRowLaterCount',
            HomeSmallAction.logEntryKey});
      expect(
          HomeSmallAction.postponeUpdate(first, today)['homeRowDueDate'],
          '2026-10-21');
      expect(HomeSmallAction.postponeUpdate(first, today),
          isNot(contains('outcome')),
          reason: '改日 keeps the plan waiting (我嘅計劃)');
    });

    test('做咗: the existing follow-up answer + followUpSource home_row', () {
      final u = HomeSmallAction.doneUpdate(today);
      expect(u['outcome'], 'happened');
      expect(u['followUpSource'], 'home_row');
      expect(u['homeRowStatus'], 'done');
      expect(u['homeRowAnsweredDate'], '2026-10-20');
      expect(u[HomeSmallAction.logEntryKey],
          {'status': 'done', 'atLocal': today.toIso8601String(),
            'forDate': '2026-10-20', 'movedTo': null});
    });

    test('reminders: 改日 moves the waiting one to tomorrow, same time; '
        'queues one when it was already sent; second 改日 / 做咗 drop them',
        () {
      final p = plan('a', createdAt: DateTime(2026, 10, 19, 10, 5));
      final first = HomeSmallAction.postpone(p, today);
      const waiting = PlanReminder(id: 'r1', fireAt: '2026-10-20T10:05:00.000');
      final ops = HomeSmallAction.reminderOpsAfterPostpone(p, first, [waiting]);
      expect(ops.single.kind, PlanReminderOpKind.move);
      expect((ops.single.from, ops.single.to),
          ('2026-10-20T10:05:00.000', '2026-10-21T10:05:00.000'));
      // Already sent (no waiting one), or the server gave up: queue anew.
      for (final unsent in [
        const <PlanReminder>[],
        const [PlanReminder(id: 'r1', fireAt: '2026-10-20T10:05:00.000',
            dispatchStatus: 'skipped_stale')],
      ]) {
        final o = HomeSmallAction.reminderOpsAfterPostpone(p, first, unsent);
        expect(o.single.kind, PlanReminderOpKind.create);
        expect(o.single.request!.fireAt, DateTime(2026, 10, 21, 10, 5));
        expect(o.single.request!.kind, 'm7_followup');
        expect(o.single.request!.linkedDocId, 'a');
      }
      // A retry still waiting is moved too.
      expect(
          HomeSmallAction.reminderOpsAfterPostpone(p, first, const [
            PlanReminder(id: 'r1', fireAt: '2026-10-20T10:05:00.000',
                dispatchStatus: 'retry_no_tokens'),
          ]).single.kind,
          PlanReminderOpKind.move);
      final second = HomeSmallAction.postpone(
          plan('a', due: '2026-10-21', laterCount: 1),
          DateTime(2026, 10, 21, 9));
      final drop = HomeSmallAction.reminderOpsAfterPostpone(p, second, const [
        PlanReminder(id: 'r1', fireAt: '2026-10-21T10:05:00.000'),
      ]);
      expect(drop.single.kind, PlanReminderOpKind.delete);
      expect(
          HomeSmallAction.reminderOpsAfterDone(const [waiting]).single.kind,
          PlanReminderOpKind.delete);
      // A UTC fireAt keeps its Hong Kong clock time.
      expect(HomeSmallAction.fireAtOnDay('2026-10-20T10:05:00.000Z',
          '2026-10-21'), '2026-10-21T10:05:00.000Z');
      expect(HomeSmallAction.fireAtDay('2026-10-20T10:05:00.000'),
          '2026-10-20');
      expect(HomeSmallAction.fireAtDay('2026-10-20T01:05:00.000Z'),
          '2026-10-20');
    });

    test('usage rows: only ids and fixed codes; malformed ones dropped', () {
      final sink = InMemoryUsageEventSink();
      final rec = UsageEventRecorder(
          sink: sink, enabled: () => true, appVersion: '0', buildNumber: '0')
        ..setProfile(homeProfile(ArmAssignment.b));
      const t = UsageEventType.homeSmallActionShown;
      expect(rec.recordHomeSmallAction(t, rowState: 'ask'), isTrue);
      expect(rec.recordHomeSmallAction(t, rowState: 'plan', planId: 'Ab_9-z'),
          isTrue);
      expect(rec.recordHomeSmallAction(t, rowState: 'plan'), isFalse);
      expect(rec.recordHomeSmallAction(t, rowState: 'hidden'), isFalse);
      expect(
          rec.recordHomeSmallAction(UsageEventType.homeSmallActionDone,
              planId: '去公園'),
          isFalse);
      expect(
          rec.recordHomeSmallAction(UsageEventType.homeSmallActionPostpone,
              planId: 'p1'),
          isFalse, reason: 'moved is required');
      expect(
          rec.recordHomeSmallAction(UsageEventType.readerOpen, planId: 'p1'),
          isFalse);
      expect(
          rec.recordReader(UsageEventType.homeSmallActionLater, unitId: 'u1'),
          isFalse);
      expect(rec.recordHomeSmallAction(UsageEventType.homeSmallActionLater),
          isTrue);
      expect(sink.events.map((e) => e.toMap()..remove('clientAt')).toList(), [
        {'type': 'home_small_action_shown', 'appVersion': '0',
          'buildNumber': '0', 'platform': 'unknown', 'schemaVersion': 1,
          'rowState': 'ask'},
        {'type': 'home_small_action_shown', 'appVersion': '0',
          'buildNumber': '0', 'platform': 'unknown', 'schemaVersion': 1,
          'rowState': 'plan', 'planId': 'Ab_9-z'},
        {'type': 'home_small_action_later', 'appVersion': '0',
          'buildNumber': '0', 'platform': 'unknown', 'schemaVersion': 1},
      ]);
      // Not enrolled: nothing.
      rec.setProfile(homeProfile(ArmAssignment.b, cohort: null));
      expect(rec.recordHomeSmallAction(UsageEventType.homeSmallActionLater),
          isFalse);
    });

    test('the copy (SA1–SA5)', () {
      expect(HomeV2Copy.smallActionAsk, '今日想做啲咩小行動？');
      expect(HomeV2Copy.smallActionLater, '遲啲先');
      expect(HomeV2Copy.smallActionPlan('飲茶'), '今日計劃：飲茶');
      expect(HomeV2Copy.smallActionDone, '做咗');
      expect(HomeV2Copy.smallActionPostpone, '改日');
    });
  });

  testWidgets('without a test seam the row opens 今日小行動 (SocialSuggestionsPage)',
      (tester) async {
    late Widget page;
    await tester.pumpWidget(Builder(builder: (context) {
      page = HomeV2Scope.buildSmallActionPage(context);
      return const SizedBox();
    }));
    expect(page, isA<SocialSuggestionsPage>());
  });

  // -------------------------------------------------------------------
  // The row, both arms
  // -------------------------------------------------------------------

  for (final arm in testableArms) {
    final tag = arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';

    group(tag, () {
      testWidgets('no plan: 今日想做啲咩小行動？ + 遲啲先; tap → 今日小行動',
          (tester) async {
        final run = HomeRun(arm);
        await _pump(tester, run);
        expect(_ask, findsOneWidget);
        expect(find.text(HomeV2Copy.smallActionAsk), findsOneWidget);
        expect(find.text(HomeV2Copy.smallActionLater), findsOneWidget);
        expect(_planRow, findsNothing);
        await _tap(tester, find.text(HomeV2Copy.smallActionAsk));
        expect(run.smallActionPageOpens, 1);
        expect(find.text('今日小行動 page'), findsOneWidget);
        expect(_usageCodes(run), ['shown:ask', 'open']);
        expect(run.usageSink.events.where((e) => e.type.isHomeSmallAction),
            everyElement(predicate<UsageEvent>((e) => e.uid == 'u1')));
      });

      testWidgets('遲啲先: folds away; hidden days 1–3 (restart too), back on '
          'day 4', (tester) async {
        final run = HomeRun(arm);
        await _pump(tester, run);
        await _tap(tester, _later);
        expect(_ask, findsNothing);
        expect(find.text(HomeV2Copy.smallActionAsk), findsNothing);
        expect(run.smallActions.laterMark, '2026-10-20');
        expect(run.smallActionPageOpens, 0);
        await _restart(tester, run);
        expect(_ask, findsNothing, reason: 'day 1 after a restart');
        await _toDay(tester, run, DateTime(2026, 10, 21, 8));
        expect(_ask, findsNothing, reason: 'day 2');
        await _toDay(tester, run, DateTime(2026, 10, 22, 14, 50));
        expect(_ask, findsNothing, reason: 'day 3');
        await _toDay(tester, run, DateTime(2026, 10, 23, 7));
        expect(_ask, findsOneWidget, reason: 'day 4');
        expect(_usageCodes(run), ['shown:ask', 'later', 'shown:ask']);
      });

      testWidgets('a plan for today: 今日計劃 + 做咗 / 改日; 做咗 → tick, data, '
          'push dropped, not asked again that day', (tester) async {
        final run = HomeRun(arm);
        _seedPlan(run, 'p1');
        await _pump(tester, run);
        expect(find.text('今日計劃：去公園行下'), findsOneWidget);
        expect(_doneBtn, findsOneWidget);
        expect(_postponeBtn, findsOneWidget);
        expect(_ask, findsNothing);
        final before = Map<String, dynamic>.of(run.smallActions.planDocs['p1']!);
        expect(run.smallActions.remindersOf('p1'), hasLength(1));

        await _tap(tester, _doneBtn);
        expect(_doneRow, findsOneWidget);
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
        expect(find.text('今日計劃：去公園行下'), findsOneWidget);
        expect(_doneBtn, findsNothing);
        expect(_postponeBtn, findsNothing);
        final doc = run.smallActions.planDocs['p1']!;
        expect(doc['outcome'], 'happened');
        expect(doc['followUpSource'], 'home_row');
        expect(doc['homeRowStatus'], 'done');
        expect(doc['homeRowAnsweredDate'], '2026-10-20');
        expect(doc['followedUpAt'], isNotNull);
        expect(doc['homeRowLog'], hasLength(1));
        expect(doc['action'], before['action']);
        expect(doc['whenText'], before['whenText']);
        expect(doc.keys.toSet().difference(before.keys.toSet()),
            everyElement(isIn(_homeKeys)),
            reason: 'status fields only, no text');
        // That day's follow-up push is not sent (its reminder is gone).
        expect(run.smallActions.remindersOf('p1'), isEmpty);
        // Not asked again that day, even after a restart.
        await _restart(tester, run);
        expect(_doneRow, findsOneWidget);
        expect(_doneBtn, findsNothing);
        // Next day: no plan for that day → the question again.
        await _toDay(tester, run, DateTime(2026, 10, 21, 9));
        expect(_ask, findsOneWidget);
        expect(_usageCodes(run),
            ['shown:plan:p1', 'done:p1', 'shown:done:p1', 'shown:ask']);
      });

      testWidgets('改日: folds away; plan + reminder move to tomorrow, same '
          'time; shown again the next day', (tester) async {
        final run = HomeRun(arm);
        _seedPlan(run, 'p1', hour: 11);
        await _pump(tester, run);
        await _tap(tester, _postponeBtn);
        expect(_planRow, findsNothing);
        expect(_ask, findsNothing, reason: 'collapsed for the rest of day 1');
        final doc = run.smallActions.planDocs['p1']!;
        expect(doc['outcome'], isNull);
        expect(doc['homeRowStatus'], 'later');
        expect(doc['homeRowDueDate'], '2026-10-21');
        expect(doc['homeRowLaterCount'], 1);
        expect(doc.containsKey('followUpSource'), isFalse);
        expect(run.smallActions.plan('p1').isPending, isTrue);
        final r = run.smallActions.remindersOf('p1').single;
        expect(r['fireAt'], '2026-10-21T11:00:00.000');
        expect(r['movedFromFireAt'], '2026-10-20T11:00:00.000');
        expect(r['delivered'], isFalse);
        await _restart(tester, run);
        expect(_planRow, findsNothing, reason: 'day 1, restart');
        expect(_ask, findsNothing);
        await _toDay(tester, run, DateTime(2026, 10, 21, 9, 15));
        expect(_planRow, findsOneWidget);
        expect(find.text('今日計劃：去公園行下'), findsOneWidget);
        expect(_usageCodes(run), [
          'shown:plan:p1',
          'postpone:p1:moved=true',
          'shown:plan:p1',
        ]);
      });

      testWidgets('改日 after the day\'s push already went out: a new one is '
          'queued for tomorrow at the plan\'s time', (tester) async {
        final run = HomeRun(arm, now: DateTime(2026, 10, 20, 15));
        _seedPlan(run, 'p1', hour: 10);
        run.smallActions.deliverReminders('p1');
        await _pump(tester, run);
        await _tap(tester, _postponeBtn);
        final rs = run.smallActions.remindersOf('p1');
        expect(rs, hasLength(2));
        expect(rs.first['delivered'], isTrue);
        expect(rs.last['fireAt'], '2026-10-21T10:00:00.000');
        expect(rs.last['delivered'], isFalse);
        expect(rs.last['movedBy'], 'home_row');
      });

      testWidgets('two 改日 in a row: not moved again; day 3 asks '
          '今日想做啲咩小行動？; the plan stays in 我嘅計劃', (tester) async {
        final run = HomeRun(arm);
        _seedPlan(run, 'p1', action: '同阿明飲茶');
        await _pump(tester, run);
        await _tap(tester, _postponeBtn); // day 1 → day 2
        await _toDay(tester, run, DateTime(2026, 10, 21, 10));
        expect(find.text('今日計劃：同阿明飲茶'), findsOneWidget);
        await _tap(tester, _postponeBtn); // day 2: not moved
        expect(_planRow, findsNothing);
        expect(_ask, findsNothing, reason: 'collapsed for the rest of day 2');
        final doc = run.smallActions.planDocs['p1']!;
        expect(doc['homeRowLaterCount'], 2);
        expect(doc['homeRowDueDate'], '2026-10-21', reason: 'not moved');
        expect(doc['outcome'], isNull);
        expect(doc['deletedAt'], isNull);
        expect(doc['homeRowLog'], hasLength(2));
        expect((doc['homeRowLog'] as List).last,
            containsPair('movedTo', null));
        // Day 2's push is not sent: its reminder is gone.
        expect(run.smallActions.remindersOf('p1'), isEmpty);
        await _toDay(tester, run, DateTime(2026, 10, 22, 9));
        expect(_ask, findsOneWidget);
        expect(find.text(HomeV2Copy.smallActionAsk), findsOneWidget);
        expect(_planRow, findsNothing);
        expect(_usageCodes(run), [
          'shown:plan:p1',
          'postpone:p1:moved=true',
          'shown:plan:p1',
          'postpone:p1:moved=false',
          'shown:ask',
        ]);
        // 我嘅計劃 still lists it (waiting for 件事點呀).
        ActionPlanRepository.testOverride = _StoreRepo(run.smallActions);
        unawaited(run.navKey.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => const ActionLoopLandingPage())));
        await settle(tester);
        expect(find.text('同阿明飲茶'), findsOneWidget);
      });

      testWidgets('long plan text: one line ending in …, at 1.30 on a '
          '360-wide phone', (tester) async {
        final run = HomeRun(arm);
        const long = '星期六朝早同阿明、阿芳同埋舊同事一齊去公園行一個鐘，'
            '之後去茶樓飲早茶，再去街市買餸返屋企煮飯';
        _seedPlan(run, 'p1', action: long);
        await _pump(tester, run, size: const Size(360, 800), textScale: 1.30);
        final title = find.text('今日計劃：$long');
        expect(title, findsOneWidget);
        final text = tester.widget<Text>(title);
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        final para = tester.renderObject<RenderParagraph>(title);
        expect(para.didExceedMaxLines, isTrue);
        final lineHeight = para.text.style!.fontSize! * 1.30 * 1.3;
        expect(para.size.height, lessThan(lineHeight * 1.5),
            reason: 'one line, not several');
        expect(tester.takeException(), isNull);
        // Short plans and the buttons fit too.
        expect(_doneBtn, findsOneWidget);
        expect(_postponeBtn, findsOneWidget);
      });
    });
  }

  if (bothTestable) {
    testWidgets('both arms see the same row and write the same fields',
        (tester) async {
      final seen = <ArmAssignment, List<String>>{};
      final written = <ArmAssignment, Map<String, dynamic>>{};
      for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
        HomeSmallActionRow.resetShownLog();
        final run = HomeRun(arm);
        _seedPlan(run, 'p1');
        await _pump(tester, run);
        seen[arm] = [
          for (final t in tester.widgetList<Text>(find.descendant(
              of: _planRow, matching: find.byType(Text))))
            t.data ?? '',
        ];
        await _tap(tester, _doneBtn);
        written[arm] = Map.of(run.smallActions.planDocs['p1']!)
          ..remove('arm')
          ..remove('followedUpAt')
          ..remove('homeRowAnsweredAt');
        await tester.pumpWidget(const SizedBox());
      }
      expect(seen[ArmAssignment.a], seen[ArmAssignment.b]);
      expect(written[ArmAssignment.a].toString(),
          written[ArmAssignment.b].toString());
    });
  }
}
