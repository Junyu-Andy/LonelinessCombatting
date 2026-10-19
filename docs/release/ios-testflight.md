# iPhone 更新走 TestFlight（10/16 Junyu 定）

> 结论先说：以后 iPhone 的安装和更新都走 TestFlight 的「外部测试」公开链接。老人和 RA 不用 Apple ID 进团队，装一个 TestFlight App、点一条链接就能装；以后每次更新 TestFlight 自己提示。**测试员可以在 TestFlight 里自己选装哪个版本**（「先前的版本」），旧版本保留 90 天。10/15 用 USB 装的那部手机，10/22 改装 TestFlight 版即可，资料保留。

## 一、你要先做一次的事（只做一次）

1. **接受开发者协议**：App Store Connect 用 Account Holder 登录，首页若有黄色横幅「Agreements」就点进去接受。不接受，外部测试提交不了。
2. **App Store Connect 建 App 记录**（如果还没有）：My Apps → 「+」→ New App → 平台 iOS、名称「陪住」、Bundle ID `hk.hku.hkuimse.withyouapp`、SKU 随便填（例如 `withyou-2026`）。
3. **建一个外部测试组**：App → TestFlight → External Testing → 「+」→ 组名「陪住 試用」→ 勾 **Enable Public Link**。会得到一条 `https://testflight.apple.com/join/XXXXXXXX` 的链接，存好，之后每个人都用它。
4. **测试信息**（External Testing 页面右侧「Test Information」）：填一个联系邮箱和一段测试说明（可以写「香港長者陪伴研究試用」），隐私政策网址填现有的那条。第一次提交外部测试要过 Apple 的 Beta 审核，通常 1–2 天；之后同一个 App 的新版本一般不用再审（改动大时偶尔会再审）。**建议今天就上传第一个包提交审核，别等到 10/22。**

## 二、每次出新版本（每次都做）

在 Mac 上，仓库 `main` 拉到最新：

```bash
flutter pub get
flutter build ipa --release \
  --dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true \
  --build-number=<比上次大的整数>
```

- `--build-number` 每次上传必须比上一次大（例如 3、4、5……）。版本号（1.0.0 那种）不用改。
- 上传：打开 Xcode → Window → Organizer → 选刚 archive 的那条 → Distribute App → TestFlight & App Store → 一路 Next。或者用 Transporter App 拖 `build/ios/ipa/*.ipa`。
- App Store Connect → TestFlight：等「Processing」变成可用（10–30 分钟）。第一次会问「出口合规」，选 **None of the algorithms mentioned above**（只用 HTTPS），以后可在 `Info.plist` 加 `ITSAppUsesNonExemptEncryption = NO` 就不再问。
- 把这个版本**加进「陪住 試用」组**：External Testing → 组 → Builds → 「+」→ 选版本 → 提交。第一次会进 Beta 审核。

## 三、测试员和老人这边

1. App Store 装 **TestFlight**。
2. 在手机 Safari 打开公开链接 → Accept → Install。桌面出现「陪住」，图标角上有个小黄点，是 TestFlight 版的标记。
3. 以后有新版本，TestFlight 会推送通知；打开 TestFlight 点 Update 就行。
4. **想自己换版本**：TestFlight → 陪住 → 往下拉到 **Previous Builds（先前的版本）** → 选一个 → Install。只要那个版本还没过期（上传后 90 天）、你没有在 App Store Connect 里把它从组里拿掉，就能装。装旧版不会清资料。
5. 不想自动提示更新：TestFlight → 陪住 → 关掉 **Automatic Updates**。

## 四、和研究流程有关的几点

- **资料保留**：TestFlight 版和 10/15 USB 装的开发版是同一个 Bundle ID、同一个团队，直接覆盖安装，登录和本机资料都在。10/22 给那部 iPhone 装 TestFlight 版即可，不用重新登记。
- **版本号记录**：面访记录里记「自己 → 關於」看到的版本和 build 号；同一位老人中途换版本要在 `docs/STUDY_CHANGELOG.md` 对应行的「生效方式」能查到。
- **推送**：TestFlight 版用的是正式推送证书（APNs），APNs 密钥按 `w0-install-script.md` 2.3 节补上后，TestFlight 版能收推送。
- **测试组里放谁**：老人、Maria、你自己都用同一条公开链接。公开链接默认上限 10,000 人，够用；不想外人进来就把链接只发给需要的人，或在组设置里关掉 Public Link 改成按邮箱邀请。
- **内部测试（Internal Testing）不用**：那要把每个人的 Apple ID 加进 App Store Connect 团队，老人多半没有 Apple ID，而且团队名单里会出现参与者。

## 五、常见卡点

| 现象 | 原因 | 做法 |
|---|---|---|
| 上传后一直 Processing 超过一小时 | Apple 偶发 | 等；超过两小时重新上传一个 build 号 +1 的包 |
| 「Missing Compliance」 | 出口合规没答 | 在 TestFlight 版本页点 Manage → 选 None of the algorithms |
| 外部测试按钮灰的 | 开发者协议没接受 | 第一节第 1 条 |
| 老人点链接说「无法接受邀请」 | 手机没装 TestFlight，或 iOS 版本低于 TestFlight 要求 | 先装 TestFlight；iOS 15 以下的旧机走 USB |
| Previous Builds 里没有旧版 | 旧版过了 90 天，或被从组里移除 | 重新上传一个包，或在 App Store Connect 把旧版重新加进组 |
