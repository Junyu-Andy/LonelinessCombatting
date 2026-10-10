# 内部实机测试（第一轮，当前 main）

日期：2026-10-10。放在仓库 `docs/release/internal-test-1010.md`。依据：研究侧 10/10 第 5 条 (2)。

只给 Junyu 和实验室同事用，不找老人，不需要伦理批准。只测 Android。测完的数据都是测试员数据，以后按 10/9 第 18 条 (7) 清掉，不分析。

## 结论

1. 打两个包：`phase_b`（测 Hybrid 组和规则组）和 `phase_a`（测 ADA）。
2. 每人在控制台把自己的测试账号改成指定组别，不用登记入口，不碰分组开关和分配序列。
3. **规则组模板这一轮测不到**：41 条模板还没写进代码（任务 T33），现在规则组小欣签到后只回一句固定的“收到喇。聽日再見。”，阿珍回忆后没有回应。T33 合并后打第二轮包再测。
4. 这一轮测的是现有功能。会话定义、Brief PR 新邀请规则、每周问卷新排程、记忆分层、语音都还没做，看到的是旧做法，不用报这些地方的问题。

## 一、打包（GitHub Actions）

1. 打开仓库页面 → **Actions** → 左边选 **Build APK** → 右边 **Run workflow**。
2. 分支选 `main`，variant 选 `phase_b`，按 Run。约 10–15 分钟。
3. 同样再跑一次，variant 选 `phase_a`。
4. 每次运行结束后，在页面底部 **Artifacts** 下载 zip，解压得到 `app-release.apk`。文件名里有 `phase_b` 或 `phase_a`，别弄混。
5. 传到 Android 手机（WhatsApp 发给自己、Google Drive 或 USB 都可以），点开安装，按提示允许“安装未知来源的应用”。
6. 一部手机只装一个包。两个包的应用名相同，后装的会覆盖先装的。

**测试工具**：如果仓库 Secrets 里有 `TESTER_PIN`，包里能解锁测试工具（日程模拟、测试推送）：在「關於」页连点版本号 7 次，输入这个密码。打包前在 Settings → Secrets and variables → Actions 看一下有没有这个名字；没有的话，这一轮不用测试工具也能测，只是看不到日程模拟。

## 二、Firestore 配置（Junyu 在控制台做一次）

| 文档 | 字段 | 设成 | 为什么 |
| --- | --- | --- | --- |
| `meta/memory_config` | `enabled`、`policy`、`phaseBArmA` | 已是 `true`、`"C"`、`true`，不用改 | Hybrid 组的服务器记忆（v1） |
| `meta/randomization_config` | `enabled` | **保持 `false` 或不建** | 不测分组；打开会让新账号分不到组 |
| `app_config/phase_b` | `djgW2InAppEnabled` | `true` | 测新版 W2 DJG（6 题，问卷包原文） |
| `app_config/phaseA_schedule` | `adaEnabled`、`day7OpenEndedEnabled` | 都设 `true` | 测 ADA 和第 7 日流程 |
| `app_config/phaseA_schedule` | `adaHelpPhone` | 填 Junyu 的手机号 | 测“唔識填？打俾研究員”按钮 |

这几个开关现在打开没有风险：没有老人在用。测完在 `docs/STUDY_CHANGELOG.md` 记一行“10/10 内部测试打开、某日关闭”，正式上线前按上线清单重设。

## 三、测试账号

每人用一个没注册过的邮箱在 App 里注册（Gmail 可以用加号别名，例如名字后加 `+hybrid`）。注册后 Junyu 在 Firestore 控制台打开 `users/{这个账号的 uid}`，按下表改字段。改完让测试的人**完全关掉 App 再打开**（App 只在启动时读这些字段）。

| 账号 | 用哪个包 | 字段 |
| --- | --- | --- |
| B-Hybrid（每人可各开一个） | `phase_b` | `arm: "A"`、`armAssignmentMode: "randomise"`、`isTester: true`、`w0Date: "YYYY-MM-DD"`、`ahJanAhBakVariant: "feminine"` 或 `"masculine"` |
| B-规则组 | `phase_b` | `arm: "B"`、`armAssignmentMode: "randomise"`、`isTester: true`、`w0Date: "YYYY-MM-DD"`、`ahJanAhBakVariant` 同上 |
| A | `phase_a` | 注册后自动是 `arm: "A"`；加 `isTester: true`。要测第 7 日，把 `createdAt` 改成 6 天前 |

- `w0Date` 填 13 天前的日期，就能在第 14 天的窗口里看到 W2 DJG（App 把 W0 当天算第 1 天）。只测聊天的账号填今天。
- `armAssignmentMode: "randomise"` 不能漏：服务器靠它判断“Phase B 的 Hybrid 组”，漏了就没有服务器记忆。
- `isTester: true` 的账号**收不到推送**（W2 DJG、ADA 第 7 日），安全告警也**不发邮件**，只记录。这一轮看首页卡片和 Firestore 记录即可。要测推送和告警邮件，另开一个不加 `isTester` 的账号，测完用整人删除脚本删掉。
- 控制台改字段时注意类型：`arm`、`w0Date` 是字符串，`isTester` 是布尔值。

## 四、测什么、看哪里

每项测完在表里写：谁测的、哪天、手机型号、结果、截图。问题发到同一个地方（例如一个 WhatsApp 群或一份共享表），注明账号和大概时间，方便查日志。

| # | 测什么 | 怎么测 | 看哪里算通过 |
| --- | --- | --- | --- |
| 1 | 安装和注册 | 装包、注册、走完引导 | 不闪退；引导大约多长时间（记下来，试跑要用） |
| 2 | Hybrid 聊天 | B-Hybrid 账号和小欣、阿珍或阿伯、通通各聊 5 句以上 | 回复正常；`llm_calls` 里有这几次调用，`model_returned` 有值、`error` 是 false |
| 3 | 规则组不调 LLM | B-规则组账号做签到、回忆、和通通聊 | `llm_calls` 里没有这个 uid；签到后看到“收到喇。聽日再見。” |
| 4 | 服务器记忆 | B-Hybrid 账号告诉小欣家人名字、兴趣；离开聊天页；等 30 分钟 | `users/{uid}/mem_facts` 有新条目；下次和小欣聊，小欣会用到 |
| 5 | “唔好記住” | 聊天里说“呢段唔好記住”，再讲一件事 | 这次会话之后 `mem_facts` 没有新条目 |
| 6 | 删一条记忆 | 设置 →「我記得嘅嘢」删一条 | 下次聊天不再提起 |
| 7 | 安全流程 | 两组账号各打一句合成测试句（`docs/dev-reports/T6-safety-parity-20261006-scripts/` 里的句子） | 出现危机页；`safety_events` 有一条；两组流程一样 |
| 8 | AI 不写热线号码 | B-Hybrid 账号问“有冇熱線可以打” | 回复里没有电话号码，有危机页入口 |
| 9 | W2 DJG | B-Hybrid、B-规则组账号（`w0Date` 13 天前）打开首页 | 首页有“第 2 週問卷”卡；6 题是问卷包原文；提交后 `djg_responses/W2` 有分数（服务器算） |
| 10 | 每周问卷（Weekly PR、PGIC） | 星期日 20:00 到星期二之间打开 App | 首页出每周问卷；`weekly_pr`、`pgic` 有记录 |
| 11 | Brief PR（旧规则） | 聊天 2 轮以上后离开 | 弹出 4 题；`brief_pr` 有记录 |
| 12 | ADA 第 1 次到访 | A 账号（新注册当天）打开首页 | 有 ADA 短版（B + D），一屏一项，可跳过，最后选提醒时间 |
| 13 | ADA 第 7 日 | A 账号（`createdAt` 改成 6 天前） | 首页有“第 7 日問卷”卡；ADA 全版加开放题；中途退出再进入能接着做 |
| 14 | 求助按钮 | ADA 任一屏按“唔識填？打俾研究員” | 拨出 `adaHelpPhone` 的号码 |
| 15 | 盲法和后台 | 用 `unblinded` 账号登录 | 能进研究员页面；Phase A 的 ADA 完成情况能看到 |

## 五、这一轮不测的

- 规则组模板（等 T33）。
- 新的会话定义、收尾按钮、列表页评价卡、Brief PR 五种状态（等 T25）。
- 研究周、第 7、14、21、28 天的每周问卷、社会接触探针（等 T24）。
- 记忆分层（等 T31）。
- 语音输入（STT 未获批，开关关着；改走服务器转写要等 T27）。
- 登记入口、等待页、研究期前缀（等 T21）。
- iOS。

## 六、测完以后

1. 把第二节打开的开关关回去（或在上线清单里注明要重设），在 `docs/STUDY_CHANGELOG.md` 记一行。
2. 问题清单发回开发窗口，按问题开任务。
3. 测试账号保留到第二轮；正式上线前按 10/9 第 18 条 (7) 统一清掉（T32 的清理脚本）。
