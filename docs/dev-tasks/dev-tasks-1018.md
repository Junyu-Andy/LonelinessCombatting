# dev-tasks-1018：入组问卷 T47 后续、提示词语气槽位、S1a 日志标签、记忆机制核对

来源：claude/decisions-log.md 10/16 第 3、4、5 条，10/18 第 1、2 条；10/18 晚按 PR #113 记忆机制核对报告（docs/dev-reports/memory-mechanism-20261018.md）修订，改动处标【1018晚】。取代 claude/开发窗口交接-1015-intake.md 第 1、2 节里与本文件不一致的内容（第 0 节六个问题仍要答）。放进仓库 docs/dev-tasks/，编号由开发窗口分配（接 T48 之后）。（开发窗口 10/18 编号 **T49**：A＝T49a 入组后续、B＝T49b 提示词、C＝T49c S1a 日志、E＝T49e 两层开关和修 bug；D 已是 PR #113。）

共同规则：(1) 不推 main，只开 PR 草稿；(2) 不碰生产数据，只用 emulator 和合成数据；(3) 新行为放在开关后；(4) 老人看得到的文字只写草稿；(5) 不改热线号码。

排期原则：10/19 第一位 PB 登记后干预冻结。本文件的 A、B 两项改 Hybrid 组的干预输入，冻结后合并要记偏离日志（STUDY_CHANGELOG 写生效日和受影响的 cohort），不因此推迟上线。C、D 不改干预。

## A. 入组问卷 T47 后续（10/16 第 3、4 条，10/18 第 2 条 (2)）

T47 按 10/15 第 12 条做了五题版（研究员登记页录入、开关 `researcherIntakeEnabled` 默认关、老人端 `IntakeShortPage`、登记页不再选配对）。Junyu 10/16 改定：字段全部保留、不删、多选不限数量。按下面改，开关名沿用 `researcherIntakeEnabled`。

1. 研究员录入页（登记页「入組資料」区）改为全部字段：`mainGoals`（加 `mainGoalOther`）、`lonelinessTimings`、`typicalMorning` / `typicalAfternoon` / `typicalEvening`、`onMind`、`activities` 和 `topics`（后台一屏两组选项，研究员按老人一句话的回答勾）、`lifeChapters`、`avoidTopics`、`inputMode`、`preferredTimes`；新加 `formerOccupation`（文本）、`hometown`（文本）、`petName`（文本，可空）、`encouragementStyle`（直接／溫和／冇所謂）。多选不限数量，全部可空。提交写 `users/{uid}/intake`（同一 `IntakeResponse` 结构，新字段加进模型），`completedParts` 标研究员录入部分，并写 `interests`、`avoidTopics`，记审计日志（谁、何时、哪个研究编号）。只有 `unblinded` 能调用，走 callable。
2. 老人端只剩两页：「想夥伴知道嘅屋企人或者朋友」（`importantPeople` → `closeContacts`，稱呼和關係）和「想重新聯絡嘅人」（`reconnectPeople`）。上限各 10 人（10/18 第 2 条 (2)）。研究员在旁协助，不代填。两页填完 `allCompleted = true`；研究员还没录入时老人照常进主页，陪伴者按“没有 A 部分”处理。
3. 接上读取方（10/18 第 2 条 (2)）。T47 报告确认多数字段从来没人读、`closeContacts` 从来没被写过。【1018晚】按 #113 报告，App 里的 `intake_memory_seeder.dart` 在 Hybrid 组根本不跑，首次记忆靠研究员录入时服务器写 `mem_facts`；所以下表全部在服务器端录入函数里接，不改 App seeder。“层”一栏在 `meta/memory_config.layersEnabled` 关着时不生效（见 E1），先按类目写，开关开了自然分层：

| 字段 | 写给谁 | 层 |
|---|---|---|
| `mainGoals` | 三位 | 共享 |
| `lonelinessTimings` | 小欣 | 私有 |
| `typical*` | 小欣，共享层作息 | 共享 |
| `onMind` | 小欣 | 私有 |
| `activities`、`topics` | 通通兴趣标签（现有） | 共享 |
| `lifeChapters` | 阿珍／阿伯 | 私有 |
| `avoidTopics` | 提示词禁区（现有） | 不进记忆 |
| `inputMode` | 语音按钮提示（现有） | 不进记忆 |
| `preferredTimes` | 只记录，不读 | 不进记忆 |
| `closeContacts` | 小欣、行动计划（T48 已接） | 共享 |
| `reconnectPeople` | 小欣、行动计划 | 共享 |
| `formerOccupation`、`hometown` | 阿珍／阿伯回忆开题，三位可见 | 共享 |
| `petName` | 通通、小欣 | 共享 |
| `encouragementStyle` | 提示词语气槽位，见 B | 不进记忆 |

4. 配对：登记页不选配对，只读显示老人在引导里第一次选的 `ahJanAhBakVariant`；老人没选时显示「未揀」。分析变量以第一次选择为准（10/18 第 2 条 (3)），改动记日志；登记表配对条目照改。
5. 规则组：录入照做（两组相同），模板回应不读这些字段（1015-intake 第 0 节第 2 题要答清楚哪些字段规则组用到，比如 `closeContacts` 进行动计划）。
6. 旧数据：三位 PILOT 的旧 6 页数据读取不报错；新字段缺省为空。
7. 登记表：C19 改为“A 部分研究员口头问并录入（14 个字段），B 部分老人自填（两页，各至多 10 人），字段不删，选项不限数量，两组相同”；配对条目改为“老人在引导里自选，研究员只记录”。
8. W0 SOP：【1018晚】#113 已答：研究员录入后，老人下一条消息就带上，不用重开 App；通通的兴趣按钮和行动计划的人名按钮要完全关闭 App 再打开才更新。产品窗口写进 B20 第 7 节、claude/PB-W0当天流程-1015.md 和 docs/release/w0-install-script.md。

验收（emulator）：开关开，新老人只见两页，各填 10 人能保存；研究员录入全部字段后，Hybrid 组老人下次打开，小欣首次记忆含目标、作息、孤单时段、心事和重要的人，通通含活动话题和宠物名，阿珍／阿伯含人生阶段、以前职业和家乡，`avoidTopics` 在提示词禁区；规则组老人行为与之前一致；`blinded` 和参与者账号调用录入被拒；旧 PILOT 账号不报错；登记页配对只读。

## B. 三位陪伴者提示词新版与语气槽位（10/16 第 5 条）

开发的草稿已由产品窗口审过（审阅文档 https://claude.ai/code/artifact/cfa656af-1a62-42f5-b6b2-0849f870f208 的主 tab，批注已答），按下面定稿进仓库，文件按 CLAUDE.md 规则新开版本号：siu_yan.v2、ah_jan_ah_bak.v2、tung_tung.v3。

1. 语气槽位：`resolvePrompt` 读 `intake.encouragementStyle`，与 `avoidTopics` 同一机制插入 §2.7。三段文字用短版：
   - 直接：「呢位用戶鍾意人直接講。重點放第一句，少鋪墊。其他規矩照舊，唔好提起呢個設定。」
   - 温和：「呢位用戶鍾意人溫和啲講。句子短啲、慢啲，留餘地。其他規矩照舊，唔好提起呢個設定。」
   - 默认（冇所謂或未录入）：照开发原文。
   不写“入組時揀咗”。规则组不读这个字段。
2. 身份声明：「AI 機械人」改「電腦程式夥伴」；被问起时老实说是电脑程式、不是真人；不用 AI、模型、機械人等字；不说自己是哪一版（参与者盲法）。
3. 删搜资料旧句：通通活动范围和模式 B 标题去掉“搵資料／搜尋”；小欣规矩 8 改为「過去同通通傾下」。
4. PR 里 Junyu 看最终文本再合。STUDY_CHANGELOG 如实写：没录入鼓励方式者行为不变（只有 2、3 的文字变）；影响 Hybrid 组全部 cohort；生效日为部署日。
5. 登记表组间差异加“语气按入组偏好调整，只在 Hybrid 组”。B07 §5.2 一句由产品窗口改。
6. 三位 PILOT 老人 W4 时补问鼓励方式并录入（研究侧记在 B20）。
7. 【1018晚】同一 PR 顺带两件：(a) 三份提示词末尾的 `rolling_summary`、`named_entities` 槽位服务器从不填（#113 第 7 条），删掉这两段死文字，不改行为；(b) 回忆页是唯一没加「⛔ 用戶要求唔好提起呢啲話題」一行的页面（#113 订正），补上，与其他三页一致。两件都写进 STUDY_CHANGELOG。

## C. S1a 触发打日志标签（10/18 第 1、2 条）

搜一搜维持关闭，不做任何搜索或资讯工具。只加一项记录：老人问到要上网查的事、系统给出固定回复 S1a 时，在会话日志记一个事件（研究编号、陪伴者、会话号、时间），两组都记，不含老人原话。运营看板不用显示，导出时按组统计次数即可。不改干预内容，不改 S1a 文字。顺带答一个待核：Hybrid 组遇到这类问题，S1a 是逐字输出还是由 LLM 改述（看 prompt 和代码）。约 0.5 人日，不卡上线。

## D. 记忆机制核对报告（不改代码）

【1018晚】已完成：PR #113，docs/dev-reports/memory-mechanism-20261018.md。下面原文保留作记录。按审阅文档「记忆机制说明（10/16）」tab 第 5 节的 prompt 写 docs/dev-reports/memory-mechanism-20261018.md，八节加“要 Junyu 定的事”。重点答五件事：抽取提示词现在是 v2 还是 v3、分层标签是否已实现并按陪伴者过滤；rolling_summary 上限和压缩规则；「唔好記住」怎样识别、漏判时的行为；会话非正常结束时是否写入；删除是否两层同删、删后是否重算摘要。发现代码与 10/9 第 15 条、10/14 第 6 条不一致的，列出来给工时，不开工。

## E. 【1018晚】#113 报告带出的事（按 Junyu 10/18 晚的决定执行，未定的先不动）

1. 两层记忆开关 `meta/memory_config.layersEnabled`：Junyu 10/18 晚定“打开”（10/18 第 3 条）。10/19 第一位 PB 登记前生效，Phase B 全程开着不再动。分工和步骤：
   (a) 开发窗口今晚在 emulator 跑一遍，`layersEnabled: true`、`policy: "C"`、`phaseBArmA: true`、抽取提示词仍是 v2。合成 Hybrid 用户做六步：① 和小欣聊 3 轮，提到家人名字和一件健康事，结束会话，看 `mem_facts`：家人条 layer 为 shared，健康条 layer 为 private、sourceAgent 为小欣；② 开通通会话，看发给 DeepSeek 的提示词：含家人条，不含健康条；③ 开阿珍／阿伯会话，同 ②；④ 在小欣会话说「唔好記住」再讲一件新事，结束，看两层都没新条目；⑤ 设定页删一条 shared 事实，看三位名下都没了；⑥ 看会话日志有没有分开记共享层和私有层的调用条数（S6 要用）。规则组用户再跑 ①，确认没有任何写入。六步结果写进 docs/dev-reports/，每步一行“过／不过”。
   (b) 六步全过：开发窗口把结果发给 Junyu，Junyu 10/19 早上在控制台把 `meta/memory_config.layersEnabled` 设为 boolean true（检查清单第 9 项），再开登记门。STUDY_CHANGELOG 记一行：两层记忆 10/19 起对全部 Hybrid 组启用，PILOT-01、02 从该日起也是两层，之前为策略 C。
   (c) 任何一步不过：不开，Junyu 照旧登记，开关留 false，当天告诉产品窗口，由产品窗口改 B07 §5.2、B08、B23 的两层写法为策略 C（这是 10/18 对话里的方案 (a)），修订包若已交则进下一次修订。不要在登记后再开。
   (d) 开了之后：登记表 C05 的分层、按陪伴者过滤、分层剂量三件事改为“已实现并启用（10/19）”；docs/dev/architecture.md 同步；研究侧 B07 §5.2、B08、B23 的两层写法不用改。A3 表的“层”一栏从此生效。
2. 抽取提示词 v3：Phase B 维持 v2，不切（v2 由服务器按类目定层，开关开关都能用）。v3 留给 Phase B 之后。
3. 记忆交接时机不一致（小欣签到页在“切换陪伴者”“30 分钟超时”不叫服务器；回忆页四种结束都不叫；只靠服务器 30 分钟扫描，最坏晚 45 分钟）：按 bug 修，让四页四种结束都叫服务器整理。10/19 登记后合并要记偏离日志（修 bug，不改干预内容）。排 10/26。
4. 删除记忆时 `mem_extractions.raw_output` 仍留模型原文：加一步，删一条事实时把对应抽取记录的 `raw_output` 一并清空或改为遮蔽，审计字段（时间、条数、版本）保留。研究侧 B09 写明。排 10/26。
5. 「唔好記住」识别是规则加关键词，四句易混句放过：不改代码。研究侧在 W0“讲给老人听的话”加一句，教老人用「唔好記住」这四个字。
6. 数据按 #113 第 10 节其余各项列工时的，全部排 Phase B 之后，不在本文件内。

## F. 1015-intake 第 0 节还没答的问题

第 1 题（字段读取方）T47 报告已答；第 2 题（规则组用到哪些字段）、第 3 题（配对能否直接读，本文件 A4 已按“能”写，不能就说）、第 4 题（旧数据）、第 5 题（生效延迟和重开 App）、第 6 题（内地和海外网络能否用）仍要答，写进 docs/dev-reports/。第 6 题影响 W0 问不问离港，10/19 前最好有答案。

## G. 10/19 前的非开发操作（Junyu 在控制台做，开发窗口只提供脚本和核对）

1. `sequenceUploadEnabled` 改回 false；`meta/randomization_config.enabled` 设 true；`meta/alert_config` 已建（enabled true，primaryEmail 为 Junyu，无 backupEmail）。
2. 团队和评估员账号 `isTester: true`（规则只允许管理员写，用 Admin SDK 脚本或控制台）。
3. 开 `enrollmentGateEnabled`；其余开关按 10/15 第 8 条的正式状态。
4. 开发窗口给一个只读核对脚本，列出以上各项的当前值，Junyu 跑一次贴结果。

## H. 排期

| 什么时候前 | 要有 |
|---|---|
| 10/18 晚 | E1 (a) emulator 六步 |
| 10/19 登记前 | G 全部；F 第 6 题；E1 (b) 开开关 |
| 10/22 | B（PR 草稿，Junyu 看文本）；A 的 1、2、4、7 |
| 10/26 | A 的 3、5、6；C；E3、E4 |
| 已完成 | D 报告（PR #113） |

## I. 要 Junyu 定的事

没有。E1 已定为打开；六步测试不过时按 E1 (c) 处理，不用再问。开发窗口遇到要定的事列在对话结尾，不替 Junyu 定。
