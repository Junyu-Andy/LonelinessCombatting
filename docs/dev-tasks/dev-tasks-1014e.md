# dev-tasks-1014e：10/14 第 11 条和 10/15 第 1 条带来的开关、配置和小改动（接 1014c、1014d；10/15 早上修订）

来源：claude/decisions-log.md 10/14 第 11 条、10/15 第 1–4 条。10/15 上午第二次修订：读过 main `6c55601`（#78 T43、#79 T46、#80 T40 已合）和 docs/dev-reports/answers-1014c-20261015.md。接在 dev-tasks-1014c.md、1014d.md 之后（仓库已编号 T38–T46，PR #75）。产品窗口 10/15 早上读过 main `b0d2700`、`docs/dev-reports/handoff-20261014.md`、`docs/release/w0-install-script.md` 后修订。放进仓库 docs/dev-tasks/。本文件分“已定，直接做”和“待 Junyu 定，先不动”两部分，不要混。

共同规则：(1) 不推 main，只开 PR 草稿；(2) 不碰生产数据，只用 emulator 和合成数据；(3) 新行为放在开关后；(4) 老人看得到的文字只写草稿；(5) 不改热线号码。

## 1. 今晚到 10/15 早上要做的（不是开发，是配置和部署）

1. 打包按 `docs/release/w0-install-script.md` 第二节：Android 用 GitHub Actions `phase_b_templates`，从 main 打。编译参数必须带 `PHASE_B=true` 和 `RULE_TEMPLATE_REPLIES=true`。iOS 暂停（10/15 第 2 条 (7)）。
2. 部署一次 Firebase（规则加 Functions）。
3. 开关：`onboardingAfterEnrollmentFix = true`；`enrollmentGateEnabled = false`（10/19 第一位 PB 登记前再开，开前团队和评估员账号设 `isTester: true`）；`voiceInputEnabled = true`，但开之前开发窗口先答：开着时老人会不会看到任何【占位】文字（T27 的 S6 失败状态）。`sessionBriefPrV2Enabled` 10/15 **先关**：问卷按钮仍是【占位】，T46 未合并（产品窗口 10/15 更正，见第 4 节第 3 条）；文字定稿且 T46 合并后、10/19 冻结前打开。
4. `PI_EMAIL` 密钥设为 Junyu 的地址，保留。
5. 建 `meta/alert_config`：`enabled: true`、`primaryEmail` 为 Junyu、不设 `backupEmail`、`escalateAfterHours` 留默认。不设后备是 Junyu 10/14 第 11 条 (7) 定的。注意 #73 把“首发失败即转后备”也合进了 main：没有后备时首发失败就没有第二条路，开发窗口请确认失败会写进 `alert_audit_log` 并在后台告警列表标出。建好后用 `isTester: true` 的测试账号触发一次急性级事件，Junyu 收到邮件后才算配置完成。说明：现在 `meta` 里没有这份文档是正常的，T34 要手工建；文档不存在时代码按 enabled 为假走 T19 老路，急性级只发到 `PI_EMAIL`。
6. 1014c 第 1 节第 1、2 题（PILOT 账号发不发告警；T21 版本选择的操作步骤）仍要在 10/15 早上前答。

## 2. 已定，直接做（PR 草稿，排在 T24 之后，10/19 前）

1. **每周有效会话按 `endedAt` 归周**（第 11 条 (4)）。`usage_weekly` 现在按 `startedAt`，改为 `endedAt`，与 `isValid` 同一时刻写。登记表有效会话条目补一句。
2. **Brief PR 七档只显示数字**（第 11 条 (5)）。维持现做法，不开新任务；T25 报告第 10 节对应行标“已定 A”。
3. **`isTester` 只允许管理员写**（第 11 条 (6)，backlog 96）。`firestore.rules` 改为客户端不能写 `users/{uid}.isTester`；设置改走 Admin SDK 脚本或控制台。随规则一起在 10/19 开门前部署。验收：emulator 里参与者账号写 `isTester` 被拒；管理员脚本能写。
4. **取消告警后备**（第 11 条 (7)）。新写决策记录，标 0038 的“12 小时转后备”一条 Superseded；`escalateAlerts` 在 `backupEmail` 为空时什么都不做（代码已允许为空，核对一次并补测试）。不删代码，以后要恢复只需填 `backupEmail`。
5. **DeepSeek 前的个人信息遮蔽**（10/15 第 1 条 (3)）。代码 `stripPII` 已在出站前遮蔽电话、电邮、身份证号样式和西式楼层单位；不去姓名、中文地址、银行账号（`docs/privacy/strip_pii.md`）。不改代码。B08、B23 的 ICF 一句已按此改。开发窗口核对 `docs/dev/architecture.md` 和 DMP 段落与 strip_pii.md 一致即可。
6. **教育库热线文字有错**（N7，SPEC:C 安全文字条目）。`lib/features/education/data/education_library.dart` 第 418、419、533、534 行写的是「撒瑪利亞防止自殺會熱線 2382 0000」。2382 0000 是生命熱線（Suicide Prevention Services）的号码；香港撒瑪利亞防止自殺會是 2389 2222。两处都不对应。改法只写草稿：机构名改为「生命熱線」，号码不动；英文同理改为 "Suicide Prevention Services (生命熱線) 2382 0000"。热线号码本身不改（共同规则 5），只改机构名。另外 `functions/prompts/crisis_resources.json` 的 `verifiedDate` 等 Junyu 核对后填日期，产品窗口已把四个号码对过 HKU CSRP 名单（见 1014e 对话记录），Junyu 仍要自己确认一次。

7. **Hybrid 回忆按条数算有效**（10/15 第 2 条 (1)）。`hybridReminiscenceValidRequiresSave` 默认改为 false；登记表有效会话定义和 T25 报告 2.2 表改为“Hybrid 回忆：≥3 条老人消息且都有回复”；S9 行为不变。10/19 前。
8. **S10b 一律「頭先」**（10/15 第 2 条 (2)）。`BriefPrScheduler.timePhrase` 返回固定「頭先」，S10b 文案变为「你頭先同{陪伴者}傾過偈，想問返你嗰次嘅感覺，大概半分鐘。」；删占位分支；`docs/spec/copy/` 同步。问卷按钮定稿「下一題」「上一題」「唔評住」，首次说明沿用 T25 草稿。T46 合并后一起进 10/19 构建，然后开 `sessionBriefPrV2Enabled`。
9. **删注册页 UCLA 输入框**（N6，10/15 第 2 条 (5)）。`login_page.dart` 去掉「UCLA 基線總分（20–80）」字段和说明文字；`baselineUclaScore` 字段保留在模型里不再写入；登记表注明 Phase B 注册页不收任何量表。10/19 前。
10. **主热线 18111**（10/15 第 2 条 (4)）。参与者材料由产品窗口改；App 侧不改号码，只做第 6 条的机构名更正和 `verifiedDate`。

11. **研究员仪表板入口**（10/15 第 3 条 (1)，Junyu 同意）。登记页右上角加入口进「研究員儀錶板」，只对 `unblinded`；`blinded` 看不到。小 PR，10/19 前。T43 报告里“確認處理”这一步随之可做。
12. **W4 名单含 PILOT**（T43 报告第 5a 步发现）。`functions/assessor.js` `phaseBParticipants` 只取 `studyPeriod == "B"`，三位 PILOT 不在评估员的 W4 名单上。1014c 第 0 节第 1 条已定 PILOT 的 W4 由 Keran 做，所以名单要含 `studyPeriod == "PILOT"`，名单行照旧不带组别。开发窗口编号，11/9（PILOT 第 25 天）前合并；T43 测试第 5a 步的断言反过来。
13. **T40 补传阈值**（答复第 7 题）。`uploadedLate` 用“服务器时间减客户端时间 > 5 分钟”判定。这是实现细节，产品窗口给默认值，Junyu 有异议再改。
14. **iPhone 提醒**（10/15 第 3 条 (2)）。三位 PILOT 老人用 iPhone，Apple 开发者协议未过，没有 APNs，服务器推送一条都到不了。iOS 装机和提醒替代方案由 10/15 下午的 iOS 窗口给出（claude/ios-window-prompt-1015.md）；可能产生一个新任务（本机通知作 iPhone 替代通道），等 Junyu 定后再编号。在此之前 T24 的推送对 iPhone 按“人工 WhatsApp”处理，看板上标出。

15. **T39 放 App 内研究员后台**（10/15 第 4 条 (1)）。沿用现有 `unblinded` 角色检查；网页版以后要再说。T39 可以开。
16. **`MEMORY_V1` 测试包的记忆总开关留着不动**（10/15 第 4 条 (2)）。Phase A 瘦身批次时一起处理。
17. **iPhone 本机通知评估**（10/15 第 4 条 (3)，先答后做）。开发窗口答：(1) 加 flutter_local_notifications 给 iOS 排本机提醒要改哪些文件、多少工时；(2) 按研究日排 56 条每日提醒加 8 条每周问卷提醒是否超过 iOS 待发上限（约 64 条 [待核]），要不要每次打开 App 时重排；(3) 现有每日心情和每周问卷的推送文字能否直接复用。10/22 前能进构建就做，进不了就对 iPhone 用 WhatsApp 人工提醒。本机通知不走 APNs，不受开发者协议影响。Junyu 看完答复再定做不做。

## 3. 要先答的问题（按现在的代码答，写进 docs/dev-reports/）

1. **iOS**：暂停（10/15 第 2 条 (7)），Apple 开发者协议卡住，试跑只在安卓跑。协议解决后再按 w0-install-script 2.3 节处理。
2. **注册页的 UCLA 输入框**。`login_page.dart` 注册时有一个可选的「UCLA 基線總分（20–80）」输入框，存到 `users/{uid}.baselineUclaScore`，说明文字写“用嚟做分層分組”。现在分层由 `enrollParticipant` 按研究员录入的 DJG-ES 情感分做，和这个字段无关；研究用的是 UCLA-3（3 题，总分 3–9），没有 20 题版。请答：这个字段还有没有任何读取方；注册页还有哪些字段（姓名、年龄、紧急联系人等）是老人自己填的。产品窗口建议删掉输入框（N6），等 Junyu 定。
3. **Hybrid 回忆有效口径**。见第 4 节第 1 条，先不改。
4. **Android 正式签名**（10/15 第 1 条 (4)）：这是一个小开发任务，不是纯配置。`android/app/build.gradle.kts` 第 38–40 行仍用 debug 签名；要加 release `signingConfig` 读 `key.properties`，GitHub Actions 的 Build APK 工作流加 keystore 和口令的 secrets，步骤见 `docs/dev-reports/T36-apk-phase-b-templates-20261014.md` 第三节。开发窗口编号（接 T46 之后），10/19 第一位 PB 装机前合并；换了密钥后研究期间不再换。10/15 的三位 PILOT 都是 iPhone，不受影响。

## 4. 待 Junyu 定，先不动

1. 已定，见第 2 节第 7 条。
2. 已定，见第 2 节第 8 条。
3. 已定（10/15 第 2 条 (3)）：T46 按本机存储；文字见第 2 节第 8 条。
4. 已定，见第 2 节第 9 条。
5. 已定，见第 2 节第 10 条。
6. **`purge_tester_data`**（backlog 102）。建议 10/19 前只跑列出模式（不加 `--confirm`），把清单给 Junyu 过目，再定删哪些。脚本本来就不碰已登记的 phase_b / pilot 账号和研究员账号。
7. **1014d 文件**：Junyu 10/14 自己把 1014c、1014d 放进仓库（PR #75，T38–T46），产品窗口 10/15 记为采纳（10/15 第 1 条 (1)）。1014d 的回访规则（3–5 天 WhatsApp、6 天电话、只算第 1–28 天）和 T40 由此成为已定。
8. 已定，见第 2 节第 11 条。
9. 已定，见第 2 节第 15 条。
10. 已定，见第 2 节第 16 条。

## 5. 排期

| 什么时候前 | 要有 |
|---|---|
| 10/15 早上 | 第 1 节全部（只安卓）；T43 按 claude/试跑前测试流程-1015.md A 部分跑 |
| 10/19 | 第 2 节第 1、3、4、6、7、8、9、11 条和 Android 正式签名随 10/19 构建和部署进；第 8 条（S10b「頭先」和按钮文字）合并后开 `sessionBriefPrV2Enabled`（T46 已合） |
| 11/9 | 第 2 节第 12 条 W4 名单含 PILOT |
| 不卡上线 | 第 2 节第 2、5 条 |

## 6. 要 Junyu 定的事

第 4 节第 6 条（purge 清单）；第 2 节第 17 条答复后定本机通知做不做。开发窗口遇到其他要定的事，照旧列在对话结尾，不替 Junyu 定。
