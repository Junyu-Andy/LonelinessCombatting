/// 1020 D (3), (4) and G (2) — page 1's 「今日要做嘅事」 rows and the
/// 「去搵人傾」 button (`homeLayoutV2Enabled`).  Both arms identical.
///
///   (a) [CheckInTodoRow]   — every day; opens 小欣 and starts today's
///       check-in; a tick when done; after 3 days without one the old
///       「幾日冇見你」 banner's words sit under it (no separate banner).
///   (b) Brief PR invitation — the existing BriefPrCardHost (TodayPage).
///   (c) [QuestionnaireTodoRow] — W5 while a weekly questionnaire is open
///       (days left), else W4 (the next opening day by study week).
///   (d) the action-plan follow-up — the existing ActivePlanBanner.
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
  });

  final IconData leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool done;

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
              child: Row(
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
                  if (onTap != null)
                    Icon(Icons.chevron_right_rounded, size: 28, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
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
    await Navigator.of(context).push(MaterialPageRoute<void>(
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
      onTap: _done ? null : _open,
    );
  }
}

// ---------------------------------------------------------------------------
// (c) weekly questionnaire — G (2)
// ---------------------------------------------------------------------------

/// What the questionnaire row shows: W5 for an open bundle not yet done
/// ([due] set), else W4 for the next opening ([opensOn]).
class QuestionnaireRowInfo {
  const QuestionnaireRowInfo.open(WeeklyBundleDue this.due, int this.daysLeft)
      : opensOn = null;
  const QuestionnaireRowInfo.upcoming(DateTime this.opensOn)
      : due = null,
        daysLeft = null;

  final WeeklyBundleDue? due;
  final int? daysLeft;
  final DateTime? opensOn;

  bool get isOpen => due != null;

  String get text => isOpen ? HomeV2Copy.w5(daysLeft!) : HomeV2Copy.w4(opensOn!);

  /// Whole days (24 h) still left in [window] at [now], at least 1 while
  /// open: 20:00 on the opening day → 3 for a 3-day window, the last
  /// morning → 1.
  static int daysLeftIn(WeeklyWindow window, DateTime now) {
    final minutes = window.close.difference(now).inMinutes;
    final days = (minutes / (24 * 60)).ceil();
    return days < 1 ? 1 : days;
  }

  /// The first bundle whose window opens after [now], or null (after W7).
  static WeeklyBundle? nextBundle(
      PhaseBConfig cfg, WeeklyScheduleMode mode, DateTime w0, DateTime now) {
    for (final b in WeeklySchedule.bundlesFor(cfg, mode)) {
      if (WeeklySchedule.windowFor(b, w0, cfg).open.isAfter(now)) return b;
    }
    return null;
  }

  /// W5 when a bundle is open and not all done, else W4 for the next one,
  /// else null (nothing left: the row hides).
  static Future<QuestionnaireRowInfo?> resolve({
    required PhaseBConfig cfg,
    required WeeklyScheduleMode mode,
    required DateTime w0,
    required DateTime now,
    required WeeklyBundleStore? store,
  }) async {
    final open = WeeklySchedule.openBundleAt(cfg, mode, w0, now);
    if (open != null) {
      Map<WeeklyPart, String?> status = {
        for (final p in open.bundle.parts) p: null,
      };
      if (store != null) {
        try {
          status = await store.partStatus(open.bundle);
        } catch (_) {}
      }
      final due = WeeklyBundleDue(
          bundle: open.bundle, window: open.window, status: status);
      if (!due.allDone) {
        return QuestionnaireRowInfo.open(due, daysLeftIn(open.window, now));
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
      title: info.text,
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
