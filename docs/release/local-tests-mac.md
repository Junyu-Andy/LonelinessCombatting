# 在 Mac 上跑全部测试（和 CI 同一套）

> 2026-10-20 第一版（1020i 第一节）。
> 2026-10-20 1020j：Windows 电脑见 `local-tests-windows.md`（同一个脚本，在 Git Bash 里跑）；装 iPad 和安卓手机见 `dev-install-devices.md`。

## 结论

- 在仓库根目录跑**一行**：

  ```bash
  bash tool/run_local_tests_mac.sh
  ```

- 跑的内容和 GitHub 上的 CI 一样：
  1. `flutter analyze`；
  2. 小讀本 HTML 检查；
  3. 六套 Flutter 测试，清单就是 CI 用的 `tool/ci_flutter_tests.sh`；
  4. Functions 单元测试；
  5. Firestore 规则测试和 Functions 模拟器测试；
  6. 隐私脚本测试（删除参与者、共享同意、清测试员）。
- **只连本机模拟器，只用测试里造的数据。** 脚本一开头会检查环境变量，发现指向正式项目就停下，不跑。
- 每一步打印「通过」或「失败」。某一步失败，后面的步骤照跑。最后打印汇总和总用时。
- 全部跑完大约 **15–25 分钟**（10/20 在云端试跑一次，12 分钟）。第一次多几分钟，要下载依赖和模拟器。

## 一、第一次准备（只做一次）

先打开「终端」（Terminal）。下面每个工具都先用「检查」那一行看看有没有装好。显示的版本对，就跳过「安装」。

| 工具 | 要的版本 | 检查 | 安装 |
|---|---|---|---|
| Homebrew | 任何版本 | `brew --version` | 见 <https://brew.sh> 首页那一行 |
| Flutter | **3.35.3**（和 CI 一样，见下面说明） | `flutter --version` | 见下面「装 Flutter 3.35.3」 |
| Node | **24**（`v24.x`） | `node -v` | `brew install nvm`，然后 `nvm install 24 && nvm use 24` |
| Java | **21 或更新**（模拟器要用） | `java -version` | `brew install --cask temurin@21` |
| firebase-tools | 最新版（和 CI 一样）；这边试跑用的是 15.34.0 | `firebase --version` | `npm install -g firebase-tools` |

说明：

- **Flutter 必须是 3.35.3。** 版本不同，`flutter analyze` 的条数和部分测试结果会不一样（CLAUDE.md：Gradle 8.12 不支持更新的 Flutter）。
- **装 Flutter 3.35.3**（已经有别的版本也可以这样另装一份）：

  ```bash
  git clone https://github.com/flutter/flutter.git -b 3.35.3 ~/dev/flutter
  echo 'export PATH="$HOME/dev/flutter/bin:$PATH"' >> ~/.zshrc
  ```

  关掉终端再开一个新的。跑 `flutter --version`，第一行应该是 `Flutter 3.35.3`。
- **Node**：之前按 `docs/release/phase_a_deploy_workflow_mac.md` 第 0.2 步装过 nvm 的，只要 `nvm use 24`。
- **Java**：装好后关掉终端再开一个新的，`java -version` 应该显示 `21`。装了几个版本、显示的不是 21，就先运行：

  ```bash
  export JAVA_HOME=$(/usr/libexec/java_home -v 21)
  ```

- 不需要 `firebase login`。模拟器不用登录。

## 二、跑测试

**用一个新开的终端窗口。** 跑过只读脚本（例如 `list_pilot99.js`）的那个窗口设了正式项目的钥匙，测试脚本会拒绝在那里跑。

```bash
cd ~/dev/LonelinessCombatting
git checkout main
git pull
bash tool/run_local_tests_mac.sh
```

想测某个 PR 的分支，把第二、三行换成：

```bash
git fetch origin
git checkout <分支名>
git pull
```

### 只跑一部分

在命令后面加 `--only` 和组名。几个组用逗号隔开，中间不要空格。

| 组名 | 跑什么 | 大约多久 |
|---|---|---|
| `analyze` | `flutter analyze` 和小讀本 HTML 检查 | 1 分钟 |
| `flutter` | 六套 Flutter 测试 | 7–15 分钟 |
| `functions` | Functions 单元测试 | 1 分钟 |
| `rules`（也可以写 `emulator`） | Firestore 规则测试 + Functions 模拟器测试，自动起停模拟器 | 4–6 分钟 |
| `privacy` | 隐私脚本测试，自动起停模拟器 | 1 分钟 |

例子：

```bash
bash tool/run_local_tests_mac.sh --only flutter
bash tool/run_local_tests_mac.sh --only rules,functions
bash tool/run_local_tests_mac.sh --help      # 看用法
```

## 三、结果怎么看

最后一段是汇总，像这样：

```
================= 汇总 =================
✓ 通过  准备：flutter pub get（0 分 05 秒）
✓ 通过  flutter analyze（0 分 11 秒） —— 共 93 条提示，其中 error 0 条
✓ 通过  小讀本 HTML 检查（0 分 00 秒）
✓ 通过  Flutter 测试（6 套，和 CI 同一份清单）（6 分 45 秒）
✓ 通过  准备：安装 Functions 依赖（npm ci）（0 分 06 秒）
✓ 通过  Functions 单元测试（0 分 03 秒）
✓ 通过  准备：安装规则测试依赖（0 分 08 秒）
✓ 通过  Firestore 规则测试 + Functions 模拟器测试（自动起停模拟器）（4 分 11 秒）
✓ 通过  隐私脚本测试（删除参与者、共享同意、清测试员）（0 分 32 秒）
----------------------------------------
总用时 12 分 01 秒。日志：build/local-tests/20261020-065950/
全部通过。
```

- 全部是 ✓，最后一行是「全部通过。」：和 CI 绿灯一样。
- 有 ✗ 的：把汇总这一段，和 `build/local-tests/<时间>/` 里对应的日志文件，一起发给开发窗口。
  - Flutter 那一步会列出是哪一套失败。
  - Functions 那一步会列出是哪个文件失败，例如「—— 失败的文件：test/xxx_test.js」。
  - 规则和模拟器那一步会分开写「Firestore 规则测试」和「Functions 模拟器测试」各自的结果。
- `flutter analyze` 只在有 error 时算失败，和 CI 一样。汇总里写着共几条提示；info 和 warning 是原有的（10/20 是 93 条），不算失败。条数比 CI 多，说明本机版本和 CI 不同，或者有新改动。
- 日志在 `build/` 下面，不会进 git。

## 四、常见报错

### 1. 「✗ 停止：设了正式项目的钥匙 GOOGLE_APPLICATION_CREDENTIALS=…」

这个终端设过正式项目的钥匙（跑只读脚本时设的）。二选一：

- 关掉这个终端，开一个新的再跑；或者
- 在这个终端里先运行：

  ```bash
  unset GOOGLE_APPLICATION_CREDENTIALS
  ```

提示里写的是别的变量（`GCLOUD_PROJECT`、`FIRESTORE_EMULATOR_HOST` 等），就照提示 `unset` 那个变量。

### 2. 「端口被占用：8080（进程 1234：java）」

上一次的模拟器没关掉，或者别的程序占了这个端口。

1. 看是谁占的（把 8080 换成提示里的端口）：

   ```bash
   lsof -nP -iTCP:8080 -sTCP:LISTEN
   ```

2. 是 `java`（多半是上次没关的模拟器），或者你认得、可以关的程序，就关掉它（把 1234 换成提示里的进程号）：

   ```bash
   kill 1234
   ```

3. 再跑一次。不确定那是什么程序，就重启电脑再跑。

模拟器用的端口：8080、9099、9199、4400、4500、9150。

### 3. 「模拟器要 Java 21 或更新，现在是：没有 Java」

Java 没装，或者版本太旧。按第一节装 Java 21，**开一个新终端**再跑。装了还是显示旧版本，就先运行 `export JAVA_HOME=$(/usr/libexec/java_home -v 21)`。

Mac 可能弹出「要安装 Java 吗」的窗口。点「取消」，用上面的 `brew` 命令装。

### 4. 模拟器没起来

汇总里写「Functions 模拟器测试没有跑（模拟器没起来，看日志）」，或者规则那一步很快就失败。

打开 `build/local-tests/<时间>/rules_emulator.log`（隐私那一步看 `privacy.log`）看开头几行：

| 日志里看到 | 怎么办 |
|---|---|
| `port taken`、`Could not start` | 照第 2 条处理端口 |
| `java`、`JAVA_HOME` | 照第 3 条处理 Java |
| `Download failed`、`ENOTFOUND` | 第一次要下载模拟器，检查网络后重跑 |
| `command not found: firebase` | `npm install -g firebase-tools` |

Mac 弹出「是否允许 java 接受传入网络连接」：点「允许」或「拒绝」都可以。模拟器只用本机。

### 5. 「⚠ CI 用 Flutter 3.35.3，你的版本不同」或「⚠ CI 用 Node 24」

只是提醒，测试照跑，但结果可能和 CI 不一样。按第一节换成对的版本再跑一次。Node 用 `nvm use 24` 切换。

### 6. 「准备：安装 Functions 依赖（npm ci）」失败

多半是网络问题，重跑就好。还是失败，把 `npm_functions.log` 发给开发窗口。

## 五、安全

- **只连本机模拟器。** 脚本开头检查这些环境变量，任何一个指向正式项目就停：
  - `GOOGLE_APPLICATION_CREDENTIALS`、`GCLOUD_PROJECT`、`GOOGLE_CLOUD_PROJECT`、`FIREBASE_CONFIG`；
  - `FIRESTORE_EMULATOR_HOST`、`FIREBASE_AUTH_EMULATOR_HOST`、`FIREBASE_STORAGE_EMULATOR_HOST` 不是本机地址。
- 测试运行时还把 `gcloud` 的登录信息挡住，测试程序找不到任何正式项目的钥匙。
- 命令里的项目名 `loneliness-pilot-dev` 只是模拟器里的名字，和 CI 一样。数据全部是测试自己造的，跑完随模拟器一起清掉。
- 不碰序列、`randomization_state` 和分配日志。
- Flutter 会改 `analysis_options.yaml` 和 `pubspec.lock`。跑之前这两个文件没改过的话，脚本跑完会还原它们。
