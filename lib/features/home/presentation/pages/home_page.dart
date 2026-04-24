import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/figure_placeholder.dart';
import '../../../action_support/presentation/pages/action_support_page.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../context/presentation/pages/check_in_page.dart';
import '../../../context/presentation/pages/reflection_page.dart';
import '../../../context/presentation/pages/social_map_page.dart';
import '../../../crisis/presentation/pages/emergency_support_page.dart';
import '../../../follow_up/presentation/pages/follow_up_page.dart';
import '../../../resources/presentation/pages/community_resources_page.dart';
import '../../../wellbeing/presentation/pages/calm_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<_SocialEntry> _todayEntries = [
    _SocialEntry(
      person: '表姐',
      summary: '喺家庭群組講咗幾句日常嘢，氣氛輕鬆。',
      feeling: _Feeling.warm,
      time: const TimeOfDay(hour: 10, minute: 24),
    ),
  ];

  void _addEntry(_SocialEntry entry) {
    setState(() => _todayEntries.insert(0, entry));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _GreetingHero(now: now, appTitle: l10n.appTitle),
          const SizedBox(height: 20),
          _TodayVibeCard(
            mood: 3,
            loneliness: 4,
            socialEnergy: 2,
            onCheckIn: () => _open(const CheckInPage()),
          ),
          const SizedBox(height: 20),
          _SocialLogCard(
            entries: _todayEntries,
            onAdd: _addEntry,
          ),
          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.apps_rounded,
            title: '想由邊度開始？',
            subtitle: '揀一個功能。',
          ),
          const SizedBox(height: 14),
          _QuickActionsGrid(
            actions: [
              _QuickAction(
                icon: Icons.favorite_outline,
                label: '快速 Check-in',
                color: const Color(0xFFFEE2E2),
                onTap: () => _open(const CheckInPage()),
              ),
              _QuickAction(
                icon: Icons.people_outline,
                label: '社交關係圖',
                color: const Color(0xFFDBEAFE),
                onTap: () => _open(const SocialMapPage()),
              ),
              _QuickAction(
                icon: Icons.forum_outlined,
                label: '互動反思',
                color: const Color(0xFFE0E7FF),
                onTap: () => _open(const ReflectionPage()),
              ),
              _QuickAction(
                icon: Icons.self_improvement,
                label: '靜一靜',
                color: const Color(0xFFD1FAE5),
                onTap: () => _open(const CalmPage()),
              ),
              _QuickAction(
                icon: Icons.lightbulb_outline,
                label: '行動支援',
                color: const Color(0xFFFEF3C7),
                onTap: () => _open(const ActionSupportPage()),
              ),
              _QuickAction(
                icon: Icons.event_note_outlined,
                label: '跟進提醒',
                color: const Color(0xFFFCE7F3),
                onTap: () => _open(const FollowUpPage()),
              ),
              _QuickAction(
                icon: Icons.handshake_outlined,
                label: '社區資源',
                color: const Color(0xFFCCFBF1),
                onTap: () => _open(const CommunityResourcesPage()),
              ),
              _QuickAction(
                icon: Icons.health_and_safety_outlined,
                label: '即時支援',
                color: const Color(0xFFFFE4E6),
                onTap: () {
                  AnalyticsScope.of(context)
                      .logEmergencyOpened(from: 'home_quick_actions');
                  _open(const EmergencySupportPage());
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          const FigurePlaceholder(
            description: '插畫：兩個輪廓喺手機兩端微笑，象徵簡短嘅問候已經有溫度。',
            height: 110,
            icon: Icons.chat_bubble_outline,
          ),
          const SizedBox(height: 16),
          _DailySuggestionCard(
            onReachOut: () => _open(const SocialMapPage()),
          ),
          const SizedBox(height: 20),
          _BoundaryReminderCard(
            onEmergency: () {
              AnalyticsScope.of(context)
                  .logEmergencyOpened(from: 'home_boundary_card');
              _open(const EmergencySupportPage());
            },
          ),
        ],
      ),
    );
  }

  void _open(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}

class _GreetingHero extends StatelessWidget {
  final DateTime now;
  final String appTitle;

  const _GreetingHero({required this.now, required this.appTitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = now.hour;
    final String greeting;
    final IconData icon;
    if (hour >= 5 && hour < 11) {
      greeting = '早晨！';
      icon = Icons.wb_sunny_outlined;
    } else if (hour >= 11 && hour < 14) {
      greeting = '午安！';
      icon = Icons.light_mode_outlined;
    } else if (hour >= 14 && hour < 18) {
      greeting = '下午好';
      icon = Icons.wb_cloudy_outlined;
    } else if (hour >= 18 && hour < 22) {
      greeting = '夜晚好';
      icon = Icons.nights_stay_outlined;
    } else {
      greeting = '夜深喇，慢慢嚟';
      icon = Icons.bedtime_outlined;
    }

    const weekdayNames = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final dateLine = '${now.month} 月 ${now.day} 日　${weekdayNames[now.weekday - 1]}';

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.78),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 30, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLine,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      greeting,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.spa_outlined,
                  size: 20, color: Colors.white.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '揀一件你而家做到嘅事 — $appTitle 陪你。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.95),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'HKU',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '工業及製造系統工程學系',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayVibeCard extends StatelessWidget {
  final int mood;
  final int loneliness;
  final int socialEnergy;
  final VoidCallback onCheckIn;

  const _TodayVibeCard({
    required this.mood,
    required this.loneliness,
    required this.socialEnergy,
    required this.onCheckIn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.today_outlined,
                  size: 26,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('今日狀態', style: theme.textTheme.titleLarge),
                ),
                TextButton.icon(
                  onPressed: onCheckIn,
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  label: const Text('Check-in'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _VibeBar(label: '心情', value: mood),
            const SizedBox(height: 12),
            _VibeBar(label: '孤獨感', value: loneliness),
            const SizedBox(height: 12),
            _VibeBar(label: '社交能量', value: socialEnergy),
          ],
        ),
      ),
    );
  }
}

class _VibeBar extends StatelessWidget {
  final String label;
  final int value;

  const _VibeBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(label, style: theme.textTheme.bodyLarge),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: value / 5,
              minHeight: 14,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor:
                  AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
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

class _SocialLogCard extends StatefulWidget {
  final List<_SocialEntry> entries;
  final ValueChanged<_SocialEntry> onAdd;

  const _SocialLogCard({required this.entries, required this.onAdd});

  @override
  State<_SocialLogCard> createState() => _SocialLogCardState();
}

class _SocialLogCardState extends State<_SocialLogCard> {
  final TextEditingController _personController = TextEditingController();
  final TextEditingController _summaryController = TextEditingController();
  _Feeling _feeling = _Feeling.warm;

  @override
  void dispose() {
    _personController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  void _save() {
    final summary = _summaryController.text.trim();
    if (summary.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請寫低少少今日嘅互動再儲存。')),
      );
      return;
    }
    final hasPerson = _personController.text.trim().isNotEmpty;
    widget.onAdd(_SocialEntry(
      person: hasPerson ? _personController.text.trim() : '冇指定對象',
      summary: summary,
      feeling: _feeling,
      time: TimeOfDay.fromDateTime(DateTime.now()),
    ));
    AnalyticsScope.of(context).logSocialLogEntry(
      hasPerson: hasPerson,
      summaryLength: summary.length,
      feeling: _feeling.name,
    );
    _personController.clear();
    _summaryController.clear();
    setState(() => _feeling = _Feeling.warm);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('今日社交記錄', style: theme.textTheme.titleLarge),
                ),
                _CountBadge(count: widget.entries.length),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.note_alt_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '寫低　•　之後睇返',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _personController,
              style: theme.textTheme.bodyLarge,
              decoration: const InputDecoration(
                labelText: '同邊個？',
                hintText: '阿May / 表姐…',
                prefixIcon: Icon(Icons.person_outline, size: 24),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summaryController,
              maxLines: 3,
              style: theme.textTheme.bodyLarge,
              decoration: const InputDecoration(
                labelText: '做咗啲乜？',
                hintText: '傳語音、傾咗 5 分鐘…',
                prefixIcon: Icon(Icons.edit_outlined, size: 24),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.mood_outlined,
                    size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '感覺點？',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _Feeling.values.map((f) {
                final selected = f == _feeling;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(f.emoji),
                      const SizedBox(width: 6),
                      Text(f.label),
                    ],
                  ),
                  selected: selected,
                  onSelected: (_) => setState(() => _feeling = f),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, size: 24),
                label: const Text('儲存今日記錄'),
              ),
            ),
            if (widget.entries.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(color: theme.colorScheme.outlineVariant, height: 1),
              const SizedBox(height: 16),
              Text(
                '今日已記錄',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              ...widget.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SocialEntryTile(entry: e),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SocialEntryTile extends StatelessWidget {
  final _SocialEntry entry;

  const _SocialEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeLabel =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              entry.feeling.emoji,
              style: const TextStyle(fontSize: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.person,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      timeLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(entry.summary, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 26, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _QuickActionsGrid extends StatelessWidget {
  final List<_QuickAction> actions;

  const _QuickActionsGrid({required this.actions});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: actions.map((a) => _QuickActionTile(action: a)).toList(),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction action;

  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: action.color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  action.icon,
                  size: 24,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(
                action.label,
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailySuggestionCard extends StatelessWidget {
  final VoidCallback onReachOut;

  const _DailySuggestionCard({required this.onReachOut});

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
                  Icons.wb_twilight_outlined,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text('今日小建議', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.format_quote_rounded,
                      size: 26, color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '「早晨，諗起你。」',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.bolt_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '一句已經夠。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReachOut,
                icon: const Icon(Icons.people_outline, size: 24),
                label: const Text('睇下可以聯絡邊個'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoundaryReminderCard extends StatelessWidget {
  final VoidCallback onEmergency;

  const _BoundaryReminderCard({required this.onEmergency});

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
                  Icons.shield_outlined,
                  size: 26,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text('溫馨提示', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.emergency_outlined,
                      size: 24, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '緊急情況　→　撥 999',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onEmergency,
                icon: const Icon(Icons.health_and_safety_outlined, size: 24),
                label: const Text('打開即時支援'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

enum _Feeling {
  warm('溫暖', '🤗'),
  ok('一般', '🙂'),
  awkward('有少少尷尬', '😅'),
  drained('攰', '😮‍💨'),
  lonely('仲係孤獨', '😔');

  final String label;
  final String emoji;

  const _Feeling(this.label, this.emoji);
}

class _SocialEntry {
  final String person;
  final String summary;
  final _Feeling feeling;
  final TimeOfDay time;

  _SocialEntry({
    required this.person,
    required this.summary,
    required this.feeling,
    required this.time,
  });
}
