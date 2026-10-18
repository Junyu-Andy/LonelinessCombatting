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

1. **上限从哪来**：第 1 节（研究侧 10/15 定稿草案）写的「最多两项／最多 3 人／最多 3 项」，不是技术限制。**Junyu 10/16 定：全部不限**。现在目标、兴趣随便揀，重要的人先显示三行、按「加多一位」加行；服务器只留技术上限（目标 6 项即全部、兴趣 23 项即全部、人 20 位），字数上限不变（稱呼、關係各 20 字，「其他」40 字，「唔想提起」和研究员备注各 200 字）。
2. **怎么进提示词**（只 Hybrid 组）：录入后服务器把答案写成固定格式的记忆句，每位夥伴各一份——目标→三位「嚟呢度主要想：…」；兴趣加「其他」→小欣、通通「平時鍾意：…」；勾了同意的人→小欣「重要嘅人：…」；唔想提起→三位「唔想主動提起：…（用戶一開始就講明，唔好主動提）」。每次聊天接在人设提示词后的 `<memory>` 块里，带「记忆使用规则」。通通另外在闲聊模式把 `profile.interests` 列表接在提示词后面（只能在老人主动闲聊时引用）。打字定讲不进提示词。
3. **自由栏照字面进固定句子**：在「唔想提起」写「老人家什麼都想說」会变成「唔想主動提起：老人家什麼都想說……」，没有意义甚至让夥伴小心翼翼。观察类的话用新加的「研究員備註」：原句变成三位夥伴的一条「研究員觀察：……」。
4. **通通一页**：`researcherIntakeEnabled` 开着时（第 2 题由研究员录），或老人刚在精简问卷答过兴趣，引导里通通一页只介绍不问；「完成」保留已有兴趣，不再互相覆盖。之前的顺序是老人引导先揀、研究员后录覆盖，老人要「完全关闭再打开 App」才看到新的——Junyu 说「我選完了通通進去沒這個 option」多半是这个原因。

## 9. 10/16 任务单修订版：做了什么，第 0 节第 5、6 题的答案

研究侧 10/16 把任务单改成「字段全部保留、不限选项数；甲部研究员口头问并录入，乙部重要嘅人由老人自填；新加四题」。按此重做，第 1–8 节里和它冲突的描述以本节为准。

1. **甲部（研究员录入页，14 块）**：目标（加其他）、幾時孤單、作息三格、心事、鍾意做乜（通通那 23 项加其他）加鍾意傾乜（原 topics 10 项加其他）、人生階段、唔想提起、打字定講、幾時方便；C 部四题：以前做邊行、喺邊度長大、寵物、直接定溫和；最后研究员备注。全部可空，多选不限。服务器只留技术上限（列表最多全选，人 20 位，字数 40／120／200／300）。
2. **乙部（老人 App 一页，S19）**：重要嘅人、想重新聯絡嘅人，先显示三行、一行，按钮加行，不限人数。写 intake 文档（merge，`completedParts` 加 2）、profile.closeContacts（share=true）和新标记 `intakePeopleDone`。开关开着时老人只见这一页；关着时仍是五题一屏（含重要嘅人）。
3. **记忆（只 Hybrid 组）**从合并后的整份 intake 文档生成，所以谁先录都一样：目标、唔想提起、职业、家乡、语气偏好、研究员备注→三位；幾時孤單、作息、心事（`sensitivity: sensitive`、`feeling`，只有老人自己提起才用）、重要嘅人（勾了同意的）、想重新聯絡嘅人→小欣；兴趣、话题、宠物→小欣和通通；人生阶段→阿珍／阿伯；打字定讲、幾時方便不进记忆。老人若在研究员录入**之后**才填乙部，研究员再按一次「錄入」即可刷新（服务器从合并文档重算）。
4. **语气（第 2 节第 7 条）**先弱版：写成记忆一条「鍾意人點樣講嘢：直接啲／溫和啲」（「冇所謂」不写）。提示词槽位版的三份草稿已交 Junyu（`companion-prompts-tone-slot-20261016.md`），PI 审后切版本号。
5. **第 0 节第 5 题（生效时间）**：研究员录入后——夥伴记忆：下一次聊天就带上（服务器每轮读）；通通的兴趣清单和开场白、行动计划的「同邊個」快捷按钮、小欣人设里的重要嘅人：老人**完全关闭再打开 App**后生效（App 启动时读一次资料）；唔想提起：目前是记忆一条，下一次聊天生效。建议 B20 第 7 节写一句：「研究員錄入後，請老人家完全關閉 App 再打開一次。」
6. **第 0 节第 6 题（内地／海外网络）**：内地无 VPN——登录（Firebase Auth）、资料（Firestore）、聊天（Cloud Functions，香港节点）、推送（FCM 走 Google 服务）**全部不通**，等于不能用；DeepSeek 虽在内地可达，但我们是经 Functions 调用，一样不通；语音输入开关关着，不涉及。海外（日本等）全部正常，推送也正常。所以 W0 值得问一句「呢 8 個星期會唔會離開香港超過幾日？」，去内地的那几天算缺勤，不是故障；长期在内地的老人不适合入组。
7. **第 2 节第 5 条登记表**改动（照旧由产品窗口改）：C19 加研究员录入；个人化问卷条目改为「甲部研究员口头问并录入，乙部老人自填，字段不删，选项不限数量，两组相同（规则组不读）」；配对条目改为「老人在引导里自选，研究员只记录」；新加「研究员备注」一条（进 Hybrid 组夥伴记忆，老人看不到）。

## 10. 10/18 §A 收尾（T49a，同一分支 `feat/t47-intake-v2`）

**结论**：按 `dev-tasks-1018.md` §A 收尾。人数上限改成每组 10 位；Hybrid 组的入组记忆按 §A3 表重新分类，「唔想提起」和「直接定溫和」不再写成记忆；想重新聯絡嘅人接进行动计划快捷按钮（两组）；旧 6 页数据再录一次不报错。开关仍是 `researcherIntakeEnabled`，没有加新开关。

**1. 改了什么**

- **人数上限 10**：老人乙部页两组各最多 10 行，到 10 行「加一位」按钮消失；服务器 `MAX_PEOPLE` 20 → 10（第 11 位报 `too_many_people`）；研究员看到的错误字改「重要嘅人最多錄 10 位。」。开关关着时的五题页（`intake_short_page.dart`）没有改，仍不限（任务单没提，见下面第 6 条待定）。
- **记忆路由（只改服务器 `intakeFactsFor`）**：
  - 「通常覺得孤單嘅時候」类目 routine → **feeling**（私有）。
  - 「想傾嘅人生階段」类目 preference → **story**（私有）。
  - 删掉「唔想主動提起」：唔想提起改靠 App 提示词末尾那行「⛔ 用戶要求唔好提起呢啲話題」。
  - 删掉「鍾意人點樣講嘢」：`users/{uid}.encouragementStyle` 照写，等 Prompt 2 的语气槽位读。
  - 其余照旧（目标、作息、心事、兴趣、话题、重要嘅人、想重新聯絡嘅人、职业、家乡、宠物、研究员备注）。
  - 每条的 `layer` 和 `visibility` 改由 `memory.layerFor` / `memory.visibilityFor` 算，和聊天抽出来的一样（原来一律 private / agent）。`layersEnabled` 关着时 layer 不起作用；开了以后 family、living、routine、hobby、preference 共享，feeling、story 和敏感的私有。
  - **配套（任务单没写，我加的）**：入组每位陪伴者各写一份。visibility 改了以后，`以前做邊行`、`喺邊度長大`（living）和 `寵物`（family）在现在的默认策略 C 下会被其他陪伴者也看到，同一句会在记忆块里出现两三次；`layersEnabled` 开了以后目标、兴趣也会重复。所以 `memory.js` `selectForInjection` 加了一步：**入组来源**（`source_session_id: "intake"`）的同一类目、同一标题、同一内容只留一条，优先自己那份。聊天抽出来的不动。
- **想重新聯絡嘅人接行动计划**：profile 新字段 `reconnectContacts`（结构同 `closeContacts`，share 一律 true）。乙部页保存时一起写。行动计划「同邊個」一步的按钮改读 `profile.planContacts`：先 `closeContacts`（勾了同意的），再 `reconnectContacts`，同名只出一个。两组都改，规则组仍只是列表。导出：旧版盲法导出 `blindRow` 和 `tool/check_blinded_export.js` 都把 `reconnectContacts` 当个人信息去掉（里面是人名）。
- **`completedParts` 修正（我加的）**：研究员录入原来把 `completedParts` 直接写成 `[1,3,4,5,6]`，会抹掉老人乙部的 2，也会把旧 6 页的 `[1..6]` 改短。改为在原有的上面加（`arrayUnion`）。
- **W0 SOP**：`docs/release/w0-install-script.md` 第 5、6 步后面加了定稿一句，第 5 步注明各最多 10 位。

**2. §A4 配对「第一次选择」现在怎么拿**

- 登记那一刻老人资料里的 `ahJanAhBakVariant` 写进 `enrollments/{uid}.companionVariant`（`functions/randomization.js` `elderVariant`），客户端不能改。之后老人再改：App 写 `events` 一行 `ah_jan_ah_bak_changed`（`from`、`to`、`where`）；服务器开关 `pairingChangeServerLogEnabled` 开着时还会写 `pairing_change_log`（含 `registeredVariant`）。
- **边界**：老人登记前就改过（引导里先选阿珍，登记前在夥伴资料页改成阿伯），`companionVariant` 记的是阿伯，不是第一次的选择。第一次选择要从最早一条 `ah_jan_ah_bak_changed` 的 `from` 取。另外：服务器开关当时开着的话，`pairing_change_log` 也有（第一次从空到阿珍那一行，`registeredVariant` 为空）；开关默认关，所以一般只有 App 事件。App 事件只在“已经有配对再改”时写，从空到第一次选择不写。
- 代码没改。分析时要用哪个值，见第 6 条待定。

**3. §A5 规则组用到哪些字段**（读代码，两组同一个 App）

| 字段 | 规则组 | Hybrid 组 |
|---|---|---|
| `interests`（研究员录的鍾意做乜） | **读**：通通页开头的兴趣按钮两组都有（`tung_tung_page.dart`，一次两个、換一換），按了只是把「我想傾下 X」填进输入框，回应仍是模板。规则组开场白是固定池，不看兴趣 | 兴趣按钮 + 通通提示词 + 开场白 + 记忆 |
| `closeContacts`、`reconnectContacts` | **读**：行动计划 B 页「同邊個」的选项（只是列表） | 行动计划 A 页快捷按钮；小欣记忆（服务器写） |
| `avoidTopics` | 不读 | 小欣签到、通通、阿珍／阿伯自由对话和开场白的提示词「⛔」一行（App） |
| `inputMode` | 不读 | **也不读**：§A3 写「语音按钮提示（现有）」，但代码里没有任何地方读 `profile.inputMode`，只存着 |
| `encouragementStyle` | 不读 | 现在没人读（等 Prompt 2 语气槽位） |
| `preferredTimes` | 不读 | 不读（只记录） |
| 其余（目标、孤單时段、作息、心事、话题、人生阶段、职业、家乡、宠物、研究员备注、intake 文档里的人） | 不读 | 只经服务器 `mem_facts` |
| `hasCompletedIntake`、`intakePeopleDone` | 两组一样决定显示哪一页（`ConsentGate`） | 同左 |

emulator 测试保留「规则组录入后 `mem_facts` 为 0」，并加了「intake 文档照写」。服务器的规则组防线没有动。

**4. §A6 旧数据**

emulator 新用例：三位 PILOT 式旧 6 页文档（作息、心事、人生阶段、旧结构的人——`extra` 是联系频率、没有 `share`——`completedParts` 1–6、`itemTimestamps`），研究员再录一次后：读取不报错；新字段（职业、宠物、语气、备注）为空；旧的人、`allCompleted`、`itemTimestamps`、`createdAt` 原样；`completedParts` 仍是 1–6；`factsInputFromDoc` 直接吃旧文档。App 端 `IntakeResponse.fromFirestore` 读同样的合并文档也不报错（Flutter 测试）。

注意两点：①研究员再录会把甲部所有字段按新录的覆盖（没录的变空），旧的作息、心事、人生阶段不会留下来——这是 merge 的本来行为，第 9 节已是如此。②旧 6 页的人没有 `share`，所以不会进小欣记忆和行动计划按钮；开关打开后这三位老人 `intakePeopleDone` 是 false，会看到一次乙部页，重新填就有。

**5. 测试**（结果见 PR #111 评论）

- `firebase emulators:exec --only firestore --project loneliness-pilot-dev "cd functions && node test/researcher_intake_emulator_test.js"`：7 条。
- `cd functions && node test/memory_test.js`：新加「入组每位一份只显示一次」。
- `flutter test test/t47_researcher_intake_test.dart test/onboarding_order_test.dart test/enrollment_page_test.dart test/action_plan_test.dart test/safety_check_test.dart`：新加 10 行上限、`reconnectContacts` 往返、行动计划两页、旧文档读取。
- `flutter analyze` 0 error；ESLint 新改的文件干净。

**6. 要 Junyu 定的**

1. 分析用的配对：`enrollments.companionVariant`（登记那一刻）还是“第一次选择”（登记前改过的要从 App 事件取）。要服务器也留第一次选择，就在 W0 前把 `pairingChangeServerLogEnabled` 打开。
2. `inputMode` 没有读取方。要做语音按钮提示，还是只记录。
3. 规则组通通页显示研究员录入的兴趣按钮（两组相同的界面）。确认可以接受，还是规则组不显示。
4. 开关关着时的五题页要不要也限 10 位。
5. 三位 PILOT 老人开关打开后会看到一次乙部页：照常让他们填，还是控制台把 `intakePeopleDone` 设 true 跳过（跳过的话旧的人不进小欣记忆）。
6. Prompt 2 合并之前，「直接定溫和」没有任何陪伴者用到，阿珍／阿伯回忆页也还没有「⛔」一行（本 PR 去掉了原来写进记忆的那条）。要不要等 Prompt 2 一起部署。
7. §A3 路由改动按 CLAUDE.md 要有决策记录，编号待分配（第 6 节的草稿可以并进去）。
