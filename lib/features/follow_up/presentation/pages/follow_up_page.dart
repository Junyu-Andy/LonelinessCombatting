import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';

enum _Pace { daily, everyOther, weekly }

class FollowUpPage extends StatefulWidget {
  const FollowUpPage({super.key});

  @override
  State<FollowUpPage> createState() => _FollowUpPageState();
}

class _FollowUpPageState extends State<FollowUpPage> {
  _Pace _pace = _Pace.everyOther;

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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Row(
            children: [
              Icon(
                Icons.event_note,
                size: 36,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.followUpTab,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.followUpSubtitle,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.alarm_outlined,
            title: '即將到嘅提醒',
          ),
          const SizedBox(height: 14),
          ..._reminders.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
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
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded, size: 26),
              label: const Text('加多一個提醒'),
            ),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.insights_outlined,
            title: '今個星期嘅進度',
          ),
          const SizedBox(height: 14),
          const _WeeklyProgressCard(
            checkInCount: 4,
            checkInGoal: 5,
            stepsTried: 2,
            contactsReached: 1,
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.tune_outlined,
            title: '節奏調整',
          ),
          const SizedBox(height: 14),
          _PaceCard(
            pace: _pace,
            onChanged: (value) => setState(() => _pace = value),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.celebration_outlined,
            title: '小成就',
          ),
          const SizedBox(height: 14),
          const _CelebrationCard(),
        ],
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
        Icon(icon, size: 30, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge,
          ),
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

  _Reminder copyWith({bool? active}) {
    return _Reminder(
      icon: icon,
      title: title,
      when: when,
      active: active ?? this.active,
    );
  }
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
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(reminder.icon, size: 30, color: iconColor),
            ),
            const SizedBox(width: 14),
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
                  const SizedBox(height: 4),
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
              scale: 1.2,
              child: Switch(
                value: active,
                onChanged: onToggle,
              ),
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Check-in 次數',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 18,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$checkInCount / $checkInGoal',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _StatRow(
              icon: Icons.directions_run,
              label: '試過嘅行動',
              value: '$stepsTried 次',
            ),
            const SizedBox(height: 10),
            _StatRow(
              icon: Icons.forum_outlined,
              label: '有傾過偈嘅朋友',
              value: '$contactsReached 位',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.emoji_emotions_outlined,
                    size: 24,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '已經完成大部分，最後差少少就夠今個星期嘅目標。',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
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
        Icon(icon, size: 26, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _PaceCard extends StatelessWidget {
  final _Pace pace;
  final ValueChanged<_Pace> onChanged;

  const _PaceCard({required this.pace, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final options = const [
      (_Pace.daily, '每日', '每日有少少聯絡'),
      (_Pace.everyOther, '隔日', '兩至三日一次'),
      (_Pace.weekly, '每週幾次', '一星期幾次就夠'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '你希望幾密會收到提醒？',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            ...options.map((option) {
              final selected = option.$1 == pace;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onChanged(option.$1),
                  child: Container(
                    padding: const EdgeInsets.all(14),
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
                          size: 28,
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option.$2,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                option.$3,
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
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _CelebrationCard extends StatelessWidget {
  const _CelebrationCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final moments = const [
      '連續 4 日完成 check-in',
      '主動傳咗一個短訊畀表姐',
      '踏出屋企行咗一轉',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今個星期值得肯定自己嘅地方',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...moments.map(
              (moment) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 26,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        moment,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '就算行得慢，方向都係啱嘅。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
