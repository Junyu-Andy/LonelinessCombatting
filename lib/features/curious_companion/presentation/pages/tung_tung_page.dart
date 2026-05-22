/// Tung Tung's conversation surface (Developer Requirements §6).
///
/// The page is structurally similar to the reminiscence and reflective
/// dialogue surfaces but layers in two Tung-Tung-specific affordances:
///   • Topic chips drawn from the user's onboarding interests, which
///     pre-fill the composer when tapped.
///   • A "Look something up" button that proxies through the webSearch
///     cloud function and injects results into the next LLM call so
///     Tung Tung can ground its reply.
///
/// Article context can be passed via the [articleContext] constructor
/// argument — M8's "問下呢篇" button uses this so Tung Tung opens
/// already aware of which article the user wants to discuss.
library;

import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/agent_context/agent_context_service.dart';
import '../../../../core/agents/agent_avatar.dart';
import '../../../../core/agents/agent_registry.dart';
import '../../../../core/agents/first_intro_overlay.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/llm/transcript_consent_prompter.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../auth/presentation/auth_service_scope.dart';
import '../../../brief_pr/data/brief_pr_gate.dart';
import '../../../brief_pr/presentation/pages/brief_pr_page.dart';
import '../../../onboarding/data/interest_labels.dart';
import '../../../response_feedback/presentation/widgets/thumbs_feedback.dart';
import '../../data/search_repository.dart';

class TungTungPage extends StatefulWidget {
  /// Optional article body / title injected by M8's "問下呢篇" entry.
  /// Tung Tung will ground answers in this text instead of search.
  final String? articleContext;
  final String? articleTitle;

  const TungTungPage({super.key, this.articleContext, this.articleTitle});

  @override
  State<TungTungPage> createState() => _TungTungPageState();
}

class _TungTungPageState extends State<TungTungPage> {
  static const _fallbackPersonaPrompt = '''
你叫通通，係一個 AI 機械人。短而活潑，唔做醫療／財務／交易建議。
冇 search 資料時老實話「我未確定，要唔要一齊查下？」。
''';

  final _inputCtrl = TextEditingController();
  final List<_Turn> _turns = [];
  final DateTime _sessionStartedAt = DateTime.now();
  bool _briefPrSurfaced = false;
  bool _busy = false;
  SearchRepository? _searchRepo;

  /// Toggle armed by the inline "幫我查" button. When true, the next
  /// _send() call runs a web search first and injects the results
  /// alongside the user turn so Tung Tung grounds its reply on them.
  /// Cleared after each send so the user must re-arm intentionally.
  bool _searchArmed = false;

  /// Map of search query → result snippets, accumulated this session.
  /// Tung Tung's next LLM call appends a `[SEARCH_RESULTS]` block
  /// composed from the most recent successful query.
  final List<_SearchSession> _searches = [];

  @override
  void initState() {
    super.initState();
  }

  bool _openerSeeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Assigned once; didChangeDependencies fires repeatedly (locale
    // change, settings change, route push/pop) and a `late final`
    // crashes on the second assignment.
    if (_searchRepo == null) {
      final auth = AuthServiceScope.of(context);
      _searchRepo = SearchRepository(available: auth.available);
    }
    // Seed an opening bubble so the page reads as a chat from the
    // first frame. Tung Tung's tone is light + curious; the article
    // grounded mode (M8 hand-off) opens differently.
    if (!_openerSeeded) {
      _openerSeeded = true;
      _seedOpener();
    }
  }

  Future<void> _seedOpener() async {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final profile = AppSettingsScope.read(context).profile;

    // Article-Q&A mode (M8 "問下呢篇") has its own dedicated opener
    // flow; never substitute the cached personalised greeting there.
    if (widget.articleContext != null) {
      final opener = isEn
          ? 'I read the piece you opened. Ask me anything about it.'
          : '我睇完你揀嘅嗰篇。有咩想問都得。';
      setState(() => _turns.add(_Turn.bot(opener)));
      return;
    }

    // Try the cached personalised greeting warmed by TodayPage.  This
    // references the user's interests / last session topic rather
    // than the generic boilerplate below.
    if (profile != null) {
      try {
        final core = CoreServicesScope.of(context);
        final cached = await core.agentGreeting.readCachedGreeting(
          uid: profile.uid,
          agentId: AgentRegistry.tungTungId,
          isEn: isEn,
        );
        if (!mounted) return;
        if (cached != null && cached.isNotEmpty) {
          setState(() => _turns.add(_Turn.bot(cached)));
          return;
        }
      } catch (_) {
        // fall through to hardcoded opener
      }
    }

    final interests = profile?.interests ?? const <String>[];
    final highlight = interests.isNotEmpty ? interests.first : null;
    final opener = highlight != null
        ? (isEn
            ? 'Hi — you mentioned $highlight when we first met. '
                'Anything you want to chat about today?'
            : '你好啊。你之前提過「$highlight」。今日想傾啲咩？')
        : (isEn
            ? 'Hi — what have you been wondering about lately?'
            : '你好啊。最近有冇咩想知或者想傾嘅嘢？');
    if (mounted) {
      setState(() => _turns.add(_Turn.bot(opener)));
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
    final isFirstTurn = _turns.isEmpty;
    if (isFirstTurn) {
      await TranscriptConsentPrompter.maybePrompt(
        context: context,
        moduleKey: 'tung_tung_chat',
      );
      if (!mounted) return;
    }

    // Snapshot + reset the search-armed flag now so a second send
    // doesn't accidentally re-search the same query.
    final searchThisTurn = _searchArmed;

    setState(() {
      _busy = true;
      _turns.add(_Turn.user(text));
      _inputCtrl.clear();
      _searchArmed = false;
    });

    // If the user armed search, run it before the LLM call so the
    // results are part of this turn's contextSuffix.
    if (searchThisTurn && _searchRepo != null) {
      final resp = await _searchRepo!.search(text);
      if (!mounted) return;
      setState(() {
        _searches.add(_SearchSession(
          query: text,
          results: resp.results,
          unavailable: resp.unavailable,
          reason: resp.reason,
        ));
      });
    }

    final core = CoreServicesScope.of(context);
    final profile = AppSettingsScope.read(context).profile;
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    final persona = await core.personaResolver.resolve(
      agentId: AgentRegistry.tungTungId,
      profile: profile,
    );

    // Compose the suffix: persona context + interests list + article
    // context (if any) + search snippets (if any).
    final suffix = StringBuffer();
    if (persona?.contextSuffix != null) {
      suffix.writeln(persona!.contextSuffix);
      suffix.writeln();
    }
    // Interests are ONLY injected for free-form chitchat — never when
    // Tung Tung is grounded in an article ("問下呢篇" flow) or running
    // a web search.  In those modes the user wants help with the
    // specific topic, not a hobby suggestion.
    final inChitchatMode =
        widget.articleContext == null && _searches.isEmpty;
    if (inChitchatMode &&
        profile != null &&
        profile.interests.isNotEmpty) {
      suffix.writeln(isEn
          ? '[Interests captured at onboarding — only reference if the '
              'user opens a chitchat thread; do NOT push them]'
          : '[onboarding 時話過嘅興趣 — 只有用戶主動講開閒聊先可以引用，唔好硬推]');
      for (final i in profile.interests.take(10)) {
        suffix.writeln('- $i');
      }
      suffix.writeln();
    }
    if (widget.articleContext != null) {
      suffix.writeln(isEn
          ? '[Article context — ground all answers in this text]'
          : '[文章內容 — 所有回答只可以根據呢段]');
      if (widget.articleTitle != null) {
        suffix.writeln('TITLE: ${widget.articleTitle}');
      }
      suffix.writeln(widget.articleContext);
      suffix.writeln();
    }
    if (_searches.isNotEmpty) {
      final latest = _searches.last;
      suffix.writeln('[SEARCH_RESULTS for "${latest.query}"]');
      if (latest.unavailable) {
        suffix.writeln(isEn
            ? '(search backend not configured)'
            : '（搜尋未配置）');
      } else if (latest.results.isEmpty) {
        suffix.writeln(isEn
            ? '(no usable results — be honest about this)'
            : '（冇可用結果，要老實話）');
      } else {
        for (final r in latest.results.take(5)) {
          suffix.writeln('- ${r.title}: ${r.snippet}');
        }
      }
      suffix.writeln();
    }
    if (profile?.avoidTopics?.isNotEmpty == true) {
      suffix.writeln(
          '⛔ 用戶要求唔好提起呢啲話題（就算唔小心都唔好）：${profile!.avoidTopics}');
      suffix.writeln();
    }

    final history = _turns
        .take(_turns.length - 1)
        .map((t) => LlmTurn(fromUser: t.fromUser, text: t.text))
        .toList();
    final response = await core.llm.send(
      moduleId: 'tung_tung_chat',
      promptKey: persona?.promptKey,
      agentId: AgentRegistry.tungTungId,
      systemPrompt: persona == null ? _fallbackPersonaPrompt : null,
      contextSuffix: suffix.toString().trim().isEmpty
          ? null
          : suffix.toString().trim(),
      history: history,
      userInput: text,
    );

    if (profile != null &&
        profile.consent.transcriptRetentionFor(AgentRegistry.tungTungId)) {
      await core.agentContext.appendTurn(
        uid: profile.uid,
        agentId: AgentRegistry.tungTungId,
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
            ? 'I\'m not sure what to say to that — tell me a bit more?'
            : '我未諗到點答 —— 講多少少好嗎？');
    setState(() {
      _busy = false;
      _turns.add(_Turn.bot(replyText));
    });

    if (profile != null &&
        response.text.trim().isNotEmpty &&
        profile.consent.transcriptRetentionFor(AgentRegistry.tungTungId)) {
      await core.agentContext.appendTurn(
        uid: profile.uid,
        agentId: AgentRegistry.tungTungId,
        turn: AgentContextTurn(
          fromUser: false,
          text: replyText,
          timestamp: DateTime.now(),
        ),
      );
    }

    final escalation = _higher(response.inputFlag, response.outputFlag);
    if (escalation.level != DistressLevel.none) {
      await core.distressRouter.route(escalation, context: context);
    }
  }

  DistressMatch _higher(DistressMatch a, DistressMatch b) =>
      a.level.index >= b.level.index ? a : b;

  String _acuteSafetyMessage(bool isEn) => isEn
      ? 'What you just said is important. Please call Samaritans Hong '
          'Kong at 2896 0000 right now.'
      : '你啱啱講嘅嘢非常重要。請即刻打撒瑪利亞會 2896 0000。';

  void _toggleSearch() {
    setState(() => _searchArmed = !_searchArmed);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final profile = AppSettingsScope.of(context).profile;
    final agent = AgentRegistry.byId(AgentRegistry.tungTungId);
    final variant = agent.resolveVariant(null);

    return FirstIntroOverlay(
      agentId: AgentRegistry.tungTungId,
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) await _maybeSurfaceBriefPr();
        },
        child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              AgentAvatar(
                agent: agent,
                size: 32,
                openProfileOnTap: true,
              ),
              const SizedBox(width: 10),
              Text(isEn ? variant.displayNameEn : variant.displayNameZh),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (widget.articleTitle != null)
                _ArticleContextBanner(title: widget.articleTitle!),
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
                            agentId: 'tung_tung',
                            moduleId: 'tung_tung_chat',
                            turnKey: 'turn_$i',
                          ),
                        ),
                    ],
                    // Interest chips only surface in pure chitchat mode.
                    // In the article-Q&A flow ("問下呢篇") the user is
                    // here for the article — surfacing hobbies would
                    // derail them.
                    if (!_turns.any((t) => t.fromUser) &&
                        widget.articleContext == null &&
                        profile != null &&
                        profile.interests.isNotEmpty)
                      _InterestChips(
                        interests: profile.interests.take(6).toList(),
                        onTap: (label) {
                          _inputCtrl.text = isEn
                              ? 'Let\'s talk about $label'
                              : '我想傾下 $label';
                        },
                      ),
                    if (_busy)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    if (_searches.isNotEmpty &&
                        _searches.last.results.isNotEmpty)
                      _SearchResultsCard(session: _searches.last),
                    if (_searches.isNotEmpty &&
                        _searches.last.unavailable)
                      _SearchUnavailableHint(
                          reason: _searches.last.reason),
                  ],
                ),
              ),
              _Composer(
                controller: _inputCtrl,
                busy: _busy,
                accent: agent.accentColor,
                searchArmed: _searchArmed,
                onSend: _send,
                onToggleSearch: _toggleSearch,
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
      agentId: 'tung_tung',
      sessionStartedAt: _sessionStartedAt,
      exchangeCount: exchangeCount,
    );
    if (!shouldShow || !mounted) return;
    final anchor = await gate.isAnchorPromptFor(
      uid: profile.uid,
      agentId: 'tung_tung',
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BriefPrPage(
          agentId: 'tung_tung',
          agentDisplayName: '通通',
          isAnchorPrompt: anchor,
        ),
      ),
    );
  }
}

class _SearchSession {
  final String query;
  final List<SearchResult> results;
  final bool unavailable;
  final String? reason;
  const _SearchSession({
    required this.query,
    required this.results,
    required this.unavailable,
    this.reason,
  });
}

class _Welcome extends StatelessWidget {
  final dynamic profile;
  final Color accent;
  const _Welcome({required this.profile, required this.accent});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final name =
        profile?.displayName?.trim().isNotEmpty == true ? profile.displayName : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        isEn
            ? 'Hi${name.isEmpty ? '' : ' $name'} — what do you want to '
                'chat about today?'
            : '${name.isEmpty ? '' : '$name，'}你今日想傾啲咩？',
        style: theme.textTheme.titleLarge,
      ),
    );
  }
}

class _InterestChips extends StatelessWidget {
  final List<String> interests;
  final ValueChanged<String> onTap;

  const _InterestChips({required this.interests, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final i in interests)
            ActionChip(
              label: Text(
                InterestLabels.label(i, isEn),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              onPressed: () => onTap(i),
              backgroundColor: theme.colorScheme.surface,
              side: BorderSide(
                color: theme.colorScheme.outline,
                width: 1,
              ),
            ),
        ],
      ),
    );
  }
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

class _SearchResultsCard extends StatelessWidget {
  final _SearchSession session;
  const _SearchResultsCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEn
                    ? 'Search results for "${session.query}"'
                    : '「${session.query}」嘅搜尋結果',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final r in session.results.take(5)) ...[
                Text(r.title, style: theme.textTheme.bodyLarge),
                Text(
                  r.snippet,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchUnavailableHint extends StatelessWidget {
  final String? reason;
  const _SearchUnavailableHint({this.reason});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final detail = switch (reason) {
      'search_api_key_unset' =>
        isEn ? 'SEARCH_API_KEY secret is not set.' : 'SEARCH_API_KEY 未設定。',
      'search_cx_unset' =>
        isEn ? 'SEARCH_CX secret is not set.' : 'SEARCH_CX 未設定。',
      'both_secrets_unset' => isEn
          ? 'Search secrets are not set. Run `firebase functions:secrets:set` '
              'and redeploy the webSearch function.'
          : '搜尋所需嘅 secret 未設定。請設好 secret 之後重新 deploy webSearch。',
      'function_unavailable' =>
        isEn ? 'Firebase Functions are not reachable.' : 'Firebase Functions 連唔到。',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEn
                  ? 'Lookup is not yet available — the search backend is '
                      'not configured.'
                  : '搜尋功能未啟用 —— 後端未配置。',
              style: theme.textTheme.bodyMedium,
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArticleContextBanner extends StatelessWidget {
  final String title;
  const _ArticleContextBanner({required this.title});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.menu_book_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isEn
                  ? 'Grounded in: $title'
                  : '根據文章：$title',
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final Color accent;
  final bool searchArmed;
  final Future<void> Function() onSend;
  final VoidCallback onToggleSearch;

  const _Composer({
    required this.controller,
    required this.busy,
    required this.accent,
    required this.searchArmed,
    required this.onSend,
    required this.onToggleSearch,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.dividerColor, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (searchArmed)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  isEn
                      ? 'Tung Tung will search the web for your next message.'
                      : '通通會用網絡搜尋你下一句要查嘅嘢。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _SearchToggleButton(
                  armed: searchArmed,
                  accent: accent,
                  enabled: !busy,
                  onPressed: onToggleSearch,
                ),
                const SizedBox(width: 4),
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
                      hintText: searchArmed
                          ? (isEn
                              ? 'What should I look up?'
                              : '想查咩？')
                          : (isEn ? 'Type or speak…' : '寫或者講都得…'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: busy ? null : () => onSend(),
                  icon: const Icon(Icons.arrow_upward_rounded),
                  iconSize: 28,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Toggle that arms the search-augmented send. When `armed`, the icon
/// is filled with the agent's accent; otherwise it renders as an
/// outlined idle button. Tapping flips the flag; the actual search
/// runs when the user hits send.
class _SearchToggleButton extends StatelessWidget {
  final bool armed;
  final Color accent;
  final bool enabled;
  final VoidCallback onPressed;

  const _SearchToggleButton({
    required this.armed,
    required this.accent,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final tooltip = isEn
        ? (armed ? 'Search ON for next message' : 'Search the web')
        : (armed ? '下一句會搜尋' : '幫我查');
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      iconSize: 22,
      style: IconButton.styleFrom(
        backgroundColor: armed ? accent : Colors.transparent,
        foregroundColor: armed
            ? Colors.white
            : Theme.of(context).colorScheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: armed ? accent : Theme.of(context).colorScheme.outlineVariant,
            width: 1.4,
          ),
        ),
      ),
      icon: const Icon(Icons.travel_explore_outlined),
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
