# 开发记录

按时间记下做过什么、讨论过什么。最新的在最上面。设计决定的理由见 `docs/decisions/`，参与者能感受到的改动见 `docs/STUDY_CHANGELOG.md`。

每次合并 PR 或做出决定后，在这里加一段。

---

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
