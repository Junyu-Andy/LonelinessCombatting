# 0042：试跑账号走正式的每周问卷排程，不再用压缩排程

- 日期：2026-10-15
- 状态：已采纳（负责人 10/15 口头定；10/15 确认编号 0042；代码 PR #92 已合并）
- 影响范围：pilot × 两组（每周问卷的推送日、窗口、周数）
- 相关代码：PR #92（`fix/pilot-standard-schedule`）：`functions/weekly_schedule.js` `scheduleModeFor`、`lib/core/scheduling/weekly_schedule.dart` `modeForCohort`
- 取代：T24 报告（`docs/dev-reports/T24-weekly-schedule-20261014.md`）第 2 节「排程（试跑）」和第 9 节「试跑压缩时其他按日期出现的环节」。

## 背景

T24 给试跑设计了压缩排程（第 1、3、5、7 天推、1 天窗口、没有第 5–7 周），目的是几天内把整套流程跑一遍。10/15 负责人定试跑流程和正式完全一样，推送都按 Phase B 正常走。

## 决定

- `cohort: pilot` 的账号和 `phase_b` 用同一张排程表：第 7、14、21、26 天 20:00 推、3 天窗口、第 35、42、49 天只推 PGIC、W4 到第 29 天结束；`scheduleMode` 记 `standard`。
- 压缩排程的代码和配置键（`pilotBundleDays`、`pilotWindowDays`）保留，不再对应任何 cohort，只有共用表测试在用。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 在控制台把 `pilotBundleDays` 改成 [7, 14, 21, 26]、`pilotWindowDays` 改成 3 | 压缩模式还是没有第 5–7 周，W4 关窗规则也不同，不是「完全一样」 |
| 删掉压缩排程代码 | 以后要再压缩试跑要重写；留着只占两行映射 |

## 后果

- 对研究：试跑老人第 7 天才有第一次问卷；试跑期间验证不了第 5–7 周。试跑记录按正式排程写。
- 对开发：改回去只需改两行映射。
- 对论文：无。
