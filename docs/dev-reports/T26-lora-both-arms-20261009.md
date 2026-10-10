# T26 LoRA 两组共用（2026-10-09，SPEC:C13；10/10 补 Phase A 和试跑）

> 分支 `feat/lora-both-arms-v2`。决策 0033（取代 0025 里"两组是否都用"的部分）。没有连生产 Firestore；测试只用合成句子和假模型。

## 10/10 补充：Phase A 和试跑也用（`dev-tasks-1010.md` 第三节 T26）

结论：**代码本来就不分研究期，没改功能代码；补了测试和文档。** Phase A、Phase B、试跑用同一个分类器、同一套安全流程、同两个开关。

1. **先把 main 合进本分支**（含 `dev-tasks-1010.md`、登记表 v7、陪伴者图片）。只有 `STUDY_CHANGELOG.md`、`history.md`、`backlog.md` 冲突，都是两边各加一行，两边都留。
2. **App 端不分研究期**：
   - 开关 `app_config/phase_a.safetyClassifierEnabled` 名字里有 phase_a，但它是全局配置：两种构建都在启动时读（`lib/main.dart` `PhaseAConfig.load`，不看 `FeatureFlags.phaseB`）。
   - 是否问分类器只看开关、有没有接分类器、输入点（`lib/core/safety/safety_check.dart` `classifierActiveFor`）；不读构建、组别、研究期。
   - Phase A 特有的输入也问分类器：ADA 自由作答（`lib/features/ada/presentation/ada_page.dart`，`adaFreeText`）、第 7 日开放题（`lib/features/ada/presentation/day7_open_page.dart`，`day7OpenEnded`），都走 `checkAndRoute`。
3. **服务器不分研究期**：`classifySafety`（`functions/index.js`）和 `functions/safety_classifier.js` 不读用户文档、组别或研究期；开关 `meta/safety_config.classifierEnabled` 只有一份。
4. **试跑**：研究期字段还没做（T21 未合并）。试跑参与者按选定版本走 Hybrid 或规则组的页面，安全检测和两组一样，所以也一样用分类器。
5. **新增测试**：
   - App：`test/safety_classifier_test.dart` 新组 `Phase A, Phase B and pilot`：开关打开时每个老人输入点都问分类器（Phase A 特有的两个也是）；ADA、第 7 日开放题和签到留言得到同样的级别和同样的安全事件。这个测试文件现在也在 `PHASE_B=true` 那套里跑（`tool/ci_flutter_tests.sh`），两种构建结果相同。
   - 服务器：`functions/test/safety_classifier_emulator_test.js` 新测试：Phase A、Phase B、试跑和规则组的合成账号（`users.cohort` 和 `enrollments.studyPeriod` 两种写法都放了）得到同样的答案、同样字段的记录，记录里没有组别和研究期。
6. **开关不变**：两个开关都默认关，没有新开关。
7. 决策 0033 还没合并，本次在同一份里补了第 7 条"两期和试跑也一样"，标题和影响范围跟着改；0025 没动。

### 给 T34（告警邮件）：`safety_events` 的分类器字段没有改名

T26 没有改 `safety_events` 的任何字段（`lib/core/safety/safety_event_writer.dart`）。判断"LoRA 是否参与判定"可用：
- `detector`：`classifier`（分类器把级别调高了）/ `both`（两边级别相同且已升级）/ `lexicon`（级别来自词库，包括分类器没回、出错或给得更低）；只在问过分类器时写（`lib/core/safety/safety_classifier.dart` `detectorLabel`）。
- `classifierStatus`（`ok` / `timeout` / `error` / `disabled` 等）、`classifierLevel`、`classifierScore`、`classifierVersion`：问过分类器才有。

（另：10/10 产品窗口第 10 条 Phase A 暂停，决策 0034 在 PR #55 草稿里。本 PR 写的"Phase A 也用"不影响：Phase A 恢复时照样同一套。）

### 两期不一样的地方（本次没改）

- **研究员电话代填的 ADA 和第 7 日开放题**（只有 Phase A 有）：文字在服务器上只查词库（`functions/ada.js` `lexicon.analyze`），不问分类器。老人自己填的那条路径会问。记 backlog 87。
- **T21 拆配置时**：`app_config/phase_a` 里的分类器开关和 `meta/safety_config` 不能拆成每期一份，否则可能一期开、一期关。记 backlog 88，T21 照做。

## 结论先说

1. **两组共用已写成决策 0033**，0025 顶部标了 Superseded，正文没改（`docs/decisions/0033-safety-classifier-both-arms.md`、`docs/decisions/0025-safety-classifier-slot-both-arms.md`）。
2. **只给级别和分数、只触发两组相同的安全流程**：T8 已经是这样，本次核对过，没有改服务器和规则（`functions/safety_classifier.js`、`lib/core/safety/safety_check.dart` `checkUserTextClassified`）。
3. **补了"对应消息编号"**：两条安全记录本来就有同一个编号，但消息记录 `turns` 里没有，对不上是哪条消息。现在 `turns` 加了 `safetyTurnId`，两组都写。
4. **开关仍默认关**，没有模型。上线清单加了 H 节（地址、鉴权、部署机器等）。
5. 发现一处分类器打开后会不一致的地方：通通 Hybrid 组"搜一搜关闭"固定回应不问分类器（第 4 节，backlog 85）。本次没改。

## 1. 开关（没有改，默认值照旧）

| 开关 | 位置 | 默认 |
|---|---|---|
| `safetyClassifierEnabled` | `app_config/phase_a`（`lib/core/config/phase_a_config.dart`） | **关** |
| `safetyClassifierTimeoutMs` | 同上 | 1500 |
| `classifierEnabled` | `meta/safety_config`（`functions/safety_config.js`） | **关** |
| `classifierUrl` / `classifierTimeoutMs` / `classifierMaxChars` | 同上 | 无 / 1200 / 1000 |
| `SAFETY_CLASSIFIER_TOKEN` | Functions 环境变量 | 无 |

两个总开关都开才生效。本次新增的 `turns.safetyTurnId` 不在开关后面：它只是把已有的编号多写一处，参与者感受不到；开关关着时也写（编号本来就生成）。

## 2. 记录字段核对（两组相同）

| 要记的 | `safety_classifier_calls`（服务器写，`functions/safety_classifier.js`） | `safety_events`（App 写，`lib/core/safety/safety_event_writer.dart`） | `users/{uid}/turns`（`lib/core/session/chat_session_recorder.dart`） |
|---|---|---|---|
| 风险等级 | `level`（已有） | `tier`（合并后）、`classifierLevel`（已有） | `detector.tier`（已有） |
| 分数 | `score`（已有） | `classifierScore`（已有） | — |
| 时间 | `ts`（已有） | `createdAt`（已有） | `ts.userSent`（已有） |
| 消息编号 | `turn_id`（已有） | `turnId`（已有） | **`safetyTurnId`（新增）** |

- 三处是同一个编号。Hybrid 组由 `LlmGateway.send` 生成（`lib/core/llm/llm_gateway.dart`），随 `LlmResponse.turnId` 写进 `turns`。
- 规则组：签到 B（`check_in_arm_b.dart`）、回忆 B（`reminiscence_arm_b_page.dart`）、通通 B（`tung_tung_page.dart`）现在由页面先生成编号，传给安全检测，再传给记录（`rule_submission_flow.dart` 新参数 `safetyTurnId`）。以前规则组的编号是检测里随手生成的，没有传出来。
- 表单页、入组开放题没有 `turns` 记录，编号只在两条安全记录里（和以前一样）。
- 两条安全记录不存原文、不存组别。`turns` 在盲法导出的 `HELD_BACK` 里（`functions/blinding.js`），新字段不会进盲法导出。没有碰 `blinding.js`。
- Firestore 规则不用改：`users/{uid}/turns` 是本人可写的通用规则（`firestore.rules` `match /users/{uid}/{collection}/{document=**}`）。

## 3. 测试

新增 3 个测试，在 `test/safety_classifier_test.dart` 的 `message id (both arms)` 组：

| 测试 | 结果 |
|---|---|
| Hybrid：网关的编号 = 分类器收到的编号 = 安全事件 `turnId` = `turns.safetyTurnId` | 通过 |
| 规则组：页面给的编号 = 分类器收到的 = 安全事件 = `turns.safetyTurnId` | 通过 |
| 开关关：`turns.safetyTurnId` 仍等于安全事件的编号 | 通过 |

T8 原有的两组一致测试（T6 的 20 句）不变，仍通过。

两套全量测试（推送前各跑一次）：`tool/ci_backend_tests.sh` 全部通过（"All backend tests passed"，含分类器模拟器测试 11/11、T7 14/14）；`tool/ci_flutter_tests.sh` 六套构建变体全部通过（默认构建 390 个）。

## 4. 分类器打开后仍会不一致的地方（本次没改）

- **通通 Hybrid 组"搜一搜关闭"的固定回应**（`lib/features/curious_companion/presentation/pages/tung_tung_page.dart`，`_isSearchOffQuestion` 那段）：老人问搜索类问题、词库没命中时，直接给固定句，只做词库检测，不问分类器，也不写安全记录编号。规则组（通通 B）同一句话会先走 `checkUserTextClassified`。这只在通通固定回应开关和分类器开关**都打开**时才出现。改法是固定句之前也走同一个检测；要改到页面流程，本次按"改动尽量少"不动，记 backlog 85。
- 决策 0025 留下的两个问题仍在：离线时规则组只有词库；误报会减少干预剂量（backlog 60）。

## 5. 上线清单

`docs/release/prelaunch-checklist.md` 新增 H 节 H1–H6：模型地址和返回格式、鉴权（Bearer 密钥或 Google 身份）、部署机器和地区、延迟和输入长度、DMP/ICF/HREC、打开开关和对编号。只加条目，没写核对人，没改分工。

## 6. 改动的文件

- App：`lib/core/session/chat_session_recorder.dart`、`lib/features/brief_pr/data/rule_submission_flow.dart`、`lib/features/context/presentation/pages/check_in_arm_b.dart`、`lib/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart`、`lib/features/curious_companion/presentation/pages/tung_tung_page.dart`。
- 测试：`test/safety_classifier_test.dart`。
- 文档：决策 0033（新）、0025（顶部一行）、`docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`、`docs/history.md`、`docs/dev/backlog.md`（58 改、84–86 新）、`docs/release/prelaunch-checklist.md`。
- 服务器、`firestore.rules`、`lib/core/safety/`：没改。

## 要带回研究侧的发现

（10/10 补充）

0. 两期和试跑现在就是同一个分类器、同一套流程，不用另外打开。两点要研究侧知道：① 研究员电话代填的 Phase A 问卷文字只查词库、不问分类器（研究员当时就在电话上），要不要也问（backlog 87）；② 开关只有一套，打开就是两期、试跑、两组同时打开。

（10/9 原有）

1. **接真实模型前要研究侧给**：地址、鉴权方式、部署机器和地区、返回格式（只给分数的话要切点）、实测延迟（上线清单 H1–H4，backlog 59）。
2. **DMP、ICF、HREC**：规则组的原话（去掉电话等）会发给分类器，要写明；HREC 是否修订（H5，backlog 58）。
3. **CLAUDE.md 那句"规则组永远不能调用 LLM"**：LoRA 分类器本身可能就是一个微调的语言模型。决策 0033 按"不生成文字、不是对话模型"处理，服务器防线没动。要不要把这句写清楚（backlog 86）。
4. **通通 Hybrid 组搜索类问题不问分类器**（第 4 节）：分类器打开前要改成两组一样（backlog 85）。
5. 离线不对等和误报的问题仍按 backlog 60 待定。
