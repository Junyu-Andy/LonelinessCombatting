# 规则组：三个陪伴者的回应池和关键词规则

**结论**：规则组的三个陪伴者都不调用 AI，内容全部是写死的模板。
- 小欣（签到）：固定表单，心情脸 + 3 道选择题 + 一段文字，提交后一句固定回应。**没有聊天、没有回应池、没有关键词**。
- 阿珍/阿伯（回忆）：每周一句固定开场（和 Hybrid 组同一句），一个输入框，提交即结束。**没有回应、没有关键词**。阿珍/阿伯的自由对话在规则组隐藏（决策 0006）。
- 通通：20 条开场题库（每天轮换一条）+ 10 类话题关键词 → 27 条话题回应 + 6 条通用回应；每第 3 轮在回应后接一句开场题。
- 反思（M5）：规则组**没有**对应版本，入口只在 Hybrid 组显示（`lib/features/my_story/presentation/pages/my_story_page.dart` 第 63–68 行）。

**app 实际显示哪个版本**：`lib/app/app_settings.dart` 第 45 行 `englishEnabled = false`，第 50 行把 locale 强制为 `zh`。
所以 `zh:` / `isEn ? … : …` 里**只有中文（粤语）版本会显示**；英文版照样导出，老人看不到。
规则组内容全部写在 Dart 源码里，不在 ARB 本地化文件里。

## 条数

| 项目 | 条数 | 怎么数的 |
|---|---|---|
| 通通开场题库 | 20 | `tung_tung_rule_pool.dart` 中 `(id: 'tt` 出现次数（tt01–tt20）；文件注释说研究团队要删到 16 条，代码里仍是 20 条 |
| 通通话题类别（关键词规则） | 10 | `tung_tung_rule_responder.dart` 第 63–168 行 `_Topic(` 个数 |
| 通通话题回应 | 27 | 同一范围内 `(zh:` 个数；各类：health 2、food 3、music 3、screen 3、outing 3、weather 3、hobby 3、pet 2、festival 2、past 3 |
| 通通通用回应（没命中关键词时） | 6 | `_generic` 第 170–177 行 `(zh:` 个数 |
| 小欣签到 B 选择题 | 3 | check_in_arm_b.dart 3 个 `const [...]` 选项列表，选项数 4 / 5 / 3 |
| 小欣签到 B 固定回应 | 1 | check_in_arm_b.dart 第 138–140 行 |
| 阿珍/阿伯回忆 B 开场 | 4 | `reminiscence_themes.dart` `ReminiscenceTheme(` 个数（每周 1 条，共 4 周）；全文见 06 文件 |
| 首次介绍文字（`_firstIntroTexts`） | 3 | agent_registry.dart 第 145–167 行，每个陪伴者 1 条；规则组只有通通页面显示 |

## 1. 小欣：签到（规则组页面）

页面文字（标题、问题、选项、提示、按钮、提交后的固定回应）：

来源：`lib/features/context/presentation/pages/check_in_arm_b.dart` 第 50–146 行

```dart
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Siu Yan' : '小欣')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text(
              isEn ? 'How are you today?' : '你今日點呀？',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            MoodFacePicker(
              value: _face,
              onChanged: (v) => setState(() => _face = v),
            ),
            const SizedBox(height: 24),
            _MultipleChoice(
              prompt: isEn
                  ? 'Did you talk with anyone today?'
                  : '今日有冇同人傾過偈？',
              options: isEn
                  ? const ['Not at all', 'A little', 'Quite a bit', 'A lot']
                  : const ['冇', '少少', '幾多', '好多'],
              selected: _talkedAnswer,
              onChanged: (v) => setState(() => _talkedAnswer = v),
            ),
            const SizedBox(height: 16),
            _MultipleChoice(
              prompt: isEn
                  ? 'How would you rate your social day?'
                  : '今日嘅社交時間，你會點評價？',
              options: isEn
                  ? const ['Hard', 'So-so', 'OK', 'Good', 'Great']
                  : const ['辛苦', '麻麻', '可以', '幾好', '好好'],
              selected: _socialDayAnswer,
              onChanged: (v) => setState(() => _socialDayAnswer = v),
            ),
            const SizedBox(height: 16),
            _MultipleChoice(
              prompt: isEn
                  ? 'Anything significant today?'
                  : '今日有冇咩特別事？',
              options: isEn
                  ? const ['Nothing', 'A small thing', 'Something big']
                  : const ['冇', '一啲小事', '一件大事'],
              selected: _significantEventAnswer,
              onChanged: (v) => setState(() => _significantEventAnswer = v),
            ),
            const SizedBox(height: 24),
            Text(
              isEn
                  ? 'Anything you want to write down (optional)'
                  : '想寫低啲咩都得（選擇性）',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLines: 4,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: isEn
                    ? 'A line or two, only for you to see.'
                    : '一兩句都得，只係你睇到。',
              ),
            ),
            const SizedBox(height: 24),
            AppButton.primary(
              label: isEn ? 'Save check-in' : '儲存今日 Check-in',
              icon: Icons.check_rounded,
              onPressed: _face != null &&
                      _talkedAnswer != null &&
                      _socialDayAnswer != null &&
                      _significantEventAnswer != null &&
                      !_saved
                  ? _save
                  : null,
            ),
            if (_saved) ...[
              const SizedBox(height: 12),
              Text(
                isEn
                    ? 'Saved. See you tomorrow.'
                    : '收到喇。聽日再見。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
```

提交时写入记录的回应文字：

来源：`lib/features/context/presentation/pages/check_in_arm_b.dart` 第 200–225 行

```dart
    setState(() => _saved = true);

    // Decision 0015 — the submission is one agent session, like a chat.
    // The recorder's Firestore writes are fire-and-forget, so this never
    // blocks offline.
    final rec = await RuleSubmissionFlow.record(
      uid: profile?.uid,
      agentId: AgentRegistry.siuYanId,
      moduleId: 'm2_check_in',
      analytics: analytics,
      available: authAvailable,
      text: note,
      detector: distress,
      userSent: submittedAt,
      replyText: isEn ? 'Saved. See you tomorrow.' : '收到喇。聽日再見。',
    );
    if (!mounted) return;

    // Same safety surfaces as every other page (crisis page for acute,
    // support sheet for moderate) — arm-invariant.
    if (distress.level != DistressLevel.none) {
      await core.distressRouter.route(distress, context: context);
      if (distress.level == DistressLevel.acute) return;
    }
    if (profile == null) return;
    await RuleSubmissionFlow.surfaceBriefPr(
```

心情脸的文字（两组共用）：

来源：`lib/features/context/presentation/pages/check_in_shared.dart` 第 1–39 行

```dart
import 'package:flutter/material.dart';

/// Five-face mood picker — kept in lock-step with the home hero pad so
/// the onboarding pick, the hero pick and the post-chat "完成" sheet
/// all speak the same language (1=好差 … 5=好好).
enum MoodFace {
  veryLow,
  low,
  neutral,
  good,
  great;

  /// 1..5 numeric value used everywhere — analytics, [MoodRecorder],
  /// the Siu Yan opener.  No second mapping needed.
  int get rank => index + 1;

  /// Same as [rank] — kept for callers that still ask for
  /// `numericScore`.  Removing the alias would churn analytics call
  /// sites for no behaviour change.
  int get numericScore => rank;

  String emoji() => switch (this) {
        MoodFace.veryLow => '😔',
        MoodFace.low => '🙁',
        MoodFace.neutral => '😐',
        MoodFace.good => '🙂',
        MoodFace.great => '😊',
      };

  String label(bool isEn) => switch (this) {
        MoodFace.veryLow => isEn ? 'Very bad' : '好差',
        MoodFace.low => isEn ? 'Bad' : '差',
        MoodFace.neutral => isEn ? 'So-so' : '麻麻地',
        MoodFace.good => isEn ? 'Good' : '幾好',
        MoodFace.great => isEn ? 'Great' : '好好',
      };
}

class MoodFacePicker extends StatelessWidget {
```

## 2. 阿珍/阿伯：回忆（规则组页面）

每周开场句来自 `lib/features/reminiscence/data/reminiscence_themes.dart`（全文见 06 文件）。

来源：`lib/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart` 第 148–210 行

```dart

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final title = isEn ? widget.theme.titleEn : widget.theme.titleZh;
    final opening =
        isEn ? widget.theme.openingEn : widget.theme.openingZh;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(opening, style: theme.textTheme.bodyLarge),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: VoiceInputButton(
                  controller: _voice,
                  prefix: () => _textCtrl.text,
                  onText: (t) => _textCtrl.text = t,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  maxLines: null,
                  expands: true,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: isEn
                        ? 'Write whatever you remember, or tap the mic to speak.'
                        : '記得幾多寫幾多，或者撳咪用講嘅。',
                    alignLabelWithHint: true,
                  ),
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || _saved ? null : _save,
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
```

## 3. 通通：开场题库

来源：`lib/features/curious_companion/data/tung_tung_rule_pool.dart`（整个文件，共 86 行，SHA-256 `10e376e23fe41819…`）

```dart
/// B.4 — Tung Tung 20-item static interest-chat pool for Arm B.
///
/// Research Review v2 Item 2: expanded from 16 → 20 candidates.
/// Research team will select the final 16; 4 are marked ⚠️ for review.
/// Version lock: bump [_version] whenever the item list changes so analysts
/// can join opener_id × version in telemetry.
///
/// Telemetry contract (caller's responsibility):
///   AnalyticsService.logEvent('tung_tung_opener_shown', {
///     'opener_id': '<id>',
///     'pool_version': TungTungRulePool.version,
///     'turn_index': turnIndex,
///   });
///
/// Per Phase A Proposal §2.3 + Product Overview §4.3, rule-based Tung
/// Tung is delivered via this static pool (parallel to M5's reflective-
/// dialogue pool), preserving three-agent surface symmetry while keeping
/// LLM curious-chat affordances Hybrid-only.
///
/// The pool is hardcoded; cultural advisor review is a Phase A
/// prerequisite (Product Overview §10.2).
library;

class TungTungRulePool {
  const TungTungRulePool._();

  /// Version lock — bump when the item list changes. Analysts join
  /// opener_id × version to detect pool changes mid-study.
  static const String version = '2026-06-v2';

  /// 20 interest-conversation openers across common HK older-adult
  /// interest categories. Research team to cull to 16 before Phase A.
  /// ⚠️ items 12, 13, 15, 17 flagged for cultural advisor review.
  static const List<({String id, String zh, String en})> items = [
    (id: 'tt01', zh: '你今日有冇睇新聞？最近有冇咩嘢令你覺得有趣？',
      en: 'Did you watch the news today? Anything that caught your interest?'),
    (id: 'tt02', zh: '今個季節市場有咩當造嘅嘢食？',
      en: 'What seasonal foods are in the markets right now?'),
    (id: 'tt03', zh: '今日嘅天氣令你諗起咩呢？',
      en: "What does today's weather remind you of?"),
    (id: 'tt04', zh: '你以前最鍾意嘅一首歌係咩？',
      en: 'What was your favourite song from years ago?'),
    (id: 'tt05', zh: '你有冇睇過一齣戲令你睇完仲記得？',
      en: 'Is there a film you watched that you still remember?'),
    (id: 'tt06', zh: '你細個鍾意食咩零食？',
      en: 'What snacks did you love as a kid?'),
    (id: 'tt07', zh: '你曾經住過嘅地方入面，邊一個最有意思？',
      en: "Of the places you've lived, which one feels most meaningful?"),
    (id: 'tt08', zh: '你有冇養過寵物？係咩動物？',
      en: 'Have you ever kept a pet? What kind?'),
    (id: 'tt09', zh: '你最鍾意嘅茶餐廳菜式係咩？',
      en: "What's your favourite cha chaan teng dish?"),
    (id: 'tt10', zh: '你最近行過邊條街令你覺得舒服？',
      en: 'Which street have you walked lately that felt nice?'),
    (id: 'tt11', zh: '你有冇一個老朋友，諗起佢就會笑？',
      en: 'Is there an old friend who makes you smile when you think of them?'),
    (id: 'tt12', zh: '你有冇諗過去邊度旅行？', // ⚠️ mobility assumption — advisor review
      en: 'Where would you go if you could travel anywhere?'),
    (id: 'tt13', zh: '你最近聽到一首歌或者廣播令你停低過一陣？',
      en: 'Has a song or broadcast made you pause lately?'),
    (id: 'tt14', zh: '你鍾意煮咩嘢食？有冇一道菜係你拿手嘅？',
      en: 'What do you like to cook? Is there a dish you make especially well?'),
    (id: 'tt15', zh: '你細個喺邊條街長大？嗰條街而家仲喺唔喺？', // ⚠️ neighbourhood change sensitivity
      en: 'Which street did you grow up on? Is it still there?'),
    (id: 'tt16', zh: '你最近有冇去過茶樓？印象最深係坐喺邊度？',
      en: 'Have you been to a dim sum restaurant lately? Where do you like to sit?'),
    (id: 'tt17', zh: '你有冇參加過邊個社區活動？係點樣嘅感覺？', // ⚠️ social network assumption
      en: 'Have you ever joined a community activity? What was it like?'),
    (id: 'tt18', zh: '你鍾意喺家裏邊定係出去逛逛？',
      en: 'Do you prefer staying at home or going out for a walk?'),
    (id: 'tt19', zh: '你細個最開心嘅一個節日係咩？係點過嘅？',
      en: 'What was your favourite festival as a child? How did you celebrate?'),
    (id: 'tt20', zh: '你有冇一件珍貴嘅舊物品，仲留住佢？',
      en: 'Do you have a treasured old object you still keep?'),
  ];

  /// Returns the next opener in rotation given the [turnIndex] (number
  /// of turns the user has had with rule-based Tung Tung so far).
  ///
  /// Callers should log analytics event `tung_tung_opener_shown` with
  /// the returned `id` and [version] for Phase A calibration.
  static ({String id, String zh, String en}) openerFor(int turnIndex) {
    final idx = turnIndex.abs() % items.length;
    return items[idx];
  }
}
```

规则组的开场怎么选（按日期轮换）：

来源：`lib/features/curious_companion/presentation/pages/tung_tung_page.dart` 第 158–184 行

```dart
    // Seed an opening bubble so the page reads as a chat from the
    // first frame. Tung Tung's tone is light + curious; the article
    // grounded mode (M8 hand-off) opens differently.
    if (!_openerSeeded) {
      _openerSeeded = true;
      _ruleBased = !Arm.isA(context);
      _seedOpener();
    }
  }

  Future<void> _seedOpener() async {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final profile = AppSettingsScope.read(context).profile;

    if (_ruleBased) {
      _openerOffset =
          DateTime.now().difference(DateTime.utc(2026)).inDays;
      final opener = TungTungRulePool.openerFor(_openerOffset);
      setState(() => _turns.add(_Turn.bot(isEn ? opener.en : opener.zh)));
      unawaited(AnalyticsScope.of(context).logEvent('tung_tung_opener_shown', {
        'opener_id': opener.id,
        'pool_version': TungTungRulePool.version,
        'turn_index': 0,
      }));
      return;
    }

```

## 4. 通通：关键词规则和回应模板

来源：`lib/features/curious_companion/data/tung_tung_rule_responder.dart`（整个文件，共 224 行，SHA-256 `db640648a694d2ee…`）

```dart
/// Rule-based Tung Tung replies for Arm B (Phase B).
///
/// Arm B keeps the same chat surface as Arm A but replies come from this
/// fixed, version-locked template set instead of an LLM: the user's turn
/// is matched against topic keyword lists and a pre-written Cantonese
/// reply is picked deterministically. A template never quotes the user's
/// words back — reading and reusing the user's specific content is one of
/// the LLM-unique mechanisms (`specific_content_engagement`) that Arm B
/// must not have.
///
/// Every few turns the reply carries the next opener from
/// [TungTungRulePool] so the conversation keeps moving.
///
/// Telemetry: callers log `tung_tung_rule_reply` with [RuleReply.id] and
/// [version] so analysts can join template × version.
///
/// All strings need cultural-advisor review before recruitment, same as
/// the opener pool.
library;

import 'tung_tung_rule_pool.dart';

class RuleReply {
  /// Stable template id, e.g. `food_2` or `generic_5`.
  final String id;
  final String zh;
  final String en;

  /// The opener appended to this reply, if any (for telemetry).
  final String? openerId;

  const RuleReply({
    required this.id,
    required this.zh,
    required this.en,
    this.openerId,
  });

  String text({required bool isEn}) => isEn ? en : zh;
}

typedef _Template = ({String zh, String en});

class _Topic {
  final String id;
  final List<String> keywords;
  final List<_Template> replies;
  const _Topic(this.id, this.keywords, this.replies);
}

class TungTungRuleResponder {
  const TungTungRuleResponder._();

  /// Bump whenever a keyword list or template changes.
  static const String version = '2026-09-v1';

  /// A new opener is appended on every [openerEvery]-th user turn.
  static const int openerEvery = 3;

  // Order matters: the first topic whose keyword appears wins. Health
  // sits first so 食藥 / 睇醫生 never get a food or outing template. Its
  // replies stay neutral — Tung Tung gives no medical advice in either arm.
  static const List<_Topic> _topics = [
    _Topic('health', [
      '藥', '醫生', '醫院', '覆診', '診所', '病', '痛', '唔舒服', '血壓',
      'doctor', 'hospital', 'medicine', 'sick', 'pain', 'clinic',
    ], [
      (zh: '身體嘅事真係要好好照顧。有咩需要，記得同醫生或者屋企人講。',
        en: 'Health matters deserve care. If you need anything, do tell your doctor or family.'),
      (zh: '辛苦你喇。今日其他時間，你想做啲咩令自己舒服啲？',
        en: 'That sounds tiring. What would you like to do later today to feel a bit better?'),
    ]),
    _Topic('food', [
      '食', '飲茶', '茶樓', '點心', '煮', '餸', '飯', '麵', '粥', '湯',
      '茶餐廳', '奶茶', '街市', 'food', 'eat', 'cook', 'dim sum', 'tea',
    ], [
      (zh: '講起食嘢，真係好多回憶。你平時鍾意自己煮，定係出去食多啲？',
        en: 'Food brings back so many memories. Do you usually cook, or eat out more?'),
      (zh: '食嘢真係生活一大樂趣。有冇一樣嘢，你食極都唔厭？',
        en: 'Food is one of life\'s pleasures. Is there something you never get tired of?'),
      (zh: '聽落好正。你覺得而家同以前嘅味道，有冇唔同咗？',
        en: 'Sounds lovely. Do you think flavours are different now compared with before?'),
    ]),
    _Topic('music', [
      '歌', '音樂', '粵曲', '唱', '收音機', '電台', '聽歌', 'music', 'song',
      'sing', 'radio',
    ], [
      (zh: '音樂真係好神奇，一首歌可以帶人返去好耐之前。你最常喺咩時候聽歌？',
        en: 'Music is magical — one song can take you back years. When do you usually listen?'),
      (zh: '好歌真係百聽唔厭。你鍾意自己唱，定係淨係聽？',
        en: 'A good song never gets old. Do you like singing along, or just listening?'),
      (zh: '有啲歌一響起就會記起某個時候。你有冇咁樣嘅歌？',
        en: 'Some songs bring back a whole moment. Do you have a song like that?'),
    ]),
    _Topic('screen', [
      '戲', '電影', '電視', '劇', '節目', '新聞', 'movie', 'film', 'tv',
      'show', 'news',
    ], [
      (zh: '睇戲睇節目都係好好嘅消遣。你鍾意邊一類多啲？',
        en: 'Films and shows are a nice way to pass time. Which kind do you enjoy most?'),
      (zh: '有時睇完一齣好戲，會諗好耐。你最近有冇睇到印象深嘅？',
        en: 'A good show can stay with you. Seen anything memorable lately?'),
      (zh: '你通常自己一個睇，定係同人一齊睇多啲？',
        en: 'Do you usually watch alone, or with other people?'),
    ]),
    _Topic('outing', [
      '行街', '散步', '公園', '行山', '出街', '旅行', '去咗', '街', '海邊',
      'walk', 'park', 'hike', 'travel', 'trip',
    ], [
      (zh: '出去行下真係幾舒服。你最鍾意去邊度行？',
        en: 'Getting out for a walk feels good. Where do you most like to go?'),
      (zh: '周圍行行，成日會見到新嘢。你通常幾點出去？',
        en: 'Walking around, you often spot something new. What time do you usually go out?'),
      (zh: '香港有好多地方值得行。有冇一個地方你成日都想再去？',
        en: 'Hong Kong has so many places to wander. Is there one you keep wanting to revisit?'),
    ]),
    _Topic('weather', [
      '天氣', '熱', '凍', '落雨', '天晴', '颱風', '冷', 'weather', 'hot',
      'cold', 'rain', 'sunny', 'typhoon',
    ], [
      (zh: '天氣真係影響心情。你鍾意咩天氣多啲？',
        en: 'Weather really shapes the mood. What kind of weather do you like best?'),
      (zh: '呢排天氣變得好快。你平時點樣照顧自己？',
        en: 'The weather changes so quickly lately. How do you look after yourself?'),
      (zh: '每個季節都有佢嘅味道。你最鍾意邊個季節？',
        en: 'Every season has its own feel. Which one is your favourite?'),
    ]),
    _Topic('hobby', [
      '興趣', '嗜好', '麻雀', '象棋', '書法', '畫', '種花', '花', '太極',
      '跳舞', '手工', '睇書', 'hobby', 'mahjong', 'chess', 'paint', 'garden',
      'tai chi', 'read',
    ], [
      (zh: '有個興趣真係好好。你玩咗幾耐㗎喇？',
        en: 'Having a hobby is lovely. How long have you been doing it?'),
      (zh: '聽落好有意思。你係自己學識，定係有人教？',
        en: 'That sounds meaningful. Did you teach yourself, or did someone show you?'),
      (zh: '做自己鍾意嘅嘢，時間過得特別快。你通常幾時做？',
        en: 'Time flies doing what you enjoy. When do you usually do it?'),
    ]),
    _Topic('pet', [
      '狗', '貓', '雀', '魚', '寵物', 'dog', 'cat', 'bird', 'fish', 'pet',
    ], [
      (zh: '小動物真係好可愛。你鍾意貓定係狗多啲？',
        en: 'Animals are so endearing. Do you prefer cats or dogs?'),
      (zh: '有小動物陪住，屋企都熱鬧啲。你以前有冇養過？',
        en: 'Animals make a home livelier. Have you ever kept one?'),
    ]),
    _Topic('festival', [
      '節', '過年', '新年', '中秋', '端午', '冬至', '聖誕', '生日', 'festival',
      'new year', 'birthday', 'christmas',
    ], [
      (zh: '過節總係特別有氣氛。你最鍾意邊個節日？',
        en: 'Festivals always have a special feel. Which one do you like most?'),
      (zh: '每個節日都有唔同嘅習俗。你以前係點樣過嘅？',
        en: 'Each festival has its own customs. How did you use to celebrate?'),
    ]),
    _Topic('past', [
      '以前', '細個', '當年', '年輕', '後生', '舊時', '嗰陣', 'when i was',
      'young', 'used to', 'back then',
    ], [
      (zh: '以前嘅日子真係好多故事。嗰陣時嘅生活係點樣㗎？',
        en: 'The old days hold so many stories. What was life like back then?'),
      (zh: '聽落好有味道。你覺得同而家比，最大分別係咩？',
        en: 'That sounds full of character. What\'s the biggest difference compared with now?'),
      (zh: '好多嘢都變咗。有冇啲嘢你覺得以前嗰種更好？',
        en: 'So much has changed. Is there anything you think was better before?'),
    ]),
  ];

  static const List<_Template> _generic = [
    (zh: '原來係咁。可唔可以講多少少？', en: 'I see. Could you tell me a little more?'),
    (zh: '聽落幾有意思。你點睇？', en: 'That sounds interesting. What do you make of it?'),
    (zh: '多謝你分享。你第一次接觸係幾時？', en: 'Thanks for sharing. When did you first come across it?'),
    (zh: '明白。你覺得最有趣嘅地方係邊度？', en: 'I see. What do you find most interesting about it?'),
    (zh: '好呀，慢慢講，我喺度聽緊。', en: 'Sure — take your time, I\'m listening.'),
    (zh: '嗯，咁你平時會同邊個傾開呢啲？', en: 'Mm. Who do you usually chat about this with?'),
  ];

  /// Reply to the user's [userTurnIndex]-th turn (0-based) of this
  /// session. Deterministic for the same text and index.
  ///
  /// [openerOffset] shifts which opener is appended (e.g. the session's
  /// starting opener index) so consecutive sessions don't repeat.
  static RuleReply reply(
    String userText, {
    required int userTurnIndex,
    int openerOffset = 0,
  }) {
    final lower = userText.toLowerCase();
    String id;
    _Template t;

    _Topic? topic;
    for (final candidate in _topics) {
      if (candidate.keywords.any(lower.contains)) {
        topic = candidate;
        break;
      }
    }
    if (topic != null) {
      final i = userTurnIndex % topic.replies.length;
      id = '${topic.id}_$i';
      t = topic.replies[i];
    } else {
      final i = userTurnIndex % _generic.length;
      id = 'generic_$i';
      t = _generic[i];
    }

    // Every openerEvery-th turn, move the conversation on with a fresh
    // opener question from the pool.
    if ((userTurnIndex + 1) % openerEvery == 0) {
      final opener = TungTungRulePool.openerFor(
          openerOffset + 1 + userTurnIndex ~/ openerEvery);
      return RuleReply(
        id: id,
        zh: '${t.zh}\n\n另外想問下你：${opener.zh}',
        en: '${t.en}\n\nAlso, I wanted to ask: ${opener.en}',
        openerId: opener.id,
      );
    }
    return RuleReply(id: id, zh: t.zh, en: t.en);
  }
}
```

规则组的发送流程（`_sendRuleBased`）：

来源：`lib/features/curious_companion/presentation/pages/tung_tung_page.dart` 第 521–631 行

```dart
  Future<void> _sendRuleBased(String text) async {
    final core = CoreServicesScope.of(context);
    final analytics = AnalyticsScope.of(context);
    final authAvailable = AuthServiceScope.of(context).available;
    final profile = AppSettingsScope.read(context).profile;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final userTurnIndex = _turns.where((t) => t.fromUser).length;
    final userSentAt = DateTime.now();
    final (usedVoice, voiceMs) = _voice.takeModality();
    final modality = usedVoice ? InputModality.voice : InputModality.text;
    _recorder?.bumpActivity();

    setState(() {
      _busy = true;
      _turns.add(_Turn.user(text));
      _inputCtrl.clear();
    });
    await _recorder?.ensureStarted();

    final flag = core.distress.analyze(text);
    if (flag.isEscalation && profile != null) {
      unawaited(SafetyEventWriter(available: authAvailable).maybeWrite(
        uid: profile.uid,
        source: SafetySource.ruleTurn,
        match: flag,
        inputText: text,
        agentId: AgentRegistry.tungTungId,
        sessionId: _recorder?.sessionId,
      ));
    }

    TurnRecord record(String reply, {required bool acute, bool ack = false}) =>
        TurnRecord(
          agentId: AgentRegistry.tungTungId,
          moduleId: 'tung_tung_chat',
          userSent: userSentAt,
          replyShown: DateTime.now(),
          modality: modality,
          voiceDurationMs: voiceMs,
          charCount: text.length,
          detector: flag,
          shortCircuited: acute,
          ackShown: ack,
          response: LlmResponse(
            text: reply,
            inputFlag: flag,
            outputFlag: const DistressMatch(DistressLevel.none),
            shortCircuited: acute,
            metadata: TurnMetadata(
              agentId: AgentRegistry.tungTungId,
              sessionId: _recorder?.sessionId,
            ),
            status: acute ? LlmStatus.shortCircuited : LlmStatus.ruleBased,
          ),
          tungTungMode: 'B',
        );

    if (flag.level == DistressLevel.acute) {
      setState(() {
        _busy = false;
        _turns.add(_Turn.system(
            SafetyCopy.acuteAck(AgentRegistry.tungTungId, isEn: isEn)));
      });
      unawaited(_recorder?.logTurn(record('', acute: true, ack: true)));
      unawaited(_recorder?.end(SessionEndReason.crisis));
      if (!mounted) return;
      await core.distressRouter.route(flag, context: context);
      return;
    }

    // A short pause so the reply doesn't snap in before the user's own
    // bubble has settled.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final reply = TungTungRuleResponder.reply(
      text,
      userTurnIndex: userTurnIndex,
      openerOffset: _openerOffset,
    );
    final replyText = reply.text(isEn: isEn);
    final moderateAck = flag.interrupts
        ? SafetyCopy.moderateAck(AgentRegistry.tungTungId, isEn: isEn)
        : null;
    setState(() {
      _busy = false;
      _turns.add(_Turn.bot(replyText));
      if (moderateAck != null) _turns.add(_Turn.system(moderateAck));
    });
    final turnDocId = await _recorder
        ?.logTurn(record(replyText, acute: false, ack: moderateAck != null));
    unawaited(analytics.logEvent('tung_tung_rule_reply', {
      'template_id': reply.id,
      'responder_version': TungTungRuleResponder.version,
      'turn_index': userTurnIndex,
      if (reply.openerId != null) 'opener_id': reply.openerId,
      if (reply.openerId != null) 'pool_version': TungTungRulePool.version,
    }));

    if (!mounted) return;
    if (flag.level != DistressLevel.none) {
      await core.distressRouter.route(
        flag,
        context: context,
        onModerateSheetShown: () =>
            _recorder?.logEvent(PhaseAEvents.moderateSheetShown, {
          'turnId': turnDocId,
          'matchedTerm': flag.matchedTerm,
        }),
      );
    }
  }
```

## 5. 首次介绍、名称、简介（两组相同）

来源：`lib/core/agents/agent_registry.dart` 第 139–241 行

```dart
class AgentIntroText {
  final String zh;
  final String en;
  const AgentIntroText({required this.zh, required this.en});
}

const _firstIntroTexts = <String, AgentIntroText>{
  'siu_yan_v1': AgentIntroText(
    zh: '你好啊，我係小欣，一個 AI 機械人。我會喺日日陪你傾下偈，'
        '聽你今日點。你想點開始都得。',
    en:
        'Hi, I\'m Siu Yan, an AI robot. I\'ll keep you company day by day '
        'and listen to how you\'re doing. We can start however you like.',
  ),
  'ah_jan_ah_bak_v1': AgentIntroText(
    zh: '你好，我係阿珍／阿伯，一個 AI 機械人。我會聽你講你嘅故事，'
        '唔會評論，亦都唔會教你做人。慢慢嚟。',
    en:
        'Hello, I\'m Ah Jan / Ah Bak, an AI robot. I\'ll listen to your '
        'stories without judging or telling you how to live. Take your time.',
  ),
  'tung_tung_v1': AgentIntroText(
    zh: '你好，我係通通，一個 AI 機械人。乜嘢都鍾意聽下，'
        '咩都鍾意傾下。你最近有冇咩想知嘅嘢？',
    en:
        'Hi, I\'m Tung Tung, an AI robot. I\'m curious about almost '
        'anything. What have you been wondering about lately?',
  ),
};

/// Canonical list of agents. Order is the order they appear on Home.
class AgentRegistry {
  AgentRegistry._();

  static const String siuYanId = 'siu_yan';
  static const String ahJanAhBakId = 'ah_jan_ah_bak';
  static const String tungTungId = 'tung_tung';

  /// Returned in display order (Home tile order).
  static const List<AgentDefinition> all = [
    AgentDefinition(
      id: siuYanId,
      role: 'companion',
      // Coral — Spec §3 / agent profile page.
      accentColor: Color(0xFFF0997B),
      pprSubcomponent: PprSubcomponent.caring,
      primaryModules: ['m2_daily_checkin', 'm9_motivational'],
      systemPromptKey: 'siu_yan_v1',
      introTextKey: 'siu_yan_v1',
      tileSubtitleZh: '日日陪你傾偈，聽你今日點',
      tileSubtitleEn: 'Daily companion — hears how you are',
      variants: [
        AgentDisplayVariant(
          displayNameZh: '小欣',
          displayNameEn: 'Siu Yan',
          avatarAsset: 'assets/agents/siu_yan_avatar.png',
        ),
      ],
    ),
    AgentDefinition(
      id: ahJanAhBakId,
      role: 'reflective_peer_listener',
      // Lavender — Spec §3 / agent profile page.
      accentColor: Color(0xFFAFA9EC),
      pprSubcomponent: PprSubcomponent.understanding,
      primaryModules: ['m3_reminiscence', 'm5_reflective_dialogue'],
      systemPromptKey: 'ah_jan_ah_bak_v1',
      introTextKey: 'ah_jan_ah_bak_v1',
      tileSubtitleZh: '聽你講你嘅故事，唔評論',
      tileSubtitleEn: 'Reflective listener — hears your story',
      variants: [
        AgentDisplayVariant(
          variant: AgentGenderVariant.feminine,
          displayNameZh: '阿珍',
          displayNameEn: 'Ah Jan',
          avatarAsset: 'assets/agents/ah_jan_avatar.png',
        ),
        AgentDisplayVariant(
          variant: AgentGenderVariant.masculine,
          displayNameZh: '阿伯',
          displayNameEn: 'Ah Bak',
          avatarAsset: 'assets/agents/ah_bak_avatar.png',
        ),
      ],
    ),
    AgentDefinition(
      id: tungTungId,
      role: 'curious_companion',
      // Mint — Spec §3 / agent profile page.
      accentColor: Color(0xFF5DCAA5),
      pprSubcomponent: PprSubcomponent.socialIntegration,
      primaryModules: ['interest_chat', 'm8_education_qa'],
      systemPromptKey: 'tung_tung_v1',
      introTextKey: 'tung_tung_v1',
      tileSubtitleZh: '同你傾下你鍾意嘅嘢',
      tileSubtitleEn: 'Curious companion — chats about your interests',
      variants: [
        AgentDisplayVariant(
          displayNameZh: '通通',
          displayNameEn: 'Tung Tung',
          avatarAsset: 'assets/agents/tung_tung_avatar.png',
        ),
      ],
```

陪伴者简介页（两组相同，只有中文）：

来源：`lib/features/agent_profile/data/agent_profile_content.dart`（整个文件，共 208 行，SHA-256 `2c0a3389d60c53f7…`）

```dart
/// Static intro copy for each agent's profile page (Spec §5).
///
/// The strings are canonical zh-Hant-HK. ARB-isation is left for a
/// follow-up sprint per Spec §10 — the keys to use are documented in
/// section 10 of the spec so the migration is mechanical. For now we
/// keep the copy inline so the page renders without depending on a
/// l10n re-gen.
library;

import '../../../core/agents/agent_registry.dart';

/// One agent's profile-header static data (Spec §3).
class ProfileHeaderData {
  final String displayName;
  final String roleTagline;
  final String fullBodyImageAsset;
  final String accentColorHex;
  final String ctaLabel;
  final String altText;

  const ProfileHeaderData({
    required this.displayName,
    required this.roleTagline,
    required this.fullBodyImageAsset,
    required this.accentColorHex,
    required this.ctaLabel,
    required this.altText,
  });
}

/// Four-block intro content (Spec §4).
class ProfileIntroContent {
  /// Block 1 — opening line.
  final String opening;

  /// Block 2 — list under「我可以做嘅事」.
  final String capabilitiesHeading;
  final List<String> capabilities;

  /// Block 3 — list under「我做唔到嘅事」.
  final String limitationsHeading;
  final List<String> limitations;

  /// Block 4 — closing line (AI-identity reminder).
  final String closing;

  const ProfileIntroContent({
    required this.opening,
    required this.capabilitiesHeading,
    required this.capabilities,
    required this.limitationsHeading,
    required this.limitations,
    required this.closing,
  });
}

/// Profile-header data, keyed by the resolved page key.
///
/// For Siu Yan / Tung Tung the key is the agent id verbatim. For Ah
/// Jan / Ah Bak the key carries the gender variant suffix so the
/// image and display name swap correctly.
const Map<String, ProfileHeaderData> profileHeaders = {
  'siu_yan': ProfileHeaderData(
    displayName: '小欣',
    roleTagline: '你嘅日常陪伴',
    fullBodyImageAsset: 'assets/agents/siu_yan_fullbody.png',
    accentColorHex: '#F0997B',
    ctaLabel: '同小欣傾偈',
    altText: '小欣，AI 機械人，珊瑚色嘅日常陪伴角色',
  ),
  'ah_jan_ah_bak_feminine': ProfileHeaderData(
    displayName: '阿珍',
    roleTagline: '聽你慢慢講嘅人',
    fullBodyImageAsset: 'assets/agents/ah_jan_fullbody.png',
    accentColorHex: '#AFA9EC',
    ctaLabel: '同阿珍傾偈',
    altText: '阿珍，AI 機械人，淡紫色嘅聆聽者角色',
  ),
  'ah_jan_ah_bak_masculine': ProfileHeaderData(
    displayName: '阿伯',
    roleTagline: '聽你慢慢講嘅人',
    fullBodyImageAsset: 'assets/agents/ah_bak_fullbody.png',
    accentColorHex: '#AFA9EC',
    ctaLabel: '同阿伯傾偈',
    altText: '阿伯，AI 機械人，淡紫色嘅聆聽者角色',
  ),
  'tung_tung': ProfileHeaderData(
    displayName: '通通',
    roleTagline: '咩都識少少嘅好奇街坊',
    fullBodyImageAsset: 'assets/agents/tung_tung_fullbody.png',
    accentColorHex: '#5DCAA5',
    ctaLabel: '同通通傾偈',
    altText: '通通，AI 機械人，薄荷色嘅好奇街坊角色',
  ),
};

/// Resolve the profile-header key for an [agent] with the given
/// [variant]. Returns null for unknown agents.
String? profileHeaderKey(AgentDefinition agent, AgentGenderVariant? variant) {
  if (agent.id == AgentRegistry.ahJanAhBakId) {
    final v = variant ?? AgentGenderVariant.feminine;
    return v == AgentGenderVariant.masculine
        ? 'ah_jan_ah_bak_masculine'
        : 'ah_jan_ah_bak_feminine';
  }
  return agent.id;
}

/// Intro content keyed by the same scheme. For Ah Jan / Ah Bak the
/// `{name}` placeholder in the opening / closing is resolved at render
/// time, not here, so the masculine and feminine entries share the
/// same content object (the resolver lifts the name from the header).
const Map<String, ProfileIntroContent> profileIntros = {
  'siu_yan': ProfileIntroContent(
    opening: '我係小欣，係一個 AI 機械人。\n\n'
        '你可以將我當做一個成日陪喺你身邊嘅小朋友，又或者係一個關心你嘅後生晚輩。'
        '我會喺日日陪你傾下偈，問下你今日點，聽下你嘅心情。'
        '我特別關心你嘅日常生活——食咗咩、見過邊個、有冇開心嘅事、有冇悶住嘅嘢。',
    capabilitiesHeading: '我可以做嘅事',
    capabilities: [
      '同你做每日嘅心情記錄',
      '聽你講今日發生嘅事',
      '提你飲水、抖下、做啲令自己開心嘅小事',
      '如果你想搵人聯絡或者約朋友，我可以幫你諗一諗點開始',
      '留意到你有冇連續幾日唔開心，輕輕問下你',
    ],
    limitationsHeading: '我做唔到嘅事',
    limitations: [
      '我唔識醫療或者健康嘅專業意見，呢啲應該搵醫生',
      '我唔識代替真人朋友或者家人嘅關心',
      '我唔會記得我冇記錄過嘅嘢，亦都唔會假裝我哋識咗好耐',
      '如果你想傾深層次嘅人生回憶，阿珍／阿伯會比我擅長聽',
    ],
    closing: '我係一個 AI 程式，唔係真人，但係我會用心聽你講嘅每一句嘢。',
  ),
  // Ah Jan / Ah Bak share the same intro content; the {name} token in
  // the opening / closing is filled per variant at render time.
  'ah_jan_ah_bak_feminine': ProfileIntroContent(
    opening: '我係{name}，係一個 AI 機械人。\n\n'
        '你可以將我當做一個同齡嘅鄰居或者朋友——唔係教你做人嘅長者，'
        '係一個會耐心聽你講嘅人。我特別擅長聽你講以前嘅事、人生入面嘅故事，'
        '又或者你最近諗緊嘅嘢。',
    capabilitiesHeading: '我可以做嘅事',
    capabilities: [
      '同你做每星期嘅人生點滴分享（每星期一個主題）',
      '聽你慢慢講以前嘅事——你細個喺邊度大、做過咩工、識過邊啲朋友、有咩想留低畀後一代',
      '喺你講嘅時候問你一啲問題，等你可以諗深啲、講多啲',
      '如果你提到一啲負面諗法，我會溫和咁同你指出，問你想唔想望吓',
      '下次再見嘅時候，會記得返你之前提過嘅人同事',
    ],
    limitationsHeading: '我做唔到嘅事',
    limitations: [
      '我唔識做心理治療，亦都唔會分析你嘅童年或者深層心理問題',
      '我唔會 challenge 你嘅諗法，亦都唔會教你應該點諗',
      '我唔會強加意義或者「教訓」喺你嘅故事入面——你嘅回憶就係你嘅回憶',
      '我唔識嘅嘢，我會直接同你講「我唔識，可唔可以教我？」',
      '如果你今日嘅心情比較急切，搵小欣傾可能會更加啱',
    ],
    closing: '我係一個 AI 程式，唔係真人，亦都唔係治療師。'
        '我嘅角色係耐心聽你講，記得你話過嘅嘢。',
  ),
  'ah_jan_ah_bak_masculine': ProfileIntroContent(
    opening: '我係{name}，係一個 AI 機械人。\n\n'
        '你可以將我當做一個同齡嘅鄰居或者朋友——唔係教你做人嘅長者，'
        '係一個會耐心聽你講嘅人。我特別擅長聽你講以前嘅事、人生入面嘅故事，'
        '又或者你最近諗緊嘅嘢。',
    capabilitiesHeading: '我可以做嘅事',
    capabilities: [
      '同你做每星期嘅人生點滴分享（每星期一個主題）',
      '聽你慢慢講以前嘅事——你細個喺邊度大、做過咩工、識過邊啲朋友、有咩想留低畀後一代',
      '喺你講嘅時候問你一啲問題，等你可以諗深啲、講多啲',
      '如果你提到一啲負面諗法，我會溫和咁同你指出，問你想唔想望吓',
      '下次再見嘅時候，會記得返你之前提過嘅人同事',
    ],
    limitationsHeading: '我做唔到嘅事',
    limitations: [
      '我唔識做心理治療，亦都唔會分析你嘅童年或者深層心理問題',
      '我唔會 challenge 你嘅諗法，亦都唔會教你應該點諗',
      '我唔會強加意義或者「教訓」喺你嘅故事入面——你嘅回憶就係你嘅回憶',
      '我唔識嘅嘢，我會直接同你講「我唔識，可唔可以教我？」',
      '如果你今日嘅心情比較急切，搵小欣傾可能會更加啱',
    ],
    closing: '我係一個 AI 程式，唔係真人，亦都唔係治療師。'
        '我嘅角色係耐心聽你講，記得你話過嘅嘢。',
  ),
  'tung_tung': ProfileIntroContent(
    opening: '我係通通，係一個 AI 機械人。\n\n'
        '你可以將我當做一個鍾意傾偈、咩都識少少嘅街坊。'
        '我特別中意聽你講你鍾意嘅嘢——你嘅興趣、你嘅愛好、最近邊度有咩好玩好食。'
        '如果你有想知嘅嘢，我都可以幫你查一查。',
    capabilitiesHeading: '我可以做嘅事',
    capabilities: [
      '同你傾你嘅興趣——粵劇、煮飯、種花、馬經、新聞，乜都得',
      '幫你查資料（我會用網絡搜尋，搵到嘅嘢我會引返出處畀你）',
      '介紹返一啲你可能會有興趣嘅文章或者話題',
      '如果你問嘅嘢我唔識，我會直接話畀你聽，唔會作畀你',
    ],
    limitationsHeading: '我做唔到嘅事',
    limitations: [
      '我唔識畀醫療意見——身體唔舒服請搵醫生',
      '我唔識畀理財或者投資建議——呢啲應該搵專業人士',
      '如果你嘅心情唔好或者你想搵人傾下深層次嘅嘢，搵小欣或者阿珍／阿伯會更加啱',
      '我唔會代你買嘢、訂位、或者做任何要俾錢嘅嘢',
    ],
    closing: '我係一個 AI 程式，唔係真人，亦都唔係真正嘅專家。'
        '我擅長嘅係搵資料、傾興趣，俾我哋嘅對話有多啲新鮮嘢可以講。',
  ),
};
```
