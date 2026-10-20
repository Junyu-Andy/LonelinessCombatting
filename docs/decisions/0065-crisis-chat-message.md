# 0065：急性之后，聊天窗口只显示一条固定的安全消息，号码就是危机页那几个，两组相同

- 日期：2026-10-20
- 状态：提议中（Junyu 10/20 晚定：按修 bug 处理，不加开关，直接替换，进 10/21 冻结构建；开头一句 Junyu 10/20 定稿，decisions-log 第 86 条、交接 1020n 第一节）
- 影响范围：phase_b、pilot（含 RCT-）× 两组；所有会触发急性的聊天页
- 相关代码：分支 `claude/zealous-fermat-8rgqtg-crisismsg-1020m`；`lib/features/crisis/presentation/widgets/crisis_chat_message.dart`（新）、七个聊天页和两个规则组表单页、`lib/core/safety/safety_copy.dart`（删 `acuteAck`）

## 背景

Maria 测试发现（decisions-log 10/20 第 84 条）：急性触发后，危机页列出四个号码（生命熱線、撒瑪利亞會、醫管局精神健康專線、急症室 / 999），聊天窗口里却只有一句「請即刻打撒瑪利亞會 2896 0000」。老人没看危机页、或者没打电话就关掉，回到聊天看到的是另一套说法。

查到的来源：这句话**不是模型写的，也不是规则组模板**，而是安全流程里的固定句——`functions/prompts/safety_acknowledgements.json` 每位陪伴者的 `acute` 一条，`{{HOTLINE_NAME}} {{HOTLINE_NUMBER}}` 由 `crisis_resources.json` 里标了 `acuteTemplateReference` 的那一项（撒瑪利亞會）填进去。两组、所有聊天页都走这一条（`SafetyCopy.acuteAck`）。另外，旧的四个聊天页（旧 check-in、通通、回忆 v1、反思对话）会把这句话当作陪伴者说过的话，在之后的轮次发给模型。

## 决定

1. 急性之后（老人的话命中急性；或 Hybrid 组模型回复的扫描命中急性），聊天窗口显示**一条**固定消息 `CrisisChatMessage`，两组、每个聊天页都是同一个组件：
   - 开头一句（定稿，1020n 第一节）：「如果你而家好唔開心、好難頂，請即刻打以下電話，有人會聽你講：」
   - 下面逐项列出危机页的机构名和号码，**直接读危机页用的同一份配置**（`crisis_resources.json`，经 `SafetyCopy.crisis`），顺序、写法和危机页一样；代码里不写任何号码；
   - 最下面一个按钮「打開緊急求助頁」，打开的就是急性流程打开的那个危机页（记 `crisis_page_shown`，`from: crisis_chat_message`）。
2. 旧的按陪伴者区分的急性句**删掉**（`SafetyCopy.acuteAck` 和它的所有调用）。`safety_acknowledgements.json` 里的 `acute` 三条留在文件里不再被 App 读取（改这份文件会改 prompt 包的哈希，冻结前不动；服务器的 `safetyAcknowledgement` 函数 App 从来不调用）。
3. 这条消息不是模型写的，**也不发给模型**：旧四页在拼对话历史时跳过它（小欣新页本来就跳过系统句）。
4. 规则组旧的两个表单页（旧 check-in、回忆 v1）以前急性后页面上什么都不显示（check-in 还显示「收到喇。聽日再見。」）；现在同样显示这条消息，和 Hybrid 组旧聊天页对齐。
5. 不加开关（Junyu 10/20 晚改的指示）。检测、级别、门槛、危机页本身、号码、告警、会话结束方式都不变；中度提示不变；Hybrid 组模型回复里的号码照旧换成「【緊急熱線】」链接（T7 过滤，决策 0018）。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 只把 `acuteTemplateReference` 改指向别的热线 | 聊天里仍然只有一个号码，和危机页的四个还是对不上 |
| 改 `safety_acknowledgements.json` 的三句急性话，写上四个号码 | 号码又写了一份，日后改危机页会漏；改这份文件还会改 prompt 包哈希 |
| 放在开关后面 | Junyu 定按修 bug 处理，直接替换；关开关等于保留错误的说法 |
| 聊天里只放按钮，不列号码 | 老人可能不点；号码直接看得到更稳妥，而且和危机页一字不差 |

## 后果

- 对研究：两组急性后看到的东西完全相同（之前也相同，但只有一个号码）。规则组旧表单页多了这条消息，是安全界面，不是干预内容。`turns.ackShown` 在 Hybrid 组「模型回复被扫出急性」的那一轮由 false 变 true（现在确实显示了安全消息）。开头一句 Junyu 10/20 已定稿（1020n 第一节）；如需 PI / 伦理复核安全文字，一并送审。
- 对开发：新组件一个，九个页面各改几行，删 `acuteAck`，改四个旧测试，新测试 `test/crisis_chat_message_1020m_test.dart`（三种构建都跑）。
- 对论文：安全监测一节可写「急性触发后，聊天界面显示与危机页相同的求助资源清单，两组一致」。
