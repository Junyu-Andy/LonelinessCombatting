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
  late final List<_SocialEntry> _todayEntries;
  bool _entriesInitialised = false;

  void _addEntry(_SocialEntry entry) {
    setState(() => _todayEntries.insert(0, entry));
  }

  void _editEntry(int index, _SocialEntry updated) {
    setState(() => _todayEntries[index] = updated);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_entriesInitialised) {
      _entriesInitialised = true;
      _todayEntries = [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
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
            onCheckIn: () => _open(const CheckInPage()),
          ),
          const SizedBox(height: 20),
          _SocialLogCard(
            entries: _todayEntries,
            onAdd: _addEntry,
            onEdit: _editEntry,
          ),
          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.apps_rounded,
            title: isEn ? 'Where to start?' : '想由邊度開始？',
            subtitle: isEn ? 'Pick a feature.' : '揀一個功能。',
          ),
          const SizedBox(height: 14),
          _QuickActionsGrid(
            actions: [
              _QuickAction(
                icon: Icons.favorite_outline,
                label: isEn ? 'Check-in' : '快速 Check-in',
                color: const Color(0xFFFEE2E2),
                onTap: () => _open(const CheckInPage()),
              ),
              _QuickAction(
                icon: Icons.people_outline,
                label: isEn ? 'Social Map' : '社交關係圖',
                color: const Color(0xFFDBEAFE),
                onTap: () => _open(const SocialMapPage()),
              ),
              _QuickAction(
                icon: Icons.forum_outlined,
                label: isEn ? 'Reflect' : '互動反思',
                color: const Color(0xFFE0E7FF),
                onTap: () => _open(const ReflectionPage()),
              ),
              _QuickAction(
                icon: Icons.self_improvement,
                label: isEn ? 'Calm Down' : '靜一靜',
                color: const Color(0xFFD1FAE5),
                onTap: () => _open(const CalmPage()),
              ),
              _QuickAction(
                icon: Icons.lightbulb_outline,
                label: isEn ? 'Activities' : '行動支援',
                color: const Color(0xFFFEF3C7),
                onTap: () => _open(const ActionSupportPage()),
              ),
              _QuickAction(
                icon: Icons.event_note_outlined,
                label: isEn ? 'Follow-up' : '跟進提醒',
                color: const Color(0xFFFCE7F3),
                onTap: () => _open(const FollowUpPage()),
              ),
              _QuickAction(
                icon: Icons.handshake_outlined,
                label: isEn ? 'Community' : '社區資源',
                color: const Color(0xFFCCFBF1),
                onTap: () => _open(const CommunityResourcesPage()),
              ),
              _QuickAction(
                icon: Icons.health_and_safety_outlined,
                label: isEn ? 'Crisis Support' : '即時支援',
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
          FigurePlaceholder(
            description: isEn
                ? 'Illustration: two silhouettes smiling across phones — a short greeting already feels warm.'
                : '插畫：兩個輪廓喺手機兩端微笑，象徵簡短嘅問候已經有溫度。',
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
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final hour = now.hour;
    final String greeting;
    final IconData icon;
    if (hour >= 5 && hour < 11) {
      greeting = isEn ? 'Good morning!' : '早晨！';
      icon = Icons.wb_sunny_outlined;
    } else if (hour >= 11 && hour < 14) {
      greeting = isEn ? 'Good noon!' : '午安！';
      icon = Icons.light_mode_outlined;
    } else if (hour >= 14 && hour < 18) {
      greeting = isEn ? 'Good afternoon' : '下午好';
      icon = Icons.wb_cloudy_outlined;
    } else if (hour >= 18 && hour < 22) {
      greeting = isEn ? 'Good evening' : '夜晚好';
      icon = Icons.nights_stay_outlined;
    } else {
      greeting = isEn ? 'It\'s late — take it easy' : '夜深喇，慢慢嚟';
      icon = Icons.bedtime_outlined;
    }

    final weekdayNames = isEn
        ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final dateLine = isEn
        ? '${weekdayNames[now.weekday - 1]}, ${now.month}/${now.day}'
        : '${now.month} 月 ${now.day} 日　${weekdayNames[now.weekday - 1]}';

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
                  isEn ? 'Pick something you can do right now — $appTitle is with you.' : '揀一件你而家做到嘅事 — $appTitle 陪你。',
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
                isEn ? 'Data and Systems Engineering, HKU' : '數據及系統工程學系',
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
  final VoidCallback onCheckIn;

  const _TodayVibeCard({
    required this.mood,
    required this.loneliness,
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
                  child: Builder(builder: (ctx) {
                    final isEn = Localizations.localeOf(ctx).languageCode == 'en';
                    return Text(isEn ? 'Today\'s Status' : '今日狀態', style: Theme.of(ctx).textTheme.titleLarge);
                  }),
                ),
                TextButton.icon(
                  onPressed: onCheckIn,
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  label: const Text('Check-in'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Builder(builder: (ctx) {
              final isEn = Localizations.localeOf(ctx).languageCode == 'en';
              return Column(
                children: [
                  _VibeBar(label: isEn ? 'Mood' : '心情', value: mood),
                  const SizedBox(height: 12),
                  _VibeBar(label: isEn ? 'Loneliness' : '孤獨感', value: loneliness),
                ],
              );
            }),
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
  final void Function(int index, _SocialEntry updated) onEdit;

  const _SocialLogCard({
    required this.entries,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  State<_SocialLogCard> createState() => _SocialLogCardState();
}

class _SocialLogCardState extends State<_SocialLogCard> {
  final TextEditingController _personController = TextEditingController();
  final TextEditingController _summaryController = TextEditingController();
  _Feeling _feeling = _Feeling.warm;
  bool _isExpanded = false;
  int? _editingIndex;

  @override
  void dispose() {
    _personController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  void _openForm({int? editIndex}) {
    setState(() {
      _isExpanded = true;
      _editingIndex = editIndex;
      if (editIndex != null) {
        final e = widget.entries[editIndex];
        _personController.text = e.person;
        _summaryController.text = e.summary;
        _feeling = e.feeling;
      } else {
        _personController.clear();
        _summaryController.clear();
        _feeling = _Feeling.warm;
      }
    });
  }

  void _closeForm() {
    setState(() {
      _isExpanded = false;
      _editingIndex = null;
    });
    FocusScope.of(context).unfocus();
  }

  void _save() {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final summary = _summaryController.text.trim();
    if (summary.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEn
              ? 'Please write a little about today\'s interaction.'
              : '請寫低少少今日嘅互動再儲存。'),
        ),
      );
      return;
    }
    final hasPerson = _personController.text.trim().isNotEmpty;
    final entry = _SocialEntry(
      person: hasPerson
          ? _personController.text.trim()
          : (isEn ? 'No specific person' : '冇指定對象'),
      summary: summary,
      feeling: _feeling,
      time: TimeOfDay.fromDateTime(DateTime.now()),
    );
    if (_editingIndex != null) {
      widget.onEdit(_editingIndex!, entry);
    } else {
      widget.onAdd(entry);
      AnalyticsScope.of(context).logSocialLogEntry(
        hasPerson: hasPerson,
        summaryLength: summary.length,
        feeling: _feeling.name,
      );
    }
    _closeForm();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(Icons.edit_note_rounded,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isEn ? 'Today\'s Social Log' : '今日社交記錄',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (widget.entries.isNotEmpty)
                  _CountBadge(count: widget.entries.length),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _isExpanded && _editingIndex == null
                        ? Icons.close
                        : Icons.add_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  tooltip: isEn ? 'Add entry' : '新增記錄',
                  onPressed: () {
                    if (_isExpanded && _editingIndex == null) {
                      _closeForm();
                    } else {
                      _openForm();
                    }
                  },
                ),
              ],
            ),

            // Empty state (not expanded, no entries)
            if (!_isExpanded && widget.entries.isEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _openForm,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.edit_outlined,
                          size: 32,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5)),
                      const SizedBox(height: 8),
                      Text(
                        isEn
                            ? 'No entries yet\nWrite down today\'s interaction'
                            : '今日尚未記錄\n寫低今日嘅社交互動吧',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Input form (expanded)
            if (_isExpanded) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _personController,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  labelText: isEn ? 'With whom?' : '同邊個？',
                  hintText: isEn ? 'May / Cousin…' : '阿May / 表姐…',
                  prefixIcon:
                      const Icon(Icons.person_outline, size: 24),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _summaryController,
                maxLines: 3,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  labelText: isEn ? 'What happened?' : '做咗啲乜？',
                  hintText: isEn
                      ? 'Voice message, chatted 5 min…'
                      : '傳語音、傾咗 5 分鐘…',
                  prefixIcon:
                      const Icon(Icons.edit_outlined, size: 24),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.mood_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    isEn ? 'How did it feel?' : '感覺點？',
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
                        Text(f.label(isEn)),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _feeling = f),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined, size: 24),
                      label: Text(_editingIndex != null
                          ? (isEn ? 'Update' : '更新記錄')
                          : (isEn ? 'Save' : '儲存')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _closeForm,
                      child: Text(isEn ? 'Cancel' : '取消'),
                    ),
                  ),
                ],
              ),
            ],

            // Recorded entries
            if (widget.entries.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(
                  color: theme.colorScheme.outlineVariant, height: 1),
              const SizedBox(height: 16),
              Text(
                isEn ? 'Logged today' : '今日已記錄',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              ...widget.entries.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SocialEntryTile(
                    entry: e.value,
                    onEdit: () => _openForm(editIndex: e.key),
                  ),
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
  final VoidCallback onEdit;

  const _SocialEntryTile({required this.entry, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeLabel =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
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
          IconButton(
            icon: Icon(Icons.edit_outlined,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
            tooltip:
                Localizations.localeOf(context).languageCode == 'en'
                    ? 'Edit'
                    : '修改',
            onPressed: onEdit,
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
                Builder(builder: (ctx) {
                  final isEn = Localizations.localeOf(ctx).languageCode == 'en';
                  return Text(isEn ? 'Today\'s Suggestion' : '今日小建議', style: theme.textTheme.titleLarge);
                }),
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
                    child: Builder(builder: (ctx) {
                      final isEn = Localizations.localeOf(ctx).languageCode == 'en';
                      return Text(
                        isEn ? '"Good morning — thinking of you."' : '「早晨，諗起你。」',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }),
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
                  child: Builder(builder: (ctx) {
                    final isEn = Localizations.localeOf(ctx).languageCode == 'en';
                    return Text(
                      isEn ? 'One line is enough.' : '一句已經夠。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReachOut,
                icon: const Icon(Icons.people_outline, size: 24),
                label: Builder(builder: (ctx) {
                  final isEn = Localizations.localeOf(ctx).languageCode == 'en';
                  return Text(isEn ? 'See who you can reach out to' : '睇下可以聯絡邊個');
                }),
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
                Builder(builder: (ctx) {
                  final isEn = Localizations.localeOf(ctx).languageCode == 'en';
                  return Text(isEn ? 'Reminder' : '溫馨提示', style: theme.textTheme.titleLarge);
                }),
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
                    child: Builder(builder: (ctx) {
                      final isEn = Localizations.localeOf(ctx).languageCode == 'en';
                      return Text(
                        isEn ? 'Emergency → Call 999' : '緊急情況　→　撥 999',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      );
                    }),
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
                label: Builder(builder: (ctx) {
                  final isEn = Localizations.localeOf(ctx).languageCode == 'en';
                  return Text(isEn ? 'Open Crisis Support' : '打開即時支援');
                }),
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
  warm('溫暖', 'Warm', '🤗'),
  ok('一般', 'OK', '🙂'),
  awkward('有少少尷尬', 'A bit awkward', '😅'),
  drained('攰', 'Drained', '😮‍💨'),
  lonely('仲係孤獨', 'Still lonely', '😔');

  final String labelZh;
  final String labelEn;
  final String emoji;

  const _Feeling(this.labelZh, this.labelEn, this.emoji);

  String label(bool isEn) => isEn ? labelEn : labelZh;
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
