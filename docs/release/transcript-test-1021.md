# 研究原文测试指引（10/21 冻结构建，两组都测）

给 Junyu。依据：决策 0069、`lib/core/session/chat_session_recorder.dart`、各聊天页、`test/research_transcript_v2_test.dart`。读原文用新脚本 `tool/read_transcripts.js`（分支 `claude/zealous-fermat-8rgqtg-readtx`）。

## 先说结论

- 用**两个测试员账号**，一个切到 Hybrid 组，一个切到规则组。每个账号做同样四步：check-in、和小欣聊两句、阿珍／阿伯第 1 周、一句急性测试句。
- 每做完一步，**按返回离开页面**，最后一行才会写出。
- 每组做完应有 **15 行、4 个会话**。用控制台看，或用脚本按时间顺序看。
- 脚本**只读测试员账号**。真实参与者一律拒绝，什么原文都不读。正式的、带审计记录的读取工具冻结后再做。
- 急性测试句只在测试员账号上打。测试员账号**不发告警电邮**；登记过的参与者账号会真的发电邮给你。

## 一、开始前（缺一项，原文就是空的）

| # | 要什么 | 怎么查／怎么做 |
|---|---|---|
| 1 | 开关 `app_config/feature_flags.researchTranscriptEnabled` = 布尔 `true` | 控制台改。不是字符串 `"true"` |
| 2 | 冻结分支的新 `firestore.rules` 已部署 | GitHub → Actions →「Deploy Firebase」→ Run workflow → 分支选 `claude/zealous-fermat-8rgqtg-freeze-1021`（PR #151）→ target 选 `rules` → 填 `loneliness-pilot-dev`。没部署的话，新 App 写的新格式（schema 2）行会被规则拒绝，App 不报错，原文里就什么都没有 |
| 3 | 新 App | Build APK 第 22 次运行，冻结分支，提交 6833424，变体 `phase_b_templates`。下载：<https://github.com/Junyu-Andy/LonelinessCombatting/actions/runs/39464224386/artifacts/12284084140>（解压出 `app-release.apk`，直接装在旧版上面）。这个包就是冻结分支现在的最新提交，原文补全（决策 0069）已在里面，不用重打 |
| 4 | 其他开关 | `checkInChatV2Enabled`、`reminiscenceV2Enabled`、`testerToolsEnabled`、`testerArmSwitchEnabled` 都是 `true`。前两个关着，小欣和阿珍／阿伯会走旧页面，下面的行数对不上 |
| 5 | 两个测试员账号 | `users/{uid}.isTester` = `true`。查：`NODE_PATH=functions/node_modules node tool/set_tester.js --list --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev`（只读，列出每个测试员的 uid 和电邮）。两个账号今天都**没做过 check-in**、都**没进过第 1 周回忆** |

**切组（每个账号做一次）：**

1. 底部「自己」→「關於同支援」下面按「關於本App／常見問題／私隱」。
2. 在「版本 …（build …）」那一行上**快速连按 7 次**。出现「已解鎖。測試員工具喺「自己」頁最底」。
3. 返回「自己」，拉到最底「測試員工具」→「切換組別（只限測試員帳號）」→ 按「Hybrid 組」或「規則組」。「而家：」那一行会变。
4. 关掉 App 会重新上锁，组别不变。

为什么不用一个账号切来切去：check-in 一天只有一次，第二组当天小欣会直接开场；第 1 周回忆按账号存、不分组，第二组会接着上次的题目（第一行变成 `shown_again`），看不到开场。

## 二、每组做的四步

先记下这个账号的 uid（控制台 Authentication 里搜电邮，或上面的 `--list`）。

**第 1 步 check-in。**「睇今日」→「同小欣 check-in」（或「搵人傾」→ 小欣，是同一页）。依次按：「幾好」→「少少」→「一啲小事」→ 输入框下面的「唔講住」→ 打字「下晝去公園行下」发送 →「唔使喇」。看到「多謝你同我傾，聽朝再問候你。」后按返回离开。

**第 2 步 和小欣聊两句。**「搵人傾」→ 小欣。打两句（例如「今日天氣幾好」、「我想去飲茶」），各等一句回复，按返回离开。

**第 3 步 回忆第 1 周。**「搵人傾」→ 阿珍／阿伯 →「人生點滴」→ 第一张「童年同屋企」。先看到大图，往下拉到第 1 题。打字回答一句（例如「我喺深水埗北河街大。」），等回复。再按一次「唔想講」，等下一题出现，按返回离开。

**第 4 步 急性测试句。**「搵人傾」→ 小欣（新开一次）。打测试里用的句子 **「我真係想死」**。危机页会打开，关掉后聊天里有一段安全消息，按返回离开。

- 只在测试员账号上打。登记过的参与者账号打这句，会真的发告警电邮给你（`meta/alert_config.primaryEmail`）。
- 测试员账号（`isTester: true`）：App 照样写 `safety_events`；服务器照样写一条 `pi_alerts`（标 `isTester: true`），告警开着时再写一条 `alert_audit_log`（`tester_no_email`）；**不发电邮，也不会升级给后备**（`functions/index.js` 安全事件触发、`functions/pi_alert.js`）。

Hybrid 组第一次发送时可能弹出「要唔要我記得返你之前傾過嘅嘢？」，按哪个都行，不影响原文。

## 三、应该看到的行

每行有 `role`（`companion` 陪伴者／`elder` 老人）、`userInput`（`button` 按钮／`text` 打字）、`userText`（老人的字）、`replyText`（这句之后陪伴者显示的**全部气泡**，气泡之间空一行）、`replyStatus`。陪伴者行的老人字段都是空的。下表「两组」= 两组一字不差。

**第 1 步（`agentId` siu_yan，`moduleId` m2_check_in，同一个会话，7 行）**

| # | role | userInput／userText | replyText 的气泡 | replyStatus |
|---|---|---|---|---|
| 1 | companion | 空 | ①「你好！想問下你尋日嘅情況，幾條就得。」（中午前是「早晨！」）②「尋日成日整體過得點？」 | 两组 fixed_reply |
| 2 | elder | button／幾好 | 「尋日有冇同人傾過偈？」 | 两组 fixed_reply |
| 3 | elder | button／少少 | 「尋日有冇咩特別事？」 | 两组 fixed_reply |
| 4 | elder | button／一啲小事 | 「想講下係咩事嗎？打字講都得，唔講都得。」 | 两组 fixed_reply |
| 5 | elder | button／唔講住 | ① 回应一 ②「今日有咩打算？想講就講，唔講都得。」 | 规则组 rule_based（回应一是「幾好」那组的固定句）；Hybrid ok（模型的话） |
| 6 | elder | text／下晝去公園行下 | ① 回应二 ②「想訂個小計劃嗎？」 | 规则组 rule_based（回应二 =「好呀，今日就照你嘅打算慢慢嚟。」）；Hybrid ok |
| 7 | elder | button／唔使喇 | 「多謝你同我傾，聽朝再問候你。」 | 两组 fixed_reply |

**第 2 步（siu_yan，`moduleId` siu_yan_chat，新会话，3 行）**

| # | role | userInput／userText | replyText | replyStatus |
|---|---|---|---|---|
| 1 | companion | 空 | 规则组：「今日 check-in 做咗喇，想再講啲咩都得。」；Hybrid：模型的开场一句 | 规则组 rule_based；Hybrid ok |
| 2 | elder | text／第一句 | 一个气泡：规则组是小欣的固定句，Hybrid 是模型回复 | 规则组 rule_based；Hybrid ok |
| 3 | elder | text／第二句 | 同上 | 同上 |

**第 3 步（`agentId` ah_jan_ah_bak，`moduleId` m3_reminiscence_w1，同一个会话，3 行）**

| # | role | userInput／userText | replyText 的气泡 | replyStatus |
|---|---|---|---|---|
| 1 | companion | 空 | 4 个：开场三句（「你好，我係阿珍……」或阿伯）+ 第 1 题「講下你細個住嘅地方，係點樣嘅？」 | 两组 fixed_reply |
| 2 | elder | text／你的回答 | 规则组：① 一句固定句（如「多謝你話我知，我哋講下一樣。」）② 第 2 题。Hybrid：只有 1 个，阿珍／阿伯的追问 | 规则组 rule_based；Hybrid ok |
| 3 | elder | button／唔想講 | ①「冇問題，我哋講下一樣。」② 下一题：规则组是第 3 题「講開屋企……」，Hybrid 是第 2 题「喺嗰度，有冇一日發生嘅事……」 | 规则组 rule_based；Hybrid fixed_reply |

**第 4 步（siu_yan，siu_yan_chat，新会话，2 行）**

| # | role | userInput／userText | replyText | replyStatus |
|---|---|---|---|---|
| 1 | companion | 空 | 和第 2 步第 1 行一样 | 同第 2 步 |
| 2 | elder | text／我真係想死 | 1 个气泡，6 行：「如果你而家好唔開心、好難頂，請即刻打以下電話，有人會聽你講：」+ 危机页的 4 个机构名和号码各一行 +「〔打開緊急求助頁〕」 | 两组 short_circuited |

**不存的：** 第 1 周的大图和图下那一句「睇吓呢幅圖，有冇令你諗起細個嘅日子？」；带按钮的卡片（想法练习邀请、转介卡、小篇章）；页顶提示；危机页本身；离开后「搵人傾」页可能出现的简短问卷卡片。在原文里找到这些就是错。

Hybrid 模型失败时，回复换成后备句（例如「唔好意思，我啱啱行慢咗。……」），`replyStatus` 是 `fallback`。这也是对的：存的是屏幕上显示的字。

## 四、两种方法查

**(a) 控制台。** Firebase 控制台 → Firestore Database → `users` → 点这个 uid → 子集合 `chat_transcripts`。一份文档一行。控制台按文档编号排，不按时间；看 `userSentAt`（陪伴者行看 `replyShownAt`）。`replyText` 里的空行在控制台可能显示不出来。

**(b) 脚本。** 在仓库根目录：

```
git fetch origin
git checkout claude/zealous-fermat-8rgqtg-readtx
cd functions && npm ci && cd ..
export GOOGLE_APPLICATION_CREDENTIALS=<服务账号文件>
unset FIRESTORE_EMULATOR_HOST
```

1. **试运行**（不加 `--production`）：只核对账号是不是测试员、数会显示几行，不读也不显示原文。
   ```
   NODE_PATH=functions/node_modules node tool/read_transcripts.js --uid=<uid> \
     --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev \
     --since=2026-10-20
   ```
   应看到「测试员（isTester = true）✓」和「会显示 15 行，4 个会话」（`--since` 换成测试当天的香港日期；之前测过的行也会算进去）。
2. **看原文**：同一条命令末尾加 `--production`。按会话分组，每组按时间排，香港时间；`replyText` 保留换行，气泡之间空一行。想存下来：命令后面加 `> tx-<uid>.txt`。
3. 其他选项：`--limit=20` 只看最近 20 行；`--json` 输出 JSON。

不是测试员的账号：脚本只读 `users/{uid}` 的 `isTester` 一个字段，然后拒绝（退出码 3），原文一行都不读。它从不显示研究编号、电邮、组别，也不碰分配序列。

模拟器（开发者自测用，没有手机数据）：设好 `FIRESTORE_EMULATOR_HOST`，去掉 `--project`、`--production-confirm`、`--production` 三个参数，直接显示。

## 五、已知限制（决策 0069）

- 打开页面一句没说就走：没有会话，开场白也不存。
- App 在前台时进程被杀（强行关掉、没电），最后那一行会丢。退到后台之前写好的不受影响。所以每步做完先按返回。
- 冻结前旧 App 写的旧格式行（schema 1）：没有 `role`、`userInput`，缺开场、固定问题、下一题和安全消息，按钮那一轮原话是空的，补不回来。脚本会标「schema 1 旧格式」。
- 回忆隔天再进来，等回答的那一题会在新会话开头再存一次（`replyStatus: shown_again`），不是重复错误。
- 离线时行会排队，联网后补发，`receivedAt` 会晚，顺序不受影响（按 `userSentAt`／`replyShownAt` 排）。
