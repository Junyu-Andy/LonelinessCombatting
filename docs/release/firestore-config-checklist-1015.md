# Firestore 配置核对表（10/15）

按 `main` 的代码列出**每一份代码会读的配置文档和每个键**：默认值（文档或字段不存在时的行为）、现在该设成什么、谁在读。给 Junyu 在 Firebase 控制台逐项对。布尔值一律要是布尔类型，字符串 `"true"` 当关。

先说结论：
- **三处要改**：`app_config/feature_flags` 补四个开关；`sessionBriefPrV2Enabled` 搬到 `app_config/phase_b`；`app_config/phase_a` 里的三个测试值删掉。
- **三处 10/19 前必须确认**：`meta/memory_config`（Hybrid 组的记忆靠它）、`meta/randomization_config.enabled`（登记 PB 靠它）、`meta/alert_config`。
- 其余没列「建议」的，不动。

## 1. `app_config/feature_flags`（App 和服务器都读；只认 `true`；没有文档 = 全关）

| 键 | 默认 | 现在设 | 作用 |
|---|---|---|---|
| `onboardingAfterEnrollmentFix` | 关 | **true** | T37：登记后先走伙伴介绍、兴趣、S5，再进首页。关着这三页整段跳过 |
| `voiceInputEnabled` | 关 | **true** | 语音输入（T27 服务器转写）。粤语失败提示已定稿；英文版仍占位，老人用不到 |
| `usageEventsEnabled` | 关 | **true** | T40：App 记录打开、前台、后台事件；看板「当天是否打开」靠它 |
| `opsDashboardEnabled` | 关 | **true** | T39：研究员登记页的「營運看板」入口和三个服务器函数 |
| `enrollmentGateEnabled` | 关 | 关；**10/19 第一位 PB 登记前改 true** | T21 登记门：没登记、不是测试账号的人只看到等待页。开之前把团队和评估员账号设 `isTester: true` |
| `assessorViewEnabled` | 关 | 关；11/9 前改 true | T30 评估员视图和 W4 名单、录入函数 |
| `outcomeCompletionSummaryEnabled` | 关 | 关；和上面一起开 | T30 研究员后台的完成率汇总 |
| `webSearchEnabled` | 关 | 关（没定就不动） | 通通「幫我查」（只 Hybrid 组） |
| `searchOffReplyEnabled` | 关 | 关 | 搜一搜关着时通通的固定一句，文字未定稿 |
| `replyFeedbackEnabled` | 关 | 关 | Phase B 包里回复旁的点赞点踩，关着隐藏 |
| `week1NudgeEnabled` | 关 | 关 | Phase B 包里第 3、6 天「你仲未同 X 傾過」提示，关着隐藏 |
| `memoryLayersNoticeEnabled` | 关 | 关 | T31 记忆分层的说明页，和 `meta/memory_config.layersEnabled` 配套 |
| `sessionBriefPrV2Enabled` | — | **删掉** | 放错位置，代码不读这里。见第 2 节 |

## 2. `app_config/phase_b`（`PhaseBConfig`；服务器 `weekly_schedule.js`、`djg_w2.js` 也读）

| 键 | 默认 | 现在设 | 作用 |
|---|---|---|---|
| `sessionBriefPrV2Enabled` | 关 | **true** | T25：收尾按钮、评价卡、一题一屏；关着是旧弹窗 |
| `weeklyScheduleV2Enabled` | 关 | true（已设） | T24 研究周每周问卷总开关 |
| `socialContactProbeEnabled` | 关 | true（已设） | 每周问卷第四部分 S12（W1–W4） |
| `weeklyPushHour` | 10（10/20 第 98 条起；之前 20） | **10**（10/20 第 96 条，Junyu 已改生产） | 只在 `weeklyReminderV2Enabled` 关时用：每周问卷的推送钟点和 72 小时窗口的起点。开着时（正式设置）不读：第 1–7 周都是当天 00:00 开、10:00 推（第 5–7 周 PGIC 从第 98 条起也一样） |
| `weeklyBundleDays` / `weeklyWindowDays` / `week4CloseDay` / `djgWeeks` / `pgicOnlyDays` | [7,14,21,26] / 3 / 29 / [1,2,3] / [35,42,49] | 不动 | 排程表。`weeklyWindowDays` 3 = 提醒 v2 开时整 3 天（第 1–3、5–7 周：开放日到第三天 23:59），关时 72 小时；`week4CloseDay` 只在提醒 v2 关时用 |
| `djgW2ReminderHours` | 24 | 不动 | 提醒间隔（T18 旧的第 14 天 DJG 用；研究周每周问卷只在提醒 v2 关时用，开着时每周的提醒都在固定日子 10:00） |
| `sessionIdleTimeoutMinV2` | 30 | 不动 | V2 的会话闲置超时 |
| `briefPrDailyCapPerAgent` / `briefPrCatchUpExpiryHours` / `freeChatValidMinUserMessages` / `hybridCheckInValidRequiresMood` / `hybridCheckInValidMinUserMessages` / `hybridReminiscenceValidRequiresSave` | 1 / 2 / 3 / true / 1 / false（#82 起） | 不动 | 有效会话和邀请规则 |
| `djgW2InAppEnabled`、`djgW2DayOffset`、`djgW2WindowDays`、`djgW2PushHour` | 关 / 14 / 7 / 10 | 不动 | T18 旧的第 14 天 DJG；V2 开着时整个让位 |
| `pilotBundleDays`、`pilotWindowDays` | [1,3,5,7] / 1 | 不动，已作废（0042） | 只剩测试在用 |

## 3. `app_config/phase_a`（`PhaseAConfig`：App 运行参数的远端覆盖，**Phase B 包也读**）

控制台截图（10/15）里有三个字段，都是测试时留下的，**建议删掉这三个字段**（整份文档删了也行，不建就用默认值）：

| 键 | 现在的值 | 默认 | 后果 |
|---|---|---|---|
| `sessionIdleTimeoutMin` | 1 | 10 | 只在 `sessionBriefPrV2Enabled` 关着时用。V2 一旦关掉，老人停 1 分钟就算会话结束、弹旧评价。删 |
| `w2DayOffset` | 0 | 14 | Phase A 第 2 周卡片的天数。V2 开着时被研究周取代；留着是隐患。删 |
| `week1NudgeDays` | [1] | [3, 6] | Phase B 包里这个提示已隐藏（`week1NudgeEnabled` 关）。删 |

其余键没出现在控制台就是默认值，不用建：`transcriptRetentionDefault`（true）、`sharedContextUseDefault`（true）、`enforceSharedContextConsent`（true，服务器也读）、`briefPRItemCount`、`briefPRMinTurns`、`w2WindowDays`、`weeklyPrPushHour`、`weeklyPrCloseWeekday`、`hotlineFilterClient`、`safetyClassifierEnabled`、`safetyClassifierTimeoutMs`、`safetyScanAllInputs`。

## 4. `app_config/reminders`（服务器）

| 键 | 默认 | 现在设 | 作用 |
|---|---|---|---|
| `m7FollowupPushEnabled` | 关 | **要 Junyu 定** | 通通页老人自己订的行动计划到时推一条「你今日有個小計劃，得閒打開睇下。」（S4a，决策 0022）。关着老人订了也不会收到提醒 |
| `quietHoursStart` / `quietHoursEnd` | 22:00 / 08:00 | 不动 | 安静时段窗口 |
| `maxAttempts` / `staleHours` | 默认 | 不动 | 提醒重试 |

## 5. `app_config/usage_copy`（App）

决策 0028 的 7 处「使用频率」文字覆盖。没有文档 = 显示原文。不用建。

## 6. `meta/memory_config`（服务器；客户端不能读写）**10/19 前必须确认**

| 键 | 默认 | 现在设 | 作用 |
|---|---|---|---|
| `enabled` | **关** | **必须 true** | 记忆总开关。关着 Hybrid 组没有任何记忆，和方案不符 |
| `phaseBArmA` | 关 | **必须 true** | Phase B / 试跑的 Hybrid 组强制开记忆（不看每人的 `memory_enabled`） |
| `policy` | 默认 | 不动 | 共享策略 |
| `layersEnabled` | 关 | 关（T31 没定） | 记忆分层 |
| `excludeSafetyTurns`、`omitSensitiveSummary`、`honourForgetRequests`、`deleteSummaryWithItem`、`honourMemoryWithdrawal`、`sensitiveFactQuota`、`strictFactValidation` | 开（只认 `false` 关） | 不动 | T10 修复 |
| `forgetAckReply` | 关 | 不动 | 老人说「唔好記」时的确认一句 |
| `extractionPrompt` | 默认版本 | 不动 | 抽取 prompt 版本 |

## 7. `meta/randomization_config`（服务器）**10/19 前必须确认**

| 键 | 默认 | 现在设 | 作用 |
|---|---|---|---|
| `enabled` | **关** | **true**（登记 PB 前） | 关着 `enrollParticipant` 拒绝登记（`disabled`）。试跑账号也走这个函数，所以现在应该已经是 true，对一眼 |

另外分配序列要已经由 Calvin 上传（`uploadRandomizationSequence`），两个分层各一条，没有序列登记 PB 会失败。

## 8. `meta/alert_config`（服务器）**10/19 前必须确认**（1014e 第 1 节第 5 条）

| 键 | 默认 | 现在设 |
|---|---|---|
| `enabled` | 关（没有文档 = 急性级只发到 `PI_EMAIL` 密钥） | **true** |
| `primaryEmail` | — | Junyu 的地址 |
| `backupEmail` | — | **不设**（决策 0041） |
| `escalateAfterHours` | 默认 | 不动 |

建好后用 `isTester: true` 的测试账号触发一次急性级事件，收到邮件才算完成。

## 9. `meta/safety_config`（服务器）

没有文档 = 热线规则和热线过滤都开，分类器关。不用建。`classifierEnabled` 默认关，要开另有 T8 的 URL 和超时配置。

## 10. `meta/blinding_config`（服务器）

`enabled`、`includeBriefPr`、`includeUsageSummary`、`processExportEnabled`、`outcomeExportPaused` 都默认关。周导出给 Calvin 的时候再开（T30）。现在不用建。

## 11. 不用管的

- `app_config/phaseA_schedule`：只属于 Phase A，Phase B 包不读。
- `app_config/arm_assignment`、`meta/arm_counter`：T19 起停用。
- `meta/data_lock`：T30 锁库时才建。

## 12. 不在 Firestore 里但一起核的

- Functions 密钥：`PI_EMAIL`（Junyu）、DeepSeek 密钥、SMTP。
- 团队和评估员账号 `users/{uid}.isTester: true`（登记门开之前；现在只能用 `tool/set_tester.js` 或控制台改，App 里改不了）。
- 评估员账号的 Auth custom claim `blinded`、Junyu 的 `unblinded`。
