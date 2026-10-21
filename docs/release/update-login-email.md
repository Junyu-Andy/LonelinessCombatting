# 改登录电邮、重设密码（运维工具）

> 2026-10-20 第一版（1020j 第七节）。`tool/update_login_email.js`；不改 App、Functions 和规则。

## 结论

- 老人的登录电邮要换（例如打错了、换了电邮），或者忘了密码，用这个工具改。
- 先**空跑**：只显示改前改后，什么都不改。确认无误，再加 `--confirm --production` 正式改。
- 每次正式修改都在 Firestore 的 `account_admin_log` 写一条记录：谁、何时、哪个编号、旧电邮和新电邮的后四位。
- 不读序列、`randomization_state` 和分配日志。

## 怎么用

要用**能写的**管理钥匙（就是你跑 `delete_participant.js` 用的那把），不是看板的只读钥匙。在仓库根目录，新开一个终端：

```bash
cd ~/dev/LonelinessCombatting
export GOOGLE_APPLICATION_CREDENTIALS=~/dev/keys/<管理钥匙>.json
```

**改登录电邮**，先空跑：

```bash
NODE_PATH=functions/node_modules node tool/update_login_email.js \
  --research-id=RCT-001 --new-email=新电邮@example.com
```

会显示：

```
账号：uid abc…，研究编号 RCT-001
登录电邮：old@example.com  →  新电邮@example.com
App 资料里的电邮（users/abc….email）：old@example.com → 新电邮@example.com
空跑：什么都没改。确认无误后加 --confirm --production 再跑一次。
```

核对无误后，正式改（同一行，最后加两个参数）：

```bash
NODE_PATH=functions/node_modules node tool/update_login_email.js \
  --research-id=RCT-001 --new-email=新电邮@example.com --confirm --production
```

**重设密码**：把 `--new-email=…` 换成 `--reset-password`。正式改时会打印一个新密码，**只显示这一次**，交给老人。它由 10 个小写字母和数字组成，去掉了容易看错的 0、o、1、l。老人手机上要用新密码重新登录。

两样可以一起改：`--new-email=… --reset-password`。

没有研究编号的账号（例如测试员）用 `--uid=<uid>` 代替 `--research-id`。

## 会拒绝的情况

| 提示 | 意思 |
|---|---|
| `another account already uses this e-mail` | 新电邮已经被另一个账号用了 |
| `research ID … not found` | 没有这个研究编号 |
| `not on the emulator: add --production …` | 正式改要同时加 `--confirm --production` |
| `GOOGLE_APPLICATION_CREDENTIALS is not set` | 没设钥匙 |
| `nothing to change` | 没写要改什么 |

## 记录里有什么

`account_admin_log` 每次正式修改写一条，内容如下。只有服务器和管理钥匙能读，App 读不到。删除参与者（`tool/delete_participant.js`）时**不删**这些记录，和其他审计日志一样保留；删除回执的「没覆盖到」一栏会列出它（decisions-log 10/21，第 130 条之后的答复）。

| 字段 | 内容 |
|---|---|
| `action` | `email`、`password` 或 `email+password` |
| `researchId`、`uid` | 哪个账号 |
| `oldEmailLast4`、`newEmailLast4` | 旧电邮、新电邮 **@ 前面**的最后四个字符（整串的最后四位多半是 `.com`，看不出是哪个电邮） |
| `passwordReset` | 有没有重设密码（密码本身不记） |
| `by` | 用的哪把钥匙（服务账号的电邮） |
| `operator` | 电脑上的用户名 |
| `status`、`at`、`finishedAt` | 先写「pending」再改；改完是「done」，失败是「failed」并记错误代码 |

## 测试

`test/admin_tools/update_login_email_test.js`：用 Auth 和 Firestore 模拟器加合成账号测试，已经加进 CI 和 `tool/run_local_tests_mac.sh` 的隐私脚本那一步。
