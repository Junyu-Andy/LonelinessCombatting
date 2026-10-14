# 瘦身任务单（SL1–SL8，2026-10-14 定号）

> 给做瘦身的单独会话。任务内容就是 `docs/dev-reports/handoff-20261014.md` 第五节那张七步表（PR #74），这里只做三件事：给每一步一个编号、写清先后和门槛、补充第五节没写的两件事（results 目录是什么；Phase A 改为 fork 后删，决策 0040）。
>
> 编号用 `SL`（slim，瘦身），不用 `T`：`T` 号是负责人的功能任务单（已到 T46），`S` 号是界面文案编号（S2–S12），`R`、`C`、`X` 也都有人用。

## 结论

- 一步一个编号、一个 PR。SL1–SL7 和交接第五节的第 1–7 步一一对应，SL8 是贯穿各步的注释清理。
- 决策记录：Phase A 移除用 **0040**（已写，状态「提议中」，产品窗口确认后改「已采纳」）。其余各步不改行为，不需要决策记录；SL4、SL5 若改了配置文档的字段名要加。
- 时间：10/19 冻结前只做 SL1。冻结后、W4（11/9）前做 SL2、SL3、SL5。SL4、SL6、SL7 排到试跑结束后。
- 每个 PR 的门槛：`tool/ci_flutter_tests.sh` 和 `tool/ci_backend_tests.sh` 全过；用 GitHub Actions 打一个 `phase_b_templates` 测试包，和改前的包对比首页、三个陪伴者、设置页、每周问卷；`docs/dev/architecture.md` 同一个 PR 更新；行为没变就不写 `docs/STUDY_CHANGELOG.md`。
- 瘦身 PR 要在功能 PR（T38–T46）合完后的安静窗口开，不然 `functions/index.js`、`docs/*` 顶部会反复撞。

## 编号表

| 编号 | 做什么（细节见交接第五节同序号那行） | 决策 | 什么时候 | 风险 |
|---|---|---|---|---|
| SL1 | `tool/memory_eval/results/` 的原始输出移出仓库，只留汇总（见下） | 不需要 | 随时，10/19 前 | 零 |
| SL2 | 先 fork 本仓库为 Phase A 仓库并打 tag，再删 Phase A 专用代码、测试、规则和 8 个服务器函数 | **0040** | 冻结后、W4 前；0040 采纳后才能开 PR | 低 |
| SL3 | `functions/index.js` 拆薄：只留注册，逻辑进模块；一次 `eslint --fix`；CI 加 lint | 不需要 | 冻结后第一件 | 低 |
| SL4 | 聊天页抽公共壳（`Composer`、`SessionEndFlow`） | 不需要 | 试跑稳定后 | 中 |
| SL5 | 三套配置读取合一（App 一套 load/parse/current；服务器一个 `config.js`） | 改字段名才要 | 和 SL3 一起 | 低 |
| SL6 | 研究周/研究日、角色判断、推送发送、导出白名单各只留一份 | 不需要 | T24/T30 合并后 | 低 |
| SL7 | `user_profile.dart` 按字段更新；`settings_page.dart`、`researcher_dashboard_page.dart` 拆成每卡一文件 | 不需要 | 以后 | 中 |
| SL8 | 注释和死代码清理：随 SL2–SL7 每个 PR 顺手做，不单开 PR | 0040 第 6 条 | 贯穿 | 低 |

## SL1 补充：`tool/memory_eval/results/` 里是什么、为什么这么大

**是什么。** 这是记忆抽取的验收测试结果（T4、T10、T31 三份报告的证据）。脚本用 30 段自己编的粤语对话（`dialogues/`）在 Firebase 模拟器上跑真实的服务器记忆代码，真的调用 DeepSeek，把模型抽出来的事实、跟进、摘要和标准答案（`gold/`）比对打分。每跑一轮就在 `results/<轮次>/` 留三个文件：

| 文件 | 内容 | 大小 |
|---|---|---|
| `raw.json` | 整轮的原始记录：规则组零抽取零注入的检查、30 段对话各自的调用记录和抽出的每条记忆、跑完后的记忆全貌、跨陪伴者泄露检查时截下来的整段 system prompt、删除检查 | 每轮约 1 万到 1.3 万行，占全部的 **九成** |
| `score.json` | 打分汇总（精确率、编造数、每段的判定计数） | 约 800 行 |
| `appendix.md` | 逐条判定表，报告直接引用 | 约 300–400 行 |

**为什么有 14 个条目。** 不是一轮，是三次任务各跑了几轮：

| 条目 | 来源 | 说明 |
|---|---|---|
| `stub` | T4 | 用标准答案冒充模型跑一遍，只为检查脚本本身，不联网 |
| `run1`、`run2` | T4（10/6） | 记忆 v1 验收，真实调用两轮看稳定性 |
| `t10_run1`–`t10_run4` | T10（10/7） | 修抽取 prompt 后重跑，四轮是四次修改 |
| `t10_run3_replay`、`t10_run4_replay` | T10 | 用第 3、4 轮录下的模型输出重放再打分，不联网；内容和 `t10_run3`/`t10_run4` 几乎一样，是为了证明打分可重算 |
| `t31_v3_run1` | T31（10/10） | 抽取 prompt v3 的分层检查，只有 `raw.json` 和 `layers.md` |
| `ledger*.json` | 三次任务 | 每段对话调用 DeepSeek 的次数记账（上限 3 次），每个几十行 |

合计 31 个文件、约 9.8 万行、3.9 MB（交接第五节写的「17 万行」偏大，以 `git ls-files` 统计为准）。其中 9 个 `raw.json` 约 8.8 万行；`score.json`、`appendix.md`、`layers.md` 和账本加起来约 1 万行。

**建议怎么处理（SL1 的具体做法）。** 不整个目录删掉：报告引用了逐条判定和调用次数，这些是论文记忆部分的证据。做法：

1. 9 个 `raw.json` 移出仓库，打成一个 zip 挂到 GitHub Release（或存到研究侧的共享盘），在 `tool/memory_eval/README.md` 写明下载地址和放回 `results/<轮次>/raw.json` 就能用 `--mode=replay` 重算。
2. `.gitignore` 加 `tool/memory_eval/results/*/raw.json`，以后的新轮次原始输出默认不进仓库。
3. `score.json`、`appendix.md`、`layers.md`、`ledger*.json` 留在仓库里（约 1 万行），报告里的引用不用改。
4. 三份报告（T4、T10、T31）各加一行：原始输出已移至 Release 附件。

这样仓库少约 8.8 万行、3.5 MB，证据链不断，脚本的重放模式照样能用。

## SL2 补充：先 fork 再删（决策 0040）

顺序固定，不能倒：

1. 功能 PR 合完、冻结包打好之后，在 `main` 上打 tag `phaseA-archive-YYYYMMDD`。
2. GitHub 上 fork 本仓库为 Phase A 仓库。fork 里只做三件事：关掉 `deploy-firebase.yml` 和 `build-apk.yml`（或删 secret `FIREBASE_SERVICE_ACCOUNT`），`.firebaserc` 改成占位项目名，README 顶部写一句「Phase A 存档，暂停开发，不要部署」。目的是 fork 永远不能碰 Phase B 的 Firebase 项目。
3. 0040 状态改「已采纳」，0034 顶部加一行「第 2、6 条由 0040 取代」。
4. 本仓库开 SL2 的 PR，删的清单在 0040 第 3 条，不删的在第 4 条（`PHASE_B` 开关保留，决策 0037）。
5. 合并后部署 Functions 时确认删除 8 个已部署的函数；打一个测试包和 tag 那个包对比。
6. 登记表里 Phase A 的条目改为「已移至 Phase A 仓库」（研究侧）。

## SL8 补充：注释怎么删

- 删：描述已删功能的注释；写「Phase A 时……」「以后 Phase A 恢复要……」的说明；复述代码在做什么的逐行注释；注释掉的旧代码；文件顶部过时的「TODO」和「临时」说明。
- 留：指向决策编号（`决策 0033`）、任务编号（`T21`）、登记表条目（`C15`）、文案编号（`S6`）的注释，哪怕只有一行；安全检测里解释「为什么这样判」的注释；服务器上「规则组不能调 LLM」那道防线旁边的说明。
- 原则：注释回答「为什么」就留，回答「是什么」就删。删完 `grep -rn "Phase A\|phase_a\|ADA\|day7" lib functions` 应该只剩 `cohort` 取值和 `PA-` 拒绝那几处。
