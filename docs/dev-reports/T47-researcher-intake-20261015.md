# T47：入组问卷精简为五题，改由研究员在登记页录入（PR 草稿）

任务单 `docs/dev-tasks/dev-tasks-1015-intake.md`（10/15 第 10 条）。分支 `feat/t47-researcher-intake`，从 `main` @ f8cc93b 开出。只用 emulator 和合成数据。

## 1. 结论

- 做完了第 2 节 1–4、6 条：服务器录入函数、登记页「入組資料」区、开关 `researcherIntakeEnabled`（默认关）、老人端五题一页的备用问卷、登记页不再选配对、W0 流程文档。
- 第 2 节第 5 条（登记表 `feature-registry.md`）按约定不改，要改的三处写在第 5 节给产品窗口。
- 第 0 节四题按代码答在第 2 节。最重要的一条：**原问卷大部分字段从来没人读**，`interests` 不是来自入组问卷，`closeContacts` 从来没被写过。
- 五题文字（S16）是研究侧草案，等 Junyu 一句确认；开关默认关，确认前老人看到的还是精简版（关着时）。

## 2. 第 0 节四题的答案

**1. 每个字段被谁读（按 `main` @ f8cc93b）**

| 字段 | 读取方 | 处理 |
|---|---|---|
| `mainGoals` | `intake_memory_seeder.dart`（三位陪伴者的首次记忆一句「用戶嚟呢度，主要係…」） | 保留（第 1 题） |
| `typicalMorning / Afternoon / Evening` | 只有 seeder（小欣首次记忆「佢嘅日常大致係…」） | 不再收集；seeder 那一句删掉 |
| `avoidTopics` | seeder（只给小欣加一句「有啲話題用戶唔想提起，唔好主動講」，**不进服务器提示词**）；`users/{uid}.avoidTopics` 存着，服务器没人读 | 保留（第 4 题）。任务单说的「提示词禁区」现在并不存在，见第 5 节 |
| `inputMode`、`preferredTimes` | 写进 `users/{uid}`，没有读取方（语音按钮提示没做） | `inputMode` 保留（第 5 题）；`preferredTimes` 不再收集 |
| `importantPeople`、`reconnectPeople` | 没有读取方。seeder 明文规定 HOLD：第三方姓名不进端点 | 第 2 题保留 `importantPeople`，写到 `closeContacts`（见下） |
| `activities`、`activitiesOther`、`topics`、`topicsOther` | 没有读取方 | 第 3 题改用通通兴趣那一步的 23 项（见下）；`topics` 不再收集 |
| `lonelinessTimings`、`onMind`、`lifeChapters`、`mainGoalOther` | 没有读取方（`onMind` 明文规定永不读） | 不再收集 |
| 导出 | `blinding.js` / `process_export.js` 不读 `onboarding/intake`；`closeContacts` 在导出时被当 PII 剥掉 | 不变 |

两个任务单假设和代码不一样：
- **`profile.interests` 不是来自入组问卷**，而是老人在「介紹三個夥伴」通通那一步自己点的（`agent_onboarding_page.dart`，用 `InterestLabels` 的 23 个 id）。原问卷的 `activities`（电视、收音机…）是另一套 id，没人读。所以第 3 题改成用通通那 23 项，录入直接写 `interests`；老人在引导里点的和研究员录的是同一个字段，后写的覆盖先写的。
- **`closeContacts` 从来没被写过**（`UserProfile` 有这个字段，原问卷没写它），现在也没有读取方（小欣、行动计划都不读）。本次按任务单把第 2 题写进 `closeContacts`，先存着；要不要让小欣或行动计划用，Junyu 定。

**2. 规则组用不用 intake**：一个字段都不用。模板回应只看陪伴者和心情档（`rule_reply_pool.dart`）；配对读 `ahJanAhBakVariant`；行动计划 B 页不读 intake。`interests` 在通通页的兴趣标签两组都显示，但那本来就不是 intake 的字段。登记表可以写「两组相同：intake 只影响 Hybrid 组陪伴者的首次记忆和通通的兴趣标签，规则组不读」。

**3. 配对**：以前 `enrollParticipant` 把研究员选的配对写进 `users/{uid}.ahJanAhBakVariant`，会覆盖老人自己的选择（T37 之前就是这里让引导被跳过）。本次改为：登记不再收配对，函数读老人资料里已有的 `ahJanAhBakVariant` 记进 `enrollments.companionVariant`（没选就记空），不写 `users` 的这个字段；登记页的确认框显示「配對：阿珍（老人家自選）」或「未揀」。老人之后在引导里再选，照旧记 `ah_jan_ah_bak_changed` 事件（T37）。

**4. 旧 6 页数据并存**：新结构是旧结构的子集。`IntakeResponse` 的字段都保留（可空），读旧文档不报错；研究员录入用 merge 写，旧字段原样留着（emulator 测试核过：`typicalMorning`、`onMind` 不动，`allCompleted` 翻成 true）。不用迁移。

## 3. 做了什么

| 位置 | 改动 |
|---|---|
| `functions/researcher_intake.js`（新） | `recordIntake`：只有 `unblinded`；按 uid 写 `users/{uid}/onboarding/intake`（merge）、`users/{uid}` 的 `hasCompletedIntake / interests / closeContacts / avoidTopics / inputMode`、`intake_audit_log` 一行（谁、何时、哪个编号、各题填了几项，不含答案文字）。上限：目标 2、人 3、兴趣 3、其他 40 字、话题 200 字。没登记、测试员、自己的账号拒绝 |
| `functions/index.js` | callable `recordResearcherIntake`：电邮走 Auth，研究编号走 `research_ids` |
| `functions/randomization.js` | `enrol` / `enrolPilot` 不再要求 `companionVariant`，记老人自选，不写 `ahJanAhBakVariant` |
| `firestore.rules` | `intake_audit_log` 客户端不可读写（注释 + 明确 deny） |
| `lib/core/feature_flags/remote_feature_flags.dart` | `researcherIntakeEnabled` |
| `lib/features/consent/presentation/consent_gate.dart` | 开关开：跳过问卷；关：`IntakeShortPage` |
| `lib/features/onboarding/presentation/pages/intake_short_page.dart`（新） | 老人端五题一页（S16），写法和原页一致（intake 文档 + 资料字段 + T7 安全检测） |
| `lib/features/onboarding/presentation/pages/intake_flow_page.dart` | 删掉（1805 行的 6 页问卷） |
| `lib/features/enrollment/presentation/intake_section.dart`（新） | 登记页「入組資料」区：电邮或编号、五题、錄入、已錄入 |
| `lib/features/enrollment/presentation/enrollment_page.dart` | 去掉配对选择；确认框显示老人自选；页底加「入組資料」 |
| `lib/features/enrollment/data/enrollment_service.dart` | `companionVariant` 可空；`IntakeBackend` / `CloudIntakeBackend` / `IntakeAnswers` |
| `lib/core/agent_context/intake_memory_seeder.dart` | 去掉作息一句 |
| `lib/features/onboarding/data/interest_labels.dart` | `InterestLabels.ids` |

## 4. 测试

- `functions/test/researcher_intake_emulator_test.js`（新，4 条）：校验和上限、写入三处 + 审计、旧字段保留、再录覆盖、各种拒绝、编号查找。
- `functions/test/randomization_emulator_test.js` 20/20：配对改为记录老人自选（`pa` 选了阿珍 → 记阿珍；`pb` 没选 → 记空；输入里的 `companionVariant` 被忽略）。
- Flutter：`t47_researcher_intake_test.dart`（新，4 条）：录入区走后台、两项上限、电邮/编号分流、错误文字；开关开 → 没有问卷直接进主页；开关关 → 五题一页，完成后 `hasCompletedIntake`、`interests`、`closeContacts`、`inputMode` 写进资料。`enrollment_page_test`、`onboarding_order_test`、`intake_memory_seeder_test` 按新行为更新，全过。`flutter analyze` 0 error。
- 验收表第 3 节：1（跳过 + 录入后小欣/通通有内容：seeder 单元测试）、2（没录入时 seeder 返回 null：原有测试）、3、5、6、7 都有自动测试；4 规则组不读 intake，靠第 2 节第 2 题的代码核对；「`avoidTopics` 出现在提示词禁区」**现在不成立**，见第 5 节。

## 5. 要带回研究侧的发现

0. **（T48 补）Phase B 的 Hybrid 组用服务器记忆 v1，下面说的 App 播种（`intake_memory_seeder.dart`）只在记忆 v0 跑，Phase B 不跑。** 所以在 T48 之前，入组答案在 Phase B 里从未到过任何陪伴者。T48 让研究员录入时由服务器直接写记忆条目，见 `T48-shared-contacts-20261015.md`。

1. **`avoidTopics` 没有进提示词**。任务单和登记表都写「提示词禁区（安全）」，代码里它只给小欣的首次记忆加一句「唔好主動講」，阿珍/阿伯、通通和服务器提示词都不看。要真的做成禁区，要在 `functions` 组提示词时读 `users/{uid}.avoidTopics`，是另一个小任务，Junyu 定要不要。
2. **`closeContacts` 没有读取方**。录进去了，小欣和行动计划现在都不用。要用也是另开任务。
3. **登记表（`feature-registry.md`）三处改动**，按规矩我不改，请产品窗口改：C19 加「研究员录入入组资料」；个人化问卷条目改为五题，两组相同（规则组不读）；配对条目改为「老人在引导里自选，研究员只记录」。
4. **五题文字（S16）**等 Junyu 一句确认。老人端备用页的标题「傾偈之前，想問你五樣嘢」、开头「答唔答都得，答咗夥伴會更加了解你。」、按钮「完成」是开发窗口拟的，请产品窗口核。
5. **第 3 题的选项**用了通通兴趣那 23 项而不是原问卷的 `activities`，原因见第 2 节第 1 题。
6. **开关打开的时机**：老人的包要含本 PR（10/19 构建），服务器要部署本 PR。开关开着而研究员还没录入时，老人正常用，只是陪伴者没有首次记忆；录入后老人下次完全关闭再打开 App 才生效。
7. 现有三位 PILOT 老人已经答过 6 页，不用重录；要补第 2 题的「重要的人」可以用录入区再录一次（merge，覆盖五题，旧字段留着）。

## 6. 决策记录草稿（编号待分配）

- **标题**：入组个人化问卷精简为五题，由研究员在 W0 面访口头问并在后台录入；配对由老人自选、研究员只记录
- **状态**：提议中（负责人 10/15 第 10 条定）
- **影响范围**：phase_b、pilot × 两组（两组相同；规则组不读 intake）
- **背景**：6 页问卷老人答 10–15 分钟很吃力；答案只用于 Hybrid 组陪伴者的个人化，而且大部分字段没人读。
- **决定**：五题（目标、重要的人、兴趣、唔想提起的话题、打字定讲）；研究员录入（`recordResearcherIntake`，开关 `researcherIntakeEnabled`）；老人端只留五题一页做备用；登记不再收配对。
- **考虑过的其他方案**：只精简老人端问卷不改录入方——老人仍要在手机上答，10/15 的观察说明仍然吃力；全部删掉——Hybrid 组陪伴者第一次见面就没有任何背景，个人化效果打折。
- **后果**：对研究，登记表 C19 和个人化条目要改（第 5 节第 3 条）；对开发，`avoidTopics` 进提示词、`closeContacts` 接小欣另开任务；对论文，方法一节写「个人化资料由研究员在基线面访口头收集」。
- **取代**：无（T37 的引导顺序不变）。

## 7. 10/16 改版：一题一屏，先客观后主观

Junyu 10/16 看了五题一页的版本：五题挤在一起，可读性差；要求先问客观题，快完成时才问主观题。改法：

1. **老人端备用页**（`intake_short_page.dart`）改成一题一屏，顶上「第 N 題，共 5 題」加进度条，底下「上一題」「下一題」，最后一屏「完成」；翻页回到页顶（同 10/15 问卷的做法），输入框弹键盘时自动顶上来。
2. **顺序**改为：(1) 你打字多定係講多 → (2) 你平時鍾意做啲咩 → (3) 有冇邊幾位屋企人或者朋友想夥伴知道 → (4) 你最想呢個 app 幫到你啲乜 → (5) 有冇咩話題你唔想夥伴提起。前三题是事实（怎么用、做什么、有谁），第四题是愿望，第五题是最私人的自由一句，放最后。
3. **研究员录入页**（`intake_section.dart`）同一顺序，每题一个带编号的块，中间有分隔线；研究员照 1 到 5 读就和老人端一致。
4. 问法文字不变（S16），只加了「第 N 題，共 5 題」「上一題」「下一題」三句，待产品窗口核。存的字段、服务器函数、记忆播种都不变。
5. **删掉的题目没有回来**：作息（朝早／晏晝／夜晚）、心事、想重新連繫的人、孤独时段、人生阶段、话题、偏好时段，这些 10/15 定删，现在哪里都不问；旧数据留在三位 PILOT 的记录里不动。要加回任何一题，Junyu 一句话定，加回来是半天的事。

## 8. 10/16 问答：选择上限、怎么进提示词、研究员备注

1. **上限从哪来**：第 1 节（研究侧 10/15 定稿草案）写的「最多两项／最多 3 人／最多 3 项」，不是技术限制；服务器另有字数上限（稱呼、關係各 20 字，「其他」40 字，「唔想提起」200 字）。要放宽改一个数字。
2. **怎么进提示词**（只 Hybrid 组）：录入后服务器把答案写成固定格式的记忆句，每位夥伴各一份——目标→三位「嚟呢度主要想：…」；兴趣加「其他」→小欣、通通「平時鍾意：…」；勾了同意的人→小欣「重要嘅人：…」；唔想提起→三位「唔想主動提起：…（用戶一開始就講明，唔好主動提）」。每次聊天接在人设提示词后的 `<memory>` 块里，带「记忆使用规则」。通通另外在闲聊模式把 `profile.interests` 列表接在提示词后面（只能在老人主动闲聊时引用）。打字定讲不进提示词。
3. **自由栏照字面进固定句子**：在「唔想提起」写「老人家什麼都想說」会变成「唔想主動提起：老人家什麼都想說……」，没有意义甚至让夥伴小心翼翼。观察类的话用新加的「研究員備註」：原句变成三位夥伴的一条「研究員觀察：……」。
4. **通通一页**：`researcherIntakeEnabled` 开着时（第 2 题由研究员录），或老人刚在精简问卷答过兴趣，引导里通通一页只介绍不问；「完成」保留已有兴趣，不再互相覆盖。之前的顺序是老人引导先揀、研究员后录覆盖，老人要「完全关闭再打开 App」才看到新的——Junyu 说「我選完了通通進去沒這個 option」多半是这个原因。
