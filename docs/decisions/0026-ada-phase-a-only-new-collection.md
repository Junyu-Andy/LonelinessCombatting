# 0026：ADA 新做成一屏一项的 Phase A 问卷，存独立集合；旧的“陪伴者区分评估”保留，Phase B 默认关掉

- 日期：2026-10-07
- 状态：提议中（代码在开关后面，默认关；题目措辞、时间点、回忆窗口等研究侧和 EA260417 批复）
- 影响范围：phase_a × 两组（ADA、第 7 日开放题，默认关）；phase_b × 两组（旧 agent_diff 入口默认关）
- 相关代码：`lib/features/ada/`、`lib/core/config/phase_a_schedule_config.dart`、`firestore.rules`（T17，分支 `feat/ada`，SPEC:C22）

## 背景

研究侧要把 ADA（三个陪伴者的分辨问卷，Phase A 问卷 v1.3 附件 C）做进 App，只用于 Phase A：第 1 次到访当场一次、第 7 日一次。App 里已有一个“陪伴者区分评估”（`agent_diff`，第 14、28 天，两组、两种构建都出现）。它的题目来源相同，但结构和附件 C 不符：一页一个矩阵、不能跳过、不逐屏保存、没有表单版本和输入方式字段，部分 A 默认选“完全冇”，D 题问的是“仲有咩想補充”。登记表 v2 的 C15 写明 Phase B 不含 ADA，但现在 Phase B 构建也会弹它。

## 决定

- **新做，不改旧的**。新页面 `AdaPage`，数据存 `users/{uid}/ada_responses/{时间点}`。旧页面、旧集合 `agent_diff` 和已有数据都不动。
- **表单可配置**：短版 = A+B+D，全版 = A+B+C+D。哪个时间点用哪一版、在入组第几天出现、回忆窗口的文字、能否跳过，都从 `app_config/phaseA_schedule` 读。
- **一屏一项**：A 一屏（三个陪伴者各一行），B 每个特质一屏，C 每个情境一屏，D 一屏。可返回，每换一屏保存一次。默认允许跳过，跳过的题记 `"skipped"`。
- **只在 Phase A**：`PHASE_B=true` 的构建里，ADA 和第 7 日开放题的入口一律不出现，配置写什么都不管用。Phase A 构建里也要研究侧打开 `adaEnabled` 才出现（默认关）。
- **旧入口**：Phase B 构建默认不再显示旧的 agent_diff（按 v2 规格）；编译开关 `LEGACY_AGENT_DIFF_PHASE_B=true` 可恢复。Phase A 构建里，`adaEnabled` 打开后旧入口让位给新 ADA，避免同一个人做两次相近的问卷；关着时和现在一样。
- **第 7 日 3 道开放题**：复用 D 部分的长文字组件，存 `users/{uid}/day7_open_responses/day7`，开关 `day7OpenEndedEnabled` 默认关。
- **安全**：D 部分和开放题的文字经 `SafetyService`，新增输入点 `ada_free_text`、`day7_open_ended`。
- **研究编号**：App 拿不到研究编号（决策 0021，编号只在服务器、只有非盲角色能读），文档里存 `uid`，分析时由服务器按 `research_id_map` 换。
- **规则**：两个新集合只有本人能读写；提交后不能再改；客户端不能删。整人删除脚本会删到它们。ADA 不进 Phase B 盲法导出。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 改造旧 agent_diff 页面 | 旧集合已在盲法导出白名单里，字段结构不同；改了会让旧数据和新数据混在一个集合、一个时间点字段里，分析时难分开。旧页面在 Phase B 构建里还在用（开关打开时） |
| 新 ADA 存进 agent_diff 集合，加版本字段 | 同上；而且 agent_diff 会进 Phase B 盲法导出，ADA 只属于 Phase A |
| 时间表写进现有 `app_config/phase_a` | 这份文档两期共用（T21 要拆）。新键单独放 `app_config/phaseA_schedule`，名字就说明只属于 Phase A，T21 迁移时整份搬 |
| 旧入口的 Phase B 开关放远程配置 | 远程配置现在两期共用，改一下会同时影响两期；编译开关只跟 Phase B 包走 |

## 后果

- 对研究：ADA 的题目、回忆窗口、时间点、短版/全版分配、第 7 日开放题都是占位，要研究侧定稿和 EA260417 批复。Phase B 构建不再出现旧 agent_diff，和 C15 一致；如果已有 Phase B 参与者见过它，要写进偏离记录。
- 对开发：新增 `lib/features/ada/`、一份配置、两个集合的规则；T21 拆分配置时把 `app_config/phaseA_schedule` 归到 Phase A。
- 对论文：Phase A 方法部分写 ADA 的施测时间和版本；Phase B 不报告 ADA。
