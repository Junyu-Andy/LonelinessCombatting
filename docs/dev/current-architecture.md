# 陪住 App 现状架构审计（只读）

> 审计日期：2026-10-04 ｜ 对象：`main` @ `fa62c81`（分支 `claude/jolly-hypatia-3v2zvw` 与 `main` 同一提交）
> 性质：只读审计，没有改动任何代码、配置或其他文档。每条结论附「文件:行号」证据；没有证据的写「未找到」。
> 置信度：**高** = 直接看到代码；**中** = 从调用关系推断；**低** = 只看到命名或注释。
> 读者：项目负责人。先看第 0 节的结论和第 K 节的风险表，再按需要看各节。

## 0. 结论先行

**三份必读文档的情况**

| 文档 | 情况 |
|---|---|
| `docs/dev/architecture-v2.md` | **未找到**。本地和远端全部 10 个分支（`git ls-tree`）都没有这个文件，git 历史里也从未添加过。 |
| `docs/dev/safety-hardening-phaseB.md` | **未找到**。同上。 |
| `docs/dev/memory-and-entry-spec.md` | 存在。文件里没有「【待核对】」标记，但第 7 节「待确认」和第 8 节「技术核对」列了待答问题，第 12 节逐条回答。`docs/research/memory-in-hybrid-arm.md` 第 8 节的待确认项也一并回答。 |

因为 `architecture-v2.md` 不存在，最后一节「对 architecture-v2.md 的修正建议」改为对现有 `docs/dev/architecture.md` 和 `memory-and-entry-spec.md`（含 8.4 的工作量估计）的修正建议。

**最严重的 3 个问题**（详见 K 节）

| # | 问题 | 证据 | 置信度 |
|---|---|---|---|
| 1 | **规则组签到页的 acute 处理和 A 组不一致**：只弹一个硬编码热线的对话框，不打开紧急支援页、不写 `turns`、不走 `DistressRouter`；而且 `moderate_review` 级也会弹窗打断。两组「安全检测完全一致」的要求在这一页不成立。 | `lib/features/context/presentation/pages/check_in_arm_b.dart:182-198, 283-306`；对比 `lib/core/safety/distress_router.dart:70-78` | 高 |
| 2 | **研究关键字段客户端可写**：`strataCell`、`baselineUclaScore`、`ageGroup`、`memory_enabled`、`isTester` 客户端可随意改；`arm` 为 null 时客户端可自设 A/B；`meta/arm_counter` 任何登录用户可 +1；owner 可删除整个 `users/{uid}` 文档和 `sessions`/`turns`/`brief_pr` 等全部子集合。 | `firestore.rules:57-79, 185-211` | 高 |
| 3 | **研究员告警和仪表板实际不可用**：`pi_alerts` 没有任何读取方；仪表板读的 `shared_context.safetyFlags` 全仓库无写入者；仪表板从客户端直读 `te_audit_queue` 和整个 `users` 集合，但规则全拒且没有 role 判断；App 里也没有进入仪表板的入口。研究员能收到的只有 acute 级的 SMTP 邮件（且需要配好 4 个 secret）。 | `functions/index.js:874-910`；`lib/features/researcher_dashboard/presentation/pages/researcher_dashboard_page.dart:171, 449, 541`；`firestore.rules:63-79, 149-151`；`lib/core/agent_context/shared_context_service.dart:282`（无调用者） | 高 |

**其他需要知道的高置信度事实**

- 两组除回应生成外还有 17 处差异（K 表 1），其中 13 处与「只有回应后端不同」原则冲突：Brief PR 不在签到 B / 回忆 B 弹出、自由对话入口 B 组隐藏、逐模块转录同意只问 A 组，与「只有回应生成后端不同」原则冲突。
- `cohort` 字段代码里不存在，只在注释里出现（`docs/decisions/0011` 标明未实现）。
- 服务器拒绝 B 组调 LLM 的条件是 `arm === "B"`，`arm` 为 null 时放行（`functions/index.js:255-260`）。
- 5-flag 标注不是 LLM 标注，是纯正则（`functions/llm_flags.js`），不额外调用模型。
- 安全词表只在客户端，纯子串匹配，无规范化；服务器没有对等词表。
- `proxyDeepSeek` 对 DeepSeek 的 fetch 没有超时和重试，只靠函数级 55 秒超时。
- 定时推送三条全部不按组别区分；两条是 FCM topic 广播，测试账号和「今日休息」用户也会收到。
- 热线号码有 5 处硬编码绕过 `crisis_resources.json`，其中教育文章把 2382 0000 标成与 JSON 不同的机构名。

---

## A. 总体结构

### A1. 目录结构（两层）

| 目录 | 用途 | 置信度 |
|---|---|---|
| `lib/app` | 应用壳：`app.dart`（MaterialApp、全局 Scope）、`main_shell.dart`（4 个底部 tab）、`app_settings*`、主题 | 高 |
| `lib/core/agent_context` | v0 记忆：每个陪伴者的缓冲区与滚动摘要、intake 种子、跨陪伴者共享上下文 | 高 |
| `lib/core/agents` | 陪伴者注册表、头像、persona 解析 | 高 |
| `lib/core/arm` | `Arm.of / isA / isB / ArmGate`（只有 `arm_scope.dart` 一个文件） | 高 |
| `lib/core/config` | `PhaseAConfig` 运行参数 + `app_config/phase_a` 远程覆盖 | 高 |
| `lib/core/connectivity` | 联网检测、离线待发 | 中 |
| `lib/core/cross_referral` | 跨陪伴者转介三层逻辑 | 高 |
| `lib/core/fcm` | FCM token 登记、通知事件记录 | 高 |
| `lib/core/feature_flags` | 编译开关 `FeatureFlags`；`HybridOnlyMount`（无调用者） | 高 |
| `lib/core/llm` | `LlmGateway`（调 `proxyDeepSeek` 的唯一入口）、开场白服务、转录同意提示 | 高 |
| `lib/core/memory` | v0 存储、v1 客户端只读服务、`MemoryMode`、跨模块回调 | 高 |
| `lib/core/reminders` | 提醒意向写 `users/{uid}/reminders`（没有接本地通知） | 高 |
| `lib/core/repair` | 「重讲一次」修复按钮 | 低 |
| `lib/core/safety` | 安全词表、路由、事件写入、覆盖层、文案（两组共用） | 高 |
| `lib/core/scheduling` | 入组天数、待办问卷、日程模拟器 | 高 |
| `lib/core/session` | `ChatSessionRecorder`：会话与 turn 记录、空闲计时 | 高 |
| `lib/core/survey` / `telemetry` / `time` / `voice` / `version` / `testing` | Likert 控件 / 页面停留 / 可模拟时钟 / 语音输入 / 版本固定 / 测试员 PIN | 中 |
| `lib/features/*` | 34 个功能模块，见 A2 | 高 |
| `lib/l10n` | zh / zh_Hant_HK / en 文案 | 高 |
| `lib/shared/widgets` | 通用控件 | 高 |
| `functions/` | Cloud Functions：`index.js`（1697 行）、`arm.js`、`memory.js`、`llm_flags.js`、`prompts/`、`test/` | 高 |
| `firestore.rules` | 216 行安全规则 | 高 |
| `test/` | Flutter 单测 33 个 + `rules/`（规则测试）+ `parity/` | 高 |
| `tool/` | CI 脚本、管理脚本（dump、删除记忆、迁移、配置研究员）、版本导出 | 高 |
| `docs/` | `decisions/ dev/ history/ privacy/ prompts/ release/ research/ safety/` + `STUDY_CHANGELOG.md` | 高 |
| 根目录 `*.md` | 早期开发笔记（`ARCHITECTURE_NOTES.md` 等），部分已过时 | 中 |

### A2. Flutter 主要页面和模块

| 项 | 结论 | 证据 | 置信度 |
|---|---|---|---|
| 启动流程 | `AuthGate` → 无 profile 进 `LoginPage`；有 profile 进 `ConsentGate(MainShell)` | `lib/features/auth/presentation/pages/auth_gate.dart:46-80` | 高 |
| ConsentGate | 未同意→同意页；未完成 intake→intake 页；未选阿珍/阿伯→陪伴者引导页；否则主界面 | `lib/features/consent/presentation/consent_gate.dart:25-40` | 高 |
| 底部 4 个 tab | 睇今日 `TodayPage` / 搵人傾 `TalkPage` / 做啲嘢 `MePage` / 自己 `SettingsPage` | `lib/app/main_shell.dart:29, 117-131` | 高 |
| 路由 | 无命名路由，全部 `MaterialPageRoute` push | `lib/app/app.dart:206-240` | 高 |

`lib/features` 模块一句话（按页面文件名判断，置信度中）：

| 模块 | 一句话 | 模块 | 一句话 |
|---|---|---|---|
| action_loop | M7 行动计划：landing / arm_a / arm_b / followup | me | 「做啲嘢」工具列表 |
| adherence | ≥3 天没签到的横幅 | memory | 「我記得嘅嘢」页（v1 只读/删/确认） |
| agent_profile | 陪伴者资料页 | my_story | 人生回顾：本周入口、历史 |
| analytics | 写 `users/{uid}/events` | onboarding | intake 问卷、陪伴者引导 |
| assessment | DJG-ES、PGIC、agent_diff 量表 | personalization | 个人资料编辑 |
| auth | 登录/注册、`UserProfile`、`ArmAssigner` | phase_b_probes | 三种 Phase B 探针（无入口调用，见 F） |
| brief_pr | 会话后 Brief PR + gate | ppr | PPR 量表（无调用者） |
| consent | 同意页 + ConsentGate | progress | M9 进度页 |
| context | M2 签到 arm_a / arm_b | reflective_dialogue | 阿珍/阿伯自由对话（仅 A） |
| crisis | 紧急支援页、安全页脚卡 | reminiscence | M3 回忆 landing / arm_a / arm_b |
| curious_companion | 通通聊天（A LLM / B 规则） | researcher_dashboard | 研究员仪表板（无入口） |
| education | M8 文章库 | response_feedback | 👍👎 |
| follow_up | 跟进区块 | settings | 设置、FAQ、隐私、关于、测试员工具 |
| llm_features | 5 个 LLM 特征写 `llm_turn_features` | social_suggestions | M6 社交建议 |
| loneliness_probe | 周度孤独感探针（默认关） | talk / today / thought_exercise / weekly_pr / wellbeing | 搵人傾 / 首页 / 想法练习 / Weekly PR / 平静页 |

### A3. Cloud Functions 完整清单

全部 region `asia-east2`；所有 callable 都是 `enforceAppCheck: false`。`index.js` 自己包装 `arm.js` / `memory.js` / `llm_flags.js`（`functions/index.js:9-11`），没有 re-export。置信度全部为高。

| 名称 | 触发 | 选项 | 做什么 | 证据 |
|---|---|---|---|---|
| `proxyDeepSeek` | callable | secret `DEEPSEEK_API_KEY`；maxInstances 10；timeout 55s | 全部 LLM 对话：登录检查 → B 组拒绝 → 解析 prompt → 注入 v1 记忆 → stripPII → DeepSeek → 5-flag | `index.js:273-413` |
| `safetyAcknowledgement` | callable | maxInstances 5 | 按陪伴者/级别返回安全回应模板并填热线；**客户端没有调用它** | `index.js:420-434` |
| `referralJudgement` | callable | `DEEPSEEK_API_KEY`；timeout 20s | 跨陪伴者转介第二层 LLM 判断；B 组拒绝 | `index.js:440-566` |
| `webSearch` | callable | secret `SEARCH_API_KEY`；timeout 20s | Brave Search；B 组拒绝；客户端常量已全局关闭 | `index.js:568-646`；`tung_tung_page.dart:104` |
| `transcribeAudio` | callable | timeout 120s；512MiB | Google Speech v2（chirp_2 → long）；**无组别检查**；客户端没有调用方 | `index.js:648-796` |
| `onSafetyEventCreated` | Firestore `safety_events/{id}` | secrets `SMTP_HOST/USER/PASS`、`PI_EMAIL` | 分钟级去重 → 只对 acute 写 `pi_alerts` → 非测试账号发 SMTP 邮件 | `index.js:798-935` |
| `onThoughtExerciseCreated` | Firestore `users/{uid}/thought_exercise/{id}` | env `TE_AUDIT_SAMPLE_RATE`（默认 1.0） | 抽样写 `te_audit_queue` | `index.js:962-1010` |
| `weeklyLonelinessProbe` | cron `0 9 * * SUN` Asia/Hong_Kong | retry 1 | 给 `weeklyProbeEnabled==true` 用户写顶层 `pending_loneliness_probes/{uid}`；不推送 | `index.js:1056-1096` |
| `blindedDataExport` | cron `0 2 * * SUN` HK | timeout 540s；1GiB | 盲法导出 16 个集合到 Storage `exports/{date}/` | `index.js:1181-1273` |
| `memoryEndSession` | callable | `DEEPSEEK_API_KEY`；timeout 60s | v1：取缓冲区 → DeepSeek 抽取 → 写 `mem_*` | `index.js:1353-1378` |
| `memorySweep` | cron `every 15 minutes` HK | timeout 300s | v1：补抽取 30 分钟空闲的缓冲区，重试失败记录（attempts<3） | `index.js:1380-1443` |
| `dailyMoodReminder` | cron `0 19 * * 1-6` HK | — | FCM topic `all` 广播 | `index.js:1445-1459` |
| `weeklySurveyReminder` | cron `0 20 * * 0` HK | — | topic 广播 + 给非测试账号写 `weekly_pr_pushed` 事件 | `index.js:1461-1497` |
| `assignArm` | callable | maxInstances 10 | 服务器分组（见 B） | `index.js:1549-1565`；`arm.js:70-125` |
| `week2Push` | cron `0 10 * * *` HK | — | 入组第 14–16 天逐设备推送 | `index.js:1567-1631` |
| `sendTestPush` | callable | timeout 60s | 测试账号对自己发测试推送 | `index.js:1650-1696` |

### A4. Firestore 集合

规则要点：`users/{uid}` 本人读/写/删（`firestore.rules:63-72`）；`users/{uid}/{任意子集合}` 本人读写，`mem_*` 除外（`:77-79`）；其余默认拒绝（`:214`）。

| 路径 | 用途 | 谁写 | 客户端规则 | 证据 | 置信度 |
|---|---|---|---|---|---|
| `users/{uid}` | 资料、`arm`、`strataCell`、`armAssignmentMode`、`consent`、`memory_enabled`、`isTester`、`baselineUclaScore`、`ageGroup`、`createdAt`、`w2PushSentAt` | App + 服务器（分组字段、`w2PushSentAt`） | 本人读/删/建/改；`arm` 写一次 | `rules:63-72`；`lib/features/auth/data/user_profile.dart:359-397` | 高 |
| `users/{uid}/sessions`、`turns` | 会话与每轮记录（字段见 E1） | App | 本人读写删 | `lib/core/session/chat_session_recorder.dart:339, 435` | 高 |
| `users/{uid}/events` | 行为事件 | App + 服务器 | 本人读写删 | `lib/features/analytics/data/analytics_service.dart:155-157` | 高 |
| `users/{uid}/agent_contexts/{agentId}` | v0 缓冲区 + 滚动摘要（也是 v1 的输入） | App；服务器 claim | 本人读写删 | `lib/core/agent_context/agent_context_service.dart:157-159`；`memory.js:665` | 高 |
| `users/{uid}/shared_context/current` | 跨陪伴者共享：转介、行动计划、情绪 | App | 本人读写删 | `shared_context_service.dart:194-197` | 高 |
| `users/{uid}/memory/{moduleId}/entries`；`memory/m3_reminiscence/sessions/week_N` | v0 模块摘要、回忆会话 | App | 本人读写删 | `memory_store.dart:47-51`；`m3_session_store.dart:187-192` | 高 |
| `users/{uid}/mem_facts`、`mem_summaries`、`mem_followups` | v1 记忆 | 服务器 | 本人读/删；`mem_facts` 仅可 pending_confirmation→active | `rules:89-102`；`memory.js:742-797` | 高 |
| `users/{uid}/mem_injections`、`mem_extractions` | v1 注入日志、抽取记录 | 服务器 | 全拒 | `rules:103-108` | 高 |
| `users/{uid}/brief_pr`、`weekly_pr`、`pgic`、`djg_es`、`agent_diff`、`daily_mood`、`check_in_responses`、`ppr_responses`、`loneliness_probes`、`response_feedback`、`tester_feedback`、`llm_turn_features`、`agent_greetings`、`onboarding/intake`、`fcm_tokens`、`reminders`、`action_plans`、`thought_exercise`、`thought_records`、`cross_module_callbacks`、`unblinding_probes`、`dependency_probes`、`distinguishability_probes`、`pending_loneliness_probes/current`、`m3_reminiscence` | 问卷、量表、反馈、特征、开场白、intake、推送 token、各功能数据 | App | 本人读写删 | `brief_pr_page.dart:131-133`；`weekly_pr_page.dart:117-119`；`pending_prompts_service.dart:138-165`；`djg_es_page.dart:44-46`；`agent_diff_page.dart:156-158`；`mood_recorder.dart:40`；`check_in_arm_b.dart:206-208`；`llm_turn_features.dart:101-103`；`agent_greeting_service.dart:62-64`；`intake_repository.dart:10-16`；`fcm_service.dart:144-146`；`reminder_service.dart:91-93`；`action_plan.dart:105-107`；`thought_exercise_entry.dart:152-154`；`phase_b_probes.dart:136-169`；`loneliness_probe.dart:84-110` | 高 |
| `safety_events/{id}` | 安全事件（字段见 D5） | App create；服务器回写 `dedup_key` | 仅本人 create；不可读改删 | `rules:123-131` | 高 |
| `safety_event_dedup`、`pi_alerts` | 去重哨兵、acute 告警队列 | 服务器 | 全拒 | `rules:137-142` | 高 |
| `te_audit_queue` | 想法练习审计队列 | 服务器写；仪表板客户端读写（被规则拒） | 全拒 | `rules:149-151` | 高 |
| `pending_loneliness_probes/{uid}`（顶层） | cron 写的待答队列；**App 读的是 `users/{uid}/pending_loneliness_probes/current`，两个路径不同，未找到镜像代码** | 服务器 | 全拒 | `index.js:1086`；`lib/features/loneliness_probe/data/loneliness_probe.dart:84-90`；`rules:159-161` | 高 |
| `export_blind_keys/{date}` | 盲法映射与盐 | 服务器 | 全拒 | `rules:167-169` | 高 |
| `stt_usage` | 语音转写用量 | 服务器 | 无规则（默认拒） | `index.js:747` | 高 |
| `meta/arm_counter` | 4 层 A/B 计数 | 服务器 | **登录用户可读、可写（每次恰好 +1）** | `rules:185-211` | 高 |
| `meta/memory_config` | v1 记忆开关 | 控制台手工 | 无规则（默认拒） | `memory.js:516` | 高 |
| `app_config/arm_assignment`、`app_config/phase_a` | 随机开关、运行参数 | 控制台手工 | 登录用户可读，不可写 | `rules:118-121` | 高 |
| `researchers` | — | — | **未找到**（研究员靠 custom claim） | `tool/provision_researcher.js:5-9` | 高 |

### A5. 编译开关、构建 flavor、环境变量

| 开关 | 默认 | 读取位置 | 影响 | 置信度 |
|---|---|---|---|---|
| `PHASE_B`（dart-define） | `false` | `lib/core/feature_flags/feature_flags.dart:33-34, 45` | false 时 `Arm.of` 恒为 A（`arm_scope.dart:30`）；`MemoryMode.phaseB` 需要它为 true | 高 |
| `FORCE_ARM` | 空 | `lib/core/arm/arm_scope.dart:23, 31-33` | 仅 `PHASE_B=true` 时覆盖组别；**无 release 保护** | 高 |
| `MEMORY_V1` | `false` | `feature_flags.dart:35-36, 53` | 测试员可自愿开 v1 | 高 |
| `WEEKLY_PROBE` | `false` | `feature_flags.dart:31-32, 40` | 显示周度孤独感探针 | 高 |
| `FORCE_LLM_FALLBACK` | `false` | `lib/core/llm/llm_gateway.dart:386-387` | 所有 LLM 调用走 fallback | 高 |
| `TESTER_PIN` | 空（= 测试工具锁死） | `lib/core/testing/tester_gate.dart:25, 31` | 关于页连点 7 次输入 PIN 解锁 | 高 |
| Android flavor | **未找到** `productFlavors`；applicationId `com.example.app_demo`，debug 签名 | `android/app/build.gradle.kts:27-40` | — | 高 |
| 服务器 secrets（`defineSecret`） | `DEEPSEEK_API_KEY`、`SMTP_HOST`、`SMTP_USER`、`SMTP_PASS`、`PI_EMAIL`、`SEARCH_API_KEY` | `functions/index.js:15-19, 568` | — | 高 |
| 服务器 env | `GCLOUD_PROJECT`/`GCP_PROJECT`；`TE_AUDIT_SAMPLE_RATE`（仓库内没有设置的地方） | `index.js:707, 985` | — | 高 |
| Firebase 项目 | `loneliness-pilot-dev`；`firebase.json` 无 emulators 配置块 | `.firebaserc:3`；`firebase.json:2-48` | — | 高 |
| CI 传递 | `tool/ci_flutter_tests.sh:31-37`（PHASE_B / FORCE_ARM=B / MEMORY_V1）；`build-apk.yml:50-55`；`codemagic.yaml` 不传任何 dart-define | — | — | 高 |

### A6. `meta/*` 与 `app_config/*` 配置文档

| 文档 | 字段 | 类型 / 默认 | 读取位置 | 置信度 |
|---|---|---|---|---|
| `app_config/arm_assignment` | `randomise` | bool；非 `true` → 全部分 A，mode `force_a` | `functions/arm.js:74, 104-108` | 高 |
| `app_config/phase_a` | `sessionIdleTimeoutMin` 10、`briefPRMinTurns` 2、`briefPRItemCount` 4（clamp 3–4）、`weeklyPrPushHour` 20、`weeklyPrCloseWeekday` 2、`w2DayOffset` 14、`w2WindowDays` 3、`week1NudgeDays` [3,6] | int / List | 客户端 `lib/core/config/phase_a_config.dart:22-31, 74-112`；服务器只读 `w2DayOffset`/`w2WindowDays`（`index.js:1524-1532`） | 高 |
| `meta/arm_counter` | `cell_0..cell_3: {aCount, bCount}`、`updatedAt` | map / int，缺省 0 | `arm.js:73, 100-116` | 高 |
| `meta/memory_config` | `enabled`（默认 false）、`policy`（A/B/C，默认 C）、`phaseBArmA`（默认 false） | — | `memory.js:515-524`；`index.js:1391-1398` | 高 |
| `meta/memory_config.mrtFollowupEnabled` | 规格 4.2 提到 | **代码未找到** | — | 高 |
| `tool/export_config.js` | 规格第 6 节提到 | **文件不存在** | — | 高 |

---

## B. 分组

### B1. `assignArm` 完整逻辑（`functions/arm.js`）

| 项目 | 结论 | 证据 | 置信度 |
|---|---|---|---|
| 输入 | 只用 `request.auth.uid`，不接受客户端数据 | `index.js:1549-1556`；`arm.js:70` | 高 |
| 分层 | UCLA `baselineUclaScore > 44` 为高（非数字按 44 = 低）；`ageGroup` 字符串映射 62/67/72/77，`>= 70` 为老（未知按 60）；`strataCell` 0–3 | `arm.js:21-44, 95-96` | 高 |
| 开关 | `app_config/arm_assignment.randomise === true` 才随机；否则全 A | `arm.js:74, 104` | 高 |
| `armAssignmentMode` | 只有 `"randomise"` 和 `"force_a"` 两个值 | `arm.js:106` | 高 |
| 层内规则 | 少者优先；相等时 `Math.random() < 0.5`（无种子、无日志） | `arm.js:52-57, 71` | 高 |
| 事务 | 同一事务读 user / counter / config，写 counter + user | `arm.js:76-124` | 高 |
| 写入字段 | `arm`、`strataCell`、`armAssignedBy: "server"`、`armAssignedAt`、`armAssignmentMode`（merge） | `arm.js:115-121` | 高 |
| 幂等 | 已有 arm 原样返回 `assigned: false`，不计数 | `arm.js:83-92` | 高 |
| 错误 | 无 profile → `failed-precondition`；其他 → `internal` | `arm.js:80-82`；`index.js:1552-1563` | 高 |
| 审计日志 | **未找到**（不写时间、层、计数、硬币结果） | — | 高 |

伪代码：
```
tx: user, counter=meta/arm_counter, config=app_config/arm_assignment
if !user.exists → profile_missing
if user.arm ∈ {A,B} → return 已有值
cell = strata(baselineUclaScore>44, age>=70)
arm = randomise ? (少者优先, 平局 Math.random) : "A"
counter[cell][arm]++ ; user.set{arm, strataCell, armAssignedBy, armAssignedAt, armAssignmentMode}
```

### B2. 客户端调用与 `Arm.of`

| 项目 | 结论 | 证据 | 置信度 |
|---|---|---|---|
| 注册时调用 | `signUp()` 先写 profile 再调 `assignArm`；失败不阻断注册 | `lib/features/auth/data/auth_service.dart:120-141` | 高 |
| 登录回填 | `existing.arm == null` → 再调；失败下次再试 | `auth_service.dart:202-221` | 高 |
| callable 超时 | 20 秒 | `lib/features/auth/data/arm_assigner.dart:95-108` | 高 |
| `Arm.of` | 非 PHASE_B 包恒返回 A；PHASE_B 包：`FORCE_ARM` 优先，否则 `profile.arm` | `lib/core/arm/arm_scope.dart:26-35` | 高 |
| `arm` 为 null | PHASE_B 包显示 **B 组** 界面（决策 0004） | `arm_scope.dart:42-43` | 高 |
| 绕过 `Arm.of` 直接读 `profile.arm` 的地方 | 5 处（不受 FORCE_ARM 影响） | `reflective_dialogue_page.dart:257, 482`；`pending_prompts_service.dart:98`；`agent_greeting_service.dart:133`；`memory_mode.dart:28-33` | 高 |

### B3. 哪些地方读取组别

服务器：

| 位置 | 用途 | 条件原文 | `arm` 为 null | 置信度 |
|---|---|---|---|---|
| `index.js:243-249` `armFor` | 读 `users/{uid}.arm`，按实例缓存非 null 值 | `snap.get("arm") \|\| null` | 不缓存 | 高 |
| `index.js:255-260` `assertLlmAllowed` | 拒绝 B 组 | `if (await armFor(uid) === "B") throw permission-denied` | **放行** | 高 |
| `index.js:287 / 452 / 599` | `proxyDeepSeek` / `referralJudgement` / `webSearch` 入口调用上项 | 同上 | 放行 | 高 |
| `index.js:675-690` `transcribeAudio` | **无组别检查** | — | — | 高 |
| `memory.js:538-547` `inScope` | v1 记忆范围 | `arm==="B"→false; phaseBArmA && arm==="A" && mode==="randomise"→true; else memory_enabled===true` | 看 `memory_enabled` | 高 |
| `index.js:1396-1409` `memorySweep` | 同上 + `if (arm === "B") continue` | — | — | 高 |
| `index.js:1172-1175` 导出 | `arm` → `groupCode` | — | 非字符串则丢弃 | 高 |
| 推送函数 | **未见按组别分支** | — | — | 高 |

客户端（界面分支完整表见 F4）：`check_in_page.dart:16`、`reminiscence_landing.dart:71-74`、`tung_tung_page.dart:163`、`my_story_page.dart:65`、`social_suggestions_page.dart:69,124,168`、`education_article_page.dart:162`、`progress_page.dart:68,92,169`、`today_page.dart:82`、`greeting_hero.dart:58-119`、`facts_recap_row.dart:54-81`、`action_loop_landing.dart:107`、`action_loop_followup_page.dart:94`、`m3_session_detail_page.dart:127`、`memory_mode.dart:27-40`、`llm_gateway.dart:197`、`analytics_service.dart:47-50`、`researcher_dashboard_page.dart:541-551`（置信度高）。

客户端 **没有** 在 `LlmGateway` 统一拒绝 B 组的代码；B 组不调 LLM 依赖各页面分支 + 服务器 `assertLlmAllowed`（置信度中）。

### B4. cohort

| 结论 | 证据 | 置信度 |
|---|---|---|
| 代码里**没有** `cohort` 字段；5 处命中全是注释 | `lib/shared/widgets/app_modal.dart:10`；`user_profile.dart:10`；`researcher_dashboard_page.dart:447`；`reminiscence_themes.dart:2`；`phase_b_probes.dart:101`；`functions/`、`firestore.rules`、`test/`、`tool/` 未找到 | 高 |
| 区分 Phase A/B 的实际字段是 `armAssignmentMode` | `arm.js:106`；`memory.js:541-542` | 高 |

### B5. Firestore 规则对组别相关字段

| 字段 / 对象 | 客户端能否写 | 证据 | 置信度 |
|---|---|---|---|
| `arm` | 当前为 null 时可自设 A/B；已有 A/B 后不能改、删、置 null | `firestore.rules:50-52, 67-71` | 高 |
| `armAssignmentMode`、`armAssignedBy`、`armAssignedAt` | 不能新增或改动 | `rules:57-61` | 高 |
| `strataCell` | **可随意写改**（不在保护列表；`toMap` 会回写） | `rules:57-61`；`user_profile.dart:380` | 高 |
| `baselineUclaScore`、`ageGroup` | **可随意写改**（分层输入） | `user_profile.dart:363, 398` | 高 |
| `memory_enabled`、`isTester`、`consent`、`weeklyProbeEnabled` | 可随意写改 | `user_profile.dart:374, 388, 397`；`test/rules/profile_arm.test.js:137-142` | 高 |
| 整个 `users/{uid}` | owner 可删除 | `rules:64` | 高 |
| `meta/arm_counter` | 任何登录用户可读、可 +1 | `rules:185-211` | 高 |
| 研究员判定 | 规则里**没有** researcher / custom claim 分支 | `firestore.rules` 全文 grep 无 `researcher` | 高 |

### B6. 分组相关测试

`test/rules/profile_arm.test.js`（arm 写一次、B→A 拒绝、客户端写 mode 拒绝）、`test/rules/arm_counter.test.js`（每次恰 +1）、`functions/test/arm_test.js`（分层纯逻辑）、`functions/test/arm_emulator_test.js`（幂等、并发只计 1 次、平衡）、`functions/test/memory_test.js:309-330`（记忆 scope）。**未找到** `proxyDeepSeek` 对 B 组 permission-denied 的后端测试（置信度高）。

### B7. HTML 随机化工具

仓库里**没有**独立 HTML 随机化工具（`find -name "*.html"` 只有 Flutter 壳 `web/index.html`）。「v1.3.1 / DJG-ES」只在 `docs/research/memory-in-hybrid-arm.md:103` 出现。`assignArm` 用的是 UCLA(>44) × 年龄(≥70) 四格最小化，不是 DJG-ES 分层（`arm.js:21-57`）。`docs/research/arm_assignment_scheme_v1.md:42-45` 仍描述旧的客户端 `ArmAssigner(forceArmA)` 机制，与现行实现不一致。置信度高。

---

## C. 回应生成

### C1. 规则组引擎

全部在**客户端**、全部是 Dart 常量、全部确定性（无随机数）；服务器没有模板。置信度高。

| 模块 | 文件 | 条数 | 选法 | 证据 |
|---|---|---|---|---|
| 通通回复 | `lib/features/curious_companion/data/tung_tung_rule_responder.dart` | 10 主题 27 条 + 6 条 generic = 33 | 关键词包含匹配，按主题顺序首个命中；主题内按 `userTurnIndex % n` 轮换；每第 3 轮追加一个 opener | `:63-177, 194-220` |
| 通通开场 | `tung_tung_rule_pool.dart` | 20 条（版本 `2026-06-v2`） | `(今天 − 2026-01-01 天数) % 20`，每天换一条 | `:34-85`；`tung_tung_page.dart:173-175` |
| 签到 B | `check_in_arm_b.dart` | 6 脸 + 3 道选择题 + 自由文本 | 无回复生成；保存后固定句「收到喇。聽日再見。」 | `:71-102, 135-138` |
| 回忆 B | `reminiscence_arm_b_page.dart`；`reminiscence_themes.dart` | 4 周主题各 1 句开场 | 按 `weekIndex`；无追问 | `reminiscence_themes.dart:26-67` |
| M5 反思固定题库 | **未找到**；B 组不显示入口 | — | — | `my_story_page.dart:63-68` |
| M6 社交建议 | `suggestion_pool.dart` | 16 条 | 当年第几天 `% 16` 起连取 2 条 | `:31-163`；`social_suggestions_page.dart:148-150` |
| M7 行动计划 | `action_loop_arm_b_page.dart` | 四组各 3 个下拉项 | 用户自选 | `:111-130` |

B 组是否有路径调 LLM：13 个 `llm.send` 调用点全部被 `ArmGate` / `Arm.isA` / `_ruleBased` 门控（13 处调用点：`check_in_arm_a.dart:519`、`reminiscence_arm_a_page.dart:424, 623`、`tung_tung_page.dart:386`、`reflective_dialogue_page.dart:245, 471`、`social_suggestions_page.dart:102`、`action_loop_arm_a_page.dart:192`、`action_loop_followup_page.dart:100`、`education_article_page.dart:100`、`progress_page.dart:104`、`agent_greeting_service.dart:124`、`rolling_summary_compiler.dart:110`；对应门控：`check_in_page.dart:16-19`、`tung_tung_page.dart:271-274`、`social_suggestions_page.dart:69`、`action_loop_followup_page.dart:94`、`education_article_page.dart:162`、`progress_page.dart:92`、`today_page.dart:82`）。`HybridOnlyMount` 定义了但**无任何页面使用**（`lib/core/feature_flags/hybrid_only_mount.dart`）。置信度高。

### C2. `proxyDeepSeek` 完整流程（`functions/index.js`）

| 步骤 | 行号 | 内容 | 置信度 |
|---|---|---|---|
| 配置 | 273-282 | `enforceAppCheck: false`；`timeoutSeconds: 55`；maxInstances 10 | 高 |
| 鉴权 | 284-287 | 未登录 → `unauthenticated`；`assertLlmAllowed`（B 拒绝，null 放行） | 高 |
| 校验 | 289-297 | `messages` 非空数组；`moduleId` 默认 `"unknown"` | 高 |
| 解析 prompt | 100-121 | 无 `promptKey` 有 `systemPrompt` → **原样用客户端文本**；有 `promptKey` → 读 `functions/prompts/<key>.txt`；替换 `{{VARIANT_NAME}}`；`contextSuffix` 经 `stripPII` 后接在后面 | 高 |
| 版本号 | 59-71 | 从文件第 1 行正则解析为 `siu_yan_v1@2026-06`；raw prompt 调用为 null | 高 |
| 记忆 v1 注入 | 313-321 → `memory.js:607-650` | 条件：agentId 合法、moduleId 匹配 `INJECT_MODULES`（`memory.js:37-39`）、`meta/memory_config.enabled` 且 `inScope`；块 ≤2000 字；再 `stripPII` 后追加到 system prompt **末尾**。顺序：persona → contextSuffix → 记忆块 | 高 |
| stripPII | 143-165, 328-331 | 4 条正则：电话、邮箱、HKID、楼层/室；**姓名不脱**；uid 换成盐化哈希 `X-Session-Code` | 高 |
| 消息数组 | 348-351 | `[system, ...客户端传来的 history + 本轮]`；客户端不截断 history（`llm_gateway.dart:407-417`） | 高 |
| 调用 | 333-361 | `https://api.deepseek.com/chat/completions`；`model: "deepseek-chat"`；`max_tokens: 800`；`top_p: 0.95`；温度按陪伴者 0.5 / 0.7 / 0.85（`:213-227`） | 高 |
| 超时 | 281 | 仅函数级 55s；**fetch 无 timeout、无 AbortController** | 高 |
| 重试 | — | **未找到** | 高 |
| 出错 | 364-376 | 非 2xx → `HttpsError('internal', 'deepseek <status>: <body前400字>')`；fallback 文本在客户端 | 高 |
| 5-flag | 393-398 | `computeLlmFlags` 纯正则 | 高 |
| 返回 | 400-412 | `{text, moduleId, agentId, systemPromptHash, llmFlags, model, temperature, promptVersion}`；**无 usage、无 latency** | 高 |
| 写库 | — | 函数本身不写 turn；只有 `injectMemory` 写 `mem_injections` 和更新 `mem_followups`；turn 由客户端 `ChatSessionRecorder` 写 | 高 |
| 客户端传了但服务器不读 | — | `regenerate` 标志（`llm_gateway.dart:425`，`index.js` 0 处引用） | 高 |

### C3. 记忆抽取的 DeepSeek 调用

`index.js:1326-1351 callDeepSeekJson`：同一 URL，`model: "deepseek-chat"`，`response_format: json_object`，`temperature: 0.2`，`max_tokens: 1500`；fetch 无超时；失败写 `mem_extractions.status='failed'`，由 `memorySweep` 每 15 分钟重试到 `attempts<3`，无退避（`memory.js:85-93, 826-833`；`index.js:1423-1437`）。置信度高。

### C4. 客户端 `LlmGateway`（`lib/core/llm/llm_gateway.dart`）

| 环节 | 行号 | 说明 | 置信度 |
|---|---|---|---|
| 调用前 | 94-132 | `DistressDetector.analyze(userInput)`；escalation 写 safety event；**acute 短路不调 LLM** | 高 |
| 传输 | 377-489 | `httpsCallable('proxyDeepSeek')`，`.timeout(50s)`；**无重试** | 高 |
| 错误分类 | 458-487 | `cf_<code>` / `timeout` / `network` / `bad_shape` / `forced_fallback` → `LlmStatus.fallback` | 高 |
| 调用后 | 159-177 | 对输出再查一次词表；空文本 → `empty_response` | 高 |
| fallback 文案 | `assets/config/llm_fallback_messages.json`；`safety_copy.dart:142, 155-159` | 页面在 `isFallback` 时替换回复 | 高 |
| 离线 | `lib/core/connectivity/connectivity_service.dart:13-23` | 4 个 A 组聊天页自己暂存、恢复后重发；网关不处理 | 高 |
| contextSuffix 拼装 | `lib/core/agents/persona_resolver.dart:109-168` + 各页面（`check_in_arm_a.dart:508-513`、`tung_tung_page.dart:324-377` 等） | v0 摘要、命名实体、主题线、情绪片段、兴趣、文章、搜索结果、avoidTopics | 高 |

### C5. 两组分叉点

| 模块 | 分叉点 | A 组 | B 组 | 置信度 |
|---|---|---|---|---|
| M2 签到 | `check_in_page.dart:16-19`（ArmGate） | `check_in_arm_a.dart` | `check_in_arm_b.dart` | 高 |
| M3 回忆 | `reminiscence_landing.dart:71-76`；`current_session_entry.dart:110-115` | `reminiscence_arm_a_page.dart` | `reminiscence_arm_b_page.dart` | 高 |
| M5 自由对话 | `my_story_page.dart:65` | `reflective_dialogue_page.dart` | 无入口 | 高 |
| 通通 | `tung_tung_page.dart:163, 172, 271, 770` | 同页 LLM 分支 | 同页 `_sendRuleBased` | 高 |
| M8 文章问答 | `education_article_page.dart:162` | 「問通通呢篇」按钮 | 无 | 高 |
| M6 社交建议 | `social_suggestions_page.dart:69, 124, 168` | LLM 2 条 | 池轮换 2 条 | 高 |
| M7 行动计划 / 跟进 | `action_loop_landing.dart:107-109`；`action_loop_followup_page.dart:94` | LLM | 模板 / 只保存 | 高 |
| M9 进度 | `progress_page.dart:92, 169` | 周小结卡 | 无 | 高 |
| 首页开场白预热 | `today_page.dart:82` | 预生成 | 不调用 | 高 |
| 跨陪伴者转介 | `check_in_arm_a.dart:685-686`；`reflective_dialogue_page.dart:390-391` | 调 `referralJudgement` | 无 | 中 |

### C6. v0 滚动摘要与 prompt 文件

- `rolling_summary_compiler.dart:110-122` 走 `LlmGateway.send → proxyDeepSeek`，`moduleId: rolling_summary_fold`，raw `systemPrompt`，`skipSafetyScan: true`；v1 用户改调 `memoryEndSession`（`:60-63`）。置信度高。
- prompt 文件：`siu_yan_v1.txt`（第 1 行 `v1 (rev 2026-06)`，82 行）、`ah_jan_ah_bak_v1.txt`（`v1 (rev 2026-09)`，117 行）、`tung_tung_v1.txt`（`v1 (rev 2026-06)`，98 行）。命名仍是 `<name>_v1.txt`，未按 CLAUDE.md 迁移到 `<name>.v<N>.txt`。置信度高。
- `docs/prompts/context_suffix_template.txt` **运行时不读取**，只用于导出脚本、版本 pin 测试和 bundle hash（`tool/export_spec_inputs.py:42`；`test/phase_a_version_pin_test.dart:58`）。置信度高。
- 抽取 prompt 在 `functions/memory.js:194-229` 代码里，不在文件里。置信度高。

---

## D. 安全

### D1. 词表

| 项 | 结论 | 证据 | 置信度 |
|---|---|---|---|
| 位置、格式 | `lib/core/safety/distress_detector.dart`，Dart `static const List<_TermGroup>` | `:121-126, 193-366` | 高 |
| 版本 | `wordlistVersion = 'v5-2026-09'` | `:164` | 高 |
| 条数 | acute 160 / moderate_interrupt 48（含 S-7 可配置 4 条）/ moderate_review 19 / low 42 = 269；与 `docs/safety/distress_detector_lexicon_v5-2026-09.md` 逐条一致 | `:193-272, 279-327, 334-351, 353-366, 170-173` | 高 |
| 排除短语 / 白名单 | **未找到** | `:176-178` 只有注释 | 高 |
| 服务器端词表 | `functions/memory.js:71-75` `SAFETY_TERMS` 仅 17 条，只用于记忆过滤，不是安全路由；3 条客户端没有（死咗算 / 跳樓 / 跳楼） | `memory.js:153-156, 281-286, 323-327` | 高 |
| 性能文档 | `docs/safety/distress_detector_performance_v1.0.md` 基于 v3 词表、190 条自写语料、单人标注；v4/v5 之后未重跑 | 文档 `:12-17, 55-60` | 高 |

### D2. 匹配函数

| 问题 | 结论 | 证据 | 置信度 |
|---|---|---|---|
| 算法 | `text.toLowerCase()` 后按 acute → interrupt → review → low 顺序 `contains`，首个命中即返回 | `distress_detector.dart:406-417` | 高 |
| 规范化 | 无繁简转换、无去空格 / 标点、无全半角；靠词表同时列繁 / 简 / 变体 | `:407-408, 189, 223-233` | 高 |
| 运行位置 | 只在客户端；服务器 `proxyDeepSeek` 对输入**不做**任何词表检查 | `index.js` 无 `hitsSafety` 调用 | 高 |
| 两组是否都跑 | 是。A 组网关对输入（`llm_gateway.dart:96`）和输出（`:161`）各一次；B 组各页只查输入：通通 `tung_tung_page.dart:540`、回忆 B `:62`、签到 B `:155`。**B 组行动计划自由文本未检测**（`action_loop_arm_b_page.dart` 无 `analyze`），A 组走网关会检测 | 各行 | 高 |
| node 最小示例 | 客户端词表是 Dart 常量，**未找到 node 可直接调用的实现**。最接近的是服务器 17 条词的 `hitsSafety`，已实际运行通过（exit 0）： | `memory.js:153, 845` | 高 |

```js
const m = require('/home/user/LonelinessCombatting/functions/memory.js');
m.hitsSafety('我想自殺');     // true
m.hitsSafety('今日去街市');   // false
m.hitsSafety('自 殺');        // false（不去空格）
```
注意：这个函数只有 17 条词，不能替代客户端 269 条词表做评估。

### D3. 5-flag 标注（`functions/llm_flags.js`）

| 项 | 结论 | 证据 | 置信度 |
|---|---|---|---|
| 是否 LLM | **否**。纯正则 / 子串启发式，文件里没有模型调用、没有 prompt | 全文无 fetch / 模型名 | 高 |
| 标注对象 | 输入+输出成对：F1/F2/F4 看 (userInput, assistantOutput)，F3 只看输出，F5 看 moduleId+输出 | `:276-286` | 高 |
| 调用时机 | `proxyDeepSeek` 拿到 DeepSeek 文本后同步计算，随响应返回 | `index.js:394-407` | 高 |
| 超时 / 出错 | 无 try/catch、无超时（纯同步） | — | 高 |
| 写到哪 | 客户端 `turns.flags.F1..F5`；`users/{uid}/llm_turn_features`（仅 A 组） | `chat_session_recorder.dart:177, 198-211`；`llm_turn_features.dart:116` | 高 |
| 两组 | B 组被 `assertLlmAllowed` 拦截，B 组 `turns.flags` 存在但全为 null | `recorder:206-210` | 高 |
| 五个 flag | `specific_content_engagement`（输入实体在输出中复现，`:96-125`）、`cross_session_memory`（输出 n-gram 来自 rollingSummary/buffer，`:154-175`）、`honest_unfamiliarity`（「我未聽過」等正则，`:185-202`）、`mixed_content_routing`（输入含信息+情绪且输出含转介措辞，`:211-234`）、`generative_summary`（摘要类 moduleId 或 ≥60 字+时间标记+第二人称，`:253-270`） | — | 高 |
| 测试 | `functions/test/llm_flags_test.js` 11 条手写 fixture，不测稳定性 | `:22-175` | 高 |

### D4. 四级路由两组对比

路由器本身两组共用（`lib/core/safety/distress_router.dart:47-80`）：none/low 只更新已隐藏的 pill；moderate_review 什么都不做；moderate_interrupt 弹底部 sheet；acute 全屏打开 `EmergencySupportPage`。模板来自 `functions/prompts/safety_acknowledgements.json`（`{{HOTLINE_NAME/NUMBER}}` = 撒瑪利亞會 2896 0000）。服务器 `safetyAcknowledgement` 函数客户端**未调用**。

| 级别 | A 组（网关路径） | B 组通通 / 回忆 B | B 组签到 | 差异 | 置信度 |
|---|---|---|---|---|---|
| none / low | LLM 回复；写 `turns.detector`；不路由 | 模板回复；同 | 只存 `check_in_responses` | 签到 B 不调 router | 高 |
| moderate_review | LLM 照常回复，**不加模板**；写 `safety_events`；不打断 | 同（`tung_tung_page.dart:601-603`；`reminiscence_arm_b_page.dart:63-71`） | **弹 `_SafetyEscalationDialog`**（条件是 `isEscalation`，包含 review） | **签到 B 对 review 也打断** | 高 |
| moderate_interrupt | LLM 回复 + 系统气泡模板；写事件；底部 sheet | 模板回复 + 同一气泡（通通）；回忆 B 无气泡但有 sheet | 弹 AlertDialog，文案硬编码「撒瑪利亞會熱線 2896 0000」；不开 sheet | 文案来源不同 | 高 |
| acute | 网关短路不调 LLM；显示 acuteAck 气泡；`shortCircuited=true`；会话 `endReason=crisis`；全屏危机页 | 同（通通 `:578-588`；回忆 B `:72-110`，但仍把全文存入 M3 session） | **只弹同一个 AlertDialog**：无危机页、无 acuteAck、无 `turns`、无 crisis 会话 | **签到 B acute 不开危机页** | 高 |

证据：`check_in_arm_b.dart:182-198, 283-306`；`llm_gateway.dart:120-132`；`distress_router.dart:62-78`。

### D5. `safety_events` 字段与告警

字段（`lib/core/safety/safety_event_writer.dart:58-72`）：`uid`、`source`（gateway_input / gateway_output / m3_turn / rule_turn）、`textHash`（整段输入 SHA-256）、`level`（旧四级，两个 moderate 都写 `moderate`）、`tier`（五级）、`category`、`lexiconVersion`、`matchedTerm`（**明文**）、`agentId`、`sessionId`（签到 B / 回忆 B 不传）、`createdAt`；服务器回写 `dedup_key`（`index.js:829`）。写入条件 `isEscalation`。

规则：仅本人 create，不可读改删（`rules:123-131`）。

`onSafetyEventCreated`（`index.js:798-935`）：分钟桶去重（`:822-856`）→ `level !== "acute"` 直接返回（`:858`）→ **总是**写 `pi_alerts`（`:874-888`）→ 测试账号不发邮件（`:890`）→ 缺任一 SMTP secret 则只 log（`:896-910`）→ nodemailer SMTP 587 发邮件给 `PI_EMAIL`，正文含 agentId / source / 事件路径，不含文本（`:912-933`）。

| 问题 | 结论 | 证据 | 置信度 |
|---|---|---|---|
| FCM 告警 | 未找到 | — | 高 |
| 已读确认 | **没有**：`safety_events` / `pi_alerts` 无 acknowledged 字段；仪表板读的是 `SharedContext.safetyFlags`（全仓库无写入者）且无确认按钮；`pi_alerts` 无任何读取方 | `shared_context_service.dart:282`；`researcher_dashboard_page.dart:449-466` | 高 |
| moderate 级 | 只留记录，不告警 | `index.js:858` | 高 |

### D6. 热线号码（原样列出）

| 号码 | 文中机构名 | 位置 |
|---|---|---|
| 2382 0000 | 生命熱線 / Suicide Prevention Services | `functions/prompts/crisis_resources.json:10-12` |
| 2896 0000 | 撒瑪利亞會 / The Samaritans Hong Kong（acute 模板用） | `crisis_resources.json:22-24, 29` |
| 2466 7350 | 醫院管理局精神健康專線 | `crisis_resources.json:34-36` |
| 999 | 急症室 | `crisis_resources.json:45-48`；`safety_copy.dart:108-111, 193` |
| 2896 0000 / 2382 0000 / 999 | 撒瑪利亞會 / 生命熱線 / 緊急情況 | `lib/features/education/data/education_library.dart:164-172, 181-189` |
| **2382 0000** | **撒瑪利亞防止自殺會熱線 / Samaritans of HK**（与 JSON 里 2382 0000 = 生命熱線不符） | `education_library.dart:418, 419, 533, 534` |
| 2896 0000 | 撒瑪利亞會熱線（硬编码在 B 组对话框） | `check_in_arm_b.dart:295-296` |
| 18111 | 情緒通（不在 JSON 里） | `lib/features/crisis/presentation/widgets/safety_footer_card.dart:41, 57-58` |
| 999 | — | `safety_footer_card.dart:90, 104-105`；`settings_page.dart:787-788`；`faq_page.dart:17, 44, 57, 86`；`privacy_policy_page.dart:42, 82` |

`crisis_resources.json:4` 的 `verifiedDate` 为空，危机页脚显示「資料核對日期：待核對」（`emergency_support_page.dart:124-125`）。`safety_copy.dart:103-104` 写的「号码永远不在代码里」约定，有 5 处没遵守。置信度高。

### D7. 安全测试

`test/distress_corpus_test.dart`（190 条语料，acute 召回 ≥0.95、moderate ≥0.80、none 精确率 ≥0.90）、`distress_detector_test.dart`（锁 19/48 拆分）、`distress_t1_sensitisation_test.dart`、`safety_copy_test.dart`（四条资源顺序、模板）、`safety_overlay_suppressor_test.dart`。`test/parity/` 只做 ArmGate golden 截图，**不测安全路由**。**未找到** `safety_events` 规则测试。置信度高。

---

## E. 会话与测量

### E1. 会话定义（`lib/core/session/chat_session_recorder.dart`）

| 项目 | 结论 | 证据 | 置信度 |
|---|---|---|---|
| `sessionId` | 有：`s_` + 微秒时间戳(36 进制) + hash 低 24 位 | `:607-611` | 高 |
| 开始 | **第一条用户消息**，不是打开页面 | `:349-384, 406-408` | 高 |
| 结束 | `user_left`（离开页面）；`timeout`（`PhaseAConfig.sessionIdleTimeoutMin` = 10 分钟）；`crisis`；`app_killed`（下次启动补记） | `:302-303, 388-402, 563-583`；`phase_a_config.dart:23` | 高 |
| 工具会话 | `ToolSessionScope`，进页开离页关，`kind: 'tool'` | `:614-700` | 高 |
| `sessions` 字段 | `participantId, sessionId, kind, agentId, toolId, moduleId, theme, startedAt, lastActivityAt, endedAt, endReason, userTurnCount, fallbackCount, briefPR{shown,completed,items}, sessionSummaryShown, sessionSummaryHasTEPointer, lexiconVersion` | `:369-386, 434-438, 497-507, 535-539` | 高 |
| `turns` 字段 | `participantId, sessionId, agentId, moduleId, theme, ts{userSent,replyShown}, input{modality,voiceDurationMs,charCount}, detector{tier,matchedTerm,category,lexiconVersion,shortCircuited,ackShown}, llm{status,error,model,latencyMs,systemPromptHash,promptVersion,temperature}, flags{F1..F5}, referral{offered,target}, te{offered,offerText}, tungtung{mode,articleId,searchInvoked}, feedback{thumb,reason}, createdAt` | `:139-185, 547-556` | 高 |
| `sessionId` 用在哪 | `turns`、`safety_events.sessionId`、`brief_pr.sessionRef`、`sessions.briefPR`；**不进 `proxyDeepSeek` 请求体**（`functions/` 下 0 命中）；`memoryEndSession` 只传 `agentId` | `llm_gateway.dart:144-155`；`memory_v1_service.dart:103-105`；`brief_pr_page.dart:117` | 高 |
| 另一套 sessionId | `AnalyticsService` 有 App 级前后台 sessionId，写在每条 `events` 顶层 | `analytics_service.dart:21, 45, 94, 126` | 高 |

### E2–E4. 量表

| 量表 | 触发时点 | 存储 | 字段 | 关联 | 证据 | 置信度 |
|---|---|---|---|---|---|---|
| Brief PR | 离开聊天页或 10 分钟 idle 时原地弹；条件 `endReason != crisis` 且 `userTurnCount ≥ 2`；挂在签到 A、回忆 A、自由对话、通通（两组）；**签到 B、回忆 B、行动 B 未挂载** | `users/{uid}/brief_pr` | `schemaVersion(2), agentId, agentDisplayName, sessionRef, understanding, validation, caring, insensitivity (1–7), isAnchorPrompt, status, promptedAt, respondedAt, arm` | 关联 agentId + sessionId | `brief_pr_gate.dart:27-61`；`brief_pr_response.dart:67-81`；`check_in_arm_a.dart:890`、`tung_tung_page.dart:786` 等；`check_in_arm_b.dart` grep 无 BriefPr | 高 |
| Weekly PR | 日历窗口周日 20:00 → 周二 23:59；首页横幅；PGIC 先，再 12 题；referent = 评价周 `sessions(kind=agent)` 最多会话的陪伴者，否则 `no_referent` 只问 PGIC | `users/{uid}/weekly_pr`；错过写 `missed_{weekIso}` | `weekIso, agentId, agentDisplayName, sessionCountThisWeek, items{u1..i3}, status, promptedAt, respondedAt, arm, referentAgentId, referentRule` | 关联陪伴者，不关联会话 | `weekly_pr_window.dart:26-65`；`weekly_pr_trigger.dart:146-187, 224-242`；`weekly_pr_response.dart:41-53` | 高 |
| ADA（`agent_diff`） | 入组第 14–16 天与 ≥28 天各一次，首页横幅 | `users/{uid}/agent_diff` | `wave, timepoint, usageFreq, personality, function, freeResponse, answeredAt` | 按陪伴者打分，不关联会话 | `pending_prompts_service.dart:108-121`；`agent_diff_response.dart:41-48` | 高 |
| PGIC | 周窗口内评价周无记录时先问；设置页也有入口 | `users/{uid}/pgic`（`pgic_response.dart:3` 注释写 `pgic_responses`，**与实际不符**） | `value(1–7), answeredAt, isoWeek, weekIso` | 无 | `pgic_page.dart:55-67` | 高 |
| DJG-ES | 第 14–16 天 | `users/{uid}/djg_es` | `timepoint, itemsVersion, answers, score, status, answeredAt` | 无 | `djg_es_page.dart:43-47` | 高 |
| daily_mood | 首页每日首次 + 签到 B | `users/{uid}/daily_mood` | `mood, date_iso, is_primary, source_surface, arm…` | 无 | `mood_recorder.dart:39-80` | 高 |
| check_in_responses | 仅签到 B | `users/{uid}/check_in_responses` | `arm, mood, talked, social_day, significant_event, note, date_iso` | 无 | `check_in_arm_b.dart:204-216` | 高 |
| ppr_responses、loneliness_probes | **仓库内无调用者**（未启用） | — | — | — | grep 0 命中 | 高 |

B 组影响（置信度中）：签到 B / 回忆 B 不写 `sessions`，所以 B 组 Weekly PR 的 referent 只可能是通通，否则 `no_referent`。

### E5. 日程

起算字段是 `profile.createdAt`（账号创建日 = 第 1 天），没有 `enrolledAt` / `consentAt` 字段（`lib/core/scheduling/enrolment_day.dart:9-14`；`pending_prompts_service.dart:100, 108`）。服务器 `week2Push` 用同一算法（`index.js:1580-1595`）。Weekly PR 用日历 ISO 周，不按研究周。置信度高。

---

## F. 入口与界面

### F1. 首页入口

| tab | 入口 | 点进哪里 | 组别差异 | 证据 | 置信度 |
|---|---|---|---|---|---|
| 睇今日 | GreetingHero 情绪五表情 | A 组首次打分后弹「想同小欣講多兩句？」→ `CheckInArmA`；B 组只提示「記低咗」 | **有** | `greeting_hero.dart:119-121, 159-165, 196-202` | 高 |
| 睇今日 | CheckInStatusChip / ContinueChatCard | `CheckInPage` / 三个陪伴者页 | 无 | `checkin_status_chip.dart:77-78`；`continue_chat_card.dart:124-138` | 高 |
| 睇今日 | PendingPromptsBanner | PGIC / WeeklyPr / DJG-ES / AgentDiff 页 | 无 | `pending_prompts_banner.dart:85-148` | 高 |
| 睇今日 | AgentTileRow 三位陪伴者 | 小欣→`CheckInPage`；阿珍/阿伯→`ReminiscenceLandingPage`；通通→`TungTungPage` | 两组都显示三张卡 | `agent_tile_row.dart:89-116` | 高 |
| 睇今日 | FactsRecapRow | 无跳转 | B 组额外数 `m2_check_in_submitted` 事件 | `facts_recap_row.dart:81-92` | 高 |
| 睇今日 | HomeToolShortcuts：行動 / 望一望 / 進度 | `ActionLoopLandingPage` / `ThoughtExercisePage` / `ProgressPage` | 无 | `home_tool_shortcuts.dart:25-41` | 高 |
| 睇今日 | ActivePlanBanner、Week1NudgeBanner、MissedCheckInBanner、SafetyFooterCard | 行动跟进 / 关闭 / — / 危机页 | 无 | `today_page.dart:105-127` | 高 |
| 搵人傾 | 复用 AgentTileRow | 同上 | 无 | `talk_page.dart:41` | 高 |
| 做啲嘢 | 望一望心入面 / 行动计划 / 文章 / 社交小行動 | `ThoughtExercisePage` / `ActionLoopLandingPage` / `EducationLibraryPage` / `SocialSuggestionsPage` | 无 | `me_page.dart:55-98` | 高 |

### F2. 三个陪伴者承载的模块

| 陪伴者 | 模块 / 页面 | 组别 | 证据 | 置信度 |
|---|---|---|---|---|
| 小欣 `siu_yan` | M2 签到（A 对话 / B 表单）；A 组签到中邀请做想法练习 M5；首页情绪 CTA（仅 A） | 两组 / 仅 A | `check_in_page.dart:16-19`；`check_in_arm_a.dart:724-733` | 高 |
| 阿珍/阿伯 `ah_jan_ah_bak` | M3 回忆（A/B 页）；人生回顧 `MyStoryPage`；自由反思对话（仅 A）；转介目标 | 两组 / 仅 A | `reminiscence_landing.dart:71-84`；`my_story_page.dart:63-67` | 高 |
| 通通 `tung_tung` | 闲聊（A LLM / B 规则，同一页面）；M8 文章问答按钮（仅 A）；「幫我查」网络搜索（两组都关） | 两组 / 仅 A | `tung_tung_page.dart:104, 163, 595`；`education_article_page.dart:162` | 高 |
| 无陪伴者 | M6 社交建议、M7 行动计划、望一望心入面（TE）、进度 | 两组 | `social_suggestions_page.dart:103`；`action_loop_arm_a_page.dart:193`；`thought_exercise_page.dart:30` | 高 |

通通的角色：好奇 / 闲聊 / 资讯陪伴者（`agent_registry.dart:225-239` role `curious_companion`）。规格 4.1 设想的「通通承载行动计划、社交建议」**现状不成立**，这两个模块现在没有陪伴者。置信度高。

### F3. 设置页（「自己」tab）

| 条目 | 行为 | 显示条件 | 证据 | 置信度 |
|---|---|---|---|---|
| 個人資料 | `PersonalizationPage` | 总是 | `settings_page.dart:93-106` | 高 |
| 緊急支援 | `EmergencySupportPage` | 总是 | `:109-117` | 高 |
| 人生回顧 | `MyStoryPage` | 总是 | `:120-128` | 高 |
| 記憶 区块 | — | `FeatureFlags.memoryV1 \|\| MemoryMode == phaseB` | `:133-134` | 高 |
| └ 俾佢哋記得我講過嘅嘢（开关） | 写 `memory_enabled` | 仅 MEMORY_V1 测试包（随机 A 组无开关） | `:140-164` | 高 |
| └ 我記得嘅嘢 | `RememberedPage`：看三个流、确认 pending 事实、删除；无新增/编辑 | 同区块 | `:165-176`；`remembered_page.dart:52-56, 163-171, 229-235` | 高 |
| 顯示設定 / 語言 / 通知（安靜時段、語音讀出、今日休息） | 本地设置 | 总是 | `:180-272` | 高 |
| 關於同支援 → 關於 / 常見問題 / 私隱 | — | 总是 | `:283-301` | 高 |
| 研究员入口 | **无**（注释「Research section deferred」） | — | `:303-305` | 高 |
| 測試員工具（isTester 开关、重置资料、預覽量表、日程模擬/測試推送、PGIC/AgentDiff） | — | `TesterGate.unlocked`（关于页版本行点 7 次 + PIN） | `:307-403`；`support_about_page.dart:122-127` | 高 |
| 對話保留設定 | `_TranscriptRetentionTile` 定义了但**从未挂载** | 从不显示 | `:891` | 高 |

「我的資料」页（规格 3.7）**不存在**；规格说的「现有设置页里单独的『我記得嘅嘢』入口」存在于 `:165-176`。

### F4. 所有按组别 / isV1 / cohort 分支的界面代码

基础：`Arm.of`（`arm_scope.dart:26-43`）；`MemoryModes.of`（`memory_mode.dart:27-40`：B→off；PHASE_B && A && randomise→phaseB；MEMORY_V1 && memoryEnabled→optIn）。`cohort` / `kPhaseB` 无代码分支。置信度全部高。

| 文件:行号 | 条件原文 | A 组 | B 组 |
|---|---|---|---|
| `context/.../check_in_page.dart:16-19` | `ArmGate(armA:…, armB:…)` | `CheckInArmA` | `CheckInArmB` |
| `today/.../today_page.dart:82` | `if (!Arm.isA(context)) return;` | 预热开场白 | 不预热 |
| `today/.../greeting_hero.dart:58, 77` | `arm: isArmA ? 'A' : 'B'` | 数据标签 | 数据标签 |
| `greeting_hero.dart:119` | `if (isArmA && mounted)` | 小欣 CTA / 心情变化对话框 | 只提示 |
| `today/.../daily_mood_prompt.dart:46, 66` | 同标签 | — | — |
| `today/.../facts_recap_row.dart:54, 81` | `if (!isArmA)` | 数 sessions | 加数签到事件 |
| `today/.../pending_prompts_banner.dart:103` | `Arm.of(context)?.code ?? 'A'` | 写 no-referent 记录 | 同（默认 A） |
| `curious_companion/.../tung_tung_page.dart:163, 172, 271, 770` | `_ruleBased = !Arm.isA` | LLM、同意提示、折叠 | 规则、无 LLM、不折叠 |
| `tung_tung_page.dart:780` | `memoryV1: …isV1` | v1 跳过 v0 折叠 | 不可达 |
| `education/.../education_article_page.dart:162` | `Arm.isA && !_askMode` | 「問通通呢篇」 | 无 |
| `social_suggestions/.../social_suggestions_page.dart:69, 124-131, 168-171` | `Arm.isA` | LLM 建议；→ ArmA 计划 | 池建议；→ ArmB 计划 |
| `action_loop/.../action_loop_landing.dart:107-109` | 三元 | ArmA 页 | ArmB 页 |
| `action_loop/.../action_loop_followup_page.dart:94` | `if (Arm.isA)` | LLM 回应 | 固定文案 |
| `progress/.../progress_page.dart:68, 92, 169` | `Arm.isA` | 周小结卡 | 无 |
| `reminiscence/.../reminiscence_landing.dart:71-76` | 三元 | ArmA 页 | ArmB 页 |
| `reminiscence/.../reminiscence_arm_a_page.dart:677` | `memoryV1` | v1 跳过折叠 | — |
| `reminiscence/.../m3_session_detail_page.dart:127` | `Arm.isA && !_editing` | 可改写小结 | 不可 |
| `my_story/.../my_story_page.dart:65` | `if (Arm.isA)` | 自由对话入口 | 隐藏 |
| `my_story/.../current_session_entry.dart:110-115` | 三元 | ArmA 页 | ArmB 页 |
| `reflective_dialogue/.../reflective_dialogue_page.dart:644` | `memoryV1` | v1 跳过折叠 | 不可达 |
| `reflective_dialogue_page.dart:257, 482` | `profile?.arm?.code` | 标签 | 标签 |
| `context/.../check_in_arm_a.dart:835` | `memoryV1` | 同上 | 不可达 |
| `settings/.../settings_page.dart:133-134, 140` | `memoryV1 \|\| mode==phaseB`；`mode != phaseB` | 記憶区块；随机 A 无开关 | 无区块 |
| `onboarding/.../agent_onboarding_page.dart:373-374` | `mode == phaseB` | 介绍页加记忆告知段 | 无 |
| `memory/.../remembered_page.dart:32` | `!isV1` | 列表 | 「記憶已經熄咗」 |
| `brief_pr_page.dart:106, 160`；`weekly_pr_page.dart:98`；`thumbs_feedback.dart:83` | `Arm.of(context)?.code ?? 'B'` | 标签 | 标签 |
| `lib/core/llm/llm_gateway.dart:197` | `isArmA: armCode == 'A'` | 写 `llm_turn_features` | 不写 |
| `lib/core/agents/persona_resolver.dart:86-90, 92, 113` | `memoryV1` | v1 不读 v0 摘要、不种子、不注入 | 不调用 |
| `lib/core/llm/agent_greeting_service.dart:103-104, 133` | `!isV1`；`profile.arm` | v0 才读摘要 | 不调用 |
| `lib/features/analytics/data/analytics_service.dart:50, 119, 129, 201` | `_arm` | 事件带 arm | 事件带 arm |
| `lib/features/auth/data/auth_service.dart:206` | `existing.arm == null` | 补分组 | 同 |
| `lib/core/scheduling/pending_prompts_service.dart:98` | `profile.arm` | 标签 | 标签 |
| `researcher_dashboard_page.dart:550-551` | `data['arm'] == 'A'/'B'` | 计数 | 计数 |
| `lib/core/feature_flags/hybrid_only_mount.dart:56-57` | `allowsAffordance(key, isArmA)` | **无调用处** | — |
| `TranscriptConsentPrompter.maybePrompt`（9 个 A 组 / LLM 页面） | 只在 A 页面调用 | 逐模块转录同意弹窗 | 不问 |

### F5. 注册流程

`LoginPage`（电邮、密码、稱呼、年齡、緊急聯絡人，以及「研究人員填寫」UCLA 基線總分 20–80，`login_page.dart:227-266`）→ `signUp` 写 profile 后调 `assignArm`（`auth_service.dart:130`）→ `ConsentPage`（按「繼續」写 `functionalData=true`、`transcriptRetention=true`，无记忆同意项，`consent_page.dart:122-130`）→ 6 部分 Intake（`intake_flow_page.dart:9-18`）→ `AgentOnboardingPage`（阿珍/阿伯性别必选，`:305`；三位陪伴者转录保留写死为 true，`:48-56`；仅 phaseB 模式显示记忆告知，`:372-386`）→ 主界面。App 内没有 UCLA 问卷。置信度高。

---

## G. 记忆：v0/v1 入口与 isV1 分支核对

| 项目 | 结论 | 证据 | 置信度 |
|---|---|---|---|
| v0 写入 | 4 个 A 组聊天页每轮 `appendTurn` → `agent_contexts/{agentId}.shortTermBuffer`；离页时 `compileAtSessionEnd` 折叠 | `agent_context_service.dart:155-160`；`rolling_summary_compiler.dart:54-151`；`check_in_arm_a.dart:826-836` 等 | 高 |
| v0 其他写入 | intake 种子；`memory/{moduleId}/entries`（仅签到 A，**无 isV1 门控**）；`recordEntities` / `writeThemeThread` 无调用者 | `persona_resolver.dart:92-106`；`check_in_arm_a.dart:766`；grep 无结果 | 高 |
| v1 客户端入口 | `MemoryV1Service.endSession(agentId)` 调 `memoryEndSession`；由 `compileAtSessionEnd` 在 `memoryV1==true` 时转调 | `memory_v1_service.dart:101-110`；`rolling_summary_compiler.dart:60-63` | 高 |
| 客户端 isV1 | `memory_mode.dart:27-40`；分支点见 F4 表；**客户端不看 `meta/memory_config`**（kill switch 只在服务器生效） | `memory_mode.dart:10-12` 注释 | 高 |
| 服务器 isV1 | `inScope = enabled && arm!=B && ((phaseBArmA && arm==A && randomise) \|\| memory_enabled)`；`meta/memory_config` 不存在 = 全关 | `memory.js:515-547` | 高 |
| v0 在 Phase B A 组是否停用 | **部分停用**：折叠、摘要注入、种子、问候已停；但仍写 `shortTermBuffer`（v1 输入）、仍写 `memory/m2_check_in/entries`、`crossModuleMemory` 仍读 v0 entries | `cross_module_memory.dart:100`；`check_in_arm_a.dart:476, 766` | 高 |
| B 组写不写缓冲区 | 不写：`appendTurn` 8 个调用点全在 A 组路径；服务器 `claimBuffer` 也被 `inScope` 挡 | `tung_tung_page.dart:271-273, 770`；`memory.js:540` | 高 |
| 决策 0013（安全标记不进记忆） | 客户端用户轮与陪伴者轮都用 `!response.hasEscalation` 门控；服务器 `SAFETY_TERMS` 丢弃命中的事实和跟进 | `check_in_arm_a.dart:539-542, 635-640`；`llm_gateway.dart:325-326`；`memory.js:281-286, 323-327` | 高 |
| 决策 0010（保留 3 年） | 代码里**没有** TTL / 定时删除；唯一实现是手动脚本 `tool/delete_memory.js`（默认 dry-run） | `tool/delete_memory.js:1-26, 64-100`；决策 0010 L28 | 高 |
| 文档不一致 | `memory-v1.md` L10「v0 保持不变」与代码及其 L59 冲突；`functions/memory.js:4-9` 头注释过时；`pgic_response.dart:3` 集合名注释错 | — | 高 |
| 开场白与记忆 | `greeting_*` 注入事实 / 摘要，但**不注入待跟进**（`sessionStart` 排除 greeting）；回忆 A 每周开场 `m3_reminiscence_wN_opener` 未传 agentId，**无记忆注入** | `memory.js:615-618`；`reminiscence_arm_a_page.dart:227-278` | 高 / 中 |

---

## H. 推送

### H1. FCM 时间表（`functions/index.js`，全部 Asia/Hong_Kong，**无按组别分支**）

| 函数 | cron | 发给谁 | 标题 · 正文 | data | 记录 | 证据 | 置信度 |
|---|---|---|---|---|---|---|---|
| `dailyMoodReminder` | `0 19 * * 1-6` | topic `all` 广播（含测试账号、今日休息用户、未分组用户） | 陪住 · 今日過得點？得閒入嚟同我哋講兩句，想講先講，唔講都冇所謂。 | `{kind: daily_mood_reminder}` | 无 | `:1445-1459, 1296-1311` | 高 |
| `weeklySurveyReminder` | `0 20 * * 0` | topic `all` 广播 | 陪住 · 今個禮拜過得點？得閒入嚟答幾條，想答先答，唔想都冇問題。 | `{kind: weekly_survey_reminder}` | 给非测试账号写 `events{weekly_pr_pushed}` | `:1461-1497` | 高 |
| `week2Push` | `0 10 * * *` | 按 `createdAt` 算入组第 14–16 天、非测试、未发过；逐 `fcm_tokens` 发 | 陪住 · 入嚟兩個禮拜喇，有幾條短問題想問下你。得閒先答，唔急。 | `{kind: w2_push}` | `users.w2PushSentAt`；`events{w2_push_sent}` | `:1526-1631` | 高 |
| `weeklyLonelinessProbe` | `0 9 * * SUN` | 只写队列，**不推送** | — | — | — | `:1056-1096` | 高 |

- 推送没有 deep link：App 端只记 `notification_received` / `notification_opened` 事件，点开回首页由 `PendingPromptsBanner` 按时间窗路由（`lib/core/fcm/fcm_service.dart:101-116`）。置信度高。
- 本地提醒：`lib/core/reminders/reminder_service.dart` 只写 `users/{uid}/reminders` 意向文档（行动计划后 24 小时，两组同文案），**没有接 `flutter_local_notifications`，也没有代码读取它触发通知**。置信度高。
- `sendTestPush`：测试账号对自己发三种正式文案，标题「陪住（測試）」（`:1650-1696`）。
- 周问卷推送时间写死在 cron，`app_config/phase_a.weeklyPrPushHour` 改了不影响推送。置信度高。

### H2. 开场白

| 页面 | A 组 | B 组 | 证据 | 置信度 |
|---|---|---|---|---|
| 首页问候 | 两组一样：按时段 l10n 文案 + 称呼，不是 LLM | 同 | `greeting_hero.dart:217-241` | 高 |
| 通通 | `TodayPage` 每天对阿珍/通通各预生成一次，存 `agent_greetings/{YYYY-MM-DD}_{agentId}`（本机日期），走 `proxyDeepSeek` `moduleId=greeting_<agentId>`，提示词含兴趣、avoidTopics、上次话题、周次；服务器注入事实/摘要但不注入待跟进 | 20 条题库按天轮换 | `agent_greeting_service.dart:96-134, 159-169`；`tung_tung_page.dart:172-183` | 高 |
| 签到 | 按当天心情分固定句，不走 LLM | 表单，无开场白 | `check_in_arm_a.dart:277-300` | 高 |
| 回忆 | 每周主题现场调 LLM（`m3_reminiscence_wN_opener`，10 秒超时回退固定句） | 4 周固定主题句 | `reminiscence_arm_a_page.dart:108-118, 227-278`；`reminiscence_themes.dart:27-66` | 高 |
| 自由对话 | 读同一 `agent_greetings` 缓存 | 无入口 | `reflective_dialogue_page.dart:137-148` | 高 |

### H3. 跨陪伴者转介

L1 关键词（`triggers_config.dart:42-137`）→ L2 `referralJudgement`（最近 10 轮原文 + 判定指令，temperature 0.3）→ L3 冷却（10 轮 / 24 小时）。只在小欣 A 和阿珍自由对话页触发，通通不作来源。记录写 `shared_context.pendingReferrals[]`（含完整原句 `triggerSnippet`）、`events{cross_referral_*}`、`turns.referral`。`drainOnArrival` 无调用点。置信度高。

---

## I. 版本与日志

### I1. 每条消息现在记录的版本信息

| 字段 | 位置 | 有无 | 证据 | 置信度 |
|---|---|---|---|---|
| `promptVersion`（如 `siu_yan_v1@2026-06`） | `turns.llm.promptVersion` | 有（raw prompt 调用为 null） | `index.js:59-71`；`chat_session_recorder.dart:168-176` | 高 |
| `model`（DeepSeek 响应原样） | `turns.llm.model` | 有 | 同上 | 高 |
| `systemPromptHash`（persona+suffix，不含记忆块） | `turns.llm.systemPromptHash` | 有 | `index.js:195-199, 309` | 高 |
| `lexiconVersion` | `turns.detector`、`sessions`、`safety_events` | 有 | `recorder:164, 392` | 高 |
| `temperature`、`latencyMs`、`status`、`error` | `turns.llm` | 有 | `recorder:168-176` | 高 |
| `flags._version` | 返回体内（值 2） | 有 | `llm_flags.js:285` | 高 |
| `appVersion`、`buildNumber` | `lib/core/version/build_info.g.dart`（1.0.0+3）；**不写进 turns** | 部分 | `build_info.g.dart:5-12` | 高 |
| `buildSha`、`memoryVersion`、`sensitivityLexiconVersion`、`usage`、`system_fingerprint` | — | **未找到** | — | 高 |
| 工件哈希 `kArtefactHashes` | 8 个文件（3 persona、suffix 模板、2 个 safety JSON、fallback JSON、词表 dart） | 有（编译期常量） | `build_info.g.dart:13-20` | 高 |

### I2. 测试与 CI

| 类别 | 内容 | 证据 | 置信度 |
|---|---|---|---|
| Flutter 单测 | `test/` 33 个文件：分组、Brief PR 量表、安全语料、记忆门控、版本 pin、日程模拟、通通规则池、契约测试等；`test/parity/` 只有 ArmGate golden | `tool/ci_flutter_tests.sh:30-37` | 高 |
| 四套构建变体 | ① 默认全量；② `PHASE_B=true` 跑 arm_gate / parity / memory_v1_client；③ `PHASE_B=true FORCE_ARM=B` 跑 tung_tung_arm_b / my_story_arm；④ `MEMORY_V1=true` 跑 memory_v1_client | 同上 | 高 |
| 规则测试 | `test/rules/` 3 个 mocha：`profile_arm`、`arm_counter`、`memory_rules`（需模拟器） | `test/rules/package.json:7` | 高 |
| Functions 测试 | `functions/test/` 5 个：arm 纯逻辑、arm 模拟器、llm_flags golden、memory 纯逻辑、memory 模拟器（DeepSeek 用桩） | `tool/ci_backend_tests.sh:11-33` | 高 |
| CI | `.github/workflows/ci.yml`（push / PR：analyze + 四套 Flutter 测试 + 后端测试）；`build-apk.yml`（手动，variant phase_a / phase_b / memory_v1）；`deploy-firebase.yml`（手动 + production 环境审批 + 手输项目 id） | `ci.yml:10-60`；`build-apk.yml:17-70`；`deploy-firebase.yml:14-70` | 高 |
| Codemagic | 只投 TestFlight；`flutter analyze \|\| true`、`flutter test \|\| true`（失败不阻断） | `codemagic.yaml:21-66` | 高 |
| 覆盖缺口 | 无 `proxyDeepSeek` B 组拒绝测试；无 `safety_events` 规则测试；parity 不测安全路由；`llm_flags` 不测稳定性 | — | 高 |

---

## J. 研究员 dashboard 现有功能

`lib/features/researcher_dashboard/presentation/pages/researcher_dashboard_page.dart`（767 行，唯一文件）。

| 区块 | 读哪里 | 能做什么 | 行号 | 置信度 |
|---|---|---|---|---|
| 未處理嘅 distress flags | `collectionGroup('shared_context')` 的 `safetyFlags`（**全仓库无写入者**） | 只看，无确认按钮 | `:131, 449-466` | 高 |
| 參與度 | `collection('users')` 计 A/B 人数 | 只看 | `:134, 541-559` | 高 |
| 對話審計隊列 | `collectionGroup('agent_contexts')` 计数 | 只看 | `:137, 577-596` | 高 |
| 想法練習審計 | `te_audit_queue` pending | 6 项表单 → `status='reviewed'` | `:144, 171-176, 259-270` | 高 |
| 跨 agent 轉介 / PPR 分布 | `shared_context` / `ppr_responses` | 只看 | `:147-150, 610, 646` | 高 |
| safety_events、pi_alerts 确认、导出、看记忆、`mem_forget_requests` | **未找到** | — | — | 高 |

| 项 | 结论 | 证据 | 置信度 |
|---|---|---|---|
| 入口 | **无**：lib 内没有任何地方导航到该页 | grep 0 命中；`settings_page.dart:303-305` | 高 |
| 权限 | 只认 custom claim `role == 'researcher'`（`'pi'` 不被接受） | `:39-48, 80-96` | 高 |
| 规则 | `firestore.rules` 无 role 判断；`te_audit_queue` 全拒、`users` 仅 owner → 客户端读取会被拒 | `rules:63-79, 149-151` | 高 |
| 脚本 | `tool/provision_researcher.js` 设 claim（`--confirm` 解析了但未使用）；`tool/admin_dump.js` 只读导出单用户 12 个子集合 + `safety_events`，**不含 `mem_*`** | `provision_researcher.js:46, 90-95`；`admin_dump.js:41-97` | 高 |

---

## K. 风险清单

### 表 1：除回应生成外，两组的所有差异点

| # | 差异 | 类别 | 与「只有回应后端不同」 | 证据 | 置信度 |
|---|---|---|---|---|---|
| 1 | B 组无阿珍/阿伯自由对话入口 | 功能 | 冲突（整个模块缺席） | `my_story_page.dart:63-68` | 高 |
| 2 | **Brief PR 不在签到 B / 回忆 B / 行动 B 弹出** | 测量 | 冲突 | `brief_pr_gate.dart`；三份 arm_b 文件 grep 无 BriefPr | 高 |
| 3 | 签到 B / 回忆 B 不写 `sessions` / `turns`（无 `ChatSessionRecorder`） | 测量 | 冲突（使用量口径、Weekly PR referent 不同） | 同上 grep | 高 |
| 4 | **签到 B 的 acute / moderate_review 处理与 A 组不同** | 安全 | 冲突 | `check_in_arm_b.dart:182-198, 283-306` | 高 |
| 5 | 行动计划 B 自由文本无安全检测 | 安全 | 冲突 | `action_loop_arm_b_page.dart`（无 analyze） | 高 |
| 6 | 逐模块转录同意弹窗只问 A 组 | 同意流程 | 冲突 | `TranscriptConsentPrompter` 9 个调用文件全是 A 页 | 高 |
| 7 | onboarding 记忆告知段只给 Phase B A 组 | 同意流程 | 冲突（但符合决策 0001） | `agent_onboarding_page.dart:372-387` | 高 |
| 8 | 设置页「記憶」区块 / 「我記得嘅嘢」只 A 组 | 界面 | 冲突（设定页项目不同） | `settings_page.dart:133-134` | 高 |
| 9 | 首页心情打分后 A 组弹「同小欣傾」CTA | 引导 | 冲突 | `greeting_hero.dart:119-129` | 高 |
| 10 | 文章页「問通通呢篇」按钮只 A | 界面 | 冲突 | `education_article_page.dart:162` | 高 |
| 11 | 进度页周小结卡只 A | 界面 | 冲突（注释称已认可） | `progress_page.dart:92-94, 165-169` | 高 |
| 12 | 回忆小结「再编辑」只 A | 界面 | 冲突（小） | `m3_session_detail_page.dart:127` | 高 |
| 13 | 跨陪伴者转介只 A | 功能 | 冲突 | `check_in_arm_a.dart:685-686`；`index.js:452` | 高 |
| 14 | 个性化开场白 `agent_greetings` 只 A；签到 B / 回忆 B 无开场白 | 内容 | 可接受（生成差异） | `today_page.dart:82` | 高 |
| 15 | 记忆 v1 只 A（服务器 + 客户端） | 记忆 | 符合决策 0001 | `memory.js:540`；`memory_mode.dart:28-30` | 高 |
| 16 | `llm_turn_features` 只 A 写 | 测量 | 可接受 | `llm_turn_features.dart:116` | 高 |
| 17 | B 组「对话数」额外统计签到事件 | 显示 | 可接受（补齐口径） | `facts_recap_row.dart:81-92` | 高 |
| 18 | 推送、安全词表、问卷时间表 | — | 一致 | `index.js:1445-1648`；`lib/core/safety/` | 高 |

### 表 2：客户端可写的研究关键字段

| 字段 / 对象 | 客户端权限 | 证据 | 置信度 |
|---|---|---|---|
| `users/{uid}.arm` | 当前为 null 时可自设 A/B | `firestore.rules:70-71` | 高 |
| `users/{uid}.strataCell` | 可随意写改 | `rules:57-61`（不在保护列表） | 高 |
| `users/{uid}.baselineUclaScore`、`ageGroup` | 可随意写改（分层输入） | `user_profile.dart:363, 398` | 高 |
| `users/{uid}.memory_enabled`、`isTester`、`consent`、`weeklyProbeEnabled`、`quietTodayActivatedAt` | 可随意写改 | `user_profile.dart:374-397` | 高 |
| 整个 `users/{uid}` 文档 | owner 可删除 | `rules:64` | 高 |
| `meta/arm_counter` | 任何登录用户可 +1（可扭曲平衡） | `rules:203-211` | 高 |
| `users/{uid}/sessions`、`turns`、`events`、`brief_pr`、`weekly_pr`、`pgic`、`djg_es`、`daily_mood`、`agent_contexts`、`action_plans`、`thought_exercise`、`llm_turn_features`、`response_feedback` 等 | owner 可创建、修改、**删除** | `rules:77-79` | 高 |
| `safety_events` | 可创建任意 level（含 `none`）；不可改删 | `rules:123-131` | 高 |
| `proxyDeepSeek` 的 `systemPrompt` | 客户端可传任意原文 system prompt（无 `promptKey` 时服务器原样使用） | `index.js:100-103` | 高 |

### 表 3：所有外部数据流

| 服务 | 从哪发 | 发送了什么 | 位置 | 经 stripPII | 置信度 |
|---|---|---|---|---|---|
| DeepSeek `api.deepseek.com`：对话 | 服务器 `proxyDeepSeek` | persona + contextSuffix（v0 摘要、命名实体、情绪、兴趣）+ v1 记忆块 + **客户端全部 history 原文** + 本轮输入；uid 盐化哈希 | `index.js:273-361`；`llm_gateway.dart:407-417` | messages / suffix / 记忆块是；raw `systemPrompt` 否；姓名不脱 | 高 |
| DeepSeek：开场白 `greeting_*` | 同上 | 兴趣、avoidTopics、周次、上次话题（在 raw systemPrompt 内） | `agent_greeting_service.dart:123-134, 218-224` | systemPrompt 否 | 高 |
| DeepSeek：v0 折叠 `rolling_summary_fold` | 同上 | 旧摘要 + 整段会话原文 | `rolling_summary_compiler.dart:100-125` | 是 | 高 |
| DeepSeek：文章问答 m8 / 行动跟进 m7 / 周小结 m9 | 同上 | 文章正文 + 问答；用户输入；计数均值 | `education_article_page.dart:96-105`；`action_loop_followup_page.dart:94-101`；`progress_page.dart:104-118` | 是 | 高 |
| DeepSeek：`referralJudgement` | 服务器 | 源陪伴者 persona + 最近 ≤10 轮原文 + 命中片段 | `index.js:440-566` | 是 | 高 |
| DeepSeek：记忆抽取 | 服务器 `memoryEndSession` / `memorySweep` | 已有事实 + 整段缓冲区原文 | `index.js:1326-1351`；`memory.js:194-237` | 是 | 高 |
| Brave Search `api.search.brave.com` | 服务器 `webSearch` | 用户整条输入原文作 `q` | `index.js:620-621` | **否** | 高 |
| 同上：是否生效 | 客户端 `_searchEnabled = false` 全局关闭，函数仍部署 | `tung_tung_page.dart:104` | — | 高 |
| Google Speech-to-Text v2 | 服务器 `transcribeAudio` | base64 音频内联，不存 GCS；写 `stt_usage` | `index.js:648-796` | — | 高 |
| 同上：客户端调用方 | **未找到**；实际语音输入用 `speech_to_text` 包交给 OS 识别器（`_onDeviceOnly = false`） | `lib/core/voice/voice_input_button.dart:398-404` | — | 中 |
| Whisper / OpenAI | 代码中**没有**；`docs/VOICE_WHISPER_TESTING.md` 已过时 | grep 无 | — | 高 |
| Firebase Auth / Firestore / FCM | 客户端 + 服务器 | 邮箱密码登录；所有研究数据；推送 token | `auth_service.dart:53, 100`；`fcm_service.dart:156-166` | — | 高 |
| Firebase App Check | 客户端激活；**服务器全部 8 个 callable `enforceAppCheck: false`** | `lib/main.dart:44-52`；`index.js:277, 421, 444, 591, 678, 1357, 1550, 1651` | — | 高 |
| SMTP（nodemailer，端口 587） | 服务器 `onSafetyEventCreated` | acute 事件：agentId、source、事件路径（无 uid、无原文） | `index.js:912-933` | — | 高 |
| Cloud Storage 盲法导出 | 服务器 `blindedDataExport` | 16 个集合 NDJSON 到默认 bucket `exports/{date}/`；白名单外字段原样导出（`turns`、`thought_exercise` 自由文本未脱敏）；无 `storage.rules` 文件 | `index.js:1130-1273` | 行级删 email / displayName / 紧急联络人；uid 盐化 | 高 |
| Crashlytics / Analytics / Sentry / 短信 / Slack / Webhook | **未找到** | — | — | 高 |
| `url_launcher` | 客户端 | 仅 `tel:` 拨号 | `emergency_support_page.dart:147-149` | — | 高 |

### 表 4：硬编码的密钥或敏感信息（只写位置）

| 类型 | 位置 | 说明 | 置信度 |
|---|---|---|---|
| Firebase 客户端 apiKey / appId / projectId / storageBucket | `lib/firebase_options.dart:50-72` | 公开客户端配置，明文入库 | 高 |
| `google-services.json`（含 api_key） | `android/app/google-services.json:16-18` | 已入库，`.gitignore` 未覆盖 | 高 |
| `GoogleService-Info.plist`（API_KEY、GCM_SENDER_ID） | `ios/Runner/GoogleService-Info.plist:5-8` | 已入库 | 高 |
| 服务器 secret 名（值不在仓库） | `functions/index.js:15-19, 568` | `DEEPSEEK_API_KEY`、`SMTP_*`、`PI_EMAIL`、`SEARCH_API_KEY` | 高 |
| `TESTER_PIN` 示例值 | `lib/core/testing/tester_gate.dart:8`（注释） | 无默认值；CI 从 secret 注入 | 高 |
| App Check web key 占位 | `lib/main.dart:52` | 占位字符串 | 高 |
| 联络邮箱 | `privacy_policy_page.dart:138`；`tool/*.js` 注释示例 | 非密钥 | 高 |
| service account 路径 | `tool/admin_dump.js:13` 等只要求 `GOOGLE_APPLICATION_CREDENTIALS`，无硬编码 | — | 高 |
| git 历史 | 只有上述两个 Firebase 配置文件；无 serviceAccount / .env / .pem / .jks | `git log --all --diff-filter=A` | 高 |
| `sk-` / PEM 模式 | 未找到 | — | 高 |

---

## L. 对 `memory-and-entry-spec.md` 与研究文档「待确认」项的逐条回答

| 待确认（出处） | 回答 | 证据 | 置信度 |
|---|---|---|---|
| `assignArm` 与 HTML 随机化工具的关系（规格 §1、§7；研究 §8） | 仓库里没有 HTML 工具，也没有引用。`assignArm` 自己按 UCLA×年龄四格最小化分组，不是 DJG-ES。代码无法回答以哪个为准；若以 HTML 工具为准，`assignArm` 的分层与计数逻辑要整个换掉。 | B7 | 高 |
| Brief PR 现在的弹出时点（规格 3.8、§7；研究 §8） | 离开聊天页或 10 分钟 idle 时，本会话用户发言 ≥2 轮且非 crisis。会话从第一条用户消息开始。**签到 B / 回忆 B 不弹**，只有 A 组页面和通通弹。规格 3.8「打开聊天页时生成 sessionId、30 分钟无消息结束」与现状（第一条消息、10 分钟）都不一致。 | E1、E2 | 高 |
| 现在的首页入口与通通的角色（规格 4.1、§7） | 4 个 tab；首页有情绪、继续聊天、三张陪伴者卡、三个工具快捷键等 10 余个入口，超过规格「不超过 4 个」。通通只承载闲聊与文章问答，**不承载**行动计划和社交建议（这两个是无陪伴者的工具）。 | F1、F2 | 高 |
| phase_a 用 v1 还是 v0（规格 §2、§7；研究 §8） | 现状：`armAssignmentMode == force_a` 的用户走 v0（服务器 `inScope` 只对 randomise 的 A 组强制 v1）。要让 phase_a 用 v1，必须先加 cohort 字段并改 `inScope`。代码无法替负责人决定。 | `memory.js:538-547` | 高 |
| 注册 / protocol / ICF 原文（研究 §8） | 仓库内没有这些文件。**未找到**。 | — | 高 |
| E4 微随机是否采用（研究 §8） | 代码里没有 `mrtFollowupEnabled`、`mem_mrt`。未实现，待负责人决定。 | A6 | 高 |
| 规格 8.2-1 DeepSeek 模型版本 | `model` 字段只会是 `deepseek-chat`；代码**不记录** `system_fingerprint`、`usage`。 | C2 | 高 |
| 规格 8.2-5「我的資料」在规则组几乎是空的 | 现状没有「我的資料」页；「对话保留设定」UI 从未挂载；保留开关写死为 true。 | F3 | 高 |
| 规格 8.4 `meta/arm_counter` 客户端可读 | 现状不止可读，还可写 +1。 | B5 | 高 |
| 规格 8.4 `buildSha` 注入 | 未实现；CI 和 Codemagic 都没有传 `BUILD_SHA`。 | A5、I1 | 高 |
| 规格 3.10 prompt 注册表 | persona 在 `functions/prompts/<name>_v1.txt`；抽取 prompt 在 `memory.js` 代码里；v0 折叠 prompt 在 `rolling_summary_compiler.dart` 代码里；文件命名未迁移。 | C6 | 高 |

---

## M. 对 architecture-v2.md 的修正建议

`docs/dev/architecture-v2.md` 不存在，以下针对现有 `docs/dev/architecture.md`（技术文档）和 `docs/dev/memory-and-entry-spec.md`（规格，含 8.4 的工作量估计）。

### M1. 不成立或不准确的假设

| 文档说法 | 实际 | 证据 |
|---|---|---|
| architecture.md §1「两组界面一样，差别只在回应是谁生成的」 | K 表 1 列了 13 处与此冲突的差异，其中安全处理（签到 B）和测量（Brief PR、sessions）两处最重要 | K 表 1 |
| architecture.md §4「`proxyDeepSeek`… 每次先查分组，B 组直接拒绝。即使 App 哪里判断错了，B 组也拿不到 LLM」 | 成立，但 `arm` 为 null 时放行，分组失败期间的用户在 Phase B 包里显示 B 组界面却能调 LLM（如果某处 UI 判断错）；`transcribeAudio` 无检查 | `index.js:255-260, 675-690` |
| architecture.md §4「客户端不能写 `armAssignmentMode` / `armAssignedBy` / `armAssignedAt`」 | 成立，但 `strataCell`、`baselineUclaScore`、`ageGroup` 可写，`arm` 为 null 时可自设 | `rules:57-71` |
| architecture.md §5「调 DeepSeek，计算 5 个 LLM 独有机制标记」—— 读者可能理解为 LLM 标注 | 是纯正则，不调用模型 | `llm_flags.js` |
| architecture.md §5「服务器 `onSafetyEventCreated` 通知 PI」 | 只对 acute 通知，且只通过 SMTP 邮件，需要 4 个 secret 都配好；无已读确认；`pi_alerts` 无人读 | `index.js:858-910` |
| architecture.md §9「`safetyAcknowledgement`：按陪伴者返回安全回应模板」 | 函数存在但客户端不调用，模板由客户端从 JSON 资产读 | C2、D4 |
| architecture.md §9「`webSearch`：通通的网络搜索（只 A 组）」 | 客户端常量已全局关闭，两组都没有 | `tung_tung_page.dart:104` |
| architecture.md §9「`transcribeAudio`：语音转文字（两组）」 | 客户端没有调用方；实际语音输入走 OS 识别器 | K 表 3 |
| architecture.md §10「记忆 v1 在服务器上再查一次自杀、自残等词」 | 只有 17 条词，只用于记忆过滤，不是安全路由 | `memory.js:71-75` |
| architecture.md §8「`agent_greetings`… App 写」「`memory/{moduleId}/entries`… 各模块」 | `memory/*/entries` 实际只有签到 A 写 | `check_in_arm_a.dart:766` |
| memory-v1.md「A 组现有的滚动摘要（v0）保持不变」 | v1 用户已停折叠、停注入、停种子，只剩缓冲区写入 | G |
| 规格 §0 原则 1、§3.8「打开聊天页时生成 sessionId… 30 分钟无消息结束」 | 现状是第一条消息开始、10 分钟结束；`sessionId` 不进 `proxyDeepSeek` 和 `memoryEndSession` | E1 |
| 规格 §3.5「prompt 顺序：persona → 记忆块 → 对话历史 → 待跟进」 | 现状 persona → contextSuffix → 记忆块（含待跟进）全在 system 消息里，每轮重新读 3 个集合 | C2 |
| 规格 §4.1「通通：行动计划、社交建议」 | 这两个模块现在没有陪伴者 | F2 |
| 规格 §6「运行 `tool/export_config.js`」 | 文件不存在 | A6 |
| `docs/research/arm_assignment_scheme_v1.md` §2 客户端 `ArmAssigner(forceArmA)` | 已改为服务器 `app_config/arm_assignment.randomise` | B7 |

### M2. 工作量估计（规格 8.4：P0 十项 + cohort 约 8–12 天）应该怎么调

规格 8.4 的估计只覆盖了记忆与入口。本次审计发现的问题里，有几项在冻结前必须做且不在那 8–12 天里。建议分三档重排：

| 档 | 事项 | 为什么必须 | 估计（开发日） |
|---|---|---|---|
| **冻结前必须（新增）** | 签到 B 的 acute / moderate_review 路由改成和 A 组一致（走 `DistressRouter`、写 `turns`、打开危机页）；行动计划 B 加安全检测 | 两组安全处理必须一致；现在 B 组签到 acute 不开危机页 | 1 |
| 冻结前必须（新增） | 规则收紧：`strataCell` / `baselineUclaScore` / `ageGroup` 禁止客户端改；`arm` 为 null 时禁止客户端自设；`meta/arm_counter` 客户端不可写不可读；`sessions` / `turns` / `brief_pr` / `weekly_pr` / `safety_events` 相关子集合禁止客户端 update / delete；`proxyDeepSeek` 拒绝无 `promptKey` 的 raw `systemPrompt`（或只允许白名单 moduleId） | 研究关键数据可被篡改或删除 | 1–2 |
| 冻结前必须（新增） | 研究员告警可用：要么把 `pi_alerts` 接到仪表板并加确认字段，要么确认 SMTP 四个 secret 已配置并实测收到邮件；仪表板要么加入口 + 规则里加 role 判断，要么明确声明不用 | 现在 acute 告警只靠邮件，无人能确认 | 1–2 |
| 冻结前必须（新增） | 热线号码统一走 `crisis_resources.json`；修正 `education_library.dart:418/419/533/534` 的机构名；填 `verifiedDate` | 对参与者的安全信息错误 | 0.5 |
| 冻结前必须（新增） | `proxyDeepSeek` 和 `callDeepSeekJson` 加 fetch 超时（AbortController）与一次重试 | 现在只靠 55 秒函数超时 | 0.5 |
| 冻结前必须（规格已有） | cohort 字段 + 删 `PHASE_B` 开关（§1）；版本追溯字段 `buildSha` / `memoryVersion` / `lexiconVersions`（§3.6）；统一 sessionId（§3.8）；Brief PR 在签到 B / 回忆 B 挂载或在分析里只用两组都有的页面（8.2-2）；签到 B / 回忆 B 写 `sessions` | 规格原有 | 规格原估 |
| 可以推迟到研究后 | §3.4 分层摘要、§3.5 每会话组装一次、§3.9 回调匹配、§3.3 口头删除 | 不影响安全和数据完整性 | — |
| 不需要开发的 | §3.1 测试集金标准标注、§3.2 词表审核 | 人工 | — |

综合：规格原估 8–12 天里，建议把 §3.4 / §3.5 / §3.9 / §3.3（约 4–5 天）往后推，把上面 5 项新增（约 4–6 天）排进来。总量仍在 8–12 天，但内容换了。如果 10 月中旬开始 Phase B，优先顺序建议：安全一致（签到 B）→ 规则收紧 → 告警可用 → cohort 与版本字段 → sessionId 与 Brief PR 口径 → 热线与超时。

### M3. 其他建议改掉的文档陈述

- `docs/dev/ci-cd.md:28` 说 Codemagic「上架商店」，实际只投 TestFlight 且测试失败不阻断。
- `docs/VOICE_WHISPER_TESTING.md` 整份已过时（Whisper 代码不在仓库）。
- `docs/STUDY_CHANGELOG.md` 没有任何推送、开场白、热线相关条目，而这些都是参与者能感受到的。
- `functions/memory.js:4-9` 头注释、`pgic_response.dart:3` 注释与代码不符。
- 死代码可以在文档里标明或删除：`HybridOnlyMount`、`_TranscriptRetentionTile`、`_TungTungComingSoon`、`ToolQuickLinks`、`QuietTodayBanner`、`OnboardingPage`（滑页版）、`drainOnArrival`、`recordEntities` / `writeThemeThread`、`regenerate` 标志、`education_article_page.dart:68` 永远为 false 的 `_askMode`。
