# T43 PILOT 版本指定核对清单（emulator 试跑，2026-10-15 前，SPEC:C01、C19）

分支 `chore/t43-pilot-checklist`，从 main `c1f88d6`（含 #59–#76）开出。依据：`docs/dev-tasks/dev-tasks-1014c.md` 第 2 节 T43。T43 不是新功能（T21 已做），本任务**只加了一个测试文件和文档，没有改任何行为代码**。只用 Firestore 模拟器和合成数据、合成邮箱，没有连生产 Firestore，没有真的发信。

## 结论

**六句核对里五句通过，一句不过**：评估员账号看 W4 名单时确实看不到任何组别字眼，但三位 PILOT 老人**根本不在名单上**——现在的代码（T30）只把 `PB-` 的人放进 W4 名单。1014c 第 0 节要求 11/9（PILOT 第 25 天）前名单含 PILOT，这项改动还没有做，要另开任务（见「要 Junyu 定的事」第 1 项）。其余：登记三人、不占序列、三条日志、告警邮件、登记门，全部按预期。

## 1. 核对表（1014c 每一句 → 测试 → 结果）

测试文件：`functions/test/t43_pilot_checklist_emulator_test.js`，11 个步骤串成一条链，按 W0 当天的真实顺序跑。`tool/ci_backend_tests.sh` 用通配 `functions/test/*_emulator_test.js`，新文件自动纳入 CI。

| 1014c 原文 | 测试步骤 | 结果 | 看到了什么 |
|---|---|---|---|
| （前提）登记入口开着 | 1 | 通过 | `meta/randomization_config.enabled = true`；两层序列上传后指针 low = 0、high = 0；分配日志、试跑日志都是空 |
| 登记 PILOT-01、02（Hybrid）、03（规则组） | 2 | 通过 | 非盲研究员账号登记三个新 uid，各配一个阿珍/阿伯。每人 `users/{uid}`：`cohort = "pilot"`、`arm` = A / A / B、`w0Date` = 登记当天（香港日期）、`armAssignmentMode = "pilot_designated"`、`armAssignmentMethod = "pilot_designated_v1"`、`armAssignedBy = "researcher"`、**没有 `isTester` 字段**、没有 `strataCell`。`enrollments/{uid}`：`studyPeriod = "PILOT"`、`sequencePosition = null`、`stratum = null`、`w0DjgEmotional = null`。研究编号对照表两边都有 |
| 两层序列指针不动 | 3 | 通过 | 登记三人后 low、high 的 `next` 和第 1 步完全一样；`arm_assignment_log` 仍是 0 行。对照：第 5 步登记一个 `PB-901` 后指针恰好动了 1 |
| `pilot_assignment_log` 三条 | 4 | 通过 | 恰好 3 条，都是 `designate`：PILOT-01:A、PILOT-02:A、PILOT-03:B；有时间、操作人；没有 `stratum`、`sequencePosition` |
| 评估员账号看 W4 名单不显示版本 | 5a | **不过** | 打开 `assessorViewEnabled`，用 `blinded` 身份在 PILOT 第 25 天调名单函数（`functions/assessor.js` `dueList`）：**三位 PILOT 一个都不在名单上**，只有对照的 `PB-901`（第 25 天、窗口开放中）。原因：`assessor.js` `phaseBParticipants` 只查 `enrollments.studyPeriod == "B"`（T30 报告第 3.2 节写明"试跑 `PILOT-` 不在名单"）。1014c 第 0 节第 1 条改成"W4 名单含 PILOT"，代码还没跟上。测试把现状钉住（断言 PILOT 行数 = 0 并注明预期是 3），改完代码后这一行要反过来 |
| 同上（不显示版本的部分） | 5b | 通过 | 名单返回对象逐个键、逐个值、整段 JSON 字符串都查过：没有 arm / cohort / version / hybrid / rule / A 組 / B 組 / group_ / pilot_designated / randomise / strat / sequence，也没有单独的 "A" / "B"。每行只有 `researchId`、`windowStartDate`、`windowEndDate`、`studyDay`、`windowState`、`entered` 六个键。非盲研究员调这个函数被拒（`not_blinded`） |
| PILOT 账号触发一次测试告警，邮件发出 | 6a | 通过 | `meta/alert_config` = `{enabled: true, primaryEmail, backupEmail, escalateAfterHours: 12}`（T34 字段名）。PILOT-01（没有 `isTester`）写一条 acute `safety_events` → `onSafetyEventCreated` 跑完：`pi_alerts` 1 行（`alertVersion 3`、`isTester false`、`researchId PILOT-01`、`studyPeriod PILOT`、`studyDay 0`、`emailSentTo [第一收件人]`、`escalationPending true`，没有 `arm` / `matchedTerm` / `textHash` / `inputPoint` / `cohort`）；发信 stub 收到**恰好 1 封**，收件人是第一收件人；邮件写「研究编号 Research ID: PILOT-01」「研究期 Study period: 试跑 Pilot run」「研究第几天 Study day: 0」「来源 Source: 老人输入」；邮件和主题里没有命中词、uid、输入点、Hybrid、Arm A/B、A 組/B 組、規則組、pilot_designated。`alert_audit_log` 一条 `email_sent` |
| 同上（测试账号对照） | 6b | 通过 | 一个 `isTester: true` 的账号同样写 acute 事件：`pi_alerts` 有行（`isTester true`、`escalationPending false`），**不发信**，`alert_audit_log` 记 `tester_no_email` |
| 附加：登记门开着时 PILOT 能用、没登记的不能用 | 7a | 通过 | `app_config/feature_flags.enrollmentGateEnabled = true`，清掉服务器 1 分钟缓存（`study_period.resetGateCache()`，T21 测试同法）；PILOT-01（Hybrid）调 `proxyDeepSeek`：有回复，模型 stub 被调 1 次，`llm_denied_log` 0 行 |
| 同上 | 7b | 通过 | 一个没登记的 uid 调同一入口：被拒（`Not registered for the study yet`），模型没被调，`llm_denied_log` 1 行 `reason: not_enrolled`、没有 `arm` |
| 同上（规则组防线） | 7c | 通过 | PILOT-03（规则组）调同一入口：被拒（`not part of this study arm`），模型没被调，`llm_denied_log` 的记录没有 `reason`、没有 `arm`（T19 格式不变） |

关于第 5 步"把三位 PILOT 的 W0 日期设成 25 天前"：测试没有改写数据，而是把名单函数的"今天"设成登记日 + 25 天（函数本来就接受这个参数），效果相同，数据保持登记当天的原样。

## 2. 测试运行结果

单独跑（`flock /tmp/firebase-emulator.lock firebase emulators:exec --only firestore --project loneliness-pilot-dev 'cd functions && node test/t43_pilot_checklist_emulator_test.js'`，本机 Node 22，Firestore 模拟器 1.22.0）：

```
  ok  1. randomization switch on, both sequences uploaded, pointers noted
  ok  2. PILOT-01 / 02 Hybrid, PILOT-03 rule arm: cohort pilot, studyPeriod PILOT, arm, w0Date = today, pilot_designated, no isTester
  ok  3. both sequence pointers unchanged; allocation log still empty
  ok  4. pilot_assignment_log: exactly 3 rows, all `designate`
  ok  5a. assessor W4 list on PILOT day 25 — CURRENT BEHAVIOUR: the three PILOT accounts are not listed (T30 lists studyPeriod B only; 1014c §0 wants them in by 11/9)
  ok  5b. nothing in the assessor's list says arm / cohort / version / hybrid / rule / A 組 / B 組 (keys, values, whole JSON)
  ok  6a. alert_config on; PILOT-01 acute event → one e-mail to the primary, no arm, no wording
  ok  6b. a tester account (isTester: true): alert row tagged, no e-mail
  ok  7a. enrolment gate on: PILOT-01 (Hybrid) may call the LLM entry
  ok  7b. enrolment gate on: an unregistered uid is refused (not_enrolled)
  ok  7c. PILOT-03 (rule arm) is refused the LLM as always (no reason field)
t43_pilot_checklist_emulator_test: 11/11 passed
```

注意 5a 的 "ok" 是"现状和测试写的一样"，不是"1014c 的要求达到了"。

全套后端（`flock /tmp/firebase-emulator.lock tool/ci_backend_tests.sh`）：见文末「全套结果」。

ES2018 检查：`grep -nE '\?\?|\?\.'` 在新文件里没有命中。测试末尾把自己写的集合和开关全部清掉，下一个测试文件看到的模拟器和之前一样。

## 3. 给 W0 现场（10/15）的提醒

1. **两个开关是两回事**：登记要 `meta/randomization_config.enabled = true`（T19 的登记入口）；登记门 `app_config/feature_flags.enrollmentGateEnabled` 是另一个开关，开不开见「要 Junyu 定的事」第 3 项。PILOT 登记**不需要**序列已上传（试跑不占序列；T21 测试在没有序列时也能登记 `PILOT-`），所以 Calvin 的序列晚一点上传不影响 10/15。
2. **登记页怎么选版本**：研究员登录 → 「研究員登記」→ 输入老人电邮和研究编号 `PILOT-01`。编号以 `PILOT-` 开头后，情感分和 W0 日期两栏消失，换成两个按钮「A 組（Hybrid：規則 + AI）」「B 組（規則組）」→ 选阿珍 / 阿伯 → 「檢查」→ 确认框里**再选一次版本**，两次一样才能按「確認登記」。10/15 的分配：**PILOT-01、PILOT-02 按「A 組」；PILOT-03 按「B 組」**。
3. **选错了怎么办**：同一个编号第二次提交不会改版本（以第一次为准，页面会提示），要用 `tool/correct_arm_assignment.js` 更正，会在 `pilot_assignment_log` 记一条 `correction`。
4. **登记后老人要完全关掉 App 再打开**（登记页已有这句提醒）。App 只在启动时读组别和等待页；不重开，老人看到的还是登记前的界面。
5. **服务器认出组别的时间**：新账号登记后，Hybrid 的 LLM 入口**马上**能用（服务器的 10 分钟组别缓存只在已经有组别时才写入，新登记的第一次调用读的是最新值；测试 7a 就是这样过的）。但如果**事后更正**组别，服务器最多 10 分钟才认出新组别（`functions/index.js` `_ARM_CACHE_MS`）。登记门开关本身的改动最多 1 分钟生效。
6. **研究日从登记当天算**：PILOT 的 `w0Date` 是登记那天的香港日期，不是填的；登记日是第 0 天。10/15 登记 → 第 25 天 = 11/9（W4 窗口 11/9–11/15）、第 56 天 = 12/10，和 1014c 写的日期一致。
7. **告警会真的发信**：PILOT 账号不是测试账号，急性事件会发邮件。`meta/alert_config.enabled` 开 → T34 格式发到 `primaryEmail`；关（或文档不存在）→ T19 旧格式发到密钥 `PI_EMAIL`。10/15 如果团队要用自己的账号演练触发词，先确认这些账号 `isTester: true`，否则也会发信。
8. **评估员的 W4 名单现在没有 PILOT**：11/9 前如果代码没改，Keran 打开评估员页看不到三位 PILOT，也录不了他们的 W4 DJG-ES（`submitEntry` 对 `PILOT-` 返回 `not_phase_b`）。

## 4. 要带回研究侧的发现

1. **W4 名单和 W4 纸本录入都不含 PILOT**（`functions/assessor.js` `phaseBParticipants` 和 `submitEntry` 两处只认 `studyPeriod == "B"`）。1014c 第 0 节第 1 条要 11/9 前含 PILOT，是**行为改动**，不在本任务范围（本任务不改代码）。改的时候要一起定：全体合并完成率（`completionSummary`）的分母含不含 PILOT；过程数据导出、锁库导出是否也要含 PILOT（现在都只导 `phase_b`）。
2. 告警邮件对 PILOT 老人写「研究期 Study period: 试跑 Pilot run」，收件人一看就知道是试跑；这是研究期不是组别，不影响盲法（Junyu 本来就是非盲）。
3. 规则组 PILOT-03 若 App 误调 LLM，服务器一样拒绝并记 `llm_denied_log`（没有组别字段）；10/15 之后可以看这个集合有没有 PILOT-03 的记录，作为 App 端分组是否正确的旁证。
4. `isTester` 仍是客户端可写（待办 96、决策 0037 第 4 项）：登记时服务器不写这个字段，三位 PILOT 老人默认不是测试账号；但拿到测试密码的人能自己改。10/15 前后请不要把测试密码给试跑老人。

## 5. 要 Junyu 定的事

1. **W4 名单含 PILOT 怎么改、归哪个任务**：(a) `phaseBParticipants` 改成 `studyPeriod in ["B", "PILOT"]`，名单和录入都放开，完成率分母也含 PILOT；(b) 只放开名单和录入，完成率仍只算 Phase B；(c) 不改，PILOT 的 W4 由 Junyu 纸本保存、不进 App。编号由开发窗口分配；11/9 前要合并部署，建议 10/22 前（和 T24 每周问卷一批）。
2. **10/15 当天 `meta/alert_config.enabled` 开还是关**：开 → 发到 `primaryEmail`（要先建文档、填 Junyu 和 Calvin 的地址，按 T34 上线清单）；关 → 发到密钥 `PI_EMAIL`。两种都会对 PILOT 发信。
3. **登记门 10/15 开不开**（T21 决策 0037 第 6 项仍待定）。开之前要有 fixes-after-review 第 1 项（登录后重读开关，#74）在包里，并把团队账号设成 `isTester: true`。

## 6. 改了哪些文件

- 新增：`functions/test/t43_pilot_checklist_emulator_test.js`（11 步，只读现有函数：`randomization.enrol`、`assessor.dueList`、`index.onSafetyEventCreated`、`index.proxyDeepSeek`；邮件和 Auth 用 T34 测试的 stub，DeepSeek 用 fetch stub）。
- 文档：本报告；`docs/history.md` 顶部一段。没有改 `docs/dev/backlog.md` 的编号行（编号由开发窗口管）；没有改行为代码，所以不动 `docs/STUDY_CHANGELOG.md` 和 `docs/dev/architecture.md`。

## 全套结果

`flock /tmp/firebase-emulator.lock tool/ci_backend_tests.sh`（本机 Node 22、Java 21、Firestore 模拟器 1.22.0；CI 用 Node 24）：**全过，0 失败**，结尾「All backend tests passed.」。

- 单元：`ada_test` 9、`blinding_test` 11、`djg_w2_test` 9、`final_copy_test` 4、`llm_flags_test` 11、`llm_log_test` 11、`memory_test` 55、`outcome_instruments_test` 12、`pi_alert_test` 16、`quiet_hours_test` 9、`randomization_test` 9、`study_period_test` 8、`study_week_test` 6、`weekly_schedule_test` 12，其余各文件无失败。
- Firestore 规则：167 项 passing。
- 模拟器：`ada` 9、`analysis_export` 5、`arm` 6、`assessor` 10、`blinding` 7、`djg_w2` 7、`enrollment_gate` 7、`llm_calls` 17、`memory_acceptance` 5、`memory` 19、`memory_layers` 11、`prelaunch_config` 6、`randomization` 20、`reminders` 9、`safety_alert_t34` 16、`safety_classifier` 12、`safety_t7` 14、`t30_server` 6、**`t43_pilot_checklist` 11/11**、`weekly_schedule` 10，其余各文件无失败。新文件排在 `t30_server` 之后、`weekly_schedule` 之前跑，前后文件都没有受影响。
- 删除脚本 6、共享同意脚本 4、测试员清理脚本 4。
