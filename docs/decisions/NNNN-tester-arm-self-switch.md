# NNNN：测试员帐号可以在 App 里自己切换 Hybrid 组／规则组（编号待 Junyu 给）

- 日期：2026-10-16
- 状态：提议中
- 影响范围：只影响 `isTester` 帐号，不影响任何 cohort（pilot / phase_b 的参与者都不变）× 两组
- 相关代码：PR 草稿，分支 `claude/gifted-bardeen-yhizmk`；`functions/tester_arm.js`、`functions/index.js` `setTesterArm`

## 背景

团队要在同一部手机上把两个版本都走一遍，包括 Hybrid 组的跨次记忆。以前改组只能用 `tool/correct_arm_assignment.js`（要管理员、要理由，按登记记录改），而且测试员通常没登记，切到 Hybrid 也没有记忆。服务器的分组缓存 10 分钟，改完还要等。

## 决定

1. 新的服务器函数 `setTesterArm`（asia-east2）：只有登入且 `users/{uid}.isTester === true` 的帐号能用，只能改自己；开关 `app_config/feature_flags.testerArmSwitchEnabled`（**默认关**）。
2. 它用管理员权限改 `users/{uid}.arm`（`enrollments/{uid}` 有就跟着改），并在 `arm_assignment_log` 记一行 `action: "tester_switch"`（uid、from、to、at、by 本人）。不动 `strataCell` 和分配序列。
3. 缺什么补什么，让测试员像试跑老人一样走完整流程：没有 `cohort` 写 `"pilot"`，模式不是正式／试跑写 `"pilot_designated"`，没有 `w0Date` 写今天；`armAssignedBy` 写 `"tester_switch"` 作标记。不写 `enrollments`、不给研究编号。
4. 测试员的组别服务器不缓存，切完下一次调用就生效；参与者照旧缓存 10 分钟。
5. 记忆 v1 对 Arm A 的测试员打开（和正式 Hybrid 组同一条件：记忆总开关、`phaseBArmA`、撤回记忆都照旧）；切到规则组只是停用，不删，切回来还在。
6. 每周问卷推送：切过组的测试员（有 `tester_switch` 标记）照常排程；没切过的测试员和以前一样不推。
7. 研究数据照旧按 `isTester` 排除；研究员面板的人数和两组人数也不再算测试员。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 继续用 `correct_arm_assignment.js` | 要管理员在电脑上跑、要登记记录，测试员没有；而且有 10 分钟缓存 |
| 放宽 `firestore.rules`，让测试员客户端自己写 `arm` | 分组字段只有服务器能写是 T19 的防线，不能为测试开口子 |
| 用 `FORCE_ARM` 打调试包 | 只改界面，服务器仍按旧组放行或拒绝 AI；正式包不能带 |
| 用登记函数给测试员登记成 `PILOT-` | 会占研究编号、进评估员名单和运营看板，污染研究数据 |
| 写进 `pilot_assignment_log` | 任务指定 `arm_assignment_log`；两份日志都不进导出，行里有 `action: "tester_switch"` 可区分 |

## 后果

- 对研究：参与者的分组、记忆、推送、导出都不变；不影响操纵定义、测量和两组对等。测试员帐号带上 `cohort: "pilot"` 后，`tool/purge_tester_data.js` 仍把它当测试员（已改）。如果以后有人把一个切过组的帐号的 `isTester` 去掉，它会变成一个没有研究编号的试跑帐号——不要这样做，要删就用清理脚本。
- 对开发：服务器一个新函数和一个新文件；`armFor`、`memory.inScope`、`memorySweep`、`dispatchWeeklyBundles`、清理脚本各改一处；App 测試員工具加一块、`AuthService.reloadProfile`、记忆模式加一条。
- 对论文：不用写。测试员不是参与者。
