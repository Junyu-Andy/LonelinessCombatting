# T48：「重要的人」经老人同意后给小欣和行动计划；入组答案写进服务器记忆（PR 草稿）

接 T47（`feat/t47-researcher-intake`，PR #100），分支 `feat/t48-contacts-and-seed`，**先合 #100 再合这个**。Junyu 10/15 定：「重要的人」要给，但要筛选、确认之后才进入。只用 emulator 和合成数据。

## 1. 结论

- 录入时每位重要的人旁边多一个勾「老人家同意：可以畀夥伴知道呢位」。没勾的只存着，夥伴永远不知道。勾了的：小欣第一次见面的记忆里有「佢身邊重要嘅人：阿女（女）」；通通的行动计划「同邊個」一步直接列出这几位，一点就填。规则组的行动计划页也列出来（那是个下拉表，没有 LLM）。
- **顺手修了一个更大的洞**：T47 报告以为入组答案靠 App 里的「首次记忆播种」给陪伴者，核对后发现 Phase B 的 Hybrid 组用的是**服务器记忆 v1**，App 那条路根本不跑。也就是说在今天之前，入组问卷的答案在 Phase B 里**一个字都没到过陪伴者**。现在研究员录入时，服务器直接把五题写成记忆条目（每位陪伴者一份），下一次聊天就在提示词里。规则组不写（没有 LLM）。
- 老人自己答精简版（开关关着时）输入的人，视为同意分享。

## 2. 改了什么

| 位置 | 改动 |
|---|---|
| `functions/researcher_intake.js` | 每位的人带 `share`；Hybrid 组（`arm: A`）录入后写 `users/{uid}/mem_facts`：目标（三位都有）、兴趣（小欣、通通）、同意分享的人（只给小欣）、唔想提起的话题（三位都有，作「唔好主動提」）。每位陪伴者各一份（`visibility: agent`、`layer: private`、`source_session_id: "intake"`）。再录一次把上一次的 intake 条目标 `superseded`，对话里抽取的条目不动 |
| `lib/features/auth/data/user_profile.dart` | `CloseContact.share`、`label` |
| `lib/features/enrollment/presentation/intake_section.dart` | 每位一个勾 |
| `lib/features/onboarding/presentation/pages/intake_short_page.dart` | 老人自答的人 `share: true` |
| `lib/core/agent_context/intake_memory_seeder.dart`、`persona_resolver.dart` | 记忆 v0 那条路（Phase A、测试包）：小欣加一句同意分享的人；intake 文档里的人仍不播种 |
| `lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart` | 「同邊個」一步上方一排快捷按钮 |
| `action_loop_arm_b_page.dart` | 下拉选项前面加同意分享的人 |

## 3. 测试

- `functions/test/researcher_intake_emulator_test.js` 6/6：`intakeFactsFor` 按陪伴者路由、只带同意分享的人；Hybrid 组录入写 9 条、再录覆盖（旧的 superseded，对话条目不动）、规则组 0 条。
- Flutter：`t47_researcher_intake_test`（勾走后台、老人自答 share）、`intake_memory_seeder_test`（分享的人只到小欣、没传就没有）、默认套 637 条通过；`flutter analyze` 0 error。

## 4. 要带回研究侧的发现

1. **Phase B 以前根本没用上入组答案**（见第 1 节）。这条要补进 T47 报告第 2 节，也是对 10/15 之前三位试跑老人的说明：她们的陪伴者没有任何入组背景。研究员用「入組資料」给她们录一次，服务器就补上。
2. **人名会进 DeepSeek**。同意分享的人以「阿女（女）」这种称呼进服务器记忆，再进提示词。`docs/privacy/strip_pii.md` 本来就不剥姓名，这次只是多了一个来源，而且是老人明确同意的。ICF 里「夥伴會記住你講過嘅人」那句是否覆盖「研究员录入的人」，请产品窗口核一眼。
3. **记忆分层开着时**（`layersEnabled`，现在关）：intake 条目是 private 层、按陪伴者各一份，所以不受「共享层」影响，三位各自看到自己那份。
4. 决策记录草稿（第 5 节）推翻的是 Sprint Plan §0 的「第三方姓名不进端点」硬规定，要编号。

## 5. 决策记录草稿（编号待分配）

- **标题**：入组时老人明确同意的「重要的人」可以进陪伴者记忆（小欣）和行动计划；入组五题由服务器写成记忆条目
- **状态**：提议中（Junyu 10/15 定「要给，确认之后再进入」）
- **影响范围**：phase_b、pilot × Hybrid 组（记忆条目）；两组（行动计划的快捷选项）
- **背景**：Sprint Plan §0 定第三方姓名不进 LLM 端点，所以入组问卷的「重要的人」一直只存不用。10/15 Junyu 定要用，但要老人同意。同时发现 Phase B 用服务器记忆，App 的播种路径不跑，入组答案从未到过陪伴者。
- **决定**：录入时每位单独勾「可以畀夥伴知道」；只有勾了的进小欣记忆和行动计划；入组五题由服务器写成每位陪伴者各一份的记忆条目，再录覆盖。
- **后果**：对研究，ICF/DMP 加一句「入组时老人同意分享的人会进陪伴者记忆」；对开发，无；对论文，个人化一节写明来源。
- **取代**：Sprint Plan §0「importantPeople / closeContacts HOLD」。
