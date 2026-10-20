# Android 固定签名钥匙

> 2026-10-20 第一版（1020j 第二节）。

## 结论

- 以前 GitHub Actions 每次打包都用一把新的、随机的签名钥匙。所以装新版本必须先卸载旧的，再重新登录，老人自己做不到。
- 现在改成**一把固定的钥匙**：钥匙放在仓库的 Secret 里，每次打包都用它签。之后的更新可以直接覆盖安装，不用卸载，也不用重新登录。
- **没有这把钥匙，Build APK 会直接失败**，不会再悄悄用随机钥匙打包。
- 钥匙文件和密码由 Junyu 保管，另存一份离线备份。**钥匙丢了，已经装好的 App 就再也不能直接更新**，所有人都要卸载重装。
- 已经装着旧包的人（PILOT 两位、PB-01 至 04）换到新包时，还要**再卸载一次**；之后就不用了。
- RCT- 参与者从 W0 起装的第一个包就是用固定钥匙签的，以后的更新都直接覆盖。

## 一、第一次准备（Junyu，大约 15 分钟，只做一次）

要在打冻结构建**之前**做完。

### 1. 在 Mac 上生成钥匙

打开终端，运行（`keytool` 是 Java 自带的，装了 Java 21 就有）：

```bash
mkdir -p ~/dev/keys
keytool -genkeypair -v -keystore ~/dev/keys/peizhu-release.jks \
  -alias peizhu -keyalg RSA -keysize 4096 -validity 10000 -storetype PKCS12
```

- 它会让你输两次密码。用一个长密码，存进你的密码管理器。
- 接着问姓名、单位、城市等，照实填或直接按回车跳过都可以；最后输入 `y` 确认。
- 完成后运行：

  ```bash
  chmod 600 ~/dev/keys/peizhu-release.jks
  ```

### 2. 记下钥匙的指纹

```bash
keytool -list -v -keystore ~/dev/keys/peizhu-release.jks -alias peizhu | grep SHA256
```

会打印一行 `SHA256: AB:CD:…`。把冒号后面那串复制下来，第 4 步要用。

### 3. 离线备份

把 `~/dev/keys/peizhu-release.jks` 复制一份到离线的地方，例如加密 U 盘，或者密码管理器的附件；密码另外存。不要发邮件，不要放进仓库。仓库的 `.gitignore` 已经挡住 `.jks` 文件。

### 4. 放进 GitHub

打开仓库网页 → **Settings** → **Secrets and variables** → **Actions**。

在 **Secrets** 标签，点 **New repository secret**，加四个：

| 名称 | 值 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | 钥匙文件转成的一长串文字，见下面 |
| `ANDROID_KEYSTORE_PASSWORD` | 第 1 步的密码 |
| `ANDROID_KEY_ALIAS` | `peizhu` |
| `ANDROID_KEY_PASSWORD` | 第 1 步的密码（同一个） |

第一项的值这样得到：在终端运行下面这行，它会把那串文字复制进剪贴板，再粘贴进网页。

```bash
base64 -i ~/dev/keys/peizhu-release.jks | pbcopy
```

再到 **Variables** 标签，点 **New repository variable**：

| 名称 | 值 |
|---|---|
| `ANDROID_SIGNING_SHA256` | 第 2 步复制的那串（带不带冒号都行） |

设了这个变量以后，哪次打包签出来的指纹和它不一样，构建就失败。这样可以挡住有人误换了钥匙。

## 二、打包

和以前一样：**Actions** → **Build APK** → **Run workflow** → 选分支和版本。

- 跑完后，打开这次运行的页面，**Summary** 里有一段「APK 签名」，写着证书 SHA-256。每次都应该和第 2 步的一样。
- 构建失败、提示 `Release signing secrets missing`：第一节第 4 步的 Secret 没设全。
- 构建失败、提示 `is not ANDROID_SIGNING_SHA256`：签名和登记的指纹不一样。**不要把这个包发给参与者**，告诉开发窗口。

## 三、参与者怎样装

| 谁 | 怎么做 |
|---|---|
| RCT-（10/21 起的 W0） | 直接装冻结构建。以后的更新点开新的 APK，选「更新」，不用卸载，登录保留 |
| PILOT 两位、PB-01 至 04 | 手机上的旧包是随机钥匙签的。换到新包时，要先卸载旧的、装新的、重新登录，**只这一次**。服务器上的资料不受影响；手机里还没上传的草稿会丢 |
| 测试员 | 同 PILOT：换一次，之后直接更新 |

## 四、要注意

- **版本号不能往回改。** Android 只拒绝「比已装版本号小」的包。`pubspec.yaml` 里 `version: 1.0.0+N` 的 `N`，以后只能增加或不变。
- **App Check**：App 正式包用 Play Integrity，从 APK 直接安装的 App 本来就拿不到 Play Integrity 的凭证。现在服务器没有强制 App Check，所以换钥匙对它没有影响。将来如果要强制，要先在 Firebase 控制台登记这把钥匙的 SHA-256。
- **iPhone 不受影响**：iPhone 走 TestFlight，签名由 Apple 管。
- 本机 `flutter run --release` 没有设这些环境变量，仍用本机的调试钥匙。那样打出来的包不要给参与者。
