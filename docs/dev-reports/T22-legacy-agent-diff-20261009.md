# T22 旧“陪伴者区分评估”收尾（SPEC:C15、C22）— 报告

日期：2026-10-09。分支 `fix/legacy-agent-diff`。依据 `docs/dev-tasks/dev-tasks-1008.md` T22、登记表 v4 C15。

## 结论

- **Phase B 新版盲法导出不再含旧 `agent_diff`**：从导出白名单拿掉，导出清单里列为“揭盲前不导出”；检查脚本见到 `agent_diff` 文件会报错（退出 1）。
- **Phase A**：`adaEnabled` 打开时不弹旧 `agent_diff`，关着时照旧。这在 T17 已经实现（`lib/features/ada/data/ada_gate.dart` 的 `legacyAgentDiffVisible`），本次只补了测试，没改 App 代码。
- **没有新开关**。没删旧集合、旧页面，没改已有数据。老人看到的没有任何变化，也没有新文字。
- 两套全量测试都通过（第 3 节）。
- 没写新决策记录：这是执行登记表 C15 和决策 0026 已定的事，不是新的设计决定。

## 1. 改了哪些文件

| 文件 | 改动 |
|---|---|
| `functions/blinding.js` | `OUTCOME_COLLECTIONS` 删去 `agent_diff`；`HELD_BACK` 加上 `agent_diff`（导出 `manifest.json` 的 `heldBackUntilUnblinding` 里会写明）；注释更新 |
| `tool/check_blinded_export.js` | `ALLOWED_FILES` 删去 `agent_diff`；`HELD_BACK_FILES` 加上，报错写“must not be exported before unblinding” |
| `functions/test/blinding_test.js` | 新测试“T22: old agent_diff is held back”；原来借 `agent_diff` 测长字符串的那行改用 `weekly_pr` |
| `functions/test/blinding_emulator_test.js` | 合成队列（已种 `agent_diff` 数据）导出后：没有 `agent_diff.ndjson`、清单写明不导出、检查脚本退出 0 |
| `test/ada_test.dart` | 真实构建测试里补上：Phase A 构建 `adaEnabled` 开 → 不显示旧问卷，关 → 显示 |
| `docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`、`docs/history.md`、`docs/dev/backlog.md` | 按 CLAUDE.md 更新；待办第 78、79 项 |

## 2. 代码里还会读或导出 `agent_diff` 的地方（都没改）

| 位置 | 做什么 | 说明 |
|---|---|---|
| `lib/features/assessment/presentation/pages/agent_diff_page.dart` | 旧问卷页，写 `users/{uid}/agent_diff` | 页面保留 |
| `lib/core/scheduling/pending_prompts_service.dart` | 第 14 天、第 28 天判断要不要弹，读 `agent_diff` 看做过没有 | 先看 `AdaGate.legacyAgentDiffVisible`，关着时不读 |
| `lib/features/today/presentation/widgets/pending_prompts_banner.dart` | 首页横幅入口 | 同上 |
| `lib/features/settings/presentation/pages/settings_page.dart` 第 417、1139 行 | 设置页入口 | 同上 |
| `functions/index.js` 第 1380、1486 行 | **旧版**导出（`meta/blinding_config.enabled` 关着时，写 `exports/`），整份文档导出，uid 换哈希，`freeResponse` 原文也在 | 也是 Phase A 的导出，没改；见待办 79 |
| `tool/admin_dump.js` 第 79 行 | 单人原始数据导出（带 uid），研究员排查用 | 不是盲法导出，没改 |
| `tool/delete_participant.js` 第 134 行 | 整人删除时按子集合全部删除，`agent_diff` 也在内 | 不变 |

Phase B 构建：`LEGACY_AGENT_DIFF_PHASE_B` 默认关（T17），App 不弹、不写新数据。

## 3. 测试

- `tool/ci_backend_tests.sh`：全部通过（Functions 单元测试、规则测试、emulator 测试；其中 blinding 11 项、blinding emulator 7 项）。emulator 用合成的两组队列，含 `agent_diff` 数据，导出后没有 `agent_diff`，检查脚本退出 0。
- `tool/ci_flutter_tests.sh`：6 套构建变体全部通过（Phase A 默认构建和 `PHASE_B=true` 都跑了 `test/ada_test.dart`）。
- Phase A 开/关和 Phase B 的覆盖：`AdaGate` 单元测试（`phaseB` false/true × `adaEnabled` 开/关 × 旧开关）和真实构建测试。**App 侧没有 Firestore emulator 测试**：项目没有假 Firestore 的测试库，为这一条加依赖不划算；`pending_prompts_service.dart` 在 `legacyDiff` 为假时直接跳过，不读 `agent_diff`，所以逻辑全在 `AdaGate` 里。

## 4. 要带回研究侧的发现

1. **Phase B 里已有的旧 `agent_diff` 数据**：T17 之前的 Phase B 包会在第 14、28 天弹旧问卷。如果有人做过，算偏离还是忽略？这些数据现在不进盲法导出，揭盲后要不要用？（待办 78）
2. **旧版导出仍含 `agent_diff`**（盲法开关关着时，`functions/index.js`），包括 `freeResponse` 原文。它同时是 Phase A 的导出，T22 没动。要不要在 T21 按研究期分开时一起处理？（待办 79）
3. Phase A 的 `adaEnabled` 打开以后，旧问卷整个不出现（第 14、28 天都没有）。如果 Phase A 打开 ADA 后仍要旧问卷，请说明（T17 报告第 10 节第 7 条，未变）。
