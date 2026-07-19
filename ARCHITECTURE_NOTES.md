# Architecture Notes — 评估与 pilot 后重构建议

> 结论先行：**架构整体是健康的**（feature-first 分层、core 服务注入、LLM 统一走 gateway、
> 安全检测集中在 DistressDetector），pilot 前不需要也不应该重构。
> 以下问题按「pilot 后处理」排序，都是会持续产生 bug 的结构性根源。

## 1. 聊天页脚手架五处复制（最高优先）
`tung_tung` / `reflective_dialogue` / `reminiscence_arm_a` / `check_in_arm_a` /
`education_article` 各自复制了 `_Composer`、`_send`、`_Turn`、busy 状态机、
Brief PR 退出钩子。B03（语音竞态）、busy 卡死、Brief PR pop 竞态——同一个 bug
要修五遍，就是这个结构造成的。
**建议**：抽 `shared/chat/` 的 `ChatComposer` + `ChatSessionController`
（持有 turns/busy/voice/send 管线，页面只注入 persona 与 moduleId）。

## 2. Analytics 事件名漂移
同一动作两个名字（`check_in_submitted` vs `m2_check_in_submitted`，B04 根因）；
`weekly_pr_trigger` 的会话开始事件集合里甚至同时列了 `m3_session_started` 和
`m3_session_start` 两种拼写。
**建议**：建 `analytics_events.dart` 常量表，全库禁止裸字符串事件名；
写一个 contract test 断言读写两侧引用同一常量。

## 3. Firestore 访问路径不统一
一部分走 repository（action_plan、mood_recorder），一部分在 widget 里直接
`FirebaseFirestore.instance`（facts_recap、weekly_pr_page、researcher_dashboard、
check_in_arm_b 的新写入也暂时如此）。查询形态（是否需要索引）因此散落各处失控——
这次「缺复合索引」问题就是这么漏出去的。
**建议**：全部下沉到 `data/` 仓库层；CI 里 grep 禁止 presentation 层 import
cloud_firestore。

## 4. 离线写库策略（本轮已统一，需固化为规范）
规则：**UI 永远乐观放行；Firestore 写一律 fire-and-forget（SDK 离线队列负责补发）；
绝不在用户和下一步之间 await 一个网络写**。本轮已把 consent/intake/checkin/
weekly_pr/ppr/safety 全改成这个模式。
**建议**：写进 CONTRIBUTING，新代码 review 按这条卡。

## 5. Profile 内存态与 Firestore 脱钩
`profileChanges()` 只在登录/登出时发射；运行期改 profile 要手动同步
`settings.profile`（今日休息、PPR firstSeen 都各补了一次）。漏一处就是一个
「重启才生效」bug。
**建议**：改成对 `users/{uid}` 挂 snapshot listener，单一数据流。

## 6. 三份 ISO 周实现
`weekly_pr_response`（正确）/ `pgic_response`（本轮修好）/ `loneliness_probe`
（第三种）。**建议**：抽 `core/time/iso_week.dart`，一处实现 + 单测。

## 7. 静默吞错
全库大量 `catch (_) {}`，问题只能靠用户口头报。**建议**：pilot 后接一个轻量错误
上报（Crashlytics 或写 `users/{uid}/client_errors`），catch 处统一走它。

## 8. 遗留的 Phase 开关（上线前必须核对）
- `arm_scope.dart` 硬编码所有人 Arm A（Phase A stub，注释里自己写了要撤）。
- `logM2CheckInSubmitted` helper 已无人调用（logCheckIn 双写取代），可删。
- iOS APNs 未实现（通知只有 Android FCM）。

## 9. 测试缺口
契约测试不错，但五条核心用户流程（onboarding→checkin→对话→问卷）没有 widget
test；本轮修的 busy 卡死 / pop 竞态类 bug 恰恰是 widget test 能拦住的。
**建议**：pilot 后补 4–5 条 golden-path widget tests。
