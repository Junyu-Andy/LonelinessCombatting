# 规则组：16 项活动建议池和 Action Loop 模板

**结论**：规则组的社交建议从 16 条固定建议里每天轮出 2 条；选中一条后进入行动计划表单（Action Loop），
时间、地点、同谁、做不到点算各有 3 个固定选项，24 小时后有一条固定提醒。跟进页两组共用，规则组跟进后没有回应文字。

**app 实际显示哪个版本**：`lib/app/app_settings.dart` 第 45 行 `englishEnabled = false`，第 50 行把 locale 强制为 `zh`。
所以 `zh:` / `isEn ? … : …` 里**只有中文（粤语）版本会显示**；英文版照样导出，老人看不到。
规则组内容全部写在 Dart 源码里，不在 ARB 本地化文件里。

## 条数

| 项目 | 条数 | 怎么数的 |
|---|---|---|
| 社交建议池 | 16 | `suggestion_pool.dart` 第 31–154 行行首 `SocialSuggestion(` 个数（不含第 1 个类构造函数）；家人 4、朋友 4、社区 4、独处反思 4 |
| Action Loop 选项 | 12 | action_loop_arm_b_page.dart 第 111–130 行：时间 3、地点 3、同谁 3、做不到点算 3 |
| Action Loop 24 小时提醒模板 | 1 | action_loop_arm_b_page.dart 第 92–95 行 |

## 1. 建议池

来源：`lib/features/social_suggestions/data/suggestion_pool.dart`（整个文件，共 164 行，SHA-256 `c29cfca6d8801f50…`）

```dart
/// Spec §M6: "rotating list of generic suggestions drawn from a fixed
/// pool of ~40 items grouped by effort level (low/medium/high) and type
/// (family/friend/community/solo-reflective)."
///
/// Sprint 3 ships an HK-flavoured seed pool (16 items). The full ~40
/// will be co-designed in Phase A — this list is meant to be edited.
/// Avoid Western-centric activities; lean local (yum cha, parks,
/// community centres, MTR-walkable distances).
enum SuggestionEffort { low, medium, high }

enum SuggestionType { family, friend, community, soloReflective }

class SocialSuggestion {
  final String id;
  final String zh;
  final String en;
  final SuggestionEffort effort;
  final SuggestionType type;
  const SocialSuggestion({
    required this.id,
    required this.zh,
    required this.en,
    required this.effort,
    required this.type,
  });
}

class SuggestionPool {
  const SuggestionPool();

  static const all = <SocialSuggestion>[
    // Family — low effort
    SocialSuggestion(
      id: 'family_text_morning',
      zh: '傳個「早晨」短訊畀屋企人。',
      en: 'Send a "good morning" text to a family member.',
      effort: SuggestionEffort.low,
      type: SuggestionType.family,
    ),
    SocialSuggestion(
      id: 'family_voice_note',
      zh: '錄個 30 秒語音畀仔女或孫，講今日見到咩。',
      en: 'Record a 30-second voice note for a child or grandchild '
          'about something you saw today.',
      effort: SuggestionEffort.low,
      type: SuggestionType.family,
    ),
    SocialSuggestion(
      id: 'family_share_photo',
      zh: '揀一張舊相分享畀屋企人，講個小故事。',
      en: 'Pick an old photo, share it with family with a short note.',
      effort: SuggestionEffort.medium,
      type: SuggestionType.family,
    ),
    SocialSuggestion(
      id: 'family_yum_cha',
      zh: '約屋企人去飲茶，唔使一定週末。',
      en: 'Invite family to yum cha — doesn\'t have to be the weekend.',
      effort: SuggestionEffort.high,
      type: SuggestionType.family,
    ),

    // Friend — low to high
    SocialSuggestion(
      id: 'friend_check_in',
      zh: '打畀好耐冇傾偈嘅朋友，問句最近點。',
      en: 'Call a friend you haven\'t spoken to in a while, just to say hi.',
      effort: SuggestionEffort.medium,
      type: SuggestionType.friend,
    ),
    SocialSuggestion(
      id: 'friend_morning_walk',
      zh: '約朋友早上喺公園散步 20 分鐘。',
      en: 'Walk in the park with a friend for 20 minutes in the morning.',
      effort: SuggestionEffort.medium,
      type: SuggestionType.friend,
    ),
    SocialSuggestion(
      id: 'friend_share_recipe',
      zh: '同朋友 WhatsApp 分享一個你鍾意嘅煮食方法。',
      en: 'WhatsApp a friend a recipe you enjoy making.',
      effort: SuggestionEffort.low,
      type: SuggestionType.friend,
    ),
    SocialSuggestion(
      id: 'friend_birthday_call',
      zh: '聽日有冇朋友生日？提早一日 send 個祝福。',
      en: 'Anyone\'s birthday tomorrow? Send a message a day early.',
      effort: SuggestionEffort.low,
      type: SuggestionType.friend,
    ),

    // Community — outings + groups
    SocialSuggestion(
      id: 'community_centre_visit',
      zh: '去屋企附近嘅長者中心睇下今個禮拜有咩活動。',
      en: 'Drop by the local community centre and see this week\'s events.',
      effort: SuggestionEffort.medium,
      type: SuggestionType.community,
    ),
    SocialSuggestion(
      id: 'community_morning_park',
      zh: '朝早去公園做下太極或者散步，留意吓有冇熟面孔。',
      en: 'Morning tai chi or stroll in the park — keep an eye out for '
          'familiar faces.',
      effort: SuggestionEffort.low,
      type: SuggestionType.community,
    ),
    SocialSuggestion(
      id: 'community_library',
      zh: '去公共圖書館坐一坐，揀一本書翻吓。',
      en: 'Spend an hour at the public library with one book.',
      effort: SuggestionEffort.low,
      type: SuggestionType.community,
    ),
    SocialSuggestion(
      id: 'community_volunteer_short',
      zh: '報名一個 1-2 小時嘅義工活動，唔使長期承諾。',
      en: 'Sign up for a 1–2 hour volunteer slot — no long commitment.',
      effort: SuggestionEffort.high,
      type: SuggestionType.community,
    ),

    // Solo-reflective
    SocialSuggestion(
      id: 'solo_letter',
      zh: '寫一封信畀以前嘅自己，唔需要寄。',
      en: 'Write a letter to your past self — you don\'t have to send it.',
      effort: SuggestionEffort.medium,
      type: SuggestionType.soloReflective,
    ),
    SocialSuggestion(
      id: 'solo_three_things',
      zh: '寫低今日三件令你覺得平靜嘅事。',
      en: 'Write down three things today that felt calm.',
      effort: SuggestionEffort.low,
      type: SuggestionType.soloReflective,
    ),
    SocialSuggestion(
      id: 'solo_music',
      zh: '聽一首你後生時鍾意嘅歌，記低諗起嘅人或地方。',
      en: 'Play a song you loved when you were younger. Note who or where '
          'it brings to mind.',
      effort: SuggestionEffort.low,
      type: SuggestionType.soloReflective,
    ),
    SocialSuggestion(
      id: 'solo_window_watch',
      zh: '坐喺窗邊 10 分鐘，留意外面有咩動靜。',
      en: 'Sit by the window for 10 minutes and watch what passes.',
      effort: SuggestionEffort.low,
      type: SuggestionType.soloReflective,
    ),
  ];

  /// Pick the next [count] suggestions deterministically from a rotation
  /// seed (e.g. day-of-year) so Arm B users see a stable but rotating
  /// set without us tracking shown-history.
  List<SocialSuggestion> rotate({required int seed, int count = 2}) {
    final list = [...all];
    final offset = seed.abs() % list.length;
    return List.generate(count, (i) => list[(offset + i) % list.length]);
  }
}
```

## 2. 社交建议页（规则组显示部分）

来源：`lib/features/social_suggestions/presentation/pages/social_suggestions_page.dart` 第 130–216 行

```dart
        builder: (_) => ActionLoopArmBPage(seedAction: suggestion),
      ));
    }
  }

  void _acceptArmB(SocialSuggestion s) {
    // Per spec, Arm B "accepts a suggestion → hand off to Module 7
    // (rule-based version) for a static plan template." That means
    // the planner — not a silent half-row. The action text is pre-
    // filled; the user picks when/where/contact/fallback.
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    _planFromSuggestion(isEn ? s.en : s.zh);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final pool = const SuggestionPool();
    // Use day-of-year as rotation seed (stable per day per device).
    final seed = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    final rotated = pool.rotate(seed: seed);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'One small invitation' : '今日嘅小邀請'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              isEn
                  ? 'Pick anything that feels right. Skip what doesn\'t.'
                  : '揀一個試下，唔啱就 skip。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (Arm.isA(context))
              ..._buildArmA(isEn)
            else
              ..._buildArmB(rotated, isEn),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildArmA(bool isEn) {
    if (_busy) {
      return [
        AppLoadingIndicator.inline(
          message: isEn
              ? 'Thinking of a small idea for you…'
              : '諗緊一啲適合你嘅小行動…',
        ),
      ];
    }
    final items = _personalised;
    if (items == null || items.isEmpty) {
      // Fall back to the static pool if the model returned nothing.
      return _buildArmB(
        const SuggestionPool().rotate(seed: DateTime.now().day),
        isEn,
      );
    }
    return [
      for (final s in items)
        _SuggestionCard(
          title: s,
          onAccept: () => _planFromSuggestion(s),
          acceptLabel: isEn ? 'Plan it' : '計劃做',
        ),
    ];
  }

  List<Widget> _buildArmB(List<SocialSuggestion> rotated, bool isEn) {
    return [
      for (final s in rotated)
        _SuggestionCard(
          title: isEn ? s.en : s.zh,
          onAccept: () => _acceptArmB(s),
          acceptLabel: isEn ? 'Plan it' : '計劃做',
        ),
    ];
  }
}
```

## 3. Action Loop 表单（规则组）

来源：`lib/features/action_loop/presentation/pages/action_loop_arm_b_page.dart` 第 80–215 行

```dart
          armCode: 'B',
          createdAt: DateTime.now(),
        ),
      );
      if (planId != null) {
        final reminders = FirestoreReminderQueue(available: auth.available);
        await reminders.schedule(
          uid: profile.uid,
          profile: profile, // B.10 — 今日休息 suppression
          request: ReminderRequest(
            kind: 'm7_followup',
            fireAt: DateTime.now().add(const Duration(hours: 24)),
            titleZh: '件事點呀？',
            titleEn: 'How did it go?',
            bodyZh: '你之前計劃做：${_actionCtrl.text.trim()}。',
            bodyEn: 'Your plan: ${_actionCtrl.text.trim()}.',
            linkedDocId: planId,
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    final times = isEn
        ? const ['Morning', 'Afternoon', 'Evening']
        : const ['上晝', '下晝', '晚上'];
    final places = isEn
        ? const ['At home', 'Outdoors', 'Somewhere else']
        : const ['屋企', '出街', '其他地方'];
    final contacts = isEn
        ? const ['Family', 'A friend', 'Alone']
        : const ['屋企人', '朋友', '一個人'];
    final fallbacks = isEn
        ? const [
            'Try again later in the day',
            'Try again tomorrow',
            'Let it go for this time',
          ]
        : const [
            '今日遲啲再試',
            '聽日再試',
            '今次算',
          ];

    return Scaffold(
      appBar: AppBar(
          title: Text(isEn ? 'Plan a small step' : '計劃一個小行動')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              isEn
                  ? 'Pick the pieces of your plan.'
                  : '揀返你個計劃嘅資料。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            _Label(text: isEn ? 'What' : '做咩'),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _actionCtrl,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText:
                          isEn ? 'e.g. Call my sister' : '例：打電話畀家姐',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                VoiceInputButton(
                  controller: _voice,
                  prefix: () => _actionCtrl.text,
                  onText: (t) {
                    _actionCtrl.text = t;
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Label(text: isEn ? 'When' : '幾時'),
            _ChipPicker(
              options: times,
              selected: _timeOfDay,
              onChanged: (v) => setState(() => _timeOfDay = v),
            ),
            const SizedBox(height: 16),
            _Label(text: isEn ? 'Where' : '邊度'),
            _ChipPicker(
              options: places,
              selected: _place,
              onChanged: (v) => setState(() => _place = v),
            ),
            const SizedBox(height: 16),
            _Label(text: isEn ? 'Who' : '同邊個'),
            _ChipPicker(
              options: contacts,
              selected: _contact,
              onChanged: (v) => setState(() => _contact = v),
            ),
            const SizedBox(height: 16),
            _Label(text: isEn ? 'If it doesn\'t work out' : '如果唔成功'),
            _ChipPicker(
              options: fallbacks,
              selected: _fallback,
              onChanged: (v) => setState(() => _fallback = v),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isComplete && !_busy ? _save : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  isEn ? 'Save plan' : '儲存計劃',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ],
        ),
      ),
```

## 4. Action Loop 入口页（两组共用）

来源：`lib/features/action_loop/presentation/pages/action_loop_landing.dart` 第 100–205 行

```dart
          ],
        ),
      ),
    );
  }

  void _openPlanner(BuildContext context) {
    final builder = Arm.isA(context)
        ? (_) => const ActionLoopArmAPage()
        : (BuildContext _) => const ActionLoopArmBPage();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }

  void _openFollowUp(BuildContext context, ActionPlan plan) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActionLoopFollowUpPage(plan: plan),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final bool isEn;
  const _IntroCard({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_rtl_outlined,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  isEn ? 'One small step at a time' : '由一件小事開始',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isEn
                  ? 'Pick one thing to try. We\'ll ask how it went next '
                      'time you open the app.'
                  : '揀一件你想試嘅小事。下次返嚟，我會問你件事點呀。',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingPlanCard extends StatelessWidget {
  final ActionPlan plan;
  final VoidCallback onTap;
  const _PendingPlanCard({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.hourglass_bottom,
                    size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.action, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${plan.whenText} · ${plan.whoWith}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  isEn ? 'How did it go?' : '點呀？',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
```

## 5. Action Loop 跟进页（两组共用；只有 Hybrid 组跟进后有 AI 回应）

来源：`lib/features/action_loop/presentation/pages/action_loop_followup_page.dart` 第 130–230 行

```dart

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final p = widget.plan;

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'How did it go?' : '件事點呀？')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isEn ? 'Your plan was' : '你之前計劃',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                    const SizedBox(height: 6),
                    Text(p.action, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text('${p.whenText} · ${p.whereText} · ${p.whoWith}',
                        style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isEn ? 'Did it happen?' : '件事有冇發生？',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _OutcomeChoice(
              outcome: FollowUpOutcome.happened,
              labelZh: '做到喇',
              labelEn: 'Yes, I did it',
              selected: _outcome,
              onChanged: (v) => setState(() => _outcome = v),
            ),
            _OutcomeChoice(
              outcome: FollowUpOutcome.partial,
              labelZh: '做咗一部分',
              labelEn: 'Partly',
              selected: _outcome,
              onChanged: (v) => setState(() => _outcome = v),
            ),
            _OutcomeChoice(
              outcome: FollowUpOutcome.didNotHappen,
              labelZh: '未做到',
              labelEn: 'Not this time',
              selected: _outcome,
              onChanged: (v) => setState(() => _outcome = v),
            ),
            const SizedBox(height: 16),
            Text(
              isEn ? 'Anything to add (optional)' : '想加少少嘢都得（選擇性）',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    style: theme.textTheme.bodyLarge,
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                VoiceInputButton(
                  controller: _voice,
                  prefix: () => _noteCtrl.text,
                  onText: (t) => _noteCtrl.text = t,
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _outcome != null && !_busy && !_saved ? _save : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _busy
                    ? const CircularProgressIndicator()
                    : Text(
                        _saved
                            ? (isEn ? 'Saved' : '已儲存')
                            : (isEn ? 'Save' : '儲存'),
                        style: const TextStyle(fontSize: 20),
                      ),
              ),
            ),
            if (_llmReply != null) ...[
```
