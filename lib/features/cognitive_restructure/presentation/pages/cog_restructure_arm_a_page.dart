import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../action_loop/presentation/pages/action_loop_arm_a_page.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/thought_record.dart';

/// M4 — Cognitive Restructuring, Arm A.
///
/// Spec §M4 Arm A flow:
///   1. The user names or LLM detects a negative social cognition.
///   2. Reflect it back gently as a *thought*, not a fact.
///   3. Three brief Socratic moves, one screen each:
///        a. Evidence for the thought
///        b. Evidence against / alternative explanations
///        c. A small low-stakes behavioural experiment
///   4. Experiment can be handed off to M7 (Action Loop) for planning.
///
/// System-prompt invariants per spec engineering notes:
///   - Validate before challenge.
///   - Never tell the user the thought is "wrong".
///   - Always offer the experiment as optional.
///   - Refuse CBT on grief / recent loss / trauma triggers and redirect
///     to safety surface.
class CogRestructureArmAPage extends StatefulWidget {
  final String? seedThought;
  const CogRestructureArmAPage({super.key, this.seedThought});

  @override
  State<CogRestructureArmAPage> createState() =>
      _CogRestructureArmAPageState();
}

enum _Step { name, forEvidence, againstEvidence, experiment, review, saved }

class _CogRestructureArmAPageState extends State<CogRestructureArmAPage> {
  static const _reflectSystemPromptZh = '''
你係一個溫和嘅聆聽者，唔係 CBT 教練、唔係教師。你嘅工作係：
- 用粵語/口語繁體中文，最多 2 句。
- 重複用戶提到嘅諗法（用引號），然後溫柔咁話佢：「呢個係一個諗法，唔係事實。」
- 唔好評論、唔好叫佢「諗開心啲」、唔好話佢「諗錯咗」。
- 如果用戶提到喪親、最近嘅死亡、或者強烈情緒（例如「自殺」），唔好繼續呢個練習，
  改為話佢可以隨時打 2896 0000 撒瑪利亞會熱線。
''';

  static const _reflectSystemPromptEn = '''
You are a gentle listener, not a CBT coach, not a teacher. Your job:
- Reply in plain English, max 2 sentences.
- Repeat the user's thought back (in quotes), then softly say: "That is
  a thought, not a fact."
- Do not analyse, do not say "think positive", do not call it "wrong".
- If the user mentions bereavement, a recent death, or strong distress
  ("kill myself" etc), do NOT continue this exercise. Tell them they can
  call Samaritans Hong Kong on 2896 0000 any time.
''';

  static const _experimentSystemPromptZh = '''
你係一個鼓勵者。用戶剛剛諗緊一個諗法，亦寫低咗證據兩面。
依家請你提議一個好細、好低風險嘅實驗，幫佢測試呢個諗法。
- 一句講晒，唔超過 30 字。
- 永遠係「可以」、「不如試下」嘅語氣，唔好強迫。
- 例：「不如聽朝傳個短訊問候佢，睇下佢點覆。」
唔好教訓、唔好總結。
''';

  static const _experimentSystemPromptEn = '''
You are encouraging. The user just shared a thought and listed evidence
both ways. Suggest one very small, low-stakes experiment to test the
thought. One sentence, max 30 words. Always optional language ("you
could try", "maybe…"). Example: "Send her a short message tomorrow and
see how she replies." No lectures, no summary.
''';

  late final TextEditingController _thoughtCtrl;
  final _forCtrl = TextEditingController();
  final _againstCtrl = TextEditingController();
  final _experimentCtrl = TextEditingController();
  String _llmReflection = '';
  _Step _step = _Step.name;
  bool _busy = false;
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _thoughtCtrl = TextEditingController(text: widget.seedThought ?? '');
  }

  @override
  void dispose() {
    _thoughtCtrl.dispose();
    _forCtrl.dispose();
    _againstCtrl.dispose();
    _experimentCtrl.dispose();
    super.dispose();
  }

  Future<void> _reflect() async {
    final text = _thoughtCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final response = await core.llm.send(
      moduleId: 'm4_cog_restructure_reflect',
      systemPrompt: isEn ? _reflectSystemPromptEn : _reflectSystemPromptZh,
      history: const [],
      userInput: text,
    );
    if (!mounted) return;
    if (response.shortCircuited || response.hasEscalation) {
      // The detector caught grief / acute distress in the thought. Per
      // spec, refuse the exercise and route the user gently elsewhere.
      setState(() {
        _busy = false;
        _llmReflection = isEn
            ? 'What you\'re carrying sounds heavy. This exercise isn\'t '
                'right for that. Please call Samaritans Hong Kong at '
                '2896 0000 — they are open 24 hours.'
            : '聽你咁講，你而家承擔緊好重嘅嘢。呢個練習唔啱依家做。'
                '請即刻打撒瑪利亞會熱線 2896 0000，24 小時都有人聽。';
      });
      return;
    }
    setState(() {
      _busy = false;
      _llmReflection = response.text.isNotEmpty
          ? response.text
          : (isEn
              ? 'That is a thought, not a fact. Let\'s look at it together.'
              : '呢個係一個諗法，唔係事實。我哋一齊睇下。');
      _step = _Step.forEvidence;
    });
  }

  Future<void> _proposeExperiment() async {
    setState(() => _busy = true);
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final response = await core.llm.send(
      moduleId: 'm4_cog_restructure_experiment',
      systemPrompt:
          isEn ? _experimentSystemPromptEn : _experimentSystemPromptZh,
      history: const [],
      userInput: [
        'thought: ${_thoughtCtrl.text}',
        'evidence for: ${_forCtrl.text}',
        'evidence against: ${_againstCtrl.text}',
      ].join('\n'),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _experimentCtrl.text = response.text.isNotEmpty
          ? response.text
          : (isEn
              ? 'Try one small thing this week and notice what actually happens.'
              : '今個禮拜試下做一件細件事，留意實際發生咗咩。');
      _step = _Step.experiment;
    });
  }

  Future<String?> _saveRecord() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) return null;
    final repo = ThoughtRecordRepository(available: auth.available);
    return repo.create(
      profile.uid,
      ThoughtRecord(
        thought: _thoughtCtrl.text.trim(),
        evidenceFor: _forCtrl.text.trim(),
        evidenceAgainst: _againstCtrl.text.trim(),
        experiment: _experimentCtrl.text.trim(),
        armCode: 'A',
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _handOffToM7() async {
    // Persist the record first so we have an id to link from M7.
    setState(() => _busy = true);
    final recordId = await _saveRecord();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _handedOff = true;
    });
    // Replace this page with M7's Arm A planner, pre-filled with the
    // experiment as the "what". Letting the user complete When / Where /
    // Who / Fallback in M7 keeps the if-then plan whole instead of
    // silently writing a half-filled ActionPlan.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ActionLoopArmAPage(
          seedAction: _experimentCtrl.text.trim(),
          linkedThoughtRecordId: recordId,
        ),
      ),
    );
  }

  Future<void> _saveAndExit() async {
    setState(() => _busy = true);
    await _saveRecord();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _Step.saved;
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.of(context).pop();
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
            _StepBadge(step: _step),
            const SizedBox(height: 12),
            if (_step == _Step.name) ...[
              Text(
                isEn
                    ? 'What thought has been weighing on you?'
                    : '邊個諗法令你最重？',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _thoughtCtrl,
                autofocus: true,
                maxLines: 3,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: isEn
                      ? 'e.g. "Calling my daughter would just bother her."'
                      : '例：「打畀阿女只會煩到佢。」',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _reflect,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _busy
                      ? const CircularProgressIndicator()
                      : Text(
                          isEn ? 'Reflect' : '輕輕睇下',
                          style: const TextStyle(fontSize: 20),
                        ),
                ),
              ),
            ],
            if (_step != _Step.name && _llmReflection.isNotEmpty) ...[
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_llmReflection,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_step == _Step.forEvidence) ...[
              _Question(
                title: isEn
                    ? 'What makes this feel true?'
                    : '咩令你覺得呢個諗法係真？',
                hint: isEn
                    ? 'List anything that supports it.'
                    : '寫低任何支持呢個諗法嘅嘢。',
                controller: _forCtrl,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || _forCtrl.text.trim().isEmpty
                    ? null
                    : () => setState(() => _step = _Step.againstEvidence),
                child: _buttonLabel(isEn ? 'Next' : '下一步'),
              ),
            ],
            if (_step == _Step.againstEvidence) ...[
              _Question(
                title: isEn
                    ? 'What might be another explanation?'
                    : '有冇另一種睇法？',
                hint: isEn
                    ? 'Anything that doesn\'t fit the thought.'
                    : '寫低任何唔啱呢個諗法嘅嘢。',
                controller: _againstCtrl,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || _againstCtrl.text.trim().isEmpty
                    ? null
                    : _proposeExperiment,
                child: _busy
                    ? const CircularProgressIndicator()
                    : _buttonLabel(isEn ? 'Suggest an experiment' : '提議一個小實驗'),
              ),
            ],
            if (_step == _Step.experiment) ...[
              Text(
                isEn
                    ? 'A tiny experiment (optional)'
                    : '一個小實驗（可以唔做）',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _experimentCtrl,
                maxLines: 4,
                style: theme.textTheme.bodyLarge,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _handOffToM7,
                icon: const Icon(Icons.checklist_rtl_outlined),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    isEn ? 'Plan it as a small step' : '計劃做呢件小事',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _saveAndExit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    isEn ? 'Save without planning' : '只儲存唔計劃',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
            if (_step == _Step.saved) ...[
              Center(
                child: Text(
                  _handedOff
                      ? (isEn
                          ? 'Saved and added to your small steps.'
                          : '儲咗低，亦加咗去「小行動」。')
                      : (isEn ? 'Saved.' : '已儲存。'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buttonLabel(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: const TextStyle(fontSize: 20)),
      );
}

class _Question extends StatefulWidget {
  final String title;
  final String hint;
  final TextEditingController controller;
  const _Question({
    required this.title,
    required this.hint,
    required this.controller,
  });

  @override
  State<_Question> createState() => _QuestionState();
}

class _QuestionState extends State<_Question> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: widget.controller,
          autofocus: true,
          maxLines: 4,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: widget.hint,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

class _StepBadge extends StatelessWidget {
  final _Step step;
  const _StepBadge({required this.step});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final labels = isEn
        ? const ['Name', 'Evidence for', 'Other view', 'Experiment', 'Done']
        : const ['命名', '支持證據', '另一面', '小實驗', '完成'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(labels.length, (i) {
        final active = i == step.index;
        final done = i < step.index;
        final color = active
            ? theme.colorScheme.primary
            : done
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest;
        final fg = active
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            labels[i],
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              color: fg,
            ),
          ),
        );
      }),
    );
  }
}
