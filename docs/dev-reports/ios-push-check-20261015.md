# iPhone 推送三问：代码核查（2026-10-15）

对象：仓库 `main`（提交 `4436a80`，合并 PR #82 之后）。只读代码，没有改任何代码；没有连 Firebase 项目，没有碰生产数据。热线号码没有涉及。

## 0. 结论

1. **通知权限在「登入」或「建立帳號」成功的那一刻请求**，不是第一次打开 App，也不在引导里，也不等登记。老人按下登入键后一两秒，系统弹窗就压在下一页上面（新账号是同意页，登记门开着没登记的人是等待页 S8，老用户是主页）。弹窗之前没有任何 App 自己的解释页。
2. **令牌不在 `users/{uid}` 的字段里，而在子集合 `users/{uid}/fcm_tokens/{令牌前 16 位}`**，字段 `token`、`platform`、`updatedAt`。代码**没有**调用 `getAPNSToken`，直接 `getToken()`；iPhone 上没有 APNs 令牌时 `getToken()` 抛错，代码接住，**什么都不写**（不是写空字串）。写入时机是**登录后**（同意页之前），之后每次冷启动都会再试一次。
3. **`ios/Runner/GoogleService-Info.plist` 在仓库里**，`BUNDLE_ID = hk.hku.hkuimse.withyouapp`，和 Xcode 工程、`lib/firebase_options.dart`、`firebase.json` 四处一致，三处写的是同一个 iOS 应用编号 `1:1036416880071:ios:1e4db1760f64ac52a91de2`。AppDelegate 和 Info.plist **不缺 firebase_messaging 要的东西**：`FirebaseAppDelegateProxyEnabled` 没写等于默认开（插件默认就要开），所以 AppDelegate 不需要加代码。真正缺的只有 Push Notifications 能力（没有 `Runner.entitlements`、工程里没有 `aps-environment`）和 Background Modes。
4. **加完 Xcode 两项能力后，仓库里不需要再改别的文件**；锁屏能不能收到，卡在仓库外的两件事：Firebase 控制台上传 APNs 密钥（`.p8`），以及签名用的描述文件要带 Push 能力。另外第一次装机那一次 `getToken()` 可能赶不上 APNs 令牌（第 2.3 节），测试时装好、允许通知后**杀掉 App 重开一次**再发测试消息最稳。

---

## 1. App 什么时候请求通知权限

### 1.1 调用链（文件和行号）

| 步骤 | 位置 | 内容 |
|---|---|---|
| 请求权限 | `lib/core/fcm/fcm_service.dart:70`（在 `initialize()` 里，第 59–146 行） | `messaging.requestPermission(alert: true, badge: true, sound: true, provisional: false)`，异常只打日志 |
| 谁调 `initialize` | `lib/app/app.dart:151`，`_onAuthUidChanged(uid)`（第 140–155 行） | uid 从空变成有值时调；变回空时 `deregister()`（第 153 行） |
| 谁调 `_onAuthUidChanged` | `lib/features/auth/presentation/pages/auth_gate.dart:92` | `AuthGate` 监听 `authService.profileChanges()`，每帧画完后（`addPostFrameCallback`，第 80 行）发现 uid 变了就调 |
| `FcmService` 的来源 | `lib/main.dart:131`；`lib/app/app.dart:56、80、269` | `available: firebaseReady`；没有 Firebase 时整段跳过（第 60 行） |

`requestPermission` 的注释（第 66–68 行）说“调用方应先给老人看过 App 自己的解释”，**但现在没有任何页面做这件事**，仓库里也没有别处调用 `requestPermission`。

### 1.2 对应到老人看到的页面

登录前 `AuthGate` 显示登录页（`auth_gate.dart:112–113`），**不会**弹权限窗。老人在登录页按「登入」或「建立帳號」（`login_page.dart:79、291`）成功后：

1. 认证流发出新 profile，`AuthGate` 这一帧画出 `StaffGate → EnrollmentWaitGate → ConsentGate → MainShell`（`auth_gate.dart:121–128`）。`StaffGate` 读角色时先显示一个只有转圈的空页（`staff_gate.dart:117–120`，最多 5 秒）。
2. 这一帧画完，`addPostFrameCallback` 触发 `_onAuthUidChanged` → `fcm.initialize` → `requestPermission`，**系统弹窗出现**。

所以弹窗压在“登录后的第一页”上，视账号而定（`consent_gate.dart:78–95`）：

| 账号状态 | 弹窗下面那一页 |
|---|---|
| 刚建的新账号 | 转圈页，很快变成**同意页**（`ConsentPage`） |
| 登记门开着、还没登记、不是测试员 | **等待页 S8**（`enrollment_wait_gate.dart:55`） |
| 已同意但没做入组问卷 / 没做「介紹三個夥伴」 | 入组问卷页 / 引导第一屏 |
| 老用户 | 主页 |
| 研究员 / 评估员 | 登记页 / 评估员页（弹窗照样出，但随后 `suppressForStaff` 会删掉令牌、退出主题，`fcm_service.dart:52–55、92–95`） |

**之后每次冷启动**：有保存的登录态时 uid 也是“从空变有”，`initialize` 会再跑一遍（`requestPermission` 第二次起 iOS 不再弹，直接返回现状）。老人在这台 iPhone 上**只会看到一次**系统弹窗，就是第一次登录那次；拒绝了以后要去 iOS「設定」里开。

### 1.3 老人看到的文字

弹窗是 iOS 系统的，App 控制不了内容，只带 App 名「陪住」（`Info.plist` 的 `CFBundleDisplayName`）。弹窗前没有 App 自己的说明文字。若以后想加一句（放开关后，先写草稿）：

> 【草稿】「陪住」想俾你手機提醒：每日傾偈、每星期答幾條問題。下一個畫面㩒「允許」就得。

本次不改代码。

---

## 2. FCM 令牌存在哪里、怎么取

### 2.1 存放位置

- **不是** `users/{uid}` 上的字段。写在子集合 `users/{uid}/fcm_tokens/{docId}`（`fcm_service.dart:172–187`），`docId` 是令牌前 16 位（第 191–192 行）。
- 文档字段：`token`（完整令牌）、`platform`（`iOS` / `android` 等）、`updatedAt`（服务器时间）。`merge: true`。
- 登出时删这份文档并退出主题（第 149–170 行）。
- Firestore 规则：`fcm_tokens` 即使登记门开着也允许写（`firestore.rules:130、145`），所以没登记的 iPhone 也能登记令牌。

**服务器怎么读**：所有按人发的推送都读这个子集合（`functions/reminders.js:210`、`functions/weekly_schedule.js:490`、`functions/index.js:2299、2644`、`functions/ada.js:307`、`functions/djg_w2.js:249`），只取 `typeof token === "string" && token.length > 0`。每日/星期日的 doorbell 不读令牌，发主题 `all`（`functions/index.js:1745`），靠 App 端 `subscribeToTopic('all')`（`fcm_service.dart:107`）。测试推送 `sendTestPush` 读 `fcm_tokens` 逐个发（`functions/index.js:2624–2650`），只给 `isTester: true` 的账号用。

### 2.2 iOS 上有没有先取 APNs 令牌

**没有。** 全仓库没有 `getAPNSToken` 的调用（在 `lib/`、`test/` 里搜不到）。顺序是：`requestPermission` → 直接 `getToken()`（第 88 行）→ `subscribeToTopic` → 绑 `onTokenRefresh`（第 140 行）。

### 2.3 没有 APNs 令牌时会怎样

firebase_messaging **15.2.10**（`pubspec.lock`）在真机 iPhone 上，APNs 令牌还没到就调 `getToken()` 会抛 `[firebase_messaging/apns-token-not-set]`（代码第 83–85 行的注释也写明了）。代码接住异常，`token` 保持 `null`，**第 96 行判空后不写 Firestore**，所以不会出现空字串令牌，`fcm_tokens` 下根本没有这台 iPhone 的文档。`subscribeToTopic` 同样失败并被接住。结果：服务器那边“找不到令牌”，而不是“令牌为空”。

两个会让第一次装机拿不到令牌的情况：

1. **现在的状态**：没有 Push 能力和 APNs 密钥，APNs 令牌永远不来，每次启动都抛同一个错。这就是 `docs/release/w0-install-script.md` 第 2.3 节说的“iPhone 推送现在收不到”。
2. **补好能力之后的第一次启动**：`requestPermission` 内部会向 Apple 注册远程通知，APNs 令牌是**异步**回来的；紧跟着的 `getToken()` 可能还是抛 `apns-token-not-set`。兜底有两层：`onTokenRefresh`（第 140 行；但它在 `getToken` 之后才绑，令牌如果在这几十毫秒之间到达会漏掉），以及**下一次冷启动**再跑一遍 `initialize`（第 1.2 节）。所以测试流程里“装好 → 允许通知 → 杀掉重开一次 → 看 `fcm_tokens` 有没有 `platform: iOS` 的文档”是必要的一步。

要彻底消掉第 2 种情况，Firebase 官方做法是先 `getAPNSToken()`，为空就短暂重试后再 `getToken()`。这是 App 行为改动，按规则要放开关后、另开 PR、同一 PR 更新 `docs/STUDY_CHANGELOG.md` 和 `docs/dev/architecture.md`。本报告不做。

### 2.4 登录前还是登录后写

**登录后。** `initialize(uid)` 需要 uid，由第 1.1 节的链条在登录成功后触发；写入 Firestore 用的是已登录的身份。顺序上在同意页、入组问卷、引导**之前**，也早于研究员登记（登记门开着的人先到 S8，令牌照样写）。登录前（登录页）没有任何 FCM 调用。

---

## 3. iOS 工程配置

### 3.1 GoogleService-Info.plist

- 文件在：`ios/Runner/GoogleService-Info.plist`，已提交（提交 `7aced0d`「iOS signing + Firebase config onto main」）。不在 `.gitignore` 里。
- `BUNDLE_ID = hk.hku.hkuimse.withyouapp`，`PROJECT_ID = loneliness-pilot-dev`，`GOOGLE_APP_ID = 1:1036416880071:ios:1e4db1760f64ac52a91de2`。

四处对照：

| 位置 | 值 |
|---|---|
| `ios/Runner/GoogleService-Info.plist` | `hk.hku.hkuimse.withyouapp`，appId `…:ios:1e4db1760f64ac52a91de2` |
| `ios/Runner.xcodeproj/project.pbxproj:388、571、597`（Runner 三个配置） | `PRODUCT_BUNDLE_IDENTIFIER = hk.hku.hkuimse.withyouapp` |
| `lib/firebase_options.dart:68、72` | 同一 appId，`iosBundleId: 'hk.hku.hkuimse.withyouapp'` |
| `firebase.json` `flutter.platforms.ios.default.appId` | 同一 appId |

**和 Firebase 项目里的 iOS 应用一致吗**：plist 和 `firebase_options.dart` 都是 FlutterFire CLI 从项目下载/生成的（`firebase.json` 记录了这次生成），三处 appId 相同，说明 Firebase 项目里确有一个 bundle id 为 `hk.hku.hkuimse.withyouapp` 的 iOS 应用。本次没有登录 Firebase 控制台核对（规则 2），控制台上要人眼看的只剩两项：项目设置 → 您的应用 → iOS 应用的 bundle id，以及 Cloud Messaging → Apple 应用配置里有没有 APNs 密钥（`docs/release/prelaunch-checklist.md` B5）。

补充：App 在 `lib/main.dart:43–44` 用 `DefaultFirebaseOptions.currentPlatform` 初始化，不是靠读 plist，所以即使 plist 不在，Firebase 也能启动；保留 plist 是为了原生 SDK 和 Codemagic 的 Restore 步骤（`codemagic.yaml` 第 40–47 行）。`RunnerTests` 目标的 bundle id 还是模板的 `com.example.appDemo.RunnerTests`，不影响推送。

### 3.2 AppDelegate.swift

`ios/Runner/AppDelegate.swift` 是 Flutter 3.35 的模板：`FlutterAppDelegate` + `FlutterImplicitEngineDelegate`，只注册插件，没有任何 Firebase 代码。**这是对的**：

- `Info.plist` 没写 `FirebaseAppDelegateProxyEnabled`，等于默认 `YES`（方法替换开着），firebase_messaging 默认就按这个模式工作：APNs 令牌由插件自己转给 Firebase，通知点击也由插件接。只有把这个键设成 `NO` 时才需要在 AppDelegate 手写 `didRegisterForRemoteNotificationsWithDeviceToken` 等回调。现在不需要。
- 不需要 `FirebaseApp.configure()`，因为初始化在 Dart 侧（`main.dart:43`）。

一点要在真机确认的：工程用了 Flutter 3.35 的 UIScene 启动方式（`Info.plist` 的 `UIApplicationSceneManifest` → `FlutterSceneDelegate`）。远程通知注册回调仍走 AppDelegate，插件 15.2.10 按理没问题，但这是新路径，第一次真机测试时留意一下日志里有没有 `apns-token-not-set` 一直不消失。

### 3.3 Info.plist

有：`CFBundleDisplayName = 陪住`、`ITSAppUsesNonExemptEncryption = false`、麦克风和语音识别的说明文字。

没有、也**不该**有：`FirebaseAppDelegateProxyEnabled`（见上）。

没有、**要加**：`UIBackgroundModes` 含 `remote-notification`。这是 Xcode 勾 Background Modes → Remote notifications 时自动写进 Info.plist 的。严格说只显示横幅不靠它（它是静默推送 / 后台数据消息用的），但 FlutterFire 文档把它列为标准配置，勾上即可。

### 3.4 Push 能力（缺）

- `ios/Runner/` 下没有 `Runner.entitlements`；`project.pbxproj` 没有 `CODE_SIGN_ENTITLEMENTS`，也没有 `SystemCapabilities` / `com.apple.Push`。签名是 `CODE_SIGN_STYLE = Automatic`。
- 这就是 `w0-install-script.md` 2.3 节第 3 步要补的东西。

### 3.5 依赖管理方式（顺带）

`ios/` 没有 `Podfile`，工程走 Swift Package Manager（`project.pbxproj` 里的 `FlutterGeneratedPluginSwiftPackage`）。iOS 已经打过 1.0.0+3（提交 `230c158`），说明 firebase_messaging 在这条路上能编过，不是障碍。`codemagic.yaml` 里 `cocoapods: default` 一行用不上但无害。

---

## 4. 加完 Push Notifications 和 Background Modes 后，还要改什么

**仓库里：不需要再改别的文件。** `Runner.entitlements`（`aps-environment`）、`project.pbxproj`（`CODE_SIGN_ENTITLEMENTS` + `SystemCapabilities`）、`Info.plist`（`UIBackgroundModes`）之外，Dart 和 Swift 都不用动，原因见第 3.2 节（替换默认开）和第 2 节（权限、令牌、主题都已写好）。`sendTestPush` 发的是带 `notification.title/body` 的普通消息，iOS 不需要额外的 `apns` 字段就会在锁屏显示。

**仓库外，缺一样都收不到：**

| 项 | 在哪做 | 不做的后果 |
|---|---|---|
| APNs 密钥 `.p8`（Key ID、Team ID） | Apple Developer → Keys 新建；上传到 Firebase 控制台 → 项目设置 → Cloud Messaging → Apple 应用 | 令牌拿得到、Firestore 也有，但服务器发送报 `third-party-auth-error`，手机一条也不到 |
| App ID 开 Push Notifications、描述文件带 Push | Xcode 自动签名加能力时会自动改 App ID 并重发描述文件；Codemagic 的 `xcode-project use-profiles` 用的描述文件要重新生成 | 安装或签名时报 entitlements 不匹配，或 APNs 令牌永远不来 |
| 真机 + 允许通知 | 模拟器不发 APNs 令牌（Apple 芯片 Mac 的 iOS 16+ 模拟器例外，不建议用来验） | 一直 `apns-token-not-set` |

**测试步骤建议（只用测试账号，不动参与者数据）**：

1. Xcode 加两项能力 → 提交 `Runner.entitlements`、`project.pbxproj`、`Info.plist` 开 PR；同一 PR 按 CLAUDE.md 更新 `docs/STUDY_CHANGELOG.md`（推送相关）和 `docs/dev/architecture.md`，并把 `w0-install-script.md` 2.3 节、`prelaunch-checklist.md` B5 划掉。
2. 上传 `.p8` 到 Firebase 控制台。
3. 真机装包，用 `isTester: true` 的测试账号登录，系统弹窗选允许。
4. **杀掉 App 重开一次**（第 2.3 节的原因），到 Firestore 看 `users/{测试uid}/fcm_tokens/` 出现 `platform: iOS` 的文档。
5. 锁屏，然后：用测试工具页的测试推送按钮（`sendTestPush`，15 秒延迟），或者在 Firebase 控制台 Messaging 对这个令牌发一条测试消息。
6. 收不到时按顺序查：Firestore 没有 iOS 令牌文档 → 第 2.3 节；有令牌但 `sendTestPush` 返回 `errors` 里有 `third-party-auth-error` → APNs 密钥；`errors` 空但手机没显示 → 手机通知设置或 App 在前台（App 没调 `setForegroundNotificationPresentationOptions`，前台时 iOS 默认不显示横幅，锁屏不受影响）。

注意 Debug 装（USB）用的是 `aps-environment = development`，TestFlight 是 `production`；Firebase 的 `.p8` 密钥两种都通用，不用分别配。

---

## 5. 本次没有做的事

- 没有改代码、没有加开关、没有改任何热线号码。
- 没有连 Firebase 控制台或 Apple Developer，第 3.1 节“与 Firebase 项目一致”是从仓库内三处相同 appId 推出的，控制台那一眼留给 Junyu。
- 第 2.3 节的 `getAPNSToken` 加固是建议，不在本 PR 里做。
