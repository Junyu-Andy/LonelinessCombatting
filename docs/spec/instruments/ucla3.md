# UCLA-3（三题孤独感量表）规格 v1.0

放在仓库 `docs/spec/instruments/ucla3.md`。对应任务 T35（W8 App 内问卷，决策 0036）。

状态（2026-10-21）：题目、指示和选项照「开发窗口交接 1021-W8」第三节逐字照抄（文书窗口 10/21 已与 W0、W4 问卷册逐字核对）。下面第 3 节的两张表由测试逐字读取：`test/w8_questionnaire_test.dart` 和 App 代码 `lib/features/w8/data/w8_items.dart` 比对，对不上测试就失败。研究侧要改字：先改这里，再改代码（两边不一致时测试会提醒）。

## 1. 用途

W8 第 2 部分「孤單嘅感覺」。两组都测，App 内自填，第 56 天开放（第 63 天 23:59 关，第 70 天前仍收、记超窗）。只在 W8 用。

## 2. 怎么显示

- 部分名「孤單嘅感覺」，页顶「第 2 部分，共 5 部分」。
- 第 1 题上面显示指示：以下三條問題，請揀很少、有時、定係經常。
- 一屏一题，三个大按钮；「上一題」「跳過呢題」；三题之后「提交」。

## 3. 题目（粤语原文，照用，不要改写）

机器可读：编号列是存储用的题号。

| 编号 | 分量表 | 题目 |
| --- | --- | --- |
| q1 | total | 你多常感到缺乏陪伴？ |
| q2 | total | 你多常感到被冷落、被排除在外？ |
| q3 | total | 你多常感到與他人疏離、孤立？ |

选项（每题单选）：

| 存储值 | 显示 |
| --- | --- |
| 1 | 很少 |
| 2 | 有時 |
| 3 | 經常 |

跳过的题存 `skipped`（缺失）。

## 4. 计分

服务器算（App 不算）：总分 = 三题之和，3–9 分，分数越高越孤独；任一题跳过，总分为 `null`。存 `scores.total`，`scoringVersion: ucla3_v1`。分析时也可以从原值重算。

## 5. 存储

- `users/{uid}/ucla3_responses/W8`，一份。App 写：`timepoint`、`bundle`（都是 `W8`）、`itemsVersion`、`answers`（题号 → 1–3 或 `skipped`）、`answeredAt`（题号 → 作答的服务器时间，每答一题写一次）、`status`（`in_progress` → `submitted`）、`startedAt`、`submittedAt`（服务器时间）和本机时间。
- 服务器写（`functions/w8_questionnaire.js`，规则不让 App 写）：`studyWeek`（8）、`studyDay`（56，W8 开放那天，和每周问卷同一口径）、`submittedStudyDay`（交的那天是第几天）、`outOfWindow`（第 63 天 23:59 之后交为 `true`）、`windowStart`、`windowEnd`、`acceptUntil`、`stampedAt`；有计分的另写 `scores`、`scoringVersion`、`scoredAt`。
- 第 70 天过后还没交：服务器写 `status: missed`、`missed: true`、`missedAt`。交了或缺失之后 App 不能再改，也不能删。
- 锁库前不按组给 Junyu；整人删除时随 `users/{uid}` 一起删（`tool/delete_participant.js`）；锁库后进分析导出（`tool/analysis_export.js` 的 `ucla3_responses` 表）。

## 6. 改动记录

| 日期 | 改动 | 题号、字段、计分 |
| --- | --- | --- |
| 2026-10-21 | 新建（T35，交接 1021-W8 第三节逐字）。 | 新建 |
