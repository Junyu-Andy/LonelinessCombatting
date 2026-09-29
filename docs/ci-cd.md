# CI/CD 使用说明

三个 GitHub Actions 工作流，都在 `.github/workflows/`。在 GitHub 仓库页面顶部的 **Actions** 标签页里可以看到它们。

| 工作流 | 什么时候跑 | 做什么 |
|---|---|---|
| **CI** (`ci.yml`) | 每次 push、每个 PR 自动跑 | Flutter 静态检查 + 四种构建模式的测试（Phase A、Phase B、B 组页面、记忆 v1）；Cloud Functions 测试 + Firestore 规则测试（在模拟器里跑） |
| **Build APK** (`build-apk.yml`) | 手动 | 为任意分支打一个可以装到安卓手机的 APK，可选 phase_a / phase_b / memory_v1 |
| **Deploy Firebase** (`deploy-firebase.yml`) | 手动，需要审批 | 先跑后端测试，再把 Firestore 规则和/或 Cloud Functions 部署到 `loneliness-pilot-dev` |

## 看测试结果

- 每个提交旁边、每个 PR 底部会有 ✓ 或 ✗，点进去可以看到哪一步失败。
- 本地也能跑同样的测试：`tool/ci_flutter_tests.sh` 和 `tool/ci_backend_tests.sh`。

**已知：** 在词库 v4 的问题决定之前，CI 的 Flutter 部分会是红的。原因是 4 条安全检测测试（「我想死」现在只判为 moderate）。这是真实存在的待决问题，所以没有跳过或屏蔽这些测试。

## 自己在手机上试

1. Actions → **Build APK** → **Run workflow**；
2. 选分支（例如 `claude/affectionate-newton-f8cgur`）和版本（例如 `phase_b`）；
3. 大约 10 分钟后，打开这次运行，在页面底部 **Artifacts** 下载 zip，解压得到 APK；
4. 传到安卓手机上安装（需要允许「安装未知来源应用」）。

注意：
- 这个 APK 连的是真实的 `loneliness-pilot-dev` 项目。请用测试账号，不要用参与者账号。
- `phase_b` 版本按账号注册时抽到的组别显示页面；组别一旦写入就不能再改。想看 B 组，需要一个被分到 B 组的测试账号（可以由管理员在 Firebase Console 里给新测试账号设置 `arm: "B"`）。
- 用 debug 密钥签名，只适合内部测试。上架商店仍然走 Codemagic（`codemagic.yaml`，iOS）。

## 部署的一次性设置

仓库 **Settings** 里做两件事：

1. **Secrets and variables → Actions → New repository secret**
   名称 `FIREBASE_SERVICE_ACCOUNT`，内容是一个 Google Cloud 服务账号的 JSON 密钥（在 Firebase Console → 项目设置 → 服务账号 生成，需要能部署规则和函数的权限）。
2. **Environments → New environment**，命名为 `production`，勾选 **Required reviewers** 并填上审批人。之后每次部署都要这个人点「批准」。

部署时还要在输入框里手动键入项目 id `loneliness-pilot-dev` 作为确认，防止误点。

**当前两个分支都还没有部署。** 规则改动（分组只能写一次、计数器修复）和 Cloud Functions 改动（B 组防线）要等你确认后再部署。
