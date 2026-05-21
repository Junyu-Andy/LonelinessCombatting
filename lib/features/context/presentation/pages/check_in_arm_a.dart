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
import '../../../../core/memory/cross_module_memory.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../analytics/data/analytics_service.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../brief_pr/data/brief_pr_gate.dart';
import '../../../brief_pr/presentation/pages/brief_pr_page.dart';
import '../../../response_feedback/presentation/widgets/thumbs_feedback.dart';
import '../../../reflective_dialogue/data/negative_cognition_detector.dart';
import '../../../thought_exercise/presentation/naming_thought_card.dart';
import '../../../thought_exercise/presentation/thought_exercise_page.dart';
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
  /// Client-side fallback used only when the Cloud Function bundle does
  /// not ship the Siu Yan prompt yet (e.g. functions deployed from an
  /// older revision). Production responses come from the server-side
  /// `siu_yan_v1.txt` resolved by promptKey.
  static const _fallbackPersonaPrompt = '''
你叫小欣，係一個 AI 機械人，唔係真人。每次回覆 1-2 句、reference 用戶啱啱講嘅
具體細節、不分析、不診斷、不重 frame、不建立依賴。
''';

  final _inputCtrl = TextEditingController();
  final List<_Turn> _turns = [];
  final DateTime _sessionStartedAt = DateTime.now();
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

  /// Seeds the conversation with Siu Yan's opening bubble so the
  /// surface reads as a chat from the first frame instead of a
  /// faceless prompt. Localisation is handled here rather than in
  /// initState because Localizations.of needs the inherited context.
  bool _openerSeeded = false;

  /// Active cross-referral suggestion (Sprint 5). Cleared on dismiss
  /// or after the user accepts the handoff.
  SurfacedReferral? _pendingReferral;

  /// Phase A spec §2.6 — Siu Yan's Thought Exercise offer pathway.
  /// **Only Siu Yan** is authorised to surface the TE tool (Hybrid arm
  /// only).  When the negative-cognition detector matches on a user turn,
  /// we cache the matched thought + the assistant turn that preceded it
  /// (for the B.5 audit trigger) and render [NamingThoughtCard] on the
  /// next frame.  The card auto-fills Field 3 of the exercise on accept.
  static const _negCogDetector = NegativeCognitionDetector();
  String? _pendingNamingThought;
  String? _pendingNamingInvitation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analytics = AnalyticsScope.of(context);
    if (!_openerSeeded) {
      _openerSeeded = true;
      final isEn = Localizations.localeOf(context).languageCode == 'en';
      _turns.add(_Turn.bot(isEn
          ? 'Hi — how are you today? Write a few words or speak whenever you\'re ready.'
          : '你好啊。你今日點？寫幾句、或者用咪都得。'));
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    // The opening bot bubble is seeded in didChangeDependencies, so
    // "first turn" here means the first user-authored turn.
    final isFirstTurn = !_turns.any((t) => t.fromUser);
    if (isFirstTurn) {
      await TranscriptConsentPrompter.maybePrompt(
        context: context,
        moduleKey: 'm2_check_in',
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

    // Resolve Siu Yan persona + agent_context suffix. Falls back to a
    // tiny client-side persona prompt if the resolver returns null
    // (e.g. Firebase unavailable during guest mode demo).
    final persona = await core.personaResolver.resolve(
      agentId: AgentRegistry.siuYanId,
      profile: profile,
      includeSharedMood: true,
    );
    final crossModuleInjection = _crossModuleCallbackUsedThisSession
            ?.toSystemPromptInjection(isEn: isEn) ??
        '';
    final contextSuffix = [
      if (persona?.contextSuffix != null) persona!.contextSuffix!,
      if (crossModuleInjection.trim().isNotEmpty) crossModuleInjection.trim(),
      if (profile?.avoidTopics?.isNotEmpty == true)
        '⛔ 用戶要求唔好提起呢啲話題（就算唔小心都唔好）：${profile!.avoidTopics}',
    ].join('\n\n').trim();

    final history = _turns
        .take(_turns.length - 1)
        .map((t) => LlmTurn(fromUser: t.fromUser, text: t.text))
        .toList();
    final response = await core.llm.send(
      moduleId: 'm2_check_in',
      promptKey: persona?.promptKey,
      agentId: persona?.agent.id ?? AgentRegistry.siuYanId,
      systemPrompt: persona == null ? _fallbackPersonaPrompt : null,
      contextSuffix: contextSuffix.isEmpty ? null : contextSuffix,
      history: history,
      userInput: text,
    );

    // Append the user's turn to Siu Yan's short-term buffer so
    // subsequent sessions and cross-agent reads (PersonaResolver) can
    // see it. Honours the per-agent transcript retention flag.
    if (profile != null &&
        profile.consent.transcriptRetentionFor(AgentRegistry.siuYanId)) {
      await core.agentContext.appendTurn(
        uid: profile.uid,
        agentId: AgentRegistry.siuYanId,
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
        _turns.add(_Turn.system(_acuteSafetyMessage()));
      });
      await core.distressRouter.route(response.inputFlag, context: context);
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

    // Persist the assistant turn so the buffer round-trips properly.
    if (profile != null &&
        response.text.isNotEmpty &&
        profile.consent.transcriptRetentionFor(AgentRegistry.siuYanId)) {
      await core.agentContext.appendTurn(
        uid: profile.uid,
        agentId: AgentRegistry.siuYanId,
        turn: AgentContextTurn(
          fromUser: false,
          text: response.text,
          timestamp: DateTime.now(),
        ),
      );
    }

    // Route the higher of the two flags so moderate-on-output still
    // triggers the soft sheet even if input was clean.
    final escalation = _higher(response.inputFlag, response.outputFlag);
    if (escalation.level != DistressLevel.none) {
      await core.distressRouter.route(escalation, context: context);
    }

    // Phase A spec §2.6 — Siu Yan's Thought Exercise offer.  We surface
    // the naming card iff (a) negative cognition matched on this turn,
    // (b) no other card is currently pending, (c) distress hasn't
    // escalated.  Cached invitation = Siu Yan's last assistant reply
    // (B.5 audit-trigger race fix).
    if (_pendingNamingThought == null &&
        _pendingReferral == null &&
        !response.hasEscalation) {
      final match = _negCogDetector.scan(text);
      if (match != null) {
        final lastBot = _turns.lastWhere(
          (t) => !t.fromUser && !t.isSystem,
          orElse: () => _Turn.bot(''),
        );
        setState(() {
          _pendingNamingThought = match.fullTurn;
          _pendingNamingInvitation = lastBot.text;
        });
      }
    }

    // Cross-referral routing (Sprint 5). Skip when a naming card is
    // pending or the conversation has escalated to safety.
    if (_pendingNamingThought == null &&
        _pendingReferral == null &&
        !response.hasEscalation) {
      core.referralRouting.onUserTurn(AgentRegistry.siuYanId);
      final surfaced = await core.referralRouting.maybeSurface(
        sourceAgentId: AgentRegistry.siuYanId,
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
  }

  Future<void> _acceptNaming() async {
    final thought = _pendingNamingThought;
    final invitation = _pendingNamingInvitation;
    if (thought == null) return;
    final profile = AppSettingsScope.read(context).profile;
    setState(() {
      _pendingNamingThought = null;
      _pendingNamingInvitation = null;
    });
    if (mounted) {
      await AnalyticsScope.of(context)
          .logM5ThoughtExerciseOpened(origin: 'siu_yan_offer');
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThoughtExercisePage(
          initialThought: thought,
          agentId: AgentRegistry.siuYanId,
          agentInvitationText: invitation,
          originTurnRef: profile != null
              ? 'users/${profile.uid}/agent_contexts/${AgentRegistry.siuYanId}'
              : null,
        ),
      ),
    );
  }

  void _declineNaming() {
    setState(() {
      _pendingNamingThought = null;
      _pendingNamingInvitation = null;
    });
  }

  DistressMatch _higher(DistressMatch a, DistressMatch b) {
    return a.level.index >= b.level.index ? a : b;
  }

  String _acuteSafetyMessage() {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    // System-voice crisis copy (NOT agent voice).  Deliberately avoids
    // attachment phrasing forbidden in the agent prompts ("我好擔心你"
    // / "我會諗起你") — this is a directive system message shown when
    // the LLM is short-circuited, not Siu Yan speaking.
    return isEn
        ? "What you've just said is heavy. Please call the Samaritans "
            "Hong Kong hotline now: 2896 0000 (24 hours)."
        : '你頭先講嘅嘢好重。請即刻打撒瑪利亞會熱線 2896 0000，'
            '24 小時都有人聽。';
  }

  String _scriptedAck() {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return isEn
        ? 'Thanks for telling me. I\'m here.'
        : '多謝你話畀我知。我喺度。';
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
    await _maybeSurfaceBriefPr();
  }

  Future<void> _maybeSurfaceBriefPr() async {
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) return;
    final exchangeCount = _turns.where((t) => t.fromUser).length;
    final gate = BriefPrGate();
    final shouldShow = await gate.shouldSurfaceBriefPr(
      uid: profile.uid,
      agentId: 'siu_yan',
      sessionStartedAt: _sessionStartedAt,
      exchangeCount: exchangeCount,
    );
    if (!shouldShow || !mounted) return;
    final anchor = await gate.isAnchorPromptFor(
      uid: profile.uid,
      agentId: 'siu_yan',
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BriefPrPage(
          agentId: 'siu_yan',
          agentDisplayName: '小欣',
          isAnchorPrompt: anchor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    final userTurnCount = _turns.where((t) => t.fromUser).length;
    final canEnd = userTurnCount >= 1 && !_saved;
    return FirstIntroOverlay(
      agentId: AgentRegistry.siuYanId,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEn ? 'Today\'s Check-in' : '今日 Check-in'),
          actions: [
            TextButton(
              onPressed: canEnd ? () => _openMoodSheet(isEn) : null,
              child: Text(
                _saved
                    ? (isEn ? 'Saved' : '已儲存')
                    : (isEn ? 'End' : '完成'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  children: [
                    for (int i = 0; i < _turns.length; i++) ...[
                      _TurnBubble(turn: _turns[i]),
                      if (!_turns[i].fromUser && !_turns[i].isSystem)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ThumbsFeedback(
                            agentId: 'siu_yan',
                            moduleId: 'm2_check_in',
                            turnKey: 'turn_$i',
                          ),
                        ),
                    ],
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
                    if (_pendingNamingThought != null)
                      NamingThoughtCard(
                        thought: _pendingNamingThought!,
                        onAccept: _acceptNaming,
                        onDecline: _declineNaming,
                      ),
                    if (_pendingReferral != null)
                      ReferralSuggestionCard(
                        surfaced: _pendingReferral!,
                        handoffExecutor: CoreServicesScope.of(context)
                            .handoffExecutor,
                        sourceAgentId: AgentRegistry.siuYanId,
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

  /// Bottom-sheet mood picker. Surfaces only when the participant
  /// taps "完成" — earlier iterations anchored the picker at the foot
  /// of the chat list which read as visual clutter throughout the
  /// session.
  Future<void> _openMoodSheet(bool isEn) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        var localFace = _face;
        var localPicked = _facePicked;
        var localBusy = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 8,
                bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEn
                        ? 'How would you describe your mood today?'
                        : '你今日心情，揀一個你覺得最似嘅樣？',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  MoodFacePicker(
                    value: localFace,
                    onChanged: (v) => setSheet(() {
                      localFace = v;
                      localPicked = true;
                    }),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: !localPicked || localBusy
                          ? null
                          : () async {
                              setSheet(() => localBusy = true);
                              setState(() {
                                _face = localFace;
                                _facePicked = true;
                              });
                              await _saveSession();
                              if (!ctx.mounted) return;
                              Navigator.of(ctx).pop();
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          isEn ? 'Save check-in' : '儲存今日 Check-in',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: localBusy
                          ? null
                          : () => Navigator.of(ctx).pop(),
                      child: Text(
                        isEn ? 'Not yet' : '未準備好',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
