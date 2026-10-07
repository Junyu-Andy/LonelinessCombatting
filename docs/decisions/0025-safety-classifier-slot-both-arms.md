# 0025：安全分类器（LoRA）做成两组共用的独立分类接口，经 Cloud Function 中转，只能调高级别；开关默认关

- 日期：2026-10-07
- 状态：提议中（代码已写，开关默认关。**研究侧和 PI 确认本记录之前不打开**）
- 影响范围：所有 cohort × 两组（开关打开后）；开关关着时没有任何影响
- 相关代码：分支 `feat/safety-classifier-slot`（T8，SPEC C13）

## 背景

T6 发现词库对间接自杀表达召回很低（8 句 acute 只命中 2 句），T7 之后 Hybrid 组连「AI 回复里偶然提到机构名」这层补救也没有了。研究侧想用本地 LoRA 模型做第二道检测，但还没定是否上线。任务单要求：两组走同一个槽位、只返回风险等级和分数、超时或失败回退到词库、默认关。

这和 CLAUDE.md 有冲突：「规则组（Arm B）永远不能调用 LLM」，服务器上还有 `assertLlmAllowed` 防线（`functions/index.js`）。LoRA 分类器也是模型。另一方面，CLAUDE.md 又要求「安全检测两组必须完全一致」，只给 Hybrid 组用就违反这一条。

## 决定

1. **独立的分类接口，不是对话模型调用**：
   - 新的 Cloud Function `classifySafety`，只返回 `{status, level, score, modelVersion}`，**不返回任何文字**，也不改对话内容。模型多回的任何字段都丢掉。
   - 不经过 `proxyDeepSeek`，不调用 DeepSeek，**也不调用、不放宽 `assertLlmAllowed`**。这道防线照旧挡住规则组调用所有对话模型接口（测试里验证了）。
   - 规则组因此会有一条新的外发路径：老人的原话（去掉电话等个人信息后）发给分类器。这是本记录要研究侧确认的核心取舍。
2. **放在两组共用的一层**：槽位在 `lib/core/safety/`（`SafetyService` 后面，`safety_classifier.dart`），不放在 Hybrid 组才用的 `LlmGateway`。Hybrid 组的聊天（经 `LlmGateway`）、规则组的签到 B、回忆 B、通通 B、入组开放题、所有表单页都走同一个方法 `checkUserTextClassified`。App 生成的模型输入和搜一搜的搜索词不送分类器。
3. **经 Cloud Function 中转，不让 App 直连**，理由：
   - 鉴权：只有登录的参与者能调用（Firebase Auth）；模型那边只需要认服务器一个调用方。
   - 地址保密：模型地址放在 `meta/safety_config.classifierUrl`（客户端读不到），密钥放服务器环境变量 `SAFETY_CLASSIFIER_TOKEN`，都不进 App 安装包。
   - 日志写入方：服务器为每次中转写一条 `safety_classifier_calls`，App 改不了。App 只补写服务器看不到的情况（请求根本没回来）。
   - 离线：两种做法离线时都调不到模型，没有区别；中转多一次网络往返，所以 App 等待上限设 1.5 秒，服务器等模型 1.2 秒。
4. **只能调高，不能调低**：最终级别 = 词库和分类器里较高的那个。理由：不减少已有覆盖；词库是确定的、可复现的，分类器的错误不会让一句词库已命中的话变成「没事」。
   - 代价（T6 复核提醒）：分类器误报会让 Hybrid 组更常被判为 acute、不调用 AI，减少干预剂量；规则组误报会更常不给模板回应、多弹支援面板。两组规则相同，但对两组体验的影响不同。上线前要用语料测误报率。
5. **回退**：词库已经是 acute 时不问分类器（危机页不能等）。超时（默认 1.5 秒）或失败：只用词库结果，照常往下走，记一条日志。一轮仍只写一条 `safety_events`，加 `detector`（lexicon / classifier / both）和分类器字段。
6. **离线**：签到 B、回忆 B、通通 B 提交时立即检测，离线时只能用词库；Hybrid 组聊天离线时 AI 本来就调不通（T6 报告第 4 节写签到 A、回忆 A 等联网后才扫描，那时可以用分类器）。这是**新的组间不对等**：规则组离线提交得不到第二道检测。本次不补救，但两组的回退都有日志（`client_timeout` / `client_error`），可以按组统计离线回退率；要不要补救（例如联网后补测、只记日志不弹页面）留给研究侧定。
7. **开关**（都默认关，两个都开才生效）：
   - App：`app_config/phase_a.safetyClassifierEnabled`（等待上限 `safetyClassifierTimeoutMs`，默认 1500）；
   - 服务器：`meta/safety_config.classifierEnabled`、`classifierUrl`、`classifierTimeoutMs`（默认 1200）、`classifierMaxChars`（默认 1000）。
   - 开关关着时：所有检测仍是原来的同步调用，时序和写入的事件内容完全不变（有测试）。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 只给 Hybrid 组用（放进 `LlmGateway`） | 违反「安全检测两组必须完全一致」；规则组漏检时没有任何补救，最需要第二道检测 |
| 经 `proxyDeepSeek` 或放宽 `assertLlmAllowed` | 会削弱「规则组永远不能调用 LLM」的防线；分类器是独立接口，不需要碰它 |
| App 直连模型 | 地址和密钥要放进安装包；日志只能由 App 写，可被改；鉴权要模型自己做 |
| 分类器可以调低词库的级别 | 会减少已有覆盖；词库的结果可复现，分类器的不一定 |
| 分类器只记日志、不影响级别（影子模式） | 可以作为打开前的过渡（见后果），但不能解决漏检；任务单要求接进检测结果 |
| 做成手机端模型 | 能消除离线不对等，但模型大小和老人手机性能未知，研究侧还没定 |

## 后果

- 对研究：
  - 打开开关之前要研究侧和 PI 确认：规则组多一条外发路径（原话发给分类器）是否可接受；DMP、ICF 要写明；HREC 是否要修订。
  - 打开后，两组的安全事件会因分类器增加，事件里 `detector` 可以区分来源；误报会减少 Hybrid 组的 AI 回复次数。
  - 离线时规则组只有词库（第 6 点），分析时按 `safety_classifier_calls.status` 统计各组回退率。
  - `safety_classifier_calls` 两组都有记录，但 `input_point` 的取值两组不同（如 `chat_check_in` 对 `check_in_note`），原样导出会揭盲。揭盲前不导出（T12 的白名单本来就不含它）。
- 对开发：`lib/core/safety/safety_classifier.dart`、`safety_check.dart`、`safety_event_writer.dart`；`LlmGateway` 和签到 B、回忆 B、通通 B、入组页各一处；`functions/safety_classifier.js`、`safety_config.js`、`index.js`（`classifySafety`）；`firestore.rules`。接真实模型前要研究侧提供地址、鉴权方式、部署机器、输入长度、返回格式和延迟（T8 报告）。
- 对论文：安全监测一节写明「词库 + 分类器，分类器只能调高级别，超时或失败回退到词库；两组相同」；局限里写离线时规则组只有词库。
