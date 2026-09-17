# Phase A 基线版 — Mac 逐步部署与测试准备（含云端配置）

分支：`claude/youthful-heisenberg-dtl2cc`　Firebase 项目：`loneliness-pilot-dev`（`.firebaserc`）
预计耗时：首次 60–90 分钟（含工具安装），之后每次重新部署 10 分钟。

每一步都写了「怎么确认成功」。任何一步红字先停下，不要往后跑。

---

## 0. 本机前置（一次性）

```bash
# 0.1 Flutter（要求 Dart ≥ 3.9，即 Flutter ≥ 3.35；仓库在 3.47.4 上通过分析与测试）
flutter --version
flutter doctor            # Xcode / CocoaPods 必须是绿的，Android toolchain 可选

# 0.2 Node 24（functions/package.json 的 engines 要求；Firebase CLI 本身用 Node 20+ 即可）
brew install nvm          # 已有则跳过
nvm install 24 && nvm use 24
node --version            # v24.x

# 0.3 Firebase CLI + 登录
npm install -g firebase-tools
firebase login
firebase projects:list    # 能看到 loneliness-pilot-dev

# 0.4 拉代码
cd ~/path/to/LonelinessCombatting
git fetch origin
git checkout claude/youthful-heisenberg-dtl2cc
git pull
git log --oneline -1      # 应看到 "Phase A baseline follow-ups" 或更新的 commit
```

## 1. 本机门禁（Gate 1，约 2 分钟）

```bash
flutter pub get
flutter analyze           # 必须 0 error（info/warning 是基线遗留，可忽略）
flutter test              # 必须 All tests passed（152 条）
cd functions && npm ci && node --check index.js && node test/llm_flags_test.js && cd ..
```

确认：`flutter test` 末行 `All tests passed!`；`llm_flags_test.js` 末行 `All 11 fixtures passed.`

`flutter pub get` 会改写 `analysis_options.yaml` 和 `pubspec.lock`，这是 Flutter 工具的行为，**不要提交这两个文件**（`git checkout analysis_options.yaml pubspec.lock`）。

## 2. 云端：Secrets 核对（不新增，只确认在）

本版没有新增 secret。新函数 `week2Push` 只用 Admin SDK。

```bash
firebase functions:secrets:access DEEPSEEK_API_KEY   # 打印出值即存在
firebase functions:secrets:access SEARCH_API_KEY     # 可无（搜索已停用）
# SMTP_HOST / SMTP_USER / SMTP_PASS / PI_EMAIL：acute 邮件通知用；没配也能跑，只是不发邮件
```

缺 `DEEPSEEK_API_KEY` 的话：`firebase functions:secrets:set DEEPSEEK_API_KEY`（交互式粘贴）。

## 3. 云端：部署规则与函数

```bash
firebase deploy --only firestore:rules,functions
```

要看到的输出：

- `firestore: released rules firestore.rules to cloud.firestore`
- 函数列表里 **`week2Push(asia-east2)`** 是 `Successful create operation`，`proxyDeepSeek` / `referralJudgement` / `safetyAcknowledgement` 是 `Successful update operation`。
- 若报 `Cloud Scheduler API has not been used`：在 GCP 控制台启用 Cloud Scheduler API 后重跑（项目已有三个 onSchedule 函数在跑，一般已启用）。
- 若 Node 版本报错：确认 `nvm use 24` 生效后重跑。

本版规则变更：`safety_events.level` 允许新值、新增 `app_config/{doc}` 只读。**不部署规则，客户端读 `app_config/phase_a` 会被拒绝**（只是回默认值，不会崩，但你后面第 4 步的测试参数就不生效）。

部署后验证一次 LLM 通路（可选但推荐）：

```bash
firebase functions:log --only proxyDeepSeek -n 5
```

## 4. 云端：Firestore 测试参数（强烈建议，让时间相关流程当天就能测）

Firebase Console → Firestore → 新建集合 `app_config` → 文档 ID `phase_a`，字段：

| 字段 | 测试值 | 正式值（不建文档即默认） | 作用 |
|---|---|---|---|
| `sessionIdleTimeoutMin` | `1`（number） | 10 | 1 分钟不说话就结束 session，测 timeout + Brief PR |
| `briefPRMinTurns` | `2` | 2 | T-13 / T-14 |
| `briefPRItemCount` | `4` | 4 | 改成 3 看第四题消失 |
| `w2DayOffset` | `0` | 14 | 新账号当天就出「第 2 週問卷」，测 T-16 的 app 内路径 |
| `w2WindowDays` | `3` | 3 | |
| `week1NudgeDays` | `[1]`（array of number） | [3, 6] | 入组当天出「你仲未同 X 傾過」 |
| `weeklyPrPushHour` | `20` | 20 | 配合改系统时间测 T-15 |

app 每次冷启动读一次；改完杀掉 app 重开。**测完把这个文档删掉或改回正式值**，否则参与者 1 会用到测试参数。

## 5. 云端：测试账号标记

对每个测试账号，在 `users/{uid}` 上设 `isTester: true`（app 内「設定 → 測試工具」有开关，或在 Console 手动加）。作用：T-1～T-3 的 acute 事件仍会写 `safety_events` 和 `pi_alerts`，但**不会给 PI 发邮件**。

## 6. 客户端：装到 iPad / 安卓

```bash
flutter clean && flutter pub get      # 本版新增了 asset 路径，clean 一次最稳
flutter devices
flutter run -d <设备id>               # 正常 build
```

签名 / bundle id 三方一致的检查沿用 `TESTING_WORKFLOW.md` 阶段 0。

**T-11 专用 build**（LLM 强制失败，用完切回正常 build）：

```bash
flutter run -d <设备id> --dart-define=FORCE_LLM_FALLBACK=true
```

装好后先做两件事：

1. 設定 → 關於同支援：看到「版本 1.0.0（build 3）」「詞表 v5-2026-09」「Prompt bundle 前 8 位」。前 8 位要等于 `docs/release/phase_a_baseline_versions.md` 里 promptBundleHash 的前 8 位（T-18）。
2. 任一 agent 发一句「今日去咗飲茶」→ 有回复 → Firestore `users/{uid}/turns` 出现一条文档，`llm.status = ok`、`llm.model` 有值、`detector.tier = none`。这一步通了，L-1 链路就通了。

## 7. 推送（FCM）

- 周日 20:00 / 周一至周六 19:00 的 doorbell 是既有的 topic 广播，不用改。
- `week2Push` 每天 10:00 HKT 扫描，按设备 token 推（`users/{uid}/fcm_tokens`）。**iOS 的 APNs 仍未配置（既有限制）**，所以 W2 推送只能在安卓上收到；iOS 靠打开 app 看首页横幅即可覆盖 T-16 的 app 内部分。
- 想立刻验证函数本身而不等 10:00：GCP Console → Cloud Scheduler → 找 `firebase-schedule-week2Push-asia-east2` → **Force run**。前提是第 4 步把 `w2DayOffset` 设成 0 且该账号今天注册、`isTester` 不为 true（函数跳过 tester）。看 `users/{uid}/events` 里出现 `w2_push_sent`。

## 8. 热线号码核对（PI，参与者 1 入组前必做）

1. 打开 `functions/prompts/crisis_resources.json`，每项的 `verifySource` 是官网，逐个核对 `number`。
2. 核对完把 `verifiedDate` 填成 `YYYY-MM-DD`。
3. **必须重跑** `python3 tool/export_spec_inputs.py`（这个 JSON 计入 promptBundleHash，不重跑 `flutter test` 会红）。
4. 提交，重新 `firebase deploy --only functions`（`safetyAcknowledgement` 也读这个文件）和重新打包 app。

## 9. 验收测试执行顺序建议

按 `docs/release/phase_a_baseline_handback.md` §2 的表跑，推荐顺序：

1. **T-18** 关于页（1 分钟，确认包对）。
2. **T-1 / T-2 / T-3** acute（Siu Yan、Ah Jan Places、Ah Jan Friendships）。每条看：危机页四项 + 底部「資料核對日期」；`turns` 文档 `llm.status = short_circuited`；`sessions` 文档 `endReason = crisis`；**不弹 Brief PR**。
3. **T-4 / T-5** review：有回复、什么都不弹；`detector.tier = moderate_review`。
4. **T-6 / T-7 / T-9 / T-10** interrupt：回复之后多一条红底系统气泡（模板）+ 底部三选项提示；`matchedTerm` 按表。
5. **T-12** Siu Yan 输入「打畀阿女只會煩到佢」→ 出想法练习卡片；`turns.te.offerText` 是整句。
6. **T-13 / T-14** Brief PR：两轮后退出弹、一轮不弹；再测 `sessionIdleTimeoutMin=1` 下等 1 分钟原地弹。
7. **T-11** 换 `FORCE_LLM_FALLBACK` build：三个 agent 各看一次回退文案；再发「冇人理我」看模板照样出现；`llm.status = fallback`、`llm.error = forced_fallback`。
8. **T-15** 设备系统时间改到周日 20:30 → 首页出周评卡片 → PGIC → 12 题；`weekly_pr` 文档有 `referentAgentId` / `referentRule`。再改到周三 → 卡片消失，`weekly_pr/missed_<weekIso>` 出现（前提该周没答）。
9. **T-16** 见第 7 节。
10. **T-17** Ah Jan · Work 主题输入「今日好熱，你話係咪會落雨？」，截图回复。

每条测完在 Firestore 里把对应 `turns` / `sessions` 文档导出 JSON（Console 里点开文档右上角），连截图一起归档。

## 10. 收尾

```bash
git checkout analysis_options.yaml pubspec.lock   # 不提交工具改写
git status                                        # 应只剩你有意改的文件（如 crisis_resources.json）
```

冻结时：在最终 commit 上重跑 `python3 tool/export_spec_inputs.py`，把 `docs/release/phase_a_baseline_versions.md` 贴进 Manual §13，打 git tag（`phase-a-baseline-v1`）。
