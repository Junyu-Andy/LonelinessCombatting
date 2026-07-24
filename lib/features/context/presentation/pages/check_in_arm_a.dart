import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agent_context/agent_context_service.dart';
import '../../../../core/agent_context/rolling_summary_compiler.dart';
import '../../../../core/agent_context/shared_context_service.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/agents/first_intro_overlay.dart';
import '../../../../core/connectivity/connectivity_service.dart';
import '../../../../core/connectivity/offline_pending_banner.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/cross_referral/referral_routing_service.dart';
import '../../../../core/cross_referral/referral_suggestion_card.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/llm/transcript_consent_prompter.dart';
import '../../../../core/memory/cross_module_memory.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../../shared/widgets/rich_chat_text.dart';
import '../../../../shared/widgets/composer_send_button.dart';
import '../../../analytics/data/analytics_service.dart';
import '../../../analytics/presentation/analytics_scope.dart';
import '../../../brief_pr/data/brief_pr_gate.dart';
import '../../../brief_pr/presentation/pages/brief_pr_page.dart';
import '../../../response_feedback/presentation/widgets/thumbs_feedback.dart';
import '../../../reflective_dialogue/data/negative_cognition_detector.dart';
import '../../../thought_exercise/presentation/naming_thought_card.dart';
import '../../../thought_exercise/presentation/thought_exercise_page.dart';
import '../../../today/data/mood_recorder.dart';
import 'check_in_shared.dart';

/// M2 — hybrid check-in (Arm A). Free-text or voice opener, LLM produces
/// a brief empathetic reflection + at most one adaptive follow-up. The
/// six-face mood picker is shown as an optional structured tail.
class CheckInArmA extends StatefulWidget {
  /// Optional mood face the user just picked on the home hero mood
  /// pad.  When set, Siu Yan's opener references it instead of the
  /// generic "你今日點？" so the handoff doesn't feel like the agent
  /// forgot.  1=好差, 2=差, 3=麻麻地, 4=幾好, 5=好好.
  final int? initialMoodValue;

  /// The mood the user had *before* [initialMoodValue] on the same day,
  /// when this check-in was launched from the home "your mood changed"
  /// prompt. Lets Siu Yan's opener name the change (better / worse).
  final int? previousMoodValue;

  const CheckInArmA({
    super.key,
    this.initialMoodValue,
    this.previousMoodValue,
  });

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
  final _voice = VoiceInputController();
  final List<_Turn> _turns = [];
  final DateTime _sessionStartedAt = DateTime.now();

  // Offline resend: a message typed while offline is held here (shown as a
  // banner, not added to the transcript) and auto-sent when connectivity
  // returns, so nothing is silently lost.
  final _connectivity = ConnectivityService();
  String? _pendingOffline;
  StreamSubscription<bool>? _connSub;

  // The user text currently in flight, so a send failure can roll the
  // bubble back and restore the composer (see _failSend).
  String? _inFlightText;

  bool _busy = false;
  MoodFace _face = MoodFace.neutral;
  bool _facePicked = false;
  bool _saved = false;
  AnalyticsService? _analytics;

  /// Decision A — the check-in asks for today's mood FIRST (a blocking
  /// gate) when it isn't already known, then opens the conversation; the
  /// end-of-session sheet no longer re-asks.  A mood already logged today
  /// (home pad / earlier) skips the gate entirely.
  bool _resolvingMood = true; // true until we know if today's mood exists
  bool _moodGateResolved = false;
  MoodFace? _gateFace; // selection inside the mood gate

  /// B04 — mood value (1..5) that is already stored in `daily_mood` for
  /// today (via the home pad or an earlier session).  At save time we
  /// only write a new `daily_mood` entry when the face the user ends
  /// with differs from this, so the check-in flows into the day summary
  /// without double-recording the home-pad pick.
  int? _moodValueAlreadyInDailyMood;

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

  /// Mood value (1..5) used to phrase the opener.  Resolved from (in
  /// priority order) the explicit `initialMoodValue`, today's
  /// `daily_mood` doc, or the most recent `daily_mood` doc.  Null
  /// means we have no mood history and fall back to a generic opener.
  int? _resolvedMoodValue;

  /// True iff `_resolvedMoodValue` came from today's record — controls
  /// whether the opener phrases it as "you said today …" or "last time
  /// you said …".
  bool _resolvedMoodIsToday = true;

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
      if (widget.initialMoodValue != null) {
        // Came in straight from the home mood pad — use the face the
        // user just tapped and seed synchronously so the chat reads as
        // immediate.
        _resolvedMoodValue = widget.initialMoodValue;
        _resolvedMoodIsToday = true;
        _face = _faceFromValue(widget.initialMoodValue!);
        _facePicked = true;
        // The home pad recorded this pick to daily_mood already.
        _moodValueAlreadyInDailyMood = widget.initialMoodValue;
        _resolvingMood = false;
        _moodGateResolved = true;
        final prev = widget.previousMoodValue;
        _turns.add(_Turn.bot(
          (prev != null && prev != widget.initialMoodValue)
              ? _moodChangeOpener(isEn, prev, widget.initialMoodValue!)
              : _openingLine(isEn),
        ));
      } else {
        // Entered via the agent tile — look up today's mood first; if
        // none, fall back to the most recent record so Siu Yan can at
        // least say "上次你話麻麻地".
        unawaited(_resolveMoodAndSeedOpener(isEn));
      }
    }
  }

  Future<void> _resolveMoodAndSeedOpener(bool isEn) async {
    final profile = AppSettingsScope.read(context).profile;
    int? moodValue;
    bool fromToday = true;
    if (profile != null) {
      final recorder = MoodRecorder();
      final today = await recorder.latestForDate(
        uid: profile.uid,
        dateIso: MoodRecorder.dateIsoFor(DateTime.now()),
      );
      if (today != null) {
        moodValue = today.mood;
        fromToday = true;
      } else {
        final recent = await recorder.mostRecent(uid: profile.uid);
        if (recent != null) {
          moodValue = recent.mood;
          fromToday = false;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _resolvingMood = false;
      _resolvedMoodValue = moodValue;
      _resolvedMoodIsToday = fromToday;
      if (moodValue != null && fromToday) {
        // Already logged today → skip the gate, straight to conversation.
        _face = _faceFromValue(moodValue);
        _facePicked = true;
        _moodValueAlreadyInDailyMood = moodValue;
        _moodGateResolved = true;
        _turns.add(_Turn.bot(_openingLine(isEn)));
      } else {
        // Not logged today → show the mood gate first; the opener is
        // seeded once the user picks (see _onGatePicked).
        _moodGateResolved = false;
      }
    });
  }

  /// Decision A — user picked a face in the mood gate: record it, seed the
  /// opener referencing today's mood, and reveal the conversation.
  void _onGatePicked() {
    final face = _gateFace;
    if (face == null) return;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final profile = AppSettingsScope.read(context).profile;
    if (profile != null) {
      final v = face.numericScore;
      // Fire-and-forget (offline-safe) so the mood is captured even if the
      // conversation is abandoned right after.
      unawaited(() async {
        try {
          await MoodRecorder().record(
            uid: profile.uid,
            mood: v,
            arm: 'A',
            sourceSurface: 'check_in_a_gate',
          );
        } catch (_) {}
      }());
    }
    setState(() {
      _face = face;
      _facePicked = true;
      _moodValueAlreadyInDailyMood = face.numericScore;
      _resolvedMoodValue = face.numericScore;
      _resolvedMoodIsToday = true;
      _moodGateResolved = true;
      _turns.add(_Turn.bot(_openingLine(isEn)));
    });
  }

  String _openingLine(bool isEn) {
    final mood = _resolvedMoodValue;
    if (mood == null) {
      return isEn
          ? 'Hi — how are you today? Write a few words or speak whenever you\'re ready.'
          : '你好啊。你今日點？寫幾句、或者用咪都得。';
    }
    if (_resolvedMoodIsToday) {
      if (isEn) {
        switch (mood) {
          case 1:
            return 'I saw you marked today as quite hard. I\'m here — take your time, what\'s weighing on you?';
          case 2:
            return 'You said today doesn\'t feel great. Want to tell me a bit more about what\'s going on?';
          case 3:
            return 'So-so today. Want to share what\'s on your mind, big or small?';
          case 4:
            return 'You said today feels okay. What\'s been the best part so far?';
          case 5:
            return 'You said today\'s been good! Tell me what made it nice.';
        }
      }
      switch (mood) {
        case 1:
          return '見到你話今日好差。我喺度，慢慢講，係咩事令你咁辛苦呀？';
        case 2:
          return '你話今日差咗，係邊方面唔舒服呀？同我講多少少。';
        case 3:
          return '麻麻地嘅一日，腦海入面有咩想講，無論大小都得。';
        case 4:
          return '你話今日幾好。咁今日最好嘅一刻係咩呢？';
        case 5:
          return '你話今日好好喎！同我講下係咩令你咁開心？';
      }
    } else {
      // Most-recent (non-today) mood — phrase as "last time you said …
      // how about today?" so the opener still asks for fresh input.
      if (isEn) {
        switch (mood) {
          case 1:
            return 'Last time you marked things as quite hard. How are you doing today?';
          case 2:
            return 'Last time felt bad. How\'s today — any different?';
          case 3:
            return 'Last time was so-so. What about today?';
          case 4:
            return 'Last time felt okay. How\'s today going?';
          case 5:
            return 'Last time was good! How\'s today shaping up?';
        }
      }
      switch (mood) {
        case 1:
          return '上次你話好辛苦。今日點呀？同我講少少。';
        case 2:
          return '上次你話差咗少少。今日好啲未呀？';
        case 3:
          return '上次麻麻地。今日有冇好啲？';
        case 4:
          return '上次你話幾好。今日呢？';
        case 5:
          return '上次你話好好。今日仲係咁好嗎？';
      }
    }
    return isEn
        ? 'Hi — what\'s on your mind today?'
        : '你好啊。你今日點？';
  }

  /// Opener when the user just changed their mood on the home pad —
  /// names the shift (better / worse) using the last and current faces.
  String _moodChangeOpener(bool isEn, int from, int to) {
    final fromLabel = _faceFromValue(from).label(isEn);
    final toLabel = _faceFromValue(to).label(isEn);
    final better = to > from;
    if (isEn) {
      return better
          ? 'Earlier you felt "$fromLabel", and now "$toLabel" — glad to hear. '
              'What changed?'
          : 'Earlier you felt "$fromLabel", and now "$toLabel". Want to tell '
              'me what happened?';
    }
    return better
        ? '你頭先話「$fromLabel」，而家「$toLabel」咗喎，係咩令你好啲咗？'
        : '你頭先話「$fromLabel」，而家變咗「$toLabel」。發生咗咩事？同我講下。';
  }

  MoodFace _faceFromValue(int v) {
    switch (v) {
      case 1:
        return MoodFace.veryLow;
      case 2:
        return MoodFace.low;
      case 3:
        return MoodFace.neutral;
      case 4:
        return MoodFace.good;
      case 5:
        return MoodFace.great;
    }
    return MoodFace.neutral;
  }

  @override
  void initState() {
    super.initState();
    // When connectivity returns, auto-send anything queued while offline.
    _connSub = _connectivity.onStatusChange.listen((online) {
      if (online && _pendingOffline != null && mounted) _resendPending();
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _inputCtrl.dispose();
    super.dispose();
  }

  /// Re-send the message queued while offline through the normal path
  /// (which adds the user turn + calls the LLM), now that we're online.
  void _resendPending() {
    final t = _pendingOffline;
    if (t == null) return;
    setState(() => _pendingOffline = null);
    _inputCtrl.text = t;
    _send();
  }

  /// Wrapper so ANY throw inside the send pipeline can't strand
  /// `_busy = true` and permanently dead the composer. Classified failures
  /// surface as a system bubble with an error code instead of vanishing.
  Future<void> _send() async {
    try {
      await _sendInner();
    } on LlmFailureException catch (e) {
      _failSend(e.failure);
    } catch (e) {
      if (kDebugMode) debugPrint('[check_in_a] send failed: $e');
      _failSend(LlmFailure(LlmFailureCode.unknown, e.toString()));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  /// Roll the UI back to the pre-send state — in-flight user bubble
  /// removed, text restored to the composer so one tap resends — and
  /// surface the failure as a system bubble carrying its error code.
  void _failSend(LlmFailure f) {
    if (!mounted) return;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    setState(() {
      final t = _inFlightText;
      if (t != null) {
        final i = _turns.lastIndexWhere((x) => x.fromUser && x.text == t);
        if (i != -1) _turns.removeAt(i);
        if (_inputCtrl.text.trim().isEmpty) _inputCtrl.text = t;
        _inFlightText = null;
      }
      _turns.add(_Turn.system(f.userMessage(isEn)));
    });
  }

  Future<void> _sendInner() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    // Offline → hold the message (banner) and auto-send on reconnect instead
    // of firing an LLM call that silently fails with no reply.
    if (!await _connectivity.isOnline()) {
      if (!mounted) return;
      setState(() {
        _pendingOffline =
            _pendingOffline == null ? text : '$_pendingOffline\n$text';
        _inputCtrl.clear();
      });
      return;
    }
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
      _inFlightText = text;
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
      _crossModuleCallbackUsedThisSession = await guardFirestore(
        () => core.crossModuleMemory.getEligibleCallback(
          uid: profile.uid,
          forModuleFamily: 'm2',
          candidateSourceModuleIds: const [
            'm3_reminiscence_w4',
            'm3_reminiscence_w3',
            'm3_reminiscence_w2',
            'm3_reminiscence_w1',
          ],
          currentTurnDistress: inputFlag.level,
        ),
      );
      if (_crossModuleCallbackUsedThisSession != null) {
        // Conservative: mark used even if the LLM ignores the hint.
        await persistQuietly(
          'check_in_a',
          () => core.crossModuleMemory.markUsed(
            uid: profile.uid,
            forModuleFamily: 'm2',
            callback: _crossModuleCallbackUsedThisSession!,
          ),
        );
      }
    }

    // Resolve Siu Yan persona + agent_context suffix. Falls back to a
    // tiny client-side persona prompt if the resolver returns null
    // (e.g. Firebase unavailable during guest mode demo).
    final persona = await guardFirestore(
      () => core.personaResolver.resolve(
        agentId: AgentRegistry.siuYanId,
        profile: profile,
        includeSharedMood: true,
      ),
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
      agentContextSnapshot: persona?.agentContextSnapshot,
      history: history,
      userInput: text,
      uid: profile?.uid,
    );

    // Transport failure → roll back and show the coded error bubble
    // instead of masquerading as a scripted ack.
    if (response.failure != null) {
      throw LlmFailureException(response.failure!);
    }

    // Append the user's turn to Siu Yan's short-term buffer so
    // subsequent sessions and cross-agent reads (PersonaResolver) can
    // see it. Honours the per-agent transcript retention flag.
    // Non-fatal: a persistence hiccup must not discard the reply we
    // already have.
    if (profile != null &&
        profile.consent.transcriptRetentionFor(AgentRegistry.siuYanId)) {
      await persistQuietly(
        'check_in_a',
        () => core.agentContext.appendTurn(
          uid: profile.uid,
          agentId: AgentRegistry.siuYanId,
          turn: AgentContextTurn(
            fromUser: true,
            text: text,
            timestamp: DateTime.now(),
          ),
        ),
      );
    }
    if (!mounted) return;
    if (response.shortCircuited) {
      setState(() {
        _busy = false;
        _inFlightText = null;
        _turns.add(_Turn.system(_acuteSafetyMessage()));
      });
      await core.distressRouter.route(response.inputFlag, context: context);
      return;
    }
    setState(() {
      _busy = false;
      _inFlightText = null;
      if (response.text.isNotEmpty) {
        _turns.add(_Turn.bot(response.text,
            promptHash: response.metadata.systemPromptHash));
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
      await persistQuietly(
        'check_in_a',
        () => core.agentContext.appendTurn(
          uid: profile.uid,
          agentId: AgentRegistry.siuYanId,
          turn: AgentContextTurn(
            fromUser: false,
            text: response.text,
            timestamp: DateTime.now(),
          ),
        ),
      );
    }

    // Route the higher of the two flags so moderate-on-output still
    // triggers the soft sheet even if input was clean.
    final escalation = _higher(response.inputFlag, response.outputFlag);
    if (escalation.level != DistressLevel.none) {
      await core.distressRouter.route(escalation, context: context);
    }
    if (!mounted) return;

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
      // Fire-and-forget: offline, Firestore write futures wait for
      // server ack — awaiting them froze the mood sheet's save button
      // forever.  The SDK queues the writes and syncs later.
      unawaited(() async {
        try {
          await core.memory.writeSummary(
            uid: profile.uid,
            moduleId: 'm2_check_in',
            summary: summary,
            armCode: 'A',
            hasTranscriptConsent: profile.consent.transcriptRetention,
            tags: [
              if (_facePicked) 'mood:${_face.name}',
              if (callback != null)
                'cross_callback:${callback.sourceFamily}',
            ],
          );
        } catch (_) {}
      }());
    }

    // B04 — flow the end-of-session mood into daily_mood so the home
    // hero + weekly recap reflect the check-in.  Skipped when the same
    // value is already recorded for today (home-pad pick), so we don't
    // double-write; a *changed* face becomes a supplementary entry.
    if (profile != null &&
        _facePicked &&
        _face.numericScore != _moodValueAlreadyInDailyMood) {
      final moodToRecord = _face.numericScore;
      _moodValueAlreadyInDailyMood = moodToRecord;
      unawaited(() async {
        try {
          await MoodRecorder().record(
            uid: profile.uid,
            mood: moodToRecord,
            arm: 'A',
            sourceSurface: 'check_in_a',
          );
        } catch (_) {
          // The analytics event below still captures the value.
        }
      }());
    }

    // §1C — update the shared recent-mood snippet (no LLM; straight from the
    // mood the user just logged) so other agents can reference it gently.
    if (profile != null && _facePicked) {
      final moodScore = _face.numericScore;
      unawaited(() async {
        try {
          await core.sharedContext.updateRecentMood(
            uid: profile.uid,
            mood: SharedMoodSummary(
              summary: '最近一次心情評分：$moodScore/5。',
              asOf: DateTime.now(),
            ),
          );
        } catch (_) {}
      }());
    }

    // §1C — fold this session into Siu Yan's rolling summary and clear the
    // verbatim buffer. Fire-and-forget (context-free) so the save stays
    // snappy; no-ops in guest mode / when transcript retention is off.
    if (profile != null) {
      final compiler = RollingSummaryCompiler(
        agentContext: core.agentContext,
        llm: core.llm,
      );
      unawaited(compiler.compileAtSessionEnd(
        uid: profile.uid,
        agentId: AgentRegistry.siuYanId,
        retentionOn:
            profile.consent.transcriptRetentionFor(AgentRegistry.siuYanId),
      ));
    }
    _analytics?.logCheckIn(
      mood: _face.numericScore,
      loneliness: 3,
      socialEnergy: 3,
    );
    _saved = true;
    if (mounted) setState(() {});
  }

  /// Decision A — leaving the chat IS completing the check-in. Runs from
  /// PopScope after the route pops: the mood was captured up-front by the
  /// gate, so once the user has said anything (≥1 turn), exiting finalises
  /// the check-in automatically (toast confirms) and the chat stays just a
  /// chat — no 完成 button whose meaning collided with 阿伯's.
  Future<void> _finalizeOnExit() async {
    final userTurnCount = _turns.where((t) => t.fromUser).length;
    if (_saved || userTurnCount < 1) return;
    // Captured NOW (pop callback, element still live) — everything after
    // the awaits below must not touch context: the State is disposed once
    // the pop animation ends.
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final uid = AppSettingsScope.read(context).profile?.uid;
    await _saveSession();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
            isEn ? "Today's check-in is done ✓" : '今日 check-in 完成 ✓'),
      ));
    if (uid == null) return;
    await _surfaceBriefPr(nav, uid);
  }

  /// Context-free Brief PR surfacing (runs post-pop via the captured
  /// navigator, same pattern as the Tung Tung / reflective surfaces).
  Future<void> _surfaceBriefPr(NavigatorState nav, String uid) async {
    final exchangeCount = _turns.where((t) => t.fromUser).length;
    final gate = BriefPrGate();
    final shouldShow = await gate.shouldSurfaceBriefPr(
      uid: uid,
      agentId: 'siu_yan',
      sessionStartedAt: _sessionStartedAt,
      exchangeCount: exchangeCount,
    );
    if (!shouldShow) return;
    final anchor = await gate.isAnchorPromptFor(
      uid: uid,
      agentId: 'siu_yan',
    );
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => BriefPrPage(
          agentId: 'siu_yan',
          agentDisplayName: '小欣',
          isAnchorPrompt: anchor,
        ),
      ),
    );
  }

  /// Decision A — blocking mood gate shown before the conversation when
  /// today's mood isn't known yet. Nothing is pre-selected (B14).
  Widget _buildMoodGate(bool isEn) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Siu Yan' : '小欣')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEn
                    ? 'First — which face is closest to how you feel today?'
                    : '首先，揀一個最似你今日心情嘅樣？',
                style: theme.textTheme.titleLarge?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 28),
              MoodFacePicker(
                value: _gateFace,
                onChanged: (v) => setState(() => _gateFace = v),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _gateFace == null ? null : _onGatePicked,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      isEn ? 'Start chatting' : '開始傾偈',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    // Decision A: resolve today's mood first, then either force a pick
    // (gate) or go straight to the conversation.
    if (_resolvingMood) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_moodGateResolved) {
      return _buildMoodGate(isEn);
    }

    return FirstIntroOverlay(
      agentId: AgentRegistry.siuYanId,
      // Decision A — no 完成 button: backing out IS finishing the
      // check-in (auto-save + toast + Brief PR gate via _finalizeOnExit).
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) unawaited(_finalizeOnExit());
        },
        child: Scaffold(
        appBar: AppBar(
          title: Text(isEn ? 'Siu Yan' : '小欣'),
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
                            promptHash: _turns[i].promptHash,
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
              if (_pendingOffline != null)
                OfflinePendingBanner(text: _pendingOffline!, isEn: isEn),
              _Composer(
                controller: _inputCtrl,
                voice: _voice,
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

}

class _Turn {
  final bool fromUser;
  final bool isSystem;
  final String text;
  final String? promptHash;
  const _Turn._(this.fromUser, this.isSystem, this.text, {this.promptHash});
  factory _Turn.user(String t) => _Turn._(true, false, t);
  factory _Turn.bot(String t, {String? promptHash}) =>
      _Turn._(false, false, t, promptHash: promptHash);
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
        child: RichChatText(
          text: turn.text,
          style: TextStyle(fontSize: 17, height: 1.4, color: fg),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoiceInputController voice;
  final bool busy;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.voice,
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
              controller: voice,
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
            ComposerSendButton(
                  onPressed: busy
                      ? null
                      : () async {
                      // B03 — stop dictation before snapshot + clear.
                      await voice.stopForSend();
                      onSend();
                    },
                ),
          ],
        ),
      ),
    );
  }
}
