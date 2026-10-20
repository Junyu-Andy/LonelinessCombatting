// 1020m 第二节 / 1020n 第三节、第五节 — page 1's small-action row in
// 「今日要做嘅事」 (HomeSmallActionRow; decision 0064).  Synthetic accounts only, both arms
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

final _ask = find.byKey(HomeSmallActionRow.askKey);
final _later = find.byKey(HomeSmallActionRow.laterKey);
final _more = find.byKey(HomeSmallActionRow.moreKey);
final _overflow = find.byKey(HomeSmallActionRow.overflowKey);
Finder _planOf(String id) => find.byKey(HomeSmallActionRow.planKey(id));
Finder _doneOf(String id) => find.byKey(HomeSmallActionRow.doneKey(id));
Finder _nextOf(String id) => find.byKey(HomeSmallActionRow.nextDayKey(id));
Finder _doneBtnOf(String id) =>
    find.byKey(HomeSmallActionRow.doneButtonKey(id));
Finder _postponeBtnOf(String id) =>
    find.byKey(HomeSmallActionRow.postponeButtonKey(id));
final _planRow = _planOf('p1');
final _doneRow = _doneOf('p1');
final _doneBtn = _doneBtnOf('p1');
final _postponeBtn = _postponeBtnOf('p1');

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

double _top(Finder f) =>
    (f.evaluate().single.renderObject! as RenderBox).localToGlobal(Offset.zero).dy;

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

/// 1020n 第五节: the plan text fills two lines and ends in 「…」.
void _expectTwoLines(WidgetTester tester, Finder title) {
  expect(title, findsOneWidget);
  final text = tester.widget<Text>(title);
  expect(text.maxLines, 2);
  expect(text.overflow, TextOverflow.ellipsis);
  final para = tester.renderObject<RenderParagraph>(title);
  expect(para.didExceedMaxLines, isTrue, reason: 'cut, with …');
  final lineHeight = para.text.style!.fontSize! * 1.30 * 1.3;
  expect(para.size.height, greaterThan(lineHeight * 1.5),
      reason: 'wraps to a second line');
  expect(para.size.height, lessThan(lineHeight * 2.5),
      reason: 'two lines, not more');
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

    test('resolve: one line per plan; today\'s first, then the day a plan '
        'is made, then ask', () {
      const ask = HomeSmallActionLineKind.ask;
      const planL = HomeSmallActionLineKind.plan;
      const doneL = HomeSmallActionLineKind.done;
      const next = HomeSmallActionLineKind.nextDayPlan;
      const more = HomeSmallActionLineKind.more;
      const over = HomeSmallActionLineKind.overflow;
      List<HomeSmallActionLineKind> kinds(List<ActionPlan> ps,
              {String? mark}) =>
          HomeSmallAction.resolve(ps, today, laterMark: mark).kinds;
      expect(kinds([]), [ask]);
      expect(kinds([], mark: '2026-10-19'), isEmpty);
      expect(kinds([plan('a')]), [planL]);
      // A plan for today beats 遲啲先.
      expect(kinds([plan('a')], mark: '2026-10-20'), [planL]);
      // Made today (its day is tomorrow): 聽日計劃 + 仲有冇其他計劃？, also
      // during 遲啲先 (no 遲啲先 in this state).
      expect(kinds([plan('a', createdAt: today)]), [next, more]);
      expect(kinds([plan('a', createdAt: today)], mark: '2026-10-20'),
          [next, more]);
      // Made earlier for a later day (not today's, not made today): ask.
      expect(kinds([plan('a', createdAt: DateTime(2026, 10, 18), due:
          '2026-10-25')]), [ask]);
      // A plan overdue from yesterday is not today's either.
      expect(kinds([plan('a', createdAt: DateTime(2026, 10, 18, 10))]),
          [ask]);
      expect(
          kinds([plan('a', answered: '2026-10-20', status: 'done',
              outcome: FollowUpOutcome.happened)]),
          [doneL]);
      // 改日 today: that line folds away; nothing else today → nothing.
      expect(
          kinds([plan('a', answered: '2026-10-20', status: 'later',
              due: '2026-10-21', laterCount: 1)]),
          isEmpty);
      // Each plan on its own: another plan for today still asks.
      final mixed = HomeSmallAction.resolve([
        plan('a', answered: '2026-10-20', status: 'later',
            due: '2026-10-21', laterCount: 1),
        plan('b', createdAt: DateTime(2026, 10, 19, 12)),
        plan('c', createdAt: DateTime(2026, 10, 19, 13),
            answered: '2026-10-20', status: 'done',
            outcome: FollowUpOutcome.happened),
      ], today);
      expect(mixed.kinds, [planL, doneL]);
      expect([for (final l in mixed.lines) l.plan!.id], ['b', 'c']);
      // 改日 today, then a new plan made today: 聽日計劃 for the new one.
      expect(
          kinds([
            plan('a', answered: '2026-10-20', status: 'later',
                due: '2026-10-21', laterCount: 1),
            plan('n', createdAt: today),
          ]),
          [next, more]);
      // Answered on the 件事點呀 page: a tick (happened) or nothing.
      expect(kinds([plan('a', outcome: FollowUpOutcome.happened)]), [doneL]);
      expect(kinds([plan('a', outcome: FollowUpOutcome.didNotHappen)]),
          isEmpty);
      // Deleted plans never show.
      expect(kinds([plan('a', deletedAt: today)]), [ask]);
      expect(kinds([plan('a', createdAt: today, deletedAt: today)]), [ask]);
      // In the order they were made; at most two, then 仲有 N 個計劃.
      final three = HomeSmallAction.resolve([
        plan('late', createdAt: DateTime(2026, 10, 19, 15)),
        plan('early', createdAt: DateTime(2026, 10, 19, 8)),
        plan('mid', createdAt: DateTime(2026, 10, 19, 11)),
        plan('last', createdAt: DateTime(2026, 10, 19, 14, 30)),
      ], today);
      expect(three.kinds, [planL, planL, over]);
      expect([three.lines[0].plan!.id, three.lines[1].plan!.id],
          ['early', 'mid']);
      expect(three.lines[2].count, 2);
      final threeNext = HomeSmallAction.resolve([
        for (final id in ['x', 'y', 'z']) plan(id, createdAt: today),
      ], today);
      expect(threeNext.kinds, [next, next, over, more]);
      expect(threeNext.lines[2].count, 1);
      expect([for (final l in threeNext.lines) l.rowState],
          ['next_day_plan', 'next_day_plan', null, null]);
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
      // 1020n: next_day_plan needs the plan id; more / list carry nothing.
      expect(rec.recordHomeSmallAction(t, rowState: 'next_day_plan'), isFalse);
      final probe = InMemoryUsageEventSink();
      final rec2 = UsageEventRecorder(
          sink: probe, enabled: () => true, appVersion: '0', buildNumber: '0')
        ..setProfile(homeProfile(ArmAssignment.a));
      expect(
          rec2.recordHomeSmallAction(t,
              rowState: 'next_day_plan', planId: 'p9'),
          isTrue);
      expect(
          rec2.recordHomeSmallAction(UsageEventType.homeSmallActionMore,
              planId: 'p9'),
          isTrue);
      expect(rec2.recordHomeSmallAction(UsageEventType.homeSmallActionList),
          isTrue);
      expect([for (final e in probe.events) e.toMap()..remove('clientAt')], [
        {'type': 'home_small_action_shown', 'appVersion': '0',
          'buildNumber': '0', 'platform': 'unknown', 'schemaVersion': 1,
          'rowState': 'next_day_plan', 'planId': 'p9'},
        {'type': 'home_small_action_more', 'appVersion': '0',
          'buildNumber': '0', 'platform': 'unknown', 'schemaVersion': 1},
        {'type': 'home_small_action_list', 'appVersion': '0',
          'buildNumber': '0', 'platform': 'unknown', 'schemaVersion': 1},
      ]);
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

    test('the copy (SA1–SA8)', () {
      expect(HomeV2Copy.smallActionNextDay('飲茶'), '聽日計劃：飲茶');
      expect(HomeV2Copy.smallActionMore, '仲有冇其他計劃？');
      expect(HomeV2Copy.smallActionOverflow(1), '仲有 1 個計劃');
      expect(HomeV2Copy.smallActionOverflow(3), '仲有 3 個計劃');
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

      testWidgets('1020n: the day a plan is made → 聽日計劃 + 仲有冇其他計劃？ '
          '(no 遲啲先); tap it → 今日小行動 → a second plan; the next day each '
          'plan 做咗 / 改日 on its own', (tester) async {
        final run = HomeRun(arm);
        // Made this morning (via 今日小行動): its day is tomorrow.
        run.smallActions.addPlan('p1',
            action: '同阿明去公園行下', createdAt: DateTime(2026, 10, 20, 9));
        await _pump(tester, run);
        expect(_nextOf('p1'), findsOneWidget);
        expect(find.text('聽日計劃：同阿明去公園行下'), findsOneWidget);
        expect(_more, findsOneWidget);
        expect(find.text(HomeV2Copy.smallActionMore), findsOneWidget);
        expect(_later, findsNothing, reason: 'no 遲啲先 in this state');
        expect(_ask, findsNothing);
        expect(_doneBtnOf('p1'), findsNothing, reason: 'no buttons today');
        expect(_postponeBtnOf('p1'), findsNothing);
        // 仲有冇其他計劃？ → 今日小行動, where the elder saves another plan.
        await _tap(tester, _more);
        expect(run.smallActionPageOpens, 1);
        expect(find.text('今日小行動 page'), findsOneWidget);
        run.smallActions.addPlan('p2',
            action: '打電話畀阿芳', createdAt: DateTime(2026, 10, 20, 9, 40));
        run.navKey.currentState!.pop();
        await settle(tester);
        expect(_nextOf('p1'), findsOneWidget);
        expect(_nextOf('p2'), findsOneWidget);
        expect(_more, findsOneWidget);
        expect(_overflow, findsNothing);
        expect(_top(_nextOf('p1')) < _top(_nextOf('p2')), isTrue);
        expect(_top(_nextOf('p2')) < _top(_more), isTrue);
        // The next day: one line each, each with its own buttons.
        await _toDay(tester, run, DateTime(2026, 10, 21, 9, 30));
        expect(_planOf('p1'), findsOneWidget);
        expect(_planOf('p2'), findsOneWidget);
        expect(find.text('今日計劃：同阿明去公園行下'), findsOneWidget);
        expect(find.text('今日計劃：打電話畀阿芳'), findsOneWidget);
        expect(_more, findsNothing);
        await _tap(tester, _doneBtnOf('p1'));
        expect(_doneOf('p1'), findsOneWidget, reason: 'p1 ticked');
        expect(_doneBtnOf('p2'), findsOneWidget, reason: 'p2 still asks');
        expect(_postponeBtnOf('p2'), findsOneWidget);
        await _tap(tester, _postponeBtnOf('p2'));
        expect(_planOf('p2'), findsNothing, reason: 'p2 folded for today');
        expect(_doneOf('p1'), findsOneWidget, reason: 'p1 tick stays');
        final d1 = run.smallActions.planDocs['p1']!;
        final d2 = run.smallActions.planDocs['p2']!;
        expect((d1['outcome'], d1['homeRowStatus'], d1['homeRowLaterCount']),
            ('happened', 'done', null));
        expect((d2['outcome'], d2['homeRowStatus'], d2['homeRowLaterCount'],
            d2['homeRowDueDate']), (null, 'later', 1, '2026-10-22'));
        expect(run.smallActions.remindersOf('p1'), isEmpty);
        expect(run.smallActions.remindersOf('p2').single['fireAt'],
            '2026-10-22T09:40:00.000');
        // Day after: only p2 (moved), its own second 改日 does not move it.
        await _toDay(tester, run, DateTime(2026, 10, 22, 9));
        expect(_planOf('p2'), findsOneWidget);
        expect(_planOf('p1'), findsNothing);
        expect(_doneOf('p1'), findsNothing);
        await _tap(tester, _postponeBtnOf('p2'));
        expect(run.smallActions.planDocs['p2']!['homeRowLaterCount'], 2);
        expect(run.smallActions.planDocs['p2']!['homeRowDueDate'],
            '2026-10-22');
        expect(_usageCodes(run), [
          'shown:next_day_plan:p1',
          'more',
          'shown:next_day_plan:p2',
          'shown:plan:p1',
          'shown:plan:p2',
          'done:p1',
          'shown:done:p1',
          'postpone:p2:moved=true',
          'shown:plan:p2',
          'postpone:p2:moved=false',
        ]);
      });

      testWidgets('1020n: three plans → two lines + 「仲有 1 個計劃」 → 我嘅計劃; '
          'the same the day they are made', (tester) async {
        final run = HomeRun(arm);
        for (final (i, id) in ['p1', 'p2', 'p3'].indexed) {
          _seedPlan(run, id, action: '計劃$id', hour: 9 + i);
        }
        await _pump(tester, run);
        expect(_planOf('p1'), findsOneWidget);
        expect(_planOf('p2'), findsOneWidget);
        expect(_planOf('p3'), findsNothing);
        expect(_overflow, findsOneWidget);
        expect(find.text('仲有 1 個計劃'), findsOneWidget);
        expect(_top(_planOf('p2')) < _top(_overflow), isTrue);
        await _tap(tester, _overflow);
        expect(run.myPlansPageOpens, 1);
        expect(find.text('我嘅計劃 page'), findsOneWidget);
        run.navKey.currentState!.pop();
        await settle(tester);
        // 改日 on p1 folds it away: p2 and p3 now fit, no 仲有 N 個計劃.
        await _tap(tester, _postponeBtnOf('p1'));
        expect(_planOf('p2'), findsOneWidget);
        expect(_planOf('p3'), findsOneWidget);
        expect(_overflow, findsNothing);
        expect(_usageCodes(run), [
          'shown:plan:p1',
          'shown:plan:p2',
          'list',
          'postpone:p1:moved=true',
          'shown:plan:p3',
        ]);
        // Made today: two 聽日計劃 lines, 仲有 1 個計劃, 仲有冇其他計劃？.
        final made = HomeRun(arm);
        for (final (i, id) in ['n1', 'n2', 'n3'].indexed) {
          made.smallActions.addPlan(id,
              action: '聽日$id', createdAt: DateTime(2026, 10, 20, 8, i));
        }
        await tester.pumpWidget(const SizedBox());
        HomeSmallActionRow.resetShownLog();
        await _pump(tester, made);
        expect(_nextOf('n1'), findsOneWidget);
        expect(_nextOf('n2'), findsOneWidget);
        expect(_nextOf('n3'), findsNothing);
        expect(find.text('仲有 1 個計劃'), findsOneWidget);
        expect(_more, findsOneWidget);
        expect(_top(_overflow) < _top(_more), isTrue);
        await _tap(tester, _overflow);
        expect(made.myPlansPageOpens, 1);
      });

      testWidgets('1020n: 仲有 N 個計劃 opens the real 我嘅計劃 page listing '
          'every plan', (tester) async {
        final run = HomeRun(arm);
        for (final (i, id) in ['p1', 'p2', 'p3', 'p4'].indexed) {
          _seedPlan(run, id, action: '計劃$id', hour: 9 + i);
        }
        await _pump(tester, run);
        expect(find.text('仲有 2 個計劃'), findsOneWidget);
        ActionPlanRepository.testOverride = _StoreRepo(run.smallActions);
        unawaited(run.navKey.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => const ActionLoopLandingPage())));
        await settle(tester);
        for (final id in ['p1', 'p2', 'p3', 'p4']) {
          expect(find.text('計劃$id'), findsOneWidget, reason: id);
        }
      });

      testWidgets('long plan text (30+ characters): two lines, then …, at '
          '1.30 on a 360-wide phone — 今日計劃 and 聽日計劃', (tester) async {
        final run = HomeRun(arm);
        const long = '星期六朝早同阿明、阿芳同埋舊同事一齊去公園行一個鐘，'
            '之後去茶樓飲早茶，再去街市買餸返屋企煮飯';
        _seedPlan(run, 'p1', action: long);
        await _pump(tester, run, size: const Size(360, 800), textScale: 1.30);
        final title = find.text('今日計劃：$long');
        expect(title, findsOneWidget);
        expect(long.length, greaterThan(30));
        _expectTwoLines(tester, title);
        // The buttons fit too.
        expect(_doneBtn, findsOneWidget);
        expect(_postponeBtn, findsOneWidget);
        // The day a plan is made: 聽日計劃, same rule.
        run.smallActions.addPlan('n1',
            action: long, createdAt: DateTime(2026, 10, 20, 9));
        run.smallActions.planDocs.remove('p1');
        run.smallActions.addPlan('n2', action: '飲茶',
            createdAt: DateTime(2026, 10, 20, 9, 5));
        await settle(tester);
        _expectTwoLines(tester, find.text('聽日計劃：$long'));
        expect(tester.takeException(), isNull);
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
