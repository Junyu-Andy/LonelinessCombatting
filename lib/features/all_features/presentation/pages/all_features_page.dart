import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../features/analytics/presentation/analytics_scope.dart';
import '../../../../features/context/presentation/pages/check_in_page.dart';
import '../../../../features/context/presentation/pages/reflection_page.dart';
import '../../../../features/context/presentation/pages/social_map_page.dart';
import '../../../../features/crisis/presentation/pages/emergency_support_page.dart';
import '../../../../features/follow_up/presentation/pages/follow_up_page.dart';
import '../../../../features/personalization/presentation/pages/personalization_page.dart';
import '../../../../features/resources/presentation/pages/community_resources_page.dart';
import '../../../../features/wellbeing/presentation/pages/calm_page.dart';

class AllFeaturesPage extends StatelessWidget {
  const AllFeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final settings = AppSettingsScope.of(context);
    final profile = settings.profile;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _AllFeaturesHeader(isEn: isEn),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileCard(
                  isEn: isEn,
                  displayName: profile?.displayName,
                  email: profile?.email,
                  isGuest: profile == null,
                ),
                const SizedBox(height: 24),
                _SectionLabel(
                  icon: Icons.widgets_outlined,
                  title: isEn ? 'All Features' : '所有功能',
                ),
                const SizedBox(height: 14),
                _FeaturesGrid(isEn: isEn),
                const SizedBox(height: 28),
                _SectionLabel(
                  icon: Icons.celebration_outlined,
                  title: isEn ? 'Activities to try' : '可以試下嘅活動',
                ),
                const SizedBox(height: 14),
                _ActivitiesList(isEn: isEn),
                const SizedBox(height: 28),
                _SafetyFooter(isEn: isEn),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Banner ───────────────────────────────────────────────────────────────────

class _AllFeaturesHeader extends StatelessWidget {
  final bool isEn;
  const _AllFeaturesHeader({required this.isEn});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.apps_rounded, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEn ? 'All Features' : '全部 / All',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isEn
                      ? 'Everything in one place'
                      : '所有工具，一眼睇晒',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile card ─────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final bool isEn;
  final String? displayName;
  final String? email;
  final bool isGuest;

  const _ProfileCard({
    required this.isEn,
    required this.displayName,
    required this.email,
    required this.isGuest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = displayName ?? (isEn ? 'Guest' : '訪客');
    final sub = isGuest
        ? (isEn ? 'Sign in to save your progress' : '登入以儲存紀錄')
        : (email ?? '');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PersonalizationPage(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 26,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionLabel({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 26, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleLarge),
      ],
    );
  }
}

// ── Features grid ─────────────────────────────────────────────────────────────

class _FeatureItem {
  final IconData icon;
  final String labelZh;
  final String labelEn;
  final Color accent;
  final Widget Function() pageBuilder;

  const _FeatureItem({
    required this.icon,
    required this.labelZh,
    required this.labelEn,
    required this.accent,
    required this.pageBuilder,
  });
}

class _FeaturesGrid extends StatelessWidget {
  final bool isEn;
  const _FeaturesGrid({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final items = [
      _FeatureItem(
        icon: Icons.mood_outlined,
        labelZh: '心情打卡',
        labelEn: 'Check-In',
        accent: const Color(0xFF93C5FD),
        pageBuilder: () => const CheckInPage(),
      ),
      _FeatureItem(
        icon: Icons.map_outlined,
        labelZh: '社交地圖',
        labelEn: 'Social Map',
        accent: const Color(0xFF86EFAC),
        pageBuilder: () => const SocialMapPage(),
      ),
      _FeatureItem(
        icon: Icons.auto_stories_outlined,
        labelZh: '反思日記',
        labelEn: 'Reflect',
        accent: const Color(0xFFFCA5A5),
        pageBuilder: () => const ReflectionPage(),
      ),
      _FeatureItem(
        icon: Icons.self_improvement,
        labelZh: '靜一靜',
        labelEn: 'Calm',
        accent: const Color(0xFFB6E1C9),
        pageBuilder: () => const CalmPage(),
      ),
      _FeatureItem(
        icon: Icons.track_changes_outlined,
        labelZh: '跟進計劃',
        labelEn: 'Follow-Up',
        accent: const Color(0xFFFDE68A),
        pageBuilder: () => const FollowUpPage(),
      ),
      _FeatureItem(
        icon: Icons.groups_outlined,
        labelZh: '社區資源',
        labelEn: 'Community',
        accent: const Color(0xFFC4B5FD),
        pageBuilder: () => const CommunityResourcesPage(),
      ),
      _FeatureItem(
        icon: Icons.health_and_safety_outlined,
        labelZh: '危機支援',
        labelEn: 'Crisis Help',
        accent: const Color(0xFFFDA4AF),
        pageBuilder: () => const EmergencySupportPage(),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, i) => _FeatureTile(
        item: items[i],
        isEn: isEn,
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final _FeatureItem item;
  final bool isEn;
  const _FeatureTile({required this.item, required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => item.pageBuilder()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, size: 26, color: Colors.black87),
              ),
              Text(
                isEn ? item.labelEn : item.labelZh,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Activities list ───────────────────────────────────────────────────────────

class _ActivitiesList extends StatelessWidget {
  final bool isEn;
  const _ActivitiesList({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final items = isEn
        ? const [
            _ActivityData(
              icon: Icons.self_improvement,
              title: 'Sit quietly 3 min',
              tag: 'Solo',
              tagIcon: Icons.person_outline,
              accent: Color(0xFFB6E1C9),
            ),
            _ActivityData(
              icon: Icons.directions_walk,
              title: 'Walk 10 min',
              tag: 'Solo',
              tagIcon: Icons.person_outline,
              accent: Color(0xFFB6E1C9),
            ),
            _ActivityData(
              icon: Icons.local_cafe_outlined,
              title: 'Meet a friend for tea',
              tag: 'Social',
              tagIcon: Icons.handshake_outlined,
              accent: Color(0xFFFFD8A8),
            ),
            _ActivityData(
              icon: Icons.volunteer_activism_outlined,
              title: 'Elderly / community centre',
              tag: 'With others',
              tagIcon: Icons.groups_2_outlined,
              accent: Color(0xFFCFD8FF),
            ),
          ]
        : const [
            _ActivityData(
              icon: Icons.self_improvement,
              title: '靜坐 3 分鐘',
              tag: '一個人',
              tagIcon: Icons.person_outline,
              accent: Color(0xFFB6E1C9),
            ),
            _ActivityData(
              icon: Icons.directions_walk,
              title: '行 10 分鐘',
              tag: '一個人',
              tagIcon: Icons.person_outline,
              accent: Color(0xFFB6E1C9),
            ),
            _ActivityData(
              icon: Icons.local_cafe_outlined,
              title: '約朋友飲茶',
              tag: '約人',
              tagIcon: Icons.handshake_outlined,
              accent: Color(0xFFFFD8A8),
            ),
            _ActivityData(
              icon: Icons.volunteer_activism_outlined,
              title: '長者／社區中心',
              tag: '見到人',
              tagIcon: Icons.groups_2_outlined,
              accent: Color(0xFFCFD8FF),
            ),
          ];

    return Column(
      children: items
          .map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ActivityTile(data: a),
            ),
          )
          .toList(),
    );
  }
}

class _ActivityData {
  final IconData icon;
  final String title;
  final String tag;
  final IconData tagIcon;
  final Color accent;

  const _ActivityData({
    required this.icon,
    required this.title,
    required this.tag,
    required this.tagIcon,
    required this.accent,
  });
}

class _ActivityTile extends StatelessWidget {
  final _ActivityData data;
  const _ActivityTile({required this.data});

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
                color: data.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(data.icon, size: 28, color: Colors.black87),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(data.title, style: theme.textTheme.titleMedium),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: data.accent.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(data.tagIcon, size: 16, color: Colors.black87),
                  const SizedBox(width: 4),
                  Text(
                    data.tag,
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

// ── Safety footer ─────────────────────────────────────────────────────────────

class _SafetyFooter extends StatelessWidget {
  final bool isEn;
  const _SafetyFooter({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          AnalyticsScope.of(context)
              .logEmergencyOpened(from: 'all_features_safety_footer');
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
                      isEn ? "Can't cope? → Call 999" : '撐唔住？　→　撥 999',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEn ? 'View all support hotlines' : '睇所有支援熱線',
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
