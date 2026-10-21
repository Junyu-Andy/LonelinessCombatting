# 电脑上看的运营看板（本机，只读）

> 2026-10-20 第一版（1020i 第二版第二节；决策记录 0061）。
> 2026-10-21 按决策 0072 改（decisions-log 10/20 第 66 条）：总览在组别旁边显示整份每周问卷做完没有；每人页显示每日心情数值。演示数据的截图在 `docs/dev-reports/1021-dashboard-shots/`。

## 结论

- 在 Mac 上跑一行，浏览器里打开看板：

  ```bash
  cd ~/dev/LonelinessCombatting
  bash tool/dashboard/start.sh
  ```

- 五页：
  - 总览；
  - 今天要做；
  - 每人页；
  - 结局完成率；
  - 导出 CSV。
- **只读。** 看板程序不往 Firestore 写任何东西。它读不到这些：
  - 问卷答案和分数；
  - 对话原文；
  - 分配序列、分配日志和改组记录。
- **10/21 起（决策 0072）**：
  - 总览每人一行，组别旁边是每一周的**整份**每周问卷做完没有（只看做没做完）；
  - 每人页显示每天的心情数值（1 至 5）。心情数值只在每人页，别的页和 CSV 都没有。
- 「確認處理」和「標記誤觸」可以在看板上按：
  - 用你自己的 App 账号登录，走和 App 研究员后台同一个服务器入口；
  - 服务器照旧记下谁、何时按的。
- 看板只在你这台电脑上打开（`127.0.0.1`），别人连不上。
- 第一次要先做第一节的三件事（建只读账号、下载钥匙、开一个 API），大约 15 分钟。

## 一、第一次准备（只做一次）

### 1. 建一个只给看板用的只读服务账号

不要用你现在 `~/dev/keys` 里的那把钥匙。那把能写数据，看板会拒绝启动。

1. 打开 Google Cloud 控制台的服务账号页：
   <https://console.cloud.google.com/iam-admin/serviceaccounts?project=loneliness-pilot-dev>
2. 点「创建服务账号」：
   - 名称写 `dashboard-viewer`，点「创建并继续」；
   - 「角色」只选一个：**Cloud Datastore 查看者**（英文 Cloud Datastore Viewer，代码 `roles/datastore.viewer`）；
   - 点「完成」。
3. 在列表里点 `dashboard-viewer`，进「密钥」标签：「添加密钥」→「创建新密钥」→ 选 JSON →「创建」。浏览器会下载一个 `.json` 文件。
4. 把它移到固定位置，并且只让你自己能读（在终端里运行，把下载的文件名换成你的）：

   ```bash
   mv ~/Downloads/loneliness-pilot-dev-xxxxxxxx.json ~/dev/keys/dashboard-viewer.json
   chmod 600 ~/dev/keys/dashboard-viewer.json
   ```

钥匙不要放进仓库文件夹，看板发现钥匙在仓库里会拒绝启动。控制台如果提示「组织政策不允许创建密钥」，把截图发给开发窗口。

### 2. 打开 Cloud Resource Manager API

看板启动时，会用这个 API 问 Google「这把钥匙能做什么」。这一步不读也不写数据。

打开 <https://console.cloud.google.com/apis/library/cloudresourcemanager.googleapis.com?project=loneliness-pilot-dev>，点「启用」。已经启用就不用管。

### 3. 网页 API 钥匙（可能不用做）

只有按「確認處理」「標記誤觸」时才用到。

1. 打开 <https://console.cloud.google.com/apis/credentials?project=loneliness-pilot-dev>，找 「Browser key (auto created by Firebase)」。
2. 看它的「应用限制」：
   - 写着「无」：什么都不用做；
   - 写着「网站」：把下面两行加进去，保存。

   ```
   http://127.0.0.1:8787/*
   http://localhost:8787/*
   ```

另外，你的 App 账号要有 `unblinded` 角色。在 App 研究员后台能按「確認處理」，就说明有。

## 二、每次打开

**先试演示（推荐第一次做）。** 用模拟器和合成数据，不用钥匙，不连正式项目：

```bash
cd ~/dev/LonelinessCombatting
bash tool/dashboard/start.sh --demo
```

**看真实数据：**

```bash
cd ~/dev/LonelinessCombatting
git pull
bash tool/dashboard/start.sh
```

- 终端里出现「✓ 钥匙检查：只读钥匙」和「看板已打开」，浏览器会自己打开 <http://127.0.0.1:8787/>。没自动打开，就自己把地址粘贴进浏览器。
- 关掉看板：回到终端按 `Ctrl+C`。
- 钥匙不在 `~/dev/keys/dashboard-viewer.json` 的话，这样跑：`DASHBOARD_KEY=<钥匙路径> bash tool/dashboard/start.sh`。

## 三、各页看什么

**数据刷新**：读到的数据在内存里留 5 分钟，所以翻页快。要马上看最新的，按右上角「刷新」。页面顶部写着数据是几点读的。

### 总览

每人一行。只有登记过的 RCT-、PB-、PILOT-；勾「显示测试账号」才显示测试账号。

| 列 | 说明 |
|---|---|
| 组别 | 从登记记录读 |
| 研究日 | W0 是第 0 天，香港日期 |
| 最后打开 | 最近一次把 App 打开到前台；旧构建没有这项记录，就用最近一次会话（标「旧构建口径」） |
| 跟进 | 第 1 至 28 天，连续 3 至 5 天没打开是「发 WhatsApp」，6 天及以上是「打电话」；第 29 天起是「随访期」。和 App 运营看板相同 |
| 有效会话 | 本周（研究周）和累计，从研究第 1 天算；括号里是小欣 / 阿珍阿伯 / 通通 |
| Brief PR | 邀请数 / 完成数 |
| 本周 check-in | 本周到今天，有几天做完 check-in |
| 每周问卷（整份） | 每一周一个小格，W1 至 W4 一行、W5 至 W8 一行。看那一周问卷的**每一部分**，都做完才算「完成」。状态：未开始、未做完、过时、完成；「3/4」是 4 部分做完了 3 部分。W8 App 里还没做，写「未做」 |
| 未确认告警 | 没按「確認處理」的告警数 |

**每周问卷有哪几部分**（和 App 同一份排期）：

- 第 1 至 3 周：DJG-ES、Weekly PR、PGIC；
- 第 4 周：Weekly PR、PGIC；
- S12（社交接触）开着时，第 1 至 4 周也算它；
- 第 5 至 7 周：只有 PGIC，第 35、42、49 天 00:00 开，开 3 个整天（决策 0067）。

**怎样算做完**：和服务器同一个规则。DJG-ES、S12 是提交了；Weekly PR 是做完或跳过；PGIC 是有作答时间。几号开、几号截止也用服务器的同一份代码；第 4 周到评估员记下 W4 那天截止，没记的话最晚第 42 天。

**为什么组别旁边放整份问卷（决策 0072）**：Junyu 10/20 第 66 条定的，要照着看板提醒和跟进。这样能按组看出谁没做完结局问卷（DJG-ES、PGIC、S12），是有意的取舍。催的时候两组同样对待：照「今天要做」名单和每天 10:00 的邮件催。看板只看做没做完，答案和分数照旧读不到。

W4 排期看板不管，用你自己的排期表。

### 今天要做

- (a) 发 WhatsApp、(b) 打电话：规则同上。
- (c) 每周问卷今天是最后一天、还没做完的人。规则和每天 10:00 的提醒邮件相同：W1 至 W3 是第 9、16、23 天，W4 是第 28 天。第 5 至 7 周不进邮件，这里也不列。
- (d) 未确认的安全告警，每条有「確認處理」和「標記誤觸」两个按钮（见第四节）。
- 这一页不显示组别。

### 每人页

在总览或名单里点研究编号进入。顶上写着组别。内容：

- 安全事件：级别、类别、来源、时间、是否标了误触、告警是否已确认。没确认的有两个按钮。
- 每周问卷：W1 至 W8 每周一行。几号开、几号截止（含这天）、状态，和每一部分做没做（✓ 做了，— 没做）。只看做没做完，没有答案。
- 每日：打开、第一次打开时间、前台分钟、各陪伴者的有效会话、Brief PR、check-in，和**心情数值**：
  - 1 好唔開心、2 唔係幾好、3 一般般、4 幾好、5 好開心（和 App 首页的五个脸一样）；
  - 一天记了几次，第一次的放前面（分析用的是第一次），后面写「再记 …」；
  - 没记写「—」。
- 会话：每次会话的开始时间、陪伴者、类型、分钟、老人发言条数、是否有效。没有对话内容。
- Brief PR：每次的四项分数。

要看对话：App 现在也没有「查看对话」，要做的话另外决定。

### 结局完成率

- 全体合并，不分组，只算 Phase B（RCT- 和 PB-，不含 PILOT）；少于 5 人不显示。
- App 内问卷（DJG-ES、PGIC、S12 的 W1 至 W3）：只算窗口已经结束的人。
- W4 纸本（DJG-ES、PHQ-9）：算研究第 32 天及以后的人（W4 窗口第 25 至 31 天之后）。
- 只数完成与否，看板读不到答案。

### 导出

按「导出 CSV」，两份文件存到 `~/dev/dashboard-exports/`：

- `process_weekly_…csv`：每人每个研究周一行（打开天数、前台分钟、有效会话、Brief PR、check-in 天数、记了心情的天数）；
- `process_daily_…csv`：每人每天一行，和 App 运营看板导出的列相同。

只有过程数据和组别。没有心情数值（只有「记了心情的天数」），也没有问卷答案。文件只有你能读。想换文件夹：`DASHBOARD_EXPORT_DIR=<文件夹> bash tool/dashboard/start.sh`，不能放在仓库里。

## 四、在看板上「確認處理」「標記誤觸」

1. 在「今天要做」(d) 或每人页的安全事件里，点按钮。
2. 弹出确认框，核对研究编号和时间后点「确定」。
3. 第一次按要登录：用 App 里同一个电邮和密码。
4. 完成后，页面重新读取，这条告警的状态会变。

**标误触不等于确认。** 标了误触，告警还算「未确认」，12 小时后照样发升级邮件。两个按钮要分开按。

- 登录只在这个网页里有效：密码直接发给 Google，不经过看板程序，也不存盘；关掉网页就登出。
- 服务器照旧检查角色（要 `unblinded`），照旧写 `alert_audit_log`（你的账号、时间）。App 后台的按钮也照常能用。
- 演示模式下这两个按钮不能按。

## 五、费用

估算按 60 人、跑到第 8 周：

- 每次「刷新」读一遍总览和「今天要做」，大约 1 万多次读取（总览要读每人四种问卷的完成记录）。
- 平常看页面 5 分钟内不重读。
- 一天刷新 30 次约 30 万次读取，大约 0.2 美元。

## 六、常见问题

| 看到 | 怎么办 |
|---|---|
| 「这把钥匙能写 Firestore」 | 用错钥匙了。按第一节建 `dashboard-viewer`，用它的钥匙 |
| 「这把钥匙不能读 Firestore」 | 服务账号没加「Cloud Datastore 查看者」角色，回第一节第 1 步第 2 点加上 |
| 「检查钥匙权限失败：…Cloud Resource Manager API…」 | 第一节第 2 步，启用这个 API，等一两分钟再试 |
| 「找不到看板的只读钥匙」 | 钥匙不在 `~/dev/keys/dashboard-viewer.json`，见第二节最后一点 |
| 「钥匙放在仓库里面了」 | 把钥匙移到 `~/dev/keys/` |
| 「钥匙文件别人也能读」 | 运行它提示的 `chmod 600 …` |
| 端口 8787 被占用 | `DASHBOARD_PORT=8788 bash tool/dashboard/start.sh`；第一节第 3 步的两行也要改成 8788 |
| 按钮提示「这个账号没有权限」 | 登录的账号没有 `unblinded` 角色，换你自己的 App 账号 |
| 按钮提示「服务器开关没开」 | 标记误触要 `safetyFalseAlarmMarkEnabled` 开着 |
| 登录时提示 API 钥匙被拒绝 | 第一节第 3 步 |
| 页面写「读取出错」 | 按「刷新」再试；还不行，把终端里的错误发给开发窗口 |

## 七、给开发看的

- 代码在 `tool/dashboard/`：
  - `server.js`：本机网页服务；
  - `lib/guarded_db.js`：唯一读 Firestore 的地方，有白名单和字段投影，没有写；
  - `lib/fields.js`：白名单。心情数值是唯一的例外：`READ_EXCEPTIONS` 允许读 `daily_mood.mood`，`OUTPUT_ALLOW` 只许它出现在每人页的 `days[].moods[].mood`，而且只能是数字；
  - `lib/pages.js`、`lib/load.js`：五页，规则调用 `functions/`；
  - `lib/key_check.js`：启动时检查钥匙；
  - `public/`：网页，`auth.js` 负责登录和两个服务器入口。
- 测试：
  - `tool/dashboard/test/dashboard_unit_test.js`；
  - `tool/dashboard/test/dashboard_emulator_test.js`：合成数据里所有答案、对话、分配字段都带记号，测试检查记号既没从 Firestore 读回来，也没出现在任何页面或 CSV 里。心情数值带另一种记号：测试检查它只从 `daily_mood` 读、出现在每人页，不出现在总览、今天要做、结局完成率和 CSV 里。总览每一周的状态也逐人核对。
- 两份测试已加进 `tool/ci_backend_tests.sh` 和 `tool/run_local_tests_mac.sh`。
