# 0029：Phase B 由非盲研究员登记后分组，按 W0 DJG 情感分分层、置换区组；PI 改为盲法角色，给 PI 的告警不带组别线索

- 日期：2026-10-07
- 状态：提议中（随 T19 的 PR 草稿，合并即采纳；开关默认关）
- 影响范围：phase_b × 两组（分组、W0 日期）；所有 cohort（角色、给 PI 的告警）
- 相关代码：分支 `fix/randomization`（T19，SPEC:C01）。`functions/randomization.js`、`functions/arm.js`、`functions/pi_alert.js`、`functions/index.js`（`enrollParticipant`、`assertLlmAllowed`、`onSafetyEventCreated`）、`firestore.rules`、`lib/features/enrollment/`、`tool/randomization_sequence.js`、`tool/correct_arm_assignment.js`、`tool/provision_researcher.js`、`tool/prelaunch_config.js`
- 取代：决策 0003（分组方式）。决策 0021 的角色部分（`pi` = 非盲）

## 背景

研究侧 10/7 定了：分组在 App 内完成，不再用 HTML 随机化工具；分层用 W0 纸本 DJG 情感分量表分（研究员录入，0–1 低、2–3 高），不用老人自填的年龄组和 UCLA；每层 1:1 置换区组，区组 2 和 4 混用。非盲研究员是 Keran，PI（Junyu）是盲法评估者。

原来的做法（决策 0003）是注册时服务器按 UCLA × 年龄最小化分配，计数器 `meta/arm_counter` 客户端仍能写增量，分层变量也是老人自己填的（T13 报告第 5 条）。T12 把 `role: pi` 设成了非盲角色，和新决定相反。给 PI 的告警邮件带 `Agent`、`Source`、`Input point`，其中 `gateway_*`、`ai_output_scan`、`chat_reflective`、`system_generated` 等只在 Hybrid 组出现，`rule_turn` 只在规则组出现。

## 决定

**一、登记和分组**

1. 老人先在自己手机上注册（不变）。非盲研究员用自己的账号登录同一个 App，登录后直接进「研究員登記」页（不是老人能看到的入口）。填：老人的登入电邮、研究编号、W0 情感分（0–3）、阿珍/阿伯、W0 日期（默认当天）。
2. 先「檢查」：服务器试运行，核对账号存在、没有组别、不是测试员、研究编号没被占用，并返回账号名字给研究员核对。**试运行不返回组别**。
3. 确认框里再选一次情感分，两次一致才能提交。
4. Cloud Function `enrollParticipant` 只接受 `role: unblinded`，在一个事务里取该层下一个未用位置，写组别、W0 日期、配对、登记记录、研究编号对照表和分配日志。
5. 一个账号只分配一次；重复提交返回原组别并记日志。组别写入后客户端不能改；更正只能用 `tool/correct_arm_assignment.js`，必须写理由（至少 10 个字）并留日志。
6. 组别只在研究员登记页显示。

**二、分配序列**

1. `tool/randomization_sequence.js`：非盲研究员用自己选的种子（至少 16 个字符，建议放文件里传入）生成。每层至少 60 个位置；同一个种子生成同样的序列，可以复核。
2. 生成时只在本地写一个文件（含种子和序列，放 `randomization-private/`，已加进 `.gitignore`），屏幕上只显示长度和指纹，不显示组别。文件交导师离线保存后从电脑删掉。
3. 上传只写序列和指针，不写种子。已上传或已有人分配后拒绝覆盖。
4. 脚本默认只对模拟器执行；对正式项目要同时给 `--project` 和 `--production-confirm`。

**三、旧路径**

- 最小化分配代码删除。`assignArm` 只返回已有组别；`meta/randomization_config.enabled` 关着时给 Phase A / pilot 分 A 组，开着时不分。
- `app_config/arm_assignment.randomise` 停用：开关关着时它若为 true，`assignArm` 拒绝分组（不能把 Phase B 的人误分进 A 组）。
- `meta/arm_counter` 客户端一律不能读写。HTML 随机化工具停用写进上线清单。

**四、角色**

- `unblinded`（Keran）：登记、看组别、读研究编号对照表、后台看两组人数、生成上传序列。
- `blinded`（PI 和其他盲法人员）：后台不显示两组人数和单组板块，只用盲法导出。
- 旧名字 `pi`、`researcher` 不再有任何权限（规则、后台、登记页、Function 都按新名字判断）。迁移：`tool/provision_researcher.js --list-legacy` 找出旧账号，`--revoke` 后按新角色重新发放。

**五、给 PI 的告警**

- `pi_alerts` 和邮件去掉 `source`、`inputPoint`、`agentId`；只留 uid（只在告警文档里）、研究编号、级别、时间、告警编号。两组字段和文字完全一样。
- 每条 acute 事件照旧写告警、照旧发邮件（测试员照旧不发邮件），检测和分级都不变。细节留在 `safety_events`，由非盲研究员按告警编号查。

**六、W0 日期**

- 登记时记 `w0Date`。App `w0DateFor` 和服务器 `w0DateKey` 先用它，没有再用 `createdAt`。

**七、两组隔离**

- 规则组调用 `proxyDeepSeek`、`referralJudgement`、`webSearch` 被拒绝，并记 `llm_denied_log`（不存文字）。服务器分组缓存 10 分钟过期，避免更正后旧组别长期生效。

**开关**：`meta/randomization_config.enabled`，默认 false（文档不存在 = 关）。关着时不能登记，`assignArm` 的行为和以前的 Phase A 一样。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 研究员用管理脚本登记 | 要在电脑上装 Node 和服务账号密钥；服务账号能读写所有数据，权限过大；记录里的"操作研究员"只能靠自报。研究员在入组现场有手机，用 App 页面最省事 |
| 研究员先建登记、老人注册时输入研究编号来认领 | 老人或研究员在老人手机上要多输一次编号，输错就绑错人；认领前的分组悬空，更难查 |
| 用配对码对上账号 | 要多做一套码的生成、过期和展示；研究员本来就帮老人建了电邮账号，用电邮查找加名字核对就够 |
| 研究编号继续用服务器生成的 `P` + 6 位 | 任务单要求研究员录入研究编号；纸本问卷用的就是研究编号，两套编号容易混 |
| 试运行时显示下一个组别 | 研究员会提前知道下一位的组别，破坏分配隐藏 |
| 序列存进 Firestore 时连种子一起存 | 种子能复原整条序列；只存序列和指纹，种子离线保存 |
| 给 PI 的邮件保留来源和陪伴者，只是不写组别 | 来源和输入点本身就能推出组别（见背景） |
| 规则组停发 PI 告警，或只发一组 | 削弱安全告警，违反决策 0014 |
| 把 `ahJanAhBakVariant` 锁成只有服务器能写 | App 的整份资料保存会带上这个字段，锁上后老人的设置保存会整份失败；先不锁，见后果 |

## 后果

- 对研究：protocol 和统计分析计划要写"按 W0 DJG 情感分分层（0–1 / 2–3）、层内 1:1 置换区组（2 和 4 混用）、非盲研究员生成序列、服务器在登记时分配"；最小化方法不再适用。分层变量来自纸本，W0 必须在登记前完成。DMP 要写种子和序列文件的保管人（导师）和分配日志的保留。PI 只能用盲法导出和盲法视图；PI 收到的告警只有研究编号，要靠非盲研究员查细节。
- 对研究：登记前老人看到规则组界面（决策 0004），分到 Hybrid 组的人如果没在当天登记，前几次用的是规则组界面。建议入组当天、老人离开前完成登记并让老人重开 App；登记前的数据怎么算由研究侧定（T19 报告）。
- 对开发：上线顺序是部署 → 非盲研究员上传序列 → 打开开关 → 发放角色。Firestore 数据访问审计日志在 Google Cloud 控制台开（清单 C 节）。T21 会在登记时加研究期字段。
- 对论文：方法部分的随机化、分配隐藏和盲法段落按本决定写。
