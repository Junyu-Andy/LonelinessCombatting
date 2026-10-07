# 0018：所有自由输入走同一个安全检测入口；AI 回复里不出现任何电话号码

- 日期：2026-10-07
- 状态：提议中（随 T7 PR 合并后采纳）
- 影响范围：所有 cohort × 两组（检测入口、事件记录）；所有 cohort × Hybrid 组（热线过滤）
- 相关代码：分支 `fix/safety-hardening`（T7，SPEC C12）

## 背景

T6 报告发现三件事：
- 有几处自由输入（Thought Exercise、入组开放题、陪伴者比较页、「其他」反馈框、规则组行动计划）两组都不做安全检测；
- 7 处 AI 调用没带用户编号，安全事件被数据库拒收；同一轮对话的输入和 AI 回复各写一条事件；
- Hybrid 组的 AI 会自己写热线号码，60 次里 2 次机构和号码配错。

研究侧已定：所有自由输入两组都检测；禁止 AI 自写热线（任务单 T7）。

## 决定

1. **一个入口**：`lib/core/safety/safety_check.dart` 的 `SafetyService`，两组共用。
   - `detect`：只检测，不写、不弹页面；
   - `checkUserText`：检测，中度以上写一条 `safety_events`；
   - `checkAndRoute`：再加上弹危机页（acute）或支援面板（moderate_interrupt），给表单页用；
   - 通知 PI 仍由服务器 `onSafetyEventCreated` 负责（acute）。
2. **事件记录**：每条 `safety_events` 都有 `source`（`user_input` / `ai_output_scan` / `form`）、`inputPoint`（哪个输入框）、`turnId`。一轮对话只算一条：AI 回复的扫描只在级别高于输入时才写，服务器按 `turnId` 去重（键里不再含 `source`），重复的标 `isDuplicate`，并把主事件升到这一轮的最高级别。
3. **热线过滤（只 Hybrid 组）**：
   - prompt 末尾加一条规则（`functions/prompts/hotline_rule.v1.txt`）：不写号码，在该放号码的地方写「【緊急熱線】」；
   - `proxyDeepSeek` 返回前把所有电话号码换成「【緊急熱線】」，App 再过一遍；
   - App 把「【緊急熱線】」显示成链接，文字用现有的「緊急熱線」，点开是现有的危机页；
   - 每次替换在 `hotline_filter_log` 记一条，不存原文和号码。
4. **开关**（默认都开，可以关）：
   - App：`app_config/phase_a` 的 `safetyScanAllInputs`、`hotlineFilterClient`；
   - 服务器：`meta/safety_config` 的 `hotlinePromptRule`、`hotlineOutputFilter`。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 只在 prompt 里禁止，不做过滤 | 模型不一定照做；T6 里它已经在不该写的时候写了 |
| 只在 App 端过滤 | 旧版本 App 不会过滤；服务器是唯一一定经过的地方 |
| 把号码换成批准清单里的号码 | 要判断 AI 想指哪个机构，容易配错，正是 T6 发现的问题 |
| 服务器删除同一轮的第二条事件 | 删除不能撤回；标 `isDuplicate` 保留审计 |
| 服务器上再放一份词库，检查搜索词 | 两份词库会走样；搜索词在 App 端先过统一入口 |

## 后果

- 对研究：
  - 两组的检测覆盖现在一致（输入点见 T7 报告的表）；规则组仍没有「AI 回复扫描」这一层（规则组没有 AI 回复）。
  - 分析安全事件时只数 `isDuplicate == false`，按 `source` 分开；`ai_output_scan` 只会出现在 Hybrid 组。
  - `hotline_filter_log` 只有 Hybrid 组有，原样导出等于揭盲（与 `llm_calls` 相同）。
  - prompt 多了一条规则，要请 PI 审核；`promptVersion` 变成 `siu_yan_v1@2026-06+hotline_rule.v1` 这样。
  - DMP / ICF 如果写「所有输入都会做安全检测」，现在属实（词库层面）。
- 对开发：T8（分类器槽位）、T10（记忆）、T15（规则组模板回应）都调用这个入口。
- 对论文：安全监测一节写明「所有自由文字输入两组都经同一词库检测；Hybrid 组 AI 回复中的电话号码一律替换为危机页入口」。
