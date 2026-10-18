# NNNN：三位陪伴者提示词升版（小欣 v2、阿珍／阿伯 v2、通通 v3），加一个按入组偏好填的语气槽位

- 日期：2026-10-18
- 状态：提议中（草稿，编号待分配；Junyu 看过最终文本再合）
- 影响范围：phase_b、pilot × Hybrid 组（规则组不调用 AI，不读这些提示词）
- 相关代码：`functions/prompts/siu_yan.v2.txt`、`ah_jan_ah_bak.v2.txt`、`tung_tung.v3.txt`；`functions/prompt_registry.js`；`functions/index.js`（`resolvePrompt`、`proxyDeepSeek`、`referralJudgement`）；`lib/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart`；PR 草稿（分支 `feat/t49b-prompts-tone-slot`，T49b）

## 背景

10/16 第 5 条定：入组时问老人「鍾意人直接啲講定溫和啲講」，陪伴者要照着调语气。同时现行三份提示词有几处旧文字：自称「AI 機械人」（10/15 起老人看到的介绍已改叫「電腦程式夥伴」，S15）；通通还写着「幫佢搵資料」、模式 B 叫「興趣閒聊 + 搜尋」（Phase B 搜一搜关闭，决策 0019）；末尾「Context injection 格式」列的 `rolling_summary`、`named_entities` 服务器从来不填（`docs/dev-reports/memory-mechanism-20261018.md` 第 4.3 节）。另外回忆页是 Hybrid 组唯一没把「唔想提起的话题」告诉陪伴者的聊天页。

## 决定

1. 新开三个版本文件，旧文件不动：小欣 v2、阿珍／阿伯 v2、通通 v3（rev 2026-10）。App 发的 key 不变，服务器在 `PROMPT_FILES` 里换文件。
2. 三份都在规矩前面加一节「語氣（由入組資料決定）」，里面是 `{{TONE_RULE}}`。服务器每次调用读 `users/{uid}.encouragementStyle` 填：
   - `direct`：呢位用戶鍾意人直接講。重點放第一句，少鋪墊。其他規矩照舊，唔好提起呢個設定。
   - `gentle`：呢位用戶鍾意人溫和啲講。句子短啲、慢啲，留餘地。其他規矩照舊，唔好提起呢個設定。
   - `either`、没录入、读不到：（用戶冇特別偏好，照以下規矩嘅默認語氣。）
   语气只从服务器读到的资料来，App 传什么都不算。规则组在服务器第一步就被拒绝，到不了这里。
3. 身份说法改「電腦程式夥伴」；被问起时「老實講你係電腦程式，唔係真人」；不用「AI」「模型」「機械人」这些字，不说自己是哪一版（参与者盲法）。
4. 删掉搜资料的旧句（通通活动范围、模式 B 标题；小欣规矩 8 改成「過去同通通傾下」）。通通「冇 search 結果唔好作數字」两条保留。
5. 删掉末尾「Context injection 格式」整节；小欣规矩 7、阿珍规矩 11 改说「系統會喺提示詞後面附上記憶（<memory> 塊）」。
6. 回忆页（Hybrid）在发给陪伴者的上下文里补上「⛔ 用戶要求唔好提起呢啲話題（就算唔小心都唔好）：…」，和签到页同一句。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 把语气偏好当一条记忆写进去（T48 的入组记忆） | 记忆可能被挤出预算、可能不注入（记忆开关关时）；语气是每一句都要守的规矩，放在提示词本身更稳。T48/#111 现在也写了一条「鍾意人點樣講嘢」记忆，两处重复，见「后果」 |
| App 把偏好放进 `contextSuffix` | App 传的东西可以被改；而且要改三个页面，规则组页面也会碰到这段代码 |
| 原文件直接改 | CLAUDE.md：改内容就新建版本文件，不覆盖旧文件 |
| 新行为放开关后默认关 | 语气槽位本身没有单独开关。没录入鼓励方式的人只看到默认那一句，行为不变；`encouragementStyle` 只有 #111 的研究员录入会写，而那个入口在 `researcherIntakeEnabled` 开关后面（默认关）。提示词换版本和 tung_tung.v2（决策 0019）一样，随 Functions 部署生效 |

## 后果

- 对研究：干预输入变了。没录入鼓励方式的老人：只有身份说法和搜资料旧句的文字变（第 3、4 条），行为预期不变；第 5 条删的是从来没填过的死文字。录了 `direct` / `gentle` 的老人：语气按偏好调整，只在 Hybrid 组。登记表组间差异要加一句「语气按入组偏好调整，只在 Hybrid 组」，B07 §5.2 一句由产品窗口改（任务单 §B5）。10/19 冻结后合并算 protocol deviation，STUDY_CHANGELOG 已记。三位试跑老人 W4 时补问鼓励方式（§B6，研究侧记在 B20）。
- 对开发：`llm_calls` / `turns` 的 `systemPromptHash` 和 `promptVersion`（`siu_yan_v2@2026-10`、`ah_jan_ah_bak_v2@2026-10`、`tung_tung_v3@2026-10`）从部署那一刻变。每次调用多读一次 `users/{uid}`。PR #111 现在还把偏好写成记忆条目「鍾意人點樣講嘢：直接啲（用戶入組時自己揀）」，和语气槽位重复，而且用了任务单不让用的「入組時揀」说法，合并前要定留哪一处。
- 对论文：方法部分 Hybrid 组干预描述加一句「陪伴者语气按入组时老人表达的偏好（直接／温和）调整」；fidelity 部分写明生效日。
