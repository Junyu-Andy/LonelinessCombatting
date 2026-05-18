/// Weekly 12-item PPR scale (Dev Req §11, Design Rationale §8).
///
/// Adapted from Crasta, Rogge & Reis (2021). The wording draft here is
/// pending the cognitive-interview pilot — once that completes, the
/// labels in [pprWeeklyItems] should be revised.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/ppr_scale.dart';

class PprWeeklyPage extends StatefulWidget {
  final String agentId;
  const PprWeeklyPage({super.key, required this.agentId});

  @override
  State<PprWeeklyPage> createState() => _PprWeeklyPageState();
}

class _PprWeeklyPageState extends State<PprWeeklyPage> {
  final Map<String, int> _responses = {};
  final _freeTextCtrl = TextEditingController();
  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _freeTextCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final repo = PprResponseRepository(available: auth.available);
    await repo.submit(
      profile.uid,
      PprResponse(
        agentId: widget.agentId,
        form: 'weekly_12_item',
        items: Map.from(_responses),
        submittedAt: DateTime.now(),
        freeText: _freeTextCtrl.text.trim().isEmpty
            ? null
            : _freeTextCtrl.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  bool get _isComplete => _responses.length == pprWeeklyItems.length;

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final agent = AgentRegistry.tryById(widget.agentId);
    final profile = AppSettingsScope.of(context).profile;
    final agentName = agent == null
        ? widget.agentId
        : (isEn
            ? agent
                .resolveVariant(profile?.ahJanAhBakVariant)
                .displayNameEn
            : agent
                .resolveVariant(profile?.ahJanAhBakVariant)
                .displayNameZh);

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Weekly feedback' : '每週回饋')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEn
                      ? 'Twelve questions about your experience with '
                          '$agentName this week.'
                      : '12 條問題，關於你呢個禮拜同 $agentName 嘅體驗。',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                for (final item in pprWeeklyItems)
                  _LikertItem(
                    item: item,
                    agentName: agentName,
                    value: _responses[item.id],
                    onChanged: (v) => setState(() => _responses[item.id] = v),
                  ),
                const SizedBox(height: 8),
                Text(
                  isEn
                      ? 'Anything else you\'d like the team to know? (optional)'
                      : '仲有冇其他想我哋知？（可以唔填）',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _freeTextCtrl,
                  minLines: 3,
                  maxLines: 6,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed:
                      !_isComplete || _saving || _saved ? null : _save,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      _saved
                          ? (isEn ? 'Thank you' : '多謝')
                          : (isEn ? 'Submit' : '提交'),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LikertItem extends StatelessWidget {
  final PprWeeklyItem item;
  final String agentName;
  final int? value;
  final ValueChanged<int> onChanged;
  const _LikertItem({
    required this.item,
    required this.agentName,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final prompt = (isEn ? item.promptEn : item.promptZh)
        .replaceAll('{agent}', agentName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prompt, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) {
              final v = i + 1;
              final selected = value == v;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => onChanged(v),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        '$v',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isEn ? 'Strongly disagree' : '非常唔同意',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                isEn ? 'Strongly agree' : '非常同意',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
