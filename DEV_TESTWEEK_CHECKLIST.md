# 內測開測前 — Dev 確認清單（逐條逼出明確答覆）

> 口徑：以下「代碼側」由本輪實作者直接答（是/否＋文件＋驗證方式，可當場核）；
> 「運行/部署側」要 Junyu 在**已部署 + 已登入**的環境當面確認，因為 secret 值、
> 是否 deploy、真機到達這些，代碼裡看不到。**P0 未全綠不開測。**

---

## P0 — 不確認就別開測

### 1. 三類問卷的存在性與落庫

驗收標準：測試帳號推到到期條件 → 問卷出現在 `PendingPromptsBanner` → 答完 → 寫進 Firestore。

| 項目 | 代碼側（已確認） | 運行側（Junyu 當面演） |
|---|---|---|
| **Brief PR** | ✅ 觸發＝session 結束且 **≥180 秒 + ≥3 輪**，每 agent 每日一次；**首次＝anchor，不可 skip**（`brief_pr_gate.dart`）。**滑塊＝4 個**：understanding / validation / caring / **insensitivity（反向計分）**。**量程＝0–100**（居中 50、不顯數字）。落庫 `users/{uid}/brief_pr/{auto}`。 | ☐ 當場推條件→答→Firestore 見記錄 |
| **每日心情** | ✅ 按天，home hero 卡 + banner。落庫 `users/{uid}/daily_mood/{auto}`（mood 1–5）。 | ☐ 當場見 |
| **Weekly PR（12 題）** | ✅ 第 7 天（周日 20:00–23:59）出 banner；**錨到當周 session 數最多的 agent**（降序排序）；空周寫 `no_referent`。**7 點 Likert**。落庫 `users/{uid}/weekly_pr/{auto}`。 | ☐ 當場見 |

> ⚠️ **要你拍板（HREC 對齊）**：Brief PR 代碼是 **0–100**，Weekly PR 是 **1–7**。
> 兩個量程不同 —— 確認 **HREC 文件寫的跟代碼一致**（尤其 Brief PR 是 0–100 還是 1–7）。
> 不一致就要改一邊，這是數據效度問題，不能"差不多"。

---

### 2. Tester 旗標 + 急性警報抑制

| 問題 | 代碼側（已確認） | 運行側 |
|---|---|---|
| tester 的 acute 是否只寫 `safety_events`、不發郵件？ | ✅ 已實作（`onSafetyEventCreated` 查 `users/{uid}.isTester`，true 則寫 `safety_events` + tagged `pi_alerts`，**不發 PI 郵件**）。 | ☐ **deploy functions 後**驗一次 |
| tester 數據能否從正式數據剔除？ | ✅ `UserProfile.isTester` 旗標已落庫，可篩。 | ☐ — |

> 同一個旗標兩個用途，兩者都做了。**前提：本輪改動要先 `firebase deploy --only functions`。**

---

### 3. SMTP / PI_EMAIL 當前到底配沒配

| 問題 | 答覆來源 |
|---|---|
| 線上是否已接 PI 警報郵件？ | ⚠️ **只有 Junyu 知道** —— 都是 secret，代碼無值。查：`firebase functions:secrets:access PI_EMAIL`（同 SMTP_HOST/USER/PASS）。 |
| PI_EMAIL 收件人是誰？ | ⚠️ 同上，secret。設定：`firebase functions:secrets:set PI_EMAIL`。**安全規程：acute 警報應觸達 PI。** |

> 🔴 **決定 Day 6 能否照跑**：若 **PI_EMAIL 已配 且 本輪 tester 抑制未 deploy** →
> Day 6 同事打 distress 腳本會直接給 PI 連發自殺警報。
> **開測前必須二選一**：① 先 deploy 本輪 tester 抑制；② Day 6 一律用 isTester 帳號。
> 兩件事要當面對齊：☐ secret 狀態確認　☐ 抑制已 deploy　☐ Day 6 帳號是 tester

---

## P1 — 影響測試有效性

### 4. 通知門鈴（FCM）

| 問題 | 代碼側（已確認） | 運行側 |
|---|---|---|
| Console 群發能否推到真機、點開正確開 app？ | ✅ 登入後自動訂閱 topic `all`；Android 13 `POST_NOTIFICATIONS` 權限 + manifest 已加；門鈴設計（點開＝開 app 交給 banner，無 deep link）。 | ☐ Console 向 topic `all` 發一條，你真機收 |
| Scheduled function 部署沒、在跑沒？ | ✅ 已寫：`dailyMoodReminder`（一至六 19:00 HKT）、`weeklySurveyReminder`（周日 20:00 HKT），溫和粵語。 | ☐ **deploy + 開 Cloud Scheduler**；看 Functions 日誌按時觸發 |
| iOS / APNs 做了沒？ | ❌ **未做**（歸 Phase A / `codemagic.yaml` scaffold 已起）。 | ☐ **確認測試機是 Android**（對得上才行） |

---

### 5. Consent 開關 → 記憶累積

| 問題 | 代碼側（已確認） |
|---|---|
| consent 沒開時，跨 session 記憶是否真的不累積？ | ✅ **是**。transcript retention consent 關 → 逐輪 buffer 不寫 → session 末 fold 直接 `skipped_consent_off` → **rollingSummary 不更新**（可在 `agent_contexts/{agent}.lastFoldStatus` 看到）。 |

> 🔴 **行動**：所有測試帳號註冊時**必須開 transcript retention consent**，
> 否則 Day 2–3 測的跨 session 連續性（論文機制本身）會假陰性。

---

## P2 — 安全詞表增敏（T1）

| 問題 | 代碼側（已確認） |
|---|---|
| 6/4 那批 T1 做了沒？ | ✅ 已做：補「負累」+ 7 條 acute 漏詞，**只增不刪、fail-safe**；詞表版本 `v2-2026-06-T1` + CHANGELOG；紅測轉綠（**acute recall 0.86→1.00**，precision 不變）。 |

> ⚠️ **要你/PI 書面簽字**才當 active（任務 gating）。且需在**已部署的 build** 上驗，
> 否則 Day 6 測 distress，分不清「漏檢」是詞表問題還是路由問題。

---

## 一句話分流

- **代碼側全部 ✅**（問卷、滑塊數/量程、tester 抑制、FCM 客戶端、consent 行為、T1 詞表）。
- **真正要當面逼 Junyu 的，只有運行/部署側 4 件**：
  1. ☐ `firebase deploy --only functions`（否則通知 + tester 抑制 + T1 都不生效）
  2. ☐ `PI_EMAIL` / SMTP 現值（決定 Day 6）
  3. ☐ Console 群發 + scheduled function 真機/日誌驗證
  4. ☐ HREC 量程對齊（Brief PR 0–100？）、測試機＝Android、測試帳號開 consent + 設 isTester
