/// W2/W4 Agent Differentiation assessment page.
///
/// Multi-part tab form:
///   Part A: usage frequency matrix (3 agents × 4 frequency levels)
///   Part B: personality trait rating matrix (5 traits × 3 agents, 1-5)
///   Part C: scenario preference (W4 only, 5 scenarios × 4-option radio)
///   Part D: free-text response
///
/// Stores result at `users/{uid}/agent_diff/{auto-id}` with
/// `timepoint: "week2"|"week4"` field (Sprint 1 spec).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = [
      const Tab(text: 'A 使用頻率'),
      const Tab(text: 'B 性格印象'),
      if (_isW4) const Tab(text: 'C 情境偏好'),
      const Tab(text: 'D 你想講'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('夥伴評估 (第 ${widget.wave} 週)'),
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
            onChanged: (agentId, freq) =>
                setState(() => _usageFreq[agentId] = freq),
          ),
          _PartBView(
            personality: _personality,
            onChanged: (traitId, agentId, rating) =>
                setState(() => _personality[traitId]![agentId] = rating),
          ),
          if (_isW4)
            _PartCView(
              function: _function,
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
  final void Function(String agentId, int freq) onChanged;

  const _PartAView({required this.usageFreq, required this.onChanged});

  static const _freqLabels = ['完全冇用', '少少', '定期', '好頻繁'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '上個月你用咗以下夥伴幾多次？',
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
                  const TableCell(
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('夥伴',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                  ..._freqLabels.map(
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
                final label = AgentDiffAgents.labels[agentId] ?? agentId;
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
  final void Function(String traitId, String agentId, int rating) onChanged;

  const _PartBView({required this.personality, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '請為每個夥伴嘅性格評分（1=完全唔符合，5=非常符合）',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ...AgentDiffTraits.all.map((traitId) {
            final label = AgentDiffTraits.labels[traitId] ?? traitId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: AgentDiffAgents.all.map((agentId) {
                      final agentLabel =
                          AgentDiffAgents.labels[agentId] ?? agentId;
                      final selected = personality[traitId]?[agentId] ?? 0;
                      return Expanded(
                        child: Column(
                          children: [
                            Text(agentLabel,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13)),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(5, (i) {
                                final rating = i + 1;
                                final isSelected = selected == rating;
                                return GestureDetector(
                                  onTap: () =>
                                      onChanged(traitId, agentId, rating),
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 120),
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? theme.colorScheme.primary
                                            : Colors.transparent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.outline,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '$rating',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isSelected
                                                ? Colors.white
                                                : theme
                                                    .colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
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
// Part C: scenario preference (W4 only)
// ---------------------------------------------------------------------------

class _PartCView extends StatelessWidget {
  final Map<String, String> function;
  final void Function(String scenarioId, String agentId) onChanged;

  const _PartCView({required this.function, required this.onChanged});

  static const _agentOptions = [
    ...AgentDiffAgents.all,
    'any',
  ];

  static const _agentOptionLabels = {
    AgentDiffAgents.siuYan: '小欣',
    AgentDiffAgents.ahJanAhBak: '阿珍／阿伯',
    AgentDiffAgents.tungTung: '通通',
    'any': '都係',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '以下情況你會選擇邊個夥伴？',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ...AgentDiffScenarios.all.map((scenarioId) {
            final label = AgentDiffScenarios.labels[scenarioId] ?? scenarioId;
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
                          _agentOptionLabels[agentId] ?? agentId;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '仲有咩想補充？',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '關於呢三個夥伴，你有咩感受、意見或者建議，都可以寫喺度。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 8,
            enabled: !saved,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(
              hintText: '可以寫低你嘅感受或者建議…',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(16),
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
                      '多謝你嘅評估！已經儲存。',
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
                    : const Text('提交評估'),
              ),
            ),
        ],
      ),
    );
  }
}
