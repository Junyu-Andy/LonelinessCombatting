import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../action_loop/data/action_plan.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/thought_record.dart';

/// M4 — Cognitive Restructuring, Arm B (rule-based).
///
/// Spec §M4 Arm B flow:
///   1. One static psychoeducation card explaining common patterns
///      (mind-reading / fortune-telling / all-or-nothing).
///   2. On-demand journaling template: thought-type dropdown +
///      three fixed text fields (evidence for / evidence against /
///      alternative).
///   3. "Make a small test" button that hands off to M7 (rule-based)
///      with a static plan template.
class CogRestructureArmBPage extends StatefulWidget {
  const CogRestructureArmBPage({super.key});

  @override
  State<CogRestructureArmBPage> createState() =>
      _CogRestructureArmBPageState();
}

enum _ThoughtType { mindReading, fortuneTelling, allOrNothing, other }

extension on _ThoughtType {
  String labelZh() => switch (this) {
        _ThoughtType.mindReading => '讀心 / 估佢點諗',
        _ThoughtType.fortuneTelling => '占卜 / 估將來最壞',
        _ThoughtType.allOrNothing => '非黑即白',
        _ThoughtType.other => '其他',
      };

  String labelEn() => switch (this) {
        _ThoughtType.mindReading => 'Mind-reading',
        _ThoughtType.fortuneTelling => 'Fortune-telling',
        _ThoughtType.allOrNothing => 'All-or-nothing',
        _ThoughtType.other => 'Other',
      };

  String storedName() => name;
}

class _CogRestructureArmBPageState extends State<CogRestructureArmBPage> {
  final _thoughtCtrl = TextEditingController();
  final _forCtrl = TextEditingController();
  final _againstCtrl = TextEditingController();
  final _altCtrl = TextEditingController();
  _ThoughtType? _type;
  bool _busy = false;

  @override
  void dispose() {
    _thoughtCtrl.dispose();
    _forCtrl.dispose();
    _againstCtrl.dispose();
    _altCtrl.dispose();
    super.dispose();
  }

  bool get _isComplete =>
      _type != null &&
      _thoughtCtrl.text.trim().isNotEmpty &&
      _forCtrl.text.trim().isNotEmpty &&
      _againstCtrl.text.trim().isNotEmpty;

  Future<String?> _saveRecord() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) return null;
    final repo = ThoughtRecordRepository(available: auth.available);
    return repo.create(
      profile.uid,
      ThoughtRecord(
        thought: _thoughtCtrl.text.trim(),
        thoughtType: _type?.storedName(),
        evidenceFor: _forCtrl.text.trim(),
        evidenceAgainst: _againstCtrl.text.trim(),
        alternative: _altCtrl.text.trim().isEmpty
            ? null
            : _altCtrl.text.trim(),
        armCode: 'B',
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _saveAndExit() async {
    if (!_isComplete) return;
    setState(() => _busy = true);
    await _saveRecord();
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
  }

  Future<void> _saveAndPlanTest() async {
    if (!_isComplete) return;
    setState(() => _busy = true);
    final recordId = await _saveRecord();
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile != null && recordId != null) {
      // Static plan template for Arm B (per spec).
      final actionRepo = ActionPlanRepository(available: auth.available);
      final planId = await actionRepo.create(
        profile.uid,
        ActionPlan(
          action: _altCtrl.text.trim().isEmpty
              ? _thoughtCtrl.text.trim()
              : _altCtrl.text.trim(),
          whenText: '',
          whereText: '',
          whoWith: '',
          fallback: '',
          armCode: 'B',
          createdAt: DateTime.now(),
        ),
      );
      if (planId != null) {
        final repo = ThoughtRecordRepository(available: auth.available);
        await repo.linkActionPlan(profile.uid, recordId, planId);
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Examine a worry' : '檢視一個諗法')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _PsychoEdCard(isEn: isEn),
            const SizedBox(height: 16),
            Text(
              isEn ? 'What is the thought?' : '邊個諗法令你最重？',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _thoughtCtrl,
              maxLines: 3,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: isEn
                    ? 'e.g. "Calling my daughter would just bother her."'
                    : '例：「打畀阿女只會煩到佢。」',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              isEn ? 'Which pattern fits best?' : '邊種模式最似？',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _ThoughtType.values.map((t) {
                final sel = t == _type;
                return ChoiceChip(
                  label: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 6),
                    child: Text(isEn ? t.labelEn() : t.labelZh(),
                        style: const TextStyle(fontSize: 16)),
                  ),
                  selected: sel,
                  onSelected: (_) => setState(() => _type = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _Slot(
              title: isEn
                  ? 'Evidence the thought is true'
                  : '支持呢個諗法嘅證據',
              controller: _forCtrl,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 12),
            _Slot(
              title: isEn
                  ? 'Evidence against, or another explanation'
                  : '反對嘅證據，或者另一種解釋',
              controller: _againstCtrl,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 12),
            _Slot(
              title: isEn
                  ? 'An alternative, kinder thought (optional)'
                  : '一個溫和啲嘅諗法（選擇性）',
              controller: _altCtrl,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed:
                  _isComplete && !_busy ? _saveAndPlanTest : null,
              icon: const Icon(Icons.checklist_rtl_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  isEn ? 'Make a small test' : '計劃一個小測試',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _isComplete && !_busy ? _saveAndExit : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  isEn ? 'Save without test' : '只儲存唔計劃',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PsychoEdCard extends StatelessWidget {
  final bool isEn;
  const _PsychoEdCard({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEn ? 'Three common patterns' : '三種常見諗法模式',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              isEn
                  ? '• Mind-reading: assuming you know what someone thinks.\n'
                      '• Fortune-telling: predicting the worst outcome.\n'
                      '• All-or-nothing: only seeing the extremes.\n\n'
                      'Naming the pattern doesn\'t make a worry go away — '
                      'but it can give you a tiny gap between the thought '
                      'and the feeling.'
                  : '• 讀心：當自己知道對方點諗。\n'
                      '• 占卜：預估最壞嘅結果。\n'
                      '• 非黑即白：淨係睇到兩個極端。\n\n'
                      '叫出個模式嚟，唔會令擔心消失，'
                      '但可以喺諗法同感覺之間，留個小空隙。',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final VoidCallback onChanged;
  const _Slot({
    required this.title,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 3,
          style: theme.textTheme.bodyLarge,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}
