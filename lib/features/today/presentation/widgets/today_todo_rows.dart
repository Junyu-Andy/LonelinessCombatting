/// 1020 D (3), (4) and G (2) — page 1's 「今日要做嘅事」 rows and the
/// 「去搵人傾」 button (`homeLayoutV2Enabled`).  Both arms identical.
///
///   (a) [CheckInTodoRow]   — every day; opens 小欣 and starts today's
///       check-in; a tick when done (still opens 小欣's chat, 1020e 一.(6));
///       after 3 days without one the old 「幾日冇見你」 banner's words sit
///       under it (no separate banner).
///   (b) Brief PR invitation — the existing BriefPrCardHost (TodayPage).
///   (c) [QuestionnaireTodoRow] — W5 while a weekly questionnaire is open
///       (請盡快回答 / 聽日截止 / 今晚截止; week 4 記得喺見面之前答埋佢 —
///       1020e), else W4 (the next opening day by study week).  1020l §二
///       (1): two lines like the check-in row — a title, then a small
///       line with the deadline day (W5-2) or the opening day (W4).
///   (d) 1020m 第二节: the small-action row ([HomeSmallActionRow],
///       home_small_action_row.dart) — 「今日想做啲咩小行動？」 / 「今日計劃：
///       {…}」 with 「做咗」「改日」.  It replaced batch 3's action-plan
///       follow-up here (the old ActivePlanBanner, which stays only in the
///       old one-page layout).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../app/home_tab_switcher.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/config/phase_b_config.dart';
import '../../../../core/scheduling/w0_date.dart';
import '../../../../core/scheduling/weekly_schedule.dart';
import '../../../../core/time/app_clock.dart';
import '../../../adherence/data/adherence_check.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../auth/data/user_profile.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../brief_pr/data/brief_pr_v2.dart';
import '../../../weekly_bundle/data/weekly_bundle.dart';
import '../../../weekly_bundle/presentation/weekly_bundle_flow_page.dart';
import '../../data/home_v2_copy.dart';
import '../home_v2_scope.dart';

/// D1 「今日要做嘅事」.
class TodoSectionTitle extends StatelessWidget {
  const TodoSectionTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
      child: Text(
        HomeV2Copy.todoTitle,
        key: const ValueKey('today_todo_title'),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// One to-do line: a state icon, the words, a chevron when it opens
/// something.  ≥ 60 px tall.
class TodoRowTile extends StatelessWidget {
  const TodoRowTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.onTap,
    this.done = false,
    this.trailing,
    this.footer,
    this.titleMaxLines,
  });

  final IconData leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool done;

  /// 1020m: in place of the chevron (the 「遲啲先」 text button).
  final Widget? trailing;

  /// 1020m: full width under the title line (「做咗」「改日」).
  final Widget? footer;

  /// 1020m: 1 = one line ending in 「…」 (a plan's text); null = wraps.
  final int? titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = done
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSecondaryContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Material(
        color: done
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: _withFooter(Row(
                children: [
                  Icon(leading,
                      size: 26,
                      color: done ? theme.colorScheme.primary : fg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: titleMaxLines,
                          overflow: titleMaxLines == null
                              ? null
                              : TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: fg,
                            height: 1.3,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: fg,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null)
                    trailing!
                  else if (onTap != null)
                    Icon(Icons.chevron_right_rounded, size: 28, color: fg),
                ],
              )),
            ),
          ),
        ),
      ),
    );
  }

  Widget _withFooter(Widget row) {
    final f = footer;
    if (f == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [row, const SizedBox(height: 10), f],
    );
  }
}

// ---------------------------------------------------------------------------
// (a) check-in
// ---------------------------------------------------------------------------

class CheckInTodoRow extends StatefulWidget {
  const CheckInTodoRow({super.key});

  @override
  State<CheckInTodoRow> createState() => _CheckInTodoRowState();
}

class _CheckInTodoRowState extends State<CheckInTodoRow>
    with WidgetsBindingObserver {
  bool _done = false;
  int? _daysSince;
  bool _started = false;

  /// While not done, re-read every 30 s (a check-in from page 2 flips the
  /// tick without a restart), as the old status chip.
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeV2Refresh.changes.addListener(_load);
    BriefPrV2.changes.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_load());
      _poll = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_done) unawaited(_load());
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    HomeV2Refresh.changes.removeListener(_load);
    BriefPrV2.changes.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final uid = AppSettingsScope.read(context).profile?.uid;
    if (uid == null) return;
    final scope = HomeV2Scope.maybeOf(context);
    final check =
        AdherenceCheck(available: AuthServiceScope.of(context).available);
    var done = false;
    int? days;
    try {
      done = await (scope?.checkedInToday ?? check.hasCheckedInToday)(uid);
    } catch (_) {}
    try {
      days = await (scope?.daysSinceLastCheckIn ?? check.daysSinceLastCheckIn)(
          uid);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _done = done;
      _daysSince = days;
    });
  }

  Future<void> _open() async {
    await HomeSurfaceScope.push(
        context,
        MaterialPageRoute<void>(
          builder: (ctx) => HomeV2Scope.buildCheckIn(ctx),
        ));
    HomeV2Refresh.bump();
  }

  @override
  Widget build(BuildContext context) {
    final missed = !_done &&
        _daysSince != null &&
        _daysSince! >= AdherenceCheck.bannerThresholdDays;
    return TodoRowTile(
      key: const ValueKey('today_todo_check_in'),
      leading: _done
          ? Icons.check_circle_rounded
          : Icons.radio_button_unchecked_rounded,
      title: HomeV2Copy.checkInRow,
      subtitle: missed ? HomeV2Copy.checkInMissed : null,
      done: _done,
      // 1020e 一.(6): still tappable when done — 小欣's chat then opens
      // with SY0 (rule arm) or the LLM opener (batch 2's done-today path).
      onTap: _open,
    );
  }
}

// ---------------------------------------------------------------------------
// (c) weekly questionnaire — G (2)
// ---------------------------------------------------------------------------

/// How an open questionnaire is worded (1020e 二.1 (5), 二.2 (4)).
enum QuestionnaireOpenState {
  /// W5a 請盡快回答 — the window's first day (and any day before the day
  /// before the last).
  asap,

  /// W5b 聽日截止 — the day before the window's last day.
  tomorrow,

  /// W5c 今晚截止 — the window's last day.
  tonight,

  /// W5d 記得喺見面之前答埋佢 — week 4 (closes after the W4 visit).
  beforeVisit,
}

/// What the questionnaire row shows: W5 for an open bundle not yet done
/// ([due] set), else W4 for the next opening ([opensOn]).
class QuestionnaireRowInfo {
  const QuestionnaireRowInfo.open(
      WeeklyBundleDue this.due, QuestionnaireOpenState this.state)
      : opensOn = null;
  const QuestionnaireRowInfo.upcoming(DateTime this.opensOn)
      : due = null,
        state = null;

  final WeeklyBundleDue? due;
  final QuestionnaireOpenState? state;
  final DateTime? opensOn;

  bool get isOpen => due != null;

  /// The whole sentence (W4 / W5), as in the spec.
  String get text => switch (state) {
        null => HomeV2Copy.w4(opensOn!),
        QuestionnaireOpenState.asap => HomeV2Copy.w5(HomeV2Copy.w5Asap),
        QuestionnaireOpenState.tomorrow =>
          HomeV2Copy.w5(HomeV2Copy.w5Tomorrow),
        QuestionnaireOpenState.tonight => HomeV2Copy.w5(HomeV2Copy.w5Tonight),
        QuestionnaireOpenState.beforeVisit =>
          HomeV2Copy.w5(HomeV2Copy.w5BeforeVisit),
      };

  /// 1020l §二 (1) — the row's title line: W5 without its full stop (a
  /// title, like 「同小欣 check-in」; it then fits one line on a 360-wide
  /// phone at the standard size); W4 up to its colon (`下次問卷`).
  String get title {
    if (state == null) return HomeV2Copy.w4Title;
    final t = text;
    return t.endsWith('。') ? t.substring(0, t.length - 1) : t;
  }

  /// 1020l §二 (1) — the small second line: W4 after its colon (the opening
  /// day …); W5-2 (the window's last day) while open in weeks 1–3 / 5–7;
  /// none in week 4 (closes after the visit, no date to give).
  String? get subtitle {
    final s = state;
    if (s == null) return HomeV2Copy.w4Subtitle(opensOn!);
    if (s == QuestionnaireOpenState.beforeVisit) return null;
    return HomeV2Copy.w5Deadline(lastDay(due!.window));
  }

  /// The calendar day of the window's last instant (a window ending at
  /// 00:00 ends the day before).
  static DateTime lastDay(WeeklyWindow window) {
    final last = window.close.subtract(const Duration(microseconds: 1));
    return DateTime(last.year, last.month, last.day);
  }

  /// From the window the App's schedule gives (no day numbers here, so a
  /// moved window — batch 4's day 7 00:00 – day 9 23:59, the week-4 close
  /// at the W4 visit — words itself): week 4 → [beforeVisit]; else by the
  /// calendar day of the window's last instant: that day → [tonight], the
  /// day before → [tomorrow], earlier → [asap].
  static QuestionnaireOpenState openState(
      WeeklyBundle bundle, WeeklyWindow window, DateTime now) {
    if (bundle.closeRule == WeeklyCloseRule.week4) {
      return QuestionnaireOpenState.beforeVisit;
    }
    final last = window.close.subtract(const Duration(microseconds: 1));
    final lastDay = DateTime.utc(last.year, last.month, last.day);
    final today = DateTime.utc(now.year, now.month, now.day);
    final daysToLast = lastDay.difference(today).inDays;
    if (daysToLast <= 0) return QuestionnaireOpenState.tonight;
    if (daysToLast == 1) return QuestionnaireOpenState.tomorrow;
    return QuestionnaireOpenState.asap;
  }

  /// The first bundle whose window opens after [now], or null (after W7).
  static WeeklyBundle? nextBundle(
      PhaseBConfig cfg, WeeklyScheduleMode mode, DateTime w0, DateTime now) {
    for (final b in WeeklySchedule.bundlesFor(cfg, mode)) {
      if (WeeklySchedule.windowFor(b, w0, cfg).open.isAfter(now)) return b;
    }
    return null;
  }

  /// W5 for the first open bundle not yet all done, else W4 for the next
  /// one, else null (nothing left: the row hides).  1020g 一 (7): the W4
  /// window closes on the day its visit was recorded ([week4RecordedOn],
  /// `w4RecordedOnFor`), and with v2 it can overlap W5 / W6, so every open
  /// bundle is checked in push order (as PendingPromptsService
  /// .weeklyBundleDue) — a finished W4 no longer hides an open W5.
  static Future<QuestionnaireRowInfo?> resolve({
    required PhaseBConfig cfg,
    required WeeklyScheduleMode mode,
    required DateTime w0,
    required DateTime now,
    required WeeklyBundleStore? store,
    DateTime? week4RecordedOn,
  }) async {
    final open = WeeklySchedule.openBundlesAt(cfg, mode, w0, now,
        week4RecordedOn: week4RecordedOn);
    for (final o in open) {
      Map<WeeklyPart, String?> status = {
        for (final p in o.bundle.parts) p: null,
      };
      if (store != null) {
        try {
          status = await store.partStatus(o.bundle);
        } catch (_) {}
      }
      final due =
          WeeklyBundleDue(bundle: o.bundle, window: o.window, status: status);
      if (!due.allDone) {
        return QuestionnaireRowInfo.open(
            due, openState(o.bundle, o.window, now));
      }
    }
    final next = nextBundle(cfg, mode, w0, now);
    if (next == null) return null;
    final opens = WeeklySchedule.windowFor(next, w0, cfg).open;
    return QuestionnaireRowInfo.upcoming(
        DateTime(opens.year, opens.month, opens.day));
  }
}

class QuestionnaireTodoRow extends StatefulWidget {
  const QuestionnaireTodoRow({super.key});

  /// Shown only where the study-week schedule runs (T24 switch
  /// `weeklyScheduleV2Enabled`, Phase B build, a registered cohort);
  /// otherwise the old PendingPromptsBanner handles the questionnaires.
  static bool activeFor(UserProfile? profile) => WeeklyBundleGate.active(profile);

  @override
  State<QuestionnaireTodoRow> createState() => _QuestionnaireTodoRowState();
}

class _QuestionnaireTodoRowState extends State<QuestionnaireTodoRow>
    with WidgetsBindingObserver {
  QuestionnaireRowInfo? _info;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeV2Refresh.changes.addListener(_load);
    // Testers' schedule simulation (測試員工具 → 日程模擬) moves this row
    // like the old questionnaire card.
    AppClock.instance.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HomeV2Refresh.changes.removeListener(_load);
    AppClock.instance.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  WeeklyBundleStore? _store(String uid) {
    final custom = HomeV2Scope.maybeOf(context)?.weeklyStore;
    if (custom != null) return custom(uid);
    if (!AuthServiceScope.of(context).available) return null;
    return FirestoreWeeklyBundleStore(uid);
  }

  Future<void> _load() async {
    if (!mounted) return;
    final profile = AppSettingsScope.read(context).profile;
    final mode = WeeklySchedule.modeForCohort(profile?.cohort);
    final w0 = w0DateFor(profile);
    if (profile == null || mode == null || w0 == null) {
      if (_info != null) setState(() => _info = null);
      return;
    }
    final info = await QuestionnaireRowInfo.resolve(
      cfg: PhaseBConfig.current,
      mode: mode,
      w0: w0,
      // A scheduling decision: the (possibly simulated) App clock.
      now: HomeV2Scope.maybeOf(context)?.clock?.call() ?? AppClock.now(),
      store: _store(profile.uid),
      week4RecordedOn: w4RecordedOnFor(profile),
    );
    if (mounted) setState(() => _info = info);
  }

  Future<void> _open(WeeklyBundleDue due) async {
    final profile = AppSettingsScope.read(context).profile;
    final mode = WeeklySchedule.modeForCohort(profile?.cohort);
    final w0 = w0DateFor(profile);
    if (profile == null || mode == null || w0 == null) return;
    // As the old card (PendingPromptsBanner._openWeeklyBundle).
    unawaited(AnalyticsScope.of(context)
        .logEvent('weekly_bundle_opened', {'bundle': due.bundle.id}));
    await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => WeeklyBundleFlowPage.forUser(
        uid: profile.uid,
        arm: Arm.of(context)?.code ?? profile.arm?.code ?? 'A',
        bundle: due.bundle,
        referentRange: WeeklySchedule.referentRangeFor(
            due.bundle, w0, PhaseBConfig.current, mode),
        initialStatus: due.status,
      ),
    ));
    HomeV2Refresh.bump();
  }

  /// 1020l §二 (1): the same tile as the check-in row — a title line and a
  /// small second line (the deadline day, or the opening day), the arrow
  /// only when it opens the questionnaire.  Tapping is unchanged: open →
  /// the questionnaire; not yet open → nothing.
  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final due = info.due;
    return TodoRowTile(
      key: ValueKey(info.isOpen
          ? 'today_todo_questionnaire_open'
          : 'today_todo_questionnaire_next'),
      leading: info.isOpen
          ? Icons.assignment_outlined
          : Icons.event_available_outlined,
      title: info.title,
      subtitle: info.subtitle,
      onTap: due == null ? null : () => _open(due),
    );
  }
}

// ---------------------------------------------------------------------------
// (4) 「去搵人傾」
// ---------------------------------------------------------------------------

class GoTalkButton extends StatelessWidget {
  const GoTalkButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: FilledButton.icon(
        key: const ValueKey('today_go_talk'),
        onPressed: () => HomeTabSwitcher.maybeOf(context)?.goToTalk(),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 64),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        icon: const Icon(Icons.forum_rounded, size: 28),
        label: const Text(
          HomeV2Copy.goTalk,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
