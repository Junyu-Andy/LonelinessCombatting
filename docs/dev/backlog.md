# 待办与待决定

> 随时更新。做完的移到 `docs/history.md`，划掉或删掉这里的条目。
> 最后更新：2026-10-06

## 1. 已决定、待开发

| # | 事项 | 依据 | 备注 |
|---|---|---|---|
| 1 | **cohort 标记**：现有账号标 `pilot`；`assignArm` 写 `phase_a` / `phase_b`；规则禁止客户端写；计数器清零；删 `PHASE_B` 开关 | 决策 0011 | 阻断项：分组以 `assignArm` 还是 HTML 工具为准 |
| 2 | 记忆和入口的 P0 | `docs/dev/memory-and-entry-spec.md` 第 3 节 | 等负责人调研完记忆架构 |
| 3 | `meta/arm_counter` 改为客户端不可读、不可写 | 决策 0003（W1） | 分组已在服务器做，客户端不再需要它。可以和第 1 项一起做 |
| 4 | 每次分组写审计日志（时间、层、当时计数、结果、硬币） | `arm_assignment_scheme_v1.md` W2 | 建议和第 1 项一起做 |

## 2. 上线前必须做（负责人操作）

| # | 事项 | 怎么做 |
|---|---|---|
| 5 | 部署的一次性设置 | 仓库 Settings：加 secret `FIREBASE_SERVICE_ACCOUNT`；新建 environment `production` 并设审批人。见 `docs/dev/ci-cd.md` |
| 6 | `main` 分支保护 | Settings → Branches：必须走 PR、CI 通过才能合并 |
| 7 | 部署 | 顺序见 `docs/dev/architecture.md` 第 9 节 |
| 8 | ICF 修订 | 记忆强制开启、发给 DeepSeek、查看和删除、保留 3 年。负责人在改 |
| 23 | 研究文件里的模型名 | 登记表 C03、protocol、ICF、DMP、HREC 材料里的「DeepSeek-V3」「deepseek-chat」改为 DeepSeek-V4.1-Flash（`deepseek-flash`，思考关闭）。见决策 0017 |
| 24 | 部署决策 0017 的改动 | 现在线上的 Functions 还在请求旧名 `deepseek-chat`，DeepSeek 停用旧名当天 Hybrid 组会全部报错。合并后尽快部署 Functions |

## 3. 待决定

| # | 问题 | 现状 | 谁决定 |
|---|---|---|---|
| 9 | 分组以 `assignArm` 为准，还是以独立 HTML 随机化工具（v1.3.1）为准 | 代码里只有 `assignArm`（最小化）；仓库里没有 HTML 工具 | 负责人 / 统计师 |
| 11 | **自由对话在规则组隐藏**，和「界面完全一致」原则冲突 | 决策 0006 | 负责人 |
| 13 | 分组失败期间（显示规则组界面）的数据算不算 | 决策 0004 | 负责人 |
| 14 | Hybrid 组有人留在研究里但要求删除全部记忆：要不要让服务器停止记新的 | 现在删了还会继续记 | 负责人 |
| 15 | phase_a 用记忆 v0 还是 v1 | 规格倾向 v1 | 负责人 |
| 16 | 安全词库 v5 的临床取舍 | 搁置，先沿用（决策 0012） | PI |
| 17 | 周度孤独感问卷 Phase B 开不开 | 编译开关 `WEEKLY_PROBE`，默认关 | 负责人 |
| 18 | 通通规则组模板的文化顾问审核 | 未审核 | 负责人 |
| 19 | CODEOWNERS：安全文件改动必须 PI 审核 | 需要 PI 的 GitHub 账号 | 负责人 |
| 20 | E4 微随机是否采用 | 规格 4.2 预留开关 | 负责人 |

## 4. 暂缓或以后再做

- 端到端测试用例表（暂缓）。
- 单独的 staging Firebase 项目（不需要）。
- 函数代码约 880 个 lint 格式错误一次性修复，之后 CI 检查格式。
- Dependabot 自动更新依赖。
- Android 正式签名（现在用调试密钥，只能内部测试）。
- 记忆 P2：RAG、人生叙事摘要、遗忘、对话中确认、按内容共享、多条待跟进、删除 v0（见规格第 5 节）。
- 回忆 A 组研究记录仍保存 acute 那一轮原文（研究数据的决定，未改）。
