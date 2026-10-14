# T30 角色、评估员视图、序列上传、过程数据与结局数据、锁库导出（2026-10-14，SPEC:C01、C19、C20）

> 任务单：`docs/dev-tasks/dev-tasks-1010.md` 第四节 T30，按 `dev-tasks-1010b.md` 第二节和 `dev-tasks-1014.md` 第三节的更正执行（评估员视图只剩 W4；两位评估员 Keran、Mingyan Wang 都是 `blinded`；评估员不被登记门挡；PHQ-9 第 9 题走 T34 入口；ADA 不做）。分支 `fix/roles-exports`，从 `main`（已含 T25 PR #67）开出。
> 只用 Firebase 模拟器和合成数据，没有连正式项目。截图：`docs/dev-reports/T30-roles-exports-20261014-screenshots/`。

## 结论（先看这里）

1. **三个角色定了含义，代码和脚本都按新含义**（`tool/provision_researcher.js`）：`unblinded` = Junyu（不设盲，但不生成、不看序列）；`blinded` = 独立 W4 结局评估员（Keran，后备 Mingyan Wang）；新角色 `sequence_uploader` = 只给 Calvin，只能上传序列。
2. **评估员视图做好了，开关默认关**（`app_config/feature_flags.assessorViewEnabled`）。开后，`blinded` 账号登录就直接进评估员页（在登记门和同意页之前，不会停在等待页 S8，不收参与者推送），只有两样东西：W4 到期名单（研究编号、W0 后第 25–31 天的窗口、今日第几天、已录入/未录入、超窗标记）和 W4 纸本 DJG-ES 录入（逐题、提交前确认两次、施测日期、方式）。分数在服务器算，评估员看不到；存进只有服务器能读写的 `outcome_entries`；提交后不能改，更正用 `tool/correct_outcome_entry.js`（写理由、留日志）。W8 不在评估员视图（T35 在 App 内推）。
3. **评估员读不到任何能看出组别或过程的东西**：规则里 `blinded` 一条读权限都没有，名单和录入都走服务器函数，函数只回研究编号、窗口、第几天、录没录、超没超窗。两个合成评估员账号逐项核对：组别、组别代号、Brief PR、Weekly PR、使用量、对话、安全事件、别人的结局记录、序列，全部被拒（规则测试 8 条、模拟器测试 10 条、App 测试 11 条，第 7 节）。
4. **PHQ-9 第 9 题 ≠ 0 自动记安全事件并告警**（来源 `assessor_entry`，调 T34 的 `functions/questionnaire_safety.js`）。PHQ-9 的规格文件还没来，题目先用【占位】，机制已通测试；文件到了只改 `functions/outcome_instruments.js` 的题目文字和 App 常量，不改结构。
5. **序列上传改成 Calvin 自己上传、不用服务账号**：新函数 `uploadRandomizationSequence`（只认 `sequence_uploader`，开关 `meta/randomization_config.sequenceUploadEnabled` 默认关，两层任何一层已有人分配就拒绝），`tool/randomization_sequence.js` 在 Calvin 电脑上生成、用他自己的登录调函数上传；每次上传写一条只有服务器能读的日志（时间、账号、两层长度和指纹，**没有组别、没有种子**）。任何客户端角色都读不到序列、指针和日志。
6. **过程数据和结局数据分开**：新的过程数据导出（Brief PR 含 T25 v3 字段、Weekly PR、使用量含 `validSessionCount`、会话层、安全事件带来源）给 `unblinded`，每行带研究编号和真实组别，**不含任何结局数值、不含对话原文**，写到 Storage `exports_process/{日期}/`（开关 `meta/blinding_config.processExportEnabled` 默认关）。锁库前可以停掉含结局数值的 `exports_v2`（开关 `outcomeExportPaused` 默认关，代码保留）。研究员后台给 `unblinded` 一节「結局問卷完成率（全體合併）」：按问卷按时间点全体合并，少于 5 人不显示（开关 `outcomeCompletionSummaryEnabled` 默认关）。
7. **整人删除保留一行分配记录**：`tool/delete_participant.js --allocation-record` 删除前写 `allocation_records/{研究编号}`（研究编号、层、组别、序列位置、分配时间、退出日期；没有 uid、姓名、联系方式），然后把带 uid 的 `arm_assignment_log` / `pilot_assignment_log` 行也删掉。不带这个参数时仍是 T19 的做法。
8. **阿珍/阿伯改动服务器记日志**：新触发器 `onUserPairingChanged`（开关 `app_config/feature_flags.pairingChangeServerLogEnabled` 默认关）在用户文档的配对字段变化时写 `pairing_change_log`（uid、时间、改前、改后、登记值）。登记值在 `enrollments/{uid}.companionVariant`，本来就只有服务器能写，不动。
9. **锁库和分析导出**：`tool/analysis_export.js --lock` 写 `meta/data_lock`（要 `--confirm` 和 `--confirm-lock` 两个确认，锁过不能再锁）；没锁拒绝导出；导出 Phase B 全部参与者（不含试跑、测试账号），研究编号代替 uid，组别照实，**不含对话原文**（`turns` 只有元数据），18 个表的清单见第 6 节；`--synthetic` 不读 Firestore，生成 72 个合成参与者（两组两层、含缺失），表和列和真实导出完全一样（测试逐表比对），每行 `dataset: "synthetic"`。默认只对模拟器，正式项目要 `--project` + `--production-confirm`；每次锁库和导出写 `analysis_export_log`。
10. **全部开关默认关**，合并部署后行为不变。第一位参与者 W4 前（约 11/13）要做的事见第 11 节。

## 1. 现状（改之前，任务第 1 节）

| 问题 | 改之前 | 位置 |
|---|---|---|
| `blinded`、`unblinded` 各能读什么、看什么 | `unblinded`：规则允许读 `research_id_map`、`research_ids`（T12）、`pi_alerts`（T34）；App 里登录直接进「研究員登記」页（`StaffGate`），研究员后台看全部板块（两组人数、单组板块、安全告警）。`blinded`：规则里**一条读权限都没有**（和老人一样，只能读自己的用户文档）；App 里登录进的是**普通参与者 App**（同意页、入组问卷、主页），要从测试员工具进研究员后台，后台只显示不分组的板块（参与度、PPR 分布、未处理 distress flags）。登记门开着时，`blinded` 账号因为没有 `cohort` 会停在等待页 S8（T21 报告 4.5） | `firestore.rules`（`isUnblinded()`）；`lib/features/enrollment/presentation/staff_gate.dart`；`lib/features/researcher_dashboard/data/dashboard_access.dart` |
| 导出有哪些、含什么、谁能读、多久跑 | 每周日 02:00 `blindedDataExport` 跑一次。`meta/blinding_config.enabled` 关（默认）：旧导出 `exports/{日期}/`，全部集合（含 `turns`、`events` 的原文和参数、`safety_events` 原始 `source`），uid 换成每周换盐的哈希，组别换成每周重抽的 Group_X/Y。开：新版 `exports_v2/{日期}/`，只有结局量表白名单（`djg_responses`、`djg_es`、`pgic`、`weekly_pr`、`daily_mood`、`loneliness_probes`，加 `safety_events` 用户输入来源）和研究编号、固定组别代号；过程数据揭盲前不导出。两种都写在 Storage，**只有服务账号能读**（没有 Storage 规则给任何客户端角色） | `functions/index.js` `blindedDataExport`；`functions/blinding.js`；T12 报告第 3 节 |
| 研究员后台显示哪些和结局有关的数字 | **没有结局分数**。「參與度」一节按人数、按组（`unblinded` 看 Arm A / Arm B 人数）；「PPR 總體分布」是 Phase A 的每周 PPR 汇总（全体，不分组）；没有 DJG、PGIC 的任何数字 | `lib/features/researcher_dashboard/presentation/pages/researcher_dashboard_page.dart` |
| 分配序列怎样上传 | `tool/randomization_sequence.js --upload` 用 **服务账号凭据**（`GOOGLE_APPLICATION_CREDENTIALS`）直接写 `randomization_sequences`、`randomization_state`；上传人填 `--operator` 自报；没有上传日志；任务单写由 Keran 跑 | `tool/randomization_sequence.js`（T19） |

## 2. 角色（任务第 2 节）

### 2.1 三个角色

| 角色 | 给谁 | 能做什么 | 代码 |
|---|---|---|---|
| `unblinded` | Junyu | 登记（看组别）、读研究编号对照表、安全告警和「確認處理」、后台两组人数和单组板块、过程数据导出、全体合并完成率（开关开后）。**不生成、不看序列**：规则不让任何客户端读序列，上传函数只认 `sequence_uploader` | `firestore.rules`；`functions/randomization.js`；`functions/assessor.js` `completionSummary` |
| `blinded` | Keran、Mingyan Wang（W4 结局评估员） | 只有评估员视图：W4 到期名单、W4 纸本 DJG-ES 录入。规则里没有任何读权限，名单和录入都走服务器函数 | `functions/assessor.js`；`lib/features/assessor/`；`lib/features/enrollment/presentation/staff_gate.dart` |
| `sequence_uploader` | Calvin | 调 `uploadRandomizationSequence` 上传序列。规则里没有任何读权限；App 里当普通账号（没有专属页面） | `functions/sequence_upload.js`；`tool/randomization_sequence.js` |

旧名字 `pi`、`researcher` 仍然什么权限都没有（测试 `test/rules/assessor_rules.test.js`、`test/assessor_view_test.dart`）。

### 2.2 发账号的命令和核对（Junyu 自己跑，线上操作）

```
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
NODE_PATH=functions/node_modules node tool/provision_researcher.js --email=<Keran 的 App 登录电邮> --role=blinded
NODE_PATH=functions/node_modules node tool/provision_researcher.js --email=<Mingyan Wang 的 App 登录电邮> --role=blinded
NODE_PATH=functions/node_modules node tool/provision_researcher.js --email=<Calvin 的 App 登录电邮> --role=sequence_uploader
NODE_PATH=functions/node_modules node tool/provision_researcher.js --list
```

`--list` 打印所有带角色的账号，一行一个，例如 `keran@…: role=blinded`、`mingyan@…: role=blinded`、`calvin@…: role=sequence_uploader`、`junyu@…: role=unblinded`。核对：两位评估员都是 `blinded`，没有别的账号是 `blinded`；只有 Calvin 是 `sequence_uploader`；没有带旧名字的（`--list-legacy` 显示 0 个）。账号已有别的角色要先 `--revoke`。发完要让对方退出再登录（或等约 1 小时）。

### 2.3 ADA 研究员页面

任务原文第 2.3 条（ADA 给 `unblinded`）按 1010b 更正不做：ADA 属 Phase A，暂停。

## 3. 评估员视图（任务第 3 节；1014 更正：只剩 W4）

### 3.1 进入方式

`StaffGate`（`lib/features/enrollment/presentation/staff_gate.dart`）登录后读一次 Auth 角色：`unblinded` → 登记页（T19 不变）；`blinded` 且开关 `assessorViewEnabled` 开 → `AssessorPage`；其他 → 参与者 App。`StaffGate` 在 `EnrollmentWaitGate`（登记门）和 `ConsentGate` 之上（`lib/features/auth/presentation/pages/auth_gate.dart`），所以评估员账号**不会停在 S8、不会进同意页**。路由到评估员页或登记页时 App 调 `FcmService.suppressForStaff(uid)`（`lib/core/fcm/fcm_service.dart`）：不存推送令牌、不订阅广播主题、已订阅的退订——**评估员账号不收参与者推送**。从评估员页只能登出；研究员后台对开关开着的 `blinded` 账号显示「冇權限」（`DashboardAccess.withAssessorView`）。开关关时和现在一样（`blinded` 进普通 App）。

### 3.2 到期名单（`assessorDueList`）

服务器（`functions/assessor.js` `dueList`）读 `enrollments` 里 `studyPeriod == "B"` 的记录（试跑 `PILOT-` 不在名单；测试账号不能登记），按 `w0Date` 算：窗口 = W0 后第 25–31 天（`W4_WINDOW`），今日第几天，状态 `before` / `open` / `after`，加 `outcome_entries` 里该编号 W4 已录入的问卷（施测日期、是否超窗）。返回字段只有：`researchId`、`windowStartDate`、`windowEndDate`、`studyDay`、`windowState`、`entered`。测试用正则逐个键检查没有 arm / group / brief / weekly / usage / session / turn / chat / sequence / strat / safety / uid / email / score（`functions/test/assessor_emulator_test.js`「due list」）。名单按「窗口开放中 → 未到期 → 已超窗」排。

### 3.3 纸本录入（`submitOutcomeEntry`）

- 页面 `lib/features/assessor/presentation/outcome_entry_page.dart`：先选施测日期（不能是将来）和方式（當面 / 電話 / 視像 → `in_person` / `phone` / `video`），然后**一题一屏**，三个选项照问卷包（是 / 大致是 / 不是）加「缺答（紙本冇填）」，可返回上一题；最后一屏核对；提交前**两次确认**（第一次说明题数和缺答数，第二次重复研究编号和施测日期）。
- 服务器（`functions/assessor.js` `submitEntry`）：核对角色、开关、研究编号存在且是 Phase B、问卷在 `functions/outcome_instruments.js` 里、时间点 W4、日期、方式、每题答案合法；算分（DJG-ES 和 `functions/djg_w2.js` 同一规则，测试逐例比对）；在事务里写 `outcome_entries`，同一编号同一问卷已有记录就拒绝（`already_entered`）；回给 App 的只有 `recorded`、编号、问卷、时间点、`outOfWindow`、缺答的题——**没有分数**。
- 超窗（施测日期在第 25–31 天之外，早或晚）照样录，记 `outOfWindow: true`，名单上标「已錄入（超窗）」。
- 给 T24 的 W4 施测日期：写 `weekly_status/{uid}.w4VisitDate`（`YYYY-MM-DD`）和 `w4EntryAt`、`w4EntryInstrument`；另有函数 `assessor.w4VisitDateFor(db, uid)`。T24 关第 4 周问卷时读这个字段即可（见第 10 节交叉）。
- 更正：`tool/correct_outcome_entry.js --entry=<id> --item=q3 --value=no --reason="…" --operator=… --confirm`（也可改 `--assessment-date`、`--mode`；`--value=skipped` 标缺答）；理由至少 10 字；服务器重新算分，写 `outcome_entries.correctedAt`，在 `outcome_entry_corrections` 记改前、改后、理由、操作人、时间。不带 `--confirm` 只打印。

### 3.4 规格文件和问卷登记表

- `docs/spec/instruments/djg_es.md`（新）：题目、选项、计分、存储、窗口，从 T18 的代码整理，格式照 `ada.md`。第 6 节写了给以后纸本问卷的格式要求。
- 代码里的登记表 `functions/outcome_instruments.js`：`DJG-ES`（6 题、三选项、`djg6_v1` 计分）、`PHQ-9`（9 题 0–3、总分、题目【占位】、`safetyItem` 第 9 题）。App 端题目用 T18 的 `DjgW2Items`（`lib/features/assessment/data/djg_w2.dart`）。两边都有逐字比对规格文件的测试。
- PHQ-9 规格文件到了：改 `functions/outcome_instruments.js` `PHQ_9.items` 的文字和 `options` 的显示，加 App 端常量和录入页入口，加逐字测试；不改函数、集合和流程。

### 3.5 安全（任务第 3.4 条，1010b 更正）

提交处调用 `questionnaire_safety.recordQuestionnaireSafetyEvent(db, {uid, source: "assessor_entry", instrument: "PHQ-9", item: 9, rawValue, enteredBy, researchId})`。第 9 题为 0 不写；不是 0 写一条 `safety_events`（`alwaysAlert: true`，T34 的 `onSafetyEventCreated` 不论级别都告警）。记录先写、再调入口，入口失败不丢记录。默认级别仍是 T34 的 `acute`（待 Junyu 定，T34 报告「要 Junyu 定的事」第 1 条）。测试：`functions/test/assessor_emulator_test.js`「PHQ-9 entry」。

## 4. 过程数据和结局数据（任务第 4 节）

### 4.1 过程数据导出（给 Junyu）

`functions/process_export.js`，开关 `meta/blinding_config.processExportEnabled`（默认关）。开后在每周日的 `blindedDataExport` 里一起跑，写 Storage `exports_process/{日期}/`，每次写一条 `process_export_log`。只有 Phase B 参与者（`cohort: phase_b`，不含测试账号），每行 `researchId` + 真实 `arm`。文件和字段（白名单，不在表里的不导出）：

| 文件 | 字段 |
|---|---|
| `participants` | `researchId`、`arm`、`strataCell`、`w0Date`、`cohort` |
| `brief_pr` | T25 v3：`schemaVersion`、`scheduleVersion`、`sessionId`、`agentId`、`sessionType`、`endReason`、`sessionEndedAt`、`lastReplyAt`、`invitedAt`、`invitedDayKey`、`inviteChannel`、`everShown`、`shownAt`、`ratedAt`、`finalStatus`、`dueNotInvitedReason`、四题原始分；旧 v2 的 `isAnchorPrompt`、`status`、`promptedAt`、`respondedAt`；T24 以后的 `studyWeek`、`studyDay` |
| `weekly_pr` | `weekIso`、`agentId`、`items`、`status`、`promptedAt`、`respondedAt`、`sessionCountThisWeek`、`referentRule`、`studyWeek`、`studyDay` |
| `sessions` | T25 会话层：`sessionId`、`agentId`、`moduleId`、`theme`、`startedAt`、`endedAt`、`endReason`、`userTurnCount`、`fallbackCount`、`lastActivityAt`、`scheduleVersion`、`sessionType`、`userMessageCount`、`replyCount`、`lastReplyAt`、`isValid`、`moodRecorded`、`summarySaved`、`isRuleSubmission`、`ruleSubmissionCompleted`、`briefPrInvitedTodayAlready`、`briefPrSkippedByCap`、`briefPrInvited`、`briefPrStatus` |
| `usage_weekly` | `isoWeek`、`sessionCount`、`validSessionCount`（T25）、`activeDays` |
| `safety_events` | `source`（原始）、`sourceGroup`（四种）、`level`、`tier`、`category`、`lexiconVersion`、`agentId`、`inputPoint`、`createdAt`、`instrument`、`item`、`crisisPageShown`、`isDuplicate`、`escalatedBy`；**不带** `matchedTerm`、`textHash`、`rawValue` |
| `manifest.json` | 行数、排除人数、`neverHere` 清单 |

**不在里面**：`outcome_entries`、`djg_responses`、`djg_es`、`pgic`、`loneliness_probes`、`daily_mood`、`ucla3_responses`（结局）；`turns`、任何文字、uid、电邮、姓名、路径引用。导出前跑 `leakCheck`，发现结局集合或文字类字段名就不写。测试：`functions/test/t30_server_emulator_test.js`「process export」。

**谁能读**：Storage 没有 Firestore 那样的规则文件在仓库里（`firebase.json` 只部署 Firestore 规则），现在 `exports/`、`exports_v2/`、`exports_process/` 都只有服务账号能拿。要让 `unblinded` 在控制台之外直接读 `exports_process/`，要加 Storage 规则 `match /exports_process/{all=**} { allow read: if request.auth.token.role == 'unblinded'; }` 并部署——这是部署层面的改动，本任务没做（第 8 节「规则管不到的地方」和第 12 节）。

### 4.2 锁库前不按组给 Junyu 结局数值

- `meta/blinding_config.outcomeExportPaused`（默认关）开后，`blindedDataExport` 不再写 `exports_v2`（也不写旧 `exports`），只记日志；代码保留给 `tool/analysis_export.js`。
- 研究员后台（`unblinded`）新一节「結局問卷完成率（全體合併）」（`lib/features/researcher_dashboard/presentation/widgets/outcome_completion_section.dart`），数据来自 `outcomeCompletionSummary` 函数：每份结局问卷按时间点，分母 = 已到该时间点的 Phase B 参与者数，分子 = 已完成；**少于 5 人不显示数字**（服务器置 `suppressed: true`，App 再查一次）。现在有 `DJG-ES W4`（评估员录入）、`PHQ-9 W4`、`DJG-ES W2`（App 内 `djg_responses/W2`）；T35 的 W8 问卷合并后在 `completionSummary` 加一行即可。开关 `app_config/feature_flags.outcomeCompletionSummaryEnabled`（默认关）。
- 规则：`outcome_entries` 等 T30 集合对所有客户端角色关闭；`users/{uid}/djg_responses` 仍只有本人能读（`unblinded` 也不能）；测试 `test/rules/assessor_rules.test.js`「outcome records」。

### 4.3 规则管不到的地方（只列出，不改权限）

1. Junyu 是 Firebase/Google Cloud 项目 Owner：控制台里能直接打开 `outcome_entries`、`randomization_sequences`、`enrollments`、Storage 里的导出。只能靠操作规范（不打开）和 Firestore 数据访问审计日志（上线清单 G5）。
2. 能部署 Cloud Functions 的人（GitHub「Deploy Firebase」工作流的审批人）能部署读任何数据的代码。靠 PR 审查和部署审批（清单 A2）。
3. Storage 的读权限不在仓库里（4.1）。
4. 评估员视图走函数，但函数日志（Cloud Logging）里会记调用者 uid 和错误信息；不记录答案。
5. `tool/admin_dump.js`、`tool/analysis_export.js` 等脚本用服务账号，谁有密钥谁就能读全部；密钥的保管写进 DMP。

## 5. 删除、阿珍/阿伯改动（任务第 5.1、5.2 条）

### 5.1 整人删除：改前改后保留什么

| | T19（现在默认） | T30 `--allocation-record` |
|---|---|---|
| `arm_assignment_log` 这个人的行（含 uid、研究编号、层、位置、组别、时间、操作人） | **整条保留**，列在「没覆盖」 | **删除** |
| `pilot_assignment_log` 这个人的行 | 整条保留 | 删除 |
| `allocation_records/{研究编号}` | 没有 | **写一行**：`researchId`、`studyPeriod`、`stratum`、`arm`、`sequencePosition`、`allocatedAt`、`withdrawnAt`、`writtenBy`。没有 uid、姓名、电邮、电话 |
| 已用的序列位置（`randomization_state.next`） | 不动 | 不动（位置本来就只是指针） |
| 其余（`users/{uid}` 整棵树、登记记录 `enrollments`、研究编号对照表、安全事件、告警、`outcome_entries`、`pairing_change_log`、`weekly_status`…） | 删除（后三项是 T30 新加进删除范围的） | 删除 |

决策草稿见第 9 节。默认不带参数是为了遵守「新行为默认关」；Junyu 定了以后可以把它改成默认（一行改动）。

### 5.2 阿珍/阿伯改动日志

- T37 已有：App 在开关 `onboardingAfterEnrollmentFix` 开时写 `events` `ah_jan_ah_bak_changed`（from、to、at、where）。
- T30 加：`onUserPairingChanged`（`functions/index.js`，`functions/pairing_log.js`）监听 `users/{uid}` 写入，`ahJanAhBakVariant` 变了且开关 `pairingChangeServerLogEnabled` 开时写 `pairing_change_log`：`uid`、`from`、`to`、`at`、`registeredVariant`（登记值）、`researchId`、`source: "profile_write"`。不靠 App，老人在哪里改都记。
- 登记值 `enrollments/{uid}.companionVariant` 只有服务器能写（T19 规则），分析以它为准。规则测试「a participant cannot set their own pairing in the registration record」。

## 6. 锁库和分析导出（任务第 5.3 条）

`tool/analysis_export.js`（新）。目标：默认模拟器；正式项目 `--project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev`。

- `--lock --operator=<电邮> --confirm --confirm-lock [--note=…]`：写 `meta/data_lock {lockedAt, lockedBy, note}`，已锁拒绝；只给一个确认参数时只打印状态。
- 导出 `--operator=<电邮> [--out=<目录>]`：没有 `meta/data_lock` 直接拒绝。写 `<目录>/<表>.ndjson` 和 `manifest.json`（行数、列定义、锁库信息）。
- `--synthetic [--n=72] [--seed=…] [--out=…]`：不连 Firestore；文件名前缀 `synthetic_`，每行 `dataset: "synthetic"`，manifest `synthetic: true`。同一 `--seed` 结果相同。
- 每次锁库、导出写 `analysis_export_log`（时间、操作人、模式、行数、锁库时间、输出目录名）。

逐个表清单（列定义在脚本 `TABLES`，真实和合成完全一致，测试逐表比对）：

| 表 | 来源 | 列（研究编号、组别之外） |
|---|---|---|
| `participants` | `users` + `enrollments` | `stratum`、`strataCell`、`w0Date`、`companionVariantAtRegistration`、`enrolledAt`、`ageGroup`、`baselineUclaScore`、`withdrawn` |
| `allocation_records` | `allocation_records` | 退出者的一行（5.1） |
| `outcome_entries` | `outcome_entries` | 问卷、版本、时间点、施测日期、方式、录入时间、原始答案、缺答、分数、计分版本、第几天、超窗、更正时间（**不带**评估员 uid） |
| `djg_responses` | `users/*/djg_responses` | T18/T35 字段：答案、分数、状态、窗口、推送/提醒/开始/提交/缺失时间、`studyWeek`、`studyDay`、`outOfWindow` |
| `pgic` | `users/*/pgic` | `value`、周、`studyWeek`、`studyDay`、`answeredAt`、`outOfWindow` |
| `ucla3_responses` | `users/*/ucla3_responses`（T35） | 时间点、周、答案、分数、状态、提交时间、超窗 |
| `weekly_pr`、`brief_pr` | 同 4.1 | 同 4.1（不带 `agentDisplayName`、`sessionRef`） |
| `daily_mood` | `users/*/daily_mood` | `mood`、`date_iso`、`is_primary`、`prompted_at`、`responded_at` |
| `loneliness_probes` | `users/*/loneliness_probes` | `score`、`isoWeek`、`answeredAt` |
| `sessions` | `users/*/sessions` | 同 4.1 的会话层字段 |
| `turns` | `users/*/turns` | **只有元数据**：`sessionId`、`agentId`、`moduleId`、`ts`、`llmStatus`、`promptVersion`、`latencyMs`、`inputCharCount`、`safetyLevel`、`safetyTurnId`。老人的话和回复的文字都不导出 |
| `events` | `users/*/events` | `name`、`ts`（参数不导出，可能含原文） |
| `safety_events` | `safety_events` | 同 4.1，另加 `rawValue`（问卷来源那一题的原始值） |
| `llm_calls` | `llm_calls` | 时间、类型、agent、模型、token、状态码、延迟、错误、`session_id`（T25） |
| `usage_weekly` | 由 `sessions` 算 | `isoWeek`、`sessionCount`、`validSessionCount`、`activeDays` |
| `memory_counts` | `mem_facts/summaries/followups` | 只数条数，不导出内容 |

测试（`functions/test/analysis_export_emulator_test.js`）：没锁拒绝；锁一次；锁后导出含组别和结局分数、只含 Phase B、没有 uid / 电邮 / 姓名 / 对话原文 / 评估员 uid；合成和真实的表名、列名逐表相同；文件写出能读回。

## 7. 测试

| 任务第 7 节 | 怎么测 | 文件 | 结果 |
|---|---|---|---|
| 1 `blinded` 只能进评估员视图；读组别、Brief PR、Weekly PR、使用量、对话、安全事件、别人的结局记录全部被拒 | 规则：两个合成评估员账号对 27 个路径逐个读、逐个集合列表读，全部拒绝；写也拒绝。App：开关开时 `blinded` → 评估员页（没有参与者 App、没有 S8），`unblinded` → 登记页，参与者和旧角色 → App；评估员页面全部文字用正则查组别、Group_、Hybrid、規則組、Brief PR、Weekly PR、使用量、對話、安全、序列、LLM，没有命中；两个账号的名单逐字相同。服务器：名单和录入对非 `blinded` 一律 `not_blinded`，回包没有泄露键 | `test/rules/assessor_rules.test.js`；`test/assessor_view_test.dart`；`functions/test/assessor_emulator_test.js` | 通过（8 / 11 / 10） |
| 2 到期名单第 25–31 天出现；已录入标出 | 三个合成参与者：第 26 天 open、第 17 天 before、第 38 天 after；录入后名单带施测日期；超窗的标出；试跑账号不在名单 | 同上「due list」；`test/assessor_view_test.dart`「due list」 | 通过 |
| 3 DJG-ES 录入：二次确认；服务器算分；提交后不能改；更正脚本留日志 | App：取消第一次确认不发；两次确认后才调函数；提交的只有原始答案没有分数。服务器：分数按 `djg6_v1`、回包没有分数；同编号再录 `already_entered`；更正理由短拒绝、题号错拒绝、改后重算分并写日志。PGIC 按 1014 更正不在评估员视图 | `functions/test/assessor_emulator_test.js`「entry」「correction」；`functions/test/outcome_instruments_test.js` | 通过 |
| 4 序列：只有 `sequence_uploader` 能上传；已有人分配后拒绝；任何客户端角色读序列被拒；上传日志里没有种子 | 开关关拒绝；`unblinded`、`blinded`、老人、旧角色拒绝；坏序列拒绝；上传后两层文档和指针正确、日志有长度和指纹、没有 `arms`、没有组别字母、没有种子；再传拒绝；有人分配后带 `replace` 也拒绝。规则：五种身份读序列、指针、日志全拒。工具：载荷不含种子、目标判断、用自己账号换 token 再调函数（假 fetch） | `functions/test/t30_server_emulator_test.js`；`test/rules/assessor_rules.test.js`；`functions/test/outcome_instruments_test.js` | 通过 |
| 5 过程数据导出有组别、没有结局数值；全体合并完成率少于 5 人不显示 | 导出两人（A、B）：每行 `arm`；T25 的 `schemaVersion: 3`、`isValid`、`validSessionCount`；安全事件带 `source` 和 `sourceGroup`；没有 `outcome_entries`、`djg_responses`、`pgic`、`daily_mood`、`turns`；没有 uid、电邮、姓名、原文、`matchedTerm`；`leakCheck` 为空。完成率：3 人 → 隐藏；7 人到期、4 人录入 → `4/7`；回包没有组别和编号；App 端 n<5 显示「少於 5 人，不顯示」 | `functions/test/t30_server_emulator_test.js`；`functions/test/assessor_emulator_test.js`「pooled completion」；`test/assessor_view_test.dart` | 通过 |
| 6 整人删除后只剩那一行分配记录，不含个人信息 | 带参数删除后 `residue` 为空、这个人的 `arm_assignment_log` 行没了、别人的还在；`allocation_records/PB-017` 只有 8 个字段，没有 uid、电邮、姓名；不带参数时日志行不在计划里；`outcome_entries`、`pairing_change_log`、`weekly_status` 都在删除范围 | `test/delete_participant/delete_participant_test.js`「--allocation-record」 | 通过 |
| 7 阿珍/阿伯改动有日志，登记值不变 | 开关关不写；开后一行 from/to/登记值/编号；无关字段的写入不记；`enrollments.companionVariant` 不变；规则：老人改不了登记记录 | `functions/test/t30_server_emulator_test.js`「pairing change」；规则测试 | 通过 |
| 8 `analysis_export.js`：没锁库拒绝；锁库后导出含组别和结局、不含对话原文；`--synthetic` 字段和真实导出一致 | 见第 6 节 | `functions/test/analysis_export_emulator_test.js`；`functions/test/outcome_instruments_test.js`「analysis export」 | 通过 |
| 规格逐字 | `docs/spec/instruments/djg_es.md` 的 6 题、3 选项 = `functions/outcome_instruments.js` = App `DjgW2Items`；DJG-ES 计分 = `functions/djg_w2.js` | `functions/test/outcome_instruments_test.js`；`test/assessor_view_test.dart` | 通过 |
| 评估员不收推送 | `FcmService.suppressForStaff`：没有单元测试（要 Firebase Messaging），逻辑是 `initialize` 前后各查一次名单；写在第 13 节「还没做」 | — | 未测 |

整套：`flutter analyze` 0 错误（89 条 info/warning，其中 1 条是 T25 合并后原有的 `researcher_dashboard_page.dart:374`，其余 88 条和 main 相同）；`tool/ci_flutter_tests.sh` 六套；`flock /tmp/firebase-emulator.lock tool/ci_backend_tests.sh`：结果在 PR 描述和 JSON 里。

截图：`docs/dev-reports/T30-roles-exports-20261014-screenshots/`（1 名单、2 日期和方式、3 第一题、4 核对、5/6 两次确认、7 已录入）。按钮上的文字在截图里显示为方块：截图测试只加载了系统的文泉驿字体给三个字体名，按钮用的字体名没对上，是截图环境的问题，不是 App 的问题（真机上正常字体）。

## 8. 开关

| 开关 | 位置 | 默认 | 管什么 |
|---|---|---|---|
| `assessorViewEnabled` | `app_config/feature_flags` | 关 | `blinded` 登录进评估员视图；`assessorDueList`、`submitOutcomeEntry` 才接受调用；研究员后台对 `blinded` 关闭 |
| `outcomeCompletionSummaryEnabled` | `app_config/feature_flags` | 关 | 研究员后台「結局問卷完成率（全體合併）」一节和 `outcomeCompletionSummary` 函数 |
| `pairingChangeServerLogEnabled` | `app_config/feature_flags` | 关 | `onUserPairingChanged` 写 `pairing_change_log` |
| `sequenceUploadEnabled` | `meta/randomization_config` | 关 | `uploadRandomizationSequence` 接受上传。建议 Calvin 上传当天开、传完关 |
| `processExportEnabled` | `meta/blinding_config` | 关 | 每周写 `exports_process/{日期}/` |
| `outcomeExportPaused` | `meta/blinding_config` | 关 | 开后 `blindedDataExport` 不写 `exports_v2` / `exports` |
| `--allocation-record` | `tool/delete_participant.js` 参数 | 不带 | 删除时写 `allocation_records` 并删分配日志行 |

## 9. 决策记录草稿（编号待开发窗口分配）

### 草稿一：角色改为 unblinded = Junyu、blinded = 独立评估员、sequence_uploader = Calvin

- 日期：2026-10-14
- 状态：提议中（随 T30 PR 草稿；取代 0029 第四节的角色分工，0021 第 5 条早已被 0029 取代）
- 影响范围：phase_b、pilot × 两组（人员角色，不影响老人）
- 相关代码：`tool/provision_researcher.js`、`firestore.rules`、`functions/assessor.js`、`functions/sequence_upload.js`、`lib/features/enrollment/presentation/staff_gate.dart`、`lib/features/assessor/`

**背景**：10/14 研究侧定了人员分工：Junyu 不设盲但不生成、不看序列；序列由 Calvin 生成和上传；W4 结局评估员是 Keran，后备 Mingyan Wang；W8 没有评估员。0029 写的是 Keran 非盲、PI 盲法，已不符。

**决定**：(1) `unblinded` 只给 Junyu：登记、看组别、过程数据、告警；不能读序列（规则），不能上传（函数只认 `sequence_uploader`）。(2) `blinded` 只给两位评估员，含义改为「独立结局评估员」：只有评估员视图（W4 名单、W4 纸本录入），规则里零读权限，所有数据经函数按字段白名单返回。(3) 新角色 `sequence_uploader` 只给 Calvin，只能调上传函数；序列在他本机生成，种子不上传；上传写服务器日志。(4) 三个角色都由 Junyu 用 `tool/provision_researcher.js` 发，`--list` 核对。

**考虑过的其他方案**：让 Junyu 继续用服务账号脚本上传（Junyu 会接触序列，违反分工）；评估员用 Firestore 规则直接读名单（规则做不到按字段白名单，`enrollments` 里有组别）；给 Calvin `unblinded`（他就能登记和看组别，超出需要）。

**后果**：对研究：protocol 的盲法段落写「非盲研究员 Junyu 不参与序列生成；序列由 Calvin 生成上传；W4 由不接触分组信息的评估员施测录入」；DMP 写角色发放和审计日志。对开发：以后新的研究员功能先问「哪个角色」，规则里 `blinded` 永远不加读权限。对论文：方法部分按此写。

### 草稿二：整人删除后保留一行不含个人信息的分配记录

- 日期：2026-10-14
- 状态：提议中（随 T30；取代 T19 报告「分配日志整条保留」的做法，不改 0029 正文）
- 影响范围：phase_b、pilot × 两组（退出的参与者）
- 相关代码：`tool/delete_participant.js --allocation-record`，`allocation_records/{researchId}`

**背景**：0020 和 ICF 承诺退出时删除个人数据；T19 为试验完整性整条保留分配日志，但那一行带 uid。10/9 研究侧定：只留研究编号、层、组别、分配时间、退出日期。

**决定**：删除时写 `allocation_records/{研究编号}`（8 个字段，无 uid/姓名/联系方式），同时删掉这个人的 `arm_assignment_log`、`pilot_assignment_log` 行；其余照常删。分析导出带 `allocation_records`。研究编号本身继续用于分析（ITT 的分母）。

**考虑过的其他方案**：保留整行（带 uid，和 ICF 的「删除」说法对不上）；什么都不留（CONSORT 流程图和 ITT 分析缺分母）。

**后果**：对研究：ICF/DMP 写「退出后保留研究编号、分层、组别、分配和退出日期，用于报告流程图和 ITT 分析」。对开发：Junyu 确认后把 `--allocation-record` 改成默认。对论文：CONSORT 流程图的退出人数来自这张表。

### 草稿三：锁库记录和分析导出

- 日期：2026-10-14
- 状态：提议中（随 T30）
- 影响范围：phase_b × 两组
- 相关代码：`tool/analysis_export.js`、`meta/data_lock`、`analysis_export_log`

**背景**：10/9 研究侧定：结局数据锁库前不按组给 Junyu；锁库后一次导出全部数据给分析；OSF 预注册的分析代码要先在合成数据上跑通。

**决定**：(1) 锁库 = 写 `meta/data_lock`（时间、操作人），两次确认，不可撤销（撤销只能在控制台删文档，审计日志会记下）。(2) 导出只在锁库后，Phase B 全部参与者，研究编号，真实组别，不含对话原文，表和列固定（第 6 节）。(3) 合成数据用同一脚本生成，表列相同，标明 synthetic。(4) 锁库前 `exports_v2` 可以用 `outcomeExportPaused` 停掉。

**考虑过的其他方案**：锁库后仍周导出（没必要，一次导出即可复现）；对话原文也导出（10/9 第 29 条 (1) 明确不要）。

**后果**：对研究：统计分析计划写锁库日期和导出清单；OSF 注册附合成数据的 manifest。对开发：T35 的 W8 集合已留列（`djg_responses/W8`、`ucla3_responses`），合并后核对一次列名。对论文：数据可得性声明按此写。

## 10. 和其他 PR 的交叉

| PR | 交叉 |
|---|---|
| T25 `feat/session-briefpr`（#67，已合并进 main） | 本分支从合并后的 main 开出。过程数据导出和分析导出已含 Brief PR v3 字段、`sessions.isValid`、`usage_weekly.validSessionCount`、`llm_calls.session_id` |
| T24 `feat/weekly-schedule` | **W4 施测日期**：读 `weekly_status/{uid}.w4VisitDate`（`YYYY-MM-DD`，评估员提交时写；更正时更新并写 `w4CorrectedAt`），或调 `require("./assessor").w4VisitDateFor(db, uid)`。`weekly_status` 在规则里已设为只有服务器能读写；T24 若也写这个集合，用 `merge: true`。T24 的 `studyWeek` / `studyDay` 函数定下来后，`functions/assessor.js` 的 `w4Window` 可以改用（现在用 `djg_w2.js` 的 `daysBetween` / `addDays`）。会改到同一批文件：`functions/index.js`、`firestore.rules`、`docs/dev/architecture.md` |
| T27 `feat/stt-server` | `functions/index.js`（都加函数）；没有逻辑交叉 |
| T32 `feat/phase-a-final` | 没有交叉（Phase A 暂停） |
| T34（已合并） | 调它的 `questionnaire_safety.js`；没有改它 |
| T35（未开） | W8 问卷的 `djg_responses/W8`、`ucla3_responses` 已在分析导出的表里；`completionSummary` 要加 W8 一行 |

## 11. 上线（第一位参与者 W4 前，约 11/13）

1. 合并部署（Functions + Firestore 规则）。
2. Junyu 发角色（2.2），`--list` 核对。
3. 建 `app_config/feature_flags.assessorViewEnabled: true`（评估员视图）；要看完成率再加 `outcomeCompletionSummaryEnabled: true`；要服务器记配对改动加 `pairingChangeServerLogEnabled: true`。每开一个在 `docs/STUDY_CHANGELOG.md` 补一行。
4. Calvin 上传序列（在第一位参与者登记前，和 T19 的顺序一样）：Junyu 临时把 `meta/randomization_config.sequenceUploadEnabled` 设 `true` → Calvin 在自己电脑 `node tool/randomization_sequence.js --seed-file=… ` 生成（文件交导师离线保存）→ `--upload --email=<Calvin> --password-file=<文件> --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev` → 屏幕显示两行 `+ … uploaded` → Junyu 把开关改回 `false` → `tool/prelaunch_config.js` 核对 `0 used`。
5. 过程数据：要周导出就设 `meta/blinding_config.processExportEnabled: true`；锁库前要停结局导出就设 `outcomeExportPaused: true`。Storage 读权限见 4.1。
6. 评估员账号不要设 `isTester`（T21 报告 4.5 的过渡办法在 T30 合并后不再需要）。

上线清单 `docs/release/prelaunch-checklist.md` B4、G2 和新加的 T30 行已照此更新。

## 12. 改了哪些文件

- 新增（服务器）：`functions/assessor.js`、`functions/outcome_instruments.js`、`functions/sequence_upload.js`、`functions/process_export.js`、`functions/pairing_log.js`；测试 `functions/test/outcome_instruments_test.js`、`assessor_emulator_test.js`、`t30_server_emulator_test.js`、`analysis_export_emulator_test.js`。
- 新增（脚本）：`tool/analysis_export.js`、`tool/correct_outcome_entry.js`。
- 新增（App）：`lib/features/assessor/data/assessor_service.dart`、`lib/features/assessor/presentation/assessor_page.dart`、`outcome_entry_page.dart`、`lib/features/researcher_dashboard/presentation/widgets/outcome_completion_section.dart`；测试 `test/assessor_view_test.dart`、`test/rules/assessor_rules.test.js`；截图测试 `docs/dev-reports/T30-roles-exports-20261014-screenshots/t30_shots_test.dart`。
- 新增（文档）：`docs/spec/instruments/djg_es.md`、本报告。
- 修改：`functions/index.js`（四个 callable、一个触发器、`blindedDataExport` 的两个开关）、`functions/blinding.js`（导出 `pick`）、`firestore.rules`（角色注释、九个服务器专用集合）、`tool/provision_researcher.js`（角色、`--list`、延迟加载 admin）、`tool/randomization_sequence.js`（Calvin 的上传流程；admin 上传函数只留给模拟器测试）、`tool/delete_participant.js`（`--allocation-record`、三个新集合）、`lib/core/feature_flags/remote_feature_flags.dart`（两个开关）、`lib/core/fcm/fcm_service.dart`（`suppressForStaff`）、`lib/features/enrollment/presentation/staff_gate.dart`（三路路由）、`lib/features/auth/presentation/pages/auth_gate.dart`、`lib/app/app.dart`（`onStaffRoute`）、`lib/features/researcher_dashboard/data/dashboard_access.dart`、`presentation/pages/researcher_dashboard_page.dart`（完成率一节、评估员拒绝）、`test/rules/package.json`、`test/delete_participant/delete_participant_test.js`、`docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`、`docs/history.md`、`docs/dev/backlog.md`、`docs/release/prelaunch-checklist.md`。

## 13. 还没做 / 要跟进

1. **Storage 规则**：仓库里没有 Storage 规则文件，`exports_process/` 现在只有服务账号能读；要让 `unblinded` 直接下载要加规则并部署（4.1）。
2. **序列上传的端到端**：函数本身和工具的两步（换 token、调函数）都有测试，但没有在 Functions 模拟器上整条跑过（CI 的模拟器只开 Firestore）。上线前 Calvin 先对模拟器试一次（`firebase emulators:start --only auth,functions,firestore`，环境变量 `FIREBASE_AUTH_EMULATOR_HOST`、`FUNCTIONS_EMULATOR_HOST`）。
3. **评估员不收推送**：`FcmService.suppressForStaff` 没有自动测试（要 Firebase Messaging）；真机用评估员账号登录后在 Firestore 看 `users/{uid}/fcm_tokens` 应为空。
4. **PHQ-9 规格文件**到了再接题目文字。
5. **T24** 合并后把 `w4Window` 改用它的研究周函数；**T35** 合并后在 `completionSummary` 加 W8。

## 架构优化观察（不在本任务改）

1. `functions/index.js` 已超过 2500 行、1300 条 lint 错误，每个任务都往里加函数；可以按领域拆成 `index.js` 只做 `exports.x = onCall(...)` 的薄壳，逻辑都在模块里（T30 已这样做：`assessor.js` 等只暴露纯函数，`index.js` 只包错误码）。
2. 角色判断散在五处（规则 `isUnblinded()`、`dashboard_access.dart`、`enrollment_service.dart`、`assessor_service.dart`、各 callable 的 `caller.role`）；可以在 `functions/roles.js` 和 `lib/core/auth/roles.dart` 各放一份角色常量和判断，减少改名时漏改。
3. 研究周 / 研究日的换算有三份（`functions/djg_w2.js`、`functions/pi_alert.js`、`lib/core/scheduling/w0_date.dart`），T24 定下共享函数后应统一，`assessor.js` 的 `w4Window` 也改用。
4. 导出有四套字段白名单（`blinding.js`、`process_export.js`、`analysis_export.js`、旧 `blindedDataExport`）；可以合成一份「字段登记表」（集合 → 字段 → 过程/结局/文字），四个导出都从它读，加一个「新集合没登记就报错」的测试。
5. Storage 没有规则文件在仓库里，导出的读权限完全靠「只有服务账号」；建议加 `storage.rules` 进 `firebase.json`，按前缀给角色读权限，并加进 CI。
6. `pi_alerts`、`safety_events`、`outcome_entries` 等顶层集合都靠 `uid` 字段找人，删除脚本要逐个登记；长远可以把这类集合统一放到 `users/{uid}/…` 下或维护一份「按 uid 索引的集合清单」给删除脚本和导出共用。

## 要 Junyu 定的事

| # | 事项 | 选项 | 建议 |
|---|---|---|---|
| 1 | 三个角色的含义（草稿一） | A. 按草稿一采纳；B. Calvin 也用 `unblinded` | A |
| 2 | 整人删除保留一行分配记录（草稿二），以及是否改成默认 | A. 采纳并改成默认（下一个 PR 一行改动）；B. 采纳但保持要带参数；C. 维持 T19 整条保留 | A，并同步 ICF/DMP 的措辞 |
| 3 | 锁库和分析导出（草稿三） | A. 采纳；B. 要加/减表（见第 6 节清单） | A |
| 4 | `assessorViewEnabled` 何时开 | 第一位参与者 W4 前（约 11/13）；或发角色当天就开 | 发角色当天开，让评估员先熟悉页面（名单那时还是空的或只有「未到期」） |
| 5 | 过程数据周导出要不要开、Storage 读权限要不要给 `unblinded` | A. 开 `processExportEnabled`，加 Storage 规则让 Junyu 直接下载；B. 开，但仍只用服务账号拿；C. 不开，锁库后一次导出 | B（最少改动；需要时再加规则） |
| 6 | 锁库前要不要停 `exports_v2`（`outcomeExportPaused`） | A. 第一位参与者 W2 前开（那之后才有结局数值）；B. 不停，反正只有服务账号能读 | A |
| 7 | PHQ-9 第 9 题 ≠ 0 的默认级别 | 同 T34 报告第 1 条：A. 一律 acute；B. 按答案分 | A（现状） |
| 8 | 完成率的分母口径 | A. 已到窗口开始日的人（现状）；B. 已过窗口结束日的人 | A |
| 9 | 评估员录入 PHQ-9 要不要在 App 里也开入口 | 规格文件到了再做；现在只有 DJG-ES | 等文件 |

## 要带回研究侧的发现

1. **DJG-ES W4 的「缺答」怎么算**：现在任一题缺答，该分量表不算分（和 App 内 W2 一致，`djg6_v1`）。如果统计分析计划允许按比例补或最多缺一题，要在规格文件第 4 节写明，代码一行改。
2. **W4 窗口的严格程度**：超窗照样录、只打标记（1010b 第 2 条）。分析时怎样处理超窗记录（纳入 / 敏感性分析）要写进分析计划；`outcome_entries.outOfWindow` 和 `studyDay` 都在导出里。
3. **PHQ-9 规格文件**仍未提供（10/10 第 9 条 (8)）；没有它，W4 纸本 PHQ-9 不能在 App 里录入，第 9 题的自动告警也不会触发。
4. **评估员和老人的接触方式**：录入页的「方式」是當面 / 電話 / 視像；如果研究侧还要记「谁施测」（Keran 还是 Mingyan）以外的信息（例如陪同者在场），要先说，现在只记录入账号。
5. **Storage 的读权限**和 **Owner 控制台权限**（4.3）只能靠操作规范和审计日志，protocol 的局限段落要写。
6. **退出者的研究编号**在 `allocation_records` 里保留（草稿二），ICF 的「删除」说法要对上。
7. **Calvin 的账号**：他需要一个 App 登录账号（电邮 + 密码）才能用自己的身份上传；上传时密码放在本机文件里传给脚本，不进命令历史。
