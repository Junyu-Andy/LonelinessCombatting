import 'package:flutter/material.dart';
import 'check_in_page.dart';
import 'social_map_page.dart';
import 'reflection_page.dart';

class ContextPage extends StatelessWidget {
  const ContextPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            '呢個模組負責理解你目前嘅狀態，等之後嘅建議可以更貼近你嘅生活。',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          const _TodaySnapshotCard(
            mood: 3,
            loneliness: 4,
            socialEnergy: 2,
            lastCheckIn: '今日早上',
          ),
          const SizedBox(height: 24),
          _ContextEntryCard(
            icon: Icons.monitor_heart_outlined,
            title: '快速 Check-in',
            subtitle: '睇下今日心情、孤獨感同最近社交經驗。',
            buttonText: '打開 Check-in',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CheckInPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          _ContextEntryCard(
            icon: Icons.people_outline,
            title: '社交關係圖',
            subtitle: '整理身邊嘅重要關係，睇下邊啲人比較容易聯絡。',
            buttonText: '打開社交關係圖',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SocialMapPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          _ContextEntryCard(
            icon: Icons.forum_outlined,
            title: '互動反思',
            subtitle: '回顧最近同人接觸嘅感覺，邊度有連結，邊度仲有落差。',
            buttonText: '打開反思頁',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReflectionPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TodaySnapshotCard extends StatelessWidget {
  final int mood;
  final int loneliness;
  final int socialEnergy;
  final String lastCheckIn;

  const _TodaySnapshotCard({
    required this.mood,
    required this.loneliness,
    required this.socialEnergy,
    required this.lastCheckIn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.today_outlined,
                  size: 30,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '你今日嘅狀態',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SnapshotRow(label: '心情', value: mood),
            const SizedBox(height: 12),
            _SnapshotRow(label: '孤獨感', value: loneliness),
            const SizedBox(height: 12),
            _SnapshotRow(label: '社交能量', value: socialEnergy),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '上次 Check-in：$lastCheckIn',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  final String label;
  final int value;

  const _SnapshotRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: theme.textTheme.bodyLarge,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: value / 5,
              minHeight: 16,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor:
                  AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          child: Text(
            '$value/5',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _ContextEntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTap;

  const _ContextEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      icon,
                      size: 40,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                subtitle,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 26),
                  label: Text(buttonText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
