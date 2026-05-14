import 'package:flutter/material.dart';

import '../../../../app/app_settings_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/memory/memory_store.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/voice/voice_input_button.dart';
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
  static const _systemPromptZh = '''
你叫阿暖，係一個傾聽者，唔係醫生、唔係朋友替代品。今次同一位香港長者做人生回顧分享。

規矩：
- 用粵語/口語繁體中文，每次最多 2 句。
- 認真聽。回應一定要 reference 用戶提過嘅具體細節（人名、地名、感受）。
- 問題要開放、溫和。問人物、地方、嗰陣嘅感受。
- 唔好分析、唔好總結、唔好詮釋。**唔好用「你一定覺得…」或者「你應該…」**。
- 唔好提其他功能、唔好叫佢去做行動計劃、唔好試圖 reframe。
- 如果用戶想停，溫柔回應，唔好挽留。
''';

  static const _systemPromptEn = '''
You are a warm listener — not a doctor, not a substitute friend. You are
in a life-review session with a Hong Kong older adult.

Rules:
- Reply in plain English, max 2 sentences.
- Listen carefully. Always reference a specific detail the user named
  (a person, a place, a feeling).
- Ask gentle, open questions about people, places, or feelings.
- Do NOT analyse, summarise mid-session, or interpret. Do NOT say
  "you must have felt..." or "you should...".
- Do NOT suggest other modules or push action plans. Do NOT reframe.
- If the user wants to stop, accept warmly without pushing back.
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

  /// Short summaries of every prior week the user has completed, oldest
  /// first. Loaded once on first build via [didChangeDependencies] so we
  /// have access to the scope.
  List<MemoryEntry> _priorWeeks = const [];
  bool _priorLoaded = false;

  @override
  void initState() {
    super.initState();
    // Seed the conversation with the themed opening from the system.
    _turns.add(_Turn.bot(_isEnNow() ? widget.theme.openingEn : widget.theme.openingZh));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_priorLoaded) {
      _priorLoaded = true;
      _loadPriorWeeks();
    }
  }

  /// Read summaries from earlier weeks of this same reminiscence track
  /// (m3_reminiscence_w1 .. w{current-1}) so the LLM can reference them
  /// later in the session and so we can show a "上週你提過…" hint.
  Future<void> _loadPriorWeeks() async {
    final profile = AppSettingsScope.read(context).profile;
    final core = CoreServicesScope.of(context);
    if (profile == null || widget.theme.weekIndex == 1) return;
    final priorIds = [
      for (var w = 1; w < widget.theme.weekIndex; w++)
        'm3_reminiscence_w$w',
    ];
    final entries = await core.memory.recentAcross(
      uid: profile.uid,
      moduleIds: priorIds,
      perModule: 1,
    );
    if (!mounted) return;
    // Oldest first so a callback ("two weeks ago…") feels chronological.
    entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    setState(() => _priorWeeks = entries);
  }

  String _priorContextPrompt(bool isEn) {
    if (_priorWeeks.isEmpty) return '';
    final lines = _priorWeeks
        .map((e) => '- ${e.summary}')
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

  bool _isEnNow() {
    // Read once during initState by walking widgets.binding's window —
    // safer to default to zh and let didChangeDependencies update.
    return WidgetsBinding.instance.platformDispatcher.locale.languageCode ==
        'en';
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
    setState(() {
      _busy = true;
      _turns.add(_Turn.user(text));
      _inputCtrl.clear();
    });
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final history = _turns
        .take(_turns.length - 1)
        .map((t) => LlmTurn(fromUser: t.fromUser, text: t.text))
        .toList();
    final basePrompt = isEn ? _systemPromptEn : _systemPromptZh;
    final response = await core.llm.send(
      moduleId: 'm3_reminiscence_w${widget.theme.weekIndex}',
      systemPrompt: basePrompt + _priorContextPrompt(isEn),
      history: history,
      userInput: text,
    );
    if (!mounted) return;
    if (response.shortCircuited) {
      setState(() {
        _busy = false;
        _turns.add(_Turn.system(isEn
            ? 'I\'m glad you trusted me with that. Please call Samaritans '
                'Hong Kong at 2896 0000 right now.'
            : '多謝你信我，肯講出嚟。請即刻打撒瑪利亞會熱線 2896 0000。'));
      });
      return;
    }
    setState(() {
      _busy = false;
      _turns.add(_Turn.bot(response.text.isNotEmpty
          ? response.text
          : (isEn
              ? 'Thank you for sharing. Tell me more if you\'d like.'
              : '多謝你話畀我聽。想再講多啲都得。')));
    });
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
    final fallback = isEn
        ? _turns
            .where((t) => t.fromUser)
            .map((t) => t.text)
            .join('\n')
        : _turns
            .where((t) => t.fromUser)
            .map((t) => t.text)
            .join('\n');
    final body = response.text.isNotEmpty ? response.text : fallback;
    setState(() {
      _busy = false;
      _summaryCtrl.text = body;
    });
  }

  Future<void> _acceptSummary() async {
    final profile = AppSettingsScope.read(context).profile;
    final core = CoreServicesScope.of(context);
    if (profile != null) {
      await core.memory.writeSummary(
        uid: profile.uid,
        moduleId: 'm3_reminiscence_w${widget.theme.weekIndex}',
        summary: _summaryCtrl.text.trim(),
        armCode: 'A',
        hasTranscriptConsent: profile.consent.transcriptRetention,
        tags: ['week:${widget.theme.weekIndex}'],
      );
    }
    if (!mounted) return;
    setState(() => _saved = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.of(context).pop();
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
                      ? 'Here\'s what I heard. Edit anything that\'s not quite right.'
                      : '呢個係我聽到嘅。有邊度想改可以改。',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: _summaryCtrl,
                    maxLines: null,
                    expands: true,
                    style: theme.textTheme.bodyLarge,
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
                FilledButton(
                  onPressed: _busy || _saved ? null : _acceptSummary,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _saved
                          ? (isEn ? 'Saved' : '已儲存')
                          : (isEn ? 'Save this memory' : '儲存呢段回憶'),
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
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

class _Bubble extends StatelessWidget {
  final _Turn turn;
  const _Bubble({required this.turn});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

class _PriorWeeksHint extends StatelessWidget {
  final List<MemoryEntry> entries;
  final bool isEn;
  const _PriorWeeksHint({required this.entries, required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = entries.last.summary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
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
