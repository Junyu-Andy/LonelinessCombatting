import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../action_loop/data/action_plan.dart';
import '../../../action_loop/presentation/pages/action_loop_followup_page.dart';
import '../../../action_loop/presentation/pages/action_loop_landing.dart';
import '../../../auth/presentation/auth_service_scope.dart';

/// Today's active M7 plan banner. Surfaces the next pending plan scheduled
/// for today (or, if none scheduled today, the oldest pending plan whose
/// scheduledFor has already passed and still has no outcome).
///
/// Tap → follow-up page (if its time has passed) or landing page (if still
/// upcoming). Renders nothing when there's no plan to surface — Today
/// should stay calm.
class ActivePlanBanner extends StatelessWidget {
  const ActivePlanBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppSettingsScope.of(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null || !auth.available) {
      return const SizedBox.shrink();
    }
    final repo = ActionPlanRepository(available: auth.available);
    return StreamBuilder<List<ActionPlan>>(
      stream: repo.pending(profile.uid),
      builder: (context, snap) {
        final plan = _pickPlanForToday(snap.data);
        if (plan == null) return const SizedBox.shrink();
        return _Banner(plan: plan);
      },
    );
  }

  /// Pick the plan to surface, in priority order:
  ///   1. A pending plan whose scheduledFor is today and still upcoming.
  ///   2. A pending plan whose scheduledFor was today but already passed
  ///      (overdue same-day → show follow-up nudge).
  ///   3. The oldest pending plan that's overdue from a previous day.
  /// Returns null otherwise — banner hides.
  static ActionPlan? _pickPlanForToday(List<ActionPlan>? plans) {
    if (plans == null || plans.isEmpty) return null;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    ActionPlan? upcomingToday;
    ActionPlan? earlierToday;
    ActionPlan? oldestOverdue;
    for (final p in plans) {
      final s = p.scheduledFor;
      if (s == null) continue;
      if (!s.isBefore(todayStart) && s.isBefore(tomorrowStart)) {
        if (!s.isBefore(now)) {
          upcomingToday ??= p;
        } else {
          earlierToday ??= p;
        }
      } else if (s.isBefore(todayStart)) {
        oldestOverdue ??= p;
      }
    }
    return upcomingToday ?? earlierToday ?? oldestOverdue;
  }
}

class _Banner extends StatelessWidget {
  final ActionPlan plan;
  const _Banner({required this.plan});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final scheduled = plan.scheduledFor;
    final now = DateTime.now();
    final isOverdue = scheduled != null && scheduled.isBefore(now);

    final timeLabel = scheduled == null
        ? plan.whenText
        : '${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}';
    final action = plan.action.isNotEmpty
        ? plan.action
        : (isEn ? 'Plan' : '小行動');
    final summary = isEn ? '$timeLabel · $action' : '$timeLabel　$action';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Card(
        color: isOverdue
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.secondaryContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _open(context, isOverdue),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  isOverdue
                      ? Icons.history_toggle_off_rounded
                      : Icons.checklist_rtl_outlined,
                  size: 30,
                  color: isOverdue
                      ? theme.colorScheme.onTertiaryContainer
                      : theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOverdue
                            ? (isEn ? 'How did it go?' : '件事點呀？')
                            : l10n.todayActivePlanLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isOverdue
                              ? theme.colorScheme.onTertiaryContainer
                              : theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: isOverdue
                              ? theme.colorScheme.onTertiaryContainer
                              : theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 28,
                    color: isOverdue
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, bool isOverdue) {
    if (isOverdue) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ActionLoopFollowUpPage(plan: plan),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ActionLoopLandingPage(),
        ),
      );
    }
  }
}
