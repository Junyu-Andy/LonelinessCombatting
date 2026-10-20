/// 1020m 第二节 / 1020n 第三节 — page 1's small-action row in
/// 「今日要做嘅事」, after the check-in and questionnaire rows.  Part of the
/// page-1 layout (`homeLayoutV2Enabled`); no switch of its own — it
/// replaced batch 3's action-plan follow-up there.  Both arms identical; no
/// model call.  One line per plan ([HomeSmallAction.resolve]):
///
///   - No plan: SA1 「今日想做啲咩小行動？」 (撳: 今日小行動 =
///     [SocialSuggestionsPage], the 做啲嘢 page's first card) and SA2
///     「遲啲先」 on the right (folds away; hidden that day and the next
///     two, back on day 4 — a per-phone mark).
///   - Plans for today: one SA3 「今日計劃：{做咩}」 line each (at most two
///     lines of text, then 「…」) with SA4 「做咗」 (a tick for the rest of
///     the day) and SA5 「改日」 (that line folds away for the rest of the
///     day; the plan moves to tomorrow once).  Each plan counts on its own.
///   - The day a plan is made (its day is tomorrow): one SA6 「聽日計劃：
///     {做咩}」 line each, no buttons, then SA7 「仲有冇其他計劃？」 (撳:
///     今日小行動, to make another).  No 「遲啲先」.
///   - More than two plan lines: the first two, then SA8 「仲有 N 個計劃」
///     (撳: 我嘅計劃 = ActionLoopLandingPage).
///
/// What a plan's day is and what the buttons write: [HomeSmallAction]
/// (decision 0064).  Usage events: `home_small_action_*`
/// ([UsageEventRecorder.recordHomeSmallAction]).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/usage/usage_event_recorder.dart';
import '../../../../core/usage/usage_events_scope.dart';
import '../../../action_loop/data/action_plan.dart';
import '../../../action_loop/data/home_small_action.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/home_v2_copy.dart';
import '../../data/small_action_row_store.dart';
import '../home_v2_scope.dart';
import 'today_todo_rows.dart';

class HomeSmallActionRow extends StatefulWidget {
  const HomeSmallActionRow({super.key});

  /// Tests: forget which `home_small_action_shown` rows were written.
  @visibleForTesting
  static void resetShownLog() => _HomeSmallActionRowState._shownLogged.clear();

  /// Keys of one plan's widgets (tests, screenshots).
  static ValueKey<String> planKey(String id) =>
      ValueKey('today_todo_small_action_plan_$id');
  static ValueKey<String> doneKey(String id) =>
      ValueKey('today_todo_small_action_done_$id');
  static ValueKey<String> nextDayKey(String id) =>
      ValueKey('today_todo_small_action_next_$id');
  static ValueKey<String> doneButtonKey(String id) =>
      ValueKey('today_todo_small_action_done_button_$id');
  static ValueKey<String> postponeButtonKey(String id) =>
      ValueKey('today_todo_small_action_postpone_button_$id');
  static const askKey = ValueKey('today_todo_small_action_ask');
  static const laterKey = ValueKey('today_todo_small_action_later');
  static const moreKey = ValueKey('today_todo_small_action_more');
  static const overflowKey = ValueKey('today_todo_small_action_overflow');

  /// Plan texts: at most this many lines, then 「…」 (1020n 第五节).
  static const int planTitleMaxLines = 2;

  @override
  State<HomeSmallActionRow> createState() => _HomeSmallActionRowState();
}

/// 「做咗」「改日」: big enough for the elder (as the Brief PR card's
/// buttons); the font family comes from the button theme.
const _buttonText = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

class _HomeSmallActionRowState extends State<HomeSmallActionRow>
    with WidgetsBindingObserver {
  /// `home_small_action_shown` once per account, day, row state and plan
  /// while the App is running (a restart may record it again).
  static final Set<String> _shownLogged = {};

  SmallActionRowStore? _store;
  StreamSubscription<List<ActionPlan>>? _sub;
  String? _uid;
  List<ActionPlan> _plans = const [];
  bool _plansLoaded = false;
  String? _laterMark;
  bool _markLoaded = false;

  /// Plans whose 做咗 / 改日 is on its way: their buttons wait for the
  /// plans to change.
  final Set<String> _busy = {};
  Timer? _busyTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeV2Refresh.changes.addListener(_readMark);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store ??= HomeV2Scope.maybeOf(context)?.smallActionStore ??
        DefaultSmallActionRowStore(
            available: AuthServiceScope.of(context).available);
    final uid = AppSettingsScope.of(context).profile?.uid;
    if (uid != _uid) {
      _uid = uid;
      _subscribe();
      unawaited(_readMark());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _busyTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    HomeV2Refresh.changes.removeListener(_readMark);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back the next day: today's lines are worked out again in build.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      unawaited(_readMark());
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = null;
    _plans = const [];
    _plansLoaded = false;
    final uid = _uid;
    final store = _store;
    if (uid == null || store == null) return;
    void loaded(List<ActionPlan> list) {
      if (!mounted) return;
      _busyTimer?.cancel();
      setState(() {
        _plans = list;
        _plansLoaded = true;
        _busy.clear();
      });
    }

    _sub = store.plans(uid).listen(
          loaded,
          onError: (Object _) {
            if (mounted) setState(() => _plansLoaded = true);
          },
          // No Firebase (guest mode, tests): an empty stream.
          onDone: () {
            if (mounted && !_plansLoaded) setState(() => _plansLoaded = true);
          },
        );
  }

  Future<void> _readMark() async {
    final store = _store;
    if (store == null) return;
    String? mark;
    try {
      mark = await store.readLaterMark();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _laterMark = mark;
      _markLoaded = true;
    });
  }

  DateTime _now() => HomeV2Scope.now(context);

  UsageEventRecorder? get _usage => UsageEventsScope.maybeOf(context);

  void _logShown(String uid, HomeSmallActionState s, DateTime now) {
    final day = HomeSmallAction.dayOf(now);
    final usage = _usage;
    for (final line in s.lines) {
      final rowState = line.rowState;
      if (rowState == null) continue;
      final planId = line.plan?.id;
      if (!_shownLogged.add('$uid|$day|$rowState|${planId ?? ''}')) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        usage?.recordHomeSmallAction(UsageEventType.homeSmallActionShown,
            rowState: rowState, planId: planId);
      });
    }
  }

  void _setBusy(String planId) {
    _busy.add(planId);
    _busyTimer?.cancel();
    _busyTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _busy.isNotEmpty) setState(_busy.clear);
    });
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _push(WidgetBuilder builder) async {
    await HomeSurfaceScope.push(
        context, MaterialPageRoute<void>(builder: builder));
    HomeV2Refresh.bump();
  }

  /// 「今日想做啲咩小行動？」 → 今日小行動.
  Future<void> _open() async {
    _usage?.recordHomeSmallAction(UsageEventType.homeSmallActionOpen);
    await _push(HomeV2Scope.buildSmallActionPage);
  }

  /// 「仲有冇其他計劃？」 → 今日小行動 (make another plan).
  Future<void> _more() async {
    _usage?.recordHomeSmallAction(UsageEventType.homeSmallActionMore);
    await _push(HomeV2Scope.buildSmallActionPage);
  }

  /// 「仲有 N 個計劃」 → 我嘅計劃.
  Future<void> _list() async {
    _usage?.recordHomeSmallAction(UsageEventType.homeSmallActionList);
    await _push(HomeV2Scope.buildMyPlansPage);
  }

  void _later() {
    final today = HomeSmallAction.dayOf(_now());
    _usage?.recordHomeSmallAction(UsageEventType.homeSmallActionLater);
    setState(() => _laterMark = today);
    final store = _store;
    if (store != null) {
      unawaited(() async {
        try {
          await store.writeLaterMark(today);
        } catch (_) {}
      }());
    }
  }

  void _done(ActionPlan plan) {
    final uid = _uid;
    final store = _store;
    final id = plan.id;
    if (uid == null || store == null || id == null || _busy.contains(id)) {
      return;
    }
    _usage?.recordHomeSmallAction(UsageEventType.homeSmallActionDone,
        planId: id);
    setState(() => _setBusy(id));
    final now = _now();
    // Fire-and-forget: offline, the write completes only on server ack;
    // the plans stream already shows it (Firestore's local view).
    unawaited(() async {
      try {
        await store.markDone(uid, plan, now);
      } catch (_) {}
    }());
  }

  void _postpone(ActionPlan plan) {
    final uid = _uid;
    final store = _store;
    final id = plan.id;
    if (uid == null || store == null || id == null || _busy.contains(id)) {
      return;
    }
    final now = _now();
    _usage?.recordHomeSmallAction(UsageEventType.homeSmallActionPostpone,
        planId: id, moved: HomeSmallAction.postpone(plan, now).moved);
    setState(() => _setBusy(id));
    unawaited(() async {
      try {
        await store.postpone(uid, plan, now);
      } catch (_) {}
    }());
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    var lines = const <HomeSmallActionLine>[];
    if (uid != null && _plansLoaded && _markLoaded) {
      final now = _now();
      final state =
          HomeSmallAction.resolve(_plans, now, laterMark: _laterMark);
      _logShown(uid, state, now);
      lines = state.lines;
    }
    // 遲啲先 / 改日: the line folds away.
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final l in lines) _line(l)],
      ),
    );
  }

  Widget _line(HomeSmallActionLine l) => switch (l.kind) {
        HomeSmallActionLineKind.ask => _askRow(),
        HomeSmallActionLineKind.plan => _planRow(l.plan!, done: false),
        HomeSmallActionLineKind.done => _planRow(l.plan!, done: true),
        HomeSmallActionLineKind.nextDayPlan => _nextDayRow(l.plan!),
        HomeSmallActionLineKind.more => TodoRowTile(
            key: HomeSmallActionRow.moreKey,
            leading: Icons.add_circle_outline_rounded,
            title: HomeV2Copy.smallActionMore,
            onTap: _more,
          ),
        HomeSmallActionLineKind.overflow => TodoRowTile(
            key: HomeSmallActionRow.overflowKey,
            leading: Icons.format_list_bulleted_rounded,
            title: HomeV2Copy.smallActionOverflow(l.count),
            onTap: _list,
          ),
      };

  static String _action(ActionPlan plan) =>
      plan.action.trim().isEmpty ? '小行動' : plan.action.trim();

  Widget _askRow() {
    final theme = Theme.of(context);
    return TodoRowTile(
      key: HomeSmallActionRow.askKey,
      leading: Icons.emoji_people_rounded,
      title: HomeV2Copy.smallActionAsk,
      onTap: _open,
      trailing: TextButton(
        key: HomeSmallActionRow.laterKey,
        onPressed: _later,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: theme.colorScheme.onSecondaryContainer,
        ),
        child: const Text(
          HomeV2Copy.smallActionLater,
          style: TextStyle(fontSize: 15, decoration: TextDecoration.underline),
        ),
      ),
    );
  }

  Widget _nextDayRow(ActionPlan plan) => TodoRowTile(
        key: HomeSmallActionRow.nextDayKey(plan.id ?? ''),
        leading: Icons.event_outlined,
        title: HomeV2Copy.smallActionNextDay(_action(plan)),
        titleMaxLines: HomeSmallActionRow.planTitleMaxLines,
      );

  Widget _planRow(ActionPlan plan, {required bool done}) {
    final id = plan.id ?? '';
    final busy = _busy.contains(id);
    return TodoRowTile(
      key: done
          ? HomeSmallActionRow.doneKey(id)
          : HomeSmallActionRow.planKey(id),
      leading: done
          ? Icons.check_circle_rounded
          : Icons.radio_button_unchecked_rounded,
      title: HomeV2Copy.smallActionPlan(_action(plan)),
      titleMaxLines: HomeSmallActionRow.planTitleMaxLines,
      done: done,
      footer: done
          ? null
          : Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: HomeSmallActionRow.doneButtonKey(id),
                    onPressed: busy ? null : () => _done(plan),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 24),
                    label: const Text(HomeV2Copy.smallActionDone,
                        style: _buttonText),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: HomeSmallActionRow.postponeButtonKey(id),
                    onPressed: busy ? null : () => _postpone(plan),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.event_repeat_rounded, size: 24),
                    label: const Text(HomeV2Copy.smallActionPostpone,
                        style: _buttonText),
                  ),
                ),
              ],
            ),
    );
  }
}
