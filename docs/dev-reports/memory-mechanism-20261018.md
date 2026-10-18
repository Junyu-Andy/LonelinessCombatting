# Hybrid 组跨会话记忆：代码核对报告（2026-10-18）

> 核对对象：仓库 `main` @ d6c38d9（2026-10-16）。**只核对，不改代码、不改提示词。**读者是 PI：每一条先给结论，再给代码依据（文件路径和函数名）。代码里查不到的写「代码里没有」。
> 本报告只说 Hybrid 组用的**服务器记忆 v1**；App 里旧的「每位陪伴者一段滚动摘要」（记忆 v0）只在和 v1 有关系的地方提。规则组任何记忆都没有，见第 2 节第 4 条。
> 前提：v1 要服务器配置文档 `meta/memory_config` 里 `enabled: true` 且 `phaseBArmA: true` 才会跑（`functions/memory.js` `loadConfig`、`inScope`）。10/15 的核对表（`docs/release/firestore-config-checklist-1015.md` 第 6 节）要求 10/19 前确认这两个值；本报告以它们已打开为前提。

## 0. 一页摘要

| 问题 | 结论 |
|---|---|
| 记忆存在哪 | 每位老人自己名下的五个集合 `users/{uid}/mem_facts`、`mem_summaries`、`mem_followups`、`mem_injections`、`mem_extractions`。三位陪伴者**共用一个池**，每条带「哪位陪伴者写的」（`agent_id`）。「层」（`layer`）和「来源陪伴者」（`sourceAgent`）两个字段**只有在开关 `layersEnabled` 打开时才写**；这个开关现在是关的 |
| 什么时候写 | 老人离开聊天页时 App 叫服务器整理（`memoryEndSession`）；没叫到的（App 被杀、断网、锁屏），服务器每 15 分钟扫一次，把 30 分钟没有新消息的对话整理掉（`memorySweep`）。但**小欣签到页和阿珍／阿伯回忆页在「切换陪伴者」和「30 分钟无消息」时不叫服务器**，只能等扫描；回忆页按返回键（不按「儲存」）也不叫 |
| 抽取用哪份提示词 | 代码默认 `memory_extraction.v2`。v3 已写好但没启用（要在 `meta/memory_config.extractionPrompt` 填 v3）。v2 里**没有**共享层／私有层的分类文字；层由服务器按类目规则定，不由模型定 |
| 下次开聊谁读 | 服务器 `proxyDeepSeek` 每一轮都读一次记忆、过滤、拼进提示词；App 不参与。现在（`layersEnabled` 关）按「策略 C」过滤：称呼、家人、居住三类非敏感事实三位共享，其余只给写它的那位；摘要、待跟进只给写它的那位。老人没勾「共享同意」时什么都不共享 |
| 唔好記住 | 规则加关键词，不用模型（`functions/memory_forget.js`）。识别到：那次会话**什么都不写**（不调模型），并删掉三位陪伴者名下所有「看起来是同一件事」的旧条目。识别发生在会话结束整理时，不是当轮；陪伴者当轮不会回「好，我唔會記住」（开关 `forgetAckReply` 默认关）。五句粤语全部识别到，四句易混句全部放过 |
| 删除 | 老人在「我記得嘅嘢」删一条事实或待跟进，服务器触发器连带删它来源那次会话的摘要和措辞完全相同的条目；删一条摘要只删那条。v1 没有「滚动摘要」要重算。**已经送去 DeepSeek 的内容没有任何处理**；另外服务器审计记录 `mem_extractions.raw_output` 里还留着模型当时输出的原文（删条目不会清它） |
| 首次记忆 | App 里的 `intake_memory_seeder.dart` **在 Hybrid 组不跑**（只服务记忆 v0）。研究员录入入组资料时，服务器直接把目标、兴趣、同意分享的人、唔想提起写成每位陪伴者的 `mem_facts`（T48）。生效：老人**下一次发消息**夥伴就带上，不用重开 App；通通的兴趣按钮、行动计划的人名按钮要完全关闭再打开 App |
| 隐私和记录 | 记忆块拼进提示词前过一次 `stripPII`（电话、电邮、身份证、楼层号）；整理记忆时发给模型的对话原文也过。每次注入记一条 `mem_injections`（用了哪些条目、各几条、多少字）；**共享层／私有层分开计数只在 `layersEnabled` 开时才记**，现在没有 |

## 1. 数据结构

**结论**：记忆放在每位老人名下的五个集合里，三位陪伴者共用一个池，每条带 `agent_id`（哪位陪伴者写的）。`layer`（shared／private）和 `sourceAgent` 两个字段**只有 `layersEnabled` 开着时才写**；关着时读取旧条目会按同一规则临时推算层，但不写回。

依据：

- 集合和写入方：`functions/memory.js` 文件头注释和 `processExtraction`（写 `mem_summaries`、`mem_facts`、`mem_followups`、更新 `mem_extractions`）、`injectMemory`（写 `mem_injections`）、`claimBuffer`（写 `mem_extractions`）。`firestore.rules` 第 424–443 行：老人能读、删 `mem_summaries`、`mem_followups`、`mem_facts`，只能把 `mem_facts.status` 从 `pending_confirmation` 改成 `active`；`mem_injections`、`mem_extractions` 客户端完全不能读写。
- `mem_facts` 每条字段（`processExtraction` 写入处）：`agent_id`、`category`（8 类：name 稱呼、family 家人、living 居住、hobby 興趣、routine 日常、event 重要事件、health 健康、preference 其他喜好；v3 多 feeling、story、grief）、`key`（标题 ≤40 字）、`value`（≤200 字）、`quote`（老人原话 ≤200 字）、`visibility`（shared／agent，旧的策略 C 字段）、`sensitivity`（normal／sensitive）、`status`（active／pending_confirmation／superseded）、`user_corrected`、`revision_count`、`needs_review`（改过 3 次以上）、`confidence`（永远 null）、`replaces`、`superseded_by`、`source_session_id`（来源那次整理的编号）、`created_at`、`updated_at`；`layersEnabled` 开时另加 `layer`、`sourceAgent`（`layerFields`）。
- `mem_summaries`：`agent_id`、`summary`（≤150 字）、`turn_count`、`started_at`、`ended_at`、`day_key`（对话发生那天，香港时间）、`visibility: "agent"`、`sensitivity`、`source_session_id`；文档编号就是那次整理的编号。
- `mem_followups`：`agent_id`、`description`（≤120 字）、`due_date`、`quote`、`sensitivity`、`status`（pending／asked）、`asked_at`、`source_session_id`、`created_at`。
- `mem_injections`（每次注入一条）：`agent_id`、`module_id`、`memory_ids`、`layers`（这里的 layers 是「待跟进、事实、敏感事实、摘要各几条」，不是共享／私有）、`policy`、`chars`、`created_at`；`layersEnabled` 开时再加 `layer_counts`（shared／private 各几条）、`source_agents`、`layers_enabled: true`、`session_id`（`injectMemory`、`injectionDose`）。
- `mem_extractions`（每次整理一条）：`agent_id`、`turns`（整理成功后清空）、`screened_safety_turns`、`status`（pending／done／failed）、`attempts`、`created_at`、`prompt_version`、`excluded_safety_turns`、`raw_output`（模型原始输出，最多 2 万字，**整理完也留着**）、`dropped`、`counts`、`finished_at`，「唔好記住」时还有 `outcome: "forget_request"`、`forget`。
- 一个池还是分开存：一个池。`loadMemory` 一次读整个 `mem_facts`／`mem_summaries`／`mem_followups`，再按 `agent_id` 和可见性过滤（第 4 节）。
- 层的推算：`itemLayer`（摘要、待跟进一律 private；敏感一律 private；事实按类目 `SHARED_LAYER_CATEGORIES`）；来源陪伴者：`itemSource`（`sourceAgent` 没有就用 `agent_id`）。
- 研究员录入写的入组记忆（T48）：`functions/researcher_intake.js` `seedMemoryFacts`，每位陪伴者各一份，`visibility: "agent"`、`layer: "private"`、`sourceAgent` 等于那位陪伴者、`source_session_id: "intake"`、`sensitivity: "normal"`、`status: "active"`（见第 7 节）。

## 2. 写入

**结论**：触发整理的是两件事：老人离开聊天页时 App 叫服务器函数 `memoryEndSession`；服务器每 15 分钟的 `memorySweep` 把 30 分钟没有新消息的对话、以及上次失败的整理补做。整理从 App 平时写的对话缓冲区（`users/{uid}/agent_contexts/{陪伴者}.shortTermBuffer`，最多 20 轮）取原话，一次事务取走并清空，所以同一段对话只整理一次。四个聊天页叫 `memoryEndSession` 的时机**不一样**，见下表。

### 2.1 对话怎样进缓冲区

- 每发一条消息并收到回复，App 把老人那句和回复各追加一轮到 `agent_contexts/{陪伴者}.shortTermBuffer`，超过 20 轮丢最旧的；同时写 `lastUpdated`（`lib/core/agent_context/agent_context_service.dart` `appendTurn`，`bufferCap = 20`）。**一次对话超过 20 轮，整理时只看到最后 20 轮**。
- 只有「保留對話紀錄」开着、而且那一轮没有被安全检测标记时才追加（例如 `lib/features/curious_companion/presentation/pages/tung_tung_page.dart` 第 460–465 行：`!response.hasEscalation && profile.consent.transcriptRetentionFor(...)`）。
- 追加用 Firestore 事务（`runTransaction`）。**断网时事务失败，那几轮不进缓冲区**，联网后也不补写（`appendTurn` 里没有重试；代码里没有离线补写）。

### 2.2 四个聊天页什么时候叫 `memoryEndSession`

App 这边统一经 `lib/core/agent_context/rolling_summary_compiler.dart` `compileAtSessionEnd(memoryV1: true)` → `lib/core/memory/memory_v1_service.dart` `endSession` → 服务器 `memoryEndSession`。失败不重试，交给扫描（`endSession` 的注释和 `catch`）。

| 页面 | 收尾按钮 S9 | 返回键／手势 | 切换陪伴者 | App 前台 30 分钟无消息 |
|---|---|---|---|---|
| 通通（`tung_tung_page.dart`） | 叫（`onClose` → `maybePop` → `PopScope` → `_maybeSurfaceBriefPr` → 编译器，第 907–918 行） | 叫（同上） | 叫（`_onSwitchedAway` → `_maybeSurfaceBriefPr`，第 274 行） | 叫（`_onIdleTimeout`，第 267 行） |
| 阿珍／阿伯 自由对话（`reflective_dialogue_page.dart`） | 叫（第 668–678 行） | 叫 | 叫 | 叫 |
| 小欣签到（`check_in_arm_a.dart`） | 叫，但只在老人至少发过 1 条消息时（`_finalizeOnExit` → `_saveSession` 第 853–863 行） | 同左 | **不叫**（`_onSwitchedAway` 第 424 行只走 `_surfaceBriefPr`，不走 `_saveSession`） | **不叫**（`_onIdleTimeout` 第 415 行同上）。之后老人再离开页面时才叫 |
| 阿珍／阿伯 回忆（`reminiscence_arm_a_page.dart`） | 叫（S9 在这页是「生成小结」，按「儲存」保存小结时叫，第 695–705 行） | **不叫**（`_maybeSurfaceBriefPr` 第 734–750 行没有编译器调用） | **不叫** | **不叫** |

没叫到的，都靠服务器扫描（下一小节）。

### 2.3 三种异常情况

| 情况 | 有没有写入 | 依据 |
|---|---|---|
| App 被系统杀掉 | **有，延后**。App 没机会叫服务器；缓冲区已在 Firestore（联网时写的）。`memorySweep` 每 15 分钟跑一次，发现某位陪伴者的缓冲区非空且 `lastUpdated` 早于 30 分钟前，就整理（`functions/index.js` `memorySweep`，`idleBefore = 30 分钟`）。最坏 45 分钟后写入 | `index.js` 第 1831–1900 行 |
| 断网 | **部分**。断网期间发的那几轮进不了缓冲区（2.1）；离开页面时 `memoryEndSession` 调不通，`endSession` 吞掉错误。联网后扫描会整理缓冲区里已有的轮次 | `agent_context_service.dart` `appendTurn`；`memory_v1_service.dart` `endSession` |
| 锁屏 30 分钟 | **有，由服务器扫描写入**。App 的 30 分钟空闲计时器在退到后台时**暂停**，回前台从零重算（`lib/core/session/idle_session_timer.dart` 文件头），所以锁屏不会触发 App 端的「超时」。但服务器只看 `lastUpdated`：锁屏超过 30 分钟，扫描就把缓冲区整理掉。老人解锁继续聊，新的几轮会成为**第二次**整理（同一次「来访」变成两条摘要） | `idle_session_timer.dart`；`index.js` `memorySweep` |

### 2.4 规则组

**完全不写**。服务器：`inScope` 遇到 `arm === "B"` 直接返回 false，`memoryEndSession` 回 `inactive`、`memorySweep` 跳过、`injectMemory` 返回空（`memory.js` `inScope`、`memoryActive`）。App：规则组页面（`check_in_arm_b.dart`、`reminiscence_arm_b_page.dart`、通通的 `_ruleBased` 分支）没有 `appendTurn` 调用，缓冲区也不写。测试：`functions/test/memory_acceptance_emulator_test.js`「rule-based arm: no extraction, no injection, no model call」。

### 2.5 整理时还会过滤什么

- 老人原话先用 App 同一份安全词库查（`functions/safety_lexicon.json`，`screenTurns`）：命中 moderate 或 acute 的那一轮和陪伴者的回复不发给模型、不存；这次会话不写摘要（`validateExtraction` `excludeSafety`）。
- 「唔好記住」识别见第 5 节。
- 模型输出再校验：每条事实、待跟进必须附老人原话里连续的一段，对不上的丢弃（`validateExtraction` `quoted`）；含自杀自残词的丢弃；health 类一律敏感，另按 `SENSITIVE_TERMS` 词表判敏感（`classifySensitivity`）；敏感事实先存成 `pending_confirmation`，老人在页面确认后才会用。

## 3. 抽取提示词

**结论**：现在跑的是 `functions/prompts/memory_extraction.v2.txt`（代码默认 `DEFAULT_EXTRACTION_PROMPT = "memory_extraction.v2"`，可由 `meta/memory_config.extractionPrompt` 改成 v1 或 v3；`t10Flags`）。正式项目有没有填这个字段要在控制台看，10/15 核对表没有列它，按默认算 v2。v3 文件存在（T31 写的），**没有启用**。v2 里**没有**把内容分到共享层和私有层的文字，只有「敏感」的判法；层由服务器按类目决定（`layerFor`），模型不参与。v3 多了三类（feeling、story、grief）和一段「每個 category 嘅意思同埋邊個陪伴者會知」。

依据：`memory.js` `buildExtractionPrompt`（填 `{{TODAY}}`、`{{WEEKDAY}}`、`{{CATEGORIES}}` 三个槽位；用户消息是「[現有事實]」加「[今次對話]」逐轮原话）；`processExtraction` 调 `callDeepSeekJsonFor`（`index.js`，`response_format: json_object`，`temperature 0.2`，`max_tokens 1500`，记一条 `llm_calls`，`call_type: memory_extraction`）。

v2 和 v3 全文见附录 A、附录 B。v3 的分类规则是这几句：「三位陪伴者都會知（共享）：name、family、living、routine、hobby、preference」「只有今次呢位陪伴者知（私有）：feeling、health、grief、story、event」「一件事如果同時講到共享同私有嘅內容……分開兩條記」「唔肯定歸邊類，就揀私有嗰類」。注意：即使切到 v3，服务器还是按 `layerFor` 的类目表定层，模型写错类目只影响归类，不会把私有内容变成共享（`validateExtraction` 校验类目必须在允许列表里）。

## 4. 注入

**结论**：下次开聊时，**服务器**在每一轮 `proxyDeepSeek` 调用里读整个池、过滤、拼成一块接在人设提示词后面（`index.js` `proxyDeepSeek` → `memory.injectMemory`）。App 不读 `mem_*`，也不能读 `mem_injections`。过滤按老人的共享策略：现在（`layersEnabled` 关）是策略 C；老人的 `consent.sharedContextUse` 不是 true 时降为策略 B（什么都不共享，`effectivePolicy`）。

### 4.1 读哪些、怎么过滤（`selectForInjection`、`visibleTo`，`layersEnabled` 关时）

| 内容 | 自己写的 | 另外两位写的 |
|---|---|---|
| 事实，非敏感 | 全部 | 只有 `visibility: "shared"` 的，即 name 稱呼、family 家人、living 居住三类（`SHARED_CATEGORIES`、`visibilityFor`） |
| 事实，敏感（已确认） | 给 | 不给 |
| 摘要 | 最近 3 天，同一天合成一行 | 不给（策略 C 下摘要当策略 B 处理） |
| 待跟进 | 到期的 1 条，只在一次对话的第一轮，问过标 `asked`，过期 7 天不再提 | 不给 |

`layersEnabled` 开后改为 `visibleInLayers`：共享层（name、family、living、routine、hobby、preference，非敏感）三位都给；私有层只给 `sourceAgent`；摘要、待跟进一律私有。入组录入的事实是每位各一份私有副本，不受影响。

### 4.2 三位各自看到对方什么（现在的设置）

- 小欣：自己的全部，加阿珍／阿伯、通通记下的稱呼、家人、居住（非敏感）。
- 阿珍／阿伯：自己的全部，加小欣、通通的稱呼、家人、居住。
- 通通：同上对称。
- 入组录入的四类事实（目标、兴趣、同意分享的人、唔想提起）每位各有一份，所以三位都看到各自那份（第 7 节）。
- 测试：`functions/test/memory_emulator_test.js`「another agent sees only the shared basic fact (policy C)」；`memory_layers_emulator_test.js` 第 1–4 条是开关开后的情况。

### 4.3 块的长度和压缩

- 整块封顶 **2,000 字符**（`LIMITS.maxChars`，注释估约 1,500 token）。超长不是压缩，是**按顺序整条去掉**：先去敏感事实，再去摘要（按天），再去事实，最后去待跟进（`renderMemoryBlock` 的 while 循环）。
- 配额：事实最多 20 条（按类目优先级 `CATEGORY_PRIORITY`，同类按最近更新）；已确认的敏感事实另有 5 个名额（`sensitiveFactQuota`）；摘要最近 3 天、每条 ≤150 字；待跟进 1 条。
- 块的样子：`<memory>` 里四段「[到期要關心嘅事]」「[關於對方嘅資料]」「[之前傾過]」「[敏感]（只喺對方自己提起先可以用）」，后面跟 6 条「記憶使用規則」（`USAGE_RULES`）。
- **`rolling_summary` 和 `named_entities` 两个槽位：代码里没有。** 三份陪伴者提示词末尾写「呢個 prompt 之後會有 context block：rolling_summary、named_entities……」，但服务器 `resolvePrompt`（`index.js` 第 146–168 行）只填 `{{VARIANT_NAME}}`，然后把 App 传来的 `contextSuffix` 原样接上。App 组 `contextSuffix` 时（`lib/core/agents/persona_resolver.dart` `resolve`）：记忆 v1 用户**不放**滚动摘要（`summaryText = ''`，连「[過往摘要]」那段都不加）；`namedEntities` 只有在 `agent_contexts` 文档里有时才加，而写入它的 `recordEntities` **没有任何调用方**（全仓库搜索），所以这段从来是空的。即：对 Hybrid 组，提示词里关于过去的内容只来自服务器的 `<memory>` 块，加上 App 另外接的「⛔ 用戶要求唔好提起呢啲話題」一行（`check_in_arm_a.dart` 第 538 行、`tung_tung_page.dart` 第 432 行、`reflective_dialogue_page.dart` 第 258 行；回忆页没有这行）。
- 哪些模块注入：`INJECT_MODULES`——小欣签到、阿珍／阿伯自由对话和回忆、通通聊天、三位的开场白生成。周小结、社交建议等不注入。

## 5. 「唔好記住」

**结论**：用**规则加关键词**识别，不用模型（`functions/memory_forget.js` `detectForget`：先去掉「記性唔好」「唔好記錯」「唔記得」「提醒」等易混词，再按 9 组正则匹配）。只看老人自己的话。识别发生在**会话结束整理时**（`processExtraction` → `screenTurns(forget: true)`），不是当轮；识别到就：这次会话**整段不写**——不调模型、不写摘要、事实、待跟进，`mem_extractions` 里的原话清空，标 `outcome: "forget_request"`；然后删掉三位陪伴者名下所有「看起来是同一件事」的旧事实、旧待跟进、旧摘要（`forgetRelated`：和请求那句及前两句老人原话有 2 个以上相同的两字片段，`memory_forget.relatedTo`）。所以不存在「只不写一层」，而是整次不写、两层旧的都删。

- 当轮回复：陪伴者会不会回一句「好，今次傾嘅嘢我唔會記住」，由开关 `meta/memory_config.forgetAckReply` 决定，**默认关**（`t10Flags`）。开了才在那一轮的提示词末尾加 `memory_forget_ack.v2.txt` 的指令（`forgetAck`，S2 定稿文字）。
- 漏判时：会话照常整理。v2 提示词里有一句「用戶要求唔好記住、當冇講過、唔好話畀人知嘅內容」一律不抽取，是给模型的软指令，没有保证；老人可以事后在「我記得嘅嘢」删。代码里没有别的兜底。
- 开关：`honourForgetRequests` 默认开，写 `false` 关。
- 试验（`node` 直接跑 `memory_forget.js` 的 `detectForget`，它是纯函数，不碰 Firestore，所以不用开 emulator；2026-10-18）：

| 老人可能说的话 | 识别结果 |
|---|---|
| 呢件事你唔好記住呀 | 识别（dont_remember） |
| 當我冇講過啦 | 识别（never_said） |
| 唔好話畀其他人知 | 识别（dont_tell） |
| 你唔使記呢啲嘢 | 识别（no_need_to_remember） |
| 我個仔啲嘢，你知就得，唔好講出去 | 识别（dont_spread） |
| 我記性唔好，成日唔記得食藥 | 不识别（正确：不是请求） |
| 唔好記錯呀，佢係我個侄 | 不识别（正确） |
| 你唔使記掛我 | 不识别（正确） |
| 我今日好開心，同個女去咗飲茶 | 不识别（正确） |

已知边界（文件头注释）：否定句「唔係叫你唔好記住」会被当成请求；转述句「個女叫我唔好話畀人知」也当请求（宁可多删）。

## 6. 删除

**结论**：老人在「我記得嘅嘢」页删一条（`lib/features/memory/presentation/pages/remembered_page.dart` `_ItemCard._delete` → `MemoryV1Service.delete`），App 直接删那一个 Firestore 文档。删的是**事实或待跟进**时，服务器触发器 `memoryFactDeleted`／`memoryFollowupDeleted`（`index.js` 第 1905–1920 行）再调 `deleteSummaryForItem`，连带删：它来源那次会话的摘要（文档编号等于 `source_session_id`，或 `source_session_id` 相同的）、`value` 完全相同的其他事实、`description` 完全相同的其他待跟进；`layersEnabled` 开时还删措辞去掉标点后相同的、同类目同标题的、原文含这条内容（≥4 字）的摘要（`sameThing`）。删的是**摘要**时没有触发器，只删那一条。

- 两层同删：现在没有「层」字段，但连带删除不看 `agent_id`，三位名下相同措辞的都删；开关开后按 `sameThing` 覆盖两层。
- `rolling_summary` 重算：v1 没有滚动摘要，每次会话一条独立摘要，删后**不重算**（原话在整理成功时已清空，`turns: []`，也没法重算）。
- 已送 DeepSeek 的内容：**没有任何处理**。代码里没有向 DeepSeek 发删除请求的地方；`llm_calls` 只存 token 数和模型名，不存内容。另外**服务器自己的 `mem_extractions.raw_output`**（模型当时输出的整段 JSON，最多 2 万字）在整理完后保留，删条目、「唔好記住」都不清它，只有 `tool/delete_memory.js` 整个删掉 `mem_extractions` 时才清（`docs/dev/memory-v1.md`「删除记忆」）。见第 10 节第 3 条。
- 整人退出：`tool/delete_memory.js --confirm` 删五个 `mem_*` 集合和 v0 的 `agent_contexts` 等，并写 `memoryWithdrawnAt`，之后服务器不再记录、不再注入（`inScope` `honourMemoryWithdrawal`）。

## 7. 首次记忆（入组资料）

**结论**：`lib/core/agent_context/intake_memory_seeder.dart` 在 Hybrid 组**不运行**：它只在 `PersonaResolver.resolve` 里 `!memoryV1` 时被调用（`persona_resolver.dart` 第 90 行），把入组答案写进 v0 的 `rollingSummary`。Phase B Hybrid 组用 v1，所以这条路不走。现在给 Hybrid 组的首次记忆是**研究员录入时服务器写的 `mem_facts`**（T48，`functions/researcher_intake.js` `recordIntake` → `seedMemoryFacts`，只在 `users/{uid}.arm === "A"` 时写）。

写成什么（`intakeFactsFor`）：

| 入组字段 | 写给谁 | 类目／标题 | 层 |
|---|---|---|---|
| `mainGoals` | 小欣、阿珍／阿伯、通通各一条 | preference／嚟呢度主要想 | 每份都是 `layer: "private"`、`sourceAgent` 等于收到的那位（每位一份，所以三位都看到自己那份） |
| `interests` 加 `interestsOther` | 小欣、通通 | hobby／平時鍾意 | 同上 |
| `importantPeople` 里勾了「老人家同意」的 | 小欣 | family／重要嘅人 | 同上 |
| `avoidTopics` | 三位各一条 | preference／唔想主動提起：…（用戶一開始就講明，唔好主動提） | 同上 |
| `inputMode` | 不写 | — | — |

再录一次会把上一次的入组事实标 `superseded` 再写新的；聊天抽取出来的事实不动（`seedMemoryFacts` 只找 `source_session_id == "intake"`）。这些条目 `sensitivity: "normal"`、`status: "active"`，**不经过**「敏感先确认」。

**生效时间**（可直接写进 W0 操作单）：

1. 研究员按「錄入」之后，老人**下一次发消息**，夥伴的提示词就带上这些记忆，不用重开 App（`proxyDeepSeek` 每轮现读 `mem_facts`，`loadMemory`）。
2. 通通聊天页的兴趣按钮、行动计划「同邊個」的人名按钮、小欣人设里的重要嘅人，读的是老人手机上启动时载入的资料，要老人**完全关闭再打开 App**（`AppSettings.profile` 在启动时读一次；代码里没有实时监听）。
3. 前提：老人已经登记（`recordIntake` 对未登记帐号报 `not_enrolled`），且服务器 `meta/memory_config.enabled` 和 `phaseBArmA` 为 true。

旧 6 页问卷的三位 PILOT 老人：他们的答案在 `users/{uid}/onboarding/intake`，没有经过 `seedMemoryFacts`，所以夥伴**没有**他们的首次记忆，研究员录一次就有（T47 报告第 5 节第 0 条）。

## 8. 隐私和记录

**结论**：

1. **送 DeepSeek 前的去识别**：`index.js` `stripPII` 把香港电话、电邮、身份证号样式、楼层号替换成占位符。用在三处：`proxyDeepSeek` 里记忆块拼进系统提示词前（`stripPII(memoryBlock)`）、每条对话消息（`scrubbed`）、App 传来的 `contextSuffix`（`resolvePrompt`）；整理记忆时发给模型的对话原文（`callDeepSeekJsonFor` 的 `stripPII(prompt.user)`）。**不处理**：人名、地名（文件头注释写明是刻意的，否则记忆功能没法用）；陪伴者人设提示词本身（没有个人信息）。请求头只带一个按次随机的会话代号，不带 uid（`sessionCodeFor`）。
2. **每次会话用了多少条记忆**：有记录，在 `mem_injections`，**每轮一条**（不是每次会话一条）：`memory_ids`、`layers`（待跟进、事实、敏感事实、摘要各几条）、`chars`、`policy`。**共享层和私有层分开计数**（`layer_counts`、`source_agents`）和会话编号（`session_id`）**只在 `layersEnabled` 开时写**（`injectMemory` 里 `if (active.cfg.layersEnabled)`）。现在开关关着，所以 S6 要的「共享层调用、私有层调用分开计」**现在没有记录**；要用 S6 必须先开 `layersEnabled`。把每轮加总成每次会话，要用 `session_id`，也只有开关开时才有。
3. 每次模型调用：`llm_calls`（`functions/llm_log.js` `buildLogRow`）记 `call_type`（对话 chat、整理 memory_extraction 等）、`agent_id`、`uid`、模型名、`prompt_tokens`、`completion_tokens`、延迟、`session_id`（App 传了才有；整理调用没有）。不存文字。
4. 操纵检验标志 `cross_session_memory`（`functions/llm_flags.js` `flagCrossSessionMemory`）只看 App 传来的 `agentContext.rollingSummary` 和 `shortTermBuffer`；v1 用户 App 传的 `rollingSummary` 是空字串、不传 `shortTermBuffer`（`persona_resolver.dart` `snapshotMap`），所以**这个标志对 Hybrid 组永远是 false**，不反映服务器记忆有没有被用上。要看记忆有没有用，只能看 `mem_injections`。

## 9. 冲突：代码和 `docs/spec/feature-registry.md`、`docs/dev/architecture.md` 不一致的地方

| # | 文件说的 | 代码里的 | 依据 |
|---|---|---|---|
| 1 | 登记表 C05：「每条记忆标所属层和来源陪伴者，调用时按陪伴者过滤」「记忆剂量按共享层和私有层分开计」 | 两个字段和分层计数都在开关 `layersEnabled` 后面，开关默认关，10/15 核对表写「关（T31 没定）」。现在跑的是旧的策略 C（共享三类）。「按陪伴者过滤」现在是按 `agent_id` 加 `visibility` | `memory.js` `t10Flags`、`visibleTo`、`injectMemory`；`firestore-config-checklist-1015.md` 第 6 节 |
| 2 | 登记表 C05：「记忆抽取 prompt 升 v3，PI 审后才上线」 | v3 文件在，默认仍 v2；PI 审没有记录 | `DEFAULT_EXTRACTION_PROMPT` |
| 3 | 登记表 C05：「老人说唔好記住的那次会话两层都不写入」 | 一致（整次不写），但识别在会话结束时，当轮不会确认（`forgetAckReply` 默认关）；登记表没写这个时间差 | 第 5 节 |
| 4 | 登记表 C05 / C16：会话结束＝收尾按钮、返回、切换陪伴者、30 分钟无消息 | 会话记录（`sessions`）是这样结束的；但**记忆整理**在小欣签到页的切换和超时、回忆页的返回、切换、超时都不触发，只靠 30 分钟后的服务器扫描（最坏再等 15 分钟） | 第 2.2 节 |
| 5 | architecture 第 7 节表格：v1 适用「`arm == A` 且 `armAssignmentMode == randomise`」；v0 是「pilot 用户」 | T21 起试跑的 Hybrid（`pilot_designated`）也是 v1；表格下面第 100 行自己也这样写，表格没改 | `memory.js` `inScope`（`PHASE_B_MODES`）、`memory_mode.dart` |
| 6 | `memory-v1.md`「已定」：「Phase B A 组在 onboarding 第一页看到『佢哋會記得你講過嘅嘢……』」 | 一致：这句在引导页，只对记忆模式为 Phase B Hybrid 的帐号显示 | `lib/features/onboarding/presentation/pages/agent_onboarding_page.dart` 第 411–420 行（`MemoryModes.of(...) == MemoryMode.phaseB`） |
| 7 | 三份陪伴者提示词末尾的「Context injection 格式：rolling_summary、named_entities、recent_mood……」 | 服务器只填 `{{VARIANT_NAME}}`；v1 用户 App 不放滚动摘要，`named_entities` 从来没写过。提示词这段描述的是 v0 时代的输入 | 第 4.3 节 |
| 8 | architecture 第 8 节表格：`mem_facts` 等「T31 开关打开后带 layer、sourceAgent」 | 一致；但 T48 的入组事实**不管开关**都写 `layer: "private"` 和 `sourceAgent` | `researcher_intake.js` `seedMemoryFacts` |
| 9 | 登记表 C20：「退出时按 ICF 删除，含记忆（两层）」；architecture 第 7 节「删除要一致」 | 单条删除和整人删除都不清 `mem_extractions.raw_output`（整人删除脚本会删整个集合，单条不会） | 第 6 节 |
| 10 | `docs/dev/memory-and-entry-spec.md` 3.3 口头删除：会话标 `doNotStore`、当轮回复、写 `mem_forget_requests` 给研究员 48 小时内处理 | 代码是另一种做法：不标会话、不写 `mem_forget_requests`、自动删相关旧条目；当轮回复有开关默认关。这份规格写的是「要改成什么样」，和登记表都没更新 | 第 5 节 |

## 10. 要 Junyu 定的事

核对中发现和已定设计不一致、要决定的，按影响排：

1. **两层（10/9 第 15 条）现在没有开。** 开 `meta/memory_config.layersEnabled` 和 `app_config/feature_flags.memoryLayersNoticeEnabled` 就是设计里的分层、按来源陪伴者过滤、分层计剂量（S6）、S7 说明。代码和测试都在（`memory_layers_emulator_test.js` 11 条）。不开，共享的只有稱呼、家人、居住三类，作息和兴趣不共享，S6 没法分层计。**决定：开不开、哪天开；开了之后影响所有 Hybrid 老人从那天起的对话。**工时：开开关 0；旧条目不迁移（决策 0035 第 4 条），不用改代码。
2. **抽取提示词 v3 要不要切。** 不切，模型不知道有 feeling、story、grief 三类，这类内容会被归到 event 或 preference（preference 在两层设计里是**共享**类，心事有被归成共享的风险，虽然敏感词命中仍会变私有）。切，PI 要先审 v3 全文（附录 B）。工时：审完改一个字段，0 开发。
3. **`mem_extractions.raw_output` 保留**（第 6 节）。老人删了条目，服务器审计记录里还有模型当时的原文。决定：删条目时也清对应 `raw_output`（半天，含测试），或接受现状写进 ICF／数据管理计划。
4. **小欣签到页、回忆页的记忆交接时机**（第 2.2 节）：切换陪伴者、30 分钟超时、回忆页按返回时不叫服务器，只靠扫描，最坏晚 45 分钟。老人在这 45 分钟内换一位夥伴再聊，那位看不到刚才的内容。决定：统一成四个页面每种结束都叫（半天，含测试），或接受。
5. **「唔好記住」的当轮确认**（`forgetAckReply`）默认关，S2 文字已定稿（T33）。决定：开不开。开是改一个字段。
6. **断网时的那几轮不进记忆**（第 2.1 节）。接受，或加离线补写（1 天，要处理顺序和重复）。
7. **缓冲区 20 轮上限**：一次聊超过 20 轮（老人 10 句加回复 10 句）只整理最后 20 轮。决定：接受，或提高上限（改一个数字；整理时发给模型的原文会变长）。
8. **三份陪伴者提示词末尾的「Context injection 格式」一段**（第 9 节第 7 条）描述的是 v0，对 v1 用户是误导（模型被告知会有 rolling_summary 却没有）。改提示词要新版本号、PI 审；可以和语气槽位（`companion-prompts-tone-slot-20261016.md`）一起改。工时：改文件半小时，审核另计。
9. **操纵检验标志 `cross_session_memory` 对 Hybrid 组永远 false**（第 8 节第 4 条）。要按 `mem_injections` 重算这个标志（1 天），或在分析里改用 `mem_injections`。
10. **10/14 第 6 条「不设开关」**：代码里 Hybrid 组确实没有老人能关的开关（设定页只有「我記得嘅嘢」入口，`settings_page.dart` 第 164–174 行），一致；但研究员侧的三个服务器开关（`enabled`、`phaseBArmA`、`layersEnabled`）和 `tool/delete_memory.js` 的撤回仍在。没有要定的，只是提醒。

## 附录 A：现在运行的抽取提示词 `functions/prompts/memory_extraction.v2.txt`（原文）

```text
你負責由一段長者同 AI 陪伴者嘅對話入面，抽取值得記住嘅資料。
只可以抽取「用戶」自己明確講過、當真講嘅內容，唔好推測、唔好補充。
每一條事實同待跟進事項，都要附上 quote：用戶原句入面連續嘅一段字，一字不改。
用繁體書面中文寫 value / summary / description，人名同重要粵語詞保留原文。
唔好記錄電話、地址、身份證號碼。

以下內容一律唔好抽取，亦唔好寫入 summary：
- 假設嘅說話（「如果……」「假如……」「要係……就……」）、願望式嘅幻想、講笑、誇張說法。
- 陪伴者自己講嘅嘢；陪伴者嘅名，或者用戶點樣稱呼陪伴者。
- 用戶否認咗嘅猜測。
- 用戶要求唔好記住、當冇講過、唔好話畀人知嘅內容。
- 涉及自殺、自殘、唔想活、一了百了、儲藥、想消失嘅內容。

如果對話入面有任何涉及自殺、自殘、唔想活、儲藥嘅說話（包括隱晦講法），safety_concern 填 true。

今日係 {{TODAY}}（{{WEEKDAY}}，香港時間）。
「聽日」「下個禮拜四」「月尾」呢類相對日期，要換算成 YYYY-MM-DD。
冇講明日期嘅事，唔好當待跟進事項。
有日期嘅計劃記做待跟進事項就夠，唔好再記多一次做事實。

category 只可以用：{{CATEGORIES}}。
name 只記用戶自己嘅稱呼（例如「張婆婆」），唔好記其他人或者陪伴者嘅名。
facts 入面每條要標 op：
- add：新事實
- update：修正或更新同一類（category 一樣）嘅現有事實，要填 fact_id（用下面「現有事實」嘅 id）；
  如果用戶係糾正之前講錯嘅嘢，correction 填 true
- no_change：唔使輸出（省略）
健康、家庭矛盾、財務、情緒困擾、喪親等內容，sensitive 填 true。

summary 只寫中性、日常嘅內容（例如做過咩、去過邊、同邊個見面）。
健康、家庭矛盾、財務、情緒困擾、喪親呢類敏感內容唔好寫入 summary；
需要記嘅話放入 facts，sensitive 填 true。冇中性內容就填空字串。

只輸出一個 JSON 物件，格式：
{"summary": "≤150字，第三身描述今次傾咗咩",
 "safety_concern": false,
 "facts": [{"op": "add|update", "fact_id": "", "category": "",
   "key": "簡短標題", "value": "", "quote": "", "sensitive": false,
   "correction": false}],
 "followups": [{"description": "", "due_date": "YYYY-MM-DD", "quote": ""}]}
```

`{{TODAY}}`、`{{WEEKDAY}}`、`{{CATEGORIES}}` 由服务器填：今天的香港日期、星期、允许的类目列表（v2 是 8 类）。

## 附录 B：已写好、未启用的 `functions/prompts/memory_extraction.v3.txt`（原文）

```text
你負責由一段長者同 AI 陪伴者嘅對話入面，抽取值得記住嘅資料。
只可以抽取「用戶」自己明確講過、當真講嘅內容，唔好推測、唔好補充。
每一條事實同待跟進事項，都要附上 quote：用戶原句入面連續嘅一段字，一字不改。
用繁體書面中文寫 value / summary / description，人名同重要粵語詞保留原文。
唔好記錄電話、地址、身份證號碼。

以下內容一律唔好抽取，亦唔好寫入 summary：
- 假設嘅說話（「如果……」「假如……」「要係……就……」）、願望式嘅幻想、講笑、誇張說法。
- 陪伴者自己講嘅嘢；陪伴者嘅名，或者用戶點樣稱呼陪伴者。
- 用戶否認咗嘅猜測。
- 用戶要求唔好記住、當冇講過、唔好話畀人知嘅內容。
- 涉及自殺、自殘、唔想活、一了百了、儲藥、想消失嘅內容。

如果對話入面有任何涉及自殺、自殘、唔想活、儲藥嘅說話（包括隱晦講法），safety_concern 填 true。

今日係 {{TODAY}}（{{WEEKDAY}}，香港時間）。
「聽日」「下個禮拜四」「月尾」呢類相對日期，要換算成 YYYY-MM-DD。
冇講明日期嘅事，唔好當待跟進事項。
有日期嘅計劃記做待跟進事項就夠，唔好再記多一次做事實。

category 只可以用：{{CATEGORIES}}。
每個 category 嘅意思同埋邊個陪伴者會知：
三位陪伴者都會知（共享）：
- name：用戶鍾意人點叫佢（例如「張婆婆」）
- family：家人同身邊嘅人（名、關係，例如個女、老友、鄰居）
- living：居住情況（同邊個住、住邊區）
- routine：日常作息（幾點起身、平日去邊、做咩）
- hobby：興趣
- preference：其他喜好（鍾意食乜、鍾意咩節目）
只有今次呢位陪伴者知（私有）：
- feeling：心事同情緒（擔心、唔開心、掛住人、覺得孤單）
- health：身體情況、睇醫生、食藥
- grief：哀傷內容（親人過身、拜祭、掛念已經離開嘅人）
- story：回憶故事（舊時嘅經歷、年輕時嘅事）
- event：最近發生嘅重要事情
一件事如果同時講到共享同私有嘅內容（例如「個女阿欣成日陪我睇醫生」），
分開兩條記：family 記「個女叫阿欣」，health 記「有睇醫生」。
唔肯定歸邊類，就揀私有嗰類。
name 只記用戶自己嘅稱呼（例如「張婆婆」），唔好記其他人或者陪伴者嘅名。
facts 入面每條要標 op：
- add：新事實
- update：修正或更新同一類（category 一樣）嘅現有事實，要填 fact_id（用下面「現有事實」嘅 id）；
  如果用戶係糾正之前講錯嘅嘢，correction 填 true
- no_change：唔使輸出（省略）
健康、家庭矛盾、財務、情緒困擾、喪親等內容，sensitive 填 true。
feeling、grief 嘅內容一般都係 sensitive。

summary 只寫中性、日常嘅內容（例如做過咩、去過邊、同邊個見面）。
健康、家庭矛盾、財務、情緒困擾、喪親呢類敏感內容唔好寫入 summary；
需要記嘅話放入 facts，sensitive 填 true。冇中性內容就填空字串。

只輸出一個 JSON 物件，格式：
{"summary": "≤150字，第三身描述今次傾咗咩",
 "safety_concern": false,
 "facts": [{"op": "add|update", "fact_id": "", "category": "",
   "key": "簡短標題", "value": "", "quote": "", "sensitive": false,
   "correction": false}],
 "followups": [{"description": "", "due_date": "YYYY-MM-DD", "quote": ""}]}
```

## 附录 C：「唔好記住」确认句 `functions/prompts/memory_forget_ack.v2.txt`（原文，开关 `forgetAckReply` 开时才用）

```text
[對方啱啱要求你唔好記住頭先講嘅嘢]
用下面呢句說話確認，一字不改，唔好加其他說話：「好，今次傾嘅嘢我唔會記住。你想講乜照講，我會留心聽。」
之後唔好再主動提返呢件事。
```

## 附录 D：本次核对读过的代码

`functions/memory.js`、`functions/memory_forget.js`、`functions/safety_lexicon.js`、`functions/index.js`（`resolvePrompt`、`stripPII`、`proxyDeepSeek`、`memoryEndSession`、`memorySweep`、`memoryFactDeleted`／`memoryFollowupDeleted`）、`functions/llm_log.js`、`functions/llm_flags.js`、`functions/researcher_intake.js`、`functions/prompts/memory_extraction.v2.txt`、`.v3.txt`、`memory_forget_ack.v2.txt`、`siu_yan_v1.txt`、`ah_jan_ah_bak_v1.txt`、`tung_tung.v2.txt`、`firestore.rules`、`tool/prelaunch_config.js`；App：`lib/core/memory/memory_v1_service.dart`、`memory_mode.dart`、`lib/core/agent_context/rolling_summary_compiler.dart`、`agent_context_service.dart`、`intake_memory_seeder.dart`、`lib/core/agents/persona_resolver.dart`、`lib/core/session/chat_session_recorder.dart`、`idle_session_timer.dart`、`lib/app/app.dart`、`lib/core/llm/agent_greeting_service.dart`、四个聊天页、`lib/features/memory/presentation/pages/remembered_page.dart`、`lib/features/settings/presentation/pages/settings_page.dart`。测试：`functions/test/memory_test.js`、`memory_emulator_test.js`、`memory_acceptance_emulator_test.js`、`memory_layers_emulator_test.js`、`test/memory_v1_client_test.dart`（只读了名字，没有重跑）。
