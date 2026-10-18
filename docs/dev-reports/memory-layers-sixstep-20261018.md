# 两层记忆开关 emulator 六步核对（dev-tasks-1018 E1 (a)，2026-10-18 晚）

> 结论先说：**六步加规则组一步，全部过。** 按 E1 (b)，Junyu 10/19 早上可以在控制台把 `meta/memory_config.layersEnabled` 设为 boolean `true`（核对表第 9 项），再开登记门。开了之后 Phase B 全程不再动。
> 环境：Firestore emulator，`meta/memory_config = {enabled: true, policy: "C", phaseBArmA: true, layersEnabled: true}`，抽取提示词仍是 v2（没有设 `extractionPrompt`）。模型用桩（固定 JSON），所以查的是**服务器怎样存、怎样过滤、怎样记日志**，不是模型抽得准不准。代码：`main` @ d6c38d9。脚本：`functions/test/memory_layers_sixstep_emulator_test.js`，可重跑：
>
> ```bash
> firebase emulators:exec --only firestore --project loneliness-pilot-dev \
>   "cd functions && node test/memory_layers_sixstep_emulator_test.js"
> ```

## 六步结果

| 步 | 做什么 | 看什么 | 结果 |
|---|---|---|---|
| ① | 合成 Hybrid 老人（`arm: "A"`、`armAssignmentMode: "pilot_designated"`、共享同意开）和小欣聊 3 轮：讲个女叫阿欣、上星期睇医生血压高咗少少、今日落雨；结束会话（`claimBuffer` → `processExtraction`） | `mem_facts`：家人条 `layer: "shared"`、`sourceAgent: "siu_yan"`；健康条 `layer: "private"`、`sourceAgent: "siu_yan"`、`sensitivity: "sensitive"`；`mem_extractions.prompt_version` 是 `memory_extraction.v2` | **过** |
| ② | 开通通会话（`injectMemory`，模块 `tung_tung_chat`） | 发给 DeepSeek 的记忆块含「個女」那条，不含「血壓」那条 | **过** |
| ③ | 开阿珍／阿伯会话（模块 `reflective_dialogue`） | 同 ② | **过** |
| ④ | 小欣新会话：「呢件事你唔好記住呀」，再讲「我個仔阿明下個月結婚」；结束会话 | 模型一次都没被调用；`mem_facts`、`mem_summaries` 数量不变（2→2、1→1）；抽取记录 `outcome: "forget_request"`、原话已清空 | **过** |
| ⑤ | 模拟设定页删掉那条 shared 的家人事实（删文档，再跑触发器函数 `deleteSummaryForItem`） | `mem_facts` 里没有任何 family 条；通通、阿珍／阿伯、小欣三位再开会话的记忆块都不含「個女」 | **过** |
| ⑥ | 看 `mem_injections` | 4 条注入日志每条都有 `layer_counts: {shared, private}`、`layers_enabled: true`、`session_id`；通通第一次注入 `shared: 1, private: 0`，`source_agents.shared.siu_yan: 1` | **过** |
| 规则组① | 合成规则组老人（`arm: "B"`）照 ① 走 | `memoryActive` 为空；`injectMemory` 返回空字串；`mem_facts`、`mem_injections` 都是 0 条；`inScope` 为 false | **过** |

另外重跑了 T31 原有的 11 条分层集成测试（`functions/test/memory_layers_emulator_test.js`），全部过。

## 两点要知道

1. **健康类事实先「等确认」。** 步 ① 的血压条存下来时是 `status: "pending_confirmation"`（健康类一律敏感，老人要在「我記得嘅嘢」按「好，記住」才会用）。为了考的是「层」而不是「等确认」，脚本在 ② 之前把它改成已确认，再看通通和阿珍／阿伯确实看不到——看不到是因为它在私有层。
2. **开关开后旧条目不迁移**（决策 0035 第 4 条）：PILOT-01、02 之前存下的条目没有 `layer` 字段，读取时按同一规则推算（`memory.js` `itemLayer`），不用处理。

## 10/19 的操作（E1 (b)）

1. Junyu 在 Firebase 控制台 → Firestore → `meta` → `memory_config`：确认 `enabled: true`、`phaseBArmA: true`，加或改 `layersEnabled` 为 **boolean** `true`。不要动 `policy`。
2. 可同时开 `app_config/feature_flags.memoryLayersNoticeEnabled: true`，「我記得嘅嘢」顶部会显示 S7 说明（决策 0035 第 8 条说两个一起开）。
3. 再开登记门（`enrollmentGateEnabled`）。
4. STUDY_CHANGELOG 已先写一行（生效日 2026-10-19，Junyu 开了才算）。登记表 C05 的「已实现并启用」由产品窗口改。
