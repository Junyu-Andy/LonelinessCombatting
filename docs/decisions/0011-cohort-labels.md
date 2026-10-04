# 0011：用 cohort 区分 pilot / phase_a / phase_b，Phase A 和 B 用同一个版本

> 补记（2026-10-04）：这个决定在 2026-10-01 的对话里做出，代码还没改。

- 日期：2026-10-01
- 状态：已采纳，**未实现**
- 影响范围：所有 cohort
- 相关代码：—

## 背景

正式参与者都还没入组。现有账号都是 pilot 期的；之后 Phase A（单组）和 Phase B（随机两组）都要招募，并且共用一个 Firebase 项目。现在只能靠 `armAssignmentMode` 推断是哪一批人。

## 决定

- `users/{uid}.cohort` = `pilot` / `phase_a` / `phase_b`，由服务器写入，客户端不能改。
- 现有全部账号一次性标 `pilot`。
- 之后注册的，`randomise` 关着标 `phase_a`，开着标 `phase_b`。
- 打开随机前把 `meta/arm_counter` 清零。
- 分析和记忆查询按 `cohort` 过滤。
- Phase A 和 Phase B 用同一个版本，删掉 `PHASE_B` 编译开关。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| Phase A 完全丢弃 | 负责人改为：Phase A 仍单独招募，但版本和 Phase B 同步 |

## 后果

- 对研究：pilot 数据和正式数据从字段上分开。
- 对开发：见 `docs/dev/memory-and-entry-spec.md` 第 1 节；阻断项是分组方式以 `assignArm` 还是 HTML 工具为准。
