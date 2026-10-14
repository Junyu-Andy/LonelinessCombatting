# 设置页「語音讀出內容」隐藏、「安靜時段」接成真功能（2026-10-14，编号待开发窗口分配；SPEC:C17、C19）

分支 `fix/quiet-hours-hide-readback`，从 main `a8ab92e`（含 #65）开。依据：负责人 10/14 核对 W0 流程发现两个开关没有功能（backlog 97），并定了做法：语音读出隐藏，安静时段"对应调整"。没有连生产 Firestore。

## 结论

1. 「語音讀出內容」那一行从设置页拿掉。偏好值（`notifications.voiceReadback`）仍保存在本机，以后接上 TTS 再显示。
2. 「安靜時段」变成真功能：开关除了存本机，还写到 `users/{uid}.quietHoursEnabled`（布尔；**缺字段 = 开**，和页面默认一致）。服务器按人发推送前调用 `inQuietHours`，在窗口内就先不发、下个 tick 再看。窗口做成配置 `app_config/reminders.quietHoursStart` / `quietHoursEnd`（香港时间 `HH:mm`），默认 `22:00`–`08:00`。
3. 现在接上的发送点：行动计划提醒（`functions/reminders.js` `dispatchOne`）。T24 正在做的每周问卷推送器已被告知要调用同一个函数。每日心情提醒和每周问卷提醒是广播（FCM 主题 `all`），按人过滤做不到，它们本来在 19:00、20:00 发，不在默认窗口内；T24 把推送改按人发之后就会受管。
4. 老人能感受到的：设置页少一行；默认窗口内不会收到按人发的推送。两组相同。页面上原来的说明文字「晚上 10 點到早上 8 點唔會出聲提醒。」没有改（它现在是真的）。

## 一、改了什么

| 文件 | 改动 |
|---|---|
| `lib/features/settings/presentation/pages/settings_page.dart` | 删掉「語音讀出內容」卡；「安靜時段」切换时另写 `users/{uid}.quietHoursEnabled`（`set` + `merge`，失败只记调试日志） |
| `functions/quiet_hours.js`（新） | `quietHoursConfigFrom` / `readQuietHoursConfig`（读 `app_config/reminders`，坏值退回默认）、`inQuietHours(user, now, cfg)`（香港时间，跨午夜窗口；起点含、终点不含；起点 = 终点视为关闭） |
| `functions/reminders.js` | `readConfig` 带上窗口；`dispatchOne` 对到期的提醒先查安静时段，窗口内返回 `null`（留到下个 15 分钟；超过 `staleHours` 仍按旧规则作废） |
| `functions/test/quiet_hours_test.js`（新） | 9 项：默认值、坏配置、缺字段 = 开、边界 22:00 / 08:00 / 21:59、白天不拦、开关关、同日窗口、零长窗口 |
| `test/app_settings_persistence_test.dart` | 设置页不再有「語音讀出內容」；其余断言照旧 |
| 文档 | `STUDY_CHANGELOG.md` 一行；`architecture.md` 三处；`history.md`；`backlog.md` 第 97 项改为已做 |

Firestore 规则不用改：`quietHoursEnabled` 是老人自己文档里的普通字段，规则本来允许本人写、不属于分组字段。

## 二、测试

| 测试 | 结果 |
|---|---|
| `node functions/test/quiet_hours_test.js` | 9/9 |
| `node functions/test/reminders_test.js` | 通过（原有） |
| `flutter test test/app_settings_persistence_test.dart` | 8 项通过 |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | 0 error（86 条旧提示） |
| ESLint（`quiet_hours.js`、`reminders.js`、新测试） | 0 问题 |
| 全套 | 由 GitHub CI 跑 |

## 三、和其他 PR 的交叉

- T24（`feat/weekly-schedule`，在做）：要 `require("./quiet_hours")`，已通知；若它先合并而本分支后合并，`functions/quiet_hours.js` 可能两边都加——内容相同则无冲突。
- 文档四件和 T24、T30、T27、T32 相邻，两边都留。
- 合并后需要部署 Functions（`reminders.js`）；App 要重新打包。

## 要 Junyu 定的事

1. 本改动的 T 号。
2. 默认窗口 22:00–08:00 是否合适（页面说明文字就是这两个时间）。
3. 语音读出以后要不要做（接 TTS 是新功能，要另开任务）。

## 要带回研究侧的发现

1. 登记表 C17 可补一句：推送按人发时遵守老人的安静时段（默认 22:00–08:00，可在设置关）。
2. 「語音讀出內容」已从设置页拿掉；W0 不介绍。
