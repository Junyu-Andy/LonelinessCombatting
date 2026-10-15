# T25 会话定义与 Brief PR 第二版 报告（2026-10-14）

分支 `feat/session-briefpr`，SPEC:C16、C14。PR 草稿。依据：`docs/dev-tasks/dev-tasks-1009b.md` T25、`dev-tasks-1010.md` §二 §三、`dev-tasks-1010b.md` §二、登记表 C14 / C16、`docs/spec/copy/short-texts.md` S9 / S10a / S10b、决策 0015。

## 结论

1. **规则做好了，有测试**：会话怎样结束、哪些会话算有效、什么时候邀请 Brief PR、每天几次、2 小时过期、重复提交挡住、危机不邀请、两组同一套。规则都在 `lib/core/session/session_rules.dart` 和 `lib/features/brief_pr/data/brief_pr_scheduler.dart`，不碰 Firestore，所以可以用假时钟逐条测。
2. **全部放在一个开关后面**：`app_config/phase_b.sessionBriefPrV2Enabled`，**默认关**。关着时 App 和现在完全一样（10 分钟超时、离开聊天页弹窗 Brief PR、首次不能跳过）。有测试证明关着时走旧路。
3. 开关打开后参与者看到的变化：聊天页左上角多一个「今日傾到呢度」按钮；聊天完不再弹窗，回到「搵人傾」页顶部出一张评价卡（「好呀」／「今次唔評」）；点「好呀」才进问卷，一题一屏。两组一样。
4. **没做完的**（详见第 9 节）：截图；`brief_pr` 记录里 T24 的 `studyWeek` / `studyDay`；收尾按钮的首次说明只在每次启动后显示一次（没有跨次启动的本地存储）；决策记录只有草稿（编号待开发窗口分配）。
5. 规则组（B 组）仍然不会调用 LLM：新代码里没有任何 LLM 调用；评分不进聊天、不进记忆。
6. 已合并 T21 之后的 `main`（e851205），没有冲突。

## 1. 开关和配置

都在 Firestore `app_config/phase_b`（`lib/core/config/phase_b_config.dart`），只有 Phase B 构建会读（Phase B 和试跑用同一个包）。读不到、值不对就用默认值；开关只有布尔 `true` 才算开。

| 键 | 默认 | 作用 |
|---|---|---|
| `sessionBriefPrV2Enabled` | **关** | 总开关。关 = 现状；开 = 下面全部 |
| `sessionIdleTimeoutMinV2` | 30 | 多少分钟没有新消息算会话结束（`timeout`） |
| `briefPrDailyCapPerAgent` | 1 | 每位陪伴者每天最多邀请几次（0 = 永不邀请） |
| `briefPrCatchUpExpiryHours` | 2 | 距会话最后一条完整回复多少小时后邀请过期 |
| `freeChatValidMinUserMessages` | 3 | 自由聊天（通通、反思对话）要几条**有回复**的消息才算有效 |
| `hybridCheckInValidRequiresMood` | true | Hybrid 小欣签到：要记录了心情 |
| `hybridCheckInValidMinUserMessages` | 1 | Hybrid 小欣签到：要几条有回复的消息 |
| `hybridReminiscenceValidRequiresSave` | true | Hybrid 阿珍回忆：要按「儲存」存了本周小结才算有效（false 时按自由聊天的条数算） |

开关关着时，超时分钟数仍读 `app_config/phase_a.sessionIdleTimeoutMin`（10），和现在一样（`SessionRules.legacy`）。

## 2. 会话规则（登记表 C16）

代码：`lib/core/session/session_rules.dart`、`lib/core/session/chat_session_recorder.dart`、`lib/core/session/idle_session_timer.dart`。

### 2.1 会话怎样结束（`endReason`）

| 值 | 什么时候 | 评价卡走哪条路 |
|---|---|---|
| `close_button` | 按左上角 S9「今日傾到呢度」。阿珍回忆页按它会先走小结 + 儲存，存完算 `close_button` | 列表页卡 S10a |
| `back` | 返回键、侧滑返回手势、AppBar 返回箭头 | S10a |
| `switch_agent` | 这位陪伴者的会话还开着，另一位陪伴者开始了会话（例如转介后直接进另一个聊天页） | S10a |
| `timeout` | 连续 30 分钟没有新消息。切 App、接电话、锁屏只暂停计时，回来不足 30 分钟就重新数；超过 30 分钟回来才算结束 | 下次打开补问 S10b |
| `recovered` | App 被杀掉或崩溃，下次启动按已存的消息数和时间补判（`sweepUnclosed`）；旧版行（没有 `scheduleVersion`）仍记 `app_killed`，不补问 | S10b |
| `crisis` | 触发 acute，和现在一样 | 不邀请，记 `due_not_invited` |
| `submitted` | 规则组签到 B、回忆 B 的一次提交（决策 0015）。不在 C16 的列表里，见第 7 节要定的事 | S10a |

开关关着时仍写 `user_left` / `app_killed`，不变。

### 2.2 哪些会话有效（`isValid`，“完成一个互动单元”）

| 会话类型 `sessionType` | 页面 | 有效条件 |
|---|---|---|
| `free_chat` | 通通（两组）、Hybrid 反思对话 | ≥3 条老人消息，每条都收到真实回复（fallback、危机短路的回合不算） |
| `check_in` Hybrid | 小欣签到 A | 记录了今天心情（进聊天前必选）+ ≥1 条有回复 |
| `check_in` 规则组 | 签到 B | 必填项填完、提交、看到回应页 = 一次完整提交 |
| `reminiscence` Hybrid | 阿珍回忆 A | 按「儲存」存了本周小结（聊了很多但没存 = 无效） |
| `reminiscence` 规则组 | 回忆 B | 一次完整提交 |

危机结束的聊天如果已满足条数，`isValid` 仍为 true，但不邀请（见第 3 节）；规则组的 acute 提交因为没有看到回应页，`isValid = false`。

### 2.3 会话日志字段 `users/{uid}/sessions/{sessionId}`

原有字段不动（`participantId`、`sessionId`、`agentId`、`moduleId`、`theme`、`startedAt`、`endedAt`、`endReason`、`userTurnCount`、`fallbackCount`、`lastActivityAt`、`briefPR`…）。新加：

| 字段 | 含义 |
|---|---|
| `scheduleVersion` | 1 = 旧规则写的行；2 = 开关打开后写的行。分析时按它区分 |
| `sessionType` | `free_chat` / `check_in` / `reminiscence`（按 `moduleId` 推出） |
| `userMessageCount` | 老人发了几条消息（全部） |
| `replyCount` | 其中几条收到真实回复 |
| `lastReplyAt` | 最后一条完整回复的时间（过期时钟从这里起算） |
| `isValid` | 是否有效会话（结束时写；补判时也写） |
| `moodRecorded` / `summarySaved` | Hybrid 签到 / 回忆的两个条件 |
| `isRuleSubmission` / `ruleSubmissionCompleted` | 规则组表单页的两个标记 |
| `briefPrInvitedTodayAlready` | 结束时这位陪伴者今天是否已经邀请过（true / false；无效会话为 null） |
| `briefPrSkippedByCap` | 有效但因每日上限没邀请 |
| `briefPrInvited` / `briefPrStatus` | 邀请了 / 记了 `due_not_invited`（方便查） |

## 3. Brief PR 邀请规则（登记表 C14）

代码：`lib/features/brief_pr/data/brief_pr_scheduler.dart`（规则）、`brief_pr_record.dart`（记录）、`brief_pr_store.dart`（存取）、`brief_pr_v2.dart`（页面接入）。

1. 只在**有效会话结束后**判一次；聊天中不邀请；没有主动评价入口。
2. 每位陪伴者**每个本地日**最多 `briefPrDailyCapPerAgent`（1）次；跳过、过期的也算用掉一次。超过的：不建评分记录，只在会话行标 `briefPrSkippedByCap: true`。
3. 会话以 `crisis` 结束、或危机处置中：建一条 `finalStatus = due_not_invited`、`dueNotInvitedReason = crisis` 的记录，不出卡，也不占当天名额。
4. `close_button` / `back` / `switch_agent` / `submitted` 结束 → 「搵人傾」列表页卡 S10a。`timeout` / `recovered` 结束 → 下次打开列表页卡 S10b。邀请时 App 还没进列表页就被杀掉的，下次打开也按 S10b 显示。
5. 距该次会话**最后一条完整回复**超过 2 小时未答 → `expired`；1:59、2:00 仍显示，2:01 过期（有测试）。
6. 卡上「今次唔評」= `skipped`；「好呀」进问卷：四题都答 = `completed`；答了一部分放弃 = `partially_completed`；一题未答就放弃 = `skipped`。
7. 记录文档编号 = 会话编号，写入用 merge：后台、断网、崩溃后再提交只会覆盖同一条，而且已经有最终状态的记录不再改（第一次的答案为准）。断网时 Firestore SDK 排队重试，App 侧另外重试 3 次。
8. 评分不写进聊天、不进记忆、陪伴者不回应。记忆写入时点没变：会话结束时（`RollingSummaryCompiler.compileAtSessionEnd` / `memoryEndSession`）就交给记忆，不等评分——核对了四个 Hybrid 页面，没有一个等 Brief PR。阿珍回忆页**不按儲存就离开**时现在也不交记忆，靠服务器 30 分钟 sweep 兜底（原有行为，未改）。

### 3.1 Brief PR 记录字段 `users/{uid}/brief_pr/{sessionId}`

| 字段 | 含义 |
|---|---|
| `schemaVersion` | 3（旧弹窗记录是 2、自动编号，照旧可读，不改） |
| `scheduleVersion` | 2 |
| `uid`、`sessionId`（= 文档编号，另有 `sessionRef` 同值）、`agentId`、`agentDisplayName`（小欣 / 阿珍 / 阿伯 / 通通） | 谁、哪次、哪位 |
| `sessionType`、`endReason`、`sessionEndedAt`、`lastReplyAt` | 从会话抄来 |
| `invitedAt`、`invitedDayKey`（本地日 `YYYY-MM-DD`，上限按它数） | 邀请时间 |
| `inviteChannel` | `list_page` / `catch_up`，显示时按实际渠道回写 |
| `everShown`、`shownAt` | 卡是否出现过、第一次出现时间 |
| `ratedAt` | 评分 / 跳过时间 |
| `finalStatus` | `completed` / `partially_completed` / `skipped` / `expired` / `due_not_invited`；待答时为 null（“展示未答”只是过程状态） |
| `dueNotInvitedReason` | `crisis` / `system_error` |
| `understanding`、`validation`、`caring`、`insensitivity` | 四题 1–7 原始分，不反转；没答的为 null |
| `arm` | A / B |
| `studyWeek` / `studyDay` | **没有**，等 T24 的函数（见第 9 节） |

## 4. 界面

| 项目 | 做法 | 文字 |
|---|---|---|
| 收尾按钮 | 四个聊天页（小欣 A、阿珍回忆 A、反思对话、通通）AppBar 左上角，开关开才出现；返回键 / 手势照旧可用 | S9「今日傾到呢度」逐字 |
| 首次说明 | 每次启动后第一次出现按钮时 SnackBar 一句 | `【占位】撳「今日傾到呢度」就係今次傾完；想再傾隨時返嚟。` |
| 评价卡 | `lib/features/brief_pr/presentation/widgets/brief_pr_invite_card.dart`，放在 `talk_page.dart` 顶部，不遮挡陪伴者卡片、底部标签、返回；两个按钮 ≥48×48（放大字体到 2 倍有测试） | S10a / S10b 逐字；{陪伴者} 按 `ahJanAhBakVariant`；按钮「好呀」「今次唔評」 |
| S10b 时间 | 只用三种：当天 12 点前结束 → 今朝；前一天 18 点后 → 尋晚；12:00–17:59 结束（当天或前一天）→ 星期X 下晝 | 其余 → `【占位】早排`（见第 10 节） |
| 问卷 | `brief_pr_flow_page.dart`：一题一屏、标题 “1/4”、题干「今次傾偈」+ 原四句、七个整行选项（1 / 4 / 7 带原有锚点文字）、下一题和完成分开、左上返回上一题、底部放弃 | 「完成」沿用 App 原有；`【占位】下一題`、`【占位】返回`、`【占位】放棄評價` |

规则组签到 B、回忆 B：提交后不再弹窗，走同一个调度器，回到列表页出同一张卡（`rule_submission_flow.dart`）。

## 5. 每人每周有效会话数

没有现成的汇总表。导出 `usage_weekly`（`functions/blinding.js`，`includeUsageSummary`）多一列 `validSessionCount` = 该周 `sessions.isValid == true` 的行数（旧行没有 `isValid`，算 0）。T30 直接查：

```
users/{uid}/sessions where isValid == true and endedAt in [周一 00:00, 下周一 00:00)
```

按 `startedAt` 还是 `endedAt` 归周要研究侧定（`usage_weekly` 现在按 `startedAt`）。

## 6. `llm_calls` 会话编号

`proxyDeepSeek` 本来已收 `sessionId`（T31 加的），现在传给 `functions/llm_log.js`，每条 `llm_calls` 多 `session_id`（最长 128 字符；服务器自发的记忆抽取、转介判断为 null）。规则组不调用，无影响。单元测试 `functions/test/llm_log_test.js`。

## 7. 测试

| 任务文本第 13 条 | 测试文件 | 结果 |
|---|---|---|
| 收尾按钮结束 | `test/session_v2_recorder_test.dart`「close button / back」；`test/brief_pr_card_test.dart`「S9 close button」 | 通过 |
| 返回键 / 手势结束 | 同上「close button / back」（页面上两者都走 PopScope → `back`） | 通过 |
| 切换陪伴者结束 | `session_v2_recorder_test.dart`「switch companion」 | 通过 |
| 30 分钟超时 | 同上「idle 30 min」 | 通过 |
| 切 App 30 分钟内回来不结束；超过才结束 | 同上「app switch / lock screen = pause only」（20 分钟 / 31 分钟） | 通过 |
| 崩溃恢复 | 同上「crash recovery」（v2 行 → `recovered` + `isValid`；旧行 → `app_killed`；关着 → `app_killed`） | 通过 |
| 有效与否（每类、两组） | `test/session_rules_test.dart`（自由聊天、Hybrid 签到、Hybrid 回忆、规则组表单、配置项） | 通过 |
| 每日上限 | `test/brief_pr_scheduler_test.dart`「daily cap per companion」（同陪伴者 / 不同陪伴者 / 次日重置 / 跳过也算 / 配置 2 和 0） | 通过 |
| 补问和过期边界 1:59 / 2:01 | 同上「expiry」 | 通过 |
| 重复提交 | 同上「duplicate submission」；`brief_pr_card_test.dart`「a second flow … cannot overwrite」 | 通过 |
| 两组一致 | `brief_pr_scheduler_test.dart`「rule arm submission and Hybrid check-in go through the same path」（字段集合相同）；`session_rules_test.dart`「same rule object serves both arms」 | 通过 |
| 开关关 = 旧行为 | `brief_pr_scheduler_test.dart`「switch off」；`session_v2_recorder_test.dart`「switch off = pre-T25 behaviour」；`brief_pr_card_test.dart`「switch off … renders nothing」 | 通过 |
| 危机不邀请 | `brief_pr_scheduler_test.dart`「crisis」 | 通过 |
| 文字逐字、48×48、1/4 | `brief_pr_card_test.dart` | 通过 |
| `llm_calls.session_id` | `functions/test/llm_log_test.js`「T25」 | 通过 |
| `usage_weekly.validSessionCount` | `functions/test/blinding_emulator_test.js` | 见下 |

整套（结果填在 PR 和返回值里）：`flutter analyze --no-fatal-infos --no-fatal-warnings`、`tool/ci_flutter_tests.sh`（六套）、`flock /tmp/firebase-emulator.lock tool/ci_backend_tests.sh`。

**截图：没有。** 原因：早前的截图做法要 `flutter build web` + Playwright，本任务时间先给规则和测试；widget 测试里渲染出的 PNG 没有中文字体（方块），不能用。要补的话按 `docs/dev-reports/T33-final-copy-20261010-screenshots/t33_screens_main.dart` 的方式做一个入口，用 `InMemoryBriefPrStore` 喂一张卡（`BriefPrCardHost(scheduler: …)`）就能截。

## 8. 改了哪些文件

- 新：`lib/core/session/session_rules.dart`；`lib/features/brief_pr/data/brief_pr_record.dart`、`brief_pr_store.dart`、`brief_pr_scheduler.dart`、`brief_pr_v2.dart`；`lib/features/brief_pr/presentation/pages/brief_pr_flow_page.dart`；`lib/features/brief_pr/presentation/widgets/brief_pr_invite_card.dart`、`brief_pr_card_host.dart`、`session_close_button.dart`；`test/session_rules_test.dart`、`test/brief_pr_scheduler_test.dart`、`test/session_v2_recorder_test.dart`、`test/brief_pr_card_test.dart`。
- 改：`lib/core/config/phase_b_config.dart`（8 个键）；`lib/core/session/chat_session_recorder.dart`（`SessionEndReason` 移到 `session_rules.dart` 并转出；v2 计数、30 分钟、`switch_agent`、`recovered` 分类、`patchSession`）；`lib/features/brief_pr/data/rule_submission_flow.dart`；四个聊天页 `check_in_arm_a.dart`、`reminiscence_arm_a_page.dart`、`tung_tung_page.dart`、`reflective_dialogue_page.dart`（收尾按钮、结束原因、v2 分流，各 ~30 行）；`lib/features/talk/presentation/pages/talk_page.dart`（卡）；`lib/app/app.dart`（sweep 接调度器）；`functions/llm_log.js`、`functions/index.js`（`session_id`）；`functions/blinding.js`（`validSessionCount`）；`functions/test/llm_log_test.js`、`functions/test/blinding_emulator_test.js`。
- 文档：`docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`（第 6.0 节、第 8 节、`app_config/phase_b` 行）、`docs/history.md`、`docs/dev/backlog.md`（第 97–99 项）、本报告。
- 没改：`firestore.rules`（`users/{uid}/brief_pr`、`sessions` 已被 `users/{uid}/{collection}` 规则覆盖，本人读写）；安全检测；prompt；`docs/spec/`。

## 9. 和其他 PR 的交叉

| PR | 交叉 |
|---|---|
| T21 `fix/phase-config-split` | **已在 main**，本分支已合并（e851205），无冲突。T21 改了 `functions/index.js`、`lib/core/memory/memory_mode.dart`，和本任务的改动不在同一处 |
| T34 `feat/safety-alert-email` | 可能同改 `functions/index.js`、四份文档；合并时保留两边 |
| T36 `chore/apk-phase-b-templates` | 不碰同一文件，只有文档 |
| T37 `fix/onboarding-settings` | `lib/app/app.dart`（本任务改了 `_onAuthUidChanged` 4 行）、文档 |
| T24（未开）| `brief_pr` 要加 `studyWeek` / `studyDay`，等 T24 的函数；T28、T29、T30 依赖本任务的 `isValid` / `finalStatus` |

## 10. 要 Junyu 定的事

| 事项 | 选项 | 建议 |
|---|---|---|
| 规则组表单页的结束方式写 `submitted` 还是归入 `close_button` | A. `submitted`（现做法，分析时一眼看出是表单）；B. `close_button`（严格按 C16 六种） | A，并在 C16 加一行说明 |
| 问卷里一题未答就「放弃」算什么 | A. `skipped`（现做法）；B. 另设 `abandoned` | A |
| 收尾按钮首次说明 | A. 每次启动后第一次显示一次（现做法）；B. 只显示一次（要加本地存储依赖或在用户文档写标记） | 开关打开前定；建议 B，另开小任务 |
| 阿珍回忆页的 S9 | A. 按 S9 = 走小结 + 儲存（现做法，保证能成为有效会话）；B. S9 直接结束不存小结（会让大多数回忆会话无效） | A（S9 行为不变）。**10/15 另定**：Hybrid 回忆有效改按条数（≥3 条有回复），`hybridReminiscenceValidRequiresSave` 默认 false（1014e 第 2 节第 7 条） |
| 问卷 2、3、5、6 分没有文字锚点 | A. 只显示数字（现做法，和原弹窗一致）；B. 研究侧给七档文字 | **已定 A**（10/14 第 11 条 (5)，`dev-tasks-1014e.md` 第 2 节第 2 条） |
| `【占位】` 文字定稿 | 下一題 / 返回 / 放棄評價 / 首次说明 / S10b 其余时间说法（第 11 节） | **已定稿**（10/15，1014e 第 2 节第 8 条）：「下一題」「上一題」「唔評住」；首次说明沿用草稿原文；S10b 一律「頭先」。已写进 `docs/spec/copy/short-texts.md` S10b、S10c |
| 每人每周有效会话按 `startedAt` 还是 `endedAt` 归周 | — | 建议 `endedAt`，和 `isValid` 同一时刻写 |
| 决策记录编号 | 第 12 节草稿 | 开发窗口分配后落盘 |

## 11. 要带回研究侧的发现

1. **S10b 时间说法覆盖不到的情况**（2 小时过期前提下只剩两类）：① 当天 18:00 后结束、当天打开（例如 20:30 聊完、22:00 打开）——没有“今晚”说法；② 跨到次日但前一天 18:00 前结束的（例如前一天 17:30 结束、次日 00:30 打开，已过期，极少见）。现在这些显示 `【占位】早排`，请给说法（如「今晚」）。
2. Hybrid 回忆“按儲存才有效”意味着：老人聊了半小时但没按儲存就返回 = 无效会话、不邀请 Brief PR，也不立即交记忆。请确认这是想要的口径，或把 `hybridReminiscenceValidRequiresSave` 设为 false（改为按条数）。
3. 自由聊天“3 条有回复”里，fallback（模型超时的固定句）不算回复：网络差的老人会更难达到有效会话。
4. 每日上限按本地日 00:00 重置，不是“24 小时内”。
5. 旧的弹窗式 Brief PR 记录（`schemaVersion: 2`）和新记录（3）字段不同，分析脚本要分开读。
6. 规则组和 Hybrid 组都用同一张卡、同一套时点，但触发门槛不同（表单一次提交 vs 聊天 3 条），决策 0015 的 Methods 说明仍然适用。

## 12. 决策记录草稿（编号待开发窗口分配）

- 日期：2026-10-14
- 状态：草稿
- 影响范围：phase_b、pilot × 两组
- 相关代码：`lib/core/session/session_rules.dart`、`lib/features/brief_pr/data/brief_pr_scheduler.dart`、`brief_pr_gate.dart`、`brief_pr_page.dart`

**背景**：Brief PR 原来在离开聊天页时弹窗，老人用户发言 ≥2 轮就弹；每位陪伴者第一次弹出没有「跳过」（anchor），以保证至少一份数据。产品窗口 10/8–10/10 定了新规则（C14、C16）：只在有效会话后、列表页出卡、每天一次、可跳过。

**决定**：
1. 新规则全部在 `app_config/phase_b.sessionBriefPrV2Enabled` 后面。开关关着：旧弹窗路径（`BriefPrGate` / `BriefPrPage`）和 anchor 规则原样保留。开关打开：旧路径不再执行。
2. anchor 规则在新版里**取消**：每张卡都有「今次唔評」。理由：每天一次 + 卡片不打断聊天，已经把负担压到最低；强迫作答与“可随时拒绝”的伦理口径不一致，也会让第一份评分带有被迫的偏差。
3. 开关打开并稳定一周后，删除旧路径代码和 `sessions.briefPR` 子字段的写入（backlog 第 98 项）。
4. 新旧行用 `sessions.scheduleVersion`（1 / 2）、`brief_pr.schemaVersion`（2 / 3）区分，分析时按版本分别处理。

**考虑过的其他方案**：保留 anchor（第一次不能跳过）——被否，理由如上；新旧两套同时跑按人切换——被否，分析口径会乱。

**后果**：对研究：Methods 要写明 Brief PR 的触发条件从“≥2 轮、离页弹窗”改为“有效会话、列表页卡、每陪伴者每天 1 次”，以及生效日期；对开发：四个聊天页仍各自接一次结束流程（见第 13 节）。

## 13. 架构优化观察（不在本任务改）

| 观察 | 位置 | 一句话建议 |
|---|---|---|
| 六个聊天 / 表单页各自重写一遍“会话结束 → 记忆 → Brief PR”流程，本任务又在四个页面各加了约 30 行同样的分流 | `check_in_arm_a.dart`（1170 行）、`reminiscence_arm_a_page.dart`（1140 行）、`tung_tung_page.dart`（1340 行）、`reflective_dialogue_page.dart`（840 行）、`check_in_arm_b.dart`、`reminiscence_arm_b_page.dart` | 抽一个 `ChatSessionScope` / `SessionEndFlow` 包住页面：PopScope、收尾按钮、idle、switch、记忆交接、Brief PR 调度全在一处，页面只提供 `agentId`、`moduleId` 和几个标记 |
| 页面把聊天 UI、LLM 调用、安全路由、记忆、日志、Brief PR 都放在一个 State 里，单文件 800–1300 行 | 同上 | 按“消息列表 + 输入框”“发送管线”“结束流程”拆成三个类；先从通通页开始 |
| `PhaseAConfig` 与 `PhaseBConfig` 两份配置，很多键实际是全局的（`safetyClassifierEnabled`、`sessionIdleTimeoutMin`） | `lib/core/config/phase_a_config.dart`、`phase_b_config.dart` | Phase A 暂停后合成一份 `StudyConfig`（T21 报告也列了），按键注明适用范围，而不是按文件分 |
| Brief PR 有新旧两套数据模型并存（`BriefPrResponse` v2 自动编号 / `BriefPrRecord` v3 按会话编号） | `lib/features/brief_pr/data/` | 开关打开稳定后删 v2 路径（backlog 第 98 项） |
| `ChatSessionRecorder` 既是会话状态机，又是 Firestore 写入器，又是分析事件发送器，还带静态的 `sweepUnclosed` / `patchSession` | `lib/core/session/chat_session_recorder.dart`（约 800 行） | 拆成纯状态机（可测）+ `SessionStore`（Firestore）；本任务的 `SessionRules` / `SessionTally` 已经是纯的那一半 |
| 陪伴者显示名（阿珍 / 阿伯）在每个页面各自解析一次 | 各页面 `resolveVariant(profile.ahJanAhBakVariant)` | `AgentRegistry.displayName(agentId, profile)` 一个入口 |
| 导出里 `usage_weekly` 由 `blinding.js` 顺手算，没有服务器端汇总 | `functions/blinding.js` | T30 做过程数据导出时把会话汇总挪到独立模块 |
