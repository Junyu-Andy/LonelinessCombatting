# 回忆 v2（App 部分）：两组同一份开放问题、小篇章和评分、离开按钮

日期：2026-10-20。分支 `claude/zealous-fermat-8rgqtg-reminiscence-app`（从 `claude/zealous-fermat-8rgqtg-keyboard` 3125ac2 开）。范围：1020d 第二至第八节的 App 部分。服务器部分（小篇章 Cloud Function、`ah_jan_ah_bak.v3` 提示词、推送、Firestore 规则）由另一个开发窗口做；第一节的两个 bug 不在这个分支。

## 结论

- 做完了。新行为全部在两个远程开关后面，**默认关**，关时回忆页和离开按钮一字不变：
  - `app_config/feature_flags.reminiscenceV2Enabled`：新回忆页、小篇章、评分、「我嘅人生小篇章」。
  - `app_config/feature_flags.leaveButtonV2Enabled`：「離開（會暫存）」和「離開」。
- 开关开时，两组进回忆周都是**同一个页面、同一段开场、同样 8 题、同样的输入框和「唔想講」**。文字只有一份（`docs/spec/copy/reminiscence-v2.md`），测试逐字比对代码。
- 两组唯一的差别在老人答完一题之后：Hybrid 组模型追问一条、再回一句；规则组一句固定句，**全程零 LLM 调用**（测试里装了“一叫就报错”的假模型，每个规则组测试都确认 0 次调用）。
- 第 8 题后两组同一句结束句和「完成今個禮拜」。小篇章两组同一个画面：标题、正文、三题评分、「改一改」「儲存」。
- 中途离开会暂存，下次从没答的那题接着。
- 全部 Flutter 测试（六套）通过；`flutter analyze` 没有新问题。
- **老人看到的新文字全部是草稿**，等你在截图里定（第 9 节列出每一处）。

## 1. 老人会看到什么

### 1.1 每周流程（两组相同）

1. 本周第一次进回忆页：阿珍／阿伯说开场，**三个气泡**（第 1 周和第 2 至 4 周不同，见文字表）。之后再进来不再说开场，只显示原来的对话。
2. 出第 1 题（粗体气泡）。下面是一个「唔想講」按钮和输入框（提示「記得幾多寫幾多。」）。没有答案选项，没有话题卡。
3. 老人作答 → 每题之后的回应（见 1.2）→ 下一题，一直到第 8 题。
4. 第 8 题之后：「今個禮拜嘅問題問完喇，多謝你。撳『完成今個禮拜』，我幫你整理成一篇小文章。」和「完成今個禮拜」按钮。也可以先离开，下次再撳。

### 1.2 每题之后

| 情况 | Hybrid 组 | 规则组 |
|---|---|---|
| 答完一题 | 模型按答案追问一条（要具体），老人答后模型回一句（不超过 2 句，不提问），然后下一题 | 一句固定句，然后下一题 |
| 第 1 至 6 题答完 | 同上 | 三句轮换，近 2 次不重复：「多謝你話我知，我哋講下一樣。」→「收到，我記低咗。我哋講下一樣。」→「聽落好有畫面。我哋講下一樣。」 |
| 第 7 题答完 | 同上 | 「嗰陣真係唔容易，多謝你肯講。我哋講最後一樣。」 |
| 第 8 题答完 | 同上，然后结束句 | 直接结束句（结束句本身有「多謝你」） |
| 撳「唔想講」（题目或追问） | 「冇問題，我哋講下一樣。」，不调 LLM | 同一句 |
| 第 8 题撳「唔想講」 | 直接结束句 | 同 |
| 答的内容讲到亲人离世、过去的困难（`moderate_review`） | 模型照提示词规矩回应（只承认，不追问细节） | 第 1 至 6 题改用 rule-templates.md 的 Z5 哀伤模板（同样轮换）；第 7 题仍用第 7 题那句 |
| 模型失败 | 用一般句里轮到的一句，然后下一题；记一条事件 | 不适用 |
| 每题追问上限 | 默认 1；`app_config/phase_b.reminiscenceFollowupsMax` 设 2 就追问两次再回一句 | 不追问 |

Hybrid 组每次叫模型：提示词 key `ah_jan_ah_bak_v3`，moduleId `m3_reminiscence_w{N}`（服务器的记忆、安全输入点、拒绝规则组的防线照旧），阿珍／阿伯按老人配对。附的 context 第一行是标记，接着几行：

```
[回憶·追問]
本週主題：童年同屋企
題目：講下你細個住嘅地方，係點樣嘅？
老人答：……
```

回一句时第一行是 `[回憶·回應]`，并加 `追問：……` 和 `老人再答：……`（追问两次时有两组）。「再講多啲」时第一行是 `[回憶·再講多啲]`，下一行 `本週主題：……`，老人的话是那次的输入。之后照旧附阿珍／阿伯的记忆块和「唔想提起」那一行。

### 1.3 完成之后：小篇章

- 撳「完成今個禮拜」：
  - 规则组：手机上即时排好。标题「第 N 章：主題」，每题一个小标题（草稿，例如「細個住嘅地方」「最記得嘅一日」），下面是老人的原话，**一字不改**；撳了「唔想講」的题不出现。不推送。
  - Hybrid 组：写一份请求给服务器，页面显示「整理緊…你可以先離開，整理好會話你知。」。服务器写好后，回忆页显示「第 N 章整理好喇」和正文；推送由服务器发。生成失败时显示「今次整理唔到。撳「重新整理」再試一次。」。
- 两组同一个画面：「第 N 章整理好喇」、标题、正文；下面三题评分（一次一题，1 至 7 只显示数字，两端有字，「唔評住」跳过这一题）；评完才出「改一改」「儲存」。评的是原稿。
- 「改一改」：正文变成可以改的输入框；「儲存」存改稿和改动比例。不改直接「儲存」也可以（改动比例 0）。
- 再往下有「再講多啲」：自由补充，Hybrid 组模型照常回一句，规则组固定回「收到，我記低咗。想再講可以繼續寫。」（草稿）。补充之后出「重新整理」，重新生成小篇章，然后再评一次分。
- 原来的 80 字小结照旧生成和保存（Hybrid 组照旧由模型写，规则组存老人原话），下周模型的 context 和记忆照旧读它。小结不给老人看。

### 1.4 我嘅人生小篇章

回忆首页「我嘅回憶」那个按钮在开关开时换成「我嘅人生小篇章」。页面按周列出已整理好的章节（标题和前几行），点进去看全文，可以再「改一改」。不做分享。回忆首页每周那一格，整理好但还没撳过「儲存」时显示「第 N 章整理好喇」。

### 1.5 离开按钮（开关 `leaveButtonV2Enabled`）

- 回忆页左上角「離開（會暫存）」：只是离开，不结束本周；会话按现有规则结束，照常可以邀请 Brief PR。
- 其他陪伴者聊天页（小欣、通通等）左上角的「今日傾到呢度」改「離開」，第一次出现时的说明改「撳『離開』就係今次傾完。想再傾隨時返嚟，之前講過嘅都喺度。」。会话结束规则和 Brief PR 邀请不变。
- 新说明用新的设备标记，所以看过旧说明的老人也会看到一次新说明。
- 只开离开按钮、不开回忆 v2 时，旧回忆页左上角也叫「離開」（旧 Hybrid 页撳了会出总结页）。建议两个开关一起开。

### 1.6 中途离开、再进来

每说一句就存。离开（左上角按钮、返回键、30 分钟没动静）后再进来：显示之前全部消息，从没答的那题接着；如果离开时模型的追问还没答，就接着答那条追问。

### 1.7 安全

- 每句老人输入都过同一个安全检测，两组同一个输入点 `chat_reminiscence`（Hybrid 组在网关里，和旧 Hybrid 回忆页一样；规则组直接调，同一个点；分类器开关开时两组都问分类器）。`lib/core/safety/` 没改。
- 命中急性（acute）或需要打断的中度（`moderate_interrupt`）：这次不再出题，输入框收起，出现有的安全提示和流程（急性：危机页；中度：支援提示）。那一句标记起来，不进小篇章，以后不再发给模型。下次进来从下一题接着。
- 命中 `moderate_review`（离世、过去的困难）不停题，见 1.2。理由：现有安全流程对它本来就是只记录不打断；回忆题（第 7 题、第 3 周第 5 题）本身会引出这类内容。【待 Junyu 确认】

## 2. 开关和配置

| 名称 | 位置 | 默认 | 作用 |
|---|---|---|---|
| `reminiscenceV2Enabled` | `app_config/feature_flags` | 关（只有字面 `true` 才开） | 新回忆页、小篇章、评分、我嘅人生小篇章 |
| `leaveButtonV2Enabled` | `app_config/feature_flags` | 关（只有字面 `true` 才开） | 「離開（會暫存）」「離開」和新说明 |
| `reminiscenceFollowupsMax` | `app_config/phase_b` | 1（1 至 2，其他值取近的一边） | Hybrid 组每题追问几次 |
| `reminiscenceV2ValidMinQuestions` | `app_config/phase_b` | 3 | 一次进入答了几题算有效会话 |

`app_config/phase_b` 只在 Phase B 构建里读，Phase A 构建用默认值。

## 3. 写了什么数据

### 3.1 每周对话 `users/{uid}/reminiscence_v2/week_{N}`

| 字段 | 内容 |
|---|---|
| `weekIndex` | 1–4 |
| `arm` | `A`（Hybrid）或 `B`（规则组） |
| `configVersion` | 文字版本，现在是 `reminiscence_v2.draft-20261020` |
| `status` | `in_progress` → `questions_done` → `chapter_requested`（Hybrid）→ `chapter_ready` |
| `currentQuestion` | 正在问的题 1–8，9 = 八题问完 |
| `followupsAsked` | 每题追问了几次，例如 `{"1": 1, "3": 1}`（规则组空） |
| `messages` | 逐句：`{id, role: assistant / user, kind, questionIndex, text, at}`；`kind` 是 `opener / question / answer / followup / followup_answer / reply / fixed_line / skip / closing / extra / extra_reply`。另有两个可选字段：`copyId`（哪一句固定文字或 `llm` / `llm_fallback`，方便分析）、`safety`（这句命中 acute / `moderate_interrupt` 而停题时才有） |
| `transcriptRetained` | `messages` 有没有存在服务器（同意关时 false） |
| `ratedRequestId` | 已评分的那次小篇章请求（每个版本只问一次评分） |
| `chapterRequestedAtMessage` | 上次整理时有几条消息（之后有补充才出「重新整理」） |
| `createdAt`、`updatedAt` | 服务器时间 |

### 3.2 小篇章 `users/{uid}/reminiscence_chapters/week_{N}`（和服务器分支的约定）

App 写（撳「完成今個禮拜」或「重新整理」时）：

| 字段 | 内容 |
|---|---|
| `weekIndex` | 周数 |
| `source` | `hybrid` 或 `rule` |
| `status` | Hybrid：`requested`；规则组：`ready` |
| `requestId` | 每次新的随机 16 位十六进制字符串 |
| `requestedAt` | 服务器时间 |
| `input` | `{themeZh, items: [{questionIndex, question, answer 或 null, skipped, followups: [{q, a}], reply 或 null}], extras: [{text, reply 或 null}]}`：整周对话，服务器不用再读 `reminiscence_v2`。8 题都在；撳「唔想講」的题 `skipped: true`；停题的那句 `answer: null`；追问撳「唔想講」时 `a: null`；规则组 `reply` 是 null（固定句不算内容） |
| `ruleText`、`version` | 只有规则组：排好的正文（不含标题）、版本（每次重新整理加 1） |
| `editedText`、`editRatio`、`savedAt` | 撳「儲存」时；每次新请求会把这三项删掉（新稿还没改） |

服务器写（App 从不写）：`status`（`generating` → `ready` / `failed`）、`finalText`、`version`、`rounds`、`flags`、`generatedAt`。App 在 `status == ready` 时显示 `finalText`（Hybrid）或 `ruleText`（规则组）。

改动比例：原稿和改稿之间的**字级编辑距离**（Levenshtein：每增、删、换一个字算 1，一个汉字算一个字）÷ 原稿字数。0 = 没改；1 = 改动次数和原稿字数一样多；加了很多字时可以大于 1。原稿永远是服务器的 `finalText` 或 App 的 `ruleText`，在「我嘅人生小篇章」再改也是和原稿比。

### 3.3 评分 `users/{uid}/reminiscence_chapter_ratings/{自动编号}`

`weekIndex`、`studyWeek`（按 W0 算的研究周，没有 W0 时 null）、`chapterVersion`、`source`（hybrid / rule）、`accuracy`、`satisfaction`、`share`（1–7，「唔評住」时 null）、`skipped: {accuracy, satisfaction, share}`（true / false）、`ratedAt`（服务器时间）。评的是原稿。不进 Brief PR，不进记忆。

### 3.4 其他

- `sessions` 行：新页面的会话多两个字段 `reminiscenceV2: true`、`reminiscenceQuestionsAnswered`（这次答了几题）。别的页面的行不变。
- 80 字小结：照旧写 `memory/m3_reminiscence/sessions/week_{N}`（`end_summary_original`、`status: completed`），下周 context、跨伙伴回调、我嘅故事都照旧读。
- 事件：规则组每句固定句 `rule_template_reply`（`theme: reminiscence_v2`、`template_id`）；Hybrid 组模型失败 `reminiscence_v2_llm_fallback`；每轮照旧写 `turns`。
- 手机上：同意关时的原话 `shared_preferences` 键 `reminiscence_v2.{uid}.week_{N}`；新说明的标记 `session.leaveHintShown`。

### 3.5 Firestore 规则

查过：`users/{uid}/{collection}/{document=**}` 已经允许本人读写（入组门照旧），三个新集合都在这条下面，**App 这边不用改规则**；它们不在“研究周字段只能服务器写”的名单里，所以评分的 `studyWeek` 可以由 App 写。`reminiscence_chapters` 的服务器字段只能服务器写，这条规则由服务器分支加，我没碰 `firestore.rules`。

## 4. 保留对话的同意

旧回忆页的做法：`consent.transcriptRetentionFor('ah_jan_ah_bak')` 关时，M3 周文档的 `turns` 不写，但周文档的状态和老人确认过的小结照写（算老人自己的作品，不算原始对话）。

新页面照同一个开关：

- 同意开：`reminiscence_v2/week_{N}` 的 `messages` 存全部对话。
- 同意关：服务器那份只存进度（`status`、`currentQuestion`、`followupsAsked` 等），`messages: []`，`transcriptRetained: false`；原话留在页面内存和手机（`shared_preferences`），所以老人离开再进来照样接得上。换手机或删 App 就没有了。
- 小篇章请求：照约定，`input` 里带整周对话，规则组的 `ruleText` 也是原话。这和旧页面“小结照存”同一个理由（小篇章是老人看、可以改的作品），但 `input` 本身就是对话。**建议服务器在生成完后、同意关的人把 `input` 清掉**，或者你定同意关时不做 Hybrid 小篇章。【待 Junyu 确认】
- Hybrid 组照旧在第一句时问一次「要唔要我記得返」（旧页面的提示，同意关时才出）。

## 5. 对服务器约定的假设

1. context 块放在 `contextSuffix` 的**最前面**，所以整个 `contextSuffix` 的第一行和块的第一行都是标记；后面是阿珍／阿伯的记忆块、「唔想提起」，网关再在最后加 `[今週主題]`、`[模組]`。
2. 追问两次时，第二次追问的块里有第一次的 `追問：` / `老人再答：`；回一句的块里有全部追问。`[回憶·再講多啲]` 块只有 `本週主題：`，老人的话在 userInput。
3. 模型的 history 是本周对话（最多最近 16 轮），不含停题那句。
4. Hybrid 的 `version` 由服务器写；评分的 `chapterVersion` 取文档里的 `version`，没有时写 1。App 用 `requestId` 判断“这一版评过没有”。
5. 重新整理时 App 把 `status` 设回 `requested`、换新 `requestId`、删掉 `editedText` / `editRatio` / `savedAt`；旧的 `finalText` 留着直到服务器覆盖（App 只在 `ready` 时显示）。如果服务器规则不许 App 删这三项，要放行。
6. 规则组的文档 App 直接写 `status: ready`，服务器不用处理（推送也不发）。
7. 推送「你嘅第 N 章整理好喇，得閒入嚟睇下。」由服务器发。现在点推送不会跳到指定页面（`fcm_service.dart` 只记录打开事件），所以点了只是打开 App；我没有加跳转。
8. `ah_jan_ah_bak_v3` 由服务器分支登记；App 不碰 `build_info.g.dart`、`functions/`、`firestore.rules`。服务器没登记前，Hybrid 组调用会失败，页面会用一般句继续（不会卡住）。

## 6. 测试

### 6.1 新测试

`test/reminiscence_v2_test.dart`（加进 `tool/ci_flutter_tests.sh` 的「phase B arm gating」；默认构建也跑，规则组的用例跳过）。假模型、假存储、假时钟，合成数据：

- 开关：只有字面 `true` 才开；关时回忆首页打开旧页面、显示「我嘅回憶」、S9 仍是「今日傾到呢度」；开时打开新页面、显示「我嘅人生小篇章」。
- 规则组第 1 周 8 题全答：三个开场气泡、8 题顺序、G1→G2→G3→G1→G2→G3、第 7 题那句、结束句和按钮、文档字段、有效会话（Brief PR 卡）、**0 次 LLM 调用**。
- 规则组第 7、8 题「唔想講」。
- 规则组小篇章：原话一字不改、「唔想講」的题不出现、文档字段（不含服务器字段）、80 字小结（无 LLM）、三题评分含「唔評住」和写入的数据、「改一改」和改动比例。
- 规则组「再講多啲」、「重新整理」（版本 2、新 `requestId`、再评一次）。
- 规则组哀伤内容出 Z5，继续出题；acute 停题、危机页、再进来从下一题接着；`moderate_interrupt` 出支援提示、停题。
- Hybrid：每题一条追问、一句回应，标记、key、moduleId、阿珍、块的每一行；「唔想講」不调 LLM；整周（第 7 题唔想講）14 次调用；追问上限 2；模型失败用一般句；acute 不调模型、停题。
- Hybrid 小篇章请求文档字段、「整理緊…」、服务器 `generating` → `ready` 后显示「第 1 章整理好喇」和正文、评分、「再講多啲」（`[回憶·再講多啲]`）、「重新整理」。
- 两组：离开（「離開（會暫存）」）再进来，对话和进度都在、开场不重复（Hybrid 停在追问上也接得上）；同意关时服务器没有原话、手机有、再进来照样；只答 2 题不算有效会话，「唔想講」不算；第 2 周开场；两组开场、题目、结束句完全一样。
- 我嘅人生小篇章：列表只列整理好的、点进去改一改、改动比例、回首页「整理好喇」消失。
- 离开按钮：开时其他页「離開」和新说明（只出一次，看过旧说明也出），回忆页「離開（會暫存）」；关时「今日傾到呢度」和旧说明；「離開（會暫存）」结束会话、本周仍是 `in_progress`、答够 3 题有 Brief PR 卡。

`test/reminiscence_v2_copy_test.dart`（每套构建都跑）：文字表和代码逐字一致（开场、32 题、小标题、固定句、按钮、评分）；一般句轮换；规则组排版；请求 `input`；改动比例；同意关时周文档不带原话。

### 6.2 结果

全部通过（2026-10-20，Flutter 3.35.3，本机合成数据，没有连 Firebase 正式环境）。

`tool/ci_flutter_tests.sh` 六套：

| 套 | 结果 |
|---|---|
| phase A (default build) | `+763 ~67: All tests passed!` |
| phase B arm gating（含新测试，两组） | `+408 ~9: All tests passed!` |
| phase B arm B pages | `+206 ~10: All tests passed!` |
| memory v1 client | `+18: All tests passed!` |
| rule template replies (switch only) | `+31 ~2: All tests passed!` |
| rule template replies on | `+31 ~2: All tests passed!` |

- `test/reminiscence_v2_test.dart`：Phase B 构建 28 条全过；默认构建 19 条过、9 条规则组用例跳过（默认构建里人人都是 Hybrid）。
- `test/reminiscence_v2_copy_test.dart`：10 条全过。
- `flutter analyze`：93 个提示，全部是原有的（0 个 error），新代码没有新增。
- 没跑 `tool/ci_backend_tests.sh`：这个分支没改 `functions/` 和 `firestore.rules`。

## 7. 截图

在 `docs/dev-reports/reminiscence-v2-shots/`。360 逻辑像素宽（2 倍图，720×1560），中文字体文泉驿，App 主题，合成数据，测试渲染（不是真机）。**Hybrid 组的追问、回应和小篇章正文是测试用的假模型写的句子，只为看版面，不代表真模型会这样写。** 文件名带 `rule`（规则组）或 `hybrid`。截图里的按钮字体是测试换上的，真机用系统字体。

| 文件 | 画面 |
|---|---|
| `01_opener_q1_*` | 第 1 周开场三个气泡 + 第 1 题、「唔想講」、输入框、左上「離開（會暫存）」 |
| `02_answer_fixed_line_rule` | 规则组答第 1 题 → 固定句 G1 → 第 2 题 |
| `02_answer_followup_hybrid` | Hybrid 答第 1 题 → 模型追问 |
| `03_reply_next_question_hybrid` | 答追问 → 模型回一句 → 第 2 题 |
| `04_skip_*` | 第 2 题撳「唔想講」→「冇問題，我哋講下一樣。」→ 第 3 题 |
| `05_q7_line_rule` | 规则组第 7 题那句 → 第 8 题 |
| `06_closing_*` | 结束句和「完成今個禮拜」 |
| `07_generating_hybrid` | Hybrid「整理緊…」 |
| `08_chapter_rating1_*` | 「第 1 章整理好喇」、标题、正文（规则组：小标题 + 原话） |
| `08b_rating1_scrolled_*` | 往下：评分第 1 题（1–7、两端文字、「唔評住」） |
| `09_rating2_*`、`10_rating3_*` | 评分第 2、3 题 |
| `11_after_rating_*` | 评完 |
| `12_edit_*` | 「改一改」：正文可改，「儲存」 |
| `12b_saved_more_button_*` | 已儲存，「再講多啲」 |
| `13_more_*` | 「再講多啲」一句和回应（规则组固定句），「重新整理」 |
| `14_chapters_list_*` | 我嘅人生小篇章 |
| `15_landing_*` | 回忆首页（「我嘅人生小篇章」入口） |
| `15b_landing_chapter_ready` | 回忆首页第 1 周显示「第 1 章整理好喇」 |
| `16_week2_opener_*` | 第 2 周开场 |
| `17_leave_other_page_first_note` | 其他陪伴者页「離開」和新的首次说明 |
| `18_leave_reminiscence_page` | 回忆页「離開（會暫存）」 |

## 8. 真机测试步骤

准备（只用 emulator 或测试帐号，合成内容）：

1. 先合并、部署服务器分支（Functions、提示词、Firestore 规则）。只测规则组时可以不等。
2. Firestore 控制台：`app_config/feature_flags` 加 `reminiscenceV2Enabled: true`、`leaveButtonV2Enabled: true`；Phase B 构建另要 `app_config/phase_b.sessionBriefPrV2Enabled: true`（看 Brief PR 卡）。
3. 两个测试帐号（`isTester`），一个 Hybrid 组、一个规则组（或开 `testerArmSwitchEnabled` 用「測試員工具」切组）。装这个分支的 Phase B 构建（`--dart-define=PHASE_B=true`）。重开 App 让开关生效。

规则组：

1. 首页 → 阿珍／阿伯 → 「童年同屋企」。看到三个开场气泡和第 1 题，左上「離開（會暫存）」。
2. 答第 1 题 → 「多謝你話我知，我哋講下一樣。」→ 第 2 题。第 2 题撳「唔想講」→「冇問題，我哋講下一樣。」。
3. 答第 3 题后撳「離開（會暫存）」。再进来：之前的对话都在，从第 4 题接着，没有再说开场。
4. 答完到第 8 题：第 7 题后是「嗰陣真係唔容易……我哋講最後一樣。」，第 8 题后直接结束句和「完成今個禮拜」。
5. 撳「完成今個禮拜」：马上出「第 1 章：童年同屋企」，每题小标题下是自己打的原话，第 2 题不出现。
6. 往下评三题（试一下「唔評住」），然后「改一改」改几个字 →「儲存」。
7. 「再講多啲」写一句 → 固定回一句 →「重新整理」→ 正文末尾多了「再講多啲」一段，要再评一次。
8. 回回忆首页 → 「我嘅人生小篇章」→ 第 1 章在，点进去可以再改。
9. 控制台核对：`users/{uid}/reminiscence_v2/week_1`、`reminiscence_chapters/week_1`（`source: rule`、`status: ready`）、`reminiscence_chapter_ratings`。Functions 日志里这个帐号**没有** `proxyDeepSeek` 调用。

Hybrid 组：

1. 同上进第 1 周。答第 1 题 → 模型追问一条（要具体，问时间、地点、人）→ 答 → 模型回一句（不提问）→ 第 2 题。
2. 第 2 题撳「唔想講」→ 固定句，没有追问。
3. 在追问出来后撳「離開（會暫存）」，再进来：追问还在，接着答。
4. 用一个童年不在香港的说法答（例如在汕头长大），看模型有没有假设香港（1020d 9 (3)）。
5. 答完 → 「完成今個禮拜」→「整理緊…」，可以离开。等推送「你嘅第 1 章整理好喇……」，点开 App 进回忆页：显示「第 1 章整理好喇」和正文。
6. 评分、改一改、再講多啲（模型回一句）、重新整理（再出「整理緊…」，好了再评一次）。
7. 控制台核对 `reminiscence_chapters/week_1`：App 写的字段和服务器写的字段（`finalText`、`version`、`rounds`、`flags`、`generatedAt`）。

两组都试：

- 某一题打「我真係想死」（合成）：出危机页，回来后不再出题；再进来从下一题接着。
- 只答两题就离开：Brief PR 卡不出；答够三题离开：出卡。
- 其他聊天页左上角是「離開」，第一次出新说明。
- 把两个开关关掉重开 App：回忆页回到旧样子，左上角回到「今日傾到呢度」。

## 9. 要 Junyu 定的事

文字（全部草稿，见 `docs/spec/copy/reminiscence-v2.md` 和截图）：

1. 开场三个气泡（第 1 周、第 2 至 4 周），照 1020d 第三节。「第{N}章」开场里没有空格，标题「第 N 章：主題」有空格，要不要统一。
2. 规则组 32 个小标题（开发写的）。
3. 固定句、结束句照 1020d；「再講多啲」规则组那句「收到，我記低咗。想再講可以繼續寫。」是开发写的。
4. 评分三题和两端文字照 1020d 第七节【待 Junyu 确认题目】；评分上方「想問你三條問題（1 至 7）」、「下一題」「完成」「唔評住」。
5. 「整理緊…你可以先離開，整理好會話你知。」「今次整理唔到。撳「重新整理」再試一次。」「（今個禮拜冇寫低內容。）」「完成咗一個禮拜，小篇章就會喺度。」「第 N 章整理好喇」「我嘅人生小篇章」「已儲存」。
6. 「離開（會暫存）」「離開」和首次说明【1020d 待 Junyu 确认】。

做法（开发先按默认做了）：

7. 有效会话：两组同一标准，这次进入答了至少 3 题（追问的回答、「唔想講」不算）【1020d 2 (5) 待确认】。
8. 规则组整理好不推送【1020d 6 (1) 待确认】。
9. 命中 `moderate_review`（离世、过去的困难）不停题；规则组第 1 至 6 题用 Z5 哀伤模板，第 7 题仍用第 7 题那句。只有 acute 和 `moderate_interrupt` 停题。
10. 第 8 题答完规则组不出固定句，直接结束句；第 8 题「唔想講」两组都直接结束句。
11. 「唔想講」也放在追问下面（撳了就出「冇問題，我哋講下一樣。」，不再回一句）。
12. 同意关时：服务器不存原话，原话存手机；小篇章请求仍带整周对话（建议服务器生成后清掉）。
13. 回忆首页「我嘅回憶」换成「我嘅人生小篇章」（旧的 80 字小结页不再有入口；开关开之前做过旧回忆的人，旧内容要从旧页看）。
14. 新的「離開」说明每台手机另出一次（看过旧说明的人也会看到）。
15. 规则组小篇章里「再講多啲」的内容排在最后，小标题「再講多啲」。
16. 小篇章显示时页面自动滚到标题；评分在正文下面，要往下拉。
17. 追问上限放在 `app_config/phase_b.reminiscenceFollowupsMax`（只在 Phase B 构建读）。
18. 决策编号（草稿 `docs/decisions/NNNN-reminiscence-v2-app.md`）。

## 10. 没做、要注意

- 第一节两个 bug（输入框提示、「AI 機械人」）不在这个分支；新页面的输入框提示直接用第一节改好的「記得幾多寫幾多。」。
- 提示词、小篇章 Cloud Function、推送、Firestore 规则、`build_info.g.dart` 在服务器分支。合并时两边按第 3.2 和第 5 节核对。
- Hybrid 组离线时：模型调用失败就用一般句继续（不排队重发，旧 Hybrid 页会排队）。
- 只开 `leaveButtonV2Enabled`、不开回忆 v2 时，旧回忆页左上角也显示「離開」，旧 Hybrid 页撳了会出总结页。建议两个开关一起开。
- 截图是测试渲染，不是真机；真机请按第 8 节走一遍。
