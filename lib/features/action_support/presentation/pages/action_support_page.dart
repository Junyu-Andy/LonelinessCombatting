import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/figure_placeholder.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../crisis/presentation/pages/emergency_support_page.dart';
import '../../../resources/presentation/pages/community_resources_page.dart';
import '../../../wellbeing/presentation/pages/calm_page.dart';

class ActionSupportPage extends StatelessWidget {
  const ActionSupportPage({super.key});

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
                Icons.spa_rounded,
                size: 34,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.actionTab,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.actionSubtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const FigurePlaceholder(
            description: '插畫：陽光照入窗，桌上有一壺熱茶同一本攤開嘅書，氣氛舒服。',
            height: 130,
            icon: Icons.local_florist_outlined,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _QuickTile(
                  icon: Icons.self_improvement,
                  label: '靜一靜',
                  onTap: () {
                    AnalyticsScope.of(context)
                        .logEmergencyOpened(from: 'action_calm_tile');
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CalmPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickTile(
                  icon: Icons.map_outlined,
                  label: '社區資源',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CommunityResourcesPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.local_florist_outlined,
            title: '今日做啲令自己舒服嘅事',
          ),
          const SizedBox(height: 14),
          const _TinyStepCard(
            effort: '2 分鐘',
            icon: Icons.sms_outlined,
            title: '同表姐傳個短訊',
            detail: '「早晨，幾時飲茶？」',
            why: '感受連結',
            whyIcon: Icons.favorite_outline,
          ),
          const SizedBox(height: 14),
          const _TinyStepCard(
            effort: '5 分鐘',
            icon: Icons.phone_in_talk_outlined,
            title: '打電話畀阿May',
            detail: '問聲週末點，順便分享你今日嘅一件小事。',
            why: '重新接線',
            whyIcon: Icons.link_rounded,
          ),
          const SizedBox(height: 14),
          const _TinyStepCard(
            effort: '15 分鐘',
            icon: Icons.park_outlined,
            title: '落公園散下步',
            detail: '帶水　•　享受陽光。',
            why: '舒展身心',
            whyIcon: Icons.wb_sunny_outlined,
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.chat_bubble_outline,
            title: '想開口問候人？揀一句用得',
          ),
          const SizedBox(height: 14),
          const _OpenerCard(
            audience: '畀屋企人',
            icon: Icons.family_restroom,
            line: '「諗起你，食咗飯未？」',
          ),
          const SizedBox(height: 12),
          const _OpenerCard(
            audience: '畀朋友',
            icon: Icons.group_outlined,
            line: '「好耐冇傾，你最近點？」',
          ),
          const SizedBox(height: 12),
          const _OpenerCard(
            audience: '畀舊同學／同事',
            icon: Icons.school_outlined,
            line: '「見到一樣嘢諗起你，講聲 hi。」',
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.celebration_outlined,
            title: '揀件喜歡嘅嚟試吓',
          ),
          const SizedBox(height: 14),
          const _ActivityGrid(),
          const SizedBox(height: 28),
          const _SafetyFooter(),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
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

class _TinyStepCard extends StatelessWidget {
  final String effort;
  final IconData icon;
  final String title;
  final String detail;
  final String why;
  final IconData whyIcon;

  const _TinyStepCard({
    required this.effort,
    required this.icon,
    required this.title,
    required this.detail,
    required this.why,
    required this.whyIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon,
                      size: 30, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Chip(
                            icon: Icons.timer_outlined,
                            label: effort,
                            color: theme.colorScheme.primaryContainer,
                            textColor: theme.colorScheme.onPrimaryContainer,
                          ),
                          _Chip(
                            icon: whyIcon,
                            label: why,
                            color: theme.colorScheme.surfaceContainerHighest,
                            textColor: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(detail, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.check_rounded, size: 24),
                    label: const Text('會試'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.skip_next_rounded, size: 24),
                    label: const Text('唔啱'),
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

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;

  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenerCard extends StatelessWidget {
  final String audience;
  final IconData icon;
  final String line;

  const _OpenerCard({
    required this.audience,
    required this.icon,
    required this.line,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 26, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    audience,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(line, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                AnalyticsScope.of(context)
                    .logOpenerCopied(audience: audience);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已複製：$line'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              tooltip: '複製',
              icon: const Icon(Icons.copy_rounded, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityGrid extends StatelessWidget {
  const _ActivityGrid();

  @override
  Widget build(BuildContext context) {
    final activities = const [
      _Activity(
        icon: Icons.self_improvement,
        title: '靜坐 3 分鐘',
        tag: '一個人',
        tagIcon: Icons.person_outline,
        accent: Color(0xFFB6E1C9),
      ),
      _Activity(
        icon: Icons.directions_walk,
        title: '行 10 分鐘',
        tag: '一個人',
        tagIcon: Icons.person_outline,
        accent: Color(0xFFB6E1C9),
      ),
      _Activity(
        icon: Icons.local_cafe_outlined,
        title: '約朋友飲茶',
        tag: '約人',
        tagIcon: Icons.handshake_outlined,
        accent: Color(0xFFFFD8A8),
      ),
      _Activity(
        icon: Icons.volunteer_activism_outlined,
        title: '長者／社區中心',
        tag: '見到人',
        tagIcon: Icons.groups_2_outlined,
        accent: Color(0xFFCFD8FF),
      ),
    ];

    return Column(
      children: activities
          .map(
            (activity) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ActivityTile(activity: activity),
            ),
          )
          .toList(),
    );
  }
}

class _Activity {
  final IconData icon;
  final String title;
  final String tag;
  final IconData tagIcon;
  final Color accent;

  const _Activity({
    required this.icon,
    required this.title,
    required this.tag,
    required this.tagIcon,
    required this.accent,
  });
}

class _ActivityTile extends StatelessWidget {
  final _Activity activity;

  const _ActivityTile({required this.activity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: activity.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(activity.icon, size: 28, color: Colors.black87),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                activity.title,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: activity.accent.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(activity.tagIcon, size: 16, color: Colors.black87),
                  const SizedBox(width: 4),
                  Text(
                    activity.tag,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
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

class _SafetyFooter extends StatelessWidget {
  const _SafetyFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          AnalyticsScope.of(context)
              .logEmergencyOpened(from: 'action_safety_footer');
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const EmergencySupportPage(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                size: 28,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '撐唔住？　→　撥 999',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '睇所有支援熱線',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
