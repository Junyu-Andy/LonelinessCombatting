# NNNN：行动计划只必填「做咩」「幾時」、可以改和删；Hybrid 组计划用上小欣的记忆（编号待 Junyu 给）

- 日期：2026-10-20
- 状态：提议中（Junyu 10/20 定做，1020e 二.7；看 PR 截图定字后采纳）
- 影响范围：pilot / phase_b × 两组（第 1 部分两组同一规则）；第 2 部分只有 Hybrid 组（规则组没有模型调用）
- 相关代码：分支 `claude/zealous-fermat-8rgqtg-actionplan-impl`；`lib/features/action_loop/`、`functions/memory.js`、`functions/reminders.js`；现状报告 `docs/dev-reports/action-plan-current-20261020.md`（PR #129）

## 背景

Junyu 反映两件事：从建议进行动计划要填很多项；订好的计划不能改。PR #129 的现状报告证实：Hybrid 组要连续打 4 次字（每项必填，空着按「下一步」没反应），规则组 4 组选项都要选；订好的计划不能改、不能删，答完「件事點呀」就看不到。另外 10/19 第 36 条 (a)：计划生成要接上小欣的记忆。现在 Hybrid 组计划页的两次模型调用不带陪伴者编号，服务器不加任何记忆。

## 决定

**第 1 部分：开关 `app_config/feature_flags.actionPlanSimplifiedEnabled`（默认关，只认布尔 `true`）**

1. 两组同一条规则：必填只有「做咩」和「幾時」；邊度、同邊個、唔得點可以不填。从建议进去，「做咩」预填建议原文，看得到、可以改，所以老人只需填「幾時」。
2. 页面样子维持两组现在的差别：Hybrid 组一问一答（做咩 → 幾時 → 檢視，「加多啲細節」可选，三步各可「跳過」）；规则组一页选项（只有「幾時」必选，其余可不选、再撳可取消）。
3. 「等住跟進」里的计划可以改「做咩」「幾時」（两组同一页，不用模型），可以删除（先确认）。
4. 删除是软删除：计划留在数据库，写 `deletedAt`；App 删掉它未发的提醒；服务器 `dispatchReminders` 见到 `deletedAt` 也不发。
5. 改「幾時」不移动提醒：提醒本来就固定在存后 24 小时，和「幾時」无关。不写 `scheduledFor`（否则首页隐藏的横幅会出现）。
6. 只加新字段，不改旧字段名：`planFormVersion: 2`、`source`、`seedAction`、`original`、`editCount`、`lastEditedAt`、`editLog`、`deletedAt`、`deletedFrom`；事件 `m7_plan_saved`、`m7_plan_edited`、`m7_plan_deleted`（不带老人原文）。开关关时一个都不写。
7. 改过的文字两组都过同一套安全检测（`SafetyService.checkAndRoute`，输入点 `action_plan`）。

**第 2 部分：开关 `app_config/feature_flags.actionPlanMemoryEnabled`（默认关，只认布尔 `true`），另开一个开关，方便两部分分开开**

1. Hybrid 组计划页「檢視」那句（`m7_action_loop_summary`）和「件事點呀」回应（`m7_action_loop_followup`）带上 `agentId: siu_yan`；服务器把这两个模块加进 `INJECT_MODULES`，注入小欣的记忆块（和其他小欣对话同一套选择、分层、长度上限）。
2. 小欣到期要关心的事（follow-up）**不**在这两处放、也不在这两处用掉：和 1020c 对 `m6_suggestions` 的处理一样。
3. 这两句的提示词仍写在 App 里（不搬文件）；开关开时换成新版：自称「小欣（一個電腦程式夥伴）」，可用记忆里讲过的人和习惯，不作没讲过的人和事，不提唔想提起的话题。旧版原样保留给开关关时用。
4. 规则组开或关都没有模型调用；服务器的组别拒绝照旧。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 两组用同一个计划页 | 规则组「幾時」会变成自由文字，Hybrid 组的模型总结也要动，改动大，数据含义变化多 |
| 「幾時」改成真正的日期钟点，提醒跟着走 | 要改提醒和首页横幅，超出冻结前能做完的范围；留到 Phase B 之后 |
| 硬删除 | 「订了几个计划」会少掉，查不回来 |
| 两部分共用一个开关 | 记忆部分只影响 Hybrid 组，Junyu 可能想分开开；分开更容易回退 |
| 计划页也放小欣的 follow-up | 计划页不是对话，放了会让小欣之后不再问，和 1020c 对建议页的决定矛盾 |

## 后果

- 对研究：第 1 部分两组同一规则，组间对等不变；但开关前后「填了几项」不能直接比（用 `planFormVersion` 区分）。改过的计划 `action`／`whenText` 是最新版本（最初版本在 `original`）；规则组 `whenText` 改过后可能是自由文字（`editCount > 0`）；`whereText`／`whoWith`／`fallback` 可以是空字串。第 2 部分改了 Hybrid 组的干预内容（计划用上记忆），开开关那天要记 STUDY_CHANGELOG；冻结后合并算 protocol deviation。
- 对开发：计划页两个、列表页、跟进页、新的改计划页、数据层、两处服务器函数；新测试覆盖两组、开关开关、规则组零模型调用。
- 对论文：方法部分 M7 一句（必填项、可改可删、Hybrid 计划用记忆）；数据字典加新字段。
