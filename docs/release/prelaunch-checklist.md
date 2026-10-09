# Phase B 上线前检查清单

> 2026-10-07 建立（T13）。来源：T1–T6 报告和 `docs/dev/ci-cd.md`、`docs/dev/architecture.md`。
> 每一项都要有人核对、写上日期。任何一项没过，不让第一位 phase_b 参与者入组。

**结论先说**：上线前必须手动做的有五类——GitHub 设置、Firebase 密钥和部署、分组准备（非盲研究员上传序列、种子离线保存、HTML 工具停用、审计日志、角色）、Firestore 配置文档、研究侧核对（热线、文案、ICF）。Firestore 配置可以用 `tool/prelaunch_config.js` 写，但这个脚本默认只对模拟器执行，对正式项目要另加确认参数。

## A. GitHub 仓库设置

| # | 项目 | 怎么核对 | 来源 | 核对人 / 日期 |
|---|---|---|---|---|
| A1 | 部署用的 secret `FIREBASE_SERVICE_ACCOUNT` 已加 | 仓库 Settings → Secrets and variables → Actions，列表里能看到这个名字（看不到内容是正常的） | `docs/dev/ci-cd.md`；T2 | |
| A2 | environment `production` 已建，**Required reviewers** 填了审批人 | Settings → Environments → production，看审批人名单 | `docs/dev/ci-cd.md` | |
| A3 | `main` 分支保护：必须走 PR、CI 通过才能合并 | Settings → Branches，看 `main` 的规则 | backlog 第 6 项 | |
| A4 | `TESTER_PIN` 是否设置（设置了，测试包能打开测试工具） | Settings → Secrets 里有没有这个名字；正式发给参与者的包，研究侧决定要不要设 | `docs/dev/ci-cd.md` | |

## B. Firebase 项目（`loneliness-pilot-dev`）

| # | 项目 | 怎么核对 | 来源 | 核对人 / 日期 |
|---|---|---|---|---|
| B1 | Functions 密钥都已设置：`DEEPSEEK_API_KEY`、`SEARCH_API_KEY`、`SMTP_HOST`、`SMTP_USER`、`SMTP_PASS`、`PI_EMAIL` | Google Cloud 控制台 → Secret Manager，六个名字都在、都有版本。`PI_EMAIL` 的值要 PI 本人确认是对的邮箱 | `functions/index.js` 第 17–21、575 行；T2 第 2 节 | |
| B2 | 规则和 Functions 已按顺序部署 | Actions →「Deploy Firebase」最近一次成功运行的提交号 = 要上线的提交号。Firebase 控制台 → Functions 列表里有 `assignArm`、`proxyDeepSeek`、`dispatchReminders` 等；Firestore → 规则 页显示的内容和仓库 `firestore.rules` 一致 | `docs/dev/architecture.md` 第 9 节 | |
| B3 | 决策 0017 的改动已部署（请求 `deepseek-flash`） | 部署后在 Firestore `llm_calls` 里看最新一条：`model_requested` = `deepseek-flash` | backlog 第 24 项；T5 | |
| B4 | 研究人员角色已按 T19 发放：Keran = `unblinded`，PI（Junyu）和其他盲法人员 = `blinded`；没有账号还带旧名字 `pi` / `researcher` | `NODE_PATH=functions/node_modules node tool/provision_researcher.js --list-legacy` 显示 0 个；Keran 登录 App 后直接进「研究員登記」页；PI 登录后看到的是普通 App，没有登记页 | 决策 0029；T19 | |
| B5 | iOS 推送（APNs）是否配置 | Firebase 控制台 → 项目设置 → Cloud Messaging → Apple 应用配置。没配置时 iOS 手机收不到任何推送（只用 Android 可跳过） | `functions/index.js` `sendTestPush` 注释 | |
| B6 | Firestore、Storage 的地区；Storage 访问规则 | Firebase 控制台 → Firestore / Storage 设置页记下地区；Storage → 规则 页确认不是公开读写（仓库里没有 `storage.rules`） | T2 第 3.2 节、第 15 条 | |

## C. Firestore 配置文档

用脚本写（推荐）或在控制台手动写。**先在模拟器上跑一遍看输出**：

```
cd functions && npm ci && cd ..
firebase emulators:exec --only firestore --project demo-prelaunch \
  "NODE_PATH=functions/node_modules node tool/prelaunch_config.js --phase=b --apply"
```

对正式项目执行（上线当天，由负责人执行；需要服务账号凭据）：先不带 `--apply` 看一遍会写什么，再带上：

```
NODE_PATH=functions/node_modules node tool/prelaunch_config.js --phase=b \
  --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev
# 确认输出无误后，加 --apply。脚本也检查两条分配序列已上传（只显示长度和指纹）
```

| # | 项目 | 正确的值 | 怎么核对 | 来源 | 核对人 / 日期 |
|---|---|---|---|---|---|
| C1 | `meta/memory_config` | `enabled: true`、`policy: "C"`、`phaseBArmA: true` | 控制台打开这个文档看三个字段；或不带 `--apply` 跑脚本，三行都显示 `=`。没有这个文档时 Hybrid 组**没有任何记忆** | T1 C05；T4；`functions/memory.js` `loadConfig` | |
| C2 | `meta/randomization_config` | `enabled: true`（其余字段 `stratifyBy`、`strata`、`method`、`blockSizes` 只做记录） | 同上。不是 `true` 时研究员**不能登记**，老人一直没有组别（看到规则组界面）；**必须在第一位 phase_b 老人注册前打开**，否则这位老人会被当作 Phase A 分进 A 组 | 决策 0029；`functions/arm.js` | |
| C3 | 两条分配序列已上传（`randomization_sequences/low`、`high`），都还没人用 | 每条至少 60 个位置，`0 used` | 不带 `--apply` 跑 `tool/prelaunch_config.js`，两行都显示 `= … positions, 0 used`。上传由 Keran 执行，见下面 G 节 | 决策 0029 | |
| C3b | `app_config/arm_assignment` 已删除（T19 停用） | 文档不存在 | 控制台看；脚本会提示 `randomise is still true` | 决策 0029 | |
| C4 | `app_config/reminders.m7FollowupPushEnabled` | 研究侧决定。默认不建 = 行动计划提醒不发 | 控制台看。打开后，在 `users/{uid}/events` 能看到 `m7_reminder_sent` | 决策 0022 | |
| C5 | `app_config/phase_a`（只有 Phase A 用） | 研究侧决定 `w2DayOffset` 等参数；不建就用默认值 14 / 3 | 控制台看 | T2 | |

## G. 分组准备（T19，决策 0029）

**只能由非盲研究员（Keran）做 G1–G3。PI 不能在场看屏幕，不能拿到种子或序列文件。**

| # | 项目 | 怎么做 / 怎么核对 | 核对人 / 日期 |
|---|---|---|---|
| G1 | 生成序列 | Keran 自己想一个种子（至少 16 个字符），写进一个只有自己能读的文本文件。在仓库根目录：`NODE_PATH=functions/node_modules node tool/randomization_sequence.js --seed-file=<种子文件>`。屏幕只显示两层的长度和指纹。生成的文件在 `randomization-private/`（已在 `.gitignore`，不会进仓库） | |
| G2 | 上传序列 | 先对模拟器试一次；正式项目：`... --seed-file=<种子文件> --upload --operator=<Keran 的电邮> --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev`。显示两行 `+ … uploaded` 即成功。已上传过会拒绝 | |
| G3 | **种子已离线保存** | 把 `randomization-private/` 里的文件和种子文件交导师离线保存（例如加密 U 盘），记下指纹；然后从电脑上删掉这两个文件。`git status` 里看不到它们 | |
| G4 | **HTML 随机化工具已停用** | 研究团队不再使用 v1.3.1 HTML 工具；各人电脑上的副本删除或归档，并写明"已停用，以 App 登记为准" | |
| G5 | Firestore 数据访问审计日志已开 | Google Cloud 控制台 → 选项目 `loneliness-pilot-dev` → IAM 和管理 → 审计日志 → 在服务列表里勾选 **Cloud Firestore API** → 勾 **数据读取** 和 **数据写入**（"管理员读取"也勾上）→ 保存。核对：日志浏览器（Logs Explorer）里查 `protoPayload.serviceName="firestore.googleapis.com"`，能看到读写记录。注意：通过 Cloud Function 的读写记在函数的服务账号名下；谁登记、谁分组看 `arm_assignment_log` 的 `by` / `byEmail`；控制台里直接打开 `randomization_sequences`、`enrollments`、`arm_assignment_log` 会以本人账号记下 | |
| G6 | 只有必要的人有项目权限 | Google Cloud 控制台 → IAM：PI 的 Google 账号**不要**有能读 Firestore 的角色（例如 Owner、Editor、Datastore Viewer），否则 PI 能在控制台看到组别和序列 | |

## D. App 构建

| # | 项目 | 怎么核对 | 来源 | 核对人 / 日期 |
|---|---|---|---|---|
| D1 | 发给参与者的包用 `--dart-define=PHASE_B=true` 编译 | Actions →「Build APK」运行记录里选的是 phase_b；装好后用一个测试账号确认 B 组看到的是规则组界面 | T1 C01、C22；T4 | |
| D2 | 正式包**没有**带 `FORCE_ARM` | 打包命令/运行记录里没有 `FORCE_ARM`。代码里没有自动防护，只能人工看 | T1 C01 第 4 条 | |
| D3 | 正式签名 | 现在用调试密钥，只能内部测试 | backlog 第 4 节 | |

## E. 研究侧核对

| # | 项目 | 怎么核对 | 来源 | 核对人 / 日期 |
|---|---|---|---|---|
| E1 | **PI 核对危机热线号码** | PI 逐个拨打或对照机构官网核对 `functions/prompts/crisis_resources.json` 的号码，填上 `verifiedDate`。开发不改号码 | T6；backlog 第 25 项 | |
| E2 | AI 自己写热线号码的问题已有处理方案 | 看 T7 的处理结果（热线出站过滤） | T6 第 5 条 | |
| E3 | 怀旧入口文案改成 4 周（T13 草稿）已定稿 | 看 T13 报告的草稿和 PR 里单独的那个提交 | T1 C06 | |
| E4 | ICF、DMP 与代码一致（记忆强制开启、发给 DeepSeek、保留期、删除方式） | 对照 T2 报告第 4 节逐条看 | T2；backlog 第 8 项 | |
| E5 | 研究文件里的模型名已改为 DeepSeek-V4.1-Flash | 登记表、protocol、ICF、DMP、HREC 材料 | backlog 第 23 项；决策 0017 | |
| E6 | 打 `phaseB-v1.0.0` tag，保存配置快照 | tag 指向上线提交；把 C1–C4 的值记进 `STUDY_CHANGELOG` | `docs/dev/memory-and-entry-spec.md` 第 6 节；CLAUDE.md | |

## H. 安全分类器（LoRA）接入（T24，决策 0025、0033）

两组共用已定（10/8）。**没有模型之前两个开关都保持关**，本节整节可以不做、不影响上线；要打开时逐项核对。

| # | 项目 | 怎么核对 | 来源 | 核对人 / 日期 |
|---|---|---|---|---|
| H1 | **部署机器**已定 | 线上 Cloud Function 连不到个人电脑。建议放在 `asia-east2`（香港）的 Cloud Run 或同区域服务器，与 Functions 同区；数据出境和存放地点与 DMP 一致。记下项目名、区域、服务名 | T8 报告第 5 节；backlog 59 | |
| H2 | **地址**已填 | 一个 HTTPS 地址，接受 `POST`，正文 `{"text": "..."}`，返回 `{"level": "none / low / moderate_review / moderate_interrupt / acute", "score": 0–1, "model_version": "…"}`。填进 Firestore `meta/safety_config.classifierUrl`（客户端读不到）。只给分数时要研究侧先给分数到级别的切点并改代码 | `functions/safety_classifier.js` | |
| H3 | **鉴权**已配 | 现在支持 Bearer 密钥：Functions 环境变量 `SAFETY_CLASSIFIER_TOKEN`（建议改放 Secret Manager，和 B1 一起）。模型那边只接受带这个密钥的请求。若用 Cloud Run IAM（Google 身份令牌）要先改代码 | T8 报告第 2、5 节 | |
| H4 | 延迟和截断参数 | 实测延迟后定：`meta/safety_config.classifierTimeoutMs`（默认 1200）、`classifierMaxChars`（默认 1000）、`app_config/phase_a.safetyClassifierTimeoutMs`（默认 1500，限 200–5000） | T8 报告第 2 节 | |
| H5 | 评估通过 | 用 T6 的 20 句和 `docs/safety/distress_detector_performance_v1.0.md` 的语料测召回、误报、延迟，研究侧和 PI 签字接受 | backlog 59、60 | |
| H6 | 文件已改 | DMP、ICF 写明两组老人的文字（去掉电话等）会发给安全分类器、只返回风险等级；HREC 是否修订有结论 | 决策 0033；backlog 85 | |
| H7 | 打开开关 | 先开服务器 `meta/safety_config.classifierEnabled: true`，再开 App `app_config/phase_a.safetyClassifierEnabled: true`（App 启动时读）。核对：用测试账号两组各发一句，`safety_classifier_calls` 各有一条 `status: ok`，`turn_id` 能在该账号 `users/{uid}/turns` 的 `safetyTurnId` 里找到。当天在 STUDY_CHANGELOG 补一行 | 决策 0033 | |

## F. 上线后第一天

| # | 项目 | 怎么核对 |
|---|---|---|
| F1 | 第一位参与者登记后分到了组 | 由 Keran 核对（PI 不看）：登记页显示组别；控制台 `users/{uid}`：`arm` 有值，`armAssignedBy: "server"`，`armAssignmentMode: "randomise"`，`w0Date` 是登记填的日期；`arm_assignment_log` 有一条 `allocate` |
| F2 | Hybrid 组有记忆写入 | 第一次聊天结束后 30 分钟内，`users/{uid}/mem_summaries` 有内容 |
| F3 | 规则组没有 LLM 调用 | `llm_calls` 里没有规则组参与者的 uid |
