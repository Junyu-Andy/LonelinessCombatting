# Phase A 基线版 — 全项目复核（2026-09-17）

对照：《开发变更规格 v1》（2026-09-11）、《开发对齐 checklist》（2026-09-17）、仓库 HEAD。
分三类：**已在本轮修掉**、**与规格不匹配但需要你/PI 决定**、**可优化但不建议基线前动**。

## 0. 结论

规格 19 项里 17 项在代码里可核实为「已实现且与规格一致」；2 项（M-5 intake 12 题、M-4 DJG-ES 题目）缺 Questionnaire v1.3 无法对齐。checklist B「当前状态核实」六条现在都有明确答案（见 §2）。E 红线里开发侧能做的（T-1/T-4/T-6 逻辑、V-1 hash）已就绪，其余四条是 PI 侧（HREC、号码、S-7 签字、真机走通）。

## 1. 本轮复核发现并已修掉的（commit 见 git log）

| # | 发现 | 处理 |
|---|---|---|
| 1 | M-3 规定 Siu Yan 的 `[Recent mood snippet]` 从每日心情取，但只有 check-in 页会更新 shared context；首页心情垫和新加的每日提示记了 `daily_mood` 却不更新 snippet，Siu Yan 看不到 | 两处补 `updateRecentMood` |
| 2 | M-7「10 分钟无用户消息」：原 idle 计时器在 app 退到后台时暂停、回前台从零重来，后台放一小时 session 也不结束 | 回前台时若离开时长 ≥ 超时即结束 session |
| 3 | L-1 事件 `screen_view(screen, dwellMs)`、`agent_switch(from,to)`、`weekly_pr_pushed` 三个名字没有按规格发出（用了既有近似事件） | 三个都补成规格名 |
| 4 | 每周分析盲导出（`blindedDataExport`）不包含新集合 `turns / sessions / brief_pr / weekly_pr / pgic / djg_es / agent_diff / daily_mood / response_feedback` | 加入导出白名单 |
| 5 | 规格 §5 不动清单：用程序比对基线 `c80a2ab` 与当前词表 | acute 160 条、low 42 条逐字一致；moderate 67 条集合一致，interrupt 内保持 v4 顺序。通过 |

## 2. checklist B 六条的明确答案

| 问题 | 答案 | 证据 |
|---|---|---|
| moderate 时 LLM 调不调用 | **调用**，两类都调；基线前代码就是调用的，只是 JSON 注释写反了，已改注释 | `llm_gateway.dart`：只有 acute short-circuit；`llm_gateway_test.dart` 有断言 |
| theme / module_id 怎么送 | 基线前：theme 以 themeLock 段进 suffix 开头（仅回忆页）；**module_id 从未进模型**。现：网关在 suffix 末尾追加 `[今週主題]`（有 theme 时）+ `[模組]`（所有 agent 调用） | `phase_a_gateway_test.dart`；测试对话需真机（T-17） |
| 五旗 / referral / te 怎么产生 | 五旗 = CF 正则（确定性，非模型自报）；referral = 转介卡实际弹出（可靠）∪ 回复文本正则（辅助）；te = 客户端命中 + 卡片全文 | 回传报告 §5 |
| stripPII 剥哪些、作用于摘要/实体吗 | 电话 / email / HKID / 西式楼层；**不剥姓名、中文数字、中文地址**。出站到 DeepSeek 的 messages、contextSuffix（含 rolling summary、named entities）、referralJudgement 都剥；**Firestore 存储不剥** | `docs/privacy/strip_pii.md` |
| M-1～M-6 哪些做了 | M-1/2/3/4/6 做了；**M-5 intake 12 题没做**（无 v1.3） | 本文 §3 |
| 语音模态和时长记了吗 | 记了：`input.modality` + `input.voiceDurationMs`（听写 start→stop 累计） | `voice_input_button.dart` `takeModality()` |

## 3. 与规格/文件不匹配、需要你或 PI 决定的

1. **M-5 Onboarding intake 12 题**：仓库只有 6 部分旧 intake（Part 1–6，约 18 个界面元素），没有 v1.3 Annex，不能替你编题。interests 现在来自「agent onboarding」页的兴趣 chips + intake Part 4 的 topics（`IntakeMemorySeeder` 合并），功能上满足「通通从 intake 取」，但题目本身待换。→ 需要 v1.3 文件。
2. **M-4 DJG-ES 题目**：用的是公开 6 题短表的粤语工作稿。→ 需要 v1.3 文本；替换只改 `djg_es_response.dart` 的字符串。
3. **M-1 Brief PR 四个 stem**：沿用现有 stem（明白我 / 尊重我 / 關心我 / 搞錯重點）。checklist A 说「以 v1.3 为准」。→ 同上。
4. **L-1 `turns.theme`「Ah Jan 必须有 theme」**：反思对话页（同一 Ah Jan prompt，但产品定义为无主题锁）theme 为 null。→ 建议接受 null 表示「无主题会话」，或者你定一个固定值如 `open`。
5. **L-3 `te.offerText` 与转录同意**：提议句原样包含参与者那句话（例「打畀阿女只會煩到佢」），**不受 per-agent 转录保留开关约束**（规格要求 100% 审计）。既有的 `thought_exercise` 集合本来也存原文。→ 请 PI 确认 HREC 表述覆盖这一点。
6. **L-2 promptBundleHash 定义**：规格写「三份 prompt + suffix 模板 + acknowledgements.json」；实现多包了 `crisis_resources.json` 和 `llm_fallback_messages.json`（都是参与者可见的安全文案，V-1 表也列了 fallback）。→ 建议接受这个更宽的定义，并在 Manual 写明。
7. **M-2 推送时间 config**：客户端窗口读 `weeklyPrPushHour`，但 CF 的 cron 是写死的周日 20:00（`onSchedule` 无法读运行时配置）。改推送时间 = 改 `functions/index.js` 一行 + 重部署。→ 接受即可，写进 Manual。
8. **S-1 表里 low → pill**：pill 早在基线前就被产品决定全局隐藏（`safety_overlay.dart` 注释），low 现在只更新状态不显示任何东西。→ 与规格「pill（不变）」字面一致（确实没变），但要知道参与者看不到 pill。
9. **`notification_received`**：只能记前台收到；app 在后台/被杀时 FCM 不唤醒 app（未注册 background handler），这类事件缺失。`notification_opened` 不受影响。→ 接受，或 Phase B 加 background handler。
10. **iOS APNs 未配置**（既有）：W2 逐设备推送在 iOS 收不到；周日/每日 doorbell 同样。→ 若参与者用 iPad，推送在 Phase A 等于不存在，只剩首页横幅。这是 checklist E「Weekly PR 真机走通」要注意的前提。
11. **S-4 号码**：仍未核对（见部署手册 §8）。
12. **Arm 开关**：`arm_scope.dart` 把所有人强制为 Arm A（注释写明 Phase A stub，Phase B 前撤）。与规格「Rule-based 臂模板不在本版范围」一致，但要写进 Manual，免得以为在跑随机化。

## 4. 可优化但不建议基线前动（Phase A 冻结后再说）

1. 四个聊天页各自复制了约 80 行 recorder 接线（ARCHITECTURE_NOTES #1 的老问题加重了）。抽 `ChatSessionController` 是正确方向，但改动面大，不宜在冻结前做。
2. `LlmTurnFeatures`（B.1 旧集合）与 `turns.flags` 现在存两份同样的五旗。保留是为了旧 dashboard；Phase B 可以只留 `turns`。
3. `PprBriefPage`（旧 2 题 PPR）只剩测试工具入口引用，可删。`logDistressDetected` 无人调用，可删。
4. `flutter analyze` 有 80 余条基线遗留 info/warning（未用 import、`dangling_library_doc_comments` 等），零 error；清一次很快但会污染冻结 diff。
5. `Week1NudgeBanner`、`referentForRatedWeek` 各自读整个 `sessions` 子集合；pilot 规模无所谓，参与者上百后要加 `limit` 或按周分桶。
6. stripPII 的地址规则基本无效、不剥姓名（有意）；若 HREC 对「地址」有硬要求，需要换方案，不是加几条正则能解决的。

## 5. 对 checklist D 日期的建议

- 「开发回传 C 项」：代码侧的 1/3/4/5/6/8 今天就能给（都在 `docs/release/` 与 `docs/privacy/`）；2（T 截图）和 7（危机页截图）取决于你什么时候跑真机。
- 「版本冻结」前必须做的开发动作只剩两件：填 `verifiedDate` 后重跑 `tool/export_spec_inputs.py`；在冻结 commit 打 tag。
