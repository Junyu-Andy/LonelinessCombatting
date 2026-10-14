# 负责人核对后的四个修复（2026-10-14，编号待开发窗口分配；SPEC:C01、C14、C17、C19）

分支 `fix/flags-after-login-and-guards`，从 main `cd46235`（含 #70）开。依据：负责人 10/14 核对 W0 流程和第一批 PR 后发现的 5 个问题；第 4 个（`isTester` 客户端可写）维持待办 96，其余 4 个在此修。没有连生产 Firestore。

## 结论

| # | 问题 | 修法 | 影响 |
|---|---|---|---|
| 1 | 新装 App 第一次注册/登录后开关不生效：`lib/main.dart` 启动时读 `app_config/*`，那时没登录，`firestore.rules` 只让登录后读，读取被拒按默认值处理，之后不再读 | `auth_gate.dart`：账号出现后再读一次 `RemoteFeatureFlags`、`PhaseBConfig`、`PhaseAConfig`、`UsageCopy`，然后 `setState` 重建，登记门、T37 引导开关等按真实值走 | 登记门打开前**必须**有这个修复，否则老人注册后看不到等待页、问卷答案被规则悄悄拒绝 |
| 2 | T34 第一封告警发不出去（SMTP 错、第一收件人被当成 `blinded` 剔除、没有收件人）时不会转后备 | 失败时在告警行写 `primaryFailedAt`、`primaryFailedReason`、`escalationPending: true`；`escalateDue` 对这种行**立即**算到期（不等 12 小时），下一次 15 分钟巡检发给后备 | 打开 `meta/alert_config.enabled` 前要有 |
| 3 | T25 补问卡（S10b）在没有定稿时间说法的情况显示「【占位】早排」 | `brief_pr_scheduler.nextCard`：补问卡要用的时间说法是【占位】时不显示，记录改为 `due_not_invited`，原因 `copy_pending` | 打开 `sessionBriefPrV2Enabled` 前要有；研究侧给齐说法后把 `timePhrase` 补全即可 |
| 5 | 「安靜時段」手机上和服务器可能不一致（重装、换账号） | 登录后读 `users/{uid}.quietHoursEnabled`：有就以它为准改手机设置；没有就把手机上的值写上去 | 小 |

## 一、改了什么

| 文件 | 改动 |
|---|---|
| `lib/features/auth/presentation/pages/auth_gate.dart` | 登录后 `_reloadRemoteConfig()` + `_syncQuietHours()`，再 `setState` |
| `functions/index.js`（`onSafetyEventCreated`） | 没有收件人 / 发信失败两处写 `primaryFailedPatch` |
| `functions/pi_alert.js` | 新 `primaryFailedPatch`、`escalationDue`；`escalateDue` 改用后者 |
| `lib/features/brief_pr/data/brief_pr_record.dart` | 新原因 `copy_pending` |
| `lib/features/brief_pr/data/brief_pr_scheduler.dart` | `nextCard` 的【占位】守卫 |
| 测试 | `functions/test/pi_alert_test.js` +1（到期规则 8 种情况）；`test/brief_pr_scheduler_test.dart` +1（20:30 聊完 22:00 打开 → 不出卡、`copy_pending`） |
| 文档 | STUDY_CHANGELOG 一行；architecture.md 第 12 节；history；backlog 96 加复核注 |

## 二、测试

| 测试 | 结果 |
|---|---|
| `node functions/test/pi_alert_test.js` | 16/16 |
| `flutter test --dart-define=PHASE_B=true test/brief_pr_scheduler_test.dart` | 36 项通过（原有 35 + 新 1；原有的三种定稿说法仍出卡） |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | 0 error（90 条旧提示） |
| 全套 | GitHub CI |

第 1 项没有自动测试：`AuthGate` 要真 Firebase 才能跑。核对方法：新注册一个测试账号，不重开 App，控制台里的开关（例如 `onboardingAfterEnrollmentFix`）应立刻按设定走。请在下一次测试包上核对。

## 三、还没做 / 注意

- Brief PR 问卷页按钮「下一題」「返回」「放棄評價」和收尾按钮首次说明仍是【占位】草稿（T25 报告已列）：老人按「好呀」进问卷就会看到。开 `sessionBriefPrV2Enabled` 前要定稿。
- 转后备邮件的抬头仍写"N 小时无人确认"，第一封失败立即转时措辞不完全贴切；收件人是研究人员，先不改。
- `isTester` 客户端可写（待办 96）：维持，前提测试密码不外传。

## 要 Junyu 定的事

1. 本改动的 T 号。
2. 第 1 项真机核对由谁、何时做（建议下一次 `phase_b_templates` 包）。

## 要带回研究侧的发现

1. S10b 缺的时间说法（当天 18:00 后聊完、当晚再打开；两天前；前一天上午）定稿前，这些情况的 Brief PR 不邀请、记 `copy_pending`，分析时和 `crisis` 一样算"应邀请未邀请"。
