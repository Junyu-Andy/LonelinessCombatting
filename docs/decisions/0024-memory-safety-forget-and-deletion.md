# 0024：记忆只用安全的原话，摘要不写敏感内容，「唔好記住」整段不记，删除要连带摘要和以后的记录

- 日期：2026-10-07
- 状态：提议中（T10，PR 草稿；修复本身研究侧已定，下面的具体做法待负责人确认）
- 影响范围：所有 cohort × Hybrid 组（记忆 v1 只在 Hybrid 组）。规则组没有记忆，不受影响
- 相关代码：分支 `fix/memory-safety`（T10，SPEC:C05）

## 背景

T4 验收（`docs/dev-reports/T4-memory-acceptance-20261006.md`）整体不通过，研究侧定了上线前必须修 4 件事：
1. 安全内容进了会话摘要。服务器只查模型写出来的东西（17 个词），不查老人原话。
2. 摘要绕过了「敏感内容先确认」。
3. 「唔好記住」没有实现。
4. 页面上删一条，摘要里同样内容还在；删除脚本跑完，Phase B Hybrid 组的新对话照样被记下（强制开启不看 `memory_enabled`）。

难点：安全检测在 App（Dart），记忆整理在服务器（JS）。两边不能各写一套词表。

## 决定

1. **服务器用 App 同一份词库查老人原话。**
   - `functions/safety_lexicon.json` 由 App 的 `DistressDetector.lexicon` 生成；测试 `test/safety_lexicon_export_test.dart` 在两者不一致时失败，`UPDATE_SAFETY_LEXICON=1` 重新生成。两边还用同一组例句（`test/fixtures/safety_lexicon_cases.json`）互相核对。
   - 规则和 App 一样：moderate 或 acute（App 写 `safety_events`、不进缓冲区的那几档）。命中的那一轮老人原话、以及陪伴者对它的回复，不发给模型、不存进 `mem_extractions`。
   - 这一次会话有任何一轮命中，**整次不写摘要**；其他轮次的事实照常抽取（它们的引文都来自没命中的原话）。
   - 抽取 prompt v2 让模型另报 `safety_concern`（词库认不出的隐晦说法，如「儲安眠藥」）。为 true 时同样不写摘要，敏感的事实和跟进也不写。
   - 服务器原来查模型输出的 17 个词保留；摘要另外再用 App 词库查一次。
2. **摘要不写敏感内容（选「不写」，不选「先确认」）。** 抽取 prompt v2 要求摘要只写中性日常内容；服务器再按敏感规则判一次，判为敏感的摘要整条不存。之前已存的敏感摘要不再注入。敏感词表加了健康、丧亲、情绪类词（只会让更多条目等确认、更多摘要不存）。
3. **「唔好記住」：规则 + 关键词（`functions/memory_forget.js`），只看老人自己的话。**
   - 识别到后，这一次会话**整段不记**：不调用模型，不写摘要、事实、跟进，原话也不留。
   - 另外删除以前存下、看起来是同一件事的条目（任何陪伴者的事实、跟进、摘要），判断方法是和请求那句及前一句老人原话有 2 个以上相同的两字片段（去掉常见虚词）。
   - 覆盖的说法和边界见 T10 报告第 3 节。
   - 陪伴者回一句确认：开关 `forgetAckReply` 默认关；文字只是草稿（`functions/prompts/memory_forget_ack.v1.txt` 里是占位），占位没换掉之前打开开关也不会生效。
4. **删除要一致。**
   - 页面上删一条事实或跟进，服务器触发器同时删除它来源那次会话的摘要（不重新生成：原话在整理后就清掉了）。
   - `tool/delete_memory.js --confirm` 除了 `memory_enabled: false`，还写 `memoryWithdrawnAt`。服务器见到它就不再记录和注入，Phase B Hybrid 组也一样（强制开启让位于撤回）。这个字段只有服务器能写（Firestore 规则）。只清记忆、不停记忆（如测试账号）用 `--keep-memory-on`。
   - `tool/delete_participant.js` 删掉账号和用户文档后，服务器找不到用户，本来就不再记录；App 重建资料也写不了组别，所以仍不在范围内（有测试）。
   - 定时整理（`memorySweep`）改为和结束会话用同一条范围判断。
5. **顺带修了 T4、T16 里改动小的几处**（开关 `strictFactValidation`、`sensitiveFactQuota`）：陪伴者的名字不能记成老人的称呼；「更新」只能更新同一类事实；已记成跟进的计划不再记一次事实；已确认的敏感事实有自己的 5 个名额。
6. **抽取 prompt 改为文件**：`functions/prompts/memory_extraction.v1.txt`（原样搬出）和 `v2.txt`（新规则）。默认用 v2，可用 `extractionPrompt` 切回 v1。

所有开关在 Firestore `meta/memory_config`，修复默认开（写 `false` 关闭），确认句默认关：

| 开关 | 默认 |
|---|---|
| `excludeSafetyTurns` | 开 |
| `omitSensitiveSummary` | 开 |
| `honourForgetRequests` | 开 |
| `forgetAckReply` | **关** |
| `deleteSummaryWithItem` | 开 |
| `honourMemoryWithdrawal` | 开 |
| `strictFactValidation` | 开 |
| `sensitiveFactQuota` | 开 |
| `extractionPrompt` | `memory_extraction.v2` |

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 服务器另写一份安全词表 | 两边会慢慢不一致；任务单要求用同一份 |
| 服务器读 App 写的 `safety_events` 来判断哪一轮命中 | 事件不存原文，只有 hash；缓冲区里也没有轮次编号能对上 |
| 摘要敏感内容先让老人确认 | 要在「我記得嘅嘢」页面加新的界面和文字，老人看得到，要先定稿；「不写」更简单，也更保守 |
| 命中安全内容时整次会话什么都不记 | 一句话命中就丢掉整次会话的普通事实，代价太大；摘要是整次会话的概括，所以只停摘要 |
| 「唔好記住」只去掉那一句 | 老人说的「呢件事」通常在前面几句，切不准；整段不记最稳妥 |
| 用模型判断「唔好記住」指的是哪件事 | 多一次调用；而且不可预期。规则可测、可审 |
| 删一条事实后重新生成摘要 | 原话在整理后已清掉，无法重新生成 |
| 删除脚本后只看 `memory_enabled` | 每个 App 账号的 `memory_enabled` 默认就是 `false`，直接看它会关掉所有人的记忆 |

## 后果

- 对研究：ICF 可以写「你可以叫陪伴者唔好記住」「删除后陪伴者不会再记得」，但要说清边界：识别靠关键词；整段不记；以前的条目按字面相近删除，可能删多也可能漏删。确认句文字要研究侧定稿。词库没收的隐晦自伤说法（例如「儲安眠藥」）靠模型的 `safety_concern`，不是规则，有漏的可能；词库本身的扩充仍要 PI 签核（决策 0012）。删除脚本跑过的人，Phase B Hybrid 组的「强制记忆」对他停止，要在 fidelity 里记录。
- 对开发：`docs/dev/memory-v1.md` 和 `architecture.md` 第 7 节已更新。改 App 词库后要重新生成 `functions/safety_lexicon.json`（测试会提醒）。新增两个 Firestore 删除触发器。
- 对论文：方法部分写记忆的安全过滤与 App 共用词库；局限部分写「唔好記住」和关联删除是基于规则的。
