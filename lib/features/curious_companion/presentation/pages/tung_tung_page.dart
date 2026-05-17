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
  bool _busy = false;
  late final SearchRepository _searchRepo;

  /// Map of search query → result snippets, accumulated this session.
  /// Tung Tung's next LLM call appends a `[SEARCH_RESULTS]` block
  /// composed from the most recent successful query.
  final List<_SearchSession> _searches = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AuthServiceScope.of(context);
    _searchRepo = SearchRepository(available: auth.available);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _send({String? prefilledInput}) async {
    final text = (prefilledInput ?? _inputCtrl.text).trim();
    if (text.isEmpty || _busy) return;
    final isFirstTurn = _turns.isEmpty;
    if (isFirstTurn) {
      await TranscriptConsentPrompter.maybePrompt(
        context: context,
        moduleKey: 'tung_tung_chat',
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
    if (profile != null && profile.interests.isNotEmpty) {
      suffix.writeln(isEn
          ? '[Interests captured at onboarding]'
          : '[onboarding 時話過嘅興趣]');
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

  Future<void> _onLookup() async {
    final query = _inputCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack(context,
          Localizations.localeOf(context).languageCode == 'en'
              ? 'Type what you\'d like to look up first.'
              : '先寫低你想查嘅嘢。');
      return;
    }
    setState(() => _busy = true);
    final resp = await _searchRepo.search(query);
    if (!mounted) return;
    setState(() {
      _searches.add(_SearchSession(
        query: query,
        results: resp.results,
        unavailable: resp.unavailable,
      ));
      _busy = false;
    });
    await _send(prefilledInput: query);
  }

  void _showSnack(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
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
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              AgentAvatar(agent: agent, size: 32),
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
                    if (_turns.isEmpty)
                      _Welcome(profile: profile, accent: agent.accentColor),
                    if (_turns.isEmpty &&
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
                    for (final t in _turns) _TurnBubble(turn: t),
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
                      _SearchUnavailableHint(),
                  ],
                ),
              ),
              _Composer(
                controller: _inputCtrl,
                busy: _busy,
                accent: agent.accentColor,
                onSend: _send,
                onLookup: _onLookup,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchSession {
  final String query;
  final List<SearchResult> results;
  final bool unavailable;
  const _SearchSession({
    required this.query,
    required this.results,
    required this.unavailable,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final i in interests)
            ActionChip(
              label: Text(i),
              onPressed: () => onTap(i),
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
  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          isEn
              ? 'Lookup is not yet available — the search API key '
                  'hasn\'t been configured in this deployment.'
              : '搜尋功能未啟用 —— 部署嘅時候未設定 search API key。',
          style: theme.textTheme.bodyMedium,
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
  final Future<void> Function({String? prefilledInput}) onSend;
  final VoidCallback onLookup;

  const _Composer({
    required this.controller,
    required this.busy,
    required this.accent,
    required this.onSend,
    required this.onLookup,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.dividerColor, width: 1),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: busy ? null : onLookup,
                  icon: const Icon(Icons.travel_explore_outlined, size: 20),
                  label: Text(
                    isEn ? 'Look this up' : '幫我查',
                    style: const TextStyle(fontSize: 14),
                  ),
                  style: TextButton.styleFrom(foregroundColor: accent),
                ),
              ],
            ),
            Row(
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

class _Turn {
  final bool fromUser;
  final bool isSystem;
  final String text;
  const _Turn._(this.fromUser, this.isSystem, this.text);
  factory _Turn.user(String t) => _Turn._(true, false, t);
  factory _Turn.bot(String t) => _Turn._(false, false, t);
  factory _Turn.system(String t) => _Turn._(false, true, t);
}
