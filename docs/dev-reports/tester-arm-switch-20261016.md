# 测试员自切组别：做了什么、查到的缺口（2026-10-16）

> 分支 `claude/gifted-bardeen-yhizmk`，PR 草稿。决策草稿 `docs/decisions/0049-tester-arm-self-switch.md`（编号待 Junyu 给）。只用了 emulator 和合成帐号。

## 1. 结论

- 测试员帐号（`isTester`）现在可以在「測試員工具」里自己切 Hybrid 组／规则组，切完整个 App 和服务器**立即**按新组走；Hybrid 组有跨次记忆，切去规则组不删，切回来还在。
- **默认关**：要先在控制台把 `app_config/feature_flags.testerArmSwitchEnabled` 设成 `true`。关着时测试员看得到这一块，但按钮灰掉并写明原因。
- **参与者一律不变**：分组只能由登记和 `correct_arm_assignment.js` 改；参与者调用这个函数会被拒，什么都不写。`firestore.rules` 没放宽。安全检测、热线没动。

## 2. 怎样用

1. 管理员：`tool/set_tester.js --uid=… --tester=true`；控制台开 `testerArmSwitchEnabled`。
2. 测试员：设定 →「關於同支援」→ 点版本号 7 次 → 输 TESTER_PIN →「測試員工具」→「切換組別（只限測試員帳號）」→ 按「Hybrid 組」或「規則組」。
3. 要看出两组分别，用 Phase B 包（`PHASE_B=true`）。Phase A 包界面一律是 Hybrid 组（块里会写明）。

## 3. 改了哪些

| 地方 | 改动 |
|---|---|
| `functions/tester_arm.js`（新） | 切组逻辑：检查 `isTester` → 检查开关 → 一个事务里改 `users`（和已有的 `enrollments`）、写 `arm_assignment_log` 一行 `action: "tester_switch"`（uid、from、to、at、by） |
| `functions/index.js` `setTesterArm` | asia-east2 onCall；守门照抄 `sendTestPush`；切完让本实例忘掉缓存 |
| `functions/index.js` `armFor` | 测试员的组别**不缓存**（每次现读）；参与者照旧 10 分钟 |
| `functions/memory.js` `inScope` | 加一条：`isTester && arm === "A"` 视同正式 Hybrid 组（仍看总开关、`phaseBArmA`、撤回记忆）；规则组照旧 false |
| `functions/index.js` `memorySweep` | 多查「Arm A 的测试员」，和 `inScope` 对齐 |
| `functions/weekly_schedule.js` | 每周问卷推送：切过组的测试员照常排程，其他测试员照旧跳过 |
| `tool/purge_tester_data.js` | 切过组的测试员（有 `cohort: "pilot"` 但没登记）仍算测试员，可以清理 |
| App `MemoryModes` | Phase B 包里 Arm A 测试员走 `phaseB` 模式（和试跑 Hybrid 老人一样）：「我記得嘅嘢」页、跳过 v0 摘要都走同一条路 |
| App `AuthService.reloadProfile` | 从服务器重读帐号，切组后放进 `AppSettings`，`Arm.of` 和所有 `ArmGate` 立即重画 |
| App 设定页 | 測試員工具里加切组块（PIN 解锁且 `isTester` 才显示） |
| App 研究员面板 | 「Participants / Arm A / Arm B」人数不再算测试员 |

## 4. 第 4 点：测试员没有 cohort／w0Date 时少了什么，怎么补

`enrollParticipant` 拒绝测试员（`randomization.js` 两处 `tester_account`），所以由 `setTesterArm` 在缺的时候补上：`cohort: "pilot"`、`armAssignmentMode: "pilot_designated"`（加 `armAssignmentMethod`）、`w0Date: 今天（香港）`，另写 `armAssignedBy: "tester_switch"` 作标记。**不写 `enrollments`、不给研究编号。**

| 功能 | 补之前（测试员没登记） | 补之后 |
|---|---|---|
| 服务器记忆 v1 | 只有 `memory_enabled` 才有 | Arm A 就有；`memorySweep` 也会收尾 |
| App 记忆模式 | Phase B 包里是 v0（关） | 和试跑 Hybrid 老人一样（v1） |
| 每周问卷（App 卡片） | 没有 cohort，不显示 | 显示（还要 `weeklyScheduleV2Enabled` 开） |
| 每周问卷（服务器推送、提醒、过期标记） | 跳过测试员 | **已改**：切过组的测试员照常推；状态行 `researchId: null` |
| 研究周／第几天 | 按帐号建立日 | 按 `w0Date`（第一次切组那天） |
| 使用事件（T40） | 规则要 cohort，写不进 | 写得进（`researchId: null`），导出按 `isTester` 排除 |
| 登记门（T21） | 测试员本来就放行 | 不变 |
| 入组问卷录入（T47） | 拒绝测试员 | 仍拒绝（要研究编号）——测试员走不了研究员录入，属预期 |
| ADA（Phase A） | Phase A 包里按建立日显示 | 切过组后服务器不再当它是 Phase A 参与者（`ada.isPhaseAParticipant`）。Phase B 包本来不显示 ADA，不受影响；在 Phase A 包里测 ADA 请用没切过组的测试员 |
| W2 DJG（`djg_w2`） | 只给 `phase_b` | 不变（试跑老人也没有），一致 |
| 行动计划 | 只按组显示 | 不变，切组即生效 |
| 引导「介紹三個夥伴」 | — | `onboardingAfterEnrollmentFix` 开、帐号已有配对但没完成标记时可能再走一次引导；属边缘情况，不影响参与者 |

## 5. 研究数据仍然排除测试员（已核对）

| 地方 | 怎样排除 |
|---|---|
| `tool/analysis_export.js` | `isPhaseB` 里 `if (u.isTester === true) return false;`（另外 cohort 不是 `phase_b` 也排除） |
| `functions/blinding.js`（每周盲法导出） | `isBlindedParticipant` 里排除 `isTester`，并计数 |
| `functions/process_export.js` | 用同一个函数排除，并计数 |
| `tool/check_blinded_export.js` | 只检查导出文件里的字段，不看人；导出本身已排除测试员 |
| 评估员名单、结局完成率（`assessor.js`）、运营看板（`ops_dashboard.js`） | 只列 `enrollments` 里的人；切组从不写 `enrollments`，测试员不会出现 |
| App 研究员面板人数 | **原来没有排除**，本 PR 已改 |
| `arm_assignment_log` | 不进任何导出；`tester_switch` 行可按 `action` 区分 |

## 6. 验收（emulator）

- `functions/test/tester_arm_emulator_test.js`：8 项全过——切 A 后立即通过 `assertLlmAllowed`，切 B 后立即被拒并写 `llm_denied_log`；参与者被拒、`users`／`enrollments` 不变、无日志行；未登录、开关关／非 `true`、错组别都拒；字段只在缺时写、`strataCell` 不动、已有 `enrollments` 跟着改、每次一行 `tester_switch`；切 A 后一次聊天写入 `mem_facts` 和 `mem_summaries`，切 B 再切回 A 记忆仍在并重新注入；每周推送只推切过组的测试员。
- `test/tester_arm_switch_test.dart`（假 backend，默认包和 `PHASE_B=true` 都跑）：PIN 没解锁不显示；非测试员不显示；测试员按钮调用后 `Arm.of` 立即变；失败显示原因；开关关时按钮不可按。
- `tool/ci_backend_tests.sh`、`tool/ci_flutter_tests.sh` 全过（`randomization`、T19／T21 相关测试未改）。

## 7. 要注意

- 切过组的帐号**不要再去掉 `isTester`**：它会变成一个没有研究编号的试跑帐号（会收推送、有记忆）。要删就用 `tool/purge_tester_data.js`。
- `inScope` 的新条件对所有 Arm A 测试员生效（不只切过组的）。在 **Phase A 包**里，App 走 v0、服务器又注入 v1，会重复；参与者包都是 Phase B 包，不受影响。测记忆请用 Phase B 包。
- 没做：不改参与者分组、`correct_arm_assignment.js`、`firestore.rules` 的 `arm` 限制、热线、安全检测、IAM、`feature-registry.md`；没跑 Deploy Firebase。
