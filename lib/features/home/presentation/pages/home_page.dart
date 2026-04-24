import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../analytics/presentation/analytics_scope.dart';

/// Dashboard — the "review" surface. Shows how long the user has
/// been with the app, today's mood, today's social log (empty by
/// default, editable), and a small retro-stats card.
///
/// Quick actions / daily suggestions have moved to the Daily tab
/// and All Features tab respectively.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final List<_SocialEntry> _todayEntries;
  bool _entriesInitialised = false;
  // Hardcoded for demo. Later: fetch from Firestore user.createdAt.
  final DateTime _appStartDate =
      DateTime.now().subtract(const Duration(days: 0));

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
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final daysUsed = now.difference(_appStartDate).inDays + 1;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _GreetingHero(now: now, appTitle: l10n.appTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              children: [
                _AppUsageCard(days: daysUsed),
                const SizedBox(height: 20),
                const _TodayVibeCard(mood: 3, loneliness: 4),
                const SizedBox(height: 20),
                _SocialLogCard(
                  entries: _todayEntries,
                  onAdd: _addEntry,
                  onEdit: _editEntry,
                ),
                const SizedBox(height: 20),
                _ReviewCard(entries: _todayEntries),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Greeting hero ───────────────────────────────────────────────

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
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            Color.alphaBlend(
              theme.colorScheme.tertiary.withValues(alpha: 0.6),
              theme.colorScheme.primary.withValues(alpha: 0.78),
            ),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: 120×120 illustration slot (placeholder for now)
          Container(
            width: 108,
            height: 108,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, size: 56, color: Colors.white),
          ),
          const SizedBox(width: 16),
          // Right: greeting + subtitle + HKU tag
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
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEn
                      ? '$appTitle is with you.'
                      : '$appTitle 陪你。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'HKU · DSE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
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

// ─── App usage days ──────────────────────────────────────────────

class _AppUsageCard extends StatelessWidget {
  final int days;
  const _AppUsageCard({required this.days});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Text('🎉', style: theme.textTheme.headlineSmall),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                children: [
                  TextSpan(text: isEn ? 'You\'ve been here ' : '你已經用咗呢個 App '),
                  TextSpan(
                    text: '$days',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                      fontSize: 22,
                    ),
                  ),
                  TextSpan(
                    text: isEn
                        ? (days == 1 ? ' day' : ' days')
                        : ' 日',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Today's vibe (mood + loneliness only) ───────────────────────

class _TodayVibeCard extends StatelessWidget {
  final int mood;
  final int loneliness;

  const _TodayVibeCard({
    required this.mood,
    required this.loneliness,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
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
                  child: Text(
                    isEn ? 'Today\'s Status' : '今日狀態',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _VibeBar(label: isEn ? 'Mood' : '心情', value: mood),
            const SizedBox(height: 12),
            _VibeBar(
                label: isEn ? 'Loneliness' : '孤獨感', value: loneliness),
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

// ─── Social log card ─────────────────────────────────────────────

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

  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (mounted && status == SpeechToText.doneStatus) {
          setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening({required bool isEn}) async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    if (!_speechAvailable) return;
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _summaryController.text = result.recognizedWords;
          _summaryController.selection = TextSelection.collapsed(
            offset: _summaryController.text.length,
          );
        });
      },
      localeId: isEn ? 'en-US' : 'zh-HK',
    );
  }

  @override
  void dispose() {
    _speech.cancel();
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
              ? 'You haven\'t written anything yet!'
              : '你仲未寫喎！'),
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
                const SizedBox(width: 4),
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
            if (!_isExpanded && widget.entries.isEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEn
                          ? 'You haven\'t written anything yet!'
                          : '你仲未寫喎！'),
                      duration: const Duration(milliseconds: 1800),
                    ),
                  );
                  _openForm();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 22, horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.6),
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
                            ? 'No entries yet\nTap to write down today\'s interaction'
                            : '今日尚未記錄\n點一下寫低今日嘅社交互動',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.75),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_isExpanded) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _personController,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  labelText: isEn ? 'With whom?' : '同邊個？',
                  hintText: isEn ? 'May / Cousin…' : '阿May / 表姐…',
                  prefixIcon: const Icon(Icons.person_outline, size: 24),
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
                  prefixIcon: const Icon(Icons.edit_outlined, size: 24),
                ),
              ),
              if (_speechAvailable) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _toggleListening(isEn: isEn),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isListening
                          ? Colors.red.shade50
                          : theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isListening
                            ? Colors.red.shade300
                            : theme.colorScheme.primaryContainer,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          size: 20,
                          color: _isListening
                              ? Colors.red
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isListening
                              ? (isEn ? 'Listening…' : '聆聽中…')
                              : (isEn ? 'Tap to speak' : '點一下語音輸入'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _isListening
                                ? Colors.red
                                : theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.mood_outlined,
                      size: 20, color: theme.colorScheme.onSurfaceVariant),
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
            if (widget.entries.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(color: theme.colorScheme.outlineVariant, height: 1),
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
    final isEn = Localizations.localeOf(context).languageCode == 'en';
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
            child: Text(entry.feeling.emoji,
                style: const TextStyle(fontSize: 24)),
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
            tooltip: isEn ? 'Edit' : '修改',
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

// ─── Review card (log stats) ─────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final List<_SocialEntry> entries;
  const _ReviewCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    // Hardcoded weekly / total: same as today count until persistence is
    // wired up — the card's shape is what we want to land.
    final todayCount = entries.length;
    final weekCount = entries.length;
    final totalCount = entries.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded,
                    size: 26, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  isEn ? 'Recent Log' : '近期記錄',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: isEn ? 'Today' : '今日',
                    count: todayCount,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    label: isEn ? 'This week' : '本週',
                    count: weekCount,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    label: isEn ? 'All time' : '累計',
                    count: totalCount,
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

class _StatTile extends StatelessWidget {
  final String label;
  final int count;
  const _StatTile({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Models ──────────────────────────────────────────────────────

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
