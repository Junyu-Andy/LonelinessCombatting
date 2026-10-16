# W0 面访：装 App 和入组引导（v1，2026-10-15）

给 Junyu 在 W0 面访时照做。按 `main @ c1f88d6`（#59–#76 全部合并后）的代码写。取代 PR #61 里的草稿 v0（已关闭）：v0 第二、四、六节说的问题（引导被跳过、字体不保存、告警只有旧版）都已修好，顺序也变了。

**状态：操作步骤可用；第四节「讲给老人听的话」仍是草稿，产品窗口定稿前只能照念给试跑参与者，正式参与者要等定稿。**

## 一、面访前 Junyu 要做的事（一次做完，最晚面访当天上午）

| # | 做什么 | 在哪里 | 不做的后果 |
|---|---|---|---|
| 1 | **Deploy Firebase 已做**：第 7 次运行部署的就是 `main @ c1f88d6`（10/14 15:37 UTC，成功）。#77、#78 只有文档和测试，不用再部署 | GitHub Actions → Deploy Firebase | 以后合了改 `functions/` 或规则的 PR 才要再跑 |
| 2 | `meta/randomization_config.enabled = true`（布尔） | Firebase 控制台 | 登记页提交失败 |
| 3 | `meta/memory_config`：`enabled: true`、`policy: "C"`、`phaseBArmA: true` | 控制台 | Hybrid 组没有记忆 |
| 4 | 团队账号、评估员账号 `users/{uid}.isTester = true`；3 位 PILOT 老人**不要**设 | 控制台 | 团队账号的测试聊天会发告警邮件；登记门开着时团队账号卡在等待页 |
| 5 | 密钥 `PI_EMAIL` = Junyu 的邮箱 | Firebase 控制台 → Functions → Secrets（或 `firebase functions:secrets:set`） | 急性告警没有收件人 |
| 6 | `meta/alert_config`：`enabled: true`、第一收件人 Junyu、后备 Calvin（字段名见 `docs/dev-reports/T34-*.md` 第 2 节）。不建这个文档 = 旧版告警（只发 `PI_EMAIL`，只有急性级） | 控制台 | 两种都能收到急性告警；差别是新版有 12 个字段和后备 |
| 7 | 定登记门：**建议明天保持关**（默认），用第三节「顺序 A」。要开就同时设 `app_config/feature_flags.enrollmentGateEnabled = true` 和 `onboardingAfterEnrollmentFix = true`，用「顺序 B」 | 控制台 | 开了门但没开修复：登记后的引导会整段跳过 |
| 8 | 其他开关保持关：`app_config/phase_b.sessionBriefPrV2Enabled`、`weeklyScheduleV2Enabled`、`socialContactProbeEnabled`、`assessorViewEnabled`，语音输入开关 | 控制台 | 开了会显示【占位】文字 |
| 9 | 打包（第二节） | GitHub Actions / Mac | — |
| 10 | 纸本：ICF、W0 问卷、给老人带回家的卡（登入电邮和密码、研究编号、研究人员电话、W4 日期） | — | — |

布尔值在控制台要选 boolean 类型，写成字符串 `"true"` 不生效。

## 二、打包和装机

### 2.1 两个平台共用的规则

- 参与者包的编译参数固定是 `--dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true`。少一个都不行：没有 `PHASE_B` 显示的是 Phase A 界面；没有 `RULE_TEMPLATE_REPLIES` 规则组没有模板回应。
- 不能带 `FORCE_ARM`、`TESTER_PIN`、`RULE_TEMPLATE_REPLIES_ALLOW_PLACEHOLDER`。
- 一部手机只装这一个包。以前装过陪住的手机先卸载。
- 装好后看「自己 → 關於」的版本号，记进面访记录。

### 2.2 Android

GitHub Actions → Build APK → 选 `phase_b_templates`，从 `main` 打（T36，见 `docs/dev/ci-cd.md`）。传到手机安装，允许「未知来源」。

### 2.3 iOS（10/15 的方案）

**先说结论**：以前上过 TestFlight 的包，如果打包命令没有带上面两个参数，**不能给参与者用**，要重新打。10/15 下午一位参与者，建议走「方案 1：Xcode 用 USB 装」，同一个包同时上传 TestFlight internal 作为以后更新的通道。External TestFlight 要过 Beta 审核（首个包 1–2 天）又卡在开发者协议，10/15 不指望。

| 方案 | 要什么 | 多快 | 有效期 | 缺点 |
|---|---|---|---|---|
| **1. Xcode + USB**（推荐 10/15 用） | 一台能跑 Xcode 的 Mac、数据线、老人手机「信任此电脑」；Xcode 自动签名会把这部手机登记进开发者账号（每年 100 部） | 装机现场 5 分钟 | 付费开发者账号的开发签名到期前（约 1 年） | 以后更新要再连一次线，或改走 TestFlight（同一个 bundle id、同一个团队，TestFlight 包可以直接覆盖，资料保留） |
| 2. TestFlight internal | 上传后等处理（通常 10–30 分钟）；**老人的 Apple ID 要加进 App Store Connect 团队**（给最低权限角色），老人手机装 TestFlight 并接受邀请邮件 | 上传当天 | 每个包 90 天；更新自动 | 老人多半没有 Apple ID 或不会操作邀请；团队成员名单里会出现参与者 |
| 3. TestFlight external | Beta 审核 + 新开发者协议 | 1–2 天起 | 90 天 | 10/15 来不及 |

**方案 1 的命令**（在 Mac 上，仓库 `main`）：

```bash
flutter pub get
flutter devices                      # 找到老人手机的设备 id
flutter run -d <设备id> --release \
  --dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true
```

跑完可以拔线，App 留在手机上。第一次在 Xcode 里要选好 Team（Runner → Signing & Capabilities → Automatically manage signing）。老人手机第一次跑开发签名的 App 要到「設定 → 一般 → VPN 與裝置管理」信任开发者。

**同时上传 TestFlight**（可选，为以后更新）：

```bash
flutter build ipa --release \
  --dart-define=PHASE_B=true --dart-define=RULE_TEMPLATE_REPLIES=true
```

然后用 Xcode 的 Organizer 或 Transporter 上传 `build/ios/ipa/*.ipa`。`codemagic.yaml` 已改成同样的参数和 bundle id `hk.hku.hkuimse.withyouapp`，接好签名后也可以在 Codemagic 打。

**iPhone 的推送现在收不到。** 原因有两处，都不在代码里：Firebase 还没有 Apple 推送（APNs）密钥；Xcode 工程没有开 Push Notifications 能力（没有 entitlements 文件）。装机不受影响，但每日提醒、每周问卷提醒、以后的 Brief PR 邀请在 iPhone 上一条都不会到。要在 PILOT 第 7 天（10/22）前补上：

1. Apple Developer → Certificates, Identifiers & Profiles → Keys → 新建一个 APNs key，下载 `.p8`，记下 Key ID 和 Team ID。
2. Firebase 控制台 → 项目设置 → Cloud Messaging → Apple 应用 → 上传这个 `.p8`。
3. Xcode 打开 `ios/Runner.xcworkspace` → Runner → Signing & Capabilities → `+ Capability` 加 **Push Notifications**，再加 **Background Modes** 勾 **Remote notifications**。Xcode 会生成 `Runner.entitlements` 并改 `Info.plist`，把这两个文件提交进仓库（开一个 PR）。
4. 重新打包、重新装（USB 再连一次或 TestFlight 更新）。

补上之前，iPhone 参与者的提醒只能靠人工（WhatsApp / 电话）。

其他 iOS 检查：登录是电邮加密码，和 Android 一样；App Check 在正式包用 DeviceCheck，服务器函数不强制校验（`enforceAppCheck: false`），不会拦住聊天；语音输入开关关着，不会要麦克风权限。

## 三、操作步骤

**先定今天用哪个顺序**（看第一节第 7 条）：

- **顺序 A（登记门关，默认）**：老人先做引导，研究员后登记。老人在登记前**不要聊天**（没有组别时聊天记录没有组别）。
- **顺序 B（登记门开 + `onboardingAfterEnrollmentFix` 开）**：研究员先登记，老人重开 App 后再做引导（T37）。

两种顺序的研究员登记一样：登记页输入 `PILOT-01` 这类编号后，情感分和 W0 日期两栏会**换成两个版本按钮**「A 組（Hybrid：規則 + AI）」「B 組（規則組）」；确认框里再选一次，两次一样才能「確認登記」（T21）。版本按 1014c：PILOT-01、02 选 A 組（Hybrid），PILOT-03 选 B 組（规则组）。编号跟人走，不跟到场顺序走；谁用哪个编号由 Junyu 在面访前定好。

### 顺序 A（登记门关）

| # | 谁 | 做什么 | 看到什么算做完 |
|---|---|---|---|
| 1 | 研究员 | 纸本同意、W0 问卷 | 完成 |
| 2 | 研究员 | 装 App（第二节） | 桌面有「陪住」 |
| 3 | 老人和研究员 | 打开 App，弹出通知权限时按「允許」 | 系统弹窗消失。按了拒绝就收不到任何提醒，要到手机设定里打开 |
| 4 | 研究员代按 | 「未有帳號？建立一個」→ 填称呼、紧急联络人称呼和电话 → 电邮、密码（至少 6 个字）→「建立帳號」。「UCLA 基線總分」留空 | 进到「開始之前」 |
| 5 | 老人 | 同意页「開始之前」→「繼續」 | T47 开关开着（10/16 修订）：先填一页「生命中重要嘅人」和「想重新聯絡嘅人」（可跳过），再进「介紹三個夥伴」；关着：进精简问卷（五题，一题一屏，先客观后主观） |
| 6 | 研究员 | **T47 修订（10/16）**：口头问老人甲部 14 题，照录入页 1 到 14 的顺序读（目标、幾時孤單、作息、心事、鍾意做乜／傾乜、人生階段、唔想提起、打字定講、幾時方便、以前做邊行、喺邊度長大、寵物、直接定溫和、研究员备注），全部可空、不限数，在研究员手机登记页最下面「入組資料」录入（可在第 8 步登记之后再录，录入前要先登记）。重要嘅人老人已在第 5 步自己填，这里不问。开关关着时改为老人自己在 App 答五题 | 「已錄入」 |
| 7 | 老人 | 「介紹三個夥伴」：小欣 → 揀阿珍或阿伯 → 通通的兴趣（可跳过）→ 使用建议（开关开时才有）→「完成」 | 进到主页「睇今日」。**先不要聊天** |
| 8 | 研究员 | 研究员手机「研究員登記」：老人的登入电邮、研究编号 `PILOT-0X`、版本按钮（T47 起**不用选配对**，确认框会显示老人第 7 步自己揀的那位；老人还没揀就显示「未揀」）→「檢查」→ 确认框再选一次版本 →「確認登記」 | 结果卡出现。**版本和组别只在研究员手机显示，不读出来、不写在纸上** |
| 9 | 研究员 | 老人完全关掉 App（最近使用列表滑走）再打开 | 重新进入主页 |
| 10 | 研究员和老人 | 按第四节带老人走一遍（约 10 分钟）。**先做签到和看页面，最后才试聊天** | 老人自己做完一次签到 |
| 11 | 研究员 | 「自己 → 顯示設定」调字体和高对比。T37 之后会保存，重开 App 不会跳回「標準」 | 老人看得清 |
| 12 | 研究员 | 付 HKD 50，约 W4 面访（第 28 天前后 3 天），写在卡上 | 老人拿到卡 |

**第 8 步之后**：Hybrid 组的服务器最多要 10 分钟认出组别。这段时间聊天可能只回一句备用话。所以第 10 步最后才试聊天。

### 顺序 B（登记门开）

1. 第 1–4 步同上。注册后老人看到的是**等待页**（S8：「你好！研究人員會幫你完成登記……」），没有按钮。
2. 研究员登记（同上第 8 步，配对选老人口头说的那位；之后引导里会预先选好，老人可以改）。
3. 老人完全关掉 App 再打开 → 同意页 → 入组问卷 → 「介紹三個夥伴」（配对那一屏已预选）→ 主页。
4. 然后同上第 10–12 步。

老人在引导里改选另一位，App 会记一条改动日志；分析以登记值为准（C19）。

## 四、讲给老人听的话（草稿，待产品窗口定稿；两组一样）

原则：(1) 两组讲一样的话，不提哪一组；(2) 不提“记忆”“AI 会记得你”“問下呢篇”“反思傾偈”，因为这些只有一组有；(3) 不提组别、不比较版本；(4) 危机支援一定要讲。

1. **开场**：「呢個 app 叫陪住，入面有三位朋友陪你傾偈。我而家同你一齊行一次，你有咩唔明隨時問我。」
2. **主页「睇今日」**：「每日打開，第一頁就係呢度。上面可以揀你今日嘅心情。下面有三位朋友，想搵邊位就㩒『傾偈』。」
3. **小欣（签到）**：「小欣日日陪你傾偈，聽你今日點。我哋而家一齊試一次。」（带老人做完一次签到）
4. **阿珍或阿伯（人生點滴）**：「你揀咗嘅阿珍（或者阿伯）會陪你講吓以前嘅事。一共 4 個主題，每個禮拜一個。得閒嘅時候慢慢講就得。」
5. **通通**：「通通會同你傾下你鍾意嘅嘢。」
6. **「做啲嘢」页**：「呢度有啲小練習同文章，得閒可以睇下。」
7. **危机支援（必讲）**：「如果覺得好唔開心、好難頂，㩒右下角紅色呢個掣，入面有可以即刻打嘅熱線。有即時危險就打 999。」（指给老人看红色按钮和主页底部的安全卡）
8. **使用建议**（意思同 ICF 方案一，用词照 S5）：「建議你每日都嚟傾下偈，例如食完早餐或者瞓覺之前。為咗研究準確，希望你每個禮拜最少用五次。唔係硬性規定，用多用少都唔會影響你參加研究或者收到嘅報酬。」
9. **问卷和提醒**：「手機會有提醒。有時 app 會請你答幾條簡單問題，傾完偈之後亦可能問你幾條，大概半分鐘。唔想答可以㩒跳過。」（iPhone 在推送补好之前要改口：「我哋會用 WhatsApp 提你。」）
10. **研究人员会看对话**（与 ICF 一致）：「研究團隊會睇你喺 app 入面嘅對話，用嚟檢查 app 有冇出錯同做分析，唔會俾其他人知道係你。」
11. **结束**：「之後如果 app 有咩問題，可以打卡上面嘅電話搵我。大概四個禮拜後，我哋會再見一次。」

## 五、App 现在的状态（main @ c1f88d6）

**已有并生效**：三位陪伴者（两组界面相同，回应方式不同）；规则组模板回应（带 `RULE_TEMPLATE_REPLIES` 的包）；安全检测和「即時支援」页（两组一致）；记忆 v1（Hybrid）；研究员登记含试跑版本指定（T21）；登记门（开关）；登记后引导修复（开关）；字体、高对比、安静时段**会保存**（T37）；「安靜時段」真的会压住夜间提醒（T44）；点赞点踩、第一周提示在 Phase B 包里隐藏（T45）；「語音讀出內容」已隐藏（T44）。

**已合并但开关关着（文字没定稿）**：会话定义和 Brief PR v2（T25，`sessionBriefPrV2Enabled`）；研究周和每周问卷 v2（T24，`weeklyScheduleV2Enabled`）；评估员视图（T30，`assessorViewEnabled`）；语音输入 v2（T27）；告警邮件新版（T34，`meta/alert_config`，可开）。

**开关关着时老人实际遇到的**：Brief PR 按旧规则弹出；每周问卷按日历周（星期日 20:00）推，不按研究周；每日心情提醒照旧。10/22（PILOT 第 7 天）前要定稿 T24 文字并打开 `weeklyScheduleV2Enabled`。

**没有**：W8 问卷（T35）、debrief（T42）、停服（T38）、运营看板（T39）、使用事件记录（T40）、每日汇总告警（T41）。

## 六、要 Junyu 定的事

1. 老人没有电邮怎么办：用老人自己的；或团队为每人开一个专用电邮，密码写在卡上。
2. 10/15 用顺序 A 还是 B（建议 A）。
3. 10/15 来的人用 PILOT-01 还是 02（版本都是 Hybrid），以及第一位改期后的编号安排。
4. iPhone 推送（第 2.3 节四步）谁来做、几号做完；补好之前用 WhatsApp 人工提醒。
5. iOS 以后更新走 TestFlight internal 还是再连线。
