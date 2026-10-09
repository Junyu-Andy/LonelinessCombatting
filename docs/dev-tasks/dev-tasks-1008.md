# 陪住 开发任务 第四批（T22、T23，另加 T21 补充）

日期：2026-10-08。依据：工作台“开发对齐”（10/8）；登记表 v3；`docs/spec/instruments/ada.md` v1.0；T17b、T18、T19、T20 报告和两份交接（`T17-T20-handoff-20261007.md`、`T19-T17b-handoff-20261007.md`）里“要带回研究侧的发现”。基线：main @ `5f52416`（#47 合并后，T1–T20 和 T17b 都已在 main）。

放在仓库 `docs/dev-tasks/dev-tasks-1008.md`。每个 Claude Code 会话只需要说：“读 docs/dev-tasks/dev-tasks-1008.md，先读‘共同规则’，再执行 Tn。”

## 前置

1. 把登记表最新版（v4，随 dev-tasks-1009.md 发出）放到 `docs/spec/feature-registry.md`，覆盖 v2。
2. 顺序：T22 先做（小，半天内）；T21（含下面的补充）在 T22 合并后开，因为两者都改 `functions/blinding.js`；T23 在 T21 合并后开。
3. T21 的原任务仍以 `docs/dev-tasks/dev-tasks-1007b.md` 为准，本文件只加补充条目。

## 共同规则（每个任务都适用）

1. 不推送 main，不自己合并。每个任务开一个 PR 草稿，描述里写对应的 `SPEC:Cxx`。
2. 不连接生产 Firestore，不读写真实参与者或试用者的数据。用 Firebase emulator 和合成数据。
3. 不修改 `docs/spec/feature-registry.md`。
4. 新加的行为一律放在开关后面。开关的名字和默认值写进报告。
5. 老人看得到的文字（问卷措辞、提示语、推送）：只留配置键和【占位】文字，定稿由研究侧给。报告里列出每个键和占位内容。
6. 不要改热线号码。号码由 PI 核对。
7. 报告写到 `docs/dev-reports/`，文件名带任务号和日期。每条说法都附文件路径。报告结尾单列“要带回研究侧的发现”。

---

## T22 旧“陪伴者区分评估”收尾（分支 `fix/legacy-agent-diff`，SPEC:C15、C22）

已定：ADA 只用于 Phase A，Phase B 的已批测量里没有它（登记表 C15）。Phase A 的 ADA 只在第 1 次到访和第 7 日施测（ada.md §2）。T17 已让 Phase B 构建不再弹旧的“陪伴者区分评估”（`agent_diff`，第 14、28 天）。

1. **Phase B 盲法导出**：把 `agent_diff` 及其字段从盲法导出白名单去掉。报告列出改了哪些文件；说明代码里还有哪些地方会读或导出这类数据。
2. **Phase A**：`app_config/phaseA_schedule.adaEnabled` 打开时，Phase A 不再弹旧 `agent_diff`；关着时保持现状。不新加开关，跟随 `adaEnabled`。
3. 不删旧集合和旧页面，不改已有数据。
4. 测试：emulator 合成数据，覆盖 Phase A 构建 `adaEnabled` 开和关、Phase B 构建；盲法导出检查脚本退出 0，导出里没有 `agent_diff`。

输出：PR 草稿，加上 `docs/dev-reports/T22-legacy-agent-diff-YYYYMMDD.md`。

---

## T21 补充（分支照旧 `fix/phase-config-split`，SPEC:C01、C22）

T19、T17b、T18、T20 的报告提出了几处要和研究期字段一起做的事。下面几条并入 T21，在 T22 合并后开工；报告仍是 `docs/dev-reports/T21-phase-config-YYYYMMDD.md`。

1. **Phase A 也经研究员登记入口登记**（T19 的入口，同一个 `unblinded` 角色）：写研究期 A，发研究编号，不走序列分组；Phase A 一律用 Hybrid 新版（含记忆）。登记页上研究期要单选，提交前和情感分一样再确认一次。Phase A 不填 W0 DJG 情感分。
2. **研究编号**：Phase A 登记时写进 `research_id_map`；`ada_status.researchId` 随之有值；Phase A 导出时把 uid 换成研究编号（T17 待办第 63 项）。编号格式先沿用 T19 的规则。
3. **Phase A 日程从哪天算**：加配置键 `app_config/phaseA_schedule.dayOneAnchor`，取值 `createdAt`（默认，即现状）或 `registration`（登记日）。ADA 的 `visit1`、第 7 日窗口、第 7 日开放题都跟这个键走。默认值不变，研究侧定了再改。
4. **“只在 Phase B”的判断统一改看研究期字段**：`functions/djg_w2.js`（现在看 `cohort`）、`functions/ada.js` 的推送筛选、`functions/memory.js` 的 `inScope`、`functions/blinding.js` 的 `isBlindedParticipant`。报告列出每一处改前改后的判断。
5. **没登记的账号不调用 LLM**：没有研究期字段的账号（测试账号除外），服务器拒绝所有 LLM 生成调用，记一条 `llm_denied_log`。这些账号在 App 里本来就显示规则组界面，老人看到的不变。报告写明测试账号怎么识别。
6. **使用建议文案按研究期分开读**：`app_config/usage_copy` 拆成 Phase A 和 Phase B 各一份；两份都不存在时显示原文。不写任何新措辞。
7. 测试在原 T21 第 7 条之外加：Phase A 登记后有研究编号、没有序列位置被占用；`dayOneAnchor` 两个取值下第 7 日窗口正确；没登记的账号调用 LLM 被拒并有日志；两期的 `usage_copy` 互不影响。

---

## T23 核对轮次 2（分支 `docs/T23-audit-YYYYMMDD`，SPEC:C01–C22）

在 T21 合并后做。只读，不改代码。

1. 用登记表第三节的核对 prompt，按最新版（v4）逐项重核 C01–C22。
2. 另列一节：哪些开关和配置会改变老人看到的东西，各自现在的默认值；和 `docs/STUDY_CHANGELOG.md` 是否对得上。
3. 另列一节：登记表之外的组间差异。
4. 跑两套全量测试，报告与编号相关的通过和失败。

输出：PR 草稿，加上 `docs/spec/audit-YYYYMMDD.md`。不要做第三节里的“第二步”（加锚点注释），等研究侧确认核对结果。

---

## 这批不要做

- 研究编号的固定格式、阿珍/阿伯能不能被老人改、登记前那段数据怎么处理：等研究侧定。
- W2 DJG 的“第 14 天”口径（`djgW2DayOffset`）：等研究侧定，不改默认值。
- 发给 PI 的安全告警内容再改动：T19 的做法先保留，研究侧另定。
- ADA 研究员页面的角色（#47 定为 `blinded`、`unblinded` 都能用，研究编号只给 `unblinded`）：先不改，等研究侧确认。
- 部署、写配置、发角色由谁操作：等研究侧定，不改 `docs/release/prelaunch-checklist.md` 的分工。
- `llm_calls` 区分缓存命中：等研究侧决定是否需要。
- LoRA 正式上线（T8 的开关保持关闭）；“会话”的定义；“搜一搜”的替代方案；F2–F5；修改热线号码。
- 老人看得到的任何定稿文字：全部等研究侧给。
