/// W2/W4 Agent Differentiation assessment page.
///
/// Multi-part tab form:
///   Part A: usage frequency matrix (3 agents × 4 frequency bands)
///   Part B: personality trait rating matrix (4 traits × 3 agents, 1-5)
///   Part C: scenario preference (W4 only, 5 scenarios × 4-option single-select)
///   Part D: free-text response (+ voice input)
///
/// Aligned to Agent_Differentiation_Assessment_Final_v1.0 (2026-06).
///
/// Stores result at `users/{uid}/agent_diff/{auto-id}` with
/// `timepoint: "week2"|"week4"` field (Sprint 1 spec).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../data/agent_diff_response.dart';

class AgentDiffPage extends StatefulWidget {
  /// 2 or 4.
  final int wave;

  const AgentDiffPage({super.key, required this.wave});

  @override
  State<AgentDiffPage> createState() => _AgentDiffPageState();
}

class _AgentDiffPageState extends State<AgentDiffPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Part A: agent → frequency (0-3)
  final Map<String, int> _usageFreq = {
    for (final a in AgentDiffAgents.all) a: 0,
  };

  // Part B: traitId → agentId → rating (1-5)
  final Map<String, Map<String, int>> _personality = {
    for (final t in AgentDiffTraits.all)
      t: {for (final a in AgentDiffAgents.all) a: 0},
  };

  // Part C (W4 only): scenarioId → agentId / 'any'
  final Map<String, String> _function = {};

  // Part D
  final _freeResponseCtrl = TextEditingController();

  bool _saving = false;
  bool _saved = false;

  bool get _isW4 => widget.wave == 4;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _isW4 ? 4 : 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _freeResponseCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    final profile = AppSettingsScope.read(context).profile;
    if (profile != null) {
      try {
        final response = AgentDiffResponse(
          wave: widget.wave,
          usageFreq: Map.from(_usageFreq),
          personality: {
            for (final e in _personality.entries)
              e.key: Map.from(e.value),
          },
          function: _isW4 ? Map.from(_function) : null,
          freeResponse: _freeResponseCtrl.text.trim(),
          answeredAt: DateTime.now(),
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('agent_diff')
            .add(response.toFirestore());
      } catch (_) {
        // Graceful degradation.
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
  }

  /// Short agent labels, with Ah Jan / Ah Bak resolved to the user's chosen
  /// gender variant so a participant who picked 阿伯 never sees 阿珍.
  Map<String, String> _agentLabels(bool isEn) {
    final variant =
        AppSettingsScope.read(context).profile?.ahJanAhBakVariant;
    return {
      AgentDiffAgents.siuYan: isEn ? 'Siu Yan' : '小欣',
      AgentDiffAgents.ahJanAhBak:
          AgentRegistry.ahJanAhBakName(variant, isEn: isEn),
      AgentDiffAgents.tungTung: isEn ? 'Tung Tung' : '通通',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final agentLabels = _agentLabels(isEn);
    final tabs = [
      Tab(text: isEn ? 'A How often' : 'A 使用頻率'),
      Tab(text: isEn ? 'B Personality' : 'B 性格印象'),
      if (_isW4) Tab(text: isEn ? 'C Situations' : 'C 情境偏好'),
      Tab(text: isEn ? 'D Your thoughts' : 'D 你想講'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn
            ? 'Companion check-in (Week ${widget.wave})'
            : '夥伴評估 (第 ${widget.wave} 週)'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PartAView(
            usageFreq: _usageFreq,
            agentLabels: agentLabels,
            onChanged: (agentId, freq) =>
                setState(() => _usageFreq[agentId] = freq),
          ),
          _PartBView(
            personality: _personality,
            agentLabels: agentLabels,
            onChanged: (traitId, agentId, rating) =>
                setState(() => _personality[traitId]![agentId] = rating),
          ),
          if (_isW4)
            _PartCView(
              function: _function,
              agentLabels: agentLabels,
              onChanged: (scenarioId, agentId) =>
                  setState(() => _function[scenarioId] = agentId),
            ),
          _PartDView(
            controller: _freeResponseCtrl,
            saved: _saved,
            saving: _saving,
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Part A: usage frequency matrix
// ---------------------------------------------------------------------------

class _PartAView extends StatelessWidget {
  final Map<String, int> usageFreq;
  final Map<String, String> agentLabels;
  final void Function(String agentId, int freq) onChanged;

  const _PartAView({
    required this.usageFreq,
    required this.agentLabels,
    required this.onChanged,
  });

  static const _freqLabelsZh = ['完全冇', '少過一次', '一至兩次', '三次或以上'];
  static const _freqLabelsEn = ['Not at all', '<1×/wk', '1–2×/wk', '3+×/wk'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final freqLabels = isEn ? _freqLabelsEn : _freqLabelsZh;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'In a typical week over the past 2 weeks, how often did you '
                    'talk with each companion?'
                : '喺過去兩個星期，正常一個禮拜入面，你大約同每個夥伴傾過幾多次？',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
              4: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                children: [
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(isEn ? 'Companion' : '夥伴',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                  ...freqLabels.map(
                    (l) => TableCell(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(l,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
              ...AgentDiffAgents.all.asMap().entries.map((e) {
                final agentId = e.value;
                final label = agentLabels[agentId] ?? agentId;
                final selected = usageFreq[agentId] ?? 0;
                return TableRow(
                  children: [
                    TableCell(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 14),
                        child: Text(label,
                            style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                    ...List.generate(4, (i) {
                      final isSelected = selected == i;
                      return TableCell(
                        child: GestureDetector(
                          onTap: () => onChanged(agentId, i),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.outline,
                                    width: isSelected ? 0 : 1.5,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check,
                                        color: Colors.white, size: 18)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Part B: personality trait rating matrix (1-5)
// ---------------------------------------------------------------------------

class _PartBView extends StatelessWidget {
  final Map<String, Map<String, int>> personality;
  final Map<String, String> agentLabels;
  final void Function(String traitId, String agentId, int rating) onChanged;

  const _PartBView({
    required this.personality,
    required this.agentLabels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'For each statement, rate how much it describes each '
                    'companion (1 = not at all, 5 = very much).'
                : '下面每一句說話，話我哋知佢有幾形容到每個夥伴。'
                    '（1=完全唔似，5=好似）',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          // One trait per block; the 3 companions are stacked VERTICALLY,
          // each on its own full-width row of 5 large buttons — this removes
          // the cramped 3×5 horizontal matrix that overlapped on phones.
          ...AgentDiffTraits.all.map((traitId) {
            final label = (isEn
                    ? AgentDiffTraits.labelsEn[traitId]
                    : AgentDiffTraits.labels[traitId]) ??
                traitId;
            return Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, height: 1.3),
                  ),
                  const SizedBox(height: 14),
                  for (final agentId in AgentDiffAgents.all) ...[
                    _AgentRatingRow(
                      agentLabel: agentLabels[agentId] ?? agentId,
                      selected: personality[traitId]?[agentId] ?? 0,
                      onRate: (rating) => onChanged(traitId, agentId, rating),
                    ),
                    if (agentId != AgentDiffAgents.all.last)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// One companion's 1–5 rating for a single trait: name on the left, five
/// full-width number buttons filling the rest of the row (no overlap).
class _AgentRatingRow extends StatelessWidget {
  final String agentLabel;
  final int selected;
  final ValueChanged<int> onRate;

  const _AgentRatingRow({
    required this.agentLabel,
    required this.selected,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            agentLabel,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              for (var rating = 1; rating <= 5; rating++) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => onRate(rating),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected == rating
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected == rating
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                          width: selected == rating ? 2 : 1.2,
                        ),
                      ),
                      child: Text(
                        '$rating',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: selected == rating
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                if (rating < 5) const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Part C: scenario preference (W4 only)
// ---------------------------------------------------------------------------

class _PartCView extends StatelessWidget {
  final Map<String, String> function;
  final Map<String, String> agentLabels;
  final void Function(String scenarioId, String agentId) onChanged;

  const _PartCView({
    required this.function,
    required this.agentLabels,
    required this.onChanged,
  });

  static const _agentOptions = [
    ...AgentDiffAgents.all,
    'any',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final agentOptionLabels = {
      ...agentLabels,
      'any': isEn ? 'Any of them' : '邊個都得／冇所謂',
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'If you wanted to do the following things, which companion '
                    'would you go to first?'
                : '如果你想做下面呢啲嘢，你會首先搵邊個夥伴？',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ...AgentDiffScenarios.all.map((scenarioId) {
            final label = (isEn
                    ? AgentDiffScenarios.labelsEn[scenarioId]
                    : AgentDiffScenarios.labels[scenarioId]) ??
                scenarioId;
            final selected = function[scenarioId];
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _agentOptions.map((agentId) {
                      final agentLabel =
                          agentOptionLabels[agentId] ?? agentId;
                      final isSelected = selected == agentId;
                      return GestureDetector(
                        onTap: () => onChanged(scenarioId, agentId),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            agentLabel,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Part D: free-text response + submit
// ---------------------------------------------------------------------------

class _PartDView extends StatelessWidget {
  final TextEditingController controller;
  final bool saved;
  final bool saving;
  final VoidCallback onSubmit;

  const _PartDView({
    required this.controller,
    required this.saved,
    required this.saving,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn ? 'Anything else you would like to share?' : '仲有咩想補充？',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isEn
                ? 'Any thoughts, feelings or suggestions about the three companions — you can write them here.'
                : '關於呢三個夥伴，你有咩感受、意見或者建議，都可以寫喺度。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (!saved)
            Row(
              children: [
                VoiceInputButton(
                  prefix: () => controller.text,
                  onText: (t) => controller.text = t,
                ),
                const SizedBox(width: 8),
                Text(
                  isEn ? 'or speak' : '或者用講嘅',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 8,
            enabled: !saved,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              hintText: isEn
                  ? 'Write your thoughts or suggestions here…'
                  : '可以寫低你嘅感受或者建議…',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 24),
          if (saved)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: theme.colorScheme.primary, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEn
                          ? 'Thank you for the check-in! Your responses are saved.'
                          : '多謝你嘅評估！已經儲存。',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : onSubmit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  textStyle:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                child: saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEn ? 'Submit' : '提交評估'),
              ),
            ),
        ],
      ),
    );
  }
}
