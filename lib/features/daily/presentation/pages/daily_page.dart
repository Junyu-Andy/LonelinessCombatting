import 'package:flutter/material.dart';

import '../../../analytics/presentation/analytics_scope.dart';
import '../../../crisis/presentation/pages/emergency_support_page.dart';

/// "每日 / Daily" — a feed surface picked for the user based on their
/// recent mood + social log. Shows three read-ables (news / articles /
/// tips) and three small action suggestions for today.
class DailyPage extends StatelessWidget {
  const DailyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    final feedItems = isEn
        ? const [
            _FeedData(
              tag: 'Mental Health',
              tagColor: Color(0xFFDBEAFE),
              readMinutes: 3,
              title: 'How to Break the Silence?',
              summary:
                  'Research shows a small greeting can change someone\'s day — here\'s how to start.',
              icon: Icons.chat_bubble_outline,
            ),
            _FeedData(
              tag: 'Wellness',
              tagColor: Color(0xFFD1FAE5),
              readMinutes: 5,
              title: 'Loneliness & Sleep',
              summary:
                  'The connection you might not know. What science says about lonely nights.',
              icon: Icons.bedtime_outlined,
            ),
            _FeedData(
              tag: 'Try Today',
              tagColor: Color(0xFFFEF3C7),
              readMinutes: 5,
              title: '5-Minute Mindfulness',
              summary:
                  'A single exercise you can do at your desk. We\'ll walk you through it.',
              icon: Icons.self_improvement,
            ),
          ]
        : const [
            _FeedData(
              tag: '心理健康',
              tagColor: Color(0xFFDBEAFE),
              readMinutes: 3,
              title: '點樣主動打破沉默？',
              summary: '研究話，一個小問候可以改變一日 — 由一句開始，比你諗嘅容易。',
              icon: Icons.chat_bubble_outline,
            ),
            _FeedData(
              tag: '身心健康',
              tagColor: Color(0xFFD1FAE5),
              readMinutes: 5,
              title: '孤獨感與睡眠',
              summary: '你可能唔知嘅關係。科學點樣講孤獨嘅夜晚？',
              icon: Icons.bedtime_outlined,
            ),
            _FeedData(
              tag: '今日試吓',
              tagColor: Color(0xFFFEF3C7),
              readMinutes: 5,
              title: '5 分鐘正念練習',
              summary: '一個可以喺枱邊做嘅小練習。我哋一步一步帶你行。',
              icon: Icons.self_improvement,
            ),
          ];

    final tinySteps = isEn
        ? const [
            _StepData(
              effort: '2 min',
              icon: Icons.sms_outlined,
              title: 'Send a text to a relative',
              detail: '"Good morning — hope you\'re well!"',
              why: 'Feel connected',
              whyIcon: Icons.favorite_outline,
            ),
            _StepData(
              effort: '5 min',
              icon: Icons.phone_in_talk_outlined,
              title: 'Call a friend',
              detail: 'Ask how their weekend went.',
              why: 'Reconnect',
              whyIcon: Icons.link_rounded,
            ),
            _StepData(
              effort: '15 min',
              icon: Icons.park_outlined,
              title: 'Stroll in the park',
              detail: 'Bring water  •  enjoy the sunshine.',
              why: 'Refresh body & mind',
              whyIcon: Icons.wb_sunny_outlined,
            ),
          ]
        : const [
            _StepData(
              effort: '2 分鐘',
              icon: Icons.sms_outlined,
              title: '同表姐傳個短訊',
              detail: '「早晨，幾時飲茶？」',
              why: '感受連結',
              whyIcon: Icons.favorite_outline,
            ),
            _StepData(
              effort: '5 分鐘',
              icon: Icons.phone_in_talk_outlined,
              title: '打電話畀阿May',
              detail: '問聲週末點。',
              why: '重新接線',
              whyIcon: Icons.link_rounded,
            ),
            _StepData(
              effort: '15 分鐘',
              icon: Icons.park_outlined,
              title: '落公園散下步',
              detail: '帶水　•　享受陽光。',
              why: '舒展身心',
              whyIcon: Icons.wb_sunny_outlined,
            ),
          ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          // Header banner ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE0F2FE), Color(0xFFF0FDF4)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.wb_sunny_rounded,
                      size: 36, color: Color(0xFFEAB308)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEn ? 'Daily For You' : '每日推薦',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isEn
                            ? 'Picked just for you based on your recent mood'
                            : '根據你最近嘅情況，特別揀咗呢啲',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF475569),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Daily feed ───────────────────────────────────────────
          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.auto_stories_outlined,
            title: isEn ? 'Learn Something Today' : '今日知多啲',
          ),
          const SizedBox(height: 14),
          ...feedItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FeedCard(data: item),
            ),
          ),

          // Recommended for today ────────────────────────────────
          const SizedBox(height: 16),
          _SectionHeader(
            icon: Icons.local_florist_outlined,
            title: isEn ? 'Recommended for Today' : '今日行動建議',
          ),
          const SizedBox(height: 14),
          ...tinySteps.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _TinyStepCard(step: s, isEn: isEn),
              )),

          // Safety footer ────────────────────────────────────────
          const SizedBox(height: 12),
          _SafetyFooter(isEn: isEn),
        ],
      ),
    );
  }
}

// ─── Feed card ──────────────────────────────────────────────────

class _FeedData {
  final String tag;
  final Color tagColor;
  final int readMinutes;
  final String title;
  final String summary;
  final IconData icon;

  const _FeedData({
    required this.tag,
    required this.tagColor,
    required this.readMinutes,
    required this.title,
    required this.summary,
    required this.icon,
  });
}

class _FeedCard extends StatelessWidget {
  final _FeedData data;
  const _FeedCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isEn
                  ? 'Feature in progress — stay tuned 🙏'
                  : '功能開發中，敬請期待 🙏'),
              duration: const Duration(milliseconds: 1800),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: data.tagColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(data.icon, size: 28, color: Colors.black87),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: data.tagColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            data.tag,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.schedule,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          isEn
                              ? '${data.readMinutes} min read'
                              : '${data.readMinutes} 分鐘',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tiny step card (copied structure from action_support_page) ──

class _StepData {
  final String effort;
  final IconData icon;
  final String title;
  final String detail;
  final String why;
  final IconData whyIcon;

  const _StepData({
    required this.effort,
    required this.icon,
    required this.title,
    required this.detail,
    required this.why,
    required this.whyIcon,
  });
}

class _TinyStepCard extends StatelessWidget {
  final _StepData step;
  final bool isEn;

  const _TinyStepCard({required this.step, required this.isEn});

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
                  child: Icon(step.icon,
                      size: 30, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Chip(
                            icon: Icons.timer_outlined,
                            label: step.effort,
                            color: theme.colorScheme.primaryContainer,
                            textColor: theme.colorScheme.onPrimaryContainer,
                          ),
                          _Chip(
                            icon: step.whyIcon,
                            label: step.why,
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
            Text(step.detail, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.check_rounded, size: 24),
                    label: Text(isEn ? 'I\'ll try' : '會試'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.skip_next_rounded, size: 24),
                    label: Text(isEn ? 'Not now' : '唔啱'),
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

// ─── Section header + safety footer ──────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 28, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
      ],
    );
  }
}

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
              .logEmergencyOpened(from: 'daily_safety_footer');
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
                      isEn ? 'Can\'t cope? → Call 999' : '撐唔住？　→　撥 999',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEn
                          ? 'View all support hotlines'
                          : '睇所有支援熱線',
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
