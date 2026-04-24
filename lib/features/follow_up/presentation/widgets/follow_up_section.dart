import 'package:flutter/material.dart';

enum FollowUpPace { daily, everyOther, weekly }

/// The body of the follow-up surface (reminders, weekly progress, pace,
/// celebrations) split out so it can be embedded inside the personalisation
/// page as well as the standalone follow-up page.
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

  final List<_Reminder> _reminders = [
    _Reminder(
      icon: Icons.phone_in_talk_outlined,
      title: '打電話畀阿May',
      when: '星期三　下午 3:00',
      active: true,
    ),
    _Reminder(
      icon: Icons.message_outlined,
      title: '問候表姐',
      when: '星期五　早上 10:00',
      active: true,
    ),
    _Reminder(
      icon: Icons.directions_walk,
      title: '落公園行 15 分鐘',
      when: '星期六　下午 4:00',
      active: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.withHeader)
          const _SectionHeader(
              icon: Icons.alarm_outlined, title: '即將到嘅提醒'),
        if (widget.withHeader) const SizedBox(height: 14),
        ..._reminders.asMap().entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReminderCard(
              reminder: entry.value,
              onToggle: (value) {
                setState(() {
                  _reminders[entry.key] =
                      entry.value.copyWith(active: value);
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded, size: 24),
            label: const Text('加多一個提醒'),
          ),
        ),
        const SizedBox(height: 24),
        const _SectionHeader(
            icon: Icons.insights_outlined, title: '今個星期嘅進度'),
        const SizedBox(height: 12),
        const _WeeklyProgressCard(
          checkInCount: 4,
          checkInGoal: 5,
          stepsTried: 2,
          contactsReached: 1,
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
        const _CelebrationCard(),
      ],
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

class _Reminder {
  final IconData icon;
  final String title;
  final String when;
  final bool active;

  _Reminder({
    required this.icon,
    required this.title,
    required this.when,
    required this.active,
  });

  _Reminder copyWith({bool? active}) => _Reminder(
        icon: icon,
        title: title,
        when: when,
        active: active ?? this.active,
      );
}

class _ReminderCard extends StatelessWidget {
  final _Reminder reminder;
  final ValueChanged<bool> onToggle;

  const _ReminderCard({required this.reminder, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = reminder.active;
    final iconColor = active
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final tileColor = active
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(reminder.icon, size: 28, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: active
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    reminder.when,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 1.1,
              child: Switch(value: active, onChanged: onToggle),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyProgressCard extends StatelessWidget {
  final int checkInCount;
  final int checkInGoal;
  final int stepsTried;
  final int contactsReached;

  const _WeeklyProgressCard({
    required this.checkInCount,
    required this.checkInGoal,
    required this.stepsTried,
    required this.contactsReached,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = (checkInCount / checkInGoal).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Check-in', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: ratio.toDouble()),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) =>
                          LinearProgressIndicator(
                        value: value,
                        minHeight: 16,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$checkInCount / $checkInGoal',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    )),
              ],
            ),
            const SizedBox(height: 16),
            _StatRow(
                icon: Icons.directions_run,
                label: '行動',
                value: '$stepsTried 次'),
            const SizedBox(height: 8),
            _StatRow(
                icon: Icons.forum_outlined,
                label: '傾偈朋友',
                value: '$contactsReached 位'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.emoji_emotions_outlined,
                      size: 22,
                      color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('差少少就達標 🎉',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 24, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        Text(value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            )),
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

class _CelebrationCard extends StatelessWidget {
  const _CelebrationCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moments = const [
      (Icons.check_circle, '連續 4 日 check-in'),
      (Icons.send_rounded, '傳短訊畀表姐'),
      (Icons.directions_walk, '行出屋企一轉'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text('值得肯定', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            ...moments.map(
              (moment) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(moment.$1,
                        size: 22, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(moment.$2,
                          style: theme.textTheme.bodyLarge),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
