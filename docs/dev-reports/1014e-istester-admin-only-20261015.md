# 1014e 第 2 节第 3 条：`isTester` 只允许管理员写（2026-10-15）

分支 `fix/istester-admin-only`，从 main `e6926df` 开。PR 草稿。依据：`docs/dev-tasks/dev-tasks-1014e.md` 第 2 节第 3 条（10/14 第 11 条 (6)，backlog 96）。没有改热线、IAM、feature-registry；只用模拟器。

## 结论

1. **规则**：`users/{uid}` 的客户端新建不能带 `isTester`（true 或 false 都拒），更新不能新增、改动或删除它；其他字段照旧可写，`isTester: true` 的账号做普通的 merge 写也照旧（App 不再带这个字段，服务器的值留着）。
2. **App**：`UserProfile.toMap` 不再输出 `isTester`（仍从 `fromMap` 读）；设置页「測試員帳號」从开关改成只读说明（显示是不是测试员、由管理员设置）。注册和任何资料更新都不会再碰这个字段，所以规则不会误拦正常写入（规则测试覆盖了“注册 create”“tester 账号的 merge 写”“重复写同一值”三种）。
3. **设置方法**：`tool/set_tester.js --uid=<uid> --tester=true`（或 `--email=`，要 Auth；`--list` 列出全部测试账号）。模拟器默认，真项目要 `--project` + `--production-confirm`。**登记过的账号（有 `enrollments/{uid}`）默认拒绝**，加 `--allow-registered` 才能标，免得把 PILOT / PB 老人标成测试员。控制台直接改也可以。
4. **验收**（1014e）：模拟器里参与者账号写 `isTester` 被拒（规则测试）；管理员脚本能写（脚本模拟器测试）。
5. **部署**：规则要在 10/19 开登记门前部署；部署后先用脚本给团队账号和两位评估员账号设 `isTester: true`（登记门开着时没有 cohort 又不是测试员的账号只看到等待页）。App 侧随 10/19 构建，旧包的开关写入会被规则拒绝（无害，只是开关拨不动）。

## 改了什么

| 文件 | 改动 |
|---|---|
| `firestore.rules` | `createLeavesTesterEmpty`、`updateLeavesTesterUntouched`，接进 `users/{uid}` 的 create / update |
| `lib/features/auth/data/user_profile.dart` | `toMap` 去掉 `isTester` |
| `lib/features/settings/presentation/pages/settings_page.dart` | 测试员开关 → 只读 `ListTile`（key `settings_tester_flag`） |
| `tool/set_tester.js`（新） | 管理员脚本，`run(db, auth, args)` 可测 |
| `test/rules/tester_flag_rules.test.js`（新，5 项）、`test/rules/package.json` | 规则测试 |
| `functions/test/set_tester_emulator_test.js`（新） | 脚本：设 / 清 / 列、拒绝登记过的账号、`--allow-registered`、坏输入 |
| `test/user_profile_test.dart` | `toMap` 无 `isTester`，`fromMap` 仍读 |
| 文档 | `STUDY_CHANGELOG.md` 一行；`architecture.md` 第 4 节防护一条 + 顶部核对；`history.md`；`backlog.md` 第 96 项；本报告 |

## 测试

| 测试 | 结果 |
|---|---|
| 规则 `tester_flag_rules.test.js` + 全部规则 | 见下 |
| `set_tester_emulator_test.js` | 见下 |
| `flutter test test/user_profile_test.dart test/app_settings_persistence_test.dart` | 见下 |
| `tool/ci_backend_tests.sh`、六套 Flutter | 本机 / CI |

## 要 Junyu 定的事

无。

## 要带回研究侧的发现

1. 上线清单（登记门打开前）加一步：用 `tool/set_tester.js` 给团队和评估员账号设 `isTester: true`，并 `--list` 核对名单里没有 `PILOT-` / `PB-`。
2. 旧包（10/15 装的）里的测试员开关在规则部署后会拨不动，不影响老人（那个开关要输入测试密码才看得到）。
