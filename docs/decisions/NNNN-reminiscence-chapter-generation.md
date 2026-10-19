# NNNN：Hybrid 组的小篇章由服务器生成：Pro 思考写稿、Flash 逐句核对、最多改两轮、仍无出处的句子删去；规则组不调模型

- 日期：2026-10-20
- 状态：提议中（开发窗口草稿，等 Junyu 定编号和报告第 11 节各点）
- 影响范围：pilot、phase_b × Hybrid 组（规则组只多导出和看板里的计数，不调模型）
- 相关代码：分支 `claude/zealous-fermat-8rgqtg-reminiscence-server`；`functions/reminiscence_chapter.js`、`functions/index.js` `onReminiscenceChapterWritten`、`functions/prompts/reminiscence_chapter_draft.v1.txt`、`functions/prompts/reminiscence_chapter_check.v1.txt`、`functions/prompts/ah_jan_ah_bak.v3.txt`、`firestore.rules`；报告 `docs/dev-reports/reminiscence-v2-server-20261020.md`

## 背景

1020d 第六节：老人每周答完 8 题后撳「完成今個禮拜」，得到一篇第一人称的「小篇章」。Hybrid 组由模型写，规则组由 App 把老人原话排版。1020d 指定 Hybrid 组用 `deepseek-v4-pro`（思考开）写、`deepseek-flash`（思考关）逐句核对、最多改 2 轮，2 轮后仍无出处或细节错的句子删去。老人可以离开 App，生成好再推送。决策 0017 之前只有 Flash（思考关）一种调用；这是研究里第一次用 Pro 和思考模式。

## 决定

1. **在服务器生成，用 Firestore 触发器**：App 写 `users/{uid}/reminiscence_chapters/week_{N}`（`source: 'hybrid'`、`status: 'requested'`、新的 `requestId`、整周对话 `input`），触发器 `onReminiscenceChapterWritten` 接手，写回 `status`、`finalText`、`version`、`flags`、`deletedSentences`、`generatedAt`、`failReason`。老人不用等在页面上。
2. **规则组不调模型**：`source: 'rule'` 的文档触发器一读都不读就返回。Hybrid 请求先查开关 `reminiscenceV2Enabled`（关 → `failed`／`disabled`），再重新读 `users/{uid}`，按 `assertLlmAllowed` 同一规则（规则组；登记门 + 测试员例外）并要求组别为 A；不合格 → `failed`／`not_hybrid`（或 `not_enrolled`），照 `proxyDeepSeek` 记 `llm_denied_log`，零调用。
3. **流程**：Pro 写初稿 → Flash 输出 `{"ok", "issues": [{type, quote, suggestion}]}`（7 类）→ 不合格交回 Pro 改，最多 2 轮 → 仍「无出处」「细节错」的句子按 `quote` 删去（去标点空白后包含、跨句、或字形近似），其余问题照交并写 `flags`。Flash 回坏 JSON 重问一次，仍坏当作不合格。
4. **试运行后加的三道保护**：(a) 「太口语」只认口语语法字；原句在引号外一个口语语法字都没有，代码剔走这一条（存档保留）。(b) 「太口语／太书面」交回 Pro 时不带 Flash 的改法。(c) Pro 交空稿（整篇留在思考里）自动重试，默认 2 次。
5. **同一个 `requestId` 只做一次**（事务 + `runs/{requestId}` 存档）；重新请求换新 `requestId`，`version` 加 1；生成中被新请求取代的只存档、不覆盖。
6. **存档**：每轮的稿、核对结果、模型、用时、token、提示词版本存 `runs/{requestId}`，客户端完全不能读写，整人删除时一起删。
7. **配置**：模型名、思考、轮数、重试、时间预算、推送开关和文字在 `meta/reminiscence_config`（只有服务器能读），代码有默认值。核对永远思考关。
8. **推送**：只 Hybrid 组，「你嘅第 N 章整理好喇，得閒入嚟睇下。」（草稿），安静时段和「今日休息」不推。
9. **规则**：`reminiscence_chapters` 单独一条规则，客户端只能写客户端字段，`status` 只能写 `requested`（Hybrid，新 `requestId`）或 `ready`（规则组）。
10. **数据**：小篇章元数据进过程数据导出和分析导出，不含正文；评分只进锁库后的分析导出；盲法导出不含这三个集合；运营看板每人一行加仍有标记和失败的篇数。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| App 调一个 callable 等结果 | Pro 思考一次 5–120 秒，改两轮更久；老人要一直开着页面，网络一断就白做 |
| 每轮存档放在小篇章文档的 `rounds` 字段 | 老人自己能读到草稿和核对意见；文档变大。改成服务器专用子集合 |
| 只靠 Flash 判语体 | 试运行里 Flash 把「屋企」「返學」「食」当毛病，两轮后把老人原话改成普通话，还因「食／吃」把一句有出处的话删了 |
| Pro 交空稿时改用思考关重写 | 等于换了 1020d 指定的写法；重试两次已足够（每次空稿只多 2 秒） |
| 核对失败就标失败、不交稿 | 1020d 说两轮后「照最后一版交出，后台标记」；现在照交，标「核对失败」，留给 Junyu 定 |
| 删句后再让 Pro 顺一顺 | 等于第 3 轮改写，超出 1020d 的上限 |

## 后果

- 对研究：Hybrid 组多了一样模型生成、老人会看到的东西，属于干预内容；规则组的小篇章不经模型，两组差别只在「谁来写」。登记表 C03 要加 `deepseek-v4-pro`（思考开）只用于小篇章写稿；protocol／HREC 的模型描述要补。研究的数据多了 `reminiscence_chapters`、评分和存档（存档有老人原话的改写稿，和对话同等保管）。评分是不是结局待定。
- 对开发：新模块和触发器、两份提示词、规则、导出和看板计数；App 那一半另一个窗口做。开开关前要先部署 Functions 和规则。
- 对论文：方法部分写明小篇章由 DeepSeek-V4-Pro（思考模式）写、DeepSeek-V4.1-Flash（非思考）核对、最多改两轮、无出处句删除；局限：模型核对不保证零错误，模型版本不能锁定。
