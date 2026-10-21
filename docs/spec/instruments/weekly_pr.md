# Weekly PR（每周关系感知，12 题）规格 v1.0

放在仓库 `docs/spec/instruments/weekly_pr.md`。

状态（2026-10-21）：仓库里原来没有这份规格，本文件由开发窗口照冻结构建的代码整理（`lib/features/weekly_pr/data/weekly_pr_response.dart` 的 `WeeklyPrItems`）。下面的题目表由测试 `test/weekly_pr_v3_1021_test.dart` 逐字读取，和代码对不上测试就会失败。研究侧核对后可以直接改这里，再改代码。

## 1. 用途

两组都测，每周一次，问老人对**这一周用得最多的那个伙伴**的感受（小欣、阿珍／阿伯或通通，自动选，记在 `referentRule`）。两组题目、选项、顺序规则完全相同。

## 2. 题目怎么显示

- 题目里的 `〈AGENT〉` 换成伙伴的名字（例如「小欣」），伙伴名和每题的关键字显示为粗体。
- 每题 7 个选项，1 到 7，左边写「唔同意」，右边写「同意」。
- `scaleDirectionCuesEnabled` 开着时（1020k）：9 题正向题打乱后分在第 1 页（5 题）和第 2 页（4 题），反向题 i1–i3 固定在第 3 页，页顶有提示句。
- 存在 `users/{uid}/weekly_pr/{自动编号}`，字段 `items` 是「题号 → 1–7」。

## 3. 题目（粤语原文，照用，不要改写）

机器可读：编号列是存储用的题号，分量表列是 `understanding`、`validation`、`caring` 或 `reverse`。

| 编号 | 分量表 | 题目 |
| --- | --- | --- |
| u1 | understanding | 呢個禮拜 〈AGENT〉 都明白我嘅感受。 |
| u2 | understanding | 呢個禮拜 〈AGENT〉 都明白我嘅想法。 |
| u3 | understanding | 呢個禮拜 〈AGENT〉 真係聽到我講嘅嘢。 |
| v1 | validation | 呢個禮拜 〈AGENT〉 尊重我嘅感受。 |
| v2 | validation | 呢個禮拜 〈AGENT〉 認可我講嘅嘢。 |
| v3 | validation | 呢個禮拜 〈AGENT〉 冇對我指指點點。 |
| c1 | caring | 呢個禮拜 〈AGENT〉 真心關心我。 |
| c2 | caring | 呢個禮拜 〈AGENT〉 為我著想。 |
| c3 | caring | 呢個禮拜 〈AGENT〉 嘅回應令我覺得舒服。 |
| i1 | reverse | 呢個禮拜 〈AGENT〉 嘅回應好似搞錯重點。 |
| i2 | reverse | 呢個禮拜 〈AGENT〉 好似唔在乎我講嘅嘢。 |
| i3 | reverse | 呢個禮拜 〈AGENT〉 嘅回應令我覺得唔舒服。 |

i1–i3 是反向题。计分方法本文件不改，照原计划。

## 4. 改动记录

| 日期 | 改动 | 题号、字段、计分 |
| --- | --- | --- |
| 2026-10-20 | （1020f）12 题开头「頭先」改为「呢個禮拜」：问整个星期，不是刚才那一次。 | 不变 |
| 2026-10-20 | （1020k）反向题 i1–i3 固定在第 3 页，页顶加提示句；开着开关时多存 `itemOrder`。 | 不变 |
| 2026-10-21 | （Junyu 10/21，冻结构建）v3「呢個禮拜 〈AGENT〉 冇判斷我。」改为「呢個禮拜 〈AGENT〉 冇對我指指點點。」，粗体关键字由「判斷」改为「指指點點」。u3「真係聽到我講嘅嘢」不改。两组相同。 | 不变 |
