# CI/CD 使用说明

三个 GitHub Actions 工作流，都在 `.github/workflows/`。在 GitHub 仓库页面顶部的 **Actions** 标签页里可以看到它们。

| 工作流 | 什么时候跑 | 做什么 |
|---|---|---|
| **CI** (`ci.yml`) | 每次 push、每个 PR 自动跑 | Flutter 静态检查 + 四种构建模式的测试（Phase A、Phase B、B 组页面、记忆 v1）；Cloud Functions 测试 + Firestore 规则测试（在模拟器里跑） |
| **Build APK** (`build-apk.yml`) | 手动 | 为任意分支打一个可以装到安卓手机的 APK，可选 phase_a / phase_b / memory_v1 / phase_b_templates。`phase_b_templates` 是给参与者和内部测试用的 Phase B 包（`PHASE_B=true` 加规则组模板 `RULE_TEMPLATE_REPLIES=true`，T36） |
| **Deploy Firebase** (`deploy-firebase.yml`) | 手动，需要审批 | 先跑后端测试，再把 Firestore 规则和/或 Cloud Functions 部署到 `loneliness-pilot-dev` |

## 看测试结果

- 每个提交旁边、每个 PR 底部会有 ✓ 或 ✗，点进去可以看到哪一步失败。
- 本地也能跑同样的测试：`tool/ci_flutter_tests.sh` 和 `tool/ci_backend_tests.sh`。

**说明：** CI 全绿只代表代码行为符合测试里写的期望。安全词库里的临床取舍（例如「我想死」判为 `moderate_interrupt`）暂按 v5 沿用，PI 签核搁置，见 `docs/decisions/0012-*`。

## 自己在手机上试

1. Actions → **Build APK** → **Run workflow**；
2. 选分支（通常是 `main`）和版本（参与者和内部测试用 `phase_b_templates`；`phase_b` 是不带规则组模板的旧选项）；
3. 大约 10 分钟后，打开这次运行，在页面底部 **Artifacts** 下载 zip，解压得到 APK；
4. 传到安卓手机上安装（需要允许「安装未知来源应用」）。

注意：
- 这个 APK 连的是真实的 `loneliness-pilot-dev` 项目。请用测试账号，不要用参与者账号。
- `phase_b` 版本按账号注册时抽到的组别显示页面；组别一旦写入就不能再改。想看 B 组，需要一个被分到 B 组的测试账号（可以由管理员在 Firebase Console 里给新测试账号设置 `arm: "B"`）。
- 用 debug 密钥签名，只适合内部测试。上架商店仍然走 Codemagic（`codemagic.yaml`，iOS）。

**测试工具：** 如果在仓库 Secrets 里设了 `TESTER_PIN`，打出来的包可以解锁测试工具（日程模拟器、测试推送）：在「關於」页连点版本号 7 次，再输入这个密码。没有设置时，测试工具在这个包里完全打不开。

**测试工具（10/19 起不用另外打包）：** 帐号是测试员（`isTester: true`，只有管理员能设：`tool/set_tester.js` 或控制台），而且控制台 `app_config/feature_flags.testerToolsEnabled` 是 `true` 时，任何包（包括给老人的包）在「關於」页连点版本号 7 次就直接解锁，不用密码。参与者点了没有反应。

**Flutter 版本：** CI、打包和 Codemagic 都固定用 **Flutter 3.44.1**（Dart 3.12.1），和团队本地一致（见 `.metadata`）。10/20 从 3.35.3 升上来，只换工具版本，老人看到的不变（决策 0068）。Gradle 8.12、AGP 8.9.1、Kotlin 2.1.0 在 3.44.1 的支持范围内，打包时会有「版本快要不支持」的提示，不影响打包。**下次再升 Flutter，先把它们升到 Gradle 8.14、AGP 8.11.1、Kotlin 2.2.20 以上**（`android/gradle/wrapper/gradle-wrapper.properties`、`android/settings.gradle.kts`；Kotlin 2.2 还要把 `android/app/build.gradle.kts` 的 `kotlinOptions` 改成 `compilerOptions`），单独开一个 PR 做。

## iOS 包

- 本机 Mac 编不了 iOS 时走 Codemagic（`codemagic.yaml`，TestFlight internal），或在能跑 Xcode 的 Mac 上用 USB 直接装。两种都用和 Android `phase_b_templates` 一样的编译参数：`--dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true`。少了就不是 Phase B 的包。
- `codemagic.yaml` 的 bundle id 是 `hk.hku.hkuimse.withyouapp`，和 Xcode 工程、`ios/Runner/GoogleService-Info.plist` 一致；签名和 App Store Connect 的接入还要在 Codemagic 后台配。
- iPhone 推送要先配 APNs 密钥和 Xcode 的 Push Notifications 能力，步骤见 `docs/release/w0-install-script.md` 第 2.3 节。没配好时 iPhone 收不到任何提醒。

## 部署的一次性设置

仓库 **Settings** 里做两件事：

1. **Secrets and variables → Actions → New repository secret**
   名称 `FIREBASE_SERVICE_ACCOUNT`，内容是一个 Google Cloud 服务账号的 JSON 密钥（在 Firebase Console → 项目设置 → 服务账号 生成，需要能部署规则和函数的权限）。
2. **Environments → New environment**，命名为 `production`，勾选 **Required reviewers** 并填上审批人。之后每次部署都要这个人点「批准」。

部署时还要在输入框里手动键入项目 id `loneliness-pilot-dev` 作为确认，防止误点。

**截至 2026-10-04，main 上的规则和 Cloud Functions 都还没有部署。** 部署顺序见 `docs/dev/architecture.md` 第 9 节。
