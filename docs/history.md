# 开发记录

按时间记下做过什么、讨论过什么。最新的在最上面。设计决定的理由见 `docs/decisions/`，参与者能感受到的改动见 `docs/STUDY_CHANGELOG.md`。

每次合并 PR 或做出决定后，在这里加一段。

---

## 2026-10-15 1014e 第 2 节第 12 条：评估员 W4 名单含 PILOT（PR 草稿，分支 `feat/w4-list-pilot`）

- `functions/assessor.js`：`assessedParticipants`（B + PILOT）给名单和录入，`phaseBParticipants`（只 B）留给全体合并完成率——T43 报告第 5 节第 1 项的三个选项取 (b)，Junyu 要 (a) 的话改一处常量。App 两句文字加“或試跑”。T43 测试第 5a 步的断言反过来（三位 PILOT 在名单上）。报告 `docs/dev-reports/1014e-w4-list-pilot-20261015.md`。

## 2026-10-14 T39 运营看板「每人」页（PR 草稿，分支 `feat/ops-dashboard`）

- 按 1014c 边界 + 1014d 收窄只做第 2 页（每人一行 → 每日网格、最近会话、CSV）和第 1 页第 7 项（今日回访到期名单）。聚合在 Cloud Function：`opsDashboardPeople` / `Person` / `Csv`（`functions/ops_dashboard.js`），每日 `opsDailyRollup` 把过去的研究日存成 `ops_daily`，今天按需算。开关 `opsDashboardEnabled` 默认关，只给 `unblinded`。
- 入口放在研究员登记页右上角：核对时发现原来的「研究員儀錶板」（`researcher_dashboard_page.dart`，T34 告警、T30 完成率都在那里）在 App 里**没有任何入口**（T19 起 `unblinded` 登录直接进登记页），要带回研究侧。
- 回访阶段、旧构建后备口径、单段 60 分钟封顶都按 1014d；结局集合一个都不读（测试扫源码）。报告 `docs/dev-reports/T39-ops-dashboard-20261014.md`。

## 2026-10-14 T40 使用事件记录（PR 草稿，分支 `feat/usage-events`）

- 1014d 第 6 题的答案：App 早就在 `events` 里记 `app_foreground` / `app_background`，但那条行的 `timestamp` 被服务器时间覆盖，手机时间没有留下；也没有构建版本号、补传标记、登记前不记。所以 T40 按“补齐缺的、放开关后”做：新子集合 `users/{uid}/usage_events`，App 写类型、手机时间、服务器时间、版本号、平台；服务器触发器补研究编号、香港日期、研究日、`uploadedLate`。开关 `usageEventsEnabled` 默认关；规则只让已登记的本人新建、不能读改删。
- 离线：靠 Firestore SDK 的离线队列缓存、联网后补传；`uploadedLate` 由服务器按“收到时间比手机时间晚 5 分钟以上”判定（客户端自己判不可靠，离线时被杀掉会丢标记）。真机断网三次的验收要在 W0 装机时做，模拟器只能模拟“晚到的行”。
- 报告 `docs/dev-reports/T40-usage-events-20261014.md`，决策草稿在第 7 节。

## 2026-10-14 T46 收尾按钮首次说明只显示一次（PR 草稿，分支 `fix/session-end-hint-once`）

- T25 的收尾按钮说明每次启动 App 都再显示一次（当时 App 没有本机存储）。T37 之后有了 `shared_preferences`，T46 把“已经说明过”记在本机（`session.closeHintShown`），同一台手机只显示一次；重装会再显示一次。两组相同，文字不改。存储读不到时退回每次启动一次。
- 要在打开 `sessionBriefPrV2Enabled` 前合并。报告 `docs/dev-reports/T46-session-end-hint-20261014.md`。

## 2026-10-15 T43 PILOT 版本指定核对清单（emulator，PR 草稿，分支 `chore/t43-pilot-checklist`）

- 按 1014c 第 2 节在模拟器上把 W0 当天的流程串成一条链跑了一遍（`functions/test/t43_pilot_checklist_emulator_test.js`，11 步）：登记 PILOT-01、02（Hybrid）、03（规则组）→ 两层序列指针不动 → `pilot_assignment_log` 三条 `designate` → 评估员 W4 名单没有组别字眼 → PILOT 账号 acute 告警发一封到第一收件人、测试账号不发 → 登记门开着时 PILOT Hybrid 能用 LLM、没登记的和规则组被拒。
- **一条不过**：评估员的 W4 名单（和 W4 纸本录入）现在只含 `PB-`，三位 PILOT 不在名单上（`functions/assessor.js` 只认 `studyPeriod == "B"`）。1014c 第 0 节要 11/9 前含 PILOT，是行为改动，待 Junyu 定改法和编号。
- 没有改行为代码，只加测试和文档。报告：`docs/dev-reports/T43-pilot-checklist-20261015.md`（含给 W0 现场的 8 条提醒）。
- 同一 PR：1014c 第 1 节五题、1014d 第 0 节两题的正式回答 `docs/dev-reports/answers-1014c-20261015.md`。要点：PILOT 告警会发；T21 已在部署的 Functions（Deploy Firebase 第 7 次 = main `c1f88d6`）；`stripPII` 只去电话、邮箱、身份证样式、西式楼层单位，不去姓名和中文地址；参与者包里没有记忆总开关；后台 8 节、导出 4 套、没有运营看板；`events` 有 `app_foreground` / `app_background` 但存的是服务器时间（handoff 初步答案反了）；离线写入缓存后补传、不丢、无补传标记。

## 2026-10-15 W0 装机脚本 v1、iOS 包的编译参数（PR 草稿）

- `docs/release/w0-install-script.md` 按 #59–#76 合并后的 main 重写（取代 #61 的草稿 v0，#61 已关闭）：面访前 Junyu 的 10 项准备、Android/iOS 打包和装机（iOS 10/15 走 Xcode USB，TestFlight internal 作更新通道）、登记门开/关两种顺序、讲给老人听的话（草稿原样保留）、App 现状、要定的事。
- `codemagic.yaml`：bundle id 改成 `hk.hku.hkuimse.withyouapp`，构建加 `PHASE_B=true`、`RULE_TEMPLATE_REPLIES=true`，和 Android `phase_b_templates` 一致。不部署、不改行为。
- 发现：iPhone 推送要补 APNs 密钥和 Xcode Push Notifications 能力，10/22 前要做；记在脚本第 2.3 节。

## 2026-10-14 晚 产品窗口 10/14 第 5–10 条：登记表 v10，任务单 1014c、1014d（T38–T46）

- **定了**：试跑一轮 3 人（PILOT-01、02 Hybrid，03 规则组）10/15 做 W0，按正式配置跑完整 8 周；W8 问卷 13 题加可跳过的 AIMHS，试跑也推；第 63 天后推 debrief，约第 70 天停服；记忆不能整个关闭；告警急性即时、中级每日汇总、低级只记录；运营看板和使用事件记录（回访用）。
- 登记表 v10（C01、C05、C12、C15、C19、C20，新增 C23 使用事件记录）。任务单 `dev-tasks-1014c.md`（产品窗口原文，N1–N5 换成正式编号）和 `dev-tasks-1014d.md`。编号：T38 停服、T39 运营看板、T40 使用事件、T41 每日汇总告警、T42 debrief、T43 试跑核对、T44（#68 补号）、T45（#65 补号）、T46 收尾说明只显示一次。决策 0036 预留给 T35，下一个 0040。

## 2026-10-14 负责人核对后的四个修复（PR 草稿，分支 `fix/flags-after-login-and-guards`）

- 负责人核实：新装 App 第一次注册/登录后控制台开关不生效（启动时读开关、那时没登录、规则拒绝、之后不再读）。登记门开着时后果是老人直接进同意页、问卷答案被悄悄拒绝。修法：登录后再读一次开关并重建门（`auth_gate.dart`）。
- 顺带修：T34 第一封告警发不出去时下一次巡检直接转后备（`primaryFailedAt`）；T25 补问卡没有定稿时间说法时不显示【占位】、记 `due_not_invited: copy_pending`；「安靜時段」登录后和服务器对齐。`isTester` 客户端可写维持待办 96。编号待开发窗口分配。报告：`docs/dev-reports/fixes-after-review-20261014.md`。
## 2026-10-14 T30 角色、评估员视图、序列上传、过程/结局数据、锁库导出（PR 草稿，分支 `fix/roles-exports`）

- 角色按 10/14 分工：`unblinded` = Junyu、`blinded` = W4 评估员（Keran、Mingyan Wang）、新 `sequence_uploader` = Calvin。`tool/provision_researcher.js` 加 `--list`。
- 评估员视图（`lib/features/assessor/`，`functions/assessor.js`）：`blinded` 登录直接进 W4 到期名单和纸本 DJG-ES 录入；规则里 `blinded` 零读权限，全走函数；分数服务器算，存 `outcome_entries`，更正用 `tool/correct_outcome_entry.js`；PHQ-9 第 9 题走 T34 入口。规格文件 `docs/spec/instruments/djg_es.md`。
- 序列上传改为 Calvin 自己的登录调 `uploadRandomizationSequence`（`functions/sequence_upload.js`），上传记日志；`tool/randomization_sequence.js` 不再用服务账号。
- 过程数据导出 `functions/process_export.js`（含 T25 的 Brief PR v3、`validSessionCount`），`exports_v2` 可暂停；后台全体合并完成率（n<5 不显示）。
- 删除可保留一行分配记录（`allocation_records`）；配对改动服务器日志 `pairing_change_log`；`tool/analysis_export.js` 锁库 + 导出 + 合成数据。
- 七个开关全部默认关。报告：`docs/dev-reports/T30-roles-exports-20261014.md`（含三份决策草稿、架构观察）。

## 2026-10-14 T24 研究周和每周问卷（PR 草稿，分支 `feat/weekly-schedule`）

- 做了什么：研究周换算函数（服务器 `functions/study_week.js`、App `lib/core/scheduling/study_week.dart`，同一张测试表 `test/fixtures/study_week_table.json`）；每周问卷按研究周排程（`functions/weekly_schedule.js`、`lib/core/scheduling/weekly_schedule.dart`，同一张表 `test/fixtures/weekly_schedule_table.json`）；一个流程四部分（`lib/features/weekly_bundle/`）；按人推送、提醒、记缺失的定时函数 `weeklyBundleDispatch`；记录的研究周字段只由服务器写（触发器 + 规则）；`brief_pr` 按会话结束时间补周次（`onBriefPrWritten`）；社会接触探针 S12（`social_contact_probes`）。T34 的 `pi_alert.js` 改用共享函数。
- 开关：`app_config/phase_b.weeklyScheduleV2Enabled`、`socialContactProbeEnabled` 都默认关。推送、流程文字仍是【占位】。
- 没做 / 待定：W4 面访日期延长（T30 没合并，留了 `week4CloseFor(w0, w4VisitDate)` 钩子，现在只按第 29 天关）；推送钟点默认 20:00（沿用现在的每周推送），要 Junyu 定；W8 由 T35 做。
- 报告：`docs/dev-reports/T24-weekly-schedule-20261014.md`。
## 2026-10-14 T27 语音改走服务器 STT v2（SPEC:C18，PR 草稿，分支 `feat/stt-server`）

- **做了**：App 的麦克风按钮不再用手机系统识别，改为用 `record` 包把 16 kHz 单声道 PCM 录进内存（不写文件），包成 WAV 上传 `transcribeAudio`，文字填进输入框。服务器新模块 `functions/stt.js`：Google STT v2 `chirp_2`，**只用 `asia-southeast1`**（原来 `functions/index.js` 第 848–855 行的两档 `STT_TIERS` 删掉，不做配置项），每次调用最多两次尝试（瞬时失败重试 1 次），再失败返回类别 `timeout` / `server_error` / `no_speech` / `too_long` / `unavailable`；请求只有 6 个字段，没有任何数据记录参数，`functions/test/stt_test.js` 逐字段检查并扫描日志语句。App 失败时在麦克风上方贴一张 S6 小卡（不是聊天气泡、不写 turns 和记忆），`events` 记 `voice_transcription_failed`（`sessionId`、`agentId`、`category`、`at`）。`speech_to_text` 依赖删掉。
- **没变**：开关 `voiceInputEnabled` 默认关；关着时按钮不显示、不碰麦克风、服务器拒绝。两组代码路径完全相同。
- **讨论过**：S6 怎样“在输入框旁”显示——13 个页面各自放一个提示要改每个页面；改为按钮自己用 `OverlayPortal` 贴在麦克风上方，所有页面一致。`no_speech` 和 `too_long` 不重试（同一段音频再试也一样）。英文界面的 S6 没有定稿，用【占位】。
- **待定**（见报告「要 Junyu 定的事」）：控制台核对 data logging 的截图归档；`stt_usage` 要不要保留；开关打开前要不要先在试跑账号试一周。报告：`docs/dev-reports/T27-stt-server-20261014.md`。

---

## 2026-10-14 T32 第 6 条：旧测试员数据批量清理脚本（PR 草稿，分支 `feat/phase-a-final`）

- Phase A 暂停（决策 0034），T32 只剩第 6 条。新脚本 `tool/purge_tester_data.js`：列出 `isTester` 账号和没有研究期（`cohort` 不是 `phase_b` / `pilot`）的账号及每人的数据量；默认只列不删；`--confirm --production --project=… --production-confirm=…` 才逐人调用 `tool/delete_participant.js` 删除，并写服务器专用的运行记录 `admin_runs`（只有数量）。已登记的 `phase_b` / `pilot` 账号和 `unblinded` / `blinded` 角色的账号永远不碰。由 Junyu 在 10/19 登记前自己跑（上线清单新增 I 节），开发只在模拟器上测（`test/delete_participant/purge_tester_data_test.js`，已接进 `tool/ci_backend_tests.sh`）。
- 待定：没登记的账号要不要一并删（backlog 102）。报告 `docs/dev-reports/T32-phase-a-final-20261014.md`。

---

## 2026-10-14 设置页「語音讀出內容」隐藏、「安靜時段」接成真功能（PR 草稿，分支 `fix/quiet-hours-hide-readback`）

- 负责人定：语音读出先隐藏（没有功能读它）；安静时段接上：开关写到 `users/{uid}.quietHoursEnabled`，服务器按人发推送前查 `functions/quiet_hours.js`，窗口在 `app_config/reminders` 配置（默认 22:00–08:00）。行动计划提醒已接；T24 的每周推送器要接。编号待开发窗口分配。报告：`docs/dev-reports/quiet-hours-hide-readback-20261014.md`。
## 2026-10-14 T25 会话定义与 Brief PR 第二版（SPEC:C16、C14，PR 草稿，分支 `feat/session-briefpr`）

- **做了**：会话规则（`lib/core/session/session_rules.dart`）：结束方式 `close_button` / `back` / `switch_agent` / `timeout`（30 分钟）/ `recovered` / `crisis`，有效会话按“完成一个互动单元”（自由聊天 ≥3 条有回复；Hybrid 签到 = 心情 + ≥1 条有回复；Hybrid 回忆 = 按儲存；规则组 = 一次完整提交）。Brief PR 第二版：只在有效会话后、每位陪伴者每天 1 次、危机不邀请、列表页评价卡（S10a / S10b）、2 小时过期、一题一屏问卷、记录按会话编号去重、五种最终状态 + `everShown`。两组同一套。`llm_calls` 加 `session_id`，`usage_weekly` 加 `validSessionCount`。**开关 `app_config/phase_b.sessionBriefPrV2Enabled` 默认关**，关着时一切照旧。
- **没做**（见报告 `docs/dev-reports/T25-session-briefpr-20261014.md`）：截图；`brief_pr` 的 `studyWeek` / `studyDay`（T24）；收尾按钮首次说明的跨次启动记忆；决策记录编号待分配（旧弹窗和 anchor 的处理草稿在报告里）。
- 合并了 T21 之后的 `main`（e851205），无冲突。

---

## 2026-10-14 Phase B 包隐藏点赞点踩和第一周提示（PR 草稿，分支 `fix/phase-b-hide-feedback-nudge`）

- 负责人核对 W0 流程时发现：点赞点踩只有 Hybrid 组的签到、回忆、反思对话有（通通、文章两组都有），登记表没写这项差异；第一周提示读 Phase A 配置，Phase B 老人也会看到。负责人定：先关掉，保主干。
- 做法：`PHASE_B=true` 的包里两处都不渲染，两组相同；两个远程开关 `replyFeedbackEnabled`、`week1NudgeEnabled`（`app_config/feature_flags`）设为 `true` 可恢复。Phase A 包不变。编号待开发窗口分配。报告：`docs/dev-reports/phase-b-hide-feedback-nudge-20261014.md`。
## 2026-10-14 T34 安全告警邮件（PR 草稿，分支 `feat/safety-alert-email`）

- **做了**：告警邮件改版放在总开关 `meta/alert_config.enabled` 后面（默认关 = 现状）。开着时：中英双语、12 个固定字段（不含组别、原话、命中词）；收件人从 `meta/alert_config` 读，`blinded` 账号去掉并记 `alert_audit_log`；测试账号只记不发；研究员后台 `unblinded` 多「安全告警」一节和「確認處理」（Cloud Function `acknowledgeAlert` 查角色）；定时函数 `escalateAlerts` 每 15 分钟把超过 `escalateAfterHours`（默认 12）没确认的告警转发后备一次。新模块 `functions/questionnaire_safety.js`：问卷 / 评估员录入来源（PHQ-9 第 9 题 ≠ 0）写安全事件、不论级别都告警，只有服务器能写；没有接任何调用方（App 没有 PHQ-9，W8 不推；评估员录入页是 T30 的）。`safety_events` 新字段 `crisisPageShown`（两组同样写）。盲法导出 v2 多 `sourceGroup`，v1 导出也补这个字段。`functions/study_period.js` 和 T21 的逐字节相同。
- **讨论过**：新字段和决策 0029 第五节（告警不带组别线索、PI 盲法）冲突；现在 Junyu 是 `unblinded`、盲的是评估员，决策草稿写在报告里，编号等开发窗口分配。来源「AI 回复扫描」只有 Hybrid 组有，后备收件人 Calvin 看得到（backlog 92，未定）。
- 报告：`docs/dev-reports/T34-safety-alert-email-20261014.md`。

---
## 2026-10-14 T37 登记后的引导顺序和显示设定保存（SPEC:C01、C19，PR 草稿，分支 `fix/onboarding-settings`）

- **做了**：① 开关 `app_config/feature_flags.onboardingAfterEnrollmentFix`（默认关）：开时「介紹三個夥伴」要不要做改为看“引导已完成”标记 `users/{uid}.onboardingCompletedAt`，先登记后引导不再跳过伙伴介绍、兴趣和 S5；配对一屏预选登记值，改选记 `events` `ah_jan_ah_bak_changed`，登记记录不动。② 字体、高对比、安静时段、语音读出改为保存在手机本机（`shared_preferences`，新依赖），无开关。
- 两种顺序、门开关、修复开关的组合各有测试；规则测试证明老人账号能写标记、不能顺带改组别、不能碰 `enrollments`。截图在 `docs/dev-reports/T37-onboarding-settings-20261014-screenshots/`。
- 待定：开关上线时默认开还是关（建议开）；改配对的日志何时搬到服务器（T30）。报告 `docs/dev-reports/T37-onboarding-settings-20261014.md`。

---

## 2026-10-14 T36 Build APK 加 `phase_b_templates` 选项（PR 草稿，分支 `chore/apk-phase-b-templates`）

- 手动打包工作流多一个选项：`PHASE_B=true` 加 `RULE_TEMPLATE_REPLIES=true`，给参与者和内部测试用；不带 `FORCE_ARM`。只改手动打包，不改 CI 和部署。
- 签名仍是调试密钥；换正式密钥的步骤和影响写在报告第三节，要负责人定。报告：`docs/dev-reports/T36-apk-phase-b-templates-20261014.md`。

## 2026-10-14 T21 研究期和登记，第一部分（SPEC:C01，PR 草稿，未合并）

- **做了**：研究编号只认 `PB-`、`PILOT-`，`PA-` 和没有前缀的登记时拒绝（Phase A 暂停，决策 0034）；服务器按前缀写 `users/{uid}.cohort`（`phase_b` / `pilot`，决策 0011 的字段）和 `enrollments.studyPeriod`；试跑在登记页由负责人选版本、再选一次确认，不占序列，研究日从登记日算，记 `pilot_assignment_log`；试跑 Hybrid 账号有服务器记忆，试跑不进盲法导出、不收旧的 Phase A 第 2 周推送。
- 登记门（`app_config/feature_flags.enrollmentGateEnabled`，默认关）：开时没登记、不是测试账号的账号只看到 S8，服务器拒绝 LLM 调用（`llm_denied_log` 记 `not_enrolled`），Firestore 规则拒绝写研究数据。
- 没做、待定：`PHASE_B` 编译开关去留；广播推送对未登记账号的筛选（T24）；盲法人员账号（T30）。报告 `docs/dev-reports/T21-phase-config-20261014.md`。
- **10/14 第二次更新**：再合 main `46d3ef9`（#60）；负责人对 6 件待定事的答复是“改动最少、可以回退”，六项都按现有做法（`PHASE_B` 保留、`pilot` 指试跑、`isTester` 不改、试跑研究日从登记日算、登记门默认关、开的时间待定），写成决策 0037（提议中，待 Junyu 确认），0011 顶上加一行“`pilot` 的含义已由 0037 取代”；评估员账号和登记门的关系交 T30（`dev-tasks-1014.md`）。代码行为没改；backlog 加第 96 项（`isTester` 客户端可写）。

## 2026-10-14 产品窗口 10/14 第 1–4 条排进第九批（T35）；登记表 v9

- **定了**：数据收集 10/19 开始；W4 结局评估员是 Keran，后备 Mingyan Wang，评估员视图只剩 W4；W8 不再有评估员，App 在第 56 天推送 DJG-ES、PGIC、UCLA-3，第 63 天关闭，超窗作答照记并标记；W8 不推 PHQ-9、GAD-7。
- 登记表 v9（C12、C15、C19、C20）。任务单 `dev-tasks-1014.md`：更正 T30（评估员视图只剩 W4、两个评估员账号、评估员不被登记门挡住）、T24（不含 W8，核对旧的每周孤独探针）、T34（W8 没有 PHQ-9 触发）；新任务 T35（W8 App 问卷），决策编号 0036 预留给它。
- 10/11 起登记表、T 编号、决策编号只由开发窗口改和分配，仓库会话只执行。

## 2026-10-10 产品窗口 10/10 第二次交接（第 6–11 条）：T34 告警邮件；Phase A 暂停；错字改正；登记表 v8

- **定了**：告警邮件加字段（研究编号、研究期、陪伴者、来源、级别和类别、词库版本、LoRA、研究日、危机页、事件编号），不放组别和原话；收件人做成配置，第一收件人负责人、后备 Calvin Or，评估员不在名单；后台“确认处理”，12 小时没确认转后备；PHQ-9 第 9 题不是 0 也告警（问卷、评估员录入两种来源）。**Phase A 暂停**，以后单独开仓库和 Firebase 项目（决策 0034）；登记只认 `PB-`、`PILOT-`。W8 窗口第 53–63 天、目标第 56 天，超窗可录；试跑作答窗口 1 天；`event` 记忆归私有层；Hybrid 有效会话条件定了；S5 放入组引导。
- 定稿文字的错字已照研究侧改正改好（`docs/spec/copy/`）。登记表 v8（统筹会话按负责人转来的交接改）。任务单 `docs/dev-tasks/dev-tasks-1010b.md`：新任务 T34，更正 T21、T24–T27、T30–T33（T32 只剩清理测试员数据脚本）。
- 给产品窗口的回复 `docs/dev-reports/product-reply-20261010.md`：T20 的 7 处使用频率文字清单；App 里没有 PHQ-9；告警来源“AI 回复扫描”会露出组别，后备收件人是否要盲待定。
- 10/8 交接 R1–R9 的去向写在 `docs/dev-reports/开发窗口交接-1010.md`。原件找不回来，负责人定以这份重建版为准。
- 同日按 `dev-tasks-1010.md` 开了 T21、T26（在 PR #52 分支上续做）、T31、T33 四个会话。

## 2026-10-10 T33 定稿文字接入（PR 草稿）

- 规则组模板换成定稿 41 条，结构改为「陪伴者 × 五档心情」，没选心情用 G-1，回忆里的哀伤内容用 Z5（决策 0032，部分取代 0023）。
- 短文字接入：S1a（通通固定回应）、S2（新 prompt 文件 v2）、S3（人生點滴入口，无开关）、S4a（行动计划提醒推送）、S5（入组引导最后一屏，开关默认关）。
- 同日按 `dev-tasks-1010b.md` 的 T33 更正：文字换成研究侧改正错字后的版本，去掉“待确认”标记；S5 改放入组引导；T20 的 7 处不动。
- 发现网页版构建 `newTurnId` 的错误（Android 不受影响），记入 backlog 第 95 项。
- 报告：`docs/dev-reports/T33-final-copy-20261010.md`。

## 2026-10-10 T31 记忆分层（PR 草稿，分支 `feat/memory-layers`）

- 记忆分共享层和私有层，按研究侧 10/9 第 15 条：作息、兴趣、喜好加入共享；心事、健康、哀伤、回忆、待跟进私有。服务器写 `layer`、`sourceAgent`，按陪伴者过滤；旧条目读取时推算，不迁移。决策 0035（0032 不确定、0033 是 T26、0034 是 Phase A 暂停）。适用 Phase B Hybrid 组（含试跑）；`event` 归私有已由研究侧确认。
- 设置里删一条会连带删其他陪伴者的私有副本和引用它的摘要；记忆剂量按层计。
- 抽取 prompt v3 写好、没切换；用 T4 的 30 段合成对话跑了一遍（26 次真实调用），结果在 `tool/memory_eval/results/t31_v3_run1/`。
- 开关 `layersEnabled`、`memoryLayersNoticeEnabled` 默认关。报告 `docs/dev-reports/T31-memory-layers-20261010.md`。

## 2026-10-10 产品窗口 10/9 第 13–29 条、10/10 第 1–5 条排进第七批（T30–T33）；登记表 v7；定稿文字导入

- **定了**：研究期按登记编号前缀（`PA-`、`PB-`、`PILOT-`），登记前只显示等待页、不收研究数据，两期都由负责人登记；分配序列由 Calvin 生成、上传和保管，负责人的账号读不到序列；语音只用 `asia-southeast1`，失败重试 1 次后提示改打字，不开数据记录；Phase A 用同一个最终构建；第 4 周问卷第 26 天开、第 29 天或 W4 面访当天关，PGIC 第 35、42、49 天；记忆分共享层和私有层；整人删除时保留一行分配记录；分析导出不含对话原文。
- 登记表 v7（合并统筹会话的 v5 和开发窗口的 v6、v7）。任务单：`dev-tasks-1009.md` 第三版（T24 研究周和每周问卷）；`dev-tasks-1010.md`（顺序、对 T21–T29 的更正、新任务 T30 角色和导出、T31 记忆分层、T32 Phase A 最终构建、T33 定稿文字接入）。`dev-tasks-1009c.md` 作废，没有放进仓库。
- 定稿文字导入 `docs/spec/copy/`：规则组 41 条模板、短文字 S1a–S12。原文照录；疑似错字（侾、傳、諦、゗、捣、鐘意）研究侧确认前不上线。
- 第一轮内部实机测试指引 `docs/release/internal-test-1010.md`（只限团队，不找老人）。
- T 编号和登记表只由开发窗口改，统筹会话只执行和写报告。PR #49（旧编号 T24 的 LoRA）已由 #52（T26）取代。

## 2026-10-10 陪伴者图片：透明背景；阿珍、阿伯改紫色

- 8 张陪伴者图片原来把灰白格子画在图里（不是真透明），已改成真正的透明背景，人物不变。
- 阿珍（薄荷绿）和通通撞色。负责人看了几套预览（淡紫、奶茶、雾蓝、藕紫、蜂蜜黄），选了藕紫，并要求不要调浅颜色。阿珍改藕紫、阿伯改灰紫，只改色相；代码里的主题色和首页卡片颜色跟着改。决策 0031。
- `IMAGES.md` 改写成现在的机械人形象说明，删掉过时的真人肖像出图要求。
- 表情（阿珍半闭眼、阿伯垂眼）没改，要改得重画。

## 2026-10-10 T26 补充：Phase A 和试跑也用（PR 草稿 #52）

- 按 `dev-tasks-1010.md` 第三节：分类器两期和试跑同一套。先把 main 合进分支。核对代码本来就不分研究期（App 两种构建都读同一个开关，服务器不读研究期），只补了测试（App 两种构建都跑；服务器用 Phase A、Phase B、试跑的合成账号），决策 0033 补第 7 条。
- 发现：研究员电话代填的 Phase A 问卷文字只查词库（backlog 87）；T21 拆配置时分类器开关不能分期（backlog 88）。

## 2026-10-09 T26 LoRA 两组共用（PR 草稿）

- 按 10/8 第 1 条写决策 0033：安全分类器两组共用，取代 0025 里"两组是否都用"的部分（0025 顶部标 Superseded）。只给级别和分数，只触发两组相同的安全流程；`assertLlmAllowed` 不动。
- 核对记录字段：`safety_classifier_calls` 和 `safety_events` 已有同一个编号（`turn_id` / `turnId`），但消息记录 `turns` 里没有。补了 `turns.safetyTurnId`，两组都写。
- 上线清单加 H 节（地址、鉴权、部署机器等）。开关仍默认关。报告 `docs/dev-reports/T26-lora-both-arms-20261009.md`。

## 2026-10-09 T22 旧 agent_diff 收尾（SPEC:C15、C22，PR 草稿，未合并）

- **做了**：新版盲法导出不再导出旧的“陪伴者区分评估”（`agent_diff`），清单里列为“揭盲前不导出”，检查脚本见到它会报错。Phase A 打开 `adaEnabled` 后不弹旧问卷，T17 已经做了，这次补了测试。没有新开关。
- 没删旧集合、旧页面，没动已有数据。报告：`docs/dev-reports/T22-legacy-agent-diff-20261009.md`。待办第 78–79 项。

## 2026-10-09 产品窗口 10/8 交接和 10/9 决定排进第六批（T25–T29）；登记表 v5

- **定了**（10/9 第 1–3 条和补充）：盲法导出维持决策 0021，数据收集期间不含 Brief PR 和每人会话数，另做全体合并的完成率；语音改为 App 录音上传服务器 STT v2（`chirp_2`，`asia-southeast1`），只存文字，失败退 global 区先做成配置项；有效会话按"完成一个互动单元"（自由聊天 3 条消息，签到和回忆按完成模块流程，规则组一次提交算一次，决策 0015 保留）；LoRA 两组共用；试跑编号 PILOT-01 起、不收集收款资料。
- 登记表在 v4 上改为 v5（C13、C14、C16、C18）。任务单 `docs/dev-tasks/dev-tasks-1009b.md`：T25 会话与 Brief PR、T26 LoRA 两组共用、T27 语音改走服务器、T28 试跑支持、T29 操纵检验抽样导出。第四、五批（`dev-tasks-1008.md`、`dev-tasks-1009.md`）照 T22 → T21 → T24 → T23 的顺序做。
- 统筹会话的现状报告 `docs/dev-reports/product-reply-20261009.md`：记忆读写和共享、Brief PR 字段缺口、STT 现状（App 现用手机系统识别，不经服务器；录音上传代码 main 上没有）、Hybrid 签到和回忆的流程及有效会话提议、产出窗口 24 条核对。
- 之前统筹会话按自己的编号开的三个会话（T21、会话与 Brief PR、LoRA 和探针）和第四批计划冲突，已停掉；LoRA 那个留下一个没开 PR 的分支 `feat/lora-both-arms`，T26 改用 `feat/lora-both-arms-v2`。

## 2026-10-07 T19、T17b 合成一个 PR

- T19（分组重做）和 T17b（ADA 按 `docs/spec/instruments/ada.md` 补做）各一个云端会话，合成这一个 PR。交接文档 `docs/dev-reports/T19-T17b-handoff-20261007.md`。
- 合并时的衔接：T17b 的研究员页面和 `adaStaff*` callable 改认 T19 的新角色（`blinded`、`unblinded`；研究编号只给 `unblinded`），旧名 `pi`、`researcher` 不再有权限；整人删除脚本同时覆盖 `enrollments`、`llm_denied_log`、`ada_status`。
- **部署即生效、不受开关控制的三处**：旧角色账号失去权限，要按新角色重发；发给 PI 的告警只剩研究编号、级别、时间、编号；分组计数器客户端不能读写。分组开关 `meta/randomization_config.enabled` 必须在第一位 Phase B 老人注册前打开。

## 2026-10-07 T19 App 内分组重做（SPEC:C01，PR 草稿，未合并）

- **现状**：注册时 `assignArm` 按 UCLA × 年龄 4 层最小化分配（少的那组优先，一样多抛硬币），分层变量是老人自填的；计数器 `meta/arm_counter` 客户端仍能写增量；`role: pi` 是非盲角色；给 PI 的告警邮件带来源和陪伴者。
- **做了**：研究员登记页（非盲研究员登录后直接进入）+ Cloud Function `enrollParticipant`：按 W0 DJG 情感分分层、置换区组序列、事务分配、分配日志、重复提交不重抽、脚本更正；序列生成和上传脚本（种子不进仓库、不上传）；最小化分配删除；角色改名 `unblinded` / `blinded`，PI 为盲法；给 PI 的告警去掉能推出组别的字段；W0 日期优先用登记日；规则组 LLM 被拒记日志。开关 `meta/randomization_config.enabled` 默认关。决策 0029（取代 0003）。
- **测试**：72 个合成参与者，两位研究员同时提交，每层最大人数差 2，没有重复占位；客户端读写序列、分组、计数器、日志都被拒；盲法导出没有组别。
- 报告：`docs/dev-reports/T19-randomization-20261007.md`。待办第 72–74 项。

## 2026-10-07 T17b ADA 按定稿规格补做（SPEC:C22，PR 草稿，未合并）

- **做了**：按 `docs/spec/instruments/ada.md` v1.0 改题目（粤语原文、版本 `ada-v1.0-20261007`）、名字旁加头像；短版改为 B + D；第 1 次到访最后选第 7 日提醒时间；第 7 日 ADA 和开放题合成一个流程（进度、中途停、接着做、求助按钮）；服务器第 7 日推送、24 小时再提醒、第 9 日后记超时（推送文字是占位，不发）；研究员页面看完成情况、电话代填（`phone_by_staff`），代填文字服务器做安全检测。决策 0030。
- **做法上的选择**：研究编号不写进老人能读的答案文档（决策 0021），放在服务器专用的 `ada_status`；没配置求助电话时不拨号、只弹说明；研究员权限先用现有 `researcher` / `pi` 角色，T19 改角色时对上。
- 开关仍默认关，PI 书面确认截图前不打开。报告：`docs/dev-reports/T17b-ada-v1-20261007.md`。待办第 75–77 项。

## 2026-10-07 #39、#40、#44 合并；盲法人员和 ADA 定稿

- PR #44（第三批 T17、T18、T20）、#40（T10）、#39（T8）都已合并。#39、#40 合并前先合了 main 解决冲突；合 main 后 T17 的 ADA 测试因 T8 改了安全事件接口而编译不过，已照 T8 的写法改好测试；#40 先合进 #39，避免第二轮文档冲突。
- **研究侧定了盲法人员**：非盲研究员是 Keran（登记入组、触发分组、按组引导、生成和上传分配序列）；PI（Junyu）是盲法评估者。T12 把 `role: pi` 设成了非盲角色，T19 里改（待办第 46 项）。
- **ADA 定稿**放进 `docs/spec/instruments/ada.md`：A 部分回忆窗口改为"過去 7 日"、选项改为次数；第 1 次到访短版 B + D，第 7 日全版 A + B + C + D；第 7 日在家用 App 填，有提醒、进度、中途保存、求助电话、电话补做（`phone_by_staff`）和研究员页面的完成情况；上线前 PI 审截图。T17 按它补做。
- 任务单 `docs/dev-tasks/dev-tasks-1007b.md` 更新为研究侧 10/7 的新版。

## 2026-10-07 T10 记忆修复，重跑 T4（SPEC:C05，PR 草稿，未合并）

- **做了**：服务器用 App 同一份安全词库查老人原话（`functions/safety_lexicon.json` 从 Dart 词库生成，测试保证一致），命中的轮次不进记忆、那次会话不写摘要；摘要不写敏感内容；「唔好記住」用规则 + 关键词识别，整段不记并删除相关旧条目；页面删一条连带删摘要；`tool/delete_memory.js` 写 `memoryWithdrawnAt`，之后 Phase B Hybrid 组也不再记录。顺带修了称呼混进陪伴者名字、更新错类别、计划重复记成事实、敏感事实没有名额。抽取 prompt 改为文件，新版 v2。决策 0024。
- **重跑 T4**：真实 DeepSeek 共 104 次调用。前两轮发现评测脚本自 T11 起没给测试用户写共享同意（实际按「各看各的」跑），以及两处可修的问题，修好后再跑两轮作为验收；最后一处（同一句话存两次、删一条还剩一条）用录下的模型输出重放验证。验收 6 项里 5 项通过；「编造为 0」按标准答案口径第 3 轮有 1 条（孙子的玩笑），按凭空捏造口径两轮都是 0。
- 第二位判定人用的表：`tool/memory_eval/second_rater_t10.csv`（220 行，不含第一位的判定）。
- 报告：`docs/dev-reports/T10-memory-fix-20261007.md`。待办第 55–57 项。

## 2026-10-07 研究侧答复交接方案；第三批 T17、T18、T20 合成一个 PR

- **研究侧 10/7 答复**（`docs/dev-tasks/dev-tasks-1007b.md` 开头的表）：DJG 用 6 条版，W0、W4 由 PI 当面纸本、W8 电话或视频，都不进 App，W2 在 App 内做全部 6 题；LSNS-6 不用；UCLA 是纸本；SUS 和 Phase A 第 7 日问卷等 EA260417 批复；ADA 只用于 Phase A；每周孤独探针不修，保持关闭；分组重做（T19）；Phase A、Phase B 配置分开（T21）；建议每天用、每周至少 5 次、不强制。PI 的几项（三条 prompt、热线号码、间接自伤说法进词库）还在等。
- 登记表 v2 放进 `docs/spec/feature-registry.md`（负责人直接在 main 上提交）。C14 改为一致；C15 去掉孤独探针、ADA、LSNS-6；C12 的 5-flag 改为 H4 暴露标记。
- 第三批任务单 `docs/dev-tasks/dev-tasks-1007b.md`（T17–T21）。T17、T18、T20 各一个云端会话并行，合成这一个 PR；交接文档 `docs/dev-reports/T17-T20-handoff-20261007.md`。T19 等 #39、#40 合并后开；T21 用 T19 的研究员登记入口，排在 T19 之后。
- 合并时的衔接：首页问卷提示同时带第 2 周 DJG、ADA 和第 7 日开放题，第 2 周 DJG 打开时替换旧 DJG，旧"陪伴者区分评估"只在允许的版本出现；Firestore 规则三个新集合各有一段，并都排除在通用的"本人可读写"规则之外；App 启动时的配置读取改为同时进行（最多等 3 秒，原来依次读最多 12 秒）；修了 CI 脚本合并时漏掉的换行符；删掉上传时多出的登记表副本。
- 合并后本地跑了全部测试：后端（Functions、规则、模拟器、删除脚本、同意脚本）全过；App 六套构建变体全过；`flutter analyze` 没有 error。

## 2026-10-07 T17 ADA 进 App（SPEC:C22，PR 草稿，未合并）

- **现状对照**：App 已有“陪伴者区分评估”（agent_diff，第 14、28 天，两组、两种构建都出现）。题目来源和附件 C 相同，但一页一个矩阵、不能跳过、不逐屏保存、没有表单版本和输入方式，D 题不同。决定新做，不改旧的（决策 0026）。
- **做了**：新 ADA 页面（一屏一项，短版/全版，可返回、每屏保存、可跳过），第 7 日 3 道开放题（同一个长文字组件，麦克风跟随语音开关）；时间点、版本、回忆窗口从 `app_config/phaseA_schedule` 读，默认全关；Phase B 构建一律不显示。新集合 `ada_responses`、`day7_open_responses`：只有本人能读写、提交后锁定、整人删除脚本覆盖、不进盲法导出。两处文字经 `SafetyService`。
- **顺带修正**：Phase B 构建不再出现旧 agent_diff（登记表 v2 C15），开关 `LEGACY_AGENT_DIFF_PHASE_B` 默认关。
- 报告：`docs/dev-reports/T17-ada-20261007.md`。待办第 61–63 项。

## 2026-10-07 T20 使用建议的文案（PR 草稿）

- 研究侧定了"建议每天用、每周至少 5 次、不强制"，措辞等 ICF 定稿。
- App 里提到使用频率的 7 处文字改为先读 `app_config/usage_copy`，没有定稿时显示原文（决策 0028）。两组相同，没有新增提醒。
- prompt 和规则组模板里相关的说法只列出、没改，见 `docs/dev-reports/T20-usage-copy-20261007.md`。

## 2026-10-07 T18 第 2 周 DJG 改为 App 内全 6 题（SPEC:C15，PR 草稿，未合并）

- **查清现状**：App 里原有的 DJG（`djg_es`，6 条粤语草稿、第 14–16 天一次、`timepoint: "week2"`）就是 W2，所以按任务单替换；旧集合、旧数据、旧页面都保留，Phase A 构建行为不变。
- **做了**：新集合 `djg_responses/W2`；题目和「是 / 大致是 / 不是」照抄问卷包 §3；一屏一题、可返回、可跳题；W0 起第 14 天推送和首页卡片，窗口第 14–20 天，24 小时提醒一次，过窗口记缺失；分数由服务器算（跳题的分量表记缺失），客户端不能写分数；W2 进盲法导出白名单。决策 0027。
- **开关**：`app_config/phase_b.djgW2InAppEnabled`，默认关，还要 Phase B 构建。推送文字是占位，未定稿服务器不发。
- 报告：`docs/dev-reports/T18-djg-w2-20261007.md`。待办第 64–66 项。

## 2026-10-07 开发任务 T7–T15 合成一个 PR

- 第二批里已完成的 8 个任务（T13、T7、T9、T12、T11、T15、T14、T16）合成一个 PR，下面各段是各任务自己的记录。T8、T10 等这个 PR 合并后再开。
- **T16 记忆使用画像**（只有报告和脚本，`docs/dev-reports/T16-memory-profiles-20261007.md`、`tool/memory_profiles/`）：4 种合成画像各跑 4 周，真实 DeepSeek。2,000 字注入上限从没碰到，真正的限制是 20 条事实、3 个摘要日、1 条跟进；普通事实满 20 条后已确认的敏感事实不再注入；App 缓冲区只留最近 10 轮，长对话前面的内容抽不到；事实只增不减、矛盾两边都保留；同一件事反复生成跟进。待 T10 一并处理。
- 合并时的衔接改动：T15 的签到 B、回忆 B 改用 T7 的统一安全入口（每次提交只写一条安全事件）；整人删除脚本加上 T7 的 `hotline_filter_log` 和 T12 的研究编号对照表（`research_id_map`、`research_ids`）；T9 的 prompt 测试改为期望 T7 追加的 `+hotline_rule.v1` 版本后缀。
- 合并后在本地跑了全部测试：后端（Functions、规则、模拟器、删除脚本）全过；App 六套构建变体全过。

## 2026-10-07 T8 安全分类器接口（PR 草稿，未合并）

- 在统一安全入口 `SafetyService` 后面加了一个分类器槽位，给研究侧的 LoRA 模型预留，两组相同。经新的 Cloud Function `classifySafety` 中转，只返回级别和分数；只升不降；超时 1.5 秒或失败只用词库，并记 `safety_classifier_calls`。
- 冲突：规则组「永远不能调用 LLM」。做法是独立的分类接口，不经过、也不放宽 `assertLlmAllowed`。是否接受由研究侧和 PI 定（决策 0025，提议中）。
- 开关 `app_config/phase_a.safetyClassifierEnabled`、`meta/safety_config.classifierEnabled` 都默认关；关着时检测仍是同步的，行为不变（有测试）。用本地假模型测了正常、超时、失败。
- 报告：`docs/dev-reports/T8-safety-classifier-20261007.md`。待办第 58–60 项。

## 2026-10-07 T13 小修与上线配置（PR 草稿，未合并）

- **C01**：Firestore 规则改成分组字段（`arm`、`strataCell` 和三个 `armAssigned*`）只有服务器能写；客户端不能删自己的用户文档（决策 0022）。App 正常注册走 `assignArm`，不受影响；规则测试按新规则改写并补了用例。
- **C07**：新增定时函数 `dispatchReminders`，把 App 写进 `reminders` 的行动计划提醒推送出去，两组相同，开关默认关（决策 0022）。
- **上线配置**：新增 `tool/prelaunch_config.js`（写 `meta/memory_config`、`app_config/arm_assignment`，可选清零计数器；默认只对模拟器执行）和 `docs/release/prelaunch-checklist.md`。
- **C06**：怀旧入口「6 個主題、6 個禮拜」改为按实际主题数显示（4），单独一个提交，等研究侧确认文案。
- 报告：`docs/dev-reports/T13-prelaunch-20261007.md`。

## 2026-10-07 T7 安全加固（PR 草稿，未合并）

- **做了**：所有自由输入两组都经同一个安全检测入口 `SafetyService`；补上 7 处没带用户编号的 AI 调用；`safety_events` 每条带 `source`、`inputPoint`、`turnId`，一轮对话只算一条；Hybrid 组 AI 回复里的电话号码在服务器和 App 各过滤一次，换成危机页链接，并记 `hotline_filter_log`；prompt 加「不写电话号码」规则 `hotline_rule.v1`；搜一搜命中安全词时不发出搜索。决策 0018。
- **开关**：`safetyScanAllInputs`、`hotlineFilterClient`（`app_config/phase_a`），`hotlinePromptRule`、`hotlineOutputFilter`（`meta/safety_config`），默认都开。
- 报告：`docs/dev-reports/T7-safety-hardening-20261007.md`。

## 2026-10-07 T9 关闭搜一搜和语音输入（SPEC:C18，PR 草稿，未合并）

- **查清现状**：搜一搜在 App 里 2026-07-20 起写死关闭，老人触发不了；但服务器 `webSearch` 还开着，只拦规则组。语音两组都开着，没有开关。
- **做了**：新建配置 `app_config/feature_flags`，三个开关全部默认关（决策 0019）。关时 App 不显示麦克风和"幫我查"按钮、不发请求；服务器 `webSearch`、`transcribeAudio` 直接拒绝。语音代码保留，HREC 批准后在控制台打开。
- 通通遇到要上网查的问题有一句固定回应，两组条件相同，先过安全检测；文字是占位，开关默认关。
- 负责人决定通通 prompt 去掉"幫你查"邀请：新建 `tung_tung.v2.txt`，服务器按注册表加载，`tung_tung_v1.txt` 保留。待 PI 审核。
- 报告：`docs/dev-reports/T9-flags-20261007.md`。待办第 40–42 项。

## 2026-10-07 盲法（T12，PR 草稿，未合并）

- 新版盲法导出：每人一个跨周不变的研究编号（分组时由服务器生成），组别代码整个研究期间固定，只导出两组都答的结局量表；对话轮次、会话、事件、LLM 和记忆相关集合揭盲前不导出（决策 0021）。
- 研究编号对照表 `research_id_map`、`research_ids`，只有非盲角色（`role: pi`）能读。`meta/arm_counter` 也改为只有非盲角色能读。
- 研究者后台：`researcher`（盲法）看不到两组人数和只有一组才有数据的板块；`pi`（非盲）看全部。
- 新增检查脚本 `tool/check_blinded_export.js`，有可疑字段就非零退出，测试里跑。
- 开关 `meta/blinding_config.enabled` 默认关，关着时旧导出照旧。报告：`docs/dev-reports/T12-blinding-20261007.md`。

## 2026-10-07 T11 隐私、同意与删除（PR 草稿，未合并）

- 「共享上下文」同意接上代码：开关 `app_config/phase_a.enforceSharedContextConsent`（默认关）打开后，没同意的人每个陪伴者只用自己的记忆。App（记忆 v0）和服务器（记忆 v1，`functions/memory.js` `effectivePolicy`）读同一个键（决策 0020）。
- 「保留对话」和「共享」的默认值改为从 `app_config/phase_a` 读，默认保持现状。
- 新增 `tool/delete_participant.js`：整人删除，默认试运行，`--confirm` 才删，删完复查，存证只有数量。周度导出文件默认只数不改。在 Auth + Firestore + Storage emulator 上测过，加进 `tool/ci_backend_tests.sh`。
- **发现**：设置页「保留對話紀錄」开关没放进页面，老人关不掉；隐私页多数说法与实际不符（草稿在报告里，没改 App 文字）。
- 负责人随后定了两件事：已导出的盲法文件保留不动（ICF 的写法依赖 T12）；隐私页直接改成简短、准确的版本，细节交给同意书（单独一个提交，等负责人确认文案）。
- 负责人又确认：共享同意统一打开（默认开、迁移现有账号、不愿意的由后台按人关闭，新脚本 `tool/set_shared_context_consent.js`）；设置页放回「保留對話紀錄」开关。顺带修了 App 保存资料时把旧的 `sharedContextUse` 写回去的问题。
- 报告：`docs/dev-reports/T11-privacy-consent-20261007.md`。待决定见 `docs/dev/backlog.md` 第 43–45 项。

## 2026-10-07 T15 规则组签到、回忆的模板回应（PR 草稿，未合并）

- 规则组小欣签到、阿珍/阿伯回忆提交后，按心情从模板池给一条回应，样式和 Hybrid 组同页面的气泡一样（决策 0023）。目的是让三个陪伴者在规则组都有「输入 → 回应」。
- 放在编译开关 `RULE_TEMPLATE_REPLIES` 后面，默认关；关时两页和现在一样。模板全是【占位】文字，有占位时开关不生效。
- 回应前先做安全检测，命中 moderate 或 acute 不给模板，走原来的安全流程。检测集中在 `lib/features/rule_replies/rule_reply_safety.dart`，写成 T7 `SafetyService` 的用法，T7 合并后替换。
- 回忆 B 加了一个选填的心情脸（Hybrid 回忆没有心情输入）。
- 报告：`docs/dev-reports/T15-rule-based-replies-20261007.md`。

## 2026-10-06 开发任务 T1–T6；DeepSeek 模型名

- 研究侧功能登记表（C01–C22）放进 `docs/spec/feature-registry.md`，任务单放进 `docs/dev-tasks/dev-tasks-1006.md`。T1–T6 分六个云端会话并行执行，报告写到 `docs/dev-reports/`、`docs/spec/`、`docs/export/`。
- 云端环境接入 DeepSeek（凭据由代理注入，会话里看不到密钥），供 T4、T6 用合成对话测试。
- **发现**：代码请求的 `deepseek-chat` 实际返回 `deepseek-flash`（DeepSeek-V4.1-Flash），模型列表里已没有 `deepseek-chat`。研究文件里写的 DeepSeek-V3 不准确。
- **决定**：请求改为 `deepseek-flash` 并关闭思考模式，实际模型不变（决策 0017）。不关思考的话，转介判断会返回空内容。
- 六份产出合成一个 PR：T1 `docs/spec/audit-20261006.md`；T2 `docs/dev-reports/T2-data-dictionary-20261006.md`；T3 `docs/export/20261006/`；T4 `docs/dev-reports/T4-memory-acceptance-20261006.md` 和 `tool/memory_eval/`、`functions/test/memory_acceptance_emulator_test.js`；T5 `llm_calls` 记录（见下一段）；T6 `docs/dev-reports/T6-safety-parity-20261006.md`。每份报告都由另一个会话对照代码复核，复核意见已改正。
- **主要发现**：登记表 22 项里一致 6、不一致 10、缺失 1（C13 LoRA）、无法判断 1、待定 4；记忆验收整体不通过（编造不为 0、准确率 81.8%，跨 agent 泄露为 0）；词库对间接自杀表达召回低；ICF、DMP 有多处与代码不符。待决定事项见 `docs/dev/backlog.md` 第 25–36 项。

## 2026-10-06 模型版本记录（C04，PR 草稿，未合并）

- 服务器上所有 DeepSeek 请求改走 `functions/llm_log.js` 的 `deepSeekChat`，每次调用在 `llm_calls` 写一条：返回的 `model`、token 数、延迟、是否出错，不存原文（决策 0016）。
- 新增 Firestore 规则：`llm_calls` 客户端不能读写。
- 新增测试：`functions/test/llm_log_test.js`、`functions/test/llm_calls_emulator_test.js`、`test/rules/llm_calls_rules.test.js`。
- 真实调用冒烟测试（`functions/test/llm_live_smoke.js`，手动跑）。最初请求 `deepseek-chat`，返回的 `model` 是 `deepseek-flash`；合并决策 0017 之后请求 `deepseek-flash`、思考关闭，返回的也是 `deepseek-flash`，都正确写进日志。
- 按统筹会话补充和复核：日志加 `system_fingerprint`、`reasoning_tokens`、`http_status`；`model_requested` 从实际请求体读；`agent_id` 只接受三个陪伴者；DeepSeek 请求加超时；写日志最多等 2 秒。
- 合并了决策 0017 的分支（模型名改为 `deepseek-flash`，思考关闭）。`functions/test/deepseek_request_test.js` 改为检查 `llm_log.js` 是唯一发请求的地方。
- 报告：`docs/dev-reports/T5-model-logging-20261006.md`。

## 2026-10-04 规则组 Brief PR

- 签到 B、回忆 B 每次提交记为一次会话（`sessions` / `turns`），提交后弹 Brief PR（决策 0015）。之前这两个页面从不弹，两组结局测量口径不同。
- 签到 B 的安全提示改走统一的 `DistressRouter`：之前 acute 只弹一个写死热线的对话框，不进危机页。
- 首页「今個星期傾咗 N 次」统一从 `sessions` 统计。
- 讨论：规则组自由对话的非 LLM 方案、「我的資料」规则组内容、口头删除的替代方案（待负责人选）。

## 2026-10-04 文档整理

- 负责人提供的文档框架（`docs/README.md`、`STUDY_CHANGELOG.md`、决策记录模板、0001、记忆研究对齐文档、记忆开发规格）放进仓库。
- 补写之前在对话里做的决定：决策 0002–0014。
- 新增 `docs/dev/architecture.md`（技术文档）、本文件、`docs/dev/backlog.md`（待办）。
- `docs/memory-v1.md`、`docs/ci-cd.md` 移到 `docs/dev/`；2026-09-29 的架构说明移到 `docs/history/`，作为历史快照。
- 根目录新增 `CLAUDE.md`，写入文档规则。
- **安全词库**：PI 签核搁置，先沿用 v5（决策 0012）。

## 2026-10-01 记忆 v1 合并；分组标记的决定

**合并 PR #24**（服务器分组）和 **PR #25**（记忆 v1），都还**没有部署**。

PR #24：
- 分组改由 Cloud Function `assignArm` 在服务器上做（决策 0003）。
- Flutter 固定为 3.35.3。原因：CI 用的 3.47 要求 Gradle ≥ 8.14，项目是 8.12，打包失败。
- 打 APK 时带上 `TESTER_PIN`；加 PR 模板。
- 首页「今個星期傾咗 N 次」改为统计所有聊天（之前只算签到）。
- 规则组隐藏阿珍/阿伯自由对话入口（决策 0006）。

PR #25：
- 服务器端记忆 v1：会话摘要、事实、待跟进；原话校验；共享策略 C；「我記得嘅嘢」页面；注入日志。实现见 `docs/dev/memory-v1.md`。
- Phase B Hybrid 组强制开启（决策 0007）；敏感事实页面确认（决策 0008）；约诊不算敏感（决策 0009）；保留 3 年（决策 0010）。
- onboarding 第一页加记忆说明。
- 注册后立即生效（修了要重启 App 才生效的问题）。
- 删除脚本 `tool/delete_memory.js`。

**讨论**：
- 负责人一度想只保留 Phase B、丢弃 Phase A。随后改为：现有账号标 `pilot`，Phase A 仍单独招募，但版本和 Phase B 同步（决策 0011）。
- 负责人整理了研究设计层面的记忆文档（决策 0001：记忆属于 Hybrid 组干预包），并开始调研记忆架构。

## 2026-09-30 Phase B 补齐；CI 修复

- **合并 PR #22**（`youthful-heisenberg`，Phase A 基线）：词库 v5、安全回应模板统一（`SafetyCopy`）、会话和轮次记录（`sessions` / `turns`）、测试人员 PIN、日程模拟器、修好 `functions/package-lock.json`。
- **合并 PR #23**（Phase B 基础 + CI/CD）：见 2026-09-29。
- 讨论并决定：分组为空时显示规则组（决策 0004）；记忆 v1 在 Phase B 默认打开（决策 0007、0008）。
- CI/CD 讨论：负责人同意走 PR 流程合并；测试用例表暂缓；不需要单独的 staging Firebase 项目。

## 2026-09-29 Phase B 基础

起点：读负责人的《陪住 记忆模块 技术交付文档 v0》，对照代码梳理现状。当时的完整说明见 `docs/history/2026-09-29-phase-b-switch.md`。

**做了**（PR #23）：
- Phase B 编译开关 `PHASE_B`。之前 `Arm.of` 写死返回 A。
- 服务器防线：`proxyDeepSeek`、`referralJudgement`、`webSearch` 拒绝规则组。
- 分组只能写一次；修了「分组被抹掉、下次登录重新抽签」。
- 修好分组计数器的 Firestore 规则：原规则超过规则引擎 1000 个表达式的上限，**所有**计数写入都被拒绝，注册流程吞掉了错误，所以没人发现。
- 被安全标记的轮次不进记忆（决策 0013）。
- 规则组不预生成首页问候。
- 通通规则组版本（决策 0005）。
- 规则组安全事件通知 PI（决策 0014）。
- GitHub Actions：CI、Build APK、Deploy Firebase。

**讨论**：
- 规则组要不要单独一个仓库：不要（决策 0002）。
- 同一个仓库可以多个分支并行开发：记忆 v1 在 `claude/memory-v1` 分支单独开发，后来合并。
- 记忆文档 v0 写「Phase A/B 一律关」，和代码里已有的 v0 滚动摘要冲突。当时的处理：v0 保持，v1 单独开关。后来被决策 0001、0007 取代。

## 2026-09 之前

Phase A 基线版本的开发、评审和交付记录在 `docs/release/`：
- `phase_a_review_2026-09-17.md`：基线评审；
- `phase_a_baseline_handback.md`、`phase_a_baseline_versions.md`：交接和版本；
- `phase_a_deploy_workflow_mac.md`：Mac 上的部署流程。

更早的开发笔记在仓库根目录（`ARCHITECTURE_NOTES.md`、`STATUS.md`、`REPORT.md` 等），部分已过时。分组方案的方法学讨论在 `docs/research/arm_assignment_scheme_v1.md`（2026-07）。
