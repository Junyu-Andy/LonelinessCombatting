# T34 安全告警邮件（SPEC:C12、C19、C20）— 报告

- 日期：2026-10-14
- 分支：`feat/safety-alert-email`（从 `main` @46d3ef9 开，已合入 `main` @e851205，即 T21 合并后的 main）
- 任务原文：`docs/dev-tasks/dev-tasks-1010b.md` 第三节 T34；更正见 `docs/dev-tasks/dev-tasks-1014.md` 第三节 T34
- 状态：PR 草稿。**所有新行为都在一个总开关后面，默认关。**

## 结论（先看这里）

1. 告警邮件改版做完了，放在总开关 `meta/alert_config.enabled` 后面（`functions/pi_alert.js`）。**没有这个文档 = 关 = 和现在完全一样**：只有 acute 级发信、发到密钥 `PI_EMAIL`、没有确认、没有后备。这就是 10/14 说的过渡做法：10/19 前没合并、或合并了还没打开，把 `PI_EMAIL` 设成 Junyu 的地址即可（上线清单 B1）。
2. 开关打开后：邮件中英双语、12 个固定字段（见第 2 节），**不含组别、老人原话、命中的词**；收件人从 `meta/alert_config` 读（第一收件人 Junyu、后备 Calvin Or），发信前查账号角色，`blinded`（评估员）的地址一律去掉并记日志；测试账号只记录不发信；研究员后台（`unblinded`）多一节「安全告警」和「確認處理」按钮；12 小时（可配置）没人确认，定时函数自动把同一封邮件转给后备，每条只转一次。
3. 问卷来源做了入口 `functions/questionnaire_safety.js`（PHQ-9 第 9 题 ≠ 0 → 一条安全事件，不论级别都告警；客户端不能写这两种来源）。**App 内目前没有 PHQ-9；来源「问卷」目前没有触发题目**（`grep -ri phq lib/` 为空）。评估员录入页是 T30 的，T30 在提交处调用这个入口；本任务只用合成数据测了入口。
4. `safety_events` 新增 `crisisPageShown`（两组同样写，`lib/core/safety/safety_event_writer.dart`），**不受开关控制**，随下一个 App 版本生效；盲法导出多 `sourceGroup`，四种来源分开数。
5. 新字段和决策 0029 第五节冲突，决策草稿在第 9 节，编号等开发窗口分配。

## 0. 现状（改之前）

| 问题 | 现状 | 出处 |
|---|---|---|
| 告警怎么触发、发什么 | `onSafetyEventCreated` 去重后，**只有 acute** 写 `pi_alerts`（uid、研究编号、级别、`dedupKey`、`isTester`、`eventPath`）并发一封英文短邮件：第一行「An acute distress event was detected.」、研究编号、时间、告警编号，故意不写来源、陪伴者、级别以外的任何东西（决策 0029 第五节，PI 盲法）。收件人是密钥 `PI_EMAIL`，SMTP 用 `SMTP_HOST/USER/PASS` | `functions/index.js` `onSafetyEventCreated`；`functions/pi_alert.js`（T19 版 `buildPiAlert`、`buildPiEmail`） |
| `safety_events` 已有的字段 | `uid`、`source`、`inputPoint`、`turnId`、`textHash`、`level`、`tier`、`category`、`lexiconVersion`、`matchedTerm`、`agentId`、`sessionId`、`createdAt`；T8 分类器开着时还有 `detector`、`classifierStatus/Level/Score/Version`。服务器补 `dedup_key`、`isDuplicate`、`duplicateOf`、`escalatedBy` | `lib/core/safety/safety_event_writer.dart` |
| 告警要的字段里**没有**的 | 「是否显示危机页」（没有）；研究期（要从研究编号前缀算）；研究第几天（要从 `users/{uid}.w0Date` 算）；「LoRA 是否参与判定」没有现成字段，要从 `detector` / `classifierStatus` 推 | 同上；`functions/djg_w2.js` `w0DateKey` |
| 研究员后台给 `unblinded` 看什么安全信息 | 「未處理嘅 distress flags」（读 `shared_context.safetyFlags`，Hybrid 组会话层的旧标记）、参与度、对话审计队列、想法练习审计、跨 agent 转介、PPR。**没有**任何 `pi_alerts` / `safety_events` 的列表，也没有确认按钮 | `lib/features/researcher_dashboard/presentation/pages/researcher_dashboard_page.dart`；`data/dashboard_access.dart` |

## 1. 开关

| 开关 | 位置 | 默认 | 管什么 |
|---|---|---|---|
| `enabled` | Firestore 文档 `meta/alert_config`（只有服务器能读写，`firestore.rules`） | **关**（文档不存在、或字段不是布尔 `true` 都算关） | 整个 T34 告警改版：邮件字段、收件人配置、角色检查、确认处理、转后备。关着时 = 现状（T19 做法） |
| `primaryEmail` | 同一文档 | 空 | 第一收件人（Junyu）。空着时退回密钥 `PI_EMAIL` 并记一条 `alert_audit_log`（`primary_missing_fallback_secret`） |
| `backupEmail` | 同一文档 | 空 | 后备收件人（Calvin Or）。空着时到期的告警标 `escalationSkipped: no_backup_email`，不发信 |
| `escalateAfterHours` | 同一文档 | 12 | 多少小时没人确认转后备；要是正数 |

地址不在代码、不在仓库；由 Junyu 在控制台填（上线清单 C6、C6a）。配置每次告警都重读（告警很少，不缓存），控制台改完下一条告警就生效。

**不受开关控制的两处**（随下一个 App 版本 / 下一次部署生效）：`safety_events.crisisPageShown`（App 写，两组相同）；盲法导出的 `sourceGroup` 字段（服务器导出）。两者都只是多一个字段，不改任何行为。

## 2. 字段表

### 2.1 邮件字段（顺序固定，两组完全相同；`functions/pi_alert.js` `emailFields`）

| # | 邮件里的标签 | 取值 | 从哪里来 |
|---|---|---|---|
| 1 | 研究编号 Research ID | `PB-A07`；没登记写「未登记 Not registered yet」 | `research_id_map/{uid}`；问卷事件自带的 `researchId` 作兜底 |
| 2 | 研究期 Study period | `Phase B` / `试跑 Pilot run` / `未知 Unknown` | 研究编号前缀 `PB-` / `PILOT-`，用 T21 的 `functions/study_period.js` `periodForResearchId`（和 main 上的文件逐字节相同） |
| 3 | 陪伴者 Companion | `小欣 Siu Yan (siu_yan)`、`阿珍/阿伯 Ah Jan / Ah Bak (ah_jan_ah_bak)`、`通通 Tung Tung (tung_tung)`；没有写 `—` | `safety_events.agentId` |
| 4 | 来源 Source | `老人输入 Participant input` / `AI 回复扫描 AI reply scan` / `问卷 Questionnaire` / `评估员录入 Assessor entry` | `safety_events.source` 映射：`user_input`、`form`、`gateway_input`、`rule_turn`、`m3_turn` → 老人输入；`ai_output_scan`、`gateway_output` → AI 回复扫描；`questionnaire`；`assessor_entry` |
| 5 | 级别和类别 Level and category | `急性 acute / ideation`；问卷事件再加 `/ PHQ-9 第 9 题 item 9` | `tier`（没有用 `level`）、`category`、`instrument`、`item` |
| 6 | 词库版本 Lexicon version | `v5-2026-09`；没有写 `—` | `lexiconVersion` |
| 7 | LoRA 是否参与判定 Classifier involved | `是 Yes` / `否 No` / `未知 Unknown` | `detector` 为 `classifier` 或 `both` → 是；`lexicon` 或没有分类器字段 → 否；只有 `classifierStatus` 的旧记录 → 是；其他 → 未知 |
| 8 | 研究第几天 Study day | 整数，W0 = 第 0 天，按香港日历日；取不到写 `未知 Unknown` | `users/{uid}.w0Date`（T21 登记时写，格式 `YYYY-MM-DD`，和 `djg_w2.js` `w0DateKey` 一样）。没有 `w0Date` 就是未知，不用注册日兜底。**T24 合并后改用它的共享函数**（backlog 97、100） |
| 9 | 是否显示危机页 Crisis page shown | `是 Yes` / `否 No` / `未知 Unknown`（问卷事件、旧 App 的事件） | `safety_events.crisisPageShown` |
| 10 | 事件编号 Event ID | `safety_events/9f3kQx2LmA7bC1dE` | 事件文档路径 |
| 11 | 告警编号 Alert ID | `pi_alerts/Zt4YpQ8nRw2sV6uK` | 告警文档路径 |
| 12 | 时间（香港） Time (HKT) | `2026-10-26 14:12` | 发信时间（转后备的邮件是转发时间） |

**永远不在邮件里**：组别（`arm`）、命中的词（`matchedTerm`）、文字哈希（`textHash`）、`uid`、输入点（`inputPoint`，`chat_reflective` 等只有一组有）、会话编号、老人的任何原话、问卷的原始答案（`rawValue`）。单元测试和模拟器测试都逐项检查（第 4 节）。

### 2.2 `safety_events` 新字段

| 字段 | 谁写 | 两组 | 说明 |
|---|---|---|---|
| `crisisPageShown`（布尔） | App，`SafetyEventWriter.maybeWrite`（唯一写入点） | 相同 | 这一轮有没有弹出全屏危机页。**写之前就决定**（规则不允许事后 update）：级别是 acute 即 `true`，否则 `false`。依据：App 里所有 acute 检测都经 `DistressRouter.route` 推出 `EmergencySupportPage`（`lib/core/safety/distress_router.dart`），低于 acute 的从不弹这页；两组共用同一个 writer 和 router。规则只接受布尔（`firestore.rules`）。极端情况（页面已卸载、测试环境没有 `CoreServicesScope`）字段仍为 true，报告在此说明 |
| `instrument`、`item`、`rawValue`、`enteredBy`、`alwaysAlert` | 只有服务器（`functions/questionnaire_safety.js`） | 相同 | 问卷 / 评估员录入事件：问卷名、题号、这一题的原始值（不带其他题）、录入人。`alwaysAlert: true` 让 `onSafetyEventCreated` 不论级别都告警；规则拒绝客户端带这个字段 |
| `source` 新增取值 | 只有服务器 | 相同 | `questionnaire`、`assessor_entry`。规则列表里**没有**加这两个值，所以客户端写不了（测试见第 4 节） |

### 2.3 `pi_alerts`（告警记录）

- 开关关：T19 的记录不变（`alertVersion: 2`）。
- 开关开：`alertVersion: 3`，带邮件的全部字段（`researchId`、`studyPeriod`、`studyDay`、`agentId`、`source`、`sourceGroup`、`level`、`tier`、`category`、`lexiconVersion`、`classifierInvolved`、`crisisPageShown`、`instrument`、`item`、`alwaysAlert`）加状态：`emailSentAt`、`emailSentTo`、`escalationPending`、`acknowledgedAt`、`acknowledgedBy`（uid）、`acknowledgedByEmail`、`escalatedAt`、`escalatedTo`、`escalationSkipped`。转后备的邮件只从这条记录生成，所以和第一封字段一样。
- 规则：`unblinded` 可读；任何客户端不能写（确认走 Cloud Function）。`blinded` 读不到。

### 2.4 `alert_audit_log`（只有服务器能读写）

每行 `type`、`alertId`、`at`，类型：`email_sent`、`email_failed`、`tester_no_email`、`recipient_dropped`（带 `email`、`reason: blinded_role`、`stage: primary|escalation`）、`recipient_note`（`no_app_account` / `lookup_failed`）、`no_recipients`、`primary_missing_fallback_secret`、`acknowledged`（`by`、`byEmail`）、`escalated`（`to`、`afterHours`）、`escalation_skipped`、`escalation_email_failed`。

### 2.5 导出里的来源字段（任务第 5 节）

| 导出 | 字段 | 取值 | B12 能数什么 |
|---|---|---|---|
| 盲法导出 v2（`functions/blinding.js` `buildBlindedExport`，文件 `safety_events`） | `sourceGroup`（新）；没有原始 `source` | `participant_input`、`questionnaire`、`assessor_entry` | 这三种按人、按 `groupCode` 分开数；manifest 多 `safetyEventsBySource` 三个计数。**`ai_reply_scan` 的行照旧不进这份导出**（只有 Hybrid 组有，会露组别，决策 0021），manifest 里 `safetyEventsNotFromUserInput` 是它的条数。行里另加 `instrument`、`item`、`crisisPageShown`；**不带** `rawValue` |
| 旧的全量导出 v1（`functions/index.js` `blindedDataExport`，`safety_events.ndjson`） | `sourceGroup`（新）＋原有 `source` | 四种全有：`participant_input`、`ai_reply_scan`、`questionnaire`、`assessor_entry` | 四种来源分开数。这份导出本来就带组别映射和全部字段，给揭盲后的分析用 |

## 3. 邮件样例（合成数据）

由 `functions/pi_alert.js` `buildAlertEmail` 直接生成（规则组、通通、第 7 天）。

**第一封（发第一收件人）**

```
主题：[陪住] 安全告警 Safety alert · 急性 acute · PB-A07

陪住 安全告警 / Safety alert

研究编号 Research ID: PB-A07
研究期 Study period: Phase B
陪伴者 Companion: 通通 Tung Tung (tung_tung)
来源 Source: 老人输入 Participant input
级别和类别 Level and category: 急性 acute / ideation
词库版本 Lexicon version: v5-2026-09
LoRA 是否参与判定 Classifier involved: 否 No
研究第几天 Study day: 7
是否显示危机页 Crisis page shown: 是 Yes
事件编号 Event ID: safety_events/9f3kQx2LmA7bC1dE
告警编号 Alert ID: pi_alerts/Zt4YpQ8nRw2sV6uK
时间（香港） Time (HKT): 2026-10-26 14:12

请按研究安全流程处理，并在研究员后台点「確認處理」。12 小时内没有人确认，系统会把同一封邮件发给后备收件人。
Follow the study safety protocol and press 確認處理 (acknowledge) in the researcher dashboard. If nobody acknowledges within 12 hours, the same e-mail goes to the backup recipient.
本邮件不含组别、老人原话或命中的词；细节凭事件编号到后台查。
This e-mail carries no study arm, no participant wording and no matched term; look the event up by its ID.
自动邮件，请勿回复。 Automated message; do not reply.
```

**转后备的那封**（12 小时后，字段一样，多一行说明）

```
主题：【转后备 Escalated】[陪住] 安全告警 Safety alert · 急性 acute · PB-A07

陪住 安全告警 / Safety alert

【转后备】这条告警发出后 12 小时内没有人确认处理，现在发给后备收件人。
Escalated: nobody acknowledged this alert within 12 hours, so it is now sent to the backup recipient.

研究编号 Research ID: PB-A07
…（12 个字段和上面相同，只有「时间」是转发时间 2026-10-27 02:27）…
```

开关关着时的邮件（现状）不变：主题 `[LonelinessCombatting] Acute distress alert`，正文只有研究编号、时间、告警编号。唯一的小改动：问卷 / 评估员录入事件低于 acute 时也会发这封，第一行改为写明级别（`A safety event (level: moderate_review) from a questionnaire source was recorded…`），不再说「acute」。

## 4. 测试表（任务第 7 节逐条）

| 任务第 7 节 | 测什么 | 测试文件 | 结果 |
|---|---|---|---|
| 1 字段齐全；没有组别、原话、命中词；两组字段集合相同 | 12 个标签顺序；A 组（`ai_output_scan`、小欣、分类器 both）和 B 组（`rule_turn`、通通）同一事件的记录字段、邮件标签完全一样；邮件里找不到 `arm`、命中词、哈希、uid、输入点 | `functions/test/pi_alert_test.js`（纯函数）；`functions/test/safety_alert_t34_emulator_test.js`「switch on: both arms」 | 单元 15/15 通过；模拟器 16/16 通过 |
| 2 收件人从配置读；`blinded` 去掉；测试账号不发 | 配置文档解析和默认值；`primaryEmail` 是 `blinded` 账号时没人收信、`alert_audit_log` 记 `recipient_dropped`；没有账号的地址照发；`isTester` 只有记录、`tester_no_email` 日志、不进转后备 | 同上两份 | 通过（含在上面两份里） |
| 3 12 小时内确认的不转；超时转一次、只转一次；转后备字段相同 | 11 小时不转；13 小时转给 `backupEmail`、字段值逐行相同、`escalatedAt/To` 写了；再跑一次不再发；`escalateAfterHours: 2` 生效；开关关时定时函数什么都不做；后备是 `blinded` 时去掉并记日志 | `safety_alert_t34_emulator_test.js`「escalation」三条 | 通过 |
| 4 确认只有 `unblinded`；记录操作人和时间 | 未登录、无角色、`blinded`、旧 `pi` 都拒绝；`unblinded` 成功写 `acknowledgedAt/By/ByEmail` 和日志；重复确认保留第一次；已确认 13 小时后也不转后备；`acknowledgeAlert` 可调用函数本身的角色映射 | 同上「確認處理」两条 | 通过 |
| 5 PHQ-9 第 9 题为 0 不记；不是 0 记一条并告警，来源正确；客户端不能伪造这两种来源 | `triggers` 规则（0 / "0" 不触发，1–3 触发，其他题、其他问卷不触发）；模拟器里 0 → 没有文档；1 → 一条 `assessor_entry` 事件，级别 moderate 也告警，邮件来源「评估员录入」，不含 `rawValue`；开关关时也告警；规则拒绝任何客户端（含 `unblinded`）写 `questionnaire` / `assessor_entry` 和 `alwaysAlert` | `pi_alert_test.js`；`safety_alert_t34_emulator_test.js`「questionnaire entry」；`test/rules/safety_alert_rules.test.js` | 通过 |
| 6 导出有来源字段，四种分开数 | v2 导出：4 行各带 `sourceGroup`，`ai_output_scan` 被去掉，manifest 三个计数；行里没有 `source`、`rawValue`、`uid`；v1 的 `sourceGroupFor` 把 `ai_output_scan` 映射成 `ai_reply_scan` | `safety_alert_t34_emulator_test.js`「export」 | 通过 |
| （开关关 = 现状） | 没有 `meta/alert_config`：acute → `alertVersion: 2` 记录、旧主题、发 `PI_EMAIL`、没有日志；moderate 不发 | 同上前两条；`safety_t7_emulator_test.js`（原有 14 条照过） | 通过。第一次整套跑时 T7 有 1 条失败：我的测试结束时留下了打开的 `meta/alert_config`，T7 的 `reset` 不删它；已在我的测试末尾加清理，重跑通过 |
| 规则 | `crisisPageShown` 布尔接受（两组）、非布尔拒绝；`pi_alerts` 只有 `unblinded` 能读，谁都不能写；`alert_audit_log`、`meta/alert_config` 对所有客户端关闭 | `test/rules/safety_alert_rules.test.js`（已加进 `test/rules/package.json`） | 通过（整个规则套件 104 条 passing，含 T21 新加的 `enrollment_gate_rules.test.js`） |
| App | `crisisPageShownFor`：acute 为 true、其他为 false；词库对「我好想死」两组同一答案；`DashboardAccess.showsSafetyAlerts` 只有 `unblinded`；告警行显示研究编号、时间、来源、陪伴者、状态，「確認處理」调一次可调用函数，已确认的没有按钮，失败有提示 | `test/safety_alert_t34_test.dart`（7 条）；`test/dashboard_access_test.dart`（补 2 个断言） | 7/7、2/2 通过 |

整套：

| 命令 | 结果 |
|---|---|
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | 0 错误；88 条 info/warning 都是已知的（和 main 一样） |
| `tool/ci_flutter_tests.sh`（六套） | 六套全部 `All tests passed!`（主套 428 条） |
| `flock /tmp/firebase-emulator.lock tool/ci_backend_tests.sh` | 第二次整套通过（Functions 单元测试；规则 104 passing；模拟器测试含 `safety_alert_t34` 16/16、`safety_t7` 14/14、`enrollment_gate` 7/7；删除和同意脚本测试） |

邮件发送在测试里用 `pi_alert.setMailerForTests` 截获（不连 SMTP）；账号角色用 `pi_alert.setAuthForTests` 替代 Firebase Auth。没有发过真邮件，没有连过生产 Firestore。

截图：这次没有做（告警列表的样子由 widget 测试覆盖；时间花在合并 T21 上）。

## 5. 做法说明（给以后改的人）

- **总开关的两条路径**都在 `onSafetyEventCreated`（`functions/index.js`）里，先读 `meta/alert_config`，关就走 T19 原来的代码（原样保留在 `pi_alert.js` 顶部），开才走新代码。读配置失败按关处理并记 console 错误。
- **研究期**：`functions/study_period.js` 是 T21 的文件，和 main 逐字节相同，不要在这个分支改它。
- **研究第几天**：`pi_alert.js` `studyDay`，W0 = 第 0 天，香港日历日。试跑账号也用 `users/{uid}.w0Date`（T21 登记时写）；任务原文说试跑「从登记日算」，T24 的共享函数定下来后对齐（backlog 100）。
- **收件人角色检查**：`admin.auth().getUserByEmail`；`role == 'blinded'` 去掉。查不到账号（`auth/user-not-found`）照发并记 `no_app_account`——Calvin Or 可以没有 App 账号；Auth 临时出错也照发并记 `lookup_failed`（告警不能因为查角色失败而丢）。
- **转后备只转一次**：定时函数 `escalateAlerts`（每 15 分钟，asia-east2）只看 `escalationPending == true` 的记录，用事务把它改成 false 再发信，两个实例同时跑也只会发一封。失败（SMTP 没配、发信抛错）记 `escalation_email_failed`，不会重试（记录已认领）——见「要 Junyu 定的事」第 4 条。
- **问卷入口**：`recordQuestionnaireSafetyEvent(db, {uid, source, instrument, item, rawValue, enteredBy, researchId, level?})`，第 9 题为 0 返回 null 不写；默认级别 acute（可传 `level` 覆盖）。每条事件自带 `turnId`，去重不会把两次录入合并。**没有**从 `index.js` 再导出（`index.js` 的每个 export 都会被当成要部署的函数），T30 直接 `require("./questionnaire_safety")`。
- **`crisisPageShown`**：写在 `SafetyEventWriter.maybeWrite` 里按级别算，没有加参数，所以测试里继承它的 `_RecordingWriter` 不用改。去重时，把这一轮升到 acute 的那条扫描若带 `crisisPageShown: true`，服务器会同步到被计数的主记录上。

## 6. 改了哪些文件

| 文件 | 改动 |
|---|---|
| `functions/pi_alert.js` | 重写：保留 T19 的 `buildPiAlert` / `buildPiEmail`；新增配置读取、来源映射、研究期/研究日/分类器字段、v3 告警记录、中英邮件、收件人角色检查、邮件发送（可替换）、审计日志、`acknowledge`、`escalateDue`、测试钩子 |
| `functions/index.js` | `onSafetyEventCreated` 分开关两条路径；`alwaysAlert` 事件不论级别告警；新函数 `acknowledgeAlert`（可调用）、`escalateAlerts`（定时）；`readSmtpSecrets`；v1 导出 `safety_events` 加 `sourceGroup` |
| `functions/questionnaire_safety.js` | 新：问卷 / 评估员录入入口 |
| `functions/study_period.js` | 从 T21 复制，和 main 相同 |
| `functions/blinding.js` | v2 导出：问卷两种来源也导出，行带 `sourceGroup`、`instrument`、`item`、`crisisPageShown`，manifest `safetyEventsBySource` |
| `firestore.rules` | `safety_events`：拒绝 `alwaysAlert`，`crisisPageShown` 必须布尔（两种新来源本来就不在白名单）；`pi_alerts` `unblinded` 可读；`alert_audit_log`、`meta/alert_config` 关闭 |
| `lib/core/safety/safety_event_writer.dart` | `crisisPageShown` |
| `lib/features/researcher_dashboard/data/dashboard_access.dart` | `showsSafetyAlerts` |
| `lib/features/researcher_dashboard/presentation/widgets/safety_alerts_section.dart` | 新：告警列表、「確認處理」 |
| `lib/features/researcher_dashboard/presentation/pages/researcher_dashboard_page.dart` | 接入「安全告警」一节（`unblinded`） |
| 测试 | `functions/test/pi_alert_test.js`、`functions/test/safety_alert_t34_emulator_test.js`、`test/rules/safety_alert_rules.test.js`（＋`test/rules/package.json`）、`test/safety_alert_t34_test.dart`、`test/dashboard_access_test.dart` |
| 文档 | `docs/release/prelaunch-checklist.md`（B1、B4a、C6、C6a）、`docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`（§8、§9、§10）、`docs/history.md`、`docs/dev/backlog.md`（90 更新；新 97–100）、本报告 |

## 7. 和其他 PR 的交叉

| PR | 重叠的文件 | 说明 |
|---|---|---|
| T21 `fix/phase-config-split`（**已合入 main @e851205**） | `functions/index.js`、`firestore.rules`、`test/rules/package.json`、`functions/study_period.js`、四份文档 | 本分支已合入 main 并解决冲突：文档两边都保留；mocha 列表两个新文件都在；`study_period.js` 相同；backlog 新项顺着 T21 的 96 编为 97–100 |
| T25 `feat/session-briefpr` | 可能碰 `functions/index.js`、文档 | 不同函数，预计只有文档行冲突 |
| T36 `chore/apk-phase-b-templates` | 文档、`.github/` | 预计无代码冲突 |
| T37 `fix/onboarding-settings` | `lib/features/…`、文档 | 没碰研究员后台和安全目录，预计无冲突 |
| T24（未开） | `pi_alert.js` 的 `studyDay` 要换成它的共享函数；`index.js` | backlog 97 |
| T30（未开） | 调用 `questionnaire_safety.js`；研究员后台（评估员视图） | backlog 98；评估员视图和「安全告警」一节都在同一页，T30 按 `access` 加节即可 |

## 8. 要 Junyu 定的事

| # | 事项 | 选项 | 建议 |
|---|---|---|---|
| 1 | 评估员录入 PHQ-9 第 9 题 ≠ 0 的事件，默认记什么级别 | A. 一律 `acute`（现在的默认，偏安全一侧；B12 会把它和聊天里的 acute 一起数）；B. 按答案分：1 → `moderate_review`，2–3 → `acute`；C. 一律 `moderate_review`，只靠「不论级别都告警」 | A。告警不受级别影响，级别只影响统计口径；要分的话 T30 调用时传 `level`，代码已支持 |
| 2 | 后备收件人 Calvin Or 看不看「来源」字段（backlog 92：「AI 回复扫描」只有 Hybrid 组有） | A. 照现在：后备邮件和第一封完全一样（任务原文「字段相同」）；B. 后备邮件把「AI 回复扫描」并入「老人输入」；C. 后备邮件不写来源 | A，前提是 Calvin 不是盲法人员（10/10 共同规则 8 里盲的是评估员）。若研究侧认为 Calvin 需要保持盲，选 B，改 `buildAlertEmail` 一处 |
| 3 | `PI_EMAIL` 密钥的去留 | A. 保留做兜底（现在的做法，`primaryEmail` 空时用）；B. 开关打开并填好地址后从 `secrets` 列表删掉 | A 到 10/19 上线稳定，之后 B（backlog 99） |
| 4 | 转后备的邮件发送失败要不要重试 | A. 不重试，只记日志（现在）；B. 失败时把 `escalationPending` 改回 true，下个 15 分钟再试 | B 更稳，但要防止 SMTP 长期坏掉时每 15 分钟记一条日志；建议上线后看 `alert_audit_log` 再决定 |
| 5 | 打开开关的日期 | 部署后用测试账号验证一次（上线清单 C6）再开 | 10/19 前合并、部署，第一位参与者入组前打开 |
| 6 | `crisisPageShown` 是否也要进盲法导出 v2 | 现在进了（两组相同的字段，不露组别） | 保持 |

## 9. 决策记录草稿（编号待开发窗口分配）：取代 0029 第五节

- 日期：2026-10-14
- 状态：提议中（随 T34 的 PR 草稿；开关默认关，打开即采纳）
- 影响范围：phase_b、pilot × 两组（告警邮件）；所有 cohort × 两组（`safety_events.crisisPageShown`）
- 相关代码：分支 `feat/safety-alert-email`（T34，SPEC:C12、C19、C20）。`functions/pi_alert.js`、`functions/index.js`、`functions/questionnaire_safety.js`、`firestore.rules`、`lib/core/safety/safety_event_writer.dart`、`lib/features/researcher_dashboard/`
- 取代：决策 0029 第五节（给 PI 的告警不带组别线索）。0029 其余部分不变。

### 背景

0029 第五节写于 PI（Junyu）是盲法角色的时候：告警邮件只有研究编号、时间、告警编号，连陪伴者、来源都不写，怕露出组别。10/10 共同规则 8 改了人员安排：Junyu 不设盲（`unblinded`），由他登记、分组、处理安全事件；盲的是 W4 的独立评估员。产品窗口 10/10 第 6–8 条要求告警邮件带足够的处理信息（陪伴者、来源、级别、词库版本、LoRA、研究日、危机页、事件编号），并加确认处理和 12 小时后备。

### 决定

1. 告警邮件发给非盲的研究人员（第一收件人 Junyu，后备 Calvin Or），字段按 T34 报告第 2.1 节；**仍然不写组别、老人原话、命中的词**。两组同一事件的字段集合相同。
2. 评估员（`blinded`）永远不是收件人：地址不进配置；进了也在发信前按账号角色去掉并记日志。研究员后台的告警列表只给 `unblinded`。
3. 收件人、开关、后备时长放在 `meta/alert_config`（只有服务器能读写），不写进代码。
4. 问卷 / 评估员录入来源的安全事件（PHQ-9 第 9 题 ≠ 0）不论级别都告警，只有服务器能写。
5. 开关 `meta/alert_config.enabled` 关着时维持 0029 第五节的做法，作为 10/19 前的过渡。

### 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 维持 0029：邮件只有编号，细节到后台查 | 处理人现在就是非盲的 Junyu，少字段只会拖慢处理；后台在手机上不方便 |
| 邮件里也写组别 | 没必要：处理流程两组一样；而且后备收件人是否保持盲还没定（backlog 92） |
| 后备邮件去掉来源字段 | 任务原文要求字段相同；留给 backlog 92 决定 |
| 把地址写进代码或密钥 | 改地址要重新部署；文档可以在控制台改、下一条告警即生效 |

### 后果

- 对研究：安全事件的处理记录更完整（谁、何时确认；是否转后备）；告警邮件带「来源」后，收到「AI 回复扫描」的人可以推断该参与者在 Hybrid 组——对 Junyu 不是问题（非盲），对 Calvin 要研究侧确认（backlog 92）。protocol 的安全监测一节要补：告警字段、确认处理、12 小时后备。
- 对开发：T30 调用问卷入口；T24 替换研究日函数；上线清单 B1、B4a、C6、C6a。
- 对论文：方法的安全监测部分写明告警内容和升级流程；局限不用加。

## 10. 架构优化观察（不在本任务改）

| 观察 | 位置 | 一句话建议 |
|---|---|---|
| `functions/index.js` 约 2350 行，把 LLM 代理、分组登记、安全触发、导出、推送、ADA 等不相关的函数放在一个文件里；每次任务都改它，所有并行 PR 都在这里冲突 | `functions/index.js` | 按领域拆成 `functions/fn_safety.js`、`fn_enrollment.js`、`fn_export.js` …，`index.js` 只做 `Object.assign(exports, require(...))`；先拆安全和导出两块 |
| 「只有服务器能读写」的集合各写一段 `allow read, write: if false`，已有十几处 | `firestore.rules` | 去掉这些 match（Firestore 默认拒绝），只留一处注释列出服务器专用集合；规则测试照样能证明拒绝 |
| 角色检查在三处各写一遍：`isUnblinded()`（规则）、`DashboardAccess.fromClaims`（App）、`request.auth.token.role === 'unblinded'`（`pi_alert.acknowledge`、`enrollParticipant`） | `firestore.rules`、`lib/features/researcher_dashboard/data/dashboard_access.dart`、`functions/pi_alert.js`、`functions/index.js` | 服务器端做一个 `functions/roles.js`（`requireRole(request, 'unblinded')`），所有可调用函数共用 |
| 配置文档散在 `meta/*`（`memory_config`、`safety_config`、`randomization_config`、`blinding_config`、`alert_config`）和 `app_config/*`（`feature_flags`、`phase_a`、`reminders`、`usage_copy`），每个有自己的读取函数和缓存策略 | `functions/*.js` 各自的 `readXxxConfig`；`lib/core/feature_flags/` | 约定：`meta/*` = 服务器专用、`app_config/*` = 客户端可读；服务器用一个 `config.js` 读、带统一缓存和「读失败按默认值」；上线清单的 C 节就能自动生成 |
| 研究员后台一页 800 多行，每个小节是一个私有 widget，T30 的评估员视图和 T34 的告警都要往里加 | `lib/features/researcher_dashboard/presentation/pages/researcher_dashboard_page.dart` | 每节一个文件放 `presentation/widgets/`（本任务的 `safety_alerts_section.dart` 就是这样），页面只按 `DashboardAccess` 排节 |
| 「研究第几天 / W0」至少三处各算一遍：`djg_w2.js` `w0DateKey`、`ada.js`、现在的 `pi_alert.js` `studyDay` | `functions/djg_w2.js`、`functions/ada.js`、`functions/pi_alert.js` | T24 的共享函数出来后，三处都改用它，并把它放进 `study_period.js` 旁边 |
| 盲法导出有两套（v1 `blindedDataExport` 在 `index.js`，v2 在 `blinding.js`），字段白名单、组别映射各一份 | `functions/index.js`、`functions/blinding.js` | 研究侧确认 v1 不再用后删掉 v1；否则至少让 v1 复用 `blinding.js` 的白名单 |
| 邮件发送（nodemailer、587、`from: smtpUser`）过去写在 `index.js` 里，现在挪到 `pi_alert.sendMail`，但其他要发邮件的功能（将来的周报等）仍会各写一份 | `functions/pi_alert.js` `sendMail` | 抽成 `functions/mail.js`，带测试钩子 |
| `functions/` 约 1200 个 ESLint 缩进错误（主要是 `index.js`），每个新文件要手动避开 | `functions/.eslintrc.js` | 一次性 `eslint --fix` 单独一个 PR，之后 CI 把 lint 变成必过 |

## 11. 要带回研究侧的发现

1. **App 内没有 PHQ-9，来源「问卷」没有触发题目**（`grep -ri phq-9 lib/` 为空；W8 也不推 PHQ-9，1014 第三节）。入口和测试都在，以后要加题目时只要在那题的提交处调用 `recordQuestionnaireSafetyEvent`，不改结构。
2. 评估员录入 PHQ-9 第 9 题 ≠ 0 的默认级别（第 8 节第 1 条）要研究侧定。
3. 后备收件人是否需要保持盲（backlog 92）：决定前后备邮件和第一封完全相同。
4. `research_id_map` 没有记录的账号（没登记）发生 acute 时，邮件写「未登记」。登记门打开后这种账号不能用 LLM，但规则组界面仍能触发词库检测，所以这种邮件仍可能出现（例如测试账号以外的未登记账号）。
5. 现在 `pi_alerts` 里 T19 时期的旧记录（`alertVersion: 2`）在后台显示为「旧格式告警（没有来源、陪伴者）」，也可以确认处理。
6. 研究日对试跑账号的口径（W0 日期 vs 登记日）等 T24 统一（backlog 100）。
