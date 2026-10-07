# 0020：「共享上下文」同意真正控制跨陪伴者共享（开关默认关）；对话保留默认值改为配置；新增整人删除脚本

- 日期：2026-10-07
- 状态：提议中（代码已写，开关默认关，等研究侧按 ICF 定开关和默认值）
- 影响范围：所有 cohort × Hybrid 组（共享只在 Hybrid 组有）；删除脚本两组都适用
- 相关代码：分支 `fix/privacy-consent`（T11，SPEC:C20）

## 背景

T2 报告发现三件事：
1. `consent.sharedContextUse` 存下来了，但没有任何代码读它。陪伴者之间照样共享记忆。
2. 「保留对话」同意写死为默认开启（同意页和陪伴者介绍页都写 `true`），要改只能改代码、重新发版。
3. 没有删除整个参与者的手段。`tool/delete_memory.js` 只删记忆。

难点：现有账号的 `sharedContextUse` 全是 `false`（同意页从来没写过这个字段）。如果直接让它生效，所有人的跨陪伴者共享会在部署当天一起关掉，这是干预内容的变化，要研究侧先定。

## 决定

1. **共享同意开关**：新增开关 `enforceSharedContextConsent`，放在 Firestore `app_config/phase_a`，**默认关**。App 和服务器读同一个键。
   - 关：和现在完全一样，不看 `sharedContextUse`。
   - 开：`sharedContextUse` 不是 `true` 的人，每个陪伴者只用自己的记忆：
     - 记忆 v1（服务器）：共享策略按 B 处理（各看各的），注入和抽取都一样；
     - 记忆 v0（App）：小欣签到不再引用阿珍/阿伯的回忆摘要；转介时不再把老人原话存进 `pendingReferrals.triggerSnippet`（存空字符串）。转介卡片本身照常出现。
   - 心情分数（`recentMoodSummary`，1–5 分）不算跨陪伴者记忆，不受影响。
2. **默认值改为配置**（同样在 `app_config/phase_a`，只影响还没点过同意页的新账号）：
   - `transcriptRetentionDefault`：默认 `true`（保持现状）；
   - `sharedContextUseDefault`：默认 `false`（保持现状）。
3. **整人删除脚本** `tool/delete_participant.js`：默认只列不删；`--confirm` 才删，删完再扫一遍，有残留就报错；输出只含数量的存证清单。周度盲法导出文件默认只数不改，加 `--rewrite-exports` 才重写。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 直接让 `sharedContextUse` 生效 | 现有账号都是 `false`，部署当天所有人的共享一起关掉，改变干预内容 |
| 开关做成编译开关（`--dart-define`） | 要重新发版；而且服务器读不到 |
| App 和服务器各用一个开关 | 两个开关可能不一致；v1 用户同时走两条路径 |
| 删除脚本直接改导出文件 | 导出是全体参与者的研究数据，改不改由研究侧定 |
| 在 App 里加「删除账号」按钮 | 老人看得到的新功能，要先定文案和流程；本批只做研究员用的脚本 |

## 后果

- 对研究：开关打开前，ICF 要写清「陪伴者之间会共享哪些内容」以及默认值；打开时要同时决定现有账号的 `sharedContextUse` 怎么补（现在全是 `false`）。打开后会改变 Hybrid 组的干预内容，要在 STUDY_CHANGELOG 写明生效日期和影响的 cohort。删除脚本让 ICF 的退出删除承诺有了执行手段，但 Cloud Logging、DeepSeek/Brave 那边、研究员本机导出、手机缓存仍删不到。
- 对开发：T10 之后改记忆时，`effectivePolicy`（`functions/memory.js`）要保留。T12 改导出（研究编号）后，删除脚本要加按研究编号找行、删对照表那一行。
- 对论文：如果研究期间打开开关，fidelity 部分要写；局限部分写清哪些数据删不到。
