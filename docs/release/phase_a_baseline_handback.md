# 陪住 · Phase A 基线版 — 开发回传（Round 2 审计输入）

对应规格：《Phase A 基线版 — 开发变更规格 v1》（2026-09-11，基线 `c80a2ab`）。
本文按规格 §7「开发回传清单」逐项回答；能在仓库里核实的都给出文件路径。

状态：全部 P0/P1 条目已实现；🔴 三项按规格默认实现，改配置即可切换。**验收测试 T-1～T-18 需要在真机测试 build 上跑（需要 DeepSeek key、Firebase 项目、推送）；本仓库环境无法执行，本文只给出每条的代码路径与预期，截图与 Firestore 文档由测试轮补。**

---

## 1. 实际 Firestore schema

全部在 `users/{uid}/…` 之下（沿用 owner-only 规则，`firestore.rules` 未新增子集合规则；新增 `app_config/{doc}` 只读规则）。

### `users/{uid}/turns/{turnId}` — 每条用户消息 + 对应回复一条

写入点：`lib/core/session/chat_session_recorder.dart` → `TurnRecord.toMap()`；四个 agent 聊天页各自组装 `TurnRecord`。

| 字段 | 类型 | 来源 |
|---|---|---|
| `participantId` `sessionId` `agentId` `moduleId` | string | 页面 |
| `theme` | string / null | 只有 Ah Jan 回忆页非空（`ReminiscenceTheme.titleZh`） |
| `ts.userSent` `ts.replyShown` | Timestamp | 发送前 / setState 显示回复时 |
| `input.modality` | `text`/`voice` | `VoiceInputController.takeModality()`：本条消息期间是否启动过听写 |
| `input.voiceDurationMs` | int / null | 听写累计时长（listen start→stop），文字输入为 null |
| `input.charCount` | int | `text.length`（stripPII 前，客户端原文） |
| `detector.tier` | `none`/`low`/`moderate_review`/`moderate_interrupt`/`acute` | `DistressLevel.tierCode`；取输入与输出旗中较高者 |
| `detector.matchedTerm` `detector.category` | string / null | 首个命中词及其类别（见 §5） |
| `detector.lexiconVersion` | string | `v5-2026-09` |
| `detector.shortCircuited` `detector.ackShown` | bool | acute 时 true/true；interrupt 时 false/true；review 时 false/false |
| `llm.status` | `ok`/`fallback`/`short_circuited` | `LlmResponse.status` |
| `llm.error` | string / null | `timeout` / `cf_<code>`（deadline-exceeded、internal…）/ `network` / `empty_response` / `bad_shape` |
| `llm.model` | string / null | CF 原样回传 DeepSeek 响应体 `model` |
| `llm.latencyMs` | int | 客户端网关 stopwatch |
| `llm.systemPromptHash` `llm.promptVersion` `llm.temperature` | | CF 回传；`promptVersion` 由 prompt 文件首行解析，如 `siu_yan_v1@2026-06`、`ah_jan_ah_bak_v1@2026-09` |
| `flags.F1`…`F5` | bool / null | 见 §5；fallback / short_circuited 全 null |
| `referral.offered` `referral.target` | bool / string | 见 §5 |
| `te.offered` `te.offerText` | bool / string | 见 §5 |
| `tungtung.mode` `tungtung.articleId` `tungtung.searchInvoked` | | 通通页：A = 文章 Q&A，B = 闲聊；`articleId` 来自教育页 |
| `feedback.thumb` `feedback.reason` `feedback.at` | | 点评组件事后 merge 写入（M-6） |
| `createdAt` | serverTimestamp | |

### `users/{uid}/sessions/{sessionId}`

| 字段 | 说明 |
|---|---|
| `participantId` `sessionId` `kind` (`agent`/`tool`) `agentId` / `toolId` `moduleId` `theme` | |
| `startedAt` `lastActivityAt` `endedAt` `endReason` | `user_left` / `timeout` / `crisis` / `app_killed`（app 启动时 `sweepUnclosed` 补写） |
| `userTurnCount` `fallbackCount` | fallback 轮不计入 `userTurnCount` |
| `briefPR.shown` `briefPR.completed` `briefPR.items` | `BriefPrPage` 写；跳过 → `completed=false` |
| `sessionSummaryShown` `sessionSummaryHasTEPointer` | Ah Jan 回忆页收尾小结；后者为字符串匹配「望一望心入面」 |
| `lexiconVersion` | |

工具 session（`kind: tool`，`toolId ∈ action_loop / thought_exercise / education / progress`）由 `ToolSessionScope` 在页面进入/离开时写。

### `users/{uid}/events/{auto}`

沿用现有 `AnalyticsService` 文档结构：`name` ≡ 规格的 `type`，`params` ≡ `payload`，另有 `sessionId`（app 级）、`locale`、`arm`、`timestamp`。规格枚举全部在 `PhaseAEvents`（`chat_session_recorder.dart`）：
`te_offer` `te_accept` `te_decline` `te_module_open` `te_module_complete` `crisis_page_shown(from)` `crisis_call_tapped(resource)` `moderate_sheet_shown` `moderate_sheet_opened_resources` `referral_offered(target)` `weekly_pr_pushed`（由 CF 推送侧承担，客户端记 `notification_received/opened`）`weekly_pr_completed` `weekly_pr_missed` `mood_checkin` `w2_push_sent`（CF 写）`w2_completed` `notification_received` `notification_opened` `screen_view`（沿用既有 `screen_entered/exited` + `dwell`）`app_foreground` `app_background` `llm_fallback` `week1_nudge_shown` `app_start`。
`agent_switch(from,to)` 沿用既有 `cross_referral_accepted{fromAgent,toAgent}`。

`app_start` payload：`appVersion` `buildNumber` `lexiconVersion` `promptBundleHash` `platform`（L-2）。

---

## 2. T-1～T-18：代码路径与预期（截图待测试轮）

| # | 代码路径 | 预期（已按规格实现） |
|---|---|---|
| T-1 | 网关 short-circuit → `SafetyCopy.acuteAck('siu_yan')` 系统气泡 → `EmergencySupportPage(from: acute_route)` | 四项资源；`llm.status=short_circuited`；无 LLM 文本；session `endReason=crisis` |
| T-2 | 同上 | `matchedTerm=燒炭`，category `ideation` |
| T-3 | 同上 | `category=ideation`（可从日志识别第三人称） |
| T-4 | `DistressRouter.route` 对 `moderateReview` 直接 return | 有 LLM 回复、无提示、无模板；`tier=moderate_review`，term `過咗身`，category `loss_grief` |
| T-5 | 同上 + prompt rev 2026-09 第 9 条 | `tier=moderate_review`，term `好辛苦`，category `hardship` |
| T-6 | 页面在回复后追加 `SafetyCopy.moderateAck` + `route()` 弹底部提示 | `matchedTerm=冇人理我`（单元测试锁定） |
| T-7 | 同上 | `matchedTerm=想死`，`moderate_interrupt` |
| T-8 | low → pill 状态（pill 当前全局隐藏，状态仍更新） | 转介由 prompt 规则产生，`referral.offered` 由回复文本正则得出 |
| T-9 | 通通 moderate 模板 = `呢度有支援資源，要唔要睇下？` | 单元测试锁定 |
| T-10 | 检查顺序 interrupt 在 review 前（单元测试锁定） | `moderate_interrupt` |
| T-11 | `DeepseekLlmClient` 捕获异常 → `LlmRawResponse(error)` → 页面显示 `SafetyCopy.llmFallback` | `llm.status=fallback`；interrupt 词条模板照显示（检测在客户端，与 LLM 无关，已核实代码路径：`escalation.interrupts` 不依赖 response 文本） |
| T-12 | Siu Yan 页 `NamingThoughtCard.invitationText` 写入 `te.offerText` | 完整提议句 |
| T-13 / T-14 | `BriefPrGate.shouldSurfaceBriefPr(exchangeCount = recorder.userTurnCount ≥ briefPRMinTurns=2)` | 4 题（`briefPRItemCount`）；跳过记 `briefPR.completed=false` |
| T-15 | `WeeklyPrWindow` + `chooseReferent`（单元测试 `phase_a_weekly_window_test.dart` 覆盖并列规则） | 周日 20:00 推送（CF `weeklySurveyReminder` 既有）；首页入口至周二 23:59 |
| T-16 | CF `week2Push`（每日 10:00 HKT 扫描）+ 首页「第 2 週問卷」 | DJG-ES → Agent Differentiation |
| T-17 | 见 §4 | 需真机对话验证 |
| T-18 | `SupportAboutPage` 显示 appVersion / build / lexiconVersion / promptBundleHash 前 8 位 | 与 `docs/release/phase_a_baseline_versions.md` 一致（`phase_a_version_pin_test.dart` 守护） |

---

## 3. V-1 表

见 `docs/release/phase_a_baseline_versions.md`（由 `tool/export_spec_inputs.py` 生成；参与者 1 入组前在冻结 commit 上重跑一次）。

---

## 4. V-2 回报：theme / module_id 注入路径

**基线前实际情况（核实结论）**：

1. `theme`：回忆页把一段「今週主題：「X」…」的 themeLock 文本放进 `contextSuffix` 开头（系统 prompt 末尾），模型**能**看到主题；但 prompt 声明的 `theme` 字段并不存在，且反思对话页（同一 prompt）完全不送主题。
2. `module_id`：**只在 callable payload 里（`moduleId`），从未进入模型上下文**。prompt 的「Context injection 格式」声称有 `module_id`，实际没有 —— 按规格定义为 P0 bug。

**修复**：`LlmGateway.send` 新增 `theme` 参数；`injectThemeAndModule()` 在 suffix **末尾**追加 `[今週主題] {theme}`（有 theme 时）和 `[模組] {moduleId}`（所有 agent 调用）。回忆页传 `theme: themeTitle`。原 themeLock 段保留（不属于本版 prompt 内容改动范围）。单元测试 `phase_a_gateway_test.dart` 锁定注入格式与位置；`docs/prompts/context_suffix_template.txt` 已重新导出并计入 promptBundleHash。

**T-17 测试对话**：需要 DeepSeek 调用，本环境无 key，未执行；请在测试 build 上以 Ah Jan · Work 主题输入「今日好熱，你話係咪會落雨？」，预期一句承认后拉回工作主题。

---

## 5. 五旗 tag、`referral.offered`、`te.offered` 的产生机制

| 字段 | 机制 | Phase A 能否用 |
|---|---|---|
| `flags.F1–F5` | **CF 侧确定性正则**（`functions/llm_flags.js` `computeLlmFlags`，`_version: 2`），输入 = (用户消息, 模型回复, agentContext 快照, moduleId)，与 LLM 调用同一次 CF 请求返回，**不是模型自报、不是独立 LLM 调用**。F1 specific_content_engagement / F2 cross_session_memory / F3 honest_unfamiliarity / F4 mixed_content_routing / F5 generative_summary。 | 可用；同输入必同输出，可离线复算。已知限制：F1 用 2–4 字 CJK 子串回显，长回复易假阳；F2 只看 rolling summary + buffer 里的旧 token |
| `referral.offered` / `target` | 两路取并：(a) 客户端 `ReferralRoutingService` 真正弹出转介卡时事后 merge 写入（`referralCardTarget`，可靠）；(b) 回复文本正则 `ReferralScanner`（agent 名 + 邀请动词：搵／過去／傾下／要唔要／talk to…）。(b) 是启发式，可能漏掉不点名的转介句 | (a) 可用；(b) 作辅助，PI 复核时以 (a) 为准 |
| `te.offered` / `offerText` | **客户端**：`NegativeCognitionDetector`（关键词）命中且无升级、无 pending 卡片时，页面渲染 `NamingThoughtCard`，卡片文本（锁定句式 + 填充 thought）**原样**写入 `te.offerText`；另对模型回复扫描锁定前缀「你頭先講咗一句令我有少少 stuck」作为兜底 | 可用；`te_offer / te_accept / te_decline / te_module_open / te_module_complete` 事件配套 |

---

## 6. P-2 stripPII 说明

见 `docs/privacy/strip_pii.md`。关键发现：基线前 `contextSuffix`（rolling summary / named entities / mood）出站 DeepSeek **不经** stripPII；本版补上一行（`resolvePrompt` 内）。`referralJudgement` callable 仍未剥离（文档已标注，未改）。

---

## 7. 危机页面

`functions/prompts/crisis_resources.json`（同时作为 app asset）。四项顺序按 HREC §8.1；号码沿用公开列表但**标记为未核对**（`verifiedDate` 空 → 页面底部「資料核對日期：待核對」）。请 PI 核对后填入 `verifiedDate`。注意：基线前页面把 2382 0000 标为「撒瑪利亞防止自殺會」，公开资料该号码属生命熱線（SPS）；本版按规格名称对应，请一并核对。

---

## 8. 重新导出的文件

* `docs/prompts/agent_system_prompts_2026-09.md`（三份 prompt + suffix 模板 + SHA-256）
* `docs/safety/distress_detector_lexicon_v5-2026-09.md`（`safety_lexicon_v5-2026-09` 的内容，沿用既有文件命名）
* `docs/prompts/context_suffix_template.txt`

---

## 9. 与规格的偏差 / 需要 PI 注意

1. **M-5 Onboarding intake 12 题**：仓库没有 Questionnaire v1.3 Annex，无法重写题目。现有 6 部分 intake 保留；通通的 `interests` 已从 intake/profile 注入（`PersonaResolver` + `IntakeMemorySeeder`）。**待 v1.3 到手后替换题目**。
2. **M-1 Brief PR 题目**同上：沿用现有 4 个 stem；第 4 题由 `briefPRItemCount` 控制。规格未提「每日每 agent 一次」的旧去重，已按规格改为**每个合格 session 都问**（旧 180 s 时长门槛与每日去重一并移除）。
3. **M-2 12 题 + PGIC**：沿用现有 `WeeklyPrItems` 与 `PgicPage` 题目；referent 与窗口逻辑已按规格。
4. **M-4 DJG-ES**：题目为按公开 6 题短表的粤语工作稿（`djg_es_response.dart`，`itemsVersion: djg_es_6_draft_v1-2026-09`），待 v1.3 文本替换。W2 推送为逐设备 token 推送（不是广播 topic），需 `fcm_tokens` 已注册；iOS APNs 仍未配置（既有限制）。
5. **S-7**：默认 `moderate_interrupt`；改 `DistressDetector.hopelessnessTier` 一行即切到 acute。
6. **remote config**：实现为 Firestore `app_config/phase_a` 文档覆盖（无 Firebase Remote Config 依赖），键名与规格一致（`sessionIdleTimeoutMin` `briefPRMinTurns` `briefPRItemCount` `weeklyPrPushHour` `w2DayOffset` `w2WindowDays` `week1NudgeDays`）。CF `week2Push` 读同一文档。
7. **既有测试修正**：4 条基线时已失败的旧断言（`我想死` → acute，与 v4 D1 决定矛盾；"I don't see a reason to live" 为 v4 文档记录的已接受漏检）改为与现行词表一致。
8. **安全事件 `safety_events.level`** 保留旧四档值（`moderate`）以兼容规则与 CF 触发器，新增 `tier` / `category` / `lexiconVersion` 字段。
