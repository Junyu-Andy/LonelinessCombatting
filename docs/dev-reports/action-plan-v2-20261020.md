# 行动计划 v2：少填、可改可删、Hybrid 计划用上小欣记忆（2026-10-20）

分支 `claude/zealous-fermat-8rgqtg-actionplan-impl`，从键盘分支 `claude/zealous-fermat-8rgqtg-keyboard`（`3125ac2`，含第 2 批 Q5 和键盘顶栏）开。依据：1020e 二.7（Junyu 定两样都在冻结前做）；现状报告 `docs/dev-reports/action-plan-current-20261020.md`（PR #129）。决策草稿 `docs/decisions/0059-action-plan-simplified.md`。没连生产 Firestore，只用模拟器和合成数据；没改热线；没碰分配序列、分配日志；`lib/core/safety/` 没改。

## 结论

1. **两样都做完了，各有一个开关，默认都关。** 关着时页面、存的字段、模型调用和以前一模一样（有测试锁住）。
2. **第 1 样（开关 `actionPlanSimplifiedEnabled`）**：两组同一条规则，只必填「做咩」和「幾時」。从建议进去，「做咩」已经填好建议原文，看得到、可以改，所以老人只要填「幾時」。「等住跟進」里的计划可以「改」（做咩、幾時）和「刪除」（先问一次）。删除是软删除：计划留在数据库，App 删掉它未发的提醒，服务器也不会再推。
3. **第 2 样（开关 `actionPlanMemoryEnabled`）**：Hybrid 组计划页「檢視」那句和「件事點呀」回应，服务器会加上小欣的记忆（讲过的人名、习惯等），提示词自称「電腦程式夥伴」。小欣到期要关心的事**不会**在这两处出现、也不会被用掉，留给小欣在对话里问。
4. **规则组整个流程仍然没有任何模型调用**，两个开关开或关都一样（测试用一个一被调用就失败的假模型）。
5. **新文字都是草稿**，集中在一个文件，Junyu 看截图定（第七节）。
6. 测试：新测试 Flutter 26 项、Functions 4 项；Flutter 全部 CI 和后端全部测试结果见第五节。

## 一、老人看到什么（开关开）

截图在 `docs/dev-reports/action-plan-v2-shots/`，360 逻辑像素宽，合成数据，假的模型回复。标「两组相同」的，测试里比对过两组逐像素相同。

**从建议进去（Hybrid 组）：3 步**

| 截图 | 画面 |
|---|---|
| `10_on_A_step1_what_prefilled.png` | 第 1 步「做咩」：建议原文已填好，可改；按「下一步」 |
| `11_on_A_step2_when.png` | 第 2 步「幾時」：顶部一张卡「你想做：…」 |
| `12_on_A_step2_when_empty_hint.png` | 空着按「下一步」：红字「寫少少就得，例如「聽朝」。」（以前没反应） |
| `13_on_A_step3_review.png` | 第 3 步「檢視」：模型写的一句；「儲存計劃」；下面「加多啲細節（可以唔填）」 |
| `14_on_A_optional_where_skip.png`、`15_on_A_optional_who.png` | 选了「加多啲細節」才出现：邊度、同邊個、唔得點，每步有「跳過」 |
| `16_on_A_saved.png` | 存好 |

**从建议进去（规则组）：一页**

| 截图 | 画面 |
|---|---|
| `20_on_B_form_top.png` | 「做咩」已填好，长句会换行；邊度、同邊個、如果唔成功标「（可以唔揀）」 |
| `21_on_B_form_bottom_hint.png` | 未选「幾時」：「儲存計劃」灰色，上面一句「寫低「做咩」、揀「幾時」，就可以儲存。」 |
| `22_on_B_when_only_save_enabled.png` | 只选了「上晝」就可以储存。选过的可选项再撳一次可以取消 |

**没有建议的入口（小行動页、小欣 Q5）**：`23_on_planner_no_seed_A.png`、`23_on_planner_no_seed_B.png`。「做咩」要自己写（必填），其余同上。

**改和删（两组相同，不用模型）**

| 截图 | 画面 |
|---|---|
| `30_on_landing_buttons.png` | 「等住跟進」每张卡下面「改」「刪除」；撳卡本身仍进「件事點呀？」 |
| `31_on_edit_page.png`、`32_on_edit_page_changed.png` | 「改計劃」页：做咩、幾時（文字框 + 上晝／下晝／晚上快捷）、「儲存」、「刪除呢個計劃」 |
| `35_on_edit_need_both.png` | 任一项空着按「儲存」：「「做咩」同「幾時」都要寫。」 |
| `33_on_delete_confirm.png` | 「刪咗呢個計劃？」按钮「唔刪」「刪除」 |
| `34_on_deleted.png` | 删了：卡片消失，底部「已經刪咗。」；改过的那张显示新文字 |
| `36_on_followup_skipped_items.png` | 「件事點呀？」页：没填的项不显示（不会出现「聽朝 ·  · 」） |

**开关关（和以前一样）**：`00_off_planner_from_suggestion_A.png`（直接到第 2 步「幾時」，共 6 步）、`00_off_planner_from_suggestion_B.png`（四组都要选）、`01_off_landing.png`（卡片没有按钮，两组相同）。

## 二、改了哪些文件

| 文件 | 改动 |
|---|---|
| `lib/core/feature_flags/remote_feature_flags.dart` | 两个开关 `actionPlanSimplifiedEnabled`、`actionPlanMemoryEnabled`（`app_config/feature_flags`，只认布尔 `true`） |
| `lib/features/action_loop/data/action_plan.dart` | 新字段（只在设了时写）；`ActionPlanSource`；`ActionPlanEdits`（改动内容的纯函数）；`update()`、`softDelete()`；`pending()` 不含已删的；`ActionPlanRepository.forApp` + `testOverride`（测试用） |
| `lib/features/action_loop/data/action_plan_copy.dart`（新） | 全部新文字（草稿） |
| `lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart` | 开关开：做咩 → 幾時 → 檢視；可选三步和「跳過」；空着的提示；顶部卡片；模型输入只送填了的项。记忆开关：`agentId: siu_yan` + 新提示词 |
| `lib/features/action_loop/presentation/pages/action_loop_arm_b_page.dart` | 开关开：只必填做咩、幾時；可选项可取消；做咩换行；提示句 |
| `lib/features/action_loop/presentation/pages/action_plan_edit_page.dart`（新） | 改计划页；`confirmAndDeletePlan`（确认后软删除） |
| `lib/features/action_loop/presentation/pages/action_loop_landing.dart` | 开关开：卡片多「改」「刪除」；关时卡片和以前同一棵 widget 树 |
| `lib/features/action_loop/presentation/pages/action_loop_followup_page.dart` | 记忆开关：`agentId: siu_yan` + 新提示词；没填的项不显示 |
| `lib/features/context/presentation/pages/siu_yan_chat_page.dart` | Q5 打开计划页时带 `source: check_in_q5`（只在开关开时存） |
| `lib/features/analytics/data/analytics_service.dart` | `logM7PlanSaved`（原来没人调用）、`logM7PlanEdited`、`logM7PlanDeleted` |
| `functions/memory.js` | `INJECT_MODULES` 加 `m7_action_loop_summary`、`m7_action_loop_followup`；新 `NO_FOLLOWUP_MODULES`：这两个和 `m6_suggestions` 不放、不用掉 follow-up |
| `functions/reminders.js` | 计划有 `deletedAt` → `skipped_plan_deleted`，不推 |
| 测试 | `test/action_plan_simplified_test.dart`（新，加进 CI 两套 Phase B）；`functions/test/memory_test.js`、`memory_emulator_test.js`、`reminders_emulator_test.js` 各加用例 |

Firestore 规则不用改（老人本来就能改自己的 `action_plans`、删自己的 `reminders`）。

## 三、数据

**`users/{uid}/action_plans/{id}` 新字段（只在开关开时写；旧计划没有）**

| 字段 | 什么时候 | 意思 |
|---|---|---|
| `planFormVersion` | 新建 | `2` = 新规则下订的；空的 `whereText`／`whoWith`／`fallback` = 老人跳过 |
| `source` | 新建 | `suggestion`（建议页）／`landing`（小行動页）／`check_in_q5`（小欣 Q5） |
| `seedAction` | 从建议新建 | 建议原文（老人改过「做咩」也看得出） |
| `original` | 第一次改时写一次 | `{action, whenText}`：最初存的版本 |
| `editCount`、`lastEditedAt` | 每次改 | 改了几次（+1）、最后一次（服务器时间） |
| `editLog` | 每次改追加一条 | `{atLocal, fields, before}`：手机时间、改了哪项、改之前的值 |
| `deletedAt`、`deletedFrom` | 删除 | 服务器时间；`landing` 或 `edit`（在哪一页按的） |

旧字段名都没改。但三处意思有变化（决策草稿「后果」一节）：改过的计划 `action`／`whenText` 是最新版本（最初的在 `original`）；规则组 `whenText` 改过后可能是自由文字（`editCount > 0`）；新规则下 `whereText` 等可以是空字串（`planFormVersion: 2`）。T2 数据字典报告是旧的快照，没改；新字段以本节为准。`action_plans` 在盲法导出里本来就整块扣下（`functions/blinding.js`），新字段跟着扣下。

**`users/{uid}/events`（只在开关开时写，不带老人原文，带组别）**：`m7_plan_saved {source, filled}`（`filled` 是填了的项：whenText／whereText／whoWith／fallback）、`m7_plan_edited {fields}`、`m7_plan_deleted {from}`。

**提醒**：改「幾時」不移动提醒（提醒本来就固定在存后 24 小时，和「幾時」无关）；改「做咩」时把未发提醒里存的 `bodyZh／bodyEn` 换成新文字（推送本身不带计划原文，S4a 不变）；删除时 App 删掉这个计划所有未发提醒，服务器见到 `deletedAt` 也不推（`skipped_plan_deleted`）。**没有写 `scheduledFor`**（否则首页隐藏的横幅会出现）。

## 四、第 2 样：计划接上小欣的记忆

- 「计划生成接上小欣记忆」在代码里指：Hybrid 组计划页两次模型调用（`m7_action_loop_summary`「檢視」那句、`m7_action_loop_followup`「件事點呀」回应）以前不带陪伴者编号，服务器不加任何记忆。现在开关开时 App 带 `agentId: siu_yan`，服务器 `memory.js` 把这两个模块列进 `INJECT_MODULES`，加上小欣的记忆块（和其他小欣对话同一套选择、分层、长度上限、`mem_injections` 记录）。只在中文界面。
- **follow-up 不在这里用掉**：计划页不是对话。和 1020c 对 `m6_suggestions` 一样，这两个模块不放到期 follow-up，也不把它标为「已问」（emulator 测试：两次调用后 follow-up 仍未问，小欣签到时仍然会问）。
- `memory.js` 里 1020c（第 1 批分支 `claude/zealous-fermat-8rgqtg`）对 `m6_suggestions` 的那几行，这里**一字不差**照抄，m7 的排除写在隔两行的另一处（`NO_FOLLOWUP_MODULES`），所以两个分支谁先合都不冲突（用 `git merge-tree` 试过，见第八节）。
- 提示词仍写在 App 里（两段新版，开关开时用；旧版原样留给开关关）：自称「小欣（一個電腦程式夥伴）」，可用记忆里讲过的人名和习惯，不作没讲过的人和事，不提唔想提起的话题，不用「AI／模型／機械人」，没填的项不写。规则组没有这两次调用。
- 开关和第 1 样分开：两样可以分开开、分开关。服务器那边不看开关（App 不带 `agentId` 就不会注入），所以 Functions 先部署也不会改变任何人的体验。

## 五、测试

| 测试 | 结果 |
|---|---|
| `flutter test test/action_plan_simplified_test.dart`（默认构建、`PHASE_B=true`、`PHASE_B=true FORCE_ARM=B` 三套） | 三套都通过 |
| `tool/ci_flutter_tests.sh`（六套：默认构建、Phase B 分组、Phase B 规则组页面、记忆 v1、规则模板两套） | 六套全部通过（本机，Flutter 3.35.3）；新测试加进两套 Phase B |
| `tool/ci_backend_tests.sh`（同样步骤，私有端口配置 `firebase.ap.json`／`firebase.ap.dp.json`，不入库） | 全部通过：Functions 单元测试 22 个文件；规则 196 项；emulator 测试 30 个文件；隐私脚本 6 + 4 + 4 项 |
| `functions` ESLint（改过的 5 个文件） | 0 问题 |
| `flutter analyze`（改过的文件） | 没有新增；5 条「未使用 import」和 3 条 info 是改动前就有的 |

新测试覆盖（Flutter 26 项，Phase B 构建；Functions 4 项）：开关只认 `true`；开关关时两组计划页、列表、存的字段（只有原来 10 个键）、模型调用（不带 `agentId`、旧提示词）都和以前一样；开关开时规则组只必填做咩和幾时、可选项可取消、新字段和事件、规则组零模型调用；Hybrid 3 步、空着有提示、可选三步可跳过、模型输入只送填了的项；没有建议时做咩必填；改计划（两组，零模型调用）、列表即时更新、事件；删除先确认、「唔刪」不删、删除后卡片消失、事件；改计划页两项都要写、没改就不写；跟进页不显示空项；记忆开关开时两次调用带 `siu_yan` 和新提示词，关时不带；规则组「件事點呀」开关开也零模型调用。Functions：`m7_*` 两个模块拿到小欣的事实、不放也不用掉 follow-up、没 `agentId` 不注入、规则组不注入；软删除的计划不推、同帐号其他计划照推、之后不再重试。

## 六、真机测试步骤

先部署 Functions（Actions →「Deploy Firebase」），再装含本分支的测试包。开关在控制台 `app_config/feature_flags` 加布尔字段；改了开关要**完全关闭 App 再打开**。用测试员帐号（「切換組別」可以两组都试）。

1. **开关全关**：做啲嘢 → 一啲社交小行動 → 計劃做。Hybrid 组应直接到「幾時」、共 6 步；规则组 4 组都要选。和 10/19 版本一样。
2. 开 `actionPlanSimplifiedEnabled = true`，重开 App。
3. **Hybrid 组从建议**：計劃做 → 第 1 步看到建议原文 → 下一步 → 「幾時」空着按下一步，看到红字提示 → 填「聽朝」→ 檢視一句 → 儲存。控制台 `users/{uid}/action_plans` 新文档：`planFormVersion: 2`、`source: suggestion`、`seedAction`、`whereText` 等为空；`events` 有 `m7_plan_saved`。
4. 再订一个，在「檢視」撳「加多啲細節」，邊度跳過、同邊個填、唔得點跳過，回到檢視再储存。
5. **规则组从建议**：只选「幾時」就能储存；选了「屋企」再撳一次会取消。
6. **小欣 Q5**（`checkInChatV2Enabled` 开着时）：Q5 撳「好呀」→ 计划页「做咩」要自己写 → 储存后 `source: check_in_q5`。
7. **改**：做啲嘢 → 跟進計劃 → 卡片「改」→ 改做咩、撳「晚上」→ 儲存 → 列表即时显示新文字。控制台：`editCount: 1`、`original`、`editLog`、`lastEditedAt`；该计划的 `reminders` 文档 `bodyZh` 是新文字，`fireAt` 没变。
8. **删**：卡片「刪除」→ 先撳「唔刪」（没变）→ 再撳「刪除」→「已經刪咗。」，卡片消失。控制台：计划还在，多了 `deletedAt`、`deletedFrom: landing`；该计划未发的 `reminders` 文档没有了。在「改計劃」页底部删除时 `deletedFrom: edit`。
9. 开 `actionPlanMemoryEnabled = true`，重开 App。用一个已有小欣记忆的 Hybrid 测试员（之前和小欣聊过名字、家人）订计划：「檢視」那句可能提到讲过的人。控制台 `mem_injections` 有 `module_id: m7_action_loop_summary`；`mem_followups` 里到期的那条状态**没有**变成 `asked`；之后进小欣聊天，小欣仍会问那件事。「件事點呀」存后同样（`m7_action_loop_followup`）。
10. 规则组帐号开着两个开关重做 3–8：服务器 `llm_calls` 和 `llm_denied_log` 都不应该有这个帐号的新行。

## 七、要 Junyu 定的事

1. **全部新文字**（`lib/features/action_loop/data/action_plan_copy.dart`，看截图改）：「（可以唔揀）」「（可以唔填）」「寫低「做咩」、揀「幾時」，就可以儲存。」「寫少少就得，例如「聽朝」。」「你想做：…」「加多啲細節（可以唔填）」「跳過」「改」「刪除」「改計劃」「做咩」「幾時」「儲存」「刪除呢個計劃」「「做咩」同「幾時」都要寫。」「刪咗呢個計劃？」「唔刪」「已經刪咗。」。
2. **两个开关**开不开、哪天开（第一位 RCT- 登记前定好，之后到 Phase B 结束不改）。开那天要在 STUDY_CHANGELOG 补一行生效日期。
3. **Hybrid 组从建议进去先看到「做咩」那一步**（多按一次「下一步」，但建议看得到、可以改）。另一个做法是像以前一样跳过这一步、只在顶部卡片显示——那样就不能改。我选了前者。
4. **改计划页的「幾時」是文字框加三个快捷按钮**，两组一样。规则组改过后 `whenText` 可能不再是三个固定值之一（数据里用 `editCount` 区分）。如果要规则组只能三选一，两组就不一样了。
5. **改「幾時」不移动提醒**（提醒固定在存后 24 小时）。要提醒跟着时间走，要把「幾時」改成日期钟点，留到 Phase B 之后。
6. **记忆部分两段新提示词**（App 内，`action_loop_arm_a_page.dart` 和 `action_loop_followup_page.dart` 里的 `…Memory`）措辞。
7. 决策编号（草稿 `docs/decisions/0059-action-plan-simplified.md`）。
8. 删除的计划只在数据库里，App 里没有「已删除」列表。要不要给研究员看（例如运营看板）另议。

## 八、合并注意

- 本分支从键盘分支开，含第 2 批和键盘顶栏。PR #129 仍是现状报告，本 PR 是实现。
- `functions/memory.js`：和第 1 批分支同一段代码。m6 那几行和第 1 批一字不差，m7 的改动隔开两行；用 `git merge-tree` 试合第 1 批分支（`origin/claude/zealous-fermat-8rgqtg` `048e2a0`）和 `origin/main`，都没有冲突；合并后的 `memory.js` 同时有 m6 那几行和 `NO_FOLLOWUP_MODULES`。`functions/test/memory_emulator_test.js` 新用例加在文件末尾，避开第 1 批加用例的位置。
- `tool/check_prelaunch_values.js` 没加这两个开关（第 1 批在改同一个文件）；上线核对时手动看这两个字段。
- 四份 union 文档各只加了自己的一行／一段。
- 合并后要部署 Functions（`memory.js`、`reminders.js`）；App 要重新打包。开关关着时谁都看不到变化。
