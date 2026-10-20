# 在 Windows 上跑测试、给安卓手机装包（实验室和家里两台电脑）

> 2026-10-20 第一版（1020j）。Mac 的版本见 `local-tests-mac.md`，装机见 `dev-install-devices.md`。

## 结论

- 实验室和家里两台电脑**做一模一样的准备**，每台做一次，大约 1 小时（大部分时间在下载）。
- 准备好以后，两台电脑用法一样：
  - **跑测试**：打开「Git Bash」，和 Mac 用同一行命令 `bash tool/run_local_tests_mac.sh`（名字带 mac，Windows 也用它）。
  - **装安卓手机**：USB 连上手机，一行 `flutter run`。见 `dev-install-devices.md` 第二节。
- Windows **不能打 iPad / iPhone 的包**。iPad 只能用 Mac 装，或者走 TestFlight。
- 两台电脑之间不传文件，代码全部靠 `git pull` 同步。只有一个例外：「签名钥匙」复制一次（第三节），这样两台电脑打的包可以互相覆盖安装，手机上不用卸载。

## 一、第一次准备（每台电脑做一次）

### 1. 打开 PowerShell

开始菜单搜「PowerShell」，点「Windows PowerShell」。下面 1–4 步都在这个窗口里，一行一行复制进去按回车。

`winget` 是 Windows 自带的装软件工具。如果提示「无法识别 winget」，先在 Microsoft Store 里更新「应用安装程序」（App Installer）。

### 2. 装 Git、Java 21、Node 管理工具、Android Studio

```powershell
winget install --id Git.Git -e
winget install --id EclipseAdoptium.Temurin.21.JDK -e
winget install --id CoreyButler.NVMforWindows -e
winget install --id Google.AndroidStudio -e
```

- 每一行可能弹出「是否允许此应用更改设备」，点「是」。实验室电脑如果没有管理员权限，就请 IT 帮忙装这四个。
- **装 Node 管理工具之前**，如果电脑上已经单独装过 Node（「设置 → 应用」里能找到 Node.js），先把它卸载，否则两个会打架。

装完**关掉 PowerShell，重新开一个**。

### 3. 装 Node 24 和 firebase-tools

这一步要「以管理员身份运行」PowerShell：开始菜单搜「PowerShell」→ 右键 → 以管理员身份运行。

```powershell
nvm install 24
nvm use 24
node -v
npm install -g firebase-tools
```

`node -v` 要显示 `v24.x`。

### 4. 打开「开发人员模式」

Flutter 在 Windows 上编译要用到它。

```powershell
start ms-settings:developers
```

在打开的页面里把「开发人员模式」打开。

### 5. 装 Flutter 3.35.3

从这一步起改用 **Git Bash**：开始菜单搜「Git Bash」打开。之后在 Windows 上跑命令，一律用 Git Bash。

```bash
git config --global core.autocrlf input
git config --global core.longpaths true
mkdir -p /c/dev
git clone https://github.com/flutter/flutter.git -b 3.35.3 /c/dev/flutter
```

第一行很重要：不加的话，Git 会把脚本的换行改成 Windows 格式，测试脚本就跑不起来。

然后把 Flutter 加进系统路径。回到 **PowerShell**（普通的就行）运行：

```powershell
[Environment]::SetEnvironmentVariable('Path', 'C:\dev\flutter\bin;' + [Environment]::GetEnvironmentVariable('Path', 'User'), 'User')
```

关掉所有终端窗口，重新开一个 Git Bash：

```bash
which -a flutter     # 第一行要是 /c/dev/flutter/bin/flutter
flutter --version    # 第一行 Flutter 3.35.3（第一次会下载几分钟）
```

如果 `which -a flutter` 的第一行不是 `/c/dev/flutter/bin/flutter`，说明电脑上还有一个旧的 Flutter 排在前面。把那一段贴给开发窗口。

### 6. Android Studio 第一次打开

1. 开始菜单打开 Android Studio，一路选 **Standard**、Next，等它下载完 Android SDK（10–20 分钟）。
2. 欢迎页 → **More Actions → SDK Manager** → 上面选 **SDK Tools** 页 → 勾 **Android SDK Command-line Tools (latest)** → Apply。
3. 关掉 Android Studio。以后不用打开它。
4. Git Bash 里：

   ```bash
   flutter doctor --android-licenses     # 一路按 y 回车
   flutter doctor
   ```

   `flutter doctor` 里 **Flutter** 和 **Android toolchain** 两项要是 ✓。「Visual Studio」那一项是 ✗ 也没关系（只有做 Windows 桌面版才要），Chrome 那项也不用管。

### 7. 拿代码

```bash
cd /c/dev
git clone https://github.com/Junyu-Andy/LonelinessCombatting.git
cd LonelinessCombatting
```

第一次会弹出 GitHub 登录窗口，用你的 GitHub 帐号登录。

### 8. 最后检查一遍（Git Bash）

```bash
flutter --version    # 第一行 Flutter 3.35.3
node -v              # v24.x
java -version        # 带 "21"
firebase --version   # 有数字
```

四项都对就准备好了。两台电脑都做完第一到第八步。

## 二、跑测试

**用 Git Bash，不用 PowerShell。** 每次都新开一个窗口。

```bash
cd /c/dev/LonelinessCombatting
git checkout main
git pull
bash tool/run_local_tests_mac.sh
```

- 想测某个 PR 的分支：把 `git checkout main` 换成 `git fetch origin && git checkout <分支名>`。
- 只跑一部分、结果怎么看、日志在哪里，都和 Mac 一样，见 `local-tests-mac.md` 第二、三节。
- 第一次跑模拟器，Windows 防火墙可能弹窗问「是否允许 Java / Node 访问网络」。点「允许」或「取消」都可以，模拟器只用本机。

### Windows 上的常见报错

| 看到 | 怎么办 |
|---|---|
| `$'\r': command not found` | 第一节第 5 步的 `core.autocrlf input` 没设。设好以后，把仓库文件夹删掉重新 `git clone` |
| 「端口被占用：8080（进程 1234：java.exe）」 | 上次的模拟器没关。Git Bash 里 `taskkill //PID 1234 //F`（把 1234 换成提示里的进程号），再跑 |
| 「✗ 停止：设了正式项目的钥匙 GOOGLE_APPLICATION_CREDENTIALS」 | 这个窗口设过正式项目的钥匙。关掉开新窗口；新窗口还是这样，说明它写进了 Windows 的环境变量：开始菜单搜「编辑系统环境变量」→ 环境变量 → 删掉 `GOOGLE_APPLICATION_CREDENTIALS` |
| `flutter: command not found` | 第一节第 5 步加路径之后没有重开窗口，或者加错了。重开 Git Bash 再试 |
| `java -version` 显示 17 或别的版本 | 开始菜单搜「编辑系统环境变量」→ 环境变量 → Path，把 `Eclipse Adoptium\jdk-21…` 那一行移到最上面，重开窗口 |
| 其他 | 把汇总那一段和对应的日志文件发给开发窗口 |

## 三、两台电脑之间：签名钥匙复制一次

**为什么要做：** 每台电脑第一次打安卓包时，会自动生成一把自己的「签名钥匙」。手机只允许**同一把钥匙**签的包覆盖安装。实验室打的包装在手机上，回家用家里电脑再装，就会提示「应用未安装」或「签名不一致」，只能先卸载。卸载会清掉手机上的登录和本机资料（服务器上的资料还在，要重新登录）。

**做法（只做一次）：** 两台电脑都至少跑过一次 `flutter run` 或 `flutter build apk` 之后：

1. 在**实验室电脑**上找到这个文件：`C:\Users\<你的用户名>\.android\debug.keystore`。
2. 用 U 盘或网盘把它复制到**家里电脑**的同一个位置，覆盖原来的那个。
3. Mac 也想打安卓包的话，同样复制到 Mac 的 `~/.android/debug.keystore`。

之后三台电脑打的包是同一把钥匙，可以互相覆盖安装。

- 这把钥匙只用于测试包，不是正式发布的钥匙，丢了也没关系，大不了手机卸载重装一次。
- GitHub Actions「Build APK」打出来的包每次都是另一把钥匙。从 GitHub 的包换到自己电脑打的包（或者反过来），还是要先卸载。
- 服务器没有检查 App 的签名（App Check 没有强制），所以哪台电脑打的包都能正常连上服务器。
