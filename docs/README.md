# docs/：项目文档

## 从哪里开始读

| 想知道 | 读 |
|---|---|
| App 现在是怎么做的 | `dev/architecture.md` |
| 还有什么没做、什么没定 | `dev/backlog.md` |
| 之前做过什么、讨论过什么 | `history.md` |
| 为什么这样设计 | `decisions/` |
| 参与者会感受到的改动 | `STUDY_CHANGELOG.md` |

## 怎么记录开发迭代

文档和代码放在同一个仓库，同一个 PR 里一起改。论文的方法部分和附录从这里取材，不再凭记忆重写。

## 目录

| 位置 | 放什么 | 怎么写 |
|---|---|---|
| `decisions/NNNN-*.md` | 决策记录：每个设计决定一份 | 写好就不改。想推翻就写一份新的，旧的标 `Superseded by NNNN` |
| `STUDY_CHANGELOG.md` | 参与者能感受到、或者会影响测量的改动 | 一行一条，最新的在最上面，带 tag 和生效日期 |
| `research/` | 和论文对齐的设计文档（操纵定义、测量、分析） | 随时可以改，状态以最新版为准 |
| `dev/` | 开发规格 | 随时可以改 |
| `validation/` | 测试集、词表的验证结果 | 由脚本生成，不手改 |
| `config-snapshots/<tag>.json` | 每个 tag 对应的 Firestore `meta/*` 配置 | 由 `tool/export_config.js` 导出 |
| `history.md` | 开发记录：每次合并、每次讨论 | 合并 PR 或做出决定后加一段，最新的在最上面 |
| `dev/backlog.md` | 待办、待决定、暂缓 | 随时更新 |
| `dev/architecture.md` | App 技术文档 | 代码改了，同一个 PR 里更新 |
| `history/` | 过时文档的快照 | 不再更新 |
| `safety/` | 安全词库各版本、性能评估 | 新版本新建文件 |
| `prompts/`、`privacy/` | prompt 全文、个人信息清洗规则 | 随代码更新 |
| `release/` | Phase A 基线（pilot 期）的交接和评审 | 不再更新 |
| `spec/feature-registry.md` | 研究侧功能登记表（C01–C22），规格的唯一来源 | 只由研究侧改，开发侧不改 |
| `spec/audit-YYYYMMDD.md` | 按登记表逐项核对代码的结果 | 每轮核对新建一份 |
| `dev-tasks/` | 交给 Claude Code 的开发任务单 | 一批任务一份，按日期命名 |
| `dev-reports/` | 任务单产出的报告（文件名带任务号和日期） | 每次新建，不覆盖 |

`validation/`、`config-snapshots/` 和 `tool/export_config.js` **还没有**，Phase B 冻结前建立。

## 一次改动的流程

1. 如果改的是设计（会影响参与者体验，或者会影响测量），先在 `decisions/` 写一份决策记录。
2. 改代码。
3. 在同一个 PR 里更新 `STUDY_CHANGELOG.md`，需要的话也更新 `research/` 或 `dev/`。
4. 合并以后打 tag，导出配置快照。

纯重构、修 typo、改开发工具，只写 git commit message 就够了，不进 changelog。

## 写论文时怎么用

| 论文部分 | 从哪里取 |
|---|---|
| Methods 里的干预描述 | `research/` 里的操纵定义 |
| Intervention fidelity、protocol deviations | `STUDY_CHANGELOG.md` 里研究期间的条目 |
| Appendix 里的技术验证 | `validation/` 里最终版本的结果 |
| Discussion 里「为什么这样设计」 | `decisions/` 里的理由和被否决的方案 |

数据里每条消息都带 `buildSha` 和 `promptVersion`，所以任何一段对话都能对应到当时的代码和 changelog 条目。

## 给 Claude Code 的规则（已复制到仓库根目录的 CLAUDE.md）

```markdown
## 文档规则
- 任何改动只要涉及 prompt、记忆、分组、界面或推送，同一个 PR 里必须更新 docs/STUDY_CHANGELOG.md。
- 设计层面的决定先在 docs/decisions/ 写决策记录（模板：docs/decisions/0000-template.md），再改代码。
- 已有的决策记录不修改；要推翻就新写一份，并在旧的那份里标 Superseded。
- prompt 一律放在 functions/prompts/<name>.v<N>.txt；改内容就新建一个版本文件，不覆盖旧文件。
- 已打 phaseB-* tag 之后，行为上的改动要在 changelog 里写明影响的 cohort/组别和生效日期。
```
