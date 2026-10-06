# 两组共用：Thought Exercise（想法练习）

**结论**：想法练习页两组相同（从「自己」页和首页快捷入口进入，没有分组限制）：5 个栏目 + 前后两次 1–10 强度评分。
页面没有示例文字。Hybrid 组另有一张「邀请卡」：小欣对话中检测到负面想法时邀请老人做练习（关键词规则，见第 2 节），规则组没有。

**app 实际显示哪个版本**：`lib/app/app_settings.dart` 第 45 行 `englishEnabled = false`，第 50 行把 locale 强制为 `zh`
（`lib/main.dart` 第 115 行也传 `Locale('zh')`）。所以 `isEn ? 英文 : 中文` 和 `…Zh / …En` 成对的文字里，**只有中文版会显示**。
英文版照样导出，老人看不到。`app_zh_Hant_HK.arb` 虽然编译进去了，但 app 从不选 `zh_Hant_HK`，实际用的是 `app_zh.arb`；
本文件的内容都写在 Dart / JS 源码里，不在 ARB 文件里。

## 条数

| 项目 | 条数 | 怎么数的 |
|---|---|---|
| 练习栏目 | 5 | thought_exercise_page.dart 第 267–323 行「一」至「五」 |
| 强度评分 | 2 | 开始时 1 次（第 283–296 行）、完成时 1 次（第 381–392 行），各 10 点 |

## 1. 练习页

心情 emoji：

来源：`lib/features/thought_exercise/presentation/thought_exercise_page.dart` 第 40–52 行

```dart
  });

  @override
  State<ThoughtExercisePage> createState() => _ThoughtExercisePageState();
}

class _ThoughtExercisePageState extends State<ThoughtExercisePage> {
  // 5 emoji choices for Field 2.  Kept few + culturally neutral.
  static const _emojis = ['😟', '😔', '😐', '🙂', '😊'];

  // Research Review v2 Item 5: first-visit hint.  In-memory flag resets
  // each app session; persistent suppression requires Firestore/prefs integration.
  static bool _firstVisitHintShown = false;
```

来源：`lib/features/thought_exercise/presentation/thought_exercise_page.dart` 第 200–450 行

```dart
    // M-7 — tool session: enter = start, leave = end.
    return ToolSessionScope(
      toolId: 'thought_exercise',
      child: Scaffold(
      appBar: AppBar(
        title: Text(_showingExit
            ? (isEn ? 'Before / after' : '前後對照')
            : (isEn ? 'Look at a thought' : '望一望心入面')),
      ),
      body: SafeArea(
        child: _showingExit
            ? _buildExitView(isEn)
            : _buildEntryView(isEn),
      ),
      ),
    );
  }

  Widget _buildEntryView(bool isEn) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Research Review v2 Item 5: first-visit hint banner.
            if (_showFirstVisitHint) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEn
                            ? 'Here you can look back at your recent moods and thoughts. Take it slow — no rush.'
                            : '呢度可以畀你睇返自己最近嘅心情同諗法。慢慢嚟，唔趕。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          height: 1.4,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: theme.colorScheme.onPrimaryContainer,
                      onPressed: () => setState(() => _showFirstVisitHint = false),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ],
            // Intro line (pixel-identical across arms, static text)
            Text(
              isEn
                  ? 'A small practice to look at a thought you have. No one '
                      'will comment. There are no right answers. Take your time.'
                  : '呢個小練習係幫你慢慢望一望自己嘅諗法。冇人會評論，亦都冇答案。慢慢嚟。',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 22),
            _Label(text: isEn ? '1. The situation' : '一、嗰陣係咩情況？'),
            TextField(
              controller: _situationCtrl,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 17, height: 1.4),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 18),
            _Label(text: isEn ? '2. How did you feel?' : '二、我嗰陣覺得點？'),
            _EmojiRow(
              value: _emoji,
              choices: _emojis,
              onChanged: (e) => setState(() => _emoji = e),
            ),
            const SizedBox(height: 8),
            Text(
              isEn
                  ? 'How strong is the feeling? Tap a number (1–10)'
                  : '感覺有幾強烈？撳一個數字（1–10）',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            LikertScale(
              points: 10,
              value: _intensityBefore,
              onChanged: (v) => setState(() => _intensityBefore = v),
              lowLabel: isEn ? 'Very mild' : '好輕微',
              highLabel: isEn ? 'Very strong' : '好強烈',
            ),
            const SizedBox(height: 8),
            _Label(text: isEn ? '3. The thought' : '三、嗰個諗法係：'),
            TextField(
              controller: _thoughtCtrl,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 17, height: 1.4),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 18),
            _Label(
              text: isEn
                  ? '4. One reason this thought might be true'
                  : '四、一個令呢個諗法可能成立嘅理由',
            ),
            TextField(
              controller: _reasonCtrl,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontSize: 17, height: 1.4),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 18),
            _Label(
              text: isEn
                  ? '5. One other way to look at it (optional)'
                  : '五、一個睇呢件事嘅另一個角度（可以留空）',
            ),
            TextField(
              controller: _alternativeCtrl,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontSize: 17, height: 1.4),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: !_isComplete || _saving ? null : _saveAndAdvanceToExit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(isEn ? 'Continue' : '繼續',
                    style: const TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExitView(bool isEn) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'Re-rate how you feel right now. No judgement, no escalation '
                    "— it's fine for the number to be higher, lower, or the same."
                : '依家再 rate 一下你嘅感覺。冇判斷、冇升降警示 —— 個數字高、低、一樣 都 OK。',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),
          // Side-by-side before/after (per spec)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BeforeAfterTile(
                label: isEn ? 'Before' : '之前',
                emoji: _emoji ?? '',
                value: _intensityBefore,
              ),
              const Icon(Icons.arrow_forward, size: 28),
              _BeforeAfterTile(
                label: isEn ? 'Now' : '依家',
                emoji: _emoji ?? '', // emoji not re-selected, only intensity
                value: _intensityAfter,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            isEn
                ? 'How strong is it now? Tap a number (1–10)'
                : '依家有幾強烈？撳一個數字（1–10）',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          LikertScale(
            points: 10,
            value: _intensityAfter,
            onChanged: (v) => setState(() => _intensityAfter = v),
            lowLabel: isEn ? 'Very mild' : '好輕微',
            highLabel: isEn ? 'Very strong' : '好強烈',
          ),
          const Spacer(),
          FilledButton(
            onPressed: _saving || _intensityAfter == null
                ? null
                : _saveExitAndClose,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(isEn ? 'Done' : '完成',
                  style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}


class _EmojiRow extends StatelessWidget {
  final String? value;
  final List<String> choices;
  final ValueChanged<String> onChanged;
  const _EmojiRow({
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  /// Text label per face so elders don't have to decode the emoji alone.
  static const _labelsZh = {
    '😟': '擔心',
    '😔': '唔開心',
    '😐': '一般',
    '🙂': '幾好',
    '😊': '開心',
  };
  static const _labelsEn = {
    '😟': 'Worried',
    '😔': 'Sad',
    '😐': 'So-so',
    '🙂': 'Okay',
    '😊': 'Happy',
  };

  @override
```

## 2. 邀请卡和负面想法检测（只 Hybrid 组，小欣签到）

来源：`lib/features/thought_exercise/presentation/naming_thought_card.dart`（整个文件，共 104 行，SHA-256 `d57fa69a2442f53a…`）

```dart
/// Naming-thought invitation card (Phase A Proposal §2.6, §M2 spec May 2026).
///
/// **Only Siu Yan is authorised to surface this card** (during M2 daily
/// check-in, Arm A only).  Ah Jan/Ah Bak MUST briefly acknowledge and
/// return to listening — the unconditional listening quality on which
/// PPR-Understanding depends would be compromised otherwise.
///
/// Wording matches the Phase A locked text:
///   "你頭先講咗一句令我有少少 stuck — '{thought}'.  要唔要做個小練習慢慢望一望
///   呢個諗法？要唔要都得。"
///
/// Phase B Proposal §4.7 §point 3 declares this the third sanctioned UI
/// asymmetry between arms: Arm B users access the Thought Exercise only
/// via the 做啲嘢 tab tile (no auto-fill); only the Arm A Siu Yan offer
/// pathway exists.
library;

import 'package:flutter/material.dart';

class NamingThoughtCard extends StatelessWidget {
  /// The cognition the detector matched on — used in the invitation copy
  /// and auto-filled into Field 3 of the Thought Exercise.
  final String thought;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const NamingThoughtCard({
    super.key,
    required this.thought,
    required this.onAccept,
    required this.onDecline,
  });

  /// L-3 — the exact invitation sentence shown to the participant, with the
  /// thought summary filled in.  Logged verbatim on `turns.te.offerText`
  /// because the Thought Exercise offer is audited at 100 %.
  static String invitationText(String thought, {required bool isEn}) => isEn
      ? 'You just said something that I noticed got stuck '
          'with me — "${_trim(thought)}". Would you like '
          'to do a small practice to look at that thought? '
          'Either way is fine.'
      : '你頭先講咗一句令我有少少 stuck — 「${_trim(thought)}」。'
          '要唔要做個小練習慢慢望一望呢個諗法？要唔要都得。';

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Phase A spec-exact invitation copy.
                invitationText(thought, isEn: isEn),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onAccept,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(isEn ? 'Try it' : '好，試下'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDecline,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(isEn ? 'Not now' : '唔使住'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Trim long quoted thoughts to keep the card readable.  The full
  /// thought is auto-filled into Field 3 of the exercise anyway.
  static String _trim(String t) {
    final clean = t.trim();
    if (clean.length <= 30) return clean;
    return '${clean.substring(0, 28)}…';
  }
}
```

来源：`lib/features/reflective_dialogue/data/negative_cognition_detector.dart`（整个文件，共 83 行，SHA-256 `cea032001aeb4dd3…`）

```dart
/// Conservative client-side keyword filter for negative-social-cognition
/// detection (Walkthrough Case 5).
///
/// The Ah Jan / Ah Bak reflective dialogue surface uses this to decide
/// whether to surface the "name the thought" card after a user turn.
/// The filter is intentionally narrow — we'd rather miss most actual
/// negative cognitions than surface false positives, because the
/// "name a thought" intervention is conspicuous and over-surfacing it
/// would feel pathologising.
///
/// Triggers are absolutist or rejection-flavoured phrasings drawn from
/// the Phase 0 transcript pilot. They are NOT distress signals — those
/// are handled by [DistressDetector]. A turn may match here without
/// raising any distress flag.
library;

class NegativeCognitionMatch {
  /// The exact substring that matched.
  final String snippet;

  /// Original user turn for surfacing back to the user.
  final String fullTurn;

  const NegativeCognitionMatch({
    required this.snippet,
    required this.fullTurn,
  });
}

class NegativeCognitionDetector {
  const NegativeCognitionDetector();

  /// Triggers are short anchor phrases. Each turn is scanned once;
  /// the first match wins.
  static const List<String> _zhTriggers = [
    '阻住佢',
    '阻住個',
    '都係阻住',
    '冇人理',
    '冇人會理',
    '冇人關心',
    '冇人會關心',
    '都唔記得我',
    '都唔會理我',
    '我冇用',
    '我都係多餘',
    '都係我嘅錯',
    '都係我唔好',
    '永遠都',
    '從來都唔',
    '一定唔得',
  ];

  static const List<String> _enTriggers = [
    'bother them',
    'no one cares',
    'nobody cares',
    "no one's going to",
    'i\'m useless',
    'i am useless',
    'always my fault',
    'never going to',
    'pointless',
    'a burden',
  ];

  /// Returns the first match in [turn], or null if none.
  NegativeCognitionMatch? scan(String turn) {
    if (turn.trim().isEmpty) return null;
    for (final t in _zhTriggers) {
      if (turn.contains(t)) {
        return NegativeCognitionMatch(snippet: t, fullTurn: turn);
      }
    }
    final lower = turn.toLowerCase();
    for (final t in _enTriggers) {
      if (lower.contains(t)) {
        return NegativeCognitionMatch(snippet: t, fullTurn: turn);
      }
    }
    return null;
  }
}
```
