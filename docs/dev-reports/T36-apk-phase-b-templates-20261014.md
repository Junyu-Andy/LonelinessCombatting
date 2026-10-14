# T36 Build APK 加「Phase B 正式包」选项报告（2026-10-14，SPEC:C01、C02）

分支 `chore/apk-phase-b-templates`。依据：`docs/dev-tasks/dev-tasks-1014.md` 第四节 T36；`docs/dev-reports/prep-internal-test-20261013.md` 第四节和附录 A。只改手动打包的工作流和文档，不改 CI、不改部署工作流，没有部署，没有连生产 Firestore。

## 结论

1. Build APK 工作流多了一个选项 `phase_b_templates`：带 `--dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true`，不带 `FORCE_ARM`，不带 `RULE_TEMPLATE_REPLIES_ALLOW_PLACEHOLDER`。这是给参与者和内部测试用的 Phase B 包（`.github/workflows/build-apk.yml` 第 11–13、26、56 行）。
2. 原有三个选项（`phase_a`、`phase_b`、`memory_v1`）和 `TESTER_PIN` 的处理没有变。
3. 签名没有换：仍是调试密钥。换正式密钥要做的事和对已装 App 的影响见第三节，要 Junyu 定。
4. 在本分支上手动跑过一次 `phase_b_templates` 打包，结果见第四节。

## 一、改了什么

| 文件 | 改动 |
|---|---|
| `.github/workflows/build-apk.yml` | 文件开头的说明加 `phase_b_templates` 一行；`options` 加 `phase_b_templates`；`case` 加一行 `DEFINES="--dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true"` |
| `docs/dev/ci-cd.md` | 工作流表和「自己在手机上试」第 2 步各加一句：`phase_b_templates` 是给参与者和内部测试用的 Phase B 包 |
| `docs/history.md`、`docs/dev/backlog.md` | 记一条；待办「Android 正式签名」加指向本报告 |

YAML 用 js-yaml 解析过，四个选项都在。`ci.yml`、`deploy-firebase.yml` 没有改。

## 二、怎样用

GitHub → Actions → **Build APK** → Run workflow → 选分支（合并后用 `main`）→ 版本选 `phase_b_templates` → 等约 10–15 分钟 → 在运行页底部 Artifacts 下载 `peizhu-phase_b_templates-<分支>-<运行号>`，解压得到 `app-release.apk`。

- 这个包按账号的组别显示界面（`PHASE_B=true`），规则组签到、回忆提交后给定稿的 41 条模板回应（`RULE_TEMPLATE_REPLIES=true`，T33）。
- 规则组模板在这个包里**没有运行时开关**（编译开关）：发给参与者的那天，要在 `docs/STUDY_CHANGELOG.md` 补一行写明生效日期和组别（phase_b、pilot × 规则组）。
- 仓库 Secrets 里有 `TESTER_PIN` 时，包里的测试工具可以用测试密码解锁；没有就完全打不开。和以前一样。

## 三、签名（没有改，要 Junyu 定）

现状：`android/app/build.gradle.kts` 第 37–41 行，release 构建用的是 `signingConfigs.getByName("debug")`，即调试密钥。GitHub 跑的机器每次都是新的，调试密钥由 Android SDK 临时生成，所以**每次打包的调试密钥都不一样**；装过上一个包的手机，装新包时会因为签名不同被拒，要先卸载（卸载会清掉手机上的本地数据，Firestore 里的数据不受影响，重新登录就回来）。

换成正式密钥要做的事：

1. 生成一个 keystore（`keytool -genkey`），交 Junyu 离线保管，不进仓库。
2. 把 keystore 和密码放进仓库 Secrets（例如 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`）。
3. `android/app/build.gradle.kts` 加 `signingConfigs.release`，从 `android/key.properties` 读；release 构建改用它。`key.properties` 加进 `.gitignore`。
4. `build-apk.yml` 的 Build 步骤前加一步：把 Secrets 解码成 keystore 文件、生成 `key.properties`。没有 Secrets 时退回调试密钥，这样本地和 fork 还能打包。
5. 影响：**换密钥那次所有已装的手机都要卸载重装**（签名变了）。此后每次打包签名相同，可以直接覆盖安装，不用卸载。所以要换就要在 10/19 第一位参与者装机之前换好，之后就不要再换。

建议：在 10/19 前换成正式密钥（第 1–4 步约半天），否则研究期间每发一个新包，老人的手机都要卸载重装。

## 四、测试运行

在本分支上手动跑一次 Build APK（`phase_b_templates`）：

- 运行编号：（待填：运行编号）
- 运行链接：（待填）
- 产物名：（待填：产物名）
- 日志核对：（待填：`flutter build apk --release` 那一行带 `--dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true`，没有 `FORCE_ARM`）

## 五、和其他 PR 的交叉

只改 `.github/workflows/build-apk.yml`、`docs/dev/ci-cd.md`、`docs/history.md`、`docs/dev/backlog.md` 和本报告。和 T21（#59）、T34、T25、T37 只在 `history.md`、`backlog.md` 上可能相邻，两边都留即可。合并后不需要部署规则或 Functions。

## 要 Junyu 定的事

1. **换不换正式签名密钥，什么时候换**：(a) 10/19 前换（建议）；(b) 先用调试密钥，接受每次新包都要卸载重装。
2. **`phase_b` 旧选项要不要删**：现在留着（给不带模板的测试包用）。

## 要带回研究侧的发现

1. 参与者包一旦用 `phase_b_templates` 发出，规则组模板回应就生效（编译进包里，没有运行时开关）。发包日期要记入 STUDY_CHANGELOG 和偏离日志的起点。
