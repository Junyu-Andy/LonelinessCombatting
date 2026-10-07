# T11 隐私、同意与删除（2026-10-07）

> 任务：`docs/dev-tasks/dev-tasks-1007.md` T11，SPEC:C20。分支 `fix/privacy-consent`。决策记录 0020。
> 起点：`main` @ 9642ac5 + 任务单提交 844219d。只用 emulator 和合成数据，没有连生产 Firestore，没有调用 DeepSeek。
> 行号以本分支代码为准。

## 0. 结论先看

1. **所有新行为默认关，部署后线上行为不变。** 新加 3 个配置键，都在 Firestore `app_config/phase_a`，不建就用默认值：

   | 配置键 | 默认值 | 作用 |
   |---|---|---|
   | `transcriptRetentionDefault` | `true`（= 现状） | 新账号点「繼續」和完成陪伴者介绍时写入的「保留对话」值 |
   | `sharedContextUseDefault` | `false`（= 现状） | 新账号点「繼續」时写入的 `sharedContextUse` 值 |
   | `enforceSharedContextConsent` | `false`（= 现状，不生效） | 打开后 `sharedContextUse` 才真正控制跨陪伴者共享 |

2. **「共享上下文」同意现在可以生效了，但要研究侧打开开关。** 打开后，`sharedContextUse` 不是 `true` 的人，每个陪伴者只用自己的记忆（记忆 v1 和 v0 都改了）。**注意**：现有账号的 `sharedContextUse` 全是 `false`，打开开关等于所有人的跨陪伴者共享一起关掉。
3. **新发现：老人在 App 里关不掉「保留对话」。** 设置页的开关组件写好了，但没有放进页面（`settings_page.dart:891` 的 `_TranscriptRetentionTile` 没有任何地方使用）。同意页注释和 T2 报告都说「可以去设置里关」，实际做不到。
4. **整人删除脚本 `tool/delete_participant.js` 写好了**，在 emulator（Auth + Firestore + Storage）上用合成用户测过：试运行只列不删；`--confirm` 删干净后自动再扫一遍，零残留；存证清单只有数量，没有原文。已加进 `tool/ci_backend_tests.sh`。
5. **周度盲法导出文件删不到「只删一个人」，除非重写文件。** 脚本默认只数出这个人有几行、不改文件；加 `--rewrite-exports` 才重写。怎么处理由研究侧定（见 4.4）。
6. **隐私页 6 段里有 5 段与实际不符**。负责人 2026-10-07 决定直接改 App：新页面只讲大方向，细节交给同意书（3.3 节）。这一提交单独放，等负责人确认文案。

---

## 1. 对话保留的默认值

### 1.1 现状（改之前）

- 同意页点「繼續」写 `consent.transcriptRetention: true`，写死在代码里（原 `consent_page.dart:128`）。
- 陪伴者介绍页（onboarding 最后一步）把三个陪伴者的 `transcriptRetentionByAgent` 全写 `true`，也是写死（原 `agent_onboarding_page.dart:52-56`）。
- 也就是：**默认开启**。按代码注释和 T2 报告，老人要关得去设置里改；**但设置页其实没有这个开关**（见 1.3）。
- 默认值最终由研究侧按 ICF 决定。

### 1.2 改了什么

- 两处都改成读 `PhaseAConfig.current.transcriptRetentionDefault`（`lib/core/config/phase_a_config.dart:72`），默认 `true`，所以现在的行为不变。
  - 同意页：`consent_page.dart:131-133`
  - 陪伴者介绍页：`agent_onboarding_page.dart:54-61`
- 研究侧要改默认值：在 Firestore 控制台给 `app_config/phase_a` 加 `transcriptRetentionDefault: false`，不用重新发版。下次打开 App 生效（`PhaseAConfig.load`，`main.dart:67`）。
- **只影响之后新点同意页的账号**。已经同意过的账号不会被改。
- 「要唔要我記得返」弹窗（`transcript_consent_prompter.dart`）是老人自己选「好，开返」才写 `true`，不是默认值，没有改。

### 1.3 新发现：设置页没有关闭开关

- `lib/features/settings/presentation/pages/settings_page.dart:891` 定义了 `_TranscriptRetentionTile`（「保留對話紀錄」开关），但整个 `lib/` 里没有地方用它。
- 代码里能把 `transcriptRetention` 设成 `false` 的地方：**没有**（搜索 `transcriptRetention: false` 只在测试里）。
- 所以现在老人只能请研究团队帮忙改。本任务没有把开关放回页面：这是老人看得到的新界面，按共同规则第 5 条要研究侧先定文案和位置。见第 6 节第 2 条。

## 2. 「共享上下文」同意（`sharedContextUse`）

### 2.1 现状

- 字段存在 `users/{uid}.consent.sharedContextUse`（`user_profile.dart:64`），同意页从来没写过它，所以所有账号都是 `false`（默认值）。
- 改之前没有任何代码读它（T2 报告 5.2 第 2 条）。

### 2.2 跨陪伴者共享在哪里（逐处核对）

| # | 共享的东西 | 位置 | 组别 | 开关打开且未同意时 |
|---|---|---|---|---|
| 1 | 记忆 v1：注入 prompt 时，其他陪伴者的「共享」事实（称呼、家人、居住） | `functions/memory.js` `visibleTo` / `selectForInjection`，策略 C | Hybrid（v1 范围） | 策略按 B：只看自己的（`memory.js:541` `effectivePolicy`，`:579`） |
| 2 | 记忆 v1：抽取时给模型看的「已有事实」包括其他陪伴者的共享事实；同 key 的事实会被当成「更新」 | `memory.js` `processExtraction` | 同上 | 同样按 B：只给模型看自己的，只更新自己的（`memory.js:736-746`） |
| 3 | 记忆 v0：小欣签到第一轮引用阿珍/阿伯上周回忆摘要（每周一次） | `check_in_arm_a.dart:472-495`，`cross_module_memory.dart` | Hybrid | 不引用（`check_in_arm_a.dart:477`） |
| 4 | 记忆 v0：转介时把老人整句原话存进 `shared_context/current.pendingReferrals[].triggerSnippet`，给目标陪伴者用 | `referral_routing_service.dart:126-140` | Hybrid | 存空字符串（`:135`）。转介卡片和跳转照常 |
| — | 心情分数 `recentMoodSummary`（「最近一次心情評分：3/5」） | `greeting_hero.dart`、`daily_mood_prompt.dart`、`check_in_arm_a.dart` 写；只有小欣读（`persona_resolver.dart:142-150`） | 两组写，Hybrid 读 | **不受影响**：来自首页或签到的分数，不是另一个陪伴者的记忆 |
| — | 转介判断（`referralJudgement`）把来源陪伴者最近 10 轮发给 DeepSeek | `referral_routing_service.dart:147-170` | Hybrid | **不受影响**：用的是来源陪伴者自己的对话，目标陪伴者拿不到 |

另外核对过、**不算跨陪伴者**的：阿珍/阿伯怀旧开场读往周怀旧摘要（同一个陪伴者，`reminiscence_arm_a_page.dart:283-301`）；每日问候读该陪伴者自己的滚动摘要（`agent_greeting_service.dart:100-112`）；`persona_resolver` 读该陪伴者自己的 `agent_contexts`。

说明：`pendingReferrals` 写进去后，目前**没有代码读出来给目标陪伴者**（`handoff_executor.dart:54` 的 `drainOnArrival` 没有调用方）。但原话仍存在数据库里，所以照样按开关处理。

### 2.3 改了什么

- 新文件 `lib/core/privacy/shared_context_consent.dart`：`allowsCrossAgent(profile)`、`referralSnippet(profile, text)`。开关关时一律返回「允许」。
- App：上表第 3、4 处各加一行判断（`check_in_arm_a.dart:477`，`referral_routing_service.dart:135`）。
- 服务器：`functions/memory.js`
  - `loadConfig` 多读一份 `app_config/phase_a`，取 `enforceSharedContextConsent`（`:515-530`）；
  - 新函数 `effectivePolicy(cfg, user)`（`:541`）：开关开、且 `consent.sharedContextUse !== true` → 返回 `"B"`；
  - `memoryActive` 返回这个策略（`:579`），所以 `mem_injections.policy` 会记成 `B`，事后能查；
  - `processExtraction` 用同一个策略（`:736-746`）。
- App 和服务器读**同一个**键（`app_config/phase_a.enforceSharedContextConsent`），避免两边不一致。规则已允许登录用户读 `app_config/*`（`firestore.rules:119-122`），没有改规则。
- `sharedContextUseDefault`：同意页现在把这个值写进 `sharedContextUse`（`consent_page.dart:133`），默认 `false`，和以前存的一样。

### 2.4 测试

| 测试 | 内容 | 结果 |
|---|---|---|
| `test/shared_context_consent_test.dart` | 默认值保持现状；远端配置能覆盖、类型不对时忽略；开关关时一律允许；开关开时只有 `true` 才共享，原话片段变空 | 通过 |
| `functions/test/memory_test.js` 新增 1 条 | `effectivePolicy` 四种组合 | 通过（29/29） |
| `functions/test/memory_emulator_test.js` 新增 2 条 | ① 开关关：小欣能看到通通的共享事实（和以前一样）；开关开 + 未同意：小欣看不到，通通自己仍看得到；同意后恢复；`mem_injections` 记下 B 和 C。② 开关开 + 未同意：抽取时模型看不到小欣的事实 | 通过 |

## 3. 隐私页（`lib/features/settings/presentation/pages/privacy_policy_page.dart`）

入口：设置 → 關於本App／常見問題／私隱 → 私隱政策（`support_about_page.dart:97`）。两组都看得到。

### 3.1 逐句对照

| # | 现在的话（中文版） | 实际 | 依据 |
|---|---|---|---|
| 1 | 「你每日嘅 check-in、反思記錄、提醒同聯絡人名單，只會儲存喺你部電話本身。」（`:55-57`） | **不符**。都存在 Firebase Firestore（Google 的云端数据库），项目 `loneliness-pilot-dev` | T2 第 1 节、1.4 |
| 2 | 「我哋唔會將呢啲內容上傳到伺服器。」（`:58`） | **不符**。全部上传 | 同上 |
| 3 | 「呢個 demo 冇賬戶登入、冇雲端同步」（`:63`） | **不符**。要用邮箱登入（Firebase Auth），数据云端同步 | `auth_service.dart`；T2 2.1 第 9 项 |
| 4 | 「亦都冇任何人可以遠端讀取你填嘅嘢。」（`:64`） | **不符**。研究团队用服务账号能读（`tool/admin_dump.js`）；每周盲法导出；安全事件通知 PI | T2 3.2、3.3 |
| 5 | 「唔會同任何第三方（例如廣告商、保險公司）分享你嘅使用紀錄。」（`:69`） | 广告商、保险公司：**相符**（代码里没有）。但「第三方」整体说法**不完整**：Hybrid 组的对话内容发给 DeepSeek（中国内地）；Hybrid 组通通「搜一搜」把原话发给 Brave Search；语音输入交给手机系统的语音识别（两组）；推送经 Google FCM | T2 2.1 |
| 6 | 「只有當你自己主動選擇分享某啲內容畀信任嘅人嗰陣，資料先會離開你部電話。」（`:70-71`） | **不符**。资料一直在上传 | 同上 |
| 7 | 「入『設定 > 清除所有資料』就可以一次過刪除晒。」（`:76`） | **不符**。设置里没有这个选项。老人能删的只有「我記得嘅嘢」页的单条记忆（只有 v1 用户能看到）。整人删除要研究团队跑脚本 | T2 3.1；本报告第 4 节 |
| 8 | 「動作完成之後冇辦法復原」（`:77`） | 选项不存在，这句无从谈起 | — |
| 9 | 「緊急情況下嘅例外：…電話號碼資訊由電訊商處理」（`:82-84`） | 相符，但不完整：acute 安全事件会通知 PI（两组），App 不会自己打电话 | 决策 0014；T2 2.1 第 8 项 |
| 10 | 「任何更改會喺 app 內通知。」（`:89`） | 代码里**没有**这样的通知机制（推断：没有找到版本或政策更新提示） | 未在代码中找到 |
| 11 | 「最後更新：2026 年 4 月」 | 内容早于现在的云端架构 | — |
| 12 | 联系邮箱 zhaojyxs@connect.hku.hk，7 日内回复 | 无法从代码核对 | — |

英文版（`:12-49`）内容一一对应，问题相同。

### 3.2 准确的草稿（只放这里，不上线，待研究侧和 HREC 材料核对）

> 写法按现在页面的口吻（粤语书面）。【】里是要研究侧确认或按 ICF 填的地方。按 T2 的事实写，没有写代码做不到的承诺。

**私隱政策**

我哋相信私隱就係尊重。下面用簡單嘅方式解釋你嘅資料點樣處理。

**一、你嘅資料擺喺邊？**
你喺 app 入面填嘅嘢（例如每日心情、check-in、問卷、反思記錄、提醒、聯絡人），同埋同陪伴者傾偈嘅記錄，會經網絡儲存喺 Google 嘅 Firebase 雲端伺服器，【伺服器所在地區：待確認】。你部電話亦會暫時保留一份副本，方便冇網絡時使用。

**二、邊個睇得到？**
只有香港大學呢項研究嘅研究團隊，可以按研究需要讀取你嘅資料。分析時會盡量用編號代替你嘅名，唔會用你嘅姓名或電話。如果系統偵測到你可能有即時危險，會通知研究團隊負責人跟進。

**三、會唔會傳畀其他機構？**
我哋唔會將你嘅資料畀廣告商、保險公司等機構。為咗提供服務，以下情況資料會經過其他公司處理：
- 【只適用於部分參加者】陪伴者嘅回覆由 DeepSeek 嘅人工智能服務產生（伺服器喺中國內地）。你同陪伴者傾嘅內容會傳去產生回覆；傳之前會刪走電話、電郵、身份證號碼同地址，但人名唔會刪走。
- 【只適用於部分參加者】你喺「通通」用「搜一搜」時，你打嘅字會傳去 Brave 搜尋服務。
- 你用咪高峰講嘢時，聲音會交畀你部電話自帶嘅語音識別服務轉成文字，可能經網絡處理，由電話廠商決定。
- 推送通知經 Google 嘅服務傳送，內容唔包括你填嘅嘢。
【如 Phase B 已關閉「搜一搜」同語音輸入（T9），刪走相應兩點。】

**四、陪伴者會記得乜嘢？**
【保留對話：按 ICF 寫明預設開定關，同埋點樣更改。注意：app 設定頁而家冇呢個開關，見報告 1.3。】
【陪伴者之間共享：按 ICF 寫明三位陪伴者會唔會互相知道你講過嘅嘢（例如稱呼、家人）。】
如果你有「我記得嘅嘢」頁面，可以喺嗰度睇同刪除陪伴者記得嘅內容。

**五、點樣刪除我嘅資料？**
如果你想退出研究或者刪除資料，請聯絡研究團隊（下面嘅電郵）。我哋會刪除你嘅帳戶同儲存喺雲端嘅資料，【已經用咗喺研究分析嘅匿名資料點處理：按 ICF 填】。有啲資料我哋刪唔到：系統運作紀錄會按服務商設定自動過期；已經傳咗畀 DeepSeek、Brave 嘅內容，按佢哋嘅條款處理。刪除之後請喺電話移除 app，清走電話上嘅副本。

**六、緊急情況**
如果你用「即時支援」頁致電熱線或 999，通話由電訊商處理，唔受呢個 app 控制。app 唔會自動幫你打電話。

**七、呢份政策幾時會更新？**
有重要更改時，研究團隊會通知你。

最後更新：【定稿日期】

（英文版待中文定稿後對應翻譯。）

### 3.3 App 里的新隐私页（2026-10-07，等负责人确认文案）

负责人的要求：内容准确，但不写太细，免得老人紧张；细节（哪家公司、服务器在哪、哪些删不到）交给同意书；篇幅比原来短；中英文同步改。3.2 的长草稿可以用来核对同意书。

改动在 `privacy_policy_page.dart`，测试在 `test/privacy_policy_page_test.dart`（检查不再出现旧的不实说法，联系邮箱还在）。

| 原来 | 现在 | 为什么 |
|---|---|---|
| 「我哋相信私隱就係尊重。下面用簡單嘅方式解釋你嘅資料點樣處理。」 | 「下面簡單講下你嘅資料點樣處理。」 | 缩短 |
| 你嘅資料擺喺邊？「…只會儲存喺你部電話本身。我哋唔會將呢啲內容上傳到伺服器。」 | 你嘅資料擺喺邊？「你喺 app 入面填嘅嘢，同埋傾偈嘅紀錄，會經網絡儲存喺雲端伺服器。」 | 原文不符（3.1 第 1、2 句） |
| 我哋會睇到你填乜嘢嗎？「唔會。呢個 demo 冇賬戶登入、冇雲端同步，亦都冇任何人可以遠端讀取你填嘅嘢。」 | 邊個睇得到？「只有研究團隊會按研究需要查閱。」 | 原文不符（第 3、4 句） |
| 會唔會同第三方分享？「唔會同任何第三方…分享…只有當你自己主動選擇分享…資料先會離開你部電話。」 | 會唔會交畀其他公司？「部分功能會用其他公司嘅服務（包括人工智能服務）處理你輸入嘅內容。我哋唔會將你嘅資料交畀廣告商或者保險公司。」 | 原文不完整、不符（第 5、6 句）；只说大方向，不点名公司 |
| 我點樣刪除所有紀錄？「入『設定 > 清除所有資料』就可以一次過刪除晒…」 | 想退出研究或者刪除資料？「請聯絡研究團隊（下面嘅電郵），我哋會幫你處理。」 | 设置里没有这个选项（第 7、8 句）。没写「全部删除」：导出数据保留、部分数据删不到，细节在同意书 |
| 緊急情況下嘅例外（电讯商处理热线电话） | 删掉 | 和隐私关系不大，缩短篇幅。危机页本身不受影响 |
| 呢份政策幾時會更新？「任何更改會喺 app 內通知…」 | 删掉 | App 里没有这样的通知机制（第 10 句） |
| （无） | 想知多啲？「詳情請參閱你簽署嘅研究同意書。」 | 细节交给同意书 |
| 联系邮箱 zhaojyxs@connect.hku.hk，7 日内回复 | 保留不变 | — |
| 「最後更新：2026 年 4 月」 | 「最後更新：2026 年 10 月」 | — |

英文版逐段对应（现在 App 不显示英文）。

**和同意书对齐要注意**：新页面写「只有研究團隊會按研究需要查閱」。危机告警会通知 PI，PI 属于研究团队，所以不矛盾。如果同意书写了团队以外的人（例如伦理委员会稽核）可以查阅，这句要改。

## 4. 整人删除脚本 `tool/delete_participant.js`

### 4.1 用法

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
NODE_PATH=functions/node_modules node tool/delete_participant.js --uid=<uid>           # 试运行：只列
NODE_PATH=functions/node_modules node tool/delete_participant.js --uid=<uid> --confirm --production
# 可选：--email=<邮箱>（代替 --uid）；--rewrite-exports；--receipt=<存证文件路径>；--bucket=<bucket 名>
```

- 默认试运行，只列出数量，什么都不删。
- `--confirm` 才删。**不在 emulator 上时还要加 `--production`**，防止误删。
- 删完自动再扫一遍；还有残留（导出文件除外，见 4.4）就报错退出。
- 每次都写一份存证清单（JSON），见 4.3。
- 旧的 `tool/delete_memory.js` 保留不动：它是「只删记忆、保留研究数据」，用途不同。

### 4.2 删除范围（以 T2 数据字典为清单）

**Firestore：`users/{uid}` 整棵树。** 脚本不按名单删，而是把 `users/{uid}` 下面所有子集合（含更深一层，例如 `memory/{moduleId}/entries`）逐层找出来全删，所以以后新加的子集合也不会漏。T2 列出的子集合都在里面：

| 类别 | 集合 | 按什么找到 |
|---|---|---|
| 账号资料 | `users/{uid}` 文档本身（姓名、邮箱、紧急联系人、同意、分组字段） | 文档路径 = uid |
| 问卷 | `onboarding/intake`、`brief_pr`、`weekly_pr`、`pgic`、`djg_es`、`agent_diff`、`daily_mood`、`check_in_responses`、`loneliness_probes`、`pending_loneliness_probes/current`、`ppr_responses`、`unblinding_probes` 等 | 路径在 `users/{uid}/` 下 |
| 对话和会话 | `sessions`、`turns`、`events`、`llm_turn_features` | 同上 |
| 记忆 v0 | `agent_contexts`、`shared_context`、`agent_greetings`、`memory/*`（含怀旧 `week_n`）、`cross_module_callbacks` | 同上 |
| 记忆 v1 | `mem_facts`、`mem_summaries`、`mem_followups`、`mem_injections`、`mem_extractions`（含原始输出） | 同上 |
| 功能数据 | `thought_exercise`、`thought_records`、`action_plans`、`reminders`、`response_feedback`、`tester_feedback`、`fcm_tokens` | 同上 |

**Firestore 顶层集合：**

| 集合 | 按什么找到 |
|---|---|
| `llm_calls` | 字段 `uid` |
| `safety_events` | 字段 `uid` |
| `safety_event_dedup` | 字段 `uid` |
| `pi_alerts` | 字段 `uid` |
| `te_audit_queue` | 字段 `uid` |
| `stt_usage` | 字段 `uid` |
| `pending_loneliness_probes` | 文档 ID = uid，或字段 `uid` |
| `safety_classifier_calls` | 字段 `uid`（T8 将来加的集合，现在不存在，查不到就是 0） |

**Firebase Auth**：账号（`auth.deleteUser`）。

**Storage**：
- `users/{uid}/` 下的文件：App 现在不写 Storage（T2 1.4），一般是 0，但照样查。
- 周度盲法导出 `exports/{日期}/*.ndjson`：见 4.4。

**向量索引：无。** 代码里没有向量索引（T2 3.2、第 6 条；`memory.js` 开头注释写明 v1 不做 RAG），所以没有要删的向量。

**不删的全局文档**（不含个人内容）：`meta/arm_counter`（只有人数，留作随机分组记录；删一个人不减计数）、`meta/memory_config`、`app_config/*`、`export_blind_keys`（周度盐值和组别对照）。

**脚本删不到的**（存证清单里列在 `notCovered`）：
- Cloud Logging 里的函数日志（可能有 uid），按项目日志保留期自动过期；
- DeepSeek、Brave 那边的副本，按对方条款；
- 研究员本机用 `tool/admin_dump.js` 导出的 JSON；
- 老人手机上的 Firestore 离线缓存（卸载 App 即清除）。

### 4.3 存证清单

- 内容：脚本名、模式（dry-run / confirm）、uid、时间、每个位置找到几条（`found`）、删完后还剩几条（`remaining`）、是否验证通过（`verified`）、导出文件怎么处理、删不到的清单。
- **只有数量和位置，不含任何字段的值**：没有原文、没有邮箱、没有命中的风险词。测试里专门检查过（见 4.5 第 3 条）。
- 存 uid 是为了日后核对「这个编号确实删过」。uid 本身不是姓名或联系方式，删完后不能再从数据库对回本人。
- 存证文件默认写在当前目录 `deletion-receipt-<uid>-<时间>.json`，由研究团队按 DMP 保管。

### 4.4 已导出的盲法文件（负责人已定：方案 2，保留不动）

**限制**：`blindedDataExport` 每周日把**全体参与者**写进同一批文件，一个集合一个文件（`functions/index.js` `blindedDataExport`，`exports/{日期}/{集合}.ndjson`）。没有「一个人一个文件」，所以不能只删一个文件。

**脚本能做的**：
- 找到这个人的行：用 `export_blind_keys/{日期}.salt` 重新算出当周的 `uidHash`（每周盐不同），再加上 `participantId` 等于 uid 的行（`sessions`、`turns` 里 `participantId` 就是原始 uid，T2 3.3），以及任何字段里含原始 uid 的行（例如 `thought_exercise.originTurnRef`）。
- **默认只数不改**：存证清单写明每个文件有几行，文件原样保留。
- 加 `--rewrite-exports`（和 `--confirm` 一起）：把每个文件重写一遍，去掉这个人的行，其他人的行不动，`rowCount` 跟着改。**非默认，仅在研究侧另有决定时使用。**

**决定（2026-10-07）**：选方案 2。旧导出文件保留不动，删除脚本用默认行为（只数不改）。ICF 写明「已经用于分析的去识别数据不会删除」。**前提**：导出要先改成研究编号（T12）。在那之前导出里还是原始 uid，不能算去识别，所以 ICF 的这句话要等 T12 合并后再写（backlog 第 45 项）。

当时列出的三种做法：
1. **重写导出**（`--rewrite-exports`）：删得最干净。缺点：已经下载到分析员电脑上的副本删不到；改了历史导出，分析结果可能和之前对不上，要记录。
2. **保留导出、只删源数据**：ICF 写明「已经用于分析的去识别数据不会删除」。这是很多研究的常见做法。注意现在的导出**还没有完全去识别**（`participantId` 是原始 uid，还有自由文字，T2 3.3），所以选这条之前要先等 T12 把导出改成研究编号。
3. 给 Storage 的 `exports/` 设自动过期（例如 N 周后删），减少旧副本。仓库里没有 Storage 规则和过期设置，要在控制台做。

**T12 合并后要跟着改**：T12 把导出改成研究编号、对照表单独存放。之后脚本要（a）按研究编号找导出里的行；（b）删除对照表里这个人的一行。现在脚本里还没有，因为 T12 的集合名还没定。

### 4.5 测试（emulator：Auth + Firestore + Storage，合成用户）

测试文件：`test/delete_participant/delete_participant_test.js`；emulator 配置：`test/delete_participant/firebase.json`（只给测试用，不部署；主 `firebase.json` 没有改）。

合成数据：两个 28 位的合成 uid（要删的和要保留的），每人 19 个子集合文档（含 `memory/m3_reminiscence/sessions/week_1` 这种深层路径和 `mem_extractions.raw_output`）、7 个顶层集合各 1 条、Auth 账号、Storage 文件；一份含两人各 2 行的导出文件和对应的盐。

| # | 测试 | 结果 |
|---|---|---|
| 1 | 试运行：每个位置的数量都对（`users/{uid}` 1，`memory/*/sessions/*` 1，7 个顶层集合各 1，`safety_classifier_calls` 0，Auth 1，Storage 1，导出 2 行）；数据一条没少（12 类全在） | 通过 |
| 2 | `--confirm`：自动复查通过；另外独立扫一遍，这个人零残留；另一个人 27 条和 Auth 账号都在；导出文件 4 行原样保留，存证写「只数不改」 | 通过 |
| 3 | 存证清单不含原文、邮箱、风险词；写明「向量索引：无」 | 通过 |
| 4 | `--rewrite-exports`：导出文件只剩另一个人的 2 行，`rowCount` 改为 2 | 通过 |
| 5 | 导出行匹配：`uidHash`、`participantId`、路径里的原始 uid 都能认出；别人的 `uidHash` 不会误认 | 通过 |

另外在 emulator 上用命令行跑了一遍（试运行 → `--confirm` → 再试运行），输出：

```
Dry run — would delete 5 item(s) for synthCliDemoUser00000000001; 1 export row(s) left in place.
Deleted 5 item(s) for synthCliDemoUser00000000001; 1 export row(s) left in place.
Dry run — would delete 0 item(s) for synthCliDemoUser00000000001; 1 export row(s) left in place.
```

## 5. 测试结果汇总

| 套件 | 结果 |
|---|---|
| `tool/ci_backend_tests.sh`（Functions 单元测试、Firestore 规则 34 条、emulator 测试，以及新加的整人删除测试 5 条） | 全部通过（2026-10-07，本分支） |
| `tool/ci_flutter_tests.sh`（四套构建变体：默认、Phase B 分组、规则组页面、记忆 v1） | 四套全部通过（Flutter 3.35.3） |
| ESLint（`functions/memory.js` 和改动的测试） | 无错误 |
| `flutter analyze`（改动的文件） | 无新增问题（原有 5 条提示，改前改后一样） |

## 6. 要带回研究侧的发现

1. **对话保留默认开启**，现在可以改配置 `app_config/phase_a.transcriptRetentionDefault`，不用发版。默认值按 ICF 定。只影响以后新同意的账号。
2. **老人在 App 里关不掉「保留对话」**（`settings_page.dart:891` 的开关没放进页面）。ICF 如果写「可以随时在设置里关」，现在做不到。要不要把开关放回设置页、文案怎么写，请研究侧定（新界面，本任务没做）。
3. **共享同意开关打开前要先定三件事**：
   - ICF 怎么写「陪伴者之间共享什么」；
   - 新账号默认同意还是不同意（`sharedContextUseDefault`）；
   - **现有账号怎么办**：现在全是 `false`，打开开关当天所有人的共享一起关掉。如果要保留现有人的共享，需要先补写他们的 `sharedContextUse`（要另写脚本，本任务没做）。
   - 打开开关会改变 Hybrid 组干预内容，要写进 STUDY_CHANGELOG（cohort、组别、生效日期）。
4. **共享同意在 App 里没有入口**：同意页不问这个问题，设置页也没有。打开开关后，老人没法自己改。如果要让老人选，要加新界面（研究侧定文案）。
5. **隐私页 12 句里 8 句不符、2 句不完整**（3.1 节）。App 已改成简短版（3.3 节），等负责人确认文案。同意书要写清页面上省略的细节：哪些公司（DeepSeek、Brave、手机系统语音识别、Google）、服务器在哪、哪些数据删不到。
6. **盲法导出：已定保留不动**（4.4）。ICF 写「已经用于分析的去识别数据不会删除」，但要等 T12 把导出改成研究编号之后才成立；现在导出里还是原始 uid（T2 3.3）。
7. **删不到的数据**要写进 ICF/DMP：Cloud Logging、DeepSeek/Brave 那边、研究员本机导出、手机缓存。
8. **删除一个人不减分组计数**（`meta/arm_counter`）。之后的分组平衡按「曾经分到的人数」算。是否要减，请统计师定。
9. **删除脚本由谁跑、多久内完成、存证怎么保管**，要写进 DMP。脚本要服务账号权限。
10. backlog 第 14 条（留在研究里但要删全部记忆的人，服务器继续记新的）不在本任务范围，由 T10 处理（任务单 T10 第 4 条）。

## 7. 本任务改动的文件

- App：`lib/core/config/phase_a_config.dart`、`lib/core/privacy/shared_context_consent.dart`（新）、`lib/features/consent/presentation/pages/consent_page.dart`、`lib/features/onboarding/presentation/pages/agent_onboarding_page.dart`、`lib/core/cross_referral/referral_routing_service.dart`、`lib/features/context/presentation/pages/check_in_arm_a.dart`（只改一行条件和一行 import；T7 也会改这个文件的检测调用，冲突应很小）
- 服务器：`functions/memory.js`（只动 `loadConfig`、新加 `effectivePolicy`、`memoryActive`、`processExtraction` 的策略两处；T10 会改记忆的其他部分）
- 脚本：`tool/delete_participant.js`（新）、`tool/ci_backend_tests.sh`
- 测试：`test/shared_context_consent_test.dart`、`functions/test/memory_test.js`、`functions/test/memory_emulator_test.js`、`test/delete_participant/`（新）
- 文档：决策 0020、本报告、`docs/STUDY_CHANGELOG.md`、`docs/dev/architecture.md`、`docs/history.md`、`docs/dev/backlog.md`
- 没有改：`firestore.rules`、`firebase.json`、隐私页文字、任何 prompt、安全检测代码。
