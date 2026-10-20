# 0064：首页「今日要做嘅事」加小行动一行，「改日」= 今天没做、计划挪到明天（最多挪一次），不加开关、直接替换旧的计划跟进一行

- 日期：2026-10-20
- 状态：提议中（等 Junyu 看截图、确认「改日」的读法）；1020n（decisions-log 10/20 第 86–88 条）加了「订计划那天」和「同一天几个计划」，见文末「1020n 更新」
- 影响范围：phase_b、rct、pilot × 两组（两组完全相同，不调用模型）
- 相关代码：分支 `claude/zealous-fermat-8rgqtg-smallaction-1020m`（PR 草稿，由协调窗口开）

## 结论

1. 第一页「今日要做嘅事」在 check-in 一行和问卷一行之后加一行小行动。**不加开关，直接替换旧的一行**（Junyu 10/20 晚定）：旧的「行动计划跟进」那一行（`ActivePlanBanner`）从第一页拿走；它只在旧的一页版面（`homeLayoutV2Enabled` 关）里还在，生产上那个开关已经开着。
2. 当天没有计划：「今日想做啲咩小行動？」，右边小字「遲啲先」。撳这一行进「今日小行動」（和「做啲嘢」第一张卡片同一页）。撳「遲啲先」这一行收起，当天和之后两天不出现，第 4 天起再出现（手机本地记一个日子，不进数据库）。
3. 当天有计划：「今日計劃：{做咩}」，下面「做咗」「改日」。（1020n：每个计划一行，文字最多两行再加「…」，见文末。）
4. **「做咗」在数据里 = 现有跟进结果「做咗」**：写进计划本身的 `outcome: happened`，和「件事點呀？」页写的一样，另加 `followUpSource: home_row` 说明是首页答的。这一行打勾，当天不再问。
5. **「改日」在数据里 = 今天没做，计划保留，挪到明天**：不写 `outcome`（计划仍在「我嘅計劃」等跟进），只写状态 `later`、日子和次数。第一次「改日」把计划和它的提醒挪到明天、同一个钟点；同一个计划第二次「改日」（第二天）不再挪，提醒取消，第三天首页改回「今日想做啲咩小行動？」。计划从不删除，一直留在「我嘅計劃」。撳了「改日」这一行当天收起。
6. 当天这个计划的跟进推送：首页答了「做咗」或「改日」就不再推（App 删掉或挪走提醒；服务器也查一次，见下）。

## 背景

1020m 第二节要首页有一行直接问今天的小行动。原交接 (2)(b) 写「改日」不改计划日期；Junyu 10/20 晚改为「挪到明天、同一时间，提醒和跟进一起挪；同一个计划连续两次『改日』以后不再挪，第三天首页改回『今日想做啲咩小行動？』」。开发窗口把这句读成上面第 5 条（第一次挪、第二次不挪），**请 Junyu 确认**；如果意思是「可以挪两次、第三次才不挪」，只要把 `HomeSmallAction.maxMoves` 从 1 改成 2。

**计划本来没有日期。**「幾時」是自由文字（「聽朝」）或「上晝／下晝／晚上」，`scheduledFor` 从来没写过。App 唯一确定的日子是跟进提醒：存计划后 24 小时，推送写「你今日有個小計劃，得閒打開睇下。」。所以这里规定：**计划的日子 = 它的跟进提醒那天（香港日历，存好后 24 小时那天）**；撳过「改日」的，就是挪到的那天（`homeRowDueDate`）。结果是：今天订的计划，明天首页才显示「今日計劃」，和推送同一天。

## 决定

### 写在哪里（两组相同，不写任何新的文字）

**`users/{uid}/action_plans/{id}`（优先用现有跟进结构，3(a)）**

| 字段 | 「做咗」 | 「改日」 | 说明 |
|---|---|---|---|
| `outcome` | `happened` | 不写 | 现有字段，和「件事點呀？」页同一个值 |
| `followedUpAt` | 服务器时间 | 不写 | 现有字段 |
| `followUpSource` | `home_row` | 不写 | 新。交接写的是 `source: "home_row"`，但计划已经有 `source`（订计划时从哪里打开：建议页／小行動页／小欣 Q5，1020e），覆盖会丢掉它，所以改用这个名字 |
| `homeRowStatus` | `done` | `later` | 新，首页最后一次的答案 |
| `homeRowAnsweredDate` | 当天（香港） | 当天（香港） | 新，`YYYY-MM-DD` |
| `homeRowAnsweredAt` | 服务器时间 | 服务器时间 | 新 |
| `homeRowLaterCount` | — | 1 或 2 | 新，撳「改日」的次数 |
| `homeRowDueDate` | — | 第一次：明天 | 新，挪到的日子；第二次不变 |
| `homeRowLog` | 追加一条 | 追加一条 | 新，`{status, atLocal, forDate, movedTo}`：答案、手机时间、那天、挪到哪天（没挪是 null） |

计划 id 就是文档 id。现有结构没有「改日」这种状态（`didNotHappen` 会让计划离开「我嘅計劃」、推送也停），所以「改日」用 3(b) 的新状态字段。

**`users/{uid}/reminders/{id}`（跟进提醒，服务器推送用）**

- 「做咗」、第二次「改日」：删掉这个计划未发的提醒（和「件事點呀？」页、删除计划时一样）。
- 第一次「改日」：未发的提醒 `fireAt` 挪到明天同一钟点，加 `movedFromFireAt`、`movedBy: home_row`；如果当天的已经推过了，就给明天同一钟点（存计划的钟点）新排一条，带 `movedBy: home_row`。

**`users/{uid}/usage_events`（使用事件，3(c)，两组相同，跟 `usageEventsEnabled` 开关和已登记规则）**

| `type` | 额外字段 |
|---|---|
| `home_small_action_shown` | `rowState`：`ask`／`plan`／`done`；不是 `ask` 时加 `planId` |
| `home_small_action_open` | 无（撳「今日想做啲咩小行動？」） |
| `home_small_action_later` | 无（撳「遲啲先」） |
| `home_small_action_done` | `planId` |
| `home_small_action_postpone` | `planId`、`moved`（第二次是 `false`） |

「出现」每个帐号每天每种状态记一次（App 开着期间；重开 App 可能再记一次）。服务器照旧盖研究编号、研究日。

**手机本地（`shared_preferences`）**：`home.smallAction.laterDate`（撳「遲啲先」那天）。

### 服务器那边（`functions/reminders.js`）

App 自己会挪或删提醒；服务器推送前再查一次计划，防 App 写失败或离线：计划的 `homeRowDueDate` 比提醒那天晚 → 把提醒挪到那天同一钟点（`moved_home_later`，之后照常推）；`homeRowAnsweredDate` 不早于提醒那天 → 不推（`skipped_home_answered`）。「做咗」有 `outcome`，照旧 `skipped_followed_up`。

### 规则（`firestore.rules`）

计划和提醒仍走老人自己子集合的通用规则（不用改）。使用事件加五种 `type`，每种只能带自己的字段，`planId` 只能是字母数字（文档 id），塞不进文字。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 加开关 `homeSmallActionRowEnabled`，关时旧行为 | Junyu 10/20 晚定：不加开关，直接替换旧的一行 |
| 「改日」写 `outcome: didNotHappen` | 计划会离开「我嘅計劃」，推送也停，和「计划保留、明天再问」相反 |
| 用「幾時」文字猜日子（「今晚」= 今天） | 自由文字猜不准；规则组只有上晝／下晝／晚上，没有日子 |
| 写 `scheduledFor` 当计划日期 | 旧的一页版面横幅和个人化页「即將到嘅提醒」会因此出现，影响范围更大 |
| 字段名照交接用 `source` | 会覆盖计划原来的 `source`（订计划的入口，1020e 数据） |

## 后果

- 对研究：首页多一个回答「做咗」的地方，`outcome` 的来源要分开看（`followUpSource: home_row` 或空 = 「件事點呀？」页）。「改日」不是结果，是过程数据。旧的一行（`ActivePlanBanner`）在第一页本来就不会出现（没有计划有 `scheduledFor`），所以拿走它不改变以前收到的数据。两组相同，不影响组间对等。
- 对开发：`lib/features/action_loop/data/home_small_action.dart`（日子、状态、提醒怎样挪）、`ActionPlanRepository.markDoneFromHome／postponeFromHome`、`lib/features/today/presentation/widgets/home_small_action_row.dart`、`firestore.rules`、`functions/reminders.js`、`functions/usage_events.js`。要部署 rules 和 Functions，App 要重新打包。
- 对论文：过程数据一节（首页小行动一行的使用率、「做咗」来源）；局限：计划的日子按提醒日算，不是老人自己定的日子。
- 待 Junyu 定：①「改日」挪一次还是两次；② ~~计划的日子按提醒日（存好后第二天）算是否可以~~（1020n 按这个读法加了「订计划那天」的显示，视为确认）；③ 截图里的样式和文字（`docs/spec/copy/home-v2.md` SA1–SA8）。

## 1020n 更新（2026-10-20 晚，decisions-log 第 86–88 条，交接 1020n 第三节、第五节）

结论：**每个计划一行，各自「做咗」「改日」；最多显示两个计划，多的写「仲有 N 個計劃」；订计划那天显示「聽日計劃」和「仲有冇其他計劃？」；计划文字最多两行。** 两组相同，不调用模型，不加开关（直接改）。

- **同一天几个计划（先查后改）**：数据结构本来就允许。每次存计划都是 `action_plans` 里一个新文档，各有自己的跟进提醒（`reminders.linkedDocId`）；App、规则、服务器都没有「一天一个」的限制，`homeRow*` 字段也本来就在每个计划自己身上。不允许的只是首页这一行的显示逻辑（以前只显示最早的一个，而且当天答过一个就整行不再问）。所以**数据结构没改**，只改了 `HomeSmallAction.resolve`：
  1. 今天的计划（计划日子是今天，或今天在首页答过）每个一行，按订的先后：没答 →「今日計劃：{…}」+「做咗」「改日」；做咗 → 打勾；改日 → 这一行当天收起（别的计划照旧问）。
  2. 没有今天的行、但今天订了计划（日子是明天或以后）→ 每个一行「聽日計劃：{…}」（没有按钮），下面「仲有冇其他計劃？」（进「今日小行動」再订一个）。这时**没有「遲啲先」**。今天「改日」挪到明天的计划不算在内（它当天收起）。
  3. 今天的计划都答完或收起 → 这一行不显示。
  4. 都没有 →「今日想做啲咩小行動？」+「遲啲先」（照旧）。
  - 第 1、2 种最多两行计划；多过两个，头两行下面一行「仲有 N 個計劃」（N = 没显示的个数），撳了进「我嘅計劃」。
- **计划文字最多两行**，再长截断加「…」（取代以前的一行）。
- **研究数据**：`action_plans` 的字段不变（每个计划各自的 `outcome`、`followUpSource`、`homeRow*`）。使用事件：`home_small_action_shown` 多一个 `rowState: next_day_plan`（带 `planId`），每个计划行各记一次；新事件 `home_small_action_more`（撳「仲有冇其他計劃？」）、`home_small_action_list`（撳「仲有 N 個計劃」），都不带别的字段。`firestore.rules`、服务器盖章（`functions/usage_events.js`）和测试一起改。
- **推送**：几个计划就有几条跟进提醒，各自按自己的时间推（和以前一样）；每个计划的「做咗」「改日」只动它自己的提醒。
