# 0021：盲法导出改用研究编号和结局量表白名单；后台按 Auth 角色区分盲与非盲

- 日期：2026-10-07
- 状态：提议中（代码已写，开关默认关，等研究侧确认后打开）。第 5 条（角色）已被 0029 取代：`pi` 不再是非盲角色，改为 `unblinded` / `blinded`，PI 是盲法人员
- 影响范围：phase_b × 两组（盲法导出、研究者后台）；所有 cohort（分组时生成研究编号）
- 相关代码：分支 `fix/blinding`（T12，SPEC:C19）

## 背景

旧的盲法导出（`blindedDataExport`）只把 `arm` 换成 Group_X/Y，其他能看出组别的字段都还在：`turns.llm.*`、只有 Hybrid 组才有的 `llm_turn_features`、`safety_events.source` 等；`sessions`/`turns` 的 `participantId` 就是原始 uid；每周换盐，`uidHash` 和 Group_X/Y 跨周都对不上（T2 报告 3.3）。研究者后台直接显示两组人数（T1 C19）。

## 决定

1. **研究编号**：服务器在分组时（`assignArm` 同一个事务里）生成，形如 `P7K3QX2`（P + 6 位 Crockford base32，随机）。导出时遇到还没有编号的参与者，就补发。编号整个研究期间不变。
2. **对照表**：`research_id_map/{uid}` → `{researchId, createdAt, via}`，`research_ids/{researchId}` → `{uid, createdAt, via}`。只有服务器写；只有非盲角色能读。不写进 `users/{uid}`，App 读不到。
3. **组别代码固定**：A/B → Group_X/Y 的对应只生成一次，存在 `export_blind_keys/stable_v2`，不再每周换。客户端谁都不能读。
4. **导出用白名单**：只导出两组都答的结局量表和几个中性的参与者字段，每行带 `researchId` 和 `groupCode`。过程数据（对话轮次、会话、事件、LLM 和记忆相关集合等）**揭盲前一律不导出**。Brief PR 因为两组弹出频率不同（决策 0015），单独一个开关，默认不导出。只导出随机分组的参与者（Phase A、pilot、测试员不导出：他们全是 A 组，会暴露对应关系）。
5. **角色用 Auth custom claims**：`role: researcher` = 盲法人员；`role: pi` = 非盲。由 `tool/provision_researcher.js` 发放。Firestore 规则用 `request.auth.token.role == 'pi'` 判断非盲。`meta/arm_counter`（各层两组人数）改为只有非盲角色能读。
6. **开关**：`meta/blinding_config`，客户端不可读写。`enabled`（默认 false）：开后分组时生成编号，周导出改用新版，写到 `exports_v2/{日期}/`；关着时旧导出照旧。`includeBriefPr`、`includeUsageSummary` 默认 false。
7. **检查脚本**：`tool/check_blinded_export.js` 扫一份导出，发现可疑字段或集合就非零退出，测试里跑。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 服务器维护角色集合（如 `roles/{uid}`） | 规则每次都要多读一次文档；已有 custom claims 和发放脚本，沿用更简单 |
| 研究编号用 uid 加固定盐的哈希 | 盐泄露就能整体还原；随机编号加对照表更容易单独保管和删除 |
| 在旧导出上继续加黑名单字段 | 新字段默认会被导出；白名单默认不导出，更稳 |
| 把过程数据中性化后导出 | 两组的会话结构本身不同（规则组每次提交是一轮的会话），去字段也挡不住，揭盲前不导出最稳 |
| 开关默认开 | 共同规则要求新行为默认关；旧导出在 Storage 里，只有服务账号能拿到，先由研究侧决定何时切换 |

## 后果

- 对研究：盲法分析员只拿到结局量表、分层信息和用户输入引起的安全事件数。使用量（`usage_weekly`）和 Brief PR 要研究侧决定是否在揭盲前给。DMP 和统计分析计划要写明：研究编号对照表的保管人是非盲角色。
- 对开发：`functions/blinding.js`、`functions/arm.js`、`functions/index.js`、`firestore.rules`、研究者后台、`tool/check_blinded_export.js`。整人删除脚本（T11）要连带删除两张对照表里的记录。
- 对论文：方法部分写盲法分析员拿到的数据范围和揭盲流程。
