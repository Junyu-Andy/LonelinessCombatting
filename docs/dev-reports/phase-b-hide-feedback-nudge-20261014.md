# Phase B 包隐藏点赞点踩和第一周提示（2026-10-14，编号待开发窗口分配；SPEC:C14、C21）

分支 `fix/phase-b-hide-feedback-nudge`，从 main `e851205`（已含 T21）开。依据：负责人 10/14 核对 W0 流程时发现的两个问题和口头决定"先关掉，保主干"。只改 App，不改规则、不改 Functions，没有连生产 Firestore。

## 结论

1. `PHASE_B=true` 的包里，两组都看不到：① 聊天回复旁的「幫到我／冇咁幫到」点赞点踩；② 首页第一周提示「你仲未同 X 傾過，想試下嗎？」。
2. 两处都能用控制台恢复：`app_config/feature_flags.replyFeedbackEnabled` / `week1NudgeEnabled` 设为布尔 `true`（文档不存在或任何别的值 = 隐藏）。老人要重开 App 才生效（开关在启动时读一次）。
3. Phase A 包（不带 `PHASE_B`）行为不变。
4. 没有新的老人看得到的文字。

## 一、问题核对（main `e851205`）

| 问题 | 核对结果 | 位置 |
|---|---|---|
| 点赞点踩两组不对等 | 属实。`ThumbsFeedback` 用在 Hybrid 组的签到、回忆、反思对话页，以及两组都有的通通页和文章页；规则组签到 B、回忆 B 没有 | `lib/features/response_feedback/presentation/widgets/thumbs_feedback.dart`；调用处 `check_in_arm_a.dart` 1003 行、`reminiscence_arm_a_page.dart` 869 行、`reflective_dialogue_page.dart` 566 行、`tung_tung_page.dart` 801 行、`education_article_page.dart` 193 行 |
| 第一周提示没按 Phase B 关 | 属实。只读 `PhaseAConfig.week1NudgeDays`（默认第 3、6 天，按账号创建日算），没有按研究期或构建判断；首页在所有构建都挂了这个横幅。不是推送，是首页一行可关掉的提示，每天最多一次，记 `week1_nudge_shown` 事件 | `lib/features/today/presentation/widgets/week1_nudge_banner.dart`；`today_page.dart` |

`dev-tasks-1009b.md`"这批不要做"里写过"单条回复反馈（Phase B 不做）"，登记表 C14 只有 Brief PR，所以点赞点踩在 Phase B 两组都隐藏，而不是给规则组补上。

## 二、改了什么

| 文件 | 改动 |
|---|---|
| `lib/core/feature_flags/remote_feature_flags.dart` | 加两个开关 `replyFeedbackEnabled`、`week1NudgeEnabled`（只认布尔 `true`），和两个判断 `hideReplyFeedback`、`hideWeek1Nudge`（= 是 Phase B 包且开关没开） |
| `lib/features/response_feedback/presentation/widgets/thumbs_feedback.dart` | `build` 开头：要隐藏就不渲染（五个调用处不用改） |
| `lib/features/today/presentation/widgets/week1_nudge_banner.dart` | `_resolve` 和 `build` 开头：要隐藏就不查会话、不记事件、不渲染 |
| `tool/ci_flutter_tests.sh` | Phase B 那套加新测试文件 |
| `test/phase_b_hidden_surfaces_test.dart`（新） | 见第三节 |
| 文档 | `STUDY_CHANGELOG.md` 一行；`architecture.md` 第 12 节开关表两行；`history.md`；`backlog.md` 第 97、98 项 |

## 三、测试

| 测试 | 结果 |
|---|---|
| `flutter test test/phase_b_hidden_surfaces_test.dart`（默认构建） | 4 项通过：Phase A 包仍显示点赞点踩 |
| `flutter test --dart-define=PHASE_B=true test/phase_b_hidden_surfaces_test.dart test/phase_b_flags_test.dart` | 通过：Phase B 包默认不渲染点赞点踩；开关 `true` 时恢复；原有 Phase B 开关测试不受影响 |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | 0 error（88 条旧提示，同 main） |
| `tool/ci_flutter_tests.sh`、`tool/ci_backend_tests.sh` | 由 GitHub CI 跑（本分支只改 App，后端不变） |

第一周提示的隐藏只测了判断函数（横幅本身要 Firestore 才能渲染），逻辑和点赞点踩同一个开关模式。

## 四、和其他 PR 的交叉

- T37（#63）也改 `remote_feature_flags.dart`（加 `onboardingAfterEnrollmentFix`）和四份文档：后合并的会在这几行有冲突，两边都留。
- T25、T34：只在文档上相邻。
- 合并后不需要部署规则或 Functions；需要重新打 Phase B 包才生效。

## 要 Junyu 定的事

1. 本改动的 T 号和要不要补决策记录（Phase B 不收单条回复反馈，属登记表 C14/C21 的补充）。
2. 「安靜時段」「語音讀出內容」怎样处理（backlog 97）：接功能还是隐藏；W0 先不介绍。

## 要带回研究侧的发现

1. 登记表应补写：Phase B 两组都没有单条回复反馈；第一周提示属 Phase A。
2. 第一周提示按**账号创建日**算第 3、6 天，不是按 W0 或登记日；如果以后要在 Phase B 用，要改成研究日。
