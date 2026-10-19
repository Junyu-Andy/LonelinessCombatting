# 10/21 冻结前验收记录（dev-tasks-1020）

每批一节，每项一行「过／不过」。「开发」是 emulator 和合成账号上的自动测试和截图；「手机」是 Junyu 用两组测试账号走一遍。

## 第 1 批：后台和设定（C、B、H、I、J、第 1 节）

报告：`T50-T60-batch1-20261019.md`。截图：`acceptance-20261020-shots/`。

| 项 | 内容 | 开发 | 手机 |
| --- | --- | --- | --- |
| B | 「保留對話紀錄」不显示（#125 已合并，开关默认关） | 过（`transcript_retention_switch_test`） | 待测 |
| B | 核对报告：代码部分 | 过（报告第四节） | — |
| B | 核对报告：哪些账号关掉了 | 待 Junyu 跑脚本 | — |
| C | v2 上传、RCT-01 从 v2 第 1 位取组、新 PB- 被拒、v1 不变、只读脚本两版都列 | 未做（方案待批，报告第一节） | 待测 |
| C | 导出加 allocatedArm、receivedArm、sequenceVersion、runIn、analysisSet | 过（`analysis_export_emulator_test`） | — |
| H | 第一层没有高对比、安静时段、今日休息、保留开关；高对比在「我的設定」→「顯示」 | 过（`app_settings_persistence_test`、两组截图） | 待测 |
| H | 服务器：安静时段固定开，忽略旧的「关」；忽略今日休息 | 过（`quiet_hours_test`、`reminders_emulator_test`、`weekly_schedule_emulator_test`、`notifications_audit_emulator_test`） | — |
| H | 今日休息用过几次 | 待 Junyu 跑脚本 | — |
| I | 开关关着时没有麦克风按钮 | 过（`voice_stt_test`、`phase_b_flags_test`） | 待测（控制台先把 `voiceInputEnabled` 改成 false） |
| J | 研究员录入页说明和代码一致 | 过 | — |
| 第 1 节 | 只读核对脚本 | 过（`readonly_check_1020_emulator_test`） | 待 Junyu 跑 |
