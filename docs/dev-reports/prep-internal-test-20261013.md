# 内部测试前准备报告（2026-10-13）

> 统筹会话写，给 Junyu 和产品窗口讨论用。日期：2026-10-14 写成（文件名沿用负责人定的 1013）。
> 依据：登记表 v8（PR #55 里的 `docs/spec/feature-registry.md`）、`docs/dev-tasks/dev-tasks-1010.md`、`dev-tasks-1010b.md`（PR #55）、`docs/release/internal-test-1010.md`、`docs/dev-reports/product-reply-20261010.md` 和 `开发窗口交接-1010.md`（PR #55）、各 PR 的报告。
> 基线：`main` @ `b2cd4d3`。没有合并任何 PR，没有推 `main`，没有连生产 Firestore，没有打包。

## 结论

1. **5 个 PR 都实际跑了测试，全部通过**：每个 PR 的分支上，Flutter 六套构建变体和后端测试（含 Firestore 模拟器）都过了；GitHub 上的 CI 也都是绿的。我又把 5 个 PR 按建议顺序在本地合成一个临时分支（没有推送）再跑一遍，也全部通过。
2. **建议**：#51、#55、#52、#56 可以合；#57 **改了再合**，要改的只是文档：它和 #51 用了相同的待办编号（78、79），合并时不报冲突，但表里会重号。详见第一节。
3. **合并顺序**：#51 → #55 → #52 → #57 → #56。代码文件全部能自动合并；每一步只在 `STUDY_CHANGELOG`、`history`、`backlog` 上有文档冲突，两边都留就行。每一步的冲突和解决方法见第二节。
4. **任务二（#51 的冲突）**：已经不存在了。10/10 14:01 分支上的合并提交 `89290a7` 已经解决。交接文档的提交时间是 14:03，只晚两分钟，写的时候应该还没看到这次合并。我本地复核过：对现在的 `main` 没有冲突，相对 `main` 只多出 T22 的一行和一节。两套测试都在这个提交上跑过，全过。所以没有往 #51 推新的提交。见第三节。
5. **任务三**：内部测试指引写成 `docs/release/internal-test-1013.md`，分“这一轮能测”和“要等 T21、T24、T25、T27、T30、T34”两部分。**现在的 Build APK 工作流打不开 `RULE_TEMPLATE_REPLIES`**，测试包要么在本机打，要么先给工作流加一个选项，要 Junyu 定。没有打包、没有发给任何人。
6. **任务四（T21）**：正在做，分支 `fix/phase-config-split`。做完另开 PR 草稿，再回来更新本报告第五节。
7. 最后一节“要 Junyu 定的事”有 11 项，每项给了可选做法。

## 一、逐个 PR 核对

测试环境（本机，云端容器）：Flutter 3.35.3（Dart 3.9.2）、Node 24.21.0、firebase-tools 15.33.0、Java 21、Firestore / Auth / Storage 模拟器。命令就是仓库的 `tool/ci_flutter_tests.sh` 和 `tool/ci_backend_tests.sh`，另跑 `flutter analyze --no-fatal-infos --no-fatal-warnings`（和 CI 一样）。

先跑了 `main` 做对照：Flutter 六套全过（默认构建 387 个通过、21 个跳过）；后端全过；`flutter analyze` 88 条提示（info / warning，旧有的），0 个 error。下面各 PR 的“跳过”都是只在某个开关打开的那套里才跑的测试，属正常。

### PR #51 T22：旧“陪伴者区分评估”不进盲法导出（SPEC:C15、C22）

分支 `fix/legacy-agent-diff`，测试的提交 `89290a7`。[PR 链接](https://github.com/Junyu-Andy/LonelinessCombatting/pull/51)

1. **改了什么**
   - 新版盲法导出（`exports_v2`）不再导出旧的“陪伴者区分评估”（`agent_diff`）。导出清单里写明“揭盲前不导出”；检查脚本 `tool/check_blinded_export.js` 见到这个文件会报错。改在 `functions/blinding.js`。
   - Phase A 打开 ADA 后不弹旧问卷：T17 已经做了，这次只补测试（`test/ada_test.dart`）。
   - **老人看到的**：没有变化。**研究人员看到的**：新版盲法导出少了 `agent_diff.ndjson`。旧版导出（盲法开关关着时）和 `tool/admin_dump.js` 仍会导出它（待办第 79 项）。
2. **开关**：没有新开关。相关的旧开关都关着：`meta/blinding_config.enabled`（默认关，关时走旧版导出，T22 没动旧版）、`LEGACY_AGENT_DIFF_PHASE_B`（编译开关，默认关）、`app_config/phaseA_schedule.adaEnabled`（默认关）。
3. **测试**：
   | 测试 | 结果 |
   |---|---|
   | Flutter 六套 | 全过：默认 387（跳过 21）、Phase B 60、规则组页面 5、记忆 v1 16、模板开关两套 12 和 16 |
   | 后端（单元 + 规则 + 模拟器 + 删除脚本） | 全过；其中 `blinding_test.js` 11 项（比 main 多 1 项 T22 测试）、`blinding_emulator_test.js` 7 项（合成两组队列导出后没有 `agent_diff`，检查脚本退出 0） |
   | `flutter analyze` | 0 error（88 条提示，同 main） |
   | GitHub CI | 绿 |
4. **风险**：很小。只改服务器的导出白名单，App 不变。只在打开 `meta/blinding_config.enabled` 后的每周导出里起作用；dev 环境现在能用的功能都不受影响。一个文档问题：它加的待办第 78、79 项和 #57 撞号（见 #57）。
5. **建议：可以合**，排第一个。

### PR #52 T26：安全分类器（LoRA）两组、两期和试跑共用；`turns` 加 `safetyTurnId`（SPEC:C13）

分支 `feat/lora-both-arms-v2`，测试的提交 `8903c04`。[PR 链接](https://github.com/Junyu-Andy/LonelinessCombatting/pull/52)。它取代旧的 PR #49（旧编号 T24），#49 还开着，建议合并 #52 后关掉 #49。

1. **改了什么**
   - 写成决策 0033：分类器两组共用，只给风险等级和分数，只触发两组相同的安全流程；取代 0025 里“两组是否都用”那一部分（0025 顶部标了 Superseded）。
   - 每条消息记录（`users/{uid}/turns`）多一个字段 `safetyTurnId`，和安全事件、分类器调用记录是同一个编号，两组都写。这样一条安全记录能对到是哪一条消息。规则组签到 B、回忆 B、通通 B 改成由页面先生成编号再传给安全检测（`check_in_arm_b.dart`、`reminiscence_arm_b_page.dart`、`tung_tung_page.dart`、`rule_submission_flow.dart`、`chat_session_recorder.dart`）。
   - 上线清单加 H 节（模型地址、鉴权、部署机器等）。
   - **老人看到的**：没有变化。**研究人员看到的**：`turns` 多一个字段。
2. **开关**：两个分类器总开关都默认关，没有模型：`app_config/phase_a.safetyClassifierEnabled`（App）和 `meta/safety_config.classifierEnabled`（服务器），两个都开才生效。`safetyTurnId` 不在开关后面：它只是把已有的编号多写一处，不改变任何行为。
3. **测试**：
   | 测试 | 结果 |
   |---|---|
   | Flutter 六套 | 全过：默认 392（跳过 21）、Phase B 104（这套多跑了分类器测试）、规则组页面 5、记忆 v1 16、模板两套 12 和 16 |
   | 后端 | 全过；`safety_classifier_emulator_test.js` 12 项（比 main 多 1 项：Phase A、Phase B、试跑、规则组同一个答案、同样的记录字段） |
   | `flutter analyze` | 0 error |
   | GitHub CI | 绿 |
4. **风险**：低。改到规则组 3 个页面（签到 B、回忆 B、通通）的安全检测调用和两处记录代码，但只是多传一个编号，检测本身（`lib/core/safety/`）没改，两组一致的测试仍过。开关关着，dev 环境现在的功能不受影响。打开分类器之前还有两件已记在待办的事：通通 Hybrid 组“搜一搜关闭”固定回应不问分类器（第 85 项）；CLAUDE.md“规则组永远不能调用 LLM”和 LoRA 的关系（第 86 项）。
5. **建议：可以合**。

### PR #55 docs：10/10 第二次交接（T34 告警邮件、Phase A 暂停、错字改正、登记表 v8、R1–R9 重建版）

分支 `claude/peaceful-keller-n93a0y`，提交 `5093999`。[PR 链接](https://github.com/Junyu-Andy/LonelinessCombatting/pull/55)

1. **改了什么**（只改文档）：登记表 v8；任务单 `dev-tasks-1010b.md`（新任务 T34，更正 T21、T24–T27、T30–T33）；决策 0034（Phase A 暂停，只做 Phase B 和试跑）；定稿文字的错字改正（`docs/spec/copy/`）；给产品窗口的回复 `product-reply-20261010.md`；R1–R9 重建版 `开发窗口交接-1010.md`。**老人和研究人员**：App 和数据都没有变化；以后的开发按 v8 和 1010b 做。
2. **开关**：没有代码，没有开关。
3. **测试**：只改了 `docs/` 下 10 个文件（`git diff --stat` 核对过），代码和 `main` 完全一样，所以 `main` 的测试结果就是它的结果（全过）。GitHub CI 绿。另外核对了：它改的 `rule-templates.md`、`short-texts.md` 和 #57 里的**逐字相同**，两个都合并不会冲突。
4. **风险**：没有功能风险。合并后 Phase A 正式按暂停处理：这一轮内部测试不再打 `phase_a` 包、不测 ADA（`internal-test-1013.md` 已照改）。
5. **建议：可以合**，排在 #57 之前。

### PR #56 T31：记忆分共享层和私有层（SPEC:C05）

分支 `feat/memory-layers`，测试的提交 `0e536da`。[PR 链接](https://github.com/Junyu-Andy/LonelinessCombatting/pull/56)

1. **改了什么**（都在开关后面）
   - 开关打开后：称呼、家人、居住、作息、兴趣、喜好，三位陪伴者都能用（共享层）；健康、重要事件、心事、回忆故事、哀伤、所有摘要和待跟进，只给听到的那位（私有层）；判为敏感的一律私有。过滤在服务器上做（`functions/memory.js`）。
   - 设置里删一条，连带删其他陪伴者的同类副本和引用它的摘要。
   - 每次注入记忆都记下共享几条、私有几条、来自哪位陪伴者（“记忆剂量”，`mem_injections`）。
   - 抽取 prompt v3 写好了（`functions/prompts/memory_extraction.v3.txt`），**没有切换**，仍用 v2。
   - 「我記得嘅嘢」页顶部可以显示说明 S7（另一个开关）。
   - **老人看到的**：开关关着时没有变化。**研究人员看到的**：开关关着时没有变化；打开后记忆条目多 `layer`、`sourceAgent`，剂量日志多几个字段。
2. **开关**（都默认关）：`meta/memory_config.layersEnabled`（只认布尔 `true`）；`app_config/feature_flags.memoryLayersNoticeEnabled`（S7）；`meta/memory_config.extractionPrompt` 保持 `memory_extraction.v2`。两个开关要同一天一起开。
3. **测试**：
   | 测试 | 结果 |
   |---|---|
   | Flutter 六套 | 全过：默认 389（跳过 22）、Phase B 60、规则组页面 5、记忆 v1 17、模板两套 12 和 16 |
   | 后端 | 全过；`memory_test.js` 55 项（main 44 项）、新的 `memory_layers_emulator_test.js` 11 项、原有 `memory_emulator_test.js` 19 项和 `memory_acceptance_emulator_test.js` 5 项、Firestore 规则 86 项（多 1 项：客户端改不了 `layer`、`sourceAgent`） |
   | `flutter analyze` | 0 error |
   | GitHub CI | 绿 |
4. **风险**
   - 改动最大（`functions/memory.js` 约 260 行），而且在每次 Hybrid 聊天都会走的路上。我读过改动：开关关时走的仍是原来的函数（`visibleTo`、旧的跟进筛选），类目排序只是插入新类目、原有 8 类的先后不变；有“开关关时和现在一样”的测试。
   - v3 prompt 只靠配置挡住（文件里没有“待定稿”标记）。只要没人把 `extractionPrompt` 改成 v3 就不会用；这个配置只有服务器管理员能改。
   - 打开后有几件研究侧还没答的事（T31 报告最后一节）：讲旧时经历时提到的家人会进共享层；健康和哀伤内容多半因为安全词整轮不记；心事、哀伤要不要一律当敏感；年龄没有类目。这些**不影响合并**（开关关着），但影响什么时候打开。
   - dev 环境现在的记忆功能不受影响（开关关着）。如果这一轮内部测试打开分层，作息、兴趣、喜好会从“只给听到的那位”变成三位都知道。
5. **建议：可以合**，开关保持关。排最后：改动最大，合并后如果测试发现问题，最容易单独处理。

### PR #57 T33：定稿文字接入（规则组 41 条模板、S1a、S2、S3、S4a、S5）（SPEC:C02、C06、C07、C17、C18）

分支 `feat/final-copy`，测试的提交 `da8032c`。[PR 链接](https://github.com/Junyu-Andy/LonelinessCombatting/pull/57)

1. **改了什么**
   - 规则组签到、回忆提交后的模板换成定稿 41 条：小欣、阿珍/阿伯各按五档心情 × 4 条；回忆没选心情用 G-1；回忆里命中 `moderate_review`（哀伤、旧日艰难）时不看心情，从 Z5 选。签到命中任何安全级别、回忆命中 `moderate_interrupt` 或 `acute` 都不给模板。决策 0032。
   - 短文字：S1a（通通遇到要上网查的问题时的固定回应）、S2（“唔好記住”确认句，新文件 `memory_forget_ack.v2.txt`，v1 不动）、S3（人生點滴入口那句话）、S4a（行动计划提醒推送）、S5（入组引导最后加一屏使用建议）。
   - **老人看到的**：开关都关着时，只有 S3 会变：人生點滴入口从“4 個主題、4 個禮拜”变成“一共 4 個主題，每個禮拜一個”，**这一句没有开关**。另外英文界面也显示粤语模板（没有英文定稿）。**研究人员看到的**：模板日志 `rule_template_reply` 的编号变成定稿编号（X1-1 … G-1），`pool_version` = `2026-10-10-final`。
2. **开关**（默认都关；S3 没有开关）：
   | 开关 | 默认 | 管什么 |
   |---|---|---|
   | `RULE_TEMPLATE_REPLIES`（编译开关） | 关 | 规则组模板。现在没有【占位】，**只开这一个模板就生效** |
   | `RULE_TEMPLATE_REPLIES_ALLOW_PLACEHOLDER`（编译开关） | 关 | 只用于测试截图 |
   | `app_config/feature_flags.searchOffReplyEnabled` | 关 | S1a |
   | `meta/memory_config.forgetAckReply` | 关 | S2 |
   | `app_config/reminders.m7FollowupPushEnabled` | 关 | S4a |
   | `app_config/usage_copy.onboardingUsageAdviceEnabled`（新） | 关 | S5 |
   | （无） | — | S3 |
3. **测试**：
   | 测试 | 结果 |
   |---|---|
   | Flutter 六套 | 全过：默认 399（跳过 34，多跳过的是只在模板开关打开那两套里跑的测试）、Phase B 60、规则组页面 5、记忆 v1 16、模板两套各 31（main 是 12 和 16） |
   | 后端 | 全过；新的 `final_copy_test.js` 4 项、`memory_test.js` 44 项、`reminders_emulator_test.js` 9 项、Firestore 规则 85 项 |
   | `flutter analyze` | 0 error（88 条提示，同 main） |
   | GitHub CI | 绿 |
   - 41 条模板、S1a、S3、S5 和定稿文件逐字比对的测试在 `test/final_copy_test.dart`；S2、S4a 在 `functions/test/final_copy_test.js`。
4. **风险**
   - **待办编号撞号**（要改）：它在 `docs/dev/backlog.md` 加了第 78、79、80 项；#51 也加了第 78、79 项，内容不同。两个分支改的是表里不同的位置，**git 合并时不报冲突**，表里会出现两个 78、两个 79。#57 的报告第 5 节、`history.md` 里还写着“backlog 第 80 项”，第 67 项里写着“见第 78 项”。
   - **S3 没有开关**：合并后的下一个 App 版本，老人就会看到新句子。文字是定稿的，但和“新行为放在开关后”的做法不一样，要 Junyu 定。
   - **模板开关打开后，回忆页的心情提示是【占位】**：“【占位】你而家心情點？（可以唔揀）”。内部测试没关系；给参与者打开模板前必须定稿。
   - 签到里写到哀伤内容（`moderate_review`）没有模板，只回“收到喇。聽日再見。”（定稿只给了回忆的哀伤规则）。
   - 网页版构建的一个错误（`newTurnId` 用 `1 << 32`，网页版是 0），Android 不受影响，记在它的待办第 80 项。
   - 对 dev 环境现在的功能：开关关着时只有 S3 那句话变；规则组签到仍回“收到喇。聽日再見。”。
5. **建议：改了再合**。只要改文档：把它的待办 78、79、80 改成没人用的编号（例如 93、94、95），同时改 `history.md`、T33 报告第 5 节和第 67 项里的引用。这一步可以在合并前处理冲突时一起做（第二节第 4 步）。S3 要不要加开关，看 Junyu 的决定（“要 Junyu 定的事”第 3 项）；如果要加，代码也要改一小处。

## 二、合并顺序和每一步的冲突

**建议顺序：#51 → #55 → #52 → #57 → #56。**

理由：先合最小、最稳的 #51；#55 是文档，要在 #57 之前；#52 只多写一个字段；#57 紧跟 #55；#56 改动最大，放最后。#57 和 #56 谁先都行，代码上互不依赖。

我在本地临时分支 `tmp/integration-1013`（没有推送）按这个顺序一个个合并，记下每一步的冲突：

| 步 | 合并 | 冲突的文件 | 解决方法 |
|---|---|---|---|
| 1 | #51 | 无 | — |
| 2 | #55 | `docs/dev/backlog.md` 1 处 | #51 加的第 78、79 项和 #55 加的第 91、92 项在同一位置。两边都留，按编号排 |
| 3 | #52 | `STUDY_CHANGELOG.md` 1 处、`history.md` 1 处、`backlog.md` 2 处 | 两边都留。`STUDY_CHANGELOG` 和 `history` 按日期新的在上（T26 的 10/10 那行在 T22 的 10/09 那行上面）。`backlog` 开头“最后更新”两行合成一行；第 1 节新行按编号排（84 在 90 前） |
| 4 | #57 | `STUDY_CHANGELOG.md` 1 处、`history.md` 1 处、`backlog.md` 2 处（“最后更新”、第 67 项两边各改了一处）；**另有不报冲突的撞号** | 两边都留；第 67 项把两边加的说明合成一句。再把 #57 的待办 78、79、80 改成 93、94、95，同步改 `history.md`、T33 报告和第 67 项里的引用 |
| 5 | #56 | `STUDY_CHANGELOG.md` 1 处、`history.md` 1 处、`backlog.md` 1 处（“最后更新”） | 两边都留。`history.md` 两节之间记得空一行 |

- **代码文件都自动合并了**：`check_in_arm_b.dart`、`reminiscence_arm_b_page.dart`、`tool/ci_flutter_tests.sh`（#52 和 #57 都改）；`functions/memory.js`、`functions/test/memory_test.js`（#56 和 #57 都改）；`docs/dev/architecture.md`、`docs/release/prelaunch-checklist.md`。我看过合并结果，两边的改动都在。
- 决策编号 0032（#57）、0033（#52）、0034（#55）、0035（#56）不重复。
- 合完 5 个之后的临时分支（本地提交 `d5f45af`，没有推送），两套测试全过：Flutter 六套（默认 406、跳过 35；Phase B 104；规则组页面 5；记忆 v1 17；模板两套各 31），后端全过（`blinding_test.js` 11、`safety_classifier_emulator_test.js` 12、`memory_test.js` 55、`memory_layers_emulator_test.js` 11、`final_copy_test.js` 4、Firestore 规则 86 等），`flutter analyze` 0 error。
- **实际操作**：GitHub 网页上合并一个后，下一个 PR 会显示有冲突。要先把新的 `main` 合进那个 PR 的分支、照上表处理、等 CI 变绿再合。网页的冲突编辑器能做，但表格行很长、容易漏；可以让一个 Claude Code 会话在那个 PR 的分支上做（“要 Junyu 定的事”第 1 项）。
- 合并后要部署：#51、#56、#57 改了 Cloud Functions。用 Deploy Firebase 工作流部署 `rules_and_functions`（规则这次没改，一起部署也没关系）。

## 三、任务二：PR #51 和 main 的冲突

**结论：冲突已经解决了，不需要再改。**

1. 交接文档 `开发窗口交接-1010.md` 第四节写着 #51 和 `main` 在 `STUDY_CHANGELOG.md`、`history.md` 上有冲突。那份文档是 10/10 14:03 提交的（#55 的 `5093999`）。
2. 但 #51 分支上 10/10 14:01 已经有一个合并提交 `89290a7`（“Merge origin/main into fix/legacy-agent-diff (resolve history and changelog)”），把当时最新的 `main`（`b2cd4d3`，也就是现在的 `main`）合了进来。
3. 那次的解决方法（我逐行核对过）：两边都留；`STUDY_CHANGELOG` 里 `main` 的两行（10/10 陪伴者图片、阿珍阿伯紫色）在上，T22 的 10/09 那行在下；`history.md` 里 `main` 的两节（10/10）在上，T22 那节（10/09）在下。按日期新的在上，没有丢行，没有残留冲突标记。
4. 我本地复核：
   - `git merge-tree` 模拟 #51 合进现在的 `main`：没有冲突。GitHub 上 #51 的状态也是“可以合并（clean）”。
   - #51 相对 `main` 在这两个文件上只**增加**了 T22 的一行和一节，没有删任何东西。
   - 在 `89290a7` 上跑了两套测试：Flutter 六套全过，后端全过（第一节 #51 的表）。
5. 所以没有往 #51 推新的提交（推一个空提交没有意义）。
6. 以后要注意：如果先合 #55 再合 #51，#51 会在 `backlog.md` 冲突一处（第二节第 2 步），两边都留就行。按建议顺序 #51 第一个合，就不会再冲突。

## 四、任务三：内部测试指引

写在 `docs/release/internal-test-1013.md`，取代 `internal-test-1010.md`（在旧文件开头加了一行指向新文件）。和 1010 版比：

1. **只打一个包**：Phase B 测试包，打开 `RULE_TEMPLATE_REPLIES`。Phase A 暂停，不打 `phase_a` 包、不测 ADA。
2. **打包**：现在的 Build APK 工作流只有 `phase_a`、`phase_b`、`memory_v1`，打不开模板开关。指引写了两种做法：本机打包（现在就能用，命令写好了）；给工作流加一个 `phase_b_templates` 选项（改法见附录）。选哪个由 Junyu 定。
3. **测试账号**：注册后服务器自动给 `arm: "A"`、`force_a`，这时没有服务器记忆，一定要在控制台改成 `armAssignmentMode: "randomise"`。写了怎样分组、怎样看出分组生效（Hybrid 组设定里有「記憶」一节）、怎样切换（换到 Hybrid 后服务器要 10 分钟才认）、三种重置（只清记忆、清模板轮换、整个重来），以及 `delete_memory.js` 一定要加 `--keep-memory-on`，否则账号以后永远没有记忆。
4. **测试项和通过标准**：三位陪伴者聊天、两组回应对照、签到后 20 条和回忆后 21 条模板（同一心情连做 4 次能看到这一档的 4 条）、危机页和热线（两组每个输入点）、AI 不写热线号码、记忆（当天、隔天回调、“唔好記住”、删一条、规则组没有记忆）、闪退、回复速度、切换组别；可选：记忆分层、S1a、S5、S4a、S3、第 2 周 DJG、Brief PR。
5. **测试句子**：我用服务器那份词库（和 App 同一份）实测了 T6 的合成句：A1、A8 会触发危机页；M1–M3 是 `moderate_interrupt`；M4 是 `moderate_review`。**A2–A7（储药、跳楼、遗书等间接说法）现在词库认不出**，是已知问题（待办第 32 项），指引里写明不当新问题报。
6. **热线**：指引要求测试员看到拨号界面和号码就挂断，不要真的拨出（是真的危机热线）；发现号码不对只报告，不改。

## 五、任务四：T21

正在做（分支 `fix/phase-config-split`）。做完后在这里写结果和 PR 链接。

## 六、其他发现（不影响这一轮测试）

1. 旧 PR #49（旧编号 T24 的 LoRA）还开着，已由 #52 取代。建议 #52 合并后关掉 #49。
2. App 没有崩溃上报（没有 Crashlytics 之类），这一轮闪退只能靠人记。要不要加，留到以后。
3. 这次没有改 `docs/dev/backlog.md` 和 `docs/history.md`：5 个 PR 都在改这两个文件的同一位置，再加一个会多一轮冲突。“要 Junyu 定的事”定了以后再补。

## 要 Junyu 定的事

1. **5 个 PR 怎样合**
   - (a) 按建议顺序 5 个都合，内部测试测全部；
   - (b) 先合 #51、#55、#52、#57，#56 等研究侧答完 T31 报告最后一节的问题再合（这一轮不测记忆分层）；
   - (c) 其他组合。
   另外，处理冲突由谁做：(i) Junyu 在 GitHub 网页上做；(ii) 开一个 Claude Code 会话，在每个 PR 自己的分支上合 `main`、处理冲突、跑测试，Junyu 只按“合并”。
2. **测试包怎样打出 `RULE_TEMPLATE_REPLIES=true`**
   - (a) Junyu 在自己电脑上打（命令在指引第二节方法一；要装 Flutter 3.35.3、Java 17、Android SDK）；
   - (b) 给 Build APK 工作流加一个固定选项 `phase_b_templates`（附录 A，改 4 行；要另开一个小 PR）；
   - (c) 给工作流加一个“额外开关”的自由填写框：更灵活，但以后打参与者包时容易填错。
3. **#57 的 S3（人生點滴入口一句话）没有开关**
   - (a) 接受：文字已定稿，合并后的下一个 App 版本就显示；在 `STUDY_CHANGELOG` 写明生效日期；
   - (b) 合并前给 S3 加一个开关（默认关），和其他短文字一样；
   - (c) 这次先不接 S3，等上线前再接。
4. **这一轮内部测试打开哪些可选开关**（指引第三节；都在 dev 项目，测完关回）
   - (a) 都不开，只测必测项；
   - (b) 全开：记忆分层和 S7、S2、S1a、S5、S4a、第 2 周 DJG；
   - (c) 只开一部分（请指明）。
5. **#57 和 #51 的待办编号撞号由哪边改**
   - (a) #57 改成 93、94、95（#51 先合，改后合的那个）；
   - (b) #51 改成别的编号，#57 不动。
6. **回忆页心情提示“【占位】你而家心情點？（可以唔揀）”**（给参与者打开模板之前要定）
   - (a) 请产品窗口写定稿文字；
   - (b) 去掉这句提示，只留心情脸；
   - (c) 用定稿规则里的说法“講起呢段往事嘅心情”改写（要研究侧确认）。
7. **回复速度的通过线**（指引第 5.10 项）
   - (a) 用我提的：一半以上不超过 6 秒，每次不超过 20 秒，没有超时；
   - (b) 定别的数字；
   - (c) 这一轮只记录，不设通过线。
8. **签到里写到哀伤内容（`moderate_review`）时没有模板**
   - (a) 维持（定稿只给了回忆的哀伤规则）；
   - (b) 签到也给一条（例如从 X5 或 Z5 选），要研究侧定用哪组；
   这一项也在 #57 报告“要带回研究侧的发现”第 4 条。
9. **测试用的危险说法**
   - (a) 只用 A1、A8 测危机页（指引现在的写法）；
   - (b) 测试员自由写一些说法，漏检的记下来，作为词库改进的材料（要说明这些句子只用于测试，不进研究数据）。
10. **测试账号要不要 `isTester: true`**
    - (a) 全部加（不推定时推送，告警只记录不发信；指引现在的写法）；
    - (b) 另开一个不加的账号，专测推送和告警邮件，测完整个删除。
11. **T21**：T21 做完后在这里补要定的事。

## 附录 A：Build APK 加一个模板选项（方案，未改）

`.github/workflows/build-apk.yml` 两处：

```yaml
        options: [phase_a, phase_b, phase_b_templates, memory_v1]
```

```yaml
            phase_b)   DEFINES="--dart-define=PHASE_B=true" ;;
            phase_b_templates) DEFINES="--dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true" ;;
```

文件开头的说明里加一行“phase_b_templates — 内部测试包：Phase B + 规则组模板开”，`docs/dev/ci-cd.md` 的表也加一句。只影响手动打包，不影响 CI 和参与者包。

## 附录 B：本次测试日志的位置

测试日志在本次会话的临时目录，没有提交进仓库。要复现，在对应提交上跑 `tool/ci_flutter_tests.sh` 和 `tool/ci_backend_tests.sh`。
