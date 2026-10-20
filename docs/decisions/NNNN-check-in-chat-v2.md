# NNNN：小欣卡片两组都打开同一个聊天窗口，check-in 在窗口里用固定问题和按钮完成，规则组另有小欣聊天回应池

- 日期：2026-10-19
- 状态：提议中（开发窗口草稿，等 Junyu 定编号和下面“要 Junyu 定”的几点）
- 影响范围：pilot、run-in（PB-）、rct（RCT-）× 两组
- 相关代码：分支 `claude/zealous-fermat-8rgqtg-batch2`（1020 第 2 批：A、F (1)–(4)、(6)）

## 背景

10/19 产品窗口定（1020 第 F 节、1020b 第四节）：check-in 改成对话形式，两组的问题文字、按钮和顺序完全相同，不由 LLM 生成，差别只在小欣的两句回应；规则组的小欣卡片以前直接进表单，没有聊天，要新建。10/19 PB-02 的规则组签到没有出现模板回应（A (1)），原因是旧表单只在编译开关 `RULE_TEMPLATE_REPLIES` 打开时才给模板。10/21 是冻结构建，所以新行为放在远程开关 `checkInChatV2Enabled` 后面，关着时一切照旧。

## 决定

1. **一个页面，两组共用**：新页面 `SiuYanChatPage`。所有进小欣的入口（小欣卡片、check-in 状态行、三天未做横幅、继续聊天卡、转介）经 `CheckInPage`，开关开时都打开它。旧的 `CheckInArmA`、`CheckInArmB` 原样保留，开关关时用。
2. **check-in 顺序**：Q0 → Q1 → Q2 → Q3 →（小事/大事时）Q3b → 回应一 → Q4 → 回应二 → Q5 → Q6。问题和按钮来自同一份文字（`docs/spec/copy/check-in-chat.md`）。
3. **回应一**：规则组按 Q1 五档从 5.4 的 X1–X5 选一条（近 3 次不重复，和旧表单共用同一份记录），Q1 唔想答用 XG；Hybrid 组由 LLM（新提示词 `siu_yan.v3`）按 Q1–Q3（和 Q3b）回一两句。
4. **回应二**：规则组 Q4 有答出 R4a，唔講住出 R4b；Hybrid 组 Q4 有答由 LLM 最多提一两个去处或做法、不催促；Hybrid 组唔講住（1020e 二.8 Junyu 定）也调用 LLM，只回一句、不给建议、不提问，失败时回落 R4b。
5. **规则组模板一定出现**：新窗口里规则组的模板不再看编译开关 `RULE_TEMPLATE_REPLIES`（修 A (1)）。
6. **安全**：Q3b、Q4 和之后打的字，两组都用同一个安全检测（输入点 `chat_check_in`，分类器开关开时两组都问分类器）。命中中度中断或急性时不出模板，走现有安全流程；规则组命中中度复核时用 SN 低落回应（1020e 二.10）。**命中 acute 时 check-in 到此结束**，不再问下一题，记录 `stopped_by_safety`、`stopped_at`；研究员在后台标记「誤觸」后（开关 `safetyFalseAlarmMarkEnabled`，函数 `markSafetyFalseAlarm`），老人当天再进小欣页从停下的那题接着问，过了当天不补（1020e 二.9）。
7. **会话**：check-in 做完（答完 Q5）就算一次有效会话（类型“签到”，`sessions.checkInCompleted`）；之后在同一窗口继续聊仍是同一会话，按现有规则结束。已做完再进来的聊天算“自由聊天”（moduleId `siu_yan_chat`，≥3 条有回复才有效）。Brief PR 按现有规则：v2 下只在列表页出邀请卡，不会签到后直接弹问卷（A (2)）。
8. **规则组小欣聊天**：已做完 check-in 再进来，规则组开场用 SY0；之后每句从 SY1–SY6 轮换（整组轮完再从头，近几次不重复）；当天最近一笔 `daily_mood` 是 1 或 2（唔係幾好／好唔開心），或从低落心情的开场进来（第 3 批接入），改用 SN1–SN4。Hybrid 组已做完时由 LLM 说开场（失败时用 SY0），之后照旧 LLM 聊天，原有的想法练习邀请、跨伙伴转介、记忆都保留。
9. **记录**：每次 check-in 一份 `check_in_responses`，答一题写一次（中途离开也留下已答部分），字段见 `lib/features/context/data/check_in_response_store.dart` 和报告。规则组的 Q3b、Q4 文字只存，不发给任何模型。
10. **Q5「好呀」**：打开该组现有的行动计划页（和「小行動」页的按钮同一个），回来后出 Q6。答 Q5 那一刻 check-in 就算完成。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 在旧的 `CheckInArmA` 里加分支，规则组另写一页 | 改动旧页面，开关关时的行为难保证一字不变；两组问题来自两处代码，容易不一致 |
| Hybrid 组唔講住用固定句 R4b | 1020e 二.8 Junyu 改为调用模型（一句、不建议、不提问），固定句只作失败时的回落 |
| acute 之后继续问完 check-in | 危机处置后再问“今日有咩打算”不合适；只有研究员标记误触后，当天才接着问（1020e 二.9） |
| 规则组聊天回应按 `RuleReplyPicker` 默认窗口 3 | 6 条的 SY 组只会轮到前 4 条；改成整组轮换 |

## 后果

- 对研究：check-in 不再问当天心情（心情由第一页记录，第 3 批）；Q1 问“尋日整體”。`check_in_responses` 新字段（`flow: chat_v2`、`schema_version: 2`、按题号的 `answers`、`study_week`）。`check_in_submitted` 事件的 `mood` 改为 Q1 分数（唔想答时没有），首页周小结图沿用这个字段。规则组有了小欣自由聊天，两组小欣都有聊天，使用量可比。登记表 C02、C16 对应条目要改（产品窗口）。
- 对开发：新文件见报告；共用代码只加了 `checkInCompleted`（会话有效规则）、`AnalyticsService.logCheckInChat`、`RuleReplyPool.checkInChatEntries`。提示词 `siu_yan.v3.txt` 新文件，旧文件不动；开开关前要先部署 Functions。
- 对论文：方法部分写 check-in 两组问题相同、回应来源不同；规则组小欣聊天用固定回应池；10/21 起生效。
