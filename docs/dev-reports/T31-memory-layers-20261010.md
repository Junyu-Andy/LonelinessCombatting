# T31 记忆分层 报告（2026-10-10）

分支 `feat/memory-layers`，SPEC:C05。决策记录 `docs/decisions/0034-memory-shared-private-layers.md`。

## 结论

1. 记忆分成共享层和私有层，做好了，放在开关后面，**默认关，关时和现在完全一样**（有测试）。
2. 打开后：称呼、家人、居住、作息、兴趣、喜好三位陪伴者都能用；健康、重要事件、心事、回忆、哀伤、所有摘要和待跟进只给听到的那位；判为敏感的一律私有。过滤在服务器上做。
3. 「唔好記住」本来就两层都不写（决策 0024），补了测试。设置里删一条，现在会连带删其他陪伴者的私有副本和引用它的摘要。
4. 记忆剂量（注入日志）按共享层、私有层分开记，带来源陪伴者和会话编号。
5. 抽取 prompt v3 写好了，**没有切换**，仍用 v2。用 T4 的 30 段合成对话跑了一遍：26 次真实调用，82 条事实，58 条共享、24 条私有。
6. 有 4 件事要研究侧确认（最后一节）。最要紧的是：老人讲旧时经历时提到家人（“老公以前揸的士”），模型记成“家人”，于是进了共享层。

## 1. 开关

| 开关 | 位置 | 默认 | 作用 |
|---|---|---|---|
| `layersEnabled` | Firestore `meta/memory_config` | 关（只有布尔 `true` 才开） | 分层写入、分层过滤、剂量记录、删除扩大范围 |
| `memoryLayersNoticeEnabled` | Firestore `app_config/feature_flags` | 关（只有布尔 `true` 才开） | 「我記得嘅嘢」页顶部显示 S7 |
| `extractionPrompt` | `meta/memory_config` | `memory_extraction.v2`（不变） | 写 `memory_extraction.v3` 才用 v3 |

两个开关要同一天一起开，否则页面说明和实际共享范围对不上。已写进上线清单 C1a（`docs/release/prelaunch-checklist.md`）。

代码：`functions/memory.js` `t10Flags`（`layersEnabled`）；`lib/core/feature_flags/remote_feature_flags.dart`（`memoryLayersNoticeEnabled`）。

## 2. 分层规则

### 2.1 写入

- 每条事实、摘要、待跟进由服务器写 `layer`（`shared` / `private`）和 `sourceAgent`（`functions/memory.js` `processExtraction` 里的 `layerFields`）。开关关时不写这两个字段。
- 原来的 `agent_id`、`visibility` 照写，所以关掉开关就回到旧规则。
- 客户端不能写或改：Firestore 规则只许老人把 `status` 从待确认改成已确认（`firestore.rules` `mem_facts`）。新加了规则测试，改 `layer`、`sourceAgent` 都被拒（`test/rules/memory_rules.test.js`）。

### 2.2 类目对应

| 类目 | 中文 | 层 | 备注 |
|---|---|---|---|
| `name` | 称呼 | 共享 | |
| `family` | 家人和身边的人 | 共享 | |
| `living` | 居住情况 | 共享 | |
| `routine` | 日常作息 | 共享 | 原来只给来源陪伴者，现在共享 |
| `hobby` | 兴趣 | 共享 | 同上 |
| `preference` | 其他喜好 | 共享 | 同上 |
| `health` | 健康 | 私有 | 本来就一律敏感 |
| `event` | 重要事件 | 私有 | **开发窗口推出来的，请研究侧确认**（见最后一节） |
| `feeling` | 心事和情绪 | 私有 | v3 新类目 |
| `story` | 回忆故事 | 私有 | v3 新类目 |
| `grief` | 哀伤内容 | 私有 | v3 新类目 |
| 会话摘要 | | 私有 | |
| 待跟进 | | 私有 | 只由 `sourceAgent` 提起 |

- 代码：`SHARED_LAYER_CATEGORIES`、`V3_EXTRA_CATEGORIES`、`layerFor`（`functions/memory.js`）。
- 敏感判断照旧（`SENSITIVE_CATEGORIES`、`SENSITIVE_TERMS`、模型标的 `sensitive`）。判为敏感的，即使在共享类目也算私有。例：“同個仔嗌交”记在 `family`，但命中“嗌交”，私有。老人在页面上确认后仍是私有（确认只改 `status`）。

### 2.3 读取

- `selectForInjection` 加了 `layers` 选项，打开后用 `visibleInLayers`：自己听到的都能用；别人听到的只能用共享层的。
- 待跟进：只取 `sourceAgent` 是自己的。
- 抽取时模型看到的“现有事实”用同一条规则（`processExtraction` 里的 `canSee`），所以阿珍能更新小欣记下的共享事实，看不到小欣的私有事实。
- 开关打开后，旧的策略 A、C 都按分层规则，不再有“全共享”。策略 B 仍然什么都不共享。

### 2.4 老人关了共享同意

保持现状（决策 0020）：`consent.sharedContextUse` 不是 `true` 的人按策略 B，每位陪伴者只用自己听到的，共享层也不共享（`effectivePolicy`）。有测试。

### 2.5 旧数据

不迁移。没有 `layer` 的条目读取时按 2.2 推算（`itemLayer`）；没有 `sourceAgent` 的用 `agent_id`（`itemSource`）。存着的 `layer` 永远不会让敏感条目变成共享。

## 3. 「唔好記住」和删除

### 3.1 「唔好記住」

决策 0024 已经做到：那次会话不调用模型，三类都不写；同时删除以前相关的条目，查的是**所有陪伴者**的事实、跟进、摘要（`forgetRelated`），本来就覆盖两层。T31 没改代码，补了测试：阿珍那次会话说「唔好記住」，新条目为零；通通的共享条目和小欣的私有条目里相关的都删了（`functions/test/memory_layers_emulator_test.js` 第 5 项）。

### 3.2 设置里删一条：“同一件事”怎样判断

页面删一条事实或跟进，触发器调 `deleteSummaryForItem`（`functions/index.js` `memoryFactDeleted`、`memoryFollowupDeleted`）。

开关关时（决策 0024，不变）删：
1. 这条来源会话的摘要；
2. 措辞完全相同的事实或跟进。

开关开时再加（`sameThing`）：
3. 措辞去掉空格和标点后相同的事实、跟进（任何陪伴者）；
4. **同类目、同标题**的事实（任何陪伴者）。私有层里每位陪伴者各存一份，比如小欣和通通都记了 `story`「製衣廠」，措辞不同，靠这条删掉；
5. 原文里含这条内容的摘要，内容至少 4 个字（`LAYER_DELETE_MIN_CHARS`）。

可能多删：
- 两位陪伴者用了同一个笼统的标题记不同的事（例如两条 `event`「重要事件」），删一条会删两条。
- 第 4 条也会删同标题的旧版本（被更新取代、状态 `superseded` 的那条）。这是有意的，旧说法也算同一件事。
- 删掉的副本会再触发一次删除，范围可能再扩一点（例如副本的措辞又出现在另一条摘要里）。

可能漏删：
- 标题不同、内容是同一件事（小欣记「膝頭」，通通记「腳痛」）。
- 摘要是改写过的，不含原句（摘要本来就不写敏感内容，私有层的条目多半是敏感的，所以影响小）。
- 内容不到 4 个字时不查摘要（例如只写「阿欣」）。

## 4. 记忆剂量

开关打开后，`users/{uid}/mem_injections` 每条多 4 个字段（`injectMemory`、`injectionDose`）：

| 字段 | 内容 |
|---|---|
| `layer_counts` | `{shared: n, private: m}`：这次实际注入的条数（截断后） |
| `source_agents` | `{shared: {siu_yan: 3, …}, private: {…}}`：各层来自哪位陪伴者 |
| `session_id` | App 在 `proxyDeepSeek` 里传的 `sessionId`；现在 App 不传，是 `null`，T25 之后才有 |
| `layers_enabled` | `true` |

原来的 `memory_ids`、`layers`（跟进、事实、敏感、摘要各几条）照旧。一天里的几条摘要合成一行注入，计数按条算。

T30 的过程数据导出按人、按陪伴者、按层汇总时读这几个字段。

## 5. 抽取 prompt v3

文件：`functions/prompts/memory_extraction.v3.txt`。v2 没改。`meta/memory_config.extractionPrompt` 仍是 v2。

### 5.1 和 v2 的对照

| | v2 | v3 |
|---|---|---|
| 类目 | 8 个 | 11 个：加 `feeling` 心事和情绪、`story` 回忆故事、`grief` 哀伤内容 |
| 类目说明 | 只列名字 | 每个类目一句说明，分“三位陪伴者都會知（共享）”和“只有今次呢位陪伴者知（私有）”两组 |
| 一句话两样内容 | 没写 | 拆两条，例：「個女阿欣成日陪我睇醫生」→ family「個女叫阿欣」+ health「有睇醫生」 |
| 拿不准 | 没写 | 揀私有嗰類 |
| 敏感 | 健康、家庭矛盾、财务、情绪困扰、丧亲标 sensitive | 同 v2，另加“feeling、grief 一般都係 sensitive” |
| 其余（安全、假设句、陪伴者名字、日期换算、摘要只写中性、JSON 格式） | | 和 v2 逐字相同 |

服务器只认 prompt 自己的类目：用 v1、v2 时出现新类目整次作废，和以前一样（`categoriesFor`，有测试）。层由服务器按类目定，不看模型。

### 5.2 用 T4 合成对话跑一遍

- 脚本：`tool/memory_eval/run_v3_layers.js`。用服务器同一套代码（筛安全词和「唔好記住」、v3 prompt、校验、`layerFor`），不经 Firestore，每段从空记忆开始。
- 结果：`tool/memory_eval/results/t31_v3_run1/layers.md`（逐条），`raw.json`（模型原始输出和调用记录）。
- 真实 DeepSeek 调用照 T10 的做法记账：`tool/memory_eval/results/ledger_t31.json`，每段上限 3 次。这次 **26 次**（30 段里 4 段是「唔好記住」，服务器不会调用模型，脚本也不调用），全部 HTTP 200，返回 `deepseek-flash`，`system_fingerprint` 都是 `aeb56401ca74e127821c4f9126dcb669`，共 30,078 输入 token、11,736 输出 token。

| 类目 | 共享 | 私有 |
|---|---|---|
| name | 11 | 0 |
| family | 25 | 2（敏感：老婆已過身、丈夫中風） |
| living | 7 | 0 |
| routine | 7 | 0 |
| hobby | 5 | 0 |
| preference | 3 | 0 |
| health | 0 | 6 |
| event | 0 | 2 |
| feeling | 0 | 4 |
| grief | 0 | 2 |
| story | 0 | 8 |
| **合计** | **58** | **24** |

待跟进 27 条，全部私有。

参考（不能直接比：T10 第 4 轮是按人连续三段、带现有事实跑的）：T10 第 4 轮 v2 存下 73 条事实，按旧规则共享 42 条；同样 73 条按新分层规则算是共享 56 条、私有 17 条。

几条值得看的：
- D08、D21、D27：老人讲旧时经历，“老公以前揸的士”“阿爸係漁民”“老公以前做巴士司机”，模型记成 `family`，进了共享层。同一段里“後生喺製衣廠做車衣”记成 `story`，私有。
- D03：“今年八十歲”记成 `health`（私有）。年龄没有合适的类目。
- D24（狗过世）、D04（掛住老婆）：记成 `grief`，敏感，私有，要老人确认后才用。
- D01：“落樓梯好辛苦”那一轮被 App 安全词库（moderate_review）筛掉，膝头痛没记下来。这是 T10 的设计（决策 0013、0024），不是 v3 的问题。

## 6. 设置页说明 S7

- 「我記得嘅嘢」页顶部一张卡，文字逐字照 `docs/spec/copy/short-texts.md` S7（`lib/features/memory/data/memory_layers_copy.dart`）。测试读规格文件那一行逐字比对（`test/memory_layers_copy_test.dart`）。
- 只在用服务器记忆的人显示：页面本来就只对服务器记忆 v1 的人列出内容，其他人看到“記憶已經熄咗”，不显示 S7。没有任何记忆时也显示在“暫時未記住任何嘢”上面。
- 只有粤语原文；英文界面也显示粤语（S7 没有英文定稿）。
- 页面上的条目没有按层分组，仍按“要不要记住 / 关于你 / 要关心的事 / 之前倾过”排，每条写“同某某講嘅”。

## 7. 范围

- 只对用服务器记忆 v1 的人生效（`inScope`：Phase B Hybrid 组、`MEMORY_V1` 测试包里自愿开启的人）。Phase A 换到 v1 由 T32 做。
- 规则组：`inScope` 对 `arm == "B"` 一律返回否，零抽取、零注入不变。开关开着时也有测试。
- `functions/index.js` 只改了一处：把 `payload.sessionId` 传给 `injectMemory`。

## 8. 测试

| 任务单第 7 节 | 测试 |
|---|---|
| 1. 小欣听到的共享类事实阿珍、通通能用；健康、心事、回忆、待跟进用不到 | `memory_layers_emulator_test.js` 第 1、1b 项；`memory_test.js`「T31 layers: other companions…」 |
| 2. 判为敏感的共享类事实不共享 | 第 2 项；`memory_test.js`「category → layer」 |
| 3. 待跟进只由来源陪伴者提起 | 第 3 项 |
| 4. 共享同意关时什么都不共享 | 第 4 项；`memory_test.js`「consent off」 |
| 5. 「唔好記住」两层都没有新条目 | 第 5 项 |
| 6. 设置里删一条，两层和相关摘要都删 | 第 6 项；`memory_test.js`「same thing」 |
| 7. 注入日志计数和实际注入一致 | 第 7 项；`memory_test.js`「dose」 |
| 8. 开关关时和现在一样；规则组没有记忆读写 | 第 8a、8b 项；`memory_test.js`「layers off」；原有 `memory_emulator_test.js` 19 项、`memory_acceptance_emulator_test.js` 全过 |
| 客户端不能改 `layer`、`sourceAgent` | `test/rules/memory_rules.test.js` |
| S7 逐字、开关默认关、页面显示 | `test/memory_layers_copy_test.dart`；`test/memory_v1_client_test.dart`「T31: S7 notice…」（`MEMORY_V1=true` 构建） |

运行结果：`tool/ci_backend_tests.sh` 全过；`flutter test`（默认构建）和 `flutter test --dart-define=MEMORY_V1=true test/memory_v1_client_test.dart` 全过（Flutter 3.35.3）。

## 9. 没做的、要注意的

- 决策记录用了 0034：T26 的分支用了 0033，0032 不确定有没有被别的分支占用，跳过。合并时如果编号冲突，后合并的改。
- `session_id` 要等 T25 的 App 在 `proxyDeepSeek` 里传 `sessionId`。
- T30 的过程数据导出还没有读 `mem_injections` 的新字段，T30 做。
- 同时开的 T21 会改 `remote_feature_flags.dart`（拆语音开关），可能和这里加的 `memoryLayersNoticeEnabled` 冲突，后合并的处理。

## 要带回研究侧的发现

1. **`event`（重要事件）归私有**是开发窗口按 10/9 第 15 条的类目推的，请确认。跑 v3 时 `event` 只有 2 条（被骗两万、今晚个女请食饭），后者其实是日常，归私有偏严。
2. **旧时经历里的家人信息进了共享层**：“老公以前揸的士”“阿爸係漁民”被记成“家人”。按 10/9 的定义，家人（名字和关系）共享、回忆故事私有，这类介于两者之间。可选：(a) 接受，共享；(b) v3 再写清“讲旧时嘅事就算提到家人都记 story”，出 v4 再跑。请定。
3. **私有层里的健康和哀伤内容大多存不下来**：App 安全词库的 moderate_review 包括“好辛苦”“過咗身”等，命中的轮次整轮不进记忆（决策 0013、0024）。所以“哀伤内容只有听到的那位知道”实际上多半是“谁都不记得”。这和第五节“丧亲内容在记忆里开不开例外”是同一件事，等研究侧和 PI。
4. **心事、哀伤一律要老人确认吗**：现在 `feeling`、`grief` 不是自动敏感，靠模型标或敏感词命中。这次 6 条全被标了敏感，要老人在页面上点“好，记住”才用。要不要像健康一样写死为敏感，请定。
5. 年龄没有类目（“今年八十歲”被记成健康）。要不要加，请定。
6. 删除“同一件事”的判断是规则（第 3.2 节），可能多删或漏删。论文局限部分可能要提一句。
