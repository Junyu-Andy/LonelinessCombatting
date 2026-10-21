# 开发记录

按时间记下做过什么、讨论过什么。最新的在最上面。设计决定的理由见 `docs/decisions/`，参与者能感受到的改动见 `docs/STUDY_CHANGELOG.md`。

每次合并 PR 或做出决定后，在这里加一段。

---

## 2026-10-21 冻结前收尾：回忆列表、读少少只留小读本、望一望心入面第 2 版、W8 卡第二行、版本号（第 131、132、133 条，决策 0073；收尾 PR）

- 结论：冻结前最后一个 PR。合进 main 后再打 tag phase-b-freeze-20261020。两组相同，不加开关，不新增模型调用。
- 回忆列表打勾错的原因（只读核实）：`reminiscence_landing.dart` 的 `_completedStream` 读的是旧版回忆的 `memory/m3_reminiscence/sessions/week_N.status`，不读回忆 v2 的 `users/{uid}/reminiscence_v2/week_N`；用过旧版回忆的账号，旧记录一直显示打勾。这就是 Junyu 和 Maria 看到「没答完就打勾」的原因。`_chapterSection` 在 inProgress 时确实会显示「完成今個禮拜」，但回忆 v2 要等第 8 题之后才出结束语，实际上碰不到；这次也加了限制。
- 回忆列表现在只看回忆 v2：没进过没有图标；答了 1 题以上没完成显示「講咗 n／8 條」；8 题都处理完并撳过「完成今個禮拜」才是绿勾。
- 读少少：15 篇旧短文删掉，只留 14 篇小讀本；旧 id 清单留在 `docs/research/`。
- 望一望心入面：第 2 版题目和「前後對照」页，只有前两题必填，记录加 `version: 2`；Hybrid 组小欣邀请卡换一句。
- W8 首页卡第二行「一共 5 部分，可以分開做。」；版本号 1.0.1（build 4）。
- 小欣提示词 v5（第 134 条）：不再在对话里口头提议望一望心入面，只出邀请卡；卡的触发词加「冇人會記得我」「冇人記得我」。用合成句子在真模型上各试 5 次：v5 五次都没有「stuck」、没有邀请练习。上线检查脚本里回忆 v2、心情一行两个开关的期望值定为开。

## 2026-10-21 看板 #142 按第 66 条改：总览显示整份每周问卷，每人页显示心情数值（决策 0072 取代 0061；分支 `claude/zealous-fermat-8rgqtg-dashboard`）

- 结论：Junyu 10/20 第 66 条、10/21 确认。总览和组别同一行，显示每一周的整份每周问卷做完没有；每人页显示每天的心情数值。这是有意的盲法取舍，为了提醒和跟进。先写决策 0072，0061 只改状态行。
- 总览：W1 至 W7 每周一格，W8 写「未做」。第 1 至 3 周看 DJG-ES、Weekly PR、PGIC，第 4 周看 Weekly PR、PGIC，S12 开着时也算；第 5 至 7 周只有 PGIC（整天开关，决策 0067）。每部分都做完才算完成，没做完写「3/4」这样的部分数。排期、窗口、做完的标准都调用服务器的 `functions/weekly_schedule.js`；PGIC 用作答时间判断，不读分数。
- 每人页：多一张每周问卷表（几号开、几号截止、状态、每部分做没做）；每日表显示心情数值，一天几次全列，第一次在前。心情数值只在每人页，总览、今天要做、结局完成率、CSV 都没有。
- 仍然读不到：问卷答案和分数、对话原文、分配序列、`randomization_state`、`sequence_versions`、分配日志、改组记录。原来的测试照旧守住。
- 并入 main（10/21 冻结构建 #151），没有冲突。看板调用的 `weekly_schedule.js`（第 5 至 7 周整天）、`study_period.js`、`ops_dashboard.js` 照常可用。
- 测试：看板单元测试 12 项、模拟器测试 12 项通过（合成数据的心情数值带记号，查到只出现在每人页）；`tool/ci_backend_tests.sh` 全部通过。截图 `docs/dev-reports/1021-dashboard-shots/`。
- 不改 App、Functions、规则。不进 STUDY_CHANGELOG：看板只给研究员用，老人感受不到。

## 2026-10-20 1020i 第二版：本机只读运营看板（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-dashboard`；决策 0061）

- 新目录 `tool/dashboard/`：Node 本机网页，只在 `127.0.0.1` 打开。五页：总览、今天要做、每人页、结局完成率、导出 CSV。研究日、问卷窗口、跟进阶段、有效会话、check-in 完成，都调用 `functions/` 里的同一份代码。
- 读数据：专用只读服务账号。启动时用 `testIamPermissions` 检查，钥匙能写就拒绝启动。`lib/guarded_db.js` 只许读白名单里的集合，每次只取白名单里的字段。序列、`randomization_state`、`sequence_versions` 和分配日志写死不读。
- 盲法：总览页每周问卷一格只看 Weekly PR。结局问卷完成情况只出现在「今天要做」名单（无组别）和全体合并的完成率（Phase B，少于 5 人不显示）。心情只显示有没有记。
- 写入：「確認處理」「標記誤觸」由 Junyu 在网页上用 App 账号登录，浏览器直接调用现有的 `acknowledgeAlert`、`markSafetyFalseAlarm`。看板程序自己不写 Firestore。
- 测试：
  - `tool/dashboard/test/` 两份，已加进 CI 和 Mac 本地脚本；
  - 合成数据的答案、心情值、对话、分配字段都带记号，确认没有读回来，也没出现在任何输出里；
  - 另在模拟器上走了一遍登录和按钮：评估员账号被服务器拒绝。
- 不改 App、Functions、规则。不进 STUDY_CHANGELOG（参与者感受不到）。
## 2026-10-21 T35 W8「最後一份問卷」App 内自填（交接 1021-W8，决策 0036；分支 `claude/zealous-fermat-8rgqtg-w8-1021`，从 #151 的 head 开）

- 结论：W8 做好了，冻结后合并、部署 Functions 和规则就生效；第 56 天前谁看到的都不变。两组同一流程、同一推送、同一时间，零模型调用，不加开关。
- 流程：5 个部分（DJG-ES 6 题 → UCLA-3 → PGIC → CI1–CI3 → LSNS-6），每部分「第 N 部分，共 5 部分」，一屏一题，每题可跳过，中途离开下次从那题接着做；做完显示完成页和可选 AIMHS（「填呢份」「唔填喇」，不填仍算完成）。老人看到的字照交接第三节逐字，测试逐字比对规格和代码。PGIC 和第 1–7 周 PGIC 页一字不差，只多了跳题。
- 时间和推送：第 56 天 00:00 开、第 63 天 23:59 关，第 64–70 天仍收（标 `outOfWindow`），第 71 天起首页没有卡、没交的部分记缺失。第 56 天 10:00 推给所有已登记的 RCT-、PB-、PILOT-，第 58、60 天只推没做完的人，不受安靜時段影响；测试账号不推。第 60 天 10:00 给 Junyu 一封名单电邮（只有研究编号和研究第几天）。
- 存储照每周问卷：一部分一份 `W8` 记录（`djg_responses`、`ucla3_responses`、`pgic`、`ci_responses`、`lsns6_responses`、`aimhs_responses`），每题存原值和作答时间；研究周、研究日、超窗、分数由服务器写，规则不让 App 写。整份完成状态在 `weekly_status`；运营看板的 W8 一格改成真实完成状态，只有完成情况，没有答案。删除脚本和锁库后的分析导出都包括新集合。
- 开工方式 (4)：原来 App 只在 `events`（`app_start`）和 `usage_events` 里带版本号，看板看不到，而且所有包都是 1.0.0（build 3），分不出新旧。现在 App 每次打开写一次 `users/{uid}.appBuild`（含 `w8: true`），看板每人一行显示「App 版本」，新脚本 `tool/w8_dates.js`（只读）按研究编号列第 56/58/60/63/70 天和 App 版本。
- 开工方式 (5)：App 收到通知不会按类型跳页。旧包撳 W8 推送只会打开首页（或上次停的页面），没有问卷卡，也不会出错——等于做不了，要靠 W4 面访装新包。
- `lib/features/phase_b_probes/` 的「猜版本」「依赖感」探针确实不出现：没有任何页面引用，W8 也没有（测试检查 `lib/` 里没有文件 import 它）。
- 测试：服务器单元测试和模拟器测试（W0 星期一至日各一人，推送、提醒、电邮、超窗、缺失、两组相同、零模型调用）、规则测试、Flutter 测试（逐字、流程、首页卡、最大字号 360 宽）；截图 `docs/dev-reports/1021-w8-shots/`。报告 `docs/dev-reports/T35-w8-20261021.md`（含第 56 天日期表的算法和例子）。

## 2026-10-21 #152 Flutter 3.44.1 并入冻结版（第 127 条）

- Junyu 用 Run #23 的包在真机上照 `docs/release/flutter-3441-phone-check.md` 走完：覆盖安装（不卸载、登录还在）和两组的五步都过了。#152 合进 #151，没有冲突。
- CLAUDE.md 的 Flutter 一行改为 3.44.1（Junyu 批准）。决策 0068 照旧；它写的「提议中」以第 127 条为准，已采纳。
- 合并后在 GitHub 上用 3.44.1 重跑 CI 和 Build APK，确认指纹不变。

## 2026-10-21 冻结前：危机页第四项改名、安靜時段说明句（第 126 条 (6)，冻结合并分支 #151）

- 危机页第四项「急症室 / 999」改为「緊急求助」（英文 Emergency services）。原来名称和号码连读是「999 999」。危机页和急性后聊天消息读同一份 `crisis_resources.json`，两处一起变；App 内置的备用列表同改。号码、时段、说明句和其他三项都不动，两组相同。截图 `docs/dev-reports/1021-shots/crisis/`（两组，1.06 和最大字号 1.30）。
- 「我的設定」安靜時段的说明句改为「呢段時間 App 唔會彈通知。」（Junyu 定稿）；选择框标题照用。首页小行动三句已经是 10/20 第 88 条 (3) 的定稿，没改。
- Junyu 定：回忆四周不按研究周锁；iOS 最低版本写进安装说明、看板 #142 第 66 条（先写新决策记录取代 0061）、#152 都在冻结后，记在 backlog。

## 2026-10-21 冻结前：Weekly PR v3、计划提醒过期起算、审计更正（第 117、118 条，冻结合并分支 #151）

- Weekly PR v3 改为「呢個禮拜 {伙伴} 冇對我指指點點。」，粗体关键字跟着改。u3 不改，题号、字段、计分不变，两组相同。仓库原来没有 Weekly PR 规格，新建 `docs/spec/instruments/weekly_pr.md`，测试逐字比对规格和代码，并在最大字号、360 宽手机上检查 v3 整句显示、没有切字。截图 `docs/dev-reports/1021-shots/weekly_pr_v3_360_x130.png`。
- 审计第 1 项：时段 20:00 开始、提醒 19:50 的人，原来次日 08:00 已过 12 小时，被记 skipped_stale。现在提醒到点后、下一次派发前就进了安靜時段，而且这个时段要到点 12 小时后才结束，就从时段结束起算。默认 22:00–08:00 的时段只有 10 小时，所以默认的结果每一刻都和以前一样（测试逐个时刻比对）。模拟器测试加了 19:50 这一条。
- 审计第 4 项：STUDY_CHANGELOG 里安靜時段那一行更正：check-in 推送（P1/P2）和小篇章推送在时段内跳过、不补发；计划提醒和每周问卷才是等到时段结束。
- 审计第 2、3、5、6、7 项冻结后做；第 8 项照现状，记进已知限制。

## 2026-10-21 早上：求助句接回后半句、原文脚本再收紧、「讀少少」标题（第 114 条，冻结合并分支 #151）

- 规则组求助句：第 113 条换上的整句后面接回原来的后半句。小欣两处接「你唔係一個人。」，阿珍／阿伯接「今日辛苦你喇。」。`docs/spec/copy/rule-templates.md` 一起改，版本号改 `2026-10-21-help-line-2`。
- 只读原文脚本 `tool/read_transcripts.js`：除了 `isTester` 要是 true，还要**没有** RCT-、PB-、PILOT- 开头的研究编号，其余一律拒绝。研究编号从 `research_id_map/{uid}` 读，只读这一个字段、只比开头，不显示；不读分配记录。模拟器测试加了 RCT-、PB-、PILOT- 和 cohort 四种被拒的测试员，以及一个只有导出用假名（P 开头）的测试员可以读。
- 「讀少少」页：Junyu 看截图觉得标题不够醒目。顶栏改白底加细线，「讀少少」「小讀本」改粗体，和小讀本阅读页的顶栏一致。文字不改，两组相同。
- 「同小欣講吓感受」「同小欣講吓你嘅感受」两处按钮文字都是定稿，不改。

## 2026-10-21 小讀本 14 篇进冻结版；原生顶栏、读过的节、小欣按钮、讀下一篇（决策 0070；分支 `claude/zealous-fermat-8rgqtg-readers-1021`，并入 #151）

- 结论：readers-1021.zip 的 14 篇全部通过检查，原样放进 `assets/readers/`（每个文件和交来的一字不差）。「讀少少」按三部分分组，每篇图标和「約 n 分鐘」，读完打「✓ 讀完」。阅读页用 App 顶栏，「?」问通通只在 Hybrid 组（取代页底按钮），规则组留空、零模型调用。不加开关。决策 0070。
- 新工具：`tool/add_readers.sh <zip>` 一步加入（zip 当不可信数据，自己解析，逐篇查，只放通过的）；`tool/check_reader_html.js` 改为逐篇报告，认 `.explain.json`、manifest 新字段和 App 处理的四种 `peizhu://` 链接；`tool/readers_shots_1021.sh` 用无头 Chromium 把真网页放进 App 顶栏截图，并逐篇查（360 宽、字号 1.30 不横向超出，`back()`、`readIds()`、`peizhu:view`、隐藏的解释按钮、不发请求）。格式说明给写读本的窗口：`docs/release/readers-file-format.md`。
- 检查脚本调整两处：参考资料里「年;卷(期):页码」的页码范围不当电话号码（4 篇原本因此被误拦）；`<script type="application/json">` 里网页会显示的字也查不准用的字（14 篇都没有）。
- 硬规则「每个 peizhu:// 都要接得住」：14 篇里 `chat_siu_yan` 28、`small_action` 10、`thought` 3、`reader/open` 13（都指向包里的篇）、`explain` 72（都在隐藏按钮上，App 不设 `data-explain`）；测试逐个扫描打包的文件。
- 截图：`docs/dev-reports/readers-1021-shots/`（列表、目录、某一节、读完的目录，两组，360 宽、1.30）。真机还要测：WebView 里的 `back()`、`peizhu:view`、`setRead` 时机。

## 2026-10-20 测试员原文查看工具和 10/21 原文测试指引（分支 `claude/zealous-fermat-8rgqtg-readtx`，基于冻结分支，未开 PR）

- 结论：新加只读脚本 `tool/read_transcripts.js`，Junyu 可以自己看一个**测试员账号**存下的研究原文（`chat_transcripts`）：按会话分组、按时间排、香港时间、回复保留换行。新加一页测试指引 `docs/release/transcript-test-1021.md`：两组各用一个测试员账号，做 check-in、和小欣聊两句、回忆第 1 周、一句急性测试句，逐行核对。App、规则、Functions 都没改，参与者看到的不变，所以没有 STUDY_CHANGELOG。
- 只限测试员：脚本先只读 `users/{uid}` 的 `isTester` 一个字段，不是 `true` 就拒绝，原文一行不读。不读、不显示研究编号、电邮、组别，不碰分配序列和分配记录。正式的读取工具（给非盲角色、按研究编号、带审计记录）冻结后做，已记在 backlog。
- 安全做法照其他 tool 脚本：默认模拟器；正式项目要 `--project` 和 `--production-confirm`，这样跑是试运行（只核对账号、数行数，不读原文），再加 `--production` 才显示原文。
- 测试：`functions/test/read_transcripts_emulator_test.js`（合成数据：旧格式和新格式行、陪伴者行、按钮行、急性行，顺序、分组、换行；非测试员、`isTester` 是字符串、账号不存在都被拒，并用记录调用的包装证明只读了那一个字段；试运行只读时间字段；什么都不写；不显示电邮、研究编号、组别）。`tool/ci_backend_tests.sh` 的模拟器循环自动跑到；本地 41 个模拟器测试全过。
## 2026-10-21 小讀本交接第四节：回应池求助句、「問下通通」改 Pro（第 104、109–113 条）

- 规则组回应池：X5-4、Z5-4（以及 check-in 聊天里的 X5-4）原来叫老人去「求助資料」，App 里没有这一页。整句换成小讀本里的求助句，一字不差。「睇今日」是第一个分页的名字，「睇更多支援熱線」是首页安全卡上按钮的字，都核对过。号码不改。版本号改 `2026-10-21-help-line`，分析时可以分开前后。
- 「問下通通」：服务器认出通通的文章问答（App 放在最前面的文章标题行），就用 deepseek-v4-pro。短文和小讀本两处都算，只在 Hybrid 组。决策 0071。要部署 Functions 才生效。
- 上线检查脚本里 `htmlReadersEnabled` 的期望值改为 true。
## 2026-10-20 1020p 第一节：Flutter 3.35.3 升 3.44.1，只换工具版本（决策 0068，分支 `claude/zealous-fermat-8rgqtg-flutter344`，PR 草稿，base 冻结分支）

- 结论：CI、Build APK、Codemagic、`.metadata`、本机测试脚本改为 Flutter 3.44.1（Dart 3.12.1）。插件版本、Gradle 8.12、AGP 8.9.1、Kotlin 2.1.0、签名设定都不变。两组相同，老人看到的不变。
- `pubspec.lock` 只有 Flutter 自带的 5 个依赖跟着变（characters 1.4.0→1.4.1、matcher 0.12.17→0.12.19、material_color_utilities 0.11.1→0.13.0、meta 1.16.0→1.18.0、test_api 0.7.6→0.7.11）。
- 3.44.1 改了两处默认样子：Android 换页动画（放大淡入改成滑动淡入）和四个由主色推出来的字色（变浅）。在 `lib/app/app_theme.dart` 锁回 3.35.3 的样子；两种主题逐项比对一样，12 个截图测试文件（100 个用例）3.35.3 和 3.44.1 逐个像素相同。没锁回的只有 Android 列表拉过头时的拉伸画法。
- iPhone：`pubspec.yaml` 加 `enable-swift-package-manager: false`，插件照旧用 CocoaPods 组装（3.44.1 默认改 Swift Package Manager）。另发现 `ios/Runner/AppDelegate.swift` 用的 `FlutterImplicitEngineDelegate` 在 3.35.3 里没有，按 3.35.3 打 iPhone 包很可能编不过；3.44.1 有这个接口。要在 Mac 上确认。
- 测试只改 `test/reader_test.dart` 的外壳主题（改用 App 主题；原来用 Flutter 默认主题，新版换页变慢，3 至 4 个测试等不到页面关完）。`flutter analyze` 两个版本都是同样的 92 条，0 error。
- 没做的：Android 模拟器走查（这里没有 KVM 和 Android SDK）；真机清单 `docs/release/flutter-3441-phone-check.md`。`CLAUDE.md` 的「Flutter 固定 3.35.3」那行要 Junyu 改（开发窗口不改 CLAUDE.md）。

## 2026-10-20 研究原文补全：陪伴者的每一句都存（decisions-log 第 65、80、99/100 条，分支 `claude/zealous-fermat-8rgqtg-transcript2`，并入 #151）

- 结论：研究用原文（`chat_transcripts`）现在存下老人的每一句（含按的按钮）和陪伴者显示的每一个气泡，两组相同。不加新开关，仍看 `researchTranscriptEnabled`。老人看到的不变，`turns` 和埋点不变，规则组零 LLM 不变。决策 0069（部分取代 0063）。
- 先查后改。改之前漏的：所有开场白（小欣 check-in 的 Q0、Q1，规则组 SY0，Hybrid 开场，回忆开场三句和第一题，通通开场，想法练习对话页顶那句，旧 check-in 页开场）；check-in 的 Q2–Q6 和按钮回答（按钮只在 `check_in_responses` 有代码和字）；回复后面的下一题和回忆收尾句；中度安全句、急性后安全消息（存成空字）；想法练习对话的「呢個諗法聽落好沉重」和 👎 之后的新回复；模型失败时存了模型的字而不是屏幕上的后备句；回忆 v2 的 Hybrid 回复被安全扫描拦下时，存了老人没看到的模型原字。
- 现在：老人一句一行，`replyText` 是这句之后、下一句之前所有气泡，中间空一行；老人开口前的存成 `role: companion` 一行；按钮存按钮上的字（`userInput: button`）；急性后存安全消息的字（开头一句 + 危机页的机构名和号码 + 「〔打開緊急求助頁〕」）。每周回忆大图那一句不存。回忆 v2 隔天回来，等回答的那一题在新会话开头再存一次（`shown_again`）。
- 一行在老人下一句、会话结束、离开页面、App 退到后台时写出。一句没说就离开：没有会话，开场白不存。
- `firestore.rules`：新格式（schema 2）字段和取值限死；旧格式（schema 1，冻结前的 App）照旧接受；只许本人新建、登记或测试员、开关开、长度上限、谁都不能读改删，都不变。要随冻结构建部署，可以先部署。
- 测试：新加 `test/research_transcript_v2_test.dart`（每个聊天页每组一段模拟对话，逐行核对；两组对照；规则组每段都断言零模型调用），已加进 `tool/ci_flutter_tests.sh` 两个 Phase B 列表；规则测试加 schema 2 七组；盲法检查把原文字段列为禁止字段；删除测试加一行陪伴者行。
- 没做：读取工具（1020l 起就欠着）；进程在前台被杀时最后一行会丢；规则组回忆在「答了但回复还没出」时被杀、下次补回复，那一行原话为空（`turns` 同样）。
## 2026-10-20 安卓通知小图标（第 99–100 条）

- 结论：加了专门的通知小图标。陪住图标做成白色剪影（两个人和一张桌，茶杯是镂空），透明底，五种密度都有（`android/app/src/main/res/drawable-*/ic_stat_peizhu.png`）。AndroidManifest 设了 FCM 的默认通知图标和颜色（主题色 #C2703F）。App 没有本地通知，所有通知都经 FCM，所以都用这个图标。两组相同。
- 查原因：App 图标是 10/15 换的（#97，不是 #126）。10/16 起 GitHub 打的安卓包都已经是新图标。手机通知里还显示 Flutter 标志，说明那个包是 10/15 以前打的（或者是别处打的旧包）。新图标是彩色、不透明的，没有专门的通知图标时，安卓只看透明度，会显示成一块；所以不管哪一种，都要加这个通知图标。
- 图标由 `tool/make_notification_icon.py` 从 `assets/icon/app_icon.png` 生成，可以重跑。测试 `test/android_notification_icon_test.dart` 查 AndroidManifest 里的设置，以及五个图标的尺寸和白色透明。
- 这里没有安卓模拟器，也没有真机。通知栏的真机截图要等装上冻结构建以后拍。

## 2026-10-20 首页 check-in 一行：急性中断那天也打勾（第 99–100 条）

- 结论：check-in 因急性中断、研究员没标「誤觸」时，首页「同小欣 check-in」一行显示已打勾。以前这一行没打勾，撳进去却是聊天，看起来像「不能 check-in」（Maria 测到的第二种情况）。两组相同，不加开关。
- 规则只有一条（`check_in_response_store.dart` 的 `isStoppedUnmarked`），首页和小欣页共用，和服务器 `daily_checkin_push.js` 的算法一致。标了「誤觸」不打勾，老人可以从停下那题接着做；第二天照常。
- Maria 的第一种情况（测试员「日程模擬」）照 Junyu 定不改：check-in 按真实日期算。
- 测试在 `test/home_v2_test.dart` 的 check-in 一行组：两组，当天中断未标 → 打勾、撳进去是聊天；标了誤觸或昨天中断 → 不打勾。

## 2026-10-20 第 98 条：第 5 至 7 周 PGIC 改按整天开关；`weeklyPushHour` 默认 10（分支 `claude/zealous-fermat-8rgqtg-pgicdays`，并入冻结 PR #151）

- 结论：第 5 至 7 周 PGIC 和第 1 至 3 周一样按整天：第 35 天 00:00 开，第 37 天 23:59 关（42–44、49–51 同）。开放日 10:00 推给所有人，第二天 10:00 只推给没答的人。不预告，最后一天不提醒，不进 Junyu 的电邮，文字沿用原来两条。首页问卷一行第一天「請盡快回答」、第二天「聽日截止」、第三天「今晚截止」。两组相同，不加开关，决策 0067（取代 0055 第 8 条）。
- 做法：放进原来的提醒 v2（`weeklyReminderV2Enabled`，生产已开），服务器和 App 用同一张测试表。开关开着时旧的第 5–7 周做法（推送起 72 小时、24 小时后提醒）删掉；开关关着时七周全部照旧。
- `PhaseBConfig.weeklyPushHour` 和服务器默认值都由 20 改为 10，和生产一致。1020p 第二节记下的「读不到配置时差 10 小时」随之解决。
- 部署时已在第 5–7 周窗口里的人：已发的推送和提醒不重发，窗口改在第三天 23:59 关。没答的在第 38 天 08:00（定时任务第一次跑）记缺失。
- 测试：服务器单元测试；新的模拟器测试 `functions/test/pgic_whole_days_emulator_test.js`（合成账号跑第 34–38 天，每小时跑一次推送任务；第 6、7 周；部署时已在窗口里；开关关）；新的 Flutter 测试 `test/pgic_whole_days_1020_test.dart`（两个 Phase B 列表都加了；共用表、首页一行每天的字、两组）。旧的 T24 模拟器测试把 `weeklyPushHour` 固定为 20，内容不变。
## 2026-10-20 1020o (4a) 跟进：第一次进入某一周停在大图（decisions-log 10/20 第 99/100 条；分支 `claude/zealous-fermat-8rgqtg-scene2-1020o`，未开 PR，不加开关）

- 结论：Junyu 定了上一段留下的两件事。第 99 条：第一次进入某一周，画面一打开就停在大图（像之前的 `_start` 截图），老人往下拉才到第 1 题；之后再进入、或者没有大图时，照旧停在最新一句。第 100 条：模型不知道图的内容，不改提示词——就是现在的做法，不改。
- 做法（`reminiscence_v2_page.dart`）：这一次进入加了大图（第一次进入）时，页面准备好后把对话列表拉到最上面（列表是倒排的，最上面就是这一周的开头），多试几帧直到停稳——因为最上面的气泡要建出来才量得到高度，下面的输入框出现时列表也会变短。开场和第 1 题在同一帧一起出来，不会把画面推回下面。老人按发送或「唔想講」时，列表回到最新一句（和其他聊天页一样）。iPad 上一周的内容整页放得下，列表照旧贴在底部，大图在画面里。
- 两组相同、不调用模型；登记表不加新版本（属于 v10.11 那一项的显示细节，在这里记一笔）。
- 测试：`test/reminiscence_scene_1020o_test.dart` 加：第一次进入（手机 360 字号 1.30 和 1.06、iPad）大图顶部在画面里、手机上停在最上面且一直停住；再进入、没有大图时停在最新一句；答第 1 题之后跟到最新一句。三种构建都跑。截图 `docs/dev-reports/1020o-shots/scene/` 的 `_landing` 现在就是停在大图的样子。

## 2026-10-20 1020o/1020p 补充第一项：危机页核对日期（第 97 条）

- 结论：`crisis_resources.json` 的 `verifiedDate` 填 2026-10-20，危机页底部从「資料核對日期：待核對」变成「資料核對日期：2026-10-20」。四个号码没改。两组相同。
- 测试 `test/crisis_verified_date_1020p_test.dart`：日期是 2026-10-20、四个号码和以前一字不差、两组危机页底部都显示日期。1020j 第三节「危机页核对日期」这一项就此完成。

## 2026-10-20 1020p 第二节：问卷推送钟点核对（只读，没改推送）

- 结论：Junyu 已把 `weeklyPushHour` 改为 10。上线检查脚本的期望值改成 10。按固定钟点发给老人的研究推送，**没有一个落在 20:00 至 08:00**（只剩一个旧的星期日 20:00 提醒，但登记闸门开着时谁都不发）。
- 各推送钟点：check-in 早上 08:30；check-in 提醒 19:00；第 1–4 周问卷（预告、开放、两次提醒）10:00；第 5–7 周 PGIC 10:00，提醒 24 小时后也是 10:00；研究员每日邮件 10:00（发给研究员，不是老人）。行动计划提醒和回忆小篇章的通知按事件时间发，落在安靜時段里的会留到时段结束。W8 问卷（第 56 天，T35）和 debrief（T42）还没做，没有推送。Phase A 的第 7 天 ADA 推送按参加者自己选的钟点（08:00–21:00），不属于 Phase B。
- App 读不到配置时（第一次打开就没网）：用默认 20，第 5–7 周那几天首页问卷一行会在 10:00–20:00 之间显示「今日開」而不是可以填，最后一天会多显示到 20:00。只显示日期，不显示钟点。只在这种少见情况下出现，下次读到配置就对了。按交接不改，记在待办。

## 2026-10-20 1020o 第二节补充：「常見問題」整页换成新版（decisions-log 10/20 第 93 条，冻结合并分支 #151）

- 结论：页顶一句和六条问答全部换成 Junyu 定的新版，每条问题前加一个小图标（医生、锁、字体、日历、月亮、心；Material 图标，主题色，和问题字一样大，对齐问题第一行）。两组相同，直接替换，不加开关；上一版（同日上一段）的文字已删。
- 页顶旧句「如果呢度搵唔到答案，可以喺「設定」搵聯絡方法畀我哋。」删掉（「設定」页已经没有）。
- 引号照上次：单独显示时『』换成「」。英文版跟着改意思。号码只有 18111 和 999。
- 第 4 条仍跟 `app_config/usage_copy.faq_skip_checkin_answer`；生产上有没有设，等 Junyu 跑 `tool/check_prelaunch_values.js` 的结果。
- 测试 `test/faq_1020o_test.dart`：两组、普通和高对比、最大字号、360 宽手机；页顶一句和六条逐字核对，图标、颜色、大小核对，六条全部展开不溢出，旧问题和旧页顶句不再出现。截图 `docs/dev-reports/1020o-shots/faq/`。

## 2026-10-20 1020o 第三节：「安靜時段」回到「我的設定」，老人自己定时间（分支 `claude/zealous-fermat-8rgqtg-quiethours-1020o`，未开 PR，交给冻结分支合并）

- 结论：「自己 → 我的設定」多一项「安靜時段」，一句说明和「由」「到」两个选择，默认 22:00 到 08:00，没有开关。两组相同。取代 10/19 第 14 条 (2)（固定开）。
- 范围先按「由」20:00–23:00、「到」06:00–08:00、每半小时一格（Junyu 已定），避开 08:30、10:00、19:00 的研究推送。范围写在 App、服务器、规则三处，三处不一致测试会失败。
- 服务器先看本人的值，没有就用全局值；超出范围按边界算。计划提醒派发时间改为 06:00–22:45，个人时段内的提醒等到时段结束再发，过期从时段结束算起。没设过的人行为不变（模拟器测试逐个时间点核对）。
- 每次改动记一条使用事件 `quiet_hours_changed`。旧开关残留（手机上的 `notifications.quietHours`、登录时写 `quietHoursEnabled`）删掉。
- 已有的东西：`functions/quiet_hours.js` 和各推送的时段检查（10/14 起），这次只是让它先看本人的值；设定页 10/20 拿走开关时留下的同步代码一并清掉。
- 待 Junyu 看：截图 `docs/dev-reports/1020o-shots/quiethours/`；第一层「我的設定」小字仍是「顯示：高對比模式」，要不要加上安靜時段。常见问题第 5 条（1020o 第二节）已经指向「我的設定」嘅「安靜時段」，和这次一致。
## 2026-10-20 1020o 第四节 (3)(4a)：主题图片放进来；回忆每周第一个气泡是一张大图（分支 `claude/zealous-fermat-8rgqtg-scene-1020o`，未开 PR，不加开关）

- 结论：两组相同、不调用模型、不加开关。Junyu 的 8 张图（4 张主题图 512×512 PNG，26–47 KB；4 张大图 1024×768 JPG，96–122 KB，都在 200 KB 以下）放进 `assets/reminiscence/`，`.gitkeep` 删掉。1020o 的文字 Junyu 已定；「我嘅人生小篇章」两处入口都留（之前写的「待 Junyu 定」以这一段为准）。
- 主题卡：图片在了，卡片显示图片；读不出时仍回到数字方块（测试按文件在不在分两种情况检查）。
- 大图气泡：回忆 v2 页（`reminiscence_v2_page.dart`）第一次进入某一周时，先加一条新类型 `scene` 的消息（`copyId: scene_N`，文字是这一周那一句），再加开场三句和第 1 题。只有 App 里真的有这张图（查资源清单）才加；画面上图读不出来时整个气泡不画。气泡宽度和其他气泡一样（屏宽 88%，iPad 在 600 宽的栏里），圆角，图 4:3。
- 发给模型的对话历史**不放**这一句：模型看不到图，也没有图的文字描述；放进去它可能会讲图里没有的东西。这一句也不等回答，不影响追问。开场三句照旧放进历史。规则组不调用模型，没有变化。
- 研究对话记录（`chat_transcripts`）只在老人每说一句时写一行，这个气泡不是老人的一句，不写；老人第 1 题的回答照旧写。周对话存档（`reminiscence_v2/week_N`）里多一条 `scene`，小篇章请求只按题目取答案，不受影响。
- 再进入：这条消息已经存了，所以它留在这一周对话的最上面，只出现一次，不会重加；这个版本之前已经开始的那一周没有这张图（不补加）。
- 手机字大时，老人一进来看到的是最新的第 1 题，大图在上面，要往上拉才看到（截图有两张：一进来、拉到最上）。
- 测试：新加 `test/reminiscence_scene_1020o_test.dart`（两组；四周的图和句子、在开场前；读不出图／App 没有图时不出现；不发给模型；离开再进不重加；小手机大字），加进 `tool/ci_flutter_tests.sh` 两个 Phase B 列表；`reminiscence_v2_test.dart` 的消息顺序加上 `scene`。截图：`docs/dev-reports/1020o-shots/scene/`（第 1 周开头），`docs/dev-reports/1020o-shots/landing/` 换成有主题图的版本。

## 2026-10-20 1020n：安全消息开头一句定稿；首页小行动一行每个计划一行、订计划那天显示「聽日計劃」（分支 `claude/zealous-fermat-8rgqtg-smallaction-1020m`）

- 结论：Junyu 对 1020m 的回复（decisions-log 第 86–88 条）三处都做完，两组相同，不调用模型，不加开关。
- 第一节：急性后聊天里的安全消息开头一句改为「如果你而家好唔開心、好難頂，請即刻打以下電話，有人會聽你講：」，草稿句从代码、测试、文档里删掉；号码和按钮不变。截图重拍在 `docs/dev-reports/1020n-shots/crisis/`（旧的 `1020m-shots/crisis/` 删掉）。
- 第三节：先查了数据结构——同一天几个计划本来就可以（每个计划一个文档、一条提醒，没有任何限制）；只是首页这一行以前只显示一个。改成每个计划一行、各自「做咗」「改日」，最多两行，多的写「仲有 N 個計劃」（进「我嘅計劃」）；订计划那天显示「聽日計劃：…」（没有按钮）和「仲有冇其他計劃？」（进「今日小行動」），没有「遲啲先」。使用事件多 `next_day_plan`、`home_small_action_more`、`home_small_action_list`。
- 第五节：计划文字最多两行再加「…」。截图在 `docs/dev-reports/1020n-shots/`（手机 1.06、1.30：订计划那天两个计划；今天三个计划）。
## 2026-10-20 1020o 第二节：「常見問題」五条答案改写（冻结合并分支 #151）

- 结论：第 2 至 6 条照交接 1020o 改写，第 1 条不改；两组相同，直接改，不加开关。
- 第 3 条核对 App 后改了两处：App 的字体有五级（标准、稍大、大、较大、特大），揀咗之后成个 App 即刻变，**没有预览**；所以写成「揀字體大小，由標準到特大一共五級，揀咗之後成個 App 嘅字即刻跟住變」。「自己」「顯示設定」「我的設定」「高對比模式」四个名字与 App 一致。
- 第 5 条的「安靜時段」在第三节加回「我的設定」。第 6 条的「想搵人傾吓？」「睇更多支援熱線」与首页安全卡一致。
- 答案里的引号用「」（交接文件里『』是引号里的引号）。
- 测试 `test/faq_1020o_test.dart`：两组、普通和高对比、最大字号、360 宽手机，六条逐字核对、全部展开不溢出；第 4 条仍跟 `app_config/usage_copy`。截图 `docs/dev-reports/1020o-shots/faq/`。
- 我读不到生产，`faq_skip_checkin_answer` 生产上有没有设，要 Junyu 跑 `tool/check_prelaunch_values.js` 看（已加一行只读显示）。
## 2026-10-20 1020o 第一、四节：「自己」页改为「我嘅人生小篇章」，旧「我的故事」页删除；回忆首页加阿珍／阿伯气泡和主题图片（分支 `claude/zealous-fermat-8rgqtg-selfpage-1020o`，未开 PR，不加开关）

- 结论：两组相同、不调用模型、不加开关（Junyu 第 87 条：直接改，旧版本删掉）。老人看得到的新文字都是草稿，等 Junyu 定。
- 第一节：「自己」页（`settings_page.dart`）「人生回顧」改名「我嘅人生小篇章」、加一行说明，打开回忆 v2 的小篇章页 `ReminiscenceChaptersPage`。阿珍／阿伯页上的同名按钮照留（两处都留还是只留一处，待 Junyu 定）。旧页 `MyStoryPage` 和只给它用的四个小组件、两个测试删掉；`MyStoryProgress`（「接著傾」卡片和首页小结在用）保留。
- 删除前只读检查旧页：① **「反思傾偈」**（Hybrid 组，和阿珍／阿伯自由倾偈）的固定入口只有这一处；另一条路是小欣／通通聊天里的转介卡「好，過去傾」（只在模型判断要转介时出现）。为了不让它消失，卡片原样搬到回忆首页最下面，仍只给 Hybrid 组（决策 0006 不变），转介那条路没动。② 「今週」卡片和「故事線」打开某一周的回忆页——回忆首页本来就有四个主题，不会少。③ 「完成咗嘅回憶」列表打开旧版（v1）每周摘要页 `M3SessionDetailPage`——回忆首页在 `reminiscenceV2Enabled` 关时有「我嘅回憶」按钮通往同一页；开关开时只剩小篇章，旧版摘要在 App 里看不到（数据不动）。正式参与者 10/21 起用 v2，没有旧版摘要；只影响试跑时用过旧版回忆的帐号。
- 小篇章页（普通和高对比）截图核对过：白底黑字，看得清，不用改。
- 第四节：回忆首页 `reminiscence_landing.dart` 顶上换成阿珍／阿伯头像（按 `ahJanAhBakVariant`，读不出图显示「伯」／「珍」，沿用 1020l 的 `AgentAvatar`）加气泡。气泡文字可以被 `app_config/usage_copy` 的 `reminiscence_landing_intro_zh`（英文 `_en`）整句替换，替换的文字里 `{name}`、`{weeks}` 也会换；如果正式环境这个字段已经有值，会显示那个旧值而不是新句，要删掉或改成新句。原来的 S3 那句（`short-texts.md`）不再使用。
- 主题卡：删「第 N 週」，加一行主题说明（按周数对应）；左边数字方块改为图片 `assets/reminiscence/theme_1.png` 至 `theme_4.png`，底色和「做啲嘢」卡片一样。图片还没进仓库：`pubspec.yaml` 登记整个文件夹，文件夹里放 `.gitkeep`，所以现在构建和测试都能过，卡片显示原来的数字方块。**图片到了：把四张图放到 `assets/reminiscence/theme_N.png`（N = 1 至 4，按主题周数），不用改代码和 pubspec**，重新构建即可。
- 顺手修：回忆首页在没登录（访客／测试）时，主题卡滑出屏幕再滑回来会报错（「已完成」那条数据流只能听一次），改成可以重复听。
- 测试：新加 `test/selfpage_landing_1020o_test.dart`（两组、阿珍／阿伯、高对比文字对比度、滑动、旧页已删且没有地方引用），加进 `tool/ci_flutter_tests.sh` 两个 Phase B 列表；`test/reminiscence_v2_copy_test.dart` 逐字比对 `reminiscence-v2.md` 新加的 L-INTRO、L-THEME-1 至 4、L-ME。截图在 `docs/dev-reports/1020o-shots/selfpage/` 和 `docs/dev-reports/1020o-shots/landing/`。

## 2026-10-20 1020m 第二节：首页「今日要做嘅事」的小行动一行（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-smallaction-1020m`）

- 结论：第一页在 check-in 一行和问卷一行之后加一行：没有计划时「今日想做啲咩小行動？」+「遲啲先」（收起 3 天）；当天有计划时「今日計劃：{做咩}」+「做咗」「改日」。两组相同，不调用模型。**不加开关，直接替换旧的一行**（Junyu 10/20 晚定；旧的计划跟进一行 `ActivePlanBanner` 从第一页拿走，它在第一页本来也不会出现，因为没有计划有 `scheduledFor`）。
- 计划没有日期，所以「计划的日子」定为它的跟进提醒那天（存好后 24 小时那天）。「做咗」写进现有的 `outcome: happened`，加 `followUpSource: home_row`（不用 `source`，那个字段已经是订计划的入口）。「改日」只记状态 `later`：第一次把计划和提醒挪到明天同一钟点，第二次不再挪、提醒取消，第三天首页改回问句；计划一直留在「我嘅計劃」。
- 跟进推送：App 在「做咗」／「改日」时删掉或挪走提醒；服务器推送前也查计划（`moved_home_later`、`skipped_home_answered`）。使用事件多五种 `home_small_action_*`，规则和测试一起加。
- 待 Junyu 定：「改日」挪一次还是两次（决策 0064 写了读法）；计划日子按提醒日算是否可以；五句文字和截图（`docs/dev-reports/1020m-shots/smallaction/`）。
## 2026-10-20 1020m 第一节：「做啲嘢」四张大卡片（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-tools-page`）

- 顺序改为今日小行動 → 我嘅計劃 → 讀少少 → 望一望心入面；四张大卡片，图用第 3 批已经做好的 `assets/tools/` 四张（`docs/dev-reports/T53-T54-batch3-20261020.md` 1.6 节）；标题和小字照 10/19 第 37 条 (2)；页顶只留「自己隨時用」。两组相同。
- Junyu 10/20 晚定：直接改，不加开关，旧版本删掉。所以「做啲嘢」不再看 `homeLayoutV2Enabled`，旧列表（`MeListItem`）已删除。
- 最大字号、360 宽手机上四个标题都在一行（图块 72）。
- 教训：之前估这项「要 Junyu 给图、3–4 小时」，是没有先查 `docs/dev-reports/`；图第 3 批早就做了。以后开工前先查。
## 2026-10-20 1020m 第三节：急性之后聊天里只显示一条固定安全消息，号码和危机页一致（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-crisismsg-1020m`，按修 bug 处理，不加开关，直接替换）

- 起因：Maria 发现急性触发后，危机页列四个号码，聊天里却写「請即刻打撒瑪利亞會 2896 0000」（decisions-log 10/20 第 84 条）。
- 查到的来源：两组、所有聊天页都是安全流程里的同一句固定话（`safety_acknowledgements.json` 的 `acute`，热线名和号码取自危机页配置里标了 `acuteTemplateReference` 的撒瑪利亞會），经 `SafetyCopy.acuteAck` 显示。不是模型写的，也不是规则组模板；提示词里没有叫模型提撒瑪利亞會。旧的四个聊天页还会把这句话当陪伴者的话发给模型。
- 做法：新组件 `CrisisChatMessage`（开头一句（1020n 定稿）+ 危机页配置里的全部机构名和号码 +「打開緊急求助頁」按钮），所有会触发急性的聊天页两组都用它；删掉 `acuteAck`；Hybrid 组模型回复被扫出急性时也显示；这条消息不发给模型；规则组旧 check-in、回忆表单急性后也显示（以前什么都没有）。没有开关（Junyu 改的指示）。号码、检测、危机页、告警都不变。决策草稿 0065。
- 测试：`test/crisis_chat_message_1020m_test.dart`（三种构建都跑，已加进 CI 两个 Phase B 清单）：每个聊天页两组各触发一次急性，核对消息里的号码和危机页同一份配置一致、聊天里没有别的号码、按钮打开危机页、规则组零 LLM、中度不受影响、模型回复里的号码照旧变成链接。截图在 `docs/dev-reports/1020n-shots/crisis/`（1020n 定稿开头一句后重拍）（危机页的拨号按钮字在测试画图里显示成方块，是测试字体的问题，真机正常）。

## 2026-10-20 1020k：反向题前的过渡句、Weekly PR 反向三题固定第三页（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-scale-cues`）

- 起因：Maria 测试时发现老人在一串同方向的题里容易把反向题答反。Junyu 定了三处文字（decisions-log 10/20 第 77–79 条）。
- 做法：新开关 `scaleDirectionCuesEnabled`（默认关）。开着时 Brief PR 第 4 题、Weekly PR 第 3 页、DJG-ES 第 4 题前各加一行；Weekly PR 反向三题固定在第 3 页，正向九题在第 1、2 页随机；记录多一个 `itemOrder`。两组相同，题目、选项、计分不变。决策草稿 0062。
- 测试：Weekly PR 页面跑十次，i1–i3 每次都在第 3 页、正向九题从没上第 3 页；排页函数另跑 1000 次。最大字号（1.30）、360 宽手机下三处都不切字、不遮按钮。截图在 `docs/dev-reports/1020k-shots/`。
## 2026-10-20 1020l (1)：对话原文修复（1020j 第一节 (4)，PR 草稿，分支 `claude/zealous-fermat-8rgqtg-transcript`）

- 每一轮聊天在原有记录之外，再存一份老人原话和屏幕上的回复（`users/{uid}/chat_transcripts`），两组都存。新开关 `researchTranscriptEnabled` 默认关。
- 规则保证：只有本人登记后能新建，谁都读不到、改不了、删不掉；只有管理权限能读；删除参与者脚本一并删除；不进盲法导出。
- 测试：规则 12 项、删除脚本、盲法导出、Dart 5 项（含「每个聊天页都把原话传进来」的检查）。决策草稿 0063。
- 还没做：读取／导出工具（给操纵检验编码和看板「查看對話」用），见 backlog。
## 2026-10-20 1020l 第一节 (4)：选了阿伯，回忆入口不再显示「珍」（分支 `claude/zealous-fermat-8rgqtg-avatar-1020l`，未开 PR，按修 bug 处理，不加开关）

- 结论：选了阿伯的老人，「傾偈」页「接著傾 · 同阿伯講舊時」卡片左边会看到一个大「珍」字。现在显示阿伯的头像图片；图片读不出来时显示「伯」。两组相同。
- 原因：这张卡片（`continue_chat_card.dart`）的头像不是图片，而是每位夥伴写死的一个字，阿珍／阿伯那一格固定是「珍」，不看老人的选择；旁边的名字是按选择算的，所以名字对、头像错。
- 改了什么：卡片头像改用共用头像组件 `AgentAvatar`（按 `ahJanAhBakVariant` 选图，三位都显示图片）；卡片的名字和头像在显示时读设定并跟着变。头像后备字改为那一位自己的字（阿伯 → 伯、阿珍 → 珍、小欣 → 小、通通 → 通），原来阿珍、阿伯都显示「阿」；夥伴介绍页大图的后备字同样处理。陪伴者页面顶栏（`CompanionTitle`）改为跟着设定变：在介绍页换了阿珍／阿伯，回到回忆页顶栏马上是新选的那位。转介卡（Hybrid 组小欣聊天里「搵 阿伯？」）的头像原来固定阿珍的图，改为按选择。
- 回忆页逐一查过：新版周页、旧版 A 组和 B 组页、「我嘅人生小篇章」列表（没有头像）和章节页、回忆首页（没有头像）、第一次见面的介绍卡；对话气泡都不画头像。这些地方本来就按选择取图，只有后备字和换选择后不刷新两个问题，已一并修。
- 同类但没改（列出待定）：引导页第一页「三位夥伴」一览在老人选之前固定写阿珍（名字和图一致）；几处按选择显示名字的文字（每周问卷、首页提示条、记忆页、评估页）只在打开页面时读一次，换选择后要重开页面才更新。危机页联络人头像取的是联络人名字的第一个字，与夥伴无关。
- 测试：新加 `test/reminiscence_avatar_1020l_test.dart`（阿伯／阿珍各一遍，三种构建都跑，已加进 `tool/ci_flutter_tests.sh` 两个 Phase B 列表）。截图在 `docs/dev-reports/1020l-shots/avatar/`（手机 360×800 字号 1.06、1.30，iPad 820×1180 字号 1.06）。
## 2026-10-20 1020l 第二节 (2)：iPad 上页面限宽 600、居中，手机不变（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-ipad-1020l`）

- 结论：iPad 上内容放在中间一栏，最阔 600，两边用 App 的底色；手机完全不变。新开关 `wideScreenFrameEnabled`，默认关。两组相同。
- 做法：只改一处。新文件 `lib/app/wide_screen_frame.dart`（`WideScreenFrame`），装在 `app.dart` 的 `MaterialApp.builder` 里、字号那一层下面，所有页面都经过它。条件：开关开、屏幕较短一边 ≥ 600、宽度 > 600。栏里的 MediaQuery 宽度报 600，按屏幕宽度排版的地方（聊天气泡等）当成 600 宽的设备；左右安全区减去两边空位，上下安全区和键盘高度不变。弹出框、底部弹出、提示条、底部分页按钮都在栏里。
- 手机为什么不变：手机较短一边都小于 600，横放也不会出这一栏；这时只多一个不画任何东西的 `KeyedSubtree`。它带 GlobalKey，iPad 分屏缩放、这一栏出现或消失时，打开着的页面不会跳回首页。
- 为什么加开关：PI 规则「新行为放在开关后」。开关只管 iPad，Junyu 在 iPad 真机看过再开；上线检查脚本 `tool/check_prelaunch_values.js` 已列出，期望值待定。
- 测试：`test/wide_screen_1020l_test.dart` 24 个，三种构建都跑（已加进 CI 两套 Phase B 清单）。手机 360×800、412×915（直放、横放，字號 1.06、1.30）整棵渲染树和「完全没有这一层」逐项一样；真 App（`MyApp`）手机上开关开、关画出来一样；iPad 820×1180、1180×820 内容 600 宽、居中，弹出框、提示条、底部弹出在栏里，键盘和安全区正确，分屏缩放不丢页面。`ui_text_scale_sweep_test.dart` 照旧通过。
- 截图 `docs/dev-reports/1020l-shots/ipad/`：iPad 直放、横放首页（开关关 / 开对比）和小欣聊天窗口；手机 360×800 字號 1.06、1.30 首页（和没有这一层逐个像素比对过）。生成脚本 `test_manual/wide_screen_shots_1020l_test.dart`。
- 没写决策记录：只是排版修正，不改研究设计，也不改两组的差别。
## 2026-10-20 1020l：首页开关核对、问卷一行改样子（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-home-1020l`）

- 结论：Junyu iPad 上看到的两件事（三位伙伴还在第一页；和小欣聊完邀请卡只在第二页）就是**第一页按「开关关着」建出来的旧版面**。开关开着时代码是对的：第一页没有伙伴，邀请卡两页都有（新测试 `test/home_flags_1020l_test.dart` 两组都证明了）。
- 第一页为什么会按「关」建：我们不看正式控制台（规则 2），可能是三种之一——(a) 控制台里 `homeLayoutV2Enabled` 当时是关的；(b) 开关是在 App 开着时才改的（App 回到前台不重读开关）；(c) 已经做完入门的帐号在新装的 App 第一次登入（例如新 iPad）：开机那次读开关会被拒（还没登入），登入后那次才读到，但第一页已经建好，一直停在旧版面，要完全关掉 App 再开才变；开机读开关超过 3 秒没回来也一样。(c) 已修：登入后那次读到的首页开关和建页时不同，四个分页马上重建（开关没变就不动）。(a)(b) 不用改代码。
- 在控制台改了开关之后：**要把 App 完全关掉（从多工画面向上扫走）再打开**；只回到桌面再回来不会重读开关。
- 问卷一行改成和 check-in 一行一样：一行粗体标题、一行小字、能撳的才有箭头。开放中的小字「{日期}截止」是新字（草稿 W5-2）；未开放的两行用原来 W4 的字。
- 第三节（10/19 第 37 条「做啲嘢」重排、四张大卡、第一页小行动一行）只估工时，不写代码。
## 2026-10-20 1020l 第一节 (2)(3)：小欣页提示移到顶部、签到选项按钮和五个表情按钮排整齐（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-siuyan-1020l`）

- 结论：小欣聊天页（开关 `checkInChatV2Enabled`）以前在底部弹出、盖住输入框的提示，都移到标题栏下面；签到的选项按钮一样宽、一样高。两组相同。开关关时不变。
- 移到顶部的：「今日傾到呢度」首次说明、中度安全提示、离线待发那一行、语音两条提示（语音开关关着）。前一页留下的底部小提示不再画在小欣页上（页面自带 `ScaffoldMessenger`）。没动的：首次见面介绍框、记忆开关询问框（都是要先点的对话框）、危机页（整页）、聊天里的支持句和其他卡片（本来就在对话里）。
- 中度安全提示：文字、三个选项、事件记录、时机都不变，只换位置，放在页顶时留白收紧一点（`DistressRouter.route` 新增可选参数 `showModerateInline`，`DistressModerateSheet` 新增可选 `onClose`；不传就是原来的底部弹出，一点不变）。签到时照旧等老人点选项才问下一题。检测规则没动。页面布局：底栏高度不变，消息列表至少留一块（160 px 或四分之一），提示区拿其余。360 宽手机最大字时三个选项和最新一句都看得到；320×700 这种很小的屏幕加最大字，「我冇事，繼續」要在提示区里往下滑（有滚动条），两个求助按钮仍看得到。
- 新组件：`lib/shared/widgets/top_notice_area.dart`（页顶提示区）、`lib/shared/widgets/equal_button_grid.dart`（等宽按钮格）。只有小欣页用。`session_close_button.dart`、`voice_input_button.dart`：页面有提示区才放顶部，否则照旧。
- 测试 `test/siu_yan_prompts_mood_1020l_test.dart`（量位置：在标题栏下、不压输入框、最新一句完整可见；按钮同宽同高、一行、居中），加进 CI 两个 Phase B 组。截图在 `docs/dev-reports/1020l-shots/siuyan/`。
- 五个表情的心情按钮（`MoodFacePicker`，`check_in_shared.dart`）也改用 `EqualButtonGrid`：同宽同高，表情和字居中，字一行（Junyu 说的「五个按钮同宽」应是开关关着时的旧签到页）。用在旧签到页 A／B、规则组回忆页、旧首页心情框，按修 bug 处理、不加开关，两组相同。截图 `mood_face_picker_*`。
- 中度提示的三个选项都点过测试（页顶和原来的底部弹出两种）：靜一靜开呼吸页、搵人傾记事件并开同一个求助页、我冇事，繼續收起；回来后聊天照常、签到接着问。代码改为先取 Navigator 再关提示，关掉后不再用已移除的 context。
## 2026-10-20 1020j 第二节：Android 固定签名钥匙（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-signing`）

- 原因：Build APK 的正式包一直用 CI 机器的调试钥匙签名。每台 CI 机器的调试钥匙都是新生成的，所以每个新包签名都不同，装新版本要先卸载、再登录（10/15 第 12 条 (4) 原定的正式签名没做成）。
- 改法：`build.gradle.kts` 有环境变量就用固定钥匙签。工作流从四个仓库 Secret 还原钥匙，缺了就让构建失败，不再退回随机钥匙。每次构建在运行摘要里打印证书 SHA-256；设了仓库变量 `ANDROID_SIGNING_SHA256`，不一致就失败。
- 不改 App 代码；版本号仍取 `pubspec.yaml`。Junyu 要做的一次性步骤见 `docs/release/android-signing.md`。

## 2026-10-20 1020i：Mac 本地测试脚本（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-mac-tests`）；本地只读看板先答四个问题

- 新加 `tool/run_local_tests_mac.sh`：在 Mac 上一行跑完 CI 的全部测试（`flutter analyze`、小讀本 HTML 检查、六套 Flutter 测试、Functions 单元测试、规则和模拟器测试、隐私脚本测试）。每步打印通过或失败，失败不中断，最后汇总和总用时；`--only` 只跑一部分。只连本机模拟器：开头发现指向正式项目的环境变量就停。说明在 `docs/release/local-tests-mac.md`。
- 不改 App 和 Functions 的行为；CI 照旧用 `tool/ci_flutter_tests.sh` 和 `tool/ci_backend_tests.sh`。
- 第二节本地只读看板：只回答 1020i 2.4 的四个问题，不写代码，等 Junyu 选定方案。

## 2026-10-20 1020h：急性中断后当天不再重开 check-in；「当天」用香港日期；登记表 C06 小篇章来源确认（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-1020h`，接冻结合并 #139）

- `siu_yan_chat_page.dart`：`_findResumable` 改为 `_todayStops`，一次读当天的 check-in 行，分出「标了误触、可续问」和「急性中断、没标误触」两种。后者和 `done` 一样进聊天（`_seedChatOpener`），不再 `_beginCheckIn`。不加开关，放在误触续问的同一条路上。
- `mood_recorder.dart`：`dateIsoFor` 改为香港日期（UTC+8），和 `functions/pi_alert.js hkDateKey`、`false_alarm.js` 一致（1020g 第二节 (2)）。
- 测试：`check_in_chat_v2_test.dart` 两组「没标误触再进 → 聊天开场、不新开一行」、「昨天中断 → 今天从 Q0」、香港日期边界；原有「标误触 → 续问」「第二天不续问」照旧通过。
- 登记表（仓库副本 `docs/spec/feature-registry.md`）v10.1：C06 写入回忆 v2 和小篇章的组间差异，状态改为已确认（Junyu 10/20）。

## 2026-10-20 冻结合并（1020g）：11 个草稿 PR 按 Fable 的顺序合成一条分支，加第一节七项修正（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-freeze`）

- 合并顺序：#134 → #127 → #128 → #131 → #133 → #132 → #135 → #137 → #136 → #130 → #138。冲突都是两边各加几行（开关表、测试清单、规则测试清单、`pubspec.yaml` 资源目录、提示词清单），两边都留；手工合并两处：`functions/index.js`（#137 的小篇章触发器放在 #132 的 19:00 推送前面，丢掉 #137 带进来的旧 `dailyMoodReminder`）、`chat_session_recorder.dart`（`entrySurface` 和回忆 v2 的两个字段都写进会话行）；`ops_dashboard.js` 用 #130 的 `LAST_USE_SCAN` 加 #137 的小篇章查询。
- 1020g 第一节：(1) `reminiscence_chapter_test.js` 安静时段断言改 `quiet_hours`（#127 后安静时段对所有人固定开）；(2) `tool/export_spec_inputs.py` 重算提示词包 hash；(3) 上线检查脚本删重复的 `weeklyReminderV2Enabled`、补五个开关、`researcherIntakeGateEnabled` 期望 true；(4) `siu_yan_chat_page.dart` 后备提示词改「電腦程式夥伴」；(5) `reminiscence_chapter.js` 不再读 `quietTodayActivatedAt`；(6) `pending_prompts_banner.dart` PGIC 卡副标题和两处「companion」；(7) `today_todo_rows.dart` 用 `openBundlesAt(..., week4RecordedOn)` 取第一个未完成的问卷包（新测试 `test/questionnaire_row_1020g_test.dart`）。
- 决策记录编号：0051 RCT cohort 和序列 v2、0052 check-in 聊天窗口、0053 键盘顶栏、0054 首页两页和心情一行、0055 推送和每周窗口、0056 小讀本、0057 回忆 v2（App）、0058 小篇章生成、0059 行动计划、0060 研究员讲解闸门；顺手把指向 0043–0050 的旧 `NNNN-` 链接改成正式编号。

## 2026-10-20 dev-tasks-1020d 第一节：两个 bug（回忆页提示、App 端提示词「AI 機械人」）

- 1020d 第三版存进 `docs/dev-tasks/dev-tasks-1020d.md`。第一节两个 bug 不设开关，单独一个小 PR，从 main 开。
- 回忆页两组的输入框提示改为「記得幾多寫幾多。」，英文提示同步去掉讲话的半句。
- App 端 8 处中文提示词「AI 機械人」改为「電腦程式夥伴」，每处加一条「唔好用「AI」「模型」「機械人」呢啲字」，和 #118 的服务器提示词、#126 的建议页新版一致。
- 回忆 v2（第二节起）另由两个分支做（App、服务器），合在一个 PR。
- 1020e：#134 加两处语音字样（旧小欣签到开场「寫幾句都得。」；旧小欣签到、通通、反思对话输入框「寫低你想講嘅嘢。」）。
- 1020e 一.(9)「决策编号由开发编」：main 上 8 份 NNNN 草稿编为 0043–0050（文件名只把 NNNN 换成号码，英文名不变，旧文档里的 `NNNN-<名字>` 仍按名字找得到）：0043 clear-raw-output-on-delete、0044 companion-prompts-v2-tone-slot、0045 five-font-levels、0046 hide-transcript-retention-switch、0047 home-mood-entry-and-suggestions-profile、0048 home-safety-card-simplified、0049 tester-arm-self-switch、0050 tester-tools-unlock-without-pin。各 PR 里的草稿从 0051 起，合并前改名。
## 2026-10-20 第 4 批按 dev-tasks-1020e 改：每周问卷整日窗口和 10:00 推送、W4 录入即关、P1／P2 新规则（同一 PR 草稿 #132）

- 1020e 回复了第 4 批的待定项。每周问卷：第 1–3 周第 7 天 00:00 至第 9 天 23:59；第 4 周第 26 天 00:00 至评估员录入 W4 那天结束、最晚第 42 天；推送都在 10:00（预告、开放、提醒），电邮第 9、16、23、28 天。第 5–7 周不变。
- 窗口 App 和服务器一起改，都在 `weeklyReminderV2Enabled` 后：服务器 `weekly_schedule.js` `windowFor`／`week4CloseV2`／`v2StepsFor`，App `weekly_schedule.dart` 同一算法、同一张表（`v2` 节）；App 加 `RemoteFeatureFlags.weeklyReminderV2Enabled`。
- App 要知道 W4 关了：新字段 `users/{uid}.w4RecordedOn`（`assessor.js` 第一次录入 W4 时写；规则只许服务器写；`UserProfile` 读）。W4 最长开到第 42 天，会和 W5、W6 重叠，首页卡改为取第一个没做完的（`openBundlesAt`、`firstNotDone`）。
- 各部分记录开关开时多盖 `outsideWindow`；先存草稿后提交的，提交时补盖一次。缺失标记按新窗口。
- P1 跳过当天已做 check-in 的人；P2 每周问卷推送日照发；check-in 因危机中断算做过，`falseAlarm: true`（第 2 批的「誤觸」标记）不算。
- 测试员工具测试推送按钮改名，加 P2 和每周问卷新推送的按钮。
- 测试：`pushes_email_1020_emulator_test.js` 13 项、`weekly_schedule_test.js` 和 `test/weekly_schedule_test.dart` 加 v2 共用表、规则测试加 `w4RecordedOn`、`outsideWindow`；整套后端和 Flutter 六套测试通过。

## 2026-10-20 dev-tasks-1020 第 4 批：08:30／19:00 check-in 推送、每周问卷三天提醒、第三天电邮（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-batch4`）

- 从第 1 批分支（381f9a5）开。只改服务器和文档，App 不用改。报告：`docs/dev-reports/T55-T56-batch4-20261020.md`。
- F (5)：`functions/daily_checkin_push.js`。`checkInChatV2Enabled` 开时新定时函数 `dailyCheckInMorningPush`（08:30）按人发 P1；`dailyMoodReminder` 改每天 19:00，按人发 P2（当天没做完 check-in、当天又没有每周问卷推送的人）。做完的判断认三样：旧表单行、第 2 批 `chat_v2` 行（`completed` 或危机中断）、`check_in_submitted` 事件。关时照旧周一至六广播。
- G (1)：`weekly_schedule.js` 的 `dispatchWeeklyBundles` 在 `weeklyReminderV2Enabled` 开时对 W1–W4 用新文字、第二／三天（第 4 周关闭日前一天／当天）20:00 只推未完成者；第 4 周关闭日读 `weekly_status.w4VisitDate`。第 5–7 周不变。
- G (3)：`functions/weekly_email.js` + 定时函数 `weeklyIncompleteEmail`（10:00），复用 `pi_alert.js` 的收件人和发信；`meta/weekly_email_test.send` 触发测试邮件（`onWeeklyEmailTestRequested`）。
- 文字草稿 `functions/push_copy.js` ＝ `docs/spec/copy/push-and-email-1020.md`（`push_copy_test.js` 逐字比对）。`sendTestPush` 开关开时「每日心情提醒」发 P1、「每週問卷提醒」发 W1，供手机测试。
- 测试：`pushes_email_1020_emulator_test.js` 11 项（模拟时钟）；整套后端测试通过。决策草稿 `0055-daily-and-weekly-pushes-1020.md`。
- 发现：第 1–3 周 W2／W3 文字比实际窗口早一天；W4 面访日期只能事后录入、App 读不到，面访延后其实延不了。都列给 Junyu 定。
## 2026-10-20 dev-tasks-1020e 二.13：「想重新聯絡嘅人」只传勾了「可以講」的人

- 1020e 是 Junyu 对第 1 至 4 批和 #129–#131、#134 待定事项的回复。各项按 PR 分派；本段只记 #127 里这一项。
- `researcher_intake.intakeFactsFor`：「想重新聯絡嘅人」和「重要嘅人」一样只取 `share` 为真的人；建议页同样过滤。旧资料没有 `share`，当作不传。
- 新脚本 `tool/rewrite_reconnect_memory.js`：按入组文档重新写录入事实（和重新录入同一个函数），只动录入来的事实；默认预演，不打名字。emulator 测试 3 项。
- 测试改动：`researcher_intake_emulator_test` 的合成资料加一个不分享的人；`suggestions_use_profile_test` 改为只传分享的人。

## 2026-10-20 dev-tasks-1020c 第一节：#126 两个开关定开，开之前修两处

- Junyu 定开 `appFontScaleOnlyEnabled`、`suggestionsUseProfileEnabled`（10/20 手机测试过后、10/21 第一位 RCT- 登记前）。开关表、`tool/check_prelaunch_values.js` 改为期望 true。
- 查代码时发现：建议页带小欣的 agentId 请求记忆，服务器把它当一次新聊天，会放进到期「跟进」并标成已问，小欣之后就不会问。改为 `m6_suggestions` 和问候一样不放跟进（`memory.js`），加 emulator 测试（先确认改前失败）。
- 字号开关一开只看 App 字号，手机字号大的人会从 1.30 变回 1.06。改为开关打开后第一次按当时大小取不比它小的一档，只做一次（`app_settings.dart`、`app.dart`），加单元测试。
- 新测试 `test/suggestions_use_profile_test.dart`：Hybrid 开关开时传哪些字段；规则组开或关一字不差、零 LLM 调用。
- 报告第十节重写：逐项列出传给 DeepSeek 的内容和是否本来就在记忆里；「想重新聯絡嘅人」记忆和建议页都不看「可以讲」，待 Junyu 定；登记表两行草稿。

## 2026-10-19 dev-tasks-1020b：C 定案做完（RCT- 标 rct、一份 cohort 清单、序列 v2）、给 Qingyang 的上传步骤、#126 开关、语音次数（#127）

- 1020b 存进 `docs/dev-tasks/`。#127 先合了最新 main（#126）。
- C：`study_period.js` 加 RCT-（cohort `rct`，序列 v2），PB- 标 `retired`（新登记拒，旧账号照认）；`ENROLLED_COHORTS`、`PHASE_B_COHORTS` 两份清单；App `lib/core/study/cohorts.dart`；规则 `enrolledCohort()`。`weekly_schedule`、`blinding`、`djg_w2`、`tester_arm`、`analysis_export`、App `isEnrolled`／周程改读清单。防漏测试 `cohort_list_guard_test.js`。
- 序列版本：`sequence_upload.js` 重写（版本 v2、≥ 80、v2 已分配拒、同种子拒、`sequence_versions/` 记 v1 停用和 v2 使用中；读 v1 用字段过滤，不读组别）；`randomization.enrol` 从 `v2_low`／`v2_high` 取组，登记和日志加 `sequenceVersion`、`allocatedArm`；`tool/randomization_sequence.js` 要 `--version=v2`、默认 80；`check_prelaunch_values.js` 列 v1／v2 长度、已用、指纹。
- 测试：`rct_cohort_emulator_test.js`（非测试员 RCT- 和 PB- 走完全周程和三个导出）；两个分配测试改 RCT-／v2；规则测试加 rct 和 `sequence_versions`。盲法导出没有 cohort 列（检查脚本禁止），靠编号前缀分。W8（T35）还没做，第 56 天只核对周数。
- 给 Qingyang 的步骤：`docs/release/sequence-v2-upload-20261020.md`，接 prelaunch-checklist G 节。开发只写不跑。
- #126 四个开关进开关表（10/21 false），上线检查期望「没有或 false」。两个开关的四个问题答在批 1 报告第十节；「想重新聯絡嘅人」传给 DeepSeek 时不看 `share`，待 Junyu 定。
- 只读脚本加自 10/15 起每人语音转写次数（只计数）。
- 决策记录 `0051-rct-cohort-and-sequence-v2.md`（已采纳），0037 顶上标部分取代。
- 第 2 批（小欣页）同时开工，在另一个分支。

## 2026-10-19 dev-tasks-1020 第 1 批：设定页、安静时段固定开、今日休息取消、语音隐藏、导出加列、只读核对脚本；C 的序列版本方案待批（PR 草稿，分支 `claude/zealous-fermat-8rgqtg`）

- #125 合并后分支从 main 重开（快进），按「一批一个 PR」做第 1 批。dev-tasks-1020 存进 `docs/dev-tasks/`，T 号 T50–T60。
- H：`settings_page.dart` 去掉「通知」节，新 `MySettingsPage`（我的設定 → 顯示 → 高對比）；`quiet_hours.js` 不再看 `quietHoursEnabled`；`reminders.js`、`weeklyLonelinessProbe`、App `reminder_service.dart` 不再看 `quietTodayActivatedAt`。三个 emulator 测试按新规则改。
- I：麦克风本来就全经 `VoiceInputButton` 一个开关，代码不用改；要在控制台关开关。`check_prelaunch_values.js` 期望值改成 10/21 的。
- J：研究员录入页两句说明按代码改（记忆和鼓励方式下一句就用到；兴趣和唔想提起嘅话题要重开 App）。
- C(5)：`analysis_export.js` 加五列，`delete_participant.js` 留下的分配记录加 `sequenceVersion`；合成数据编号改 `RCT-S…`。
- C(2) 方案（v2 另存为 `v2_low`/`v2_high`、`sequence_versions/` 记停用、cohort 建议仍用 `phase_b` 加 `analysisSet`）写在 `docs/dev-reports/T50-T60-batch1-20261019.md`，等 Junyu 批。
- 只读核对：`tool/readonly_check_1020.js`（保留开关、行动计划推送、今日休息、过期未展示的 Brief PR）。开发没有生产权限，要 Junyu 跑。代码能答的两题已答：保留开关关掉时 `turns`／`sessions` 照写（本来无原文）；服务器不把 `shortTermBuffer` 给聊天模型。
- 顺带：#123 的冲突已由另一窗口合 main 解决，本地扫描确认无误。
## 2026-10-20 1020e 二.7：行动计划少填、可改可删；Hybrid 计划用上小欣记忆（分支 `claude/zealous-fermat-8rgqtg-actionplan-impl`，接键盘分支，PR 草稿）

- 结论：Junyu 10/20 定两样都在冻结前做（现状报告 PR #129）。两个开关都默认关。`actionPlanSimplifiedEnabled`：两组只必填「做咩」「幾時」，从建议进去「做咩」已填好可改；「等住跟進」可以改「做咩」「幾時」、可以删（软删除，未发提醒一并删，服务器也不推）。`actionPlanMemoryEnabled`：Hybrid 组计划页两次模型调用带 `agentId: siu_yan`，服务器加小欣记忆，不放、不用掉她的 follow-up。规则组仍零模型调用。
- 只加新字段（`planFormVersion`、`source`、`seedAction`、`original`、`editCount`、`lastEditedAt`、`editLog`、`deletedAt`、`deletedFrom`）和三个事件；改「幾時」不移动提醒；不写 `scheduledFor`。`memory.js` 里第 1 批对 `m6_suggestions` 的几行一字不差照抄，m7 的排除另写一处，两分支谁先合都不冲突。
- 报告（截图、真机步骤、要 Junyu 定的事）：`docs/dev-reports/action-plan-v2-20261020.md`；截图 `docs/dev-reports/action-plan-v2-shots/`；决策草稿 `docs/decisions/0059-action-plan-simplified.md`；测试 `test/action_plan_simplified_test.dart`（加进 CI 两套 Phase B）和 Functions 三个测试文件的新用例。
## 2026-10-20 1020d 回忆 v2（App 部分）：两组同一份开放问题、小篇章和评分、离开按钮改名（分支 `claude/zealous-fermat-8rgqtg-reminiscence-app`，接键盘分支，PR 草稿）

- 结论：回忆页改成两组同一页、同一份问题稿，差别只在每题答完之后（Hybrid 组模型追问一条再回一句，规则组固定句、零 LLM）。每周答完整理成小篇章，两组同一个画面，评三题，可改。全部在开关 `reminiscenceV2Enabled` 后面，默认关。离开按钮改名在另一个开关 `leaveButtonV2Enabled` 后面，默认关。
- 文字：`docs/spec/copy/reminiscence-v2.md`（开场、32 题、固定句、小标题、评分、按钮），代码 `reminiscence_v2_copy.dart` 两组读同一份，测试逐字比对。全部草稿。
- 数据：每周 `reminiscence_v2/week_{N}`（进度和逐句对话；同意关时原话只在手机）；小篇章 `reminiscence_chapters/week_{N}`（和服务器分支约定的字段）；评分 `reminiscence_chapter_ratings`；会话 `reminiscenceQuestionsAnswered`。80 字小结照旧。
- 服务器部分（小篇章 Cloud Function、`ah_jan_ah_bak.v3` 提示词、推送、Firestore 规则）由另一个开发窗口做，两边按报告里的约定拼接。第一节的两个 bug 不在这个分支。
- 报告、截图（测试渲染，Hybrid 组的回应是假模型的句子）和真机步骤：`docs/dev-reports/reminiscence-v2-app-20261020.md`。测试 `test/reminiscence_v2_test.dart`（加进 CI「phase B arm gating」）、`test/reminiscence_v2_copy_test.dart`。
- 待 Junyu：全部草稿文字；有效会话 3 题；规则组整理好不推送；`moderate_review` 不停题、规则组用 Z5；第 8 题后规则组不出固定句；同意关时小篇章请求仍带对话；看过旧说明的人再看一次新说明；决策编号（草稿 `0057-reminiscence-v2-app.md`）。
## 2026-10-20 1020d 回忆 v2 服务器端：阿珍／阿伯提示词 v3、小篇章生成、规则、导出和看板（分支 `claude/zealous-fermat-8rgqtg-reminiscence-server`，未推送、未开 PR）

- 结论：开关 `reminiscenceV2Enabled`（默认关）开时，新回忆页发 `ah_jan_ah_bak_v3`，模型每题问一条具体追问、再回一两句不提问；老人撳「完成今個禮拜」后，Hybrid 组的小篇章由服务器触发器 `onReminiscenceChapterWritten` 生成（Pro 思考写稿 → Flash 核对 → 最多改两轮 → 删仍无出处的句子），规则组不调任何模型。App 那一半由另一个窗口做，约定写在报告第 6 节。
- 真实模型名 10/19 核对过：`deepseek-flash`、`deepseek-v4-pro` 都在 DeepSeek `/models` 里。
- 合成老人试运行改了提示词四次：追问漏问、离世仍追问、Flash 把粤语词当「太口语」、改写把老人原话改成普通话、Pro 偶尔交空稿；定稿后一般追问 29/32 有一条问题、回应 33/34 不提问、离世只承认、没假设香港；三篇小篇章逐句都有出处，植入的「五歲」被 Flash 拦下并删去。代码另加两道保护（无口语语法字的「太口语」剔走、空稿重试）。
- 规则、过程／分析导出、盲法导出清单、运营看板计数一并做了；看板页面显示要改 `lib/`，留给 App 窗口。
- 全部后端测试（换端口跑）和钉版本 Flutter 测试通过。报告 `docs/dev-reports/reminiscence-v2-server-20261020.md`；决策草稿 `0058-reminiscence-chapter-generation.md`。
- 待 Junyu：三份提示词措辞、推送文字、「太口语」代码剔除、核对失败照交、评分算过程还是结局等（报告第 11 节）。

## 2026-10-20 1020c 第二项：键盘遮挡，打字时顶栏缩成一行（分支 `claude/zealous-fermat-8rgqtg-keyboard`，接第 2 批，PR 草稿）

- 结论：Junyu 报告老人打字时顶栏不让位、对话看不全，两组一样。量过：360×640、字体 1.30、键盘 300 时，聊天区只剩 99–155 像素。新开关 `keyboardCompactHeaderEnabled`（默认关）开时，键盘打开顶栏 72 → 48（「今日傾到呢度」／返回键原样保留），收键盘恢复；聊天页跳回最新一条；通通文章问答的「根據文章」条一起收起。每页多 24 像素（文章问答多 80）。没有新文字。
- 共用写法 `lib/shared/widgets/keyboard_compact.dart`（`KeyboardCompact.active`、`keyboardCompactAppBar`、`KeyboardScrollToLatest`）；`companionAppBar` 改用它，所以陪伴者页面两组一起变；表格页（望一望、行动计划两组、行动跟进、回忆总结修改、回忆详情）各改一行。
- 页面清单、量出来的数字、截图（测试渲染，不是真机）和真机步骤：`docs/dev-reports/keyboard-20261020.md`。测试 `test/keyboard_compact_header_test.dart`（加进 CI 两套 Phase B）。
- 待 Junyu：开不开开关、缩小后标题要不要一句新话、表格页要不要也缩、决策编号（草稿 `0053-keyboard-compact-header.md`）。另发现「個人資料 → 修改」弹出框键盘一出就溢出（另一个问题，没改）。
- 10/20 跟进（1020e 一.(11)）：Junyu 接受以上做法，开关真机测过再开。同一 PR 修弹出框（不放开关，两组一样）：`personalization_page.dart` 四格放进 `SingleChildScrollView`（`Flexible`），「儲存」固定在下面，`useSafeArea: true`；新测试 `test/profile_editor_keyboard_test.dart`（360×640、1.30、键盘 300：无溢出、「儲存」按得到；旧代码 5 个全失败）。修前修后截图在同一截图夹。
## 2026-10-20 1020 第 3 批跟进 1020e：check-in 一行做完可撳、问卷一行按日子写、表情字统一、心情图读 daily_mood、会话记 entrySurface（同一分支，PR #133 草稿）

- 结论：Junyu 10/20 对第 3 批的回复（1020e 一.(6)(9)、二.1 (5)、2 (4)、11、12）全部做完，都在原来两个开关后面。第 6 项（第 2 批改 v3 后重做 v4）等协调窗口通知。
- `entrySurface`：新文件 `lib/core/session/session_entry_surface.dart`；`HomeSurfaceScope`（`home_v2_scope.dart`）包住第一、二页，从那里打开的页面里开始的会话（聊天和工具）写 `sessions.entrySurface`；只在 `homeLayoutV2Enabled` 开时写；`functions/process_export.js` 导出。
- 问卷一行：`QuestionnaireOpenState` 从排程给的窗口算（最后一天／前一天／更早；第 4 周按 `WeeklyCloseRule.week4`），不写死第几天。
- 心情图：`ProgressRepository.lastMoodPerDay`、`progress_page.dart` 的七格图；`facts_recap_row.dart` 在两页版面下进「你嘅一個禮拜」。
- 测试、截图、报告第 0 节已更新；Flutter 六套、相关 Functions 测试通过。

## 2026-10-20 1020 第 3 批（D、E、G (2)）：首页分两页、心情一行不弹窗、M7／M8 进小欣聊天、问卷一行、做啲嘢工具图（分支 `claude/zealous-fermat-8rgqtg-batch3`，PR 草稿）

- 结论：两个新开关 `homeLayoutV2Enabled`、`moodRowV2Enabled` 默认关，关时一切照旧。开时第一页「睇今日」只放今天的事（问候、心情一行、「今日要做嘅事」、「去搵人傾」、本周小结、危机卡），第二页「搵人傾」放邀请卡、继续聊天卡、第一周提示和三位伙伴；心情一行没有任何弹窗；M7／M8 进小欣聊天，规则组用 O／C 模板开场（零 LLM），Hybrid 组 LLM 开场（新提示词 `siu_yan.v4`）。
- 第一页：`today_page.dart` 按开关建新版面；新文件 `today_todo_rows.dart`（check-in 一行并入三天提醒、问卷一行 W4／W5、「去搵人傾」）、`home_v2_scope.dart`（刷新信号和测试接口）；`lib/app/home_tab_switcher.dart` 让大按钮切到第二个 tab。`PendingPromptsBanner` 多一个 `hideWeeklyBundle`，问卷一行出现时不再出每周问卷卡。
- 心情一行：`mood_row_v2.dart`（状态 M1–M8），文字 `mood_row_copy.dart`、`home_v2_copy.dart`（照 `docs/spec/copy/home-v2.md`），存储 `mood_row_store.dart`（`daily_mood` 照旧经 `MoodRecorder`；「遲啲先答」和 M7 用过的日子存手机本地）。`greeting_hero.dart` 开关开时用新一行，旧表情板、小条、对话框不建。
- 1020b 第二节：`RemoteFeatureFlags.homeMoodOpensCheckInActive`（心情一行开时恒为假）、`briefPrHomeBannerActive`（新版面开时恒为假）、`dailyMoodPopupActive`；测试覆盖。
- 小欣聊天窗口：新参数 `moodEntry`（`MoodChatEntry`），进来直接是聊天；`activePromptKey` 在心情一行开时用 `siu_yan_v4`。新提示词 `siu_yan.v4.txt` = v3 + 「從首頁心情入嚟（開場）」一节，`prompt_registry.js`、`build_info.g.dart`、指纹测试都加上；v3 不动。
- 做啲嘢：`assets/tools/` 四张定稿图，`MeListItem` 多 `image`、`tileColor`，开关开时用。
- 测试：`test/home_v2_test.dart`、`test/mood_row_v2_test.dart`（加进 CI 两套 Phase B 构建）、`final_copy_test.dart` 加 `home-v2.md`、文字扫描加五个流程、Functions 加 `prompt_siu_yan_v4_test.js`、`prompt_siu_yan_v4_emulator_test.js`。报告 `docs/dev-reports/T53-T54-batch3-20261020.md`，截图 `docs/dev-reports/batch3-20261020-shots/`。
- 待 Junyu：文字定稿（5.1、5.2、5.5 和 D1–D4）、v4 新一节措辞、表情下的字要不要改成 Q1 的说法、W5 天数算法、决策编号（草稿 `0054-home-two-pages-mood-row.md`）。
## 2026-10-19 第 2 批跟进（1020e 二.5、二.8、二.9、二.10、二.12；PR #128）

- 结论：Hybrid 组 Q4 唔講住改叫模型（一句、不建议、不提问，失败回落 R4b）；规则组中度复核用 SN；check-in 因急性停下后，研究员标「誤觸」，老人当天可从停下那题接着做；Q1 按钮由低到高；输入框提示只讲打字。
- 提示词：`siu_yan.v3.txt` 原地加 `[簽到·唔講住]` 一条（v3 从未合并或部署，属 PR 内修改）；`build_info.g.dart` 重新生成。
- 新函数 `markSafetyFalseAlarm`（`functions/false_alarm.js`，只认 `unblinded`，开关 `safetyFalseAlarmMarkEnabled`）：在 `safety_events`、`pi_alerts` 和当天停下的 `check_in_responses` 行写 `falseAlarm`、`markedBy`、`markedAt`，记 `alert_audit_log`。`firestore.rules`：这三个字段客户端不能写（安全事件和 check-in 行）。
- App：告警列表加「標記誤觸」（确认框）；小欣窗口开门时读当天的 check-in 行，有已标误触、未完成、未续过的停止行就从 `stopped_at` 那题续问，另存新行 `resumed_from`。
- 导出和看板：过程导出、盲法导出、分析导出加 `falseAlarm`、`markedAt`；运营看板安全事件多一个「誤觸」计数。
- 测试：`check_in_chat_v2_test.dart` 加 19 条（唔講住调模型和回落、中度复核 SN、续问两组、隔天不续、未标不续、只续一次、后台按钮）；`false_alarm_emulator_test.js`；规则测试；过程导出和运营看板模拟器测试加断言。

## 2026-10-19 1020 第 2 批（A、F (1)–(4)、(6)）：小欣页一个聊天窗口，check-in 对话化，规则组小欣聊天（分支 `claude/zealous-fermat-8rgqtg-batch2`，PR #128 草稿）

- 结论：开关 `checkInChatV2Enabled` 开时，两组撳小欣都进同一个聊天窗口；当天未做 check-in 就自动按 Q0–Q6 一问一答，问题和按钮两组一样，不由 LLM 写；规则组回应全部来自模板（零 LLM 调用），Hybrid 组两句回应由 LLM 写。开关关时旧页面一字不变。
- 新页 `siu_yan_chat_page.dart`；文字 `check_in_chat_copy.dart`（照 `docs/spec/copy/check-in-chat.md`）；规则组聊天池 `siu_yan_rule_chat_pool.dart`；记录 `check_in_response_store.dart`。`CheckInPage` 按开关选新页或旧 `ArmGate`。
- F (6)：`rule-templates.md` 的 X1–X5 换成 5.4（按 Q1 尋日整體分档）；旧 10/10 文字移到文末，只给开关关时的旧表单用（代码 `RuleReplyPool.entries` 不动，新文字在 `checkInChatEntries`）。
- 提示词：新文件 `siu_yan.v3.txt`（= v2 + 「每日 check-in（App 對話形式）」一节），key `siu_yan_v3` 只由新窗口发；`siu_yan_v1` 仍是 v2。`build_info.g.dart` 重新生成。
- A：(1) 新窗口里规则组模板不再看编译开关 `RULE_TEMPLATE_REPLIES`，一定出现；(2) v2 下 Brief PR 只在列表页出卡，两组的问卷都有「唔評住」（测试覆盖），签到后不弹问卷；(3) 通通规则组照旧由回应池回复（`tung_tung_arm_b_test.dart` 覆盖）；(4) 规则组小欣聊天新建。
- 会话：`ChatSessionRecorder.markCheckInCompleted()` / `SessionTally.checkInCompleted`（只在为 true 时写进 `sessions`），`SessionRules.isValid` 把答完的 check-in 当有效。
- 测试：`test/check_in_chat_v2_test.dart`（加进 CI 的 Phase B 一套）、`final_copy_test.dart` 加 check-in 文字和旧 X、文字扫描加新窗口一个流程、Functions 加 `prompt_siu_yan_v3_test.js` 和 `prompt_siu_yan_v3_emulator_test.js`。报告 `docs/dev-reports/T50-T55-batch2-20261019.md`，截图在 `docs/dev-reports/batch2-20261019-shots/`。
- 待 Junyu：文字定稿、v3 提示词措辞、Hybrid 唔講住用 R4b、acute 后停止 check-in、决策编号（草稿 `0052-check-in-chat-v2.md`）。
## 2026-10-20 研究员讲解闸门（1020e 第二节第 14 条；PR 草稿，分支 `claude/zealous-fermat-8rgqtg-intake-gate`）

- 新开关 `researcherIntakeGateEnabled`（默认关）。`ConsentGate` 把两种入组问卷页（`IntakeShortPage`、`IntakePeoplePage`）包在 `ResearcherIntakeGate` 里：开着、帐号没解锁、也没做完引导（T37 规则，`needsAgentOnboarding(fixOn: true)`）时显示等候页，正中一格（九宫格中间）2 秒内点 3 下解锁，写 `users/{uid}.intakeGateUnlockedAt`（服务器时间）。两组同一页。
- 开关读取：`RemoteFeatureFlags.lastKnown`（最后一次真正读到的值；一次都没读到为 null）。为 null 时先「等一陣…」、后台重读（`load(timeout:)` 6–20 秒），8 秒后显示等候页（不跳过、可放行），读到关自动进问卷；`RemoteFeatureFlags.reads` 计数让 `ConsentGate` 重读后重新决定。
- `firestore.rules`：这个字段老人只能写一次、只能是服务器时间。新测试 `test/researcher_intake_gate_test.dart`（42 项，三种构建）、`test/rules/intake_gate_rules.test.js`（10 项）。报告 `docs/dev-reports/intake-gate-20261020.md`，决策草稿 `docs/decisions/0060-researcher-intake-gate.md`。
- 待 Junyu：等候页文字、位置（「開始之前」前还是后）、点击范围、读不到时宁可等、开关在第一位 `PB-` 前定好、W0 步骤加一句、决策编号。
## 2026-10-20 1020c「讀少少」小讀本（PR #130 草稿，分支 `claude/zealous-fermat-8rgqtg-readers`）

- 先评估（`docs/dev-reports/webview-eval-20261020.md`）：官方 `webview_flutter` 4.13.1 能装进 Flutter 3.35.3，系统版本不用改，包约大 1 MB；再写决策草稿 `docs/decisions/0056-html-readers-webview.md`，再写代码。
- 开关 `htmlReadersEnabled` 默认关；`assets/readers/manifest.json` 先是 `[]`。阅读页用 `loadHtmlString`，App 加 CSP、禁缩放 viewport、`--fs`、读节脚本；只放行首次载入和三个 `peizhu://cta/…`；WebView 放在 `ReaderSurface` 接口后，测试用替身。
- 「問下通通」只 Hybrid（C08），沿用通通文章模式，内容用 `<id>.txt`，前面那段说明是读本专用草稿（电脑程式伙伴写法）；规则组用会报错的假模型测过，没有任何调用。
- 使用事件 `reader_open/section/cta/close` 进 `usage_events`（规则白名单、服务器盖章；运营看板前台分钟只算前台／后台）。检查脚本 `tool/check_reader_html.js` 进 CI。测试单元只在 `READER_TEST_UNIT` 构建里，已验证正式构建里没有。
- 这台机器编不了 APK 和 iOS 包（连不上 Google 下载站、没有 Mac）：合并前 Junyu 跑 Build APK 和 Codemagic，两台手机按报告第 10 节测。报告：`docs/dev-reports/readers-20261020.md`。
## 2026-10-20 1020f 第一节：量表文字改回已批问卷包（PR 草稿，分支 `claude/zealous-fermat-8rgqtg-1020f`，从 `main` 开）

- 依据 decisions-log 10/20 第 48 至 50 条和已批问卷包（7/17 提交版）附录 B.3、B.5。按修 bug 处理，两组相同，不加开关。
- `pgic_page.dart`：题干、七个选项照 B.5；标题「同開始用嗰時比較」。`brief_pr_flow_page.dart`、`brief_pr_page.dart`：四题照 B.3，每题自己的两端和中点文字；一题一屏页顶「今次傾偈：〈名字〉」。`weekly_pr_response.dart`：12 题「頭先」→「呢個禮拜」。`check_in_shared.dart`（`MoodFace.label`）、`app_mood_encoding.dart`（图例）：同一套五个字。`weekly_bundle_flow_page.dart`：DJG、S12 页标题用部分名；`weekly_pr_page.dart`、`pgic_page.dart` 标题同样改。
- 只读核对（1020f 第一节第 6 项）：小篇章两次模型调用前的文字都过 `stripPII`（#137 `reminiscence_chapter.js` `normaliseInput`，`index.js` 传入）；「改一改」两组都走 `saveChapterEdit` → 共享安全检测（输入点 `reminiscence_summary_edit`）；后备收件人字段是 `meta/alert_config.backupEmail`，生产值由 Junyu 用 `tool/check_prelaunch_values.js` 查（脚本已期望「没有」）。
- `tool/check_prelaunch_values.js` 加 1020d、1020e 的七个新开关，期望值 10/20 晚由 Junyu 定（先只显示）。
- 新测试 `test/instrument_wording_1020f_test.dart`；截图 `docs/dev-reports/1020f-shots/`。
- Junyu 10/20 追加（同一 PR）：测试员工具「反饋／問卷」的 PGIC 一格改为「同開始用嗰時比較／同開始用之前比，孤獨感有冇變？」；「預覽量表」在 Phase B 构建里不再显示 Phase A 的「DJG-ES（第 2 週，6 題）」，只留「DJG W2（Phase B）」。测试 `test/tester_tools_1020f_test.dart`（两种构建）。Brief PR 一题一屏页顶「今次傾偈：〈陪伴者〉」Junyu 已定。

## 2026-10-19 W0 现场第三批（Junyu 定）：只认 App 字號、Brief PR 卡上首页、记忆页分组、资料卡和热线卡缩小（PR 草稿，分支 `feat/1019-ui-round3`，接 #122）

- 两个开关默认关：`appFontScaleOnlyEnabled`（`app.dart` 只用 `settings.fontScale`，不乘系统 textScaler）、`briefPrHomeBannerEnabled`（`today_page.dart` 问候语下面放同一个 `BriefPrCardHost`，调度规则不变）。
- 记忆页：`MemoryItem` 多 `category`（事实的服务器类目）；页面按类目和日期用 `ExpansionTile` 分组，页顶汇总一句。类目中文名照 `functions/memory.js` 的注释，记 S20 待产品窗口核。
- 资料卡 `_ProfileCard`：名字 headlineSmall、电邮 bodySmall、緊急聯絡 `ExpansionTile`。`safety_footer_card.dart` 的缩小在并入 main 时放弃，改用 #125 的两部分新卡。
- UI 扫描加「我記得嘅嘢（分組）」流程（假的 `MemoryV1Service` 喂合成条目）。

## 2026-10-19 W0 现场三件（Junyu 定）：首页表情直进签到页、建议页用入组资料、语音模型可切 chirp_3（PR 草稿，分支 `feat/1019-home-mood-suggestions-chirp3`，接 `fix/1019-field-issues`）

- 两个新开关都默认关：`homeMoodOpensCheckInEnabled`（首页第一次按表情直接进签到页，两组；规则组表格页新增 `initialMoodValue`，同一张脸不重复写 daily_mood）、`suggestionsUseProfileEnabled`（Hybrid 建议页把重要嘅人、想重新聯絡嘅人、兴趣、唔想提起给模型，并带 `agentId` 让服务器注入小欣记忆；`functions/memory.js` 的 `INJECT_MODULES` 加 `m6_suggestions`，没带 agentId 时服务器不注入，所以开关关着行为不变）。
- 建议页的提示词仍在 App 里（历史遗留），新版只在开关开着时用；要搬到 `functions/prompts/` 另排。
- `functions/stt.js`：`meta/stt_config.model` 二选一（`chirp_2` 默认、`chirp_3`），Google 拒绝时该次退回默认；`stt_usage` 和返回值记实际用的模型。
- 待 Junyu：决策编号；建议页提示词搬服务器；PPT 乙部铺垫句已加（见 scratchpad 两份 deck）。
## 2026-10-19 W0 现场第二批：自我介绍卡配对错、字体大时按钮被顶出（PR 草稿，分支 `fix/1019-intro-variant-and-dialog`）

- `first_intro_overlay.dart`：`_IntroDialog` 原来 `resolveVariant(null)`，揀阿伯也显示阿珍；现在用 profile 的配对，介绍句里的「阿珍／阿伯」换成所揀那位。卡最高占屏幕 80%，文字区 `Flexible` + `SingleChildScrollView`，按钮固定。`referral_suggestion_card.dart` 两处名字同样改按配对。
- 其他仍 `resolveVariant(null)` 的地方只涉及小欣、通通或入组前的列表，不影响。
- UI 扫描加「首次介紹卡（揀咗阿伯）」流程。
- 同日 Junyu 另提的四件（iOS 系统字体放大后观感不统一、Brief PR 要更醒目的入口、记忆页按日期分组、个人资料页和首页热线卡收起）记在 backlog，要定了再做；热线卡按规矩不动。
## 2026-10-19 Junyu 第二轮核对：切页跳回、标题跳动、「自己」页精简、首页安全卡、首页字放大、字号五档（同一 PR 草稿，分支 `claude/zealous-fermat-8rgqtg`）

- 登录后第一次点「自己」跳回「睇今日」：`AuthGate` 每次 build 都新建 `profileChanges()` 流，登录后重读开关的 `setState` 让 `StreamBuilder` 回到等待状态，整个 `MainShell` 被换掉。改为流只建一次，重读开关后只把 `configRevision` 加一交给 `StaffGate`（它据此重查评估员身份，重查时不再显示转圈）。测试 `test/auth_gate_stream_test.dart`，去掉修复会失败。
- 标题跳动：`AppAppBar` 的 `AnimatedSwitcher` 默认把新旧标题居中叠放，动画完才回到左边；`layoutBuilder` 改为靠左。
- 「自己」页：删掉开头「語言、界線、demo 資料」一句、「你嘅資料」卡和那里的登出；登出移到「個人資料」页底（键 `profile_sign_out`，先确认、回到第一页再登出）。
- 首页安全卡：两部分，见决策草稿 `0048-home-safety-card-simplified.md`（危机界面，待 PI 审核）。「24×7 政府熱線」独占一行居中，「如果唔安全，／睇更多支援熱線」固定两行——扫描截图里放在按钮旁边或一行写完时，大字下会断成「政府熱／線」「支援熱／線」。
- 「行動／望一望／進度」标签 17 pt、图标 30；「今個星期」17 pt、后面各项 16 pt。
- 字号五档（决策草稿 `0045-five-font-levels.md`）：先做过一版「加超大 1.45、最大 1.6」，Junyu 看后改为 1.06／1.12／1.18／1.24／1.30 平均五档，最大仍 1.3。`AppFontScale` = `standard`/`slightlyLarge`/`large`/`larger`/`xLarge`（旧三档名字不变，已存设定照旧读得到；原標準 1.0 变 1.06）。`combinedTextScale` 封顶 1.3。设定页五个按钮不随字号变；去掉预览，换档后 `_FontSizeCheck` 问「會唔會太大／太細」，可返回原档（测试 `test/font_scale_check_test.dart`）。
- 五档扫描：`ui_text_scale_sweep_test.dart` 支持 `SWEEP_SCALES`，新加五条流程（睇今日下半＋支援熱線页、傾完評分、人生回顧、每週問卷 W1 全套、個人資料＋登出；设定页加字号按钮）。18 条流程 × 4 种宽度（320／360／375／390）× 5 档 × 两组 = 720 次，**全部没有溢出**。中间试 1.45／1.6 时注册页小标题在 320／360 宽超出，已改为可换行（现在用不到这么大，但留着无害）。没覆盖的：首页最上面的问候和心情、继续倾偈卡、提醒横幅（要连 Firebase），「望一望」「進度」打开后的页面。底部分页的字 Flutter 自己封顶 1.3。

## 2026-10-19 Junyu 核对后六处：测试员免打包解锁、每週問卷測試页、Brief PR 横排、注册跳到错处、人生回顧去锁、做啲嘢用词与保留对话开关（PR 草稿，分支 `claude/zealous-fermat-8rgqtg`）

- 测试员工具：`TesterGate.tryUnlockAsTester`——`isTester` 且 `testerToolsEnabled` 时 7 次点击直接解锁；旧的 `TESTER_PIN` 照旧可用；非测试员不弹任何提示。决策草稿 `0050-tester-tools-unlock-without-pin.md`。
- 新页 `tester_weekly_bundle_page.dart`：W1–W7 预览（`WeeklyBundleFlowPage.previewFor`，各部分 `preview: true` 不写 Firestore）和「模擬到嗰日」（`AppClock` 拨到推送后 30 分钟，回首页）。模拟要帐号有 cohort 和 W0（切换组别一次会补上）。
- Brief PR 第二版问卷：七个选项横排（`_HorizontalScale`，键名 `brief_pr_option_N` 不变），小屏大字测试不溢出。
- 注册页：每格 `GlobalKey` + `FocusNode`，验证失败滚到第一格错处再聚焦（先滚完再聚焦，否则光标的滚动会打断动画）；服务器错误按代码对到电邮或密码格，用 `forceErrorText` 显示，改了就消失。
- 人生回顧时间线：去掉锁和灰色，未完成的主题白底加播放图标，点开对应主题（同 `reminiscence_landing.dart`）。人生點滴本来就不限次序，这里只是界面跟上。
- 「做啲嘢」页去掉「agent」；「保留對話紀錄」开关加 `transcriptRetentionToggleEnabled`（默认关），决策 0020 第 5 条标取代。仓库里没找到更早「不开放」的书面记录，待 Junyu 确认并核对 ICF。

## 2026-10-19 W0 现场两处修正：签到页揀心情那屏溢出、语音转写空格（PR 草稿，分支 `fix/1019-field-issues`）

- 小欣签到页 Decision A 的「揀心情」门：固定 Column 加 Spacer，iPhone 7 Plus 大字体下按钮被顶出屏幕。改为 `SingleChildScrollView`，和 10/15 行动计划页同一修法；UI 扫描加了这一屏（之前只测了带心情进来的路径）。为了能在没有 Firebase 的测试里走到这屏，`MoodRecorder` 改为用到时才取 Firestore，`CheckInArmA` 多一个只给测试用的 `moodRecorder` 参数。
- `functions/stt.js` `readResponse` 去掉中文字之间的空格（`tidyCantonese`），单元测试加四条。识别准确率本身没动，要换模型另定。
- 同日现场另三件待 Junyu 定：首页按表情是否直接进签到页；建议页要用上入组的人名和兴趣；语音是先关还是换模型。

## 2026-10-18 批次 #120：12 张 PR 一次合并前的 UI 扫描与两处修正（分支 `batch/1018-night`，PR 草稿）

- 把 #108–#119 合成一个批次（三处一行冲突，两边都留），后端全套、Flutter 六套都在批次分支上重跑过。
- 新增 `test_manual/ui_text_scale_sweep_test.dart`：这次动过的 13 个老人页面，在 320 / 360 / 375 / 390 逻辑像素宽和字体 1.0 / 1.3（App 封顶）下渲染并做基本交互，任何溢出都算失败；带 `SWEEP_SHOTS` 时存截图。CI 只在两套 Phase B 构建里跑它（约一分钟），默认构建那套不跑。
- 扫描结果：三种构建 13 页 × 4 宽 × 2 档全过。中途行动计划页「第 N 步 / 共 6 步」那一行在 320 / 360 宽 × 1.3 报过 34 / 13 像素右侧溢出，查明是测试默认字体把数字和斜杠都画成全宽所致（换真字体就不溢出），仍把 `app_stepper.dart` 那一行改成两边都可伸缩，窄屏大字也稳。
- 扫描发现并修了两处：通通开场白把兴趣代号 `yum_cha` 直接显示给老人（改中文标签，模型看到的也改标签）；乙部页「關係（例如：女兒、舊朋友）」并排时在所有宽度都被截断（改为每格一行）。
- 真机上系统字体调到最大也只会到 1.3 倍，10/19 真机测试按「系统标准 + App 標準」和「系统最大 + App 特大」两档走。

## 2026-10-18 T49a 入组资料按 1018 任务单 §A 收尾（PR #111 同一分支 `feat/t47-intake-v2`，PR 草稿）

- 按 `dev-tasks-1018.md` §A：人数上限每组 10；服务器入组记忆按 §A3 表重分类（孤單时段 feeling、人生阶段 story），去掉「唔想主動提起」「鍾意人點樣講嘢」两条；层和可见范围改用 `memory.layerFor` / `visibilityFor`；想重新聯絡嘅人写进新字段 `reconnectContacts`，行动计划两组都显示；旧 6 页数据加了 emulator 用例；W0 SOP 第 5、6 步后加定稿一句。
- 顺带：入组每位陪伴者各一份，改了可见范围后同一句会重复，`selectForInjection` 对入组来源去重；研究员录入的 `completedParts` 改为追加；导出去掉 `reconnectContacts`。
- 读代码答 §A4、§A5（T47 报告第 10 节）：分析用的配对在登记前改过时只有 App 事件留着第一次选择；规则组读 `interests`（通通兴趣按钮）和行动计划的人名，`inputMode` 两组都没人读。待 Junyu 定的 7 条在报告第 10 节第 6 条。

## 2026-10-16 入组资料按修订任务单重做：甲部研究员 14 题、乙部老人填重要嘅人（PR 草稿，分支 `feat/t47-intake-v2`，接 #109）

- 研究侧 10/16 把 `dev-tasks-1015-intake.md` 改版：字段全保留、不限数、新加四题、乙部由老人自填。按此重做服务器录入函数、研究员表单、老人乙部页（S19）和 Hybrid 组记忆播种（从合并后的整份文档生成，谁先录都行）。第 0 节第 5、6 题答在 T47 报告第 9 节。
- 语气槽位（第 2 节第 7 条）先按弱版做：写成一条记忆「鍾意人點樣講嘢」；提示词新版草稿已单独给 Junyu，PI 审后再切。

## 2026-10-16 研究员备注、通通一页不再问兴趣、兴趣按钮换一换、气泡加宽（PR 草稿，分支 `feat/intake-note-tung-chips`，接 #108）

- Junyu 10/16 看了五题的限制和提示词路径后定：加「研究員備註」给三位夥伴做记忆；通通在引导里再让老人揀兴趣太累，改为研究员录入时不问、老人答过也不问；通通聊天页兴趣按钮一次两个加「換一換」；聊天气泡太窄改宽。顺带发现兴趣按钮把英文代号写进输入框（「我想傾下 yum_cha」），一并修了。
- 答过的问题记在 T47 报告第 8 节：五题的选择上限是研究侧 10/15 定的，不是技术限制；自由栏照字面进固定句子，写观察类的话要用研究员备注。
## 2026-10-16 FAQ 删英文条目；iPhone 更新改走 TestFlight（PR 草稿，分支 `fix/faq-english-testflight`）

- Junyu 10/16 定 iPhone 以后走 TestFlight 外部测试公开链接，测试员可在 TestFlight「先前的版本」自己换版本。流程写在 `docs/release/ios-testflight.md`。
- FAQ 里「我可唔可以用英文？」连同「我嘅資料」页的语言一行删干净（英文开关一直是关的）。
## 2026-10-18 记忆机制核对报告（只读，不改代码；分支 `docs/memory-mechanism-1018`）

- 按 main @ d6c38d9 把 Hybrid 组跨会话记忆从写入、抽取提示词、注入、「唔好記住」、删除、首次记忆到隐私记录逐条对照代码写成 `docs/dev-reports/memory-mechanism-20261018.md`，给 PI 读。主要发现：两层开关 `layersEnabled` 没开，所以分层过滤和 S6 分层剂量现在都没有；抽取仍是 v2；小欣签到页和回忆页在切换／超时／返回时不叫 `memoryEndSession`，只靠 30 分钟扫描；`mem_extractions.raw_output` 删条目后仍保留；陪伴者提示词末尾的 rolling_summary／named_entities 槽位服务器从不填。十项要 Junyu 定的列在报告第 10 节。
- 订正：10/16 对话里说「`avoidTopics` 没有进提示词」不对——小欣签到、通通、阿珍／阿伯自由对话三页和开场白都由 App 在提示词末尾加一行「⛔ 用戶要求唔好提起呢啲話題」；只有回忆页没有。
## 2026-10-18 T49 任务单落盘；两层开关 emulator 六步核对全过（PR 草稿，分支 `test/layers-sixstep-1018`）

- 研究侧 10/18 晚的 `dev-tasks-1018.md` 进仓库，编号 T49（A 入组后续、B 提示词语气槽位、C S1a 日志、E 两层开关和两处修 bug）。
- E1 (a)：`layersEnabled: true` 下六步加规则组全过，脚本 `functions/test/memory_layers_sixstep_emulator_test.js`，报告 `docs/dev-reports/memory-layers-sixstep-20261018.md`。按 E1 (b) 交 Junyu 10/19 早上开开关。
## 2026-10-18 10/19 前配置只读核对脚本（PR 草稿，分支 `tool/check-prelaunch-values`）

- dev-tasks-1018 §G4：`tool/check_prelaunch_values.js` 只读，把 `app_config/feature_flags`、`phase_b`、`phase_a` 残留、`meta/memory_config`、`randomization_config`、`alert_config`、分配序列长度和已用位置、`isTester` 帐号数、已登记人数逐项和核对表的期望值并排打出来，✓／✗ 一目了然。不打印组别、序列和完整电邮。Junyu 跑一次贴结果。
## 2026-10-18 T49e-4 删一条记忆时清服务器审计里的模型原文（PR 草稿，分支 `fix/t49e4-raw-output`）

- #113 核对报告第 6 节发现：老人删了条目，`mem_extractions.raw_output` 里还有模型当时的原文。Junyu 10/18 晚定修（1018 §E4）。
- 做了：页面删事实／待跟进（`deleteSummaryForItem`）、页面删摘要（新触发器 `memorySummaryDeleted`）、「唔好記住」（`forgetRelated`）三处，都把来源那次整理的 `raw_output` 改成「已清除」，审计字段保留。开关 `clearRawOutputOnDelete` 默认开。`tool/delete_memory.js` 本来就整个删，不用改。
- 报告 `docs/dev-reports/T49e4-raw-output-20261018.md`；决策草稿 `docs/decisions/0043-clear-raw-output-on-delete.md`（补充 0024 第 4 条）。待定：部署前已删条目的原文。
## 2026-10-16 测试员自切组别（PR 草稿，分支 `claude/gifted-bardeen-yhizmk`）

- 要做的：测试员在同一部手机上把 Hybrid 组和规则组都完整走一遍，包括记忆。做了：服务器 `setTesterArm`（只认 `isTester`，开关 `testerArmSwitchEnabled` 默认关），测试员不吃分组缓存，Arm A 测试员有记忆 v1，切过组的测试员收每周问卷推送；App 测試員工具加「切換組別」。参与者一律不变。
- 查到的缺口和处理见报告 `docs/dev-reports/tester-arm-switch-20261016.md`；决策草稿 `docs/decisions/0049-tester-arm-self-switch.md`，编号待 Junyu 给。
## 2026-10-18 T49c 通通 S1a 固定回复记一条事件（PR 草稿，分支 `feat/t49c-s1a-event`）

- 10/18 §C：搜一搜维持关闭，只加记录。通通显示 S1a 时写 `users/{uid}/events` 的 `s1a_fixed_reply`（`agentId`、`sessionId`、`arm`、`matchedVersion`、`clientTime`，不含原话和关键词），两组相同，开关 `s1aEventLogEnabled` 默认关。每周过程数据导出加 `event_counts`（按人、按组次数）；锁库分析导出本来按事件名通用导出，不用改。
- 待核答了：代码里 Hybrid 组 S1a 是逐字显示，命中后 `return`，不调用 LLM；prompt 模式 B 第 5 条只在没出 S1a 时起作用。报告 `docs/dev-reports/T49c-s1a-event-20261018.md`。
## 2026-10-18 三位陪伴者提示词 v2/v2/v3 + 语气槽位 + 回忆页禁区行（T49b，PR 草稿，分支 `feat/t49b-prompts-tone-slot`）

- 结论：小欣、阿珍／阿伯、通通的提示词各开一个新版本文件，旧文件不动。服务器按老人入组时的「鍾意人直接啲定溫和啲講」在提示词里加一句语气；没录入的人只看到默认句，行为不变。只有 Hybrid 组。
- 文字改动（任务单 1018 §B）：自称「電腦程式夥伴」，被问起老实说是电脑程式；不用「AI」「模型」「機械人」，不说版本；删通通「幫佢搵資料」和「+ 搜尋」，小欣改说「過去同通通傾下」；删末尾从来没填过的「Context injection 格式」。
- 回忆页是 Hybrid 组唯一没把「唔想提起的话题」告诉陪伴者的聊天页，补上，和签到页同一句。
- 服务器：提示词登记表搬到 `functions/prompt_registry.js`，好做不连 Firestore 的测试；语气从服务器读的资料来，App 改不了；规则组第一步就被拒绝。
- `encouragementStyle` 要等 PR #111 合并才有人写。10/19 冻结后合并算偏离，STUDY_CHANGELOG 已记。决策记录草稿 `docs/decisions/0044-companion-prompts-v2-tone-slot.md`。Junyu 要看三份最终文本再合。
## 2026-10-18 T49e-3 小欣签到页、回忆页每种结束都马上交记忆（PR 草稿，分支 `fix/t49e3-memory-handover`）

- 10/18 记忆机制报告（PR #113 第 2.2 节）发现：小欣签到页在切换陪伴者、30 分钟超时时不叫服务器整理记忆；回忆页只在按「儲存」时叫。Junyu 10/18 晚定按 bug 修（任务单 §E3）。
- 做了：两页各加 `_handOverMemory()`，四种结束都调，每次会话一次；小欣页不再要求「至少讲过一句」才交（那个条件只管签到完成和 Brief PR）；回忆页从小结页按返回也交。`switch_agent` 可能在页面关闭后才到，交接用页面活着时存下的资料，不碰 context。没改服务器、`compileAtSessionEnd`、`MemoryV1Service`。
- 测试 `test/memory_handover_pages_test.dart` 12 项，三种构建都过；改动前的代码在 Phase B 下 8 项不过，正好是报告列的几种情况。报告 `docs/dev-reports/T49e3-memory-handover-20261018.md`。

## 2026-10-16 注册页：密码输两次、电邮换行、显示密码（PR 草稿，分支 `fix/signup-email-password`，并入 `batch/1016-morning`）

- 10/15 试跑一位老人注册后发现电邮打错，但格子只显示尾巴看不全。改：电邮格自动换行、去空格；建立帐号时密码输两次，不一样不让提交；密码格加眼睛按钮。文字见 S17，待产品窗口核。
## 2026-10-16 入组五题改为一题一屏、先客观后主观（PR 草稿，并入 `batch/1016-morning`）

- Junyu 10/16 看了 T47 的五题一页版本：挤、可读性差。改成一题一屏（进度条、上一題／下一題），顺序改为打字定講 → 鍾意做乜 → 重要嘅人 → 最想 app 幫到乜 → 唔想提起；研究员录入页同一顺序、每题一块。问法、字段、服务器都不变。T47 报告第 7 节。
- 确认过：10/15 删掉的题（作息、心事、想重新連繫的人、孤独时段、人生阶段、话题、偏好时段）现在哪里都不问；要加回由 Junyu 定。

## 2026-10-15 T48 「重要的人」经同意给夥伴；入组答案写进服务器记忆（PR 草稿，分支 `feat/t48-contacts-and-seed`，接 T47）

- Junyu 10/15 定「要给，确认之后再进入」：录入时每位单独勾同意；勾了的进小欣记忆（v0 播种加一句；v1 由服务器写条目）和行动计划快捷按钮（两组）。
- 核对时发现 Phase B Hybrid 组走服务器记忆 v1，App 的入组播种从不运行，入组答案从未到过陪伴者。T48 起研究员录入时服务器直接写 `mem_facts`（每位陪伴者一份，再录覆盖）。报告 `docs/dev-reports/T48-shared-contacts-20261015.md`，决策记录草稿在第 5 节。

## 2026-10-15 T47 入组问卷精简为五题、研究员后台录入（PR 草稿，分支 `feat/t47-researcher-intake`）

- 10/15 第 10 条：老人答 6 页问卷太吃力。先按代码答了第 0 节四题（报告第 2 节）：原问卷 17 个字段只有 `mainGoals`、作息三句、`avoidTopics` 被首次记忆播种读过；`interests` 其实来自引导里通通那一步，`closeContacts` 从来没被写过也没人读；规则组一个字段都不读。
- 做了：服务器 `recordResearcherIntake`（`functions/researcher_intake.js`，只有 `unblinded`，写 intake 文档 + 资料字段 + `intake_audit_log`）；登记页加「入組資料」区；开关 `researcherIntakeEnabled` 开着时 `ConsentGate` 跳过问卷；关着时老人答五题一页的 `IntakeShortPage`（原 6 页 `intake_flow_page.dart` 删掉）；登记页不再要研究员选配对，`enrollParticipant` 只记录老人自选的那位，不再写 `ahJanAhBakVariant`。
- 没做：登记表（`feature-registry.md`）按规矩不改，第 2 节第 5 条的三处改动写在报告里给产品窗口。报告 `docs/dev-reports/T47-researcher-intake-20261015.md`。
## 2026-10-15 选项按钮对比度（PR 草稿，分支 `fix/chip-contrast`）

- Junyu 10/15 在安卓研究员页和老人的 iPhone 上都看到：表单选项未选时全是白的，点了才变黄。原因是主题里 chip 的边框色 #E7E0D8 和页面底色 #F7F5F1 几乎一样，字也用淡色。改主题一处：未选深色边框 1.5px 和深色字，选中底色用主色 22% 并打勾，高对比模式黑边 2px。加 `test/chip_contrast_test.dart`。
## 2026-10-15 翻页回页顶、键盘遮挡、字号封顶（PR 草稿，分支 `ui/scroll-keyboard`）

- Junyu 10/15 三条：问卷点下一页不回页顶（每週夥伴評估和简短评价共用一个 ListView，加 `ValueKey` 按页重建；评估员录入页同样）；输入法弹出页面不变长（三个固定 Column 的页改成可滚动，输入框 `minLines` 代替 `expands`；四个聊天页的消息列表改 `reverse: true`，最新一句贴着输入框并跟着键盘上移；签到备注框加 `scrollPadding`）；大字模式很多页面放不下（系统字号 × App 字号封顶在 1.3）。核对时发现 `onboarding_page.dart` 已无引用，留给瘦身批次。

## 2026-10-15 陪伴者页面顶栏统一（PR 草稿，分支 `ui/companion-appbar`）

- Junyu 10/15 看到三位陪伴者页面左上角、右上角不一样。盘点后：标题三种写法、右上角只有阿珍 A 页有第二个结束按钮、规则组两页没有 T25 的收尾按钮（和「两组相同」的规定相悖）。新建 `lib/core/agents/companion_app_bar.dart`，六个页面统一用它；阿珍／阿伯页的当周主题移到页内第一行。加 `test/companion_app_bar_test.dart` 钉住规则组两页和 Hybrid 组一样。

## 2026-10-15 iOS 最低版本 13.0 → 15.0（PR 草稿，分支 `fix/ios-deployment-target-15`）

- Junyu 用新版 Xcode 打 TestFlight 包报错：Xcode 只支持 15.0 以上的部署目标。`Runner.xcodeproj` 三处 `IPHONEOS_DEPLOYMENT_TARGET` 改成 15.0；iOS 15 覆盖 iPhone 6s 及以后，老人的机不受影响。本机的 `ios/Podfile`（不在仓库里）也要改成 `platform :ios, '15.0'` 再 `pod install`。

## 2026-10-15 Junyu 五项决定落盘 + Firestore 配置核对表（PR 草稿，分支 `chore/1015-decisions-partner-config`）

- 决策 0041（告警不设后备，PR #86）、0042（试跑走正式排程，PR #92）落盘；0038 标明由 0041 部分取代。
- W4 要 S12（代码不动）；提醒时间按代码（推送后 24 小时的下一个整点），排查文件 A4、A7 改了。
- 介绍陪伴者不再说「AI」，改叫「夥伴」（S15，六处），「唔係真人」保留并加进第一句问候。
- W4 完成率的分母不含试跑（#89 现状不动）。
- 新写 `docs/release/firestore-config-checklist-1015.md`：代码读的每一份配置文档和每个键、默认值、现在该设什么。核对发现 `app_config/phase_a` 里留着测试值（`sessionIdleTimeoutMin: 1`、`w2DayOffset: 0`、`week1NudgeDays: [1]`），要删；`meta/memory_config.enabled` 和 `phaseBArmA`、`meta/randomization_config.enabled` 是 10/19 前必须确认的。

## 2026-10-15 1014e 第 2 节第 4 条：取消告警后备（PR 草稿，分支 `fix/alert-no-backup`）

- `escalateDue` 在 `backupEmail` 为空时直接返回（不认领、不写日志），告警留在待处理；后台告警列表把 `primaryFailedAt` 的行标成「郵件未發出…請即處理」（1014e 第 1 节第 5 条要的确认：首发失败写 `alert_audit_log` `email_failed` / `no_recipients`，并在列表标出）。决策 0038 状态行标“部分被取代”，新决策草稿在报告第 5 节，编号待分配。模拟器测试 17/17（新增 1 项）。报告 `docs/dev-reports/1014e-alert-no-backup-20261015.md`。
## 2026-10-15 1014e 第 2 节第 6 条：教育文章危机提示的机构名更正（PR 草稿，分支 `fix/education-hotline-name`）

- `education_library.dart` 两篇文章的提示把 2382 0000 写成撒瑪利亞防止自殺會，改为生命熱線；号码不动。新测试：文章里每个热线号码都要和 `crisis_resources.json` 的机构对得上。`verifiedDate` 等 Junyu 核对后填。报告 `docs/dev-reports/1014e-education-hotline-name-20261015.md`。
## 2026-10-15 1014e 第 2 节第 18 条：App 名称（PR 草稿，分支 `feat/app-name-1014e-18`）

- Android `android:label` 从 `app_demo` 改为「陪住」，iOS `CFBundleName` 改为 WithYou；图标用 Junyu 10/15 给的图（`assets/icon/app_icon.png`），flutter_launcher_icons 生成全部尺寸。
- 同一 PR 放进 10/15 修订版 `dev-tasks-1014e.md`（第 1 节第 3 条开关清单、第 2 节第 14、17、18、19 条）。
- 核对 10/15 中午的开关：`weeklyScheduleV2Enabled`、`socialContactProbeEnabled` 在 `app_config/phase_b` 已开；`sessionBriefPrV2Enabled` 被写到了 `feature_flags`，代码读的是 `phase_b`，没生效；`feature_flags` 里 `onboardingAfterEnrollmentFix`、`voiceInputEnabled`、`usageEventsEnabled`、`opsDashboardEnabled` 都还没设。报告 `docs/dev-reports/1014e-app-name-20261015.md`。
## 2026-10-15 通知与问卷排查 A1–A15（PR 草稿，分支 `docs/notifications-audit-1015`）

- 按产品窗口的 `notifications-audit-1015.md` 第 4 节 A 部分在 emulator 跑完 A1–A15，全部通过；服务器端固化成 `functions/test/notifications_audit_emulator_test.js`（8 条），A12、A13 由已有 Flutter 测试覆盖。五个 [待核] 按代码答了。
- 两处和排查文件不一致要研究侧定：W4 含 S12（三部分）；提醒是「推送实际发出后 24 小时的下一个整点」。报告 `docs/dev-reports/notifications-audit-20261015.md`。

## 2026-10-15 1014e 第 2 节第 3 条：`isTester` 只允许管理员写（PR 草稿，分支 `fix/istester-admin-only`）

- 规则：`users/{uid}` 新建不能带 `isTester`，更新不能动它；App `UserProfile.toMap` 不再写它（merge 写保留服务器值），设置页测试员开关改只读说明；新脚本 `tool/set_tester.js`（`--uid` / `--email`、`--tester=true|false`、`--list`，登记过的账号要 `--allow-registered`）。规则测试 5 项、脚本模拟器测试、Dart 测试。随规则在 10/19 开门前部署；部署后给团队和评估员账号设上。报告 `docs/dev-reports/1014e-istester-admin-only-20261015.md`。
## 2026-10-15 试跑改走正式每周问卷排程（PR 草稿，分支 `fix/pilot-standard-schedule`）

- Junyu 10/15 定：试跑流程和正式一样，推送都按 Phase B 正常走。代码里 `cohort: pilot` 原来还是 T24 的压缩排程（第 1、3、5、7 天、1 天窗口），开关一开，现有试跑老人会被补记缺失、新试跑老人第 1 天晚上就收推送。改法：服务器 `scheduleModeFor` 和 App `modeForCohort` 把 `pilot` 映射到 `standard`，各一行；压缩排程的代码和配置键留着不删（只有共用表测试用）。
- 模拟器测试改成验证试跑账号第 1、3、5 天什么都没有、第 7 天和 Phase B 账号同一条推送、同一个窗口。报告 `docs/dev-reports/pilot-standard-schedule-20261015.md`。

## 2026-10-15 第 6 条：三组文字定稿接入（PR 草稿，分支 `fix/copy-1015-item6`）

- 产品窗口 10/15 定稿了三组文字，照抄进代码：A. 规则组回忆页的心情提示（S13，取代现包里老人看得到的【占位】）；B. 收尾按钮首次说明分号改句号（S10c）；C. 每周问卷全部文字（S14：推送两句、标题「每週問卷」、开头一句、四个部分名称、状态字、完成句、首页提醒卡两句）。Brief PR 按钮和 S10b 不动。
- 每周问卷的推送从此不再带【占位】：`weeklyScheduleV2Enabled` 打开后会真的发出；测试里的「带占位不发」改用覆盖文字验证，保护逻辑没拆。
- 一处产品窗口没给：流程开头的第二句「可以隨時停，下次會由停低嗰度繼續。」沿用原文，等 Junyu 确认。按约定，这个 PR 等 Junyu 回「可以」再合。报告 `docs/dev-reports/copy-1015-item6-20261015.md`。

## 2026-10-15 1014e 第 2 节第 11 条：研究员登记页加「研究員儀錶板」入口（PR 草稿，分支 `feat/dashboard-entry`）

- T19 起 `unblinded` 登录直接进登记页，T34 的告警列表和「確認處理」、T30 的完成率所在的「研究員儀錶板」从此没有入口（T39 核对时发现，Junyu 10/15 同意加）。登记页右上角加一个按钮；只有 `unblinded` 到得了登记页，儀錶板页自己再查一次 claims。没有开关（只是通往已有页面的链接）。T43 报告里“確認處理”那一步合并打包后可做。
- 报告 `docs/dev-reports/1014e-dashboard-entry-20261015.md`。

## 2026-10-15 1014e 第 2 节第 9 条：注册页删 UCLA 输入框（PR 草稿，分支 `fix/remove-ucla-field`）

- `login_page.dart` 去掉「研究人員填寫」一节和「UCLA 基線總分（20–80）」字段；`baselineUclaScore` 留在模型里不再写。1014e 第 3 节第 2 题的答案：这个字段没有任何分层读取方（`enrollParticipant` 用 DJG-ES 情感分），只有盲法导出 / 锁库导出把它当参与者属性原样导出；注册页老人自己填的是电邮、密码、称呼、年龄、紧急联络人称呼和电话。报告 `docs/dev-reports/1014e-remove-ucla-field-20261015.md`。
## 2026-10-15 1014e 第 2 节第 1 条：`usage_weekly` 按 `endedAt` 归周（PR 草稿，分支 `fix/usage-weekly-endedat`）

- `functions/blinding.js` 新 `sessionWeekAnchor(endedAt, startedAt)`（结束时间优先，退回开始时间），盲法导出和 `process_export.js` 都用它；行上加 `weekBasis: "endedAt"`。单元测试 + 两个模拟器测试加了跨周一的会话。T25 报告第 5、10 节标已定。报告 `docs/dev-reports/1014e-usage-weekly-endedat-20261015.md`。
## 2026-10-15 1014e 第 2 节第 12 条：评估员 W4 名单含 PILOT（PR 草稿，分支 `feat/w4-list-pilot`）

- `functions/assessor.js`：`assessedParticipants`（B + PILOT）给名单和录入，`phaseBParticipants`（只 B）留给全体合并完成率——T43 报告第 5 节第 1 项的三个选项取 (b)，Junyu 要 (a) 的话改一处常量。App 两句文字加“或試跑”。T43 测试第 5a 步的断言反过来（三位 PILOT 在名单上）。报告 `docs/dev-reports/1014e-w4-list-pilot-20261015.md`。

## 2026-10-14 T39 运营看板「每人」页（PR 草稿，分支 `feat/ops-dashboard`）

- 按 1014c 边界 + 1014d 收窄只做第 2 页（每人一行 → 每日网格、最近会话、CSV）和第 1 页第 7 项（今日回访到期名单）。聚合在 Cloud Function：`opsDashboardPeople` / `Person` / `Csv`（`functions/ops_dashboard.js`），每日 `opsDailyRollup` 把过去的研究日存成 `ops_daily`，今天按需算。开关 `opsDashboardEnabled` 默认关，只给 `unblinded`。
- 入口放在研究员登记页右上角：核对时发现原来的「研究員儀錶板」（`researcher_dashboard_page.dart`，T34 告警、T30 完成率都在那里）在 App 里**没有任何入口**（T19 起 `unblinded` 登录直接进登记页），要带回研究侧。
- 回访阶段、旧构建后备口径、单段 60 分钟封顶都按 1014d；结局集合一个都不读（测试扫源码）。报告 `docs/dev-reports/T39-ops-dashboard-20261014.md`。

## 2026-10-14 T40 使用事件记录（PR 草稿，分支 `feat/usage-events`）

- 1014d 第 6 题的答案：App 早就在 `events` 里记 `app_foreground` / `app_background`，但那条行的 `timestamp` 被服务器时间覆盖，手机时间没有留下；也没有构建版本号、补传标记、登记前不记。所以 T40 按“补齐缺的、放开关后”做：新子集合 `users/{uid}/usage_events`，App 写类型、手机时间、服务器时间、版本号、平台；服务器触发器补研究编号、香港日期、研究日、`uploadedLate`。开关 `usageEventsEnabled` 默认关；规则只让已登记的本人新建、不能读改删。
- 离线：靠 Firestore SDK 的离线队列缓存、联网后补传；`uploadedLate` 由服务器按“收到时间比手机时间晚 5 分钟以上”判定（客户端自己判不可靠，离线时被杀掉会丢标记）。真机断网三次的验收要在 W0 装机时做，模拟器只能模拟“晚到的行”。
- 报告 `docs/dev-reports/T40-usage-events-20261014.md`，决策草稿在第 7 节。

## 2026-10-14 T46 收尾按钮首次说明只显示一次（PR 草稿，分支 `fix/session-end-hint-once`）

- T25 的收尾按钮说明每次启动 App 都再显示一次（当时 App 没有本机存储）。T37 之后有了 `shared_preferences`，T46 把“已经说明过”记在本机（`session.closeHintShown`），同一台手机只显示一次；重装会再显示一次。两组相同，文字不改。存储读不到时退回每次启动一次。
- 要在打开 `sessionBriefPrV2Enabled` 前合并。报告 `docs/dev-reports/T46-session-end-hint-20261014.md`。

## 2026-10-15 T43 PILOT 版本指定核对清单（emulator，PR 草稿，分支 `chore/t43-pilot-checklist`）

- 按 1014c 第 2 节在模拟器上把 W0 当天的流程串成一条链跑了一遍（`functions/test/t43_pilot_checklist_emulator_test.js`，11 步）：登记 PILOT-01、02（Hybrid）、03（规则组）→ 两层序列指针不动 → `pilot_assignment_log` 三条 `designate` → 评估员 W4 名单没有组别字眼 → PILOT 账号 acute 告警发一封到第一收件人、测试账号不发 → 登记门开着时 PILOT Hybrid 能用 LLM、没登记的和规则组被拒。
- **一条不过**：评估员的 W4 名单（和 W4 纸本录入）现在只含 `PB-`，三位 PILOT 不在名单上（`functions/assessor.js` 只认 `studyPeriod == "B"`）。1014c 第 0 节要 11/9 前含 PILOT，是行为改动，待 Junyu 定改法和编号。
- 没有改行为代码，只加测试和文档。报告：`docs/dev-reports/T43-pilot-checklist-20261015.md`（含给 W0 现场的 8 条提醒）。
- 同一 PR：1014c 第 1 节五题、1014d 第 0 节两题的正式回答 `docs/dev-reports/answers-1014c-20261015.md`。要点：PILOT 告警会发；T21 已在部署的 Functions（Deploy Firebase 第 7 次 = main `c1f88d6`）；`stripPII` 只去电话、邮箱、身份证样式、西式楼层单位，不去姓名和中文地址；参与者包里没有记忆总开关；后台 8 节、导出 4 套、没有运营看板；`events` 有 `app_foreground` / `app_background` 但存的是服务器时间（handoff 初步答案反了）；离线写入缓存后补传、不丢、无补传标记。

## 2026-10-15 W0 装机脚本 v1、iOS 包的编译参数（PR 草稿）

- `docs/release/w0-install-script.md` 按 #59–#76 合并后的 main 重写（取代 #61 的草稿 v0，#61 已关闭）：面访前 Junyu 的 10 项准备、Android/iOS 打包和装机（iOS 10/15 走 Xcode USB，TestFlight internal 作更新通道）、登记门开/关两种顺序、讲给老人听的话（草稿原样保留）、App 现状、要定的事。
- `codemagic.yaml`：bundle id 改成 `hk.hku.hkuimse.withyouapp`，构建加 `PHASE_B=true`、`RULE_TEMPLATE_REPLIES=true`，和 Android `phase_b_templates` 一致。不部署、不改行为。
- 发现：iPhone 推送要补 APNs 密钥和 Xcode Push Notifications 能力，10/22 前要做；记在脚本第 2.3 节。

## 2026-10-14 晚 产品窗口 10/14 第 5–10 条：登记表 v10，任务单 1014c、1014d（T38–T46）

- **定了**：试跑一轮 3 人（PILOT-01、02 Hybrid，03 规则组）10/15 做 W0，按正式配置跑完整 8 周；W8 问卷 13 题加可跳过的 AIMHS，试跑也推；第 63 天后推 debrief，约第 70 天停服；记忆不能整个关闭；告警急性即时、中级每日汇总、低级只记录；运营看板和使用事件记录（回访用）。
- 登记表 v10（C01、C05、C12、C15、C19、C20，新增 C23 使用事件记录）。任务单 `dev-tasks-1014c.md`（产品窗口原文，N1–N5 换成正式编号）和 `dev-tasks-1014d.md`。编号：T38 停服、T39 运营看板、T40 使用事件、T41 每日汇总告警、T42 debrief、T43 试跑核对、T44（#68 补号）、T45（#65 补号）、T46 收尾说明只显示一次。决策 0036 预留给 T35，下一个 0040。

## 2026-10-14 负责人核对后的四个修复（PR 草稿，分支 `fix/flags-after-login-and-guards`）

- 负责人核实：新装 App 第一次注册/登录后控制台开关不生效（启动时读开关、那时没登录、规则拒绝、之后不再读）。登记门开着时后果是老人直接进同意页、问卷答案被悄悄拒绝。修法：登录后再读一次开关并重建门（`auth_gate.dart`）。
- 顺带修：T34 第一封告警发不出去时下一次巡检直接转后备（`primaryFailedAt`）；T25 补问卡没有定稿时间说法时不显示【占位】、记 `due_not_invited: copy_pending`；「安靜時段」登录后和服务器对齐。`isTester` 客户端可写维持待办 96。编号待开发窗口分配。报告：`docs/dev-reports/fixes-after-review-20261014.md`。
## 2026-10-14 T30 角色、评估员视图、序列上传、过程/结局数据、锁库导出（PR 草稿，分支 `fix/roles-exports`）

- 角色按 10/14 分工：`unblinded` = Junyu、`blinded` = W4 评估员（Keran、Mingyan Wang）、新 `sequence_uploader` = Calvin。`tool/provision_researcher.js` 加 `--list`。
- 评估员视图（`lib/features/assessor/`，`functions/assessor.js`）：`blinded` 登录直接进 W4 到期名单和纸本 DJG-ES 录入；规则里 `blinded` 零读权限，全走函数；分数服务器算，存 `outcome_entries`，更正用 `tool/correct_outcome_entry.js`；PHQ-9 第 9 题走 T34 入口。规格文件 `docs/spec/instruments/djg_es.md`。
- 序列上传改为 Calvin 自己的登录调 `uploadRandomizationSequence`（`functions/sequence_upload.js`），上传记日志；`tool/randomization_sequence.js` 不再用服务账号。
- 过程数据导出 `functions/process_export.js`（含 T25 的 Brief PR v3、`validSessionCount`），`exports_v2` 可暂停；后台全体合并完成率（n<5 不显示）。
- 删除可保留一行分配记录（`allocation_records`）；配对改动服务器日志 `pairing_change_log`；`tool/analysis_export.js` 锁库 + 导出 + 合成数据。
- 七个开关全部默认关。报告：`docs/dev-reports/T30-roles-exports-20261014.md`（含三份决策草稿、架构观察）。

## 2026-10-14 T24 研究周和每周问卷（PR 草稿，分支 `feat/weekly-schedule`）

- 做了什么：研究周换算函数（服务器 `functions/study_week.js`、App `lib/core/scheduling/study_week.dart`，同一张测试表 `test/fixtures/study_week_table.json`）；每周问卷按研究周排程（`functions/weekly_schedule.js`、`lib/core/scheduling/weekly_schedule.dart`，同一张表 `test/fixtures/weekly_schedule_table.json`）；一个流程四部分（`lib/features/weekly_bundle/`）；按人推送、提醒、记缺失的定时函数 `weeklyBundleDispatch`；记录的研究周字段只由服务器写（触发器 + 规则）；`brief_pr` 按会话结束时间补周次（`onBriefPrWritten`）；社会接触探针 S12（`social_contact_probes`）。T34 的 `pi_alert.js` 改用共享函数。
- 开关：`app_config/phase_b.weeklyScheduleV2Enabled`、`socialContactProbeEnabled` 都默认关。推送、流程文字仍是【占位】。
- 没做 / 待定：W4 面访日期延长（T30 没合并，留了 `week4CloseFor(w0, w4VisitDate)` 钩子，现在只按第 29 天关）；推送钟点默认 20:00（沿用现在的每周推送），要 Junyu 定；W8 由 T35 做。
- 报告：`docs/dev-reports/T24-weekly-schedule-20261014.md`。
## 2026-10-14 T27 语音改走服务器 STT v2（SPEC:C18，PR 草稿，分支 `feat/stt-server`）

- **做了**：App 的麦克风按钮不再用手机系统识别，改为用 `record` 包把 16 kHz 单声道 PCM 录进内存（不写文件），包成 WAV 上传 `transcribeAudio`，文字填进输入框。服务器新模块 `functions/stt.js`：Google STT v2 `chirp_2`，**只用 `asia-southeast1`**（原来 `functions/index.js` 第 848–855 行的两档 `STT_TIERS` 删掉，不做配置项），每次调用最多两次尝试（瞬时失败重试 1 次），再失败返回类别 `timeout` / `server_error` / `no_speech` / `too_long` / `unavailable`；请求只有 6 个字段，没有任何数据记录参数，`functions/test/stt_test.js` 逐字段检查并扫描日志语句。App 失败时在麦克风上方贴一张 S6 小卡（不是聊天气泡、不写 turns 和记忆），`events` 记 `voice_transcription_failed`（`sessionId`、`agentId`、`category`、`at`）。`speech_to_text` 依赖删掉。
- **没变**：开关 `voiceInputEnabled` 默认关；关着时按钮不显示、不碰麦克风、服务器拒绝。两组代码路径完全相同。
- **讨论过**：S6 怎样“在输入框旁”显示——13 个页面各自放一个提示要改每个页面；改为按钮自己用 `OverlayPortal` 贴在麦克风上方，所有页面一致。`no_speech` 和 `too_long` 不重试（同一段音频再试也一样）。英文界面的 S6 没有定稿，用【占位】。
- **待定**（见报告「要 Junyu 定的事」）：控制台核对 data logging 的截图归档；`stt_usage` 要不要保留；开关打开前要不要先在试跑账号试一周。报告：`docs/dev-reports/T27-stt-server-20261014.md`。

---

## 2026-10-14 T32 第 6 条：旧测试员数据批量清理脚本（PR 草稿，分支 `feat/phase-a-final`）

- Phase A 暂停（决策 0034），T32 只剩第 6 条。新脚本 `tool/purge_tester_data.js`：列出 `isTester` 账号和没有研究期（`cohort` 不是 `phase_b` / `pilot`）的账号及每人的数据量；默认只列不删；`--confirm --production --project=… --production-confirm=…` 才逐人调用 `tool/delete_participant.js` 删除，并写服务器专用的运行记录 `admin_runs`（只有数量）。已登记的 `phase_b` / `pilot` 账号和 `unblinded` / `blinded` 角色的账号永远不碰。由 Junyu 在 10/19 登记前自己跑（上线清单新增 I 节），开发只在模拟器上测（`test/delete_participant/purge_tester_data_test.js`，已接进 `tool/ci_backend_tests.sh`）。
- 待定：没登记的账号要不要一并删（backlog 102）。报告 `docs/dev-reports/T32-phase-a-final-20261014.md`。

---

## 2026-10-14 设置页「語音讀出內容」隐藏、「安靜時段」接成真功能（PR 草稿，分支 `fix/quiet-hours-hide-readback`）

- 负责人定：语音读出先隐藏（没有功能读它）；安静时段接上：开关写到 `users/{uid}.quietHoursEnabled`，服务器按人发推送前查 `functions/quiet_hours.js`，窗口在 `app_config/reminders` 配置（默认 22:00–08:00）。行动计划提醒已接；T24 的每周推送器要接。编号待开发窗口分配。报告：`docs/dev-reports/quiet-hours-hide-readback-20261014.md`。
## 2026-10-14 T25 会话定义与 Brief PR 第二版（SPEC:C16、C14，PR 草稿，分支 `feat/session-briefpr`）

- **做了**：会话规则（`lib/core/session/session_rules.dart`）：结束方式 `close_button` / `back` / `switch_agent` / `timeout`（30 分钟）/ `recovered` / `crisis`，有效会话按“完成一个互动单元”（自由聊天 ≥3 条有回复；Hybrid 签到 = 心情 + ≥1 条有回复；Hybrid 回忆 = 按儲存；规则组 = 一次完整提交）。Brief PR 第二版：只在有效会话后、每位陪伴者每天 1 次、危机不邀请、列表页评价卡（S10a / S10b）、2 小时过期、一题一屏问卷、记录按会话编号去重、五种最终状态 + `everShown`。两组同一套。`llm_calls` 加 `session_id`，`usage_weekly` 加 `validSessionCount`。**开关 `app_config/phase_b.sessionBriefPrV2Enabled` 默认关**，关着时一切照旧。
- **没做**（见报告 `docs/dev-reports/T25-session-briefpr-20261014.md`）：截图；`brief_pr` 的 `studyWeek` / `studyDay`（T24）；收尾按钮首次说明的跨次启动记忆；决策记录编号待分配（旧弹窗和 anchor 的处理草稿在报告里）。
- 合并了 T21 之后的 `main`（e851205），无冲突。

---

## 2026-10-14 Phase B 包隐藏点赞点踩和第一周提示（PR 草稿，分支 `fix/phase-b-hide-feedback-nudge`）

- 负责人核对 W0 流程时发现：点赞点踩只有 Hybrid 组的签到、回忆、反思对话有（通通、文章两组都有），登记表没写这项差异；第一周提示读 Phase A 配置，Phase B 老人也会看到。负责人定：先关掉，保主干。
- 做法：`PHASE_B=true` 的包里两处都不渲染，两组相同；两个远程开关 `replyFeedbackEnabled`、`week1NudgeEnabled`（`app_config/feature_flags`）设为 `true` 可恢复。Phase A 包不变。编号待开发窗口分配。报告：`docs/dev-reports/phase-b-hide-feedback-nudge-20261014.md`。
## 2026-10-14 T34 安全告警邮件（PR 草稿，分支 `feat/safety-alert-email`）

- **做了**：告警邮件改版放在总开关 `meta/alert_config.enabled` 后面（默认关 = 现状）。开着时：中英双语、12 个固定字段（不含组别、原话、命中词）；收件人从 `meta/alert_config` 读，`blinded` 账号去掉并记 `alert_audit_log`；测试账号只记不发；研究员后台 `unblinded` 多「安全告警」一节和「確認處理」（Cloud Function `acknowledgeAlert` 查角色）；定时函数 `escalateAlerts` 每 15 分钟把超过 `escalateAfterHours`（默认 12）没确认的告警转发后备一次。新模块 `functions/questionnaire_safety.js`：问卷 / 评估员录入来源（PHQ-9 第 9 题 ≠ 0）写安全事件、不论级别都告警，只有服务器能写；没有接任何调用方（App 没有 PHQ-9，W8 不推；评估员录入页是 T30 的）。`safety_events` 新字段 `crisisPageShown`（两组同样写）。盲法导出 v2 多 `sourceGroup`，v1 导出也补这个字段。`functions/study_period.js` 和 T21 的逐字节相同。
- **讨论过**：新字段和决策 0029 第五节（告警不带组别线索、PI 盲法）冲突；现在 Junyu 是 `unblinded`、盲的是评估员，决策草稿写在报告里，编号等开发窗口分配。来源「AI 回复扫描」只有 Hybrid 组有，后备收件人 Calvin 看得到（backlog 92，未定）。
- 报告：`docs/dev-reports/T34-safety-alert-email-20261014.md`。

---
## 2026-10-14 T37 登记后的引导顺序和显示设定保存（SPEC:C01、C19，PR 草稿，分支 `fix/onboarding-settings`）

- **做了**：① 开关 `app_config/feature_flags.onboardingAfterEnrollmentFix`（默认关）：开时「介紹三個夥伴」要不要做改为看“引导已完成”标记 `users/{uid}.onboardingCompletedAt`，先登记后引导不再跳过伙伴介绍、兴趣和 S5；配对一屏预选登记值，改选记 `events` `ah_jan_ah_bak_changed`，登记记录不动。② 字体、高对比、安静时段、语音读出改为保存在手机本机（`shared_preferences`，新依赖），无开关。
- 两种顺序、门开关、修复开关的组合各有测试；规则测试证明老人账号能写标记、不能顺带改组别、不能碰 `enrollments`。截图在 `docs/dev-reports/T37-onboarding-settings-20261014-screenshots/`。
- 待定：开关上线时默认开还是关（建议开）；改配对的日志何时搬到服务器（T30）。报告 `docs/dev-reports/T37-onboarding-settings-20261014.md`。

---

## 2026-10-14 T36 Build APK 加 `phase_b_templates` 选项（PR 草稿，分支 `chore/apk-phase-b-templates`）

- 手动打包工作流多一个选项：`PHASE_B=true` 加 `RULE_TEMPLATE_REPLIES=true`，给参与者和内部测试用；不带 `FORCE_ARM`。只改手动打包，不改 CI 和部署。
- 签名仍是调试密钥；换正式密钥的步骤和影响写在报告第三节，要负责人定。报告：`docs/dev-reports/T36-apk-phase-b-templates-20261014.md`。

## 2026-10-14 T21 研究期和登记，第一部分（SPEC:C01，PR 草稿，未合并）

- **做了**：研究编号只认 `PB-`、`PILOT-`，`PA-` 和没有前缀的登记时拒绝（Phase A 暂停，决策 0034）；服务器按前缀写 `users/{uid}.cohort`（`phase_b` / `pilot`，决策 0011 的字段）和 `enrollments.studyPeriod`；试跑在登记页由负责人选版本、再选一次确认，不占序列，研究日从登记日算，记 `pilot_assignment_log`；试跑 Hybrid 账号有服务器记忆，试跑不进盲法导出、不收旧的 Phase A 第 2 周推送。
- 登记门（`app_config/feature_flags.enrollmentGateEnabled`，默认关）：开时没登记、不是测试账号的账号只看到 S8，服务器拒绝 LLM 调用（`llm_denied_log` 记 `not_enrolled`），Firestore 规则拒绝写研究数据。
- 没做、待定：`PHASE_B` 编译开关去留；广播推送对未登记账号的筛选（T24）；盲法人员账号（T30）。报告 `docs/dev-reports/T21-phase-config-20261014.md`。
- **10/14 第二次更新**：再合 main `46d3ef9`（#60）；负责人对 6 件待定事的答复是“改动最少、可以回退”，六项都按现有做法（`PHASE_B` 保留、`pilot` 指试跑、`isTester` 不改、试跑研究日从登记日算、登记门默认关、开的时间待定），写成决策 0037（提议中，待 Junyu 确认），0011 顶上加一行“`pilot` 的含义已由 0037 取代”；评估员账号和登记门的关系交 T30（`dev-tasks-1014.md`）。代码行为没改；backlog 加第 96 项（`isTester` 客户端可写）。

## 2026-10-14 产品窗口 10/14 第 1–4 条排进第九批（T35）；登记表 v9

- **定了**：数据收集 10/19 开始；W4 结局评估员是 Keran，后备 Mingyan Wang，评估员视图只剩 W4；W8 不再有评估员，App 在第 56 天推送 DJG-ES、PGIC、UCLA-3，第 63 天关闭，超窗作答照记并标记；W8 不推 PHQ-9、GAD-7。
- 登记表 v9（C12、C15、C19、C20）。任务单 `dev-tasks-1014.md`：更正 T30（评估员视图只剩 W4、两个评估员账号、评估员不被登记门挡住）、T24（不含 W8，核对旧的每周孤独探针）、T34（W8 没有 PHQ-9 触发）；新任务 T35（W8 App 问卷），决策编号 0036 预留给它。
- 10/11 起登记表、T 编号、决策编号只由开发窗口改和分配，仓库会话只执行。

## 2026-10-10 产品窗口 10/10 第二次交接（第 6–11 条）：T34 告警邮件；Phase A 暂停；错字改正；登记表 v8

- **定了**：告警邮件加字段（研究编号、研究期、陪伴者、来源、级别和类别、词库版本、LoRA、研究日、危机页、事件编号），不放组别和原话；收件人做成配置，第一收件人负责人、后备 Calvin Or，评估员不在名单；后台“确认处理”，12 小时没确认转后备；PHQ-9 第 9 题不是 0 也告警（问卷、评估员录入两种来源）。**Phase A 暂停**，以后单独开仓库和 Firebase 项目（决策 0034）；登记只认 `PB-`、`PILOT-`。W8 窗口第 53–63 天、目标第 56 天，超窗可录；试跑作答窗口 1 天；`event` 记忆归私有层；Hybrid 有效会话条件定了；S5 放入组引导。
- 定稿文字的错字已照研究侧改正改好（`docs/spec/copy/`）。登记表 v8（统筹会话按负责人转来的交接改）。任务单 `docs/dev-tasks/dev-tasks-1010b.md`：新任务 T34，更正 T21、T24–T27、T30–T33（T32 只剩清理测试员数据脚本）。
- 给产品窗口的回复 `docs/dev-reports/product-reply-20261010.md`：T20 的 7 处使用频率文字清单；App 里没有 PHQ-9；告警来源“AI 回复扫描”会露出组别，后备收件人是否要盲待定。
- 10/8 交接 R1–R9 的去向写在 `docs/dev-reports/开发窗口交接-1010.md`。原件找不回来，负责人定以这份重建版为准。
- 同日按 `dev-tasks-1010.md` 开了 T21、T26（在 PR #52 分支上续做）、T31、T33 四个会话。

## 2026-10-10 T33 定稿文字接入（PR 草稿）

- 规则组模板换成定稿 41 条，结构改为「陪伴者 × 五档心情」，没选心情用 G-1，回忆里的哀伤内容用 Z5（决策 0032，部分取代 0023）。
- 短文字接入：S1a（通通固定回应）、S2（新 prompt 文件 v2）、S3（人生點滴入口，无开关）、S4a（行动计划提醒推送）、S5（入组引导最后一屏，开关默认关）。
- 同日按 `dev-tasks-1010b.md` 的 T33 更正：文字换成研究侧改正错字后的版本，去掉“待确认”标记；S5 改放入组引导；T20 的 7 处不动。
- 发现网页版构建 `newTurnId` 的错误（Android 不受影响），记入 backlog 第 95 项。
- 报告：`docs/dev-reports/T33-final-copy-20261010.md`。

## 2026-10-10 T31 记忆分层（PR 草稿，分支 `feat/memory-layers`）

- 记忆分共享层和私有层，按研究侧 10/9 第 15 条：作息、兴趣、喜好加入共享；心事、健康、哀伤、回忆、待跟进私有。服务器写 `layer`、`sourceAgent`，按陪伴者过滤；旧条目读取时推算，不迁移。决策 0035（0032 不确定、0033 是 T26、0034 是 Phase A 暂停）。适用 Phase B Hybrid 组（含试跑）；`event` 归私有已由研究侧确认。
- 设置里删一条会连带删其他陪伴者的私有副本和引用它的摘要；记忆剂量按层计。
- 抽取 prompt v3 写好、没切换；用 T4 的 30 段合成对话跑了一遍（26 次真实调用），结果在 `tool/memory_eval/results/t31_v3_run1/`。
- 开关 `layersEnabled`、`memoryLayersNoticeEnabled` 默认关。报告 `docs/dev-reports/T31-memory-layers-20261010.md`。

## 2026-10-10 产品窗口 10/9 第 13–29 条、10/10 第 1–5 条排进第七批（T30–T33）；登记表 v7；定稿文字导入

- **定了**：研究期按登记编号前缀（`PA-`、`PB-`、`PILOT-`），登记前只显示等待页、不收研究数据，两期都由负责人登记；分配序列由 Calvin 生成、上传和保管，负责人的账号读不到序列；语音只用 `asia-southeast1`，失败重试 1 次后提示改打字，不开数据记录；Phase A 用同一个最终构建；第 4 周问卷第 26 天开、第 29 天或 W4 面访当天关，PGIC 第 35、42、49 天；记忆分共享层和私有层；整人删除时保留一行分配记录；分析导出不含对话原文。
- 登记表 v7（合并统筹会话的 v5 和开发窗口的 v6、v7）。任务单：`dev-tasks-1009.md` 第三版（T24 研究周和每周问卷）；`dev-tasks-1010.md`（顺序、对 T21–T29 的更正、新任务 T30 角色和导出、T31 记忆分层、T32 Phase A 最终构建、T33 定稿文字接入）。`dev-tasks-1009c.md` 作废，没有放进仓库。
- 定稿文字导入 `docs/spec/copy/`：规则组 41 条模板、短文字 S1a–S12。原文照录；疑似错字（侾、傳、諦、゗、捣、鐘意）研究侧确认前不上线。
- 第一轮内部实机测试指引 `docs/release/internal-test-1010.md`（只限团队，不找老人）。
- T 编号和登记表只由开发窗口改，统筹会话只执行和写报告。PR #49（旧编号 T24 的 LoRA）已由 #52（T26）取代。

## 2026-10-10 陪伴者图片：透明背景；阿珍、阿伯改紫色

- 8 张陪伴者图片原来把灰白格子画在图里（不是真透明），已改成真正的透明背景，人物不变。
- 阿珍（薄荷绿）和通通撞色。负责人看了几套预览（淡紫、奶茶、雾蓝、藕紫、蜂蜜黄），选了藕紫，并要求不要调浅颜色。阿珍改藕紫、阿伯改灰紫，只改色相；代码里的主题色和首页卡片颜色跟着改。决策 0031。
- `IMAGES.md` 改写成现在的机械人形象说明，删掉过时的真人肖像出图要求。
- 表情（阿珍半闭眼、阿伯垂眼）没改，要改得重画。

## 2026-10-10 T26 补充：Phase A 和试跑也用（PR 草稿 #52）

- 按 `dev-tasks-1010.md` 第三节：分类器两期和试跑同一套。先把 main 合进分支。核对代码本来就不分研究期（App 两种构建都读同一个开关，服务器不读研究期），只补了测试（App 两种构建都跑；服务器用 Phase A、Phase B、试跑的合成账号），决策 0033 补第 7 条。
- 发现：研究员电话代填的 Phase A 问卷文字只查词库（backlog 87）；T21 拆配置时分类器开关不能分期（backlog 88）。

## 2026-10-09 T26 LoRA 两组共用（PR 草稿）

- 按 10/8 第 1 条写决策 0033：安全分类器两组共用，取代 0025 里"两组是否都用"的部分（0025 顶部标 Superseded）。只给级别和分数，只触发两组相同的安全流程；`assertLlmAllowed` 不动。
- 核对记录字段：`safety_classifier_calls` 和 `safety_events` 已有同一个编号（`turn_id` / `turnId`），但消息记录 `turns` 里没有。补了 `turns.safetyTurnId`，两组都写。
- 上线清单加 H 节（地址、鉴权、部署机器等）。开关仍默认关。报告 `docs/dev-reports/T26-lora-both-arms-20261009.md`。

## 2026-10-09 T22 旧 agent_diff 收尾（SPEC:C15、C22，PR 草稿，未合并）

- **做了**：新版盲法导出不再导出旧的“陪伴者区分评估”（`agent_diff`），清单里列为“揭盲前不导出”，检查脚本见到它会报错。Phase A 打开 `adaEnabled` 后不弹旧问卷，T17 已经做了，这次补了测试。没有新开关。
- 没删旧集合、旧页面，没动已有数据。报告：`docs/dev-reports/T22-legacy-agent-diff-20261009.md`。待办第 78–79 项。

## 2026-10-09 产品窗口 10/8 交接和 10/9 决定排进第六批（T25–T29）；登记表 v5

- **定了**（10/9 第 1–3 条和补充）：盲法导出维持决策 0021，数据收集期间不含 Brief PR 和每人会话数，另做全体合并的完成率；语音改为 App 录音上传服务器 STT v2（`chirp_2`，`asia-southeast1`），只存文字，失败退 global 区先做成配置项；有效会话按"完成一个互动单元"（自由聊天 3 条消息，签到和回忆按完成模块流程，规则组一次提交算一次，决策 0015 保留）；LoRA 两组共用；试跑编号 PILOT-01 起、不收集收款资料。
- 登记表在 v4 上改为 v5（C13、C14、C16、C18）。任务单 `docs/dev-tasks/dev-tasks-1009b.md`：T25 会话与 Brief PR、T26 LoRA 两组共用、T27 语音改走服务器、T28 试跑支持、T29 操纵检验抽样导出。第四、五批（`dev-tasks-1008.md`、`dev-tasks-1009.md`）照 T22 → T21 → T24 → T23 的顺序做。
- 统筹会话的现状报告 `docs/dev-reports/product-reply-20261009.md`：记忆读写和共享、Brief PR 字段缺口、STT 现状（App 现用手机系统识别，不经服务器；录音上传代码 main 上没有）、Hybrid 签到和回忆的流程及有效会话提议、产出窗口 24 条核对。
- 之前统筹会话按自己的编号开的三个会话（T21、会话与 Brief PR、LoRA 和探针）和第四批计划冲突，已停掉；LoRA 那个留下一个没开 PR 的分支 `feat/lora-both-arms`，T26 改用 `feat/lora-both-arms-v2`。

## 2026-10-07 T19、T17b 合成一个 PR

- T19（分组重做）和 T17b（ADA 按 `docs/spec/instruments/ada.md` 补做）各一个云端会话，合成这一个 PR。交接文档 `docs/dev-reports/T19-T17b-handoff-20261007.md`。
- 合并时的衔接：T17b 的研究员页面和 `adaStaff*` callable 改认 T19 的新角色（`blinded`、`unblinded`；研究编号只给 `unblinded`），旧名 `pi`、`researcher` 不再有权限；整人删除脚本同时覆盖 `enrollments`、`llm_denied_log`、`ada_status`。
- **部署即生效、不受开关控制的三处**：旧角色账号失去权限，要按新角色重发；发给 PI 的告警只剩研究编号、级别、时间、编号；分组计数器客户端不能读写。分组开关 `meta/randomization_config.enabled` 必须在第一位 Phase B 老人注册前打开。

## 2026-10-07 T19 App 内分组重做（SPEC:C01，PR 草稿，未合并）

- **现状**：注册时 `assignArm` 按 UCLA × 年龄 4 层最小化分配（少的那组优先，一样多抛硬币），分层变量是老人自填的；计数器 `meta/arm_counter` 客户端仍能写增量；`role: pi` 是非盲角色；给 PI 的告警邮件带来源和陪伴者。
- **做了**：研究员登记页（非盲研究员登录后直接进入）+ Cloud Function `enrollParticipant`：按 W0 DJG 情感分分层、置换区组序列、事务分配、分配日志、重复提交不重抽、脚本更正；序列生成和上传脚本（种子不进仓库、不上传）；最小化分配删除；角色改名 `unblinded` / `blinded`，PI 为盲法；给 PI 的告警去掉能推出组别的字段；W0 日期优先用登记日；规则组 LLM 被拒记日志。开关 `meta/randomization_config.enabled` 默认关。决策 0029（取代 0003）。
- **测试**：72 个合成参与者，两位研究员同时提交，每层最大人数差 2，没有重复占位；客户端读写序列、分组、计数器、日志都被拒；盲法导出没有组别。
- 报告：`docs/dev-reports/T19-randomization-20261007.md`。待办第 72–74 项。

## 2026-10-07 T17b ADA 按定稿规格补做（SPEC:C22，PR 草稿，未合并）

- **做了**：按 `docs/spec/instruments/ada.md` v1.0 改题目（粤语原文、版本 `ada-v1.0-20261007`）、名字旁加头像；短版改为 B + D；第 1 次到访最后选第 7 日提醒时间；第 7 日 ADA 和开放题合成一个流程（进度、中途停、接着做、求助按钮）；服务器第 7 日推送、24 小时再提醒、第 9 日后记超时（推送文字是占位，不发）；研究员页面看完成情况、电话代填（`phone_by_staff`），代填文字服务器做安全检测。决策 0030。
- **做法上的选择**：研究编号不写进老人能读的答案文档（决策 0021），放在服务器专用的 `ada_status`；没配置求助电话时不拨号、只弹说明；研究员权限先用现有 `researcher` / `pi` 角色，T19 改角色时对上。
- 开关仍默认关，PI 书面确认截图前不打开。报告：`docs/dev-reports/T17b-ada-v1-20261007.md`。待办第 75–77 项。

## 2026-10-07 #39、#40、#44 合并；盲法人员和 ADA 定稿

- PR #44（第三批 T17、T18、T20）、#40（T10）、#39（T8）都已合并。#39、#40 合并前先合了 main 解决冲突；合 main 后 T17 的 ADA 测试因 T8 改了安全事件接口而编译不过，已照 T8 的写法改好测试；#40 先合进 #39，避免第二轮文档冲突。
- **研究侧定了盲法人员**：非盲研究员是 Keran（登记入组、触发分组、按组引导、生成和上传分配序列）；PI（Junyu）是盲法评估者。T12 把 `role: pi` 设成了非盲角色，T19 里改（待办第 46 项）。
- **ADA 定稿**放进 `docs/spec/instruments/ada.md`：A 部分回忆窗口改为"過去 7 日"、选项改为次数；第 1 次到访短版 B + D，第 7 日全版 A + B + C + D；第 7 日在家用 App 填，有提醒、进度、中途保存、求助电话、电话补做（`phone_by_staff`）和研究员页面的完成情况；上线前 PI 审截图。T17 按它补做。
- 任务单 `docs/dev-tasks/dev-tasks-1007b.md` 更新为研究侧 10/7 的新版。

## 2026-10-07 T10 记忆修复，重跑 T4（SPEC:C05，PR 草稿，未合并）

- **做了**：服务器用 App 同一份安全词库查老人原话（`functions/safety_lexicon.json` 从 Dart 词库生成，测试保证一致），命中的轮次不进记忆、那次会话不写摘要；摘要不写敏感内容；「唔好記住」用规则 + 关键词识别，整段不记并删除相关旧条目；页面删一条连带删摘要；`tool/delete_memory.js` 写 `memoryWithdrawnAt`，之后 Phase B Hybrid 组也不再记录。顺带修了称呼混进陪伴者名字、更新错类别、计划重复记成事实、敏感事实没有名额。抽取 prompt 改为文件，新版 v2。决策 0024。
- **重跑 T4**：真实 DeepSeek 共 104 次调用。前两轮发现评测脚本自 T11 起没给测试用户写共享同意（实际按「各看各的」跑），以及两处可修的问题，修好后再跑两轮作为验收；最后一处（同一句话存两次、删一条还剩一条）用录下的模型输出重放验证。验收 6 项里 5 项通过；「编造为 0」按标准答案口径第 3 轮有 1 条（孙子的玩笑），按凭空捏造口径两轮都是 0。
- 第二位判定人用的表：`tool/memory_eval/second_rater_t10.csv`（220 行，不含第一位的判定）。
- 报告：`docs/dev-reports/T10-memory-fix-20261007.md`。待办第 55–57 项。

## 2026-10-07 研究侧答复交接方案；第三批 T17、T18、T20 合成一个 PR

- **研究侧 10/7 答复**（`docs/dev-tasks/dev-tasks-1007b.md` 开头的表）：DJG 用 6 条版，W0、W4 由 PI 当面纸本、W8 电话或视频，都不进 App，W2 在 App 内做全部 6 题；LSNS-6 不用；UCLA 是纸本；SUS 和 Phase A 第 7 日问卷等 EA260417 批复；ADA 只用于 Phase A；每周孤独探针不修，保持关闭；分组重做（T19）；Phase A、Phase B 配置分开（T21）；建议每天用、每周至少 5 次、不强制。PI 的几项（三条 prompt、热线号码、间接自伤说法进词库）还在等。
- 登记表 v2 放进 `docs/spec/feature-registry.md`（负责人直接在 main 上提交）。C14 改为一致；C15 去掉孤独探针、ADA、LSNS-6；C12 的 5-flag 改为 H4 暴露标记。
- 第三批任务单 `docs/dev-tasks/dev-tasks-1007b.md`（T17–T21）。T17、T18、T20 各一个云端会话并行，合成这一个 PR；交接文档 `docs/dev-reports/T17-T20-handoff-20261007.md`。T19 等 #39、#40 合并后开；T21 用 T19 的研究员登记入口，排在 T19 之后。
- 合并时的衔接：首页问卷提示同时带第 2 周 DJG、ADA 和第 7 日开放题，第 2 周 DJG 打开时替换旧 DJG，旧"陪伴者区分评估"只在允许的版本出现；Firestore 规则三个新集合各有一段，并都排除在通用的"本人可读写"规则之外；App 启动时的配置读取改为同时进行（最多等 3 秒，原来依次读最多 12 秒）；修了 CI 脚本合并时漏掉的换行符；删掉上传时多出的登记表副本。
- 合并后本地跑了全部测试：后端（Functions、规则、模拟器、删除脚本、同意脚本）全过；App 六套构建变体全过；`flutter analyze` 没有 error。

## 2026-10-07 T17 ADA 进 App（SPEC:C22，PR 草稿，未合并）

- **现状对照**：App 已有“陪伴者区分评估”（agent_diff，第 14、28 天，两组、两种构建都出现）。题目来源和附件 C 相同，但一页一个矩阵、不能跳过、不逐屏保存、没有表单版本和输入方式，D 题不同。决定新做，不改旧的（决策 0026）。
- **做了**：新 ADA 页面（一屏一项，短版/全版，可返回、每屏保存、可跳过），第 7 日 3 道开放题（同一个长文字组件，麦克风跟随语音开关）；时间点、版本、回忆窗口从 `app_config/phaseA_schedule` 读，默认全关；Phase B 构建一律不显示。新集合 `ada_responses`、`day7_open_responses`：只有本人能读写、提交后锁定、整人删除脚本覆盖、不进盲法导出。两处文字经 `SafetyService`。
- **顺带修正**：Phase B 构建不再出现旧 agent_diff（登记表 v2 C15），开关 `LEGACY_AGENT_DIFF_PHASE_B` 默认关。
- 报告：`docs/dev-reports/T17-ada-20261007.md`。待办第 61–63 项。

## 2026-10-07 T20 使用建议的文案（PR 草稿）

- 研究侧定了"建议每天用、每周至少 5 次、不强制"，措辞等 ICF 定稿。
- App 里提到使用频率的 7 处文字改为先读 `app_config/usage_copy`，没有定稿时显示原文（决策 0028）。两组相同，没有新增提醒。
- prompt 和规则组模板里相关的说法只列出、没改，见 `docs/dev-reports/T20-usage-copy-20261007.md`。

## 2026-10-07 T18 第 2 周 DJG 改为 App 内全 6 题（SPEC:C15，PR 草稿，未合并）

- **查清现状**：App 里原有的 DJG（`djg_es`，6 条粤语草稿、第 14–16 天一次、`timepoint: "week2"`）就是 W2，所以按任务单替换；旧集合、旧数据、旧页面都保留，Phase A 构建行为不变。
- **做了**：新集合 `djg_responses/W2`；题目和「是 / 大致是 / 不是」照抄问卷包 §3；一屏一题、可返回、可跳题；W0 起第 14 天推送和首页卡片，窗口第 14–20 天，24 小时提醒一次，过窗口记缺失；分数由服务器算（跳题的分量表记缺失），客户端不能写分数；W2 进盲法导出白名单。决策 0027。
- **开关**：`app_config/phase_b.djgW2InAppEnabled`，默认关，还要 Phase B 构建。推送文字是占位，未定稿服务器不发。
- 报告：`docs/dev-reports/T18-djg-w2-20261007.md`。待办第 64–66 项。

## 2026-10-07 开发任务 T7–T15 合成一个 PR

- 第二批里已完成的 8 个任务（T13、T7、T9、T12、T11、T15、T14、T16）合成一个 PR，下面各段是各任务自己的记录。T8、T10 等这个 PR 合并后再开。
- **T16 记忆使用画像**（只有报告和脚本，`docs/dev-reports/T16-memory-profiles-20261007.md`、`tool/memory_profiles/`）：4 种合成画像各跑 4 周，真实 DeepSeek。2,000 字注入上限从没碰到，真正的限制是 20 条事实、3 个摘要日、1 条跟进；普通事实满 20 条后已确认的敏感事实不再注入；App 缓冲区只留最近 10 轮，长对话前面的内容抽不到；事实只增不减、矛盾两边都保留；同一件事反复生成跟进。待 T10 一并处理。
- 合并时的衔接改动：T15 的签到 B、回忆 B 改用 T7 的统一安全入口（每次提交只写一条安全事件）；整人删除脚本加上 T7 的 `hotline_filter_log` 和 T12 的研究编号对照表（`research_id_map`、`research_ids`）；T9 的 prompt 测试改为期望 T7 追加的 `+hotline_rule.v1` 版本后缀。
- 合并后在本地跑了全部测试：后端（Functions、规则、模拟器、删除脚本）全过；App 六套构建变体全过。

## 2026-10-07 T8 安全分类器接口（PR 草稿，未合并）

- 在统一安全入口 `SafetyService` 后面加了一个分类器槽位，给研究侧的 LoRA 模型预留，两组相同。经新的 Cloud Function `classifySafety` 中转，只返回级别和分数；只升不降；超时 1.5 秒或失败只用词库，并记 `safety_classifier_calls`。
- 冲突：规则组「永远不能调用 LLM」。做法是独立的分类接口，不经过、也不放宽 `assertLlmAllowed`。是否接受由研究侧和 PI 定（决策 0025，提议中）。
- 开关 `app_config/phase_a.safetyClassifierEnabled`、`meta/safety_config.classifierEnabled` 都默认关；关着时检测仍是同步的，行为不变（有测试）。用本地假模型测了正常、超时、失败。
- 报告：`docs/dev-reports/T8-safety-classifier-20261007.md`。待办第 58–60 项。

## 2026-10-07 T13 小修与上线配置（PR 草稿，未合并）

- **C01**：Firestore 规则改成分组字段（`arm`、`strataCell` 和三个 `armAssigned*`）只有服务器能写；客户端不能删自己的用户文档（决策 0022）。App 正常注册走 `assignArm`，不受影响；规则测试按新规则改写并补了用例。
- **C07**：新增定时函数 `dispatchReminders`，把 App 写进 `reminders` 的行动计划提醒推送出去，两组相同，开关默认关（决策 0022）。
- **上线配置**：新增 `tool/prelaunch_config.js`（写 `meta/memory_config`、`app_config/arm_assignment`，可选清零计数器；默认只对模拟器执行）和 `docs/release/prelaunch-checklist.md`。
- **C06**：怀旧入口「6 個主題、6 個禮拜」改为按实际主题数显示（4），单独一个提交，等研究侧确认文案。
- 报告：`docs/dev-reports/T13-prelaunch-20261007.md`。

## 2026-10-07 T7 安全加固（PR 草稿，未合并）

- **做了**：所有自由输入两组都经同一个安全检测入口 `SafetyService`；补上 7 处没带用户编号的 AI 调用；`safety_events` 每条带 `source`、`inputPoint`、`turnId`，一轮对话只算一条；Hybrid 组 AI 回复里的电话号码在服务器和 App 各过滤一次，换成危机页链接，并记 `hotline_filter_log`；prompt 加「不写电话号码」规则 `hotline_rule.v1`；搜一搜命中安全词时不发出搜索。决策 0018。
- **开关**：`safetyScanAllInputs`、`hotlineFilterClient`（`app_config/phase_a`），`hotlinePromptRule`、`hotlineOutputFilter`（`meta/safety_config`），默认都开。
- 报告：`docs/dev-reports/T7-safety-hardening-20261007.md`。

## 2026-10-07 T9 关闭搜一搜和语音输入（SPEC:C18，PR 草稿，未合并）

- **查清现状**：搜一搜在 App 里 2026-07-20 起写死关闭，老人触发不了；但服务器 `webSearch` 还开着，只拦规则组。语音两组都开着，没有开关。
- **做了**：新建配置 `app_config/feature_flags`，三个开关全部默认关（决策 0019）。关时 App 不显示麦克风和"幫我查"按钮、不发请求；服务器 `webSearch`、`transcribeAudio` 直接拒绝。语音代码保留，HREC 批准后在控制台打开。
- 通通遇到要上网查的问题有一句固定回应，两组条件相同，先过安全检测；文字是占位，开关默认关。
- 负责人决定通通 prompt 去掉"幫你查"邀请：新建 `tung_tung.v2.txt`，服务器按注册表加载，`tung_tung_v1.txt` 保留。待 PI 审核。
- 报告：`docs/dev-reports/T9-flags-20261007.md`。待办第 40–42 项。

## 2026-10-07 盲法（T12，PR 草稿，未合并）

- 新版盲法导出：每人一个跨周不变的研究编号（分组时由服务器生成），组别代码整个研究期间固定，只导出两组都答的结局量表；对话轮次、会话、事件、LLM 和记忆相关集合揭盲前不导出（决策 0021）。
- 研究编号对照表 `research_id_map`、`research_ids`，只有非盲角色（`role: pi`）能读。`meta/arm_counter` 也改为只有非盲角色能读。
- 研究者后台：`researcher`（盲法）看不到两组人数和只有一组才有数据的板块；`pi`（非盲）看全部。
- 新增检查脚本 `tool/check_blinded_export.js`，有可疑字段就非零退出，测试里跑。
- 开关 `meta/blinding_config.enabled` 默认关，关着时旧导出照旧。报告：`docs/dev-reports/T12-blinding-20261007.md`。

## 2026-10-07 T11 隐私、同意与删除（PR 草稿，未合并）

- 「共享上下文」同意接上代码：开关 `app_config/phase_a.enforceSharedContextConsent`（默认关）打开后，没同意的人每个陪伴者只用自己的记忆。App（记忆 v0）和服务器（记忆 v1，`functions/memory.js` `effectivePolicy`）读同一个键（决策 0020）。
- 「保留对话」和「共享」的默认值改为从 `app_config/phase_a` 读，默认保持现状。
- 新增 `tool/delete_participant.js`：整人删除，默认试运行，`--confirm` 才删，删完复查，存证只有数量。周度导出文件默认只数不改。在 Auth + Firestore + Storage emulator 上测过，加进 `tool/ci_backend_tests.sh`。
- **发现**：设置页「保留對話紀錄」开关没放进页面，老人关不掉；隐私页多数说法与实际不符（草稿在报告里，没改 App 文字）。
- 负责人随后定了两件事：已导出的盲法文件保留不动（ICF 的写法依赖 T12）；隐私页直接改成简短、准确的版本，细节交给同意书（单独一个提交，等负责人确认文案）。
- 负责人又确认：共享同意统一打开（默认开、迁移现有账号、不愿意的由后台按人关闭，新脚本 `tool/set_shared_context_consent.js`）；设置页放回「保留對話紀錄」开关。顺带修了 App 保存资料时把旧的 `sharedContextUse` 写回去的问题。
- 报告：`docs/dev-reports/T11-privacy-consent-20261007.md`。待决定见 `docs/dev/backlog.md` 第 43–45 项。

## 2026-10-07 T15 规则组签到、回忆的模板回应（PR 草稿，未合并）

- 规则组小欣签到、阿珍/阿伯回忆提交后，按心情从模板池给一条回应，样式和 Hybrid 组同页面的气泡一样（决策 0023）。目的是让三个陪伴者在规则组都有「输入 → 回应」。
- 放在编译开关 `RULE_TEMPLATE_REPLIES` 后面，默认关；关时两页和现在一样。模板全是【占位】文字，有占位时开关不生效。
- 回应前先做安全检测，命中 moderate 或 acute 不给模板，走原来的安全流程。检测集中在 `lib/features/rule_replies/rule_reply_safety.dart`，写成 T7 `SafetyService` 的用法，T7 合并后替换。
- 回忆 B 加了一个选填的心情脸（Hybrid 回忆没有心情输入）。
- 报告：`docs/dev-reports/T15-rule-based-replies-20261007.md`。

## 2026-10-06 开发任务 T1–T6；DeepSeek 模型名

- 研究侧功能登记表（C01–C22）放进 `docs/spec/feature-registry.md`，任务单放进 `docs/dev-tasks/dev-tasks-1006.md`。T1–T6 分六个云端会话并行执行，报告写到 `docs/dev-reports/`、`docs/spec/`、`docs/export/`。
- 云端环境接入 DeepSeek（凭据由代理注入，会话里看不到密钥），供 T4、T6 用合成对话测试。
- **发现**：代码请求的 `deepseek-chat` 实际返回 `deepseek-flash`（DeepSeek-V4.1-Flash），模型列表里已没有 `deepseek-chat`。研究文件里写的 DeepSeek-V3 不准确。
- **决定**：请求改为 `deepseek-flash` 并关闭思考模式，实际模型不变（决策 0017）。不关思考的话，转介判断会返回空内容。
- 六份产出合成一个 PR：T1 `docs/spec/audit-20261006.md`；T2 `docs/dev-reports/T2-data-dictionary-20261006.md`；T3 `docs/export/20261006/`；T4 `docs/dev-reports/T4-memory-acceptance-20261006.md` 和 `tool/memory_eval/`、`functions/test/memory_acceptance_emulator_test.js`；T5 `llm_calls` 记录（见下一段）；T6 `docs/dev-reports/T6-safety-parity-20261006.md`。每份报告都由另一个会话对照代码复核，复核意见已改正。
- **主要发现**：登记表 22 项里一致 6、不一致 10、缺失 1（C13 LoRA）、无法判断 1、待定 4；记忆验收整体不通过（编造不为 0、准确率 81.8%，跨 agent 泄露为 0）；词库对间接自杀表达召回低；ICF、DMP 有多处与代码不符。待决定事项见 `docs/dev/backlog.md` 第 25–36 项。

## 2026-10-06 模型版本记录（C04，PR 草稿，未合并）

- 服务器上所有 DeepSeek 请求改走 `functions/llm_log.js` 的 `deepSeekChat`，每次调用在 `llm_calls` 写一条：返回的 `model`、token 数、延迟、是否出错，不存原文（决策 0016）。
- 新增 Firestore 规则：`llm_calls` 客户端不能读写。
- 新增测试：`functions/test/llm_log_test.js`、`functions/test/llm_calls_emulator_test.js`、`test/rules/llm_calls_rules.test.js`。
- 真实调用冒烟测试（`functions/test/llm_live_smoke.js`，手动跑）。最初请求 `deepseek-chat`，返回的 `model` 是 `deepseek-flash`；合并决策 0017 之后请求 `deepseek-flash`、思考关闭，返回的也是 `deepseek-flash`，都正确写进日志。
- 按统筹会话补充和复核：日志加 `system_fingerprint`、`reasoning_tokens`、`http_status`；`model_requested` 从实际请求体读；`agent_id` 只接受三个陪伴者；DeepSeek 请求加超时；写日志最多等 2 秒。
- 合并了决策 0017 的分支（模型名改为 `deepseek-flash`，思考关闭）。`functions/test/deepseek_request_test.js` 改为检查 `llm_log.js` 是唯一发请求的地方。
- 报告：`docs/dev-reports/T5-model-logging-20261006.md`。

## 2026-10-04 规则组 Brief PR

- 签到 B、回忆 B 每次提交记为一次会话（`sessions` / `turns`），提交后弹 Brief PR（决策 0015）。之前这两个页面从不弹，两组结局测量口径不同。
- 签到 B 的安全提示改走统一的 `DistressRouter`：之前 acute 只弹一个写死热线的对话框，不进危机页。
- 首页「今個星期傾咗 N 次」统一从 `sessions` 统计。
- 讨论：规则组自由对话的非 LLM 方案、「我的資料」规则组内容、口头删除的替代方案（待负责人选）。

## 2026-10-04 文档整理

- 负责人提供的文档框架（`docs/README.md`、`STUDY_CHANGELOG.md`、决策记录模板、0001、记忆研究对齐文档、记忆开发规格）放进仓库。
- 补写之前在对话里做的决定：决策 0002–0014。
- 新增 `docs/dev/architecture.md`（技术文档）、本文件、`docs/dev/backlog.md`（待办）。
- `docs/memory-v1.md`、`docs/ci-cd.md` 移到 `docs/dev/`；2026-09-29 的架构说明移到 `docs/history/`，作为历史快照。
- 根目录新增 `CLAUDE.md`，写入文档规则。
- **安全词库**：PI 签核搁置，先沿用 v5（决策 0012）。

## 2026-10-01 记忆 v1 合并；分组标记的决定

**合并 PR #24**（服务器分组）和 **PR #25**（记忆 v1），都还**没有部署**。

PR #24：
- 分组改由 Cloud Function `assignArm` 在服务器上做（决策 0003）。
- Flutter 固定为 3.35.3。原因：CI 用的 3.47 要求 Gradle ≥ 8.14，项目是 8.12，打包失败。
- 打 APK 时带上 `TESTER_PIN`；加 PR 模板。
- 首页「今個星期傾咗 N 次」改为统计所有聊天（之前只算签到）。
- 规则组隐藏阿珍/阿伯自由对话入口（决策 0006）。

PR #25：
- 服务器端记忆 v1：会话摘要、事实、待跟进；原话校验；共享策略 C；「我記得嘅嘢」页面；注入日志。实现见 `docs/dev/memory-v1.md`。
- Phase B Hybrid 组强制开启（决策 0007）；敏感事实页面确认（决策 0008）；约诊不算敏感（决策 0009）；保留 3 年（决策 0010）。
- onboarding 第一页加记忆说明。
- 注册后立即生效（修了要重启 App 才生效的问题）。
- 删除脚本 `tool/delete_memory.js`。

**讨论**：
- 负责人一度想只保留 Phase B、丢弃 Phase A。随后改为：现有账号标 `pilot`，Phase A 仍单独招募，但版本和 Phase B 同步（决策 0011）。
- 负责人整理了研究设计层面的记忆文档（决策 0001：记忆属于 Hybrid 组干预包），并开始调研记忆架构。

## 2026-09-30 Phase B 补齐；CI 修复

- **合并 PR #22**（`youthful-heisenberg`，Phase A 基线）：词库 v5、安全回应模板统一（`SafetyCopy`）、会话和轮次记录（`sessions` / `turns`）、测试人员 PIN、日程模拟器、修好 `functions/package-lock.json`。
- **合并 PR #23**（Phase B 基础 + CI/CD）：见 2026-09-29。
- 讨论并决定：分组为空时显示规则组（决策 0004）；记忆 v1 在 Phase B 默认打开（决策 0007、0008）。
- CI/CD 讨论：负责人同意走 PR 流程合并；测试用例表暂缓；不需要单独的 staging Firebase 项目。

## 2026-09-29 Phase B 基础

起点：读负责人的《陪住 记忆模块 技术交付文档 v0》，对照代码梳理现状。当时的完整说明见 `docs/history/2026-09-29-phase-b-switch.md`。

**做了**（PR #23）：
- Phase B 编译开关 `PHASE_B`。之前 `Arm.of` 写死返回 A。
- 服务器防线：`proxyDeepSeek`、`referralJudgement`、`webSearch` 拒绝规则组。
- 分组只能写一次；修了「分组被抹掉、下次登录重新抽签」。
- 修好分组计数器的 Firestore 规则：原规则超过规则引擎 1000 个表达式的上限，**所有**计数写入都被拒绝，注册流程吞掉了错误，所以没人发现。
- 被安全标记的轮次不进记忆（决策 0013）。
- 规则组不预生成首页问候。
- 通通规则组版本（决策 0005）。
- 规则组安全事件通知 PI（决策 0014）。
- GitHub Actions：CI、Build APK、Deploy Firebase。

**讨论**：
- 规则组要不要单独一个仓库：不要（决策 0002）。
- 同一个仓库可以多个分支并行开发：记忆 v1 在 `claude/memory-v1` 分支单独开发，后来合并。
- 记忆文档 v0 写「Phase A/B 一律关」，和代码里已有的 v0 滚动摘要冲突。当时的处理：v0 保持，v1 单独开关。后来被决策 0001、0007 取代。

## 2026-09 之前

Phase A 基线版本的开发、评审和交付记录在 `docs/release/`：
- `phase_a_review_2026-09-17.md`：基线评审；
- `phase_a_baseline_handback.md`、`phase_a_baseline_versions.md`：交接和版本；
- `phase_a_deploy_workflow_mac.md`：Mac 上的部署流程。

更早的开发笔记在仓库根目录（`ARCHITECTURE_NOTES.md`、`STATUS.md`、`REPORT.md` 等），部分已过时。分组方案的方法学讨论在 `docs/research/arm_assignment_scheme_v1.md`（2026-07）。
