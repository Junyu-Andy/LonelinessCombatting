# 0033：安全分类器（LoRA）两组共用；只输出风险等级和分数；每条记录带对应消息编号

- 日期：2026-10-09
- 状态：已采纳（取舍由研究侧 10/8 第 1 条定下；开关仍默认关，因为还没有模型）
- 取代：决策 0025 里"两组是否都用"的部分（0025 第 1 点最后一句和"后果"里"打开开关之前要研究侧和 PI 确认"）。0025 的其他内容（独立接口、经 Cloud Function 中转、只升不降、回退、离线、开关）不变，继续有效
- 影响范围：所有 cohort × 两组（开关打开后）；开关关着时参与者没有任何变化
- 相关代码：分支 `feat/lora-both-arms`（T24，SPEC C13）

## 背景

决策 0025（T8）把分类器槽位做成两组共用，但核心取舍没定：规则组老人的原话（去掉电话等）也会发给分类器，这是规则组新的外发路径。研究侧 10/8 第 1 条定了：两组共用。登记表 v3 的 C13 同时要求只输出风险等级和分数、只触发两组相同的安全流程、记录风险等级、分数、时间和对应消息编号。

## 决定

1. **两组共用**。规则组和 Hybrid 组的老人原话都送分类器（App 生成的模型输入、搜一搜搜索词仍不送）。"规则组永远不能调用 LLM"不变：分类器不是对话模型，不经过 `proxyDeepSeek`，`assertLlmAllowed` 不动。
2. **只输出风险等级和分数**（外加模型版本号）。服务器把模型回的其他字段全部丢掉，App 和日志都拿不到任何文字。结果只用来决定安全级别，后面走两组共用的安全流程（危机页、支援面板、PI 通知），不产生老人看得到的新文字。
3. **两组的安全流程完全一致**。补了一个 T8 留下的不一致：Hybrid 组通通的"搜一搜已关"固定回应以前只看词库；开关开时，规则组通通在选固定回应前会问分类器，Hybrid 组却不问。现在 Hybrid 组也先问，被调高就走正常流程（网关里再查一次，用同一个消息编号，服务器只算一轮）。
4. **对应消息编号**：一条老人消息只有一个编号（`turnId`，App 生成）。以前它写在 `safety_events.turnId` 和 `safety_classifier_calls.turn_id`，但**没有写进消息本身的记录**（`users/{uid}/turns`），所以连不回是哪条消息。现在 `turns` 每条加 `safetyTurnId`，两组同一个字段名、同一个来源：
   - Hybrid 组：网关的检测编号（`LlmGateway.send` 返回的 `turnId`）；
   - 规则组：签到 B、回忆 B、通通 B 的检测编号（`SafetyCheckResult.turnId`）。
   这个字段不受开关控制（词库事件也需要能连回消息），不是老人看得到的东西。
5. **记录内容两组相同**：`safety_classifier_calls` 每条有级别、分数、时间（`ts`）、消息编号（`turn_id`）、模型版本、状态、延迟；不存原文、不存组别。`safety_events` 达到 moderate 时写一条，带同一个 `turnId`。
6. **盲法**：`safety_classifier_calls` 的 `input_point` 取值两组不同，原样导出会揭盲。正式写进盲法导出的 `HELD_BACK` 清单（以前只是不在白名单里）。
7. **开关仍默认关**：`app_config/phase_a.safetyClassifierEnabled`、`meta/safety_config.classifierEnabled` 都要开，并填好 `classifierUrl`，才生效。接入要的地址、鉴权和部署机器写进上线清单（`docs/release/prelaunch-checklist.md` H 节）。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 只给 Hybrid 组用 | 违反"安全检测两组必须完全一致"；研究侧已定两组共用 |
| 把 `turns` 的文档编号直接当消息编号 | 检测发生在消息写入之前（危机页不能等写入），而且规则组的签到、回忆是先检测后建会话；改顺序会动安全时序。另加一个字段最小、两组一样 |
| 消息编号只在开关打开时写 | 词库事件现在就连不回消息，PI 复核也需要；字段不影响参与者 |
| 给表单页（Thought Exercise、每周问卷等）的记录也加编号 | 表单有十几个页面，各自存在不同集合；本次只做对话类消息，表单按 uid + 时间对，列入待办 |

## 后果

- 对研究：DMP、ICF 要写明"两组老人输入的文字（去掉电话等）会发给研究团队的安全分类器，只返回风险等级"；HREC 是否要修订由研究侧定。打开开关当天在 STUDY_CHANGELOG 补一行。分析时 `safety_events.turnId` = `safety_classifier_calls.turn_id` = `turns.safetyTurnId`。
- 对开发：`lib/core/session/chat_session_recorder.dart`（`safetyTurnId`）、`lib/core/llm/llm_gateway.dart`（可传入已有编号）、`rule_submission_flow.dart`、签到 B、回忆 B、通通页；`functions/blinding.js`（`HELD_BACK`）。
- 对论文：安全监测一节写"词库 + 分类器，两组相同，分类器只输出风险等级和分数、只能调高级别"；局限仍写离线时规则组只有词库（0025 第 6 点）。
