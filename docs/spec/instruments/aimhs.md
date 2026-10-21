# AIMHS（对 AI 倾偈助手的看法，5 题）规格 v1.0

放在仓库 `docs/spec/instruments/aimhs.md`。对应任务 T35（W8 App 内问卷，决策 0036）。

状态（2026-10-21）：题目、指示和选项照「开发窗口交接 1021-W8」第三节逐字照抄（文书窗口 10/21 已与 W0、W4 问卷册逐字核对）。下面第 3 节的两张表由测试逐字读取：`test/w8_questionnaire_test.dart` 和 App 代码 `lib/features/w8/data/w8_items.dart` 比对，对不上测试就失败。研究侧要改字：先改这里，再改代码（两边不一致时测试会提醒）。

## 1. 用途

W8 完成五部分之后的可选短问卷（已批量表）。两组相同，题目讲一般的 AI 倾偈助手，W0、W4 纸本是同一套字，不透露版本。可以整份不填：不填不算 W8 未完成。

## 2. 怎么显示

- 五部分做完后，完成页显示「全部做完喇，多謝你！仲有一份可以選擇唔填嘅短問卷。」和两个按钮「填呢份」「唔填喇」。
- 「填呢份」：打开这份问卷，页名「對傾偈助手嘅睇法」（没有「第 N 部分」）。第 1 题上面显示开头：以下五句話係講 AI 傾偈助手，即係可以同人傾偈嘅電腦程式。每句請揀你有幾同意。
- 一屏一题，五个大按钮（连数字显示）；「上一題」「跳過呢題」；五题之后「提交」。
- 「唔填喇」：记 `status: declined`（参与者跳过），回首页。

## 3. 题目（粤语原文，照用，不要改写）

机器可读：编号列是存储用的题号。

| 编号 | 分量表 | 题目 |
| --- | --- | --- |
| q1 | total | 喺「明白同體諒人嘅感受」呢方面，AI 傾偈助手做唔到好似真人輔導員咁。 |
| q2 | total | 喺解決問題嘅能力上面，AI 傾偈助手可以叻過真人輔導員。 |
| q3 | total | AI 傾偈助手可以減少地域上嘅限制，令更多人得到情緒支援。 |
| q4 | total | AI 傾偈助手可以全日二十四小時都用到，令更多人得到情緒支援。 |
| q5 | total | AI 傾偈助手收費較低，可以減少經濟負擔，令更多人得到情緒支援。 |

选项（每题单选）：

| 存储值 | 显示 |
| --- | --- |
| 1 | 1 非常不同意 |
| 2 | 2 不同意 |
| 3 | 3 一半半 |
| 4 | 4 同意 |
| 5 | 5 非常同意 |

跳过的题存 `skipped`（缺失）。整份不填存 `status: declined`、`declinedAt`（服务器时间）；开始了但没交的留 `in_progress`，第 70 天后也不记缺失（可选问卷）。

## 4. 计分

服务器不计分，只存原值（1–5）。第 1 题是反向题，**只在分析时反向**，App 和服务器都不反向（交接 1021-W8 第四节 (1)）。

## 5. 存储

- `users/{uid}/aimhs_responses/W8`，一份。App 写：`timepoint`、`bundle`（都是 `W8`）、`itemsVersion`、`answers`（题号 → 1–5 或 `skipped`）、`answeredAt`（题号 → 作答的服务器时间，每答一题写一次）、`status`（`in_progress` → `submitted`，或 `declined`）、`startedAt`、`submittedAt`（服务器时间）和本机时间。
- 服务器写（`functions/w8_questionnaire.js`，规则不让 App 写）：`studyWeek`（8）、`studyDay`（56，W8 开放那天，和每周问卷同一口径）、`submittedStudyDay`（交的那天是第几天）、`outOfWindow`（第 63 天 23:59 之后交为 `true`）、`windowStart`、`windowEnd`、`acceptUntil`、`stampedAt`；有计分的另写 `scores`、`scoringVersion`、`scoredAt`。
- 可选问卷：第 70 天过后不记缺失。`status` 是 `submitted`（填了）、`declined`（「唔填喇」，参与者跳过）、`in_progress`（开始了没交）或没有这份记录（完成页没有选就离开）。交了或「唔填喇」之后 App 不能再改，也不能删。
- 锁库前不按组给 Junyu；整人删除时随 `users/{uid}` 一起删（`tool/delete_participant.js`）；锁库后进分析导出（`tool/analysis_export.js` 的 `aimhs_responses` 表）。

## 6. 改动记录

| 日期 | 改动 | 题号、字段、计分 |
| --- | --- | --- |
| 2026-10-21 | 新建（T35，交接 1021-W8 第三节逐字）。 | 新建 |
