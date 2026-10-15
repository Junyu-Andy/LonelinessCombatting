# 1014e 第 2 节第 4 条：取消告警后备收件人；第 1 节第 5 条的确认（2026-10-15）

分支 `fix/alert-no-backup`，从 main `e6926df` 开。PR 草稿。依据：`docs/dev-tasks/dev-tasks-1014e.md` 第 2 节第 4 条（10/14 第 11 条 (7)）、第 1 节第 5 条（没有后备时首发失败怎么办）。只用模拟器；没有改热线、IAM。

## 结论

1. **`backupEmail` 为空时 `escalateAlerts` 什么都不做**：原代码在没有后备时仍会“认领”到期的告警——写 `escalatedAt`、`escalationSkipped: no_backup_email`、每条一行审计日志，后台会显示「已轉後備」，其实谁也没收到。现在 `escalateDue` 读到空的 `backupEmail` 就直接返回（`skipped: no_backup_email`），告警保持 `escalationPending: true`，不写日志。代码没删，`meta/alert_config.backupEmail` 填上地址就恢复原来的 12 小时转后备。
2. **第 1 节第 5 条的确认**：首封邮件发不出去时（SMTP 出错 → `email_failed`；第一收件人被当评估员剔除或没配 → `no_recipients`），`onSafetyEventCreated` 会在 `pi_alerts` 行写 `primaryFailedAt` / `primaryFailedReason`，并写 `alert_audit_log`（10/14 修复 #73 已做）。本 PR 补的是**后台标出**：研究员后台「安全告警」列表对这些行显示「郵件未發出（發送出錯 / 冇收件人）— 冇人收到通知，請即處理」，確認處理后变「已確認處理」。没有后备时，这是唯一的第二条路，所以 Junyu 要定期看后台（或等 T41 每日汇总）。
3. **决策记录**：0038 第 1 条的“后备 Calvin Or、12 小时转后备”被取代。按规矩不改旧记录正文，只在 0038 状态行标“部分被取代”并指向本报告第 5 节的草稿；编号由开发窗口分配后落盘为 `docs/decisions/00NN-…md`。
4. 部署：合并后部署 Functions（`escalateAlerts`）；App 的后台标记随 10/19 构建。`meta/alert_config` 按 1014e 第 1 节第 5 条建：`enabled: true`、`primaryEmail` Junyu、不设 `backupEmail`。

## 改了什么

| 文件 | 改动 |
|---|---|
| `functions/pi_alert.js` | `escalateDue`：`backupEmail` 为空 → `skipped: "no_backup_email"`，直接返回；补 JSDoc |
| `lib/features/researcher_dashboard/presentation/widgets/safety_alerts_section.dart` | `SafetyAlertView` 加 `primaryFailedAt`、`primaryFailedReason`、`emailSentAt`；`stateLabel` 对首发失败的行显示「郵件未發出…請即處理」（已确认的仍显示已确认） |
| `functions/test/safety_alert_t34_emulator_test.js` | 新增 1 项：没有后备 → 不动、不发、不记日志，首发失败的标记保留；填上后备后两条都转出 |
| `test/safety_alert_t34_test.dart` | 新增 1 项：三种状态的文字 |
| `docs/decisions/0038-…md` | 状态行标“部分被取代（2026-10-15）” |
| 文档 | `STUDY_CHANGELOG.md` 一行；`architecture.md` 第 9 节 `escalateAlerts` 行、第 10 节通知一条 + 顶部核对；`history.md`；本报告 |

## 测试

| 测试 | 结果 |
|---|---|
| `node functions/test/pi_alert_test.js` | 通过 |
| `safety_alert_t34_emulator_test.js` | 17/17（含新项） |
| `flutter test test/safety_alert_t34_test.dart` | 8/8 |
| `tool/ci_backend_tests.sh` | 见 PR |
| ESLint（`pi_alert.js`、测试） | 0 问题 |

## 5. 决策记录草稿（编号待开发窗口分配）

**NNNN：安全告警不设后备收件人；发不出去的告警只在后台标出（取代 0038 第 1 条的后备和 12 小时转后备）**

- 日期：2026-10-15；状态：提议中；影响范围：所有 cohort × 两组（告警流程）；相关代码：PR `fix/alert-no-backup`。
- 背景：0038 定第一收件人 Junyu、后备 Calvin Or、12 小时没人确认转后备。负责人 10/14 第 11 条 (7) 决定不设后备（Calvin 不处理告警；后备邮件带来源字段的盲法问题 backlog 92 也随之消失）。
- 决定：`meta/alert_config` 不填 `backupEmail`；为空时 `escalateAlerts` 什么都不做；首封邮件发不出去的告警写 `alert_audit_log` 并在研究员后台标出，由 Junyu 处理；代码保留，填上地址即恢复后备。
- 考虑过的其他方案：① 删掉转后备代码——以后要恢复要重写，不如留着；② 没有后备时把告警再发一次给第一收件人——同一个邮箱收两封没有意义，SMTP 出错时也发不出。
- 后果：对研究，protocol 安全监测一节改为“单收件人 + 后台标记 + T41 每日汇总”；对开发，T41 每日汇总邮件应把 `primaryFailedAt` 的告警列在最前；对论文，无。

## 要 Junyu 定的事

1. 决策草稿的编号。

## 要带回研究侧的发现

1. 没有后备后，SMTP 出错那一刻没有任何人会收到邮件；告警只在后台列表里。建议 T41 每日汇总把“郵件未發出”的告警放最前，并在上线清单写明 Junyu 每天看一次后台。
2. `backlog 92`（后备收件人是否保持盲）随取消后备不再需要，可以关掉。
