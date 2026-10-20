# 0051：10/21 起随机分析集用 RCT- 编号、cohort 标 `rct`、从第二套序列 v2 取组；PB- 停止新登记，PB-01 至 04 作 run-in；所有按 cohort 的判断读同一份清单

- 日期：2026-10-19
- 状态：已采纳（10/19 第 16、22、28、29 条；产品窗口 dev-tasks-1020 第 C 节、1020b 第一节；方案见 `docs/dev-reports/T50-T60-batch1-20261019.md` 第一节）
- 影响范围：phase_b（run-in 四人）、RCT- 随机分析集 × 两组（登记、分组、导出；两组完全相同）。pilot 不变
- 相关代码：PR #127。`functions/study_period.js`、`functions/randomization.js`、`functions/sequence_upload.js`、`functions/blinding.js`、`functions/djg_w2.js`、`functions/weekly_schedule.js`、`functions/tester_arm.js`、`firestore.rules`（`enrolledCohort()`）、`lib/core/study/cohorts.dart`、`lib/features/enrollment/`、`tool/randomization_sequence.js`、`tool/analysis_export.js`、`tool/check_prelaunch_values.js`
- 部分取代：0037 里「`PB-…` → `cohort: "phase_b"`」作为 Phase B 唯一前缀这一条（现在 PB- 只认已有的四人，新登记用 RCT-）。0037 其余不变

## 背景

10/19 首日的四位 PB-（PB-01 至 PB-04）改作 run-in，不进随机分析集。10/21 起登记的人要另起编号和一套新序列，组成随机分析集。旧序列和分配日志不能改。

## 决定

1. **编号和标签**：RCT- 登记时写 `cohort: "rct"`，`studyPeriod` 仍为 `"B"`（W4 评估员按 studyPeriod，不受影响）。PB- 新登记一律拒绝（`research_id_prefix_retired`）；PB-01 至 04 保持 `phase_b`，PILOT 保持 `pilot`，已有记录不改。导出由 cohort 推出分析集（rct → rct，phase_b → run_in，pilot → pilot）。
2. **一份清单**：服务器 `study_period.js` 导出 `ENROLLED_COHORTS`（phase_b、rct、pilot）和 `PHASE_B_COHORTS`（phase_b、rct）；App 用 `lib/core/study/cohorts.dart`；Firestore 规则用 `enrolledCohort()`。别处不再写 cohort 字符串，`functions/test/cohort_list_guard_test.js` 会拦。试跑（pilot）10/15 起也走标准周程，所以周程读「登记过」那份清单。
3. **序列版本**：
   - v1 原地不动；
   - v2 存在 `randomization_sequences/v2_low|v2_high`，已用位置存在 `randomization_state/v2_low|v2_high`；
   - `sequence_versions/v1` 记「停用」，只存长度、已用位数、指纹；`sequence_versions/v2` 记「使用中」。
   - 上传要写版本 v2、每层不少于 80、v2 已分配就拒、和 v1 同一种子就拒（只用 v1 的长度和指纹判断）。
   - 登记和分配日志加 `sequenceVersion`；登记加 `allocatedArm`（分配时的组，改组后不变）。
4. **上传的人**：v2 由 Qingyang Li 生成上传（`docs/release/sequence-v2-upload-20261020.md`），Junyu 只开关开关、发角色。

## 考虑过的其他方案

| 方案 | 为什么没选 |
|---|---|
| RCT- 仍标 `phase_b`，另加 `analysisSet` 字段 | 产品窗口 10/19 第 28 条定为 `rct`，用一份清单防漏 |
| 标 `phase_b_rct` | 同上 |
| 在 v1 后面接着用 | run-in 和随机分析集要分开，v1 的分配要原样保留 |

## 后果

- **对研究：**
  - 随机分析集只含 RCT-；run-in 四人照常随访、收问卷。
  - 导出多 `allocatedArm`、`receivedArm`、`sequenceVersion`、`runIn`、`analysisSet`。
  - 盲法导出不放 cohort（检查脚本禁止），靠编号前缀分。
  - 登记表 C01 要改；SAP、偏离日志写明 run-in。
- **对开发：** 新增按 cohort 的判断时，只能读清单；漏了 CI 会报。
- **对论文：** 方法部分写 run-in 四人和两套序列。
