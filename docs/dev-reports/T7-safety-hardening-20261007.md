# T7 安全加固（2026-10-07，SPEC:C12）

> 分支 `fix/safety-hardening`。决策记录 0018。没有连生产 Firestore；测试用 emulator 和合成句子。

## 结论先说

1. **所有自由输入两组都检测**，经同一个入口 `SafetyService`（`lib/core/safety/safety_check.dart`）。下表 20 个输入点全部有测试并通过。
2. **7 处 AI 调用补上了用户编号**；另外写事件时如果没有编号，自动用当前登录的用户（`lib/core/safety/safety_event_writer.dart`），以后再漏也不会被拒收。
3. **一轮对话只算一条安全事件**。每条事件都有 `source`。旧的去重键含 `source`，所以同一轮会通知两次，已改。
4. **Hybrid 组 AI 回复里不再出现电话号码**：prompt 规则 + 服务器过滤 + App 再过滤一次。号码换成「緊急熱線」链接，点开是危机页。
   - 用 T6 的 20 句真实调用 DeepSeek 20 次：加了规则后 **0 次写号码**，3 次写了「【緊急熱線】」，没有写任何机构名。
5. **搜一搜**：命中安全词的话不发出搜索（T9 会把搜一搜默认关掉）。
6. 新行为都有开关，默认开（研究侧已定）。

## 1. 开关

| 开关 | 位置 | 默认 | 管什么 |
|---|---|---|---|
| `safetyScanAllInputs` | Firestore `app_config/phase_a`（App 启动时读） | 开 | T7 新增的输入点要不要检测。关了恢复 T7 之前的覆盖；聊天一直检测 |
| `hotlineFilterClient` | `app_config/phase_a` | 开 | App 端再过滤一次号码 |
| `hotlinePromptRule` | Firestore `meta/safety_config`（服务器每分钟读一次） | 开 | prompt 末尾加「不写电话号码」规则 |
| `hotlineOutputFilter` | `meta/safety_config` | 开 | 服务器在返回前替换号码并记日志 |

没有这两个文档时，全部按「开」处理（`lib/core/config/phase_a_config.dart`、`functions/safety_config.js`）。

## 2. 统一入口：接口

`SafetyService`（`lib/core/safety/safety_check.dart`），App 里一个实例，放在 `CoreServicesScope.safety`。

| 调用 | 检测 | 写 `safety_events` | 弹危机页 / 支援面板 | 通知 PI |
|---|---|---|---|---|
| `detect(text)` | 是 | 否 | 否 | 否 |
| `checkUserText(text, point:, uid:, agentId:, sessionId:, turnId:)` | 是 | 中度以上写一条 | 否，调用方负责 | 服务器负责（acute） |
| `checkAiOutput(text, turnId:, inputMatch:, …)` | 是 | 只在高于输入级别时写 | 否 | 服务器负责（acute） |
| `checkAndRoute(context, text, point:, …)` | 是 | 中度以上写一条 | 是：acute → 危机页；moderate_interrupt → 支援面板；moderate_review → 不显示 | 服务器负责（acute） |
| `route(context, results)` | 否 | 否 | 是，取几项里最严重的 | 否 |

- 返回值 `SafetyCheckResult`：`match`（级别、命中词、类别）、`point`、`scanned`（开关关掉时为 false）、`eventQueued`、`turnId`。
- 检测是同步的，不会抛错；写入不等待（离线时也不挡住危机页）。
- 通知 PI：服务器 `onSafetyEventCreated`（`functions/index.js`）写 `pi_alerts` 并发邮件，只针对 acute，测试员账号不发邮件（不变）。
- 给后续任务：T8 在 `detect` 后面接分类器；T10 用 `detect` 查老人原话；T15 先 `checkUserText` 再选模板。

## 3. `safety_events` 字段和去重

**App 写的字段**（`safety_event_writer.dart`）：`uid`、`source`、`inputPoint`、`turnId`、`textHash`、`level`、`tier`、`category`、`lexiconVersion`、`matchedTerm`、`agentId`、`sessionId`、`createdAt`。不存原文。

**`source` 的取值**：

| 值 | 含义 | 旧值 |
|---|---|---|
| `user_input` | 对话里老人说的话（含签到、回忆留言、搜索词） | `gateway_input`、`rule_turn` |
| `ai_output_scan` | AI 回复的扫描（只 Hybrid 组） | `gateway_output` |
| `form` | 表单里的自由文字 | 新 |

规则（`firestore.rules`，只改了 `safety_events` 一段，另加 `hotline_filter_log`）：`source` 必须在上面 3 个新值或 4 个旧值里；客户端不能写 `dedup_key`、`isDuplicate`、`duplicateOf`、`escalatedBy`。

**去重**（`functions/index.js` `onSafetyEventCreated`）：
- 键 = `uid + turnId`；旧版本 App 没有 `turnId` 时 = `uid + textHash + 分钟`。**都不含 `source`**。
- 同一轮的第一条是主事件（`isDuplicate: false`），后来的标 `isDuplicate: true` 和 `duplicateOf`。
- 后来的级别更高时（例如输入是 moderate、AI 回复扫出 acute），主事件升到这个级别，记 `escalatedBy`；如果这一轮因此变成 acute，通知 PI 一次。
- App 端也先挡一层：AI 回复扫描只在级别高于输入时才写。
- **分析时只数 `isDuplicate == false`**，每轮恰好一条，级别是这一轮的最高级别。

## 4. 热线过滤

- **prompt 规则**：`functions/prompts/hotline_rule.v1.txt`，接在 system prompt 最后（记忆块之后）。`promptVersion` 变成 `siu_yan_v1@2026-06+hotline_rule.v1`。**请 PI 审核这段 prompt。**
- **服务器过滤**：`functions/hotline_filter.js`，在 `proxyDeepSeek` 返回之前执行。
  - 识别：香港 8 位号码（空格、横线、全角数字、全角空格、`+852`、`(852)`、`852-`）；`800` 免费电话；内地手机；单独的 `999`；「打 / 撥 / 致電 / 熱線 / call」后面的 3–5 位服务号码（如 1823、18288）。
  - 不误伤：日期（2026-10-07、07/10/2026、20261007、2026年10月7日）、时间（3:30、10:30-11:45、10點）、金额（$4,195、HK$2,389.22、12345678 元、999蚊）、年份和年份范围（1999年、2020-2026）、百分比、楼层、步数、巴士号。共 43 个测试用例，服务器和 App 用同一份（`test/fixtures/hotline_filter_cases.json`）。
  - 换成「【緊急熱線】」。机构名不动。
- **App 再过滤一次**：`lib/core/safety/hotline_filter.dart`，在 `LlmGateway` 里。
- **显示**：`RichChatText`（五个聊天页共用）把「【緊急熱線】」画成链接，文字用现有的「緊急熱線」（`safetyPillAcute`），点开是现有的危机页 `EmergencySupportPage`。
- **日志**：集合 `hotline_filter_log`，只有服务器写，客户端不能读写。每条回复（有替换时）一条：

| 字段 | 内容 |
|---|---|
| `ts` | 时间 |
| `uid`、`agent_id`、`module_id`、`call_type` | 谁、哪个陪伴者、哪个模块 |
| `count` | 换了几个号码 |
| `kinds` | 各种类的个数，如 `{hk8: 1, emergency: 1}` |
| `approved_count`、`unapproved_count` | 是否在 `crisis_resources.json` 的批准清单里 |
| `filter_version`、`prompt_rule_version` | `hotline_filter.v1`、`hotline_rule.v1`（规则关掉时为空） |

不存原文，也不存号码。

## 5. 输入点 × 组别 × 是否检测 × 测试结果

「T7 前」一列来自 T6 报告第 2.3 节。测试列的文件：`test/safety_check_test.dart`（App）、`functions/test/safety_t7_emulator_test.js`（服务器，emulator）。每个输入点都用一句合成句测过（「every input point」一组），T6 的 20 句测过两组路径一致。

| 输入点（`inputPoint`） | 组别 | T7 前 | T7 后 | 怎么检测 | 测试结果 |
|---|---|---|---|---|---|
| 聊天：小欣签到 `chat_check_in` | Hybrid | 检测 | 检测 | `LlmGateway` | 通过（20 句两组一致；gateway 路由） |
| 签到留言 `check_in_note` | 规则 | 检测 | 检测 | `checkUserText` | 通过（20 句两组一致） |
| 聊天：阿珍回忆 `chat_reminiscence` | Hybrid | 检测 | 检测 | `LlmGateway` | 通过 |
| 怀旧留言 `reminiscence_note` | 规则 | 检测 | 检测 | `checkUserText` | 通过 |
| 聊天：自由倾偈 `chat_reflective` | Hybrid（规则组无此入口） | 检测 | 检测 | `LlmGateway` | 通过 |
| 聊天：通通 `chat_tung_tung` | 两组 | 检测 | 检测 | Hybrid `LlmGateway`；规则 `checkUserText` | 通过 |
| 问下呢篇 `article_qa` | Hybrid（目前是死代码） | 检测，事件被拒收 | 检测，带 uid | `LlmGateway` | 通过 |
| Thought Exercise `thought_exercise` | 两组 | **不检测** | 检测 | `checkAndRoute`（保存后） | 通过 |
| 入组：而家心入面 `intake_on_mind` | 两组（入组时未分组） | **不检测** | 检测 | `checkUserText` + `route` | 通过 |
| 入组：唔想傾嘅話題 `intake_avoid_topics` | 两组 | **不检测** | 检测 | 同上 | 通过 |
| 入组：其他文字（其他目标、日常、其他消遣和话题、重要的人的备注）`intake_other_text` | 两组 | **不检测** | 检测 | 同上 | 通过 |
| 陪伴者比较页 `agent_diff` | 两组 | **不检测** | 检测 | `checkAndRoute`（保存后） | 通过 |
| 「其他」反馈框 `feedback_other` | 两组 | **不检测** | 检测 | `checkAndRoute` | 通过 |
| 行动计划 `action_plan` | Hybrid | 检测，事件被拒收 | 检测，带 uid | `LlmGateway`（汇总那一步） | 通过 |
| 行动计划 `action_plan` | 规则 | **不检测** | 检测 | `checkAndRoute`（保存后） | 通过 |
| 跟进笔记 `action_followup` | Hybrid | 检测，事件被拒收 | 检测，带 uid | `LlmGateway` | 通过 |
| 跟进笔记 `action_followup` | 规则 | **不检测** | 检测 | `checkAndRoute` | 通过 |
| 回忆总结修改 `reminiscence_summary_edit` | Hybrid（规则组无此框） | **不检测** | 检测 | `checkAndRoute`（只在老人改过时） | 通过 |
| M3 重新编辑 `m3_session_edit` | Hybrid | **不检测** | 检测 | `checkAndRoute` | 通过 |
| 每周 PPR 自由题 `ppr_free_text`（代码里找到的） | 两组 | **不检测** | 检测 | `checkAndRoute` | 通过 |
| 搜一搜的搜索词 `search_query` | Hybrid（规则组无此功能） | 不检测，原话先发 Brave | 先 `detect`，命中就不搜 | `detect`（事件由同一轮的聊天检测写） | 通过（单句测试） |
| App 生成的模型输入（问候、总结、建议、进度）`system_generated` | Hybrid | 检测，部分事件被拒收 | 检测，带 uid | `LlmGateway` | 通过 |
| AI 回复 `ai_output_scan` | Hybrid | 检测，每轮多写一条 | 检测，只在高于输入时写 | `checkAiOutput` | 通过（一轮一条，4 个测试） |

**不检测的输入**（不是叙述性文字）：姓名、年龄、紧急联络人电话（`personalization_page.dart`）、重要的人的姓名和关系、登录、测试员密码、研究员后台。

**其他测试**：

| 测试 | 结果 |
|---|---|
| T6 20 句：Hybrid 路径（`LlmGateway`）和规则路径（`checkUserText`）级别、命中词、事件数、事件级别完全相同；acute 时 Hybrid 不调用模型 | 20/20 通过 |
| 词库结果与 T6 报告一致（v5 未改，9 句命中） | 通过 |
| 开关关掉：新输入点不检测，聊天仍检测；默认开 | 通过 |
| 表单页：acute → 危机页；moderate_interrupt → 支援面板；moderate_review、无风险 → 不显示 | 4/4 通过 |
| 号码过滤 43 个用例（服务器和 App 同一份） | 通过 |
| 「【緊急熱線】」显示成链接，点开是危机页 | 通过 |
| 服务器（emulator）：T6 里 AI 真实写过的两段回复（A2、A7，含配错的号码），号码全部被替换；日志一条、不含原文和号码；配错的号码记为 unapproved | 通过 |
| 服务器：规则接在最后；`promptVersion` 带规则版本；两个开关各自关掉都生效；规则组仍被拒 | 通过 |
| 服务器：同一轮输入 + 输出只算一条；输出更高时主事件升级、只通知 PI 一次；不同轮不合并；旧事件（无 `turnId`）跨 source 去重；每条都有 source | 通过 |
| 规则：`source` 必须在列表里、不能冒用别人 uid、不能自己写去重字段；`hotline_filter_log` 客户端不能读写 | 10/10 通过 |

**两套全量测试**：见第 7 节。

## 6. 真实调用（20 次）

- 脚本和结果：`docs/dev-reports/T7-safety-hardening-20261007-scripts/hotline_live.js`、`results_hotline_live.json`。
- 请求和线上一样：小欣 prompt、`m2_check_in`、`deepseek-flash`、思考关闭，末尾加 `hotline_rule.v1`。每句 1 次，返回模型 20 次都是 `deepseek-flash`，延迟约 440–890 ms。
- 结果：
  - 20 次回复都**没有写电话号码**，过滤器没有东西要换；
  - A1、A2、A3 写了「【緊急熱線】」，没有写任何机构名；
  - A4–A8（间接自杀表达）没有提热线。T6 时 A3、A5、A7 有时会写「撒瑪利亞防止自殺會」和号码。
- 注意：A1、A8 在线上会被词库拦下，不会调用 AI。

## 7. 全量测试

推送前跑了一次：
- `tool/ci_backend_tests.sh`：见 PR 描述；
- `tool/ci_flutter_tests.sh`：四套构建变体，见 PR 描述。

## 8. 改动的文件（主要）

- 服务器：`functions/hotline_filter.js`、`functions/safety_config.js`、`functions/prompts/hotline_rule.v1.txt`、`functions/index.js`（`proxyDeepSeek`、`onSafetyEventCreated`）、`firestore.rules`（`safety_events` 一段 + `hotline_filter_log`）。
- App：`lib/core/safety/safety_check.dart`、`hotline_filter.dart`、`safety_event_writer.dart`；`lib/core/llm/llm_gateway.dart`；`lib/shared/widgets/rich_chat_text.dart`；`lib/core/config/phase_a_config.dart`；以及各输入页一处调用。
- 和其他任务的交界：`tung_tung_page.dart` 只改了搜一搜前的检查和规则组检测调用（T9、T15 也改这页）；`action_loop_arm_b_page.dart` 只在保存末尾加了检测（T13 改提醒发送）；`check_in_arm_a.dart` 没改（T11 在改）。

## 要带回研究侧的发现

1. **Hybrid 组少了一层「偶然的补救」**。T6 时 AI 自己写「撒瑪利亞防止自殺會」，回复扫描命中「自殺」，会补记一次 acute 事件。加了规则后 AI 不再写机构名，这层补救没了（A3、A5、A7）。两组在词库漏检时的保护因此更一致，但 Hybrid 组漏检的间接自杀表达更少被记录。词库召回低的问题（backlog 32）更需要处理（T8 分类器）。
2. **AI 在间接自杀表达上不再提热线**。A4–A8 五句的回复都没有提热线或危机页。规则最后一句写了「其他時候唔使提熱線」，可能有影响。要不要改成「有任何自殺或傷害自己的跡象都寫【緊急熱線】」，请 PI 定（新版本要另开文件 `hotline_rule.v2.txt`）。
3. **老人看得到的新文字**（只用了现有文案，研究侧定稿）：
   - 号码换成的链接文字：现用「緊急熱線」（App 里已有的危机热线文字）。草稿备选：「撳呢度搵人傾」。
   - AI 被要求写的「【緊急熱線】」本身。如果改字，服务器、App、prompt 三处要一起改。
4. **安全事件的分析口径变了**：只数 `isDuplicate == false`；`source` 改成三类（旧值对应见第 3 节）；`ai_output_scan` 只出现在 Hybrid 组。
5. **盲法**：`hotline_filter_log` 只有 Hybrid 组有，和 `llm_calls` 一样，原样导出等于揭盲（backlog 38，交 T12）。
6. **入组问卷在分组之前**，检测命中时同样弹危机页。这是参与者第一次接触 App，研究侧要知道。
7. **搜一搜**：现在只在 App 端检查。服务器 `webSearch` 没有词库，旧版本 App 仍可能把原话发出去（T9 默认关闭后不影响）。
