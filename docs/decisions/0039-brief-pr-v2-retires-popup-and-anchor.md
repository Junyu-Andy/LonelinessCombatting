# 0039：Brief PR 第二版只在开关开时生效；旧弹窗路径随开关关保留，"首次不能跳过"（anchor）规则在新版取消

- 日期：2026-10-14
- 状态：已采纳（负责人 2026-10-14 确认编号 0039；T25 已合并，PR #67；开关 `app_config/phase_b.sessionBriefPrV2Enabled` 默认关，打开即生效）
- 影响范围：phase_b、pilot × 两组
- 相关代码：`lib/core/session/session_rules.dart`、`lib/features/brief_pr/data/brief_pr_scheduler.dart`、`brief_pr_gate.dart`、`brief_pr_page.dart`

## 背景

Brief PR 原来在离开聊天页时弹窗，老人用户发言 ≥2 轮就弹；每位陪伴者第一次弹出没有「跳过」（anchor），以保证至少一份数据。产品窗口 10/8–10/10 定了新规则（C14、C16）：只在有效会话后、列表页出卡、每天一次、可跳过。

## 决定

1. 新规则全部在 `app_config/phase_b.sessionBriefPrV2Enabled` 后面。开关关着：旧弹窗路径（`BriefPrGate` / `BriefPrPage`）和 anchor 规则原样保留。开关打开：旧路径不再执行。
2. anchor 规则在新版里**取消**：每张卡都有「今次唔評」。理由：每天一次 + 卡片不打断聊天，已经把负担压到最低；强迫作答与“可随时拒绝”的伦理口径不一致，也会让第一份评分带有被迫的偏差。
3. 开关打开并稳定一周后，删除旧路径代码和 `sessions.briefPR` 子字段的写入（backlog 第 98 项）。
4. 新旧行用 `sessions.scheduleVersion`（1 / 2）、`brief_pr.schemaVersion`（2 / 3）区分，分析时按版本分别处理。

## 考虑过的其他方案

保留 anchor（第一次不能跳过）——被否，理由如上；新旧两套同时跑按人切换——被否，分析口径会乱。

## 后果

对研究：Methods 要写明 Brief PR 的触发条件从“≥2 轮、离页弹窗”改为“有效会话、列表页卡、每陪伴者每天 1 次”，以及生效日期；对开发：四个聊天页仍各自接一次结束流程（见第 13 节）。
