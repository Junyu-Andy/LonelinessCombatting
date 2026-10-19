# 分配序列 v2：生成和上传步骤（给 Qingyang Li，10/20 下午）

接 `prelaunch-checklist.md` 第 G 节。依据：dev-tasks-1020 第 C 节、1020b 第一节 (7)、1020c 第四项。**开发只写步骤，不运行。**

产品窗口 `claude/序列v2生成流程-1020.md` 里标「[待开发确认]」的命令，**一律以本文件为准**。版本参数名是 `--version=v2`。

## 先说结论

- 10/21 起登记的 RCT- 参与者，从新的一套序列 **v2** 取组。旧的一套（v1，PB-01 至 PB-04 用过）原地停用，一个字都不改。
- v2 由 Qingyang 一个人在自己的电脑上生成和上传，用自己的 App 登录。Junyu 不生成、不看序列，上传时不在场看屏幕。
- 四件事一定要做到：
  1. 命令里写 `--version=v2`；
  2. **用一个新的种子**，不能用 v1 的；
  3. 每层不少于 80 个位置（`--length=80`，现在也是默认值）；
  4. Junyu 事前给角色、打开上传开关，上传后关掉。

## 一、Junyu 事前做（Qingyang 上传之前）

| # | 做什么 | 怎么做 |
|---|---|---|
| 1 | #127 合并、部署 | 合并 #127 后，从 main 部署 Functions 和规则：`firebase deploy --only functions,firestore:rules`。上传检查（v2、≥80、拒同一种子）在服务器上，没部署就没有这些检查 |
| 2 | 给 Qingyang 的 App 账号发上传角色 | 和以前发角色一样，先 `export GOOGLE_APPLICATION_CREDENTIALS=<服务账号文件>`（这个工具不用项目参数，按服务账号连正式项目）。① 收回 v1 上传人的角色：`NODE_PATH=functions/node_modules node tool/provision_researcher.js --email=<Calvin 的 App 登录电邮> --revoke`；② 发给 Qingyang：`NODE_PATH=functions/node_modules node tool/provision_researcher.js --email=<Qingyang 的 App 登录电邮> --role=sequence_uploader`；③ 核对：`NODE_PATH=functions/node_modules node tool/provision_researcher.js --list`，只有 Qingyang 是 `sequence_uploader` |
| 3 | 打开上传开关 | Firebase 控制台 → Firestore → `meta/randomization_config` → 字段 `sequenceUploadEnabled` 设为**布尔** `true`（不是字符串）。然后离开，不看 Qingyang 的屏幕 |

## 二、Qingyang 做（在自己的电脑上）

| # | 做什么 | 怎么做 |
|---|---|---|
| 1 | 准备仓库 | 取最新 main（含 #127）。在仓库根目录：`cd functions && npm ci && cd ..` |
| 2 | **想一个新的种子** | 至少 16 个字符，**不能是 v1 用过的那个**（也不要只改一两个字）。写进一个只有自己能读的文本文件，例如 `$HOME/seed-v2.txt` |
| 3 | 生成 | `NODE_PATH=functions/node_modules node tool/randomization_sequence.js --seed-file=$HOME/seed-v2.txt --length=80`。屏幕只显示两层（low、high）的长度和指纹（sha256），**不显示组别**。长度会是 80 到 83（按整组截止）。把两个指纹抄下来。生成的文件在 `randomization-private/`（不会进仓库） |
| 4 | 上传 | `NODE_PATH=functions/node_modules node tool/randomization_sequence.js --seed-file=$HOME/seed-v2.txt --length=80 --upload --version=v2 --email=<自己的 App 登录电邮> --password-file=<只有自己能读的密码文件> --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev`。登录用的 Web API key 自动从仓库里的 `android/app/google-services.json` 读，不用另给 |
| 5 | 看结果 | 成功：两行 `+ low: uploaded … sha256 …`、`+ high: …`，最后一行 `Done (v2)`。两个指纹要和第 3 步抄的一样 |
| 6 | 离线保存 | 把 `randomization-private/` 里的文件和种子文件交导师离线保存（例如加密 U 盘），记下两个指纹；然后从电脑上删掉这两个文件 |
| 7 | 告诉 Junyu 上传完了 | 只说「上传完成」和两个指纹，不说组别、不给文件 |

**上传被拒时（屏幕最后一行的代码）：**

| 代码 | 意思 | 怎么办 |
|---|---|---|
| `same_seed_as_v1` | 这个种子和 v1 的一样（生成出来的开头和 v1 相同） | 换一个全新的种子，从第 2 步重来 |
| `too_short` | 每层少于 80 个位置 | 加 `--length=80`，重新生成 |
| `version_required` | 没写 `--version=v2` | 加上再上传 |
| `disabled` | 上传开关没开 | 请 Junyu 把 `sequenceUploadEnabled` 设为布尔 `true` |
| `not_uploader` | 账号没有上传角色 | 请 Junyu 做第一节第 2 步 |
| `already_uploaded` | v2 已经传过 | 先问 Junyu。只有在**还没有任何 RCT- 登记**时，才可以加 `--replace` 重传 |
| `already_allocated` | v2 已经有人分配 | 不能再传。联系 Junyu |

## 三、上传之后

| # | 谁 | 做什么 |
|---|---|---|
| 1 | Junyu | 控制台把 `sequenceUploadEnabled` 改回布尔 `false` |
| 2 | Junyu | 10/21 第一位 RCT- 登记前，跑只读检查（和以前跑只读脚本一样，先 `export GOOGLE_APPLICATION_CREDENTIALS=<服务账号文件>`）：`NODE_PATH=functions/node_modules node tool/check_prelaunch_values.js --project=loneliness-pilot-dev --production-confirm=loneliness-pilot-dev`。**只看「randomization_sequences」那几行**：v2 low、v2 high 各 80 个位置以上、已用 0、指纹和 Qingyang 说的一样；`sequence_versions/v1：retired`、`sequence_versions/v2：active`。v1 那两行的已用数应该和之前一样（PB- 用过的位置不变） |
| 3 | Junyu | 手机上的「研究員登記」页输入一个 RCT- 测试编号，只按「檢查」，**不按確認登記**（确认会用掉 v2 的真实位置） |

## 不要做的事

- 不要用 v1 的种子；不要把种子、生成的文件或屏幕给别人看。
- 不要在控制台打开 `randomization_sequences`、`randomization_state`（打开会留下访问记录，也会看到组别）。
- 不要改 v1 的任何文档。
