# T8 安全分类器接口，为 LoRA 预留（2026-10-07，SPEC:C13）

> 分支 `feat/safety-classifier-slot`。决策 0025（提议中）。没有连生产 Firestore；测试用 emulator、本地假模型和合成句子。

## 结论先说

1. **接口搭好了，开关默认关。** 关着时线上行为完全不变：检测仍是原来的同步调用，写出的 `safety_events` 字段也一样（有测试，见第 4 节）。
2. **两组走同一个槽位**：放在 `lib/core/safety/` 的 `SafetyService` 后面，不在 Hybrid 组才用的 `LlmGateway` 里。
3. **不碰「规则组不能调用 LLM」的防线**：分类器走独立的 Cloud Function `classifySafety`，只返回级别和分数，不返回文字；不经过 `proxyDeepSeek`，不调用也不放宽 `assertLlmAllowed`。但规则组的原话会发给分类器，**这需要研究侧和 PI 确认后才能打开开关**（决策 0025）。
4. **只升不降**；超时（1.5 秒）或失败只用词库，并记一条日志；词库已是 acute 时不问分类器。
5. **离线时规则组只有词库**，是新的组间不对等，本次只记录不补救。

## 1. 接口

### App：`SafetyService`（`lib/core/safety/safety_check.dart`）

| 调用 | 作用 |
|---|---|
| `classifierActiveFor(point)` | 开关开、接了分类器、是老人自己的输入时为 true。App 生成的模型输入（`system_generated`）和搜一搜的搜索词不送分类器 |
| `checkUserTextClassified(text, point:, uid:, …)` | 异步。词库 → 分类器 → 取较高级别 → 写一条 `safety_events`。`classifierActiveFor` 为 false 时直接调用原来的 `checkUserText` |
| `checkUserText(…)`、`checkAndRoute(…)` | 不变。`checkAndRoute` 在开关开时内部改用上一行 |

调用方的写法（开关关时不经过任何 `await`，时序不变）：

```dart
final r = safety.classifierActiveFor(point)
    ? await safety.checkUserTextClassified(text, point: point, ...)
    : safety.checkUserText(text, point: point, ...);
```

已接入的地方：

| 输入 | 组别 | 位置 |
|---|---|---|
| 所有聊天（签到 A、回忆 A、自由倾偈、通通 A、行动计划 A、跟进笔记 A、问下呢篇） | Hybrid | `lib/core/llm/llm_gateway.dart` |
| 签到留言 | 规则 | `check_in_arm_b.dart` |
| 怀旧留言 | 规则 | `reminiscence_arm_b_page.dart` |
| 通通 B | 规则 | `tung_tung_page.dart` |
| 入组开放题（3 项） | 两组（分组前） | `intake_flow_page.dart` |
| 所有表单页（Thought Exercise、比较页、反馈、行动计划 B、跟进笔记 B、每周问卷、回忆总结修改、M3 编辑） | 两组 | 经 `checkAndRoute`，页面不用改 |

分类器槽位本身：`lib/core/safety/safety_classifier.dart`。

- `SafetyClassifier`：一个方法 `classify(text, inputPoint:, source:, turnId:)` → `ClassifierVerdict`（`status`、`level`、`score`、`modelVersion`），没有文字字段。
- `CloudSafetyClassifier`：调用 `classifySafety`（asia-east2）。
- `mergeClassifierVerdict`：只升不降。

### 服务器：`classifySafety`（`functions/index.js`，逻辑在 `functions/safety_classifier.js`）

- 需要登录；两组都可以调用；不读组别，也不写组别。
- 请求：`{text, inputPoint, source, turnId}`。
- 发给模型：`POST {classifierUrl}`，正文 `{"text": "..."}`（先经 `stripPII` 去电话、身份证号等，超过 `classifierMaxChars` 截断）；有 `SAFETY_CLASSIFIER_TOKEN` 时加 `Authorization: Bearer …`。
- 模型应返回：`{"level": "none|low|moderate_review|moderate_interrupt|acute", "score": 0–1, "model_version": "…"}`。级别不在这 5 个里算失败；其他字段（包括任何文字）丢掉。
- 返回给 App：`{status, level, score, modelVersion}`，`status` 是 `ok` / `disabled` / `timeout` / `error`。

## 2. 开关

| 开关 | 位置 | 默认 | 管什么 |
|---|---|---|---|
| `safetyClassifierEnabled` | Firestore `app_config/phase_a`（App 启动时读） | **关** | App 是否问分类器 |
| `safetyClassifierTimeoutMs` | 同上 | 1500 | App 最多等多久（限 200–5000） |
| `classifierEnabled` | Firestore `meta/safety_config`（服务器每分钟读一次，客户端读不到） | **关** | 服务器是否转给模型；关着返回 `disabled` |
| `classifierUrl` | 同上 | 无 | 模型地址；没有就当关 |
| `classifierTimeoutMs` | 同上 | 1200 | 服务器等模型多久 |
| `classifierMaxChars` | 同上 | 1000 | 超过就截断 |
| `SAFETY_CLASSIFIER_TOKEN` | Functions 环境变量 | 无 | 模型的密钥（鉴权方式定了再改成 Secret Manager） |

两个总开关（App、服务器）都开才生效。代码：`lib/core/config/phase_a_config.dart`、`functions/safety_config.js`。

## 3. 回退逻辑和日志

| 情况 | 结果 | 谁记日志 |
|---|---|---|
| 词库已是 acute | 不问分类器，立即走危机流程 | 不记（没调用） |
| 模型正常返回 | 取词库和模型里较高的级别 | 服务器，`status: ok` |
| 服务器开关关 / 没有地址 | 只用词库 | 服务器，`status: disabled` |
| 模型超时（服务器等 1.2 秒） | 只用词库 | 服务器，`status: timeout` |
| 模型报错或返回格式不对 | 只用词库 | 服务器，`status: error` |
| App 等 1.5 秒没回（离线、网络慢、冷启动） | 只用词库 | App，`status: client_timeout` |
| 调用失败（离线、未登录等） | 只用词库 | App，`status: client_error` |

- **一轮仍只写一条 `safety_events`**，开关开时多几个字段：`detector`（`lexicon` / `classifier` / `both`）、`classifierStatus`、`classifierLevel`、`classifierScore`、`classifierVersion`。开关关时没有这些字段。分类器调高的事件没有命中词和类别。
- **`safety_classifier_calls`**（`firestore.rules` 新增一段）：字段 `ts`、`uid`、`writer`（server / app）、`status`、`level`、`score`、`latency_ms`、`model_version`、`input_point`、`source`、`turn_id`、`text_length`、`truncated`、`timeout_ms`（App 写的行只有前面几项）。**不存原文，不存组别。** App 只能写自己的、只能写 `client_timeout` / `client_error`、字段固定；客户端不能读、改、删。T11 的整人删除脚本已包含这个集合（`tool/delete_participant.js`，按 `uid`）。
- **只升不降的理由**：不减少词库已有的覆盖；词库可复现，模型不一定。代价：模型误报会让 Hybrid 组更常不调用 AI（acute 短路）、规则组更常不给模板回应并多弹支援面板（T6 复核提醒）。
- **离线**：规则组的签到 B、回忆 B、通通 B 提交时立即检测，离线只能用词库；Hybrid 组离线时 AI 本来就调不通，T6 报告第 4 节写签到 A、回忆 A 联网后才扫描，那时能用分类器。所以**会造成新的组间不对等**：离线提交的规则组老人少一道检测。两组的回退都记在 `safety_classifier_calls`（App 行离线时先排队，联网后同步），可以按组统计。本次没有补救。
- **等待对体验的影响**（只在开关开时）：规则组提交按钮最多多转 1.5 秒；Hybrid 组 AI 回复前最多多等 1.5 秒。签到 B 的提交时间（`userSent`）改在检测之前取，开关关时只差微秒。

## 4. 测试结果

| 测试 | 文件 | 结果 |
|---|---|---|
| 开关默认关；从 `app_config/phase_a` 读；等待时间限范围 | `test/safety_classifier_test.dart` | 通过 |
| **开关关：`LlmGateway` 在第一个 `await` 之前就写了事件（同步，和以前一样），没问分类器，事件没有分类器字段** | 同上 | 通过 |
| **开关关：`checkAndRoute` 同样是同步写事件** | 同上 | 通过 |
| 开关关：`checkUserTextClassified` 直接走原来的 `checkUserText` | 同上 | 通过 |
| 正常：词库漏的句子被模型调高，一条事件，`detector=classifier` | 同上 | 通过 |
| 不调低：词库 moderate、模型 none → moderate | 同上 | 通过 |
| 词库 acute：不问模型、不等待 | 同上 | 通过 |
| 超时（假模型 3 秒才回、上限 0.3 秒）→ 只用词库、App 记 `client_timeout` | 同上 | 通过 |
| 默认上限 1.5 秒（假模型永不回） | 同上 | 通过 |
| 失败（假模型抛错）→ 只用词库、App 记 `client_error` | 同上 | 通过 |
| 服务器返回 timeout / error / disabled → 只用词库、App 不重复记 | 同上 | 通过 |
| Hybrid：模型调到 acute → 不调用 AI | 同上 | 通过 |
| App 生成的输入不送模型 | 同上 | 通过 |
| **两组一致**：T6 的 20 句，Hybrid 路径（`LlmGateway`）和规则路径级别、事件数、`detector` 都相同 | 同上 | 20/20 通过 |
| 服务器，本地假模型（127.0.0.1 上的 HTTP 服务）：开关默认关 → disabled、不调用模型、记一行；正常 → 只回级别分数，模型多给的文字丢掉，日志无原文无组别，发出的文字已去电话号码，带 Bearer 密钥；超时 → timeout（<1.2 秒）；HTTP 500、格式不对、地址不通 → error；长文截断；两组结果相同，规则组调用 `proxyDeepSeek` 仍被拒，DeepSeek 调用 0 次；未登录被拒 | `functions/test/safety_classifier_emulator_test.js` | 11/11 通过 |
| 规则：App 只能写自己的回退行；不能冒用 uid、不能写 server 行或其他状态、不能加字段；不能读改删；`safety_events` 接受新字段 | `test/rules/safety_events_rules.test.js` | 4/4 通过（整个文件 14/14） |

**两套全量测试**（推送前各跑一次）：

- `tool/ci_backend_tests.sh`：全部通过（Functions 单元测试；规则 59 个通过；模拟器测试含新的分类器 11/11、T7 13/13；删除脚本测试）
- `tool/ci_flutter_tests.sh`：六套构建变体全部通过（默认 328 个，其余 5 套各自通过）

## 5. 接真实 LoRA 还要研究侧提供

| 项目 | 为什么需要 | 现在的假设 |
|---|---|---|
| **地址** | 填 `meta/safety_config.classifierUrl` | 一个 HTTPS 地址，接受 POST |
| **鉴权方式** | 服务器怎么证明自己 | 可选的 Bearer 密钥（环境变量）。如果用 Google 身份（Cloud Run IAM）要改代码 |
| **部署在哪台机器** | 线上 Cloud Function 连不到负责人自己的电脑 | 建议 asia-east2 的 Cloud Run 或同区域的服务器；数据出境要和 DMP 一致 |
| **输入长度上限** | 设 `classifierMaxChars` | 1000 字，超出截断 |
| **返回格式** | 对上解析 | `{"level": 5 级之一, "score": 0–1, "model_version": "…"}`；模型如果只给分数，要研究侧给出分数到级别的切点 |
| **延迟要求** | 定等待上限 | 服务器 1.2 秒、App 1.5 秒。T6 建议 800 ms 左右，要实测 |
| 模型版本号 | 写进日志和事件，追溯用 | 模型返回 `model_version` |
| 评估结果 | 决定能不能打开 | 用 T6 的 20 句和 `docs/safety/distress_detector_performance_v1.0.md` 的语料测召回、误报、延迟 |

## 6. 盲法导出（对照 T12）

- `safety_classifier_calls` 两组都有记录，但 `input_point` 的取值两组不同（`chat_check_in` 对 `check_in_note` 等），`turn_id` 能连到只有一组才有的数据，原样导出会揭盲。T12 的新导出是白名单（`functions/blinding.js`），本来就不导出这个集合，所以现在**不会进盲法导出**。
- 如果研究侧要在揭盲前给盲法分析员看（例如各组回退率），需要中性化：`input_point` 合并成「对话 / 表单」两类、去掉 `turn_id` 和 `model_version` 以外的追溯字段、`uid` 换成研究编号。建议揭盲前不给。
- `safety_events` 新增的 `detector` 和分类器字段不在 T12 的 `SAFETY_FIELDS` 白名单里，不会导出。导出的级别是合并后的级别，两组规则相同。
- 建议 T12 把 `safety_classifier_calls` 写进 `HELD_BACK` 清单，让导出说明里写明（本次没改 T12 的代码）。

## 7. 改动的文件

- App：`lib/core/safety/safety_classifier.dart`（新）、`safety_check.dart`、`safety_event_writer.dart`；`lib/core/config/phase_a_config.dart`；`lib/core/llm/llm_gateway.dart`；`lib/main.dart`；签到 B、回忆 B、通通、入组页各一处。
- 服务器：`functions/safety_classifier.js`（新）、`safety_config.js`、`index.js`（`classifySafety`）；`firestore.rules`。
- 测试：`test/safety_classifier_test.dart`（新）、`test/safety_check_test.dart`（假写入器跟着加参数）、`functions/test/safety_classifier_emulator_test.js`（新，`ci_backend_tests.sh` 自动发现）、`test/rules/safety_events_rules.test.js`。

## 要带回研究侧的发现

1. **核心取舍要确认**：两组一致就意味着规则组的原话会发给分类器。它不是对话模型、不返回文字、不改对话，`assertLlmAllowed` 没动；但这是规则组新的外发路径。接受的话 DMP、ICF 要写，HREC 是否修订要定（决策 0025，backlog 58）。
2. **离线时的组间不对等**：规则组离线提交只有词库；Hybrid 组离线时根本拿不到 AI 回复，联网后才检测。要不要联网后补测（backlog 60）。
3. **只升不降的代价**：误报会减少 Hybrid 组的 AI 回复次数和规则组的模板回应，影响干预剂量。打开前要用语料测误报率，定一个可接受的上限（backlog 60）。也可以先打开服务器、把 App 等待上限设得很短，只看日志试运行；但这样仍会在命中时调高级别，真正的「只记日志」模式本次没做。
4. **分类器调高的事件没有命中词和类别**，PI 每周复核时只看到级别和分数，看不到为什么。需要的话要模型返回类别（不能返回文字）。
5. **接真实模型要的信息**见第 5 节（backlog 59）。
6. **等待对老人的影响**：打开后，规则组提交和 Hybrid 组 AI 回复前最多多等 1.5 秒。
