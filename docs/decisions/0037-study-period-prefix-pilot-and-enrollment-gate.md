# 0037：研究期按研究编号前缀定；试跑版本由负责人指定、不占序列；登记前只显示等待页、不收研究数据（登记门，开关默认关）

> 2026-10-19：「`PB-…` 为 Phase B 前缀」一条由 `0051-rct-cohort-and-sequence-v2.md`（已采纳）部分取代：10/21 起新登记用 RCT-（cohort `rct`，序列 v2），PB- 停止新登记，PB-01 至 04 作 run-in。其余不变。

- 日期：2026-10-14
- 状态：提议中（暂按默认，待 Junyu 确认）。随 T21 的 PR #59 合并；本记录里的六项“暂按默认”是负责人 10/14 的过渡做法，每一项都写了怎样回退
- 影响范围：phase_b、pilot × 两组（登记、研究期字段、登记门对两组完全相同）。Phase A 暂停（决策 0034），不涉及
- 相关代码：分支 `fix/phase-config-split`（T21，SPEC:C01，PR #59）。`functions/study_period.js`、`functions/randomization.js`（`enrol`、`enrolPilot`）、`functions/index.js`（`assertLlmAllowed`、`enrollParticipant`、`week2Push`、`memorySweep`）、`functions/memory.js`（`inScope`）、`firestore.rules`、`lib/features/enrollment/`（登记页、`enrollment_wait_gate.dart`）、`lib/core/feature_flags/remote_feature_flags.dart`
- 取代：决策 0011 里 `pilot` 这个值的含义（原指“现有全部旧账号”，现指 `PILOT-` 试跑账号）和“删掉 `PHASE_B` 编译开关”这一句（现为保留）。0011 的其余内容（字段名 `cohort`、只有服务器能写、按 `cohort` 筛数据）不变。报告：`docs/dev-reports/T21-phase-config-20261014.md`

## 背景

研究侧 10/9 定了研究期按登记编号的前缀区分、登记前只显示等待页、两期都由负责人登记（`docs/dev-tasks/dev-tasks-1010.md` 第三节 T21）；10/10 定了 Phase A 暂停，登记只认 `PB-` 和 `PILOT-`（决策 0034；`dev-tasks-1010b.md`）。T21 第一部分已经照这些要求做好（PR #59），报告最后一节留了 6 件要负责人定的事。10/14 负责人的答复是“改动最少、可以回退”：先按现有做法合并，等数据收集（10/19）开始前定下来。这份记录把已定的做法和这 6 项过渡默认写下来，不再分散在任务单和报告里。

## 决定

### 已定的做法（T21 已实现）

1. **研究期由研究编号的前缀决定**，服务器在登记时按前缀写、客户端不能写（`functions/study_period.js` `periodForResearchId`；`firestore.rules` 把 `cohort` 列进只有服务器能写的字段）：
   - `PB-…` → Phase B：`users/{uid}.cohort = "phase_b"`，`enrollments/{uid}.studyPeriod = "B"`；
   - `PILOT-…` → 试跑：`users/{uid}.cohort = "pilot"`，`enrollments/{uid}.studyPeriod = "PILOT"`；
   - `PA-…` 和没有这两个前缀的编号，登记时拒绝（错误码 `research_id_prefix`），什么都不写。编号其余部分仍按 T19 的格式规则，前缀后面必须还有字。
2. **试跑的版本由负责人在登记页指定**（Hybrid 或规则组），确认框里再选一次，两次一样才能提交；不填 W0 情感分、不占分配序列（两层序列的指针不动，`arm_assignment_log` 不加行）；写 `armAssignmentMode: "pilot_designated"`，每次写一条 `pilot_assignment_log`（研究编号、版本、时间、操作人）。试跑的 Hybrid 账号和 Phase B 的 Hybrid 一样有服务器记忆；试跑不进盲法导出。
3. **登记门**：开关 `app_config/feature_flags.enrollmentGateEnabled`，**默认关**，只认布尔 `true`。开时，没有 `cohort`、也不是测试账号（`isTester: true`）的账号：App 只显示等待页 S8（`docs/spec/copy/short-texts.md`，定稿文字逐字照抄，没有按钮、研究期、组别字眼或电话）；服务器拒绝它的 LLM 调用并记 `llm_denied_log`（`reason: "not_enrolled"`）；Firestore 规则不让它写 `users/{uid}/` 下的研究数据（推送令牌 `fcm_tokens` 和用户文档本身除外）。关时和以前完全一样。规则组本来就被拒绝 LLM，这一条在登记门之前判断，不变。

### 六项过渡默认（10/14 负责人答复：改动最少、可以回退）

| # | 事项 | 暂按默认 | 怎样回退 / 以后怎样改 |
|---|---|---|---|
| 1 | 编译开关 `PHASE_B` | **保留**。参与者包固定 `PHASE_B=true`（Build APK 的 `phase_b` 选项，T36 加 `phase_b_templates`），就已经是“同一个构建”；Phase A 专用行为在这个包里已被 `AdaGate` 等关住 | 以后要删或改成按研究期在运行时判断，另开任务改 8 个文件（T21 报告第 5 节的表），不影响这次合并 |
| 2 | `cohort` 的值 `pilot` | **指 `PILOT-` 试跑账号**（取代 0011 里“现有全部旧账号标 `pilot`”）。旧测试账号不标记，按 T32 的清理脚本删除 | 要换成另一个值（例如 `pilot_run`）只改 `functions/study_period.js` 的 `PERIODS` 和 `ENROLLED_COHORTS`，以及 `blinding.js`、`djg_w2.js` 里对 `pilot` 的判断；现在没有人登记过，没有数据要迁 |
| 3 | 决策记录 | **写本记录 0037**（编号由负责人分配），0011 顶上加一行“`pilot` 的含义已由 0037 取代” | 本记录状态改为“已采纳”或由新记录取代 |
| 4 | `isTester` 客户端可写 | **不改**。测试员工具里的开关要先输入测试密码（`TESTER_PIN`）才看得到，密码只给团队；缺口记进 backlog 第 96 项 | 要堵上就把 `isTester` 加进 `firestore.rules` 只有服务器能写的字段，测试员工具里的开关改成只显示，由脚本或控制台设 |
| 5 | 试跑的研究日起点 | **登记当天**（服务器把登记日的香港日期写进 `w0Date`），按任务单“试跑用登记日” | 要改成登记页填日期：登记页对 `PILOT-` 显示 W0 日期栏，`enrolPilot` 用传入的日期（和 `PB-` 一样） |
| 6 | 登记门什么时候开 | **默认关，这次合并不开**。什么时候开仍待定：等 T24（推送按人发、跳过未登记）和 T30（评估员账号不进等待页）之后开最稳；要提前开，就接受 T21 报告第 4.5 节的缺口（广播推送仍会发给未登记的手机；团队账号要先设成 `isTester: true`） | 开关在 `app_config/feature_flags`，随时可关；关了就和现在一样 |

### 10/14 任务单更正

评估员账号（`blinded` 角色）和登记门的关系交 T30（`docs/dev-tasks/dev-tasks-1014.md` 第三节 T30 第 3 条：评估员按角色直接进评估员视图，不进等待页、不收参与者推送）。T21 不改。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| App 里加研究期单选，由研究员登记时选 | 研究侧 10/9 定了按编号前缀，少一个要人手选、可能选错的格子 |
| 研究期另起字段 `studyPeriod` 放在 `users/{uid}`，不用 `cohort` | `blinding.js`、`djg_w2.js`、`ada.js` 已先看 `cohort`，用它不用改这三处；`enrollments/{uid}.studyPeriod` 仍保留给研究员看 |
| 试跑另起一个 `cohort` 值（如 `pilot_run`），把 `pilot` 留给旧账号 | 旧账号按 T32 删除，不会标 `pilot`，两种含义实际不会混；现在改值要多改三处判断。列为第 2 项的回退路径 |
| 现在就把 `PHASE_B` 改成按研究期在运行时判断 | 要改 8 个文件，而且没登记的人该显示哪种界面要另定；登记门开着时这个问题不存在。负责人要的是改动最少 |
| 这次合并就打开登记门 | T24、T30 没合并前有缺口（广播推送、评估员账号）；开关随时可开，不必和合并绑在一起 |
| 试跑登记时填 W0 日期 | 任务单写“试跑用登记日”；试跑只跑 7 天，当天登记当天开始最简单。列为第 5 项的回退路径 |
| 把 `isTester` 改成只有服务器能写 | 会影响现有测试员工具的流程；测试密码只给团队，先接受。列为第 4 项的回退路径 |

## 后果

- 对研究：研究编号的前缀就是研究期，登记表 C01 的“研究期”不必另问；试跑数据带 `cohort: "pilot"`，正式导出按 `phase_b` 筛，试跑不进盲法导出；登记门开之前，注册后、登记前这段时间的数据仍按决策 0004 / backlog 第 13 项处理。要修订的文件：登记表 C01 已写明（v8）；protocol、ICF 不涉及（登记门只影响登记前的屏幕）。
- 对开发：这次合并不改任何默认行为；`enrollmentGateEnabled` 默认关。T24、T27、T30、T34、T35 判断研究期请直接用 `functions/study_period.js` 的 `isEnrolled`、`periodForResearchId`，不要另写一套。六项里任何一项改主意，按表里“怎样回退”一栏改，都不需要迁数据。
- 对论文：方法部分写“研究期由研究编号前缀标记；试跑由研究员指定版本，不进随机序列”；登记门不进论文（它只管登记前的屏幕）。局限部分不用加。
