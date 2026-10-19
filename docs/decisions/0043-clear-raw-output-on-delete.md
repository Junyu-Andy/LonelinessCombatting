# 0043：删一条记忆时，服务器上那次整理的模型原文也清掉

- 日期：2026-10-18
- 状态：提议中（草稿，编号待定；T49e-4，PR 草稿）。**补充决策 0024 第 4 条「删除要一致」**，不取代 0024
- 影响范围：phase_b、pilot × Hybrid 组（记忆 v1 用户）。规则组没有记忆，不受影响
- 相关代码：分支 `fix/t49e4-raw-output`（`functions/memory.js` `clearRawOutputs`、`deleteSummaryForItem`、`forgetRelated`、`clearRawOutputForSummary`；`functions/index.js` `memorySummaryDeleted`）

## 背景

服务器每整理一次对话，都把模型输出的整段 JSON 存在 `users/{uid}/mem_extractions/{会话编号}.raw_output`（最多 2 万字），方便排查整理失败。决策 0024 第 4 条要求删除一致：老人删一条，摘要和同样措辞的条目一起删。但 `raw_output` 没有跟着清，老人删掉的内容在服务器审计记录里还留着原文（记忆机制核对报告 `memory-mechanism-20261018.md` 第 6 节、第 10 节第 3 条）。Junyu 10/18 晚定：删条目时一并清（任务单 1018 §E4）。

## 决定

1. **三种删除都清**：
   - 页面删一条事实或待跟进（触发器 `memoryFactDeleted`／`memoryFollowupDeleted` → `deleteSummaryForItem`）：清这条来源会话的 `raw_output`；连带删掉的摘要、同样措辞的条目，各自来源会话的也清。
   - 页面删一条摘要（新触发器 `memorySummaryDeleted`）：只清同编号那次整理的 `raw_output`（摘要编号＝整理编号），**不连带删别的**。
   - 老人说「唔好記住」（`forgetRelated`）：被删的旧条目来源会话的 `raw_output` 清掉。这次会话本身没有调模型，本来就没有 `raw_output`。
2. **怎么清**：`raw_output` 改成固定字符串 `[cleared after deletion 2026-10-18]`，另写 `raw_output_cleared_at`。整段清，不只遮蔽被删那一句（同一次整理里没删的条目，原文本来就还在 `mem_facts` 等集合里，页面看得到、能删）。
3. **保留**：`status`、`attempts`、`prompt_version`、`counts`、`dropped`、`finished_at`、`excluded_safety_turns` 不动。研究上要的「哪天整理、整理出几条、用哪个版本」都还在。
4. **不改保存逻辑**：整理时照旧存 `raw_output`，供失败排查。
5. **开关**：`meta/memory_config.clearRawOutputOnDelete`，和 0024 其他修复开关一样**默认开，只认 `false` 关**（它只删数据，不加行为）。和 `deleteSummaryWithItem` 互相独立：后者关了，删一条仍会清它自己那次整理的原文。
6. `tool/delete_memory.js`（整人退出）本来就整个删 `mem_extractions`，不用改。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 只把被删那一句从原文里遮掉 | 模型原文是 JSON，同一件事可能出现在摘要、事实、引文几处，措辞也不完全一样，遮不干净；整段清最稳妥 |
| 整理成功后马上清 `raw_output` | 任务要求保留供排查；成功的那次也可能事后发现抽错，要看原文 |
| 删整份 `mem_extractions` 文档 | 审计字段（时间、条数、版本）会一起没了，研究要用 |
| 接受现状，写进 ICF／数据管理计划 | Junyu 10/18 定修 |

## 后果

- 对研究：研究侧 B09 写一句：「删除一条记忆时，服务器上该次整理的模型原始输出同时清除；整理时间、条数和版本等审计信息保留。」参与者看不到任何变化，不算干预改动；STUDY_CHANGELOG 已记。部署前已经删掉的条目，原文还在（见 T49e-4 报告「要定的事」）。
- 对开发：新增触发器 `memorySummaryDeleted`，部署 Functions 才生效。测试在 `functions/test/memory_emulator_test.js`（T49e-4 四条）。
- 对论文：数据管理部分可写「删除时同步清除服务器上的模型原始输出」，不需要加局限。
