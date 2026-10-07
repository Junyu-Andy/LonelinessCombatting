# 0019：Phase B 关闭"搜一搜"和语音输入，用服务器能读的配置开关控制，默认关

- 日期：2026-10-07
- 状态：已采纳
- 影响范围：所有 cohort × 两组（搜一搜本来只有 Hybrid 组有；语音两组都有）
- 相关代码：`app_config/feature_flags`；`functions/feature_flags.js`；`lib/core/feature_flags/remote_feature_flags.dart`；PR 草稿（分支 `chore/phaseB-flags`）

## 背景

研究侧已定 Phase B 先关闭这两项（登记表 C18）。现状：

- 搜一搜：App 里写死关闭（`_searchEnabled = false`），但服务器 `webSearch` 照样能用，只拦规则组。万一以后打开，原话会在安全检测之前发给 Brave。
- 语音：两组都开着，没有开关，用手机系统识别，可能走云端。服务器 `transcribeAudio` 没人调用，也没有开关。
- 语音很重要：STT 修订获 HREC 批准后要重新打开。所以要能不发新版就打开。

## 决定

1. 新建一份 Firestore 配置 `app_config/feature_flags`。App 和服务器读同一份。字段值必须正好是 `true` 才算开；没有这份文档、没有字段、读取失败，一律算关。
2. 三个开关：

| 开关 | 默认 | 关的时候 |
|---|---|---|
| `webSearchEnabled` | 关 | App 不显示"幫我查"按钮，不发请求；服务器 `webSearch` 直接拒绝（`failed-precondition`），不连 Brave。规则组即使开了也没有按钮，服务器也照旧拒绝 |
| `voiceInputEnabled` | 关 | 所有页面的麦克风按钮都不显示，也不碰系统语音识别（不弹权限、不收音）；服务器 `transcribeAudio` 直接拒绝。代码保留 |
| `searchOffReplyEnabled` | 关 | 不启用下面的固定回应 |

3. 固定回应：`searchOffReplyEnabled` 开、`webSearchEnabled` 关时，老人在通通里问需要上网查的问题（关键词表，见 `tung_tung_search_intent.dart`），通通回一句固定的话。两组条件相同：
   - 先过安全词库；**只要命中任何安全等级，就照原来的安全流程走**，不出这句；
   - Hybrid 组：这一轮不调用 AI，`turns` 记 `llmStatus: fixed_reply`；
   - 规则组：这句代替话题模板，`turns` 仍记 `rule_based`；
   - 文章问答模式不触发。
   这句现在是占位文字，研究侧定稿前开关保持关。
4. 通通的 prompt 出新版 `functions/prompts/tung_tung.v2.txt`（负责人 2026-10-07 决定，需 PI 审核）：去掉"要唔要我幫你查下""一齊查下"的邀请；不确定就老实说，不编日期、价钱、地址，可以建议问家人或社工。`[SEARCH_RESULTS]` 规则保留，写明没有结果时怎么回应。只改第 4、5 点和首行版本号，其余一字不动。旧文件 `tung_tung_v1.txt` 保留。App 仍发 `tung_tung_v1`，服务器按注册表（`functions/index.js` 的 `PROMPT_FILES`）加载 v2，`promptVersion` 变为 `tung_tung_v2@2026-10`。
5. 开关放在 Firestore 而不是编译开关：HREC 批准后，研究侧在控制台改一个字段就能打开语音，不用重新发版。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| 用 `--dart-define` 编译开关 | 服务器读不到；重新打开语音要重新发版、老人要更新 |
| 放进现有的 `app_config/phase_a` | 那份是 Phase A 的运行参数，混在一起容易误改；服务器那边的读取也带默认值合并，不适合"缺省即关" |
| 固定回应交给 AI 按 prompt 说 | 说法不固定，两组不一致；要改 agent prompt，需另走 PI 审核 |
| 删除语音代码 | 研究侧要求保留，HREC 批准后重开 |

## 后果

- 对研究：
  - Phase B 两组都没有语音输入、Hybrid 组没有搜一搜。protocol、ICF 里如果写了这两项，要说明 Phase B 初期关闭。
  - 手机键盘自带的语音输入（Gboard 麦克风、iPhone 键盘的听写）不经过 App，App 关不掉。ICF 要不要提，由研究侧定。
  - 通通 prompt v1 原来邀请"要唔要我幫你查下？"，但搜索关着，老人答"要"也没有下文。v2 去掉了这句。v2 生效后，Hybrid 组通通的回复会变（不再邀请上网查），要写进 changelog。
  - 固定回应开了以后，Hybrid 组遇到这类问题不调用 AI，两组在这一点上一样。
- 对开发：上线前不用建这份文档（缺省即关）。重新打开时，在控制台写 `app_config/feature_flags`，字段设为布尔值 `true`。App 只在启动时读一次，老人要重开 App 才生效；服务器每次调用都读，立刻生效。
- 对论文：Methods 写明 Phase B 没有语音输入和网络搜索；如果中途打开语音，要写明生效日期和影响的组别。
