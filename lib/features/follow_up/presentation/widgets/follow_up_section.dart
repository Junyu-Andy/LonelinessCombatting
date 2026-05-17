import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../action_loop/data/action_plan.dart';
import '../../../action_loop/presentation/pages/action_loop_landing.dart';
import '../../../auth/presentation/auth_service_scope.dart';

enum FollowUpPace { daily, everyOther, weekly }

/// Personalisation hub section: upcoming reminders, weekly progress,
/// reminder pace, and celebrations.
///
/// Real-data only. When the participant has not yet generated data
/// (e.g. immediately after sign-up, or in guest mode), each subsection
/// shows an empty-state card instead of fabricated demo content.
class FollowUpSection extends StatefulWidget {
  /// Whether to show a leading section heading. The personalisation page
  /// already labels this section, so it sets [withHeader] = false.
  final bool withHeader;

  const FollowUpSection({super.key, this.withHeader = true});

  @override
  State<FollowUpSection> createState() => _FollowUpSectionState();
}

class _FollowUpSectionState extends State<FollowUpSection> {
  FollowUpPace _pace = FollowUpPace.everyOther;

  @override
  Widget build(BuildContext context) {
    final profile = AppSettingsScope.of(context).profile;
    final auth = AuthServiceScope.of(context);
    final hasBackend = profile != null && auth.available;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.withHeader)
          const _SectionHeader(
              icon: Icons.alarm_outlined, title: '即將到嘅提醒'),
        if (widget.withHeader) const SizedBox(height: 14),
        if (!hasBackend)
          const _EmptyCard(
            icon: Icons.alarm_outlined,
            message: '登入並建立小行動之後，呢度會列出未到嘅提醒。',
          )
        else
          _UpcomingRemindersList(uid: profile.uid, available: auth.available),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ActionLoopLandingPage(),
              ),
            ),
            icon: const Icon(Icons.add_rounded, size: 24),
            label: const Text('加多一個提醒'),
          ),
        ),
        const SizedBox(height: 24),
        const _SectionHeader(
            icon: Icons.insights_outlined, title: '今個星期嘅進度'),
        const SizedBox(height: 12),
        const _EmptyCard(
          icon: Icons.insights_outlined,
          message: '完成第一次 check-in 之後，呢度會總結今個星期嘅進度。',
        ),
        const SizedBox(height: 24),
        const _SectionHeader(icon: Icons.tune_outlined, title: '節奏調整'),
        const SizedBox(height: 12),
        _PaceCard(
          pace: _pace,
          onChanged: (value) => setState(() => _pace = value),
        ),
        const SizedBox(height: 24),
        const _SectionHeader(
            icon: Icons.celebration_outlined, title: '小成就'),
        const SizedBox(height: 12),
        const _EmptyCard(
          icon: Icons.celebration_outlined,
          message: '完成 check-in 或者小行動之後，呢度會顯示你嘅小成就。',
        ),
      ],
    );
  }
}

class _UpcomingRemindersList extends StatelessWidget {
  final String uid;
  final bool available;

  const _UpcomingRemindersList({required this.uid, required this.available});

  @override
  Widget build(BuildContext context) {
    final repo = ActionPlanRepository(available: available);
    return StreamBuilder<List<ActionPlan>>(
      stream: repo.pending(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const _EmptyCard(
            icon: Icons.alarm_outlined,
            message: '載入緊…',
          );
        }
        final now = DateTime.now();
        final upcoming = (snap.data ?? const <ActionPlan>[])
            .where((p) =>
                p.scheduledFor != null && p.scheduledFor!.isAfter(now))
            .toList()
          ..sort((a, b) => a.scheduledFor!.compareTo(b.scheduledFor!));
        if (upcoming.isEmpty) {
          return const _EmptyCard(
            icon: Icons.alarm_outlined,
            message: '暫時未有即將到嘅提醒。',
          );
        }
        return Column(
          children: upcoming
              .map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PlanReminderCard(plan: p),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _PlanReminderCard extends StatelessWidget {
  final ActionPlan plan;

  const _PlanReminderCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheduled = plan.scheduledFor!;
    final whenLabel = _formatWhen(scheduled);
    final title = plan.action.isNotEmpty ? plan.action : '小行動';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.alarm_outlined,
                  size: 28, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    whenLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatWhen(DateTime when) {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    return '${weekdays[when.weekday - 1]}　$hh:$mm';
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 26, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 26, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
      ],
    );
  }
}

class _PaceCard extends StatelessWidget {
  final FollowUpPace pace;
  final ValueChanged<FollowUpPace> onChanged;

  const _PaceCard({required this.pace, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = const [
      (FollowUpPace.daily, '每日', 7),
      (FollowUpPace.everyOther, '隔日', 3),
      (FollowUpPace.weekly, '每週', 2),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.alarm_on_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('提醒頻率', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ...options.map((option) {
              final selected = option.$1 == pace;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onChanged(option.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primaryContainer
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 26,
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(option.$2,
                              style: theme.textTheme.titleMedium),
                        ),
                        _PaceDots(
                          activeDots: option.$3,
                          activeColor: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          inactiveColor: theme.colorScheme.outlineVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _PaceDots extends StatelessWidget {
  final int activeDots;
  final Color activeColor;
  final Color inactiveColor;

  const _PaceDots({
    required this.activeDots,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(7, (i) {
        return Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: i < activeDots ? activeColor : inactiveColor,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}
