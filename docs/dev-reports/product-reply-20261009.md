# 给产品窗口的现状报告与核对（2026-10-09）

> 不是任务单里的 T22（T22 见 `docs/dev-tasks/dev-tasks-1008.md`）。由统筹会话写，回应产品窗口 10/8 交接（`交给开发窗口：10/7–10/8 已定事项`）第一节、10/9 第 1–3 条，以及产出窗口 10/7–10/8 带回事项 24 条。
> 只读代码，main @ `5f52416`。每条附文件路径。

## 结论

1. **三份现状报告和 Hybrid 两个模块的流程都在下面。**Hybrid 模块的"有效会话"条件，我的提议见第四节，请主窗口确认。
2. **语音不能只是"核对"，要开发**：服务器有 Google STT v2 转写函数，但 App 不用它，用的是手机系统自带的识别。另一个上传录音的分支早已合进 main，现在 main 上没有"录音上传"的代码，要新做。
3. **产出窗口的 24 条里，有 3 条和 10/9 第 1、3 条冲突**（第 17、18 条要求盲法导出包含 Brief PR 和每人会话数；第 10 条的有效会话定义没有模块那一档），见第六节。

## 一、三位陪伴者的记忆怎样读写和共享

**两套记忆，按人分**（`lib/core/memory/memory_mode.dart` 第 28–40 行；`docs/dev/architecture.md` 第 7 节）：

| | v1（服务器） | v0（App） |
|---|---|---|
| 谁用 | Phase B Hybrid 组（`arm == A` 且 `armAssignmentMode == randomise`）；测试包里自愿开启的人 | Phase A 和试用账号（Phase B 规则组两套都没有） |
| 存在哪里 | Firestore `users/{uid}/mem_facts`、`mem_summaries`、`mem_followups`；抽取记录 `mem_extractions`、注入日志 `mem_injections` | Firestore `users/{uid}/agent_contexts/{agentId}`：每位陪伴者一段 ≤500 字滚动摘要和对话缓冲区 |
| 什么时候写 | 会话结束时 App 调 `memoryEndSession`（离开聊天页时，`lib/core/agent_context/rolling_summary_compiler.dart` 第 57–60 行）；漏掉的由 `memorySweep` 每 15 分钟补，条件是 30 分钟没有新消息（`functions/index.js` 第 1644–1660 行）。**不等 Brief PR**：签到页先存记忆再弹 Brief PR（`lib/features/context/presentation/pages/check_in_arm_a.dart` 第 826–840、894 行） | 同一时刻，App 自己用 DeepSeek 把缓冲区折进摘要 |
| 写什么 | 会话摘要、8 类事实（称呼、家人、居住等）、带日期的待跟进。安全命中的轮次、"唔好記住"的整段、敏感摘要不写（决策 0024） | 一段摘要：傾過咩、心情走势、唔好提嘅嘢、未傾完嘅線索 |
| App 只缓冲最后 10 轮 | `lib/core/agent_context/agent_context_service.dart`（T16 报告第 5 条） | 同左 |

**谁能读到谁的**（v1，`functions/memory.js` 第 67、473–479 行）：
- 每位陪伴者都能读自己写的全部条目。
- 别的陪伴者写的：敏感条目一律读不到；普通条目只在策略 C 下、且属于"称呼、家人、居住"三类时共享（`SHARED_CATEGORIES`）。
- 会话摘要和待跟进只给写它的陪伴者（第 525 行；`selectForInjection` 里待跟进按 `agent_id` 过滤）。
- 老人关闭了共享同意（`consent.sharedContextUse` 不是 true）时，策略降为 B，什么都不共享（`effectivePolicy`，第 680 行起；决策 0020）。

**v0 的跨陪伴者通道**：小欣签到把阿珍最近几周的回忆摘要放进 prompt；共享同意关时跳过（`check_in_arm_a.dart` 第 465–530 行）。

**老人能看能改的**：「我記得嘅嘢」页面可以看、确认敏感条目、删单条（`lib/features/memory/` 下的 remembered 页面；删一条会连带删同措辞条目和对应摘要，决策 0024）。**App 内没有"关闭记忆"或"全部删除"的入口**：Phase B Hybrid 组强制开启（决策 0007），撤回只能由研究团队跑 `tool/delete_memory.js`，之后写 `memoryWithdrawnAt`、不再记录（`functions/memory.js` 第 709 行附近）。

## 二、Brief PR 记录现有字段，对照 R4

按 10/9 第 1 条：数据收集期间盲法导出**不含** Brief PR 和每人会话数（维持决策 0021），R4 的字段只进非盲导出和锁库后的分析导出。所以这里对照的是 Brief PR 记录本身。

现有字段（`lib/features/brief_pr/data/brief_pr_response.dart` 第 68–80 行）：`schemaVersion`、`agentId`、`agentDisplayName`、`sessionRef`、4 题分数、`isAnchorPrompt`、`status`、`promptedAt`、`respondedAt`、`arm`。

| R4 要的 | 现状 | 缺什么 |
|---|---|---|
| 参与者编号 | 存在 `users/{uid}/brief_pr` 下，只有 uid；研究编号在 `research_id_map` | 导出时要换成研究编号 |
| 会话编号 | `sessionRef` | 有 |
| 陪伴者编号 | `agentId` | 有 |
| 会话结束时间 | 没有（在 `sessions` 里） | **缺** |
| 邀请时间、评分时间 | `promptedAt`、`respondedAt` | 有 |
| 邀请方式（列表页 / 补问） | 没有，现在是弹窗 | **缺**（新流程） |
| 最终状态五选一、"曾展示" | `status` 只有 completed / skipped 等旧值 | **缺**（R3） |
| 4 题分数（不敏感题原始分） | 有，原始分 | 有 |
| 每人每周有效会话数 | 没有"有效会话"概念；`usage_weekly` 按旧会话计 | **缺**（R1） |
| 全体合并的完成率（不分人、不分组） | 没有 | **缺**（10/9 第 1 条） |

盲法导出现在的处理：`functions/blinding.js` 第 192 行起，`brief_pr` 只在 `meta/blinding_config.includeBriefPr` 打开时导出，默认关，正好符合 10/9 第 1 条。

## 三、语音输入（STT）现状

| 项目 | 现状 | 文件 |
|---|---|---|
| App 用什么识别 | **手机系统自带的语音识别**（`speech_to_text` 插件），`_onDeviceOnly = false`，允许系统送去手机厂商或 Google 的云端。**不经过我们的服务器** | `lib/core/voice/voice_input_button.dart` 第 5、135、312 行 |
| 服务器转写函数 | `transcribeAudio`：Google Cloud Speech-to-Text **v2**，粤语 `yue-Hant-HK`。第一档 `chirp_2` / `asia-southeast1`；失败退第二档 `long` / `global`。App 现在没有调用它 | `functions/index.js` 第 815–900 行 |
| 另一个分支 | `phase-b/google-cloud-stt` 的提交**已全部在 main 里**。注释提到的"录音上传"版本，现在 main 上没有对应代码，要新做 | `git merge-base` 核对；`voice_input_button.dart` 第 456–457 行注释 |
| 有没有存录音 | 现在的 App 不录音（交给系统识别），也没有写文件或上传 Storage 的代码；服务器函数收 `audioBase64`，转写后只回文字，代码里没有写 Storage 或日志 | 同上 |
| Google 是否保留音频 | 由 Google Cloud 项目的"数据记录"（data logging）设置决定，**代码里看不出**，要有项目权限的人在控制台核对 | — |
| 转写文字的安全流程 | 识别结果填进输入框（第 298–304 行），老人按发送后和打字走同一条路径（统一安全入口 `SafetyService`，决策 0018）。改成服务器转写后也要保持这样 | `lib/core/safety/safety_check.dart` |
| 开关 | `app_config/feature_flags.voiceInputEnabled` 默认关，两期共用一份（T21 要分开） | `docs/dev-reports/T9-flags-20261007.md` |

## 四、Hybrid 组小欣签到和阿珍回忆现在的流程，以及有效会话的提议

### 小欣签到（Hybrid，`lib/features/context/presentation/pages/check_in_arm_a.dart`）

- **是聊天，不是表单。**进入时如果今天没记心情，先选心情脸（必选），然后小欣按心情开口，之后是普通 LLM 对话；中途可能出现"给想法起名"的邀请卡（第 98–104、144–147 行）。
- **没有"完成"按钮**：离开页面就算完成签到，条件是老人至少发过 1 条消息。离开时存签到记录、写记忆，提示"今日 check-in 完成 ✓"（第 850–880 行）。
- **Brief PR**：离开后，本次会话老人发言 ≥ 2 轮（`briefPRMinTurns`）且不是危机结束才弹（第 885–905 行）。

### 阿珍回忆（Hybrid，`lib/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart`）

- **是聊天，带固定的开头和结尾**：本周主题开场问题（LLM 生成，带入前几周内容）→ 老人讲、阿珍追问 → 右上角"今日講到呢度"→ LLM 生成小结 → 老人可改 → 按"儲存"（第 34–40、610–700、805–850 行）。
- **完成**：按"儲存"后写进 `memory/m3_reminiscence/sessions/week_N`，并写记忆。没按"儲存"就离开，也会结束会话、可能弹 Brief PR，但这周的回忆没存。
- **Brief PR**：同签到，发言 ≥ 2 轮且不是危机结束。

### 提议：Hybrid 模块的"完成该模块流程"

| 模块 | 提议的完成条件 | 理由 |
|---|---|---|
| 小欣签到 | **心情已记录 + 老人至少发 1 条消息并收到小欣的回复** | 和现在"离开就算完成"的门槛一致，也对应规则组"必填项（心情和 3 道选择题）填完、提交、看到回应" |
| 阿珍回忆 | **按"儲存"保存了本周小结**（小结里至少有老人讲的 1 段话） | 这是流程的终点，对应规则组"写完、提交、看到回应" |

**两个要主窗口知道的地方：**
- 按这个提议，Hybrid 签到 1 条消息就有效，自由聊天要 3 条。两类门槛不同，是有意的（按"完成一个互动单元"）。
- **规则组"看到模板回应"现在做不到**：模板回应开关 `RULE_TEMPLATE_REPLIES` 默认关、41 条模板全是占位。关着时小欣 B 回固定一句"收到喇。聽日再見。"，阿珍 B 没有回应（`lib/features/context/presentation/pages/check_in_arm_b.dart` 第 164、274 行；`docs/dev-reports/T15-rule-based-replies-20261007.md`）。建议规则组的完成条件写成"提交后看到回应页（模板或固定句）"，等模板定稿后不用再改。

## 五、产出窗口 24 条逐条核对

| # | 要求 | 现状 | 怎么处理（"待排"= 还没进 1008/1009 任务单） |
|---|---|---|---|
| 1 | 每次 DeepSeek 调用记录模型，并写进会话记录 | 服务器每次调用写 `llm_calls`（含返回的模型、`system_fingerprint`），但**没有会话编号**；聊天轮次 `turns.llm.model` 由 App 写（`functions/llm_log.js`；`lib/core/session/chat_session_recorder.dart`） | 并入 待排（会话与 Brief PR）：`llm_calls` 加会话编号 |
| 2 | DeepSeek 是否仍经 Cloud Functions | 是。全部经 `proxyDeepSeek` 等函数，唯一请求处在 `functions/llm_log.js` | 无需改 |
| 3 | 搜一搜 Phase B 关 | 已关（`app_config/feature_flags.webSearchEnabled` 默认关，决策 0019）；按期分开在 T21 | T21 |
| 4 | App 内撤回记忆的入口 | 没有；只能删单条，撤回靠研究团队跑脚本（第一节） | **要主窗口定**：撤回方式（关闭 / 删单条 / 全部删除）写进登记表 C05 |
| 5 | 记忆存哪里；会话结束时写、不等问卷 | Firestore `users/{uid}/mem_*`；会话结束写，不等 Brief PR（第一节）。Firestore 所在区域要在控制台确认 | 待排（会话与 Brief PR） 按新会话结束规则对齐 |
| 6 | LoRA 两组都用，运行位置 | 接口已有（T8），两组共用，开关关，**没有模型**；运行位置未定（经 Cloud Function `classifySafety` 中转，模型地址待研究侧给） | 待排（LoRA 两组共用） |
| 7 | STT 模型、区域、数据记录、谁发送 | 第三节：`chirp_2` / `asia-southeast1`，退 `long` / `global`；数据记录要控制台核对；**现在是手机系统识别，不经服务器** | 待排（语音改走服务器） 改为经服务器 |
| 8 | 获批前关；只存文字不存录音 | 开关关（两期共用）；现在不录音 | T21 分期；待排（语音改走服务器） 保证不存 |
| 9 | 转写走同一套安全流程 | 是（填进输入框后同一路径） | 待排（语音改走服务器） 保持 |
| 10 | 会话定义 | 现在 10 分钟超时、离开页面结束、不分有效与否（`docs/dev/architecture.md` 第 6 节） | 待排（会话与 Brief PR）；有效会话按 10/9 第 3 条，**不是只按 3 条消息** |
| 11 | 会话记录字段 | 有会话编号、陪伴者、结束原因、结束时间；没有"是否有效"、"会话类型" | 待排（会话与 Brief PR） |
| 12–15 | Brief PR 新邀请规则和五种状态 | 现在是离开时弹窗，≥2 轮 | 待排（会话与 Brief PR） |
| 16 | 英文字段名写定后告诉产出窗口 | — | 待排（会话与 Brief PR） 写定后带回 |
| 17 | 会话和 Brief PR 字段按人导出，**盲法导出也要含** | — | **冲突**，见第六节；只进非盲导出 |
| 18 | 每人每周有效会话数，**盲法导出也要含** | — | **冲突**，见第六节 |
| 19 | 操纵检验抽样导出 | 没有 | 待排（操纵检验导出）（不卡上线） |
| 20 | 试跑编号前缀、试跑标记 | 没有；现在只有测试员 PIN 和 `pilot` cohort 的设想（决策 0011，未实现） | 待排（试跑支持） |
| 21 | 正式导出排除试跑；试跑单独导出，带每条消息的构建版本号，只含同意二次使用者 | 没有；`turns` 不记构建版本号 | 待排（试跑支持） |
| 22 | 测试配置把 W2、每周问卷、社会接触探针压到 7 天 | 有"日程模拟器"和远程参数（`app_config/phase_a` 的 `w2DayOffset` 等），但不覆盖所有环节 | 待排（试跑支持）；各环节第几天写进测试配置后带回 |
| 23 | 版本由 Keran 指定 | T19 只有按序列分配；没有手动指定组别的路径 | 待排（试跑支持）：试跑专用的指定组别入口，和正式分配分开、留日志 |
| 24 | 试跑日志：引导用时、Brief PR 完成率和每日邀请次数、闪退和重复提交 | 部分有（`events`、`sessions`）；没有闪退上报，没有引导用时统计 | 待排（试跑支持） |

## 六、冲突和要主窗口定的事

1. **盲法导出（第 17、18 条 ↔ 10/9 第 1 条）**：10/9 第 1 条定了数据收集期间盲法导出不含 Brief PR 和每人会话数。产出窗口第 17、18 条写"盲法导出也要包含"。我按 10/9 第 1 条做，请产出窗口改 B09、B12 的写法。另外，"W1–W4 有效会话总数用作敏感性分析的使用量"也只能来自非盲或锁库后的导出。
2. **有效会话定义（第 10 条 ↔ 10/9 第 3 条）**：按 10/9 第 3 条，模块按"完成流程"算，自由聊天按 3 条消息。Hybrid 模块的完成条件按第四节提议，请确认。
3. **规则组"看到模板回应"**：模板开关关着时没有模板，建议写成"看到回应页（模板或固定句）"（第四节）。
4. **记忆撤回方式**（第 4 条）：要主窗口定后写进登记表 C05。
5. **试跑的"指定版本"**（第 23 条）：试跑时由 Keran 手动指定组别，要和正式随机分配完全分开（不占序列位置、记录带试跑标记）。请确认试跑参与者不进入正式随机化。
6. **STT 失败退 global 区**：按 10/9 第 2(3) 条先保留、做成配置项，等主窗口定。
