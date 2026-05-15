import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/llm/transcript_consent_prompter.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/action_plan.dart';

/// M7 follow-up surface — "件事點呀？".
///
/// Both arms ask the same three-option outcome (happened / partial /
/// didn't happen). Arm A additionally produces an open-ended LLM
/// response that engages with the user's account; Arm B just thanks
/// them and offers the next suggestion (out-of-scope for Sprint 2).
class ActionLoopFollowUpPage extends StatefulWidget {
  final ActionPlan plan;
  const ActionLoopFollowUpPage({super.key, required this.plan});

  @override
  State<ActionLoopFollowUpPage> createState() =>
      _ActionLoopFollowUpPageState();
}

class _ActionLoopFollowUpPageState extends State<ActionLoopFollowUpPage> {
  static const _systemPromptZh = '''
你係一個鼓勵者，幫長者回顧佢嘅小行動。用粵語/口語繁體中文，
1-2 句。承認佢做咗咩，唔好教訓、唔好強加意義。
如果未做到，輕輕話佢冇問題，「下次再試」就夠。
唔好提其他功能、唔好建議新計劃。
''';

  static const _systemPromptEn = '''
You help an older adult reflect on their small step. Reply in plain
English, 1–2 sentences. Acknowledge what they did. No lecturing, no
imposed meaning. If they didn't manage it, say it's fine and next time
counts. Do not suggest other modules or new plans.
''';

  FollowUpOutcome? _outcome;
  final _noteCtrl = TextEditingController();
  String? _llmReply;
  bool _busy = false;
  bool _saved = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_outcome == null) return;
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    setState(() => _busy = true);

    if (profile != null && widget.plan.id != null) {
      final repo = ActionPlanRepository(available: auth.available);
      await repo.updateOutcome(
        profile.uid,
        widget.plan.id!,
        outcome: _outcome!,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      // Cancel any pending m7_followup reminders linked to this plan so
      // the user doesn't get nudged about something they just resolved.
      if (auth.available) {
        final pending = await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('reminders')
            .where('linkedDocId', isEqualTo: widget.plan.id)
            .where('delivered', isEqualTo: false)
            .get();
        for (final d in pending.docs) {
          await d.reference.delete();
        }
      }
    }

    if (Arm.isA(context)) {
      await TranscriptConsentPrompter.maybePrompt(
        context: context,
        moduleKey: 'm7_followup',
      );
      if (!mounted) return;
      final response = await core.llm.send(
        moduleId: 'm7_action_loop_followup',
        systemPrompt: isEn ? _systemPromptEn : _systemPromptZh,
        history: const [],
        userInput: [
          'plan: ${widget.plan.action}',
          'outcome: ${_outcome!.name}',
          if (_noteCtrl.text.trim().isNotEmpty) 'note: ${_noteCtrl.text.trim()}',
        ].join('\n'),
      );
      if (mounted) {
        _llmReply = response.text.isNotEmpty
            ? response.text
            : (isEn ? 'Thanks for telling me.' : '多謝你話畀我聽。');
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final p = widget.plan;

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'How did it go?' : '件事點呀？')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isEn ? 'Your plan was' : '你之前計劃',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                    const SizedBox(height: 6),
                    Text(p.action, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text('${p.whenText} · ${p.whereText} · ${p.whoWith}',
                        style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isEn ? 'Did it happen?' : '件事有冇發生？',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _OutcomeChoice(
              outcome: FollowUpOutcome.happened,
              labelZh: '做到喇',
              labelEn: 'Yes, I did it',
              selected: _outcome,
              onChanged: (v) => setState(() => _outcome = v),
            ),
            _OutcomeChoice(
              outcome: FollowUpOutcome.partial,
              labelZh: '做咗一部分',
              labelEn: 'Partly',
              selected: _outcome,
              onChanged: (v) => setState(() => _outcome = v),
            ),
            _OutcomeChoice(
              outcome: FollowUpOutcome.didNotHappen,
              labelZh: '未做到',
              labelEn: 'Not this time',
              selected: _outcome,
              onChanged: (v) => setState(() => _outcome = v),
            ),
            const SizedBox(height: 16),
            Text(
              isEn ? 'Anything to add (optional)' : '想加少少嘢都得（選擇性）',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    style: theme.textTheme.bodyLarge,
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                VoiceInputButton(
                  prefix: () => _noteCtrl.text,
                  onText: (t) => _noteCtrl.text = t,
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _outcome != null && !_busy && !_saved ? _save : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _busy
                    ? const CircularProgressIndicator()
                    : Text(
                        _saved
                            ? (isEn ? 'Saved' : '已儲存')
                            : (isEn ? 'Save' : '儲存'),
                        style: const TextStyle(fontSize: 20),
                      ),
              ),
            ),
            if (_llmReply != null) ...[
              const SizedBox(height: 20),
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_llmReply!,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OutcomeChoice extends StatelessWidget {
  final FollowUpOutcome outcome;
  final String labelZh;
  final String labelEn;
  final FollowUpOutcome? selected;
  final ValueChanged<FollowUpOutcome> onChanged;
  const _OutcomeChoice({
    required this.outcome,
    required this.labelZh,
    required this.labelEn,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final isSel = selected == outcome;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSel
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onChanged(outcome),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSel
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSel
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSel
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  isEn ? labelEn : labelZh,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
