# 两组共用：App 内问卷题目和选项

**结论**：

| 问卷 | 题数 | 选项 | 现在会不会显示 |
|---|---|---|---|
| Brief PR（每次会话后） | 4（`briefPRItemCount` 可设成 3） | 7 点，见下 | 会，两组 |
| Weekly PR（每周） | 12，只有中文 | 7 点「唔同意」—「同意」 | 会，两组 |
| 每周孤独探针 | 1 | 0–10 滑杆 | **不会**：页面没有入口，功能开关默认关 |
| ADA（陪伴者区分评估） | 第 2 周 15 项；第 4 周 20 项 | 见下 | 会 |
| PGIC（每周感受变化） | 1 | 7 个选项 | 会 |
| DJG | **6 条版**（情绪 3 + 社交 3），措辞是工作草稿 | 係 / 多少啦 / 唔係 | 会，第 2 周 |
| UCLA | **App 内没有 UCLA 题目**；研究员在登录页输入基线总分（20–80） | — | — |
| 每日心情 | 1 | 5 个心情脸 | 会，两组 |

DJG 是 6 条版的依据：`djg_es_response.dart` 第 1–10 行注释写明 6-item short form（De Jong Gierveld & Van Tilburg 2006），
版本号 `djg_es_6_draft_v1-2026-09`，题目 e1–e3、s1–s3 共 6 条，页面说明写「六句短句」；全仓库没有 11 条版。
注意第 8–10 行注释：措辞是粤语工作草稿，要换成问卷 v1.3 的正式文字。
另有旧版 PPR 量表（`ppr_scale.dart`），只能从测试工具进入，参与者看不到，放在最后作参考。

**app 实际显示哪个版本**：`lib/app/app_settings.dart` 第 45 行 `englishEnabled = false`，第 50 行把 locale 强制为 `zh`
（`lib/main.dart` 第 115 行也传 `Locale('zh')`）。所以 `isEn ? 英文 : 中文` 和 `…Zh / …En` 成对的文字里，**只有中文版会显示**。
英文版照样导出，老人看不到。`app_zh_Hant_HK.arb` 虽然编译进去了，但 app 从不选 `zh_Hant_HK`，实际用的是 `app_zh.arb`；
本文件的内容都写在 Dart / JS 源码里，不在 ARB 文件里。

## 条数

| 项目 | 条数 | 怎么数的 |
|---|---|---|
| Brief PR | 4 | brief_pr_page.dart 第 232、244、256、271 行 4 张题卡；第 4 题只在 itemCount ≥ 4 时显示 |
| Weekly PR | 12 | `WeeklyPrItems.items` 中 `(id:` 个数 |
| 每周孤独探针 | 1 | loneliness_probe_page.dart 第 71–74 行 |
| ADA 特质 | 4 | `AgentDiffTraits.all`；× 3 个陪伴者 = 12 项评分 |
| ADA 情境（只第 4 周） | 5 | `AgentDiffScenarios.all` |
| ADA 使用频率题 | 3 | 每个陪伴者 1 题，4 个选项（agent_diff_page.dart 第 383 行） |
| ADA 开放题 | 1 | agent_diff_page.dart Part D |
| PGIC | 1 | 1 题，7 个选项（pgic_page.dart 第 29–37 行） |
| DJG | 6 | `DjgEsItems.items` 中 `DjgEsItem(` 个数；3 个选项 |
| UCLA（App 内题目） | 0 | intake_flow_page.dart 没有 UCLA 题；只有研究员输入总分 |
| 每日心情 | 1 | daily_mood_prompt.dart 1 题，5 个选项 |

## 1. 共用评分组件

来源：`lib/core/survey/likert_scale.dart` 第 1–40 行

```dart
import 'package:flutter/material.dart';

/// Shared agree/disagree Likert selector used across the self-report
/// instruments (Weekly PR = 7-point, PPR brief + Agent Diff traits =
/// 5-point) so they read as one visual system instead of each page
/// rolling its own boxes / dots.
///
/// One horizontal row of [points] numbered circles with optional anchor
/// labels underneath the two ends. Nothing is pre-selected when [value] is
/// null. For scales whose every point has its own distinct meaning (e.g.
/// PGIC "much better … much worse"), use a labelled vertical list instead —
/// this widget only labels the two endpoints.
class LikertScale extends StatelessWidget {
  /// Number of points (typically 5 or 7).
  final int points;

  /// Currently selected value (1..points), or null when unanswered.
  final int? value;

  final ValueChanged<int> onChanged;

  /// Anchor labels under the low (1) and high ([points]) ends, plus an
  /// optional midpoint anchor (used by Brief PR's 1–7 items: 完全唔係咁 ·
  /// 一半半 · 完全係咁).
  final String? lowLabel;
  final String? midLabel;
  final String? highLabel;

  const LikertScale({
    super.key,
    required this.points,
    required this.value,
    required this.onChanged,
    this.lowLabel,
    this.midLabel,
    this.highLabel,
  });

  @override
  Widget build(BuildContext context) {
```

## 2. Brief PR

来源：`lib/features/brief_pr/presentation/pages/brief_pr_page.dart` 第 195–315 行

```dart
    final name = widget.agentDisplayName;
    // Endpoint + midpoint anchors. Kept generic so they fit the existing
    // Sprint 1 stems verbatim; the coupled wording proposed in the C1 ticket
    // (完全唔〔明白/認同/關心〕 · 一半半 · 非常〔…〕) is pending PI / cognitive
    // interview sign-off (protocol §6.4) before it can replace these.
    final posLeft = isEn ? 'Not at all' : '完全唔係咁';
    final posMid = isEn ? 'Halfway' : '一半半';
    final posRight = isEn ? 'Very much' : '完全係咁';
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'A quick check-in' : '一啲簡短回饋'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text(
              isEn ? 'Your conversation with $name just now:' : '頭先同 $name 嘅對話：',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isEn
                  ? 'Tap the number (1–7) that best matches how you felt.'
                  : '撳一個數字（1–7），最似你嘅感受。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            SurveyItemCard(
              title: isEn ? '$name understood me.' : '$name 明白我。',
              child: LikertScale(
                points: 7,
                value: _understanding,
                onChanged: (v) => setState(() => _understanding = v),
                lowLabel: posLeft,
                midLabel: posMid,
                highLabel: posRight,
              ),
            ),
            const SizedBox(height: 14),
            SurveyItemCard(
              title: isEn ? '$name respected me.' : '$name 尊重我。',
              child: LikertScale(
                points: 7,
                value: _validation,
                onChanged: (v) => setState(() => _validation = v),
                lowLabel: posLeft,
                midLabel: posMid,
                highLabel: posRight,
              ),
            ),
            const SizedBox(height: 14),
            SurveyItemCard(
              title: isEn ? '$name cared about me.' : '$name 關心我。',
              child: LikertScale(
                points: 7,
                value: _caring,
                onChanged: (v) => setState(() => _caring = v),
                lowLabel: posLeft,
                midLabel: posMid,
                highLabel: posRight,
              ),
            ),
            if (_hasInsensitivity) ...[
              const SizedBox(height: 20),
              Divider(color: theme.colorScheme.outlineVariant, thickness: 1),
              const SizedBox(height: 20),
              SurveyItemCard(
                title: isEn
                    ? '$name\'s response seemed to miss the point or feel indifferent.'
                    : '$name 嘅回應好似搞錯重點，或者唔在乎。',
                child: LikertScale(
                  points: 7,
                  value: _insensitivity,
                  onChanged: (v) => setState(() => _insensitivity = v),
                  // S4 is negatively worded; anchors run none → very much.
                  lowLabel: isEn ? 'Not at all' : '完全唔係咁',
                  midLabel: isEn ? 'A little' : '有少少',
                  highLabel: isEn ? 'Very much' : '好係咁',
                ),
              ),
            ],
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEn ? 'Done' : '完成'),
              ),
            ),
            if (_skipVisible && !widget.isAnchorPrompt) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _saving ? null : _skip,
                  child: Text(isEn ? 'Skip' : '跳過', style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
```

## 3. Weekly PR

来源：`lib/features/weekly_pr/data/weekly_pr_response.dart`（整个文件，共 103 行，SHA-256 `3c7703ded366538a…`）

```dart
/// Weekly PR (Sprint 1 §4) — 12-item 7-point per-agent Likert.
///
/// Stored at `users/{uid}/weekly_pr/{auto-id}`.

import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklyPrResponse {
  /// ISO week format e.g. '2026-W21'.
  final String weekIso;
  final String agentId;
  final String agentDisplayName;
  final int sessionCountThisWeek;

  /// Item id (u1/u2/u3/v1/v2/v3/c1/c2/c3/i1/i2/i3) → 1–7. Empty when
  /// status = 'skipped' or 'no_referent'.
  final Map<String, int> items;

  /// 'completed' | 'skipped' | 'no_referent' | 'missed'
  final String status;
  final DateTime promptedAt;
  final DateTime respondedAt;
  final String arm;

  /// M-2 — referent chosen automatically from the week's agent sessions
  /// (`max_sessions` / `tie_turns` / `tie_recency` / `none`).
  final String? referentRule;

  const WeeklyPrResponse({
    required this.weekIso,
    required this.agentId,
    required this.agentDisplayName,
    required this.sessionCountThisWeek,
    required this.items,
    required this.status,
    required this.promptedAt,
    required this.respondedAt,
    required this.arm,
    this.referentRule,
  });

  Map<String, dynamic> toFirestore() => {
        'weekIso': weekIso,
        'agentId': agentId,
        'agentDisplayName': agentDisplayName,
        'sessionCountThisWeek': sessionCountThisWeek,
        'items': items,
        'status': status,
        'promptedAt': Timestamp.fromDate(promptedAt),
        'respondedAt': FieldValue.serverTimestamp(),
        'arm': arm,
        'referentAgentId': agentId == '_none' ? null : agentId,
        'referentRule': referentRule,
      };

  /// ISO week label for [date] (defaults to `DateTime.now()`), e.g.
  /// `'2026-W21'`. Uses the ISO 8601 week numbering.
  static String currentWeekIso([DateTime? date]) {
    final d = date ?? DateTime.now();
    final dayOfYear = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
    final wday = d.weekday;
    final weekNum = ((dayOfYear - wday + 10) / 7).floor();
    int year = d.year;
    int adjusted = weekNum;
    if (weekNum < 1) {
      year = d.year - 1;
      adjusted = isoWeeksInYear(year);
    } else if (weekNum > isoWeeksInYear(year)) {
      year = d.year + 1;
      adjusted = 1;
    }
    final w = adjusted.toString().padLeft(2, '0');
    return '$year-W$w';
  }

  static int isoWeeksInYear(int year) {
    int p(int y) => (y + (y ~/ 4) - (y ~/ 100) + (y ~/ 400)) % 7;
    return (p(year) == 4 || p(year - 1) == 3) ? 53 : 52;
  }
}

/// 12 Weekly PR items per Sprint 1 §4.1.
class WeeklyPrItems {
  static const items = <({String id, String text})>[
    (id: 'u1', text: '頭先 $kAgent 都明白我嘅感受。'),
    (id: 'u2', text: '頭先 $kAgent 都明白我嘅想法。'),
    (id: 'u3', text: '頭先 $kAgent 真係聽到我講嘅嘢。'),
    (id: 'v1', text: '頭先 $kAgent 尊重我嘅感受。'),
    (id: 'v2', text: '頭先 $kAgent 認可我講嘅嘢。'),
    (id: 'v3', text: '頭先 $kAgent 冇判斷我。'),
    (id: 'c1', text: '頭先 $kAgent 真心關心我。'),
    (id: 'c2', text: '頭先 $kAgent 為我著想。'),
    (id: 'c3', text: '頭先 $kAgent 嘅回應令我覺得舒服。'),
    (id: 'i1', text: '頭先 $kAgent 嘅回應好似搞錯重點。'),
    (id: 'i2', text: '頭先 $kAgent 好似唔在乎我講嘅嘢。'),
    (id: 'i3', text: '頭先 $kAgent 嘅回應令我覺得唔舒服。'),
  ];

  static const kAgent = '〈AGENT〉';

  /// Replace the agent placeholder with the actual display name.
  static String render(String template, String agentName) =>
      template.replaceAll(kAgent, agentName);
}
```

题目随机排序、加粗关键词：

来源：`lib/features/weekly_pr/presentation/pages/weekly_pr_page.dart` 第 45–90 行

```dart
  int _pageIndex = 0;
  late List<({String id, String text})> _items;
  final Map<String, int> _ratings = {};
  late DateTime _promptedAt;
  bool _saving = false;

  /// Key phrase(s) bolded in each item so elderly readers catch the point
  /// quickly. The agent name is bolded too (added at render time).
  static const Map<String, List<String>> _keywords = {
    'u1': ['明白', '感受'],
    'u2': ['明白', '想法'],
    'u3': ['聽到'],
    'v1': ['尊重'],
    'v2': ['認可'],
    'v3': ['判斷'],
    'c1': ['關心'],
    'c2': ['著想'],
    'c3': ['舒服'],
    'i1': ['搞錯重點'],
    'i2': ['唔在乎'],
    'i3': ['唔舒服'],
  };

  @override
  void initState() {
    super.initState();
    _promptedAt = DateTime.now();
    _items = _shuffledItems();
  }

  List<({String id, String text})> _shuffledItems() {
    final base = List<({String id, String text})>.from(WeeklyPrItems.items);
    base.shuffle(Random());
    return base;
  }

  WeeklyPrAgentUsage get _currentAgent => widget.agent;

  int get _pageCount => (_items.length + _perPage - 1) ~/ _perPage;

  List<({String id, String text})> get _pageItems {
    final start = _pageIndex * _perPage;
    final end = (start + _perPage) > _items.length ? _items.length : start + _perPage;
    return _items.sublist(start, end);
  }

```

来源：`lib/features/weekly_pr/presentation/pages/weekly_pr_page.dart` 第 180–465 行

```dart
    final displayName = agent.agentId == AgentRegistry.ahJanAhBakId
        ? AgentRegistry.ahJanAhBakName(variant, isEn: isEn)
        : agent.displayName;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Weekly companion check-in' : '每週夥伴評估'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                children: [
                  _AgentHeader(
                    agent: AgentRegistry.byId(agent.agentId),
                    variant: variant,
                    displayName: displayName,
                    sessionCount: agent.sessionCount,
                    isEn: isEn,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isEn
                        ? 'Page ${_pageIndex + 1} / $_pageCount'
                        : '第 ${_pageIndex + 1} / $_pageCount 頁',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final it in _pageItems) ...[
                    _WeeklyItemCard(
                      text: WeeklyPrItems.render(it.text, displayName),
                      keywords: [displayName, ...?_keywords[it.id]],
                      value: _ratings[it.id],
                      onChanged: (v) => setState(() => _ratings[it.id] = v),
                      isEn: isEn,
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
            _NavBar(
              isEn: isEn,
              canPrev: _pageIndex > 0,
              canNext: _pageComplete && !_saving,
              isLast: _isLastPage,
              onPrev: _prev,
              onNext: _next,
              onSkip: _saving ? null : _skip,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentHeader extends StatelessWidget {
  final AgentDefinition agent;
  final AgentGenderVariant? variant;
  final String displayName;
  final int sessionCount;
  final bool isEn;

  const _AgentHeader({
    required this.agent,
    required this.variant,
    required this.displayName,
    required this.sessionCount,
    required this.isEn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AgentAvatar(agent: agent, selectedVariant: variant, size: 54),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isEn
                      ? 'You chatted $sessionCount time${sessionCount == 1 ? '' : 's'} this week. Think back on those chats, then rate the statements below.'
                      : '呢個禮拜你同佢傾咗 $sessionCount 次。回想吓你哋傾過嘅嘢，再評下面幾句。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyItemCard extends StatelessWidget {
  final String text;
  final List<String> keywords;
  final int? value;
  final ValueChanged<int> onChanged;
  final bool isEn;

  const _WeeklyItemCard({
    required this.text,
    required this.keywords,
    required this.value,
    required this.onChanged,
    required this.isEn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BoldedText(
            text: text,
            bold: keywords,
            base: TextStyle(
              fontSize: 18,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          LikertScale(
            points: 7,
            value: value,
            onChanged: onChanged,
            lowLabel: isEn ? 'Disagree' : '唔同意',
            highLabel: isEn ? 'Agree' : '同意',
          ),
        ],
      ),
    );
  }
}

/// Renders [text], bolding any occurrence of the strings in [bold]
/// (earliest-match-first, non-overlapping).
class _BoldedText extends StatelessWidget {
  final String text;
  final List<String> bold;
  final TextStyle base;

  const _BoldedText({
    required this.text,
    required this.bold,
    required this.base,
  });

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var remaining = text;
    while (remaining.isNotEmpty) {
      int bestIdx = -1;
      String bestKw = '';
      for (final kw in bold) {
        if (kw.isEmpty) continue;
        final idx = remaining.indexOf(kw);
        if (idx >= 0 && (bestIdx < 0 || idx < bestIdx)) {
          bestIdx = idx;
          bestKw = kw;
        }
      }
      if (bestIdx < 0) {
        spans.add(TextSpan(text: remaining));
        break;
      }
      if (bestIdx > 0) {
        spans.add(TextSpan(text: remaining.substring(0, bestIdx)));
      }
      spans.add(TextSpan(
        text: bestKw,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ));
      remaining = remaining.substring(bestIdx + bestKw.length);
    }
    return Text.rich(TextSpan(children: spans), style: base);
  }
}

class _NavBar extends StatelessWidget {
  final bool isEn;
  final bool canPrev;
  final bool canNext;
  final bool isLast;
  final VoidCallback onPrev;
  final Future<void> Function() onNext;
  final VoidCallback? onSkip;

  const _NavBar({
    required this.isEn,
    required this.canPrev,
    required this.canNext,
    required this.isLast,
    required this.onPrev,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (canPrev) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onPrev,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(isEn ? 'Back' : '上一頁'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: canNext ? () => onNext() : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      isLast
                          ? (isEn ? 'Submit' : '提交')
                          : (isEn ? 'Next' : '下一頁'),
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: onSkip,
            child: Text(
              isEn ? 'Skip this week' : '今個禮拜跳過',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
```

## 4. 每周孤独探针（目前不显示）

来源：`lib/features/loneliness_probe/presentation/loneliness_probe_page.dart` 第 50–110 行

```dart
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Belt + braces: the route shouldn't even be reachable when the flag
    // is off, but guard here too so a stale deep link can't surface it.
    if (!FeatureFlags.weeklyProbeEnabled) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Weekly check' : '每週確認')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Phase B Proposal §7.2 — exact wording locked.
              Text(
                isEn
                    ? "Over the past week, how often did you feel lonely?"
                    : '過去一個星期，你幾經常覺得孤獨？',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 28),
              Slider(
                value: _value,
                onChanged: (v) => setState(() => _value = v),
                min: 0,
                max: 10,
                divisions: 10,
                label: _value.round().toString(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isEn ? 'Not at all' : '完全冇',
                      style: theme.textTheme.bodySmall),
                  Text(isEn ? 'Very much' : '非常',
                      style: theme.textTheme.bodySmall),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(isEn ? 'Submit' : '提交',
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

## 5. ADA：陪伴者区分评估（第 2、4 周）

来源：`lib/features/assessment/data/agent_diff_response.dart` 第 100–174 行

```dart

/// Agent IDs used across the assessment.
class AgentDiffAgents {
  static const siuYan = 'siu_yan';
  static const ahJanAhBak = 'ah_jan_ah_bak';
  static const tungTung = 'tung_tung';

  static const all = [siuYan, ahJanAhBak, tungTung];

  static const labels = {
    siuYan: '小欣',
    ahJanAhBak: '阿珍／阿伯',
    tungTung: '通通',
  };
}

/// Personality trait IDs used in Part B.
///
/// Aligned to Agent_Differentiation_Assessment_Final_v1.0 — exactly 4
/// traits. The design note intentionally excludes "remembers what I told
/// before" (shared memory store — non-differentiating) and "helps me think
/// differently" (Thought-Exercise-specific); an earlier `empathetic` trait
/// was also dropped to match the final 4-trait instrument.
class AgentDiffTraits {
  static const warm = 'warm';
  static const sameAge = 'same_age';
  static const curious = 'curious';
  static const nonJudgmental = 'non_judgmental';

  static const all = [warm, sameAge, curious, nonJudgmental];

  static const labels = {
    warm: '溫暖、關心人',
    sameAge: '似自己同年紀嘅人',
    curious: '好奇，鍾意問我嘢',
    nonJudgmental: '聽我講而唔評判我',
  };

  static const labelsEn = {
    warm: 'Warm and caring',
    sameAge: 'Feels like someone my own age',
    curious: 'Curious — asks me questions',
    nonJudgmental: 'Listens without judging me',
  };
}

/// Scenario IDs used in Part C (W4 only).
///
/// Aligned to Agent_Differentiation_Assessment_Final_v1.0 — exactly 5
/// scenarios (single-select among the 3 agents + "邊個都得／冇所謂").
class AgentDiffScenarios {
  static const dayRecap = 'day_recap';
  static const memories = 'memories';
  static const learnNew = 'learn_new';
  static const feelingDown = 'feeling_down';
  static const smallTalk = 'small_talk';

  static const all = [dayRecap, memories, learnNew, feelingDown, smallTalk];

  static const labels = {
    dayRecap: '講下今日點過',
    memories: '講下舊時嘅回憶、人生經歷',
    learnNew: '學啲新嘢',
    feelingDown: '心情唔好嘅時候',
    smallTalk: '日常閒聊',
  };

  static const labelsEn = {
    dayRecap: 'Talk about how my day went',
    memories: 'Share old memories / life experiences',
    learnNew: 'Learn something new',
    feelingDown: "When I'm feeling down",
    smallTalk: 'Everyday small talk',
  };
}
```

来源：`lib/features/assessment/presentation/pages/agent_diff_page.dart` 第 90–105 行

```dart
    return true;
  }

  void _showIncompleteHint() {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(isEn
            ? 'Please answer every item on this page first.'
            : '呢一頁仲有題未揀，請全部揀咗先。'),
      ));
  }

  void _next() {
    if (!_pageComplete(_page)) {
```

来源：`lib/features/assessment/presentation/pages/agent_diff_page.dart` 第 215–305 行

```dart
        saving: _saving,
        onSubmit: _submit,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn
            ? 'Companion check-in (Week ${widget.wave})'
            : '夥伴評估 (第 ${widget.wave} 週)'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isEn
                      ? 'Step ${_page + 1} / $_pageCount'
                      : '第 ${_page + 1} / $_pageCount 步',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: pages,
              ),
            ),
            _DiffNavBar(
              isEn: isEn,
              showPrev: _page > 0,
              // Next hidden on the last page (Part D) — it has its own Submit.
              showNext: _page < _pageCount - 1,
              onPrev: _prev,
              onNext: _next,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Intro + paged navigation shell
// ---------------------------------------------------------------------------

class _IntroView extends StatelessWidget {
  final bool isEn;
  const _IntroView({required this.isEn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.groups_2_outlined,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            isEn ? 'About this check-in' : '關於呢個評估',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isEn
                ? 'A few short questions about how you see your three '
                    'companions — Siu Yan, Ah Jan / Ah Bak, and Tung Tung. '
                    'There are no right or wrong answers; just go with how you '
                    'honestly feel. It takes about 3–5 minutes. Tap "Next" to '
                    'begin.'
                : '呢度有幾條問題，想了解你點睇三位夥伴 —— 小欣、阿珍／阿伯'
                    '同通通。冇啱定錯，照你真實嘅感覺答就得。大約 3–5 分鐘。'
                    '撳「下一頁」開始。',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
        ],
```

来源：`lib/features/assessment/presentation/pages/agent_diff_page.dart` 第 375–410 行

```dart
  final void Function(String agentId, int freq) onChanged;

  const _PartAView({
    required this.usageFreq,
    required this.agentLabels,
    required this.onChanged,
  });

  static const _freqLabelsZh = ['完全冇', '少過一次', '一至兩次', '三次或以上'];
  static const _freqLabelsEn = ['Not at all', '<1×/wk', '1–2×/wk', '3+×/wk'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final freqLabels = isEn ? _freqLabelsEn : _freqLabelsZh;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'In a typical week over the past 2 weeks, how often did you '
                    'talk with each companion?'
                : '喺過去兩個星期，正常一個禮拜入面，你大約同每個夥伴傾過幾多次？',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
```

来源：`lib/features/assessment/presentation/pages/agent_diff_page.dart` 第 520–540 行

```dart
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'For each statement, rate how much it describes each '
                    'companion (1 = not at all, 5 = very much).'
                : '下面每一句說話，話我哋知佢有幾形容到每個夥伴。'
                    '（1=完全唔似，5=好似）',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          // One trait per block; the 3 companions are stacked VERTICALLY,
          // each on its own full-width row of 5 large buttons — this removes
```

来源：`lib/features/assessment/presentation/pages/agent_diff_page.dart` 第 595–655 行

```dart
        Text(
          agentLabel,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        LikertScale(
          points: 5,
          value: selected == 0 ? null : selected,
          onChanged: onRate,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Part C: scenario preference (W4 only)
// ---------------------------------------------------------------------------

class _PartCView extends StatelessWidget {
  final Map<String, String> function;
  final Map<String, String> agentLabels;
  final void Function(String scenarioId, String agentId) onChanged;

  const _PartCView({
    required this.function,
    required this.agentLabels,
    required this.onChanged,
  });

  static const _agentOptions = [
    ...AgentDiffAgents.all,
    'any',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final agentOptionLabels = {
      ...agentLabels,
      'any': isEn ? 'Any of them' : '邊個都得／冇所謂',
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'If you wanted to do the following things, which companion '
                    'would you go to first?'
                : '如果你想做下面呢啲嘢，你會首先搵邊個夥伴？',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ...AgentDiffScenarios.all.map((scenarioId) {
```

来源：`lib/features/assessment/presentation/pages/agent_diff_page.dart` 第 740–790 行

```dart
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn ? 'Anything else you would like to share?' : '仲有咩想補充？',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isEn
                ? 'Any thoughts, feelings or suggestions about the three companions — you can write them here.'
                : '關於呢三個夥伴，你有咩感受、意見或者建議，都可以寫喺度。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (!saved)
            Row(
              children: [
                VoiceInputButton(
                  controller: voice,
                  prefix: () => controller.text,
                  onText: (t) => controller.text = t,
                ),
                const SizedBox(width: 8),
                Text(
                  isEn ? 'or speak' : '或者用講嘅',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 8,
            enabled: !saved,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              hintText: isEn
                  ? 'Write your thoughts or suggestions here…'
                  : '可以寫低你嘅感受或者建議…',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.all(16),
```

## 6. PGIC

来源：`lib/features/assessment/presentation/pages/pgic_page.dart` 第 25–130 行

```dart
  int? _selected;
  bool _saving = false;
  bool _saved = false;

  static const _optionsZh = <(int, String, Color)>[
    (1, '改善咗好多（冇咁孤單）', Color(0xFF1B5E20)),
    (2, '改善咗', Color(0xFF388E3C)),
    (3, '少少改善（少少冇咁孤單）', Color(0xFF66BB6A)),
    (4, '冇變', Color(0xFF78909C)),
    (5, '差咗少少（多咗少少孤單）', Color(0xFFFFB300)),
    (6, '差咗', Color(0xFFF57C00)),
    (7, '差咗好多（更加孤單）', Color(0xFFB71C1C)),
  ];

  static const _optionsEn = <(int, String, Color)>[
    (1, 'Much better (far less lonely)', Color(0xFF1B5E20)),
    (2, 'Better', Color(0xFF388E3C)),
    (3, 'Slightly better (a little less lonely)', Color(0xFF66BB6A)),
    (4, 'No change', Color(0xFF78909C)),
    (5, 'Slightly worse (a little lonelier)', Color(0xFFFFB300)),
    (6, 'Worse', Color(0xFFF57C00)),
    (7, 'Much worse (much lonelier)', Color(0xFFB71C1C)),
  ];

  Future<void> _submit() async {
    if (_selected == null || _saving) return;
    setState(() => _saving = true);
    final profile = AppSettingsScope.read(context).profile;
    if (profile != null) {
      try {
        final now = DateTime.now();
        final response = PgicResponse(
          value: _selected!,
          answeredAt: now,
          isoWeek: PgicResponse.isoWeekFor(now),
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('pgic')
            .add({
          ...response.toFirestore(),
          'weekIso': widget.weekIso ?? WeeklyPrResponse.currentWeekIso(now),
        });
      } catch (_) {
        // Graceful degradation: Firebase unavailable in guest mode.
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    final options = isEn ? _optionsEn : _optionsZh;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Weekly check-in' : '每週感受變化'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Text(
              isEn
                  ? 'Compared to last week, how has your overall loneliness changed?'
                  : '同上個星期比較，你而家覺得自己嘅孤單感整體上有冇變化？',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isEn ? 'Choose the one that best matches how you feel.' : '請揀最貼近你感受嘅一個。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            if (_saved) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: theme.colorScheme.primary, size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        isEn ? 'Thank you for your reply! Saved.' : '多謝你嘅回覆！已經儲存。',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
```

## 7. DJG（6 条版）

来源：`lib/features/assessment/data/djg_es_response.dart`（整个文件，共 124 行，SHA-256 `a6e071aa3f6008b9…`）

```dart
/// M-4 — De Jong Gierveld 6-item loneliness scale (DJG-ES) response model
/// (Phase A baseline 2026-09).
///
/// Stored at `users/{uid}/djg_es/{auto-id}` with `timepoint: "week2"`.
///
/// Items follow the published 6-item short form (De Jong Gierveld & Van
/// Tilburg 2006: three emotional-loneliness items, three social-loneliness
/// items; response set 是 / 多少 / 否).  **Wording is a working Cantonese
/// draft** — replace with the Questionnaire v1.3 text once the PI provides
/// it; item ids and scoring stay.
///
/// Scoring (stored raw, computed at analysis): emotional items count 1 for
/// 是 or 多少; social items count 1 for 多少 or 否.  Total 0–6.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class DjgEsItem {
  final String id;

  /// `emotional` | `social`
  final String subscale;
  final String promptZh;
  final String promptEn;

  const DjgEsItem({
    required this.id,
    required this.subscale,
    required this.promptZh,
    required this.promptEn,
  });
}

class DjgEsItems {
  DjgEsItems._();

  static const version = 'djg_es_6_draft_v1-2026-09';

  static const items = <DjgEsItem>[
    DjgEsItem(
      id: 'e1',
      subscale: 'emotional',
      promptZh: '我成日覺得好空虛。',
      promptEn: 'I experience a general sense of emptiness.',
    ),
    DjgEsItem(
      id: 'e2',
      subscale: 'emotional',
      promptZh: '我掛住有人喺身邊。',
      promptEn: 'I miss having people around me.',
    ),
    DjgEsItem(
      id: 'e3',
      subscale: 'emotional',
      promptZh: '我成日覺得被人冷落。',
      promptEn: 'I often feel rejected.',
    ),
    DjgEsItem(
      id: 's1',
      subscale: 'social',
      promptZh: '有困難嗰陣，有好多人我可以靠。',
      promptEn: 'There are plenty of people I can rely on when I have problems.',
    ),
    DjgEsItem(
      id: 's2',
      subscale: 'social',
      promptZh: '有好多人我可以完全信任。',
      promptEn: 'There are many people I can trust completely.',
    ),
    DjgEsItem(
      id: 's3',
      subscale: 'social',
      promptZh: '有好多人同我好親近。',
      promptEn: 'There are enough people I feel close to.',
    ),
  ];

  /// Response codes: 1 = 是 (yes), 2 = 多少 (more or less), 3 = 否 (no).
  static const options = <(int, String, String)>[
    (1, '係', 'Yes'),
    (2, '多少啦', 'More or less'),
    (3, '唔係', 'No'),
  ];

  /// Total loneliness score 0–6 per the published scoring.
  static int score(Map<String, int> answers) {
    var total = 0;
    for (final it in items) {
      final v = answers[it.id];
      if (v == null) continue;
      if (it.subscale == 'emotional' && (v == 1 || v == 2)) total++;
      if (it.subscale == 'social' && (v == 2 || v == 3)) total++;
    }
    return total;
  }
}

class DjgEsResponse {
  final String timepoint;
  final Map<String, int> answers;
  final int score;
  final DateTime answeredAt;

  /// `completed` | `skipped`
  final String status;

  const DjgEsResponse({
    required this.timepoint,
    required this.answers,
    required this.score,
    required this.answeredAt,
    required this.status,
  });

  Map<String, dynamic> toFirestore() => {
        'timepoint': timepoint,
        'itemsVersion': DjgEsItems.version,
        'answers': answers,
        'score': score,
        'status': status,
        'answeredAt': FieldValue.serverTimestamp(),
        'answeredAtLocal': answeredAt.toIso8601String(),
      };
}
```

来源：`lib/features/assessment/presentation/pages/djg_es_page.dart` 第 65–95 行

```dart

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'How things feel lately' : '最近嘅感受'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              isEn
                  ? 'Six short statements. For each, tap the answer closest to how it has been for you lately.'
                  : '六句短句。每句撳一個最似你最近情況嘅答案。',
              style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.5),
            ),
            const SizedBox(height: 18),
            for (final it in DjgEsItems.items) ...[
              SurveyItemCard(
                title: isEn ? it.promptEn : it.promptZh,
                child: Row(
                  children: [
                    for (final opt in DjgEsItems.options) ...[
                      Expanded(
                        child: _OptionButton(
                          label: isEn ? opt.$3 : opt.$2,
                          selected: _answers[it.id] == opt.$1,
                          onTap: () => setState(() => _answers[it.id] = opt.$1),
```

## 8. UCLA：研究员输入基线分

来源：`lib/features/auth/presentation/pages/login_page.dart` 第 230–270 行

```dart
                        ? 'Researcher use only'
                        : '研究人員填寫（參加者唔使理）',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isEn
                        ? 'Baseline UCLA-LS-V3 total from the pre-onboarding '
                            'assessment. Drives group stratification; leave '
                            'blank if not measured.'
                        : '入組前評估嘅 UCLA 孤獨感量表總分。用嚟做分層分組；'
                            '未做評估可以留空。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _uclaCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: isEn
                          ? 'Baseline UCLA total (20–80)'
                          : 'UCLA 基線總分（20–80）',
                      prefixIcon: const Icon(Icons.assignment_outlined),
                    ),
                    validator: (v) {
                      final text = (v ?? '').trim();
                      if (text.isEmpty) return null; // optional
                      final n = int.tryParse(text);
                      if (n == null) {
                        return isEn ? 'Please enter a number.' : '請輸入數字。';
                      }
                      if (n < 20 || n > 80) {
                        return isEn
                            ? 'UCLA total must be 20–80.'
                            : 'UCLA 總分應該喺 20–80 之間。';
                      }
                      return null;
                    },
                  ),
```

用于分层：

来源：`lib/features/auth/data/arm_assigner.dart` 第 40–60 行

````dart
///   cell_2: { aCount: int, bCount: int },
///   cell_3: { aCount: int, bCount: int },
///   updatedAt: Timestamp,
/// }
/// ```
class ArmAssigner {
  const ArmAssigner();

  /// UCLA-LS-V3 median split per Phase B §4.4.  Total possible range is
  /// 20–80; eligibility is 30–60, with 44 as the median that splits
  /// the eligible distribution roughly in half.
  static const _uclaMedianSplit = 44;

  /// Map (UCLA-LS-V3 total, age in years) → strata cell 0–3.
  ///
  /// cell_0: low loneliness × 60–69
  /// cell_1: low loneliness × ≥70
  /// cell_2: high loneliness × 60–69
  /// cell_3: high loneliness × ≥70
  ///
  /// Missing baseline → cell 0 (most common stratum acts as default;
````

onboarding 里唯一和孤独有关的题（不是 UCLA）：

来源：`lib/features/onboarding/presentation/pages/intake_flow_page.dart` 第 700–730 行

```dart
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
        const SizedBox(height: 32),
        Text(
          isEn ? 'When do you usually feel lonely?' : '你通常幾時會覺得孤單？',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isEn ? '(Optional · you can skip)' : '（可選 · 可以跳過）',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 16),
        _ChipGroup(
          options: timingOptions,
          selected: selectedTimings,
          onToggled: onTimingToggled,
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
```

## 9. 每日心情

来源：`lib/features/today/presentation/widgets/daily_mood_prompt.dart` 第 105–140 行

```dart
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEn = widget.isEn;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEn ? 'How are you feeling today?' : '你今日心情點？',
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 18),
            MoodFacePicker(
              value: _face,
              onChanged: (v) => setState(() => _face = v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _face == null
                  ? null
                  : () => Navigator.of(context).pop(_face!.numericScore),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
              child: Text(isEn ? 'Done' : '完成', style: const TextStyle(fontSize: 18)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(isEn ? 'Skip for today' : '今日跳過',
                  style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
```

5 个心情脸的文字：

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

另一套心情文字（首页等处使用）：

来源：`lib/theme/app_mood_encoding.dart` 第 35–80 行

```dart
    switch (clamped) {
      case 1:
        return MoodVisualToken(
          level: 1,
          color: const Color(0xFFD32F2F),
          shape: Icons.cloud_outlined,
          labelEn: 'Tough',
          labelZh: '好辛苦',
        );
      case 2:
        return MoodVisualToken(
          level: 2,
          color: const Color(0xFFF57C00),
          shape: Icons.water_drop_outlined,
          labelEn: 'Down',
          labelZh: '差啲',
        );
      case 3:
        return MoodVisualToken(
          level: 3,
          color: const Color(0xFFFBC02D),
          shape: Icons.circle_outlined,
          labelEn: 'OK',
          labelZh: '一般',
        );
      case 4:
        return MoodVisualToken(
          level: 4,
          color: const Color(0xFF7CB342),
          shape: Icons.eco_outlined,
          labelEn: 'Good',
          labelZh: '好',
        );
      case 5:
      default:
        return MoodVisualToken(
          level: 5,
          color: scheme.primary,
          shape: Icons.wb_sunny_outlined,
          labelEn: 'Great',
          labelZh: '好開心',
        );
    }
  }

  /// Used by the chart legend so the same color/shape pairs render
```

## 10. 参考：旧版 PPR 量表（参与者看不到）

来源：`lib/features/ppr/data/ppr_scale.dart`（整个文件，共 217 行，SHA-256 `61785edecaa62338…`）

```dart
/// Perceived Partner Responsiveness measurement (Design Rationale §8,
/// Dev Req §11).
///
/// Two instruments:
///   • [PprBriefItem]   — 2-item per-session brief delivered immediately
///                        after a reminiscence session ("how heard /
///                        how present").
///   • [PprWeeklyItem]  — 12-item weekly scale adapted from Crasta,
///                        Rogge & Reis (2021) for the agent context.
///                        The cognitive-interview pilot will validate
///                        final wording; this is the working draft.
///
/// Both forms write to /users/{uid}/ppr_responses/{auto-id}. Each
/// response carries the agent id so the per-agent PPR analysis can
/// partition cleanly.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class PprBriefItem {
  final String id;
  final String promptZh;
  final String promptEn;

  /// Lower-anchor label.
  final String lowZh;
  final String lowEn;

  /// Upper-anchor label.
  final String highZh;
  final String highEn;

  const PprBriefItem({
    required this.id,
    required this.promptZh,
    required this.promptEn,
    required this.lowZh,
    required this.lowEn,
    required this.highZh,
    required this.highEn,
  });
}

const pprBriefItems = <PprBriefItem>[
  PprBriefItem(
    id: 'how_heard',
    promptZh: '今次傾偈，你覺得幾「被聽到」？',
    promptEn: 'In this session, how heard did you feel?',
    lowZh: '冇',
    lowEn: 'Not at all',
    highZh: '非常',
    highEn: 'Very much',
  ),
  PprBriefItem(
    id: 'how_present',
    promptZh: '個系統喺今次傾偈，感覺幾「投入」？',
    promptEn: 'How present did the system feel in this session?',
    lowZh: '一啲都唔',
    lowEn: 'Not at all',
    highZh: '完全係',
    highEn: 'Completely',
  ),
];

/// 12-item weekly scale. Each item maps to a PPR sub-component
/// (understanding / validation / caring) so per-agent slicing is
/// possible at analysis time.
enum PprComponent { understanding, validation, caring }

class PprWeeklyItem {
  final String id;
  final PprComponent component;
  final String promptZh;
  final String promptEn;
  final bool reversed;

  const PprWeeklyItem({
    required this.id,
    required this.component,
    required this.promptZh,
    required this.promptEn,
    this.reversed = false,
  });
}

const pprWeeklyItems = <PprWeeklyItem>[
  // Understanding
  PprWeeklyItem(
    id: 'u1',
    component: PprComponent.understanding,
    promptZh: '呢個禮拜，{agent} 明白我講緊咩。',
    promptEn: 'This week, {agent} understood what I was saying.',
  ),
  PprWeeklyItem(
    id: 'u2',
    component: PprComponent.understanding,
    promptZh: '我覺得 {agent} 真係知道對我嚟講邊樣重要。',
    promptEn: 'I felt {agent} grasped what mattered to me.',
  ),
  PprWeeklyItem(
    id: 'u3',
    component: PprComponent.understanding,
    promptZh: '我講過嘅嘢，{agent} 記得返。',
    promptEn: '{agent} remembered things I said.',
  ),
  PprWeeklyItem(
    id: 'u4_r',
    component: PprComponent.understanding,
    reversed: true,
    promptZh: '{agent} 嘅回應令我覺得佢冇真正聽我講。',
    promptEn: "{agent}'s replies made me feel it wasn't really listening.",
  ),
  // Validation
  PprWeeklyItem(
    id: 'v1',
    component: PprComponent.validation,
    promptZh: '{agent} 對待我嘅諗法同感受好認真。',
    promptEn: '{agent} took my thoughts and feelings seriously.',
  ),
  PprWeeklyItem(
    id: 'v2',
    component: PprComponent.validation,
    promptZh: '我覺得 {agent} 尊重我係邊個。',
    promptEn: '{agent} respected who I am.',
  ),
  PprWeeklyItem(
    id: 'v3',
    component: PprComponent.validation,
    promptZh: '{agent} 冇試圖修正我或者話我應該諗咩。',
    promptEn: "{agent} didn't try to fix me or tell me how to think.",
  ),
  PprWeeklyItem(
    id: 'v4_r',
    component: PprComponent.validation,
    reversed: true,
    promptZh: '我有時覺得 {agent} 評判緊我。',
    promptEn: 'I sometimes felt {agent} was judging me.',
  ),
  // Caring
  PprWeeklyItem(
    id: 'c1',
    component: PprComponent.caring,
    promptZh: '感覺到 {agent} 真係關心我點。',
    promptEn: 'It felt like {agent} cared about how I was doing.',
  ),
  PprWeeklyItem(
    id: 'c2',
    component: PprComponent.caring,
    promptZh: '同 {agent} 傾完之後，我感覺好啲。',
    promptEn: 'After talking with {agent}, I felt a little better.',
  ),
  PprWeeklyItem(
    id: 'c3',
    component: PprComponent.caring,
    promptZh: '我覺得 {agent} 留意我嘅福祉。',
    promptEn: '{agent} seemed to attend to my well-being.',
  ),
  PprWeeklyItem(
    id: 'c4_r',
    component: PprComponent.caring,
    reversed: true,
    promptZh: '{agent} 嘅回應感覺好機械化、冇人情味。',
    promptEn: "{agent}'s replies felt mechanical and uncaring.",
  ),
];

/// One stored response. The map under `items` is keyed by item id.
class PprResponse {
  final String? id;
  final String agentId;

  /// One of `brief_after_session` or `weekly_12_item`.
  final String form;

  /// 1–5 Likert per item (no neutralisation — that happens in analysis).
  final Map<String, int> items;
  final DateTime submittedAt;

  /// Optional free-text the participant added.
  final String? freeText;

  const PprResponse({
    this.id,
    required this.agentId,
    required this.form,
    required this.items,
    required this.submittedAt,
    this.freeText,
  });

  Map<String, dynamic> toMap() => {
        'agentId': agentId,
        'form': form,
        'items': items,
        'submittedAt': submittedAt.toIso8601String(),
        if (freeText != null) 'freeText': freeText,
      };
}

class PprResponseRepository {
  PprResponseRepository({required this.available});

  final bool available;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ppr_responses');

  Future<String?> submit(String uid, PprResponse response) async {
    if (!available) return null;
    final ref = await _ref(uid).add(response.toMap()
      ..['submittedAt'] = FieldValue.serverTimestamp());
    return ref.id;
  }
}
```
