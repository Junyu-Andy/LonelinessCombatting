import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/arm/arm_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../data/reflection_prompts.dart';

/// M5 — Self-Reflection Prompts.
///
/// Spec §M5: low priority module. Arm A generates a context-aware prompt
/// from recent memory; Arm B rotates a static prompt set on schedule.
/// Both arms log a short free-text response that goes into M9's
/// completion count.
///
/// Sprint 4 ships the minimum viable shape: one prompt at a time, a
/// short-text response field, save → close.
class SelfReflectionPage extends StatefulWidget {
  const SelfReflectionPage({super.key});

  @override
  State<SelfReflectionPage> createState() => _SelfReflectionPageState();
}

class _SelfReflectionPageState extends State<SelfReflectionPage> {
  static const _systemPromptZh = '''
你係阿暖。基於用戶最近嘅內容，出一個開放式反思問題（一句，唔超過 30 字）。
要求：
- 用粵語/口語繁體中文。
- 引用用戶提過嘅一個具體細節（名/地點/感受）。
- 唔係建議、唔係教訓；係邀請對方再諗多少少。
- 唔好用「你應該」、「不如試下」、「需要」。
輸出格式：淨係問題本身，唔好其他文字。
''';

  static const _systemPromptEn = '''
You are a warm companion. Based on the user's recent content, write one
open-ended reflection question (one sentence, max 25 words).
Rules:
- Plain English.
- Reference one specific detail the user has mentioned (a name, place,
  or feeling).
- Not advice, not a lesson — an invitation to think a little more.
- Avoid "you should", "you need to", "you ought to".
Output format: only the question itself, no extra text.
''';

  final _responseCtrl = TextEditingController();
  String? _prompt;
  bool _loading = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrompt());
  }

  @override
  void dispose() {
    _responseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrompt() async {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    if (Arm.isA(context)) {
      setState(() => _loading = true);
      final core = CoreServicesScope.of(context);
      final profile = AppSettingsScope.read(context).profile;
      final memorySnips = <String>[];
      if (profile != null) {
        final entries = await core.memory.recentAcross(
          uid: profile.uid,
          moduleIds: const [
            'm2_check_in',
            'm3_reminiscence_w1',
            'm3_reminiscence_w2',
            'm3_reminiscence_w3',
          ],
          perModule: 1,
        );
        memorySnips.addAll(entries.map((e) => e.summary));
      }
      final userInput = memorySnips.isEmpty
          ? (isEn ? 'No prior memory yet.' : '冇之前嘅內容。')
          : memorySnips.join('\n');
      final response = await core.llm.send(
        moduleId: 'm5_reflection_prompt',
        systemPrompt: isEn ? _systemPromptEn : _systemPromptZh,
        history: const [],
        userInput: userInput,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _prompt = response.text.isNotEmpty
            ? response.text.trim()
            : _staticPrompt(isEn);
      });
    } else {
      setState(() {
        _prompt = _staticPrompt(isEn);
      });
    }
  }

  String _staticPrompt(bool isEn) {
    // Rotate by day-of-year so the same person sees different prompts
    // across days without repeating in the first ~12 days.
    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year, 1, 1))
        .inDays;
    final pair = reflectionPrompts[dayOfYear % reflectionPrompts.length];
    return isEn ? pair.$2 : pair.$1;
  }

  Future<void> _save() async {
    final core = CoreServicesScope.of(context);
    final profile = AppSettingsScope.read(context).profile;
    setState(() => _saved = true);
    if (profile != null) {
      // Both arms write a summary; transcript consent gates persistence.
      await core.memory.writeSummary(
        uid: profile.uid,
        moduleId: 'm5_reflection',
        summary: '${_prompt ?? ''}\n\n${_responseCtrl.text.trim()}',
        armCode: Arm.isA(context) ? 'A' : 'B',
        hasTranscriptConsent: profile.consent.transcriptRetention,
      );
    }
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'A small reflection' : '一個反思')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isEn
                      ? 'A question for you to sit with — write a few '
                          'words back, or just read it and close. There '
                          'is no right answer.'
                      : '一條畀你諗下嘅問題。可以寫返幾句，或者淨係讀完就熄。'
                          '冇標準答案。',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                              child: CircularProgressIndicator()),
                        )
                      : Text(
                          _prompt ?? '',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(height: 1.5),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TextField(
                  controller: _responseCtrl,
                  maxLines: null,
                  expands: true,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: isEn
                        ? 'Write whatever comes to mind.'
                        : '諗到咩寫咩。',
                    alignLabelWithHint: true,
                  ),
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saved ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _saved
                        ? (isEn ? 'Saved' : '已儲存')
                        : (isEn ? 'Save' : '儲存'),
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
