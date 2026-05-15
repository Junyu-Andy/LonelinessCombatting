import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/memory/cross_module_memory.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../analytics/data/analytics_service.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import 'check_in_shared.dart';

/// M2 — hybrid check-in (Arm A). Free-text or voice opener, LLM produces
/// a brief empathetic reflection + at most one adaptive follow-up. The
/// six-face mood picker is shown as an optional structured tail.
class CheckInArmA extends StatefulWidget {
  const CheckInArmA({super.key});

  @override
  State<CheckInArmA> createState() => _CheckInArmAState();
}

class _CheckInArmAState extends State<CheckInArmA> {
  static const _systemPrompt = '''
You are 阿暖, a warm, attentive companion in a research-grade mHealth app for
older adults in Hong Kong. The user has just told you how they are today.

Rules:
- Reply in plain Cantonese-friendly Traditional Chinese unless the user wrote
  in English (then reply in English).
- 1–2 sentences max. Reflect what they said, naming a specific detail.
- Then ask ONE gentle follow-up question — only if their note was brief or
  surfaced something worth exploring. Otherwise just acknowledge.
- Never advise. Never diagnose. Never reframe their feeling. Do not say
  "you must have felt..." or "try to think positively".
- Never claim to be a doctor or a person. You are a digital companion.
''';

  final _inputCtrl = TextEditingController();
  final List<_Turn> _turns = [];
  bool _busy = false;
  MoodFace _face = MoodFace.neutral;
  bool _facePicked = false;
  bool _saved = false;
  AnalyticsService? _analytics;

  /// Set on the *first* user turn if the cross-module callback budget
  /// resolved a candidate. We surface this in the system prompt and
  /// record it on save so we can audit how often M2 actually wove M3
  /// content into a reply.
  CrossModuleCallback? _crossModuleCallbackUsedThisSession;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analytics = AnalyticsScope.of(context);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    final isFirstTurn = _turns.isEmpty;
    setState(() {
      _busy = true;
      _turns.add(_Turn.user(text));
      _inputCtrl.clear();
    });
    final core = CoreServicesScope.of(context);
    final profile = AppSettingsScope.read(context).profile;
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    // Cross-module callback (Layer 3): on the user's *first* turn,
    // ask the budget service whether M2 may lightly reference recent
    // M3 reminiscence content. Subsequent turns reuse whatever the
    // first turn resolved so the LLM keeps consistent context.
    if (isFirstTurn && profile != null) {
      final inputFlag = core.distress.analyze(text);
      _crossModuleCallbackUsedThisSession =
          await core.crossModuleMemory.getEligibleCallback(
        uid: profile.uid,
        forModuleFamily: 'm2',
        candidateSourceModuleIds: const [
          'm3_reminiscence_w4',
          'm3_reminiscence_w3',
          'm3_reminiscence_w2',
          'm3_reminiscence_w1',
        ],
        currentTurnDistress: inputFlag.level,
      );
      if (_crossModuleCallbackUsedThisSession != null) {
        // Conservative: mark used even if the LLM ignores the hint.
        await core.crossModuleMemory.markUsed(
          uid: profile.uid,
          forModuleFamily: 'm2',
          callback: _crossModuleCallbackUsedThisSession!,
        );
      }
    }

    final systemPrompt = _systemPrompt +
        (_crossModuleCallbackUsedThisSession
                ?.toSystemPromptInjection(isEn: isEn) ??
            '');

    final history = _turns
        .take(_turns.length - 1)
        .map((t) => LlmTurn(fromUser: t.fromUser, text: t.text))
        .toList();
    final response = await core.llm.send(
      moduleId: 'm2_check_in',
      systemPrompt: systemPrompt,
      history: history,
      userInput: text,
    );
    if (!mounted) return;
    if (response.shortCircuited) {
      setState(() {
        _busy = false;
        _turns.add(_Turn.system(_acuteSafetyMessage()));
      });
      _showSafetySheet();
      return;
    }
    setState(() {
      _busy = false;
      if (response.text.isNotEmpty) {
        _turns.add(_Turn.bot(response.text));
      } else {
        // No API key configured — keep the flow moving with a scripted
        // acknowledgement so the screen isn't dead.
        _turns.add(_Turn.bot(_scriptedAck()));
      }
    });
    if (response.inputFlag.level == DistressLevel.moderate ||
        response.outputFlag.level == DistressLevel.moderate) {
      _showSafetySheet();
    }
  }

  String _acuteSafetyMessage() {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return isEn
        ? 'I hear how hard this is. Please call Samaritans Hong Kong at '
            '2896 0000 right now — they are open 24 hours.'
        : '聽到你咁講，我好擔心你。請即刻打撒瑪利亞會熱線 2896 0000，'
            '24 小時都有人聽。';
  }

  String _scriptedAck() {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return isEn
        ? 'Thanks for telling me. I\'m here.'
        : '多謝你話畀我知。我喺度。';
  }

  void _showSafetySheet() {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEn ? 'You\'re not alone' : '你唔係一個人',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              isEn
                  ? 'Samaritans Hong Kong · 2896 0000 (24h)\n'
                      'Suicide Prevention Services · 2382 0000'
                  : '撒瑪利亞會 · 2896 0000（24小時）\n'
                      '生命熱線 · 2382 0000',
              style: const TextStyle(fontSize: 18, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(isEn ? 'Close' : '知道'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSession() async {
    final core = CoreServicesScope.of(context);
    final profile = AppSettingsScope.read(context).profile;
    if (profile != null && _turns.isNotEmpty) {
      final summary = _turns
          .where((t) => t.fromUser)
          .map((t) => t.text)
          .join('\n');
      final callback = _crossModuleCallbackUsedThisSession;
      await core.memory.writeSummary(
        uid: profile.uid,
        moduleId: 'm2_check_in',
        summary: summary,
        armCode: 'A',
        hasTranscriptConsent: profile.consent.transcriptRetention,
        tags: [
          if (_facePicked) 'mood:${_face.name}',
          if (callback != null) 'cross_callback:${callback.sourceFamily}',
        ],
      );
    }
    _analytics?.logCheckIn(
      mood: _face.numericScore,
      loneliness: 3,
      socialEnergy: 3,
    );
    if (!mounted) return;
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Today\'s Check-in' : '今日 Check-in')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                children: [
                  if (_turns.isEmpty)
                    Text(
                      isEn
                          ? 'How are you today? Write a few words or speak.'
                          : '你今日點呀？寫幾個字、或者講都得。',
                      style: theme.textTheme.titleLarge,
                    ),
                  for (final t in _turns) _TurnBubble(turn: t),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  if (_turns.length >= 2) ...[
                    const SizedBox(height: 16),
                    Text(
                      isEn
                          ? 'One last thing — how would you describe your '
                              'mood today?'
                          : '最後一條 —— 你今日心情，揀一個你覺得最似嘅樣？',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    MoodFacePicker(
                      value: _face,
                      onChanged: (v) => setState(() {
                        _face = v;
                        _facePicked = true;
                      }),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _saved ? null : _saveSession,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          _saved
                              ? (isEn ? 'Saved' : '已儲存')
                              : (isEn ? 'Save check-in' : '儲存今日 Check-in'),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _Composer(
              controller: _inputCtrl,
              busy: _busy,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Turn {
  final bool fromUser;
  final bool isSystem;
  final String text;
  const _Turn._(this.fromUser, this.isSystem, this.text);
  factory _Turn.user(String t) => _Turn._(true, false, t);
  factory _Turn.bot(String t) => _Turn._(false, false, t);
  factory _Turn.system(String t) => _Turn._(false, true, t);
}

class _TurnBubble extends StatelessWidget {
  final _Turn turn;
  const _TurnBubble({required this.turn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final align = turn.fromUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = turn.fromUser
        ? theme.colorScheme.primaryContainer
        : turn.isSystem
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest;
    final fg = turn.fromUser
        ? theme.colorScheme.onPrimaryContainer
        : turn.isSystem
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onSurface;
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(turn.text,
            style: TextStyle(fontSize: 17, height: 1.4, color: fg)),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: Theme.of(context).dividerColor, width: 1)),
        ),
        child: Row(
          children: [
            VoiceInputButton(
              prefix: () => controller.text,
              onText: (t) => controller.text = t,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(
                  hintText: isEn ? 'Type or speak…' : '寫或者講都得…',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: busy ? null : onSend,
              icon: const Icon(Icons.arrow_upward_rounded),
              iconSize: 28,
            ),
          ],
        ),
      ),
    );
  }
}
