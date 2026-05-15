import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../analytics/data/analytics_service.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import 'check_in_shared.dart';

/// M2 — rule-based check-in. No LLM. Six-face mood, three fixed
/// multiple-choice items, optional free-text field that is stored but
/// never sent to the model.
class CheckInArmB extends StatefulWidget {
  const CheckInArmB({super.key});

  @override
  State<CheckInArmB> createState() => _CheckInArmBState();
}

class _CheckInArmBState extends State<CheckInArmB> {
  MoodFace _face = MoodFace.neutral;
  int? _talkedAnswer;
  int? _socialDayAnswer;
  int? _significantEventAnswer;
  final _noteCtrl = TextEditingController();
  bool _saved = false;
  AnalyticsService? _analytics;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analytics = AnalyticsScope.of(context);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Today\'s Check-in' : '今日 Check-in')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text(
              isEn ? 'How are you today?' : '你今日點呀？',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            MoodFacePicker(
              value: _face,
              onChanged: (v) => setState(() => _face = v),
            ),
            const SizedBox(height: 24),
            _MultipleChoice(
              prompt: isEn
                  ? 'Did you talk with anyone today?'
                  : '今日有冇同人傾過偈？',
              options: isEn
                  ? const ['Not at all', 'A little', 'Quite a bit', 'A lot']
                  : const ['冇', '少少', '幾多', '好多'],
              selected: _talkedAnswer,
              onChanged: (v) => setState(() => _talkedAnswer = v),
            ),
            const SizedBox(height: 16),
            _MultipleChoice(
              prompt: isEn
                  ? 'How would you rate your social day?'
                  : '今日嘅社交時間，你會點評價？',
              options: isEn
                  ? const ['Hard', 'So-so', 'OK', 'Good', 'Great']
                  : const ['辛苦', '麻麻', '可以', '幾好', '好好'],
              selected: _socialDayAnswer,
              onChanged: (v) => setState(() => _socialDayAnswer = v),
            ),
            const SizedBox(height: 16),
            _MultipleChoice(
              prompt: isEn
                  ? 'Anything significant today?'
                  : '今日有冇咩特別事？',
              options: isEn
                  ? const ['Nothing', 'A small thing', 'Something big']
                  : const ['冇', '一啲小事', '一件大事'],
              selected: _significantEventAnswer,
              onChanged: (v) => setState(() => _significantEventAnswer = v),
            ),
            const SizedBox(height: 24),
            Text(
              isEn
                  ? 'Anything you want to write down (optional)'
                  : '想寫低啲咩都得（選擇性）',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLines: 4,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: isEn
                    ? 'A line or two, only for you to see.'
                    : '一兩句都得，只係你睇到。',
              ),
            ),
            const SizedBox(height: 24),
            AppButton.primary(
              label: isEn ? 'Save check-in' : '儲存今日 Check-in',
              icon: Icons.check_rounded,
              onPressed: _talkedAnswer != null &&
                      _socialDayAnswer != null &&
                      _significantEventAnswer != null
                  ? _save
                  : null,
            ),
            if (_saved) ...[
              const SizedBox(height: 12),
              Text(
                isEn
                    ? 'Saved. See you tomorrow.'
                    : '收到喇。聽日再見。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _save() {
    final note = _noteCtrl.text.trim();
    final distress = CoreServicesScope.of(context).distress.analyze(note);
    final profile = AppSettingsScope.read(context).profile;
    _analytics?.logCheckIn(
      mood: _face.numericScore,
      // Loneliness + social energy aren't directly captured in Arm B;
      // we proxy them from the social-day rating so the analytics
      // dashboard keeps a comparable column across arms.
      loneliness: _socialDayAnswer == null ? 3 : (5 - (_socialDayAnswer ?? 2)),
      socialEnergy: (_socialDayAnswer ?? 2) + 1,
    );
    if (distress.isEscalation && profile != null) {
      // Arm B safety surface — direct, no LLM in the loop.
      showDialog<void>(
        context: context,
        builder: (_) => _SafetyEscalationDialog(level: distress.level.name),
      );
    }
    setState(() => _saved = true);
  }
}

class _MultipleChoice extends StatelessWidget {
  final String prompt;
  final List<String> options;
  final int? selected;
  final ValueChanged<int> onChanged;
  const _MultipleChoice({
    required this.prompt,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prompt, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(options.length, (i) {
                final isSel = selected == i;
                return ChoiceChip(
                  label: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 6),
                    child: Text(options[i],
                        style: const TextStyle(fontSize: 16)),
                  ),
                  selected: isSel,
                  onSelected: (_) => onChanged(i),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyEscalationDialog extends StatelessWidget {
  final String level;
  const _SafetyEscalationDialog({required this.level});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return AlertDialog(
      title: Text(isEn ? 'Talk to someone' : '搵個人傾傾'),
      content: Text(
        isEn
            ? 'It sounds like today is heavy. You don\'t have to carry it '
                'alone. The Samaritans Hong Kong hotline is 2896 0000.'
            : '聽你咁講，今日有少少辛苦。你唔需要一個人扛。撒瑪利亞會熱線 2896 0000，可以打去傾下。',
        style: const TextStyle(fontSize: 16, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isEn ? 'Close' : '知道'),
        ),
      ],
    );
  }
}
