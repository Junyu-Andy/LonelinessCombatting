# 开发测试装机：Mac 装 iPad，Windows 装安卓手机；TestFlight 小版本只给 dev 组

> 2026-10-20 第一版（1020j）。测试环境的准备见 `local-tests-mac.md`、`local-tests-windows.md`。给参与者装机仍按 `w0-install-script.md`。

## 结论

| 设备 | 用哪台电脑 | 怎么装 |
|---|---|---|
| iPad / iPhone | 只能用 Mac | USB 一行 `flutter run`（第一节），或者走 TestFlight 的 dev 组（第三节） |
| 安卓手机 | Windows（实验室或家里）或 Mac | USB 一行 `flutter run`（第二节），或者 GitHub Actions 打 APK |

- **测试包**可以带 `TESTER_PIN`（打开测试员工具）。**给参与者的包**绝对不能带，规则见 `w0-install-script.md` 2.1。
- **TestFlight**：平时的小版本只发给内部的 dev 组；大版本才加进外部组「陪住 試用」。在 Xcode 上传时选的选项不同（第三节），这一步和代码无关。

## 一、Mac → iPad

### 第一次（每台 iPad 做一次）

1. iPad：设置 → 隐私与安全性 → 拉到最下面 → **开发者模式** → 打开，按提示重启。没有这一项的话，先做第 2 步，插上 Mac 以后就会出现。
2. 用线把 iPad 连上 Mac。iPad 上弹「要信任此电脑吗」→ 信任，输入 iPad 密码。
3. Mac 上用 Xcode 打开工程，让它自动登记这台 iPad：

   ```bash
   cd ~/dev/LonelinessCombatting
   open ios/Runner.xcworkspace
   ```

   左边点最上面的 **Runner** → 中间选 **Signing & Capabilities** → 勾 **Automatically manage signing** → **Team** 选团队 ID 是 `LD7U7N7ZY8` 的那个（就是上传 TestFlight 用的团队）。没有报红就关掉 Xcode。
4. **和 Xcode 配对**：Xcode → Window → Devices and Simulators，左边点这台设备，如果有「Pair」按钮就点一下，在设备上确认。不配对的话，Xcode 列表里看得到设备，`flutter devices` 却看不到（10/20 iPad mini，iPadOS 26）。第一次连接 Xcode 可能还要「Preparing」几分钟，设备保持解锁等它做完。
5. 设备系统要 iOS / iPadOS 15 或更新（App 的最低要求）。

### iOS 要用新版 Flutter（10/20 实测）

**iOS 不能用 3.35.3 编译。** 仓库里的 iOS 工程（`ios/Runner/AppDelegate.swift`、`Info.plist` 的 UIScene 设置）从 10/04 第一次导入起，就是新版 Flutter（3.38 以上）的写法。用 3.35.3 编译会报 `Cannot find type 'FlutterImplicitEngineDelegate'`。以前的 TestFlight 包都是用 Mac 上的 3.44.1 打的。所以：

- **iOS 用 3.44.1**：先找到它的完整路径：`for f in $(which -a flutter); do echo "$f"; "$f" --version | head -1; done`，选显示 3.44.1 的那个。下面命令里的 `$FLUTTER_IOS` 换成这个路径，或者先运行 `FLUTTER_IOS=<那个路径>`。
- 安卓和本地测试照旧用 3.35.3（直接写 `flutter`）。
- 两个版本之间切换后，第一次编译前先跑一次 `flutter clean`（用接下来要用的那个版本）。
- 新版 Xcode 还要求 `ios/Podfile` 里所有组件的最低系统是 15.0。改法见 1020j 开发窗口记录；以后会提交进仓库。

两个版本统一的事记在 `docs/dev/backlog.md`。

### 每次装

```bash
cd ~/dev/LonelinessCombatting
git checkout main && git pull
$FLUTTER_IOS devices                 # 找到 iPad 那一行，第二列是设备 id
$FLUTTER_IOS run --release -d <设备id> \
  --dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true \
  --dart-define=TESTER_PIN=<测试员 PIN>
```

- 第一次装好以后，iPad 打开 App 可能提示「不受信任的开发者」：设置 → 通用 → VPN 与设备管理 → 点开发者 → 信任。
- 装好以后在终端按 `q` 退出，App 留在 iPad 上。
- 想测 PR 的分支：把 `git checkout main` 换成 `git fetch origin && git checkout <分支名>`。
- 用 USB 装会覆盖 TestFlight 版（反过来也一样），登录和本机资料都还在。
- 编译报错就把最后 30 行贴给开发窗口。

## 二、Windows（或 Mac）→ 安卓手机

### 第一次（每部手机做一次）

1. 手机：设置 → 关于手机 → 连续点「版本号」7 下，直到提示「已进入开发者模式」。不同品牌的位置不一样，找不到就搜「版本号」。
2. 设置 → 开发者选项（有的手机在「系统」或「更多设置」里）→ 打开 **USB 调试**。
3. 用线连上电脑，手机弹「允许 USB 调试吗」→ 勾「始终允许」→ 允许。
4. Git Bash 里：

   ```bash
   flutter devices
   ```

   能看到手机型号就好了。看不到的话：换一根能传数据的线；手机通知栏里把 USB 用途改成「文件传输」；三星、小米等手机可能要先装品牌自己的 USB 驱动。

### 每次装

```bash
cd /c/dev/LonelinessCombatting      # Mac 上是 cd ~/dev/LonelinessCombatting
git checkout main && git pull
flutter run --release -d <设备id> \
  --dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true \
  --dart-define=TESTER_PIN=<测试员 PIN>
```

- 只有一部设备连着的时候，`-d <设备id>` 可以省掉。
- 提示「应用未安装」「签名不一致」或 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`：手机上装的是别的电脑打的包，或者是 GitHub 打的包。先在手机上卸载陪住再装（要重新登录）。以后不想再卸载，就照 `local-tests-windows.md` 第三节把签名钥匙复制一次。
- 想打一个 APK 文件发给别人：把 `flutter run --release -d <设备id>` 换成 `flutter build apk --release`，文件在 `build/app/outputs/flutter-apk/app-release.apk`。

### 编译参数一览

| 想测什么 | 加的参数 |
|---|---|
| Phase B 正式界面（最常用） | `--dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true` |
| 加上测试员工具 | 再加 `--dart-define=TESTER_PIN=<PIN>`（「關於」页点版本号 7 下） |
| 小讀本占位测试单元 | 再加 `--dart-define=READER_TEST_UNIT=true`（只能测试，不能给参与者） |
| Phase A（老版本界面） | 什么都不加 |

和 GitHub Actions「Build APK」的几个选项一一对应（`.github/workflows/build-apk.yml`）。

## 三、TestFlight：小版本只发 dev 组，大版本才发外部组

**这不在代码里改。** 发给哪个组，取决于两处：Xcode 上传时选哪个选项，以及 App Store Connect 里各个测试组的设置。

### 一次性设置（App Store Connect）

1. App Store Connect → 我的 App → 陪住 → **TestFlight**。
2. 先找到现在每次都会收到新版本的那个组（比如以前建的测试组）。在左边栏它在哪一栏下面：
   - 在 **Internal Testing（内部测试）** 下面：点进去 → 把 **Automatic Distribution（自动分发）** 关掉。**不用删人**：关掉以后这个组只收到你手动加的版本（大版本时在它的 **Builds** 页「+」）。已经发给它的旧版本，不想让它装就在 Builds 页「从组里移除」；不要点「Expire Build」，那会让所有组都装不了。
   - 同一个人同时在两个内部组里，两个组的版本都会收到。只想让他看大版本，就别把他放进 dev 组。
   - 「用户和访问」里删人是把人移出整个团队，和测试组无关，不要为这个去删。
   - 在 **External Testing（外部测试）** 下面：点进去 → **Builds** 页，把不该发给它们的版本移除。以后上传时选「TestFlight Internal Only」（见下面），新版本就进不了外部组。
3. 建 dev 组：左边 **Internal Testing** 旁边的「+」→ 组名 `dev` → 勾 **Enable automatic distribution** → 把要测试的人加进去。内部组只能加 App Store Connect 团队里的人：先在「用户和访问」（Users and Access）里邀请他们，角色选「开发者」或「营销」都行。

### 每次上传

| 这次是 | Xcode → Window → Organizer → Distribute App 时选 | 上传后 |
|---|---|---|
| 平时的小版本 | **TestFlight Internal Only** | 自动出现在 dev 组，不用再点。这个版本**永远不会**到外部组 |
| 大版本（给参与者或外部测试员） | **App Store Connect**（或「TestFlight & App Store」） | TestFlight → External Testing → 陪住 試用 → Builds → 「+」→ 选这个版本，手动加 |

- 小版本可以带 `TESTER_PIN`，因为只有内部的人拿得到。**大版本绝对不能带**，打包参数照 `ios-testflight.md` 第二节。
- 同一个包不能先当小版本、后来又改成大版本：选了 Internal Only 上传的包，以后加不进外部组。大版本要重新打包，build 号 +1，选 App Store Connect 上传。
