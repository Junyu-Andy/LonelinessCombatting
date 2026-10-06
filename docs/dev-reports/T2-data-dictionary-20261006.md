# T2 数据字典与外发数据清单（2026-10-06）

> 任务：`docs/dev-tasks/dev-tasks-1006.md` T2。只读代码，没有连 Firestore，没有调用 DeepSeek。
> 核对的代码：分支 `main` @ 27113ca。
> 写法：每条说法附文件路径和行号；找不到写“未在代码中找到”；推断的标“（推断）”。
> 组别写法：**两组** / **只 Hybrid（A）** / **只规则组（B）**。

## 0. 结论先看

1. **对话原文存在 Firestore 的地方有 7 处**，大多只在 Hybrid 组。规则组也有一处：怀旧 B 的留言原文，而且不受“保留对话”同意开关控制。见第 1.3 节。
2. **发往 DeepSeek 的内容**包括对话原文、近期历史和记忆条目。其中两条路径**带着用户名**，或者**没有经过去个人信息处理**（`stripPII`）。见第 2 节第 1、2 项。
3. 规则组在服务器端拿不到 DeepSeek，也拿不到 Brave 搜索。但**分组为空（还没分到组）的账号，服务器不拦**。
4. 语音输入现在用的是**手机系统自带的语音识别**（安卓是 Google，iOS 是 Apple），不是我们的 Google Cloud STT。服务器上的 `transcribeAudio` 没有任何地方调用。
5. **没有删除整个参与者数据的脚本或接口。**`tool/delete_memory.js` 只删记忆，不删问卷、日志、安全事件，也不删 Storage 里的导出文件。App 隐私页写的“設定 > 清除所有資料”在 App 里不存在。
6. **代码里没有向量索引，也没有本地 LoRA 安全模型的接入点。**
7. 登记表里写的“5-flag LLM 安全标记”，在代码里其实是**用正则算的 5 个“LLM 独有机制”标记**，不是安全标记，也不调用 LLM。安全词库是 v5，不是 v4。

---

## 1. 数据字典（Firestore）

所有集合都在项目 `loneliness-pilot-dev`（`firebase.json`，`lib/firebase_options.dart`）。
**Firestore 数据库所在地区：未在代码中找到**（`firebase.json` 没有写 location）。

### 1.1 列的含义

| 列 | 意思 |
|---|---|
| 写入方 | 客户端 = App；CF = Cloud Function（服务器） |
| PII | 是否含个人身份信息：姓名、电话、邮箱、年龄段、第三方联系人，或关于本人的自由文字 |
| 原文 | 是否含对话原文：U = 老人说的话，AI = 陪伴者的回复；“自由文字” = 老人自己填的非对话文字 |

### 1.2 每个用户下面：`users/{uid}` 和子集合

#### `users/{uid}`（用户资料）
- 字段定义在 `lib/features/auth/data/user_profile.dart:359-398`（`toMap`）。
- 写入：注册时 `auth_service.dart:121-125`；之后改资料 `:149-155`；登录 `:77-80`。
- 分组字段只由服务器写：`functions/arm.js:115-121`。
- 两组都有。

| 字段 | 类型 | 含义 / 写入时机 | 写入方 | PII | 原文 |
|---|---|---|---|---|---|
| uid | string | 账号 ID | 客户端 | ID | 否 |
| email | string | 登录邮箱 | 客户端 | **是** | 否 |
| displayName | string | 注册时填的称呼，没填就用邮箱前缀（`auth_service.dart:233`） | 客户端 | **是** | 否 |
| ageGroup | string | 年龄段 | 客户端 | **是** | 否 |
| emergencyContactName / emergencyContactPhone | string | 紧急联系人 | 客户端 | **是（第三方）** | 否 |
| closeContacts | list<{name, relation, phone}> | 亲近的人 | 客户端 | **是（第三方姓名和电话）** | 否 |
| interests | list<string> | 兴趣标签 | 客户端 | 低 | 否 |
| avoidTopics | string | 不想谈的话题，来自 intake 问卷（`intake_flow_page.dart:157-171`） | 客户端 | **是（自由文字）** | 否 |
| baselineUclaScore | int | 注册时的 UCLA 基线分（`login_page.dart:73`） | 客户端 | **是（健康量表分）** | 否 |
| preferredLanguage, highContrast, inputMode, preferredTimes, hasCompletedIntake | 各类 | 偏好和 intake 完成状态 | 客户端 | 否 | 否 |
| consent | map：functionalData、transcriptRetention、transcriptRetentionByAgent、sharedContextUse、acceptedAt | 同意设定 | 客户端 | 否 | 否 |
| ahJanAhBakVariant | string | 选阿珍还是阿伯 | 客户端 | 否 | 否 |
| arm | 'A'/'B' | 分组；写入后不能改（`firestore.rules` `armValid`） | CF `assignArm` | 否 | 否 |
| strataCell | int 0–3 | 分层（UCLA × 年龄） | CF | 由年龄和 UCLA 推出 | 否 |
| armAssignedBy, armAssignedAt, armAssignmentMode | string, 时间, string | 分组方式；客户端不能写（`firestore.rules` `serverAssignmentUntouched`） | CF | 否 | 否 |
| memory_enabled | bool | 测试员自愿开启记忆 v1 | 客户端 | 否 | 否 |
| weeklyProbeEnabled, quietTodayActivatedAt, firstIntroSeen, firstPprSeenByAgent, isTester | 各类 | 功能开关和显示记录 | 客户端 | 否 | 否 |
| createdAt, lastLoginAt | 时间或 ISO 字符串 | 注册和登录时间。注意：之后改资料会把它改写成字符串（`user_profile.dart` `toMap`） | 客户端 | 否 | 否 |
| w2PushSentAt | 时间 | 第二周推送已发 | CF `week2Push`（`functions/index.js:1567` 起） | 否 | 否 |
| memoryDeletedAt | 时间 | 跑删除脚本后写入 | 脚本 `tool/delete_memory.js` | 否 | 否 |

#### `users/{uid}/onboarding/intake`（入组问卷）
- 字段定义 `intake_response.dart:267-293`；写入 `intake_repository.dart:20-26, 43-55`。
- 两组都有（推断：onboarding 不分组）。

| 字段 | 类型 | PII / 原文 |
|---|---|---|
| mainGoals, lonelinessTimings, activities, topics, lifeChapters, preferredTimes | 选项 ID 列表 | 否 |
| mainGoalOther, activitiesOther, topicsOther | string | 自由文字 |
| importantPeople（≤5）, reconnectPeople（≤3） | list<{name, relationship, extra}> | **是（第三方姓名、关系）** |
| typicalMorning / Afternoon / Evening | string | **是（日常生活的自由文字）** |
| onMind | string | **是（自由文字，代码标为敏感，`:169`）** |
| avoidTopics | string | **是（自由文字）** |
| inputMode, completedParts, allCompleted, createdAt, updatedAt, itemTimestamps | 各类 | 否 |

#### `users/{uid}/sessions/{sessionId}`（会话）
- 写入 `lib/core/session/chat_session_recorder.dart:375-393`（开始）、`:472-477`（结束）、`:501-508`（Brief PR）、`:579-597`（登录时补记）。
- 两组都有。B 组的签到 B、怀旧 B 每次提交算一次会话（`rule_submission_flow.dart:38-71`）。
- **没有 PII，没有原文。**
- 字段：
  - participantId（= uid）、sessionId、kind（agent/tool）
  - agentId、toolId、moduleId、theme
  - startedAt、lastActivityAt、endedAt、endReason（user_left / timeout / crisis / app_killed）
  - userTurnCount、fallbackCount
  - briefPR{shown, completed, items}
  - sessionSummaryShown、sessionSummaryHasTEPointer
  - lexiconVersion

#### `users/{uid}/turns/{id}`（每一轮）
- 写入 `chat_session_recorder.dart:135-194, 435-436`；转介和点赞会补写（`:513-522, 552-574`）。
- 两组都有。B 组的标记是 `llm.status = rule_based`。

| 字段 | 内容 | PII / 原文 |
|---|---|---|
| participantId, sessionId, agentId, moduleId, theme, ts.userSent, ts.replyShown, createdAt | 标识和时间 | 否 |
| input.modality, input.voiceDurationMs, input.charCount | 文字还是语音、长度 | **只存字数，不存原文** |
| detector.tier / category / lexiconVersion / shortCircuited / ackShown | 安全检测结果 | 否 |
| detector.matchedTerm | 命中的词库关键词 | 是老人打出来的一个风险词，不是整句 |
| llm.status / error / model / latencyMs / systemPromptHash / promptVersion / temperature | 模型信息 | 否，**不存回复原文** |
| flags.F1–F5 | 5 个 LLM 机制标记 | 否 |
| referral.offered / target, te.offered | 是否转介、是否邀请做思维练习 | 否 |
| te.offerText | 思维练习邀请文字 | **含原文**：签到 A 里会引用老人原话（截 28 字，`naming_thought_card.dart:37-43`）；其他情况是 AI 回复里的一句 |
| tungtung.mode / articleId / searchInvoked | 通通模式 | 否 |
| feedback.thumb / reason / at | 点赞点踩 | 否 |

#### `users/{uid}/events/{id}`（行为日志）
- 写入 `lib/features/analytics/data/analytics_service.dart:145-168`。服务器也写几种推送记录（`functions/index.js` `weeklySurveyReminder`、`week2Push`、`sendTestPush`）。
- 两组都有；每条带 `arm`。
- 字段：name、params、sessionId、locale、highContrast、arm、timestamp。
- 原则上不存 PII，自由文字只存长度（`analytics_service.dart:16-18, 231`）。
- **例外**：`te_offer` / `te_accept` / `te_decline` 的 `offerText` 含老人原话最多 28 字（`check_in_arm_a.dart:674-676`）；`cross_referral_offered` 的 `matchedTextPrefix32` 是命中短语前 32 字。

#### 问卷和量表

| 集合 | 主要字段 | 写入位置 | 组别 | PII / 自由文字 |
|---|---|---|---|---|
| `brief_pr` | schemaVersion、agentId、agentDisplayName、sessionRef、understanding / validation / caring / insensitivity（1–7）、isAnchorPrompt、status、promptedAt、respondedAt、arm | `brief_pr_page.dart:129-134, 173-178` | 两组 | 否 |
| `weekly_pr` | weekIso、agentId、items（u1..i3，1–7）、status（completed / skipped / no_referent / missed）、sessionCountThisWeek、referentRule、arm | `weekly_pr_page.dart:96-120`；`weekly_pr_trigger.dart:224-285` | 两组（推断） | 否 |
| `pgic` | value（1–7）、isoWeek、weekIso、answeredAt。**没有 arm** | `pgic_page.dart:61-68` | 两组（推断） | 否 |
| `djg_es` | timepoint、itemsVersion、answers（e1–e3、s1–s3，**6 条**）、score（0–6）、status。**没有 arm** | `djg_es_page.dart:43-47` | 两组（推断） | 否 |
| `agent_diff` | wave、usageFreq、personality、function、**freeResponse**。**没有 arm** | `agent_diff_page.dart:143-159` | 两组（推断） | **freeResponse 是自由文字** |
| `daily_mood` | mood（1–5）、date_iso、is_primary、entry_seq_today、source_surface、arm | `mood_recorder.dart:67-80` | 两组 | 否 |
| `check_in_responses` | mood、talked、social_day、significant_event、**note**、date_iso | `check_in_arm_b.dart:236-250` | **只 B** | **note 是自由文字（当天日记）** |
| `loneliness_probes`、`pending_loneliness_probes/current` | score（0–10）、isoWeek | `loneliness_probe.dart:99-108` | 页面没有入口，默认关 | 否 |
| `ppr_responses` | agentId、form、items、freeText | `ppr_scale.dart:191-215` | 只有测试工具会写 | freeText |
| `unblinding_probes`、`dependency_probes`、`distinguishability_probes` | guess、confidence、openResponse 等 | `phase_b_probes.dart:130-173` | **没有任何调用，目前不会写** | openResponse |

#### 功能数据

| 集合 | 主要字段 | 写入位置 | 组别 | PII / 原文 |
|---|---|---|---|---|
| `thought_exercise/{id}` | situation、thought、oneReasonTrue、anotherWayToLook、emotionEmoji、intensityBefore/After、agentId、agentInvitationText、originTurnRef、entryPathway | `thought_exercise_entry.dart:156-176` | 两组；从小欣邀请进入的路径只 A（`check_in_arm_a.dart:726-733`） | **4 栏都是自由文字**；agentInvitationText 是 AI 文字；originTurnRef 含 uid |
| `thought_records` | 旧版思维练习 | `thought_record.dart:76-80` | 已弃用，没有调用 | 自由文字 |
| `action_plans/{id}` | action、whenText、whereText、whoWith、fallback、arm、outcome、followUpNote | `action_plan.dart:109-130` | 两组。A 的字段是自由文字；B 除 action 外是选项 | **action、followUpNote 是自由文字；A 组 whoWith 可能有人名** |
| `reminders/{id}` | kind、fireAt、title、**body（含计划内容）**、linkedDocId、delivered | `reminder_service.dart:69-79` | 两组 | body 含自由文字 |
| `response_feedback/{id}` | agentId、moduleId、arm、rating、reasonCategories、**reasonOtherText**、turnRef | `thumbs_feedback.dart:110-114` | 主要 A；通通在 B 组也显示（推断，`tung_tung_page.dart:683`） | reasonOtherText 是自由文字 |
| `tester_feedback/{id}` | reasons、**otherText**、promptHash、arm | `thumbs_feedback.dart:121-136` | 同上。名字叫 tester，但**所有点踩的人都会写** | otherText 是自由文字 |
| `fcm_tokens/{id}` | token、platform、updatedAt | `fcm_service.dart:156-171`；退出登录时删 | 两组 | 设备推送标识 |
| `llm_turn_features/{id}` | agentId、moduleId、systemPromptHash、flags、detectorVersion、latencyMs | `llm_turn_features.dart:110-120`（`if (!isArmA) return null`） | **只 A** | 否 |

#### 记忆相关（v0，App 写）

| 集合 | 主要字段 | 写入位置 | 组别 | PII / 原文 |
|---|---|---|---|---|
| `agent_contexts/{agentId}` | **shortTermBuffer**（最近 20 轮 {fromUser, text, timestamp}）、**rollingSummary**、lastFoldAt、lastFoldStatus | `agent_context_service.dart:190-334` | **只 A**（推断） | **U + AI 原文**。只在该陪伴者的对话保留同意打开、且该轮没有安全标记时写入。rollingSummary 是 LLM 摘要，或者用 intake 自由文字起头（`persona_resolver.dart:91-104`） |
| `shared_context/current` | recentMoodSummary、**pendingReferrals[{triggerSnippet, suggestionText, …}]** | `shared_context_service.dart:219-280`；`referral_routing_service.dart:126-135` | mood 两组；pendingReferrals 只 A | **triggerSnippet 是老人整句原话，不受同意开关控制** |
| `agent_greetings/{日期_agentId}` | text（LLM 生成的问候）、lang、agentId | `agent_greeting_service.dart:152-169` | **只 A**（`today_page.dart:82`） | AI 文字 |
| `memory/{moduleId}/entries/{id}` | **summary**（签到 A 里老人发言拼起来，≤2000 字）、tags、arm | `memory_store.dart:34-59`；调用 `check_in_arm_a.dart:766` | **只 A**（推断） | **U 原文**；只看旧的全局 `transcriptRetention` 开关 |
| `memory/m3_reminiscence/sessions/week_{n}` | **turns[]**、distress_flags、**end_summary_original**、end_summary_edited | `m3_session_store.dart:225-345` | **两组** | **U + AI 原文**。turns 受同意开关控制；**B 组的 end_summary_original 就是老人留言原文，不受同意开关控制**（`reminiscence_arm_b_page.dart:103-110`） |
| `cross_module_callbacks/{…}` | source_module_id、source_family、used_at | `cross_module_memory.dart:123-141` | 只 A（推断） | 否 |

#### 记忆 v1（服务器写，`functions/memory.js`）
- 只有 v1 范围内的用户才会写：A 组 + `armAssignmentMode == randomise` + `meta/memory_config.phaseBArmA`，或者测试员自愿开启。**B 组一律不写**（`memory.js:538-546` `inScope`）。
- App 只能读、删、确认，不能写（`firestore.rules` mem_* 段；`memory_v1_service.dart:121-140`）。

| 集合 | 主要字段 | 写入时机 | PII / 原文 |
|---|---|---|---|
| `mem_extractions/{id}` | agent_id、**turns（对话原文）**、status、attempts、raw_output（模型原始输出 ≤2 万字）、dropped、counts、error | 离开聊天页（`memoryEndSession`）或 30 分钟没新消息（`memorySweep`，每 15 分钟跑）时把缓冲区搬进来（`claimBuffer`）；抽取成功后 turns 清空（`processExtraction`） | **抽取前有 U + AI 原文**；成功后清空，失败时保留；raw_output 含模型摘录 |
| `mem_facts/{id}` | category（8 类，含 name/family/health）、key、value、**quote（老人原句）**、visibility、sensitivity、status、revision_count、needs_review、replaces | 抽取成功时 | **是**（姓名、家人、健康）；**quote 是原话片段** |
| `mem_summaries/{id}` | summary（≤150 字）、turn_count、started_at、ended_at、day_key、sensitivity | 同上 | 对话摘要 |
| `mem_followups/{id}` | description、due_date、**quote**、sensitivity、status、asked_at | 同上；注入后标 asked（`injectMemory`） | 原话片段 |
| `mem_injections/{id}` | agent_id、module_id、memory_ids、layers、policy、chars | 每次把记忆拼进 prompt 时 | 否（只有 ID） |

#### 其他子集合
- `pending_loneliness_probes/current`：见上面问卷表。
- `stt_usage` 是顶层集合，见 1.3。

### 1.3 顶层集合

| 集合 | 字段 | 写入方 / 位置 | 组别 | PII / 原文 |
|---|---|---|---|---|
| `safety_events/{id}` | uid、source（gateway_input / gateway_output / rule_turn）、**textHash（整句的 SHA-256）**、level、tier、category、lexiconVersion、matchedTerm、agentId、sessionId、createdAt；CF 补写 dedup_key | 客户端 `safety_event_writer.dart:58-72`；CF `onSafetyEventCreated` | 两组 | uid；**不存原文**，只存哈希和命中词 |
| `safety_event_dedup/{key}` | uid、source、textHash、minuteBucket、eventRef | CF | 两组 | uid |
| `pi_alerts/{id}` | uid、source、level、agentId、dedupKey、isTester、eventPath | CF，只在 acute 时写 | 两组 | uid |
| `te_audit_queue/{id}` | entryRef、uid、entryId、agentId、agentInvitationText、**thoughtPreview（思维练习“想法”栏前 80 字）**、sampled、status、audit{…, researcher_notes} | CF `onThoughtExerciseCreated`；研究员后台写审核结果（`researcher_dashboard_page.dart:259-270`） | 两组 | uid；**自由文字片段** |
| `pending_loneliness_probes/{uid}` | uid、dueAt、status | CF `weeklyLonelinessProbe` | 两组（只有 weeklyProbeEnabled 的人） | uid |
| `stt_usage/{id}` | uid、model、region、bytes、latencyMs | CF `transcribeAudio`（`functions/index.js:747-754`） | 目前没人调用 | uid |
| `export_blind_keys/{日期}` | mapping（A/B → Group_X/Y）、salt | CF `blindedDataExport` | — | 否 |
| `meta/arm_counter` | cell_0..3 的 aCount / bCount | CF `assignArm` | — | 否 |
| `meta/memory_config` | enabled、policy、phaseBArmA | 研究员在控制台写 | — | 否 |
| `app_config/arm_assignment`、`app_config/phase_a` | randomise；w2DayOffset 等参数 | 研究员在控制台写 | — | 否 |

### 1.4 Firestore 以外的存储
- **Cloud Storage**：`blindedDataExport` 每周日 2:00 把导出文件写进默认 bucket 的 `exports/{日期}/{集合}.ndjson`（`functions/index.js` `blindedDataExport`）。
  - bucket 名是 `loneliness-pilot-dev.firebasestorage.app`（`lib/firebase_options.dart:55`）；所在地区未在代码中找到。
  - 导出的内容和问题见第 3.3 节。
- **手机本地**：App 没有用 SharedPreferences、SQLite 或文件。但 Firestore SDK 默认开离线缓存：读过的文档（包括对话原文）和没上传的写入会留在手机上（推断：代码里没有关掉 `persistenceEnabled`）。
- **App 里没有用** Firebase Analytics、Crashlytics、Storage SDK、Remote Config（`pubspec.yaml:19-30`）。

---

## 2. 外发数据清单

### 2.1 总表

| # | 服务 | 发出的内容 | 含对话原文？ | 含用户名？ | 含记忆？ | 触发时机 | 服务地区（代码可见） | 密钥放在哪 | 组别 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **DeepSeek**（`proxyDeepSeek`） | system prompt（persona + contextSuffix + 记忆块），本次会话历史 + 本轮输入；header 带一个随机化的会话码（`functions/index.js:313-366`） | **是**（U + AI） | **通常否，但有例外**（见 2.2） | **是**：v1 记忆块；v0 滚动摘要、兴趣、avoidTopics、往周怀旧片段 | 每次 A 组聊天发言、开场白、问候、周小结、文章问答、行动计划、社交建议等 | 端点 `https://api.deepseek.com/chat/completions`。地区未在配置中找到；代码注释写“DeepSeek server in mainland China”（`index.js:126-131`，第 129 行） | Secret Manager：`defineSecret("DEEPSEEK_API_KEY")`（`index.js:15`） | 只 A；服务器拒 B（`assertLlmAllowed`，`index.js:255-260`） |
| 2 | **DeepSeek**（`referralJudgement`） | 来源陪伴者 persona，**最近 10 轮原文**，命中短语（`index.js:438-560`） | **是** | 否（经 stripPII） | 否 | A 组签到、反思对话中关键词命中转介条件时（`referral_routing_service.dart:151-168`） | 同上 | 同上 | 只 A；服务器拒 B |
| 3 | **DeepSeek**（记忆 v1 抽取，`callDeepSeekJson`） | 抽取指令 + 该陪伴者能看到的现有事实 + **整段对话原文**（`memory.js` `buildExtractionPrompt`；`index.js:1318-1345`） | **是** | 可能（事实里有 name、family 类） | **是** | 离开聊天页（`memoryEndSession`）；每 15 分钟扫一次闲置 30 分钟的对话（`memorySweep`） | 同上 | 同上 | 只 v1 范围内的 A 组；B 组 `inScope` 返回 false |
| 4 | **Brave Search**（`webSearch`） | **老人在通通里打的原话**作为搜索词（`tung_tung_page.dart:302`；`index.js:620-630`） | **是（一句）** | 有可能，**没有 stripPII** | 否 | A 组老人在通通里打开“搜一搜”后发言 | 端点 `https://api.search.brave.com/res/v1/web/search`；地区未在代码中找到 | Secret Manager：`SEARCH_API_KEY`（`index.js:568`） | 只 A；服务器拒 B |
| 5 | **手机系统语音识别**（Android：Google RecognitionService；iOS：Apple） | 老人的语音 | **是（语音）** | 视内容而定 | 否 | 老人按麦克风说话时（`lib/core/voice/voice_input_button.dart:113, 285-303`），`_onDeviceOnly = false`（`:125`），允许系统用云端识别 | 由手机厂商决定，未在代码中找到 | 无（系统服务） | **两组** |
| 6 | Google Cloud Speech-to-Text v2（`transcribeAudio`） | base64 语音、语言代码 | 是（语音） | — | 否 | **目前 App 没有调用**（`lib/` 里没有 `transcribeAudio`） | 先 `asia-southeast1`（chirp_2），失败退回 `global`（long）（`index.js:666-672`） | 不用密钥，用服务账号（ADC） | 两组（如果启用） |
| 7 | **FCM（Firebase Cloud Messaging）** | 推送标题和正文（固定文案），`data.kind` | 否 | 否 | 否 | 周一至六 19:00、周日 20:00 广播到 topic `all`；入组第 14–16 天 10:00 按设备 token 发（`index.js` `dailyMoodReminder`、`weeklySurveyReminder`、`week2Push`） | Google 全球服务，未在代码中找到地区 | 服务账号（admin SDK） | 两组相同 |
| 8 | **SMTP 邮件**（给 PI 的告警） | 陪伴者 ID、来源、事件路径；**不含原文和 uid 以外的身份信息**（`index.js:913-930`） | 否 | 否（事件路径里没有 uid） | 否 | acute 安全事件，非测试员，且配置了 SMTP 时 | SMTP 主机在密钥里，代码看不出 | Secret Manager：`SMTP_HOST`、`SMTP_USER`、`SMTP_PASS`、`PI_EMAIL`（`index.js:16-19`） | 两组 |
| 9 | Firebase（Auth、Firestore、Functions、App Check） | 账号、全部 App 数据 | 是 | 是 | 是 | 一直 | Functions：`asia-east2`（香港）（`index.js` 每个函数的 `region`；App 端 `instanceFor(region: 'asia-east2')`）。Firestore 和 Storage 地区未在代码中找到 | 客户端配置在 `lib/firebase_options.dart`（公开的客户端配置）；服务器用服务账号；部署用 GitHub secret `FIREBASE_SERVICE_ACCOUNT`（`.github/workflows/deploy-firebase.yml:59`） | 两组 |

规则组（B）只会对外发出第 5、7、8、9 项。

### 2.2 去个人信息（`stripPII`）覆盖到哪里

`stripPII` 只替换 4 种东西：香港电话、邮箱、身份证号、楼层门牌号（`functions/index.js:148-165`）。**不去掉人名**，代码注释说这是有意的（`:138-143`）。

| 发给 DeepSeek 的部分 | 经过 stripPII？ | 位置 |
|---|---|---|
| 对话消息（messages） | 是 | `index.js:327-330` |
| contextSuffix（走 promptKey 时） | 是 | `index.js:119` |
| 记忆 v1 块 | 是 | `index.js:320` |
| 转介判断的最近 10 轮 | 是 | `index.js:516-519` |
| 记忆抽取的对话 | 是（user 段） | `index.js` `callDeepSeekJson` |
| **App 直接传来的 systemPrompt（不走 promptKey）** | **否**，原样发出 | `index.js:103`（`if (!promptKey && rawPrompt) return rawPrompt`） |
| **Brave 搜索词** | **否** | `index.js` `webSearch` |

直接传 systemPrompt 的地方，带了什么个人信息：
- **怀旧 A 的开场白**：system prompt 里写 **“用戶稱呼：{displayName}”**，再加往周的分享片段（`reminiscence_arm_a_page.dart:236-264`）。**这就是用户名直接发给 DeepSeek。**
- **每日问候**：兴趣、avoidTopics、上次滚动摘要（`agent_greeting_service.dart:107-134`）。
- 另外，走这条路径时 contextSuffix 会被服务器直接丢掉（`index.js:103`）。这是行为问题，不是隐私问题。

其他发给服务器、但**不转给 DeepSeek** 的：`agentContext`（滚动摘要 + 人名实体表）只在服务器里算 5 个机制标记（`index.js:394-400`；`llm_flags.js` 只有正则，不联网）。

### 2.3 分组为空的账号
`assertLlmAllowed` 只在 `arm == "B"` 时拒绝（`index.js:255-260`）。还没分到组（`arm` 为空）的账号，服务器允许调用 DeepSeek。App 在 arm 为空时显示 B 组界面（决策 0004），所以正常使用不会触发（推断）。

---

## 3. 数据保存与删除

### 3.1 现有的删除方式

| 方式 | 谁能用 | 删什么 | 位置 |
|---|---|---|---|
| `tool/delete_memory.js` | 研究员，用服务账号在本机运行；默认只预览，加 `--confirm` 才删 | 记忆 v1：`mem_facts`、`mem_summaries`、`mem_followups`、`mem_injections`、`mem_extractions`。记忆 v0：`agent_contexts`、`shared_context`、`agent_greetings`、`cross_module_callbacks`，以及 `memory/*` 下的所有文档（含怀旧 `week_n`）。然后设 `memory_enabled=false`。可按 uid、邮箱或 `--all` | `tool/delete_memory.js:33-43, 66-95` |
| 「我記得嘅嘢」页面 | 老人自己（只有 v1 用户能看到） | 单条 `mem_facts` / `mem_summaries` / `mem_followups` | `memory_v1_service.dart:135-136`；`remembered_page.dart:171` |
| 测试员“重置我嘅資料” | 只有输入测试员 PIN 后可见 | `agent_contexts`、`shared_context`、`daily_mood`、`mem_facts`、`mem_followups`、`mem_summaries`、`memory/*/entries` | `lib/features/settings/data/tester_tools.dart:32-73`；`settings_page.dart:413-437` |
| 退出登录 | 老人 | 只删 `fcm_tokens` | `fcm_service.dart:143-148` |

### 3.2 没有覆盖到的

- **没有“删除整个参与者”的脚本或接口。**代码里找不到删账号（`user.delete()`、`deleteUser`）或退出研究的流程。
- **`delete_memory.js` 有意不删研究数据**（`:6-8`），包括：用户资料（含姓名、电话、紧急联系人）、`onboarding/intake`、`sessions`、`turns`、`events`、全部问卷、`thought_exercise`、`action_plans`、`reminders`、`check_in_responses`、`response_feedback`、`tester_feedback`、`llm_turn_features`、`fcm_tokens`。
- **顶层集合也不删**：`safety_events`、`safety_event_dedup`、`pi_alerts`、`te_audit_queue`（含想法片段）、`pending_loneliness_probes`、`stt_usage`。
- **Firebase Auth 账号**不删。
- **Storage 导出文件**（`exports/{日期}/*.ndjson`）不删，也没有自动过期的代码（未在代码中找到 lifecycle 设置）。
- **向量索引：代码里没有**（`memory.js` 开头注释写明 v1 不做 RAG）。所以不存在要同步删除的向量。
- **日志**：Cloud Functions 的 `console.error` 会把 DeepSeek 返回的错误正文前 400 字写进 Cloud Logging（`index.js:364-376`）；记忆失败写 uid（`memory.js` `injectMemory`）。没有删除这些日志的代码。
- **DeepSeek、Brave 那边**的保存期限由对方决定，代码里没有任何删除请求。
- **App 隐私页写的和实际不符**：`privacy_policy_page.dart:22-24, 36, 63, 76` 写“冇雲端同步”“入「設定 > 清除所有資料」就可以一次過刪除晒”。实际上数据都上传 Firestore，设置里也没有这个选项。这一页从 `support_about_page.dart:97` 可以进入。

### 3.3 盲法导出（`blindedDataExport`）的内容
- **频率和位置**：每周日 2:00（香港时间），写到 Storage 的 `exports/`。
- **导出的集合**：users、events、ppr_responses、llm_turn_features、thought_exercise、loneliness_probes、turns、sessions、brief_pr、weekly_pr、pgic、djg_es、agent_diff、daily_mood、response_feedback、safety_events、pi_alerts（`index.js` `_EXPORT_BLINDED_COLLECTIONS`）。
- **去掉的字段**：email、displayName、emergencyContactName、emergencyContactPhone、closeContacts。`uid` 换成加盐哈希；`arm` 换成 Group_X/Y（`blindRow`）。
- **没去掉的**：
  - 用户资料里的 `ageGroup`、`baselineUclaScore`、`avoidTopics`（自由文字）、`interests`。
  - `sessions` / `turns` 里的 **`participantId` 就是原始 uid**（`chat_session_recorder.dart:146, 376`），`blindRow` 只处理叫 `uid` 的字段。
  - `thought_exercise` 的 4 栏自由文字，以及 `originTurnRef`（路径里有原始 uid）。
  - `response_feedback.reasonOtherText`、`agent_diff.freeResponse`。
- **会让分析员猜出组别的字段**（推断）：
  - `llm_turn_features` 只有 A 组有；
  - `turns.llm.status = rule_based` 只出现在 B 组；
  - `turns.llm.model` 只在 A 组有值。

---

## 4. 本地 LoRA 安全模型接入点

**未在代码中找到。**`lib/`、`functions/`、`tool/` 都没有 LoRA、tflite、onnx、localhost 或本地模型调用。

现在 App 里唯一的“分类器”是关键词词库 `lib/core/safety/distress_detector.dart`（v5-2026-09）。它在 `LlmGateway` 里检查两次：发出前查老人输入（`llm_gateway.dart:94-96`），收到后查 AI 回复（`:155-157`）。如果以后接 LoRA，最自然的位置是这两处（推断）。那样它会收到老人的原话和 AI 回复原文。

---

## 5. 要带回研究侧的发现

### 5.1 与登记表 C01–C22 不一致的地方

| 编号 | 登记表写的 | 代码实际 |
|---|---|---|
| C12 | 词库 v4 | 词库是 **v5-2026-09**（`distress_detector.dart`；`docs/dev/architecture.md` 第 10 节；决策 0012） |
| C12 | Hybrid 有“5-flag LLM 标记”做安全 | `functions/llm_flags.js` 的 5 个标记是 **LLM 独有机制标记**（具体内容、跨会话记忆、坦白不熟悉、混合内容转介、生成式摘要），用正则算，**不调用 LLM，也不是安全标记**。代码里没有用 LLM 做安全判断的地方 |
| C13 | Hybrid 上线本地 LoRA | 没有任何接入点 |
| C18 | STT 在 HREC 批准前关闭 | **语音输入现在两组都开着**，用的是手机系统识别，允许走云端（`voice_input_button.dart:125`）。类注释还写“audio NEVER leave the device”（`:76-86`），已经和代码不符 |
| C20 | 退出或研究结束时按 ICF 删除，含记忆 | 只有删记忆的脚本；没有删整个参与者的脚本。见 3.2 |
| C20 | 向量索引同步删除 | 没有向量索引 |
| C04 | 每次调用记录 `model` | 只有聊天走 `proxyDeepSeek` 时把 `model` 写进 `turns.llm.model`；记忆抽取、转介判断不记录（交给 T5） |
| C15 | DJG 版本待查 | App 内 DJG 是 **6 条**（e1–e3、s1–s3，`djg_es_response.dart`） |
| C15 | 每周孤独探针在 app 内填 | 页面没有入口，开关默认关；服务器写的位置 `pending_loneliness_probes/{uid}` 和 App 读的位置 `users/{uid}/pending_loneliness_probes/current` 不一样 |

### 5.2 会影响 ICF、DMP、研究方案的事实

1. **对话原文发到 DeepSeek**（境外服务，代码注释写在中国内地）。内容包括近期历史、记忆条目、兴趣、avoidTopics。
2. **怀旧 A 开场白把老人的称呼原样发给 DeepSeek**，不经过任何去个人信息处理（`reminiscence_arm_a_page.dart:236-264`；`index.js:103`）。问候 prompt 也不经过处理。
3. `stripPII` **不去人名**。老人在对话里提到的家人姓名会发给 DeepSeek，也会进记忆 v1 的 `mem_facts`（name、family 类）。
4. **通通的搜索词（老人原话）发给 Brave Search（美国公司）**，不经过任何处理。
5. **语音会交给 Google 或 Apple 的语音识别**（两组都是）。ICF 和 DMP 要写，或者改成只在本机识别。
6. **规则组也存了自由文字**：签到 B 的 `note`、怀旧 B 的留言（`end_summary_original` 不受同意开关控制）、行动计划、思维练习。
7. **Firestore 里存对话原文的地方**：`agent_contexts.shortTermBuffer`、`memory/m3_reminiscence/.../turns`、`memory/m2_check_in/entries`、`shared_context.pendingReferrals.triggerSnippet`（不受同意开关控制）、`mem_extractions.turns`（抽取失败时保留）、`mem_facts.quote`、`turns.te.offerText`（≤28 字）。DMP 要列出这些。
8. **没有完整的退出删除流程**，Auth 账号和 Storage 导出也不删。ICF 写的删除承诺目前做不到。
9. **App 隐私页的说法和实际不符**（“冇雲端同步”“清除所有資料”）。参与者会看到这一页，提交 HREC 前要改。
10. **盲法导出没有完全去识别**：`participantId` 是原始 uid，还有自由文字，也有能看出组别的字段。见 3.3。
11. **Firestore、Storage 的地区，以及 DeepSeek、Brave 的数据保存期限，代码里都看不出**，要到 Firebase 控制台和供应商条款里确认。
12. **安全告警邮件只在 acute 时发**，测试员的告警只写记录不发邮件（`index.js:861-895`）。
