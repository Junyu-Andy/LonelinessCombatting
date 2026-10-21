# DJG-ES（De Jong Gierveld 孤独感量表，6 题）规格 v1.0

放在仓库 `docs/spec/instruments/djg_es.md`。对应任务 T30（评估员纸本录入）和 T18（App 内 W2），`SPEC:C19`、`C20`。

状态（2026-10-14）：题目和选项照已批问卷包 §3，和 App 内 W2 的代码（`lib/features/assessment/data/djg_w2.dart`、`functions/djg_w2.js`）逐字一致。本文件由开发窗口从代码整理，研究侧核对后可直接改这里；代码里的题目和选项有逐字比对测试（`functions/test/outcome_instruments_test.js`、`test/assessor_view_test.dart`），改了文件测试会提醒改代码。

## 1. 用途

主要结局。Phase B 两组都测：W0 纸本（研究员录入情感分用于分层，T19）、W2 App 内（T18）、W4 纸本由独立评估员施测后录入（T30）、W8 App 内（T35）。

## 2. 施测时间

| 时间点 | 方式 | 窗口（W0 = 第 0 天） | 谁录入 |
| --- | --- | --- | --- |
| W0 | 纸本 | 登记当天 | 非盲研究员在登记页只录情感分（0–3） |
| W2 | App 内 | 第 14–20 天 | 老人自填（T18） |
| W4 | 纸本 | 第 25–31 天 | 评估员（`blinded`）在评估员视图录入；超窗照样可录，记 `outOfWindow: true` |
| W8 | App 内 | 第 56–63 天（第 64–70 天仍收，记 `outOfWindow: true`；2026-10-21 交接 1021-W8） | 老人自填（T35，决策 0036） |

## 3. 题目与选项（粤语原文，照用，不要改写）

机器可读：下面的表由代码测试逐字读取。编号列是存储用的 id，分量表列只能是 `emotional` 或 `social`。

| 编号 | 分量表 | 题目 |
| --- | --- | --- |
| q1 | emotional | 我有一種空虛的感覺。 |
| q2 | emotional | 我想念身邊有人陪伴。 |
| q3 | emotional | 我經常覺得自己被人排斥。 |
| q4 | social | 當我遇到問題時，有許多人可以倚靠。 |
| q5 | social | 我有許多可以完全信任的人。 |
| q6 | social | 有足夠多我感到親近的人。 |

选项（每题单选）：

| 存储值 | 显示 |
| --- | --- |
| yes | 是 |
| mostly | 大致是 |
| no | 不是 |

缺答存 `skipped`。

## 4. 计分（服务器算，评估员看不到分数）

- 情感分量表（q1–q3）：答「是」或「大致是」得 1 分，「不是」0 分；0–3 分。
- 社交分量表（q4–q6）：答「大致是」或「不是」得 1 分，「是」0 分；0–3 分。
- 任一题缺答，该分量表不算分（`null`）；总分 = 两个分量表之和，缺一个就不算。
- 计分版本号 `djg6_v1`（`functions/outcome_instruments.js`、`functions/djg_w2.js` 同一规则）。

## 5. 存储

- W2、W8：`users/{uid}/djg_responses/{W2|W8}`（T18、T35 的格式）。W8 另存每题作答的服务器时间 `answeredAt`（题号 → 时间），服务器写 `studyWeek`（8）、`studyDay`、`submittedStudyDay`、`outOfWindow`；第 4 题上面一直显示过渡句「跟住三句講你身邊嘅人。」（W1–W3 只在 `scaleDirectionCuesEnabled` 开时显示）。题目、选项、计分和 W1–W3 一样（`docs/spec/copy/w8-questionnaire.md`）。
- W4 纸本：`outcome_entries/{自动编号}`（只有服务器能读写，T30）。字段：研究编号、`uid`（只给服务器做删除和合并用）、`instrument: "DJG-ES"`、`instrumentVersion`、`timepoint: "W4"`、施测日期 `assessmentDate`、施测方式 `mode`（`in_person` 當面 / `phone` 電話 / `video` 視像）、评估员 `assessorUid`、`assessorEmail`、录入时间 `enteredAt`、每题原始值 `answers`、缺答的题 `missingItems`、分数 `scores`、`scoringVersion`、窗口 `windowStartDate`、`windowEndDate`、`studyDay`、`outOfWindow`、`status: "submitted"`、更正标记 `correctedAt`。提交后评估员不能改；更正只能用 `tool/correct_outcome_entry.js`（写理由，记 `outcome_entry_corrections`）。

## 6. 规格文件格式（给以后的纸本问卷）

其余纸本问卷（例如 PHQ-9）由研究侧按本文件的格式交 `docs/spec/instruments/<问卷>.md`：

1. 第 3 节一张「编号 | 分量表 | 题目」表，编号用 `q1`、`q2`…，没有分量表就填 `total`；
2. 一张「存储值 | 显示」选项表；缺答的存储值写明；
3. 第 4 节计分规则（哪一端得分、缺答怎样处理）；
4. 第 2 节窗口（第几天到第几天）。

开发侧照抄进 `functions/outcome_instruments.js` 和 App 的题目常量，并加逐字比对测试；文件到了只加内容，不改代码结构。
