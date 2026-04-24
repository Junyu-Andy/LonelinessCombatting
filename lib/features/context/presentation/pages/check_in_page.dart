import 'package:flutter/material.dart';

import '../../../analytics/data/analytics_service.dart';
import '../../../analytics/presentation/analytics_scope.dart';

class CheckInPage extends StatefulWidget {
  const CheckInPage({super.key});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  int _mood = 3;
  int _loneliness = 3;
  int _socialEnergy = 3;
  bool _touched = false;
  AnalyticsService? _analytics;
  final TextEditingController _recentExperienceController =
      TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analytics = AnalyticsScope.of(context);
  }

  @override
  void dispose() {
    if (_touched) {
      _analytics?.logCheckIn(
        mood: _mood,
        loneliness: _loneliness,
        socialEnergy: _socialEnergy,
      );
    }
    _recentExperienceController.dispose();
    super.dispose();
  }

  void _onSliderChange(void Function() mutate) {
    setState(() {
      _touched = true;
      mutate();
    });
  }

  String _scoreLabel(int value, bool isEn) {
    if (isEn) {
      switch (value) {
        case 1: return 'Low';
        case 2: return 'Below avg';
        case 3: return 'Average';
        case 4: return 'Above avg';
        case 5: return 'High';
        default: return '';
      }
    }
    switch (value) {
      case 1: return '低';
      case 2: return '偏低';
      case 3: return '中等';
      case 4: return '偏高';
      case 5: return '高';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Quick Check-in' : '快速 Check-in'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            isEn
                ? 'A few simple steps to tell us how you are feeling today. Just pick the number closest to how you feel.'
                : '用簡單幾個步驟，話畀我哋知你今日嘅狀態。揀最貼近你感覺嘅數字就得。',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          _RatingSection(
            title: isEn ? 'Today\'s Mood' : '今日心情',
            helperLow: isEn ? 'Low' : '低落',
            helperHigh: isEn ? 'Happy' : '開心',
            value: _mood,
            onChanged: (value) => _onSliderChange(() => _mood = value),
          ),
          const SizedBox(height: 24),
          _RatingSection(
            title: isEn ? 'Loneliness Level' : '今日孤獨感',
            helperLow: isEn ? 'Very little' : '好少',
            helperHigh: isEn ? 'Very strong' : '好強',
            value: _loneliness,
            onChanged: (value) => _onSliderChange(() => _loneliness = value),
          ),
          const SizedBox(height: 24),
          _RatingSection(
            title: isEn ? 'Social Energy' : '今日社交能量',
            helperLow: isEn ? 'Drained' : '好攰',
            helperHigh: isEn ? 'Energised' : '有精神',
            value: _socialEnergy,
            onChanged: (value) => _onSliderChange(() => _socialEnergy = value),
          ),
          const SizedBox(height: 28),
          Text(
            isEn ? 'Recent Social Experience' : '最近社交經驗',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _recentExperienceController,
            maxLines: 4,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: isEn
                  ? 'e.g. Exchanged messages with a friend today, but didn\'t really open up.'
                  : '例如：今日同朋友有短訊來往，但未真正傾到心事。',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.summarize_outlined,
                        size: 28,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isEn ? 'Today\'s Summary' : '今日摘要',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SummaryLine(
                    label: isEn ? 'Mood' : '心情',
                    value: _mood,
                    note: _scoreLabel(_mood, isEn),
                  ),
                  const SizedBox(height: 10),
                  _SummaryLine(
                    label: isEn ? 'Loneliness' : '孤獨感',
                    value: _loneliness,
                    note: _scoreLabel(_loneliness, isEn),
                  ),
                  const SizedBox(height: 10),
                  _SummaryLine(
                    label: isEn ? 'Social energy' : '社交能量',
                    value: _socialEnergy,
                    note: _scoreLabel(_socialEnergy, isEn),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _recentExperienceController.text.isEmpty
                        ? (isEn
                            ? 'Recent social experience not filled in.'
                            : '未填寫最近社交經驗。')
                        : _recentExperienceController.text,
                    style: theme.textTheme.bodyLarge,
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

class _RatingSection extends StatelessWidget {
  final String title;
  final String helperLow;
  final String helperHigh;
  final int value;
  final ValueChanged<int> onChanged;

  const _RatingSection({
    required this.title,
    required this.helperLow,
    required this.helperHigh,
    required this.value,
    required this.onChanged,
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
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: List.generate(5, (index) {
                final scoreValue = index + 1;
                final selected = scoreValue == value;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: index == 4 ? 0 : 8),
                    child: _RatingButton(
                      score: scoreValue,
                      selected: selected,
                      onTap: () => onChanged(scoreValue),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(helperLow, style: theme.textTheme.bodyMedium),
                Text(helperHigh, style: theme.textTheme.bodyMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  final int score;
  final bool selected;
  final VoidCallback onTap;

  const _RatingButton({
    required this.score,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected ? theme.colorScheme.primary : Colors.white;
    final fg =
        selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: '$score',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Text(
              '$score',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final int value;
  final String note;

  const _SummaryLine({
    required this.label,
    required this.value,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label: $note',
            style: theme.textTheme.bodyLarge,
          ),
        ),
        Text(
          '$value / 5',
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
