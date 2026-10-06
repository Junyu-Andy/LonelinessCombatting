# 规则组：每周小结

**结论**：规则组**没有每周小结模板**。进度页（M9）规则组只显示图表和数字，没有文字小结卡
（`progress_page.dart` 第 90–94 行：只有 `Arm.isA` 才生成小结）。
`_staticSummary`（第 126–143 行）只在 Hybrid 组 AI 失败时作为后备，规则组不会看到。下面导出规则组实际看到的进度页文字。

**app 实际显示哪个版本**：`lib/app/app_settings.dart` 第 45 行 `englishEnabled = false`，第 50 行把 locale 强制为 `zh`。
所以 `zh:` / `isEn ? … : …` 里**只有中文（粤语）版本会显示**；英文版照样导出，老人看不到。
规则组内容全部写在 Dart 源码里，不在 ARB 本地化文件里。

## 条数

| 项目 | 条数 | 怎么数的 |
|---|---|---|
| 规则组每周小结模板 | 0 | 代码里没有 |

`_staticSummary`（只作 Hybrid 组后备）：

来源：`lib/features/progress/presentation/pages/progress_page.dart` 第 126–143 行

```dart
  String _staticSummary(WeeklyProgress d, bool isEn) {
    if (isEn) {
      final lines = <String>[];
      lines.add('Past 7 days at a glance:');
      lines.add('• Check-ins: ${d.moodScores.length}');
      lines.add('• Plans you made: ${d.plansAuthored}');
      lines.add('• Plans you followed up on: ${d.plansFollowedUp}');
      lines.add('• Reminiscence sessions: ${d.reminiscenceSessions}');
      return lines.join('\n');
    }
    final lines = <String>[];
    lines.add('呢個禮拜：');
    lines.add('• Check-in：${d.moodScores.length} 次');
    lines.add('• 計劃咗：${d.plansAuthored} 個');
    lines.add('• 跟進咗：${d.plansFollowedUp} 個');
    lines.add('• 人生點滴：${d.reminiscenceSessions} 節');
    return lines.join('\n');
  }
```

进度页文字（两组都看到的标题、图表标签、数量标签）：

来源：`lib/features/progress/presentation/pages/progress_page.dart` 第 150–250 行

```dart
    // M-7 — tool session: enter = start, leave = end.
    return ToolSessionScope(
      toolId: 'progress',
      child: Scaffold(
      appBar: AppBar(title: Text(isEn ? 'Your week' : '你嘅一個禮拜')),
      body: SafeArea(
        child: _busy
            ? AppLoadingIndicator(
                message: isEn
                    ? 'Pulling your week together…'
                    : '我整理緊你嘅一個禮拜…',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // P2 sanctioned diff #2: Arm B does not render the
                  // weekly narrative card at all (not even an empty
                  // placeholder — anything visible would leak the arm
                  // assignment).
                  if (Arm.isA(context)) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: _summary == null
                            ? AppLoadingIndicator.inline(
                                message: isEn
                                    ? 'Writing your summary…'
                                    : '寫緊你嘅週小結…',
                              )
                            : Text(
                                _summary!,
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(height: 1.5),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(isEn ? 'Mood (1–5)' : '心情（1-5）',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _BarChart(
                    values: _data?.moodScores ?? const [],
                    times: _data?.moodTimes ?? const [],
                  ),
                  const SizedBox(height: 20),
                  Text(isEn ? 'Counts' : '數量',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _CountTile(
                    label: isEn ? 'Check-ins' : 'Check-in',
                    value: _data?.moodScores.length ?? 0,
                  ),
                  _CountTile(
                    label: isEn ? 'Plans made' : '計劃咗',
                    value: _data?.plansAuthored ?? 0,
                  ),
                  _CountTile(
                    label:
                        isEn ? 'Plans followed up' : '跟進咗',
                    value: _data?.plansFollowedUp ?? 0,
                  ),
                  _CountTile(
                    label: isEn
                        ? 'Reminiscence sessions'
                        : '人生點滴',
                    value: _data?.reminiscenceSessions ?? 0,
                  ),
                ],
              ),
      ),
      ),
    );
  }
}

/// Minimal, accessible bar chart built with Containers so the elder-
/// friendly theme's font scaling applies and we don't pull in a chart
/// dependency for a 7-bar visual.
class _BarChart extends StatelessWidget {
  final List<int> values;

  /// Submission time per bar (same order as [values]); may be shorter /
  /// empty, in which case the date label is omitted for that bar.
  final List<DateTime> times;
  const _BarChart({required this.values, this.times = const []});

  /// "7/23 上午" style label so the user can tell WHEN each check-in
  /// happened — the bars alone read as anonymous numbers.
  String _whenLabel(DateTime t, bool isEn) {
    final String slot;
    if (t.hour < 12) {
      slot = isEn ? 'am' : '上午';
    } else if (t.hour < 18) {
      slot = isEn ? 'pm' : '下午';
    } else {
      slot = isEn ? 'eve' : '晚上';
    }
    return '${t.month}/${t.day}\n$slot';
  }

```
