/// On-demand reflective dialogue with Ah Jan / Ah Bak (Walkthrough
/// Case 5; Dev Req §M5 merge).
///
/// Differs from the weekly reminiscence surface in three ways:
///   1. No theme lock — the conversation is open-ended.
///   2. The "name the thought" tool is enabled (Walkthrough Case 5).
///   3. Sessions are user-initiated, not driven by the 4-week curriculum.
///
/// All other behaviour (persona, agent_context buffer, distress
/// detection, transcript-retention nudge) inherits from the same
/// gateway path as the reminiscence surface.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agent_context/agent_context_service.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/agents/first_intro_overlay.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/cross_referral/referral_routing_service.dart';
import '../../../../core/cross_referral/referral_suggestion_card.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/llm/transcript_consent_prompter.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../data/negative_cognition_detector.dart';
import 'thought_record_exercise_page.dart';

class ReflectiveDialoguePage extends StatefulWidget {
  const ReflectiveDialoguePage({super.key});

  @override
  State<ReflectiveDialoguePage> createState() => _ReflectiveDialoguePageState();
}

class _ReflectiveDialoguePageState extends State<ReflectiveDialoguePage> {
  /// Tiny client fallback so this page is renderable when the cloud
  /// function bundle doesn't yet ship Ah Jan / Ah Bak's prompt.
  static const _fallbackPersonaPrompt = '''
你叫阿珍／阿伯，係 reflective peer-listener。每次回覆 1-2 句，
reference 用戶具體細節，唔分析、唔解讀、唔重 frame。
''';

  final _inputCtrl = TextEditingController();
  final List<_Turn> _turns = [];
  bool _busy = false;
  static const _detector = NegativeCognitionDetector();

  /// The last user turn that surfaced a negative-cognition match — we
  /// only show one naming card per conversation per match so the user
  /// isn't repeatedly nudged on the same thought.
  String? _pendingNamingThought;

  /// Active cross-referral surfaced by the routing service. Cleared on
  /// dismiss or after handoff.
  SurfacedReferral? _pendingReferral;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    final isFirstTurn = _turns.isEmpty;
    if (isFirstTurn) {
      await TranscriptConsentPrompter.maybePrompt(
        context: context,
        moduleKey: 'reflective_dialogue',
      );
      if (!mounted) return;
    }
    setState(() {
      _busy = true;
      _turns.add(_Turn.user(text));
      _inputCtrl.clear();
    });
    final core = CoreServicesScope.of(context);
    final profile = AppSettingsScope.read(context).profile;
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    // Resolve Ah Jan / Ah Bak persona (variant aware).
    final persona = await core.personaResolver.resolve(
      agentId: AgentRegistry.ahJanAhBakId,
      profile: profile,
    );

    final history = _turns
        .take(_turns.length - 1)
        .map((t) => LlmTurn(fromUser: t.fromUser, text: t.text))
        .toList();

    final response = await core.llm.send(
      moduleId: 'reflective_dialogue',
      promptKey: persona?.promptKey,
      agentId: AgentRegistry.ahJanAhBakId,
      variantName: persona?.variantName,
      systemPrompt: persona == null ? _fallbackPersonaPrompt : null,
      contextSuffix: persona?.contextSuffix,
      history: history,
      userInput: text,
    );

    if (profile != null &&
        profile.consent.transcriptRetentionFor(AgentRegistry.ahJanAhBakId)) {
      await core.agentContext.appendTurn(
        uid: profile.uid,
        agentId: AgentRegistry.ahJanAhBakId,
        turn: AgentContextTurn(
          fromUser: true,
          text: text,
          timestamp: DateTime.now(),
        ),
      );
    }

    if (!mounted) return;
    if (response.shortCircuited) {
      setState(() {
        _busy = false;
        _turns.add(_Turn.system(_acuteSafetyMessage(isEn)));
      });
      await core.distressRouter.route(response.inputFlag, context: context);
      return;
    }

    final replyText = response.text.trim().isNotEmpty
        ? response.text.trim()
        : (isEn
            ? 'I\'m listening. Tell me more whenever you\'re ready.'
            : '我喺度聽緊。你準備好嗰陣再講多啲都得。');
    setState(() {
      _busy = false;
      _turns.add(_Turn.bot(replyText));
    });

    if (profile != null &&
        response.text.trim().isNotEmpty &&
        profile.consent.transcriptRetentionFor(AgentRegistry.ahJanAhBakId)) {
      await core.agentContext.appendTurn(
        uid: profile.uid,
        agentId: AgentRegistry.ahJanAhBakId,
        turn: AgentContextTurn(
          fromUser: false,
          text: replyText,
          timestamp: DateTime.now(),
        ),
      );
    }

    // Negative-cognition check on the user's last turn. We only surface
    // the naming card if (a) we matched, (b) no other card is currently
    // pending, and (c) distress hasn't escalated this turn.
    if (_pendingNamingThought == null &&
        _pendingReferral == null &&
        !response.hasEscalation) {
      final match = _detector.scan(text);
      if (match != null) {
        setState(() {
          _pendingNamingThought = match.fullTurn;
        });
      }
    }

    // Cross-referral routing (Layers 1–3). Only consider when no
    // naming card is showing this turn and the conversation hasn't
    // escalated to a safety path.
    if (_pendingNamingThought == null &&
        _pendingReferral == null &&
        !response.hasEscalation) {
      core.referralRouting.onUserTurn(AgentRegistry.ahJanAhBakId);
      final surfaced = await core.referralRouting.maybeSurface(
        sourceAgentId: AgentRegistry.ahJanAhBakId,
        profile: profile,
        userTurn: text,
        recentTurns: _turns
            .map((t) => LlmTurn(fromUser: t.fromUser, text: t.text))
            .toList(),
        localeCode: isEn ? 'en' : 'zh',
      );
      if (mounted && surfaced != null) {
        setState(() => _pendingReferral = surfaced);
      }
    }

    final escalation = _higher(response.inputFlag, response.outputFlag);
    if (escalation.level != DistressLevel.none) {
      await core.distressRouter.route(escalation, context: context);
    }
  }

  DistressMatch _higher(DistressMatch a, DistressMatch b) {
    return a.level.index >= b.level.index ? a : b;
  }

  String _acuteSafetyMessage(bool isEn) => isEn
      ? 'I hear how heavy this is. Please call Samaritans Hong Kong at '
          '2896 0000 right now.'
      : '聽到你咁講，我好擔心你。請即刻打撒瑪利亞會 2896 0000。';

  Future<void> _acceptNaming() async {
    final thought = _pendingNamingThought;
    if (thought == null) return;
    setState(() => _pendingNamingThought = null);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThoughtRecordExercisePage(
          initialThought: thought,
          originSurface: 'reflective_dialogue',
        ),
      ),
    );
  }

  void _declineNaming() {
    setState(() => _pendingNamingThought = null);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return FirstIntroOverlay(
      agentId: AgentRegistry.ahJanAhBakId,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEn ? 'Reflective chat' : '反思傾偈'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  children: [
                    if (_turns.isEmpty)
                      Text(
                        isEn
                            ? 'Whatever\'s on your mind. I\'m here to listen.'
                            : '你想諗咩、想講咩都得，我喺度聽。',
                        style: theme.textTheme.titleLarge,
                      ),
                    for (final t in _turns) _TurnBubble(turn: t),
                    if (_busy)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    if (_pendingNamingThought != null)
                      _NamingCard(
                        thought: _pendingNamingThought!,
                        onAccept: _acceptNaming,
                        onDecline: _declineNaming,
                      ),
                    if (_pendingReferral != null)
                      ReferralSuggestionCard(
                        surfaced: _pendingReferral!,
                        handoffExecutor:
                            CoreServicesScope.of(context).handoffExecutor,
                        onDismiss: () =>
                            setState(() => _pendingReferral = null),
                      ),
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
    final color = turn.fromUser
        ? theme.colorScheme.primaryContainer
        : turn.isSystem
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.secondaryContainer;
    final fg = turn.fromUser
        ? theme.colorScheme.onPrimaryContainer
        : turn.isSystem
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onSecondaryContainer;
    return Align(
      alignment:
          turn.fromUser ? Alignment.centerRight : Alignment.centerLeft,
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

class _NamingCard extends StatelessWidget {
  final String thought;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _NamingCard({
    required this.thought,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEn
                    ? 'You just said a thought.'
                    : '你啱啱講咗一個諗法。',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isEn
                    ? 'Would you like to open a small exercise to look at '
                        'that thought?'
                    : '想唔想開個小練習睇下呢個諗法？',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onAccept,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(isEn ? 'Open the exercise' : '開練習'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDecline,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(isEn ? 'Not now' : '唔使住'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
                maxLines: 5,
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
