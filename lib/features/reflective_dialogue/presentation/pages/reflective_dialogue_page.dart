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
import '../../../../core/repair/repair_button.dart';
import '../../../../core/repair/turn_repair_controller.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../../shared/widgets/rich_chat_text.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../brief_pr/data/brief_pr_gate.dart';
import '../../../brief_pr/presentation/pages/brief_pr_page.dart';
import '../../../response_feedback/presentation/widgets/thumbs_feedback.dart';
import '../../data/negative_cognition_detector.dart';

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
  final DateTime _sessionStartedAt = DateTime.now();
  bool _busy = false;
  bool _briefPrSurfaced = false;
  static const _detector = NegativeCognitionDetector();

  /// B.9 — repair controller.  Persists across rebuilds so debounce + click
  /// count survive setState.  Disposed when the page unmounts.
  final TurnRepairController _repair = TurnRepairController();

  /// B.9 — per-turn templates used when the user keeps tapping repair after
  /// the first regenerate.  Plain HK Cantonese / English, no LLM.
  static const _repairTemplates = <List<String>>[
    [
      '對唔住，我未完全捉到你嘅意思。你可唔可以再講多兩句？',
      "I'm sorry — I didn't quite catch what you meant. Could you say more?",
    ],
    [
      '我再聽多次。你而家最想我聽到嘅係邊一part？',
      'Let me listen again. Which part do you most want me to hear?',
    ],
    [
      '我哋慢慢嚟。你寫一句最重要嘅，我就跟住嗰句講。',
      "Let's slow down. Write the one line that matters most and I'll follow it.",
    ],
  ];

  /// Tracks whether we've already issued the gentle "呢個諗法聽落好沉重"
  /// acknowledgement for the current pending negative cognition.  Per
  /// Phase A Proposal §2.2: Ah Jan/Ah Bak briefly acknowledges and
  /// **returns to listening**.  They do NOT surface the Thought Exercise
  /// tool mid-session — that authority is Siu Yan's only.
  bool _negCognitionAcknowledgedThisSession = false;

  /// Active cross-referral surfaced by the routing service. Cleared on
  /// dismiss or after handoff.
  SurfacedReferral? _pendingReferral;

  /// Pre-generated personalised opener for today (if the warm-up on
  /// TodayPage succeeded).  Null = fall back to the generic empty-state
  /// copy.  Loaded once in didChangeDependencies.
  String? _personalisedOpener;
  bool _openerLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_openerLoaded) {
      _openerLoaded = true;
      _loadPersonalisedOpener();
    }
  }

  Future<void> _loadPersonalisedOpener() async {
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) return;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final core = CoreServicesScope.of(context);
    final cached = await core.agentGreeting.readCachedGreeting(
      uid: profile.uid,
      agentId: AgentRegistry.ahJanAhBakId,
      isEn: isEn,
    );
    if (!mounted || cached == null || cached.isEmpty) return;
    setState(() => _personalisedOpener = cached);
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

    final rdContextSuffix = [
      if (persona?.contextSuffix != null) persona!.contextSuffix!,
      if (profile?.avoidTopics?.isNotEmpty == true)
        '⛔ 用戶要求唔好提起呢啲話題（就算唔小心都唔好）：${profile!.avoidTopics}',
    ].join('\n\n').trim();

    final response = await core.llm.send(
      moduleId: 'reflective_dialogue',
      promptKey: persona?.promptKey,
      agentId: AgentRegistry.ahJanAhBakId,
      variantName: persona?.variantName,
      systemPrompt: persona == null ? _fallbackPersonaPrompt : null,
      contextSuffix: rdContextSuffix.isEmpty ? null : rdContextSuffix,
      history: history,
      userInput: text,
      uid: profile?.uid,
      armCode: profile?.arm?.code,
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
    final turnKey = 'turn_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _busy = false;
      _turns.add(_Turn.bot(
        replyText,
        key: turnKey,
        sourceUserInput: text,
      ));
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

    // Phase A spec §2.2: when the user expresses a negative social
    // cognition, Ah Jan/Ah Bak briefly acknowledges the weight of the
    // thought ("呢個諗法聽落好沉重") and returns to listening.  The
    // Thought Exercise is NOT surfaced from this surface — that
    // authority belongs to Siu Yan during M2 daily check-in.
    //
    // We append a one-shot system-style bubble at most once per session
    // so the user feels heard without being repeatedly pathologised.
    if (!_negCognitionAcknowledgedThisSession &&
        _pendingReferral == null &&
        !response.hasEscalation) {
      final match = _detector.scan(text);
      if (match != null) {
        _negCognitionAcknowledgedThisSession = true;
        final ackText = isEn
            ? "That thought sounds heavy. I'll keep listening."
            : '呢個諗法聽落好沉重。我繼續聽你講。';
        setState(() {
          _turns.add(_Turn.bot(ackText));
        });
        // Soft end-of-session pointer: spec §4.2 allows a one-sentence
        // mention in the session summary that the exercise is in 做啲嘢.
        // The summary text is generated by the LLM; we just flag here so
        // the summary builder can include it.  No mid-session offer.
      }
    }

    // Cross-referral routing (Layers 1–3). Only consider when the
    // conversation hasn't escalated to a safety path.
    if (_pendingReferral == null && !response.hasEscalation) {
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

  // System-voice crisis copy.  Avoids attachment phrasing forbidden
  // in agent prompts — this message is shown when the LLM is
  // short-circuited, not Ah Jan/Ah Bak speaking.
  String _acuteSafetyMessage(bool isEn) => isEn
      ? "What you've just said is heavy. Please call Samaritans Hong "
          "Kong now: 2896 0000."
      : '你頭先講嘅嘢好重。請即刻打撒瑪利亞會 2896 0000。';

  /// B.9 — handle a thumbs-down on assistant turn [turn].  First click
  /// re-sends the source input to the LLM with `regenerate: true`; later
  /// clicks advance a rule-based template.  Debounced 2s by the controller.
  Future<void> _handleRepair(_Turn turn) async {
    if (_busy) return;
    final key = turn.key;
    final source = turn.sourceUserInput;
    if (key == null || source == null || source.isEmpty) return;

    final action = _repair.onThumbsDown(key);
    if (action == null) return; // debounced

    final analytics = AnalyticsScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final core = CoreServicesScope.of(context);
    final profile = AppSettingsScope.read(context).profile;

    await analytics.logRepairClicked(
      agentId: AgentRegistry.ahJanAhBakId,
      moduleId: 'reflective_dialogue',
    );

    // Mark the original turn as repaired so we don't show the button again.
    setState(() {
      final idx = _turns.indexWhere((t) => t.key == key);
      if (idx >= 0) _turns[idx] = _turns[idx].markRepaired();
    });

    if (action.isLlmRegenerate) {
      setState(() => _busy = true);
      final persona = await core.personaResolver.resolve(
        agentId: AgentRegistry.ahJanAhBakId,
        profile: profile,
      );
      // Build history that excludes the bad turn but keeps prior context.
      final history = _turns
          .where((t) => t.key != key)
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
        userInput: source,
        uid: profile?.uid,
        armCode: profile?.arm?.code,
        regenerate: true,
      );
      final newText = response.text.trim().isNotEmpty
          ? response.text.trim()
          : _repairTemplates[0][isEn ? 1 : 0];
      final newKey = 'turn_${DateTime.now().microsecondsSinceEpoch}_r';
      setState(() {
        _busy = false;
        _turns.add(_Turn.bot(
          newText,
          key: newKey,
          sourceUserInput: source,
        ));
      });
      await analytics.logRepairCompleted(
        agentId: AgentRegistry.ahJanAhBakId,
        moduleId: 'reflective_dialogue',
        resolution: 'llm_regenerate',
      );
    } else {
      final tpl = _repairTemplates[
          action.templateIndex.clamp(0, _repairTemplates.length - 1)];
      setState(() {
        _turns.add(_Turn.bot(
          tpl[isEn ? 1 : 0],
          key: 'turn_${DateTime.now().microsecondsSinceEpoch}_t',
          sourceUserInput: source,
        ));
      });
      await analytics.logRepairCompleted(
        agentId: AgentRegistry.ahJanAhBakId,
        moduleId: 'reflective_dialogue',
        resolution: 'template_advance',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return FirstIntroOverlay(
      agentId: AgentRegistry.ahJanAhBakId,
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) await _maybeSurfaceBriefPr();
        },
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
                        _personalisedOpener ??
                            (isEn
                                ? 'Whatever\'s on your mind. I\'m here to listen.'
                                : '你想諗咩、想講咩都得，我喺度聽。'),
                        style: theme.textTheme.titleLarge,
                      ),
                    for (int i = 0; i < _turns.length; i++) ...[
                      _TurnBubble(
                        turn: _turns[i],
                        onRepair: _turns[i].fromUser ||
                                _turns[i].isSystem ||
                                _turns[i].repaired
                            ? null
                            : () => _handleRepair(_turns[i]),
                      ),
                      if (!_turns[i].fromUser && !_turns[i].isSystem)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ThumbsFeedback(
                            agentId: 'ah_jan_ah_bak',
                            moduleId: 'reflective_dialogue',
                            turnKey: _turns[i].key ?? 'turn_$i',
                          ),
                        ),
                    ],
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
                    if (_pendingReferral != null)
                      ReferralSuggestionCard(
                        surfaced: _pendingReferral!,
                        handoffExecutor:
                            CoreServicesScope.of(context).handoffExecutor,
                        sourceAgentId: AgentRegistry.ahJanAhBakId,
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
      ),
    );
  }

  Future<void> _maybeSurfaceBriefPr() async {
    if (_briefPrSurfaced) return;
    _briefPrSurfaced = true;
    final profile = AppSettingsScope.read(context).profile;
    if (profile == null) return;
    final exchangeCount = _turns.where((t) => t.fromUser).length;
    final gate = BriefPrGate();
    final shouldShow = await gate.shouldSurfaceBriefPr(
      uid: profile.uid,
      agentId: 'ah_jan_ah_bak',
      sessionStartedAt: _sessionStartedAt,
      exchangeCount: exchangeCount,
    );
    if (!shouldShow || !mounted) return;
    final anchor = await gate.isAnchorPromptFor(
      uid: profile.uid,
      agentId: 'ah_jan_ah_bak',
    );
    if (!mounted) return;
    // Resolve gender variant display name.
    final agent = AgentRegistry.byId(AgentRegistry.ahJanAhBakId);
    final variant = agent.resolveVariant(profile.ahJanAhBakVariant);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BriefPrPage(
          agentId: 'ah_jan_ah_bak',
          agentDisplayName: variant.displayNameZh,
          isAnchorPrompt: anchor,
        ),
      ),
    );
  }
}

class _Turn {
  final bool fromUser;
  final bool isSystem;
  final String text;

  /// Stable key for B.9 repair tracking — assistant turns use a generated
  /// id; user turns use null.
  final String? key;

  /// For assistant turns: the user input that produced this response, used
  /// when re-sending on repair.
  final String? sourceUserInput;

  /// For assistant turns: true once the user has tapped 唔啱意思 on it.
  final bool repaired;

  const _Turn._(this.fromUser, this.isSystem, this.text,
      {this.key, this.sourceUserInput, this.repaired = false});

  factory _Turn.user(String t) => _Turn._(true, false, t);
  factory _Turn.bot(String t, {String? key, String? sourceUserInput}) =>
      _Turn._(false, false, t, key: key, sourceUserInput: sourceUserInput);
  factory _Turn.system(String t) => _Turn._(false, true, t);

  _Turn markRepaired() => _Turn._(fromUser, isSystem, text,
      key: key, sourceUserInput: sourceUserInput, repaired: true);
}

class _TurnBubble extends StatelessWidget {
  final _Turn turn;

  /// B.9 — when non-null, render a 唔啱意思 button below the bubble.  Null
  /// for user turns, system turns, and bubbles already repaired.
  final VoidCallback? onRepair;

  const _TurnBubble({required this.turn, this.onRepair});

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
      child: Column(
        crossAxisAlignment: turn.fromUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18),
            ),
            child: RichChatText(
              text: turn.text,
              style: TextStyle(fontSize: 17, height: 1.4, color: fg),
            ),
          ),
          if (onRepair != null) RepairButton(onTap: onRepair!),
        ],
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
