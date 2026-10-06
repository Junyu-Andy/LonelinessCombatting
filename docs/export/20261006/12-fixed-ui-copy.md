# 补充：老人可见的固定界面文字（按组）

**结论**：这一份补齐前 11 个文件没有导出的固定文字：Hybrid 组页面里写死的开场白、表单提问、后备句和转介卡；
只给 Hybrid 组看的 onboarding 记忆告知（**组间差异**）；两组共用的安全弹窗、安全按钮和安全关键词词库；
onboarding 孤单时段题的选项；以及进度页、行动计划入口页的零碎文字。

**app 实际显示哪个版本**：`lib/app/app_settings.dart` 第 45 行 `englishEnabled = false`，第 50 行把 locale 强制为 `zh`
（`lib/main.dart` 第 115 行也传 `Locale('zh')`）。所以 `isEn ? 英文 : 中文` 和 `…Zh / …En` 成对的文字里，**只有中文版会显示**。
英文版照样导出，老人看不到。`app_zh_Hant_HK.arb` 虽然编译进去了，但 app 从不选 `zh_Hant_HK`，实际用的是 `app_zh.arb`；
本文件的内容都写在 Dart / JS 源码里，不在 ARB 文件里。

## 条数

| 项目 | 条数 | 怎么数的 |
|---|---|---|
| 小欣签到开场白（Hybrid） | 11 | check_in_arm_a.dart `_openingLine`：今日心情 5 句 + 上次心情 5 句 + 无心情 1 句（中文；英文另有同数）；另 `_moodChangeOpener` 心情变化 2 句 |
| Action Loop 提问（Hybrid） | 5 | action_loop_arm_a_page.dart 第 92–100 行 5 步提问 |
| 通通固定开场白（Hybrid） | 3 | tung_tung_page.dart 文章问答 1、按兴趣后备 1、通用 1 |
| 阿珍/阿伯反思固定句（Hybrid） | 5 | 重听模板 3（第 84–92 行）+ 负面想法回应 1（第 376 行）+ 开场提示 1（第 551 行） |
| onboarding 记忆告知（只 Hybrid） | 1 | agent_onboarding_page.dart 第 380–383 行 |
| 转介卡文字（Hybrid） | 1 | referral_suggestion_card.dart 第 207 行（另有按钮 2 个） |
| 安全弹窗按钮（两组） | 3 | distress_router.dart 第 136、149、168 行 |
| 孤单时段选项（两组） | 9 | intake_flow_page.dart `_timingOptionsZh` 项数 |

## A. 只有 Hybrid 组

### A1. 小欣签到开场白（按心情的固定句）

来源：`lib/features/context/presentation/pages/check_in_arm_a.dart` 第 277–362 行

```dart
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
```

### A2. Action Loop 表单文字（Hybrid 组；规则组版本见 04 文件）

5 步提问：

来源：`lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart` 第 86–102 行

```dart
    super.dispose();
  }

  String _promptZh() {
    switch (_step) {
      case _Step.action:
        return '想做嘅小事係咩？一句講晒就得。';
      case _Step.when_:
        return '幾時做？例如「聽朝食完早餐」、「今晚 8 點」。';
      case _Step.where_:
        return '喺邊度做？屋企、公園、定其他地方？';
      case _Step.who:
        return '同邊個有關？打畀邊位？或者一個人都得。';
      case _Step.fallback:
        return '如果計劃唔成功，你會點？(例如：遲啲再試)';
      case _Step.review:
      case _Step.saved:
```

步骤标签、AI 失败时的后备小结模板（第 208 行）：

来源：`lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart` 第 163–212 行

```dart

  String _stepLabel(bool isEn) {
    switch (_step) {
      case _Step.action:
        return isEn ? 'What' : '做咩';
      case _Step.when_:
        return isEn ? 'When' : '幾時';
      case _Step.where_:
        return isEn ? 'Where' : '邊度';
      case _Step.who:
        return isEn ? 'Who' : '同邊個';
      case _Step.fallback:
        return isEn ? 'If not' : '唔得點';
      case _Step.review:
        return isEn ? 'Review' : '檢視';
      case _Step.saved:
        return isEn ? 'Saved' : '完成';
    }
  }

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
    if (!mounted) return;
    final fallbackSummary = isEn
        ? '$_whenText at $_whereText, with $_whoWith — $_action. '
            'If not, $_fallback.'
        : '$_whenText 喺 $_whereText，同 $_whoWith — $_action。如果唔得，$_fallback。';
    setState(() {
      _busy = false;
      _summary = response.text.isNotEmpty ? response.text : fallbackSummary;
    });
```

页面标题、整理中、保存按钮、保存后提示：

来源：`lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart` 第 276–400 行

```dart
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Plan a small step' : '計劃一個小行動'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppStepper(
                currentStep: _step.index,
                totalSteps: _Step.values.length - 1, // exclude 'saved'
                stepLabel: _stepLabel(isEn),
              ),
              const SizedBox(height: 12),
              _ProgressChips(step: _step),
              const SizedBox(height: 16),
              if (_step == _Step.review) ...[
                Text(
                  isEn ? 'Here\'s your plan' : '呢個係你嘅計劃',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: _busy
                        ? AppLoadingIndicator.inline(
                            message: isEn
                                ? 'Let me put it together…'
                                : '畀我整理緊…',
                          )
                        : Text(
                            _summary,
                            style:
                                theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                          ),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _savePlan,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      isEn ? 'Save plan' : '儲存計劃',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ] else if (_step == _Step.saved) ...[
                const Spacer(),
                Center(
                  child: Text(
                    isEn ? 'Saved — see you back here.' : '收到。等你返嚟同我講件事點。',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const Spacer(),
              ] else ...[
                Text(
                  isEn ? _promptEn() : _promptZh(),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        style: theme.textTheme.bodyLarge,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _advance(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    VoiceInputButton(
                      controller: _voice,
                      prefix: () => _ctrl.text,
                      onText: (t) => _ctrl.text = t,
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _advance,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      isEn ? 'Next' : '下一步',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressChips extends StatelessWidget {
  final _Step step;
  const _ProgressChips({required this.step});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final labels = isEn
        ? const ['What', 'When', 'Where', 'Who', 'If not', 'Review']
        : const ['做咩', '幾時', '邊度', '同邊個', '唔得點', '檢視'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(labels.length, (i) {
```

### A3. 通通固定开场白

来源：`lib/features/curious_companion/presentation/pages/tung_tung_page.dart` 第 184–228 行

```dart

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
```

### A4. 阿珍/阿伯反思对话固定句

老人连续撳「重听」时的模板：

来源：`lib/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart` 第 80–96 行

```dart
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

```

检测到负面想法时的一句：

来源：`lib/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart` 第 366–380 行

```dart
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
```

页面标题和开场提示：

来源：`lib/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart` 第 535–553 行

```dart
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
```

### A5. onboarding 记忆告知（只给 Phase B 记忆模式的用户，即 Hybrid 组）

来源：`lib/features/onboarding/presentation/pages/agent_onboarding_page.dart` 第 352–387 行

```dart
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'Three AI companions, each with a different role'
                : '三個 AI 夥伴，各有唔同角色',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          Text(
            isEn
                ? 'These are AI robots, not people. They will not replace '
                    'your relationships with real friends and family. Each '
                    'one is designed for a specific kind of conversation, '
                    'so you choose who to talk to based on what you want '
                    'to share today.'
                : '佢哋係 AI 機械人，唔係真人，亦都唔會代替你身邊嘅家人朋友。'
                    '佢哋每一個都係專門做一件事，所以你想傾乜，就揀對應嘅夥伴。',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          // Phase B Arm A: memory is on for everyone, so say so up front.
          if (MemoryModes.of(AppSettingsScope.of(context).profile) ==
              MemoryMode.phaseB) ...[
            const SizedBox(height: 14),
            Text(
              isEn
                  ? 'They will remember what you tell them, so the next '
                      'chat can pick up where you left off. You can see '
                      'and delete what they remember any time in '
                      'Settings → What I remember.'
                  : '佢哋會記得你講過嘅嘢，下次傾偈就可以接得上。'
                      '你隨時可以喺「設定 → 我記得嘅嘢」睇返同刪走。',
              key: const Key('onboarding_memory_notice'),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
          ],
```

### A6. 跨陪伴者转介卡

来源：`lib/core/cross_referral/referral_suggestion_card.dart` 第 100–160 行

```dart
            children: [
              Row(
                children: [
                  AgentAvatar(agent: target, size: 36),
                  const SizedBox(width: 10),
                  Text(
                    isEn ? 'Talk to ' : '搵 ',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    isEn
                        ? target.resolveVariant(null).displayNameEn
                        : target.resolveVariant(null).displayNameZh,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: target.accentColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    isEn ? '?' : '？',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.surfaced.suggestionText,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: target.accentColor,
                      ),
                      onPressed: _onAccept,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          isEn ? 'Go talk to them' : '好，過去傾',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _onDecline,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          isEn ? 'Not now' : '唔使住',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ],
```

来源：`lib/core/cross_referral/referral_suggestion_card.dart` 第 195–212 行

```dart
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz_rounded, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isEn
                  ? '$fromName said you were thinking about something. '
                      'Want to start there?'
                  : '$fromName 話你諗緊一啲嘢。要唔要由嗰度開始？',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
```

## B. 两组共用

### B1. 安全弹窗（moderate_interrupt 时）

来源：`lib/core/safety/distress_router.dart` 第 100–179 行

```dart
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.favorite_border,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEn
                        ? 'Sounds like a heavy moment'
                        : '我聽到你而家可能唔多舒服',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isEn
                  ? 'Want to do something to help yourself settle?'
                  : '要唔要做啲嘢，幫自己 settle 啲？',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            _ActionButton(
              icon: Icons.air,
              label: isEn
                  ? 'Quiet a moment (4-4-6 breathing)'
                  : '靜一靜（4-4-6 呼吸）',
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CalmPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _ActionButton(
              icon: Icons.phone_in_talk_outlined,
              label: isEn ? 'Reach someone' : '搵人傾',
              onPressed: () {
                AnalyticsScope.of(context)
                    .logEvent(PhaseAEvents.moderateSheetOpenedResources);
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const EmergencySupportPage(from: 'moderate_sheet'),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  isEn ? 'I\'m OK, keep going' : '我冇事，繼續',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

```

### B2. 安全按钮（页面上的安全小标签）

来源：`lib/core/safety/safety_overlay.dart` 第 120–155 行

```dart
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final l10n = AppLocalizations.of(context);
    final level = _state?.level ?? DistressLevel.none;

    final (String label, String semantic, Color bg, IconData icon) =
        switch (level) {
      DistressLevel.none ||
      DistressLevel.low =>
        (
          l10n?.safetyPillLow ?? (isEn ? 'Talk now' : '搵人傾'),
          isEn ? 'Talk to someone now' : '即刻搵人傾',
          const Color(0xFFB91C1C),
          Icons.support_agent_rounded,
        ),
      DistressLevel.moderateReview || DistressLevel.moderateInterrupt => (
          l10n?.safetyPillModerate ?? (isEn ? 'Need support?' : '需要支援？'),
          isEn ? 'Open support options' : '打開支援選項',
          const Color(0xFF991B1B),
          Icons.support_agent_rounded,
        ),
      DistressLevel.acute => (
          l10n?.safetyPillAcute ?? (isEn ? 'Crisis line' : '緊急熱線'),
          isEn ? 'Open the crisis line' : '打開緊急熱線',
          const Color(0xFF7F1D1D),
          Icons.emergency_share_rounded,
        ),
    };

    final fontWeight =
        level == DistressLevel.acute ? FontWeight.w800 : FontWeight.w700;

```

小标签的 ARB 文字（`app_zh.arb` 是实际使用的）：

来源：`lib/l10n/app_zh.arb`（行号: 原文）

```json
65: "safetyPillLow": "搵人傾",
66: "safetyPillModerate": "需要支援？",
67: "safetyPillAcute": "緊急熱線"
```

来源：`lib/l10n/app_en.arb`（行号: 原文）

```json
65: "safetyPillLow": "Talk now",
66: "safetyPillModerate": "Need support?",
67: "safetyPillAcute": "Crisis line"
```

### B3. 安全关键词词库（DistressDetector v5，两组完全相同）

来源：`lib/core/safety/distress_detector.dart`（整个文件，共 418 行，SHA-256 `079af7a774161450…`）

```dart
/// Severity tiers for free-text input. Rule-based, deterministic, identical
/// in both arms (per Master Feature Spec §Safety controls).
///
/// Phase A baseline (S-1, 2026-09): the former single `moderate` tier is
/// split in two so that grief / hardship language spoken *as part of a
/// life-review memory* is logged for weekly review but does not interrupt
/// the participant, while present-tense hopelessness / burden / "nobody
/// cares" language still surfaces the soft support prompt.
///
/// Tiers (check order is acute → moderateInterrupt → moderateReview → low →
/// none; the first tier with a hit wins, so the enum order below is the
/// severity order and `index` comparisons are valid):
/// - [none]: no concerning content detected.
/// - [low]: language suggesting persistent loneliness, sadness, or isolation.
///   Module flows can soften copy; no escalation.
/// - [moderateReview]: recent loss / grief / past hardship.  LLM still
///   replies; **no** prompt, **no** template, **no** pill change.  Logged +
///   flagged for the research team's weekly review.
/// - [moderateInterrupt]: hopelessness, "burden" / worthlessness cognitions,
///   "nobody cares", overwhelmed.  LLM still replies; the per-agent safety
///   template is shown *in addition* and the soft support sheet is offered.
///   Logged + weekly review.
/// - [acute]: self-harm, suicidal ideation, harm-to-others. LLM is
///   short-circuited; full-screen crisis page + acute template; notify the
///   research team within 24 h.
enum DistressLevel {
  none,
  low,
  moderateReview,
  moderateInterrupt,
  acute;

  /// Either moderate tier (the pre-S-1 `moderate` band).
  bool get isModerate =>
      this == DistressLevel.moderateReview ||
      this == DistressLevel.moderateInterrupt;

  /// Snake-case tier code used in Firestore `turns.detector.tier`
  /// (`none` / `low` / `moderate_review` / `moderate_interrupt` / `acute`).
  String get tierCode => switch (this) {
        DistressLevel.none => 'none',
        DistressLevel.low => 'low',
        DistressLevel.moderateReview => 'moderate_review',
        DistressLevel.moderateInterrupt => 'moderate_interrupt',
        DistressLevel.acute => 'acute',
      };

  /// Legacy 4-band label (`none` / `low` / `moderate` / `acute`) kept for
  /// the `safety_events.level` field, whose Firestore rule and Cloud
  /// Function trigger predate the S-1 split.
  String get legacyLevelCode => isModerate ? 'moderate' : name;

  /// Parses either the enum name, the snake-case tier code, or the legacy
  /// `moderate` label (mapped to [moderateInterrupt], the fail-safe side).
  static DistressLevel parse(String? raw) {
    switch (raw) {
      case 'low':
        return DistressLevel.low;
      case 'moderate_review':
      case 'moderateReview':
        return DistressLevel.moderateReview;
      case 'moderate':
      case 'moderate_interrupt':
      case 'moderateInterrupt':
        return DistressLevel.moderateInterrupt;
      case 'acute':
        return DistressLevel.acute;
      default:
        return DistressLevel.none;
    }
  }
}

/// Lexical category of the matched term (Phase A `turns.detector.category`).
/// Lets the PI filter e.g. `harm_to_others` or third-person `ideation`
/// false positives during manual review without re-running the detector.
enum DistressCategory {
  ideation,
  worthlessness,
  selfHarm,
  harmToOthers,
  lossGrief,
  hardship,
  distress,
  low;

  String get code => switch (this) {
        DistressCategory.ideation => 'ideation',
        DistressCategory.worthlessness => 'worthlessness',
        DistressCategory.selfHarm => 'self_harm',
        DistressCategory.harmToOthers => 'harm_to_others',
        DistressCategory.lossGrief => 'loss_grief',
        DistressCategory.hardship => 'hardship',
        DistressCategory.distress => 'distress',
        DistressCategory.low => 'low',
      };
}

class DistressMatch {
  final DistressLevel level;

  /// The first matched keyword. Useful for analytics + audit; never shown to
  /// the user verbatim.
  final String? matchedTerm;

  /// Category of [matchedTerm]; null when [level] is [DistressLevel.none].
  final DistressCategory? category;

  const DistressMatch(this.level, [this.matchedTerm, this.category]);

  /// True for both moderate tiers and acute — i.e. the turn is written to
  /// `safety_events` and flagged for weekly review.
  bool get isEscalation => level.isModerate || level == DistressLevel.acute;

  /// True only when the participant-facing template + soft prompt fire
  /// (moderate_interrupt) — moderate_review is deliberately silent.
  bool get interrupts => level == DistressLevel.moderateInterrupt;
}

/// One lexicon group: every term carries the tier + category it maps to.
class _TermGroup {
  final DistressLevel level;
  final DistressCategory category;
  final List<String> terms;
  const _TermGroup(this.level, this.category, this.terms);
}

/// Rule-based detector. Cantonese / Mandarin / English keyword lists, lower-
/// cased substring match. Intentionally over-triggers in the [moderate] /
/// [acute] tiers — false positives surface resources; false negatives don't.
///
/// **Not LLM-dependent on purpose.** Safety equivalence between Arm A and
/// Arm B requires that the same input produces the same flag regardless of
/// which arm a user is in. The LLM may augment the response, but the trigger
/// must be deterministic.
class DistressDetector {
  const DistressDetector();

  /// Wordlist version. Bump on every term-list change with a CHANGELOG entry.
  ///
  /// CHANGELOG
  /// ---------
  /// v1 (2026-06, P5.4)  — initial HK Cantonese / Mandarin / English lists.
  /// v2 (2026-06, T1)    — Dev TestWeek safety sensitisation. FAIL-SAFE
  ///   additions only; detection LOGIC unchanged. Approved by Junyu (knows
  ///   PI) before merge.
  ///   • moderate +「負累」 (burden cognition, alongside 拖累 / 累贅).
  ///   • acute: covered 7 synthetic-corpus misses with broader phrasings —
  ///     EN: 'taking my own life', 'only way out', "if i'm dead",
  ///         'reason to live', 'will to live';
  ///     ZH: broadened 我唔想再生→唔想再生; added 冇我會好過 / 冇我會好啲.
  ///   • Result: acute recall 0.86→≥0.98; moderate 0.92; none precision 1.00.
  // v4-2026-07: D1–D6 (see docs/safety/distress_detector_lexicon_v4-2026-07.md).
  // D4 (hopelessness unified at moderate) is flagged PI-clinical-signoff-pending
  // in that doc — applied here for testing per Junyu's direction.
  // v5-2026-09 (Phase A baseline, S-1): the 67 moderate terms are split into
  //   moderate_review (19: loss/grief + past hardship) and
  //   moderate_interrupt (48: everything else).  Term SET unchanged from v4;
  //   only the tier assignment and the new per-term category changed.
  //   Check order acute → moderate_interrupt → moderate_review → low.
  //   S-7: the four 絕望-family terms live in [_hopelessnessTerms] and take
  //   [hopelessnessTier] so the PI's pending decision (keep moderate →
  //   interrupt, or promote to acute) is a one-line lexicon edit.
  static const String wordlistVersion = 'v5-2026-09';

  /// S-7 — tier for 冇晒希望 / 沒晒希望 / 無晒希望 / 没有希望.  Default
  /// (PI decision pending) keeps the v4 D4 position: moderate → interrupt.
  /// Flip to [DistressLevel.acute] if clinical sign-off promotes them; no
  /// other code changes are needed.
  static const DistressLevel hopelessnessTier = DistressLevel.moderateInterrupt;
  static const List<String> _hopelessnessTerms = [
    '冇晒希望', '沒晒希望', '無晒希望', '没有希望',
  ];

  // P5.4 keyword lists — tuned with HK Cantonese indirect expressions
  // alongside direct ones. Substrings are deliberately specific (e.g.
  // '結束自己' rather than '結束' alone) to avoid over-triggering on
  // benign uses ('結束會議', '死火').
  //
  // Tuning policy:
  //   - Acute: optimise for recall (false negative is the unsafe
  //     outcome). False positives are cheap — at worst we surface
  //     CrisisHelp when a participant said something fine.
  //   - Moderate: balance recall + precision; over-triggering pesters.
  //   - Low: precision-leaning; this tier never escalates.
  // v4-2026-07 lexicon — full changelog + PI decisions (D1–D6) in
  // docs/safety/distress_detector_lexicon_v4-2026-07.md.  Acute-first check
  // order is load-bearing: several acute terms contain moderate terms
  // (e.g. 真係想死 ⊃ 想死).  冇-based terms are emitted in 冇/沒/無 variants.
  // ---------------------------------------------------------------------
  // ACUTE — unchanged from v4 (term set + order).  Grouped by category.
  // ---------------------------------------------------------------------
  static const _acuteGroups = <_TermGroup>[
    _TermGroup(DistressLevel.acute, DistressCategory.ideation, [
      // EN — ideation
      'kill myself', 'end my life', 'end it all', 'suicide', 'want to die',
      'better off dead', 'no point living', 'no reason to live',
      'no will to live', 'lost my will to live', 'lost the will to live',
      "can't go on", 'cant go on', 'cannot go on', 'can not go on',
      "don't want to live", 'dont want to live', 'rather be dead',
      'take my own life', 'taking my own life', 'no way out', 'only way out',
      "if i'm dead", 'if im dead', 'kill himself', 'kill herself',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.worthlessness, [
      // EN — worthlessness
      "i'm worthless", 'i am worthless', 'im worthless', 'i have no worth',
      'no reason to exist', 'nobody needs me', 'no one needs me',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.selfHarm, [
      // EN — self-harm (v4)
      'self harm', 'self-harm', 'harm myself', 'hurt myself', 'hurting myself',
      'cut myself', 'cutting myself',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.harmToOthers, [
      // EN — harm-to-others
      'want to kill someone', 'want to kill him', 'want to kill her',
      'want to kill them', 'want to hurt someone',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.ideation, [
      // 繁體/粵語 — ideation
      '自殺', '好想死', '真係想死', '真想死', '結束自己', '結束我嘅生命',
      '了結自己', '了結生命', '想跳樓', '上吊', '燒炭',
      '冇咗我會好啲', '沒咗我會好啲', '無咗我會好啲',
      '冇咗我會好過', '沒咗我會好過', '無咗我會好過',
      '冇我嘅世界', '沒我嘅世界', '無我嘅世界', '想消失', '消失咗就好',
      '冇我會好過', '沒我會好過', '無我會好過',
      '冇我會好啲', '沒我會好啲', '無我會好啲',
      '冇得救', '沒得救', '無得救', '冇路可走', '沒路可走', '無路可走',
      '冇後路', '沒後路', '無後路', '唔想再生', '不如死咗',
      '再活落去都冇意思', '再活落去都沒意思', '再活落去都無意思',
      '活落去冇意思', '活落去沒意思', '活落去無意思',
      '生存冇意義', '生存沒意義', '生存無意義',
      '生存冇意思', '生存沒意思', '生存無意思',
      '唔想活', '活唔落去', '諗唔開',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.worthlessness, [
      // 繁體/粵語 — worthlessness
      '活著冇價值', '活著沒價值', '活著無價值',
      '生存冇價值', '生存沒價值', '生存無價值',
      '我冇價值', '我沒價值', '我無價值',
      '冇存在價值', '沒存在價值', '無存在價值',
      '我係多餘', '我係廢人', '冇人需要我', '沒人需要我', '無人需要我',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.selfHarm, [
      // 繁體/粵語 — self-harm (v4)
      '自殘', '傷害自己', '𠝹手',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.harmToOthers, [
      // 繁體/粵語 — harm-to-others
      '想殺人', '我想殺死', '我想殺咗', '想傷害人', '我想傷害佢', '我想弄死',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.ideation, [
      // 简体 — ideation
      '自杀', '真的想死', '结束自己', '了结自己', '了结生命', '想跳楼', '烧炭',
      '没我会更好', '没得救', '没有出路', '没路可走', '没有后路', '不如死了',
      '没意思活下去', '活下去没意思', '不想活', '活不下去', '想不开',
      '生存没有意义',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.worthlessness, [
      // 简体 — worthlessness
      '活着没价值', '生存没有价值', '我没有价值', '我没价值', '没有存在价值',
      '没存在价值', '我是多余的', '我是废人', '没人需要我',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.selfHarm, [
      // 简体 — self-harm (v4)
      '自残', '伤害自己',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.harmToOthers, [
      // 简体 — harm-to-others
      '想杀人', '我想杀死', '我想杀了', '想伤害别人', '我想伤害他',
    ]),
  ];

  // ---------------------------------------------------------------------
  // MODERATE_INTERRUPT — 48 of the v4 moderate terms: present-tense
  // hopelessness / burden / worthlessness / "nobody cares" / overwhelmed,
  // plus the D1-demoted bare 想死.  Template + soft prompt fire.
  // ---------------------------------------------------------------------
  static const _moderateInterruptGroups = <_TermGroup>[
    // Term ORDER inside this tier mirrors v4 so `matchedTerm` (first hit)
    // is unchanged for messages that contain several moderate terms
    // (e.g. T-6 「冇人理我，我係個負擔」 → 冇人理我).
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.distress, [
      // EN
      'hopeless', 'burden', 'nobody cares', 'no one cares', "can't cope",
      'cant cope', 'overwhelmed', 'falling apart',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.worthlessness, [
      // 繁體/粵語 — worthlessness
      '冇用', '沒用', '無用',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.distress, [
      // 繁體/粵語 — nobody cares / nobody loves me
      '冇人理我', '沒人理我', '無人理我',
      '冇人關心', '沒人關心', '無人關心', '冇人愛我', '沒人愛我', '無人愛我',
      '都唔理我', '都唔關心我',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.worthlessness, [
      // 繁體/粵語 — burden cognitions
      '拖累', '累贅', '負累', '負擔',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.distress, [
      // 繁體/粵語 — can't cope / hopeless / collapse
      '頂唔順', '撐唔住', '撐不住', '絕望',
      '孤獨到痛', '崩潰', '崩到爆',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.ideation, [
      // 繁體/粵語 — ideation-adjacent (D1: demoted from acute)
      '想死',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.worthlessness, [
      // 简体 — worthlessness
      '没用',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.distress, [
      // 简体 — nobody cares
      '没人理', '没人关心', '没人爱我',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.worthlessness, [
      // 简体 — burden
      '累赘', '负担',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.distress, [
      // 简体 — can't cope / hopeless / collapse
      '撑不住', '顶不住', '绝望', '崩溃',
    ]),
  ];

  // ---------------------------------------------------------------------
  // MODERATE_REVIEW — 19 of the v4 moderate terms: loss / grief and past
  // hardship.  These are the normal vocabulary of a life review: the LLM
  // replies and keeps listening; nothing interrupts; logged for review.
  // ---------------------------------------------------------------------
  static const _moderateReviewGroups = <_TermGroup>[
    _TermGroup(DistressLevel.moderateReview, DistressCategory.lossGrief, [
      // 繁體/粵語 — loss / grief
      '失去咗', '老伴走咗', '剛去世', '過咗身', '過世', '離世', '哀傷', '悲痛',
    ]),
    _TermGroup(DistressLevel.moderateReview, DistressCategory.hardship, [
      // 繁體/粵語 — hardship
      '好辛苦', '辛苦到',
    ]),
    _TermGroup(DistressLevel.moderateReview, DistressCategory.lossGrief, [
      // 简体 — loss / grief
      '老伴走了', '刚去世', '过世', '离世',
    ]),
    _TermGroup(DistressLevel.moderateReview, DistressCategory.lossGrief, [
      // EN — loss / grief
      'lost my husband', 'lost my wife', 'passed away', 'just died', 'grieving',
    ]),
  ];

  static const _lowGroups = <_TermGroup>[
    _TermGroup(DistressLevel.low, DistressCategory.low, [
      // EN
      'lonely', 'alone', 'isolated', 'no one to talk to', 'empty', 'sad',
      'feeling low', 'down today',
      // 繁體/粵語
      '孤獨', '孤單', '寂寞', '一個人', '冇人陪', '沒人陪', '無人陪', '空虛',
      '唔開心', '好悶', '悶悶哋', '冇心機', '沒心機', '無心機',
      '冇咩心機', '沒咩心機', '無咩心機', '冇神冇氣', '沒神沒氣', '無神無氣',
      '冇精神', '沒精神', '無精神', '失落', '低落', '心情差',
      // 简体
      '孤独', '孤单', '一个人', '没人陪', '空虚', '不开心', '没心情', '没精神',
    ]),
  ];

  /// S-7 hopelessness family, placed according to [hopelessnessTier].
  static const _hopelessnessGroup = _TermGroup(
    hopelessnessTier,
    DistressCategory.distress,
    _hopelessnessTerms,
  );

  /// All groups in check order (first hit wins).  The S-7 group is spliced
  /// in at the head of whichever tier [hopelessnessTier] names, so the
  /// acute-first ordering invariant holds for either PI decision.
  static List<_TermGroup> get _orderedGroups => [
        if (hopelessnessTier == DistressLevel.acute) _hopelessnessGroup,
        ..._acuteGroups,
        if (hopelessnessTier == DistressLevel.moderateInterrupt)
          _hopelessnessGroup,
        ..._moderateInterruptGroups,
        if (hopelessnessTier == DistressLevel.moderateReview)
          _hopelessnessGroup,
        ..._moderateReviewGroups,
        if (hopelessnessTier == DistressLevel.low) _hopelessnessGroup,
        ..._lowGroups,
      ];

  /// Lexicon export for docs / spec tooling (`tool/export_spec_inputs.py`
  /// reads the Dart source; this accessor serves the in-app version page
  /// and contract tests).  Returns `(tier, category, term)` in check order.
  static List<(DistressLevel, DistressCategory, String)> get lexicon => [
        for (final g in _orderedGroups)
          for (final t in g.terms) (g.level, g.category, t),
      ];

  /// Terms per tier — used by contract tests to lock the S-1 split
  /// (19 review / 48 interrupt) and the v4 term set.
  static Set<String> termsFor(DistressLevel level) => {
        for (final e in lexicon)
          if (e.$1 == level) e.$3,
      };

  DistressMatch analyze(String text) {
    if (text.trim().isEmpty) return const DistressMatch(DistressLevel.none);
    final lower = text.toLowerCase();
    for (final g in _orderedGroups) {
      for (final t in g.terms) {
        if (lower.contains(t.toLowerCase())) {
          return DistressMatch(g.level, t, g.category);
        }
      }
    }
    return const DistressMatch(DistressLevel.none);
  }
}
```

### B4. onboarding 孤单时段题的选项

来源：`lib/features/onboarding/presentation/pages/intake_flow_page.dart` 第 610–632 行

```dart
  static const _timingOptionsZh = <(String, String)>[
    (IntakeOptions.timingMornings, '早上'),
    (IntakeOptions.timingAfternoons, '下晝'),
    (IntakeOptions.timingEvenings, '夜晚'),
    (IntakeOptions.timingNights, '夜深'),
    (IntakeOptions.timingWeekends, '週末'),
    (IntakeOptions.timingAfterMealsAlone, '自己食完飯之後'),
    (IntakeOptions.timingFestivals, '節日'),
    (IntakeOptions.timingVaries, '冇固定時間'),
    (IntakeOptions.timingOther, '其他'),
  ];

  static const _timingOptionsEn = <(String, String)>[
    (IntakeOptions.timingMornings, 'Mornings'),
    (IntakeOptions.timingAfternoons, 'Afternoons'),
    (IntakeOptions.timingEvenings, 'Evenings'),
    (IntakeOptions.timingNights, 'Late at night'),
    (IntakeOptions.timingWeekends, 'Weekends'),
    (IntakeOptions.timingAfterMealsAlone, 'After eating alone'),
    (IntakeOptions.timingFestivals, 'Festivals / holidays'),
    (IntakeOptions.timingVaries, 'No fixed time'),
    (IntakeOptions.timingOther, 'Other'),
  ];
```

### B5. 零碎界面文字

进度页（本周没有签到时）：

来源：`lib/features/progress/presentation/pages/progress_page.dart` 第 252–264 行

```dart
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (values.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          Localizations.localeOf(context).languageCode == 'en'
              ? 'No check-ins yet this week.'
              : '今個禮拜暫時冇 check-in。',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }
```

行动计划入口页：

来源：`lib/features/action_loop/presentation/pages/action_loop_landing.dart` 第 36–90 行

```dart
  Widget _buildBody(BuildContext context, bool isEn, ThemeData theme,
      AuthService auth, UserProfile? profile, ActionPlanRepository repo) {

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Small steps' : '小行動'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _IntroCard(isEn: isEn),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openPlanner(context),
              icon: const Icon(Icons.add_circle_outline, size: 26),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  isEn ? 'Plan a small step' : '計劃一個小行動',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isEn ? 'Waiting on follow-up' : '等住跟進',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (profile == null)
              Text(
                isEn
                    ? 'Sign in to save plans across sessions.'
                    : '登入之後，計劃可以儲存。',
                style: theme.textTheme.bodyMedium,
              )
            else
              StreamBuilder<List<ActionPlan>>(
                stream: repo.pending(profile.uid),
                builder: (_, snap) {
                  final list = snap.data ?? const <ActionPlan>[];
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        isEn
                            ? 'Nothing waiting. Plan something when you\'re '
                                'ready.'
                            : '冇嘢等緊跟進。準備好就計劃一件小事啦。',
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }
                  return Column(
```
