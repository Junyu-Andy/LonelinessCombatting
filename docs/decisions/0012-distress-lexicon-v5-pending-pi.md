# 0012：安全词库先沿用 v5-2026-09，PI 临床签核搁置

> 2026-10-04 负责人决定。

- 日期：2026-10-04
- 状态：已采纳（临时）
- 影响范围：所有 cohort × 两组
- 相关代码：`lib/core/safety/distress_detector.dart`

## 背景

词库 v5 的几个临床取舍需要 PI 签核：「我想死」判为 moderate_interrupt（AI 照常回复、显示支援模板、不进紧急页）；"I don't see a reason to live." 不触发；无望类表述统一为 moderate。

## 决定

先按 v5 现状使用，签核搁置。PI 有结论后，如需改动，写新的决策记录并按 PR 流程改词库和测试。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| （当时没有认真考虑其他方案） | — |

## 后果

- 对研究：如果研究期间才改词库，要记为 protocol deviation，并写进 `STUDY_CHANGELOG.md`。
- 对开发：无。
