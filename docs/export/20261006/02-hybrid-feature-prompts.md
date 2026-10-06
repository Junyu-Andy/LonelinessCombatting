# Hybrid 组：各功能用到的 prompt

**结论**：除了三个陪伴者的对话，Hybrid 组还有 12 处功能会调用 DeepSeek，每处有自己的 prompt。
下面按功能逐字照抄：记忆抽取和注入（v1，服务器）、旧版滚动摘要（v0，App）、每周小结、「問下呢篇」、
回忆开场白和会话小结、首页个性化开场白、社交建议、行动计划、跨陪伴者转介判断。

**关于「安全标记」**：代码里**没有**用 LLM 做安全判断的 prompt。
安全检测是关键词词库（`lib/core/safety/distress_detector.dart`，两组共用）；
所谓「5 个 LLM 标记」（`functions/llm_flags.js`）是服务器在模型回复后用关键词和规则算出来的，不调用模型。
第 10 节把这两处服务器端的词表照抄出来，方便编码手册使用。

**app 实际显示哪个版本**：`lib/app/app_settings.dart` 第 41–50 行 `englishEnabled = false`，
`locale` 被强制为 `zh`。所以代码里所有 `isEn ? 英文 : 中文` 的地方，现在**只会用中文（粤语）版本**。
英文版照样导出，供审阅参考，但老人看不到，也不会发给模型。

## 条数

| 项目 | 条数 | 怎么数的 |
|---|---|---|
| 调用 DeepSeek 的功能 prompt（不含三个 persona） | 12 | 按下面第 1–9 节的 system prompt 逐个数：记忆抽取 1、v0 摘要 1、每周小结 1、問下呢篇 1、回忆开场白 1、回忆小结 1、首页开场白 2（阿珍/阿伯、通通）、社交建议 1、行动计划小结 1、行动计划跟进 1、转介判断 1；中英文算同一个 |

## 1. 记忆 v1（服务器，`functions/memory.js`）

**谁会用到**：Phase B 的 A 组（且 `meta/memory_config` 打开）以及自愿开启的测试人员。

### 1.1 抽取 prompt（会话结束后，`memoryEndSession` / `memorySweep` 调用）

分类和敏感词：

来源：`functions/memory.js` 第 41–64 行

```js
/** Fixed category list the extractor must use. */
const CATEGORIES = [
  "name", // 稱呼
  "family", // 家人（姓名、關係）
  "living", // 居住情況
  "hobby", // 興趣
  "routine", // 日常
  "event", // 重要事件
  "health", // 健康
  "preference", // 其他喜好
];

/** "Basic facts" shared with every agent under policy C. */
const SHARED_CATEGORIES = new Set(["name", "family", "living"]);

/** Categories that are always sensitive, whatever the model says. */
const SENSITIVE_CATEGORIES = new Set(["health"]);

/** Keyword rule layered on the model's own sensitive flag. */
const SENSITIVE_TERMS = [
  "病", "醫", "藥", "痛", "癌", "覆診", "手術", "入院", "過身", "去世", "死",
  "離婚", "嗌交", "吵架", "唔啱", "反面", "錢", "債", "借", "遺囑", "抑鬱",
  "焦慮", "失眠", "孤獨", "寂寞",
];
```

来源：`functions/memory.js` 第 186–228 行

```js
// Extraction: prompt + validation
// ---------------------------------------------------------------------------

/**
 * @param {{turns: Array<{fromUser: boolean, text: string}>,
 *   activeFacts: Array<object>, todayKey: string}} args
 * @return {{system: string, user: string}}
 */
function buildExtractionPrompt({turns, activeFacts, todayKey}) {
  const system = `你負責由一段長者同 AI 陪伴者嘅對話入面，抽取值得記住嘅資料。
只可以抽取「用戶」自己明確講過嘅內容，唔好推測、唔好補充。
每一條事實同待跟進事項，都要附上 quote：用戶原句入面連續嘅一段字，一字不改。
用繁體書面中文寫 value / summary / description，人名同重要粵語詞保留原文。
唔好記錄電話、地址、身份證號碼。涉及自殺、自殘嘅內容一律唔好抽取。

今日係 ${todayKey}（${weekdayZh(todayKey)}，香港時間）。
「聽日」「下個禮拜四」「月尾」呢類相對日期，要換算成 YYYY-MM-DD。
冇講明日期嘅事，唔好當待跟進事項。

category 只可以用：${CATEGORIES.join(", ")}。
facts 入面每條要標 op：
- add：新事實
- update：修正或更新現有事實，要填 fact_id（用下面「現有事實」嘅 id）；
  如果用戶係糾正之前講錯嘅嘢，correction 填 true
- no_change：唔使輸出（省略）
健康、家庭矛盾、財務、情緒困擾等內容，sensitive 填 true。

只輸出一個 JSON 物件，格式：
{"summary": "≤150字，第三身描述今次傾咗咩",
 "facts": [{"op": "add|update", "fact_id": "", "category": "",
   "key": "簡短標題", "value": "", "quote": "", "sensitive": false,
   "correction": false}],
 "followups": [{"description": "", "due_date": "YYYY-MM-DD", "quote": ""}]}`;

  const factLines = activeFacts.length === 0 ? "（暫時冇）" :
    activeFacts.map((f) =>
      `- id=${f.id} [${f.category}] ${f.key}：${f.value}`).join("\n");
  const transcript = turns
      .map((t) => `${t.fromUser ? "用戶" : "陪伴者"}：${t.text}`)
      .join("\n");
  const user = `[現有事實]\n${factLines}\n\n[今次對話]\n${transcript}`;
  return {system, user};
}
```

调用参数（temperature 0.2，JSON 输出）：

来源：`functions/index.js` 第 1321–1351 行

```js
/**
 * One strict-JSON DeepSeek call for memory extraction.
 * @param {{system: string, user: string}} prompt
 * @return {Promise<string>} raw JSON text
 */
async function callDeepSeekJson(prompt) {
  const response = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${DEEPSEEK_API_KEY.value()}`,
    },
    body: JSON.stringify({
      model: "deepseek-chat",
      messages: [
        {role: "system", content: prompt.system},
        {role: "user", content: stripPII(prompt.user)},
      ],
      response_format: {type: "json_object"},
      temperature: 0.2,
      max_tokens: 1500,
    }),
  });
  if (!response.ok) {
    const body = (await response.text()).slice(0, 300);
    throw new Error(`deepseek ${response.status}: ${body}`);
  }
  const data = await response.json();
  return (data.choices && data.choices[0] && data.choices[0].message &&
    data.choices[0].message.content) || "";
}
```

### 1.2 注入对话 prompt 的记忆块和使用规则

哪些对话会注入记忆：

来源：`functions/memory.js` 第 36–39 行

```js
/** Chat surfaces that receive the memory block. */
const INJECT_MODULES = new RegExp(
    "^(m2_check_in|reflective_dialogue|tung_tung_chat|m3_reminiscence_w\\d+" +
    "|greeting_(siu_yan|ah_jan_ah_bak|tung_tung))$");
```

长度和条数上限：

来源：`functions/memory.js` 第 85–94 行

```js
const LIMITS = {
  maxChars: 2000, // ≈1,500 tokens of Chinese
  followups: 1,
  facts: 20,
  summaryDays: 3,
  summaryChars: 150,
  followupExpireDays: 7,
  maxAttempts: 3,
  revisionReview: 3, // this many revisions of one fact → researcher review
};
```

来源：`functions/memory.js` 第 427–505 行

```js
const USAGE_RULES = `[記憶使用規則]
1. 提起記憶時要留餘地，例如「我記得你好似講過……係唔係呀？」
2. 一輪最多自然咁提起一樣記憶，唔好一次過列出。
3. 「敏感」嗰部分，只可以喺對方自己提起相關話題時先用，唔好主動引出。
4. 對方話你記錯，就道歉、接受新講法，唔好爭辯。
5. 唔肯定就唔好提；絕對唔好作對方冇講過嘅嘢。
6. 唔好講「另一位陪伴者話我知」之類嘅說話。`;

/**
 * Render the selection into the prompt block, trimming lowest priority
 * sections first so the block never exceeds LIMITS.maxChars.
 * @param {object} sel from selectForInjection
 * @return {{text: string, ids: Array<string>,
 *   layers: {followup: number, fact: number, sensitive: number,
 *   summary: number}}}
 */
function renderMemoryBlock(sel) {
  const f = sel.followups.map((x) => ({
    id: x.id, line: `- ${x.description}（${x.due_date}）`}));
  const facts = sel.facts.map((x) => ({
    id: x.id, line: `- ${x.key}：${x.value}`}));
  const sens = sel.sensitiveFacts.map((x) => ({
    id: x.id, line: `- ${x.key}：${x.value}`}));
  const sums = sel.summaryDays.map((d) => ({
    ids: d.ids, line: `- ${d.day}：${d.texts.join("；")}`}));

  const build = (nFollow, nFacts, nSens, nSums) => {
    const parts = [];
    const ids = [];
    if (nFollow > 0) {
      parts.push("[到期要關心嘅事]（開場可以自然咁問一次，問過就算）");
      for (const x of f.slice(0, nFollow)) {
        parts.push(x.line); ids.push(x.id);
      }
    }
    if (nFacts > 0) {
      parts.push("[關於對方嘅資料]");
      for (const x of facts.slice(0, nFacts)) {
        parts.push(x.line); ids.push(x.id);
      }
    }
    if (nSums > 0) {
      parts.push("[之前傾過]");
      for (const x of sums.slice(0, nSums)) {
        parts.push(x.line); ids.push(...x.ids);
      }
    }
    if (nSens > 0) {
      parts.push("[敏感]（只喺對方自己提起先可以用）");
      for (const x of sens.slice(0, nSens)) {
        parts.push(x.line); ids.push(x.id);
      }
    }
    if (parts.length === 0) return {text: "", ids};
    const text =
      `<memory>\n${parts.join("\n")}\n</memory>\n${USAGE_RULES}`;
    return {text, ids};
  };

  // Trim order (lowest priority first): sensitive → summaries → facts.
  let nF = f.length;
  let nFa = facts.length;
  let nS = sens.length;
  let nSu = sums.length;
  let out = build(nF, nFa, nS, nSu);
  while (out.text.length > LIMITS.maxChars) {
    if (nS > 0) nS--;
    else if (nSu > 0) nSu--;
    else if (nFa > 0) nFa--;
    else if (nF > 0) nF--;
    else break;
    out = build(nF, nFa, nS, nSu);
  }
  return {
    text: out.text,
    ids: out.ids,
    layers: {followup: nF, fact: nFa, sensitive: nS, summary: nSu},
  };
}
```

## 2. 记忆 v0 滚动摘要（App，`rolling_summary_compiler.dart`）

**谁会用到**：pilot 用户（非 v1）。每次会话结束时把对话折叠成 ≤500 字摘要，下次放进 `[過往摘要]`。

来源：`lib/core/agent_context/rolling_summary_compiler.dart` 第 31–43 行

```dart
  /// Hard cap from Appendix A. Characters (runes), not words — the summary
  /// is Cantonese.
  static const int _maxChars = 500;

  /// The fold instruction (Appendix A "fold" prompt draft).
  static const String _foldSystemPrompt = '''
你要把一位用戶同某個 companion 嘅過往傾偈，更新成一段簡短摘要。
輸入：舊摘要(≤500字) + 今次 session 嘅對話。
要求：
- 輸出一段 ≤500 字粵語摘要，覆蓋：傾過咩 / 而家狀態同心情走勢 / 唔好提嘅嘢 / 仲未傾完嘅線索。
- 保留仍然相關嘅，唔好無限疊加舊嘢，只記真實講過嘅，唔好捏造。
- 唔好放電話／地址／身份證等 PII。
只輸出摘要本身。''';
```

来源：`lib/core/agent_context/rolling_summary_compiler.dart` 第 96–122 行

```dart
    final transcript = buffer
        .map((t) => '${t.fromUser ? '用戶' : 'companion'}：${t.text}')
        .join('\n');
    final oldSummary = snapshot.rollingSummary.trim();
    final userInput = StringBuffer()
      ..writeln('[舊摘要]')
      ..writeln(oldSummary.isEmpty ? '（暫時未有）' : oldSummary)
      ..writeln()
      ..writeln('[今次對話]')
      ..write(transcript);

    String status;
    String? error;
    try {
      final response = await llm.send(
        moduleId: 'rolling_summary_fold',
        systemPrompt: _foldSystemPrompt,
        agentId: agentId,
        history: const [],
        userInput: userInput.toString(),
        uid: uid,
        // Every turn in this transcript was already distress-scanned live;
        // re-scanning here double-fired safety alerts (grief vocabulary is
        // routine for this population) and an acute term anywhere in the
        // session short-circuited the fold, losing that session's memory.
        skipSafetyScan: true,
      );
```

## 3. 每周小结（M9 进度页，只 A 组）

来源：`lib/features/progress/presentation/pages/progress_page.dart` 第 25–48 行

```dart
class _ProgressPageState extends State<ProgressPage> {
  // Weekly narrative summary — per Product Overview §5.4, in Siu Yan voice
  // (Hybrid arm only; Rule-based arm uses static labels).
  static const _systemPromptZh = '''
你係小欣（一個 AI 機械人）。睇住呢位香港長者過去 7 日嘅活動數字，寫一段 2-3 句嘅週小結。
要求：
- 用粵語/口語繁體中文。
- 提到 1 個具體數字（例如「呢個禮拜你做咗 3 次 check-in」）。
- 如果有完成嘅計劃，認可佢。如果冇，唔好責備、亦唔好催促。
- 唔好教訓，唔好提其他 app 功能。
- 唔好用「我會諗起你」/「我擔心你」呢類依附語言。
輸出：只係段話本身。
''';

  static const _systemPromptEn = '''
You write a 2-3 sentence weekly summary for a Hong Kong older adult,
looking at the past 7 days of their activity counts.
Rules:
- Plain English.
- Mention one concrete number (e.g. "you checked in 3 times").
- Acknowledge completed plans if any. If none, don't reproach or push.
- No lectures, no mentioning of other app features.
Output: only the paragraph itself.
''';
```

发给模型的用户消息（7 日数字）：

来源：`lib/features/progress/presentation/pages/progress_page.dart` 第 90–124 行

```dart
    // P2 sanctioned diff #2: only Arm A has a narrative summary card.
    // Arm B renders the chart + counts and nothing else here.
    if (Arm.isA(context)) {
      _generateLlmSummary(data, isEn);
    }
  }

  Future<void> _generateLlmSummary(WeeklyProgress d, bool isEn) async {
    await TranscriptConsentPrompter.maybePrompt(
      context: context,
      moduleKey: 'm9_progress',
    );
    if (!mounted) return;
    final core = CoreServicesScope.of(context);
    final response = await core.llm.send(
      moduleId: 'm9_progress_summary',
      systemPrompt: isEn ? _systemPromptEn : _systemPromptZh,
      history: const [],
      userInput: [
        'check-ins: ${d.moodScores.length}',
        'days with contact: ${d.contactDays}',
        'plans authored: ${d.plansAuthored}',
        'plans followed up: ${d.plansFollowedUp}',
        'reminiscence sessions: ${d.reminiscenceSessions}',
        if (d.moodScores.isNotEmpty)
          'avg mood (1-5): ${(d.moodScores.reduce((a, b) => a + b) / d.moodScores.length).toStringAsFixed(1)}',
      ].join('\n'),
    );
    if (!mounted) return;
    setState(() {
      _summary = response.text.isNotEmpty
          ? response.text
          : _staticSummary(d, isEn);
    });
  }
```

## 4. 「問下呢篇」（M8 文章问答，只 A 组）

来源：`lib/features/education/presentation/pages/education_article_page.dart` 第 27–62 行

```dart
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
```

`%ARTICLE%` 替换成文章全文：

来源：`lib/features/education/presentation/pages/education_article_page.dart` 第 91–105 行

```dart
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
```

另外，从文章跳到通通聊天时，文章内容作为 contextSuffix 加进通通的 prompt，见 01 文件 6.6 节。

## 5. 回忆模块（M3，阿珍/阿伯）的开场白和会话小结

来源：`lib/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart` 第 107–146 行

```dart
  String _openerSystemPromptZh(String themeTitle) => '''
你叫{{VARIANT_NAME}}（一個 AI 機械人，peer-aged 聆聽者）。今次同一位香港長者開始今週嘅人生回顧 session。
今週主題：「$themeTitle」。

請寫一句溫和、開放嘅開場白，邀請佢就「$themeTitle」呢個主題開始分享。
- 用粵語／口語繁體中文。
- 1 至 2 句，總共唔好超過 60 字。
- 如果有過往幾週嘅 context，可以自然咁 reference 一個具體細節（例如：「上次你提到$themeTitle…」），但唔強求。
- 唔好假設、唔好分析、唔好過分親密。
- 唔好用「我會諗起你」呢類依附語言。
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
```

开场白调用（附加称呼和过往几周内容）：

来源：`lib/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart` 第 226–268 行

```dart
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
```

会话小结调用：

来源：`lib/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart` 第 608–628 行

```dart
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
```

## 6. 首页个性化开场白（`agent_greeting_service.dart`，只 A 组）

只为阿珍/阿伯和通通生成；代码里没有小欣的分支（`agentId` 不是 `ah_jan_ah_bak` 时一律走通通的 prompt）。

来源：`lib/core/llm/agent_greeting_service.dart` 第 46–50 行

```dart
  /// Soft caps so a runaway LLM response doesn't blow out the chat
  /// bubble.  Cantonese characters count as 1; English uses ~2x.
  static const int _zhCharCap = 120;
  static const int _enCharCap = 250;

```

来源：`lib/core/llm/agent_greeting_service.dart` 第 114–134 行

```dart
    final weekIndex = _weekIndexSince(profile.createdAt);
    final systemPrompt = _buildPrompt(
      agentId: agentId,
      profile: profile,
      isEn: isEn,
      lastSessionTopic: lastSessionTopic,
      weekIndex: weekIndex,
    );

    try {
      final response = await _llm.send(
        moduleId: 'greeting_$agentId',
        systemPrompt: systemPrompt,
        agentId: agentId,
        userInput: isEn
            ? "Generate today's greeting."
            : '生成今日嘅開場白。',
        history: const [],
        uid: uid,
        armCode: profile.arm?.code,
      );
```

来源：`lib/core/llm/agent_greeting_service.dart` 第 211–308 行

```dart
  String _buildPrompt({
    required String agentId,
    required UserProfile profile,
    required bool isEn,
    required String? lastSessionTopic,
    required int weekIndex,
  }) {
    final interests = profile.interests.isEmpty
        ? (isEn ? '(none captured)' : '(未有記錄)')
        : profile.interests.take(8).join(isEn ? ', ' : '、');
    final avoid = (profile.avoidTopics ?? '').trim().isEmpty
        ? (isEn ? '(none)' : '冇')
        : profile.avoidTopics!.trim();
    final lastTopic = (lastSessionTopic ?? '').trim().isEmpty
        ? (isEn ? '(no prior session)' : '(冇之前傾過)')
        : lastSessionTopic!.trim();

    if (agentId == 'ah_jan_ah_bak') {
      if (isEn) {
        return '''
You are Ah Jan / Ah Bak, a reflective peer-listener helping a Hong Kong
elder revisit life memories. Here is the user's context:
- Interests: $interests
- Last session topic (if any): $lastTopic
- Current week: $weekIndex (4-week M3 reminiscence cycle)
- Do NOT bring up: $avoid

Write ONE short opener (1-2 sentences, warm conversational English) that:
- Naturally references a specific detail the user mentioned before
  (if lastSessionTopic is available), OR
- Cues a reminiscence prompt appropriate for week $weekIndex
  (week 1 = childhood, week 2 = youth/family formation,
   week 3 = midlife/work, week 4 = present/future)
- AVOID generic openers like "How are you today?"
- Do NOT mention other agents by name
- Keep it under $_enCharCap characters.

Example: "Last time you mentioned your older sister taking you to the
wet market to pick fish — would you like to share more about those days?"
''';
      }
      return '''
你係阿珍／阿伯，一位 reflective peer-listener，幫一位香港長者整理人生回憶。
以下係用戶嘅 context:
- 興趣: $interests
- 上次傾過 (如果有): $lastTopic
- 而家係第 $weekIndex 個禮拜 (4-week M3 reminiscence cycle)
- 唔好提起: $avoid

請寫一句短嘅開場白 (1-2 句, 粵語口語繁體中文)，要：
- 自然提起一個用戶之前講過嘅具體細節 (如果有 lastSessionTopic)
- 或者引一個適合 week $weekIndex 嘅 reminiscence prompt
  (week 1 = 童年, week 2 = 青年/成家, week 3 = 中年/工作, week 4 = 而家/未來)
- 唔好用 "你今日點？" 呢類 generic 嘅嘢
- 唔好提其他 agent 名
- 唔好超過 $_zhCharCap 個字。

例: "上次你話起家姐成日帶你去街市揀魚，今日想再講多啲嗰啲日子嗎？"
''';
    }

    // tung_tung
    if (isEn) {
      return '''
You are Tung Tung, a curious AI companion who loves chatting with Hong
Kong elders about their interests. Here is the user's context:
- Interests: $interests
- Last session topic (if any): $lastTopic
- Do NOT bring up: $avoid

Write ONE short opener (1-2 sentences, light + curious English) that:
- Naturally hooks into one of the user's interests (e.g. "cooking"), OR
- Follows up on the last session topic if available
- AVOID generic openers like "How are you today?"
- Do NOT mention other agents by name
- Keep it under $_enCharCap characters.

Example: "I remember you mentioned you love cooking — have you tried any
new dishes lately?"
''';
    }
    return '''
你係通通，一個好奇心強嘅 AI 機械人，鍾意陪香港長者傾偈傾興趣。
以下係用戶 context:
- 興趣: $interests
- 上次傾過 (如果有): $lastTopic
- 唔好提起: $avoid

請寫一句短嘅開場白 (1-2 句, 粵語口語繁體中文)，要：
- 自然引一個用戶嘅 interest (例如 "煮食") 入手
- 或者 follow up 上次傾過嘅話題
- 唔好用 "你今日點？" 呢類 generic 嘅嘢
- 唔好提其他 agent 名
- 唔好超過 $_zhCharCap 個字。

例: "我記得你話鍾意煮餸 — 你最近有冇試新嘅菜式？"
''';
  }
```

## 7. 社交建议（M6，个性化，只 A 组）

来源：`lib/features/social_suggestions/presentation/pages/social_suggestions_page.dart` 第 28–57 行

```dart
  // M6 social suggestions — voiced as Siu Yan (PPR Caring, daily
  // touchpoint).  Product Overview §3.1 maps Siu Yan to "daily
  // companion + motivational messaging"; social suggestions fit there.
  static const _systemPromptZh = '''
你係小欣（一個 AI 機械人），幫一位香港長者諗一兩件可以今日或聽日做嘅小社交活動。
規矩：
- 用粵語/口語繁體中文。
- 出 1 或 2 個建議，每個 1 句，唔超過 35 字。
- 如果提供咗對方提過嘅朋友或屋企人嘅名，盡量自然咁引用。
- 唔好建議要花錢、要長途、要報名嘅活動。
- 唔好用「應該」、「必須」、「你需要」呢類字眼。
- 唔好教訓、唔好提其他 app 功能。
- 唔好講「我會諗起你」/「我擔心你」呢類依附語言。
輸出格式：每個建議一行，用 - 開頭。唔好其他文字。
''';

  static const _systemPromptEn = '''
You are a warm companion. Propose one or two small social activities a
Hong Kong older adult could do today or tomorrow.
Rules:
- Reply in plain English.
- Output 1 or 2 suggestions, each one sentence, max 30 words.
- If you know names of friends or family the user has mentioned, weave
  one in naturally.
- Do not suggest expensive, far-away, or commitment-heavy activities.
- Avoid "you should", "you must", "you need to".
- Do not lecture, do not mention other app features.
Output format: one suggestion per line, each starting with "- ". No
other text.
''';
```

来源：`lib/features/social_suggestions/presentation/pages/social_suggestions_page.dart` 第 80–107 行

```dart
    final memorySnips = <String>[];
    if (profile != null) {
      final entries = await core.memory.recentAcross(
        uid: profile.uid,
        moduleIds: const [
          'm2_check_in',
          'm3_reminiscence_w1',
          'm3_reminiscence_w2',
          'm3_reminiscence_w3',
        ],
        perModule: 1,
      );
      memorySnips.addAll(entries.map((e) => '- ${e.summary}'));
    }
    final userInput = memorySnips.isEmpty
        ? (isEn
            ? 'No prior memory yet. Suggest gentle starting actions.'
            : '冇之前嘅記憶。請建議溫和嘅起步行動。')
        : (isEn
            ? 'Prior memory snippets from this user:\n${memorySnips.join('\n')}'
            : '呢位用戶之前提過嘅內容：\n${memorySnips.join('\n')}');

    final response = await core.llm.send(
      moduleId: 'm6_suggestions',
      systemPrompt: isEn ? _systemPromptEn : _systemPromptZh,
      history: const [],
      userInput: userInput,
    );
```

## 8. 行动计划（M7，只 A 组）

计划小结：

来源：`lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart` 第 48–60 行

```dart
  static const _summarySystemPromptZh = '''
你係一個鼓勵者，幫長者整理一個 if-then 計劃。用粵語/口語繁體中文，
寫一句 if-then 句式，唔超過 40 字。例：「聽朝食完早餐之後，
我會打畀阿May傾 5 分鐘。如果佢冇聽，我下午再試。」
唔好加額外建議或鼓勵。淨係寫一句句子。
''';

  static const _summarySystemPromptEn = '''
You help an older adult crystallise an if-then plan. Reply in plain
English, one sentence, max 40 words. Example: "Tomorrow morning after
breakfast, I will call May for 5 minutes. If she doesn't pick up, I will
try again in the afternoon." No extra encouragement or suggestions.
''';
```

来源：`lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart` 第 183–203 行

```dart
  Future<void> _generateSummary() async {
    await TranscriptConsentPrompter.maybePrompt(
      context: context,
      moduleKey: 'm7_action_loop',
    );
    if (!mounted) return;
    final core = CoreServicesScope.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    setState(() => _busy = true);
    final response = await core.llm.send(
      moduleId: 'm7_action_loop_summary',
      systemPrompt: isEn ? _summarySystemPromptEn : _summarySystemPromptZh,
      history: const [],
      userInput: [
        'action: $_action',
        'when: $_whenText',
        'where: $_whereText',
        'with: $_whoWith',
        'fallback: $_fallback',
      ].join('\n'),
    );
```

计划跟进：

来源：`lib/features/action_loop/presentation/pages/action_loop_followup_page.dart` 第 32–44 行

```dart
  static const _systemPromptZh = '''
你係一個鼓勵者，幫長者回顧佢嘅小行動。用粵語/口語繁體中文，
1-2 句。承認佢做咗咩，唔好教訓、唔好強加意義。
如果未做到，輕輕話佢冇問題，「下次再試」就夠。
唔好提其他功能、唔好建議新計劃。
''';

  static const _systemPromptEn = '''
You help an older adult reflect on their small step. Reply in plain
English, 1–2 sentences. Acknowledge what they did. No lecturing, no
imposed meaning. If they didn't manage it, say it's fine and next time
counts. Do not suggest other modules or new plans.
''';
```

来源：`lib/features/action_loop/presentation/pages/action_loop_followup_page.dart` 第 94–113 行

```dart
    if (Arm.isA(context)) {
      await TranscriptConsentPrompter.maybePrompt(
        context: context,
        moduleKey: 'm7_followup',
      );
      if (!mounted) return;
      final response = await core.llm.send(
        moduleId: 'm7_action_loop_followup',
        systemPrompt: isEn ? _systemPromptEn : _systemPromptZh,
        history: const [],
        userInput: [
          'plan: ${widget.plan.action}',
          'outcome: ${_outcome!.name}',
          if (_noteCtrl.text.trim().isNotEmpty) 'note: ${_noteCtrl.text.trim()}',
        ].join('\n'),
      );
      if (mounted) {
        _llmReply = response.text.isNotEmpty
            ? response.text
            : (isEn ? 'Thanks for telling me.' : '多謝你話畀我聽。');
```

## 9. 跨陪伴者转介（只 A 组）

两层：App 先用关键词找候选（9.1），再由服务器 `referralJudgement` 问模型要不要提出转介（9.2）。

### 9.1 触发关键词

来源：`lib/core/cross_referral/triggers_config.dart` 第 42–140 行

```dart
  static const List<ReferralTrigger> all = [
    // → Ah Jan / Ah Bak (reminiscence + reflective material)
    ReferralTrigger(
      targetAgentId: 'ah_jan_ah_bak',
      tag: 'ah_jan_time_terms',
      sourceAgents: ['siu_yan', 'tung_tung'],
      phrases: [
        '細個',
        '以前嗰陣',
        '年青嗰陣',
        '嗰啲年',
        '童年',
        '結婚',
        '當年',
        'when i was young',
        'back then',
        'in the old days',
      ],
    ),
    ReferralTrigger(
      targetAgentId: 'ah_jan_ah_bak',
      tag: 'ah_jan_memory_verbs',
      sourceAgents: ['siu_yan', 'tung_tung'],
      phrases: [
        '諗起',
        '想起',
        '記得',
        '回憶',
        'i remember',
        'reminded me of',
      ],
    ),

    // → Tung Tung (interests / curiosity / lookups)
    ReferralTrigger(
      targetAgentId: 'tung_tung',
      tag: 'tung_tung_lookup_intent',
      sourceAgents: ['siu_yan', 'ah_jan_ah_bak'],
      phrases: [
        '我想知',
        '邊度有',
        '係咩',
        '點解',
        '查下',
        'i want to know',
        'where can i find',
        'what is',
      ],
    ),
    ReferralTrigger(
      targetAgentId: 'tung_tung',
      tag: 'tung_tung_interest_keywords',
      sourceAgents: ['siu_yan', 'ah_jan_ah_bak'],
      phrases: [
        '粵劇',
        '馬經',
        '新聞',
        '飲茶',
        '麻雀',
        '種花',
        '老歌',
        'cantonese opera',
        'news',
        'mahjong',
      ],
    ),

    // → Siu Yan (acute emotional / isolation content)
    ReferralTrigger(
      targetAgentId: 'siu_yan',
      tag: 'siu_yan_acute_emotion',
      sourceAgents: ['ah_jan_ah_bak', 'tung_tung'],
      phrases: [
        '好慘',
        '好難過',
        '唔開心',
        '唔知點算',
        'so sad',
        'so hard',
        "i don't know what to do",
      ],
    ),
    ReferralTrigger(
      targetAgentId: 'siu_yan',
      tag: 'siu_yan_isolation',
      sourceAgents: ['ah_jan_ah_bak', 'tung_tung'],
      phrases: [
        '冇人理',
        '孤獨',
        '一個人',
        'lonely',
        'no one',
        'alone',
      ],
    ),
  ];
}

class ReferralMatch {
```

### 9.2 判断 prompt（system 用来源陪伴者的 persona 文件）

来源：`functions/index.js` 第 469–540 行

```js
    const sourcePrompt = resolvePrompt({
      promptKey: `${sourceAgentId}_v1`,
      variantName: payload.variantName,
    });
    if (!sourcePrompt) {
      throw new HttpsError("internal", "source persona prompt missing");
    }

    const judgementPrompt = locale === "en" ?
      `A cross-referral candidacy flag has been raised for ${targetAgentId}.
The matched user content was: "${matchedText}"

Considering the full conversation, decide one of:
SURFACE: user is wrapping up or wants this content addressed more deeply.
DEFER: user is mid-thought or the matter is already being addressed.
SKIP: the content is incidental.

Constraints:
- At most one referral per conversation.
- Do not surface if the user explicitly said they want to keep talking
  to you, or if a referral was offered in the past 5 turns.

Reply in this exact JSON shape:
{"decision":"SURFACE|DEFER|SKIP","suggestion":"<the referral phrasing in
your own agent voice if SURFACE, else empty>"}` :
      `而家有個 cross-referral 候選 raise 咗，target 係 ${targetAgentId}。
觸發內容係：「${matchedText}」

睇翻段對話，答以下其中一個：
SURFACE: 用戶有 wrap up 跡象或者想呢段內容俾人接住傾深啲。
DEFER: 用戶仲喺諗緊或者你哋已經喺處理緊。
SKIP: 內容係順帶一句，唔重要。

限制：
- 一段對話最多一次 referral。
- 用戶明確話「想繼續同你」唔好 surface。
- 過去 5 turn 內已經 offer 過 referral 唔好再 surface。

請用呢個 JSON 格式答：
{"decision":"SURFACE|DEFER|SKIP","suggestion":"<如果 SURFACE 用你本人嘅
agent 聲音寫邀請；其他情況留空>"}`;

    // P-2 (2026-09): same identifier scrub as proxyDeepSeek — the recent
    // turns and the matched phrase are participant text leaving the region.
    const messages = [];
    recentTurns.slice(-10).forEach((t) => {
      if (t && t.role && t.content) {
        messages.push({role: t.role, content: stripPII(t.content)});
      }
    });
    messages.push({role: "user", content: stripPII(judgementPrompt)});

    const response = await fetch(
      "https://api.deepseek.com/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": ["Bearer", DEEPSEEK_API_KEY.value()].join(" "),
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          messages: [
            {role: "system", content: sourcePrompt},
            ...messages,
          ],
          max_tokens: 200,
          temperature: 0.3,
          response_format: {type: "json_object"},
        }),
      },
    );
```

## 10. 服务器端与安全/机制标记有关的词表（不是 prompt）

记忆 v1：命中这些词的内容不进入任何记忆层：

来源：`functions/memory.js` 第 66–83 行

```js
/**
 * Safety terms: content matching these never enters any layer. Turns that
 * tripped the client lexicon are already excluded from the buffer; this is
 * a server-side backstop.
 */
const SAFETY_TERMS = [
  "自殺", "自杀", "想死", "死咗算", "唔想再生", "結束自己", "结束自己", "跳樓",
  "跳楼", "燒炭", "烧炭", "自殘", "自残", "suicide", "kill myself",
  "end my life", "self-harm",
];

/**
 * Appointment words the user volunteers with a date ("下個禮拜四睇醫生")
 * don't make a follow-up sensitive: asking how it went is the point of
 * the layer (spec: 「你上次話睇醫生，結果點呀？」). Diagnoses (癌, 手術,
 * 病 …) still do. Pending PI sign-off.
 */
const APPOINTMENT_TERMS = ["睇醫生", "覆診", "醫生", "診所", "醫"];
```

通通网络搜索结果的过滤词：

来源：`functions/index.js` 第 570–585 行

```js
const _searchSafetyDeny = [
  /\b(diagnose|diagnosis|prescribe|cure|dosage)\b/i,
  /(處方|劑量|診斷指引|醫療建議)/,
  /\b(buy now|sell now|invest in)\b/i,
  /(股票推介|理財建議|投資建議)/,
  /\b(self.?harm|suicide method)\b/i,
  /(自殺方法|自殘方法)/,
];

function passesSafetyFilter(text) {
  if (!text || typeof text !== "string") return false;
  for (const pat of _searchSafetyDeny) {
    if (pat.test(text)) return false;
  }
  return true;
}
```

5 个 LLM 机制标记用的词表（模型回复后由代码判断）：

来源：`functions/llm_flags.js` 第 185–252 行

```js
const HONEST_UNFAMILIARITY_PATTERNS = [
  // Chinese (traditional / Cantonese)
  /我未聽過/, /我冇聽過/, /我未必/, /我唔識/, /我並不(熟悉|認識)/,
  /唔好意思.{0,5}(我唔|我未)/, /你話我知/, /你可唔可以(同我講|話我聽)/,
  /我未必清楚/, /我並未認識/, /我未認識/,
  // Simplified
  /我没听过/, /我不熟悉/, /请告诉我/, /我并不认识/,
  // English
  /\bi (don'?t|do not) know\b/i,
  /\bi'?m not familiar with\b/i,
  /\bi haven'?t heard of\b/i,
  /\b(can|could) you tell me (about|more)/i,
  /\btell me more about\b/i,
];

function flagHonestUnfamiliarity(response) {
  return HONEST_UNFAMILIARITY_PATTERNS.some((p) => p.test(response));
}

// ---------------------------------------------------------------------------
// Flag 4 — mixed-content routing
// ---------------------------------------------------------------------------
// User turn contains BOTH an informational/topical marker AND an affect
// marker; response contains a cross-referral phrasing (suggests handoff to
// another agent).  This is the "detect conjoined info + emotion, route
// each to the right agent" affordance.
const INFO_MARKERS = [
  // Things you'd ask Tung Tung about — facts, topics, places
  /點(整|做|買|搵|去)/, /邊度有/, /有冇/, /幾錢/, /喺邊度/,
  /如何/, /怎樣/, /\bhow (do|can) i\b/i, /\bwhere (can|do) i\b/i,
];
const AFFECT_MARKERS = [
  // Emotional content the source agent should hand off to Siu Yan / Ah Jan
  /好[傷孤難失]/, /好(辛苦|攰|擔心|嬲|難過)/, /唔開心/, /好驚/, /好亂/,
  /\b(sad|lonely|worried|scared|anxious|hurt|angry)\b/i,
];
const REFERRAL_MARKERS = [
  // Hybrid cross-referral phrasings — "wanna talk to X?"
  /搵(阿珍|阿伯|小欣|通通)/, /同(阿珍|阿伯|小欣|通通)(傾|講)/,
  /過去(搵|同).{1,6}傾/, /要唔要去(搵|同|傾)/, /搵.{1,3}傾下/,
  /talk to (siu yan|ah jan|ah bak|tung tung)/i,
  /(siu yan|ah jan|ah bak|tung tung) might/i,
];

function flagMixedContentRouting(userInput, response) {
  const hasInfo = INFO_MARKERS.some((p) => p.test(userInput));
  const hasAffect = AFFECT_MARKERS.some((p) => p.test(userInput));
  if (!(hasInfo && hasAffect)) return false;
  return REFERRAL_MARKERS.some((p) => p.test(response));
}

// ---------------------------------------------------------------------------
// Flag 5 — generative summary
// ---------------------------------------------------------------------------
// Per-session end summary (M3) or weekly narrative (M9).  Markers:
//   moduleId in {m3_summary, m9_weekly_narrative} (preferred when client
//     tags it) OR the response has the structural shape of a summary:
//     mentions ≥2 distinct timeframe / activity markers in 1–3 sentences
//     and uses second-person address.
const TIMEFRAME_MARKERS = [
  /今個禮拜/, /上個禮拜/, /呢個星期/, /過去[幾今]?(日|個禮拜|個星期|個月)/,
  /禮拜[一二三四五六日]/, /(本|這|上)週/, /上次/, /嗰日/, /今日/,
  /\bthis week\b/i, /\blast week\b/i, /\bover the past\b/i,
];
const SECOND_PERSON_MARKERS = [
  /\b你\b/, /你嘅/, /你哋/, /\byou\b/i, /\byour\b/i,
];

```
