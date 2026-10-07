# T14 量表现状清单（2026-10-07）

> 只读核对。没有改功能代码，没有连生产 Firestore。
> 基线：`main` @ 9642ac5。行号以这个提交为准。
> 起点参考：`docs/export/20261006/10-shared-questionnaires.md`（T3 逐字导出）、`docs/spec/audit-20261006.md` 的 C14 / C15 / C22 行（T1）。下面每一项都回到代码重新核对过。
> 对应登记表：SPEC:C14、SPEC:C15（第 7 日问卷涉及 C22）。

## 结论先说

1. **研究侧记录里有 4 项在代码里找不到**：LSNS-6、Phase A 可用性（SUS 或其他）、Phase A 第 7 日问卷、UCLA 的 app 内填写。
2. **DJG 版本不一致**：研究侧是 11 条版，以情感分量表（6 题，0–6 分）为主要结局；代码是 **6 条版**，情感题只有 3 题。代码里的 `score` 也是 0–6，但它是“情感 3 + 社交 3”的总分，**不是情感分量表**。两个“0–6”含义不同，分析时容易混淆。
3. **DJG 只做一次**：只在入组第 14–16 天做。没有基线，也没有后续时间点。代码里没有任何地方用 DJG 做筛选（≥2）或分层（≥5）；现在分层用的是 UCLA（>44 算高）。
4. **Brief PR 是 1–7 分点选，不是 0–100 滑杆**。Insensitivity 题 App 存原始分，分析时才反转（8 − x），这和研究侧一致。
5. **每周孤独探针实际上不会出现**：开关 `WEEKLY_PROBE` 默认关；就算打开，问卷页也没有入口；服务器写队列和 App 读队列的路径也对不上；服务器也不发推送。
6. **ADA 应该就是代码里的“陪伴者区分评估”（agent_diff）**，但时间点不同：代码是第 14 天和第 28 天，研究侧是“当场一次、第 7 日一次”。
7. **所有问卷的题目和页面两组完全相同**。两组不同的只有 Brief PR 的弹出条件（规则组签到和回忆一提交就弹）。
8. **Phase A 和 Phase B 构建的问卷没有差别**。`PHASE_B` 只决定显示哪组界面。时间表参数 `PhaseAConfig` 两种构建都用，远程改了会同时影响 Phase B 的人。

## 1. 总表

“两组”指 Hybrid 组（A）和规则组（B）。“A/B 构建”指不加 / 加 `--dart-define=PHASE_B=true` 的安装包。

| 问卷 | 题数和题目来源 | 作答格式 | 反向计分 | 什么时候出现 | 存在哪里 | 两组相同？ | Phase A/B 构建不同？ |
|---|---|---|---|---|---|---|---|
| Brief PR | 4 题（可远程改成 3）。`lib/features/brief_pr/presentation/pages/brief_pr_page.dart:232, 244, 256, 271` | 1–7 点选，无默认值 | 第 4 题 Insensitivity。**App 存原始分**，分析时 8 − x | 每次会话结束，见第 2.1 节 | `users/{uid}/brief_pr`；另写 `users/{uid}/sessions/{id}.briefPR` | 题目相同；**弹出条件不同** | 不同（Phase A 包所有人走 A 组规则） |
| Weekly PR | 12 题（4 个分量表 × 3）。`lib/features/weekly_pr/data/weekly_pr_response.dart:82–96` | 1–7「唔同意—同意」，题目顺序每次随机 | i1–i3（Insensitivity）。**App 存原始分**，代码里没有反转 | 每周日 20:00 到周二 23:59 | `users/{uid}/weekly_pr` | 相同 | 相同 |
| PGIC | 1 题 7 选项。`lib/features/assessment/presentation/pages/pgic_page.dart:29–37` | 7 个带文字的选项，1 = 改善咗好多 … 7 = 差咗好多 | 无（数字越小越好） | 和 Weekly PR 同一窗口，排在前面 | `users/{uid}/pgic` | 相同 | 相同 |
| DJG | **6 条**（情感 3 + 社交 3）。`lib/features/assessment/data/djg_es_response.dart:39–76` | 3 档：係 / 多少啦 / 唔係 | 社交题计分方向相反，**App 存原始答案并另存总分** | 入组第 14–16 天，一次 | `users/{uid}/djg_es` | 相同 | 相同 |
| ADA（推断 = 陪伴者区分评估） | 第 2 周：使用频率 3 + 特质 12 + 开放题 1；第 4 周再加情境 5。`lib/features/assessment/data/agent_diff_response.dart:116–174` | 频率 4 档；特质 1–5；情境 4 选 1；开放题文字或语音 | 无 | 入组第 14–16 天；第 28 天起 | `users/{uid}/agent_diff` | 相同 | 相同 |
| UCLA | **App 内没有题目**。研究员在注册页输入总分。`lib/features/auth/presentation/pages/login_page.dart:227–270` | 一个数字，20–80，可留空 | 不适用（只存总分） | 注册时一次 | `users/{uid}.baselineUclaScore` | 相同 | 相同 |
| 每周孤独探针 | 1 题。`lib/features/loneliness_probe/presentation/loneliness_probe_page.dart:71–74` | 0–10 滑杆，**默认停在 5** | 无 | **实际不会出现**，见第 2.6 节 | `users/{uid}/loneliness_probes` | 相同 | 相同（另有独立开关 `WEEKLY_PROBE`） |
| 每日心情（研究侧未列） | 1 题 5 个心情脸。`lib/theme/app_mood_encoding.dart:42–75` | 1 = 好辛苦 … 5 = 好開心 | 无 | 每天第一次打开首页 | `users/{uid}/daily_mood` | 相同 | 相同 |
| LSNS-6 | **未在代码中找到** | — | — | — | — | — | — |
| Phase A 可用性（SUS 等） | **未在代码中找到** | — | — | — | — | — | — |
| Phase A 第 7 日问卷 | **未在代码中找到** | — | — | — | — | — | — |

## 2. 逐个说明

### 2.1 Brief PR

**题目**（只有中文会显示，见 `docs/export/20261006/10-shared-questionnaires.md` 开头的说明）：

| 字段 | 题目 | 端点标签 |
|---|---|---|
| `understanding` | 「{名} 明白我。」 | 完全唔係咁 · 一半半 · 完全係咁 |
| `validation` | 「{名} 尊重我。」 | 同上 |
| `caring` | 「{名} 關心我。」 | 同上 |
| `insensitivity` | 「{名} 嘅回應好似搞錯重點，或者唔在乎。」 | 完全唔係咁 · **有少少** · **好係咁** |

- 来源：`brief_pr_page.dart:200–202`（前 3 题标签）、`brief_pr_page.dart:279–281`（第 4 题标签）。
- 注意：第 4 题的中点标签是「有少少」，前 3 题是「一半半」。同一个“4 分”，文字不一样。
- 题目顺序固定，不随机。

**作答格式**：7 个数字圆点，必须点选，没有预选（`brief_pr_page.dart:3–9`）。2026-06 由 0–100 滑杆改成 1–7（`brief_pr_response.dart:7–12`）。文档里有 `schemaVersion`：2 = 1–7；没有或 1 = 旧的 0–100 记录。

**题数**：默认 4 题（`lib/core/config/phase_a_config.dart:25`）。远程文档 `app_config/phase_a` 的 `briefPRItemCount` 可以改成 3，只能是 3 或 4（`phase_a_config.dart:106`）。改成 3 时去掉的是 Insensitivity。

**计分方向**：Insensitivity 是反向题。**App 存原始分，不反转**；注释写明分析时用 8 − x（`brief_pr_response.dart:9–11, 32`）。仓库里没有分析脚本，所以“分析时反转”这一步目前只存在于注释里。

**什么时候弹出**：

| 页面 | 条件 | 来源 |
|---|---|---|
| 聊天类页面（两组的通通；A 组的签到、回忆、自由对话） | 离开页面时，本次会话用户发言 ≥ 2 轮，且不是因为危机结束 | `lib/features/brief_pr/data/brief_pr_gate.dart:109–123`；轮数 `phase_a_config.dart:24` |
| 规则组的签到、回忆 | 每提交一次算一次会话，提交后就弹，危机结束的不弹 | `lib/features/brief_pr/data/rule_submission_flow.dart:76–100`；决策 0015 |

- 每个陪伴者第一次弹出时没有「跳過」按钮；之后 3 秒后出现（`brief_pr_page.dart:82–86`）。
- 跳过也会写一条记录，`status: "skipped"`（`brief_pr_page.dart:156–179`）。
- 没有推送，只在会话结束时弹出。

**存储**：`users/{uid}/brief_pr/{自动编号}`，字段见 `brief_pr_response.dart:67–81`：4 个分数、`agentId`、`sessionRef`、`isAnchorPrompt`、`status`、`promptedAt`、`respondedAt`、`arm`、`schemaVersion`。同时在 `users/{uid}/sessions/{id}.briefPR` 写 `{shown, completed, items}`（`lib/core/session/chat_session_recorder.dart:494–509`）。

**两组**：题目相同；弹出条件不同（见上表）。规则组签到和回忆一次提交就弹，Hybrid 组要聊满 2 轮。T1 已指出这会影响两组 Brief PR 的数量和时机（推断）。

**Phase A / B 构建**：Phase A 包里 `Arm.of` 一律返回 A（`lib/core/arm/arm_scope.dart:30`），所以所有人都走“≥2 轮”规则。

### 2.2 Weekly PR

**题目**：12 题，分 4 组，每组 3 题（`weekly_pr_response.dart:84–95`）。题干都以「頭先 {名}」开头。

| 分量表 | 题号 | 内容（缩写） | 方向 |
|---|---|---|---|
| Understanding | u1 u2 u3 | 明白我嘅感受 / 想法；真係聽到我講嘅嘢 | 正向 |
| Validation | v1 v2 v3 | 尊重我嘅感受；認可我講嘅嘢；冇判斷我 | 正向 |
| Caring | c1 c2 c3 | 真心關心我；為我著想；回應令我覺得舒服 | 正向 |
| Insensitivity | i1 i2 i3 | 搞錯重點；唔在乎；回應令我覺得唔舒服 | **反向** |

- 只有中文，没有英文版。
- **题目顺序每次随机打乱**，4 题一页，共 3 页（`weekly_pr_page.dart:72–78`）。

**作答格式**：1–7，两端标「唔同意」「同意」（`weekly_pr_page.dart:340–344`）。

**计分方向**：i1–i3 是反向题。**App 存原始分**（`items` 里是 1–7），代码和注释都没有写在哪里反转。需要分析方案写明。

**评哪个陪伴者**：每周只评一个。按这周（周一 0:00 到周日 20:00）的会话数选最多的；一样多就比用户发言轮数；再一样就选最近用过的（`lib/features/weekly_pr/data/weekly_pr_window.dart:386–408`）。这周没有会话：只问 PGIC，写一条 `status: "no_referent"`（`pending_prompts_banner.dart:96–112`）。

**时间表**：

- 开放：周日 20:00 起，到周二 23:59（`weekly_pr_window.dart:313–319`；`phase_a_config.dart:26–27`）。
- 推送：Cloud Function `weeklySurveyReminder`，**每周日 20:00 香港时间**，发给所有装了 App 的设备（主题 `all`）（`functions/index.js:1475–1480, 1302–1307`）。同时给每个非测试账号记一条 `weekly_pr_pushed` 事件。
- 入口：首页横幅（`lib/core/scheduling/pending_prompts_service.dart:84–103`）。
- 可以跳过（「今個禮拜跳過」），跳过也写记录，本周不再出现（`weekly_pr_page.dart:458–460`）。
- 窗口关了还没做：写一条 `missed_{周}` 记录（`lib/features/weekly_pr/data/weekly_pr_trigger.dart:210–246`）。
- 时区：服务器用 `Asia/Hong_Kong`。App 用手机本地时间（`lib/core/time/app_clock.dart:42`）。手机时区不是香港时，窗口会跟着偏（推断）。

**存储**：`users/{uid}/weekly_pr/{自动编号}`，字段：`weekIso`、`items`（u1…i3 → 1–7）、`status`（completed / skipped / no_referent / missed）、`referentAgentId`、`referentRule`、`sessionCountThisWeek`、`arm` 等（`weekly_pr_response.dart:41–53`）。

**两组、两种构建**：相同。T1 指出：规则组一次提交算一次会话，被选中评分的陪伴者可能偏向小欣、阿珍（推断）。

### 2.3 PGIC

**题目**：「同上個星期比較，你而家覺得自己嘅孤單感整體上有冇變化？」（`pgic_page.dart:95–97`）

**作答格式**：7 个带文字的选项，竖排（`pgic_page.dart:29–37`）：

| 值 | 文字 |
|---|---|
| 1 | 改善咗好多（冇咁孤單） |
| 2 | 改善咗 |
| 3 | 少少改善（少少冇咁孤單） |
| 4 | 冇變 |
| 5 | 差咗少少（多咗少少孤單） |
| 6 | 差咗 |
| 7 | 差咗好多（更加孤單） |

**计分方向**：数字越小越好。App 存原始值，不需要反转，但分析时要记得方向。

**时间表**：和 Weekly PR 同一个窗口，同一次推送，排在 Weekly PR 前面（`pending_prompts_banner.dart:78–88`）。

- 没有「跳過」按钮。按返回键离开不写记录，窗口内会再出现。
- 窗口关了没做，**不写 missed 记录**（只有 Weekly PR 写）。

**存储**：`users/{uid}/pgic/{自动编号}`，字段 `value`、`answeredAt`、`isoWeek`（数字）、`weekIso`（字符串，被评的那一周）（`pgic_page.dart:55–67`）。注意 `pgic_response.dart:3` 的注释写成 `pgic_responses`，实际集合是 `pgic`。

**两组、两种构建**：相同。

### 2.4 DJG

**结论**：代码是 6 条短版，研究侧是 11 条版。措辞是粤语工作草稿，注释写明要换成“问卷 v1.3”的正式文字（`djg_es_response.dart:6–10`）。版本号 `djg_es_6_draft_v1-2026-09`。

**作答格式**：3 档，1 = 係，2 = 多少啦，3 = 唔係（`djg_es_response.dart:79–83`）。整份可以跳过（`djg_es_page.dart:114–115`）。

**计分**：App 存原始答案（`answers`），同时算好一个总分 `score` 存进去（`djg_es_response.dart:85–95`）：

- 情感题（e1–e3）：答「係」或「多少啦」各记 1 分；
- 社交题（s1–s3）：答「多少啦」或「唔係」各记 1 分（方向相反）；
- 总分 0–6。跳过时 `score = -1`。
- **没有单独存情感分量表分数**，但可以从 `answers` 重新算（0–3）。

**和研究侧 11 条版逐题对照**

11 条版的题目来自公开文献（De Jong Gierveld & Kamphuis 1985；中文以研究侧问卷 v1.3 为准）。仓库里没有 11 条版。

| 11 条版 | 分量表 | 英文原题 | 代码里有没有 | 代码中文（草稿） |
|---|---|---|---|---|
| 1 | 社交 | There is always someone I can talk to about my day-to-day problems | **没有** | — |
| 2 | 情感 | I miss having a really close friend | **没有** | — |
| 3 | 情感 | I experience a general sense of emptiness | e1 | 我成日覺得好空虛。 |
| 4 | 社交 | There are plenty of people I can lean on when I have problems | s1 | 有困難嗰陣，有好多人我可以靠。 |
| 5 | 情感 | I miss the pleasure of the company of others | **没有** | — |
| 6 | 情感 | I find my circle of friends and acquaintances too limited | **没有** | — |
| 7 | 社交 | There are many people I can trust completely | s2 | 有好多人我可以完全信任。 |
| 8 | 社交 | There are enough people I feel close to | s3 | 有好多人同我好親近。 |
| 9 | 情感 | I miss having people around me | e2 | 我掛住有人喺身邊。 |
| 10 | 情感 | I often feel rejected | e3 | 我成日覺得被人冷落。 |
| 11 | 社交 | I can call on my friends whenever I need them | **没有** | — |

差别汇总：

| 项目 | 研究侧（11 条版） | 代码（6 条版） |
|---|---|---|
| 题数 | 11（情感 6 + 社交 5） | 6（情感 3 + 社交 3） |
| 情感分量表 | 6 题，0–6 分 | **3 题，0–3 分**；没有单独存 |
| 存下的 0–6 分 | 情感分量表 | **情感 + 社交总分** |
| 选项 | 0–6 分的计法通常是把 3 档或 5 档答案二分（推断，按公开计分方法） | 3 档：係 / 多少啦 / 唔係 |
| 筛选 ≥2、分层 ≥5 | 有 | **代码里没有**。分层用 UCLA（`functions/arm.js:36–45`） |
| 时间点 | 主要结局，应有多个时间点（推断） | **只有一次**：入组第 14–16 天 |
| 措辞 | 问卷 v1.3 | 工作草稿。s3 把 “enough” 译成「好多」；e1 加了「成日」 |

**时间表**：

- 入组第 14、15、16 天（第 1 天 = 账号创建那天）（`pending_prompts_service.dart:108–117`；`lib/core/scheduling/enrolment_day.dart:9–14`；`phase_a_config.dart:28–29`）。
- 推送：`week2Push`，**每天 10:00 香港时间**检查，第 14–16 天的人推一次，只推一次；测试账号不推（`functions/index.js:1581–1640`）。推送文字「入嚟兩個禮拜喇，有幾條短問題想問下你。」
- 做完或跳过都写记录（带 `timepoint: "week2"`），之后不再出现。
- 第 14–16 天没打开 App，就再也不会出现，也不写 missed 记录。

**存储**：`users/{uid}/djg_es/{自动编号}`，字段 `timepoint`、`itemsVersion`、`answers`（e1…s3 → 1–3）、`score`、`status`、`answeredAt`、`answeredAtLocal`（`djg_es_response.dart:115–123`）。

**两组、两种构建**：相同。

### 2.5 ADA（推断 = 陪伴者区分评估 agent_diff）

**为什么判断是它**：代码注释两次写到对齐的文件名 `Agent_Differentiation_Assessment_Final_v1.0`（`agent_diff_response.dart:118, 148`），缩写正好是 ADA；页面也是“比较三个陪伴者”。代码里没有别的问卷叫 ADA。（推断）

**内容**（`lib/features/assessment/presentation/pages/agent_diff_page.dart`）：

| 部分 | 内容 | 格式 | 第 2 周 | 第 4 周 |
|---|---|---|---|---|
| A 使用频率 | 过去两周，平均每周和每个陪伴者倾几多次 | 4 档：完全冇 / 少過一次 / 一至兩次 / 三次或以上，存 0–3（第 383 行） | 有 | 有 |
| B 特质 | 4 个特质 × 3 个陪伴者：溫暖關心人；似自己同年紀；好奇鍾意問我嘢；聽我講而唔評判我 | 1–5（1 = 完全唔似，5 = 好似）（第 528–531、601 行） | 有 | 有 |
| C 情境 | 5 个情境各选一个陪伴者，或「邊個都得／冇所謂」 | 4 选 1（第 634–637 行） | 没有 | 有 |
| D 开放题 | 「仲有咩想補充？」 | 文字，可语音输入，可留空（第 740–782 行） | 有 | 有 |

**计分方向**：没有反向题。

**时间表**：

- 第 2 周：入组第 14–16 天，和 DJG 同一个横幅、同一次推送，DJG 做完接着做（`pending_prompts_banner.dart:116–141`）。
- 第 4 周：入组第 28 天起，**没有截止日**，**没有推送**（`pending_prompts_service.dart:118–120`）。
- 没有「跳過」按钮。按返回键离开不写记录，之后还会再出现。

**存储**：`users/{uid}/agent_diff/{自动编号}`，字段 `wave`、`timepoint`（week2 / week4）、`usageFreq`、`personality`、`function`、`freeResponse`、`answeredAt`（`agent_diff_response.dart:41–49`）。

**和研究侧对照**：研究侧是“Phase A 当场一次、第 7 日一次”。代码是第 14 天和第 28 天，没有“当场”，也没有“第 7 日”。**不一致**。

**两组、两种构建**：相同。

### 2.6 每周孤独探针

**题目**：「過去一個星期，你幾經常覺得孤獨？」两端标「完全冇」「非常」（`loneliness_probe_page.dart:71–94`）。

- 题目问“几经常”（频率），端点却是“完全冇 / 非常”（程度）。
- 滑杆**默认停在 5**（第 23 行），老人不动直接提交就记成 5。

**作答格式**：0–10 滑杆，11 个刻度。

**现在为什么不会出现**（四道关都没打开）：

1. App 编译开关 `WEEKLY_PROBE` 默认 `false`（`lib/core/feature_flags/feature_flags.dart:31–32, 40`）。
2. 就算开了，`LonelinessProbePage` 全仓库没有任何地方打开它，首页没有入口。
3. 服务器每周日 9:00（香港时间）的 `weeklyLonelinessProbe` 只给 `users/{uid}.weeklyProbeEnabled == true` 的人写队列（`functions/index.js:1062–1101`）。这个字段默认 `false`，App 里没有地方把它设成 `true`（`lib/features/auth/data/user_profile.dart:276, 470`）。
4. **路径对不上**：服务器写顶层 `pending_loneliness_probes/{uid}`（`functions/index.js:1092`），这个集合 App 不能读（`firestore.rules:160–162`）；App 读的是 `users/{uid}/pending_loneliness_probes/current`（`lib/features/loneliness_probe/data/loneliness_probe.dart:83–92`）。所以永远读不到“待做”。

另外，这个任务只写队列，**不发推送**。

**存储**（如果有人填）：`users/{uid}/loneliness_probes/{自动编号}`，字段 `score`、`answeredAt`、`isoWeek`（`loneliness_probe.dart:34–38`）。

**两组、两种构建**：两组相同。和 `PHASE_B` 无关，只看 `WEEKLY_PROBE`。

### 2.7 UCLA

- **App 内没有 UCLA 题目。**
- 注册页有一栏「研究人員填寫」：输入入组前 UCLA-LS-V3 总分，20–80，可以留空（`login_page.dart:149, 227–270`）。只在注册时出现。
- 用途：分层随机。>44 算“高孤独”（`functions/arm.js:21, 36–45`）。**留空按 44 处理，算进“低”层**。
- 存储：`users/{uid}.baselineUclaScore`（`user_profile.dart:251–255, 397`）。
- 没有任何后续时间点。
- 两组、两种构建相同。

### 2.8 每日心情（研究侧记录没有列）

- 「你今日心情點？」5 个心情脸，1 = 好辛苦，2 = 差啲，3 = 一般，4 = 好，5 = 好開心（`lib/theme/app_mood_encoding.dart:42–75`）。
- 每天第一次打开首页弹出，可以「今日跳過」（`lib/features/today/presentation/widgets/daily_mood_prompt.dart`；`today_page.dart:63, 73`）。
- 推送：`dailyMoodReminder`，**周一至周六 19:00 香港时间**，发给所有设备（`functions/index.js:1459–1473`）。
- 存储：`users/{uid}/daily_mood`；每天第一条 `is_primary: true`，之后的标 `supplementary: true`（`lib/features/today/data/mood_recorder.dart:13–26`）。
- 规则组签到页也会写同一个集合（`lib/features/context/presentation/pages/check_in_arm_b.dart:258`）。
- 两组、两种构建相同。

### 2.9 代码里有、但参与者看不到的

| 名称 | 状态 | 来源 |
|---|---|---|
| Phase B 探针：猜组别（第 4、8 周）、依赖感（第 8 周）、陪伴者可区分度（第 2、4 周） | 只有数据结构和写入函数，**没有页面，也没有触发**。注释说“Phase A 关闭”，实际两种构建都没有 | `lib/features/phase_b_probes/data/phase_b_probes.dart:1–28` |
| 旧版 PPR（每次 2 题、每周 12 题） | 只在测试员工具里 | `lib/features/ppr/data/ppr_scale.dart`；`settings_page.dart:1092–1093` |
| 测试员工具里的问卷直达入口 | 要输入测试 PIN 才看得到 | `settings_page.dart:306–400, 1060–1100` |

## 3. 推送和触发时间表（全部香港时间）

| 推送 / 任务 | 时间 | 发给谁 | 带出什么 | 来源 |
|---|---|---|---|---|
| `dailyMoodReminder` | 周一至周六 19:00 | 所有设备（主题 `all`） | 每日心情（打开首页才弹） | `functions/index.js:1459` |
| `weeklySurveyReminder` | 周日 20:00 | 所有设备（主题 `all`，测试机也收到） | PGIC → Weekly PR 横幅，开到周二 23:59 | `functions/index.js:1475` |
| `week2Push` | 每天 10:00 检查 | 入组第 14–16 天、还没推过的非测试账号，按设备推 | DJG → ADA 第 2 周横幅 | `functions/index.js:1581` |
| `weeklyLonelinessProbe` | 周日 9:00 | 只写队列，不推送 | 孤独探针（实际不会出现） | `functions/index.js:1062` |
| （无推送） | 入组第 28 天起 | — | ADA 第 4 周横幅 | `pending_prompts_service.dart:118` |
| （无推送） | 每次会话结束 | — | Brief PR | `brief_pr_gate.dart`、`rule_submission_flow.dart` |

- 时间表参数都在 `lib/core/config/phase_a_config.dart:22–31`，可以用 Firestore `app_config/phase_a` 远程改。服务器的 `week2Push` 读同一个文档（`functions/index.js:1538–1546`）。
- “入组第 N 天”按账号创建日算，不是知情同意日或分组日（`enrolment_day.dart:1–6`）。
- 推送只是“门铃”。问卷靠首页横幅出现。不打开 App 就不会做。

## 4. 两组和两种构建的差别

**两组**：

- 所有问卷的题目、选项、存储、时间表两组相同。
- 唯一不同：Brief PR 弹出条件（第 2.1 节）。
- 小问题（T1 已指出）：拿不到组别时，Brief PR 和 Weekly PR 记 `'B'`（`brief_pr_page.dart:106, 160`；`weekly_pr_page.dart:98`），横幅和 missed 记录记 `'A'`（`pending_prompts_banner.dart:103`；`pending_prompts_service.dart:98`）。

**Phase A / Phase B 构建**：

- `PHASE_B` 只改两件事：`Arm.of` 是否读真实分组（`arm_scope.dart:30`），以及记忆模式。问卷代码不看它。
- 所以 Phase A 包里没有任何 Phase A 专属问卷：没有可用性题、没有第 7 日问卷、没有“当场 ADA”。
- `PhaseAConfig` 名字叫 Phase A，但两种构建都用。远程改 `app_config/phase_a`，会同时改 Phase B 参与者的时间表和 Brief PR 题数。现在也没有 `cohort` 字段（决策 0011 未实现），无法只对一部分人生效。
- `WEEKLY_PROBE` 和 `PHASE_B` 是两个独立开关，默认都关。

## 5. 和研究侧记录对照

| 量表 | 研究侧记录 | 代码现状 | 判断 |
|---|---|---|---|
| Brief PR | 每次会话后 4 题：Understanding、Validation、Caring、Insensitivity（反向），0–100 滑杆 | 每次会话后 4 题（可改 3），**1–7 点选**；Insensitivity 存原始分，分析时反转；两组弹出条件不同 | **不一致**（格式） |
| Weekly PR | 12 题，4 个分量表各 3 题，每周一次 | 12 题，4 × 3，1–7，每周日 20:00 到周二；只评一个陪伴者；i1–i3 反向，代码没写在哪反转 | 一致（需补反向计分说明） |
| 每周孤独探针 | 每周推送 | 开关默认关；没入口；队列路径对不上；不推送 | **不一致**（实际不存在） |
| DJG | 11 条版，情感分量表 6 题（0–6 分）为主要结局；筛选 ≥2，分层 ≥5 | **6 条版**，情感 3 题；存的 0–6 是总分；只做一次（第 14–16 天）；没有筛选和分层逻辑 | **不一致** |
| UCLA | 方案里有，版本和时间点待核 | UCLA-LS-V3 总分，研究员注册时手填一次，可留空；只用于分层 | 版本：LS-V3；时间点：只有入组前（App 外） |
| ADA | 比较三个 agent；Phase A 当场一次、第 7 日一次 | （推断）agent_diff：第 14 天、第 28 天各一次 | **不一致**（时间点） |
| PGIC | 有 | 每周一题，7 选项，和 Weekly PR 一起 | 一致 |
| LSNS-6 | 3 个时间点 | **未在代码中找到**。最接近：入组问卷第 2 部分“重要的人”（最多 5 位，联络频率是自由文字）（`lib/features/onboarding/data/intake_response.dart:161–163`；`intake_flow_page.dart:811–820`），只做一次，不是量表（推断） | **缺失** |
| Phase A 可用性 | 现有题目或 SUS，待定 | **未在代码中找到**。最接近：ADA 开放题「仲有咩想補充？」和每条回复的 👍👎（`lib/features/response_feedback/`），都不是可用性量表（推断） | **缺失** |
| Phase A 第 7 日问卷 | Weekly PR、ADA、可用性题目、3 道开放题 | **未在代码中找到**。最接近：第一个周日的 Weekly PR（落在入组第 1–7 天之间，取决于哪天注册）和第 14 天的 ADA；第 3、6 天只有“试下某陪伴者”的提示，不是问卷（`week1_nudge_banner.dart`）（推断） | **缺失** |

## 6. 顺带发现的问题（只记录，没有改）

1. **孤独探针的队列路径对不上**（第 2.6 节第 4 条）。以后要开，除了打开开关、加入口，还要改路径和推送。
2. **DJG 的 `score` 字段容易被当成情感分量表**。两者都写“0–6”。
3. **第 2 周完成事件可能记早了**：ADA 页按返回离开不会保存，但横幅照样把 ADA 当成完成，可能发出 `w2_completed` 事件（`pending_prompts_banner.dart:137–141`）（推断，未在模拟器验证）。
4. **第 2 周错过就没了**：第 14–16 天没打开 App，DJG 和第 2 周 ADA 都不再出现，也不写 missed 记录。Weekly PR 有 missed 记录，这两个没有。
5. **ADA 第 4 周没有截止日**：第 28 天起一直挂在首页，直到做完。
6. **孤独探针滑杆默认 5**，题目问频率但端点是程度。
7. **Brief PR 第 4 题中点标签和前 3 题不同**（「有少少」对「一半半」）。
8. **UCLA 留空按 44 算**，进“低孤独”层。
9. **盲法导出**包括 `brief_pr`、`weekly_pr`、`pgic`、`djg_es`、`agent_diff`、`daily_mood`、`loneliness_probes`；不包括入组问卷 `onboarding/intake`（`functions/index.js:1128–1149`）。

这些都不加进 `docs/dev/backlog.md`（按统筹会话说明），由研究侧决定后再排。

## 7. 要带回研究侧的发现

1. **DJG 用哪一版要定**。代码是 6 条版（情感 3 题），研究侧要的情感分量表 6 题只有 3 题在代码里。要用 11 条版，需要补 5 题（11 条版第 1、2、5、6、11 题）、给正式中文措辞（问卷 v1.3），并说明选项是 3 档还是 5 档。
2. **DJG 的时间点要定**。现在只有第 14–16 天一次。作为主要结局，需要说明基线、中期、结束各在第几天，以及“筛选 ≥2、分层 ≥5”是在 App 里做还是 App 外做。现在分层用的是 UCLA > 44。
3. **Brief PR 是 1–7 点选**。登记表 C14 写的“0–100 滑杆”要改。Brief PR 题数（3 还是 4）仍待 PI 定。
4. **Weekly PR 的 i1–i3 要在分析方案里写明反向计分**。App 存原始分，没有任何地方反转。
5. **ADA 的定义和时间点要确认**。我按 Agent Differentiation Assessment 推断。代码是第 14 天、第 28 天；研究侧是“当场 + 第 7 日”。
6. **LSNS-6、可用性（SUS）、第 7 日问卷在代码里都没有**。如果 Phase A 要用，需要给题目、选项、时间点；也可以确认改为 App 外（纸本或访谈）收集。
7. **UCLA 只在 App 外做**，研究员在注册页填总分。需要确认：其他时间点是否也在 App 外做；留空按 44 算是否可以接受。
8. **每周孤独探针要不要开**。现在实际不存在。要开的话，需要定题目（频率还是程度）、默认值（建议不预设）、推送时间，并修好路径。
9. **两组 Brief PR 弹出条件不同**（规则组签到和回忆一提交就弹）。需要研究侧确认可以接受，或者在分析里处理。
10. **`app_config/phase_a` 改一次会同时影响 Phase A 和 Phase B 的人**。在 cohort 字段做好之前，Phase B 开始后不要随意改它。
11. **研究侧记录里没有的量表**：每日心情（每天，1–5）。代码里还有 Phase B 三个探针（猜组别、依赖感、可区分度）的数据结构，但没有页面。需要研究侧说明这些是否在方案里。
