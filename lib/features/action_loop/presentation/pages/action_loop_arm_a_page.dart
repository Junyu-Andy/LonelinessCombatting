import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/feature_flags/remote_feature_flags.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/llm/transcript_consent_prompter.dart';
import '../../../../core/reminders/reminder_service.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../../shared/widgets/app_loading_indicator.dart';
import '../../../../shared/widgets/app_stepper.dart';
import '../../../../shared/widgets/keyboard_compact.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/data/user_profile.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../data/action_plan.dart';
import '../../data/action_plan_copy.dart';

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
/// [seedAction] lets caller modules (M6 acceptance) pre-fill the "what"
/// step so the user doesn't retype the experiment. When set, the
/// planner skips the first question and starts at "when". The legacy
/// M4 thought-record cross-link was removed when M4 was deprecated in
/// Sprint 3.
///
/// 1020e 二.7 (switch actionPlanSimplifiedEnabled, read once when the page
/// opens): the steps are 做咩 → 幾時 → 檢視.  [seedAction] is shown in the
/// 做咩 box, editable (not skipped).  On 檢視 the elder may add 邊度 /
/// 同邊個 / 唔得點 (「加多啲細節」), each with 「跳過」.  An empty required
/// step says so.  Same rule as the rule arm's page.  Off: as before.
///
/// 1020e 二.7 (2) (switch actionPlanMemoryEnabled, Chinese only): the
/// summary call sends agentId siu_yan, so the server adds 小欣's memory
/// block (functions/memory.js INJECT_MODULES; never her due follow-ups),
/// with [_summarySystemPromptZhMemory].
class ActionLoopArmAPage extends StatefulWidget {
  final String? seedAction;

  /// [ActionPlanSource]; default: suggestion when [seedAction] is set,
  /// else landing.  Only stored with the switch on.
  final String? source;
  const ActionLoopArmAPage({
    super.key,
    this.seedAction,
    this.source,
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

  // 1020e 二.7 (2): used only with actionPlanMemoryEnabled — the server
  // then appends 小欣's memory block.  Identity wording as the v2 companion
  // prompts (「電腦程式夥伴」, #134).  The prompt above stays for switch off.
  static const _summarySystemPromptZhMemory = '''
你係小欣（一個電腦程式夥伴），幫長者整理一個 if-then 計劃。用粵語/口語繁體中文，
寫一句 if-then 句式，唔超過 40 字。例：「聽朝食完早餐之後，
我會打畀阿May傾 5 分鐘。如果佢冇聽，我下午再試。」
下面可能有你記得關於用戶嘅嘢：可以用返入面講過嘅人名同習慣，令句子貼身啲；
冇講過嘅人或者事唔好作；唔好提用戶話過唔想提起嘅話題。
用戶冇填嘅項目就唔好寫。
唔好加額外建議或鼓勵。唔好用「AI」「模型」「機械人」呢啲字。淨係寫一句句子。
''';

  static const _summarySystemPromptEn = '''
You help an older adult crystallise an if-then plan. Reply in plain
English, one sentence, max 40 words. Example: "Tomorrow morning after
breakfast, I will call May for 5 minutes. If she doesn't pick up, I will
try again in the afternoon." No extra encouragement or suggestions.
''';

  final _ctrl = TextEditingController();
  final _voice = VoiceInputController();
  _Step _step = _Step.action;
  String _action = '';
  String _whenText = '';
  String _whereText = '';
  String _whoWith = '';

  /// T48: contacts the elder agreed to share (profile.closeContacts);
  /// T49a: plus 想重新聯絡嘅人 (profile.reconnectContacts), one per name.
  List<CloseContact> _sharedContacts(BuildContext context) =>
      AppSettingsScope.read(context).profile?.planContacts ??
      const <CloseContact>[];
  String _fallback = '';
  String _summary = '';
  bool _busy = false;

  /// 1020e: the simplified rule (switch read once per page).
  late final bool _simple =
      RemoteFeatureFlags.current.actionPlanSimplifiedEnabled;

  /// 1020e (switch on): walking the optional 邊度 / 同邊個 / 唔得點 steps.
  bool _inExtras = false;

  /// 1020e (switch on): the optional steps were offered once already.
  bool _extrasDone = false;

  /// 1020e (switch on): 下一步 was pressed on an empty required step.
  bool _emptyHint = false;

  String? get _seed {
    final s = widget.seedAction?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  String get _source =>
      widget.source ??
      (_seed != null ? ActionPlanSource.suggestion : ActionPlanSource.landing);

  @override
  void initState() {
    super.initState();
    final seed = _seed;
    if (seed != null) {
      _action = seed;
      if (_simple) {
        // 1020e: the suggestion is shown and editable on step 1.
        _ctrl.text = seed;
      } else {
        _step = _Step.when_;
      }
    }
  }

  bool _isOptional(_Step s) =>
      _simple && (s == _Step.where_ || s == _Step.who || s == _Step.fallback);

  /// The steps the stepper and chips show.  Switch off: all six.
  List<_Step> get _visibleSteps {
    if (!_simple) {
      return const [
        _Step.action, _Step.when_, _Step.where_, _Step.who, _Step.fallback,
        _Step.review,
      ];
    }
    return _inExtras
        ? const [_Step.where_, _Step.who, _Step.fallback]
        : const [_Step.action, _Step.when_, _Step.review];
  }

  int get _visibleIndex {
    final i = _visibleSteps.indexOf(_step);
    if (i >= 0) return i;
    return _visibleSteps.length; // saved: everything done
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

  Future<void> _advance({bool skip = false}) async {
    // B03 — stop dictation before snapshotting the step's text.
    await _voice.stopForSend();
    if (!mounted) return;
    final value = skip ? '' : _ctrl.text.trim();
    if (value.isEmpty && !_isOptional(_step)) {
      // 1020e: say what is needed instead of doing nothing.
      if (_simple) setState(() => _emptyHint = true);
      return;
    }
    setState(() {
      _emptyHint = false;
      switch (_step) {
        case _Step.action:
          _action = value;
          _step = _Step.when_;
          break;
        case _Step.when_:
          _whenText = value;
          _step = _simple ? _Step.review : _Step.where_;
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
          if (_inExtras) {
            _inExtras = false;
            _extrasDone = true;
          }
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

  /// 1020e (switch on): from 檢視 into the optional steps.
  void _openExtras() {
    setState(() {
      _inExtras = true;
      _emptyHint = false;
      _step = _Step.where_;
      _ctrl.clear();
    });
  }

  String _stepLabel(bool isEn) {
    final label = _baseStepLabel(isEn);
    return _isOptional(_step) && !isEn
        ? '$label${ActionPlanCopy.optionalTypedSuffix}'
        : label;
  }

  String _baseStepLabel(bool isEn) {
    switch (_step) {
      case _Step.action:
        return isEn ? 'What' : '做咩';
      case _Step.when_:
        return isEn ? 'When' : '幾時';
      case _Step.where_:
        return isEn ? 'Where' : '邊度';
      case _Step.who:
        return isEn ? 'Who' : '同邊個';
      case _Step.fallback:
        return isEn ? 'If not' : '唔得點';
      case _Step.review:
        return isEn ? 'Review' : '檢視';
      case _Step.saved:
        return isEn ? 'Saved' : '完成';
    }
  }

  Future<void> _generateSummary() async {
    await TranscriptConsentPrompter.maybePrompt(
      context: context,
      moduleKey: 'm7_action_loop',
    );
    if (!mounted) return;
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    // 1020e 二.7 (2): 小欣's memory block (server side), Chinese only.
    final withMemory =
        RemoteFeatureFlags.current.actionPlanMemoryEnabled && !isEn;
    setState(() => _busy = true);
    final response = await core.llm.send(
      moduleId: 'm7_action_loop_summary',
      systemPrompt: isEn
          ? _summarySystemPromptEn
          : (withMemory ? _summarySystemPromptZhMemory : _summarySystemPromptZh),
      agentId: withMemory ? AgentRegistry.siuYanId : null,
      history: const [],
      uid: AppSettingsScope.read(context).profile?.uid,
      // 1020e (switch on): the items left out are not sent.
      userInput: [
        'action: $_action',
        if (!_simple || _whenText.isNotEmpty) 'when: $_whenText',
        if (!_simple || _whereText.isNotEmpty) 'where: $_whereText',
        if (!_simple || _whoWith.isNotEmpty) 'with: $_whoWith',
        if (!_simple || _fallback.isNotEmpty) 'fallback: $_fallback',
      ].join('\n'),
    );
    if (!mounted) return;
    final fallbackSummary = _simple
        ? _shortSummary(isEn)
        : isEn
            ? '$_whenText at $_whereText, with $_whoWith — $_action. '
                'If not, $_fallback.'
            : '$_whenText 喺 $_whereText，同 $_whoWith — $_action。如果唔得，$_fallback。';
    setState(() {
      _busy = false;
      _summary = response.text.isNotEmpty ? response.text : fallbackSummary;
    });
    final escalation = response.inputFlag.level.index >=
            response.outputFlag.level.index
        ? response.inputFlag
        : response.outputFlag;
    if (escalation.level.isModerate ||
        escalation.level == DistressLevel.acute) {
      await core.distressRouter.route(escalation, context: context);
    }
  }

  /// 1020e (switch on): the template line when the model sends nothing,
  /// built from the items that were filled in.
  String _shortSummary(bool isEn) {
    if (isEn) {
      final b = StringBuffer(_whenText);
      if (_whereText.isNotEmpty) b.write(' at $_whereText');
      if (_whoWith.isNotEmpty) b.write(', with $_whoWith');
      b.write(' — $_action.');
      if (_fallback.isNotEmpty) b.write(' If not, $_fallback.');
      return b.toString();
    }
    final b = StringBuffer(_whenText);
    if (_whereText.isNotEmpty) b.write(' 喺 $_whereText');
    if (_whoWith.isNotEmpty) b.write('，同 $_whoWith');
    b.write(' — $_action。');
    if (_fallback.isNotEmpty) b.write('如果唔得，$_fallback。');
    return b.toString();
  }

  Future<void> _savePlan() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) {
      // Guest mode — keep flow but skip persistence.
      setState(() => _step = _Step.saved);
      return;
    }
    final repo = ActionPlanRepository.forApp(available: auth.available);
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
        planFormVersion: _simple ? 2 : null,
        source: _simple ? _source : null,
        seedAction: _simple ? _seed : null,
      ),
    );
    if (_simple && planId != null && mounted) {
      unawaited(AnalyticsScope.maybeOf(context)?.logM7PlanSaved(
        source: _source,
        filled: [
          if (_whenText.isNotEmpty) 'whenText',
          if (_whereText.isNotEmpty) 'whereText',
          if (_whoWith.isNotEmpty) 'whoWith',
          if (_fallback.isNotEmpty) 'fallback',
        ],
      ));
    }
    if (planId != null) {
      // Queue a follow-up reminder ~24h after the planned time. Concrete
      // delivery is wired in by the device-side scheduler; here we just
      // record the intent.
      final reminders = FirestoreReminderQueue(available: auth.available);
      await reminders.schedule(
        uid: profile.uid,
        // B.10 — pass profile so 今日休息 can suppress same-day reminders.
        profile: profile,
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
      // 1020c 二: one-line bar while the keyboard is open (switch
      // keyboardCompactHeaderEnabled; off = the same AppBar as before).
      appBar: keyboardCompactAppBar(
        context,
        title: Text(isEn ? 'Plan a small step' : '計劃一個小行動'),
      ),
      body: SafeArea(
        // 10/15: scrolling page (was a fixed column with Spacers), so the
        // keyboard that opens with the autofocused field never hides the
        // 下一步 button, at any font size.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppStepper(
                currentStep: _simple ? _visibleIndex : _step.index,
                totalSteps: _simple
                    ? _visibleSteps.length
                    : _Step.values.length - 1, // exclude 'saved'
                stepLabel: _stepLabel(isEn),
              ),
              const SizedBox(height: 12),
              _ProgressChips(
                labels: [for (final s in _visibleSteps) _chipLabel(s, isEn)],
                activeIndex: _simple ? _visibleIndex : _step.index,
              ),
              const SizedBox(height: 16),
              // 1020e (switch on): what the plan is about, on every step
              // after 做咩.
              if (_simple &&
                  _step != _Step.action &&
                  _step != _Step.saved &&
                  _action.isNotEmpty) ...[
                Container(
                  key: const Key('plan_a_action_card'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    isEn
                        ? 'You want to: $_action'
                        : ActionPlanCopy.youWantTo(_action),
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                  ),
                ),
                const SizedBox(height: 14),
              ],
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
                        ? AppLoadingIndicator.inline(
                            message: isEn
                                ? 'Let me put it together…'
                                : '畀我整理緊…',
                          )
                        : Text(
                            _summary,
                            style:
                                theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('plan_a_save'),
                  onPressed: _busy ? null : _savePlan,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      isEn ? 'Save plan' : '儲存計劃',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                if (_simple && !_extrasDone) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('plan_a_add_details'),
                    onPressed: _busy ? null : _openExtras,
                    child: Text(isEn
                        ? 'Add details (optional)'
                        : ActionPlanCopy.addDetails),
                  ),
                ],
              ] else if (_step == _Step.saved) ...[
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    isEn ? 'Saved — see you back here.' : '收到。等你返嚟同我講件事點。',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                Text(
                  isEn ? _promptEn() : _promptZh(),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                // T48: the people the elder agreed to share, one tap each.
                if (_step == _Step.who && _sharedContacts(context).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final c in _sharedContacts(context))
                        ActionChip(
                          key: Key('plan_contact_${c.name}'),
                          label: Text(c.label),
                          onPressed: () => setState(() => _ctrl.text = c.name),
                        ),
                    ]),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('plan_a_field'),
                        controller: _ctrl,
                        autofocus: true,
                        // 1020e: a pre-filled suggestion wraps.
                        minLines: 1,
                        maxLines: _simple ? 4 : 1,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        style: theme.textTheme.bodyLarge,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        onChanged: _emptyHint
                            ? (_) => setState(() => _emptyHint = false)
                            : null,
                        onSubmitted: (_) => _advance(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    VoiceInputButton(
                      controller: _voice,
                      prefix: () => _ctrl.text,
                      onText: (t) => _ctrl.text = t,
                    ),
                  ],
                ),
                if (_simple && _emptyHint) ...[
                  const SizedBox(height: 8),
                  Text(
                    isEn
                        ? 'A few words are enough, e.g. "tomorrow morning".'
                        : ActionPlanCopy.emptyStepHint,
                    key: const Key('plan_a_empty_hint'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('plan_a_next'),
                  onPressed: _advance,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      isEn ? 'Next' : '下一步',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                if (_isOptional(_step)) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('plan_a_skip'),
                    onPressed: () => _advance(skip: true),
                    child: Text(isEn ? 'Skip' : ActionPlanCopy.skip),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip label of one step (the same words as before 1020e).
String _chipLabel(_Step s, bool isEn) {
  const en = ['What', 'When', 'Where', 'Who', 'If not', 'Review', 'Saved'];
  const zh = ['做咩', '幾時', '邊度', '同邊個', '唔得點', '檢視', '完成'];
  return (isEn ? en : zh)[s.index];
}

class _ProgressChips extends StatelessWidget {
  /// 1020e: the chips of the steps on show (switch off: all six, as before).
  final List<String> labels;
  final int activeIndex;
  const _ProgressChips({required this.labels, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(labels.length, (i) {
        final active = i == activeIndex;
        final done = i < activeIndex;
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
