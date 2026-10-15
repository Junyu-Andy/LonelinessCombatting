# 10/15：试跑账号改走正式的每周问卷排程（PR 草稿）

分支 `fix/pilot-standard-schedule`，从 `main` @ 8c36e80（已含 #90）开出。**急：要在 `weeklyScheduleV2Enabled` 打开前合并并部署。**

## 1. 结论

- Junyu 10/15 定：试跑流程和正式一样，推送都按 Phase B 正常走。
- 代码里 `cohort: pilot` 原来仍是 T24 的压缩排程（第 1、3、5、7 天推、1 天窗口、没有第 5–7 周）。现在服务器和 App 各改一行，`pilot` 走正式排程：第 7、14、21、26 天 20:00 推、3 天窗口、第 35、42、49 天只推 PGIC、W4 到第 29 天结束。
- 两组相同；开关关着时无任何变化。

## 2. 改了什么

| 位置 | 改动 |
|---|---|
| `functions/weekly_schedule.js` `scheduleModeFor` | `cohort === "pilot"` 返回 `standard`（原 `pilot`） |
| `lib/core/scheduling/weekly_schedule.dart` `modeForCohort` | 同上。首页卡片、待答提示、问卷页都从这里取模式 |
| `lib/core/config/phase_b_config.dart` | 注释：`pilotBundleDays` / `pilotWindowDays` 作废，只供共用表测试 |
| 压缩排程的代码（`MODE_PILOT`、`WeeklyScheduleMode.pilot`、共用表 `pilot` 段） | 保留不删，没有任何 cohort 再映射到它 |

## 3. 测试

- `functions/test/weekly_schedule_test.js` 12/12（模式映射改为 `standard`）。
- `functions/test/weekly_schedule_emulator_test.js` 10/10：W1 时间线里试跑账号和 Phase B 账号同一天推、同一天提醒、同一天记缺失；原「试跑第 1、3、5、7 天」测试改成「第 1、3、5 天什么都没有、第 7 天和 Phase B 同一条推送、同一个窗口」。
- Flutter：`weekly_schedule_test`、`weekly_bundle_flow_test` 通过；`flutter analyze` 0 error。
- 只用模拟器和合成数据。

## 4. 要带回研究侧的发现

1. **现有试跑老人**（10/13–14 登记）：按正式排程，他们的 W1 推送在登记后第 7 天 20:00（约 10/20–21）。开关要在那之前打开，否则 W1 窗口过了就不补推，只会记缺失。前提仍是 10/19 的包先装到手机。
2. **开关中途打开的补记**：服务器只回看 7 天，试跑老人的 W1 要是在开关打开前已经关窗，会记一条缺失。按上面的时间排，不会发生。
3. **决策记录**：这是设计层面的决定（推翻 T24 的试跑压缩排程），决策记录草稿见第 5 节，编号等 Junyu 分配后落盘。
4. T24 报告第 9 节「试跑压缩时其他按日期出现的环节」随之作废。

## 5. 决策记录草稿（编号待分配）

- **标题**：试跑账号走正式的每周问卷排程
- **状态**：提议中（Junyu 10/15 口头已定）
- **背景**：T24 给试跑设计了压缩排程（第 1、3、5、7 天），目的是几天内把整套流程跑一遍。10/15 Junyu 定试跑流程和正式完全一样。
- **决定**：`cohort: pilot` 的账号和 `phase_b` 用同一张排程表，`scheduleMode` 记 `standard`。压缩排程的代码保留，不再对应任何 cohort。
- **后果**：试跑老人要等第 7 天才有第一次问卷；试跑期间验证不了第 5–7 周。改回去只需改两行映射。
- **取代**：T24 报告第 2 节「排程（试跑）」和第 9 节。

## 6. 部署

合并后 Functions 部署一次，可和 #85 之后的部署合并；App 随 10/19 构建。
