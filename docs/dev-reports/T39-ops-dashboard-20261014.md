# T39 运营看板「每人」页 报告（2026-10-14）

分支 `feat/ops-dashboard`，从 main `c1f88d6`（#75 之后）开。SPEC:C19、C20。PR 草稿。依据：`docs/dev-tasks/dev-tasks-1014c.md` T39（边界、技术要求、验收）和 `dev-tasks-1014d.md`「T39 修订」（第 2 页改每人每日、回访阶段、第 1 页第 7 项、CSV、聚合、验收补充 6–11）。只用模拟器和合成数据（3 PILOT + 10 PB，两组都有）；没有连生产；没有改热线、IAM、feature-registry。

## 结论

1. **做了第 2 页（每人）和第 1 页第 7 项（今日回访到期名单）**，10/19 前要用的两样。第 1 页其余项和第 3 页按 1014d 排期（10/26 前、Junyu 定）没做，列在待办 111。
2. **只给非盲角色**：入口在研究员登记页右上角「營運看板」（只有 `unblinded` 到得了那页），开关 `app_config/feature_flags.opsDashboardEnabled`（**默认关**）。服务器三个函数都查 `role: unblinded` + 开关：评估员（`blinded`）、参与者、旧角色名直接拒绝；页面本身也查 claims，不是 `unblinded` 显示「冇權限」。
3. **聚合在服务器**（`functions/ops_dashboard.js`），客户端不读任何集合。每天 02:10 的 `opsDailyRollup` 把每人已过去的研究日算成一行存 `ops_daily/{uid}/days/{日期}`；打开看板时只补缺的天和今天（原始数据只从最早缺的那天读起）。13 个人的试跑规模每次打开约 1–2 秒。
4. **结局分数一个字都不显示**：代码不读 `djg_responses`、`djg_es`、`pgic`、`social_contact_probes`、`outcome_entries` 等任何结局集合（单元测试扫源码），回应和 CSV 里没有 score / DJG / UCLA / PHQ / GAD / PGIC 字样（模拟器测试检查键名，widget 测试检查屏幕上全部文字）。不显示分配序列；不显示对话原文（最近会话只有时间、陪伴者、类型、句数、时长、结束方式、是否有效、Brief PR 状态）。
5. **每次打开和导出都记审计日志** `ops_audit_log`（谁、何时、看了名单 / 看了谁 / 导了谁）。被拒绝的调用不记。
6. **口径**：回访阶段按 1014d（第 1–28 天，连续 3–5 天没打开「WhatsApp」，6 天以上「電話」，第 29 天起「隨訪期，只記錄」仍显示天数；第 0 天不计入）；没有 T40 事件的人按“当天有无会话开始”算打开并标「舊構建口徑」，前台时长显示「不可用」；前台单段封顶 60 分钟。
7. **核对时发现**：原有的「研究員儀錶板」页（T34 告警列表和確認處理、T30 完成率、T12 的各节）**在 App 里没有任何入口**——T19 起 `unblinded` 登录直接进登记页，没有再放链接。本任务没有动它（不在范围），要 Junyu 定放哪里（建议也放登记页右上角）。见“要带回研究侧的发现”。
8. T40（#80）还没合并时本分支也能跑：没有 `usage_events` 就全部走旧构建口径。两份合并后看板自动用 T40 事件。

## 1. 开关和入口

| 项目 | 做法 |
|---|---|
| 开关 | `app_config/feature_flags.opsDashboardEnabled`，默认关；App 和服务器都看它（`functions/feature_flags.js`） |
| 入口 | `lib/features/enrollment/presentation/enrollment_page.dart` AppBar 右上角 `Icons.insights` 按钮「營運看板」，开关关着不显示 |
| 页面 | `lib/features/ops_dashboard/presentation/ops_dashboard_page.dart`（每人表 + 今日回访到期 + 筛选）、`ops_person_page.dart`（每日网格、最近会话、CSV 页） |
| 后端 | `lib/features/ops_dashboard/data/ops_dashboard_service.dart`（三个 callable 的封装 + 模型；测试用假后端） |
| 直接访问 | 页面先查 claims（`isUnblindedClaims`），不是就「冇權限」；服务器再查一次，`not_unblinded` → permission-denied |

## 2. 第 2 页每人（一行一人）

字段（1014c 第 2 页 + 1014d 加的三项）：研究编号、研究期、组、登记日期（W0）、今天是研究第几天、最后一次使用（最后一条前台事件或最后一次会话开始，取晚者，香港时间）、**今日是否已打开、连续未打开天数、回访阶段**、「舊構建口徑」标记；有效会话总数和按陪伴者（小欣 / 阿珍／阿伯 / 通通）、按类型（自由傾偈 / 簽到 / 回憶）；Brief PR 邀请 / 完成 / 部分 / 跳过 / 过期；每周问卷 W1–W8 每周一格（已填 / 跳過 / 窗口中 / 過期未填 / 未到；W8「未做（T35）」）；每日心情填写天数；记忆条数共享 / 私有（规则组「不適用」）；语音次数 / 失败次数；安全事件急性 / 中级 / 低级和待确认；W8、Debrief 状态（T35、T42 未做，显示未做）。

筛选：研究期（试跑 / Phase B）、组（A / B）、「只睇 3 日冇用」（连续未打开 ≥ 3 天）。页面上有一行「顯示 N 人：…」便于核对。

点一行进每人页。

## 3. 每人页：每日网格（第 1 天到今天）

| 列 | 口径 |
|---|---|
| 打開 | 当天（香港自然日）有至少一条 T40 `foreground` 事件。**旧构建口径**：这个人一条使用事件都没有时，当天有任一会话开始记录即算打开；该人行和每人页都标「舊構建口徑」 |
| 第一次打開 | 最早一条 foreground 的手机时间，HH:mm；旧口径用最早一次会话开始 |
| 前台分鐘 | 各段前台时间之和。一段 = 一条 foreground 到该人的下一条事件（background，或 App 被杀后的下一条 foreground）；今天还开着的那段到现在为止。**单段超过 60 分钟按 60 计**。段归到它开始的那一天。旧口径显示「不可用」 |
| 小欣 / 阿珍／阿伯 / 通通 | 当天结束的 `isValid: true` 会话数（按会话结束时间归日，没有结束时间用开始时间；有效定义 = T25 的 `isValid`） |
| Brief PR 邀請 / 完成 | 当天邀请的记录数（T25 v3 按 `invitedAt`，旧弹窗记录按 `promptedAt`）和其中 `completed` 的数 |

下面列最近 20 次会话（无原文）。右上角「匯出 CSV」。

## 4. 回访阶段（1014d 第 2 页第 4 项）

- 连续未打开天数 = 今天的研究日 − 最后一次“当天打开”的研究日；今天打开 = 0；第 0 天（登记日）不算“打开”，所以登记后一直没开 = 今天的研究日数。
- 第 1–28 天：0–2 天「無」、3–5 天「WhatsApp」、6 天以上「電話」；第 29 天起「隨訪期，只記錄」仍显示天数；第 0 天「無」。
- 第 1 页第 7 项「今日回訪到期」：阶段为 WhatsApp / 電話的人，列研究编号、研究期、天数、阶段，按天数降序；**不含组**（回应里没有 `arm` 字段）。放在每人页顶部的卡片里（第 1 页整页以后做时搬过去）。
- 看板不记录 PI 有没有联系过。

## 5. CSV（每人每日一行）

列固定：`researchId, studyPeriod, arm, studyDay, dayKey, opened, firstOpenAt, foregroundMinutes, validSessions_siu_yan, validSessions_ah_jan_ah_bak, validSessions_tung_tung, briefPrInvited, briefPrCompleted, basis`。服务器生成（`opsDashboardCsv`，一个人或全部），App 显示文本 + 「複製全部」（手机上贴到文件或表格；没有加分享插件）。只含过程数据。

## 6. 数据和规则

| 集合 | 内容 | 谁能碰 |
|---|---|---|
| `ops_daily/{uid}/days/{日期}` | 每人每日一行（第 3 节的字段 + `uid`、`storedAt`），只存已过去的天 | 只有服务器；客户端读写都拒绝（规则测试覆盖参与者、评估员、非盲、匿名） |
| `ops_audit_log/{id}` | `type`（open_people / open_person / export_csv）、`by`、`at`、`researchId` / `count` / `people` | 只有服务器 |

读的集合（都是过程数据）：`enrollments`（名单、研究期、组、W0）、`users/{uid}`、`usage_events`、`sessions`、`brief_pr`、`weekly_pr/W1–W8`、`weekly_status`、`daily_mood`（只数天数）、`mem_facts`（只数条数，Hybrid 组）、`stt_usage`、`events`（只数 `voice_transcription_failed`）、`safety_events`（只数级别）、`pi_alerts`（只数未确认）。没有读 `turns`、任何 `mem_*` 的内容、任何结局集合、分配序列。

## 7. 测试

| 测试 | 内容 | 结果 |
|---|---|---|
| `functions/test/ops_dashboard_test.js`（13 项） | 前台分钟 3 小时封顶 60、跨午夜归起始日、被杀后的段；每日行 usage 口径和 legacy 口径；回访阶段 0 / 4（WhatsApp）/ 7（電話）/ 从未打开 / 第 29 天随访期 / 第 0 天；到期名单排序且无组；每周格五种状态；CSV 列固定且无结局列；源码不含任何结局集合名 | 13/13 |
| `functions/test/ops_dashboard_emulator_test.js` | 合成 3 PILOT + 10 PB（两组）：开关关 → disabled、rollup 跳过；`blinded` / 参与者 / 旧角色 → not_unblinded 且不记审计；13 行数字（研究日、今日打开、天数、阶段、有效会话按陪伴者 / 类型、Brief PR、记忆、心情、安全、语音、每周格）；验收 6（4 天 → WhatsApp 且在名单）、7（7 天 → 電話）、8（第 35 天 → 随访期）、9（只有会话的旧构建人 → 舊構建口徑）、10（3 小时 → 60 分钟）、11（CSV 无结局字段）；回应键名无 score / djg / ucla / phq / gad / pgic / answers / text；审计日志 5 条；rollup 存 9 天、不存今天、再读一致 | 9/9（模拟器） |
| `test/rules/ops_dashboard_rules.test.js`（8 项） | `ops_daily`、`ops_audit_log` 四种身份都不能读写 | 8/8（模拟器） |
| `test/ops_dashboard_test.dart`（8 项） | 开关只认 `true`；登记页入口随开关；`blinded` / `pi` / 无 claims → 冇權限；服务器 disabled 的提示；每人表（5 人、阶段文字、随访期、舊構建口徑、规则组记忆不適用、到期名单无「組」字、屏幕无结局字样）；三个筛选；每人页（60 分钟、冇、会话行、CSV 页复制按钮）；旧构建人的说明和「不可用」 | 8/8 |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | | 0 error；其余 info / warning 都是改动前已有的 |
| `tool/ci_flutter_tests.sh`（六套） | | 六套全过（本机，Flutter 3.35.3） |
| `tool/ci_backend_tests.sh` | | 全过（本机模拟器；规则 191 项含新 8 项） |
| ESLint（`ops_dashboard.js`、两个测试） | ES2018，没有 `??` `?.` | 0 问题 |

对应 1014c 验收：非盲账号能开每人页且数字对（模拟器 + widget）；评估员没有入口、直接访问被拒（服务器 + 页面）；页面文字和 CSV 没有结局分数字段（widget 扫全部文字、CSV 测试）；“少于 5 人完成率显示人数不足”属于第 1 页（本次没做第 1 页完成率，T30 的完成率已有 n<5 规则）；审计日志有打开记录（模拟器）。

GitHub CI 见 PR。

## 8. 改了哪些文件

- 新：`functions/ops_dashboard.js`；`lib/features/ops_dashboard/data/ops_dashboard_service.dart`、`presentation/ops_dashboard_page.dart`、`presentation/ops_person_page.dart`；`functions/test/ops_dashboard_test.js`、`ops_dashboard_emulator_test.js`；`test/rules/ops_dashboard_rules.test.js`；`test/ops_dashboard_test.dart`。
- 改：`functions/index.js`（三个 callable + `opsDailyRollup`）；`firestore.rules`（`ops_daily`、`ops_audit_log` 服务器专用；头部清单）；`lib/core/feature_flags/remote_feature_flags.dart`（`opsDashboardEnabled`）；`lib/features/enrollment/presentation/enrollment_page.dart`（入口按钮 + 两个测试钩子）；`test/rules/package.json`。
- 文档：`STUDY_CHANGELOG.md` 一行；`architecture.md` 第 8、9、12 节 + 顶部核对说明；`history.md`；`backlog.md` 第 111 项；本报告。
- 没改：安全检测、prompt、热线、`docs/spec/`、IAM、导出白名单、原有的研究员后台页。

## 9. 和其他 PR 的交叉

| PR | 交叉 |
|---|---|
| T40 `feat/usage-events`（#80） | 都改 `functions/index.js`（各自加一段，不同位置）、`firestore.rules`（T40 加 `usage_events` 规则，本分支加 `ops_*`，不同位置）、`remote_feature_flags.dart`（各加一个字段，三处都要留）、`test/rules/package.json`（mocha 清单取并集）、四份文档顶部。合并顺序建议 #80 先、本 PR 后；我在 #80 合并后把 main 合进来解冲突 |
| T46（#79） | 不重叠 |
| `chore/t43-pilot-checklist`（#78）、#77 | 只有文档，顶部相邻，两边都留 |

合并后：部署 **规则 + Functions**（三个新 callable、一个新定时任务）；研究员的手机要装含本改动的包才有入口（参与者包同一个，参与者看不到）。打开开关：控制台 `app_config/feature_flags.opsDashboardEnabled = true`。

## 要 Junyu 定的事

1. 第 2 页要不要放「查看该人对话记录」链接（1014c 待定）：没做；做的话走现有的对话查看路径并记审计。
2. 第 3 页按组汇总是否现在做（1014c 待定）：没做。
3. 旧的「研究員儀錶板」（T34 告警确认在那页）放哪个入口。
4. 前台单段 60 分钟封顶、有效会话按结束时间归日——两个实现细节，有异议再改。

## 要带回研究侧的发现

1. **研究员后台没有入口**：T34 的安全告警列表和「確認處理」、T30 的全体合并完成率都在 `researcher_dashboard_page.dart`，但 T19 之后 `unblinded` 登录直接进登记页，没有任何按钮能到那页。T43 核对单里“PILOT 账号触发一次测试告警，邮件发出”能过，但“確認處理”在 App 里点不到（只能控制台改 `acknowledgedAt`，或等 T34 的 12 小时后备）。建议和本看板一样放登记页右上角，一个小 PR。
2. 10/15 装的包没有 T40：这几位 PILOT 的“当天是否打开”按会话算，并标「舊構建口徑」；他们换到含 T40 的包之后口径自动切换，之前的天数仍是旧口径（已存的 `ops_daily` 行带 `basis: legacy`）。
3. “连续未打开”从第 1 天算、第 0 天不计：登记当天研究员已经帮老人打开过，不算老人自己打开，这是按 1014d 写的；如果研究侧想把登记日算作打开，改一处常量。
4. 每人页的每周问卷格用 `weekly_pr/Wn` 和 `weekly_status`（T24，开关 `weeklyScheduleV2Enabled` 还关着）：T24 开关打开前所有格都显示「未到」。
5. 安全事件“低级”只有在 `safety_events` 里确实写了 `level: low` 的行才有数；现在的词库大多只写 moderate / acute，所以低级一列基本是 0。
6. CSV 在手机上只能复制文本；要直接下载文件得在电脑用 Firebase 控制台或以后加分享插件。
