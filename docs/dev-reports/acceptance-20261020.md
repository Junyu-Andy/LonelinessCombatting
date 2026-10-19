# 10/21 冻结前验收记录（dev-tasks-1020）

每批一节，每项一行「过／不过」。「开发」是 emulator 和合成账号上的自动测试和截图；「手机」是 Junyu 用两组测试账号走一遍。

## 第 1 批：后台和设定（C、B、H、I、J、第 1 节）

报告：`T50-T60-batch1-20261019.md`。截图：`acceptance-20261020-shots/`。

| 项 | 内容 | 开发 | 手机 |
| --- | --- | --- | --- |
| B | 「保留對話紀錄」不显示（#125 已合并，开关默认关） | 过（`transcript_retention_switch_test`） | 待测 |
| B | 核对报告：代码部分 | 过（报告第四节） | — |
| B | 核对报告：哪些账号关掉了 | 待 Junyu 跑脚本 | — |
| C | v2 上传、RCT-01 从 v2 第 1 位取组、新 PB- 被拒、v1 不变、只读脚本两版都列 | 过（`randomization_emulator_test` 21 项、`t30_server_emulator_test` 8 项、`check_prelaunch_values` 在 emulator 上列出 v1／v2） | 待测（RCT-TEST 只按「檢查」） |
| C | RCT- 标 `rct`；所有 cohort 判断读同一份清单；防漏测试 | 过（`cohort_list_guard_test`、`study_period_test`） | — |
| C | 非测试员 RCT- 账号走完全周程（登记门、LLM、写数据、第 7/14/21/26 天问卷、W2 DJG、第 56 天、三个导出）；PB- 不受影响 | 过（`rct_cohort_emulator_test` 6 项；规则测试 197 项） | — |
| C | 导出加 allocatedArm、receivedArm、sequenceVersion、runIn、analysisSet | 过（`analysis_export_emulator_test`） | — |
| H | 第一层没有高对比、安静时段、今日休息、保留开关；高对比在「我的設定」→「顯示」 | 过（`app_settings_persistence_test`、两组截图） | 待测 |
| H | 服务器：安静时段固定开，忽略旧的「关」；忽略今日休息 | 过（`quiet_hours_test`、`reminders_emulator_test`、`weekly_schedule_emulator_test`、`notifications_audit_emulator_test`） | — |
| H | 今日休息用过几次 | 待 Junyu 跑脚本 | — |
| I | 开关关着时没有麦克风按钮 | 过（`voice_stt_test`、`phase_b_flags_test`） | 待测（控制台已改 false，1020b） |
| J | 研究员录入页说明和代码一致 | 过 | — |
| 第 1 节 | 只读核对脚本（含 1020b 加的语音转写次数） | 过（`readonly_check_1020_emulator_test`） | 待 Junyu 跑 |
| 1020b 二 | #126 四个开关进开关表和上线检查；两个开关的四个问题 | 过（报告第十节） | — |
| 1020c 一 | 两个开关定开：建议页不用掉小欣的跟进；字号开关打开时字不变小；规则组建议页不变 | 过（`memory_emulator_test` 24 项、`suggestions_use_profile_test`、`text_scale_cap_test`、`app_settings_persistence_test`） | 待测（开两个开关：手机字号调大的手机字不变小；Hybrid 组建议页叫得出名字；规则组建议页照旧） |
