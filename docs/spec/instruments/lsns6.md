# LSNS-6（Lubben 社交网络量表六题版）规格 v1.0

放在仓库 `docs/spec/instruments/lsns6.md`。对应任务 T35（W8 App 内问卷，决策 0036）。

状态（2026-10-21）：题目、指示和选项照「开发窗口交接 1021-W8」第三节逐字照抄（文书窗口 10/21 已与 W0、W4 问卷册逐字核对）。下面第 3 节的两张表由测试逐字读取：`test/w8_questionnaire_test.dart` 和 App 代码 `lib/features/w8/data/w8_items.dart` 比对，对不上测试就失败。研究侧要改字：先改这里，再改代码（两边不一致时测试会提醒）。

## 1. 用途

W8 第 5 部分「身邊嘅親人同朋友」（decisions-log 10/15 第 9 条）。两组都测，App 内自填，第 56 天开放。只在 W8 用。

## 2. 怎么显示

- 部分名「身邊嘅親人同朋友」，页顶「第 5 部分，共 5 部分」。
- 第 1 题上面先显示指示：以下六條問題問你身邊有幾多親戚同朋友，每條揀一個數目。
- 第 1 题题目上面显示引导句（App 用口语版，decisions-log 10/21 第 127 条 (4)）：先講親人，即係同你有血緣、婚姻或者收養關係嘅人。
- 第 4 题题目上面显示引导句：跟住講朋友，包括住喺你附近嘅朋友。
- 一屏一题，六个大按钮；「上一題」「跳過呢題」；六题之后「提交」。

## 3. 题目（粤语原文，照用，不要改写）

机器可读：编号列是存储用的题号。

| 编号 | 分量表 | 题目 |
| --- | --- | --- |
| q1 | family | 你有幾多個親人，係你每個月起碼見一次面、或者傾一次電話／訊息嘅？ |
| q2 | family | 你有幾多個親人，係你可以放心同佢講私人嘢嘅？ |
| q3 | family | 你有幾多個親人，係你覺得好親近、有事可以搵佢幫手嘅？ |
| q4 | friends | 你有幾多個朋友，係你每個月起碼見一次面、或者傾一次電話／訊息嘅？ |
| q5 | friends | 你有幾多個朋友，係你可以放心同佢講私人嘢嘅？ |
| q6 | friends | 你有幾多個朋友，係你覺得好親近、有事可以搵佢幫手嘅？ |

选项（每题单选）：

| 存储值 | 显示 |
| --- | --- |
| 0 | 沒有 |
| 1 | 一個 |
| 2 | 兩個 |
| 3 | 三至四個 |
| 4 | 五至八個 |
| 5 | 九個或以上 |

跳过的题存 `skipped`（缺失）。

## 4. 计分

服务器算（App 不算）：亲人分 = q1–q3 之和（0–15），朋友分 = q4–q6 之和（0–15），总分 = 两者之和（0–30），分数越高社交网络越大；一个分量表里有任一题跳过，这个分量表和总分为 `null`。存 `scores.family`、`scores.friends`、`scores.total`，`scoringVersion: lsns6_v1`。

## 5. 存储

- `users/{uid}/lsns6_responses/W8`，一份。App 写：`timepoint`、`bundle`（都是 `W8`）、`itemsVersion`、`answers`（题号 → 0–5 或 `skipped`）、`answeredAt`（题号 → 作答的服务器时间，每答一题写一次）、`status`（`in_progress` → `submitted`）、`startedAt`、`submittedAt`（服务器时间）和本机时间。
- 服务器写（`functions/w8_questionnaire.js`，规则不让 App 写）：`studyWeek`（8）、`studyDay`（56，W8 开放那天，和每周问卷同一口径）、`submittedStudyDay`（交的那天是第几天）、`outOfWindow`（第 63 天 23:59 之后交为 `true`）、`windowStart`、`windowEnd`、`acceptUntil`、`stampedAt`；有计分的另写 `scores`、`scoringVersion`、`scoredAt`。
- 第 70 天过后还没交：服务器写 `status: missed`、`missed: true`、`missedAt`。交了或缺失之后 App 不能再改，也不能删。
- 锁库前不按组给 Junyu；整人删除时随 `users/{uid}` 一起删（`tool/delete_participant.js`）；锁库后进分析导出（`tool/analysis_export.js` 的 `lsns6_responses` 表）。

## 6. 改动记录

| 日期 | 改动 | 题号、字段、计分 |
| --- | --- | --- |
| 2026-10-21 | 新建（T35，交接 1021-W8 第三节逐字）。 | 新建 |
