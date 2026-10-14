# T24 研究周和每周问卷（SPEC:C15、C17）

日期：2026-10-14。分支 `feat/weekly-schedule`，PR 草稿。任务单：`docs/dev-tasks/dev-tasks-1009.md`（第三版）、`dev-tasks-1010b.md` §二 T24、`dev-tasks-1014.md` §三 T24。

## 结论

1. **开关默认关**：`app_config/phase_b.weeklyScheduleV2Enabled`（文档不存在 = 关）。关着时一切和现在一样：星期日 20:00 开窗的日历周 Weekly PR / PGIC，T18 的第 14 天单次 DJG 照旧（测试：`test/weekly_schedule_test.dart` "switch off"、`functions/test/weekly_schedule_emulator_test.js` 第 1 条）。
2. **研究周**：W0 当天 = 第 0 天；第 k 天属于第 ceil(k/7) 周（第 1–7 天 = 第 1 周，第 8 天 = 第 2 周，第 29 天 = 第 5 周）。服务器 `functions/study_week.js`、App `lib/core/scheduling/study_week.dart`，两边用同一张表 `test/fixtures/study_week_table.json` 测（14 个点，含第 0、1、7、8、28、29 天和一个 UTC 时刻换算到香港日期的点）。T34 告警邮件的 `studyDay` 改用它。
3. **排程**（开关开时，Phase B 包 + 登记过的 `cohort`）：W1–W3 第 7、14、21 天 20:00 推送，推送后 3 × 24 小时内可答；W4 第 26 天 20:00 开，第 29 天结束关（= 第 30 天 00:00；T30 没合并，W4 面访日期的延长留了钩子）；W5–W7 第 35、42、49 天只推 PGIC；DJG 只在 W1–W3。试跑：第 1、3、5、7 天、1 天窗口、前三次有 DJG。两边同一张表 `test/fixtures/weekly_schedule_table.json`。
4. **流程**：首页一张卡片 → 开头说明（共几部分）→ DJG-ES 6 题 → Weekly PR → PGIC → 社会接触探针（S12，另有开关 `socialContactProbeEnabled` 默认关）。每部分顶上「第 N 部分，共 M 部分」，分开保存，中途停下再进来从第一个没做完的部分继续。两组同一个页面，没有 LLM，不看分组。
5. **记录**：每部分一份，编号 = 周次（`W1`…`W7`）。`studyWeek`、`studyDay`（推送那天）、`submittedStudyDay`、`pushedAt`、`windowStart`、`windowEnd`、`missed`、`scheduleMode` 只由服务器写；客户端写这些字段被规则拒绝（`test/rules/weekly_schedule_rules.test.js`，60 条规则测试全过）。`brief_pr` 按会话结束时间补 `studyWeek`、`studyDay`（跨午夜、跨第 7 → 第 8 天的会话归第 2 周，有测试）。
6. **推送**：新定时函数 `weeklyBundleDispatch`，按人发到 `fcm_tokens`（不再广播）；安静时段不发、下一小时再试；T18 的 24 小时提醒规则原样沿用；窗口过后服务器记缺失。推送、流程开头、部分名称都是【占位】文字，**推送带【占位】时服务器一条都不发**（和 T18 一样）。
7. **T18 的关系**：两个开关同时开时，研究周排程说了算：`djgW2Dispatch` 什么都不做，W2 的 DJG 由每周问卷在第 14 天推，存同一个集合 `djg_responses/W2`（同样的题、同样的服务器算分）。
8. **旧的每周孤独探针**：Phase B / 试跑不会出现（第 8 节），不用加开关。
9. **测试**：Flutter 六套、后端（单元、规则、模拟器、删除脚本）全过，见第 10 节。截图 13 张（第 11 节）。

## 1. 现状（改之前）

| 项目 | 现状 | 来源 |
|---|---|---|
| 每周问卷怎么排 | 按日历周：星期日 `weeklyPrPushHour`（20:00）开窗，开到星期二 23:59。PGIC 先问，再按本周用得最多的陪伴者问 Weekly PR；窗口过了没交，App 下次打开时写一条 `missed_{weekIso}` | `lib/features/weekly_pr/data/weekly_pr_window.dart`、`lib/core/scheduling/pending_prompts_service.dart` |
| 推送 | `weeklySurveyReminder` 星期日 20:00 对 FCM 主题 `all` 广播（没登记的人也收到），再给每个非测试账号写一条 `weekly_pr_pushed` 事件 | `functions/index.js` |
| 周次字段 | `weekly_pr.weekIso`（ISO 周，如 `2026-W44`）、`pgic.isoWeek` + `weekIso`、`loneliness_probes.isoWeek`。都是**日历周**，没有研究周 | `weekly_pr_response.dart`、`pgic_response.dart` |
| W0 从哪里来 | 登记时写的 `users/{uid}.w0Date`（T19 / T21），没有就用账号 `createdAt`：App `w0DateFor`，服务器 `djg_w2.js` `w0DateKey` | `lib/core/scheduling/w0_date.dart`、`functions/djg_w2.js` |
| 研究日 | 两种算法并存：`enrolmentDay`（W0 = 第 1 天，T18 的第 14 天 DJG 用它）；T34 `pi_alert.js` 的 `studyDay`（W0 = 第 0 天） | `lib/core/scheduling/enrolment_day.dart`、`functions/pi_alert.js` |
| DJG | T18：第 14 天 10:00 推一次，窗口第 14–20 天（按 W0 = 第 1 天算，即研究日第 13–19 天），存 `djg_responses/W2` | `functions/djg_w2.js` |
| Brief PR | T25 第二版：文档编号 = 会话编号，有 `sessionEndedAt`；`studyWeek` / `studyDay` 列为缺（等 T24） | `lib/features/brief_pr/data/brief_pr_record.dart` |

## 2. 开关和配置键

全部在 `app_config/phase_b`（App 读 `lib/core/config/phase_b_config.dart`，服务器读 `functions/weekly_schedule.js` `readConfig`）。文档不存在、字段缺、格式错 = 默认值；开关只认布尔 `true`。

| 键 | 默认 | 作用 |
|---|---|---|
| `weeklyScheduleV2Enabled` | **关** | 总开关。App 端还要求 Phase B 包（`PHASE_B=true`，决策 0037 保留）和登记过的 `cohort`（`phase_b` / `pilot`）；服务器只看 `cohort`，不推测试账号 |
| `weeklyBundleDays` | `[7, 14, 21, 26]` | W1–W4 的推送日（研究日，W0 = 0） |
| `weeklyWindowDays` | `3` | 推送后几个 24 小时内可答（W1–W3、W5–W7） |
| `week4CloseDay` | `29` | W4 到这一天结束关 |
| `djgWeeks` | `[1, 2, 3]` | 哪几周有 DJG |
| `pgicOnlyDays` | `[35, 42, 49]` | W5–W7 只推 PGIC 的日子 |
| `weeklyPushHour` | `20` | 推送钟点（香港）。**沿用现在每周推送的钟点 20:00**（`weeklySurveyReminder` 是星期日 20:00）。T18 的 DJG 是 10:00。要 Junyu 定（见最后一节） |
| `socialContactProbeEnabled` | **关** | 第 4 部分（S12） |
| `pilotBundleDays` | `[1, 3, 5, 7]` | 试跑 W1–W4 的推送日 |
| `pilotWindowDays` | `1` | 试跑窗口。两次推送相隔 2 天，窗口 1 天才不重叠（10/10 第 9 条 (4) 已确认） |
| `scheduleMode` | 不是键，由 `cohort` 推出 | `phase_b` → `standard`，`pilot` → `pilot`，其他 → 不排程 |
| `djgW2ReminderHours`（已有） | `24` | 提醒间隔，沿用 T18 的规则，不另加键 |

安静时段（和 PR #68 一起）：`app_config/reminders.quietHoursStart` / `quietHoursEnd`（默认 22:00–08:00）、`users/{uid}.quietHoursEnabled`（缺 = 开）。本任务的推送和提醒都先调 `functions/quiet_hours.js` `inQuietHours`，在时段内不发、下一小时再试（`functions/test/weekly_schedule_emulator_test.js` "quiet hours"）。默认时段 22:00–08:00 不会挡住 20:00 的推送；如果研究侧把安静时段改到覆盖推送钟点，推送会顺延到时段结束后的第一个整点（最晚 21:00，再晚就到第二天 08:00）。

## 3. 窗口的确切时刻

| 周 | 开（推送） | 关（不含） | 说明 |
|---|---|---|---|
| W1 | 第 7 天 20:00 | 第 10 天 20:00 | 3 × 24 小时。**「3 天内」= 推送后 72 小时**，不是三个日历日。研究侧核对口径 |
| W2 | 第 14 天 20:00 | 第 17 天 20:00 | 同上 |
| W3 | 第 21 天 20:00 | 第 24 天 20:00 | 同上 |
| W4 | 第 26 天 20:00 | 第 30 天 00:00（= 第 29 天结束） | `week4CloseFor(w0Date, w4VisitDate)`：取第 29 天结束和 W4 面访当天结束中较晚的；**T30 没合并，所有调用处现在传 null，只按第 29 天关**。函数和三种情况（面访第 27 天 → 第 29 天关；第 31 天 → 第 31 天结束关；没有日期 → 第 29 天关）已有测试，接上 T30 时只改调用处（backlog 104） |
| W5–W7 | 第 35、42、49 天 20:00 | 各 + 72 小时 | 只有 PGIC |
| 试跑 W1–W4 | 第 1、3、5、7 天 20:00 | 各 + 24 小时 | DJG 在前三次 |

W4 面访前没答完的：窗口到第 29 天结束都开着，评估员做完结局评估后老人用自己的手机进同一个流程补答，评估员不看（流程本来就只在老人手机上）。

## 4. 研究周函数（T35、T25 直接调用）

| 用途 | 服务器 | App |
|---|---|---|
| 时间点 → 研究日 | `functions/study_week.js` `studyDayAt(w0Key, date)`（香港日期）、`studyDayOf(w0Key, dateKey)` | `lib/core/scheduling/study_week.dart` `studyDayOf(w0, now)` |
| 研究日 → 研究周 | `studyWeekOf(day)` | `studyWeekOf(day)` |
| 时间点 → 两者 | `studyPositionAt(w0Key, date)` → `{studyDay, studyWeek}` | `studyWeekAt(w0, now)` |
| W0 | `w0DateKey(user)`（从 `djg_w2.js` 搬来，那边保留转调） | `w0DateFor(profile)`（不变） |
| 排程 | `functions/weekly_schedule.js`：`bundlesFor(cfg, mode)`、`windowFor(bundle, w0Key, cfg, {w4VisitDate})`、`openBundleAt`、`week4CloseFor`、`referentRangeFor` | `lib/core/scheduling/weekly_schedule.dart` `WeeklySchedule.*` 同名 |
| 记录盖章 | `stampPartRecord(db, uid, collection, docId, after)`（带 `bundle` 的记录补研究周字段，幂等）；`stampBriefPr(db, uid, docId, after)` | — |
| 记缺失 | `markMissedParts(userRef, {...})`：没交的每一部分写一份 `status: missed` | — |
| 推送 / 提醒 / 缺失 | `dispatchWeeklyBundles(db, messaging, {now, copy, quiet})` | — |
| 流程页 | — | `lib/features/weekly_bundle/presentation/weekly_bundle_flow_page.dart` `WeeklyBundleFlowPage`（传一个 `WeeklyBundle` 就能跑 W8：部分列表、顺序、「第 N 部分，共 M 部分」、分开保存、中途继续都在里面）|
| 部分状态 | `partSubmitted(part, data)` | `WeeklyPartStatus.isFinal(part, data)`（同一条规则） |

## 5. 流程和顺序

- 入口：首页卡片「【占位】每週問卷」（`lib/features/today/presentation/widgets/pending_prompts_banner.dart`），只在窗口内、还有部分没做完时出现（`PendingPromptsService.weeklyBundleDue`）。开关开时，旧的星期日 Weekly PR / PGIC 卡片、T18 的 W2 卡片、Phase A 的 `djg_es` 都不再出现。
- 顺序：DJG-ES（`djgWeeks`）→ Weekly PR → PGIC → 社会接触探针（开关开时）。没有 DJG 的周从 Weekly PR 开始；W5–W7 只有 PGIC。
- Weekly PR 的「本周用得最多的陪伴者」按这一研究周的会话算（`referentRangeFor`：第 7(k−1)+1 天 00:00 到推送那一刻；试跑：上一次推送到这一次推送）。没有陪伴者会话 → 写一条 `no_referent`，这一部分算完成，直接到 PGIC（和现在一样）。
- DJG：题目、选项、一屏一题、可返回、可跳题、跳题记缺失、服务器算分，全部沿用 T18 的页面和 `scoreAnswers`，只加了「第 N 部分，共 M 部分」和标题参数。
- 社会接触探针：两题各一屏，四档「冇／1 至 2 日／3 至 4 日／5 日或以上」存 0–3，题目和小字照 `docs/spec/copy/short-texts.md` S12 逐字（测试 `test/weekly_bundle_flow_test.dart` "S12 verbatim" 直接读那份文件比对）。
- 每部分提交后流程页从存储重读状态；离开一半的部分记 `in_progress`，下次「繼續」直接进那一部分；DJG 和探针还会跳到第一道没答的题。

## 6. 记录

每部分一份，文档编号 = 周次：

| 集合 | App 写 | 服务器写 |
|---|---|---|
| `users/{uid}/djg_responses/{W1\|W2\|W3}` | T18 的字段 + `bundle` | T18 的 `scores`、`scoringVersion`、`scoredAt` + 下面的研究周字段 |
| `users/{uid}/weekly_pr/{Wn}` | `WeeklyPrResponse` 的字段 + `bundle` | 研究周字段 |
| `users/{uid}/pgic/{Wn}` | `value`、`answeredAt`、`weekIso` + `bundle` | 研究周字段 |
| `users/{uid}/social_contact_probes/{W1…W4}` | `bundle`、`itemsVersion: s12_v1`、`answers {q1, q2: 0–3}`、`status`、时间 | 研究周字段 |
| `users/{uid}/brief_pr/{sessionId}` | T25 的字段 | `studyWeek`、`studyDay`（按 `sessionEndedAt`；旧记录退回 `respondedAt`）、`studyWeekBasis` |
| `weekly_status/{uid}` | — | `researchId`、`scheduleMode`、`w0Date`、`bundles.{Wn}.{pushedAt, reminderSentAt, missedAt, missedParts, windowStart, windowEnd, studyWeek, studyDay}`。**客户端不能读写**（研究编号不进老人能读的文档，决策 0021；同 T17b 的 `ada_status`） |

研究周字段（服务器写，规则拒绝客户端）：`studyWeek`（推送那天的研究周）、`studyDay`（推送那天）、`submittedStudyDay`（提交那天，缺失为空）、`pushedAt`（实际推送时间，占位文字时为空）、`windowStart`、`windowEnd`、`missed`（布尔）、`missedAt`、`scheduleMode`（`standard` / `pilot`）、`stampedAt`。试跑的 `studyWeek` 按同一条公式算（第 1、3、5、7 天都是第 1 周），周次标签看 `bundle`（W1–W4）。

规则（`firestore.rules`）：`weekly_pr`、`pgic`、`brief_pr`、`social_contact_probes` 的创建不能带这些字段，更新不能改它们（服务器已写的值原样带着不算改）；`djg_responses` 允许 `W1`、`W2`、`W3`；探针记录的答案只能是 0–3 的整数、提交时间必须是服务器时间、提交或缺失后冻结、不能删；`weekly_status` 没有客户端能读写。

导出：`functions/blinding.js` 白名单加了 `social_contact_probes` 和各记录的研究周字段；`tool/check_blinded_export.js` 同步。删除：`tool/delete_participant.js` 加 `weekly_status`（子集合本来就按树遍历），测试计数 32 → 34。

## 7. 推送、提醒、缺失（`weeklyBundleDispatch`）

每小时 08:00–21:00（香港）跑一次，只看 `cohort` 是 `phase_b` / `pilot` 的非测试账号，不看组别：

1. 窗口一开（`now >= 推送时刻`）、还没推过：安静时段内 → 记 `quiet_hours`，下一小时再看；推送文字带【占位】→ 记 `blocked_placeholder`，不发（**现在就是这个状态**）；否则按 `fcm_tokens` 逐台推，写 `weekly_status` 和事件 `weekly_bundle_push_sent`。
2. 推送后满 `djgW2ReminderHours`（24）小时（留 5 分钟余量）、还有部分没交 → 提醒一次（同样看安静时段和占位），事件 `weekly_bundle_reminder_sent`。
3. 窗口关了：没交的每一部分写一份 `status: missed`（DJG 答了一半也算缺失，答案保留），事件 `weekly_bundle_missed`。只在关窗后 7 天内补，所以开关中途打开不会把早已过去的周全记缺失。
4. 不补推。

旧推送：开关开时 `weeklySurveyReminder` 不再广播主题 `all`，改为按人发给「不在研究周排程里」的账号（不是 Phase B / 试跑、不是测试员、登记门关着时），事件 `weekly_pr_pushed` 的 `channel` 变 `fcm_token`；登记门一开就没有人收到。开关关时照旧广播（和现在完全一样）。`dailyMoodReminder` 仍是广播，没有改（backlog 105）。

推送文字（草稿，`functions/weekly_schedule.js`）：标题「陪住」；「【占位】今個禮拜嘅問卷已經開咗，得閒入嚟答幾條。」「【占位】今個禮拜嘅問卷仲未答完，得閒入嚟答埋佢。」定稿后替换、去掉【占位】才会发，STUDY_CHANGELOG 补一行。

## 8. 旧的每周孤独探针（1014 §三 T24 第 3 条）

**Phase B / 试跑不会出现**，三道锁都关着，不用再加开关：
1. `lib/features/loneliness_probe/presentation/loneliness_probe_page.dart` 的 `LonelinessProbePage` 没有任何页面引用它（`grep -rn LonelinessProbePage lib` 只有它自己）；
2. 编译开关 `WEEKLY_PROBE`（`lib/core/feature_flags/feature_flags.dart` `weeklyProbeEnabled`）默认 `false`，参与者包不带；
3. 服务器 `weeklyLonelinessProbe` 只给 `users/{uid}.weeklyProbeEnabled === true` 的账号排队，登记不写这个字段。
建议 Phase A 代码清理时一起删（backlog 107）。

## 9. 试跑压缩时其他按日期出现的环节（交 T28）

| 环节 | 现在 | 试跑压缩下 |
|---|---|---|
| T18 第 14 天 DJG | 开关开时由每周问卷取代 | 第 5 天（W3）|
| 首页第 3、6 天「你仲未同 X 傾過」提示 | Phase B 包已隐藏（#65） | 不出现 |
| 每日心情提醒 | 周一至六 19:00 广播 | 不变 |
| W4 面访、W8 问卷 | T30 / T35 | 试跑没有 W5–W7 的 PGIC；W4 = 第 7 天 |
| Brief PR 的研究周 | 按会话结束时间 | 第 1–7 天都是第 1 周 |

## 10. 测试

| 任务单第 8 节 | 测试 | 结果 |
|---|---|---|
| 1. W0 星期一到日各一人，跑 8 周 | `functions/test/weekly_schedule_test.js` "date table"（7 个 W0 × 7 周：推送日、3 × 24 小时、W4 第 29 天结束、DJG 只在 W1–W3、第 8 周不推）；`test/weekly_schedule_test.dart` "date table" 同样 49 行 | 过（表在第 12 节） |
| 2. 第 4 周关闭：面访第 27 / 31 天 / 没有 | 两边 "week-4 close"（`week4CloseFor`） | 过 |
| 3. 边界第 0、1、7、8、28、29 天；App 和服务器一样；客户端写被拒 | `functions/test/study_week_test.js` + `test/study_week_test.dart` 读同一张 `test/fixtures/study_week_table.json`；`test/rules/weekly_schedule_rules.test.js`（4 个集合 × 11 个字段的创建、更新） | 过 |
| 4. Brief PR 跨午夜、跨第 7 → 8 天归第 2 周 | `weekly_schedule_emulator_test.js` "brief_pr"（第 7 天 23:00 开始、第 8 天 00:30 结束 → `studyWeek 2`、`studyDay 8`；第 7 天 23:59 结束 → 第 1 周；旧记录退回 `respondedAt`） | 过 |
| 5. 流程顺序、中途继续；探针开关开时有第 4 部分、题目和 S12 逐字 | `test/weekly_bundle_flow_test.dart`（13 条：顺序 1/3 → 2/3 → 3/3、无陪伴者直接到 PGIC、「繼續」直接进第 2 部分、DJG 跳到第 3 题、第 4 部分 S12 两屏存 0–3、只有 PGIC 的周、截止文字） | 过 |
| 6. 试跑第 1、3、5、7 天、前三次 DJG；非试跑不受影响 | 两边 "pilot bundles"；`weekly_schedule_emulator_test.js` "pilot account" | 过 |
| 7. 总开关关 = 现在；Phase A 不变；两组相同 | `weekly_schedule_emulator_test.js` 第 1 条（关）、"W1 timeline"（两组推送内容逐字节相同、Phase A / 测试员 / 未登记不推）；`test/weekly_schedule_test.dart` "gate"（关 → 关；默认包 → 关）、"no arm check"（源码不引用分组） | 过 |
| 占位推送不发；安静时段；提醒一次；缺失一次 | `weekly_schedule_emulator_test.js` | 过 |
| T18 让位、W1–W3 算分 | `weekly_schedule_emulator_test.js` "T18 stands down"；`functions/test/djg_w2_test.js` | 过 |

整套（按 common.md 第 3 节）：

| 命令 | 结果 |
|---|---|
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | 0 个 error；88 条 info / warning（全部是 main 上已有的） |
| `tool/ci_flutter_tests.sh`（六套） | 六套全过：默认包 566 个测试、Phase B 分组 133、Phase B 规则组页面 5、记忆 v1 18、模板回复（只开开关）31、模板回复（开）31 |
| `flock /tmp/firebase-emulator.lock tool/ci_backend_tests.sh` | 全过：Functions 单元测试（含新 `study_week_test.js` 6 条、`weekly_schedule_test.js` 12 条、`quiet_hours_test.js` 9 条）；规则测试 159 条（含新 `weekly_schedule_rules.test.js`）；模拟器测试（含新 `weekly_schedule_emulator_test.js` 10 条、`djg_w2_emulator_test.js` 7 条）；删除 / 同意 / 清理脚本 5 + 4 + 4 条。第一次整套跑时删除脚本测试的「还在的地方」计数因新加 `weekly_status` 从 13 变 14，改了测试里的数字后单独重跑该组通过 |

## 11. 截图

`docs/dev-reports/T24-weekly-schedule-20261014-screenshots/`（`flutter test …/t24_shots_test.dart` 渲染，412 宽，合成数据，不连 Firebase）：

| 文件 | 内容 |
|---|---|
| `A1_w1_intro_3_parts.png` | 有 DJG 的周（W1）：开头说明，3 部分 |
| `A2_w1_part1_djg_item1.png` | 第 1 部分 DJG 第 1 题，顶上「第 1 部分，共 3 部分」 |
| `A3_w1_part2_weekly_pr.png` | 第 2 部分 Weekly PR |
| `A4_w1_part3_pgic.png` | 第 3 部分 PGIC |
| `A5_w1_resume_half_way.png` | 中途继续：第 1 部分已完成、第 2 部分做了一半 |
| `B1_w4_intro_2_parts_no_djg.png`、`B2_w4_part2_pgic.png` | 没有 DJG 的周（W4）：2 部分 |
| `C1_w6_intro_pgic_only.png`、`C2_w6_part1_pgic.png` | 只有 PGIC 的周（W6）：1 部分 |
| `D1_w1_intro_4_parts_social_on.png`、`D2_s12_item1.png`、`D3_s12_item2.png` | 探针开关开：4 部分；S12 两屏 |
| `E1_all_done.png` | 全部做完 |

已知：按钮上的字（「開始」「上一題」「提交」）在测试机上显示成方块，是测试机的字体回退问题（按钮用的字体没装），手机上正常；其他文字都正常。

## 12. 日期表（第 8 节第 1 条）

W0 在星期一到星期日各一人，正式排程、默认配置。关闭时刻不含（第 10 天 20:00 关 = 20:00 整已经不能答）。

| W0（星期） | 周 | 推送日 | 推送时刻（香港） | 关闭时刻（香港） | 部分 |
|---|---|---|---|---|---|
| 2026-10-19（一） | W1 | 第 7 天 | 2026-10-26 20:00 | 2026-10-29 20:00 | djg → weekly_pr → pgic |
| 2026-10-19（一） | W2 | 第 14 天 | 2026-11-02 20:00 | 2026-11-05 20:00 | djg → weekly_pr → pgic |
| 2026-10-19（一） | W3 | 第 21 天 | 2026-11-09 20:00 | 2026-11-12 20:00 | djg → weekly_pr → pgic |
| 2026-10-19（一） | W4 | 第 26 天 | 2026-11-14 20:00 | 2026-11-18 00:00（第 29 天结束） | weekly_pr → pgic |
| 2026-10-19（一） | W5 | 第 35 天 | 2026-11-23 20:00 | 2026-11-26 20:00 | pgic |
| 2026-10-19（一） | W6 | 第 42 天 | 2026-11-30 20:00 | 2026-12-03 20:00 | pgic |
| 2026-10-19（一） | W7 | 第 49 天 | 2026-12-07 20:00 | 2026-12-10 20:00 | pgic |
| 2026-10-20（二） | W1 | 第 7 天 | 2026-10-27 20:00 | 2026-10-30 20:00 | djg → weekly_pr → pgic |
| 2026-10-20（二） | W2 | 第 14 天 | 2026-11-03 20:00 | 2026-11-06 20:00 | djg → weekly_pr → pgic |
| 2026-10-20（二） | W3 | 第 21 天 | 2026-11-10 20:00 | 2026-11-13 20:00 | djg → weekly_pr → pgic |
| 2026-10-20（二） | W4 | 第 26 天 | 2026-11-15 20:00 | 2026-11-19 00:00（第 29 天结束） | weekly_pr → pgic |
| 2026-10-20（二） | W5 | 第 35 天 | 2026-11-24 20:00 | 2026-11-27 20:00 | pgic |
| 2026-10-20（二） | W6 | 第 42 天 | 2026-12-01 20:00 | 2026-12-04 20:00 | pgic |
| 2026-10-20（二） | W7 | 第 49 天 | 2026-12-08 20:00 | 2026-12-11 20:00 | pgic |
| 2026-10-21（三） | W1 | 第 7 天 | 2026-10-28 20:00 | 2026-10-31 20:00 | djg → weekly_pr → pgic |
| 2026-10-21（三） | W2 | 第 14 天 | 2026-11-04 20:00 | 2026-11-07 20:00 | djg → weekly_pr → pgic |
| 2026-10-21（三） | W3 | 第 21 天 | 2026-11-11 20:00 | 2026-11-14 20:00 | djg → weekly_pr → pgic |
| 2026-10-21（三） | W4 | 第 26 天 | 2026-11-16 20:00 | 2026-11-20 00:00（第 29 天结束） | weekly_pr → pgic |
| 2026-10-21（三） | W5 | 第 35 天 | 2026-11-25 20:00 | 2026-11-28 20:00 | pgic |
| 2026-10-21（三） | W6 | 第 42 天 | 2026-12-02 20:00 | 2026-12-05 20:00 | pgic |
| 2026-10-21（三） | W7 | 第 49 天 | 2026-12-09 20:00 | 2026-12-12 20:00 | pgic |
| 2026-10-22（四） | W1 | 第 7 天 | 2026-10-29 20:00 | 2026-11-01 20:00 | djg → weekly_pr → pgic |
| 2026-10-22（四） | W2 | 第 14 天 | 2026-11-05 20:00 | 2026-11-08 20:00 | djg → weekly_pr → pgic |
| 2026-10-22（四） | W3 | 第 21 天 | 2026-11-12 20:00 | 2026-11-15 20:00 | djg → weekly_pr → pgic |
| 2026-10-22（四） | W4 | 第 26 天 | 2026-11-17 20:00 | 2026-11-21 00:00（第 29 天结束） | weekly_pr → pgic |
| 2026-10-22（四） | W5 | 第 35 天 | 2026-11-26 20:00 | 2026-11-29 20:00 | pgic |
| 2026-10-22（四） | W6 | 第 42 天 | 2026-12-03 20:00 | 2026-12-06 20:00 | pgic |
| 2026-10-22（四） | W7 | 第 49 天 | 2026-12-10 20:00 | 2026-12-13 20:00 | pgic |
| 2026-10-23（五） | W1 | 第 7 天 | 2026-10-30 20:00 | 2026-11-02 20:00 | djg → weekly_pr → pgic |
| 2026-10-23（五） | W2 | 第 14 天 | 2026-11-06 20:00 | 2026-11-09 20:00 | djg → weekly_pr → pgic |
| 2026-10-23（五） | W3 | 第 21 天 | 2026-11-13 20:00 | 2026-11-16 20:00 | djg → weekly_pr → pgic |
| 2026-10-23（五） | W4 | 第 26 天 | 2026-11-18 20:00 | 2026-11-22 00:00（第 29 天结束） | weekly_pr → pgic |
| 2026-10-23（五） | W5 | 第 35 天 | 2026-11-27 20:00 | 2026-11-30 20:00 | pgic |
| 2026-10-23（五） | W6 | 第 42 天 | 2026-12-04 20:00 | 2026-12-07 20:00 | pgic |
| 2026-10-23（五） | W7 | 第 49 天 | 2026-12-11 20:00 | 2026-12-14 20:00 | pgic |
| 2026-10-24（六） | W1 | 第 7 天 | 2026-10-31 20:00 | 2026-11-03 20:00 | djg → weekly_pr → pgic |
| 2026-10-24（六） | W2 | 第 14 天 | 2026-11-07 20:00 | 2026-11-10 20:00 | djg → weekly_pr → pgic |
| 2026-10-24（六） | W3 | 第 21 天 | 2026-11-14 20:00 | 2026-11-17 20:00 | djg → weekly_pr → pgic |
| 2026-10-24（六） | W4 | 第 26 天 | 2026-11-19 20:00 | 2026-11-23 00:00（第 29 天结束） | weekly_pr → pgic |
| 2026-10-24（六） | W5 | 第 35 天 | 2026-11-28 20:00 | 2026-12-01 20:00 | pgic |
| 2026-10-24（六） | W6 | 第 42 天 | 2026-12-05 20:00 | 2026-12-08 20:00 | pgic |
| 2026-10-24（六） | W7 | 第 49 天 | 2026-12-12 20:00 | 2026-12-15 20:00 | pgic |
| 2026-10-25（日） | W1 | 第 7 天 | 2026-11-01 20:00 | 2026-11-04 20:00 | djg → weekly_pr → pgic |
| 2026-10-25（日） | W2 | 第 14 天 | 2026-11-08 20:00 | 2026-11-11 20:00 | djg → weekly_pr → pgic |
| 2026-10-25（日） | W3 | 第 21 天 | 2026-11-15 20:00 | 2026-11-18 20:00 | djg → weekly_pr → pgic |
| 2026-10-25（日） | W4 | 第 26 天 | 2026-11-20 20:00 | 2026-11-24 00:00（第 29 天结束） | weekly_pr → pgic |
| 2026-10-25（日） | W5 | 第 35 天 | 2026-11-29 20:00 | 2026-12-02 20:00 | pgic |
| 2026-10-25（日） | W6 | 第 42 天 | 2026-12-06 20:00 | 2026-12-09 20:00 | pgic |
| 2026-10-25（日） | W7 | 第 49 天 | 2026-12-13 20:00 | 2026-12-16 20:00 | pgic |

试跑（W0 = 2026-10-19）：W1 10-20 20:00 → 10-21 20:00（DJG）；W2 10-22 → 10-23（DJG）；W3 10-24 → 10-25（DJG）；W4 10-26 20:00 → 10-27 20:00（没有 DJG）。

## 13. 老人看得到的文字

题目、选项（DJG 问卷包 §3、Weekly PR、PGIC、S12）不是草稿。以下是草稿，研究侧定稿后替换：

| 位置 | 草稿 | 文件 |
|---|---|---|
| 推送、提醒 | 第 7 节两句 | `functions/weekly_schedule.js` |
| 首页卡片 | 「【占位】每週問卷」「【占位】分 N 部分，可以分開做。」「【占位】一條問題，好快答完。」 | `pending_prompts_banner.dart` |
| 流程标题 | 「【占位】每週問卷」 | `weekly_bundle_flow_page.dart` |
| 开头说明 | 「【占位】一共有 N 部分。可以隨時停，下次會由停低嗰度繼續。」「【占位】全部做完喇，多謝你！」 | 同上 |
| 部分名称 | 「【占位】最近嘅感受（6 條）」「【占位】每週夥伴評估」「【占位】每週感受變化」「【占位】過去 7 日嘅社交接觸」 | 同上 |
| 状态 | 「【占位】未開始」「【占位】做咗一半」「【占位】已完成」「【占位】已截止」 | 同上 |
| 按钮 | 「開始」「繼續」「完成」「上一題」（沿用 T17b / T18 已用的字） | 同上 |
| 部分标头 | 「第 N 部分，共 M 部分」（T17b 已用的式样） | `weekly_part_header.dart` |

## 14. 改了哪些文件

服务器：`functions/study_week.js`（新）、`functions/weekly_schedule.js`（新）、`functions/djg_w2.js`（`w0DateKey` 转调；排程开时让位、W1–W3 算分）、`functions/pi_alert.js`（`studyDay` 用共享函数）、`functions/index.js`（`weeklySurveyReminder` 按人发；新 `weeklyBundleDispatch`、`onWeeklyPrWritten`、`onPgicWritten`、`onSocialContactProbeWritten`、`onBriefPrWritten`；导出列表）、`functions/blinding.js`、`tool/check_blinded_export.js`、`tool/delete_participant.js`、`firestore.rules`。
App：`lib/core/config/phase_b_config.dart`、`lib/core/scheduling/study_week.dart`（新）、`lib/core/scheduling/weekly_schedule.dart`（新）、`lib/core/scheduling/pending_prompts_service.dart`、`lib/features/weekly_bundle/**`（新：`data/weekly_bundle.dart`、`presentation/weekly_bundle_flow_page.dart`、`social_contact_probe_page.dart`、`weekly_part_header.dart`）、`lib/features/assessment/data/djg_w2.dart`、`lib/features/assessment/presentation/pages/djg_w2_page.dart`、`pgic_page.dart`、`lib/features/weekly_pr/presentation/pages/weekly_pr_page.dart`、`lib/features/weekly_pr/data/weekly_pr_trigger.dart`、`lib/features/today/presentation/widgets/pending_prompts_banner.dart`。
测试：`test/fixtures/study_week_table.json`、`test/fixtures/weekly_schedule_table.json`（新，两边共用）、`functions/test/study_week_test.js`、`functions/test/weekly_schedule_test.js`、`functions/test/weekly_schedule_emulator_test.js`、`test/rules/weekly_schedule_rules.test.js`（+ `package.json`）、`test/study_week_test.dart`、`test/weekly_schedule_test.dart`、`test/weekly_bundle_flow_test.dart`、`test/delete_participant/delete_participant_test.js`、`tool/ci_flutter_tests.sh`。
文档：`docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`（新 6.2 节、第 8、9 节）、`docs/history.md`、`docs/dev/backlog.md`（103–107）、本报告和截图。

## 15. 和其他 PR 的交叉

| PR | 交叉 |
|---|---|
| T25 `feat/session-briefpr`（#67，已合并，本分支已并入） | `lib/core/config/phase_b_config.dart` 同一个类加键（已合并两边）；`brief_pr` 的 `studyWeek` / `studyDay` 由本任务的 `onBriefPrWritten` 按 T25 的 `sessionEndedAt` 补，T25 报告里「列为缺」的那两项现在有了 |
| 安静时段 `fix/quiet-hours-hide-readback`（#68，已合并） | 本任务直接 `require("./quiet_hours")`，没有自己的副本；`dispatchWeeklyBundles` 每次推送、提醒前都调 `inQuietHours` |
| T30 `fix/roles-exports` | W4 面访日期：`week4CloseFor` 的第二个参数现在传 null；T30 合并后把评估员录入的施测日期接进 `functions/weekly_schedule.js` `windowFor` 的 `opts.w4VisitDate` 和 App `PendingPromptsService.weeklyBundleDue`（backlog 104）。`firestore.rules`、`functions/index.js`、`functions/blinding.js` 两边都改，后合并的处理冲突 |
| T27 `feat/stt-server` | `functions/index.js`（不同函数） |
| T32 `feat/phase-a-final`（#69 已合并） | `tool/delete_participant.js`、`docs/*` 已并入 |
| T35（之后开） | 直接用第 4 节的函数：`bundlesFor` 加 W8 一项、`WeeklyBundleFlowPage` 传 W8 的 `WeeklyBundle`、`markMissedParts` / `stampPartRecord` 不用改 |
| T28 | 第 9 节的表 |

## 决策记录草稿（编号待开发窗口分配）

# 00NN：研究周从 W0 算、每周问卷按研究周推送并做成一个流程（开关默认关）

- 日期：2026-10-14
- 状态：提议中（随 T24 的 PR 草稿，合并即采纳）
- 影响范围：phase_b、pilot × 两组（相同）
- 相关代码：分支 `feat/weekly-schedule`（`functions/study_week.js`、`functions/weekly_schedule.js`、`lib/core/scheduling/study_week.dart`、`lib/core/scheduling/weekly_schedule.dart`、`lib/features/weekly_bundle/`、`firestore.rules`）

## 背景

研究侧 10/9 第 11 条及更正、第 22 条、第 26 条 (3)：研究周从 W0 面访当天起算，每周问卷在第 7、14、21 天推、第 4 周第 26 天开、PGIC 到第 7 周，试跑压缩到第 1、3、5、7 天。现在的每周问卷按日历周（星期日开窗），记的是 ISO 周，和研究周对不上；推送是广播。

## 决定

1. 研究周：W0 = 第 0 天，第 k 天属于第 ceil(k/7) 周。一个函数，服务器和 App 各一份，同一张测试表。
2. 每周问卷按研究周推送，窗口从推送那一刻起 3 × 24 小时；第 4 周到第 29 天结束（面访晚于第 29 天时延到面访当天结束，接 T30）；第 5–7 周只有 PGIC。试跑第 1、3、5、7 天、1 天窗口。
3. 一个流程、固定顺序（DJG → Weekly PR → PGIC → 社会接触探针）、每部分分开保存、中途可续。
4. 每部分一份记录，研究周字段只由服务器写；Brief PR 按会话结束时间归周。研究编号只在服务器专用的 `weekly_status`。
5. 推送按人发、看安静时段、沿用 T18 的提醒规则；过窗口服务器记缺失、不补推。
6. 开关 `weeklyScheduleV2Enabled` 默认关；开时 T18 的第 14 天推送不发、旧的星期日广播不发给 Phase B / 试跑。社会接触探针另有开关默认关。推送钟点先沿用 20:00，Junyu 定。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 继续按日历周，另存研究周字段 | 推送日和研究周对不上（星期日推送可能是第 3 天，也可能是第 9 天），研究侧要的是「第 7 天推」 |
| 窗口按日历日（第 7、8、9 天） | 推送 20:00 的话第一天只剩 4 小时；研究侧口径是「3 天内」，按 72 小时更公平。报告写明确切时刻请研究侧核对 |
| 缺失由 App 打开时写（现有 Weekly PR 的做法） | 老人整个窗口没开 App 就永远没有缺失记录（同决策 0027） |
| 客户端自己写 `studyWeek` | 可改；研究周决定数据归哪一周，保守做法是服务器写 |
| 每周一份大记录 | 四个部分来源不同（DJG 服务器算分、Weekly PR 看陪伴者），分开存最接近现有结构，T35 也好复用 |

## 后果

- 对研究：Phase B 每周问卷从日历周改为研究周；每条问卷和 Brief PR 都有 `studyWeek` / `studyDay`；缺失由服务器统一记。protocol 里「推送后 3 天内」应写成 72 小时。
- 对开发：新集合 `social_contact_probes`、`weekly_status`；新定时函数；`enrolmentDay`（W0 = 第 1 天）和 `studyDay`（W0 = 第 0 天）并存，T18 的旧路径关掉前不能删。
- 对论文：方法部分写每周问卷在第 7、14、21、26 天推送、72 小时窗口；W5–W7 只有 PGIC。

## 要 Junyu 定的事

1. **推送钟点** `weeklyPushHour`：任务单说沿用现在每周推送的钟点，所以默认 20:00。选项：(a) 20:00（现状；窗口第 10 天 20:00 关）；(b) 10:00（T18 的 DJG 钟点，白天收推送，窗口第 10 天 10:00 关）；(c) 其他。**建议 (b) 10:00**：老人白天看手机，安静时段再怎么改也挡不住，而且和 T18 的 DJG 一致。改一个数字即可，不用改代码。
2. **「3 天内」的口径**：现在是推送后 72 小时（第 10 天 20:00 关）。选项：(a) 72 小时；(b) 到第 10 天结束（24:00）。**建议 (a)**，和任务单「从推送那一刻起开 3 天」一致；研究侧核对。
3. **`brief_pr` 的周次是否也归总开关管**：现在 `onBriefPrWritten` 只在 `weeklyScheduleV2Enabled` 开时补字段（新行为一律在开关后面）。选项：(a) 照现在；(b) 不管开关都补（第一位参与者登记后开关还没开的那几天也有周次）。**建议 (b)**，字段只是加、不影响老人；一行代码。
4. **流程里的按钮字**「開始」「繼續」「完成」「上一題」没加【占位】（沿用 T17b / T18 已用的字）。选项：(a) 照现在；(b) 全部加【占位】等定稿。建议 (a)。
5. **每日心情提醒**仍是广播（backlog 105）。选项：(a) 先不改；(b) 和每周推送一样改成按人发、看安静时段。建议 (b)，但另开任务。

## 要带回研究侧的发现

1. 窗口关闭的确切时刻：推送后 72 小时（第 7 天 20:00 推 → 第 10 天 20:00 关），不是「第 10 天结束」。请确认。
2. 第 4 周：第 26 天 20:00 开、第 30 天 00:00 关（= 第 29 天结束）。面访晚于第 29 天的延长要等 T30 的施测日期。
3. 试跑的 `studyWeek`：第 1、3、5、7 天按公式都是第 1 周；周次标签在 `bundle`（W1–W4）。分析时试跑用 `bundle`，正式用 `studyWeek`（两者在正式排程里一致）。
4. 社会接触探针只在 W1–W4（任务单：第 1 至第 4 周）；W5–W7 只有 PGIC。开关默认关，打开前 S12 已经逐字接入。
5. Weekly PR 的「本周用得最多的陪伴者」按研究周的会话算（第 7(k−1)+1 天 00:00 到推送那一刻）；W4 是第 22 天到第 26 天 20:00（不是整周）。
6. DJG 答了一半过窗口算缺失（分量表为空），答案保留；和 T18 一致。
7. 没有任何 LLM 调用；两组推送内容逐字节相同（有测试）。

## 架构优化观察（不在本任务改）

1. `lib/core/scheduling/enrolment_day.dart`（W0 = 第 1 天）和 `study_week.dart`（W0 = 第 0 天）并存，`functions/djg_w2.js` 的 `windowState` 也是前者。提议：T18 旧路径下线后统一到 `study_week`，`djgW2DayOffset` 改成研究日。
2. `functions/index.js` 2500 行，定时函数和触发器的注册和业务混在一起。提议：按模块各建一个 `functions/triggers/<module>.js` 只做注册，`index.js` 只 `Object.assign(exports, …)`。
3. `lib/core/scheduling/pending_prompts_service.dart` 的 `shouldShowOnHomeNow` 已经串了 Phase A 的 Weekly PR、W2、ADA、第 7 日和 Phase B 的 DJG、每周问卷六套判断。提议：拆成每套一个 `HomeCardProvider`，列表按 cohort 装配。
4. `PgicPage`、`WeeklyPrPage` 直接用 `FirebaseFirestore.instance` 写库，测试只能靠「没有 profile 就不写」绕过。提议：像 `DjgW2Store` 那样抽一个存储接口。
5. `functions/djg_w2.js` 和 `functions/ada.js`、`functions/weekly_schedule.js` 各有一份 `sendToDevices` / `isPlaceholder` / `lookupResearchId`。提议：抽到 `functions/push.js`。
6. `firestore.rules` 的「研究周字段服务器专用」靠集合名单 `weekStampedCollections()`；T35 加集合要记得改。提议：把 T24 的记录统一放一个前缀集合（如 `survey_parts/{Wn}_{part}`），规则一条管全部。
7. `docs/dev/architecture.md` 头部已有三行并行 PR 各加的「最后核对」，合并时没有合成一行。提议：改成按日期的列表。
