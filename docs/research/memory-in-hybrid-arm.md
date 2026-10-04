# 跨会话记忆：研究设计对齐

> 适用：Phase B（Mechanism RCT），以及 Phase A 中用来验证 Phase B 量表的部分
> 决策日期：2026-10-01 ｜ 对应决策记录：`docs/decisions/0001-memory-part-of-hybrid-arm.md`
> 本文件是论文方法部分的来源。改设计时先改这里，再改论文。

## 1. 决定

跨会话记忆算作 Hybrid LLM 组干预包的一部分，规则组没有记忆。

理由：从老人随口说的粤语里提取「孫仔叫明仔」「下禮拜四覆診」这类信息，规则系统做不到。所以「听懂并记住」本身就是 LLM 带来的能力。本研究的「LLM 增量」因此定义为三件事的整体：理解、记住、生成。不单独检验其中的「生成」。

被否决的方案：给规则组加模板式记忆（抽取仍用 LLM，用固定模板说出来）。这样对等更干净，但规则组的数据也要发给 LLM 处理，ICF 要改，而且要另外开发约 2–4 天。

## 2. 操纵定义（论文用的英文草稿）

**Methods 草稿：**

> The two arms differed only in the response-generation backend. In the Hybrid LLM arm, this backend comprised (a) LLM-generated replies and (b) LLM-based cross-session memory: after each session, the system extracted a session summary, user-stated facts, and dated follow-up items from the participant's own utterances, and injected them into the prompts of subsequent sessions. The rule-based arm used scripted responses and retained no information across sessions. The user interface, navigation, module structure, and notification schedule were identical across arms.

**Limitations 草稿：**

> Because cross-session memory was bundled with LLM-generated replies, the design cannot separate the contribution of generation from that of memory. A dismantling design that adds templated memory to the rule-based arm would be needed to isolate the two.

## 3. 需要同步修改的研究文件

| 文件 | 要改什么 | 状态 |
|---|---|---|
| 注册 | 核对干预描述。如果只写了「response-generation backend 不同」，要补上「Hybrid 组含跨会话记忆」。最好在第一位参与者入组前更新 | 待核对原文 |
| Protocol | 干预描述（同上）；加入本文第 4 节的操纵检验和第 5 节的探索性分析；写明版本冻结和偏离的处理办法 | 待改 |
| Hybrid 组 ICF | 写清：会记住什么（只记老人自己说的话）；在「我的資料」里能看、能删；说「唔好記住」会怎样；保留期（研究结束后 3 年）；研究结束时记忆怎么处理 | 待改，可能需要 HREC 修订 |
| 规则组 ICF | 不需要改。注意两组都有「我的資料」入口，ICF 里的描述要和实际一致 | 核对 |
| HREC | ICF 改动要报修订；如果采用 E4 微随机，也要报修订 | 视上两行而定 |
| Phase A | 如果 Phase A 用来验证 Phase B 的量表，phase_a 用户应该用 v1，不用 v0 | 待决定 |
| Exit interview 提纲（A 和 B） | 加入第 5 节 E5 的问题 | 待加 |

研究结束时的处理需要提前写进流程，不要留到最后。记忆会加深依恋，第 8 周随访结束时要说明三件事：记忆怎么处理、陪伴者怎么告别、之后还能不能继续用。

## 4. 操纵检验与过程指标

**主要指标：每次会话的记忆回调次数（人工编码）**

- 定义：陪伴者的回复中，提到了老人在之前会话里说过的具体信息。
- 子类型：事实回调、待跟进提问、摘要引用。
- 准确性：正确、错误、被老人当场纠正。
- 信度：两名编码员独立编码 20% 的会话，报告 Cohen's κ。
- B 组也要编码。预期接近 0，作为对照。

**辅助指标：实时自动匹配（`mem_callbacks`，见开发文档 3.9）**

只用于研究期间监测，不作为论文的主要指标。

**剂量的描述性统计**

每位参与者分别报告：存了多少条事实、注入了多少次、问了多少次待跟进、被纠正多少次、多少条停在「等确认」、删除了多少条、收到多少次口头删除请求。

**忠实度**

每条消息都记录模型名、app 版本和 prompt 版本。研究期间版本冻结，任何改动都记入 `docs/STUDY_CHANGELOG.md`。

## 5. 探索性研究问题

以下全部标为探索性，在 protocol 里写明，不作为确证性假设。

| 编号 | 问题 | 数据 | 分析 | 状态 |
|---|---|---|---|---|
| E1 | 有记忆回调的会话，当次的 Brief PR 是否更高？ | A 组会话层数据：回调编码 + Brief PR | 多层模型，人内中心化；协变量为会话长度、上次 PR、入组天数 | 做 |
| E2 | 记错或被纠正的会话，PR 是否下降？ | `user_corrected` 事件 + 回调准确性编码 | 同 E1 | 做 |
| E3 | 被记住之后，自我表露是否更多、更深？（Reis & Shaver 的亲密过程模型） | 两组：表露深度编码；A 组另有每次新抽取的事实数和敏感层级 | 按周的增长模型，比较两组的变化轨迹 | 做，需要先写表露编码方案 |
| E4 | 主动跟进对当次 PR 的因果效应 | A 组中有到期待跟进的会话，按 50% 随机决定带不带 | 微随机试验分析（加权中心化最小二乘，Boruvka et al., 2018） | 待定，先看 pilot 里待跟进出现的频率；要修订注册和 HREC |
| E5 | 老人怎样体验「被记住」 | Exit interview | 主题分析 | 做 |
| E6 | 注入「记住的观点」会不会让模型更倾向附和？ | 计算实验，不涉及参与者 | 立场泄漏审计 | 归入 IEA 论文 |

E5 的建议问题（粤语版待翻译）：

1. 佢記得你講過嘅嘢嗰陣，你覺得點？（被关心，还是被监视？）
2. 有冇試過佢記錯？你點樣處理？
3. 有冇啲嘢你唔想佢記住？

E4 的样本量估算：如果每人每周约 1 次到期的待跟进，4 周 × 36 人约 144 个决策点，其中约 72 个被随机分到「带」。效应要达到中等左右才看得出来。等 pilot 数据出来再算。

## 6. 附录里要报告的技术验证

- 记忆抽取测试集的结果：每个版本的召回率、捏造率、纠正识别率、日期换算准确率、敏感误报率（见开发文档 3.1）。
- 敏感话题词表和「唔好記住」意图词表的版本、词条数、误报测试结果。
- 测试集里随 prompt 版本变化的对比表，由 `docs/validation/` 自动生成。

## 7. 先写好的局限

1. 记忆和生成捆绑在一起，无法拆分（见第 2 节）。
2. 记忆剂量因人而异。话说得越多，记住的也越多，所以剂量和投入程度相关。
3. 敏感事实需要老人在页面上确认，部分事实可能一直没被用上。
4. 抽取由第三方 LLM（DeepSeek）完成。
5. 只在粤语和香港社区老人中验证。

## 8. 待确认

- [ ] 注册和 protocol 里干预描述的原文
- [ ] Hybrid 组 ICF 里关于数据保留和查看、删除的现有写法
- [ ] Brief PR 现在在什么时点弹出（关系到会话的定义，见开发文档 3.8）
- [ ] phase_a 用 v0 还是 v1
- [ ] E4 是否采用
- [ ] app 内的 `assignArm` 和独立的 HTML 随机化工具（v1.3.1）之间是什么关系：以哪个为准，分层（DJG-ES）在哪里实现
