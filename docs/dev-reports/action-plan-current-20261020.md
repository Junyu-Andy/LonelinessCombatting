# 行动计划：现状、最小改法和工时（2026-10-20）

分支 `claude/zealous-fermat-8rgqtg-actionplan`，从第 2 批分支 `claude/zealous-fermat-8rgqtg-batch2`（`8e39e5e`，含小欣 check-in Q5）开。**只有报告和截图，App 行为没改。** 没连生产 Firestore；截图用合成数据和假的 AI 回复（测试里跑，跑完删了测试文件）。

## 结论

1. **从建议进去，要填的确实多。** Hybrid 组要连续打 4 次字（幾時、邊度、同邊個、唔得點），每一步都必须填，空着按「下一步」没反应、也没提示。规则组是一页 4 组选项，4 组都要选，「儲存計劃」才会亮，没提示还差哪一组。两组只预填了「做咩」。
2. **已经订好的计划，不能改、不能删。** 只能答「件事點呀？」。答完之后计划就从 App 里消失，没有地方再看。
3. **「时间」其实只是一句文字。** Hybrid 组是老人打的字（如「聽朝食完早餐」），规则组是上晝／下晝／晚上。提醒一律在**存计划后 24 小时**，和老人填的时间无关。提醒推送默认关。
4. **两组差别**：页面样子不同（Hybrid 一问一答，规则组一页选项）；Hybrid 组在「檢視」和「件事點呀」各调用一次 AI。**规则组在整个流程里没有任何 AI 调用**，服务器也会拒绝。
5. **最小改法**（只是方案，没做）：两组同一套规则——从建议进去「做咩」预填，只必填「幾時」，其余可以不填；已有计划可以改「做咩」和「幾時」、可以删除。放在开关 `actionPlanSimplifiedEnabled` 后面，默认关。
6. **工时约 18–20 小时**（做 + 测试 + 截图 + 文档 + 来回）。还要先写决策记录、Junyu 看截图定文字。
7. **建议：10/21 冻结前做不完，整项留到 Phase B 之后。** 按规定不做一半。

---

## 一、现状

### 1.1 所有入口

App 里没有叫「我嘅計劃」的页面。最接近的是「做啲嘢 → 跟進計劃」进去的「小行動」页。

| # | 老人怎样进去 | 打开什么 | 预填 | 代码 |
|---|---|---|---|---|
| 1 | 做啲嘢 →「一啲社交小行動」→「今日嘅小邀請」页 → 某条建议的「計劃做」 | 本组的计划页 | 「做咩」= 建议原文 | `me_page.dart:88-99`；`social_suggestions_page.dart:193-212` |
| 2 | 做啲嘢 →「跟進計劃」→「小行動」页 →「計劃一個小行動」 | 本组的计划页 | 无 | `me_page.dart:66-75`；`action_loop_landing.dart:49-59, 106-111` |
| 3 | 睇今日（首页）底部「行動」快捷 | 同 2 的「小行動」页 | 无 | `home_tool_shortcuts.dart:21-27`；`today_page.dart:133` |
| 4 | 小欣 check-in Q5「想訂個小計劃嗎？」→「好呀」 | 本组的计划页，回来后出 Q6 | 无 | `siu_yan_chat_page.dart:507, 522-538`；`check_in_chat_copy.dart:82-86`（开关 `checkInChatV2Enabled`，10/21 构建设为开） |
| 5 | 自己 → 個人資料 →「加多一個提醒」 | 同 2 的「小行動」页 | 无 | `follow_up_section.dart:51-62`；`personalization_page.dart:117` |
| 6 | 首页「今日嘅小行動」横幅 | — | — | `active_plan_banner.dart`。**永远不出现**：它只认 `scheduledFor`，而两组存计划时都不写这个字段（`active_plan_banner.dart:55`） |
| 7 | 「行動計劃」小方块 `ToolQuickLinks` | — | — | `tool_quick_links.dart`，**没有任何页面用它** |
| 8 | 提醒推送 | 只打开 App，不跳到计划 | — | `fcm_service.dart:123-131`；推送开关默认关 |

2、3、5 是同一个「小行動」页。4 和 2 打开的是同一个计划页（截图逐像素相同）。

### 1.2 从建议进去：每一步

**Hybrid 组（A）**

| 步 | 画面 | 要做什么 | 必填？怎样强制 | 预填 | 截图 |
|---|---|---|---|---|---|
| 0 | 做啲嘢 | 撳「一啲社交小行動」 | — | — | `00_entry_me_tab.png` |
| 1 | 今日嘅小邀請 | AI 出 1–2 条建议，撳「計劃做」。AI 没回就退回固定建议池 | — | — | `10_suggestions_A.png` |
| 2 | 計劃一個小行動 · 第 2 步「幾時」 | 打字 | 必填。空着按「下一步」直接 `return`，画面不变、没有提示（`action_loop_arm_a_page.dart:136-137`） | 无。**建议原文不显示**：有预填时直接跳过「做咩」这一步（`:83-87`） | `11_A_step_when.png` |
| 3 | 第 3 步「邊度」 | 打字 | 必填（同上） | 无 | `12_A_step_where.png` |
| 4 | 第 4 步「同邊個」 | 打字，或撳人名按钮填入 | 必填（同上） | 人名按钮来自入组资料（`:355-367`） | `13_A_step_who.png` |
| 5 | 第 5 步「唔得點」 | 打字 | 必填（同上） | 无 | `14_A_step_fallback.png` |
| 6 | 第 6 步「檢視」 | AI 写一句 if-then；撳「儲存計劃」 | 不能改这句 | — | `15_A_review.png` |
| 7 | 完成 | 「收到。等你返嚟同我講件事點。」0.7 秒后自动返回（`:274-279`） | — | — | `16_A_saved.png` |

合计：打 4 次字，按 6 次按钮。

**规则组（B）**

| 步 | 画面 | 要做什么 | 必填？怎样强制 | 预填 | 截图 |
|---|---|---|---|---|---|
| 0 | 做啲嘢 | 同上 | — | — | `00_entry_me_tab.png` |
| 1 | 今日嘅小邀請 | 固定 16 条里每天轮 2 条（`social_suggestions_page.dart:218-221`），撳「計劃做」 | — | — | `10_suggestions_B.png` |
| 2 | 計劃一個小行動（一页） | 做咩：文字框；幾時：上晝／下晝／晚上；邊度：屋企／出街／其他地方；同邊個：入组资料的人名 + 屋企人／朋友／一個人；如果唔成功：今日遲啲再試／聽日再試／今次算 | **五项都必填**：`_isComplete`（`action_loop_arm_b_page.dart:58-63`）；没齐时「儲存計劃」变灰（`:227`），不说差哪项 | 「做咩」= 建议原文，可改。文字框只有一行，长句被截断（`:175-184`） | `11_B_form_top.png`、`12_B_form_bottom_save_disabled.png`、`13_B_form_filled_save_enabled.png` |
| 3 | 存好 | 安全检测「做咩」后直接关页，没有确认句（`:103-114`） | — | — | — |

合计：选 4 个选项，按 1 次储存。

**没有预填的入口（2、3、4、5）**：Hybrid 组从第 1 步「做咩」开始，多打一次字；规则组「做咩」是空的。见 `20_planner_no_seed_A.png`、`20_planner_no_seed_B.png`。Q5 画面见 `30_q5_A.png`、`30_q5_B.png`。

### 1.3 已有计划现在能做什么

| 能做什么 | 现在 | 依据 | 截图 |
|---|---|---|---|
| 看 | **部分可以**。「小行動」页「等住跟進」只列**还没答**「件事點呀」的计划，每张卡显示「做咩」和「幾時 · 同邊個」；撳卡进「件事點呀？」页能看到全部四项。答了之后计划从所有页面消失；有读全部计划的方法 `all()`，但没人用 | `action_loop_landing.dart:74-98, 161-211`；`action_loop_followup_page.dart:154-172`；`action_plan.dart:152-160` | `02_landing.png`（测试没有数据库，所以列表是空的样子）、`40_followup.png` |
| 完成（答「件事點呀」） | **可以**。三选一（做到喇／做咗一部分／未做到）必选，备注选填。存后同计划的未发提醒被删除 | `action_loop_followup_page.dart:60-92, 179-240` | `40_followup.png`、`41_followup_saved_A.png`、`41_followup_saved_B.png` |
| 删除 | **不可以**。没有按钮；数据层也没有删除方法 | `action_plan.dart:98-161`（只有 create、updateOutcome、pending、all） | — |
| 改文字 | **不可以**。同上 | 同上 | — |
| 改时间 | **不可以**。而且没有「真正的时间」：只有一句文字 `whenText`；`scheduledFor` 从来不写；提醒固定在存后 24 小时 | `action_loop_arm_a_page.dart:264`；`action_loop_arm_b_page.dart:93` | — |

「件事點呀？」页两组在答之前完全一样（`40_followup.png` 两组逐像素相同）。答之后 Hybrid 组多一张 AI 回应卡（`41_followup_saved_A.png`），规则组没有（`41_followup_saved_B.png`）。

### 1.4 写了哪些数据

**`users/{uid}/action_plans/{自动编号}`**（两组同一个集合，`action_plan.dart:48-59, 109-131`）

| 字段 | 内容 | 两组差别 |
|---|---|---|
| `action` | 做咩 | 相同 |
| `whenText` | 幾時 | Hybrid 自由文字；规则组三选一 |
| `whereText`、`whoWith`、`fallback` | 邊度、同邊個、唔得點 | Hybrid 自由文字；规则组选项（同邊個可以是人名） |
| `arm` | `A` / `B` | 由页面写死（`arm_a:249`、`arm_b:82`），不读帐号 |
| `createdAt` | 服务器时间 | 相同 |
| `scheduledFor`、`outcome`、`followUpNote` | 新建时为空 | 相同 |
| `outcome`、`followUpNote`、`followedUpAt` | 答「件事點呀」时写 | 相同 |

Hybrid 组「檢視」那句 AI 总结**不存进计划**，只在屏幕上显示。

**`users/{uid}/reminders/{自动编号}`**（`reminder_service.dart:69-79`）：`kind: m7_followup`、`fireAt`（存后 24 小时）、`titleZh`「件事點呀？」、`bodyZh`「你之前計劃做：{做咩}。」、`linkedDocId`、`delivered: false`。服务器 `dispatchReminders` 只在 `app_config/reminders.m7FollowupPushEnabled` 为 true 时发，推送正文是 S4a「你今日有個小計劃，得閒打開睇下。」，不带计划原文（`functions/reminders.js:44, 121`）；计划已删或已答就不发（`:197-198`）；发了写 `events` 的 `m7_reminder_sent`（`:239`）。

**事件和会话**
- 入口 2、3、4、5：「小行動」页和 Q5 打开计划页时写一条工具会话（`sessions`，`kind: tool`，`toolId: action_loop`）和 `agent_session_start／end` 事件（`chat_session_recorder.dart:880-940`）。**入口 1（从建议进去）没有会话记录**：建议页没有包这一层。
- `m7_plan_saved`、`m7_followup_completed`、`m6_social_suggestion_shown／accepted` 四个事件**定义了但从来没被调用**（`analytics_service.dart:62, 319-330`）。所以现在「订了几个计划」只能数 `action_plans`。
- 安全检测：Hybrid 组五项文字经 AI 网关一起查（输入点 `action_plan`）；规则组查「做咩」文字（同一输入点，`arm_b:106-111`）；跟进备注同理（`action_followup`）。两组用同一个词库。
- 导出：`action_plans`、`reminders` 在盲法导出里整块扣下，揭盲后才给（`functions/blinding.js:264`）。

### 1.5 AI 用在哪里（只有 Hybrid 组）

| moduleId | 什么时候 | 做什么 | 存不存 | 服务器 `llm_calls` 类型 |
|---|---|---|---|---|
| `m6_suggestions` | 打开「今日嘅小邀請」 | 出 1–2 条建议（这是建议页，不是计划本身） | 不存 | `suggestions` |
| `m7_action_loop_summary` | 第 5 步答完 | 把五项写成一句 if-then，≤40 字；AI 没回就用模板句（`action_loop_arm_a_page.dart:190-229`） | 不存 | `session_summary` |
| `m7_action_loop_followup` | 「件事點呀」存后 | 1–2 句回应，不建议新计划（`action_loop_followup_page.dart:95-124`） | 不存 | `chat` |

- 两个 m7 提示词写在 App 代码里（`arm_a:49-61`、`followup:33-45`），不在 `functions/prompts/`（旧情况，这次不动）。
- 不注入记忆：`m7_*` 不在服务器 `INJECT_MODULES`（`functions/memory.js:71-73`）。
- 两处都先过 `TranscriptConsentPrompter`（`m7_action_loop`、`m7_followup`）。

**规则组没有 AI 调用**：规则组计划页不引用 AI 网关（`action_loop_arm_b_page.dart:1-10`）；「件事點呀」只在 `Arm.isA` 时调用（`followup:95`）；建议页 `_maybeLoadArmA` 对非 A 组直接返回（`social_suggestions_page.dart:89-90`）；Q5 按组选页面（`siu_yan_chat_page.dart:534-535`）。服务器 `proxyDeepSeek` 对 B 组也会拒绝。

### 1.6 顺带发现（不在这次范围，记下来）

1. 首页「今日嘅小行動」横幅、「個人資料」里「即將到嘅提醒」永远是空的（都只认 `scheduledFor`）。**注意：以后谁开始写 `scheduledFor`，这两处会突然出现。**
2. 四个计划相关事件从没写过（见 1.4）。
3. 从建议进去不记工具会话。
4. Hybrid 组从建议进去，整个过程看不到建议原文，直到「檢視」才看到 AI 改写后的句子。
5. 规则组「做咩」文字框一行，预填长句被截断（`11_B_form_top.png`）。
6. `reminders.bodyZh` 存了计划原文（不推送，但在数据库里）。
7. `ToolQuickLinks` 没人用。

---

## 二、最小改法（方案，没有实现）

### 2.1 做什么（两组完全相同的规则）

- **从建议进去**：「做咩」预填建议原文，看得到、可以改。**只必填「幾時」。** 邊度、同邊個、唔得點都可以不填。
- **其他入口**同一规则：必填「做咩」+「幾時」，其余可以不填。（这样代码不用分入口；从建议进去时「做咩」已经有了，等于只填「幾時」。）
- **已有计划**（「等住跟進」里的）：可以改「做咩」和「幾時」，可以删除。
- 不新增 AI 调用。Hybrid 组「檢視」的 AI 一句话照旧（这是登记的组间差别 C07），只是输入少了没填的项。改计划、删计划两组都不用 AI。
- 两组页面样子维持现在的差别（Hybrid 一问一答、规则组一页选项）。要两组页面一模一样，规则组「幾時」的含义和 Hybrid 组的 AI 总结都要动，不算最小，不建议现在做。

### 2.2 改哪些文件

| 文件 | 改动 |
|---|---|
| `lib/core/feature_flags/remote_feature_flags.dart` | 新开关 `actionPlanSimplifiedEnabled`（在 `app_config/feature_flags`，默认关；关时一切照旧） |
| `lib/features/action_loop/presentation/pages/action_loop_arm_b_page.dart` | `_isComplete` 开关开时只看「做咩」和「幾時」；邊度、同邊個、如果唔成功标题加「（可以唔揀）」，再撳一次可以取消；「做咩」框改多行；按钮上方一句提示还差什么；存时写 `source` 等新字段 |
| `lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart` | 有预填时每一步顶部显示「你想做：…」；「幾時」之后直接到「檢視」；「檢視」下面加「加多啲細節（可以唔填）」，进去的三步各有「跳過」；`_advance` 允许这三步为空；AI 输入和模板句只用已填的项；步数条按实际步数；空着按「下一步」给一句提示 |
| `lib/features/action_loop/presentation/pages/action_plan_edit_page.dart`（新） | 两组同一页：「做咩」（多行）、「幾時」（文字框 + 上晝／下晝／晚上快捷按钮）、「儲存」、「刪除呢個計劃」（先确认）。文字过同一套安全检测（`SafetyService.checkAndRoute`，输入点 `action_plan`），两组一样 |
| `lib/features/action_loop/presentation/pages/action_loop_landing.dart` | `_PendingPlanCard` 下面加「改」「刪除」两个大按钮；撳卡本身仍进「件事點呀？」 |
| `lib/features/action_loop/data/action_plan.dart` | 模型加新字段；`update()`、`softDelete()`；`pending()` 过滤掉已删的；生成更新内容的部分写成纯函数，方便测试 |
| `lib/features/social_suggestions/presentation/pages/social_suggestions_page.dart`、`action_loop_landing.dart`、`siu_yan_chat_page.dart` | 打开计划页时传入口 `source` |
| `lib/features/analytics/data/analytics_service.dart` | 接上 `m7_plan_saved`；新加 `m7_plan_edited`、`m7_plan_deleted`（都要带组别） |
| `functions/reminders.js` | 计划有 `deletedAt` 时不发，记 `skipped_plan_deleted`（防 App 删提醒失败）；加一条模拟器测试 |
| Firestore 规则 | **不用改**：老人本来就能改、删自己的 `action_plans`（`firestore.rules:206-218`） |

### 2.3 新写的字段和事件（都是新增，不改旧字段的名字）

**`action_plans` 新字段**

| 字段 | 什么时候写 | 意思 |
|---|---|---|
| `planFormVersion: 2` | 开关开时新建 | 这条是新规则下订的；空的邊度／同邊個／唔得點 = 老人跳过 |
| `source` | 新建 | `suggestion`／`landing`／`check_in_q5` |
| `seedAction` | 从建议新建 | 建议原文（老人改过「做咩」也能看出来） |
| `original` | 第一次改时写一次 | `{action, whenText}`：最初存的版本 |
| `editCount`、`lastEditedAt` | 每次改 | 改了几次、最后一次时间 |
| `editLog` | 每次改追加一条 | `{atLocal, fields, before}`：改了哪项、改之前是什么 |
| `deletedAt`、`deletedFrom` | 删除 | **软删除**：计划留在数据库，App 不再显示 |

**事件**（`users/{uid}/events`，不带老人原文）：`m7_plan_saved {source, filled}`、`m7_plan_edited {fields}`、`m7_plan_deleted {source}`。

**不写 `scheduledFor`**，否则 1.6 第 1 条的两个隐藏画面会出现。

### 2.4 改了时间，提醒和跟进怎么办

- **提醒时间不动。** 现在提醒本来就和老人填的「幾時」无关，一律存后 24 小时；「幾時」仍是一句文字，没法换算成钟点。改「幾時」后提醒仍在原来时间（推送开关默认关，开着也只推 S4a，不带计划内容）。
- 改「做咩」时，顺手把未发提醒里存的 `bodyZh／bodyEn` 换成新文字（只是数据库里的字，不影响推送）。
- **删除**：App 删掉这个计划所有未发的提醒（和「件事點呀」存后删提醒同一做法，`followup:81-92`）；服务器再加一道 `deletedAt` 检查。
- **跟进**：删了的计划从「等住跟進」消失，不会再问。改了的计划，「件事點呀？」页显示新文字；Hybrid 组跟进时 AI 读到的也是新文字。已经答过的计划不能改（本来也看不到）。
- 想要「提醒跟着时间走」，就要把「幾時」改成真正的日期钟点，还会唤醒首页横幅。这不是最小改法，留到 Phase B 之后。

### 2.5 老人看得到的新文字（全部是草稿，Junyu 在 PR 截图里定）

| 位置 | 草稿 |
|---|---|
| 规则组选项标题后缀 | 【草稿】（可以唔揀） |
| 规则组储存按钮上方提示 | 【草稿】揀咗「幾時」就可以儲存 |
| Hybrid 每步顶部 | 【草稿】你想做：{做咩} |
| Hybrid 空着按下一步 | 【草稿】寫少少就得，例如「聽朝」 |
| Hybrid「檢視」下的按钮 | 【草稿】加多啲細節（可以唔填） |
| Hybrid 可跳过的三步 | 【草稿】跳過 |
| 「等住跟進」卡上按钮 | 【草稿】改　／　刪除 |
| 改计划页标题、按钮 | 【草稿】改計劃　／　儲存　／　刪除呢個計劃 |
| 删除确认 | 【草稿】刪咗呢個計劃？　按钮：刪除／唔刪 |
| 删除后 | 【草稿】已經刪咗 |

### 2.6 对研究数据的影响

**原则：只加新字段，不偷偷改旧字段的意思。** 但有三处旧字段的意思会变，要在数据字典和 changelog 里写明：

1. `whereText`、`whoWith`、`fallback` 以前一定有值；新规则下可以是空的。用 `planFormVersion: 2` 区分。
2. 改过的计划，`action`、`whenText` 是**最新版本**，不再是「订的时候」的版本；订的时候的版本在 `original`。用 `editCount > 0` 区分。
3. 规则组的 `whenText` 以前只有三个值；改计划页允许打字后，改过的规则组计划可能是自由文字。同样用 `editCount > 0` 区分。

**删除用软删除。** 硬删除会让「订了几个计划」这个数少掉，而且删了就查不回来。软删除留一行 `deletedAt`，分析时自己决定算不算。

**组间比较**：开关开的那天起两组用同一套规则，组间比较仍然公平；但开关前后「填了几项」不能直接比。STUDY_CHANGELOG 要写清 cohort、两组、生效日期；已打 phaseB tag 的话算 protocol deviation。

**导出**：`action_plans` 本来就在盲法导出里扣下（`blinding.js:264`），新字段跟着扣下，不用改导出。数据字典（T2）要加新字段。

---

## 三、工时估计

| 部分 | 小时 |
|---|---|
| 决策记录草稿（设计改动，要先写）+ 开关 | 1 |
| 从建议进去：规则组页、Hybrid 页按新规则改 | 3.5 |
| 已有计划：改计划页、列表按钮、数据层、提醒处理、服务器一处检查 | 5 |
| 新字段、事件、入口来源 | 1 |
| 测试：两组新规则；开关关时完全不变；规则组零 AI 调用；改、删的数据内容；Functions 提醒测试；`tool/ci_flutter_tests.sh` 多套 + `tool/ci_backend_tests.sh` | 3.5 |
| 截图（两组、360 宽、开关开） | 1 |
| 文档（changelog、architecture、history、backlog、数据字典、文字草稿） | 1.5 |
| **小计** | **16.5** |
| review 来回、Junyu 定文字后再改 | 2–4 |
| **合计** | **约 18–20 小时（2–3 个工作日）** |

**风险**

1. Hybrid 组计划页流程要重排（跳步、可选步、AI 输入变少），是干预内容的改动，要决策记录。
2. 测试环境没有假数据库，「改」「删」只能测生成的数据内容，真写入要靠模拟器或真机，费时。
3. 第 2 批 Q5 也打开这个计划页，改了要重测第 2 批的画面。
4. 新文字要 Junyu 看截图定，日历上要等。
5. 一不小心写了 `scheduledFor`，首页会多出横幅。
6. 冻结后合并算 protocol deviation，要在 changelog 记组别和日期。

**建议：10/21 冻结前做不完，整项留到 Phase B 之后。**
今天到冻结不到一天，这件事要 2–3 天，而且要先写决策记录、等 Junyu 定文字。按规定不做一半：不要只做「规则组少必填」或只做「删除」，否则两组规则不一致，或数据意思中途改变。

在那之前不改 App。如果要缓解，可以在 W0 时口头教老人：订错了就在「件事點呀」揀「未做到」，再订一个新的。这不需要改代码。

---

## 四、截图

都在 `docs/dev-reports/action-plan-20261020-shots/`，360 逻辑像素宽，文泉驿正黑字体，合成数据和假的 AI 回复。标「两组相同」的，测试里比对过两组逐像素相同。

| 文件 | 内容 | 组别 |
|---|---|---|
| `00_entry_me_tab.png` | 做啲嘢：「跟進計劃」「一啲社交小行動」 | 两组相同 |
| `01_entry_home_shortcuts.png` | 首页底部「行動」快捷 | 两组相同 |
| `02_landing.png` | 「小行動」页（测试没有数据库，列表为空的样子） | 两组相同 |
| `10_suggestions_A.png` | 今日嘅小邀請（AI 建议） | Hybrid |
| `10_suggestions_B.png` | 今日嘅小邀請（固定建议池） | 规则组 |
| `11_A_step_when.png` | 第 2 步「幾時」（空着按下一步，画面不变） | Hybrid |
| `12_A_step_where.png` | 第 3 步「邊度」 | Hybrid |
| `13_A_step_who.png` | 第 4 步「同邊個」+ 人名按钮 | Hybrid |
| `14_A_step_fallback.png` | 第 5 步「唔得點」 | Hybrid |
| `15_A_review.png` | 第 6 步「檢視」AI 一句话 | Hybrid |
| `16_A_saved.png` | 完成句 | Hybrid |
| `11_B_form_top.png` | 一页表单上半（「做咩」预填被截断） | 规则组 |
| `12_B_form_bottom_save_disabled.png` | 下半，「儲存計劃」灰 | 规则组 |
| `13_B_form_filled_save_enabled.png` | 四项选齐后可以储存 | 规则组 |
| `20_planner_no_seed_A.png` | 没预填时第 1 步「做咩」（入口 2–5 和 Q5 相同） | Hybrid |
| `20_planner_no_seed_B.png` | 没预填时的表单（入口 2–5 和 Q5 相同） | 规则组 |
| `30_q5_A.png`、`30_q5_B.png` | 小欣 check-in Q5「想訂個小計劃嗎？」（问题和按钮相同，前面的回应按组不同） | 各一张 |
| `40_followup.png` | 「件事點呀？」页（看计划 + 完成） | 两组相同 |
| `41_followup_saved_A.png` | 存后多一张 AI 回应 | Hybrid |
| `41_followup_saved_B.png` | 存后没有回应 | 规则组 |

改计划、删计划没有截图：现在没有这两个功能。
