# 0062：反向题前加一行过渡句；Weekly PR 反向三题固定放第三页

- 日期：2026-10-20
- 状态：提议中（文字和做法 Junyu 已定：decisions-log 10/20 第 77 至 79 条，交接 1020k）
- 影响范围：phase_b、pilot × 两组（同一页、同一句、同一排法）；开关打开后打开的问卷
- 相关代码：分支 `claude/zealous-fermat-8rgqtg-scale-cues`；`lib/core/survey/direction_cue.dart`、`lib/features/weekly_pr/data/weekly_pr_layout.dart`、`weekly_pr_page.dart`、`brief_pr_flow_page.dart`、`brief_pr_page.dart`、`djg_w2_page.dart`、`lib/core/feature_flags/remote_feature_flags.dart`

## 背景

Maria 测试时发现：一串同方向的题里夹一题方向相反的，老人容易答反。App 里有三处：Brief PR 第 4 题（唔舒服，反向）、Weekly PR 的 i1 至 i3（反向，原来和其他九题混在一起随机）、DJG-ES 第 4 题（从「孤单」转到「身边的人」）。

## 决定

1. 新开关 `app_config/feature_flags.scaleDirectionCuesEnabled`（**默认关**，只认布尔 `true`）。关着时一切照旧。
2. 开着时：
   - Brief PR 第 4 题（一题一屏的 v2 和旧弹窗版都加）：页顶「今次傾偈：〈陪伴者〉」和题目之间加一行「最後一題反過嚟問：佢有冇令你**唔舒服**？」。前三题不加。
   - Weekly PR：正向九题（u、v、c）随机排在第 1、2 页（第 1 页 5 题，第 2 页 4 题）；反向三题（i1 至 i3）固定在第 3 页，三题之间随机。第 3 页页顶加一行「呢一頁三句講**唔好**嘅感覺，同意即係有呢種感覺。」。
   - App 内 DJG-ES（W1 至 W3 每周问卷第一部分、W8 同一页）第 4 题题干上方加一行「跟住三句講你身邊嘅人。」，不加粗。其他题不加。
3. 字号同问卷正文（18）；加粗的字用 App 的强调色（陶土色），底下一层浅色底，不用红色。
4. 题目原文、选项、字段名、存储和计分都不改。Weekly PR 记录多一个字段 `itemOrder`（这次显示的题号顺序，第 1 页到第 3 页从上到下）；只在开关开时写，所以有这个字段就代表是新排法。
5. 纸本不改。旧的一页六题 DJG 页（Phase A，Phase B 不出现）不改。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 不加开关，直接改 | 共同规则 (3)：新行为放在开关后，出问题可以关回去 |
| 反向题改成正向写法 | 改了题目原文，和已批问卷包不一致 |
| 第 1、2 页各 4 题，余下一题放第 3 页 | 交接要求第 3 页只放反向三题 |
| 记录每页几题（第二个字段） | 交接只要一个字段；新排法固定 5、4、3，有 `itemOrder` 就知道 |

## 后果

- 对研究：两组完全一样，不影响组间对等；不调用 LLM。显示改动，题目和计分不变；分析时可用 `itemOrder` 核对第 3 页。开关打开日期要写进 STUDY_CHANGELOG（打开前后的 Weekly PR 排法不同）。
- 对开发：新开关一个、新组件一个、Weekly PR 排页函数一个、记录字段一个；测试 `test/scale_direction_cues_1020k_test.dart`（含 Weekly PR 跑十次），截图 `test_manual/scale_direction_cues_shots_1020k_test.dart`。`itemOrder` 暂不进导出（见 backlog）。
- 对论文：方法部分可写一句「反向题前有一句提示，Weekly PR 反向题集中在最后一页」。
