# 小讀本要不要加 WebView：`webview_flutter` 评估（2026-10-20）

**结论**

- **可以加。** 官方包 `webview_flutter` 4.13.1 能装进我们锁定的 Flutter 3.35.3。安卓和 iOS 的最低系统版本都不用改，不会少支持任何一部手机。
- **包只大约 1 MB。** 安卓实测 Dart 部分多 0.6 MB（三种芯片合计），加上原生代码估计共约 1 MB。iOS 用系统自带的网页组件，估计也约 1 MB。
- **打包流程不用改。** Codemagic（iOS）、GitHub Actions 打 APK、现有测试，只加这个依赖都不用动。做功能时只需要：CI 加一步跑 HTML 检查脚本，`tool/ci_flutter_tests.sh` 加读本页的测试。
- **1020c 第一节 (3) 的六项都做得到。** 唯一的缺口：官方包拦不住页面里图片、样式这类"附带请求"。办法是 App 载入时自动在页面开头加一行安全规则（CSP，只准用页面自己的内容），再加检查脚本。两层一起，等于不能连外网。
- **建议用它**：固定 4.13.1，放在 `htmlReadersEnabled` 开关后，默认关。
- **10/21 风险**：这是新的原生组件，冻结版本一旦带上，安卓和 iPhone 都要真机测过。这台开发机连不上 Google 的下载站，也没有 Mac，所以**这次没有真正编出 APK 和 iOS 包**。做功能的 PR 合并前，必须在 GitHub Actions 打一次 APK、在 Codemagic 打一次 iOS 包。10/20 晚上前做不到，就整项留到 Phase B 之后，不要只先把依赖加进冻结版本。

这次只做评估：`pubspec.yaml`、`pubspec.lock` 没有改，只提交这份报告。依据：`docs/dev-tasks/dev-tasks-1020c.md` 第一节 (1)、(3)。

## 1. 用哪个版本

用 `flutter pub add webview_flutter --dry-run` 在仓库里试装（pub.dev 能连上），再在一份临时副本里真装、`flutter pub get`。结果一样：

| 包 | 装上的版本 | 它要求 | 最新版 | 为什么不是最新 |
|---|---|---|---|---|
| `webview_flutter` | **4.13.1** | Dart ^3.8.0，Flutter ≥3.32.0 | 4.14.1 | 4.14.x 要 Flutter ≥3.38 |
| `webview_flutter_android` | **4.12.0** | Dart ^3.9.0，Flutter ≥3.35.0 | 4.14.1 | 4.12.1 起要 Flutter ≥3.44 |
| `webview_flutter_wkwebview`（iOS） | **3.25.0** | Dart ^3.9.0，Flutter ≥3.35.0 | 3.27.0 | 3.25.1 起要 Flutter ≥3.38 |
| `webview_flutter_platform_interface` | **2.15.1** | Dart ^3.9.0，Flutter ≥3.35.0 | 2.15.1 | 已是最新 |

- 我们是 Flutter 3.35.3 / Dart 3.9.2。上面四个就是这个版本能用的最高版。
- `pubspec.lock` 只**新增**这四行，原有的包一个都没变。
- 写法建议：`webview_flutter: 4.13.1`（固定版本）。冻结前不要跑 `flutter pub upgrade`。

## 2. 最低系统版本

| 项目 | 仓库现在 | 这个包要求 | 要不要改 |
|---|---|---|---|
| 安卓最低版本 minSdk | 24（Android 7.0；`flutter.minSdkVersion`） | 插件 24；它用的 `androidx.webkit` 1.15.0 要 23 | 不改 |
| 安卓 compileSdk / targetSdk | 36 / 36（Flutter 3.35.3 默认） | `androidx.webkit` 1.15.0 要 compileSdk ≥35 | 不改 |
| Gradle | 8.12 | — | 不改 |
| AGP（安卓打包插件） | 8.9.1 | 插件自己写了 8.13.1，但打 App 时用的是 App 的 8.9.1（见下） | 不改 |
| Kotlin | 2.1.0 | 插件自己写了 2.3.0，同上 | 不改 |
| Java | CI 用 17（`build-apk.yml`） | 插件按 Java 17 编译 | 不改 |
| iOS 最低版本 | 15.0（`Runner.xcodeproj` 三处） | 13.0（podspec 和 Package.swift） | 不改 |

**会不会少支持手机：不会。** 两边的要求都比我们现在的低。

为什么说 Gradle 8.12 / AGP 8.9.1 能用：

1. 我们 `android/` 的设置和 Flutter 3.35.3 的默认模板完全一样（SDK 里 `gradle_utils.dart`：Gradle 8.12、AGP 8.9.1、Kotlin 2.1.0）。安卓插件 4.12.0 写明支持 Flutter ≥3.35.0。
2. 插件里写的 AGP 8.13.1、Kotlin 2.3.0、Java 17，和我们**已经在用**的 `shared_preferences_android` 2.4.23 一字不差。那个包现在每次打 APK 都在编，没有问题。
3. 插件只多一个 Google 的库 `androidx.webkit` 1.15.0。它要 minSdk ≥23、compileSdk ≥35，我们都满足。

没能实打一次 APK：这台机器连 `dl.google.com`（安卓 SDK 和 Google Maven 都在这里）会被代理拒绝（403）。所以上面是看配置得出的结论，不是编译结果。补救办法见第 7 节。

iOS 补充：仓库里没有 `ios/Podfile`。Codemagic 跑 `flutter build ipa` 时，Flutter 会自动生成 Podfile 并运行 `pod install`（Firebase 现在就是这样装上的）。新插件是本地 pod，纯 Swift，不再从网上拉别的 pod，自带隐私清单（PrivacyInfo.xcprivacy）。iOS 默认还是用 CocoaPods（3.35.3 里 Swift Package Manager 默认没开）。

## 3. 包会大多少

| 平台 | 多出来的部分 | 大小 | 怎么得来的 |
|---|---|---|---|
| 安卓 Dart 代码 | arm64 / armv7 / x86_64 各一份 | +0.19 / +0.22 / +0.19 MB，合计 **+0.6 MB**（原来 26.8 MB，多 2.3%） | **实测**。临时副本里写了一个用到全部所需功能的读本页，按 Phase B 包的编译开关编 release 版 Dart，前后比较 `app.so` |
| 安卓原生代码 | 插件（Kotlin）+ `androidx.webkit` | 估计 0.1–0.3 MB | 估计。打包时会删掉用不到的部分 |
| 安卓网页引擎 | 用手机里的「Android System WebView」 | 0 | 不打进包里 |
| **安卓合计** | `build-apk.yml` 打的是三芯片合一的 APK | **约 1 MB 以内** | |
| iOS Dart 代码 | 只有 arm64 | 估计约 0.2 MB | 参照安卓 arm64 实测；iOS 要 Mac 才能编 |
| iOS 原生代码 | 插件（Swift，源码 0.43 MB） | 估计 0.5–1 MB | 估计 |
| iOS 网页引擎 | WKWebView 是系统自带 | 0 | |
| **iOS 合计** | | **约 1 MB** | 未实测 |

小讀本 HTML 本身另算：检查脚本规定每个文件小于 1 MB。

## 4. CI 和打包要改什么

| 位置 | 只加依赖时 | 做功能时 |
|---|---|---|
| `codemagic.yaml`（iOS） | **不改**。Podfile 在打包时自动生成，`pod install` 自动装上新插件；仓库没有 Podfile.lock，不用更新 | 不改。合并前在功能分支上打一次 TestFlight 包。注意这里 `flutter test || true`，测试失败也不会拦住打包 |
| `.github/workflows/build-apk.yml` | **不改**。Gradle 从已配好的 `google()` 下载 `androidx.webkit` | 不改。合并前在功能分支上跑一次 Build APK（phase_b_templates） |
| `.github/workflows/ci.yml` | **不改**。已验证（见下） | 加一步 `node tool/check_reader_html.js`（1020c 第三节要求 CI 也跑） |
| `tool/ci_flutter_tests.sh` | **不改** | 把读本页测试加进「phase B arm gating」和「phase B arm B pages」两组，分别验 Hybrid 有「問下通通」、规则组没有 |

已验证（临时副本，只加 `webview_flutter: 4.13.1`）：
- `flutter analyze`：93 条提示，和不加时一样，0 个错误。
- `tool/ci_flutter_tests.sh`：六组全部通过。

**测试怎么写**

- WebView 是"原生视图"，Flutter 的部件测试里画不出来。实测：测试里直接打开带 WebView 的页面，会报错（`WebViewPlatform.instance != null` 断言失败）。
- 做法：和现在的 `VoiceRecorder` 一样，**接口加假实现**。
  - 定义一个读本显示接口（例如 `ReaderSurface`）：给它 HTML 和字号，它回报「读到第几节」「撳了哪个按钮」。
  - 正式版用 WebView 实现；测试里换成假实现，显示一段普通文字，可以手动触发"读到第 2 节""撳了 plan"。
  - 这样能测：四种使用事件写入且不含文字、三个按钮去对的页面、返回回到列表、两组只差「問下通通」、开关关时看不到小讀本。
- 不依赖界面的部分写成普通函数，单独测：哪些链接放行（只放 `peizhu://cta/*`）、往 HTML 里加安全规则和 `--fs`、读 `manifest.json`。
- 不推荐另一条路（在测试里伪造整个 WebView 平台层）：要多加一个开发依赖，要实现好几个类，容易随版本坏。
- WebView 里真正的表现（安全规则、缩放、JS 回传、返回手势）CI 测不到，按 1020c 第四节在模拟器和两台真机上测。

## 5. 1020c 第一节 (3) 的六项怎么做

| 需要 | 用什么 | 注意 |
|---|---|---|
| 从 asset 读 HTML，开 JS | `rootBundle.loadString('assets/readers/<id>.html')` → 加工 → `WebViewController.loadHtmlString(html)`；`setJavaScriptMode(JavaScriptMode.unrestricted)` | 也可以用 `loadFlutterAsset`，但那样没法在载入前加安全规则和字号。用 `loadHtmlString` 不给 baseUrl，页面没有"来源地址"，相对路径也载不到东西。所以 HTML 要自成一体：CSS、JS 写在文件里，图用内嵌 SVG 或 `data:` |
| 拦外部导航，只放 `peizhu://` | `NavigationDelegate(onNavigationRequest: …)`：`peizhu://cta/small_action`、`plan`、`thought` → 返回 `prevent`，再转去 App 页面；其他一律 `prevent`，不开浏览器 | iOS 首次载入会以 `about:blank` 经过这里，要放行这一次。页内 `#锚点` 跳转如果要用，也要放行，或者让 HTML 用 JS 滚动 |
| 拦外部请求（图片、样式、脚本、fetch） | **官方包做不到逐个拦**（安卓没有开放 `shouldInterceptRequest`，iOS 没有开放内容拦截规则）。补法：(a) App 载入时在 `<head>` 最前面加 `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:; media-src data:; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">`；(b) `tool/check_reader_html.js` 在 CI 里挡住外链和 `fetch(` 等 | 安卓 WebView 和 iOS WKWebView 都认这条规则。由 App 加，不靠写稿时记得加。内容是我们自己打包的，主要防的是写稿时不小心引用了外部字体或图片；两层足够。另外安卓可关 `setAllowFileAccess(false)`、`setAllowContentAccess(false)` |
| 注入 `--fs` | 同一步加工时加 `<style>:root{--fs:1.18}</style>`，值 = App 当前的字号倍数（`MediaQuery.textScalerOf(context).scale(1)`，和其他页面同一个数） | 1020c 写的是「標準、大、特大」，现在 App 已是五级（1.06–1.30），照实际倍数给。HTML 的字号要写成 `calc(18px * var(--fs))` 这类（检查脚本可加一条：必须用到 `var(--fs)`）。安卓 WebView 一般还会跟手机系统字号再放大一次，要设 `AndroidWebViewController.setTextZoom(100)`，真机核对。高對比模式不会自动套到网页里，要的话同样加一个变量 |
| 关缩放 | `enableZoom(false)`（安卓关 `setSupportZoom`；iOS 插件会加 `user-scalable=no`）＋ App 加工时就放 `<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">` | 双指放大和双击放大都关掉。CSS 加 `-webkit-text-size-adjust:100%`，免得 iPhone 横屏时自动放大字 |
| `data-section` 回传 | `addJavaScriptChannel('PeizhuReader', onMessageReceived: …)`；页面用 `IntersectionObserver` 看到某个 `data-section` 进入视窗时 `PeizhuReader.postMessage('<节编号>')`，每节只发一次 | App 只收符合格式（如 `^[a-z0-9_-]{1,40}$`）且在本单元出现过的编号，其他丢掉，保证 `reader_section` 不带文字。安卓 7 以上、iOS 12.2 以上都支持 |
| 返回键和返回手势 | 页面照常用 `MaterialPageRoute` 打开。WebView 里所有导航都被拦，没有网页历史，返回就是关掉这一页、回到「讀少少」。用 `PopScope`／`dispose` 记 `reader_close` 秒数 | 安卓返回键（含新的预测式返回）走 Flutter，没问题。**iPhone 左边缘右滑**压在 WebView 上时可能不灵，要真机看；不灵就在左边缘留一条 Flutter 自己的窄条接手势，顶部返回键始终在 |

还有两点：
- 安卓旧手机如果「Android System WebView」很旧或被停用，页面可能出不来。可以兜底：出错时改用同名 `.txt` 显示纯文字。
- 安卓首次打开 WebView 要加载引擎，低端机约半秒到一秒，先显示一个"載入中"。

## 6. 其他做法比较

| 做法 | 好处 | 坏处 | 结论 |
|---|---|---|---|
| **`webview_flutter` 4.13.1**（官方） | Flutter 官方维护；能装、不用升系统；包小；HTML、CSS、JS 显示得和浏览器里一样，Junyu 预览什么样老人就看到什么样；上面六项都有现成接口 | 部件测试画不出来（要接口加假实现）；拦不了附带请求（靠安全规则加检查脚本）；字号要另外传；iPhone 返回手势要真机看 | **推荐** |
| `flutter_widget_from_html_core` 0.17.4（不用 WebView，转成 Flutter 原生界面） | 没有原生代码，Gradle、pod 都不碰；部件测试和字号测试都能直接测；字号、高對比自动跟 App；没有 JS 也就没有联网风险 | **不跑 JS**：读到哪一节要在 Flutter 里另写；CSS 只支持一部分（复杂排版、动画不行）；「图文互动」做不了；Junyu 在浏览器里看的效果和 App 里会不一样，要改 1020c 的做法（"JS 开启"） | 备选。如果读本只是图文、不要互动，这条更稳 |
| `flutter_widget_from_html`（完整版） | 同上，多了视频、音频、网络图片 | 会顺带装上 WebView、视频、音频等一串包，比只装 WebView 还重 | 不用 |
| `flutter_html` 3.0.0 | 同类转原生 | 多年测试版后 2025-03 才出 3.0.0，维护慢；CSS 支持更少 | 不用 |
| `flutter_inappwebview` 6.1.5 | 功能最多：安卓能逐个拦请求，两边都能设内容拦截规则，能在页面开始前注入脚本 | 社区包；稳定版停在 2024-10 的 6.1.5，之后只有测试版（2026-02 的 6.2.0-beta.3）；安卓部分写死 compileSdk 34、`androidx.webkit` 1.12；体积更大；Codemagic 用的是最新 Xcode，旧版更容易出编译问题。我们只要很少的功能，用不上它的强项 | 不推荐 |

## 7. 建议和 10/21 风险

**建议**

1. 用 `webview_flutter: 4.13.1`，固定版本。依赖和功能放**同一个 PR**，不先单独加依赖。
2. 全部放在 `htmlReadersEnabled` 后，默认 false。开关关时「讀少少」和现在完全一样。
3. 按第 5 节做：App 载入时加安全规则、视口和 `--fs`；只放行 `peizhu://cta/*`；JS 回传只收节编号；安卓 `setTextZoom(100)`。
4. 读本显示走接口，测试用假实现（第 4 节）。
5. 按 CLAUDE.md：加 WebView 是设计层面的决定，先写决策记录（`docs/decisions/`）；同一个 PR 更新 STUDY_CHANGELOG、architecture、history、backlog。

**10/21 冻结前的风险**

| 风险 | 影响 | 怎么办 |
|---|---|---|
| 这次没有实际编出 APK 和 iOS 包 | 依赖本身在安卓 Gradle 或 iOS pod 上出问题，要到打包才发现 | 功能 PR 合并前：GitHub Actions 跑 Build APK（phase_b_templates），Codemagic 打一次 TestFlight。两个都过了才合 |
| 时间：1020c 排在 1020b 的 C 和第 2 至 4 批之后 | 读本页、列表、检查脚本、测试，估计开发 1 到 1.5 天，再加两台真机测试 | 10/20 晚上前达不到"两个包都打过、两台真机测过"，就整项留到 Phase B 之后。不要只把依赖放进冻结版本 |
| 冻结版本里多一个原生组件 | 开关关着时代码走不到，影响很小；但包里多了它 | 开关默认关；冻结前不升级依赖版本 |
| 开关值 | 1020b 对其他开关的做法是：10/21 第一位 RCT- 登记前定好，之后不改 | 请 Junyu 确认 `htmlReadersEnabled` 也照此办理，并写进冻结配置快照 |
| 稿件格式 | HTML 用了外部字体、没用 `var(--fs)`、或用了太新的 JS 写法，在旧安卓 WebView 上出问题 | 检查脚本挡外链；建议加查 `var(--fs)`；JS 写法保守些（不用 `?.`、`??` 这类新写法） |
| iPhone 左滑返回 | 可能被 WebView 吃掉 | 真机测；不灵就加左边缘接手势的窄条 |

## 8. 依据和复现

- 交接：`docs/dev-tasks/dev-tasks-1020c.md`、`dev-tasks-1020b.md`（冻结规则）。
- 试装：仓库里 `flutter pub add webview_flutter --dry-run`（Flutter 3.35.3，SDK 在 scratchpad）。跑完 `git status` 干净。
- 版本要求：pub.dev 的包信息接口（`/api/packages/<名>`）和 pub 缓存里各包的 `pubspec.yaml`。
- 安卓：`android/settings.gradle.kts`（AGP 8.9.1、Kotlin 2.1.0）、`android/gradle/wrapper/gradle-wrapper.properties`（Gradle 8.12）、`android/app/build.gradle.kts`（用 Flutter 默认值）；Flutter SDK `FlutterExtension.kt`（compileSdk 36、minSdk 24、targetSdk 36）、`gradle_utils.dart`；插件 `webview_flutter_android-4.12.0/android/build.gradle.kts`；对照 `shared_preferences_android-2.4.23/android/build.gradle.kts`；`androidx.webkit` 1.15.0 的官方发布说明。
- iOS：`ios/Runner.xcodeproj/project.pbxproj`（15.0）；仓库没有 `ios/Podfile`；插件 `webview_flutter_wkwebview.podspec`、`Package.swift`（13.0）；Flutter SDK `cocoapods.dart`（Podfile 自动生成）、`features.dart`（Swift Package Manager 默认未开）。
- 体积：临时副本里用 `flutter assemble`（和 Gradle 内部调用的同一步，不需要安卓 SDK）编 release 版 Dart，编译开关 `PHASE_B=true`、`RULE_TEMPLATE_REPLIES=true`，三种芯片。前：8,586,160 / 9,536,092 / 8,717,232 字节；后：8,782,768 / 9,765,468 / 8,913,840 字节。
- 部件测试：临时副本里直接打开带 WebView 的页面，得到 `WebViewPlatform.instance != null` 断言错误。
- 只加依赖的临时副本：`flutter analyze` 93 条、0 错误（和不加时相同）；`tool/ci_flutter_tests.sh` 六组全部通过（phase A、phase B arm gating、phase B arm B pages、memory v1 client、rule template replies 两组；"All Flutter suites passed."）。
- 连不上：`dl.google.com`（代理 403），所以没装安卓 SDK、没实打 APK。这里也没有 Mac，没打 iOS 包。
