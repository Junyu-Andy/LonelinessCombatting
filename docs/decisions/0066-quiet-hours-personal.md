# 0066：「安靜時段」回到「我的設定」，老人自己定开始和结束时间（在允许范围内），两组相同

- 日期：2026-10-20
- 状态：提议中（Junyu 10/20 深夜定：做，进 10/21 冻结构建；允许范围【待 Junyu 定，先按这个做】）
- 影响范围：phase_b、rct、pilot × 两组；所有逐人推送
- 相关代码：分支 `claude/zealous-fermat-8rgqtg-quiethours-1020o`；`functions/quiet_hours.js`、`functions/reminders.js`、`functions/index.js`（`dispatchReminders` 时间）、`firestore.rules`、`functions/usage_events.js`；App：`lib/core/notifications/quiet_hours_range.dart`（新）、`lib/features/settings/presentation/widgets/quiet_hours_card.dart`（新）、`lib/features/settings/data/quiet_hours_store.dart`（新）、`settings_page.dart`（`MySettingsPage`）、`user_profile.dart`、`usage_event_recorder.dart`、`app_settings.dart`、`auth_gate.dart`

## 背景

10/19 第 14 条 (2) 把安静时段改成所有人固定开（22:00–08:00），设定页的开关拿走了。Junyu 10/20 深夜改为：老人可以自己定时间，但不能关，也不能把研究推送盖住。研究推送在 08:30（P1）、10:00（每周问卷）、19:00（P2），所以允许的范围要避开这三个时间。

## 决定

1. 「自己 → 我的設定」加一项「安靜時段」：一句「呢段時間 App 唔會彈出通知。」和两个选择「由」「到」。默认 22:00 到 08:00。**没有开关**。
2. 允许范围（【待 Junyu 定，先按这个做】）：「由」20:00–23:00，「到」06:00–08:00，每半小时一格。选择框只列出这些时间。范围写在三处，内容一样：App `quiet_hours_range.dart`、服务器 `quiet_hours.js` 的 `RANGE`、`firestore.rules` 的两张表；三处不一致时测试会失败。
3. 存在 `users/{uid}.quietHoursStart`、`quietHoursEnd`（香港时间 "HH:mm"）。每次只写改动的那一项。个人资料的其他保存不带这两项，所以不会抹掉，也不会被旧值盖回。
4. 服务器 `inQuietHours()`：先看本人的值（一项一项看），没有就用 `app_config/reminders` 的全局值（默认 22:00–08:00）。本人的值超出范围，按最近的边界算；格式不对就当没有。`firestore.rules` 只接受选择框里的那些值，删除也拒绝。
5. 安静时段内的逐人推送照旧等到时段结束再发。计划提醒的派发由每天 08:00–21:45 改为 06:00–22:45（每 15 分钟），这样个人时段 06:00 结束或 23:00 才开始时也能准时；时段内的提醒按「时段结束」算过期（12 小时），20:00–08:00 这种 12 小时的时段也不会丢提醒。没有设过的人，结果和以前完全一样（派发程序正常运行时；它停了几个小时才恢复的话，夜里的提醒以前可能算过期，现在照发）。
6. 每次改动记一条使用事件 `quiet_hours_changed`（改的是「由」还是「到」、原来的时间、新的时间、手机时间）。过程数据，两组相同，需 `usageEventsEnabled` 开、已入组。
7. 旧的开关残留删掉：手机上的 `notifications.quietHours` 值和登录时把它同步到 `users/{uid}.quietHoursEnabled` 的代码（服务器 10/20 起已不看这个字段）。

## 哪些推送跟个人时段

| 推送 | 现在 |
|---|---|
| 计划跟进提醒（`dispatchReminders`） | 跟个人时段；时段内等到结束再发 |
| P1 08:30、P2 19:00（`daily_checkin_push.js`） | 跟个人时段；但允许范围永远盖不到 08:30 和 19:00，所以实际上照常发 |
| 每周问卷推送和提醒（`weeklyBundleDispatch`，10:00；旧路径整点） | 跟个人时段；时段内留到下一次整点 |
| 小篇章写好推送（`reminiscence_chapter.js`，只 Hybrid） | 跟个人时段；时段内不推（和以前一样，App 里照样显示写好了） |
| 19:00 全体广播（`checkInChatV2Enabled` 关时的旧路径）、周日 20:00 广播（`weeklyScheduleV2Enabled` 关时的旧路径） | 主题广播，**不能逐人过滤**。这两个开关现在都开着，所以不会发 |
| 周日 20:00 逐人旧提醒（只给没被每周排程覆盖、登记门关时的账号）、W2 DJG 10:00、Phase A ADA 第 7 天 | 不看安静时段（以前也不看）；正式参与者收不到前一个，后两个在 10:00 或 Phase A |

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 范围只放在 `app_config/reminders`，App 和规则都去读 | 规则每次写都要多读一次文档，App 离线时读不到；冻结前改动太大 |
| 让老人完全自由选时间 | 会盖住 08:30、10:00、19:00 的研究推送 |
| 写个人资料时把两个值一起带上（`toMap`） | 另一台手机或旧页面保存资料时可能把新值盖回旧值 |
| 提醒派发时间不改 | 个人时段 06:00 结束的人要等到 08:00 才收到；23:00 开始的人 22:00–22:45 收不到 |

## 后果

- 对研究：两组完全相同；研究推送时间不受影响。逐人推送的到达时间对设了个人时段的人可能不同（提早或推迟到他自己的时段结束），这是参与者自选的设置，需要时可以从使用事件和 `users` 文档还原。
- 对开发：部署 `firestore.rules` 和 Functions（`dispatchReminders` 的时间表改了），新 App 包。
- 对论文：方法部分「推送」一句可写「参与者可在 20:00–23:00 和 06:00–08:00 之间自定安静时段，研究推送时间不受影响」。
