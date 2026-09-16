# `stripPII()` — 范围说明（P-2，Phase A 基线版）

> 回传给 PI 的说明，不是代码变更记录。代码位置：`functions/index.js` → `stripPII`、`PII_PATTERNS`、`resolvePrompt`、`proxyDeepSeek`、`referralJudgement`。

## 1. 它在哪里生效

`stripPII` 只在 **Cloud Function 出站到 DeepSeek 之前** 运行，作用对象是本次请求里会进入模型上下文的文本：

| 出站内容 | 是否经过 stripPII | 备注 |
|---|---|---|
| `messages[]`（历史 + 本条用户消息 + 助手回复） | **是**（`proxyDeepSeek`，逐条） | 基线前已有 |
| `contextSuffix`（rolling summary、named entities、theme threads、mood snippet、`[今週主題]`/`[模組]`） | **是**（2026-09 基线新增，`resolvePrompt` 内） | 基线前 **没有**：rolling summary 是用户对话的 LLM 摘要，人名/电话若被摘要保留，会原样出站。这是本次核查发现的缺口，已补 |
| 系统 prompt 文件本身（三份 `.txt`） | 否 | 静态文本，不含参与者数据 |
| `referralJudgement` 的 `recentTurns` / `matchedText` | **否** | 这条 callable 直接转发最近 10 轮给 DeepSeek 做 SURFACE/DEFER/SKIP 判断，未走 stripPII。建议 Phase A 期间补一行（与 `proxyDeepSeek` 同样的 `scrubbed` 映射）。本次未改，因规格要求 P-2 只文档化 |
| 请求头 | n/a | 无 uid / email / IP；`X-Session-Code` 是每次冷启动随机 salt 的 uid 哈希（16 位） |

**不在 stripPII 范围内的存储**：Firestore 里的 `agent_contexts/{agent}.rollingSummary`、`namedEntities`、`turns`、`memory/*` 都是 **原文存储**（不经 stripPII）。stripPII 只是「出境到 DeepSeek」的最小化，不是「入库脱敏」。Firestore 侧的保护是 owner-only 规则 + 每周导出时 `blindRow()` 去掉 `email/displayName/emergencyContact*/closeContacts` 并把 uid 换成盐哈希。

## 2. 剥离的类别与方法

方法：**正则替换**，不是模型。四条模式，按顺序全局替换：

| 类别 | 正则 | 替换为 | 已知漏洞 / 误伤 |
|---|---|---|---|
| 香港电话（8 位，可带 +852） | `(\+?852[-\s]?)?[2-9]\d{3}[-\s]?\d{4}\b` | `[PHONE]` | 中文数字（「二三八二零零零零」）不匹配；任意 8 位数字（如年份+月日 `20260911`）会被误伤 |
| Email | `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b` | `[EMAIL]` | — |
| 香港身份证样式 | `\b[A-Z]{1,2}\d{6}\(?\d?\)?\b` | `[ID]` | 依赖 `\b` 词边界；紧贴中文字符时（「我張身份證A123456(7)」）`\b` 在 A 前仍成立（中文非 word 字符），可匹配。小写字母不匹配 |
| 地址楼层/单位 | `\b\d{1,3}\/?[FfRr]\b` | `[ADDRESS]` | 只覆盖 `12F`、`3/F`、`5R` 这类西式写法；「十二樓」「3座12樓A室」「深水埗北河街」**均不覆盖**。规格里的「地址」实际上基本未覆盖 |
| **姓名** | 无 | — | **不剥离**，且是有意为之（代码注释：用户主动对 agent 讲的人名是生命回顾干预的核心，剥离会破坏功能）。`closeContacts` 里的名字只在导出时去掉，出站到 DeepSeek 时如果出现在对话/摘要里会原样发送 |
| **银行账号** | 无 | — | 不剥离。长数字串若恰为 8 位会被电话规则误伤成 `[PHONE]`，其他长度原样出站 |

## 3. 是否作用于 rolling summary / named entities 的**存储与外发**

- **存储**：否。`RollingSummaryCompiler` 把 LLM 生成的摘要原文写入 `agent_contexts/{agent}.rollingSummary`；`namedEntities` 由客户端从对话抽取后原文存储。
- **外发**：基线前否、基线后是（见 §1，`contextSuffix` 现在过 `stripPII`）。注意 rolling summary 本身是 **DeepSeek 生成** 的：摘要 fold 调用时，`[今次對話]` 转录作为 `userInput` 走 `messages[]`，因此**已被剥离**后才送去生成摘要；模型返回的摘要里理论上不会再含被剥离类别（电话等），但会含人名。

## 4. 建议（不阻塞基线，供 PI 决定）

1. `referralJudgement` 补 stripPII（一行）。
2. 若 HREC 要求「地址」实际可控，需要换成模型或至少加入中文楼层/座/室与街道后缀规则；当前规则近似无效。
3. 中文数字电话（长者口述常见）不覆盖；语音转文字后通常已是阿拉伯数字，风险主要在打字输入。
