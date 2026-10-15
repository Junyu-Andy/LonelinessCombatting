# 1014e 第 2 节第 9 条（N6）：注册页删 UCLA 输入框；第 3 节第 2 题答案（2026-10-15）

分支 `fix/remove-ucla-field`，从 main `e6926df` 开。PR 草稿。依据：`docs/dev-tasks/dev-tasks-1014e.md` 第 2 节第 9 条、第 3 节第 2 题。只改 App 和文档。

## 结论

1. **删了**：`lib/features/auth/presentation/pages/login_page.dart` 注册表单最后的「研究人員填寫（參加者唔使理）」说明和「UCLA 基線總分（20–80）」输入框（连同它的校验）。注册时不再传 `baselineUclaScore`；`UserProfile.baselineUclaScore` 字段和 `AuthService.signUp` 的可选参数保留（旧账号可能有值；不再写入）。
2. **第 3 节第 2 题答案**：
   - **读取方**：没有任何分层逻辑读它。`enrollParticipant`（`functions/randomization.js`）按研究员录入的 DJG-ES 情感分分层；`assignArm`（`functions/arm.js`）T19 起不分层。只有两处把它当参与者属性**原样导出**：盲法导出 `functions/blinding.js` `PARTICIPANT_FIELDS` 和锁库导出 `tool/analysis_export.js`（合成数据也会生成它）。导出保留不动：字段在旧账号里可能有值，去掉反而要改导出测试；对新账号导出为空。
   - **注册页老人自己填的字段**（研究员在旁协助）：电邮、密码、称呼（「你想我哋點樣叫你？」）、年龄（「年齡」，自由文本存 `ageGroup`）、紧急联络人称呼、紧急联络电话。不收任何量表。姓名就是“称呼”，没有单独的真实姓名栏。
3. 没有开关：删掉一个无用字段是修正，不是新行为；两组相同。

## 改了什么

| 文件 | 改动 |
|---|---|
| `lib/features/auth/presentation/pages/login_page.dart` | 删 45 行（说明 + 输入框 + 校验）、控制器及其 dispose、提交时的 `baselineUclaScore` |
| `lib/features/auth/data/auth_service.dart` | `signUp` 的 `baselineUclaScore` 参数注释改为“历史字段，不再收集” |
| `test/login_page_no_ucla_test.dart`（新） | 注册表单：没有 UCLA / 分層 / 量表字样；六个字段都在；共 6 个输入框 |
| 文档 | `STUDY_CHANGELOG.md` 一行；`architecture.md` 第 8 节用户文档一行 + 顶部核对；`history.md`；本报告 |

## 测试

| 测试 | 结果 |
|---|---|
| `flutter test test/login_page_no_ucla_test.dart` | 见 PR |
| `flutter analyze` | 见 PR |
| 六套 | GitHub CI |

## 要 Junyu 定的事

无。

## 要带回研究侧的发现

1. 登记表要注明“Phase B 注册页不收任何量表”（1014e 第 2 节第 9 条说由产品窗口改）。
2. 导出里的 `baselineUclaScore` 列对 Phase B / PILOT 账号永远为空；分析脚本可以忽略这列。DMP 的数据字典如果列了它，标“Phase B 不收集”。
