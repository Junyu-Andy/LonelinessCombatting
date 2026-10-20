# 开发窗口交接 1020g（10/20 下午）：Fable 审查后的修正、评估员分工的开发项

依据：Fable 审查 11 个草稿 PR 的第二版结论（试合并分支 `review-merge`，按 #134 → #127 → #128 → #131 → #133 → #132 → #135 → #137 → #136 → #130 → #138 合并）；decisions-log 10/20 第 55、56 条；claude/开发窗口交接-1020f.md；claude/冻结流程-1020.md。

共同规则：(1) 不推 main，只开 PR 草稿；(2) 不碰生产数据，只用 emulator 和合成数据；(3) 新行为放在开关后；(4) 老人看得到的文字只写草稿；(5) 不改热线号码；(6) 不读、不改、不删序列、randomization_state、分配日志和 correctArm 记录。

Fable 的结论：没有阻断冻结的问题。两处要手工解的合并冲突（#137 对 #132 在 `functions/index.js`；#137 对 #133 在 `chat_session_recorder.dart`）在 `review-merge` 上已解好，合并 main 时可以照搬。解完后 Functions 单元测试、规则测试 246 项、模拟器测试 38 份都过。

## 一、冻结前修（按修 bug 处理，两组相同，不加开关）

(1) 测试过时：`functions/test/reminiscence_chapter_test.js:800`。#127 把安静时段改成所有人固定开，这条“老人关掉安静时段 → sent”的断言合并后必红。预期改为 `quiet_hours`，或删掉这段断言。
(2) 提示词包 hash：#133 和 #137 各自重生成了 `lib/core/version/build_info.g.dart`，合并后 hash 过时，`test/phase_a_version_pin_test.dart` 会红。最后合并的人重跑 `tool/export_spec_inputs.py` 并提交。
(3) 上线检查脚本 `tool/check_prelaunch_values.js`：
(a) `weeklyReminderV2Enabled` 列了两次（:35 和 :73），结论矛盾，删 :73。
(b) 补上没列的开关：`homeLayoutV2Enabled`、`moodRowV2Enabled`、`keyboardCompactHeaderEnabled`、`htmlReadersEnabled`、`researcherIntakeGateEnabled`。
(c) 期望值：`researcherIntakeGateEnabled` 为 true（10/20 第 54 条）；其余等 Junyu 冻结时定（第 56 条 (3)），先放占位。
(4) 自称“AI”的残留：`siu_yan_chat_page.dart:172` 客户端后备提示词还写「你叫小欣，係一個 AI 機械人」。对齐 `check_in_arm_a.dart:80–82` 的写法：「電腦程式夥伴」，加「唔好用 AI……」一句（10/16 第 5 条 (2)）。
(5) 小篇章推送：`reminiscence_chapter.js:972` 还读 `quietTodayActivatedAt`。今日休息已拿走（10/19 第 14 条 (3)），服务器其他地方已忽略它（`reminders.js:196`、`index.js:1513`），删这两行。
(6) PGIC 首页卡副标题：`pending_prompts_banner.dart:270–273` W5 至 W7 单推 PGIC 的卡还写「同上週比較……」，同一行夹英文「companion」。改成 #138 在 `settings_page.dart:384–387` 用的那句，W1 至 W8 用同一套说法（10/20 第 50 条）。
(7) 首页问卷一行：`today_todo_rows.dart:329` 调 `openBundleAt` 时不传 `week4RecordedOn`，而且只取第一个开放的问卷包。结果有两个：W4 面访记录后，这一行仍显示到第 42 天；W4 答完后，第 35 天 W5 的 PGIC 退成「下次開放」，旧卡又被 `hideWeeklyBundle` 藏掉，W5 在第一页找不到。改用 `openBundlesAt(..., week4RecordedOn)`，取第一个未完成的，做法同 `pending_prompts_service.dart:272`。首位 RCT- 的第 35 天约在 11/25；冻结前改不完，就冻结后按修 bug 改，记偏离日志。

## 二、冻结后修（按修 bug 处理，记偏离日志）

(1) 小篇章里的热线：`reminiscence_chapter_card.dart:133` 用普通 Text 显示服务器替换出的「【緊急熱線】」，老人看到的是这几个字，不是危机页链接。改用 `RichChatText`。
(2) 误触续问的“当天”：App 端 `_findResumable` 用设备本地日期（`mood_recorder.dart:36`），服务器盖章用香港日期（`false_alarm.js:90`）。统一用香港日期。
(3) 闸门开关读不到时：`researcher_intake_gate.dart:150、261`，离线第一次打开读不到开关时，等待超时后显示等待页（fail-closed）。研究员在场可以解锁，只写进 W0 流程的出错处理，不改代码。
(4) 注释：`functions/index.js:1786–1790` 注释写 P2 跳过问卷推送日，代码不跳；代码符合 1020e 一 (8)，只改注释。
(5) main 原有的残留，先报告能不能到达，再定改不改：
(a) `check_in_arm_a.dart:370–378` 旧心情字「好辛苦／麻麻地」，只在 `moodRowV2Enabled` 关时可达。
(b) `greeting_hero.dart:150–162` 旧心情板的 Hybrid 专属弹窗，只在 `moodRowV2Enabled` 关时残留。所以 `homeLayoutV2Enabled` 和 `moodRowV2Enabled` 冻结时必须同开，请写进上线检查脚本的说明。
(c) `education_library.dart:164、418、533` 正文里有「生命熱線 2382 0000」等号码。请确认这几页 Phase B 里能不能打开。能打开就报告，号码不改。
(d) `agent_diff_page.dart:780`「或者用講嘅」不受语音开关管，是 Phase A 旧页。请确认 Phase B 构建里到不到得了。

## 三、要 Junyu 定、定了再做

(1) 急性中断后当天再进小欣页：`siu_yan_chat_page.dart:312–321`。check-in 因急性中断、Junyu 没标误触时，老人当天再进小欣页会从 Q0 重新做一轮 check-in；服务器已经把当天算作做过。等 Junyu 选：
(a) 当天不再开始 check-in，直接进普通聊天，用 SY0 开场；Junyu 标了误触，才从停下的那题接着问（产品窗口建议）；
(b) 维持现在的做法。
(2) 登记表 C 项「小篇章来源与推送」还标【待确认】：Hybrid 组由模型写、写好推送；Rule-based 组即时排版、不推送。这是 10/19 第 42 条和 1020d 定下的组间差异，产品窗口建议在登记表改为已确认。等 Junyu 一句话确认。

## 四、评估员分工带来的开发项（10/20 第 55 条）

(1) 评估员账号：Maria（Keria Yichun Xiu）、Mingyan Wang、Yu Jiang、Keran Wang 四个账号设 blinded 角色，`isTester` 设 true。由 Junyu 在控制台做，冻结前做完（冻结流程第四节 (4)）。
(2) `assessorViewEnabled` 在 11/9（PILOT 第 25 天）前打开。
(3) 评估员视图录入纸本结局时，记录录入人（`enteredBy`）和时间，供 Keran Wang 核对 [待核：现有代码是否已经记录]。Keran Wang 只读核对，看不到组别、Brief PR、Weekly PR 和使用量。
(4) W4 到期名单要包括两位 PILOT 和 run-in 四人（PB-01 至 04），名单行照旧不带组别 [待核：10/19 第 28 条加了 cohort 标记后，名单是不是只取 `rct`]。11/9 前。
(5) 给第二编码员的编码导出：研究编号换成随机码，对照表另存，只给 Junyu；导出不含组别。最后一位 W4 之后才用，12 月底前合并即可。

## 五、请回报

(1) 第一节七项分别在哪个 PR，冻结的构建里有没有；(2) 第二节 (5) 四处能不能到达；(3) 第四节 (3)(4) 两个待核的结果。
