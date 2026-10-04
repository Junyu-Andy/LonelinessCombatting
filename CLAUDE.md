# CLAUDE.md

陪住：香港长者粤语陪伴 App（Flutter + Firebase + DeepSeek），Phase B 是 Hybrid 组 vs 规则组的随机对照试验。先读 `docs/dev/architecture.md`。

## 文档规则
- 任何改动只要涉及 prompt、记忆、分组、界面或推送，同一个 PR 里必须更新 docs/STUDY_CHANGELOG.md。
- 设计层面的决定先在 docs/decisions/ 写决策记录（模板：docs/decisions/0000-template.md），再改代码。
- 已有的决策记录不修改；要推翻就新写一份，并在旧的那份里标 Superseded。
- prompt 一律放在 functions/prompts/<name>.v<N>.txt；改内容就新建一个版本文件，不覆盖旧文件。（现有的 `<name>_v1.txt` 按 docs/dev/memory-and-entry-spec.md 3.10 迁移。）
- 已打 phaseB-* tag 之后，行为上的改动要在 changelog 里写明影响的 cohort/组别和生效日期。
- 代码行为变了，同一个 PR 里更新 docs/dev/architecture.md；合并或做出决定后在 docs/history.md 加一段；待办的增减更新 docs/dev/backlog.md。
- 文档用简体中文，写给非开发背景的负责人看：先说结论，短句，少术语。

## 开发须知
- Flutter 固定 3.35.3（Gradle 8.12 不支持更新的 Flutter）。
- 测试：`tool/ci_flutter_tests.sh`（四套构建变体）和 `tool/ci_backend_tests.sh`（Functions + Firestore 规则，需要模拟器）。
- Flutter 工具会改 `analysis_options.yaml` 和 `pubspec.lock`，提交前 `git checkout` 这两个文件。
- `functions/` 的 ESLint 是 ES2018：不能用 `??`、`?.`。
- 规则组（Arm B）永远不能调用 LLM；服务器上也有一道防线，不要绕过。
- 安全检测（`lib/core/safety/`）两组必须完全一致。
- 所有改动走 PR 合进 `main`，不直接推 `main`。
