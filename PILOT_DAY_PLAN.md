# Pilot Day Plan — 明天 09:00–16:00

> 前提：Mac 已充电。手上有 iPad + iPhone 真机。
> 原则：**上午把"硬门槛"清掉（编译 / 部署 / B01 网络），下午做测量与无障碍**。
> 任何一步失败：抓 console 日志（`flutter run` 窗口）+ 截图 + 记时间点，发回给 Claude 继续修。

---

## 09:00–09:45 · 环境与构建（Mac，不用真机）

- [ ] `git pull`（分支 `claude/friendly-meitner-dzj09c`）
- [ ] `flutter analyze` — **必须 0 error**（warning 可放行）。有 error 立即发回。
- [ ] `flutter test` — 全绿。
- [ ] `firebase deploy --only firestore`（rules + 新加的 indexes）
- [ ] `firebase deploy --only functions`（tester 抑制 / T1 词表 / 通知，全指着这个）
- [ ] **Bundle ID 三方一致性检查（B01 强嫌疑）**：`ios/Runner/GoogleService-Info.plist`
  的 `BUNDLE_ID` / Firebase Console iOS app 的 bundle id / Xcode 的
  `PRODUCT_BUNDLE_IDENTIFIER`（当前是占位符 `com.example.appDemo`！）三者必须一致。
  不一致 → iOS 端 Firebase 鉴权/写库静默失败，正是"真机发不出收不到"的现象。
- [ ] Firebase Console → App Check：
  - iOS app 是否已配 **DeviceCheck** 私钥？
  - `proxyDeepSeek` 的 enforcement 状态？
  - **这是 B01（真机对话不通）的头号嫌疑**。若未配：要么配好，要么临时把 enforcement 改成 unenforced（记得 pilot 后恢复）。
- [ ] 测试账号检查：全部 `isTester: true`、transcript retention consent 开、arm 已分配。

## 09:45–11:30 · iPhone 真机核心回归（`flutter run` 连线，边测边看日志）

**P0 链路，按顺序：**

- [ ] **B01/B02 对话**：三个 agent（小欣/阿珍·阿伯/通通）各发一条文字，都能收到回复。
  - 失败 → 看 console `[LlmGateway] FirebaseFunctionsException code=...`：
    - `permission-denied` / `failed-precondition` → App Check（回 09:00 那步）
    - `unauthenticated` → 登录态问题
    - `internal` → DeepSeek 上游 / secret
    - `deadline-exceeded` → 超时（网络/prompt 过长）
- [ ] **B03 语音**：点麦克风说「abc」→ **不点停止**直接点发送 → 再说「de」。
  - 验收：发出的是「abc」，第二次输入框只出现「de」，无拼接残留。
  - 在小欣、通通、阿珍/阿伯三处各做一次；行动计划表单做一次。
- [ ] **B04/B05 checkin**：完成一次 checkin →
  - 首页状态条变「✓ 今日已做咗 check-in」（≤30 秒）
  - 首页「今個星期 · 傾咗 N 次」+1
  - Firestore Console：`daily_mood` 有新条目；Arm B 账号另查 `check_in_responses`
- [ ] **Brief PR 弹出**（本轮修复的重点）：和通通聊 ≥3 分钟且 ≥3 轮 → 退出页面 → Brief PR 问卷应弹出。同一 agent 当天再退出**不应**再弹。
- [ ] **离线（本轮修复的重点）**：开飞行模式 → 做一次 checkin → 保存应**立即**成功不转圈 → 关飞行模式 → Firestore 里数据补同步到位。
  - 同样试：consent 页 Continue、intake 儲存並繼續。

## 11:30–12:00 · 安全路径（⚠️ 必须用 isTester 账号）

- [ ] 对小欣输入一句测试用急性高危语句 → 危机页面/热线信息**立刻**出现（不转圈）。
- [ ] 飞行模式下重复一次 → 危机界面仍立刻出现（本轮修复：不再被写库阻塞）。
- [ ] Firestore `safety_events` 有记录、PI **没有**收到邮件（tester 抑制生效，前提 functions 已 deploy）。
- [ ] 聊完含悲伤词汇（如「过世」）的一整段对话后正常退出 → `safety_events` **不应**出现第二条重复记录（本轮修复：总结折叠不再重扫）。

## 12:00–13:00 · 午饭 / 机动补位

## 13:00–14:30 · 测量效度 + 无障碍（iPad + iPhone 都过）

- [ ] **B14 望一望**：强度滑块初始无滑块头、表情无预选；不选不能继续；后测同样默认空。
- [ ] **B06 今日休息**：能开、**当天能关**、默认关。
- [ ] **B13**：首页五个表情已放大且带文字（好差/差/麻麻地/幾好/好好）；iPhone 小屏不换行不裁切。
- [ ] checkin 页（两个 arm）：心情脸无预选，选了才能存。
- [ ] **字号档位**：标准/大/特大各切一遍，过首页、checkin、望一望、设置 —— 记录哪些元素不放大或被裁切（= B11 的精确定位，拍照）。
- [ ] **高对比**：开启后过全部主要页面，**把变黑/不可读的位置拍照**（= B08 定位）；确认切换后停留在设置页（B10 复现路径记下来）。
- [ ] **B07**：特大字号下：聊天聊一半 → 划掉 app → 重开，记录丢了什么。
- [ ] B12 checkin preview / B25 人生回顾 UI：iPhone 上截图标注哪里太小/布局问题。

## 14:30–15:30 · 问卷与周期性触发

- [ ] PGIC / Weekly PR：用 tester 工具或改系统时间到周日 20:00–23:59 验证 banner 出现、答完不重复弹。
- [ ] PPR（阿珍/阿伯 session 后）：第一次强制版可提交；**同一天再来一次 session 不应再弹强制版**（本轮修复）。
- [ ] Agent Diff W2/W4 banner（若账号 createdAt 满 14/28 天）。

## 15:30–16:00 · 收尾

- [ ] 把所有失败项 + 截图 + console 日志整理发回 Claude。
- [ ] 确认 pilot 正式账号清单：isTester 状态按需设置（正式受试者 = false！）。
- [ ] 若一切绿：打 release 包（或 Codemagic 触发），装到 pilot 设备。

---

## 快速分流表（出问题先对号入座）

| 症状 | 先查 |
|---|---|
| 真机对话没回复 | console 的 FirebaseFunctionsException `code`；App Check |
| 保存按钮转圈不动 | 不应再发生（已全改乐观保存）——若发生，记下是哪个页面，属于漏网 |
| 问卷没弹 | 是否满足条件（时长/轮数/时间窗）；`brief_pr` / `weekly_pr` 集合里是否已有今天/本周记录 |
| 页面崩溃 | console 红字栈发回 |
| 通知没到 | iOS 上是**预期内**（APNs 未实现，只有 Android FCM） |
