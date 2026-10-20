# 待办与待决定

> 随时更新。做完的移到 `docs/history.md`，划掉或删掉这里的条目。
> 最后更新：2026-10-15（1014e 第 2 节第 18 条 App 名称 PR 草稿，图标已换；第 19 条排查已做；1014e 第 2 节第 4 条 PR 草稿，第 92 项关闭；1014e 第 2 节第 3 条 PR 草稿，第 96 项已做；试跑改走正式每周问卷排程 PR 草稿，试跑压缩排程作废；10/15 第 6 条文字定稿接入 PR 草稿，第 97 项 ⑥ 已做、第 106 项已做；1014e 第 2 节第 11 条 PR 草稿，第 111 项 ⑤ 已做；1014e 第 2 节第 7、8 条 PR 草稿，第 97 项 ⑤ 已做、加 ⑥；T39 运营看板 PR 草稿，第 111 项；T40 使用事件记录 PR 草稿，第 110 项；T46 收尾说明只显示一次 PR 草稿，第 97 项 ③ 已做；瘦身批次定号 SL1–SL8，决策 0040 提议中，见末尾；T27 语音改走服务器 PR 草稿，第 101–103 项；T34 安全告警邮件 PR 草稿，第 97–100 项；T21 第二次更新：决策 0037 六项过渡默认，第 1 项 `PHASE_B` 改为保留，加第 96 项 `isTester` 客户端可写）
> 2026-10-20 1020e 二.13：「想重新聯絡嘅人」只传「可以講」的人已改（#127）；Junyu 部署后跑 `tool/rewrite_reconnect_memory.js` 预演、再 `--apply` 重写旧记忆条目。
> 2026-10-20 1020c 第一节：#126 两个开关定开（10/20 手机测试过后、第一位 RCT- 前）；开之前已修建议页用掉跟进、字号变小两处（#127）。待 Junyu 定：「想重新聯絡嘅人」是否只传勾了「可以讲」的（记忆和建议页两处一起改）；登记表组间差异一行和显示设定一句（报告第十节草稿）。
> 2026-10-16 测试员自切组别 PR 草稿（开关 `testerArmSwitchEnabled` 默认关）；待定：决策编号；要用时在控制台开开关并给测试员帐号设 `isTester`；已知：切过组的帐号不要再去掉 `isTester`（会变成没有研究编号的试跑帐号），要删用 `tool/purge_tester_data.js`。
> 2026-10-15 T48 「重要的人」同意后给夥伴 + 入组答案进服务器记忆 PR 草稿（接 T47）；待定：决策编号、ICF 一句是否覆盖研究员录入的人。
> 2026-10-15 T47 入组问卷精简 + 研究员录入 PR 草稿（开关 `researcherIntakeEnabled` 默认关）；待定：五题文字 Junyu 确认（S16）、登记表三处改动交产品窗口、`closeContacts` 要不要接小欣/行动计划。
> 2026-10-15 决策 0041、0042 落盘；W4 含 S12、提醒口径、W4 完成率分母不含试跑三项已定；「AI」改「夥伴」PR 草稿；Firestore 配置核对表 `docs/release/firestore-config-checklist-1015.md`（`phase_a` 测试值要删；`memory_config`、`randomization_config` 10/19 前确认）。
> 2026-10-15 通知与问卷排查 A1–A15 做完（PR 草稿 `docs/notifications-audit-1015`）；待研究侧定：W4 要不要 S12、提醒时间口径。
> 2026-10-16 注册页密码输两次、电邮换行、眼睛按钮 PR 草稿（S17 三句待产品窗口核）。
> 2026-10-16 T47 改版：入组五题一题一屏、先客观后主观（并入 `batch/1016-morning`）；待定：删掉的七题要不要加回任何一题（Junyu 定）、「第 N 題，共 5 題」「上一題」「下一題」三句待产品窗口核。
> 2026-10-16 研究员备注 + 通通一页不问兴趣 + 兴趣按钮換一換 + 气泡加宽 PR 草稿（接 #108）；五题上限已按 Junyu 10/16 全部去掉；待定：S16 新加的「揀幾多項都得」「加多一位」和 S18「換一換」待产品窗口核。
> 2026-10-16 T47 修订版 PR 草稿（甲部 14 题研究员录、乙部老人填、不限数）；待定：提示词语气槽位新版（PI 审）、登记表四处改动交产品窗口、W0 要不要问「8 周内会否离港」（见 T47 报告第 9 节第 6 题）、S19 待产品窗口核。
> 2026-10-18 T49a 入组资料 §A 收尾（PR #111 同分支）；待定：分析用的配对口径（登记值还是第一次选择）、`inputMode` 要不要做读取方、规则组通通兴趣按钮是否保留、五题页要不要也限 10 位、三位 PILOT 老人开关打开后是否跳过乙部页、Prompt 2 之前语气和回忆页「⛔」的空档、§A3 路由的决策编号。
> 2026-10-16 iPhone 更新走 TestFlight（`docs/release/ios-testflight.md`）：Junyu 要做一次的三步（接受协议、建 App 记录、建外部测试组开公开链接）今天做，第一次 Beta 审核 1–2 天；FAQ 英文条目已删（PR 草稿）。
> 2026-10-18 记忆机制核对报告 PR 草稿（`docs/dev-reports/memory-mechanism-20261018.md`）；待 Junyu 定第 10 节十项：开不开两层、切不切 v3、`raw_output` 保留、四页记忆交接时机、`forgetAckReply`、断网补写、20 轮上限、提示词末尾槽位一段、`cross_session_memory` 标志、（无需决定）老人无开关一致。
> 2026-10-18 T49（`dev-tasks-1018.md`）：E1 六步核对已过，等 Junyu 10/19 开 `layersEnabled`；接下来 G 只读核对脚本、F 第 6 题（T47 报告第 9 节已答）、B 提示词 PR（10/22）、A 的 2/3/4/7（10/22、10/26）、C、E3、E4（10/26）。
> 2026-10-18 §G4 只读核对脚本 `tool/check_prelaunch_values.js`（PR 草稿）；Junyu 10/19 前跑一次（需服务帐号），✗ 的按核对表改。
> 2026-10-18 T49e-4 删记忆时清服务器模型原文 `raw_output` PR 草稿（1018 §E4，开关 `clearRawOutputOnDelete` 默认开）；待定：部署前已删条目的原文要不要一次清掉、决策编号。
> 2026-10-18 T49c S1a 固定回复记事件 PR 草稿（开关 `s1aEventLogEnabled` 默认关）；待定：何时开开关、旧事件 `tung_tung_search_off_reply` 要不要停。
> 2026-10-18 T49b 三位陪伴者提示词 v2/v2/v3 + 语气槽位 + 回忆页禁区行 PR 草稿；待定：Junyu 看三份最终文本再合；决策记录编号；PR #111 的「鍾意人點樣講嘢」记忆条目和语气槽位重复、用了「入組時揀」说法，留哪一处；登记表组间差异加一句、B07 §5.2 一句（产品窗口）；三位试跑老人 W4 补问鼓励方式（B20）；阿珍／阿伯「唔係你負責：興趣／資料／搜尋（係通通負責）」一句这次没动，要不要下一版删「搜尋」。
> 2026-10-18 T49e-3 记忆交接时机统一（dev-tasks-1018 §E3）PR 草稿，排 10/26；10/19 后合并要记偏离日志。新发现、未修：四个 Hybrid 聊天页超时后老人接着再讲、再离开，这第二次会话不记结束、不走 Brief PR（`_briefPrSurfaced` 已是 true，整段跳过）；通通和自由对话页连记忆交接也跳过（只靠扫描）。小欣页、回忆页的记忆交接本 PR 已不受影响。要另开一项定。
> 2026-10-18 批次 #120 UI 扫描后待定：乙部页「關係（例如：女兒、舊朋友）」在 320 宽 × 1.3 仍略有省略号，要不要缩短 S19 那句；`functions/index.js` #112 新代码的 24 条 ESLint 缩进另排整理。
> 2026-10-19 1020b C 已补进 #127；待：Junyu 部署 Functions 和规则、给 Qingyang 发角色开开关，Qingyang 10/20 下午上传 v2，10/21 前跑只读检查；「想重新聯絡嘅人」传给 DeepSeek 要不要看 `share`（Junyu 定）；W8（T35）未做；决策编号。
> 2026-10-19 dev-tasks-1020 第 1 批 PR 草稿（H、I、J、导出加列、只读脚本）；待定：C 序列版本方案（Junyu 批）；生产核对（Junyu 跑脚本）；控制台 `voiceInputEnabled` 改 false；APNs 密钥是否已上传；「保留對話紀錄」询问框只改总开关的旧问题（开关已隐藏，低优先）；第 2–4 批要工作台第五节文字。
> 2026-10-19 W0 现场：两开关 PR 草稿待合、合后控制台打开；待定：建议页提示词搬到 `functions/prompts/`（现在还在 App 里）；乙部页顶上要不要加「三位夥伴」铺垫句（S19，Junyu 定稿）；chirp_3 对比结果决定留哪个；决策编号。
> 2026-10-19 W0 现场第二批待定（Junyu 定了再做）：(1) iOS 系统字体放大后 App 内字体观感不统一，建议改为只认 App 内「字號」三档、忽略系统字体（`app.dart` 一行）；(2) Brief PR 入口不醒目，现在是会话结束后在陪伴者列表页出卡（T25 定的「不弹窗」），要改成弹窗或首页横幅是测量流程改动，要 PI 定；(3) 「我記得嘅嘢」页按日期分组、分类折叠、顶上一句汇总；(4) 个人资料卡重排（电邮小字、紧急联络收进一行）；首页热线卡按规矩不动。
> 2026-10-19 第二轮（切页跳回、标题跳动、「自己」页精简、首页安全卡、首页字放大、字号五档）PR 草稿；待定：首页安全卡 PI 审核；两份新决策编号；字号最小档是 1.06 还是保留 1.0（Junyu 定）。
> 2026-10-19 测试员免打包解锁、每週問卷測試页、Brief PR 横排、注册跳错处、人生回顧去锁、隐藏保留对话开关 PR 草稿；待定：两份决策编号；「保留對話紀錄」不开放要 Junyu 确认并改 ICF（若写了 App 内可关）；要用测试员工具时在控制台开 `testerToolsEnabled`。

## 1. 已决定、待开发

| # | 事项 | 依据 | 备注 |
|---|---|---|---|
| 1 | **cohort 标记**：现有账号标 `pilot`；`assignArm` 写 `phase_a` / `phase_b`；规则禁止客户端写；计数器清零；删 `PHASE_B` 开关 | 决策 0011；0037 | 研究期字段和配置拆分并入 T21（第 71 项）；T19 起 Phase B 分组在登记时做（`enrollments/{uid}.studyPeriod` 已留位置），`assignArm` 不写 cohort。**10/14（决策 0037）**：`PHASE_B` 编译开关**保留**，参与者包固定 `PHASE_B=true`，不删；`pilot` 现指 `PILOT-` 试跑账号，旧账号按 T32 删除不标记；`cohort` 由 T21 的登记写入、规则禁止客户端写（已做） |
| 2 | 记忆和入口的 P0 | `docs/dev/memory-and-entry-spec.md` 第 3 节 | 等负责人调研完记忆架构 |
| 21 | `llm_calls` 数据删除时一起删 | 决策 0016 | 盲法导出部分按决策 0021：揭盲前不导出 |
| 70 | **T19 App 内分组重做**（研究员登记、置换区组序列、事务分配和日志、客户端不能读写分组/计数器/序列，原第 3、4、51 项一并做了） | 决策 0029；`docs/dev-reports/T19-randomization-20261007.md` | PR 草稿（分支 `fix/randomization`）。合并后删这一行 |
| 89 | **T31 记忆分层**（共享层 / 私有层、按陪伴者过滤、删除覆盖两层、剂量分层计、抽取 prompt v3 未切换、S7） | 决策 0035；`docs/dev-reports/T31-memory-layers-20261010.md` | PR 草稿（分支 `feat/memory-layers`）。合并后删这一行。上线：PI 审 v3 → 研究侧定日期切 `extractionPrompt`；`layersEnabled` 和 `memoryLayersNoticeEnabled` 一起开 |
| 71 | **T21 研究期和登记**（`dev-tasks-1010.md` 第三节、`1010b.md` 更正）：第一部分已做（PR 草稿，分支 `fix/phase-config-split`）：编号前缀定研究期（只认 `PB-`、`PILOT-`）、试跑由研究员指定版本、登记门（等待页 S8、未登记不给 LLM、不收研究数据，开关默认关）。**还没做**：定时推送对未登记账号的筛选（广播推送按主题发，交 T24）；评估员账号在登记门打开后的去向（交 T30，`dev-tasks-1014.md` T30 第 3 条）。编译开关 `PHASE_B` 10/14 定为保留（决策 0037 第 1 项），不再列为待做 | `docs/dev-reports/T21-phase-config-20261014.md`；决策 0037 | PR #59。合并后删“已做”的部分；0037 的六项待负责人确认 |
| 84 | **T26 LoRA 两组、两期和试跑共用**（决策 0033；`turns.safetyTurnId`；上线清单 H 节；10/10 补 Phase A 和试跑） | `docs/dev-reports/T26-lora-both-arms-20261009.md` | PR 草稿（分支 `feat/lora-both-arms-v2`）。合并后删这一行 |
| 90 | **T34 安全告警邮件**：字段（研究编号、研究期、陪伴者、来源、级别和类别、词库版本、LoRA、研究日、危机页、事件编号）；收件人配置（Junyu、后备 Calvin Or，评估员不在名单、测试账号不发）；后台“确认处理”；12 小时没确认转后备；PHQ-9 第 9 题的问卷和评估员录入来源；导出带来源 | 产品窗口 10/10 第 6–8 条；`docs/dev-tasks/dev-tasks-1010b.md` | 现在可以开；评估员录入那一头等 T30 和 PHQ-9 规格文件 |
| 97 | **T25 会话定义与 Brief PR 第二版**：已做数据层、邀请规则、评价卡、问卷、收尾按钮、`llm_calls.session_id`（PR 草稿，分支 `feat/session-briefpr`，开关默认关）。待做：① 截图；② `brief_pr` 加 T24 的 `studyWeek` / `studyDay`；③ ~~收尾按钮首次说明跨次启动只显示一次~~（T46 已做，PR 草稿 `fix/session-end-hint-once`）；④ 决策记录（旧弹窗只在开关关时保留、anchor 取消）编号待分配后落盘；⑤ ~~开关打开前研究侧定稿【占位】文字~~（10/15 已定稿并接入，PR 草稿 `fix/t25-copy-final`）；⑥ ~~规则组回忆 B 页的「【占位】你而家心情點？（可以唔揀）」仍待产品窗口定稿（现包里可见）~~（10/15 第 6 条已定稿 S13 并接入，PR 草稿 `fix/copy-1015-item6`） | `dev-tasks-1009b.md` T25、`1010.md` §三、`1010b.md` §二 | `docs/dev-reports/T25-session-briefpr-20261014.md` |
| 98 | T25 后续：开关打开后把会话第 1 版的字段（`userTurnCount`、`briefPR`、`user_left` / `app_killed`）和弹窗 Brief PR 代码路径（`BriefPrGate`、`BriefPrPage`、`isAnchorPromptFor`）删掉；`sessions` 的 `scheduleVersion` 区分新旧行 | T25 报告 | 等开关打开并稳定一周 |
| 99 | T29、T30 用 T25 的 `sessions.isValid` / `brief_pr.finalStatus`：每人每周有效会话数查询见 T25 报告第 5 节；`usage_weekly.validSessionCount` 已加 | `dev-tasks-1009b.md` T29、`1010.md` T30 | — |
| 110 | **T40 使用事件记录**（PR 草稿，分支 `feat/usage-events`，开关 `usageEventsEnabled` 默认关）：待做 ① 真机断网三次再联网，核对三条 `uploadedLate: true`、手机时间不变（W0 装机或试跑第一周做）；② T39 看板读 `usage_events`（按 `dayKey` 聚合）；③ 旧的 `events` `app_foreground` / `app_background` 行没有手机时间，T39 后备口径只能用会话记录；④ 决策记录编号（报告第 7 节草稿） | `dev-tasks-1014d.md` T40 | `docs/dev-reports/T40-usage-events-20261014.md` |
| 111 | **T39 运营看板**（PR 草稿，分支 `feat/ops-dashboard`，开关 `opsDashboardEnabled` 默认关）：已做第 2 页每人 / 每日 / CSV 和第 1 页第 7 项。待做 ① 第 1 页其余项（已登记人数、今天有效会话人数、告警数、本周完成率、未来 7 天到期、14 天柱状图）；② 第 3 页按组汇总（Junyu 定）；③ 每人页「查看该人对话记录」链接（Junyu 定，要走现有路径并记审计）；④ W8 / debrief 两列等 T35、T42；⑤ ~~旧的「研究員儀錶板」没有入口~~（10/15 1014e 第 2 节第 11 条：登记页右上角加入口，PR 草稿 `feat/dashboard-entry`）；⑥ 参与者多于几十人时 `opsDashboardPeople` 要改为分页或只读 `ops_daily` | `dev-tasks-1014c.md` T39、`1014d.md` | `docs/dev-reports/T39-ops-dashboard-20261014.md` |
| 90 | **T34 安全告警邮件**：字段（研究编号、研究期、陪伴者、来源、级别和类别、词库版本、LoRA、研究日、危机页、事件编号）；收件人配置（Junyu、后备 Calvin Or，评估员不在名单、测试账号不发）；后台“确认处理”；12 小时没确认转后备；PHQ-9 第 9 题的问卷和评估员录入来源；导出带来源 | 产品窗口 10/10 第 6–8 条；`docs/dev-tasks/dev-tasks-1010b.md` | 现在可以开；评估员录入那一头等 T30 和 PHQ-9 规格文件 | PR 草稿已出（分支 `feat/safety-alert-email`，`docs/dev-reports/T34-safety-alert-email-20261014.md`）；评估员录入那一头等 T30 和 PHQ-9 规格文件；开关 `meta/alert_config.enabled` 默认关 |

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
| 26 | 手动建两份配置并上传序列 | `meta/memory_config`、`meta/randomization_config`（T19）；非盲研究员上传分配序列。可用 `tool/prelaunch_config.js`（它也检查序列）；逐项核对见 `docs/release/prelaunch-checklist.md`。`app_config/arm_assignment` 已停用，可删 |
| 101 | **10/19 登记前清掉试用期的测试员数据**（T32 第 6 条） | 先列不删、再 `--confirm --production`，步骤见 `docs/release/prelaunch-checklist.md` I 节。脚本 `tool/purge_tester_data.js`；报告 `docs/dev-reports/T32-phase-a-final-20261014.md` |

## 3. 待决定

| # | 问题 | 现状 | 谁决定 |
|---|---|---|---|
| 9 | 分组以 `assignArm` 为准，还是以独立 HTML 随机化工具（v1.3.1）为准 | **10/7 已定，T19 已做**（决策 0029）：App 内登记分组，HTML 工具停用（上线清单 C3） | — |
| 11 | **自由对话在规则组隐藏**，和「界面完全一致」原则冲突 | 决策 0006 | 负责人 |
| 13 | 分组前（显示规则组界面）的数据算不算。T19 起 Phase B 每个人从注册到研究员登记之间都处在这个状态 | 决策 0004；第 72 项 | 负责人 |
| 14 | Hybrid 组有人留在研究里但要求删除全部记忆：要不要让服务器停止记新的 | 现在删了还会继续记 | 负责人 |
| 15 | phase_a 用记忆 v0 还是 v1 | 规格倾向 v1 | 负责人 |
| 16 | 安全词库 v5 的临床取舍 | 搁置，先沿用（决策 0012） | PI |
| 18 | 通通规则组模板的文化顾问审核 | 未审核 | 负责人 |
| 19 | CODEOWNERS：安全文件改动必须 PI 审核 | 需要 PI 的 GitHub 账号 | 负责人 |
| 20 | E4 微随机是否采用 | 规格 4.2 预留开关 | 负责人 |
| 22 | `llm_calls` 的保存期限，写进 DMP | 含 uid，属研究数据（决策 0016） | 负责人 |
| 27 | 记忆上线前要不要先修：「唔好記住」没有实现；摘要绕过「敏感先确认」；安全内容进摘要（服务器只查模型输出，不查原文）；删除一条后摘要里仍有同样内容 | T4 验收整体不通过 | 负责人 |
| 28 | 记忆「编造事实」按哪种口径计：按标准答案（每轮 4 条）还是只算凭空捏造（0–1 条） | T4 | 负责人 |
| 29 | LoRA 安全预过滤是否两组都经过。规则组过 LoRA 等于调用模型，与「规则组永远不调用 LLM」冲突，要先写决策记录 | 代码里没有接入点；方案见 T6 | 负责人 / PI |
| 30 | 语音输入：两组都开着、没有开关，用手机系统识别，可能上传云端；登记表 C18 写「HREC 批准前关闭」 | T1、T2；**T9 已加开关、默认关**（决策 0019），重开见第 40 项 | 负责人 |
| 32 | 词库对间接自杀表达召回低（合成 8 句中 2 句）。覆盖缺口和 7 处不带 uid 已由 T7 修好（PR #38 已合并） | T6 | 负责人 / PI |
| 33 | 通通「搜一搜」把原话发给 Brave，且不去个人信息 | T7 已改为先过安全检测（命中就不搜）；**T9：App 和服务器都已关**（决策 0019），重开前要改，见第 42 项 | 负责人 |
| 34 | 同意与删除：`stripPII` 不去人名。（对话保留默认值、`sharedContextUse`、整人删除、隐私页已由 T11 处理，剩下的决定见第 43–45 项） | T2、T11 | 负责人 |
| 35 | 安全规则允许本人在分组为空时写 `arm` | T1 C01 | 负责人 |
| 43 | **上线时**：先在正式项目跑 `tool/set_shared_context_consent.js --all --confirm --production`，再部署 T11 的 Functions 和 App。ICF 写明「三位陪伴者默认共享基本信息，不愿意的可联系研究团队关闭」 | 决策 0020；T11 报告第 2 节 | 负责人 |
| 44 | ICF 里「保留对话」的说法要和 App 对上：默认开，老人可以在设置里关（T11 已放回开关） | T11 报告第 1 节 | 负责人 |
| 45 | 整人删除：已导出的盲法文件**已定保留不动**（决策 0020）；**依赖 T12**：T12 合并、导出改成研究编号后，才在 ICF 写「已经用于分析的去识别数据不会删除」。还要定：删不到的数据（日志、DeepSeek/Brave、本机导出、手机缓存）写进 ICF/DMP；删除后分组计数减不减；谁跑脚本、多久完成、存证怎么保管。App 隐私页已改成简短版，等负责人确认文案。T12 合并后脚本要加研究编号对照表 | T11 报告第 3、4、6 节 | 负责人 / 统计师 |
| 49 | 行动计划提醒要不要打开；推送里要不要带计划原文（现在只发「件事點呀？」） | T13，决策 0022。开关 `app_config/reminders.m7FollowupPushEnabled` 默认关 | 研究侧 |
| 50 | 怀旧入口文案定稿（草稿：「4 個主題、4 個禮拜」） | T13 报告；PR 里单独的提交 | 研究侧 |
| 37 | 老人看得到的新文字定稿：AI 回复里号码换成的「【緊急熱線】」链接（现用已有的「緊急熱線」）；prompt 规则 `hotline_rule.v1` 的措辞请 PI 审核 | T7 | 研究侧 / PI |
| 38 | `hotline_filter_log` 和 `safety_events` 的新字段（`isDuplicate`、`inputPoint`）加进盲法导出和整人删除。`hotline_filter_log` 只有 Hybrid 组，原样导出等于揭盲 | T7 | 负责人（T11、T12） |
| 39 | `hotline_rule.v1.txt` 还没进 `kArtefactHashes`（`tool/export_spec_inputs.py` 只列三个 persona 文件）。重新生成 `build_info.g.dart` 时一并加上 | T7 | 开发 |
| 40 | **重新打开语音**：HREC 批准 STT 后把 `app_config/feature_flags.voiceInputEnabled` 设为 `true`。之前先定是否允许系统云端识别；键盘自带语音 App 关不掉，ICF 要不要提 | T9 报告第 7 节 | 负责人 / 研究侧 |
| 41 | 通通固定回应的文字和关键词表定稿；通通 prompt v2（去掉"幫你查"邀请）**PI 审核** | T9 报告第 4、8 节 | 研究侧 / PI |
| 42 | 搜一搜若要重开：搜索词先过安全检测（T7 统一入口）、去个人信息；开关只在 App 启动时读，新装第一次打开读不到 | T2、T9 | 负责人 |
| 46 | 盲法：**10/7 已定**非盲研究员是 Keran，PI（Junyu）是盲法评估者。**T19 已改代码**（决策 0029）：角色改名 `unblinded` / `blinded`，旧 `pi` 失效；给 PI 的告警和邮件去掉能推出组别的字段。还没定：Brief PR、使用量要不要在揭盲前给盲法分析员；过程数据揭盲前不导出是否影响统计分析计划；盲法分析员揭盲前能看到什么 | 决策 0021、0029；T12、T19 报告 | 研究侧 / 统计师 |
| 47 | 盲法开关 `meta/blinding_config.enabled` 何时打开；打开前已产生的旧导出文件（含原始 uid）删不删、谁保管 | T12 报告 | 负责人 |
| 48 | 整人删除脚本（T11）要连带删除研究编号对照表 `research_id_map/{uid}`、`research_ids/{researchId}`，以及 `exports_v2/` 里的行 | T12 报告第 2 节 | 开发（T11 合并后） |
| 54 | 规则组模板回应：什么时候打开开关、只对新 cohort 还是所有规则组参与者；T7 合并后把 `rule_reply_safety.dart` 换成 `SafetyService` | T15 | 负责人 |
| 55 | 「唔好記住」：陪伴者确认句定稿（**10/10 已定稿 S2，T33 接入 `memory_forget_ack.v2.txt`**；开关 `forgetAckReply` 默认关）；识别边界是否接受（整次会话不记；以前的条目按字面相近删除，可能删多或漏删）；ICF 怎么写 | T10 报告第 3 节、决策 0024 | 研究侧 |
| 56 | 隐晦的自伤说法（「儲安眠藥……一次過食晒」「一了百了」）App 词库认不出，两组的安全流程都不会触发；记忆层现在靠模型 `safety_concern` 兜底。要不要加进词库（两组同时生效，需 PI 签核，决策 0012） | T10 报告第 1 节 | PI |
| 57 | 记忆的其余问题（T10 没处理，T16 第 5 节）：缓冲区只留 10 轮；事实只增不减、抽取 token 跟着涨；前后矛盾两边都留；同一件事重复建跟进；含「聽日」「下個禮拜」的事实过时；不常用的陪伴者看不到自己的摘要；「下個禮拜日」换算规则；`llm_calls` 不记缓存命中 | T16、T10 报告 | 研究侧定原则后开发 |
| 58 | **安全分类器能不能两组都用**：**10/8 已定两组共用，T26 已写进决策 0033**。还没定：DMP、ICF 写明、HREC 是否修订（上线清单 H5）。原问题：规则组的原话（去掉电话等）会发给分类器，这是规则组新的外发路径；它不是对话模型、不返回文字、不经过 `assertLlmAllowed`。接受的话 DMP、ICF 要写，HREC 是否修订；不接受就只能不打开（只给一组用违反两组一致） | 决策 0025（提议中）；T8 报告 | 研究侧 / PI |
| 59 | 接真实 LoRA 要提供：地址、鉴权方式、部署在哪台机器（线上连不到个人电脑）、输入长度上限、返回格式、实测延迟；用 T6 句子和词库性能语料测召回、误报和延迟，再定等待上限（现 1.5 秒）和是否先「只记日志」试运行 | T8 报告第 5 节 | 研究侧 |
| 60 | 安全分类器的两个遗留问题：① 离线时规则组只用词库（新的组间不对等），要不要联网后补测；② 只升不降会让误报减少 Hybrid 组的 AI 回复次数、规则组的模板回应，可接受的误报率是多少 | 决策 0025 第 4、6 点 | 研究侧 / PI |
| 85 | **通通 Hybrid 组"搜一搜关闭"的固定回应不问分类器**：通通固定回应开关打开时，Hybrid 组问搜索类问题、词库没命中，就直接给固定句，不经过 `checkUserTextClassified`，也不写 `safetyTurnId`；规则组同一句话会问分类器。分类器开关打开前要改成两组一样（改法：固定句之前也走同一个检测） | T26 报告第 4 节；`tung_tung_page.dart` `_replySearchOff` 之前 | 开发（分类器打开前） |
| 86 | CLAUDE.md「规则组永远不能调用 LLM」和 LoRA 分类器：分类器本身可能是一个微调的语言模型。决策 0033 按"不生成文字、不是对话模型"处理，`assertLlmAllowed` 没动。要不要在 CLAUDE.md、protocol 里把这句写清楚（例如"不调用对话模型；安全分类器除外"） | 决策 0033 第 4 点 | 研究侧 |
| 87 | **研究员电话代填的 Phase A 问卷文字不问分类器**：ADA 自由作答、第 7 日开放题由研究员代填时，服务器只查词库（`functions/ada.js`）；老人自己填会问分类器。要不要也问（研究员当时在电话上） | T26 报告 10/10 补充 | 研究侧 |
| 88 | **T21 拆配置时分类器开关不分期**：`app_config/phase_a.safetyClassifierEnabled`、`safetyClassifierTimeoutMs` 和 `meta/safety_config` 保持全局一份，不拆成 Phase A / Phase B 各一份（决策 0033 第 7 条） | 决策 0033；T26 报告 10/10 补充 | 开发（T21） |
| 61 | ADA 定稿：**10/7 已给** `docs/spec/instruments/ada.md`。T17b 已按它补做（PR 草稿，决策 0030，截图见 T17b 报告第 4 节）；**PI 书面确认截图前 ADA 开关保持关** | T17b 报告；决策 0026、0030；ada.md | PI 审截图 |
| 62 | 第 7 日 3 道开放题的题目（现为【占位】）；ADA、开放题横幅和第 2 周横幅新副标题的措辞 | T17 报告第 8 节 | 研究侧 |
| 63 | T21 拆分配置时把 `app_config/phaseA_schedule` 整份归入 Phase A；`ada_responses`、`day7_open_responses` 按研究期筛选（文档里已有 `studyPhase: "A"`）；ADA 文档存的是 uid，研究编号在服务器专用的 `ada_status/{uid}`（T17b），Phase A 导出时按 uid 对上；`functions/ada.js` 的 `isPhaseAParticipant` 换成研究期字段 | T17 报告第 4、6 节；T17b 报告 | 开发（T21） |
| 64 | W2 DJG 老人看得到的文字定稿：推送和 24 小时提醒（现在是【占位】，未定稿前服务器不发）、页面说明和按钮（「每句揀一個最啱你最近情況嘅答案。」「上一題」「跳過呢題」「提交」等）、首页卡片「第 2 週問卷 / 6 條短問題，幾分鐘就答完。」 | T18 报告第 5 节，决策 0027 | 研究侧 |
| 65 | W2 DJG 的时间口径：「第 14 天」现在按 W0 = 第 1 天算（即 W0 后 13 天），是否应为 W0 后 14 天；W0 **T19 已改为**先用研究员登记的 W0 日期、没有再用账号创建时间；窗口过后只在 7 天内补记缺失；测试账号不推送 | T18 报告第 2、6 节；T19 | 研究侧 |
| 66 | W2 DJG 开关 `app_config/phase_b.djgW2InAppEnabled` 何时打开（打开当天在 STUDY_CHANGELOG 补生效日期）；T17 已在 Phase B 隐藏旧的第 2 周陪伴者比较横幅；**开关不打开时 Phase B 第 2 周仍出旧版 DJG，措辞与问卷包不符**；「只在 Phase B」现在客户端看 `PHASE_B` 构建、服务器看 `cohort`，T21 改为按参与者研究期 | T18 报告第 6 节 | 负责人；开发（T21） |
| 67 | （10/10：7 处的位置和原文已带回产品窗口写短版，`docs/dev-reports/product-reply-20261010.md` 第一节）使用建议文案定稿：7 个键的中英文措辞（T20 报告第 2 节；7 处等产品窗口写短版；S5 放入组引导，见第 93 项）；写入 `app_config/usage_copy` 当天在 changelog 记一行 | 现在显示原文（决策 0028） | 研究侧 |
| 68 | prompt 和规则组模板里提到频率的说法要不要跟着改（T20 报告第 3 节）。改 prompt 要新版本文件和 PI 审核 | 只列出，没改 | 研究侧 / PI |
| 69 | （10/10 已定：S5 放在入组引导，新加一处，T33 做）要不要在 App 里新加一处明说"建议每天用、每周至少 5 次"（现在没有任何地方明说）；要不要按使用量提醒 | 没加，也没有提醒 | 研究侧 |
| 72 | **登记前的数据**：Phase B 老人注册后到研究员登记前，`arm` 为空、看到规则组界面；这段时间服务器不拒绝 LLM（App 不会调用；Phase A 也靠空组别运行，T21 有研究期字段后可以对未登记的 Phase B 账号也拒绝）。建议入组当天老人离开前登记并重开 App。这段数据计入还是剔除、要不要在 App 里显示「等待登记」 | T19 报告第 5 节 | 研究侧 |
| 73 | 分配记录的保管：整人删除时 `arm_assignment_log` 和已用的序列位置**现在保留**（试验完整性），`enrollments/{uid}` 删除；种子文件交导师离线保存的方式；Firestore 数据访问审计日志的保留期。写进 DMP | T19 报告第 3、7 节 | 研究侧 |
| 74 | 登记的细节：研究编号格式（现在接受 2–12 位大写字母、数字、`-`）；阿珍/阿伯由研究员登记写入，但老人在陪伴者介绍页仍能改、App 保存整份资料时可能覆盖（登记记录里保留研究员的值）；PI 告警只带研究编号，PI 跟进时够不够用 | T19 报告第 2、4 节 | 研究侧 |
| 75 | ADA 第 7 日老人看得到的草稿文字定稿：推送和 24 小时提醒（现【占位】，定稿前服务器不发）、首页卡「第 7 日問卷」、流程说明、预计时间（`day7FlowMinutes`，试跑后定）、第 1 次到访提醒时间页和选项（默认 10:00、14:00、17:00、19:00）、求助弹窗、"做咗一半"等状态字 | T17b 报告第 6 节；决策 0030 | 研究侧；预计时间等试跑 |
| 93 | **T33 S5 入组引导那一屏**：放在通通之后、「完成」之前（截图见 T33 报告）；开关 `app_config/usage_copy.onboardingUsageAdviceEnabled` 何时打开。T20 的 7 处原文不动，等产品窗口写短版 | T33 报告第 3 节 | 负责人 / 产品窗口 |
| 94 | **T33 其余发现**：回忆 B 心情提示「你而家心情點？」还是【占位】，模板开关打开前要定稿；心情脸文字（好差 / 差 / 麻麻地 / 幾好 / 好好）和定稿心情名（好唔開心 … 好開心）不同；签到命中 `moderate_review` 仍不给模板；模板和 S1a 没有英文定稿，英文界面也显示粤语 | T33 报告「要带回研究侧的发现」 | 研究侧 |
| 95 | 网页版构建里 `SafetyService.newTurnId` 用 `nextInt(1 << 32)`，JavaScript 里是 0，签到 B、回忆 B 提交会报错（Android 不受影响）。截图时本地临时改过，没提交 | T33 报告 | 开发（另开任务，改 `lib/core/safety/`，两组同时生效） |
| 96 | ~~**`isTester` 客户端可写，能绕过登记门**~~ 10/15 已做（1014e 第 2 节第 3 条，PR 草稿 `fix/istester-admin-only`）：规则拒绝客户端写 `isTester`，App 不再写，设置页开关改只读，管理员用 `tool/set_tester.js` 或控制台设置。登记门开前要给团队、评估员账号设上 | T21 报告第 4.4 节；决策 0037 | 负责人 |
| 97 | **T37 开关 `onboardingAfterEnrollmentFix` 的上线默认**：W0 装机脚本是“先登记后引导”，关着时伙伴介绍、兴趣、S5 整段跳过。建议在第一位参与者登记前打开（`app_config/feature_flags`），打开那天在 STUDY_CHANGELOG 补一行 | T37 报告第 3 节；现在默认关 | 负责人 |
| 98 | **改配对的日志搬到服务器**：T30 已做（`onUserPairingChanged` → `pairing_change_log`，开关 `pairingChangeServerLogEnabled` 默认关）；App 的 `events` 行保留 | T37 报告第 2.4 节；T30 报告 5.2 | 已做（T30 PR 草稿） |
| 76 | 求助电话号码写进 `app_config/phaseA_schedule.adaHelpPhone`（没写时按钮不拨号，只说研究员会打来）；打开 ADA 前要配好 | T17b 报告第 2 节第 5 条 | 研究侧 |
| 78 | **Phase B 已有的旧 `agent_diff` 数据**：T17 之前的 Phase B 包会在第 14、28 天弹旧问卷。如果有 Phase B 参与者或试用者做过，算偏离还是忽略；T22 后这些数据不进盲法导出，揭盲后怎么用 | T22 报告第 4 节；T17 报告第 10 节第 1 条 | 研究侧 |
| 79 | 旧版导出（`meta/blinding_config.enabled` 关着时的 `exports/`）仍导出 `agent_diff`（uid 换成哈希，`freeResponse` 原文也在）；`tool/admin_dump.js`（单人原始数据，带 uid）也会读出。T22 没改，因为它们也是 Phase A 的导出；要不要在 T21 按研究期分开时一起拿掉 | T22 报告第 2 节 | 研究侧；开发（T21） |
| 91 | App 里没有 PHQ-9（C15 写的是纸本）。“App 内 PHQ-9 第 9 题”的告警来源现在不会触发：以后哪份 App 内问卷、哪一题要触发告警 | T34 先只做入口（`docs/dev-reports/product-reply-20261010.md` 第三节第 1 条） | 产品窗口 |
| 92 | ~~告警邮件的来源“AI 回复扫描”只有 Hybrid 组有，会露出组别。后备收件人 Calvin 要不要保持盲：后备邮件不写来源，或把它并入“老人输入”~~ 10/15 不再需要：后备收件人已取消（1014e 第 2 节第 4 条，PR 草稿 `fix/alert-no-backup`） | 没定之前 T34 按原文写四种来源（同上第 2 条） | 产品窗口 |
| 97 | **「安靜時段」「語音讀出內容」没有接任何功能**（10/14 负责人核对 W0 流程发现）：`settings_page.dart` 两个开关只有页面状态（T37 起会保存），全仓库没有功能读它们，FAQ 还写着可以打开安静时段。定下来之前 W0 不介绍这两项。**10/14 已定并做了**（分支 `fix/quiet-hours-hide-readback`）：语音读出隐藏；安静时段写到 `users/{uid}.quietHoursEnabled`，服务器按人发推送前检查（`functions/quiet_hours.js`），T24 的推送器要接；语音读出以后要接 TTS 另开任务 | 10/14 核对、10/14 做 | 开发窗口分配编号 |
| 98 | **点赞点踩两组不对等、第一周提示没按 Phase B 关闭**：10/14 已在 Phase B 包里两组都隐藏（分支 `fix/phase-b-hide-feedback-nudge`，开关 `replyFeedbackEnabled`、`week1NudgeEnabled` 可恢复）。登记表要补写：Phase B 不收单条回复反馈；第一周提示属 Phase A。这两项要不要在 Phase B 以别的形式恢复，研究侧定 | 10/14 核对 | 研究侧；开发窗口分配编号 |
| 97 | **T34 之后**：`functions/pi_alert.js` 里的研究日 `studyDay`（W0 = 第 0 天，香港日历日）在 T24 合并后改用 T24 的共享函数；研究期已用 T21 的 `study_period.js` | T34 报告第 5 节；dev-tasks-1010b T34 §1.3 | T24 合并后 |
| 98 | **T30 接入**：评估员录入 W4 纸本 PHQ-9 时，在提交处调用 `functions/questionnaire_safety.js` `recordQuestionnaireSafetyEvent(db, {uid, source: 'assessor_entry', instrument: 'PHQ-9', item: 9, rawValue, enteredBy, researchId})`（第 9 题为 0 自动不写）。默认级别 acute 待 Junyu 定（T34 报告「要 Junyu 定的事」第 1 条） | T34 报告第 6 节 | T30 |
| 99 | `PI_EMAIL` 密钥何时停用：`meta/alert_config` 打开并填了 `primaryEmail` 后，密钥只做兜底；研究侧确认后可以从 `onSafetyEventCreated` / `escalateAlerts` 的 `secrets` 列表里去掉 | T34 报告第 4 节；上线清单 B1 | 开关打开后 |
| 100 | 告警邮件的「研究第几天」对试跑账号：现在也从 `users/{uid}.w0Date` 算（T21 登记时写）；任务原文说试跑「从登记日算」，T24 的共享函数定下来后对齐 | dev-tasks-1010b T34 §1.3；T34 报告第 5 节 | T24 |
| 101 | **T30 决策草稿三份待编号**（角色；删除保留一行分配记录；锁库和分析导出），Junyu 定后由开发窗口分配号码，`--allocation-record` 届时改成默认 | T30 报告第 9 节 | 负责人；开发窗口 |
| 102 | **Storage 读权限不在仓库里**：`exports/`、`exports_v2/`、`exports_process/` 只有服务账号能读；要给 `unblinded` 直接下载过程数据，要加 `storage.rules`（按前缀给角色）并进 `firebase.json` 和 CI | T30 报告 4.1、架构观察 5 | 负责人定要不要；开发 |
| 103 | **序列上传端到端**：`uploadRandomizationSequence` 和工具两步各有测试，但没在 Functions 模拟器整条跑过；Calvin 上线前先对模拟器试一次（`--only auth,functions,firestore`） | T30 报告第 13 节 | Calvin；开发 |
| 104 | **PHQ-9 规格文件到了接题目**：改 `functions/outcome_instruments.js` 的文字和 App 常量、加录入页入口和逐字测试，不改结构 | T30 报告 3.4 | 研究侧给文件；开发 |
| 105 | **T24 合并后**：`functions/assessor.js` `w4Window` 改用 T24 的研究周函数；T24 读 `weekly_status/{uid}.w4VisitDate` 关第 4 周。**T35 合并后**：`completionSummary` 加 W8 一行 | T30 报告第 10 节 | T24、T35 |
| 106 | **评估员账号不收推送**没有自动测试（`FcmService.suppressForStaff`）；真机核对 `users/{uid}/fcm_tokens` 为空 | T30 报告第 7 节 | 上线前真机 |
| 101 | **T27 语音开关打开前**：① Junyu 在 Google Cloud 控制台再核对一次 Speech-to-Text 的 data logging 是关的，截图归档（步骤见 T27 报告第 6 节）；② HREC 对 STT 修订的批准文件到了再开；③ 打开当天在 `docs/STUDY_CHANGELOG.md` 补一行 | dev-tasks-1010 §三 T27 第 4 条；T27 报告 | Junyu；研究侧 |
| 102 | `stt_usage` 集合（每次转写一行：uid、字节数、耗时、次数、成功与否、失败类别）要不要保留；保留的话删除脚本 `tool/delete_participant.js` 要一起删这个人的行（现在没有） | T27 报告第 5 节 | Junyu |
| 103 | 英文界面的 S6 没有定稿，现在是【占位】（只有测试员和研究员会看到英文界面）；要不要补一句英文定稿 | T27 报告第 2 节 | 研究侧（低优先） |
| 102 | **没登记的账号算不算“测试员”**：`tool/purge_tester_data.js` 把没有 `cohort` 的账号（`unenrolled`）和 `isTester` 一起列为可删。10/19 前如果有真实老人已装 App 注册、还没由 Junyu 登记，会出现在这个名单里。选项：(a) 删除前逐个核对名单（现做法，I1）；(b) 只删 `--only=testers`，没登记的账号留到登记门打开后再处理；(c) 用 `--created-before=<日期>` 只删某天之前建的账号 | T32 报告「要 Junyu 定的事」 | Junyu，10/19 前 |
| 103 | **每周推送钟点**：`weeklyPushHour` 默认 20（沿用现在星期日 20:00 的每周推送）。T18 的 DJG 推送是 10:00。20:00 推送意味着窗口在第 10 天 20:00 关，老人晚上收推送。Junyu 定钟点后在控制台改一个数字即可 | T24 报告「要 Junyu 定的事」 | Junyu，开关打开前 |
| 104 | **W4 问卷延到面访当天结束**：`week4CloseFor(w0Date, w4VisitDate)` 已留钩子，所有调用处现在传 null（只按第 29 天关）。T30 合并后把评估员录入的 W4 施测日期接进去（服务器 `functions/weekly_schedule.js` `windowFor` 的 `opts.w4VisitDate`、App `PendingPromptsService.weeklyBundleDue`） | T24 报告第 3 节 | T30 之后 |
| 105 | **每日心情提醒仍是主题广播**（`dailyMoodReminder`，`topic: all`），没登记的账号也收到，也不看安静时段。T24 只把每周提醒改成按人发。要不要改成按人发（成本：每天 72 人 × 设备数的单发） | T21 报告 4.5；T24 报告「交叉」 | Junyu |
| 106 | ~~**流程、推送的最终文字**：每周问卷的推送两句、流程开头说明、四个部分的名称、首页卡片两句，全部是【占位】~~（10/15 第 6 条已定稿 S14 并接入，PR 草稿 `fix/copy-1015-item6`；开头第二句「可以隨時停，下次會由停低嗰度繼續。」产品窗口没给，沿用原文，待 Junyu 确认）| T24 报告第 7 节；`docs/dev-reports/copy-1015-item6-20261015.md` | 等 Junyu 回「可以」后合并 |
| 107 | **旧的每周孤独探针代码**（`lib/features/loneliness_probe/`、`weeklyLonelinessProbe`）现在没有任何页面挂它，`WEEKLY_PROBE` 编译开关默认关，服务器只给 `weeklyProbeEnabled: true` 的用户排队。登记表 C15 写「不含」，可以在 Phase A 代码清理时一起删 | T24 报告第 8 节 | T32 以后 |

## 4. 暂缓或以后再做

- 端到端测试用例表（暂缓）。
- 单独的 staging Firebase 项目（不需要）。
- 函数代码约 880 个 lint 格式错误一次性修复，之后 CI 检查格式。
- Dependabot 自动更新依赖。
- Android 正式签名（现在用调试密钥，只能内部测试；GitHub 每次打包的调试密钥都不同，装新包要先卸载）。换密钥的步骤和影响见 `docs/dev-reports/T36-apk-phase-b-templates-20261014.md` 第三节，建议 10/19 前定。
- 记忆 P2：RAG、人生叙事摘要、遗忘、对话中确认、按内容共享、多条待跟进、删除 v0（见规格第 5 节）。
- 回忆 A 组研究记录仍保存 acute 那一轮原文（研究数据的决定，未改）。
- **代码瘦身批次 SL1–SL8**（任务单 `docs/dev-tasks/dev-tasks-slim.md`，内容是交接 `docs/dev-reports/handoff-20261014.md` 第五节的七步）：10/19 前只做 SL1（记忆评测原始输出移出仓库）；SL2（Phase A 先 fork 再删，决策 **0040** 提议中，产品窗口确认后开工）、SL3、SL5 在冻结后、W4 前；其余试跑后。单独会话做，功能 PR 合完再开。
- **Phase A 暂停**（决策 0034，产品窗口 10/10 第 10 条）：ADA、第 7 日问卷、Phase A 的 DJG、`PA-` 配置在构建里保持关闭，不再开发，代码暂不删；以后单独开仓库和 Firebase 项目，另行交接。第 61–63、75、76 项随之暂缓。
