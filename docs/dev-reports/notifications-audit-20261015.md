# 通知与问卷排查：A1–A15 在 emulator 的结果（10/15）

按 `docs/dev-tasks/notifications-audit-1015.md` 第 4 节 A 部分做。分支 `docs/notifications-audit-1015`，从 `main` @ 74888af（已含 #85、#90、#92、#94）开出。只用 emulator 和合成数据。

## 1. 结论

- **A1–A11、A14、A15 全部通过**，服务器端固化成 `functions/test/notifications_audit_emulator_test.js`（8 条，以后每次 CI 都跑）。A12、A13 由已有的 Flutter 测试覆盖，A13 补了一句断言。
- 开关都开着时，PILOT 老人收到的推送只有：第 7、14、21、26、35、42、49 天晚上 8 点各一条、没答完 24 小时后提醒一条，再加周一到周六 19:00 的每日广播。10/18 星期日没有旧广播、没有旧横幅。
- 五个 [待核] 都按代码答了（第 3 节）。
- 有两处和排查文件写的不一样，要带回研究侧（第 4 节）：W4 有三部分不是两部分；提醒时间是「推送真正发出后 24 小时」，不是固定第 8 天 20:00。

## 2. A1–A15 逐条

合成账号：PILOT Hybrid（`ph`，W0 10/15）、PILOT 规则组（`pr`，W0 10/15）、PB（`pb`，W0 10/19）、未登记（`ux`）、测试员（`ut`）。开关：`weeklyScheduleV2Enabled`、`socialContactProbeEnabled`、`sessionBriefPrV2Enabled`、`djgW2InAppEnabled` 都为 true。时间按 PILOT 研究日推进。

| # | 结果 | 怎么核的 |
|---|---|---|
| A1 | 第 1–6 天每天 19:00、20:00 跑排程：没有每人推送，`weekly_status` 没有记录。每日广播是 topic `all`，按代码每天一条（见第 3 节第 1 问） | emulator |
| A2 | 10/18（PILOT 第 3 天）20:00：PILOT 两人、PB、测试员都**不是**旧周日提醒的对象；未登记账号是（登记门关着时）；登记门开了以后谁都不是。App 内的日历周横幅：开关开着时 `pending_prompts_service.dart` 整段让位给研究周，前提是手机上的包含 T24（10/14 之后的 main） | emulator + 代码 |
| A3 | 第 7 天 19:00 没有；20:00 PILOT 两人各一条，标题「陪住」，正文 S14「今個禮拜嘅問卷開咗，得閒入嚟答幾條。」，`kind: weekly_bundle_push`；四部分 DJG、Weekly PR、PGIC、S12；窗口到第 10 天 20:00。PB（第 -4 天）、未登记、测试员没有。页面标题「每週問卷」、四个部分名、「未開始」、首页卡「一共 N 部分，可以分開做」由 `weekly_bundle_flow_test.dart` 和 `pending_prompts_banner.dart` 定稿文字核对 | emulator + Flutter |
| A4 | `ph` 第 7 天答完 DJG 和 Weekly PR。第 8 天 19:00 不到 24 小时没有；20:00 提醒一条「仲未答完」，事件 `weekly_bundle_reminder_sent` 的 `parts` = pgic、social_contact。状态字「已完成 / 未開始」由 Flutter 测试核对 | emulator + Flutter |
| A5 | 第 9 天两次、第 10 天 19:59：没有第二条提醒、没有缺失。第 10 天 20:00：`ph` 的 pgic、S12 和 `pr` 的四部分各写一份 `status: missed`、`missed: true`，已答的部分不动；第 11 天以后什么都不发。`ph` 的事件恰好三条：push_sent、reminder_sent、missed | emulator |
| A6 | 第 14 天 10:00 T18 的 `djgW2Dispatch` 返回 `supersededByWeeklyScheduleV2`，一条不发；20:00 W2 一条，四部分含 DJG | emulator |
| A7 | 第 21 天 W3 含 DJG；第 26 天 W4 = Weekly PR、PGIC、**S12**（没有 DJG），窗口到第 30 天 00:00；第 29 天 23:00 还开着，第 30 天 08:00 记缺失 | emulator |
| A8 | 第 35、42、49 天各一条，只有 PGIC；首页卡「只有一條問題，好快答完。」在 `pending_prompts_banner.dart` | emulator + 代码 |
| A9 | 第 56、63 天什么都不发（T35 未做） | emulator |
| A10 | 22:30 跑：安静时段**拦下不发**，计 `quiet_hours`，`weekly_status` 不写；07:30 仍拦；08:00 发出。是延后，不是丢弃 | emulator |
| A11 | `quietHoursEnabled: false` 的账号 22:30 照发 | emulator |
| A12 | S10a / S10b 文字、按钮「下一題」「上一題」「唔評住」、首次说明只弹一次（本机存储）、`schemaVersion` 3、补问卡 2 小时过期：`brief_pr_card_test`、`session_close_hint_test`、`session_v2_recorder_test`、`brief_pr_scheduler_test`，80 条全过 | Flutter |
| A13 | 规则组回忆页提交区上方「講完呢段往事，你而家心情點？唔揀都可以。」，不选心情也能提交：`rule_reply_pages_test`（本次加一句断言），19 条全过 | Flutter |
| A14 | 测试员账号第 7 天起从没收到任何每人推送 | emulator |
| A15 | 推送文字：`PUSH_BODY`、`REMINDER_BODY` 没有占位（断言）。全仓库还带【占位】的只剩：Phase A 的第 7 日问卷（`ada.js` 推送、`day7_flow_page`、`ada_items` 三道开放题，只给 `cohort: phase_a`，Phase A 已暂停）；T18 第 2 周 DJG 的推送（`djg_w2.js`，V2 开着时不跑，T21 对 pilot 也跳过）；语音失败提示 S6 的**英文**版（`voice_copy.dart`，粤语版已定稿）。开关开着时没有一条占位文字能到 PILOT / PB 老人面前 | grep |

另外加了两条不在清单上的：PB 账号按自己的 W0 推（第 7 天 = 10/26）；**补发规则**：窗口还开着的问卷，错过整点也会在下一个整点发出；窗口关了只记缺失，不补发。

## 3. [待核] 的答案

1. **每日广播排不排除测试账号**：不排除。`dailyMoodReminder` 发 topic `all`，手机登录后就订阅这个 topic（评估员账号除外，`suppressForStaff`）。topic 没法按人排除，测试员、未登记的人都收到。只有每人推送（研究周、提醒、告警）才看 `isTester`。
2. **`pushHour` 用不用在研究周**：用。`app_config/phase_b.weeklyPushHour`（默认 20）决定每个推送日的开窗时刻，窗口从那一刻起算 3 × 24 小时。
3. **`m7FollowupPushEnabled` 默认**：关。在 `app_config/reminders` 文档，只认 `true`。没建这份文档就是关。
4. **`weeklyProbeEnabled` 在 Phase B 账号**：都是假。它是每人字段，模型默认 false，登记流程不写它，只有手工在控制台改才会变真。
5. **`usageEventsEnabled` 位置**：`app_config/feature_flags`。
6. **A10 延后还是丢弃**：延后到安静时段结束后的第一个整点（默认 08:00）。

## 4. 要带回研究侧的发现

1. **W4 有三部分**（10/15 Junyu 定：要 S12，代码不动）：代码里 S12 在 W1–W4 都有（`social_contact_probes/{W1…W4}`，architecture 第 8 节也这样写），排查文件 A7 写的是「W4 只有 Weekly PR 和 PGIC」。哪个对要按方案定；要去掉 W4 的 S12 是一行改动。
2. **提醒时间跟着实际发出的时间走**（10/15 Junyu 同意按代码，排查文件 A4 已改）：提醒 = 推送真正发出后 24 小时。正常情况就是第 8 天 20:00。但要是推送被安静时段推迟到第 8 天 08:00，提醒就是第 9 天 08:00；关了安静时段的人推送 22:30 发出，提醒却要到第 9 天 08:00（22:30 没有整点跑）。排查文件 A4 写死「第 8 天 20:00」，建议改成「推送后 24 小时的下一个整点」。
3. **今天 iPhone 包用的是哪个 commit 要记下来**。App 端 A3、A12、A13 的定稿文字在 #82、#90 里，10/15 中午后的 main 才有；T24 的横幅让位在 10/14 的 main 才有。包要是早于 #90（8c36e80），老人会在每周问卷页看到【占位】标题、回忆页看到草稿。
4. 开关位置的纠正已在 `1014e-app-name-20261015.md` 第 3 节：`sessionBriefPrV2Enabled` 要在 `app_config/phase_b`；`feature_flags` 的四个还没设。
5. 每日广播发给所有装了 App 的设备这一点和排查文件第 2 节第 3 条一致，没有改法，记下即可。

## 5. 改了什么

| 文件 | 改动 |
|---|---|
| `functions/test/notifications_audit_emulator_test.js` | 新增，8 条，CI 随其他 `*_emulator_test.js` 一起跑 |
| `test/rule_reply_pages_test.dart` | 回忆 B 页加一句 S13 文字断言 |
| `docs/dev-tasks/notifications-audit-1015.md` | 排查文件放进仓库 |

不改任何代码行为。
