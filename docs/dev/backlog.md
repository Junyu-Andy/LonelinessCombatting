# 待办与待决定

> 随时更新。做完的移到 `docs/history.md`，划掉或删掉这里的条目。
> 最后更新：2026-10-07

## 1. 已决定、待开发

| # | 事项 | 依据 | 备注 |
|---|---|---|---|
| 1 | **cohort 标记**：现有账号标 `pilot`；`assignArm` 写 `phase_a` / `phase_b`；规则禁止客户端写；计数器清零；删 `PHASE_B` 开关 | 决策 0011 | 阻断项：分组以 `assignArm` 还是 HTML 工具为准 |
| 2 | 记忆和入口的 P0 | `docs/dev/memory-and-entry-spec.md` 第 3 节 | 等负责人调研完记忆架构 |
| 3 | `meta/arm_counter` 改为客户端不可读、不可写 | 决策 0003（W1） | 分组已在服务器做，客户端不再需要它。可以和第 1 项一起做 |
| 4 | 每次分组写审计日志（时间、层、当时计数、结果、硬币） | `arm_assignment_scheme_v1.md` W2 | 建议和第 1 项一起做 |
| 21 | `llm_calls` 加进盲法导出（`blindedDataExport`）；数据删除时一起删 | 决策 0016 | C04 PR 只做了记录，没有导出和删除。**注意**：只有 Hybrid 组有记录，揭盲前原样导出就等于揭盲 |

## 2. 上线前必须做（负责人操作）

| # | 事项 | 怎么做 |
|---|---|---|
| 5 | 部署的一次性设置 | 仓库 Settings：加 secret `FIREBASE_SERVICE_ACCOUNT`；新建 environment `production` 并设审批人。见 `docs/dev/ci-cd.md` |
| 6 | `main` 分支保护 | Settings → Branches：必须走 PR、CI 通过才能合并 |
| 7 | 部署 | 顺序见 `docs/dev/architecture.md` 第 9 节 |
| 8 | ICF 修订 | 记忆强制开启、发给 DeepSeek、查看和删除、保留 3 年。负责人在改 |
| 23 | 研究文件里的模型名 | 登记表 C03、protocol、ICF、DMP、HREC 材料里的「DeepSeek-V3」「deepseek-chat」改为 DeepSeek-V4.1-Flash（`deepseek-flash`，思考关闭）。见决策 0017 |
| 24 | 部署决策 0017 的改动 | 现在线上的 Functions 还在请求旧名 `deepseek-chat`，DeepSeek 停用旧名当天 Hybrid 组会全部报错。合并后尽快部署 Functions |
| 25 | PI 核对危机页热线号码 | `functions/prompts/crisis_resources.json` 的 `verifiedDate` 还是空的。见 T6 报告 |
| 26 | 手动建两份配置 | `meta/memory_config` 和 `app_config/arm_assignment`。不建的话 Hybrid 组没有记忆、所有人都分到 A 组。可用 `tool/prelaunch_config.js`；逐项核对见 `docs/release/prelaunch-checklist.md`（T13） |

## 3. 待决定

| # | 问题 | 现状 | 谁决定 |
|---|---|---|---|
| 9 | 分组以 `assignArm` 为准，还是以独立 HTML 随机化工具（v1.3.1）为准 | 代码里只有 `assignArm`（最小化）；仓库里没有 HTML 工具 | 负责人 / 统计师 |
| 11 | **自由对话在规则组隐藏**，和「界面完全一致」原则冲突 | 决策 0006 | 负责人 |
| 13 | 分组失败期间（显示规则组界面）的数据算不算 | 决策 0004 | 负责人 |
| 14 | Hybrid 组有人留在研究里但要求删除全部记忆：要不要让服务器停止记新的 | 现在删了还会继续记 | 负责人 |
| 15 | phase_a 用记忆 v0 还是 v1 | 规格倾向 v1 | 负责人 |
| 16 | 安全词库 v5 的临床取舍 | 搁置，先沿用（决策 0012） | PI |
| 17 | 周度孤独感问卷 Phase B 开不开 | 编译开关 `WEEKLY_PROBE`，默认关 | 负责人 |
| 18 | 通通规则组模板的文化顾问审核 | 未审核 | 负责人 |
| 19 | CODEOWNERS：安全文件改动必须 PI 审核 | 需要 PI 的 GitHub 账号 | 负责人 |
| 20 | E4 微随机是否采用 | 规格 4.2 预留开关 | 负责人 |
| 22 | `llm_calls` 的保存期限，写进 DMP | 含 uid，属研究数据（决策 0016） | 负责人 |
| 27 | 记忆上线前要不要先修：「唔好記住」没有实现；摘要绕过「敏感先确认」；安全内容进摘要（服务器只查模型输出，不查原文）；删除一条后摘要里仍有同样内容 | T4 验收整体不通过 | 负责人 |
| 28 | 记忆「编造事实」按哪种口径计：按标准答案（每轮 4 条）还是只算凭空捏造（0–1 条） | T4 | 负责人 |
| 29 | LoRA 安全预过滤是否两组都经过。规则组过 LoRA 等于调用模型，与「规则组永远不调用 LLM」冲突，要先写决策记录 | 代码里没有接入点；方案见 T6 | 负责人 / PI |
| 30 | 语音输入：两组都开着、没有开关，用手机系统识别，可能上传云端；登记表 C18 写「HREC 批准前关闭」 | T1、T2 | 负责人 |
| 31 | Hybrid 组 AI 在回复里自己写热线，合成测试 60 次里 2 次机构和号码配错。要不要禁止或过滤 | T6 | **已定并在 T7 PR 实现**（决策 0018），合并后删去本行 |
| 32 | 词库对间接自杀表达召回低（合成 8 句中 2 句）。覆盖缺口和 7 处不带 uid 已在 T7 PR 修好 | T6 | 负责人 / PI |
| 33 | 通通「搜一搜」把原话发给 Brave，且不去个人信息。T7 已改为先过安全检测（命中就不搜）；T9 默认关闭 | T2 | 负责人 |
| 34 | 同意与删除：对话保留默认开启；`sharedContextUse` 从不生效；没有整人删除；`stripPII` 不去人名；App 隐私页写「冇雲端同步」与实际不符 | T2 | 负责人 |
| 36 | 登记表要更新的行：C03 模型名、C12 词库版本（v5）、C14 量表（1–7 点选）、C15 DJG 版本（6 条） | T1 | 研究侧 |
| 49 | 行动计划提醒要不要打开；推送里要不要带计划原文（现在只发「件事點呀？」） | T13，决策 0022。开关 `app_config/reminders.m7FollowupPushEnabled` 默认关 | 研究侧 |
| 50 | 怀旧入口文案定稿（草稿：「4 個主題、4 個禮拜」） | T13 报告；PR 里单独的提交 | 研究侧 |
| 51 | `meta/arm_counter` 客户端仍可写（规则只限增量格式），能影响后来者的分组；分组用的 `ageGroup`、`baselineUclaScore` 也是参与者自己填的 | T13 报告。计数器的处理见第 3 项 | 负责人 |
| 37 | 老人看得到的新文字定稿：AI 回复里号码换成的「【緊急熱線】」链接（现用已有的「緊急熱線」）；prompt 规则 `hotline_rule.v1` 的措辞请 PI 审核 | T7 | 研究侧 / PI |
| 38 | `hotline_filter_log` 和 `safety_events` 的新字段（`isDuplicate`、`inputPoint`）加进盲法导出和整人删除。`hotline_filter_log` 只有 Hybrid 组，原样导出等于揭盲 | T7 | 负责人（T11、T12） |
| 39 | `hotline_rule.v1.txt` 还没进 `kArtefactHashes`（`tool/export_spec_inputs.py` 只列三个 persona 文件）。重新生成 `build_info.g.dart` 时一并加上 | T7 | 开发 |

## 4. 暂缓或以后再做

- 端到端测试用例表（暂缓）。
- 单独的 staging Firebase 项目（不需要）。
- 函数代码约 880 个 lint 格式错误一次性修复，之后 CI 检查格式。
- Dependabot 自动更新依赖。
- Android 正式签名（现在用调试密钥，只能内部测试）。
- 记忆 P2：RAG、人生叙事摘要、遗忘、对话中确认、按内容共享、多条待跟进、删除 v0（见规格第 5 节）。
- 回忆 A 组研究记录仍保存 acute 那一轮原文（研究数据的决定，未改）。
