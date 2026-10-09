# T24 LoRA 两组共用（2026-10-09，SPEC:C13）

> 分支 `feat/lora-both-arms`。决策 0033（取代 0025 里"两组是否都用"的部分）。没连生产 Firestore；只用单元测试、emulator 和合成句子。

## 结论先说

1. **两组共用写成决策 0033**，0025 标了部分 Superseded（`docs/decisions/0033-lora-classifier-both-arms.md`、`docs/decisions/0025-safety-classifier-slot-both-arms.md` 第 4 行）。
2. **只输出风险等级和分数**：T8 已经这样做，本次核对没改（`functions/safety_classifier.js` `parseModelResponse`、`classify` 只返回 `{status, level, score, modelVersion}`；`lib/core/safety/safety_classifier.dart` `ClassifierVerdict` 没有文字字段）。
3. **消息编号缺了一半，已补**：分类器记录和安全事件本来就有编号，但消息本身的记录（`users/{uid}/turns`）没存，连不回是哪条消息。现在 `turns` 加 `safetyTurnId`，两组同一个字段（第 2 节）。
4. **补了一处两组不一致**：开关开时，Hybrid 组通通"搜一搜已关"固定回应以前只看词库，规则组会问分类器。现在两组都问（第 3 节）。
5. **开关仍默认关**（没有模型）。接入要的地址、鉴权、部署机器写进上线清单 H 节（`docs/release/prelaunch-checklist.md`）。

## 1. 开关（没改）

| 开关 | 位置 | 默认 |
|---|---|---|
| `safetyClassifierEnabled` | `app_config/phase_a`（App 启动时读） | 关 |
| `safetyClassifierTimeoutMs` | 同上 | 1500 |
| `classifierEnabled`、`classifierUrl`、`classifierTimeoutMs`、`classifierMaxChars` | `meta/safety_config`（服务器） | 关 / 无 / 1200 / 1000 |
| `SAFETY_CLASSIFIER_TOKEN` | Functions 环境变量 | 无 |

`turns.safetyTurnId` **不在开关后面**：它只是记录字段，词库事件现在也需要连回消息，老人看不到。这是本次唯一部署即生效的改动。

## 2. 记录字段核对（两组）

| 记录 | 风险等级 | 分数 | 时间 | 消息编号 | 改动 |
|---|---|---|---|---|---|
| `safety_classifier_calls`（服务器行） | `level` | `score` | `ts` | `turn_id` | 无（`functions/safety_classifier.js` `classify`） |
| `safety_classifier_calls`（App 回退行） | 无（没拿到结果） | 无 | `ts` | `turn_id` | 无（`safety_classifier.dart` `FirestoreClassifierFallbackLog`） |
| `safety_events`（moderate 以上） | `level`/`tier`、`classifierLevel` | `classifierScore` | `createdAt` | `turnId` | 无（`safety_event_writer.dart`） |
| `users/{uid}/turns`（每条消息） | `detector.tier` | — | `ts.userSent` | **新 `safetyTurnId`** | `chat_session_recorder.dart` `TurnRecord.toMap` |

`safetyTurnId` 的来源：

| 组别 | 入口 | 来源 |
|---|---|---|
| Hybrid | 所有经网关的聊天 | `LlmGateway.send` 返回的 `turnId`（`lib/core/llm/llm_gateway.dart`） |
| Hybrid | 通通"搜一搜已关"固定回应 | 预检的 `turnId`（开关关时为空，那时也没写事件） |
| 规则 | 签到 B、回忆 B | `SafetyCheckResult.turnId` → `RuleSubmissionFlow.record(safetyTurnId:)`（`rule_submission_flow.dart`、`check_in_arm_b.dart`、`reminiscence_arm_b_page.dart`） |
| 规则 | 通通 B | `SafetyCheckResult.turnId`（`tung_tung_page.dart` `_sendRuleBased`） |

没做：表单页（Thought Exercise、每周问卷、行动计划等）没有 `turns` 记录，事件的 `turnId` 只能按 uid + 时间对上表单记录（backlog 86）。

分析时：`safety_events.turnId` = `safety_classifier_calls.turn_id` = `turns.safetyTurnId`。

## 3. 两组安全流程一致

- 分类器结果只经 `mergeClassifierVerdict` 改级别（只升不降），然后走两组共用的 `DistressRouter`（危机页 / 支援面板）和 `onSafetyEventCreated`（PI 通知）。没有新文字。
- **补的不一致**（`tung_tung_page.dart` 搜一搜固定回应分支）：开关开时，Hybrid 组先 `checkUserTextClassified`；仍是 none → 固定回应；被调高 → 走正常网关流程，网关用同一个 `turnId` 再查一次（新参数 `LlmGateway.send(turnId:)`），服务器按 `turnId` 去重，只算一轮、只通知 PI 一次。代价：被调高的这类消息会多一次分类器调用（同一 `turn_id` 两行）。开关关时行为完全不变。
- 盲法：`safety_classifier_calls` 写进 `functions/blinding.js` 的 `HELD_BACK`（T8 报告第 6 节的建议）。`turns` 本来就在 `HELD_BACK`。

## 4. 测试

| 测试 | 文件 | 结果 |
|---|---|---|
| Hybrid：分类器调用、安全事件、`turns` 记录同一个编号 | `test/safety_classifier_test.dart`（T24 组） | 通过 |
| 规则组：同上 | 同上 | 通过 |
| 开关关：`turns` 记录仍带事件编号 | 同上 | 通过 |
| 网关沿用预检编号（通通搜一搜分支） | 同上 | 通过 |
| T8 原有 48 个（开关关时同步、两组 T6 20 句一致等） | 同上 | 全部通过 |
| `TurnRecord` 字段 | `test/phase_a_logging_test.dart` | 通过 |
| 盲法导出 | `functions/test/blinding_test.js` | 10/10 |

全套（推送前各跑一次）：`tool/ci_backend_tests.sh` 全部通过；`tool/ci_flutter_tests.sh` 六套构建变体全部通过（默认 391 个）。

## 5. 改动的文件

- App：`lib/core/session/chat_session_recorder.dart`、`lib/core/llm/llm_gateway.dart`、`lib/features/brief_pr/data/rule_submission_flow.dart`、`check_in_arm_b.dart`、`reminiscence_arm_b_page.dart`、`tung_tung_page.dart`；`safety_classifier.dart` 只改注释。
- 服务器：`functions/blinding.js`（`HELD_BACK`）；`safety_classifier.js` 只改注释。
- 文档：决策 0033、0025（状态行）、`docs/release/prelaunch-checklist.md` H 节、`docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`、`docs/history.md`、`docs/dev/backlog.md`（58 改状态，新 85–86）。

## 要带回研究侧的发现

1. **DMP、ICF、HREC**：两组共用意味着规则组老人的文字也发给分类器（backlog 85）。打开开关前要写进文件。
2. **接入要研究侧给**：部署机器（建议 asia-east2 Cloud Run，线上连不到个人电脑）、HTTPS 地址、鉴权（现在支持 Bearer 密钥；用 Google 身份令牌要改代码）、返回格式（5 级之一 + 0–1 分数；只给分数要先给切点）、实测延迟。见上线清单 H 节。
3. **`turns.safetyTurnId` 部署即生效**，不受开关控制，只多一个记录字段。
4. **表单页的安全事件连不回表单记录**，只能按时间对（backlog 86）。
5. T8 遗留的离线不对等、误报代价、PI 看不到调高原因仍待定（backlog 60、T8 报告）。
