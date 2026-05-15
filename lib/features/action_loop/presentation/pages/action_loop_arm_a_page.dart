import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/reminders/reminder_service.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../cognitive_restructure/data/thought_record.dart';
import '../../data/action_plan.dart';

/// M7 — Action Loop, Arm A.
///
/// Spec §M7 Arm A flow:
///   1. LLM asks four questions in natural language: When? Where? With
///      whom? What if it doesn't work out?
///   2. LLM helps articulate a coherent if-then plan, anticipating
///      barriers from prior conversations.
///   3. Plan saved with a follow-up reminder.
///
/// For the basic build we keep the four questions explicit (chip-style
/// progress) so the participant can see where they are, but let the LLM
/// produce the summary "if-then" line at the end.
///
/// [seedAction] lets caller modules (M4 hand-off, M6 acceptance) pre-fill
/// the "what" step so the user doesn't retype the experiment. When set,
/// the planner skips the first question and starts at "when".
/// [linkedThoughtRecordId] lets M4 record the cross-link after the plan
/// is created.
class ActionLoopArmAPage extends StatefulWidget {
  final String? seedAction;
  final String? linkedThoughtRecordId;
  const ActionLoopArmAPage({
    super.key,
    this.seedAction,
    this.linkedThoughtRecordId,
  });

  @override
  State<ActionLoopArmAPage> createState() => _ActionLoopArmAPageState();
}

enum _Step { action, when_, where_, who, fallback, review, saved }

class _ActionLoopArmAPageState extends State<ActionLoopArmAPage> {
  static const _summarySystemPromptZh = '''
你係一個鼓勵者，幫長者整理一個 if-then 計劃。用粵語/口語繁體中文，
寫一句 if-then 句式，唔超過 40 字。例：「聽朝食完早餐之後，
我會打畀阿May傾 5 分鐘。如果佢冇聽，我下午再試。」
唔好加額外建議或鼓勵。淨係寫一句句子。
''';

  static const _summarySystemPromptEn = '''
You help an older adult crystallise an if-then plan. Reply in plain
English, one sentence, max 40 words. Example: "Tomorrow morning after
breakfast, I will call May for 5 minutes. If she doesn't pick up, I will
try again in the afternoon." No extra encouragement or suggestions.
''';

  final _ctrl = TextEditingController();
  _Step _step = _Step.action;
  String _action = '';
  String _whenText = '';
  String _whereText = '';
  String _whoWith = '';
  String _fallback = '';
  String _summary = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.seedAction?.trim();
    if (seed != null && seed.isNotEmpty) {
      _action = seed;
      _step = _Step.when_;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _promptZh() {
    switch (_step) {
      case _Step.action:
        return '想做嘅小事係咩？一句講晒就得。';
      case _Step.when_:
        return '幾時做？例如「聽朝食完早餐」、「今晚 8 點」。';
      case _Step.where_:
        return '喺邊度做？屋企、公園、定其他地方？';
      case _Step.who:
        return '同邊個有關？打畀邊位？或者一個人都得。';
      case _Step.fallback:
        return '如果計劃唔成功，你會點？(例如：遲啲再試)';
      case _Step.review:
      case _Step.saved:
        return '';
    }
  }

  String _promptEn() {
    switch (_step) {
      case _Step.action:
        return 'What small thing do you want to do? One sentence is fine.';
      case _Step.when_:
        return 'When? e.g. "tomorrow morning after breakfast", "8pm tonight".';
      case _Step.where_:
        return 'Where? Home, the park, somewhere else?';
      case _Step.who:
        return 'Who is involved? Who would you call? Alone is also fine.';
      case _Step.fallback:
        return 'If it doesn\'t work out, what will you do?';
      case _Step.review:
      case _Step.saved:
        return '';
    }
  }

  Future<void> _advance() async {
    final value = _ctrl.text.trim();
    if (value.isEmpty) return;
    setState(() {
      switch (_step) {
        case _Step.action:
          _action = value;
          _step = _Step.when_;
          break;
        case _Step.when_:
          _whenText = value;
          _step = _Step.where_;
          break;
        case _Step.where_:
          _whereText = value;
          _step = _Step.who;
          break;
        case _Step.who:
          _whoWith = value;
          _step = _Step.fallback;
          break;
        case _Step.fallback:
          _fallback = value;
          _step = _Step.review;
          break;
        case _Step.review:
        case _Step.saved:
          break;
      }
      _ctrl.clear();
    });
    if (_step == _Step.review) {
      await _generateSummary();
    }
  }

  Future<void> _generateSummary() async {
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    setState(() => _busy = true);
    final response = await core.llm.send(
      moduleId: 'm7_action_loop_summary',
      systemPrompt: isEn ? _summarySystemPromptEn : _summarySystemPromptZh,
      history: const [],
      userInput: [
        'action: $_action',
        'when: $_whenText',
        'where: $_whereText',
        'with: $_whoWith',
        'fallback: $_fallback',
      ].join('\n'),
    );
    if (!mounted) return;
    final fallbackSummary = isEn
        ? '$_whenText at $_whereText, with $_whoWith — $_action. '
            'If not, $_fallback.'
        : '$_whenText 喺 $_whereText，同 $_whoWith — $_action。如果唔得，$_fallback。';
    setState(() {
      _busy = false;
      _summary = response.text.isNotEmpty ? response.text : fallbackSummary;
    });
  }

  Future<void> _savePlan() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) {
      // Guest mode — keep flow but skip persistence.
      setState(() => _step = _Step.saved);
      return;
    }
    final repo = ActionPlanRepository(available: auth.available);
    setState(() => _busy = true);
    final planId = await repo.create(
      profile.uid,
      ActionPlan(
        action: _action,
        whenText: _whenText,
        whereText: _whereText,
        whoWith: _whoWith,
        fallback: _fallback,
        armCode: 'A',
        createdAt: DateTime.now(),
      ),
    );
    final linkId = widget.linkedThoughtRecordId;
    if (planId != null && linkId != null) {
      final trRepo = ThoughtRecordRepository(available: auth.available);
      await trRepo.linkActionPlan(profile.uid, linkId, planId);
    }
    if (planId != null) {
      // Queue a follow-up reminder ~24h after the planned time. Concrete
      // delivery is wired in by the device-side scheduler; here we just
      // record the intent.
      final reminders = FirestoreReminderQueue(available: auth.available);
      await reminders.schedule(
        uid: profile.uid,
        request: ReminderRequest(
          kind: 'm7_followup',
          fireAt: DateTime.now().add(const Duration(hours: 24)),
          titleZh: '件事點呀？',
          titleEn: 'How did it go?',
          bodyZh: '你之前計劃做：$_action。',
          bodyEn: 'Your plan: $_action.',
          linkedDocId: planId,
        ),
      );
    }
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
      appBar: AppBar(
        title: Text(isEn ? 'Plan a small step' : '計劃一個小行動'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProgressChips(step: _step),
              const SizedBox(height: 16),
              if (_step == _Step.review) ...[
                Text(
                  isEn ? 'Here\'s your plan' : '呢個係你嘅計劃',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: _busy
                        ? const Center(child: CircularProgressIndicator())
                        : Text(
                            _summary,
                            style:
                                theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                          ),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _savePlan,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      isEn ? 'Save plan' : '儲存計劃',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ] else if (_step == _Step.saved) ...[
                const Spacer(),
                Center(
                  child: Text(
                    isEn ? 'Saved — see you back here.' : '收到。等你返嚟同我講件事點。',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const Spacer(),
              ] else ...[
                Text(
                  isEn ? _promptEn() : _promptZh(),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  style: theme.textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _advance(),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _advance,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      isEn ? 'Next' : '下一步',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressChips extends StatelessWidget {
  final _Step step;
  const _ProgressChips({required this.step});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final labels = isEn
        ? const ['What', 'When', 'Where', 'Who', 'If not', 'Review']
        : const ['做咩', '幾時', '邊度', '同邊個', '唔得點', '檢視'];
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
              fontSize: 14,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              color: fg,
            ),
          ),
        );
      }),
    );
  }
}
