# T21 研究期和登记（第一部分）报告（2026-10-14，SPEC:C01）

分支 `fix/phase-config-split`。依据：`docs/dev-tasks/dev-tasks-1010.md` 第三节 T21，加 `dev-tasks-1010b.md`（PR #55）对 T21 的更正（只认 `PB-`、`PILOT-`，`PA-` 登记时拒绝）；`dev-tasks-1007b.md` 原任务和 `1008.md` 补充里与之冲突的部分以 1010/1010b 为准。登记表 v8 C01。Phase A 暂停（决策 0034，PR #55）。没有连生产 Firestore，只用模拟器和合成数据。

## 结论

1. **研究期按研究编号前缀**：只认 `PB-`（Phase B）和 `PILOT-`（试跑）。`PA-` 和没有前缀的编号，登记时拒绝（错误码 `research_id_prefix`），什么都不写。
2. **研究期写在哪里**：服务器在登记时写 `users/{uid}.cohort`（`phase_b` / `pilot`，用决策 0011 已定的字段）和 `enrollments/{uid}.studyPeriod`（`B` / `PILOT`）。客户端不能写、不能改（Firestore 规则）。
3. **试跑登记**：负责人在同一个登记页选版本（Hybrid 或规则组），确认框里再选一次，两次一样才能提交；不填 W0 情感分、不占分配序列；研究日从登记日算；每次写一条 `pilot_assignment_log`（研究编号、版本、时间、操作人）。试跑的 Hybrid 账号和 Phase B Hybrid 一样有服务器记忆；试跑不进盲法导出。
4. **登记门**（新开关 `app_config/feature_flags.enrollmentGateEnabled`，**默认关**）：开时，没登记、也不是测试账号的人，App 只显示等待页 S8（定稿文字逐字照抄）；服务器拒绝它的 LLM 调用并记 `llm_denied_log`；Firestore 规则不让它写研究数据。关时和现在完全一样（有测试）。
5. **没做、要定**：编译开关 `PHASE_B` 改成按研究期判断（第 5 节，建议先保留，要 Junyu 定）；广播推送对未登记账号的筛选（交 T24）；盲法人员账号在登记门打开后的去向（交 T30）。
6. **测试**：Flutter 六套、后端（单元、规则、模拟器、删除脚本）全过，见第 7 节。
7. **老人看得到的**：开关关着时没有变化。开关打开后，登记前打开 App 只看到 S8 这一句。登记页的字是给研究员看的，不是老人看的。

## 1. 开关

| 开关 | 位置 | 默认 | 管什么 |
|---|---|---|---|
| `enabled`（已有，T19） | `meta/randomization_config` | 关 | 登记入口。`PB-`、`PILOT-` 登记都要它开 |
| `enrollmentGateEnabled`（新） | `app_config/feature_flags` | 关（只认布尔 `true`） | 等待页、服务器拒绝 LLM、规则拒绝研究数据写入 |
| 前缀规则 | 没有单独开关 | — | 登记本来就在上一个开关后面；现在没有人登记过 |

`enrollmentGateEnabled`：App 启动时读一次；服务器最多 1 分钟后生效（缓存 1 分钟）；Firestore 规则立即生效。

## 2. 研究期按编号前缀

| 编号 | 研究期 | 登记时填 | 组别 | 研究日从 | 日志 |
|---|---|---|---|---|---|
| `PB-…` | `cohort: "phase_b"`、`studyPeriod: "B"` | W0 情感分、阿珍/阿伯、W0 日期 | 分配序列（T19 流程不变） | W0 日期 | `arm_assignment_log` |
| `PILOT-…` | `cohort: "pilot"`、`studyPeriod: "PILOT"` | 阿珍/阿伯、版本 | 负责人指定（`armAssignmentMode: "pilot_designated"`） | 登记日（写进 `w0Date`） | `pilot_assignment_log` |
| `PA-…` | 拒绝 | — | — | — | — |
| 其他 | 拒绝 | — | — | — | — |

- 代码：`functions/study_period.js`（`periodForResearchId`）；`functions/randomization.js`（`enrol`、新的 `enrolPilot`）；App 只用同样的规则决定显示哪些格子（`lib/features/enrollment/data/enrollment_service.dart` `enrollmentPeriodOf`），服务器再查一次。
- 编号格式：整个编号仍按 T19 的规则（2–12 个大写字母、数字或 `-`），前缀后面必须还有字。所以 `PILOT-` 后面最多 6 个字（`PILOT-123456`），`PB-`、`PILOT-` 单独不收。
- **字段名**：用决策 0011 的 `cohort`。原来 `functions/blinding.js`、`functions/djg_w2.js`、`functions/ada.js` 已经先看 `cohort`，这样不用改它们：`phase_b` 进盲法导出和 App 内 W2 DJG；`pilot` 两个都不进；两种都不算 Phase A。决策 0011 里 `pilot` 原指“现有全部旧账号”，这里改用来指 `PILOT-` 试跑。旧账号按 T32 的清理脚本删除，不标 `pilot`，所以实际不会混；但字面上有变化，要 Junyu 定（“要 Junyu 定的事”第 2 项）。

## 3. 试跑登记

1. 登记页输入 `PILOT-…` 后，情感分和 W0 日期两栏换成“试跑版本”两个按钮：「A 組（Hybrid：規則 + AI）」「B 組（規則組）」。确认框里再选一次版本，两次一样才能按「確認登記」。（`lib/features/enrollment/presentation/enrollment_page.dart`）
2. 服务器写入（`functions/randomization.js` `enrolPilot`）：
   - `users/{uid}`：`arm`、`armAssignmentMode: "pilot_designated"`、`armAssignmentMethod: "pilot_designated_v1"`、`armAssignedBy: "researcher"`、`armAssignedAt`、`w0Date`（登记当天，香港时间）、`ahJanAhBakVariant`、`cohort: "pilot"`。没有 `strataCell`。
   - `enrollments/{uid}`：研究编号、`studyPeriod: "PILOT"`、组别、配对、`w0Date`、情感分 / 分层 / 序列位置都是空。
   - 研究编号对照表（`research_ids`、`research_id_map`），和 Phase B 一样。
   - `pilot_assignment_log`：`designate`（第一次）、`resubmit`（重复提交）、`correction`（用 `tool/correct_arm_assignment.js` 更正时）。只有服务器能读写。
3. 重复提交：返回第一次的版本，不改，记 `resubmit`；输入不同时登记页提示“以第一次为准”（和 Phase B 一样）。
4. 不占序列：模拟器测试里两层序列的指针都还是 0，`arm_assignment_log` 没有新行。
5. 试跑的 Hybrid 账号有服务器记忆：`functions/memory.js` `inScope` 和 App 的 `MemoryModes` 把 `pilot_designated` 当作和 `randomise` 一样；`memorySweep` 的查询也包括它（`functions/index.js`）。
6. 整人删除：`pilot_assignment_log` 和分配日志一样保留，删除回执里列为“没有删”（`tool/delete_participant.js`）。T30 改分配记录时一起看。
7. 试跑的压缩日程（每周问卷第 1、3、5、7 天等）不在本任务，交 T24 / T28。现在试跑账号：不进 App 内 W2 DJG（`djg_w2.js` 只认 `phase_b`）；也不收旧的 Phase A 第 2 周推送（`week2Push`，本任务加了跳过）。

## 4. 登记门：等待页和“没登记不收数据”

### 4.1 App

- 顺序：登录 → 研究员账号去登记页（T19 `StaffGate`）→ **登记门**（新 `EnrollmentWaitGate`）→ 同意页、入组问卷 → 首页。等待页放在同意页之前，所以登记前不收同意页之后的任何东西。
- 等待页只有 S8 一句（`lib/features/enrollment/presentation/enrollment_wait_gate.dart`），没有按钮、没有研究期或组别字眼、没有电话。文字和 `docs/spec/copy/short-texts.md` 的 S8 逐字比对（测试）。
- 谁看到等待页：开关开、`cohort` 不是 `phase_b` / `pilot`、`isTester` 不是 `true`。
- App 只在打开时读资料，所以登记后老人要完全关掉 App 再打开，才离开等待页（和 T19 换组别一样，登记页已有这句提醒）。

### 4.2 服务器：LLM

- `proxyDeepSeek`、`referralJudgement`、`webSearch` 共用的 `assertLlmAllowed`（`functions/index.js`）：规则组照旧拒绝；开关开时，再读一次用户文档（不缓存，登记后马上生效），没登记、不是测试账号的拒绝，`llm_denied_log` 记一条，比 T19 多一个字段 `reason: "not_enrolled"`。规则组那种拒绝的记录格式不变（没有 `reason`，没有组别）。
- 记忆整理（`memoryEndSession`、`memorySweep`）本来只对 Phase B Hybrid（含试跑 Hybrid）和自愿开启的测试员做，没登记的账号本来就不在里面。

### 4.3 Firestore 规则：研究数据

- 开关开时，没登记、不是测试账号的人不能写 `users/{uid}/` 下的任何子集合（事件、聊天记录、会话、问卷、W2 DJG、ADA 等）。读自己的数据不受影响。
- 例外：`users/{uid}/fcm_tokens`（推送令牌，不是研究数据）和用户文档本身（注册、同意页要写）。
- `cohort` 加进“只有服务器能写”的字段（和 `arm` 同一组），客户端建档不能带、之后不能改、不能删。
- `safety_events` 等顶层集合没有加限制：安全记录不能被拦。等待页上没有任何输入，所以不会产生。

### 4.4 测试账号怎样识别

`users/{uid}.isTester == true`（布尔值）。注意：这个字段客户端可以写（测试员工具里的“測試員帳號”开关，要先输入测试密码才看得到）。所以一个拿到测试密码的人可以自己绕过登记门。要堵上，得把 `isTester` 也改成只有服务器能写，会影响现有测试员工具，这次没改（“要 Junyu 定的事”第 4 项）。

### 4.5 管不到的地方

1. **广播推送**：每日心情提醒、每周问卷提醒是发给 FCM 主题 `all`（所有装了 App 的手机），没登记的人也会收到；`weeklySurveyReminder` 还会给每个非测试账号写一条 `events`（服务器写，不受规则限制）。T24 重做推送时改成按人发，同时跳过没登记的人。
2. **盲法人员账号**（`blinded` 角色）：开关打开后，如果没有 `cohort`、不是测试账号，也会停在等待页。T30 会让 `blinded` 账号直接进评估员视图；在那之前，开开关前要把团队账号都设成 `isTester: true`。
3. **dev 项目里现有的账号**：都没有 `cohort`。开关一开，除了 `isTester` 的，全部停在等待页。开之前先把团队账号设成测试账号。
4. **费用**：规则里每次客户端写子集合都要读一次 `app_config/feature_flags`（开关关时也读），开时再读一次用户文档。每次写多 1–2 次读取计费，按 72 人的规模可以忽略，记在这里。

## 5. 编译开关和运行时判断（任务第 5 条）

| 编译开关 | 现在管什么 | 用在哪里 | 对应的运行时判断 / 建议 |
|---|---|---|---|
| `PHASE_B` | 按组别显示界面；不加就是 Phase A 包（全员 A 组）。也决定 ADA、第 7 日、App 内 W2 DJG、研究员后台 Phase A 板块 | `lib/core/arm/arm_scope.dart`、`lib/core/memory/memory_mode.dart`、`lib/features/ada/data/ada_gate.dart`（4 处）、`lib/features/assessment/data/djg_w2.dart`、`lib/features/phase_b_probes/data/phase_b_probes.dart`、研究员后台、设置页、`lib/main.dart`（2 处） | 见下 |
| `FORCE_ARM` | 本地调试强制组别 | `arm_scope.dart` | 保留，只调试用，不能发布 |
| `MEMORY_V1` | 测试员自愿开记忆 v1 | `memory_mode.dart`、设置页 | 保留，只测试用 |
| `WEEKLY_PROBE` | 周度孤独感问卷 | `feature_flags.dart` | 已从问卷包去掉（登记表 C15），保留关着 |
| `RULE_TEMPLATE_REPLIES`（及 `_ALLOW_PLACEHOLDER`） | 规则组模板回应 | `rule_reply_pool.dart` 等 | 不按研究期：两期同一套。是否改成远程配置另议 |
| `LEGACY_AGENT_DIFF_PHASE_B` | Phase B 包里恢复旧问卷 | `ada_gate.dart` | 保留关着 |
| `TESTER_PIN` | 解锁测试工具 | `tester_gate.dart` | 保留 |
| `FORCE_LLM_FALLBACK` | 测试 LLM 失败 | `llm_gateway.dart` | 保留，只测试用 |

**`PHASE_B` 怎样处理，没有改，要 Junyu 定**（“要 Junyu 定的事”第 1 项）。理由：

- Phase A 暂停以后，这个项目只有 `PB-` 和 `PILOT-` 两种人，两种都要 Phase B 的行为。参与者包固定 `PHASE_B=true`（Build APK 的 `phase_b`），就已经是“同一个构建”。
- 改成按研究期判断，要改上表 8 个文件，而且没登记的人（`cohort` 为空）该显示哪种界面要另定；登记门打开时他们只看到等待页，这个问题就不存在。
- Phase A 专用的行为在 `PHASE_B=true` 的包里已经关住：`AdaGate`（`ada_gate.dart`：ADA、第 7 日、旧问卷）、`week2Push` 对 `phase_b` 和 `pilot` 不推（`djg_w2.js` `week2PushShouldSkip`、本任务的 `skipsPhaseAWeek2Push`）、`functions/ada.js` 只推 `cohort: "phase_a"`（现在没有这种人）。

## 6. 第 6、7 条和 1008 补充里其他几条

- **语音开关**（第 6 条）：只要 Phase B 一份，试跑跟 Phase B（1010b 更正第 3 条）。现在的 `app_config/feature_flags.voiceInputEnabled` 本来就只有一份，所以不用拆，也没有改。
- **“只在 Phase B”的判断改看研究期**（1008 补充第 4 条）：

| 位置 | 改前 | 改后 |
|---|---|---|
| `functions/djg_w2.js` `isPhaseBParticipant` | 先看 `cohort`，没有再看 `armAssignmentMode == randomise` | 没改代码；T21 起登记会写 `cohort`，所以按研究期判断（`pilot` 不算） |
| `functions/blinding.js` `isBlindedParticipant` | 同上 | 同上：只导出 `phase_b`，试跑不进 |
| `functions/ada.js` `isPhaseAParticipant` | 先看 `cohort == phase_a`；没有再按“不是 Phase B” | 没改代码：`phase_b`、`pilot` 都不是 Phase A |
| `functions/memory.js` `inScope` | Hybrid 且 `randomise` | Hybrid 且 `randomise` 或 `pilot_designated` |
| `functions/index.js` `memorySweep` | 查 `randomise` | 查 `randomise` 和 `pilot_designated` |
| `functions/index.js` `week2Push` | 跳过 Phase B（W2 DJG 开时） | 另跳过试跑；开关开时跳过没登记的 |

- **研究日从登记时开始**（第 3 条）：Phase B 用登记时填的 W0 日期（T19 已是这样）；试跑由服务器把登记日写进 `w0Date`，App 的 `w0DateFor` 和服务器的 `w0DateKey` 都先用它。`dayOneAnchor` 是 Phase A 的配置，Phase A 暂停，没做。
- **原任务（1007b）里按研究期拆配置、名单互斥、Phase B 配置冻结**：Phase A 暂停后只剩 Phase B 和试跑，两者用同一套配置；拆配置和名单互斥现在没有对象，没做。Phase B 配置冻结是上线时的操作，不在代码里。

## 7. 测试

| 任务单第 8 条（1010b 改后） | 测试 | 结果 |
|---|---|---|
| `PB-`、`PILOT-` 各登记 1 人 | `functions/test/randomization_emulator_test.js`「T21: PB- registers…」「T21: PILOT- takes the researcher's version…」 | 通过 |
| `PA-` 和没有前缀的编号被拒 | 同上「T21: PA- and IDs without PB- / PILOT- are refused」；`functions/test/study_period_test.js`；`test/enrollment_page_test.dart` | 通过 |
| 没登记的账号只看到等待页 | `test/enrollment_wait_gate_test.dart`（只有 S8、没有按钮和输入框；S8 和定稿逐字一致；开关只认 `true`） | 通过 |
| 服务器没有它的研究记录 | `test/rules/enrollment_gate_rules.test.js`（写事件、聊天、W2 DJG 被拒；推送令牌、用户文档可写；读不受影响） | 通过 |
| LLM 调用被拒并有日志 | `functions/test/enrollment_gate_emulator_test.js`（`reason: not_enrolled`，没有调用模型；测试账号、`phase_b`、`pilot` 照常；规则组照旧拒绝；登记后马上可用） | 通过 |
| 试跑选版本后组别正确、没占序列、有日志 | `randomization_emulator_test.js`「T21: PILOT-…」三项 | 通过 |
| 开关关时和现在一样 | 上面三个文件里“gate off”各项；原有 T19 测试全部保留（`randomization_emulator_test.js`、`blinding_emulator_test.js` 里的编号从 `B001` 这类改成 `PB-001`，因为没有前缀的编号现在会被拒） | 通过 |

全量（Flutter 3.35.3、Node 24、Firestore 模拟器）：`tool/ci_flutter_tests.sh` 六套全过（默认构建 402 个，跳过 21；Phase B 61；规则组页面 5；记忆 v1 17；模板两套 12 和 16）；`tool/ci_backend_tests.sh` 全过（其中 `study_period_test.js` 8 项、`enrollment_gate_emulator_test.js` 7 项、`randomization_emulator_test.js` 20 项、`blinding_emulator_test.js` 7 项、Firestore 规则 95 项）；`flutter analyze` 0 error（88 条旧提示，和 main 一样）。

## 8. 改了哪些文件

- 服务器：`functions/study_period.js`（新）、`functions/randomization.js`、`functions/index.js`（`assertLlmAllowed`、`memorySweep`、`week2Push`、`enrollParticipant`）、`functions/memory.js`（`inScope`）、`firestore.rules`、`tool/delete_participant.js`（只改说明和回执）。
- App：`lib/features/enrollment/presentation/enrollment_wait_gate.dart`（新）、`enrollment_page.dart`、`lib/features/enrollment/data/enrollment_service.dart`、`lib/features/auth/presentation/pages/auth_gate.dart`、`lib/features/auth/data/user_profile.dart`（`cohort`，只读）、`lib/core/feature_flags/remote_feature_flags.dart`、`lib/core/memory/memory_mode.dart`。
- 测试：`functions/test/study_period_test.js`（新）、`functions/test/enrollment_gate_emulator_test.js`（新）、`functions/test/randomization_emulator_test.js`、`functions/test/blinding_emulator_test.js`（原有登记测试的编号改成 `PB-` 开头）、`test/rules/enrollment_gate_rules.test.js`（新）、`test/rules/package.json`、`test/enrollment_wait_gate_test.dart`（新）、`test/enrollment_page_test.dart`、`test/memory_v1_client_test.dart`。
- 文档：`docs/dev/architecture.md` 第 4、12 节、`docs/STUDY_CHANGELOG.md`、`docs/history.md`、`docs/dev/backlog.md` 第 71 项、本报告。

没有写新的决策记录：前缀、试跑由负责人指定、等待页、不收数据都是登记表 v8 和任务单已定的；按负责人这次的要求不分配决策编号。要不要补一份，见“要 Junyu 定的事”第 3 项。

## 9. 和其他 PR 的交叉

- 用 `git merge-tree` 模拟过：和 #51 没有冲突；和 #52、#55、#57 只在文档上冲突；和 #56 另有 `lib/core/feature_flags/remote_feature_flags.dart` 一处代码冲突（它加 `memoryLayersNoticeEnabled`，这里加 `enrollmentGateEnabled`，两个都留就行），`functions/memory.js` 能自动合并。
- 和 PR #52、#57、#56、#55、#51 都改 `docs/STUDY_CHANGELOG.md`、`docs/history.md`、`docs/dev/backlog.md`、`docs/dev/architecture.md`，后合并的两边都留。
- T24、T27、T30、T34 要用这里的 `cohort` 和 `study_period.js`：研究期判断请直接用 `isEnrolled`、`periodForResearchId`，不要另写一套。

## 要 Junyu 定的事

1. **编译开关 `PHASE_B`**
   - (a) 保留：参与者包固定 `PHASE_B=true`，Phase A 恢复时再改（本 PR 的做法）；
   - (b) 删掉：Phase B 行为变成默认，Phase A 那条路径（全员 A 组）删掉或改成按 `cohort: phase_a` 判断；
   - (c) 改成按研究期在运行时判断（改 8 个文件，没登记的人显示哪种界面要另定）。
2. **字段名 `cohort` 里的 `pilot`**
   - (a) 用 `pilot` 指 `PILOT-` 试跑（本 PR 的做法）；旧账号按 T32 删除，不标 `pilot`；
   - (b) 试跑另起一个值（例如 `pilot_run`），把决策 0011 的 `pilot` 留给旧账号；
   - (c) 不用 `cohort`，另起字段 `studyPeriod`（要改 `blinding.js`、`djg_w2.js`、`ada.js` 的判断）。
3. **要不要补决策记录**（CLAUDE.md 要求设计决定先写决策记录；这次按要求没分配编号）
   - (a) 不用：都是登记表 v8 和任务单已定的事，实现细节写在本报告；
   - (b) 补一份，编号由 Junyu 分配，内容是第 2、3、4 节的做法。
4. **`isTester` 客户端能写**（第 4.4 节）
   - (a) 维持：测试密码只给团队；
   - (b) 改成只有服务器能写，测试员工具里的开关改成只显示、要用脚本或控制台设。
5. **试跑的研究日起点**
   - (a) 登记当天（本 PR 的做法，按任务单“试跑用登记日”）；
   - (b) 和 Phase B 一样在登记页填一个日期。
6. **登记门打开的时间**：要在 T24（推送按人发）和 T30（盲法人员账号）之后，还是先开、接受第 4.5 节的缺口。
