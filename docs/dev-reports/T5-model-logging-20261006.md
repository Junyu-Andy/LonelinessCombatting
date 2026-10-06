# T5 模型版本记录（C04）报告

- 日期：2026-10-06
- 分支：`feature/model-logging`（PR 草稿，未合并，SPEC:C04）
- 决策记录：`docs/decisions/0016-log-every-llm-call-model.md`

## 结论

- 服务器上调用 DeepSeek 的地方只有 3 处代码（`proxyDeepSeek`、`referralJudgement`、记忆抽取）。App 里所有 LLM 功能都经过这 3 处。
- 现在这 3 处都改为走同一个函数 `deepSeekChat`（`functions/llm_log.js`），每次调用后在顶层集合 `llm_calls` 写一条。出错也写。不存 prompt 和回复原文。
- 规则组在服务器防线处就被拒绝，到不了 DeepSeek，所以不产生任何记录。代码里没有给规则组用的「安全标记」类 LLM 调用（5-flag 是正则，不是 LLM，见下文）。
- 测试：模拟器上 15 项全部通过，覆盖每一类调用、出错、规则组零记录；Firestore 规则测试确认 App 不能读写 `llm_calls`。
- **真实返回的 `model` 值未在本环境验证**（本环境没有 DeepSeek 密钥，也连不到 api.deepseek.com；测试用的是假响应）。

## 1. 调用 LLM 的地方

### 1.1 服务器端（真正发请求的地方）

| # | 位置 | 触发 | 用途 | 分组防线 | `call_type` |
|---|---|---|---|---|---|
| 1 | `functions/index.js` `proxyDeepSeek`（约第 274 行；请求在约第 335 行） | App 调用 | 所有对话、问候、总结、周小结、「問下呢篇」等 | `assertLlmAllowed`（约第 288 行），规则组拒绝 | 按 `moduleId` 推出，见 1.2 |
| 2 | `functions/index.js` `referralJudgement`（约第 434 行；请求在约第 515 行） | App 调用（`lib/core/cross_referral/referral_routing_service.dart` 约第 153 行） | 跨陪伴者转介第二层判断 | `assertLlmAllowed`（约第 446 行） | `referral_judgement` |
| 3 | `functions/index.js` `callDeepSeekJsonFor`（约第 1321 行），由 `memoryEndSession`（约第 1347 行）和 `memorySweep`（约第 1374 行）调用 | 离开聊天页；每 15 分钟补扫 | 记忆 v1 抽取（摘要、事实、跟进） | `memory.memoryActive` / `inScope`（`functions/memory.js` 约第 538、553 行）排除规则组；`memorySweep` 另外跳过 `arm == "B"` | `memory_extraction` |

其他外部服务不是 LLM，不记：`webSearch`（Brave 搜索）、`transcribeAudio`（Google 语音转文字）。

### 1.2 App 端（都经 `LlmGateway` → `proxyDeepSeek`）

App 只有一个入口 `lib/core/llm/llm_gateway.dart`（约第 432 行 `httpsCallable('proxyDeepSeek')`）。各功能用 `moduleId` 区分，服务器据此填 `call_type`（`functions/llm_log.js` `callTypeForModule`）：

| 功能 | 文件（约行号） | `moduleId` | `call_type` | App 是否传 `agentId` |
|---|---|---|---|---|
| 小欣签到对话 | `lib/features/context/presentation/pages/check_in_arm_a.dart`（519） | `m2_check_in` | `chat` | 是 |
| 阿珍/阿伯回忆对话 | `lib/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart`（424） | `m3_reminiscence_w{N}` | `chat` | 是 |
| 回忆开场 | 同上（256） | `m3_reminiscence_w{N}_opener` | `chat` | 否 |
| 回忆结束总结 | 同上（623） | `m3_reminiscence_w{N}_summary` | `session_summary` | 否 |
| 阿珍/阿伯自由对话 | `lib/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart`（245、471） | `reflective_dialogue` | `chat` | 是 |
| 通通闲聊 | `lib/features/curious_companion/presentation/pages/tung_tung_page.dart`（386） | `tung_tung_chat` | `chat` | 是 |
| 「問下呢篇」 | `lib/features/education/presentation/pages/education_article_page.dart`（100） | `m8_education_<文章id>` | `article_qa` | 否 |
| 每周小结（进度页） | `lib/features/progress/presentation/pages/progress_page.dart`（104） | `m9_progress_summary` | `weekly_summary` | 否 |
| 行动计划总结 | `lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart`（192） | `m7_action_loop_summary` | `session_summary` | 否 |
| 行动计划跟进回复 | `lib/features/action_loop/presentation/pages/action_loop_followup_page.dart`（100） | `m7_action_loop_followup` | `chat` | 否 |
| 社交活动建议 | `lib/features/social_suggestions/presentation/pages/social_suggestions_page.dart`（102） | `m6_suggestions` | `suggestions` | 否 |
| 首页个性化问候 | `lib/core/llm/agent_greeting_service.dart`（124） | `greeting_<agent>` | `greeting` | 是 |
| 记忆 v0 滚动摘要 | `lib/core/agent_context/rolling_summary_compiler.dart`（110） | `rolling_summary_fold` | `memory_summary` | 是 |

App 没传 `agentId` 的调用，`llm_calls.agent_id` 为 null。没有在服务器上按 `moduleId` 猜 agent。

### 1.3 安全标记

- 「5-flag」（`functions/llm_flags.js` `computeLlmFlags`）是纯正则，**不调用 LLM**。在 `proxyDeepSeek` 里对回复计算，没有单独的请求。
- App 的安全词库 `lib/core/safety/distress_detector.dart` 在本地运行，不调用 LLM。
- 记忆 v1 的安全词检查（`functions/memory.js` `hitsSafety`）也是正则。
- 所以代码里没有「安全标记类的 LLM 调用」，两组都没有。规则组因此没有任何需要记的非生成调用。

## 2. 日志字段

集合：顶层 `llm_calls/{自动 id}`，每次调用一条。写入：`functions/llm_log.js` `deepSeekChat` → `buildLogRow`。

| 字段 | 类型 | 含义 |
|---|---|---|
| `ts` | Timestamp | 发出请求的时间（Firestore Timestamp，即 UTC） |
| `call_type` | string | `chat` / `greeting` / `session_summary` / `weekly_summary` / `article_qa` / `suggestions` / `memory_summary` / `referral_judgement` / `memory_extraction` |
| `agent_id` | string 或 null | `siu_yan` / `ah_jan_ah_bak` / `tung_tung`；转介判断记发起方；App 没传时为 null |
| `uid` | string | 研究编号。代码里没有单独的研究编号，各集合都用 Firebase uid 作参与者编号（如 `lib/core/session/chat_session_recorder.dart` 的 `participantId`），这里沿用 |
| `model_requested` | string | 请求体里的模型名，目前都是 `deepseek-chat` |
| `model_returned` | string 或 null | DeepSeek 响应里的 `model` 字段；出错时为 null |
| `prompt_tokens` | number 或 null | 响应 `usage.prompt_tokens` |
| `completion_tokens` | number 或 null | 响应 `usage.completion_tokens` |
| `latency_ms` | number | 从发请求到读完响应的毫秒数 |
| `error` | boolean | 网络失败、非 2xx、响应无法解析时为 true |

- 不存 prompt、回复原文、`moduleId`、HTTP 状态码。
- 写入失败只打服务器日志，不影响老人收到回复（`deepSeekChat` 里的 try/catch）。
- 规则：`firestore.rules` 新增 `match /llm_calls/{callId} { allow read, write: if false; }`，App 不能读写；服务器用管理员权限写。
- 原来 App 写进 `turns` 的 `model` 保持不变（`proxyDeepSeek` 仍把 `model` 返回给 App）。

## 3. 测试结果

运行：`tool/ci_backend_tests.sh`（Java 21，firebase-tools 15.32.1，Firestore 模拟器）。全部通过。

| 测试 | 内容 | 结果 |
|---|---|---|
| `functions/test/llm_log_test.js`（新，无需模拟器） | `moduleId` → `call_type` 映射；成功一条、字段齐全、不含原文；非 2xx 记 `error: true`；网络失败记录后再抛出；写日志失败不影响调用 | 5/5 |
| `functions/test/llm_calls_emulator_test.js`（新，模拟器） | 直接运行真实的函数（`proxyDeepSeek` 10 种 `moduleId`、`referralJudgement`、`memoryEndSession`、`memorySweep`），DeepSeek 用假响应（替换 `fetch`，返回带 `model` 字段）；每类各写一条，字段和值正确，不含原文；上游 500 记 `error: true`；规则组从所有入口调用都被拒，DeepSeek 没被调用，`llm_calls` 零条 | 15/15 |
| `test/rules/llm_calls_rules.test.js`（新，规则） | 本人不能读自己的记录；任何客户端不能新建、覆盖、删除；未登录也不能读 | 3/3（规则测试共 34 项通过） |
| 原有测试 | `arm_test`、`llm_flags_test`、`memory_test`、`arm_emulator_test`、`memory_emulator_test`、其余规则测试 | 全部通过 |

Lint（`functions/` 的 `npx eslint .`）：

- 新文件 `llm_log.js` 和两个新测试 0 个问题。
- 整个 `functions/` 本来就有约 1000 个格式错误（见 `docs/dev/backlog.md` 第 4 节）：改动前 1022 个，改动后 1013 个。`index.js` 改动的行只有缩进类错误，和周围原有代码的缩进一致。
- 没有用 `??`、`?.`。

没有跑 Flutter 测试：这次没有改 App 代码。

## 4. 没做的和限制

- **真实返回的 `model` 值未在本环境验证。** 本环境没有 DeepSeek 密钥，也连不到 api.deepseek.com。代码按 OpenAI 兼容格式读响应顶层的 `model` 和 `usage`（推断：和现有 `proxyDeepSeek` 返回 `data.model` 的写法一致）。部署后建议先看几条真实记录。
- `llm_calls` 没有加进盲法导出 `blindedDataExport`（`functions/index.js` 约第 1114 行 `_EXPORT_BLINDED_COLLECTIONS`）。已记入 backlog 第 21 项。
- 代码里未找到删除用户数据的脚本或函数，所以 `llm_calls` 也没有删除逻辑。已记入 backlog 第 21 项。
- 每次调用多一次 Firestore 写入（推断：几十毫秒），在回复返回前完成。

## 5. 改动的文件

- `functions/llm_log.js`（新）：`deepSeekChat`、`callTypeForModule`、`buildLogRow`
- `functions/index.js`：3 处 DeepSeek 请求改走 `deepSeekChat`；`callDeepSeekJson` 改为 `callDeepSeekJsonFor(uid, agentId)`
- `firestore.rules`：`llm_calls` 客户端禁止读写
- 测试：`functions/test/llm_log_test.js`、`functions/test/llm_calls_emulator_test.js`、`test/rules/llm_calls_rules.test.js`、`test/rules/package.json`、`test/rules/README.md`
- 文档：`docs/decisions/0016-log-every-llm-call-model.md`、`docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`、`docs/history.md`、`docs/dev/backlog.md`、本报告

## 要带回研究侧的发现

### (1) 与登记表 C01–C22 不一致的地方

- **C04**：登记表写「每次调用记录返回的 `model` 字段和时间」。改动前只有 App 在 `turns` 里记了 `model`，记忆抽取和转介判断没有记。本 PR 之后服务器每次调用都记（`llm_calls`），登记表的「记录写在哪个集合、字段名」可以填 `llm_calls`，字段见第 2 节。
- **C12**：登记表写 Hybrid 组有「5-flag LLM 标记」。代码里 5-flag 是正则（`functions/llm_flags.js`），不调用 LLM，而且是「LLM 独有机制」的测量标记，不是安全标记。名称容易误解，建议研究侧核对这一项的定义。
- **C11**：每周小结由 App 进度页调用（`m9_progress_summary`），不是服务器定时生成。会被记录，但 `agent_id` 为 null。

### (2) 会影响 ICF、DMP、研究方案的事实

- `llm_calls` 是新的研究数据集合，含 Firebase uid，不含对话原文。DMP 需要写明：存在哪里（Firestore，与其他数据同一项目）、保存多久、退出研究时是否删除。
- 研究方案 / 论文 Methods 可以写：「每次调用记录 DeepSeek 返回的模型标识、token 数和延迟」。模型版本无法锁定，建议在局限中说明。
- 规则组不产生任何 LLM 调用记录，可作为「规则组零 LLM 调用」的保真度证据。
- 约 7 处调用 App 没有传 `agentId`（见 1.2 表），这些记录只能按 `call_type` 分析，不能按陪伴者分。如需按陪伴者分，要改 App（另开任务）。
