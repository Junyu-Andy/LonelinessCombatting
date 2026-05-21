/// Multi-step intake questionnaire (6-part).
///
/// Gate order in ConsentGate:
///   1. ConsentPage (functional data consent)
///   2. IntakeFlowPage (THIS — 6-part intake)
///   3. AgentOnboardingPage (agent variant + interests)
///   4. MainShell
///
/// Pages in the PageView:
///   0: Welcome intro
///   1: Part 1 — Goals + loneliness timings
///   2: Part 2 — Important people + reconnect people
///   3: Part 3 — Typical day + on-my-mind
///   4: Part 4 — Activities + topics
///   5: Part 5 — Life chapters + avoid topics
///   6: Part 6 — Input mode + preferred times
///   7: Done confirmation

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/intake_repository.dart';
import '../../data/intake_response.dart';

class IntakeFlowPage extends StatefulWidget {
  final VoidCallback onComplete;

  const IntakeFlowPage({super.key, required this.onComplete});

  @override
  State<IntakeFlowPage> createState() => _IntakeFlowPageState();
}

class _IntakeFlowPageState extends State<IntakeFlowPage> {
  final _pageController = PageController();
  final _repo = IntakeRepository();

  // Current page index (0-7)
  int _currentPage = 0;
  bool _saving = false;

  // Part 1 state
  final Set<String> _mainGoals = {};
  String _mainGoalOtherText = '';
  final Set<String> _lonelinessTimings = {};

  // Part 2 state
  final List<Map<String, String>> _importantPeople = [];
  final List<Map<String, String>> _reconnectPeople = [];

  // Part 3 state
  String _typicalMorning = '';
  String _typicalAfternoon = '';
  String _typicalEvening = '';
  String _onMind = '';

  // Part 4 state
  final Set<String> _activities = {};
  String _activitiesOtherText = '';
  final Set<String> _topics = {};
  String _topicsOtherText = '';

  // Part 5 state
  final Set<String> _lifeChapters = {};
  String _avoidTopics = '';

  // Part 6 state
  String? _inputMode;
  final Set<String> _preferredTimes = {};

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _canProceedPage1 => _mainGoals.isNotEmpty;
  bool get _canProceedPage6 => _inputMode != null;

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    setState(() => _currentPage = page);
  }

  Future<void> _saveAndContinue(int completedPart) async {
    final profile = AppSettingsScope.read(context).profile;
    if (profile != null) {
      await _repo.markPartDone(profile.uid, completedPart);
    }
    _goToPage(_currentPage + 1);
  }

  Future<void> _complete() async {
    setState(() => _saving = true);
    final profile = AppSettingsScope.read(context).profile;
    if (profile != null) {
      final now = DateTime.now();
      final response = IntakeResponse(
        mainGoals: _mainGoals.toList(),
        mainGoalOther: _mainGoalOtherText.trim().isEmpty ? null : _mainGoalOtherText.trim(),
        lonelinessTimings: _lonelinessTimings.isEmpty ? null : _lonelinessTimings.toList(),
        importantPeople: _importantPeople.isEmpty
            ? null
            : _importantPeople
                .map((m) => PersonEntry(
                      name: m['name'] ?? '',
                      relationship: m['relationship'] ?? '',
                      extra: m['extra'],
                    ))
                .toList(),
        reconnectPeople: _reconnectPeople.isEmpty
            ? null
            : _reconnectPeople
                .map((m) => PersonEntry(
                      name: m['name'] ?? '',
                      relationship: m['relationship'] ?? '',
                      extra: m['extra'],
                    ))
                .toList(),
        typicalMorning: _typicalMorning.trim().isEmpty ? null : _typicalMorning.trim(),
        typicalAfternoon: _typicalAfternoon.trim().isEmpty ? null : _typicalAfternoon.trim(),
        typicalEvening: _typicalEvening.trim().isEmpty ? null : _typicalEvening.trim(),
        onMind: _onMind.trim().isEmpty ? null : _onMind.trim(),
        activities: _activities.isEmpty ? null : _activities.toList(),
        activitiesOther: _activitiesOtherText.trim().isEmpty ? null : _activitiesOtherText.trim(),
        topics: _topics.isEmpty ? null : _topics.toList(),
        topicsOther: _topicsOtherText.trim().isEmpty ? null : _topicsOtherText.trim(),
        lifeChapters: _lifeChapters.isEmpty ? null : _lifeChapters.toList(),
        avoidTopics: _avoidTopics.trim().isEmpty ? null : _avoidTopics.trim(),
        inputMode: _inputMode ?? IntakeOptions.inputUnsure,
        preferredTimes: _preferredTimes.isEmpty ? null : _preferredTimes.toList(),
        createdAt: now,
        updatedAt: now,
        completedParts: {1, 2, 3, 4, 5, 6},
        allCompleted: true,
      );
      await _repo.save(profile.uid, response);

      // Update profile with key fields
      final auth = AuthServiceScope.of(context);
      await auth.updateProfile(profile.copyWith(
        hasCompletedIntake: true,
        avoidTopics: response.avoidTopics,
        inputMode: response.inputMode,
        preferredTimes: response.preferredTimes,
      ));
      final settings = AppSettingsScope.read(context);
      settings.profile = profile.copyWith(
        hasCompletedIntake: true,
        avoidTopics: response.avoidTopics,
        inputMode: response.inputMode,
        preferredTimes: response.preferredTimes,
      );
    }
    setState(() => _saving = false);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (i) => setState(() => _currentPage = i),
          children: [
            _WelcomePage(onStart: () => _goToPage(1)),
            _Part1Page(
              selectedGoals: _mainGoals,
              otherText: _mainGoalOtherText,
              selectedTimings: _lonelinessTimings,
              canProceed: _canProceedPage1,
              onGoalToggled: (id) => setState(() {
                if (_mainGoals.contains(id)) {
                  _mainGoals.remove(id);
                } else {
                  _mainGoals.add(id);
                }
              }),
              onOtherTextChanged: (t) => setState(() => _mainGoalOtherText = t),
              onTimingToggled: (id) => setState(() {
                if (_lonelinessTimings.contains(id)) {
                  _lonelinessTimings.remove(id);
                } else {
                  _lonelinessTimings.add(id);
                }
              }),
              onNext: () => _saveAndContinue(1),
              onSkipTimings: () => _saveAndContinue(1),
            ),
            _Part2Page(
              importantPeople: _importantPeople,
              reconnectPeople: _reconnectPeople,
              onImportantPersonAdded: (p) => setState(() => _importantPeople.add(p)),
              onImportantPersonRemoved: (i) => setState(() => _importantPeople.removeAt(i)),
              onReconnectPersonAdded: (p) => setState(() => _reconnectPeople.add(p)),
              onReconnectPersonRemoved: (i) => setState(() => _reconnectPeople.removeAt(i)),
              onNext: () => _saveAndContinue(2),
              onSkip: () => _saveAndContinue(2),
            ),
            _Part3Page(
              morning: _typicalMorning,
              afternoon: _typicalAfternoon,
              evening: _typicalEvening,
              onMind: _onMind,
              onMorningChanged: (t) => setState(() => _typicalMorning = t),
              onAfternoonChanged: (t) => setState(() => _typicalAfternoon = t),
              onEveningChanged: (t) => setState(() => _typicalEvening = t),
              onOnMindChanged: (t) => setState(() => _onMind = t),
              onNext: () => _saveAndContinue(3),
              onSkip: () => _saveAndContinue(3),
            ),
            _Part4Page(
              selectedActivities: _activities,
              activitiesOther: _activitiesOtherText,
              selectedTopics: _topics,
              topicsOther: _topicsOtherText,
              onActivityToggled: (id) => setState(() {
                if (_activities.contains(id)) {
                  _activities.remove(id);
                } else {
                  _activities.add(id);
                }
              }),
              onActivitiesOtherChanged: (t) => setState(() => _activitiesOtherText = t),
              onTopicToggled: (id) => setState(() {
                if (_topics.contains(id)) {
                  _topics.remove(id);
                } else {
                  _topics.add(id);
                }
              }),
              onTopicsOtherChanged: (t) => setState(() => _topicsOtherText = t),
              onNext: () => _saveAndContinue(4),
              onSkip: () => _saveAndContinue(4),
            ),
            _Part5Page(
              selectedChapters: _lifeChapters,
              avoidTopics: _avoidTopics,
              onChapterToggled: (id) => setState(() {
                if (_lifeChapters.contains(id)) {
                  _lifeChapters.remove(id);
                } else {
                  _lifeChapters.add(id);
                }
              }),
              onAvoidTopicsChanged: (t) => setState(() => _avoidTopics = t),
              onNext: () => _saveAndContinue(5),
              onSkip: () => _saveAndContinue(5),
            ),
            _Part6Page(
              selectedInputMode: _inputMode,
              selectedTimes: _preferredTimes,
              canProceed: _canProceedPage6,
              onInputModeSelected: (id) => setState(() => _inputMode = id),
              onTimeToggled: (id) => setState(() {
                if (_preferredTimes.contains(id)) {
                  _preferredTimes.remove(id);
                } else {
                  _preferredTimes.add(id);
                }
              }),
              onNext: () => _saveAndContinue(6),
            ),
            _DonePage(
              saving: _saving,
              onComplete: _complete,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress indicator widget (Step X of 6)
// ---------------------------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  final int step; // 1–6
  const _StepIndicator({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第 $step 步，共 6 步',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: step / 6,
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared multi-select chip widget
// ---------------------------------------------------------------------------

class _ChipGroup extends StatelessWidget {
  final List<(String, String)> options; // (id, label)
  final Set<String> selected;
  final ValueChanged<String> onToggled;

  const _ChipGroup({
    required this.options,
    required this.selected,
    required this.onToggled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((opt) {
        final isSelected = selected.contains(opt.$1);
        return GestureDetector(
          onTap: () => onToggled(opt.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Text(
              opt.$2,
              style: TextStyle(
                fontSize: 17,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Single-select radio chip widget
// ---------------------------------------------------------------------------

class _RadioChipGroup extends StatelessWidget {
  final List<(String, String)> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _RadioChipGroup({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: options.map((opt) {
        final isSelected = selected == opt.$1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => onSelected(opt.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      opt.$2,
                      style: TextStyle(
                        fontSize: 17,
                        color: theme.colorScheme.onSurface,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 0: Welcome intro
// ---------------------------------------------------------------------------

class _WelcomePage extends StatelessWidget {
  final VoidCallback onStart;
  const _WelcomePage({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Icon(Icons.waving_hand_rounded,
              size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            '你好！我哋好高興見到你。',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '喺正式開始前，想多了解你一啲。大約需要 10-15 分鐘。',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 18,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '你可以隨時跳過唔想答嘅問題。所有資料只會用嚟改善你嘅使用體驗。',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 17,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              child: const Text('開始'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 1: Part 1 — Goals + loneliness timings
// ---------------------------------------------------------------------------

class _Part1Page extends StatelessWidget {
  final Set<String> selectedGoals;
  final String otherText;
  final Set<String> selectedTimings;
  final bool canProceed;
  final ValueChanged<String> onGoalToggled;
  final ValueChanged<String> onOtherTextChanged;
  final ValueChanged<String> onTimingToggled;
  final VoidCallback onNext;
  final VoidCallback onSkipTimings;

  const _Part1Page({
    required this.selectedGoals,
    required this.otherText,
    required this.selectedTimings,
    required this.canProceed,
    required this.onGoalToggled,
    required this.onOtherTextChanged,
    required this.onTimingToggled,
    required this.onNext,
    required this.onSkipTimings,
  });

  static const _goalOptions = <(String, String)>[
    (IntakeOptions.mainGoalCompanionship, '有人可以日日同我傾下偈'),
    (IntakeOptions.mainGoalEmotionalOutlet, '一個可以講下自己感受嘅地方'),
    (IntakeOptions.mainGoalReconnect, '一啲可以幫我同屋企人或者朋友重新聯絡嘅辦法'),
    (IntakeOptions.mainGoalLearning, '學下新嘢'),
    (IntakeOptions.mainGoalShareMemories, '分享自己嘅回憶或者人生經歷'),
    (IntakeOptions.mainGoalCurious, '純粹好奇，試下睇下'),
    (IntakeOptions.mainGoalOther, '其他（請寫低）'),
  ];

  static const _timingOptions = <(String, String)>[
    (IntakeOptions.timingMornings, '早上'),
    (IntakeOptions.timingAfternoons, '下晝'),
    (IntakeOptions.timingEvenings, '夜晚'),
    (IntakeOptions.timingNights, '夜深'),
    (IntakeOptions.timingWeekends, '週末'),
    (IntakeOptions.timingAfterMealsAlone, '自己食完飯之後'),
    (IntakeOptions.timingFestivals, '節日'),
    (IntakeOptions.timingVaries, '冇固定時間'),
    (IntakeOptions.timingOther, '其他'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        const _StepIndicator(step: 1),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '你主要想從呢個 app 得到啲乜？',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '必填',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '可以揀多過一個',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 16),
        _ChipGroup(
          options: _goalOptions,
          selected: selectedGoals,
          onToggled: onGoalToggled,
        ),
        if (selectedGoals.contains(IntakeOptions.mainGoalOther)) ...[
          const SizedBox(height: 12),
          TextField(
            onChanged: onOtherTextChanged,
            maxLines: 3,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(
              hintText: '請寫低你嘅其他目的…',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(14),
            ),
          ),
        ],
        const SizedBox(height: 32),
        Text(
          '你通常幾時會覺得孤單？',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '（可選 · 可以跳過）',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 16),
        _ChipGroup(
          options: _timingOptions,
          selected: selectedTimings,
          onToggled: onTimingToggled,
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onSkipTimings,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontSize: 17),
                ),
                child: const Text('跳過'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: canProceed ? onNext : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                child: const Text('儲存並繼續'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 2: Part 2 — Important people + reconnect people
// ---------------------------------------------------------------------------

class _Part2Page extends StatelessWidget {
  final List<Map<String, String>> importantPeople;
  final List<Map<String, String>> reconnectPeople;
  final ValueChanged<Map<String, String>> onImportantPersonAdded;
  final ValueChanged<int> onImportantPersonRemoved;
  final ValueChanged<Map<String, String>> onReconnectPersonAdded;
  final ValueChanged<int> onReconnectPersonRemoved;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _Part2Page({
    required this.importantPeople,
    required this.reconnectPeople,
    required this.onImportantPersonAdded,
    required this.onImportantPersonRemoved,
    required this.onReconnectPersonAdded,
    required this.onReconnectPersonRemoved,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        const _StepIndicator(step: 2),
        const SizedBox(height: 24),
        Text(
          '生命中重要嘅人',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '你最重視嘅人係邊幾個？（最多 5 位，可以跳過）',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        _PersonTable(
          people: importantPeople,
          extraLabel: '聯絡頻率',
          onRemove: onImportantPersonRemoved,
        ),
        if (importantPeople.length < 5)
          _AddPersonButton(
            label: '+ 加一位重要嘅人',
            extraLabel: '聯絡頻率（可選）',
            onAdd: onImportantPersonAdded,
          ),
        const SizedBox(height: 28),
        Text(
          '想重新聯絡嘅人',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '有冇人你希望可以重拾聯絡？（最多 3 位，可以跳過）',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        _PersonTable(
          people: reconnectPeople,
          extraLabel: '阻礙原因',
          onRemove: onReconnectPersonRemoved,
        ),
        if (reconnectPeople.length < 3)
          _AddPersonButton(
            label: '+ 加一位想聯絡嘅人',
            extraLabel: '係咩令你唔容易聯絡？（可選）',
            onAdd: onReconnectPersonAdded,
          ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onSkip,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontSize: 17),
                ),
                child: const Text('跳過'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                child: const Text('儲存並繼續'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PersonTable extends StatelessWidget {
  final List<Map<String, String>> people;
  final String extraLabel;
  final ValueChanged<int> onRemove;

  const _PersonTable({
    required this.people,
    required this.extraLabel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      children: people.asMap().entries.map((e) {
        final i = e.key;
        final p = e.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['name'] ?? '',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      if ((p['relationship'] ?? '').isNotEmpty)
                        Text(p['relationship']!,
                            style: TextStyle(
                                fontSize: 15,
                                color: theme.colorScheme.onSurfaceVariant)),
                      if ((p['extra'] ?? '').isNotEmpty)
                        Text('$extraLabel: ${p['extra']}',
                            style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => onRemove(i),
                  iconSize: 26,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AddPersonButton extends StatelessWidget {
  final String label;
  final String extraLabel;
  final ValueChanged<Map<String, String>> onAdd;

  const _AddPersonButton({
    required this.label,
    required this.extraLabel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => _showAddDialog(context),
      style: TextButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        textStyle: const TextStyle(fontSize: 17),
      ),
      child: Text(label),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final relCtrl = TextEditingController();
    final extraCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加一個人', style: TextStyle(fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '姓名 / 稱呼',
                labelStyle: TextStyle(fontSize: 16),
              ),
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relCtrl,
              decoration: const InputDecoration(
                labelText: '關係（例如：女兒、舊朋友）',
                labelStyle: TextStyle(fontSize: 16),
              ),
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: extraCtrl,
              decoration: InputDecoration(
                labelText: extraLabel,
                labelStyle: const TextStyle(fontSize: 16),
              ),
              style: const TextStyle(fontSize: 17),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(fontSize: 16)),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop({
                'name': nameCtrl.text.trim(),
                'relationship': relCtrl.text.trim(),
                'extra': extraCtrl.text.trim(),
              });
            },
            child: const Text('加入', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    if (result != null) onAdd(result);
  }
}

// ---------------------------------------------------------------------------
// Page 3: Part 3 — Typical day + on my mind
// ---------------------------------------------------------------------------

class _Part3Page extends StatelessWidget {
  final String morning;
  final String afternoon;
  final String evening;
  final String onMind;
  final ValueChanged<String> onMorningChanged;
  final ValueChanged<String> onAfternoonChanged;
  final ValueChanged<String> onEveningChanged;
  final ValueChanged<String> onOnMindChanged;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _Part3Page({
    required this.morning,
    required this.afternoon,
    required this.evening,
    required this.onMind,
    required this.onMorningChanged,
    required this.onAfternoonChanged,
    required this.onEveningChanged,
    required this.onOnMindChanged,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        const _StepIndicator(step: 3),
        const SizedBox(height: 24),
        Text(
          '你平時係點過一日？',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '（可選 · 可以跳過）',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 20),
        _DayPartField(
          icon: Icons.wb_sunny_outlined,
          label: '早上通常做咩？',
          initialValue: morning,
          onChanged: onMorningChanged,
        ),
        const SizedBox(height: 14),
        _DayPartField(
          icon: Icons.wb_cloudy_outlined,
          label: '下晝通常做咩？',
          initialValue: afternoon,
          onChanged: onAfternoonChanged,
        ),
        const SizedBox(height: 14),
        _DayPartField(
          icon: Icons.nights_stay_outlined,
          label: '夜晚通常做咩？',
          initialValue: evening,
          onChanged: onEveningChanged,
        ),
        const SizedBox(height: 28),
        Text(
          '而家係咩喺你心入面？',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '唔一定要答，係可選嘅。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: onOnMindChanged,
          maxLines: 4,
          style: const TextStyle(fontSize: 17),
          decoration: const InputDecoration(
            hintText: '有咩想講都可以寫喺度…',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onSkip,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontSize: 17),
                ),
                child: const Text('跳過'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                child: const Text('儲存並繼續'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DayPartField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  const _DayPartField({
    required this.icon,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, right: 10),
          child: Icon(icon, size: 28, color: theme.colorScheme.primary),
        ),
        Expanded(
          child: TextField(
            onChanged: onChanged,
            maxLines: 2,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontSize: 16),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 4: Part 4 — Activities + topics
// ---------------------------------------------------------------------------

class _Part4Page extends StatelessWidget {
  final Set<String> selectedActivities;
  final String activitiesOther;
  final Set<String> selectedTopics;
  final String topicsOther;
  final ValueChanged<String> onActivityToggled;
  final ValueChanged<String> onActivitiesOtherChanged;
  final ValueChanged<String> onTopicToggled;
  final ValueChanged<String> onTopicsOtherChanged;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _Part4Page({
    required this.selectedActivities,
    required this.activitiesOther,
    required this.selectedTopics,
    required this.topicsOther,
    required this.onActivityToggled,
    required this.onActivitiesOtherChanged,
    required this.onTopicToggled,
    required this.onTopicsOtherChanged,
    required this.onNext,
    required this.onSkip,
  });

  static const _activityOptions = <(String, String)>[
    (IntakeOptions.actTv, '睇電視睇劇'),
    (IntakeOptions.actRadio, '聽收音機'),
    (IntakeOptions.actReading, '睇報紙睇書'),
    (IntakeOptions.actMahjong, '打麻雀玩啤牌'),
    (IntakeOptions.actTaichi, '打太極晨運'),
    (IntakeOptions.actWalking, '散步行山'),
    (IntakeOptions.actGardening, '種花種菜照顧植物'),
    (IntakeOptions.actCooking, '煮嘢食'),
    (IntakeOptions.actReligious, '宗教活動'),
    (IntakeOptions.actVolunteering, '做義工'),
    (IntakeOptions.actDining, '同朋友飲茶食飯'),
    (IntakeOptions.actGrandkids, '同孫仔孫女玩'),
    (IntakeOptions.actMusic, '聽歌唱歌'),
    (IntakeOptions.actCrafts, '手工'),
    (IntakeOptions.actOther, '其他'),
  ];

  static const _topicOptions = <(String, String)>[
    (IntakeOptions.topicHkHistory, '香港舊時嘅嘢香港歷史'),
    (IntakeOptions.topicFood, '飲食煮餸'),
    (IntakeOptions.topicFamilyStories, '屋企人嘅故事'),
    (IntakeOptions.topicNature, '種植動植物'),
    (IntakeOptions.topicMusicFilm, '你嗰個年代嘅音樂戲曲電影'),
    (IntakeOptions.topicHealth, '健康養生'),
    (IntakeOptions.topicCurrentEvents, '時事新聞'),
    (IntakeOptions.topicReligion, '宗教信仰人生價值'),
    (IntakeOptions.topicTravel, '旅行'),
    (IntakeOptions.topicSports, '運動'),
    (IntakeOptions.topicOther, '其他'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        const _StepIndicator(step: 4),
        const SizedBox(height: 24),
        Text(
          '你平時鍾意做啲咩消遣？',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '（可選 · 可以跳過）',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 16),
        _ChipGroup(
          options: _activityOptions,
          selected: selectedActivities,
          onToggled: onActivityToggled,
        ),
        if (selectedActivities.contains(IntakeOptions.actOther)) ...[
          const SizedBox(height: 12),
          TextField(
            onChanged: onActivitiesOtherChanged,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(
              hintText: '請寫低其他消遣…',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(14),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Text(
          '你有興趣講開邊啲話題？',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '（可選 · 可以跳過）',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 16),
        _ChipGroup(
          options: _topicOptions,
          selected: selectedTopics,
          onToggled: onTopicToggled,
        ),
        if (selectedTopics.contains(IntakeOptions.topicOther)) ...[
          const SizedBox(height: 12),
          TextField(
            onChanged: onTopicsOtherChanged,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(
              hintText: '請寫低其他話題…',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(14),
            ),
          ),
        ],
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onSkip,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontSize: 17),
                ),
                child: const Text('跳過'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                child: const Text('儲存並繼續'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 5: Part 5 — Life chapters + avoid topics
// ---------------------------------------------------------------------------

class _Part5Page extends StatelessWidget {
  final Set<String> selectedChapters;
  final String avoidTopics;
  final ValueChanged<String> onChapterToggled;
  final ValueChanged<String> onAvoidTopicsChanged;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _Part5Page({
    required this.selectedChapters,
    required this.avoidTopics,
    required this.onChapterToggled,
    required this.onAvoidTopicsChanged,
    required this.onNext,
    required this.onSkip,
  });

  static const _chapterOptions = <(String, String)>[
    (IntakeOptions.chapterChildhood, '細個嘅時候'),
    (IntakeOptions.chapterSchool, '讀書嘅日子'),
    (IntakeOptions.chapterFirstJob, '出嚟做嘢返工嘅日子'),
    (IntakeOptions.chapterMarriage, '拍拖結婚'),
    (IntakeOptions.chapterRaisingKids, '湊仔女嘅日子'),
    (IntakeOptions.chapterMoves, '搬屋移民搬區'),
    (IntakeOptions.chapterHkMilestones, '香港大事'),
    (IntakeOptions.chapterHobbiesDeveloped, '呢啲年發展嘅興趣或者技能'),
    (IntakeOptions.chapterTravel, '旅行經驗'),
    (IntakeOptions.chapterPresentFocus, '我寧願講返而家唔太想再諗以前'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        const _StepIndicator(step: 5),
        const SizedBox(height: 24),
        Text(
          '你想傾下人生嘅邊個階段？',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '（可選 · 可以跳過）',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 16),
        _ChipGroup(
          options: _chapterOptions,
          selected: selectedChapters,
          onToggled: onChapterToggled,
        ),
        const SizedBox(height: 28),
        Text(
          '有冇唔想提起嘅話題？',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '係可選嘅。你寫落嘅，我哋嘅 AI 都唔會主動提起。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: onAvoidTopicsChanged,
          maxLines: 4,
          style: const TextStyle(fontSize: 17),
          decoration: const InputDecoration(
            hintText: '例如：某啲家庭事，或者某段時期…',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onSkip,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontSize: 17),
                ),
                child: const Text('跳過'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                child: const Text('儲存並繼續'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 6: Part 6 — Input mode + preferred times
// ---------------------------------------------------------------------------

class _Part6Page extends StatelessWidget {
  final String? selectedInputMode;
  final Set<String> selectedTimes;
  final bool canProceed;
  final ValueChanged<String> onInputModeSelected;
  final ValueChanged<String> onTimeToggled;
  final VoidCallback onNext;

  const _Part6Page({
    required this.selectedInputMode,
    required this.selectedTimes,
    required this.canProceed,
    required this.onInputModeSelected,
    required this.onTimeToggled,
    required this.onNext,
  });

  static const _inputModeOptions = <(String, String)>[
    (IntakeOptions.inputTyping, '主要打字'),
    (IntakeOptions.inputVoice, '主要用語音'),
    (IntakeOptions.inputBoth, '兩樣都差唔多'),
    (IntakeOptions.inputUnsure, '暫時未知'),
  ];

  static const _timeOptions = <(String, String)>[
    (IntakeOptions.timeMorning, '朝早'),
    (IntakeOptions.timeMidday, '晏晝'),
    (IntakeOptions.timeAfternoon, '下晝'),
    (IntakeOptions.timeEvening, '夜晚'),
    (IntakeOptions.timeBeforeBed, '瞓覺之前'),
    (IntakeOptions.timeNoRoutine, '冇固定時間'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        const _StepIndicator(step: 6),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '你喜歡點樣同 AI 溝通？',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '必填',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _RadioChipGroup(
          options: _inputModeOptions,
          selected: selectedInputMode,
          onSelected: onInputModeSelected,
        ),
        const SizedBox(height: 28),
        Text(
          '你通常幾時最方便用呢個 app？',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '（可選 · 可以跳過）',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 16),
        _ChipGroup(
          options: _timeOptions,
          selected: selectedTimes,
          onToggled: onTimeToggled,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canProceed ? onNext : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            child: const Text('下一步'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 7: Done confirmation
// ---------------------------------------------------------------------------

class _DonePage extends StatelessWidget {
  final bool saving;
  final VoidCallback onComplete;

  const _DonePage({required this.saving, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded,
              size: 80, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            '多謝你答晒所有問題！',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            '我哋已經為你度身設定好一切。\n而家可以正式開始喇！',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 18,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: saving ? null : onComplete,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              child: saving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('開始使用'),
            ),
          ),
        ],
      ),
    );
  }
}
