# T37 报告：登记后的入组引导顺序、显示设定保存（2026-10-14）

分支 `fix/onboarding-settings`，从 T21（PR #59，已合并进 `main`）出发，已合并 `main` e851205，对 `main` 的差异只有 T37。SPEC:C01、C19。PR 草稿，未合并。

## 1. 一句话结论

- **修复 1 做好了，放在开关后面，默认关**：开关 `app_config/feature_flags.onboardingAfterEnrollmentFix` 打开后，先登记后引导的老人也会完整走一遍「介紹三個夥伴」（伙伴介绍、配对、兴趣、S5）。关着时和今天完全一样。**建议上线前打开**（第 3 节）。
- **修复 2 做好了，没有开关**：字体、高对比、「安靜時段」「語音讀出內容」保存在手机本机，关掉 App 再开仍保持。随下一个 App 版本生效。
- 两组相同；没有新的老人看得到的文字；规则组仍不会调用 LLM。
- 测试：新加 26 个 Flutter 测试、6 个 Firestore 规则测试，全部通过；全套 CI 脚本结果见第 6 节。截图在 `docs/dev-reports/T37-onboarding-settings-20261014-screenshots/`。

## 2. 修复 1：登记后仍做入组引导

### 2.1 问题

登录后 App 的门按顺序是：`StaffGate`（研究员去登记页）→ `EnrollmentWaitGate`（T21 登记门）→ `ConsentGate`（同意页 → 入组问卷 → 「介紹三個夥伴」）→ 主页（`lib/features/auth/presentation/pages/auth_gate.dart`、`lib/features/consent/presentation/consent_gate.dart`）。

以前 `ConsentGate` 只在 `users/{uid}.ahJanAhBakVariant`（阿珍/阿伯配对）为空时显示引导。研究员登记（`functions/randomization.js`）也会写这个字段，所以 W0 装机脚本的顺序——注册 → 等待页 → 登记 → 重开 App——会把伙伴介绍、兴趣选择和 S5 整段跳过。

### 2.2 标记的设计

新字段 **`users/{uid}.onboardingCompletedAt`**（时间）：老人在引导最后一屏按「完成」时，App 和配对、兴趣一起写入（`lib/features/onboarding/presentation/pages/agent_onboarding_page.dart` 的 `_finish`）。

- **开关关着也照写**，只是不读。这样等开关打开那天，所有在此之后完成引导的账号都有明确记录。
- 写在服务器（用户文档）而不是只存手机本机：换手机、重装 App 不会再做一次引导；导出里看得到谁在什么时候完成了引导；规则测试证明老人账号能写它、不能顺带改组别（`test/rules/onboarding_marker_rules.test.js`）。
- 为空时不写进文档（`UserProfile.toMap` 省略），所以 App 用旧资料整份保存时不会把标记擦掉（`lib/features/auth/data/user_profile.dart`）。
- Firestore 规则**没有改**：用户文档本来就允许本人写非分组字段，登记门开着时用户文档也不受限（T21 报告第 4.3 节）。

### 2.3 要不要做引导：开关开时的判断规则（兼容旧账号）

`ConsentGate.needsAgentOnboarding`（`lib/features/consent/presentation/consent_gate.dart`）：

| 情况 | 开关关（今天） | 开关开 |
|---|---|---|
| 有标记 | 看配对（有就不做） | **不做** |
| 没标记、没配对 | 做 | **做** |
| 没标记、有配对、**没登记过** | 不做 | **不做**（配对只能是 App 的引导写的，是 T37 之前完成引导的账号） |
| 没标记、有配对、**登记过**，App 留有痕迹 | 不做 | **不做**（先引导后登记的老顺序，T37 之前完成的） |
| 没标记、有配对、**登记过**，没有痕迹 | 不做（就是这个缺陷） | **做**（配对是登记写的，引导从没跑过） |

- “登记过”= `cohort` 是 `phase_b` / `pilot`，或 `armAssignmentMode` 是 `randomise` / `pilot_designated`（后者照顾 T21 之前登记的 dev 账号）。
- “App 留有痕迹”= `consent.transcriptRetentionByAgent` 有三个键。引导的「完成」一直都会写这个按陪伴者的对话保留表，服务器从不写它。例外：设定页的「保留對話紀錄」开关也会重写这张表，所以一个被跳过引导、又动过那个开关的旧账号会被算作“做过”——很少见，而且只影响 T37 之前的账号。
- 测试账号、盲法人员账号和老人一样处理：没有标记、没有配对的会看到引导（和今天一样）。

### 2.4 配对预选和改选日志

- 登记后进引导，「揀邊個陪你做人生回顧」一屏预先选好登记时的配对，可以直接「下一步」（截图 `1_register_first_4_pairing_preselected.png`）。老顺序（先引导）什么都不预选，和以前一样。
- 老人改选另一位时，App 写一条 `users/{uid}/events`：名字 `ah_jan_ah_bak_changed`，参数 `from`、`to`（`feminine` / `masculine`）、`at`（时间）、`where`（`onboarding` 引导里 / `agent_profile` 之后在陪伴者页改）。两组相同（`lib/features/analytics/data/analytics_service.dart` 的 `logAhJanAhBakChanged`）。改回去再按完成不算改。
- 陪伴者页（`lib/features/agent_profile/ui/agent_profile_screen.dart`）改选也记同一条，只在开关开时记。
- 登记记录 `enrollments/{uid}.companionVariant` App 碰不到（规则测试证明），分析以它为准（C19）。
- 现有代码里没有改配对的日志；T30 §5.2 要服务器记。建议 T30 搬到服务器时保留事件名和四个键（backlog 第 98 项）。

## 3. 开关

| 开关 | 位置 | 默认 | 管什么 |
|---|---|---|---|
| `onboardingAfterEnrollmentFix` | Firestore `app_config/feature_flags`（`lib/core/feature_flags/remote_feature_flags.dart`）；只有布尔值 `true` 算开，App 启动时读一次 | **关** | 第 2.3 节的判断规则、配对预选、改选日志 |

**建议：上线前打开，在第一位参与者登记之前。** 理由：W0 装机脚本（`docs/release/w0-install-script.md` 第六节第 2、3 项）是先登记后引导，关着时每位参与者都会跳过伙伴介绍、兴趣和 S5；打开后旧账号按第 2.3 节处理，不会被重复引导。打开那天在 `docs/STUDY_CHANGELOG.md` 补一行。

修复 2 没有开关。

## 4. 修复 2：显示设定保存在本机

- 字体（標準／大／特大）、高对比，加上「通知」里的「安靜時段」「語音讀出內容」，现在由 `AppSettings` 统一持有并保存到手机本机（`shared_preferences`；`lib/app/app_settings.dart`）。`main()` 在第一帧前读回（`AppSettings.restore`，`lib/main.dart`），所以打开 App 第一屏就是上次的字体和对比度。
- 本机键：`display.fontScale`（`standard` / `large` / `xLarge`）、`display.highContrast`、`notifications.quietHours`、`notifications.voiceReadback`。只在这台手机，不上传。
- 读不到（存储坏了、值类型不对）就用默认值；写失败不影响界面。
- 「安靜時段」「語音讀出內容」以前只是页面状态，现在也只是“记住了”，仍没有接到提醒和朗读逻辑（和以前一样，不在本任务）。
- 选项、文字都没改（测试里逐字核对）。
- 新的 pub 依赖 `shared_preferences ^2.5.5`（`pubspec.yaml`）。**`pubspec.lock` 这次要提交**：用 CI 同一版 Flutter 3.35.3 重新生成；仓库里原来的 lock 是更新的 Flutter 生成的（写着 `flutter: ">=3.44.0"`），所以 diff 里有几处传递依赖降版本，这是对齐 CI 版本的结果。`macos/Flutter/GeneratedPluginRegistrant.swift` 是工具自动加的插件注册，一起提交。

## 5. 字段和事件

| 名字 | 位置 | 谁写 | 两组 |
|---|---|---|---|
| `onboardingCompletedAt` | `users/{uid}` | App（按「完成」） | 相同 |
| `ah_jan_ah_bak_changed` {from, to, at, where} | `users/{uid}/events` | App（只在开关开时） | 相同 |
| 四个本机键（第 4 节） | 手机本机 | App | 相同 |

Firestore 规则、Cloud Functions 都没改。

## 6. 测试

| 任务要求 | 测试 | 结果 |
|---|---|---|
| 先登记后引导（门开）：注册 → S8 → 登记 → 重开 → 同意 → 问卷 → 完整引导（配对预选）→ 完成 → 主页；重开直接主页 | `test/onboarding_order_test.dart`「register-first … fix on」 | 通过 |
| 同上，S5 开关开时 S5 在流程里 | 同文件「fix on, S5 switch on」 | 通过 |
| 登记值与老人改选不同时有改动日志 {from, to, at, where}；改回去不算 | 同文件「changes the pairing」「changing and changing back」 | 通过 |
| 门开、修复关：和今天一样（跳过） | 同文件「fix off (default)」 | 通过 |
| 先引导后登记（门关），修复开/关各一遍；之后登记不会再引导；门再打开也不会 | 同文件「onboarding-first」 | 通过 |
| 兼容规则五种情况（第 2.3 节表）、T21 之前登记的模式 | 同文件「ConsentGate.needsAgentOnboarding」各用例 | 通过 |
| 开关默认关、只认布尔 `true`；`ConsentGate` 不给测试值时读 `RemoteFeatureFlags` | 同文件 | 通过 |
| 标记写入省略空值、ISO 字符串和 Timestamp 都能读回、copyWith 保留 | 同文件「marker round-trip」 | 通过 |
| 字体、高对比、安静时段、语音读出：设 → 重建 `AppSettings` → 值相同；每档字体；改回去也存；坏值回默认；没有存储也能用；设定页四个控件写穿到存储、文字不变 | `test/app_settings_persistence_test.dart`（8 个） | 通过 |
| 老人账号能写标记（建档、合并、登记门开着先登记/先引导两种）；不能顺带改 `cohort`/`arm`/`w0Date`；碰不到 `enrollments/{uid}` | `test/rules/onboarding_marker_rules.test.js`（6 个） | 通过 |

全套脚本（提交前在本机跑）：

| 命令 | 结果 |
|---|---|
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | 见第 6.1 节 |
| `tool/ci_flutter_tests.sh` | 见第 6.1 节 |
| `flock /tmp/firebase-emulator.lock tool/ci_backend_tests.sh` | 见第 6.1 节 |

### 6.1 全套结果

提交前在本机跑（合并 T21 8d65535 之后；之后再合并 `main` e851205，只有文档变动，没有重跑）：

| 命令 | 结果 |
|---|---|
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | 0 错误，87 条已知 info/warning（主干 88 条，本分支少 1 条） |
| `tool/ci_flutter_tests.sh` | 六套全过：phase A 默认包 421 个、phase B 分组 98 个、B 组页面 5 个、记忆 v1、模板回应（占位保护）31 个、模板回应（开）31 个 |
| `flock /tmp/firebase-emulator.lock tool/ci_backend_tests.sh` | 全过：Functions 单元测试 12 个文件；规则测试 102 个（含本任务新加的 6 个）；模拟器测试 16 个文件；删除与共享上下文脚本 |

### 6.2 截图

`docs/dev-reports/T37-onboarding-settings-20261014-screenshots/`，由 `t37_shots_test.dart` 用 `flutter test` 渲染（不进 CI，不进 App）：

- `1_register_first_1…7`：先登记后引导整条路：S8 等待页 → 同意页 → 引导欢迎 → **配对预选阿伯** → 兴趣 → S5 → 主页。
- `2_onboarding_first_1…2`：先引导：配对一屏什么都不选 → 选阿珍。
- `3_settings_restored_xlarge_contrast.png`：重开后设定页仍是特大字体、高对比、安静时段关、语音读出开。

限制：测试渲染器没有 Material 图标字体，图标和按钮上的图标位显示为方块；中文用系统文泉驿字体，和真机的 Noto 字体略有不同。

## 7. 改了哪些文件

- App：`lib/features/consent/presentation/consent_gate.dart`（判断规则）、`lib/features/onboarding/presentation/pages/agent_onboarding_page.dart`（预选、写标记、改选日志）、`lib/features/agent_profile/ui/agent_profile_screen.dart`（改选日志）、`lib/features/auth/data/user_profile.dart`（新字段）、`lib/core/feature_flags/remote_feature_flags.dart`（开关）、`lib/features/analytics/data/analytics_service.dart`、`lib/features/analytics/presentation/analytics_scope.dart`（日志、测试用读取）、`lib/app/app_settings.dart`、`lib/main.dart`、`lib/features/settings/presentation/pages/settings_page.dart`（本机保存）。
- 依赖：`pubspec.yaml`、`pubspec.lock`、`macos/Flutter/GeneratedPluginRegistrant.swift`。
- 测试：`test/onboarding_order_test.dart`、`test/app_settings_persistence_test.dart`、`test/rules/onboarding_marker_rules.test.js`、`test/rules/package.json`。
- 文档：`docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`（第 4 节末、第 12 节）、`docs/history.md`、`docs/dev/backlog.md`（第 97、98 项）、本报告和截图目录。

## 8. 和其他 PR 的交叉

| PR | 可能同时碰的文件 | 说明 |
|---|---|---|
| T21 `fix/phase-config-split`（#59，已合并） | `docs/*`、`lib/core/feature_flags/remote_feature_flags.dart`、`lib/features/enrollment/**` | 本分支从它出发，已合并 `main` e851205，没有冲突；普通 `git merge` 可以继续用 |
| T34 `feat/safety-alert-email` | `docs/STUDY_CHANGELOG.md`、`docs/history.md`、`docs/dev/backlog.md`、`functions/**` | 只有文档会冲突（都在表格最上面加行），保留两边 |
| T25 `feat/session-briefpr` | `docs/*`、`lib/features/analytics/data/analytics_service.dart`（如果它加日志） | 文档同上；analytics 若同时加方法，保留两边 |
| T36 `chore/apk-phase-b-templates` | `pubspec.lock`、CI 文件 | 两边都改 lock 时以重新 `flutter pub get`（3.35.3）为准 |
| 后续 T30 | `events` 改选日志搬到服务器 | 保留事件名和键 |

## 9. 要 Junyu 定的事

1. **开关 `onboardingAfterEnrollmentFix` 上线时默认开还是关。** 选项：(a) 第一位参与者登记前打开（建议）；(b) 先关着，试跑时看。建议 (a)：装机顺序就是先登记，关着等于每个人都跳过伙伴介绍和 S5。
2. **改配对的日志放哪。** 选项：(a) 先用 App 写的 `events`（现在），T30 搬到服务器；(b) 这次就不记，等 T30。建议 (a)，已做。
3. **开关开后老人改选配对，要不要在陪伴者页也记。** 现在记（同一条事件，`where: agent_profile`）。选项：(a) 保留；(b) 只记引导里的。建议 (a)，分析才知道最终用的是谁。

## 10. 要带回研究侧的发现

- 登记页写的配对和老人最终选的可能不同，分析时以 `enrollments/{uid}.companionVariant` 为准，`events` 里 `ah_jan_ah_bak_changed` 能看到改了几次（C19 已这么写；这里只是提醒导出要带上）。
- 「安靜時段」「語音讀出內容」两个开关现在只是记住了，还没有真正接到提醒和朗读逻辑（T24 推送重做时处理安静时段；朗读没有任务）。
- 引导的 S5 一屏仍受 `app_config/usage_copy.onboardingUsageAdviceEnabled` 控制（backlog 第 93 项），和本开关无关。

## 11. 架构优化观察（不在本任务改）

1. 门一层叠一层：`auth_gate.dart` → `StaffGate` → `enrollment_wait_gate.dart` → `consent_gate.dart`（同意 → 问卷 → 引导），每层各自读资料和开关。可以合成一个纯函数 `firstRunStep(profile, flags)` 返回“下一步是哪一屏”，一个 widget 按它路由，测试只测函数。
2. 三个远程配置单例同一套写法：`RemoteFeatureFlags.current`（`app_config/feature_flags`）、`PhaseAConfig.current`（`app_config/phase_a`，Phase A 已暂停但里面放着通用设定如对话保留默认值）、`UsageCopy.current`（`app_config/usage_copy`）。可以合成一个 `RemoteConfig` 读取器，各文档只是一段类型化字段；`PhaseAConfig` 至少该改名。
3. `lib/features/auth/data/user_profile.dart`（530 行，40 多个字段）手写 `copyWith` / `toMap` / `fromMap`，每加一个字段改四处。服务器才写的分组字段（`arm`、`cohort`、`w0Date`…）可以拆成一个只读的 `Enrollment` 值对象。
4. App 保存资料是整份 `toMap` 合并写（`AuthService.updateProfile`），所以旧快照会覆盖新字段（本次标记要“空值不写”才安全，backlog 第 74 项同样是这个原因）。改成按字段更新（只写改了的键）可以根治。
5. `lib/features/settings/presentation/pages/settings_page.dart` 950 多行，一个文件装所有卡片和对话框。按卡片拆成小 widget 文件。
6. `lib/features/analytics/data/analytics_service.dart` 为每个模块各加一个 `logXxx` 方法。可以只留 `logEvent(name, params)` 加一个事件名常量文件。
7. 每个 widget 测试都重搭一遍 `AnalyticsScope / AuthServiceScope / AppSettingsScope / MaterialApp`（`test/onboarding_order_test.dart`、`test/app_settings_persistence_test.dart`、`test/enrollment_wait_gate_test.dart`、截图脚本）。加一个 `test/support/test_app.dart`。
8. `test/rules/package.json` 的测试脚本是手写文件清单，新规则测试忘了加就不会跑。改成 `mocha '*.test.js'`。
9. `macos/Flutter/GeneratedPluginRegistrant.swift` 是生成文件却在仓库里，每加插件都有 diff；macOS 不是发布目标，可以加进 `.gitignore`。
