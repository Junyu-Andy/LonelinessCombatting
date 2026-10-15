# 1014e 第 2 节第 1 条：每周有效会话按 `endedAt` 归周（2026-10-15）

分支 `fix/usage-weekly-endedat`，从 main `e6926df` 开。PR 草稿。依据：`docs/dev-tasks/dev-tasks-1014e.md` 第 2 节第 1 条（10/14 第 11 条 (4)）。只改服务器导出和文档；只用模拟器。

## 结论

1. `usage_weekly`（两处：盲法导出 `functions/blinding.js`、过程数据导出 `functions/process_export.js`）改为按**会话结束时间** `endedAt` 归周、归日；没有 `endedAt` 的行（T25 之前的旧行、还没结束的会话）退回 `startedAt`。整行三个数（`sessionCount`、`validSessionCount`、`activeDays`）用同一个时间，避免一行里两种口径。行上多一列 `weekBasis: "endedAt"`，分析脚本一看就知道。
2. 影响只在跨香港时间周一 00:00 结束的会话（例如周日 23:50 开始、周一 00:10 结束 → 算下一周）。T39 看板本来就按结束时间（`ops_dashboard.js` 有效会话按 `endedAt` 归日），现在三处一致。
3. 登记表 C16 “有效会话”条目补一句“按结束时间归周”，由产品窗口改。

## 改了什么

| 文件 | 改动 |
|---|---|
| `functions/blinding.js` | `sessionWeekAnchor`、`USAGE_WEEK_BASIS`；`usage_weekly` 用结束时间；导出两个符号 |
| `functions/process_export.js` | 同上 |
| `functions/test/blinding_test.js` | 新 1 项：结束时间优先、退回开始时间、坏值为 null |
| `functions/test/blinding_emulator_test.js` | 加一条周日 23:50 开始、周一 00:10 结束的会话：W41 两条（退回 `startedAt`）、W42 一条 |
| `functions/test/t30_server_emulator_test.js` | 期望行加 `weekBasis` |
| 文档 | `STUDY_CHANGELOG.md` 一行；`architecture.md` 第 6.0 节一行 + 顶部核对；T25 报告第 5、10 节标已定；`history.md`；本报告 |

## 测试

| 测试 | 结果 |
|---|---|
| `node functions/test/blinding_test.js` | 见下 |
| `blinding_emulator_test.js`、`t30_server_emulator_test.js` | 见下 |
| ESLint（改动的四个文件） | 0 问题（`t30_server_emulator_test.js` 原有两条超长行不是本 PR 的） |
| `tool/ci_backend_tests.sh` | GitHub CI |

## 要 Junyu 定的事

无。

## 要带回研究侧的发现

1. 10/15 之前已经导出过的 `usage_weekly` 文件是按开始时间的；重新导一次即可（导出是幂等的，按日期目录存）。
2. `activeDays`（有会话的天数）也跟着改按结束时间，和 T39 看板的“当天有效会话”一致；“当天是否打开”仍按 T40 前台事件，和会话无关。
