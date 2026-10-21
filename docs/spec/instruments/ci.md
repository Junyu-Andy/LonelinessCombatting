# 继续使用意向 CI1–CI3 规格 v1.0

放在仓库 `docs/spec/instruments/ci.md`。对应任务 T35（W8 App 内问卷，决策 0036）。

状态（2026-10-21）：题目、指示和选项照「开发窗口交接 1021-W8」第三节逐字照抄（文书窗口 10/21 已与 W0、W4 问卷册逐字核对）。下面第 3 节的两张表由测试逐字读取：`test/w8_questionnaire_test.dart` 和 App 代码 `lib/features/w8/data/w8_items.dart` 比对，对不上测试就失败。研究侧要改字：先改这里，再改代码（两边不一致时测试会提醒）。

## 1. 用途

W8 第 4 部分「會唔會繼續用」（已批问卷包 Annex A.2，continuance intention）。两组都测，App 内自填，第 56 天开放。只在 W8 用。

## 2. 怎么显示

- 部分名「會唔會繼續用」，页顶「第 4 部分，共 5 部分」。
- 第 1 题上面显示指示：每句揀你有幾同意。
- 一屏一题，五个大按钮，按钮上连数字一起显示（如「1 非常不同意」）；「上一題」「跳過呢題」；三题之后「提交」。

## 3. 题目（粤语原文，照用，不要改写）

机器可读：编号列是存储用的题号。

| 编号 | 分量表 | 题目 |
| --- | --- | --- |
| q1 | total | 如果研究結束之後呢個 app 繼續開放，我會繼續用。 |
| q2 | total | 喺接落嚟嘅日子，我打算繼續用呢類陪伴功能。 |
| q3 | total | 將來如果有需要，我會再開呢個 app 嚟用。 |

选项（每题单选）：

| 存储值 | 显示 |
| --- | --- |
| 1 | 1 非常不同意 |
| 2 | 2 不同意 |
| 3 | 3 一半半 |
| 4 | 4 同意 |
| 5 | 5 非常同意 |

跳过的题存 `skipped`（缺失）。

## 4. 计分

服务器不计分，只存原值（1–5）。分析时按 SAP 处理（例如三题平均）。

## 5. 存储

- `users/{uid}/ci_responses/W8`，一份。App 写：`timepoint`、`bundle`（都是 `W8`）、`itemsVersion`、`answers`（题号 → 1–5 或 `skipped`）、`answeredAt`（题号 → 作答的服务器时间，每答一题写一次）、`status`（`in_progress` → `submitted`）、`startedAt`、`submittedAt`（服务器时间）和本机时间。
- 服务器写（`functions/w8_questionnaire.js`，规则不让 App 写）：`studyWeek`（8）、`studyDay`（56，W8 开放那天，和每周问卷同一口径）、`submittedStudyDay`（交的那天是第几天）、`outOfWindow`（第 63 天 23:59 之后交为 `true`）、`windowStart`、`windowEnd`、`acceptUntil`、`stampedAt`；有计分的另写 `scores`、`scoringVersion`、`scoredAt`。
- 第 70 天过后还没交：服务器写 `status: missed`、`missed: true`、`missedAt`。交了或缺失之后 App 不能再改，也不能删。
- 锁库前不按组给 Junyu；整人删除时随 `users/{uid}` 一起删（`tool/delete_participant.js`）；锁库后进分析导出（`tool/analysis_export.js` 的 `ci_responses` 表）。

## 6. 改动记录

| 日期 | 改动 | 题号、字段、计分 |
| --- | --- | --- |
| 2026-10-21 | 新建（T35，交接 1021-W8 第三节逐字）。 | 新建 |
