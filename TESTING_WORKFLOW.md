# Testing Workflow — 设备分工 + 可复用测试流程

## 你手上的设备与能力

| 组合 | 能测什么 | 是否稀缺 |
|---|---|---|
| **Mac + iPad**（`flutter run`） | iOS 原生:B01/B02 真机对话、App Check、iOS 语音、iOS 视觉/无障碍、B07 退 app 丢状态 | ⭐ **唯一能测 iOS,优先级最高** |
| **Windows + 安卓手机**（`flutter run`） | 所有跨平台逻辑:checkin、Brief PR、今日休息、B14、离线保存、busy 卡死、语音(安卓也有 on-device) | 快、不用签名,放开跑 |
| Windows / Mac 终端 | `flutter analyze`、`flutter test`、`firebase deploy` | 任一台即可 |

**为什么分:** iOS 的东西只有 Mac+iPad 能做,所以别拿它去测跨平台逻辑(浪费)。跨平台 bug 在安卓上表现一模一样,还快。

---

## 今天的执行顺序(单人也能跑,有 RA 就两条线并行)

### 阶段 0 · 前置(~20 分钟,两台机并行)
- **Windows 上:** `git pull` → `flutter analyze`(必须 0 error)→ `flutter test`(全绿)→ `firebase deploy --only firestore,functions`。**有红字先发我。**
- **Mac 上(同时):** `git pull` → 插 iPad → `flutter run` 处理签名 → 查 bundle id 三方一致(GoogleService-Info.plist / Firebase Console / Xcode)→ 查 App Check DeviceCheck 配置。

### 阶段 1 · 关键路径先行(Mac+iPad,~30 分钟)
> B01 是最大未知数且只能在这测,**第一件事就做它**,坏了才有最多时间排查/找我。
- 三个 agent 各发一条消息 → 都要收到回复。
- 失败 → console 抓 `[LlmGateway] FirebaseFunctionsException code=...`,把 `code` 发我。

### 阶段 2 · 两条线并行
- **A 线 Mac+iPad(iOS-only):** B03 语音(abc/de)→ iOS 视觉:B08 高对比拍照、B11 字号拍照、B12/B13 尺寸 → B07 退 app 丢状态 → 飞行模式保存。
- **B 线 Windows+安卓(跨平台,快):** B04/B05 checkin→总结 → B06 今日休息可关 → B14 默认空 → Brief PR 弹出 → PPR 不重复弹 → 离线保存全家桶 → 安卓语音做第二数据点。

### 阶段 3 · 汇合
- 周期性:改系统时间到周日 20:30 测 Weekly PR / PGIC banner。
- 失败项 + 截图 + console 日志 → 发我。

**详细每步验收标准见 `PILOT_DAY_PLAN.md`。**

---

## 可复用的固定测试流程(每次改动/每个新版本都这样走)

> 这是"能定下来的 workflow",Phase A / Phase B 都用它,不用每次重新想。

**Gate 1 — 自动(任一台,~2 分钟):** `flutter analyze && flutter test`。不过不往下走。

**Gate 2 — 安卓冒烟(~10 分钟):** 跨平台黄金路径一条龙——
注册/登录 → 首页心情 → 和一个 agent 聊满 3 分钟 → 退出看 Brief PR 弹 → checkin → 首页状态条变绿。
逻辑 bug 90% 在这一步就能抓到,快且不用签名。

**Gate 3 — iOS 真机(Mac+iPad,~20 分钟):** 只测安卓测不了的——
真机对话通不通、语音、视觉/无障碍/字号/高对比、退 app 丢状态、飞行模式保存。

**Gate 4 — 发布:** 只从 `release/phase-a` 分支出包 → 版本号 +1 → 上传 TestFlight 的「Phase A 受试者」组。
开发继续在 `main`,补丁 `cherry-pick` 回 `main`。**给受试者的每个包都对应一个 git tag(可追溯,写进论文)。**

---

## 一次性建议:把 Gate 1 自动化
`codemagic.yaml` 已经在 CI 里跑 analyze+test。可以再加一条 GitHub Actions:
每次 push 自动跑 `flutter analyze && flutter test`,红了不让合并。
这样"忘了跑测试就发版"从此不可能发生。需要的话跟我说,我来配。
