# 0046：设置页「保留對話紀錄」开关默认不显示（取代 0020 第 5 条）

- 日期：2026-10-19
- 状态：提议中（待 Junyu 确认，并核对 ICF）
- 影响范围：pilot / phase_b × 两组
- 相关代码：分支 `claude/zealous-fermat-8rgqtg`；`lib/features/settings/presentation/pages/settings_page.dart`、`lib/core/feature_flags/remote_feature_flags.dart`

## 背景

决策 0020 第 5 条把「保留對話紀錄」开关放回了设置页（「自己」→ 個人資料一节），老人可以自己关。Junyu 10/19 核对 App 时提出这个选项「不是说不开放了吗」。仓库里没有找到更早取消它的书面记录，所以这里补一份。

## 决定

1. 新开关 `app_config/feature_flags.transcriptRetentionToggleEnabled`（**默认关**，只认布尔 `true`）。关着时设置页不显示「保留對話紀錄」这一行；开了就恢复 0020 的做法。
2. 已存的同意值（`consent.transcriptRetention` 和三位陪伴者各自的值）一个都不改。之前自己关过的老人照旧是关。
3. 老人要关闭保留对话，和共享同意一样，联系研究团队由后台处理。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 直接删掉这一行代码 | 研究侧如果改主意要重新发版；用开关可以当天恢复 |
| 保留开关 | Junyu 10/19 表示不开放 |

## 后果

- 对研究：ICF 如果写了「可以在 App 设定里关闭保留对话」，要改成「联系研究团队」。登记表 C20 补一句。
- 对开发：要恢复，就在控制台把 `transcriptRetentionToggleEnabled` 设成 `true`，老人重开 App。
- 对论文：方法部分写数据保留时按新说法。
