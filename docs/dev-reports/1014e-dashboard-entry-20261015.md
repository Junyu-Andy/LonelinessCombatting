# 1014e 第 2 节第 11 条：研究员登记页加「研究員儀錶板」入口（2026-10-15）

分支 `feat/dashboard-entry`，从 main `e6926df` 开。PR 草稿。依据：`docs/dev-tasks/dev-tasks-1014e.md` 第 2 节第 11 条（10/15 第 3 条 (1)，Junyu 同意）。只改 App 和文档。

## 结论

1. 登记页（`enrollment_page.dart`）右上角加「研究員儀錶板」按钮，打开原有的 `ResearcherDashboardPage`（T34 告警列表和「確認處理」、T30 全体合并完成率、T12 的各节）。和 T39 的「營運看板」按钮并排。
2. 只给 `unblinded`：登记页只有 `unblinded` 到得了（`StaffGate`：`blinded` 开评估员视图时去评估员页，否则进参与者 App），儀錶板页本身再查一次 claims，不是 `unblinded` 显示「冇權限」（T30 起 `blinded` 开评估员视图后也是「冇權限」）。
3. 没有加开关：这只是通往已有页面的链接，页面本身的各节各有自己的开关和角色检查；T43 核对清单里“PILOT 触发告警后確認處理”这一步，合并打包后就能在 App 里做。

## 改了什么

| 文件 | 改动 |
|---|---|
| `lib/features/enrollment/presentation/enrollment_page.dart` | AppBar 加 `enroll_researcher_dashboard` 按钮；测试钩子 `onOpenResearcherDashboard` |
| `test/enrollment_dashboard_entry_test.dart`（新） | 按钮存在、可打开；`blinded` 永远不会被路由到登记页 |
| 文档 | `architecture.md` 第 4 节角色表 `unblinded` 一行 + 顶部核对；`history.md`；`backlog.md` 第 111 项 ⑤；本报告 |

## 测试

`flutter test test/enrollment_dashboard_entry_test.dart test/ops_dashboard_test.dart`：10 项通过；`flutter analyze` 0 error；六套见 CI。

## 要 Junyu 定的事

无。

## 要带回研究侧的发现

1. 儀錶板里的「未處理嘅 distress flags」「對話審計隊列」「想法練習審計」「跨 agent 轉介」「PPR 總體分布」是 Phase A 时期的节，读的是旧集合，Phase B 数据可能为空或不准；T39 看板是 Phase B 的正式口径。要不要把这些旧节藏起来，等 Phase A 瘦身批次一起定。
