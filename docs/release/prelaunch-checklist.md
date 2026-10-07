# Phase B 上线前检查清单

> 2026-10-07 建立（T13）。来源：T1–T6 报告和 `docs/dev/ci-cd.md`、`docs/dev/architecture.md`。
> 每一项都要有人核对、写上日期。任何一项没过，不让第一位 phase_b 参与者入组。

**结论先说**：上线前必须手动做的有四类——GitHub 设置、Firebase 密钥和部署、Firestore 里的三个配置文档、研究侧核对（热线、文案、ICF）。Firestore 配置可以用 `tool/prelaunch_config.js` 写，但这个脚本默认只对模拟器执行，对正式项目要另加确认参数。

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
| B4 | 研究员账号有 `role=researcher` 权限 | 用 `tool/provision_researcher.js` 发放；研究员登录后能打开后台页 | T1 C19 | |
| B5 | iOS 推送（APNs）是否配置 | Firebase 控制台 → 项目设置 → Cloud Messaging → Apple 应用配置。没配置时 iOS 手机收不到任何推送（只用 Android 可跳过） | `functions/index.js` `sendTestPush` 注释 | |
| B6 | Firestore、Storage 的地区；Storage 访问规则 | Firebase 控制台 → Firestore / Storage 设置页记下地区；Storage → 规则 页确认不是公开读写（仓库里没有 `storage.rules`） | T2 第 3.2 节、第 15 条 | |

## C. Firestore 配置文档

用脚本写（推荐）或在控制台手动写。**先在模拟器上跑一遍看输出**：

```
cd functions && npm ci && cd ..
firebase emulators:exec --only firestore --project demo-prelaunch \
  "NODE_PATH=functions/node_modules node tool/prelaunch_config.js --phase=b --apply --reset-arm-counter"
```

对正式项目执行（上线当天，由负责人执行；需要服务账号凭据）：先不带 `--apply` 看一遍会写什么，再带上：

```
NODE_PATH=functions/node_modules node tool/prelaunch_config.js --phase=b \
  --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev
# 确认输出无误后，加 --apply（第一次打开随机前再加 --reset-arm-counter）
```

| # | 项目 | 正确的值 | 怎么核对 | 来源 | 核对人 / 日期 |
|---|---|---|---|---|---|
| C1 | `meta/memory_config` | `enabled: true`、`policy: "C"`、`phaseBArmA: true` | 控制台打开这个文档看三个字段；或不带 `--apply` 跑脚本，三行都显示 `=`。没有这个文档时 Hybrid 组**没有任何记忆** | T1 C05；T4；`functions/memory.js` `loadConfig` | |
| C2 | `app_config/arm_assignment` | `randomise: true` | 同上。不是 `true` 时**所有人都分到 A 组** | T1 C01；`functions/arm.js` | |
| C3 | `meta/arm_counter` 在第一位 phase_b 参与者入组前清零 | 4 个层的 `aCount`、`bCount` 都是 0 | 控制台看；脚本的 `--reset-arm-counter` 在已有人随机分组后会拒绝执行 | `docs/dev/architecture.md` 第 9 节 | |
| C4 | `app_config/reminders.m7FollowupPushEnabled` | 研究侧决定。默认不建 = 行动计划提醒不发 | 控制台看。打开后，在 `users/{uid}/events` 能看到 `m7_reminder_sent` | 决策 0022 | |
| C5 | `app_config/phase_a`（只有 Phase A 用） | 研究侧决定 `w2DayOffset` 等参数；不建就用默认值 14 / 3 | 控制台看 | T2 | |

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

## F. 上线后第一天

| # | 项目 | 怎么核对 |
|---|---|---|
| F1 | 第一位参与者分到了组 | 控制台 `users/{uid}`：`arm` 有值，`armAssignedBy: "server"`，`armAssignmentMode: "randomise"` |
| F2 | Hybrid 组有记忆写入 | 第一次聊天结束后 30 分钟内，`users/{uid}/mem_summaries` 有内容 |
| F3 | 规则组没有 LLM 调用 | `llm_calls` 里没有规则组参与者的 uid |
