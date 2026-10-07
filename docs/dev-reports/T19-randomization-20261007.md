# T19 App 内分组重做（2026-10-07，SPEC:C01）

> 任务单：`docs/dev-tasks/dev-tasks-1007b.md` T19。分支 `fix/randomization`。决策记录 0029（取代 0003）。
> 只用 Firebase 模拟器和合成数据，没有连正式项目。

## 0. 结论

1. **Phase B 改为研究员登记后分组**：老人先注册；非盲研究员（Keran）用自己的账号登录同一个 App，直接进「研究員登記」页，录入研究编号、W0 纸本 DJG 情感分（提交前再选一次）、阿珍/阿伯、W0 日期。服务器按情感分分层（0–1 低、2–3 高），在事务里取该层置换区组序列的下一个位置，写组别和日志。
2. **旧的最小化分配删除**，计数器 `meta/arm_counter` 客户端一律不能读写，`app_config/arm_assignment` 停用。只有一条分组路径。
3. **角色改名**：`unblinded`（Keran）、`blinded`（PI 和其他盲法人员）。旧名 `pi`、`researcher` 不再有任何权限。
4. **发给 PI 的告警**原来带来源、输入点、陪伴者，能推出组别；现在去掉，两组内容一样，告警照发。
5. **W0 日期**优先用登记日，没有再用账号创建日。
6. **开关** `meta/randomization_config.enabled`，**默认关**。72 个合成参与者测试：每层两组人数最多差 2，没有重复占位，客户端读写全部被拒，盲法导出看不到组别。

## 1. 现状（改之前）

| 项目 | 现状 | 位置 |
|---|---|---|
| 算法 | 不是随机序列，是**最小化**：层内 A、B 人数少的那组优先，一样多才抛硬币（`Math.random`，不能复现） | 原 `functions/arm.js` `chooseArm` |
| 分层变量 | UCLA 基线分（>44 高）× 年龄组（≥70 高），4 层。两个值都在 `users/{uid}`，是注册表单填的（`ageGroup` 老人选，`baselineUclaScore` 研究员在"研究人員填寫"栏填），分组前本人可改 | 原 `functions/arm.js` `strataCell`；`lib/features/auth/presentation/pages/login_page.dart:73` |
| 计数器 | `meta/arm_counter`，每层 `aCount`、`bCount` | 原 `firestore.rules` `match /meta/arm_counter` |
| 谁能写 | 服务器在事务里写；**任何登录用户也能写**（规则只要求每次某一格 +1），能影响后来者的分组。读：只有 `role: pi` | 同上（T13 报告第 5 条） |
| 触发 | 注册后 App 调 `assignArm`，登录时补分 | `lib/features/auth/data/auth_service.dart` |
| 审计 | 没有每次分配的日志 | — |

## 2. 登记入口：选了 App 里的研究员页面

**怎么对上账号**：老人先在自己手机上注册（研究员在旁协助，现有流程不变），研究员再在自己手机上按**老人的登入电邮**登记。服务器先试运行，返回账号名字和注册日期给研究员核对，确认后才分组。

**理由**：

| 方案 | 结论 |
|---|---|
| **App 里的研究员页面（选这个）** | 入组现场研究员手里就有手机，不用电脑、不用命令行；用自己的 Firebase 账号登录，服务器能记下是谁登记的；权限只到"登记"这一件事 |
| 管理脚本 | 要装 Node 和服务账号密钥；服务账号能读写全部数据，权限过大；"哪位研究员操作的"只能自报 |
| 研究员先建、老人注册时输入编号认领 | 在老人手机上多输一次编号，输错就绑错人 |
| 配对码 | 要多做一套码；研究员本来就帮老人建了电邮账号 |

**页面**（`lib/features/enrollment/`，单独的文件夹，减少和 T17 冲突）：

- `presentation/staff_gate.dart`：登录后读 Auth 角色。`unblinded` → 登记页；其他人（老人、盲法人员、旧角色名）、读不到或 5 秒没回应 → 普通 App。老人看不到这个入口。`auth_gate.dart` 只改了一处（包一层 `StaffGate`）。
- `presentation/enrollment_page.dart`：填电邮、研究编号、情感分（0/1/2/3 四个按钮）、阿珍/阿伯、W0 日期（默认今天，不能选将来）→「檢查」→ 确认框列出账号名字、编号、分数和层、配对、日期，**再选一次情感分**，两次一致才能按「確認登記」→ 显示组别。已登记过的账号直接显示原组别。
- `data/enrollment_service.dart`：调 Cloud Function `enrollParticipant`。T21 要加的"研究期"字段在 `EnrollmentInput` 里留了位置；服务器登记记录里已有 `studyPeriod`（现在固定 `B`）。
- 页面文字是给研究员看的，不是老人看的。

**服务器**（`functions/randomization.js` `enrol`；`functions/index.js` `enrollParticipant`）再查一次角色，拒绝：开关关、角色不对、账号不存在、已有组别（试用/Phase A）、测试员、研究编号已被别人用、账号已有别的研究编号、自己的账号、分数不是 0–3 整数、编号格式不对（2–12 位大写字母、数字、`-`）、W0 日期在将来、没确认、序列没上传或用完。

## 3. 分配序列

- 脚本 `tool/randomization_sequence.js`（只给非盲研究员用）：种子至少 16 个字符，建议用 `--seed-file` 传入（不留在命令历史）。每层一条，1:1 置换区组，区组大小 2 和 4 随机混用（各约一半），整块生成直到至少 60 个位置（实际 60–63）。同一个种子生成同样的序列，可以复核。
- 随机数：HMAC-SHA256（种子作密钥）计数器模式 + 拒绝采样，没有取模偏差（`seededRandomInt`）。
- **不生成文件之外的副本**：屏幕上只显示长度、区组数、SHA-256 指纹。文件写到 `randomization-private/`（权限 600），里面有种子和两条序列，交导师离线保存后从电脑删掉。`.gitignore` 已加 `randomization-private/`、`randomization_sequence_*.json`、`*.seed`、`*seed*.txt`。
- 上传 `--upload`：写 `randomization_sequences/{low,high}`（`arms`、`blocks`、`length`、`sha256`、上传人、时间，**不含种子**）和 `randomization_state/{low,high}.next = 0`。已上传就拒绝；加 `--replace` 也只在两层都还没人分配时允许。
- 默认只对模拟器执行；正式项目要同时给 `--project=<id>` 和 `--production-confirm=<同一 id>`（`tool/firestore_target.js`，和 `prelaunch_config.js` 同一规则）。本任务没有执行过正式项目路径。
- 客户端（老人、盲法、非盲）都不能读写序列和指针（规则测试见第 8 节）。

## 4. 分配、日志、更正

- 事务里一次写完：`randomization_state/{层}.next + 1`；`users/{uid}`：`arm`、`strataCell`（0 低 / 1 高）、`armAssignmentMode: "randomise"`、`armAssignmentMethod: "permuted_block_v1"`、`armAssignedBy: "server"`、`armAssignedAt`、`w0Date`、`ahJanAhBakVariant`；`enrollments/{uid}`（编号、分数、层、配对、W0 日期、组别、序列位置、序列指纹、`studyPeriod`、时间、研究员 uid 和电邮）；`research_id_map/{uid}`、`research_ids/{编号}`（`via: "enrollment"`）；`arm_assignment_log` 一条 `allocate`（研究编号、层、序列位置、组别、时间、研究员）。
- `armAssignmentMode` 仍写 `randomise`，所以记忆（`functions/memory.js` `inScope`）、W2 DJG（`djg_w2.js` `isPhaseBParticipant`）、盲法导出（`blinding.js` `isBlindedParticipant`）不用改就认得这些人。
- **重复提交**：返回原组别，不占新位置，记 `resubmit`（`sameInput` 标出这次输入和第一次是否一样；不一样时页面提示"以第一次为准"）。
- **更正**：`tool/correct_arm_assignment.js --research-id=… --arm=… --reason="…" --operator=… --confirm`，理由至少 10 个字，默认只打印不写、默认只对模拟器。改 `users` 和 `enrollments` 的组别，序列位置不变，记 `correction`（原组别、新组别、理由、操作人）。客户端改不了组别和 W0 日期（规则）。
- 服务器的分组缓存原来是永久的，改为 10 分钟过期，更正最迟 10 分钟在所有实例生效（`functions/index.js` `armFor`）。
- **组别显示**：只在登记页显示一次（还有登记记录、日志，客户端都读不到）。老人完全关闭 App 再打开后按新组别显示（App 只在启动时读资料）。

**阿珍/阿伯**：登记时写进 `users/{uid}.ahJanAhBakVariant`，登记记录里也存一份。没有锁成只有服务器能写：老人在 onboarding 和陪伴者介绍页能改，App 保存整份资料时会带上这个字段，锁上会让老人的保存整份失败。所以 App 里的值可能被老人改掉，研究员登记的值以 `enrollments` 为准（待办第 74 项）。

## 5. 登记前（组别为空）的这段时间

- 老人注册后到研究员登记前，`arm` 为空，App 显示规则组界面（决策 0004），`assignArm` 不分组（开关开着时）。
- **数据怎么处理**：这段时间产生的对话、问卷等都带空组别或 B 组界面的行为。分到 Hybrid 组的人如果没在当天登记，前几次用的是规则组界面。建议：入组当天、老人离开前完成登记，并当场让老人关闭再打开 App；分析时以 `enrollments/{uid}.enrolledAt`（或 `armAssignedAt`）为干预开始，之前的数据单独标出或剔除。由研究侧定（待办第 72 项）。
- 服务器在这段时间**不拒绝** LLM：现在区分不出"Phase B 未登记"和"Phase A"（Phase A 也是空组别运行）。App 显示规则组界面，不会调用 LLM。T21 加了研究期字段后，可以对未登记的 Phase B 账号也拒绝。
- 开关关着时，`assignArm` 照旧给 Phase A / pilot 分 A 组。**所以开关必须在第一位 Phase B 老人注册前打开**，否则这位老人会被分进 A 组（写入后不能改）。已写进上线清单 C2。

## 6. 角色和迁移

| | 以前（T12） | 现在 |
|---|---|---|
| 非盲 | `role: pi` | `role: unblinded`（Keran）：登记、看组别、读研究编号对照表、后台看两组人数、生成上传序列 |
| 盲法 | `role: researcher` | `role: blinded`（PI 和其他盲法人员）：后台不显示两组人数和单组板块，只用盲法导出 |
| 旧名字 | — | `pi`、`researcher` 一律没有权限 |

一起改的地方：`firestore.rules` `isUnblinded()`；`lib/features/researcher_dashboard/data/dashboard_access.dart`；`lib/features/enrollment/data/enrollment_service.dart`（`isUnblindedClaims`）；`functions/randomization.js`（`UNBLINDED_ROLE`）；`tool/provision_researcher.js`；测试 `test/dashboard_access_test.dart`、`test/rules/blinding_rules.test.js`、`test/enrollment_page_test.dart`。

**迁移**：旧名字故意不自动换成新名字（旧的 `pi` 是非盲，自动换成任何一个都可能给错人）。步骤：
1. `NODE_PATH=functions/node_modules node tool/provision_researcher.js --list-legacy` 列出还带旧名字的账号；
2. 逐个 `--email=… --revoke`；
3. Keran `--role=unblinded`；PI 和其他人 `--role=blinded`。
脚本收到 `--role=pi` 会拒绝并提示 PI 现在是 `blinded`。上线清单 B4 要求 `--list-legacy` 显示 0 个。

## 7. 发给 PI 的东西会不会揭盲

| 东西 | 查到什么 | 处理 |
|---|---|---|
| `onSafetyEventCreated` 发给 `PI_EMAIL` 的邮件 | 主题带 `agentId`，正文带 `Agent`、`Source`、`Input point`、`Event path`。`source` 的 `gateway_input/gateway_output`、`ai_output_scan` 只有 Hybrid 组，`rule_turn` 只有规则组；`inputPoint` 的 `chat_reflective`、`system_generated`、`article_qa`、`search_query` 只有 Hybrid 组 | 改为只有：研究编号（未登记写"not registered yet"）、香港时间、告警编号；说明细节由非盲研究员按告警编号查。主题固定。两组完全一样（`functions/pi_alert.js` `buildPiEmail`） |
| `pi_alerts` 文档 | 带 `source`、`inputPoint`、`agentId` | 去掉，只留 uid、研究编号、级别、`dedupKey`、`isTester`、`eventPath`、时间、`alertVersion: 2`（`buildPiAlert`）。客户端本来就读不到 |
| 告警是否照发 | — | 照发：每条 acute（含同一轮升级成 acute）写一条告警、发一封邮件；测试员照旧只记不发。检测、分级、去重都没改（`functions/test/safety_t7_emulator_test.js` 新测试：两组各一条 acute，都告警，字段一样） |
| 告警次数 | Hybrid 组多一种来源（AI 回复扫描），告警次数可能偏多 | 没法去掉，否则削弱安全告警。写进"要带回研究侧" |
| 研究员后台 | 盲法角色已不显示两组人数和单组板块（T12）。"未處理嘅 distress flags"读 `shared_context.safetyFlags`，显示陪伴者名和原话片段；代码里**没有地方写** `safetyFlags`（`addSafetyFlag` 没人调用），这一栏永远是空的。后台在 App 里也没有入口 | 没改。以后要接上这一栏，得先去掉陪伴者和来源 |
| 盲法导出 | T12 已处理；登记的研究编号能进导出（`blinding.js` `ENROLLED_RID_PATTERN`，检查脚本也认） | 测试：8 个登记过的人导出后检查脚本退出 0，行里没有 `arm` |
| Firebase 控制台 | 能读 Firestore 的人能直接看组别和序列 | 清单 G6：PI 的 Google 账号不要有读 Firestore 的角色 |

决策 0029 第五条、STUDY_CHANGELOG 已写。

## 8. 两组隔离的检查点

| 检查点 | 在哪里 | 行为 |
|---|---|---|
| 对话 LLM | `functions/index.js` `proxyDeepSeek` → `assertLlmAllowed` | B 组拒绝 + `llm_denied_log` 记一条（uid、接口、时间，不存文字和组别） |
| 跨陪伴者转介判断 | 同上 `referralJudgement` | 同上 |
| 网络搜索 | 同上 `webSearch` | 同上（另外 `webSearchEnabled` 默认关） |
| 记忆整理 | `functions/memory.js` `inScope` | B 组不在范围，`memoryEndSession` 返回 `inactive`，不调用模型 |
| 安全分类器 | `classifySafety` | 不是对话模型，两组都用（决策 0025），不经过上面的拦截 |
| 只有 Hybrid 才有的入口 | `lib/core/arm/arm_scope.dart` `ArmGate` / `Arm.isA`；组别为空也显示 B 组界面 | 不变 |
| 组别缓存 | `armFor` | 10 分钟过期 |

测试：`functions/test/safety_t7_emulator_test.js` "Arm B still refused"：拒绝、记一条 `llm_denied_log`（`endpoint: proxyDeepSeek`，没有 `arm` 字段）、没有 `llm_calls`。

## 9. 72 个合成参与者（模拟器）

`functions/test/randomization_emulator_test.js`。72 个账号，W0 情感分用固定种子随机给（0–3），两位研究员账号成对同时提交（每次 `Promise.all` 两个），序列由测试种子生成。

**每层结果**：

| 层 | 人数 | A | B | 最后的人数差 | 过程中最大人数差 |
|---|---|---|---|---|---|
| 低（0–1 分） | 23 | 12 | 11 | 1 | 2 |
| 高（2–3 分） | 49 | 24 | 25 | 1 | 2 |

（区组最大是 4，所以任何时候层内人数差不会超过 2；测试里断言了这一点。）

**其他检查**：

| 检查 | 结果 |
|---|---|
| 序列位置 1…n 连续、不重复；每人的组别 = 序列该位置的组别 | 通过 |
| 两位研究员同时提交（36 对）：没有两个人占同一个位置；日志里两人各 36 条 | 通过 |
| 同一个人 4 次同时提交：只分配一次，其余返回原组别 | 通过 |
| 两个账号同时用同一个研究编号：一个成功，一个 `research_id_taken`，只占一个位置 | 通过 |
| 重复提交（5 人 × 2 次，第二次分数不同）：组别和层不变，不占位置，记 10 条 `resubmit` | 通过 |
| 试运行：返回账号名字，不返回组别，什么都不写 | 通过 |
| 开关关时、非 `unblinded` 角色（`blinded`、`pi`、`researcher`、无）都拒绝 | 通过 |
| 已有组别、测试员、账号已有别的编号、序列没上传、序列用完：都拒绝，不占位置 | 通过 |
| 更正：理由太短拒绝；改后日志有原组别、新组别、理由；序列位置不变 | 通过 |
| 上传：已上传拒绝；已有人分配后 `--replace` 也拒绝；上传的文档里没有种子 | 通过 |
| `assignArm`：登记过的返回原组别；没登记的返回空 | 通过 |
| 盲法导出：8 个登记的人，行里没有 `arm`、编号是登记的编号、组别代码是 Group_X/Y；检查脚本退出 0 | 通过 |

**客户端读写被拒**（`test/rules/randomization_rules.test.js`，老人、`blinded`、`unblinded`、未登录四种身份）：

| 对象 | 读 | 写 / 改 / 删 |
|---|---|---|
| `randomization_sequences`、`randomization_state` | 拒绝 | 拒绝 |
| `enrollments`、`arm_assignment_log`、`llm_denied_log` | 拒绝 | 拒绝 |
| `meta/randomization_config`、`meta/arm_counter`（含旧的合法 +1 写法） | 拒绝 | 拒绝 |
| `users/{uid}` 的 `arm`、`w0Date`、`armAssignmentMethod` | 本人可读自己的资料 | 本人不能设、不能改；建档时不能带 `w0Date` |
| 别人的 `users/{uid}`（盲法、非盲人员） | 拒绝 | — |

**盲法视图看不到组别**：后台 `DashboardAccess.blinded` 不显示两组人数和单组板块（`test/dashboard_access_test.dart`）；`StaffGate` 对 `blinded` 和旧名字显示普通 App，不显示登记页（`test/enrollment_page_test.dart`）；规则上盲法角色读不到用户资料和登记记录；盲法导出没有组别（上表）。

**App 页面测试**（`test/enrollment_page_test.dart`）：字段不全不能检查；先试运行、再选一次分数，不一致不能确认；取消不分组；已登记直接显示原组别；服务器拒绝时显示中文原因；`w0DateFor` 登记日优先、格式错误或不存在退回 `createdAt`、`w0Date` 不会被 App 写回。

**两套全量测试**（2026-10-07，推送前各跑一次）：
- `tool/ci_backend_tests.sh`：全部通过（规则测试 81 个；新增 `randomization_test.js` 9 个、`randomization_emulator_test.js` 14 个、`arm_emulator_test.js` 6 个；`safety_t7` 14 个、`prelaunch_config` 6 个、`blinding_emulator` 7 个）。
- `tool/ci_flutter_tests.sh`：六套构建变体全部通过（376 / 49 / 5 / 16 / 12 / 16 个）。

## 10. W0 日期

- 登记时记 `w0Date`（`YYYY-MM-DD`，香港日期，默认登记当天，可改成过去 60 天内的日期）。
- App `w0DateFor`（`lib/core/scheduling/w0_date.dart`）、服务器 `w0DateKey`（`functions/djg_w2.js`）：先用 `w0Date`，没有或格式不对再用 `createdAt`。W2 DJG 的第 14 天按这个日期算。
- **T17 的"第 1 次到访"**（Phase A ADA `visit1`）现在按账号创建日算（`pending_prompts_service.dart` `enrolmentDay(createdAt, …)`），这次没改：Phase A 不走这个登记入口（序列分组只用于 Phase B）。**登记日能不能当第 1 次到访日**：只有在第 1 次到访当场登记时才能。T21 让 Phase A 也经这个入口登记后，建议 Phase A 的日程也改用 `w0DateFor`（登记日），而不是账号创建日——老人可能在到访前就自己注册了。

## 11. 开关和配置

| 名字 | 默认 | 作用 |
|---|---|---|
| `meta/randomization_config.enabled` | `false`（文档不存在 = 关） | 开：可以登记分组；`assignArm` 不再分组。关：不能登记；`assignArm` 给 Phase A / pilot 分 A 组（和以前一样） |
| `meta/randomization_config` 其余字段 | 由 `prelaunch_config.js` 写 | `stratifyBy: w0_djg_emotional`、`strata: low=0-1,high=2-3`、`method: permuted_block_v1`、`blockSizes: 2,4`，只做配置快照记录；分层和方法写死在 `functions/randomization.js` |
| `app_config/arm_assignment.randomise` | 停用 | 开关关着时它若为 true，`assignArm` 拒绝分组（返回 `randomise_retired`），不会误分 A 组 |

**`tool/prelaunch_config.js`**：写 `meta/memory_config` 和 `meta/randomization_config`；**检查**两条序列已上传、至少 60 个位置、已用几个（只打印长度和指纹，不打印组别，所以 PI 也可以跑）；`app_config/arm_assignment.randomise` 还是 true 时提示删掉。`--reset-arm-counter` 随计数器删除。序列上传不放进这个脚本：PI 会跑这个脚本，而 PI 不能接触序列。

**上线清单**（`docs/release/prelaunch-checklist.md`）：B4 角色按新名字发放；C2 开关；C3 序列已上传；C3b 删 `app_config/arm_assignment`；新的 G 节：G1 生成、G2 上传、**G3 种子已离线保存**、**G4 HTML 工具已停用**、G5 Firestore 数据访问审计日志（Google Cloud 控制台操作步骤）、G6 PI 不要有读 Firestore 的项目权限。

## 12. 删掉或停用的旧路径

- `functions/arm.js` 的 `strataCell`、`chooseArm`（最小化）和计数器写入；`functions/test/arm_test.js`。
- `lib/features/auth/data/arm_assigner.dart` 的 `strataCell`、`ageYearsFromGroup` 和它们的测试（`test/sprint1_contracts_test.dart`、`test/sprint4_spec_alignment_test.dart` 各一组）。
- `firestore.rules` 的计数器增量规则 → 一律拒绝；`test/rules/arm_counter.test.js` 删除。
- `assignArm` 不再生成研究编号（Phase B 的编号由登记写入；导出时的补发 `ensureResearchId` 还在，并认登记的编号）。
- 注册表单的 UCLA、年龄组字段还在（只是不再用于分层），没动。

## 13. 改了哪些文件

- 新增：`functions/randomization.js`、`functions/pi_alert.js`、`tool/randomization_sequence.js`、`tool/correct_arm_assignment.js`、`tool/firestore_target.js`、`lib/features/enrollment/`（3 个文件）、`functions/test/randomization_test.js`、`functions/test/randomization_emulator_test.js`、`test/rules/randomization_rules.test.js`、`test/enrollment_page_test.dart`、决策 0029。
- 修改：`functions/arm.js`、`functions/index.js`、`functions/blinding.js`、`functions/djg_w2.js`、`firestore.rules`、`lib/core/scheduling/w0_date.dart`、`lib/features/auth/data/{arm_assigner,auth_service,user_profile}.dart`、`lib/features/auth/presentation/pages/auth_gate.dart`（一处）、`lib/features/researcher_dashboard/`（角色名）、`tool/{provision_researcher,prelaunch_config,check_blinded_export,delete_participant}.js`、相关测试、`.gitignore`、文档（architecture、STUDY_CHANGELOG、history、backlog、上线清单、决策 0003/0021 标注）。
- 整人删除（`tool/delete_participant.js`）：加删 `enrollments/{uid}`、`llm_denied_log`；`arm_assignment_log` 和已用的序列位置保留（列在"没覆盖"里）。

## 要带回研究侧的发现

1. **登记前的数据**：每位 Phase B 老人从注册到登记之间都是"空组别、规则组界面"。建议入组当天登记并当场重开 App；这段数据计入还是剔除、以什么时间点算干预开始，请定（待办第 72 项）。
2. **开关必须在第一位 Phase B 老人注册前打开**，否则这位老人会被当作 Phase A 分进 A 组且不能改（只能走更正脚本）。
3. **PI 收到的告警只剩研究编号、级别、时间**，不再有陪伴者和来源；PI 跟进时如需细节要问 Keran。Hybrid 组多一种告警来源（AI 回复扫描），两组告警次数可能不同，这无法在不削弱安全的前提下消除。
4. **PI 的项目权限**：PI 的 Google 账号如果在 Firebase/Google Cloud 有 Owner、Editor 或 Firestore 读取角色，就能在控制台直接看到组别和序列。请核对（清单 G6）。
5. **审计日志的口径**：Firestore 数据访问审计日志能记下谁在控制台读过序列和分组；经 Cloud Function 的读写记在函数服务账号名下，谁登记看 `arm_assignment_log`。审计日志会产生费用和保留期，要写进 DMP（待办第 73 项）。
6. **分配记录保留**：整人删除时分配日志和已用序列位置现在保留（试验完整性），登记记录删除。请确认，并和 ICF 的删除说法对上（待办第 73 项）。
7. **研究编号格式**：现在接受 2–12 位大写字母、数字、`-`（如 `B001`）。如有固定格式请给，可以收紧（待办第 74 项）。
8. **阿珍/阿伯**：研究员登记的值会写进 App，但老人在 App 里仍能改；以登记记录为准。要不要禁止老人改，请定（待办第 74 项）。
9. **Phase A 的"第 1 次到访"**目前按账号创建日。T21 让 Phase A 也经登记入口后，建议改按登记日（第 10 节）。
10. **protocol / 统计分析计划**要改写随机化方法：W0 DJG 情感分分层、层内 1:1 置换区组（2 和 4）、非盲研究员生成序列、服务器登记时分配；最小化不再适用。
