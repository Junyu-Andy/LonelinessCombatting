# 开发记录

按时间记下做过什么、讨论过什么。最新的在最上面。设计决定的理由见 `docs/decisions/`，参与者能感受到的改动见 `docs/STUDY_CHANGELOG.md`。

每次合并 PR 或做出决定后，在这里加一段。

---

## 2026-10-07 盲法（T12，PR 草稿，未合并）

- 新版盲法导出：每人一个跨周不变的研究编号（分组时由服务器生成），组别代码整个研究期间固定，只导出两组都答的结局量表；对话轮次、会话、事件、LLM 和记忆相关集合揭盲前不导出（决策 0021）。
- 研究编号对照表 `research_id_map`、`research_ids`，只有非盲角色（`role: pi`）能读。`meta/arm_counter` 也改为只有非盲角色能读。
- 研究者后台：`researcher`（盲法）看不到两组人数和只有一组才有数据的板块；`pi`（非盲）看全部。
- 新增检查脚本 `tool/check_blinded_export.js`，有可疑字段就非零退出，测试里跑。
- 开关 `meta/blinding_config.enabled` 默认关，关着时旧导出照旧。报告：`docs/dev-reports/T12-blinding-20261007.md`。

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
