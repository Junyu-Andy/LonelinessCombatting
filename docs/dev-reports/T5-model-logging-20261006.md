# T5 模型版本记录（C04）报告

- 日期：2026-10-06
- 分支：`feature/model-logging`（PR 草稿，未合并，SPEC:C04）
- 决策记录：`docs/decisions/0016-log-every-llm-call-model.md`（本 PR）；模型名见 `docs/decisions/0017-deepseek-flash-thinking-off.md`（PR #29，已合并进本分支）

## 结论

- 服务器上调用 DeepSeek 的地方只有 3 处代码（`proxyDeepSeek`、`referralJudgement`、记忆抽取）。App 里所有 LLM 功能都经过这 3 处。
- 现在这 3 处都改为走同一个函数 `deepSeekChat`（`functions/llm_log.js`），每次调用后在顶层集合 `llm_calls` 写一条。出错也写。不存 prompt 和回复原文。
- 规则组在服务器防线处就被拒绝，到不了 DeepSeek，所以不产生任何记录。代码里没有给规则组用的「安全标记」类 LLM 调用（5-flag 是正则，不是 LLM，见下文）。
- 每次请求都有超时（比所在函数的时限短），超时也记一条。写日志最多等 2 秒，不耽误回复。
- 测试：模拟器上 16 项全部通过，覆盖每一类调用、出错、规则组零记录、每个请求都带 `deepseek-flash` 和思考关闭；Firestore 规则测试确认 App 不能读写 `llm_calls`。
- **真实调用已验证（2026-10-06）**：最初代码请求 `deepseek-chat`，DeepSeek 返回的 `model` 是 **`deepseek-flash`**，两个名字不同。之后负责人决定直接请求 `deepseek-flash` 并关闭思考（决策 0017，已合并进本分支），现在请求和返回都是 `deepseek-flash`。日志把两个名字分开记，以后如果再不一致，能看出来。

## 1. 调用 LLM 的地方

### 1.1 服务器端（真正发请求的地方）

| # | 位置 | 触发 | 用途 | 分组防线 | `call_type` |
|---|---|---|---|---|---|
| # | 位置 | 触发 | 用途 | 分组防线 | `call_type` | 请求超时 |
|---|---|---|---|---|---|---|
| 1 | `functions/index.js` `proxyDeepSeek`（约第 283 行；请求在约第 344 行） | App 调用 | 所有对话、问候、总结、周小结、「問下呢篇」等 | `assertLlmAllowed`（约第 297 行），规则组拒绝 | 按 `moduleId` 推出，见 1.2 | 50 秒（函数时限 55 秒） |
| 2 | `functions/index.js` `referralJudgement`（约第 446 行；请求在约第 527 行） | App 调用（`lib/core/cross_referral/referral_routing_service.dart` 约第 153 行） | 跨陪伴者转介第二层判断 | `assertLlmAllowed`（约第 458 行） | `referral_judgement` | 17 秒（函数时限 20 秒） |
| 3 | `functions/index.js` `callDeepSeekJsonFor`（约第 1335 行），由 `memoryEndSession`（约第 1365 行）和 `memorySweep`（约第 1392 行）调用 | 离开聊天页；每 15 分钟补扫 | 记忆 v1 抽取（摘要、事实、跟进） | `memory.memoryActive` / `inScope`（`functions/memory.js` 约第 538、553 行）排除规则组；`memorySweep` 另外跳过 `arm == "B"` | `memory_extraction` | 45 秒（`memoryEndSession` 时限 60 秒，前后还有 Firestore 读写；`memorySweep` 时限 300 秒） |

三处的请求体都用 `functions/index.js` 顶部的常量 `DEEPSEEK_MODEL`（`deepseek-flash`）和 `DEEPSEEK_THINKING`（思考关闭），见决策 0017。DeepSeek 的网址只在 `functions/llm_log.js` 出现一次，`functions/test/deepseek_request_test.js` 检查这一点。

其他外部服务不是 LLM，不记：`webSearch`（Brave 搜索）、`transcribeAudio`（Google 语音转文字）。

`tool/agent_prompt_bench.py` 是开发者在本地调 prompt 用的工具，直接调用 DeepSeek，不经过服务器，不涉及参与者，所以不记日志。它现在仍请求 `deepseek-chat`（第 131 行），没有跟着决策 0017 改。

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
| `agent_id` | string 或 null | 只接受 `siu_yan` / `ah_jan_ah_bak` / `tung_tung`（`functions/memory.js` 的 `AGENTS`），其他值和 App 没传时都存 null；转介判断记发起方 |
| `uid` | string | 研究编号。代码里没有单独的研究编号，各集合都用 Firebase uid 作参与者编号（如 `lib/core/session/chat_session_recorder.dart` 的 `participantId`），这里沿用 uid 原值，没有另外编码 |
| `model_requested` | string | 从实际发出的请求体 `body.model` 读，不写死。现在请求 `deepseek-flash`，思考关闭（决策 0017） |
| `model_returned` | string 或 null | DeepSeek 响应里的 `model` 字段；出错时为 null |
| `system_fingerprint` | string 或 null | 响应里的 `system_fingerprint`。同一个模型名背后换了模型时它会变，用来发现悄悄更换（`docs/dev/memory-and-entry-spec.md` 8.2 第 1 条）。实测有值 |
| `prompt_tokens` | number 或 null | 响应 `usage.prompt_tokens` |
| `completion_tokens` | number 或 null | 响应 `usage.completion_tokens` |
| `reasoning_tokens` | number 或 null | 响应 `usage.completion_tokens_details.reasoning_tokens`。大于 0 说明开了思考模式。响应里没有这一项时存 null（2026-10-06 实测：请求 `deepseek-chat` 和 `deepseek-flash` + 思考关闭时都没有） |
| `http_status` | number 或 null | DeepSeek 返回的 HTTP 状态码；网络失败、超时时为 null |
| `latency_ms` | number | 从发请求到读完响应的毫秒数 |
| `error` | boolean | 网络失败、超时、非 2xx、响应无法解析时为 true |

- 不存 prompt、回复原文、`moduleId`。
- 写日志最多等 2 秒（`LOG_WRITE_TIMEOUT_MS`）。超时或失败只打服务器日志，不影响老人收到回复（`functions/llm_log.js` `writeLog`）。超时后写入本身没有取消，多数情况下仍会落库（推断）。
- 规则：`firestore.rules` 新增 `match /llm_calls/{callId} { allow read, write: if false; }`，App 不能读写；服务器用管理员权限写。
- 原来 App 写进 `turns` 的 `model` 保持不变（`proxyDeepSeek` 仍把 `model` 返回给 App）。

## 3. 测试结果

运行：`tool/ci_backend_tests.sh`（Java 21，firebase-tools 15.32.1，Firestore 模拟器）。全部通过。

| 测试 | 内容 | 结果 |
|---|---|---|
| `functions/test/llm_log_test.js`（新，无需模拟器） | `moduleId` → `call_type` 映射；成功一条、字段齐全、不含原文；非 2xx 记 `error: true`；网络失败记录后再抛出；写日志失败不影响调用；`system_fingerprint`、`reasoning_tokens` 有就存、没有存 null；`model_requested` 取自请求体；200 但响应不是 JSON 记 `error: true`；请求超时被中止并记录；写日志卡住时不耽误返回；不认识的 `agent_id` 存 null | 10/10 |
| `functions/test/llm_calls_emulator_test.js`（新，模拟器） | 直接运行真实的函数（`proxyDeepSeek` 10 种 `moduleId`、`referralJudgement`、`memoryEndSession`、`memorySweep`），DeepSeek 用假响应（替换 `fetch`，返回 `deepseek-flash`、`system_fingerprint`）；每类各写一条，字段和值正确（`model_requested` 等于 `index.js` 里的 `DEEPSEEK_MODEL`），不含原文；每个请求都带 `deepseek-flash`、`thinking: {type: "disabled"}` 和超时；上游 500 记 `error: true`、`http_status` 500；规则组从所有入口调用都被拒，DeepSeek 没被调用，`llm_calls` 零条 | 16/16 |
| `functions/test/deepseek_request_test.js`（来自 PR #29，本 PR 改写，无需模拟器） | `index.js` 不再直接出现 DeepSeek 网址；`llm_log.js` 恰好出现 1 次；每个 `llmLog.deepSeekChat(` 的请求体都有 `model: DEEPSEEK_MODEL,` 和 `thinking: DEEPSEEK_THINKING,`；服务器代码不请求 `deepseek-chat` | 通过（3 处调用） |
| `test/rules/llm_calls_rules.test.js`（新，规则） | 本人不能读自己的记录；任何客户端不能新建、覆盖、删除；未登录也不能读 | 3/3（规则测试共 34 项通过） |
| `functions/test/llm_live_smoke.js`（新，**手动跑，不在 CI 里**） | 真实调用 DeepSeek 一次（一句合成英文，`max_tokens` 5，和服务器一样请求 `deepseek-flash`、思考关闭），经 `deepSeekChat` 写日志再读回。不用模拟器跑 1 次、模拟器里跑 3 次，都通过：`model_requested` = `model_returned` = `deepseek-flash`，`system_fingerprint` = `aeb56401ca74e127821c4f9126dcb669`，`reasoning_tokens` = null，`http_status` = 200。合并 0017 之前请求 `deepseek-chat` 时，返回的也是 `deepseek-flash`、同一个指纹 | 通过 |
| 原有测试 | `arm_test`、`llm_flags_test`、`memory_test`、`arm_emulator_test`、`memory_emulator_test`、其余规则测试 | 全部通过 |

Lint（`functions/` 的 `npx eslint .`）：

- `llm_log.js` 和所有新增、改写的测试（含 `deepseek_request_test.js`）0 个问题。
- 整个 `functions/` 本来就有约 1000 个格式错误（见 `docs/dev/backlog.md` 第 4 节）。现在 1018 个：`index.js` 953 个，比 PR #29 分支单独的 959 个少；`llm_flags.js` 和它的测试 65 个，都是原有的。`index.js` 改动的行只有缩进类错误，和周围原有代码的缩进一致。
- 没有用 `??`、`?.`。

没有跑 Flutter 测试：这次没有改 App 代码。

**怎么手动跑真实调用的冒烟测试**（在 `functions/` 目录）：

```bash
# 有真实密钥时
DEEPSEEK_API_KEY=<密钥> node test/llm_live_smoke.js

# Claude Code 云端会话：代理会自动换上真实密钥，代码里用占位值；
# Node 原生 fetch 要加 NODE_USE_ENV_PROXY=1 才走代理
NODE_USE_ENV_PROXY=1 DEEPSEEK_API_KEY=placeholder node test/llm_live_smoke.js

# 想确认真的写进 Firestore：在仓库根目录用模拟器跑
firebase emulators:exec --only firestore --project loneliness-pilot-dev \
  "cd functions && NODE_USE_ENV_PROXY=1 DEEPSEEK_API_KEY=placeholder node test/llm_live_smoke.js"
```

文件名不以 `_test.js` 结尾，所以 `tool/ci_backend_tests.sh` 不会跑它（CI 没有密钥）。它只打印日志那一行，不打印密钥。

这个脚本一开始就写 Firestore，第一次写入是「冷」的。在模拟器里有一次超过了 2 秒上限，读回时没找到记录。所以脚本把写日志的上限放宽到 15 秒。服务器上的三个函数在调用 DeepSeek 之前都已经读过 Firestore（查分组、读记忆），写入时连接已经建好（推断：不会碰到冷启动的慢写入）。

## 4. 没做的和限制

- 真实调用只在本环境用 `llm_live_smoke.js` 验证过 `deepSeekChat` 这一层；部署后的 `proxyDeepSeek` 等函数没有对真实 DeepSeek 跑过（函数层用的是假响应）。部署后建议先看几条真实记录。
- `llm_calls` 没有加进盲法导出 `blindedDataExport`（`functions/index.js` 约第 1114 行 `_EXPORT_BLINDED_COLLECTIONS`）。已记入 backlog 第 21 项。
- 代码里未找到删除用户数据的脚本或函数，所以 `llm_calls` 也没有删除逻辑。已记入 backlog 第 21 项。
- 每次调用多一次 Firestore 写入（推断：几十毫秒），在回复返回前完成，最多等 2 秒。
- 写日志超过 2 秒就不等了。这时记录可能稍后才落库，函数实例回收的话也可能丢失（推断，没有在部署环境测过）。

## 5. 改动的文件

- `functions/llm_log.js`（新）：`deepSeekChat`、`writeLog`、`callTypeForModule`、`buildLogRow`
- `functions/index.js`：3 处 DeepSeek 请求改走 `deepSeekChat`，请求体用 `DEEPSEEK_MODEL` / `DEEPSEEK_THINKING`，各设超时；`callDeepSeekJson` 改为 `callDeepSeekJsonFor(uid, agentId)`
- 合并了 `claude/new-session-8awoah`（PR #29，决策 0017）
- `firestore.rules`：`llm_calls` 客户端禁止读写
- 测试：`functions/test/llm_log_test.js`、`functions/test/llm_calls_emulator_test.js`、`functions/test/llm_live_smoke.js`（手动）、`functions/test/deepseek_request_test.js`（改写）、`test/rules/llm_calls_rules.test.js`、`test/rules/package.json`、`test/rules/README.md`
- 文档：`docs/decisions/0016-log-every-llm-call-model.md`、`docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`、`docs/history.md`、`docs/dev/backlog.md`、本报告

## 要带回研究侧的发现

### (1) 与登记表 C01–C22 不一致的地方

- **C04**：登记表写「每次调用记录返回的 `model` 字段和时间」。改动前只有 App 在 `turns` 里记了 `model`，记忆抽取和转介判断没有记。本 PR 之后服务器每次调用都记（`llm_calls`），登记表的「记录写在哪个集合、字段名」可以填 `llm_calls`，字段见第 2 节。
- **C12**：登记表写 Hybrid 组有「5-flag LLM 标记」。代码里 5-flag 是正则（`functions/llm_flags.js`），不调用 LLM，而且是「LLM 独有机制」的测量标记，不是安全标记。名称容易误解，建议研究侧核对这一项的定义。
- **C11**：每周小结由 App 进度页调用（`m9_progress_summary`），不是服务器定时生成。会被记录，但 `agent_id` 为 null。

### (2) 会影响 ICF、DMP、研究方案的事实

- **模型名**：2026-10-06 实测，旧代码请求 `deepseek-chat`，返回的 `model` 是 `deepseek-flash`。统筹会话另外看到 DeepSeek 的 `/models` 列出的是 DeepSeek-V4.1-Flash（这一点本会话没有自己查）。现在已改为直接请求 `deepseek-flash`、思考关闭（决策 0017）。研究方案、注册和 ICF 里如果写的是「DeepSeek-V3」或「deepseek-chat」，需要核对措辞。
- **模型可能被悄悄更换**：现在每条记录都有 `system_fingerprint`（实测有值，两种请求方式下相同）。研究期间可以按日期看它有没有变，变了就查是不是换了模型、要不要记为 protocol deviation。它是否真的随模型升级变化，要等 DeepSeek 下一次升级才能确认。
- **思考模式**：`reasoning_tokens` 大于 0 就说明意外开了思考，可以据此检查。
- **研究编号是 Firebase uid 原值**：`llm_calls` 含 uid，不含对话原文。这是假名化的个人数据，DMP 需要写明：存在哪里（Firestore，与其他数据同一项目）、保存多久、退出研究时是否删除。
- **盲法**：只有 Hybrid 组会有 `llm_calls` 记录，有没有记录就等于暴露分组。揭盲前不能把这个集合原样导出给盲法人员（backlog 第 21 项）。
- 研究方案 / 论文 Methods 可以写：「每次调用记录 DeepSeek 返回的模型标识、token 数和延迟」。模型版本无法锁定，建议在局限中说明。
- 规则组不产生任何 LLM 调用记录，可作为「规则组零 LLM 调用」的保真度证据。
- 约 7 处调用 App 没有传 `agentId`（见 1.2 表），这些记录只能按 `call_type` 分析，不能按陪伴者分。如需按陪伴者分，要改 App（另开任务）。
