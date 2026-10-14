# 0033：安全分类器（LoRA）两组、两期和试跑共用；只给级别和分数，只触发两组相同的安全流程；记录带消息编号

- 日期：2026-10-09
- 状态：已采纳（研究侧 10/8 第 1 条定"两组共用"）。开关仍默认关，没有模型
- 取代：决策 0025 里"两组是否都用"这一部分（0025 其余内容仍有效：接口、经 Cloud Function 中转、只升不降、回退、开关）
- 影响范围：所有 cohort（Phase A、Phase B、试跑）× 两组（开关打开后）；开关关着时没有任何影响
- 相关代码：分支 `feat/lora-both-arms-v2`（T26，SPEC C13，登记表 v5；10/10 按 `dev-tasks-1010.md` 第三节补 Phase A 和试跑）

## 背景

决策 0025 把分类器做成两组共用的槽位，但"规则组的原话也发给分类器"留给研究侧确认（backlog 58）。研究侧 10/8 第 1 条定了：两组共用。登记表 v5 的 C13 写明：只输出风险等级和分数，不产生老人看得到的文字；结果只触发两组相同的安全流程；记录风险等级、分数、时间、对应消息编号。

核对现状时发现：分类器调用记录（`safety_classifier_calls.turn_id`）和安全事件（`safety_events.turnId`）已经带同一个编号，但老人的消息记录（`users/{uid}/turns`）里没有这个编号，两边连不起来。

## 决定

1. **两组共用，不分组**。规则组的签到 B、回忆 B、通通 B、入组开放题、表单页，和 Hybrid 组的聊天，走同一个 `checkUserTextClassified`（`lib/core/safety/safety_check.dart`），同一个 Cloud Function `classifySafety`。服务器不读组别，也不按组别分支。
2. **只给级别和分数**。`classifySafety` 只回 `{status, level, score, modelVersion}`；模型多给的字段（包括文字）丢掉。分类器不产生老人看得到的任何文字。
3. **只触发两组相同的安全流程**。分类器的结果只和词库合并（只升不降），然后走原来的安全流程：acute 危机页、moderate_interrupt 支援面板、写 `safety_events`、acute 通知 PI。没有给分类器单独的页面或文字。
4. **"规则组不调用 LLM"不变**。分类器不是对话模型：不生成回复、不改对话内容。`assertLlmAllowed` 和 `proxyDeepSeek` 都不动；规则组调用对话模型仍被拒。
5. **记录**（两组字段相同）：
   - `safety_classifier_calls`：`ts`（时间）、`level`、`score`、`status`、`model_version`、`turn_id`（消息编号）等，不存原文、不存组别（T8 已有，不改）。
   - `safety_events`：`createdAt`、合并后的 `tier`、`classifierLevel`、`classifierScore`、`turnId`（T8 已有，不改）。
   - **新增** `users/{uid}/turns/{doc}.safetyTurnId`：和上面两处是同一个编号，两组都写（Hybrid 组来自 `LlmGateway`，规则组的签到 B、回忆 B、通通 B 由页面生成后传给安全检测和记录）。这样一条安全记录能对到是哪一条消息。开关关着时也写（编号本来就有）。
   - 表单页、入组开放题没有 `turns` 记录，编号只在两条安全记录里。
6. **开关仍默认关**：`app_config/phase_a.safetyClassifierEnabled` 和 `meta/safety_config.classifierEnabled` 都开才生效。接入要的地址、鉴权、部署机器写进 `docs/release/prelaunch-checklist.md` H 节。
7. **两期和试跑也一样**（研究侧 10/9 第 19 条，`dev-tasks-1010.md` 第三节 T26）：Phase A、Phase B、试跑用同一个分类器、同一套安全流程、同两个开关。App 和服务器都不读构建（`PHASE_B`）或研究期来决定问不问分类器。Phase A 特有的输入（ADA 自由作答、第 7 日开放题）也问分类器。T21 拆分配置时，这两个开关不能拆成每期一份。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 只给 Hybrid 组用 | 研究侧已定两组共用；也违反"安全检测两组一致" |
| 开关按研究期分开（Phase A 一份、Phase B 一份） | 研究侧 10/9 第 19 条定了两期和试跑同一套安全组件；分开就可能一期开、一期关 |
| 编号另起一个字段名（如 `messageId`） | `turnId` 已经在两条安全记录里用了，再起一个名字反而难对；`turns` 里只加一个指向它的字段 |
| 把 `turns` 的文档编号当消息编号，回写到安全记录 | 安全事件在消息记录之前写（危机页不能等），回写要多一次更新，离线时更复杂 |

## 后果

- 对研究：规则组多一条外发路径（原话去掉电话等后发给分类器）。打开前 DMP、ICF 要写明，HREC 是否修订由研究侧定。决策 0025 里的离线不对等、误报减少干预剂量这两个问题仍在（backlog 60）。
- 对开发：`chat_session_recorder.dart`（`turns` 加 `safetyTurnId`）、`rule_submission_flow.dart`、签到 B、回忆 B、通通页各一处；测试在 `test/safety_classifier_test.dart`。服务器和规则不改。
- 对论文：安全监测一节写"词库 + 分类器，两组相同，分类器只能调高级别、只给级别和分数"；局限里写离线时规则组只有词库。
