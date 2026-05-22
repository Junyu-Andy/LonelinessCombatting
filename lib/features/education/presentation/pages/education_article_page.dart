import 'package:flutter/material.dart';

import '../../../../core/arm/arm_scope.dart';
import '../../../../core/core_services_scope.dart';
import '../../../../core/llm/llm_gateway.dart';
import '../../../../core/llm/transcript_consent_prompter.dart';
import '../../../../core/safety/distress_detector.dart';
import '../../../../core/voice/voice_input_button.dart';
import '../../../curious_companion/presentation/pages/tung_tung_page.dart';
import '../../../response_feedback/presentation/widgets/thumbs_feedback.dart';
import '../../data/education_library.dart';

/// M8 article view.
///   - Arm B: read-only article body + FAQ link to crisis page.
///   - Arm A: same body PLUS an "Ask me about this" button that opens
///     an LLM dialogue grounded to this article's text.
class EducationArticlePage extends StatefulWidget {
  final EducationArticle article;
  const EducationArticlePage({super.key, required this.article});

  @override
  State<EducationArticlePage> createState() => _EducationArticlePageState();
}

class _EducationArticlePageState extends State<EducationArticlePage> {
  // "問下呢篇" Q&A — per Product Overview §3.1 + §5.3, this is Tung
  // Tung's surface (curious companion grounded in source text).
  static const _systemPromptZhTemplate = '''
你係通通（一個 AI 機械人），幫一位香港長者明白佢啱啱讀緊嘅一篇短文。
規矩：
- 用粵語/口語繁體中文，每次回應最多 2-3 句。
- 你嘅答案要根據呢篇文章嘅內容回答，唔好憑空編造新資料。
- 如果問題超出文章範圍，誠實話：「呢個我都唔係好肯定」。
- 唔好提其他 app 功能、唔好叫佢去做行動計劃。
- 唔好引用用戶 onboarding 時話過嘅興趣 — 而家係討論呢篇文章。
- 唔好建議「不如試下你鍾意嘅活動」之類嘅嘢，呢度只係解釋文章。
- 用具體例子，唔好抽象。
- 唔好用「我會諗起你」/「我擔心你」呢類依附語言。

呢篇文章係：
"""
%ARTICLE%
"""
''';

  static const _systemPromptEnTemplate = '''
You help a Hong Kong older adult understand a short article they just
read.
Rules:
- Reply in plain English, max 2–3 sentences per turn.
- Answers must come from the article below. Do not invent new facts.
- If the question is outside the article's scope, honestly say so.
- Do not mention other app features, do not push action plans.
- Prefer concrete examples over abstractions.

Here is the article:
"""
%ARTICLE%
"""
''';

  final _inputCtrl = TextEditingController();
  final List<_Turn> _turns = [];
  bool _busy = false;
  bool _askMode = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    if (_turns.isEmpty) {
      await TranscriptConsentPrompter.maybePrompt(
        context: context,
        moduleKey: 'm8_${widget.article.id}',
      );
      if (!mounted) return;
    }
    setState(() {
      _busy = true;
      _turns.add(_Turn.user(text));
      _inputCtrl.clear();
    });
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final body = isEn ? widget.article.bodyEn : widget.article.bodyZh;
    final template =
        isEn ? _systemPromptEnTemplate : _systemPromptZhTemplate;
    final history = _turns
        .take(_turns.length - 1)
        .map((t) => LlmTurn(fromUser: t.fromUser, text: t.text))
        .toList();
    final response = await core.llm.send(
      moduleId: 'm8_education_${widget.article.id}',
      systemPrompt: template.replaceAll('%ARTICLE%', body),
      history: history,
      userInput: text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _turns.add(_Turn.bot(response.text.isNotEmpty
          ? response.text
          : (isEn
              ? 'Good question. Let me re-read it…'
              : '好問題，等我再睇下…')));
    });
    final escalation = response.inputFlag.level.index >=
            response.outputFlag.level.index
        ? response.inputFlag
        : response.outputFlag;
    if (escalation.level == DistressLevel.moderate ||
        escalation.level == DistressLevel.acute) {
      await core.distressRouter.route(escalation, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final title = isEn ? widget.article.titleEn : widget.article.titleZh;
    final body = isEn ? widget.article.bodyEn : widget.article.bodyZh;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  Text(
                    body,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.55,
                    ),
                  ),
                  // Research Review v2 Item 1: crisis hint footer.
                  if ((isEn
                        ? widget.article.crisisHintEn
                        : widget.article.crisisHintZh) !=
                      null) ...[
                    const SizedBox(height: 24),
                    _CrisisHintFooter(
                      text: isEn
                          ? widget.article.crisisHintEn!
                          : widget.article.crisisHintZh!,
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (Arm.isA(context) && !_askMode)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TungTungPage(
                            articleTitle: title,
                            articleContext: body,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          isEn ? 'Ask Tung Tung about this' : '問通通呢篇',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  if (_askMode) ...[
                    const SizedBox(height: 12),
                    Divider(color: theme.colorScheme.outlineVariant),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _turns.length; i++) ...[
                      _Bubble(turn: _turns[i]),
                      if (!_turns[i].fromUser)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ThumbsFeedback(
                            agentId: 'tung_tung',
                            moduleId:
                                'm8_education_${widget.article.id}',
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
                  ],
                ],
              ),
            ),
            if (_askMode) _Composer(
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
  final String text;
  const _Turn._(this.fromUser, this.text);
  factory _Turn.user(String t) => _Turn._(true, t);
  factory _Turn.bot(String t) => _Turn._(false, t);
}

class _Bubble extends StatelessWidget {
  final _Turn turn;
  const _Bubble({required this.turn});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = turn.fromUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fg = turn.fromUser
        ? theme.colorScheme.onPrimaryContainer
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

class _CrisisHintFooter extends StatelessWidget {
  final String text;
  const _CrisisHintFooter({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.favorite_border_rounded,
            size: 20,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                height: 1.4,
              ),
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
                  hintText: isEn
                      ? 'Ask anything about this piece…'
                      : '問呢篇任何問題…',
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
