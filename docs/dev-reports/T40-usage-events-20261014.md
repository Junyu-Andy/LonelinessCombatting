# T40 使用事件记录 报告（2026-10-14）

分支 `feat/usage-events`，从 main `c1f88d6`（#75 之后）开。SPEC:C23。PR 草稿。依据：`docs/dev-tasks/dev-tasks-1014d.md` T40 和第 0 节第 6、7 题；`handoff-20261014.md` 第三节第 6、7 题的初答；登记表 v10 C23（没有改它）。只用模拟器和合成数据，没有连生产；没有改热线、IAM、feature-registry。

## 结论

1. **第 6 题（有没有前台 / 后台事件）正式答案：有，但不够用。** `lib/app/app.dart` 在 App 生命周期变化时往 `users/{uid}/events` 写 `app_foreground` / `app_background`。缺四样：① 行里的 `timestamp` 被 `FieldValue.serverTimestamp()` 覆盖（`analytics_service.dart` `_persist`），**手机时间没有留下**，所以“第一次打开是几点”在离线补传时会错；② 没有构建版本号；③ 没有补传标记；④ 登记前照记（只要登录了就写）。所以 T40 要做，范围按 1014d 和交接建议收窄成“补齐缺的字段 + 开关”。
2. **第 7 题（离线怎么处理）正式答案：不会丢。** App 的 Firestore 写入都是 fire-and-forget，SDK 的离线持久化默认开着：断网时写到手机本地队列，联网后按原顺序补传，`serverTimestamp` 字段到服务器才取值。所以“手机时间”字段只要 App 自己写、不用 `serverTimestamp`，补传后就是原来的时间。缺的只是“这条是补传的”标记——客户端自己判不可靠（离线时 App 被杀掉，标记就丢），改由服务器比较两个时间。
3. **做了什么**：新子集合 `users/{uid}/usage_events`，开关 `app_config/feature_flags.usageEventsEnabled`（**默认关**）。开着时，已登记的账号每次进入前台、退到后台各写一条；服务器触发器补研究编号、香港日期、研究第几天、`uploadedLate`。老人看不到任何变化，两组相同（代码不看组别）。关着时什么都不写，其他功能不受影响；原有的 `events` 行照旧（没有动 Phase A 的分析管线）。
4. **为什么是新集合而不是在 `events` 上补字段**（交接建议是后者）：`events` 每天几百行（翻页、推送、按钮），T39 看板按人按日聚合只要这两种事件，单独一个小集合便宜、规则也能收紧（本人只能新建、不能读）；旧行没有手机时间，混在一起看板还是要分两套口径。决策草稿见第 7 节。
5. **验收**：四条验收里 1、3、4 在模拟器和单元测试里过了；第 2 条“关网切换三次再联网”涉及手机的离线队列，模拟器做不到，**要在 W0 装机或试跑第一周用真机做一次**（步骤在第 5 节）。服务器那半（三条晚到的行都标 `uploadedLate: true`、手机时间不变）在模拟器里过了。
6. **时限**：要进 10/19 冻结前的构建；合并后要部署规则和 Functions。PILOT 老人 10/15 装的包如果没有它，这段时间 T39 用“当天有无会话”的后备口径并标“旧构建口径”（1014d 第 7 条）。

## 1. 开关和配置

| 键 | 在哪 | 默认 | 作用 |
|---|---|---|---|
| `usageEventsEnabled` | `app_config/feature_flags` | **关** | App 端：开才写 `usage_events`。登录后和其他开关一起重读（10/14 修复），所以新装 App 登录后就生效 |
| 补传判定 5 分钟 | `functions/usage_events.js` `LATE_AFTER_MS`（常量） | 5 分钟 | 服务器收到时间比手机时间晚 5 分钟以上 = 补传。开发实现细节，Junyu 有异议再改成配置 |

服务器触发器没有开关：没有行就不触发；有行就补字段，无害。

## 2. 数据：`users/{uid}/usage_events/{自动编号}`

| 字段 | 谁写 | 含义 |
|---|---|---|
| `type` | App | `foreground`（进入前台，含冷启动）/ `background`（退到后台、被隐藏、被杀前） |
| `clientAt` | App | 手机时钟的时间（Timestamp）。补传时**不变** |
| `receivedAt` | App 写 `serverTimestamp` | 服务器收到并提交这条写入的时间；离线补传时就是补传那一刻 |
| `appVersion`、`buildNumber` | App | `pubspec.yaml` 的版本和构建号（`BuildInfo`），现在是 `1.0.0` / `3` |
| `platform` | App | android / ios / … |
| `schemaVersion` | App | 1 |
| `researchId` | 服务器 | 从 `research_id_map/{uid}` 抄；没登记为 null（不会发生，规则不让没登记的写） |
| `dayKey` | 服务器 | `clientAt` 的香港自然日 `YYYY-MM-DD`。T39 按它算“当天是否打开”“第一次打开时刻” |
| `studyDay` | 服务器 | `clientAt` 是研究第几天（W0 = 0，`functions/study_week.js`） |
| `uploadedLate` | 服务器 | `receivedAt − clientAt > 5 分钟` |
| `lateByMs` | 服务器 | 两者之差（毫秒），负数表示手机时钟比服务器快 |
| `clockSkew` | 服务器 | 手机时钟比服务器快 5 分钟以上（时间不可信，看板可提示） |
| `stampedAt` | 服务器 | 补字段的时间；有它就不再动 |

规则（`firestore.rules`）：本人只能**新建**，字段必须恰好是 App 的 7 个、`type` 二选一、`clientAt` 是时间戳、`receivedAt` 等于服务器时间、`schemaVersion` 是 1；`cohort` 必须是 `phase_b` / `pilot`（**登记前不记，服务器也挡**，测试账号没有 cohort 也挡）；本人不能读（研究编号不进老人能读的文档，决策 0021）、不能改、不能删；别的参与者、`unblinded`、`blinded` 都碰不到（看板走 T39 的函数）。通用的 `users/{uid}/{collection}` 规则已排除 `usage_events`。

盲法导出 `functions/blinding.js`：列入“揭盲前不导出”（`HELD_BACK`）。过程数据导出 `exports_process/`（T30）没有加它——T39 的 CSV 会按每人每日导出，比逐条事件有用；要逐条的话再加。整人删除 `tool/delete_participant.js` 走 `users/{uid}` 下全部子集合，自动覆盖。

## 3. App 端怎么判断

代码：`lib/core/usage/usage_event_recorder.dart`（纯 Dart，可注入开关、时钟、写入口）；`lib/app/app.dart` 在原有的分析会话边界（`_sessionOpen`，每段前台一次，iOS 多个生命周期状态不会重复）调用；`auth_gate.dart` 新增回调 `onProfileSeen`，每次资料流有新值（登录、登出、研究员登记后 `cohort` 到达）都告诉记录器。

1. 写一条的条件：开关开 **且** 当前账号已登记（`profile.isEnrolled`：`cohort` 是 `phase_b` / `pilot`）。
2. **冷启动**：App 一启动就算进入前台，但那时还不知道是谁登录。记录器把这段前台的开始时间记住，等资料到了、确认已登记、开关已重读，再写 `foreground`，**时间用启动那一刻**。资料到了但没登记（或登出）就丢掉。同一段前台只写一次。
3. **登记落地时 App 开着**：研究员登记后 `cohort` 经资料流到达，这段前台当时补一条 `foreground`（时间用这段前台开始的时刻），之后退后台正常写 `background`。
4. `background` 只在这段前台已经写过 `foreground` 时写，保证成对；开关中途关掉就只有 `foreground` 没有 `background`。
5. 写入是 fire-and-forget，经 SDK 离线队列；失败只记调试日志，永远不影响界面。

## 4. 测试

| 测试 | 内容 | 结果 |
|---|---|---|
| `test/usage_event_recorder_test.dart`（16 项） | 开关只认 `true`；关 = 不写；没 cohort / 测试员 / 登出 = 不写；`phase_b` × `pilot` × A × B 四种都写成对；冷启动保留原时间、不重复；登录后才读开关；登记落地时补写；无 foreground 不写 background；重复生命周期不重复；三次循环六行；换账号；行的字段集合 | 16/16 |
| `test/rules/usage_events_rules.test.js`（16 项） | 已登记本人可新建（两种 cohort）；没 cohort、测试员、`phase_a` 拒绝；本人不能读改删；7 个服务器字段都不能由客户端带；坏类型 / 字符串时间 / 客户端 receivedAt / schemaVersion 2 / 缺字段 / 多字段都拒绝；他人、`unblinded`、`blinded` 拒绝；通用规则其他子集合不受影响 | 16/16（模拟器） |
| `functions/test/usage_events_test.js`（9 项） | 在线行不算晚；离线 40 分钟算晚、`clientAt` 不改；5 分钟边界；香港日期跨午夜；时钟超前 = `clockSkew`；没 W0 / 没对照表；`receivedAt` 缺省；已盖章 / 坏类型 / 缺时间 = 不动；盖章字段集合 = 规则拒绝的集合 | 9/9 |
| `functions/test/usage_events_emulator_test.js` | 合成 PILOT-03：在线一对盖章（研究编号、香港日、研究日 5）；**三条离线行**（手机时间 10:00、10:20、10:40，12:00 一起上传）都 `uploadedLate: true`、手机时间不变；第二次运行不动；行只含 App 7 个字段 + 服务器 7 个字段 | 通过（模拟器） |
| `flutter analyze` | | 0 error、0 warning |
| `tool/ci_flutter_tests.sh`（六套） | | 六套全过（本机，Flutter 3.35.3） |
| `tool/ci_backend_tests.sh`（Functions + 规则 + 删除脚本） | | 全过（本机模拟器；规则 183 项含新 16 项） |
| ESLint（`usage_events.js`、两个测试） | ES2018，没有 `??` `?.` | 0 问题 |

对应 1014d 的四条验收：1（字段完整）= Dart 行形状测试 + 模拟器盖章；2（关网三次）= 模拟器只能模拟“晚到的行”那一半，真机见第 5 节；3（关闭时不写、其他照常）= Dart“关 = 不写”+ 规则不碰别的集合；4（登记前不写）= Dart + 规则双重。

## 5. 真机核对步骤（W0 装机或试跑第一周，5 分钟）

1. 控制台 `app_config/feature_flags.usageEventsEnabled = true`（dev 项目先试）。
2. 用一部已登记的 PILOT 手机（或 dev 项目里合成的已登记账号）打开 App，看 `users/{uid}/usage_events` 多一条 `foreground`，几秒内有 `researchId`、`dayKey`、`uploadedLate: false`。
3. 开飞行模式，切后台、切前台、切后台（三次切换）；期间集合里不会出现新行。
4. 关飞行模式，等 1 分钟：出现三条，`clientAt` 是切换当时的时间，`uploadedLate: true`。
5. 登记前的账号（没有 cohort）做同样操作：集合里没有行。

## 6. 改了哪些文件

- 新：`lib/core/usage/usage_event_recorder.dart`；`functions/usage_events.js`；`test/usage_event_recorder_test.dart`；`functions/test/usage_events_test.js`、`usage_events_emulator_test.js`；`test/rules/usage_events_rules.test.js`。
- 改：`lib/core/feature_flags/remote_feature_flags.dart`（`usageEventsEnabled`）；`lib/app/app.dart`（记录器接生命周期和 `AuthGate`，可注入）；`lib/features/auth/presentation/pages/auth_gate.dart`（`onProfileSeen` 回调，一行调用）；`firestore.rules`（`usage_events` 专用规则，通用规则排除它，头部清单一行）；`functions/index.js`（`onUsageEventCreated`）；`functions/blinding.js`（`HELD_BACK` 加 `usage_events`）；`test/rules/package.json`（mocha 清单）。
- 文档：`STUDY_CHANGELOG.md` 一行；`architecture.md` 第 8、9、12 节各一行 + 顶部核对说明；`history.md` 一段；`backlog.md` 第 110 项；本报告。
- 没改：安全检测、prompt、热线、`docs/spec/`、IAM、导出白名单（`exports_process`）。

和其他分支的交叉：T46（#79）只碰 `session_close_*` 和 `main.dart`，不重叠；`chore/t43-pilot-checklist`、#77 只有文档；四份文档顶部相邻，两边都留。T39 要读 `usage_events`，排在本 PR 之后。

合并后：部署 **规则 + Functions**（`onUsageEventCreated` 是新函数）；App 重新打包。开关什么时候开由 Junyu 定（建议和打包同一天，先在 dev 项目按第 5 节试一次）。

## 7. 决策记录草稿（编号待开发窗口分配）

**NNNN：使用事件单独一个集合，由服务器补研究编号和补传标记**

- 日期：2026-10-14；状态：提议中；影响范围：phase_b、pilot × 两组；相关代码：PR `feat/usage-events`。
- 背景：PI 要按人按日看“有没有打开、几点第一次打开、连续几天没开”（10/14 第 10 条）。App 已有 `events` 里的前台 / 后台行，但手机时间被服务器时间覆盖，也没有版本号和补传标记。
- 决定：新子集合 `users/{uid}/usage_events`，App 只写它知道的（类型、手机时间、版本、平台）+ 一个服务器时间戳；触发器补研究编号、香港日期、研究日、`uploadedLate`（晚 5 分钟以上）。本人只能新建不能读。开关 `usageEventsEnabled` 默认关。旧 `events` 行不动。
- 考虑过的其他方案：① 在 `events` 行上补字段——旧行仍没有手机时间，看板要扫全部分析事件，规则无法单独收紧；② 客户端自己判断离线并标记——App 离线时被杀掉标记就丢，且没有可靠的连网判断；③ 看板读时再算补传——登记表 C23 要求事件本身带标记。
- 后果：对研究，C23 的“研究编号、事件类型、客户端时间、服务器接收时间、构建版本号、补传标记、登记前不记”都有对应字段，DMP 的过程数据清单加一个集合；对开发，T39 按 `dayKey` 聚合；对论文，使用量（打开天数）的口径注明“前台事件，离线补传按手机时间归日”。

## 要 Junyu 定的事

1. 开关 `usageEventsEnabled` 哪天开（建议：10/19 包装机当天，先 dev 项目试）。
2. 补传阈值 5 分钟是否可接受（常量；要改成配置再说）。
3. 决策草稿的编号。

## 要带回研究侧的发现

1. **旧构建没有手机时间**：10/15 装的包（不含 T40）这几天的“是否打开”只能按会话记录算，`events` 里的 `app_foreground` 的时间是服务器收到的时间，离线时会偏后。T39 按 1014d 的后备口径处理并标“旧构建口径”。
2. **`receivedAt` 的含义**：它是服务器提交这条写入的时间；手机一直在线时和手机时间只差几秒。看板的“当天”一律按手机时间（`dayKey`），不按 `receivedAt`。
3. **时钟不对的手机**：`clockSkew` 标出手机比服务器快 5 分钟以上的情况；装机时顺手核对手机时间自动同步已开。
4. **前台时长**：1014d 第 2 页第 3 项“当天前台总时长（单段封顶 60 分钟）”可以由成对的 `foreground` / `background` 算出；App 被直接杀掉时没有 `background`，那一段按下一条 `foreground` 或封顶算，T39 报告会写明口径。
5. C23 写“研究编号”是事件字段：实现上由服务器补、老人读不到，和 C19/C20“研究编号不进参与者可读文档”一致，不用改登记表。
