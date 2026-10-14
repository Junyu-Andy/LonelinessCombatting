# 0040：Phase A 的代码先 fork 到单独仓库，再从这个仓库删掉；这个仓库只留 Phase B 和试跑

- 日期：2026-10-14
- 状态：提议中（负责人 10/14 提出；产品窗口确认后改为「已采纳」，并在 0034 顶部加一行「第 2、6 条由 0040 取代」）
- 影响范围：phase_a（代码搬走）；phase_b、pilot × 两组（行为不变，只少了关着的代码）
- 相关代码：瘦身任务 SL2（`docs/dev-tasks/dev-tasks-slim.md`）；PR 待开

## 背景

决策 0034 定了 Phase A 暂停、以后单独开仓库和 Firebase 项目，但代码「现在不删」，因为开新仓库时可能要搬走。结果是 Phase A 的整套功能（ADA、第 7 日问卷和流程、第 2 周推送、旧的每周孤独探针、`agent_diff` 对比页）还在这个仓库里，约 6,000 行代码加测试、规则和 8 个服务器函数，全部靠开关关着。它们让每次打包、每个 PR 和每次代码审查都带着一堆不会运行的东西。

负责人的想法：不等「以后」，现在就把这个仓库整个 fork 一份作为 Phase A 的仓库，然后把这个仓库当作只做 Phase B 的仓库，把用不到的功能、代码和注释尽量精简。

## 决定

1. **先 fork，后删。** 在删 Phase A 代码的 PR 合并之前，在 GitHub 上把本仓库 fork 为 `LonelinessCombatting-phaseA`（名字可改），并在本仓库 `main` 上打 tag `phaseA-archive-YYYYMMDD`，指向删代码前的最后一个提交。fork 和 tag 都包含完整历史，所以 Phase A 以后恢复时既有代码也有决策和报告。
2. **fork 里马上做三件事，别的先不动：** 关掉 `deploy-firebase.yml` 和 `build-apk.yml` 两个工作流（或删掉仓库 secrets `FIREBASE_SERVICE_ACCOUNT`），把 `.firebaserc` 的项目改成占位值。目的只有一个：fork 永远不能部署到 Phase B 正在用的 Firebase 项目 `loneliness-pilot-dev`。Phase A 自己的 Firebase 项目等 Phase A 恢复时再建（0034 第 6 条）。
3. **本仓库删 Phase A 专用代码（SL2）**：`lib/features/ada/`、`functions/ada.js`、第 7 日流程和开放题、`week2Push`、`weeklyLonelinessProbe` 和 `lib/features/loneliness_probe/`、`lib/features/phase_b_probes/`（旧探针）、`agent_diff_page.dart`、`phase_a_schedule_config.dart`、Firestore 规则里只给这些集合用的条目、它们的测试，以及 `functions/index.js` 里对应的 8 个导出（`weeklyLonelinessProbe`、`week2Push`、`adaDay7Dispatch`、`onAdaResponseWritten`、`onDay7OpenResponseWritten`、`adaStaffDay7Status`、`adaStaffLoad`、`adaStaffSave`）。删函数要同时在 Firebase 上删已部署的同名函数（`firebase deploy` 会提示删除，要确认）。
4. **不删的东西：** `PHASE_B` 编译开关保留（决策 0037 第 1 条不变，参与者包固定 `PHASE_B=true`）；`lib/core/safety/` 不动（决策 0033，两组一致）；`cohort` 字段里 `phase_a` 这个值保留（已有旧数据可能带它）；`PA-` 编号登记时拒绝的逻辑和测试保留（T21）。
5. **数据不动。** Firestore 里已有的 `ada_responses`、`day7_open_responses`、`ada_status`、`agent_diff`、`loneliness_probes` 集合不删、不迁移；导出脚本不再读它们。
6. **注释一起精简（SL8）。** 删掉描述已删功能的注释和只对 Phase A 成立的说明；保留指向决策编号、任务编号和登记表条目的注释（它们是论文和审计的线索）。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 照 0034 继续留着代码，等 Phase A 恢复再搬 | 每次打包和审查都带着 6,000 行死代码；fork 一次就解决「以后可能要搬」的顾虑 |
| 只打 tag、不 fork | tag 够找回代码，但 Phase A 以后要有自己的 issue、PR、Actions secrets，fork 现成；两样都做，成本几乎为零 |
| 把 Phase A 代码搬进本仓库的一个子目录或分支 | 还是在同一个仓库里，打包、CI、搜索都绕不开它 |
| 在 fork 里就开始把 Phase B 代码删掉 | 没人现在开发 Phase A，先冻结；恢复时再反向瘦身 |

## 后果

- 对研究：Phase B 和试跑的行为不变（所有被删的功能在 Phase B 包里本来就关着）。登记表里写「暂停」的 Phase A 条目（C22 等）改为「已移至 Phase A 仓库」。不涉及 protocol、ICF、HREC。
- 对开发：SL2 一个 PR；合并前跑全套测试、打一个测试包和删前的包对比首页、三个陪伴者、设置页、每周问卷。T21 报告第 5 节的 8 个 `PHASE_B` 文件不在这次范围。
- 对论文：不涉及 Phase B 方法。Phase A 的仓库地址写进 Phase A 自己的材料。
