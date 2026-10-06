# 两组共用：主题式怀旧课程（M3）

**结论**：课程共 4 周，每周 1 个主题、1 句开场（`reminiscence_themes.dart`）。两组看到同一份主题和开场句：
规则组直接显示开场句；Hybrid 组由 AI 生成开场白，AI 失败时才显示这句（AI 用的 prompt 见 02 文件第 5 节）。
**注意**：回忆入口页的介绍文字写「6 個主題、6 個禮拜」，和代码里的 4 周不一致（见第 2 节）。

**app 实际显示哪个版本**：`lib/app/app_settings.dart` 第 45 行 `englishEnabled = false`，第 50 行把 locale 强制为 `zh`
（`lib/main.dart` 第 115 行也传 `Locale('zh')`）。所以 `isEn ? 英文 : 中文` 和 `…Zh / …En` 成对的文字里，**只有中文版会显示**。
英文版照样导出，老人看不到。`app_zh_Hant_HK.arb` 虽然编译进去了，但 app 从不选 `zh_Hant_HK`，实际用的是 `app_zh.arb`；
本文件的内容都写在 Dart / JS 源码里，不在 ARB 文件里。

## 条数

| 项目 | 条数 | 怎么数的 |
|---|---|---|
| 主题（周） | 4 | `ReminiscenceTheme.all` 里 `ReminiscenceTheme(` 个数；`totalWeeks = 4` |
| 每周开场句 | 4 | 每个主题 1 条 `openingZh`（另有 `openingEn`） |

## 1. 主题和开场句

来源：`lib/features/reminiscence/data/reminiscence_themes.dart`（整个文件，共 75 行，SHA-256 `14d0f73d21d10250…`）

```dart
/// Spec §M3: 4-week reminiscence curriculum (P2 plan, scaled down from
/// the prior 6-week prototype for the pilot cohort). Themes track the
/// dissertation's four protected windows: place of origin, working life,
/// friendships, and legacy. The HK cultural co-design will land
/// thematic refinements in a separate document; the four prompts here
/// keep the structure for the basic build.
class ReminiscenceTheme {
  final int weekIndex; // 1..4
  final String titleZh;
  final String titleEn;
  final String openingZh;
  final String openingEn;

  const ReminiscenceTheme({
    required this.weekIndex,
    required this.titleZh,
    required this.titleEn,
    required this.openingZh,
    required this.openingEn,
  });

  /// Total weeks in the curriculum. Referenced by the My Story tab and
  /// any reader that wants to display "Week N of {totalWeeks}".
  static const totalWeeks = 4;

  static const all = <ReminiscenceTheme>[
    ReminiscenceTheme(
      weekIndex: 1,
      titleZh: '童年同屋企',
      titleEn: 'Childhood & home',
      openingZh:
          '今個禮拜，不如傾下你細個住嘅地方。你最記得邊條街、邊個鋪頭、或者邊個鄰居？',
      openingEn:
          'This week, let\'s talk about where you grew up. What street, '
              'shop, or neighbour do you remember first?',
    ),
    ReminiscenceTheme(
      weekIndex: 2,
      titleZh: '後生時期同工作',
      titleEn: 'Young adulthood & work',
      openingZh: '今個禮拜想聽下你後生嗰陣嘅故事。你嘅第一份工係咩？嗰陣係點開始嘅？',
      openingEn:
          'This week I\'d love to hear about your younger years. What was '
              'your first job? How did it begin?',
    ),
    ReminiscenceTheme(
      weekIndex: 3,
      titleZh: '一生人嘅朋友',
      titleEn: 'Friendships across a lifetime',
      openingZh:
          '今個禮拜，諗下對你嚟講重要嘅朋友。有冇一個朋友，你會覺得無論幾耐冇見，見返都好似冇變？',
      openingEn:
          'This week, think about a friend who mattered to you. Is there '
              'someone you feel never really changed, no matter how long '
              'you went without seeing them?',
    ),
    ReminiscenceTheme(
      weekIndex: 4,
      titleZh: '想留畀下一代嘅說話',
      titleEn: 'What I would tell the next generation',
      openingZh:
          '今個禮拜係最後一堂。如果你可以同年輕一代講一句說話，你想佢哋知道啲咩？',
      openingEn:
          'This is the final week. If you could leave one thing for the '
              'next generation to know, what would it be?',
    ),
  ];

  static ReminiscenceTheme byIndex(int weekIndex) {
    return all.firstWhere(
      (t) => t.weekIndex == weekIndex,
      orElse: () => all.first,
    );
  }
}
```

## 2. 回忆入口页文字

来源：`lib/features/reminiscence/presentation/pages/reminiscence_landing.dart` 第 22–60 行

```dart
    final theme = Theme.of(context);
    final profile = AppSettingsScope.of(context).profile;
    final auth = AuthServiceScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Life stories' : '人生點滴'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              isEn
                  ? 'A weekly 15–25 minute session. Six themes across six '
                      'weeks. There\'s no right answer — just what you '
                      'remember.'
                  : '每星期一節，15-25 分鐘。6 個主題、6 個禮拜。冇標準答案，記得幾多都得。',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openMemories(context),
              icon: const Icon(Icons.collections_bookmark_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  isEn ? 'My memories' : '我嘅回憶',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            for (final t in ReminiscenceTheme.all)
              _ThemeCard(
                theme: t,
                onOpen: () => _open(context, t),
                completedStream:
                    _completedStream(auth, profile?.uid, t.weekIndex),
```

## 3. 当前周怎么算

来源：`lib/features/my_story/data/my_story_progress.dart` 第 85–96 行

```dart
            : (summary.length > 60 ? '${summary.substring(0, 60)}…' : summary),
        completedAt: doc?.completedAt,
      ));
    }

    // Current week = onboarding week + elapsed weeks, clamped to total.
    final start = userCreatedAt ?? referenceDate;
    final daysIn = referenceDate.difference(start).inDays;
    final computed = (daysIn ~/ 7) + 1;
    final clamped = computed.clamp(1, allThemes.length).toInt();

    return MyStoryProgress(weeks: weeks, currentWeekIndex: clamped);
```
