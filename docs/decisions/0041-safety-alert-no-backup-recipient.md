# 0041：安全告警不设后备收件人；发不出去的告警只在后台标出（取代 0038 第 1 条的后备和 12 小时转后备）

- 日期：2026-10-15
- 状态：已采纳（负责人 10/14 第 11 条 (7) 定；10/15 确认编号 0041；代码 PR #86 已合并）
- 影响范围：所有 cohort × 两组（告警流程，老人感受不到）
- 相关代码：PR #86（`fix/alert-no-backup`）：`functions/pi_alert.js` `escalateDue`、`lib/features/researcher_dashboard/presentation/widgets/safety_alerts_section.dart`
- 取代：决策 0038 第 1 条里的「后备 Calvin Or」和「12 小时没人确认转后备」。0038 其余部分不变。

## 背景

0038 定第一收件人 Junyu、后备 Calvin Or、12 小时没人确认转后备。负责人 10/14 决定不设后备：Calvin 不处理告警；后备邮件带来源字段的盲法问题（backlog 92）也随之消失。

## 决定

- `meta/alert_config` 不填 `backupEmail`。
- `backupEmail` 为空时 `escalateAlerts` 什么都不做（记 `skipped: no_backup_email`）。
- 首封邮件发不出去的告警写 `alert_audit_log`，研究员后台的告警列表标红「郵件未發出 — 冇人收到通知，請即處理」，由 Junyu 处理。
- 代码保留，以后填上 `backupEmail` 即恢复后备。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 删掉转后备代码 | 以后要恢复要重写，不如留着 |
| 没有后备时再发一次给第一收件人 | 同一个邮箱收两封没有意义；SMTP 出错时也发不出 |

## 后果

- 对研究：protocol 安全监测一节改为「单收件人 + 后台标记 + T41 每日汇总」。
- 对开发：T41 每日汇总邮件应把 `primaryFailedAt` 的告警列在最前。
- 对论文：无。
