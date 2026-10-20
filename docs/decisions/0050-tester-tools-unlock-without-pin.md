# 0050：测试员工具改为「后台标测试员 + 服务器开关 + 点 7 次版本号」解锁，不再要打包时加测试密码

- 日期：2026-10-19
- 状态：提议中
- 影响范围：只影响 `isTester` 帐号；参与者（pilot / phase_b × 两组）看不到任何变化
- 相关代码：分支 `claude/zealous-fermat-8rgqtg`；`lib/core/testing/tester_gate.dart`、`lib/features/settings/presentation/pages/support_about_page.dart`、`lib/core/feature_flags/remote_feature_flags.dart`

## 背景

测试员工具（预览量表、日程模拟、测试推送、切换组别、重置资料）从 2026-09-23 起只能用打包时写进去的测试密码 `TESTER_PIN` 解锁。给老人的包不带密码，所以测试员要用工具就得另外打一个包，iOS 还要连线装，太麻烦（Junyu 10/19）。另外，`isTester` 从 10/16 起已经只有管理员能写（`firestore.rules`、`tool/set_tester.js`），工具背后的服务器函数也会再查一次 `isTester`。

## 决定

1. 新开关 `app_config/feature_flags.testerToolsEnabled`（**默认关**，只认布尔 `true`）。
2. 帐号的 `users/{uid}.isTester` 是 `true`、而且开关开着时，在「關於同支援」连点版本号 7 次就直接解锁，不用密码，任何包都行（包括给老人的包）。
3. 不是测试员的帐号点 7 次什么都不发生，也不出提示。测试员但开关没开，会提示「伺服器開關 testerToolsEnabled 未開」。
4. 旧的测试密码方式保留：包里带了 `TESTER_PIN` 的，照样可以输密码解锁。
5. 解锁只维持到关掉 App 为止，和以前一样。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 继续用 `TESTER_PIN` | 每次都要另外打包，iOS 要连线装，正是要解决的问题 |
| 只看 `isTester`，不要服务器开关 | 研究期间想整体关掉测试员工具时没有总闸 |
| 把测试密码放进 Firestore | 客户端要读得到才能比对，等于公开；`isTester` 本来就只有管理员能写，更可靠 |

## 后果

- 对研究：参与者帐号不能写 `isTester`，所以拿不到测试员工具；测试员照旧不进研究数据。
- 对开发：要用时在控制台开 `testerToolsEnabled`，并用 `tool/set_tester.js` 或控制台给测试员帐号设 `isTester: true`，改完重开 App。
- 对论文：无。
