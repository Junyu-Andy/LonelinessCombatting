# 分組（Arm Assignment）方案現狀 — v1 討論稿

> **用途**：如實記錄代碼中已實現的分組機制，供 Junyu / PI / 統計師討論定稿。
> 文末附「需要拍板的決定」清單。本文檔描述現狀，不代表最終協議。
>
> | | |
> |---|---|
> | 生成日期 | 2026-07-24 |
> | 對應代碼 | `lib/features/auth/data/arm_assigner.dart` · `auth_service.dart` · `firestore.rules (meta/arm_counter)` · `lib/core/arm/arm_scope.dart` |
> | 對應 commit | `f0241e1` |

---

## 1. 總體設計

**一個 app、兩個組**。每個用戶的 profile 上有一個 `arm` 字段（`A` / `B`），
所有分組差異界面用 `ArmGate(armA: …, armB: …)` 按此字段切換（checkin、
人生回顧、行動計劃、文章頁等每模塊兩套實現）。兩組裝的是同一個安裝包，
受試者無法察覺另一版本的存在；安全檢測（distress 詞表）兩組完全一致。

## 2. 分配時機與流程（代碼現狀）

分配發生在**註冊瞬間**，全自動，researcher 不選組：

```
註冊表單（researcher 協助填寫）
  ├─ 年齡段（60-64 / 65-69 / 70-74 / 75+）
  └─ UCLA-LS-V3 基線總分（20–80，researcher 填，可留空）
        ↓ signUp()
分層 strataCell（4 層）
  UCLA > 44（中位數分割）× 年齡 ≥ 70
  cell_0 低孤獨×60-69 · cell_1 低孤獨×70+ · cell_2 高孤獨×60-69 · cell_3 高孤獨×70+
  缺失值默認：UCLA 缺 → 當低孤獨；年齡缺 → 當 60-69
        ↓ Firestore 事務（meta/arm_counter）
層內平衡分配（minimization）
  該層 aCount < bCount → A
  該層 bCount < aCount → B
  相等 → 拋硬幣（Random()，未播種、無日誌）
        ↓
寫入 profile：arm / strataCell / baselineUclaScore
```

**Phase A 現狀**：兩個開關讓所有人都是 Arm A ——
`ArmAssigner(forceArmA: true)`（分配時強制 A）與 `arm_scope.dart` 的
UI 層 stub（無論 arm 是什麼都渲染 A）。Phase B 開組 = 關掉這兩個開關。

**失敗容錯**（2026-07 加固）：計數器事務失敗（如規則問題）不再阻斷註冊/
登入——profile 先以 `arm: null` 建立，之後每次登入自動重試補分。

## 3. 完整性保障（現狀）

- `meta/arm_counter` 有 Firestore 規則硬約束：一次合法寫入 = 恰好一個
  cell 的某計數 +1，其餘不變、不可回退（有 emulator 單元測試覆蓋）。
- 事件數據帶 `arm` 標籤（debug 構建強制斷言）。
- Researcher 全程不選組、不預知結果 → 具備 allocation concealment 的基本形態。

## 4. 已知薄弱點（如實列出，供討論）

| # | 問題 | 嚴重性 | 說明 / 可選修復 |
|---|---|---|---|
| W1 | **確定性 minimization 可預測** | 方法學 | 層內不平衡時下一個分配是確定的。且 `meta/arm_counter` 對任何登入賬號**可讀**——知情者理論上可預測下一位的組別，削弱 concealment。修復選項：改 biased-coin（如 p=0.8 傾向少數組）；或把分配挪到 Cloud Function（服務端執行+計數器對客戶端不可讀）。 |
| W2 | **平手拋硬幣未播種、無日誌** | 審計 | `Random()` 不可復現，且**沒有每次分配的審計記錄**（時間戳、層、當時計數、結果）。修復：分配時寫一條 `arm_assignments/{auto}` 審計文檔。 |
| W3 | **arm 字段事後可改** | 完整性 | 現行規則允許用戶寫自己 profile 全部字段，理論上可篡改自己的 arm。修復：規則加「arm 一經寫入不可變」（幾行）。 |
| W4 | **缺失基線的默認值** | 方法學 | UCLA 留空 → 一律進「低孤獨」層。若 Phase B 允許缺失入組，會系統性偏置 cell_0/1。建議：Phase B 把 UCLA 設為註冊必填。 |
| W5 | **arm=null 的過渡態** | 產品 | 容錯路徑下用戶可能帶著 arm=null 用 app 一段時間。Phase A 無所謂（UI 強制 A）；Phase B 需決定 null 期間渲染哪組（`arm_scope` 注釋原意為 fail-safe 到 B），以及該期間數據是否計入。 |
| W6 | **分配在客戶端執行** | 架構 | 事務跑在用戶設備上，依賴規則兜底。長期更穩的形態是 Cloud Function 服務端分配（同時解決 W1 可讀性與 W2 審計）。 |

## 5. 與「預生成隨機序列」方案的對比（核心待決）

| | 現狀：現場自動 minimization | 備選：統計師預生成序列 |
|---|---|---|
| 誰控制隨機性 | app 算法 | 統計師（封閉信封/名單） |
| researcher 操作 | 只錄入 UCLA 分數 | 需按序列為每位受試者錄入分配（或錄參加者編號由系統映射） |
| 層內平衡 | 動態最優 | 取決於序列設計（塊隨機） |
| 可預測性 | W1 所述風險 | 塊隨機同樣有塊尾可預測問題；封閉管理下可控 |
| 審稿人熟悉度 | minimization 是公認方法，但**須在協議中預先聲明** | 最傳統，無爭議 |
| 實現改動 | 無 | 中等（新錄入流程+序列校驗） |

## 6. Researcher 操作手冊（按現狀）

**Phase A（現在）**：無任何分組操作。UCLA 分數建議照填（存檔用）。

**Phase B（每收一名受試者）**：
1. 線下完成基線 UCLA-LS-V3，得總分；
2. 協助註冊：填年齡段 + 在「研究人員填寫」欄輸入 UCLA 總分；
3. 點「建立帳號」→ 系統自動分層、自動分組；
4. 事後核對：Firestore `users/{uid}` 的 `arm` / `strataCell` / `baselineUclaScore`。

**Phase B 技術開關**（開發側一次改動）：關 `forceArmA` + 移除 `arm_scope` stub。

## 7. 需要拍板的決定

- [ ] **D1**：隨機化方式 —— 維持現場 minimization / 改 biased-coin / 改預生成序列？（見 §5、W1）
- [ ] **D2**：是否把分配挪到 Cloud Function（服務端）？（解決 W1+W2+W6，建議 Phase B 前做）
- [ ] **D3**：是否加分配審計日誌？（W2；無論 D1 選哪個都建議加）
- [ ] **D4**：規則加「arm 不可篡改」？（W3；建議加）
- [ ] **D5**：Phase B 註冊時 UCLA 是否必填？（W4；建議必填）
- [ ] **D6**：arm=null 過渡期渲染哪組、數據如何處理？（W5）
- [ ] **D7**：協議文本相應更新（minimization 須預先聲明；HREC 一致性）
