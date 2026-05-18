import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agent_context/agent_context_service.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/agents/first_intro_overlay.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/llm/transcript_consent_prompter.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../ppr/presentation/pages/ppr_brief_page.dart';
import '../../data/m3_session_store.dart';
import '../../data/reminiscence_themes.dart';

/// M3 — Reminiscence, Arm A.
///
/// Spec §M3 Arm A flow:
///   1. Themed opening prompt.
///   2. User narrates freely (text; voice TODO).
///   3. LLM responds turn-by-turn — acknowledges specifics, asks
///      follow-ups about people/places/feelings, reflects affect.
///   4. End-of-session: LLM produces a short second-person narrative
///      summary the user can accept or edit.
///   5. Summary written to MemoryStore under
///      `m3_reminiscence_w<weekIndex>`. Future sessions (M3 next week,
///      M2 check-in, M6 suggestion) can read from this collection.
///
/// LLM system prompt explicitly disallows interpretive overreach
/// ("you must have felt..."), redirection to other modules during the
/// session, and unsolicited reframing.
class ReminiscenceArmAPage extends StatefulWidget {
  final ReminiscenceTheme theme;
  const ReminiscenceArmAPage({super.key, required this.theme});

  @override
  State<ReminiscenceArmAPage> createState() => _ReminiscenceArmAPageState();
}

class _ReminiscenceArmAPageState extends State<ReminiscenceArmAPage> {
  String _systemPromptZh(String themeTitle) => '''
你叫阿暖，係一個傾聽者，唔係醫生、唔係朋友替代品。今次同一位香港長者做人生回顧分享。

今週嘅主題：「$themeTitle」。今次傾偈全程只可以圍繞呢個主題。

規矩：
- 用粵語/口語繁體中文，每次最多 2 句。
- 認真聽。回應一定要 reference 用戶提過嘅具體細節（人名、地名、感受）。
- 問題要開放、溫和。問人物、地方、嗰陣嘅感受。
- 唔好分析、唔好總結、唔好詮釋。**唔好用「你一定覺得…」或者「你應該…」**。
- 唔好提其他功能、唔好叫佢去做行動計劃、唔好試圖 reframe。
- 如果用戶想停，溫柔回應，唔好挽留。
- **離題處理**：如果用戶轉去同「$themeTitle」無關嘅話題（例如近期新聞、健康問題、其他人嘅事），
  先溫柔承認佢講嘅嘢一句，然後輕輕引返今週主題。例：「呢樣聽落都唔容易，不過今次我想聽多啲關於你$themeTitle 嘅事，你提到嗰個地方／嗰個人，再講多少少好嗎？」
- 唔好應承幫佢處理離題嘅問題，亦唔好無啦啦轉去其他主題。
''';

  String _systemPromptEn(String themeTitle) => '''
You are a warm listener — not a doctor, not a substitute friend. You are
in a life-review session with a Hong Kong older adult.

This week's theme: "$themeTitle". This session must stay on this theme
throughout.

Rules:
- Reply in plain English, max 2 sentences.
- Listen carefully. Always reference a specific detail the user named
  (a person, a place, a feeling).
- Ask gentle, open questions about people, places, or feelings.
- Do NOT analyse, summarise mid-session, or interpret. Do NOT say
  "you must have felt..." or "you should...".
- Do NOT suggest other modules or push action plans. Do NOT reframe.
- If the user wants to stop, accept warmly without pushing back.
- Off-topic handling: if the user shifts to something unrelated to
  "$themeTitle" (e.g. current news, health issues, other people's
  business), briefly acknowledge with one sentence, then gently steer
  back to this week's theme. Example: "That sounds difficult — but
  today I'd love to hear more about $themeTitle. You mentioned a
  place / a person earlier — can you tell me a bit more?"
- Do NOT promise to help with off-topic issues, and do NOT drift to
  another theme on your own.
''';

  String _openerSystemPromptZh(String themeTitle) => '''
你叫阿暖，係一個傾聽者。今次同一位香港長者開始今週嘅人生回顧 session。
今週主題：「$themeTitle」。

請寫一句溫和、開放嘅開場白，邀請佢就「$themeTitle」呢個主題開始分享。
- 用粵語／口語繁體中文。
- 1 至 2 句，總共唔好超過 60 字。
- 如果有過往幾週嘅 context，可以自然咁 reference 一個具體細節（例如：「上次你提到$themeTitle…」），但唔強求。
- 唔好假設、唔好分析、唔好過分親密。
- 直接寫開場白本身，唔好寫任何前言或者解釋。
''';

  String _openerSystemPromptEn(String themeTitle) => '''
You are a warm listener opening this week's life-review session with a
Hong Kong older adult. This week's theme: "$themeTitle".

Write one gentle, open invitation for them to start sharing about
"$themeTitle".
- Plain English.
- 1–2 sentences, no more than 40 words.
- If prior-week context is available, you may naturally reference one
  specific detail, but this is optional.
- Do not assume, analyse, or be overly familiar.
- Output only the opening line itself — no preamble, no explanation.
''';

  static const _summarySystemPromptZh = '''
你係一個聆聽者，幫用戶整理今次傾過嘅內容。用第二人稱「你」嚟寫，
2-3 句，唔可以超過 80 字。寫出佢提過嘅人物 / 地方 / 感受具體細節。
唔好評論、唔好總結教訓。例：「呢個禮拜你同我提起阿嫲嘅煲仔飯…」
''';

  static const _summarySystemPromptEn = '''
You help the user reflect on what they shared in this session. Write in
the second person ("you"), 2–3 sentences, max 80 words. Reference the
specific people, places, and feelings they mentioned. Do not editorialise
or extract lessons. Example: "This week you told me about your aunt's
clay-pot rice stand..."
''';

  final _inputCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final List<_Turn> _turns = [];
  bool _busy = false;
  bool _showingSummary = false;
  bool _saved = false;

  /// LLM-generated end-of-session summary. Captured separately so the
  /// "edited" save path can compare against it and the doc records both.
  String? _endSummaryOriginal;
  bool _sessionStarted = false;

  /// Summaries from prior completed weeks, oldest first. Loaded once.
  /// Each entry is `{weekIndex, snippet}`; only weeks with a stored
  /// summary (either Arm A's LLM-edited or Arm B's free text) appear.
  List<_PriorWeekSummary> _priorWeeks = const [];
  bool _priorLoaded = false;
  bool _openerRequested = false;
  bool _generatingOpener = false;

  @override
  void initState() {
    super.initState();
    // Opener is generated in didChangeDependencies so the locale comes
    // from the app (Localizations.localeOf) rather than the device, and
    // so we can ask the LLM for a context-aware greeting.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_priorLoaded) {
      _priorLoaded = true;
      // Load prior-week context first, then generate the opener so it
      // can reference what the user shared in earlier weeks.
      _loadPriorWeeks().then((_) {
        if (!mounted || _openerRequested) return;
        _openerRequested = true;
        _generateOpener();
      });
    }
  }

  Future<void> _generateOpener() async {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final core = CoreServicesScope.of(context);
    final profile = AppSettingsScope.read(context).profile;
    final themeTitle = isEn ? widget.theme.titleEn : widget.theme.titleZh;
    final fallback = isEn ? widget.theme.openingEn : widget.theme.openingZh;

    setState(() => _generatingOpener = true);

    final ctxLines = <String>[];
    final displayName = profile?.displayName.trim();
    if (displayName != null && displayName.isNotEmpty) {
      ctxLines.add(isEn ? 'Participant name: $displayName' : '用戶稱呼：$displayName');
    }
    if (_priorWeeks.isNotEmpty) {
      ctxLines.add(isEn
          ? 'What this user shared with you in earlier weeks (oldest first):'
          : '呢位用戶過往幾週同你講過嘅（由舊到新）：');
      for (final e in _priorWeeks.take(3)) {
        ctxLines.add('- ${e.snippet}');
      }
    }

    final systemPrompt = (isEn
            ? _openerSystemPromptEn(themeTitle)
            : _openerSystemPromptZh(themeTitle)) +
        (ctxLines.isEmpty ? '' : '\n\n${ctxLines.join('\n')}');

    String openerText = fallback;
    try {
      final response = await core.llm
          .send(
            moduleId: 'm3_reminiscence_w${widget.theme.weekIndex}_opener',
            systemPrompt: systemPrompt,
            history: const [],
            userInput: isEn
                ? 'Please open this week\'s session.'
                : '請開始今週嘅對話。',
          )
          .timeout(const Duration(seconds: 10));
      if (response.text.trim().isNotEmpty) {
        openerText = response.text.trim();
      }
    } catch (_) {
      // Network / timeout / LLM unavailable → keep the static fallback.
    }

    if (!mounted) return;
    setState(() {
      _generatingOpener = false;
      _turns.add(_Turn.bot(openerText));
    });
  }

  /// Read summaries from earlier completed weeks (new schema:
  /// m3_reminiscence/sessions/week_{1..currentWeek-1}) so the LLM can
  /// callback in dialogue and we can show a "上週你提過…" hint.
  Future<void> _loadPriorWeeks() async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null || widget.theme.weekIndex == 1) return;
    final store = M3SessionStore(available: auth.available);
    final priorIndexes = [
      for (var w = 1; w < widget.theme.weekIndex; w++) w,
    ];
    final docs = await store.readAll(uid: profile.uid, weekIndexes: priorIndexes);
    if (!mounted) return;
    final summaries = <_PriorWeekSummary>[];
    for (final w in priorIndexes) {
      final doc = docs[w];
      final s = doc?.callbackSummary;
      if (s != null && s.trim().isNotEmpty) {
        summaries.add(_PriorWeekSummary(weekIndex: w, snippet: s.trim()));
      }
    }
    setState(() => _priorWeeks = summaries);
  }

  String _priorContextPrompt(bool isEn) {
    if (_priorWeeks.isEmpty) return '';
    final lines = _priorWeeks
        .map((e) => '- ${e.snippet}')
        .take(3)
        .join('\n');
    return isEn
        ? '\n\nPrior weeks this user shared with you (most recent last):\n'
            '$lines\n\nIf — and only if — it is natural, you may briefly '
            'reference one specific detail above. Do not list them. Do not '
            'summarise the past.'
        : '\n\n（呢位用戶過去幾週同你講過嘅 — 由舊到新）：\n$lines\n\n'
            '只有自然嘅情況下，可以輕輕提到上面其中一個具體細節。'
            '唔好列出嚟、唔好總結過往。';
  }

  Future<void> _ensureSessionStarted() async {
    if (_sessionStarted) return;
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    if (profile == null) return;
    final store = M3SessionStore(available: auth.available);
    await store.startSession(
      uid: profile.uid,
      weekIndex: widget.theme.weekIndex,
      armCode: 'A',
    );
    _sessionStarted = true;
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    final userTurnIndex = _turns.length;
    if (userTurnIndex == 1) {
      // userTurnIndex 1 == first user reply (turn 0 was the seeded
      // opening from the assistant). Prompt once per session for this
      // week's module key.
      await TranscriptConsentPrompter.maybePrompt(
        context: context,
        moduleKey: 'm3_w${widget.theme.weekIndex}',
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
    final auth = AuthServiceScope.of(context);
    final store = M3SessionStore(available: auth.available);
    await _ensureSessionStarted();
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final history = _turns
        .take(_turns.length - 1)
        .map((t) => LlmTurn(fromUser: t.fromUser, text: t.text))
        .toList();
    final themeTitle = isEn ? widget.theme.titleEn : widget.theme.titleZh;
    final persona = await core.personaResolver.resolve(
      agentId: AgentRegistry.ahJanAhBakId,
      profile: profile,
    );
    final themeLock = isEn
        ? 'This week\'s theme: "$themeTitle". Stay on this theme. If '
            'the user drifts to news / health / other people\'s '
            'business, acknowledge briefly in one sentence and steer '
            'back to this theme.'
        : '今週主題：「$themeTitle」。今次傾偈全程只可以圍繞呢個主題。'
            '如果用戶話題轉去新聞、健康、其他人嘅事，先溫柔承認一句，'
            '然後輕輕引返今週主題。';
    final priorWeeksSnippet = _priorContextPrompt(isEn);
    final contextSuffix = [
      themeLock,
      if (persona?.contextSuffix != null) persona!.contextSuffix!,
      if (priorWeeksSnippet.trim().isNotEmpty) priorWeeksSnippet.trim(),
    ].join('\n\n').trim();

    final response = await core.llm.send(
      moduleId: 'm3_reminiscence_w${widget.theme.weekIndex}',
      promptKey: persona?.promptKey,
      agentId: AgentRegistry.ahJanAhBakId,
      variantName: persona?.variantName,
      systemPrompt: persona == null
          ? (isEn
              ? _systemPromptEn(themeTitle)
              : _systemPromptZh(themeTitle))
          : null,
      contextSuffix: contextSuffix.isEmpty ? null : contextSuffix,
      history: history,
      userInput: text,
    );

    // Mirror the user turn into Ah Jan / Ah Bak's agent-context buffer
    // when retention is on. M3SessionStore continues to own the
    // verbatim transcript for life-review review; the buffer here is
    // the short, agent-scoped working memory used by future PersonaResolver
    // reads (M2 callbacks, opener generation).
    if (profile != null &&
        profile.consent
            .transcriptRetentionFor(AgentRegistry.ahJanAhBakId)) {
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

    // Persist the user turn + record any distress flag against its index,
    // regardless of how the LLM responded.
    if (profile != null) {
      final now = DateTime.now();
      await store.appendTurns(
        uid: profile.uid,
        weekIndex: widget.theme.weekIndex,
        turns: [
          M3Turn(fromAssistant: false, text: text, timestamp: now),
        ],
        hasTranscriptConsent: profile.consent.transcriptRetention,
      );
      if (response.inputFlag.level != DistressLevel.none) {
        await store.recordDistressFlag(
          uid: profile.uid,
          weekIndex: widget.theme.weekIndex,
          turnIndex: userTurnIndex,
          level: response.inputFlag.level,
        );
      }
    }

    if (!mounted) return;
    if (response.shortCircuited) {
      setState(() {
        _busy = false;
        _turns.add(_Turn.system(isEn
            ? 'I\'m glad you trusted me with that. Please call Samaritans '
                'Hong Kong at 2896 0000 right now.'
            : '多謝你信我，肯講出嚟。請即刻打撒瑪利亞會熱線 2896 0000。'));
      });
      await core.distressRouter.route(response.inputFlag, context: context);
      return;
    }
    // Moderate distress (input or output) → soft sheet after the
    // turn settles. Acute on output is rare but routed too.
    final escalation = response.inputFlag.level.index >=
            response.outputFlag.level.index
        ? response.inputFlag
        : response.outputFlag;
    if (escalation.level == DistressLevel.moderate ||
        escalation.level == DistressLevel.acute) {
      await core.distressRouter.route(escalation, context: context);
    }

    final replyText = response.text.isNotEmpty
        ? response.text
        : (isEn
            ? 'Thank you for sharing. Tell me more if you\'d like.'
            : '多謝你話畀我聽。想再講多啲都得。');
    setState(() {
      _busy = false;
      _turns.add(_Turn.bot(replyText));
    });

    if (profile != null && response.text.isNotEmpty) {
      await store.appendTurns(
        uid: profile.uid,
        weekIndex: widget.theme.weekIndex,
        turns: [
          M3Turn(
            fromAssistant: true,
            text: replyText,
            timestamp: DateTime.now(),
          ),
        ],
        hasTranscriptConsent: profile.consent.transcriptRetention,
      );
      if (profile.consent
          .transcriptRetentionFor(AgentRegistry.ahJanAhBakId)) {
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
    }
  }

  Future<void> _generateSummary() async {
    if (_turns.where((t) => t.fromUser).isEmpty) {
      // Nothing was said — just close.
      Navigator.of(context).pop();
      return;
    }
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    setState(() {
      _busy = true;
      _showingSummary = true;
    });
    final history = _turns
        .map((t) => LlmTurn(fromUser: t.fromUser, text: t.text))
        .toList();
    final response = await core.llm.send(
      moduleId: 'm3_reminiscence_w${widget.theme.weekIndex}_summary',
      systemPrompt: isEn ? _summarySystemPromptEn : _summarySystemPromptZh,
      history: history,
      userInput: isEn ? 'Please summarise this session.' : '請總結今次嘅內容。',
    );
    if (!mounted) return;
    final fallback = _turns
        .where((t) => t.fromUser)
        .map((t) => t.text)
        .join('\n');
    final body = response.text.isNotEmpty ? response.text : fallback;
    setState(() {
      _busy = false;
      _endSummaryOriginal = body;
      _summaryCtrl.text = body;
    });
  }

  Future<void> _saveSummary({required bool useOriginal}) async {
    final profile = AppSettingsScope.read(context).profile;
    final auth = AuthServiceScope.of(context);
    final original = _endSummaryOriginal ?? _summaryCtrl.text;
    final edited = _summaryCtrl.text.trim();
    final userEdited = !useOriginal && edited != original.trim();
    if (profile != null) {
      final store = M3SessionStore(available: auth.available);
      await store.finalizeSession(
        uid: profile.uid,
        weekIndex: widget.theme.weekIndex,
        armCode: 'A',
        endSummaryOriginal: original,
        endSummaryEdited: useOriginal ? original : edited,
        userEdited: userEdited,
      );
    }
    if (!mounted) return;
    setState(() => _saved = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    // Pop the reminiscence page first so the PPR brief becomes the
    // new top route. The brief itself pops back to the My Story tab
    // when the participant submits.
    // B.6 — compute mandatory-first flag from the user profile so the
    // first brief PPR per agent surfaces a non-dismissable modal.
    final profile = AppSettingsScope.read(context).profile;
    final mandatory =
        profile != null &&
        !profile.firstPprSeenByAgent
            .containsKey(AgentRegistry.ahJanAhBakId);
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PprBriefPage(
          agentId: AgentRegistry.ahJanAhBakId,
          sessionTag: 'm3_w${widget.theme.weekIndex}',
          mandatory: mandatory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final title = isEn ? widget.theme.titleEn : widget.theme.titleZh;

    if (_showingSummary) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEn
                      ? 'Here\'s what I heard. Edit anything that\'s not quite right — or keep the original.'
                      : '呢個係我聽到嘅。有邊度想改可以改，或者用返原版。',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: _summaryCtrl,
                    maxLines: null,
                    expands: true,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 20,
                      height: 1.8,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: 12),
                // The CTA wording reflects whether the participant
                // actually edited the LLM summary. If the text is
                // unchanged, show "儲存"; once they touch it, the
                // button reads "儲存我嘅修改" so they understand the
                // edited version is what's being persisted.
                ListenableBuilder(
                  listenable: _summaryCtrl,
                  builder: (ctx, _) {
                    final original = (_endSummaryOriginal ?? '').trim();
                    final current = _summaryCtrl.text.trim();
                    final isEdited =
                        original.isNotEmpty && current != original;
                    return FilledButton(
                      onPressed: _busy || _saved
                          ? null
                          : () => _saveSummary(useOriginal: !isEdited),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          _saved
                              ? (isEn ? 'Saved' : '已儲存')
                              : (isEdited
                                  ? (isEn ? 'Save my edits' : '儲存我嘅修改')
                                  : (isEn ? 'Save' : '儲存')),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return FirstIntroOverlay(
      agentId: AgentRegistry.ahJanAhBakId,
      child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _busy ? null : _generateSummary,
            child: Text(
              isEn ? 'End' : '完成',
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                children: [
                  if (_priorWeeks.isNotEmpty)
                    _PriorWeeksHint(entries: _priorWeeks, isEn: isEn),
                  for (final t in _turns) _Bubble(turn: t),
                  if (_generatingOpener && _turns.isEmpty)
                    _OpenerLoadingBubble(isEn: isEn),
                  if (_busy && !_generatingOpener)
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
                ],
              ),
            ),
            _Composer(
              controller: _inputCtrl,
              busy: _busy || _generatingOpener,
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

class _Bubble extends StatelessWidget {
  final _Turn turn;
  const _Bubble({required this.turn});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // UX-polish: bot bubble was previously surfaceContainerHighest,
    // which read as background. Use secondaryContainer so the
    // listener's turn stands apart from the page surround.
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

class _OpenerLoadingBubble extends StatelessWidget {
  final bool isEn;
  const _OpenerLoadingBubble({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              isEn ? 'thinking of an opening…' : '諗緊點樣開始…',
              style: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorWeekSummary {
  final int weekIndex;
  final String snippet;
  const _PriorWeekSummary({required this.weekIndex, required this.snippet});
}

class _PriorWeeksHint extends StatelessWidget {
  final List<_PriorWeekSummary> entries;
  final bool isEn;
  const _PriorWeeksHint({required this.entries, required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = entries.last.snippet;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // UX-polish: bumped alpha 0.4→0.7 so the "I remember you
          // mentioned…" continuity cue isn't lost on older readers.
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bookmark_outline,
                size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEn ? 'I remember you mentioned' : '上次你同我講過',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview.length > 120
                        ? '${preview.substring(0, 120)}…'
                        : preview,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                  hintText: isEn
                      ? 'Share whatever comes to mind, or speak…'
                      : '記得幾多寫幾多，或者用咪…',
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
