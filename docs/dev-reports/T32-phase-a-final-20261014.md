# T32 第 6 条：旧测试员数据批量清理脚本（2026-10-14）

分支 `feat/phase-a-final`，SPEC:C22、C20。任务单：`docs/dev-tasks/dev-tasks-1010.md` 第四节 T32 第 6 条；`docs/dev-tasks/dev-tasks-1010b.md` 第二节 T32（Phase A 暂停，只剩第 6 条）。

## 1. 结论

- 新脚本 `tool/purge_tester_data.js`：把 Firebase 项目里的账号分成四类，列出要删的两类（测试账号、没登记的账号）和每人的数据量；**默认只列不删**；加 `--confirm --production` 和项目确认参数才删，删法是逐人调用现有的 `tool/delete_participant.js`。
- **永远不碰**：已登记的 `phase_b` / `pilot` 账号、研究员和评估员账号（Auth 角色 `unblinded` / `blinded`）。它们在输出里单列“保留”和原因。
- 删完写一条服务器专用的运行记录 `admin_runs`（只有数量、uid 和类别，没有原话、没有电邮）和本地 JSON。
- 模拟器上 4 组测试全过（`test/delete_participant/purge_tester_data_test.js`，已接进 `tool/ci_backend_tests.sh`）。没有连过生产项目。
- 由 Junyu 在 **10/19 登记第一位参与者之前**自己跑，步骤写进 `docs/release/prelaunch-checklist.md` 新的 I 节。
- 没有开关：这是一个手动运行的脚本，不改 App、不改 Functions 的行为，不部署任何东西。
- 本任务只动了 `tool/`、`test/`、文档；没有 Flutter 代码。

## 2. 脚本列谁、删谁、留谁

依据：`tool/purge_tester_data.js` 顶部注释和 `classify()`。

账号来源：Auth 用户列表和 Firestore `users/*` 文档**合在一起看**，所以只有 Auth 账号没有 `users/{uid}` 的，和只有 `users/{uid}` 没有 Auth 的，都会出现。

| 类别 | 条件 | 处理 |
|---|---|---|
| `tester` | `users/{uid}.isTester == true` | 列出；`--confirm` 时删 |
| `unenrolled` | 没有研究期：`cohort` 不是 `phase_b` / `pilot`（判断用 `functions/study_period.js` 的 `isEnrolled`）。包括没有 `cohort` 字段、旧的 `phase_a`、没有 `users/{uid}` 文档的 Auth 账号 | 列出；`--confirm` 时删 |
| `enrolled` | `cohort` 是 `phase_b` / `pilot`，或有 `enrollments/{uid}` 记录。**即使也标了 `isTester`，登记优先** | 保留，输出里写原因 |
| `staff` | Auth 自定义声明 `role` 是 `unblinded` / `blinded`（也认旧名 `pi` / `researcher`，`tool/provision_researcher.js`） | 保留，输出里写原因 |
| `keep` | 命令行 `--keep=<uid>,<uid>` 列出的 | 保留 |

每人的数据量来自 `tool/delete_participant.js` 的试运行（`run({confirm:false})`）：`users/{uid}` 每个子集合的文档数、顶层集合里按 uid 找到的行数（`llm_calls`、`safety_events`、`research_id_map`……，清单在 `delete_participant.js` 的 `TOP_LEVEL`）、Auth 账号、Storage `users/{uid}/` 的文件数、周度导出里的行数。

**删除时不删的东西**（和 `delete_participant.js` 一样，见它的 `NOT_COVERED`）：`arm_assignment_log`、`pilot_assignment_log`、已用的分配序列位置、Cloud Logging、DeepSeek / Brave 那边的副本、`tool/admin_dump.js` 的本地文件、手机缓存；周度导出 `exports/` 里的行只数不改（加 `--rewrite-exports` 才重写）。

**运行记录**：`--confirm` 跑完写 `admin_runs/{自动 id}`：工具名、模式、目标（emulator / production）、时间、`--operator`、过滤参数、看到的账号数、每类人数、每个被删账号的 uid / 类别 / 原因 / 数据量 / 复查是否通过、每个保留账号的 uid / 类别 / 原因、`allVerified`。`firestore.rules` 没有 `admin_runs` 的规则，所以客户端读不到也写不了，只有服务器能写（`docs/dev/architecture.md` 第 8 节）。本地 JSON（`--receipt=<路径>`，默认 `./purge-tester-receipt-<时间>.json`）多带每人一份 `delete_participant.js` 的存证。测试检查过：两处都不含原话、电邮、命中词。

## 3. Junyu 要跑的命令

在仓库根目录，带服务账号凭据（`GOOGLE_APPLICATION_CREDENTIALS`）。完整步骤见 `docs/release/prelaunch-checklist.md` I 节。

1. 先列不删（读取也要项目确认参数，和 `tool/prelaunch_config.js` 一样，见 `tool/firestore_target.js`）：

   ```
   NODE_PATH=functions/node_modules node tool/purge_tester_data.js \
     --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev
   ```

   看两段输出：要删的名单（每行 uid、类别、原因、数据量，下面列每个子集合的数量），和 `Kept (never touched)`。核对 Keran、Junyu、两位评估员都在 Kept 里。

2. 名单里有不该删的：加 `--keep=<uid>,<uid>`，或只删测试账号 `--only=testers`，或只删某天之前建的账号 `--created-before=2026-10-15T00:00:00+08:00`。再跑一次第 1 步。

3. 删除：

   ```
   NODE_PATH=functions/node_modules node tool/purge_tester_data.js \
     --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev \
     --confirm --production --operator=<自己的电邮>
   ```

   每行开头 `OK` = 这个人删完复查通过；任何 `FAIL` 脚本以退出码 1 结束，看 JSON 里该人的 `remaining`。

4. 再跑第 1 步，应显示 `Would delete 0 account(s)`。

安全阀（都在 `main()`）：没有 `FIRESTORE_EMULATOR_HOST` 又没给 `--project` → 拒绝；给了 `--project` 没给 `--production-confirm=<同一个 id>` → 拒绝；`--confirm` 没给 `--production` → 拒绝；在模拟器里却给了生产参数 → 拒绝；`--only` 不是 `testers` / `unenrolled` → 拒绝。这五种在本机都试过，退出码都是 2。

## 4. 开关

无。脚本手动运行，不改任何运行时行为；没有新的 Firestore 配置文档。

## 5. 字段

- 新集合 `admin_runs`（服务器专用，内容见第 2 节）。不是研究数据，不进导出。
- `tool/delete_participant.js` 多导出一个常量 `NOT_COVERED`（给清理脚本写进日志用），行为不变。

## 6. 测试

| 任务单的测试项 | 测试 | 结果 |
|---|---|---|
| 合成的测试员 + 没登记 + 一个 `PB-` + 一个 `PILOT-` + 一个 `unblinded` 员工 → 列表正确 | `test/delete_participant/purge_tester_data_test.js`「list-only shows the right set…」：11 个合成账号（2 测试员、没 `cohort` 的 B 组老人、只有 Auth 的、只有文档的、旧 `phase_a`、`PB-001`、`PILOT-01`、`unblinded`、`blinded` 且标 `isTester`、`PB-002` 且标 `isTester`）；要删 6 个、保留 5 个，类别逐个核对；数据量和 `delete_participant.js` 直接试运行的结果一致 | 通过 |
| 试运行不删任何东西 | 同一测试：跑完每个账号的数据量不变、`admin_runs` 为空、日志里没有原话和电邮 | 通过 |
| 确认后只删正确的那组 | 「--confirm deletes exactly the listed set…」：6 个账号在 `delete_participant.js` 看得到的所有地方都为 0；5 个保留账号数据量不变、`enrollments` 还在、Auth 账号还在、`arm_assignment_log` 条数不变；`admin_runs` 正好 1 条且内容正确；再跑一次没有可删的 | 通过 |
| （补）`--only`、`--keep`、`--created-before` | 「--only, --keep and --created-before narrow the set」 | 通过 |
| （补）分类规则：登记和角色优先于 `isTester` | 「classify: each kind…」 | 通过 |

跑法和结果：

| 命令 | 结果 |
|---|---|
| `flock /tmp/firebase-emulator.lock tool/ci_backend_tests.sh` | 见下文（Functions 单元测试 + 规则 + 模拟器测试 + 删除 / 共享同意 / 清理脚本三个测试文件） |
| `flutter analyze`、`tool/ci_flutter_tests.sh` | **没跑**：本任务不改任何 Flutter 代码（只有 `tool/`、`test/delete_participant/`、文档）。GitHub CI 推送后仍会跑全部 |

## 7. 改了哪些文件

- `tool/purge_tester_data.js`（新）
- `tool/delete_participant.js`（只加导出 `NOT_COVERED`）
- `test/delete_participant/purge_tester_data_test.js`（新）
- `tool/ci_backend_tests.sh`（第三组多跑一个测试文件）
- `docs/release/prelaunch-checklist.md`（新 I 节 I1–I4）
- `docs/dev/architecture.md`（头部日期；第 8 节 `admin_runs` 一行和“批量清理旧测试员”一段；第 12 节脚本说明）
- `docs/dev/backlog.md`（101 上线前必做；102 待决定）
- `docs/history.md`（顶部一段）
- `docs/STUDY_CHANGELOG.md` **没加行**：参与者感受不到、不影响测量（清理的是登记前的测试数据）。
- 本报告

## 8. 和其他 PR 的交叉

- T25 `feat/session-briefpr`（#67，已合并）：动 `functions/index.js` 和文档，不碰 `tool/`；本分支已合并 `origin/main`。
- T30 `fix/roles-exports`：可能也改 `tool/delete_participant.js`（新顶层集合要加进 `TOP_LEVEL`）和 `docs/release/prelaunch-checklist.md`。清理脚本只调用 `delete_participant.js`，`TOP_LEVEL` 加了什么它自动跟着删；冲突只会在 `module.exports` 一行和文档。
- T24 `feat/weekly-schedule`、T27 `feat/stt-server`：不碰这些文件；若它们新加带 uid 的顶层集合，应同时加进 `delete_participant.js` 的 `TOP_LEVEL`，否则清理也删不到。
- 所有同天的 PR 都会改 `docs/history.md`、`docs/dev/backlog.md`（101、102 是本分支编号，若冲突按合并顺序重编）、`docs/dev/architecture.md` 头部一行。

## 9. 要 Junyu 定的事

1. **没登记的账号要不要一并删**（backlog 102）。脚本按任务单把“没有研究期字段的账号”和测试账号一起列为可删。10/19 前若有真实老人已装 App、注册了、还没登记，会出现在名单里。选项：(a) 删除前逐个核对名单（I1，现做法）；(b) 第一次只跑 `--only=testers`，没登记的留到登记门打开后处理；(c) `--created-before=<日期>` 只删某天之前建的账号。**建议 (a)+(c)**：看一遍名单，并以“开始发包给老人的日期”作 `--created-before`。
2. **什么时候跑**：建议在 10/19 登记前一天，且在 T30（评估员账号角色）发放完角色之后——角色没发的员工账号会被当作 `unenrolled` 列出（会在名单里看到，不会悄悄删）。
3. **`arm_assignment_log` 里测试员的旧条目**：按 `delete_participant.js` 的既定做法保留（试验完整性）。如果试用期曾用登记页给测试账号分过组，这些日志会留着；要不要清，由研究侧定（现在不动）。

## 10. 架构优化观察（不在本任务改）

1. `tool/delete_participant.js` 和 `tool/purge_tester_data.js` 对“是不是生产”的判断方式不同：前者只看 `--production`，后者沿用 `tool/firestore_target.js`（`--project` + `--production-confirm`）。三个脚本（加 `prelaunch_config.js`、`randomization_sequence.js`）值得统一到 `firestore_target.js`，并把 `--production` 收编进去。
2. `delete_participant.js` 的 `storagePlan` 每删一个人都把 `exports/` 全部文件下载一遍。批量删几十个账号时是 N × 文件数的下载；可以在清理脚本层面缓存一次，或让 `run()` 接收预先读好的导出内容。现在数据量小，先不动。
3. 带 uid 的顶层集合清单（`TOP_LEVEL`）靠人手维护。T24 / T27 / T30 新加集合时容易漏。可以写一个模拟器测试：遍历 `functions/` 里所有 `collection("…")` 字面量，对比 `TOP_LEVEL` 和一个“明确不删”的白名单，漏了就失败。
4. `admin_runs` 是第一个“管理脚本运行记录”集合。`set_shared_context_consent.js`、`correct_arm_assignment.js` 各有自己的日志方式；以后可以都写到 `admin_runs`，一处可查。

## 要带回研究侧的发现

1. 任务单说“没有研究期字段的账号”都是测试员数据。这个前提只在 10/19 前成立；之后装了 App 但还没登记的真实老人也没有 `cohort`。这个脚本只应在登记开始前跑一次，之后要删人应逐个用 `tool/delete_participant.js`。
2. 删除后 `arm_assignment_log` / `pilot_assignment_log` 里测试账号的条目会留下（研究编号、层、位置、组别）。DMP 若写“试用期数据全部删除”，要加一句这两类日志保留。
3. 评估员账号在 T30 之前的过渡办法是设 `isTester: true`（T21 报告第 4.5 节）。这个脚本按角色保留他们，不看 `isTester`；但如果某位员工账号**还没发角色**又标了 `isTester`，会被列为 `tester`——名单里看到员工的 uid 就先发角色或用 `--keep`。
