# 需求说明和建议：安卓和 iOS 统一用一个 Flutter 版本

> 2026-10-20 开发窗口写，给产品窗口审核。Junyu 10/20 同意方向：把安卓的 Gradle 升上去，两边都用新版 Flutter。产品定稿后出开发交接。**还没有写代码。**

## 结论

- **现状是两套版本**：
  - 安卓和 CI 固定用 Flutter 3.35.3，因为安卓的 Gradle 是 8.12，不支持更新的 Flutter。
  - iOS 必须用 3.38 以上。仓库里的 iOS 启动代码（`ios/Runner/AppDelegate.swift`、`Info.plist` 的 UIScene 设置）从 10/04 导入起就是新写法，3.35.3 编译不过。以前的 TestFlight 包都是用 Junyu Mac 上的 3.44.1 打的。
- **问题**：
  - 打包的人要记住「iOS 用这个、安卓用那个」，容易用错。10/20 晚上就因此卡了一个多小时。
  - CI 测的是 3.35.3，iOS 包却是 3.44.1 打的，**iOS 包实际上没有被 CI 测过**。
  - `codemagic.yaml` 写的是 3.35.3，用 Codemagic 打 iOS 会失败。
- **建议**：把安卓的 Gradle 升到 8.14 以上，CI、安卓、iOS、Codemagic 全部统一用同一个新版 Flutter（建议就用 Junyu 打 iOS 用的 3.44.1，iOS 那边已经验证过）。
- **时间**：**不要在 10/21 冻结构建之前做。** 做完以后，只影响下一次打的包。已经装在参与者手机上的 App 不受影响，也不需要他们更新。

## 一、要改什么（开发核对）

| 改什么 | 现在 | 改成 |
|---|---|---|
| Gradle（`android/gradle/wrapper/gradle-wrapper.properties`） | 8.12 | 8.14 以上，按新 Flutter 的要求 |
| Android Gradle Plugin、Kotlin（`android/settings.gradle.kts`） | AGP 8.9.1、Kotlin 2.1.0 | 按新 Flutter 的要求，可能要升 |
| CI（`.github/workflows/ci.yml`）、安卓打包（`build-apk.yml`）、`codemagic.yaml` | 3.35.3 | 新版本 |
| `.metadata`、`pubspec.yaml` 的 Dart 版本下限 | 3.35.3 / Dart 3.9.2 | 新版本 |
| `webview_flutter` 固定 4.13.1（`pubspec.yaml` 注释写着「3.35.3 只能用到这一版，冻结前不要升」） | 4.13.1 | 先保持不动；要升另外评估（小讀本，决策 0056） |
| `ios/Podfile` | 没在仓库里 | 提交一份，所有组件最低 iOS 15.0（新版 Xcode 要求） |
| 文档 | `CLAUDE.md`「Flutter 固定 3.35.3」、`docs/dev/ci-cd.md`、本地测试和装机说明 | 改成新版本 |

## 二、风险和怎么验证

- **测试结果可能变化**：新版 Flutter 的 `flutter analyze` 提示条数会变，个别界面测试（字号、布局）可能要调。CI 全部通过才算完成。
- **安卓包的行为**：理论上不变，但换了编译工具链，要在安卓真机上走一遍主要流程：登录、小欣 check-in、聊天、每周问卷、推送、安全流程。
- **iOS 包**：现在就是用新版打的，变化最小。照样真机走一遍。
- **两组一致**：这是编译工具的改动，不改任何内容和逻辑。两组用同一套代码，同时生效。安全检测（`lib/core/safety/`）不改。
- **签名不变**：安卓、iOS 的签名和 Bundle ID 都不变，参与者以后更新时可以覆盖安装（安卓的签名问题另见 `legacy-client-20261020.md` 第三节）。

## 三、研究记录

- 换编译工具以后打出的第一个包，在 `docs/STUDY_CHANGELOG.md` 记一行：版本号、生效日期、影响「两组相同，只是编译工具变了，内容不变」。
- 写一份决策记录，说明为什么统一、用哪个版本。

## 四、要产品定的事

1. 同意统一，用哪个版本（建议 3.44.1）。
2. 什么时候做：建议 10/21 冻结构建以后、下一次要给参与者出新包之前。
3. 和「旧版本手机」那份（`legacy-client-20261020.md`）里的安卓固定签名钥匙要不要放在同一个 PR 里做（都是打包相关，可以一起做）。

## 五、工作量估计

一个 PR，半天到一天，加 CI 和两部真机测试。
