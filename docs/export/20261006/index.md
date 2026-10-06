# 干预内容原样导出（T3，2026-10-06）

**结论**：两组老人实际看到的内容、以及 Hybrid 组发给 AI 的全部 prompt，已从源码逐字导出到本目录，共 12 个文件。
关键数字：Hybrid 组 3 个陪伴者 persona + 12 个功能 prompt；规则组通通 20 条开场 + 10 类关键词 / 27 条话题回应 + 6 条通用回应，
社交建议 16 条，规则组**没有**每周小结模板；共用 4 周怀旧课程、15 篇文章、3 种推送；DJG 是 **6 条版**；App 内**没有** UCLA 题目。

**app 显示哪个语言**：`lib/app/app_settings.dart` 第 45 行 `englishEnabled = false`，locale 被强制为 `zh`。
所以凡有中英两版的内容，老人只看到中文（粤语）版；英文版一起导出，仅供参考。`app_zh_Hant_HK.arb` 编译进了 app 但从不被选用。
本目录涉及的内容都在 Dart / JS / txt / JSON 源码里，不在 ARB 文件里（ARB 只有导航、标题之类的界面文字）。

## 文件清单和条数

| 文件 | 组别 | 内容 | 条数 |
|---|---|---|---|
| [01-hybrid-agent-system-prompts.md](01-hybrid-agent-system-prompts.md) | Hybrid 组 | Hybrid 组：三个陪伴者的 system prompt | persona prompt 文件 3；App 端后备 persona（服务器读不到文件时才用） 4 |
| [02-hybrid-feature-prompts.md](02-hybrid-feature-prompts.md) | Hybrid 组 | Hybrid 组：各功能用到的 prompt | 调用 DeepSeek 的功能 prompt（不含三个 persona） 12 |
| [03-rule-agent-pools.md](03-rule-agent-pools.md) | 规则组 | 规则组：三个陪伴者的回应池和关键词规则 | 通通开场题库 20；通通话题类别（关键词规则） 10；通通话题回应 27；通通通用回应（没命中关键词时） 6；小欣签到 B 选择题 3；小欣签到 B 固定回应 1；阿珍/阿伯回忆 B 开场 4；首次介绍文字（`_firstIntroTexts`） 3 |
| [04-rule-activities-and-action-loop.md](04-rule-activities-and-action-loop.md) | 规则组 | 规则组：16 项活动建议池和 Action Loop 模板 | 社交建议池 16；Action Loop 选项 12；Action Loop 24 小时提醒模板 1 |
| [05-rule-weekly-summary.md](05-rule-weekly-summary.md) | 规则组 | 规则组：每周小结 | 规则组每周小结模板 0 |
| [06-shared-reminiscence-course.md](06-shared-reminiscence-course.md) | 两组共用 | 两组共用：主题式怀旧课程（M3） | 主题（周） 4；每周开场句 4 |
| [07-shared-education-articles.md](07-shared-education-articles.md) | 两组共用 | 两组共用：教育文章（M8） | 文章 15；带危机提示的文章 2 |
| [08-shared-thought-exercise.md](08-shared-thought-exercise.md) | 两组共用 | 两组共用：Thought Exercise（想法练习） | 练习栏目 5；强度评分 2 |
| [09-shared-push-notifications.md](09-shared-push-notifications.md) | 两组共用 | 两组共用：推送文案和时间表 | 服务器推送种类 3；排程任务（含不推送的） 6 |
| [10-shared-questionnaires.md](10-shared-questionnaires.md) | 两组共用 | 两组共用：App 内问卷题目和选项 | Brief PR 4；Weekly PR 12；每周孤独探针 1；ADA 特质 4；ADA 情境（只第 4 周） 5；ADA 使用频率题 3；ADA 开放题 1；PGIC 1；DJG 6；UCLA（App 内题目） 0；每日心情 1 |
| [11-shared-safety-and-fallback-copy.md](11-shared-safety-and-fallback-copy.md) | 补充 | 补充：安全回应、热线和 AI 失败时的后备文字 | 安全回应模板 6；AI 后备句 4 |
| [12-fixed-ui-copy.md](12-fixed-ui-copy.md) | 补充（按组） | 补充：老人可见的固定界面文字（按组） | 小欣签到开场白（Hybrid） 11；Action Loop 提问（Hybrid） 5；通通固定开场白（Hybrid） 3；阿珍/阿伯反思固定句（Hybrid） 5；onboarding 记忆告知（只 Hybrid） 1；转介卡文字（Hybrid） 1；安全弹窗按钮（两组） 3；孤单时段选项（两组） 9 |

每个文件开头都有「条数」表，写明每个数字是怎么数的。

## 导出方法

1. **定位**：读代码找出所有内容所在的文件和行号（先人工通读，再用两个只读检索代理交叉核对）。
2. **抽取**：用 Python 脚本按「文件 + 行号范围」或「整个文件」原样复制，放进代码块，每段上方写「来源：路径 第 X–Y 行」。
   没有任何内容是手打或改写的；中英文、注释、变量占位符（如 `$themeTitle`、`${…}`、`{{VARIANT_NAME}}`、`〈AGENT〉`）都保留原样。
   为了让审阅者看到上下文，Dart 页面的摘录会带一些界面代码；需要看的是引号里的文字。
3. **核对**：脚本最后把输出里的 136 段摘录逐一和源文件重新比对，全部一字不差才写出。
4. **数条数**：用脚本数源码里的列表项（如 `(id: 'tt` 、`SocialSuggestion(`、`EducationArticle(`、`DjgEsItem(`、`(zh:` 出现次数），
   个别是人工数的（如 Brief PR 的题卡、Action Loop 选项），每个数字的数法写在各文件的「条数」表里。
5. **代码版本**：导出的代码版本是 `27113ca`（分支 `docs/T3-export-20261006` 的起点）。它和 `main`（`475b796`）相比，`lib/`、`functions/`、`assets/` 没有任何差别，所以导出内容等于 `main` 当前的内容。
6. 生成脚本没有提交进仓库（只提交本目录）；如需重跑，可以按各文件的「来源」行号复核。

## 来源文件（SHA-256 前 16 位）

| 文件 | SHA-256 |
|---|---|
| `assets/config/llm_fallback_messages.json` | `2a495b99b4d715e5` |
| `docs/prompts/context_suffix_template.txt` | `a068c471634e6577` |
| `functions/index.js` | `4782da47e48592e4` |
| `functions/llm_flags.js` | `823215be978f1d56` |
| `functions/memory.js` | `b29d83ebd3c0a4df` |
| `functions/prompts/ah_jan_ah_bak_v1.txt` | `8efcae4cd46ba28f` |
| `functions/prompts/crisis_resources.json` | `b8b0d47c5739f82e` |
| `functions/prompts/safety_acknowledgements.json` | `96fd03c84e3ece63` |
| `functions/prompts/siu_yan_v1.txt` | `7f77797921ed3608` |
| `functions/prompts/tung_tung_v1.txt` | `251584dc7f1e503d` |
| `lib/core/agent_context/intake_memory_seeder.dart` | `33c1dd1d1010f688` |
| `lib/core/agent_context/rolling_summary_compiler.dart` | `49af34a59ec9dda9` |
| `lib/core/agents/agent_registry.dart` | `e324f597f555e4fe` |
| `lib/core/agents/persona_resolver.dart` | `44d932977f51c731` |
| `lib/core/config/phase_a_config.dart` | `38fc2980cc264258` |
| `lib/core/cross_referral/referral_suggestion_card.dart` | `6c37c980d6f5202a` |
| `lib/core/cross_referral/triggers_config.dart` | `55e5a5d3294f3597` |
| `lib/core/llm/agent_greeting_service.dart` | `f632870ecda30478` |
| `lib/core/llm/llm_gateway.dart` | `78a71e2f08c5341b` |
| `lib/core/memory/cross_module_memory.dart` | `fab578e1dd4e208f` |
| `lib/core/reminders/reminder_service.dart` | `0828ae0e5527f533` |
| `lib/core/safety/distress_detector.dart` | `079af7a774161450` |
| `lib/core/safety/distress_router.dart` | `628f3a283becb60f` |
| `lib/core/safety/safety_copy.dart` | `6df027aea43a8e2e` |
| `lib/core/safety/safety_overlay.dart` | `a5c6b4e4cb073dcd` |
| `lib/core/scheduling/pending_prompts_service.dart` | `4bb6639e57daf594` |
| `lib/core/survey/likert_scale.dart` | `331d1555e0321d34` |
| `lib/features/action_loop/presentation/pages/action_loop_arm_a_page.dart` | `443d4c83ad9742f5` |
| `lib/features/action_loop/presentation/pages/action_loop_arm_b_page.dart` | `915aa29c7a035cff` |
| `lib/features/action_loop/presentation/pages/action_loop_followup_page.dart` | `66c13c9ace894212` |
| `lib/features/action_loop/presentation/pages/action_loop_landing.dart` | `87b1c7ecc2c3664f` |
| `lib/features/adherence/presentation/widgets/missed_checkin_banner.dart` | `63a33a29c609e0c1` |
| `lib/features/agent_profile/data/agent_profile_content.dart` | `2c0a3389d60c53f7` |
| `lib/features/assessment/data/agent_diff_response.dart` | `bdf3e7347a1e3665` |
| `lib/features/assessment/data/djg_es_response.dart` | `a6e071aa3f6008b9` |
| `lib/features/assessment/presentation/pages/agent_diff_page.dart` | `bf5e7b0af216dd9c` |
| `lib/features/assessment/presentation/pages/djg_es_page.dart` | `e893618bb74f4405` |
| `lib/features/assessment/presentation/pages/pgic_page.dart` | `e4d2e007053d70c7` |
| `lib/features/auth/data/arm_assigner.dart` | `6a8608e8a6d41847` |
| `lib/features/auth/presentation/pages/login_page.dart` | `7e4d1e463b72f27d` |
| `lib/features/brief_pr/presentation/pages/brief_pr_page.dart` | `26b6d44dd6127ad6` |
| `lib/features/context/presentation/pages/check_in_arm_a.dart` | `af817bb36595e4cb` |
| `lib/features/context/presentation/pages/check_in_arm_b.dart` | `946dc65e2a96a7c9` |
| `lib/features/context/presentation/pages/check_in_shared.dart` | `584b53952e34087f` |
| `lib/features/curious_companion/data/tung_tung_rule_pool.dart` | `10e376e23fe41819` |
| `lib/features/curious_companion/data/tung_tung_rule_responder.dart` | `db640648a694d2ee` |
| `lib/features/curious_companion/presentation/pages/tung_tung_page.dart` | `69e8d381cc218dee` |
| `lib/features/education/data/education_library.dart` | `763de3fa35bdb0bf` |
| `lib/features/education/presentation/pages/education_article_page.dart` | `5c69cd3ed33c2e78` |
| `lib/features/education/presentation/pages/education_library_page.dart` | `e0473a8bc1d3b2fa` |
| `lib/features/loneliness_probe/presentation/loneliness_probe_page.dart` | `0d1d24b94b903e04` |
| `lib/features/my_story/data/my_story_progress.dart` | `040396abf428cc62` |
| `lib/features/onboarding/presentation/pages/agent_onboarding_page.dart` | `b924501db2d09861` |
| `lib/features/onboarding/presentation/pages/intake_flow_page.dart` | `6ca124c5d40bb903` |
| `lib/features/ppr/data/ppr_scale.dart` | `61785edecaa62338` |
| `lib/features/progress/presentation/pages/progress_page.dart` | `be177d423c197df5` |
| `lib/features/reflective_dialogue/data/negative_cognition_detector.dart` | `cea032001aeb4dd3` |
| `lib/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart` | `9a1aa873bbc5a39e` |
| `lib/features/reminiscence/data/reminiscence_themes.dart` | `14d0f73d21d10250` |
| `lib/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart` | `f6c7caf1e8dc7ef4` |
| `lib/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart` | `10e110a14c4a96b7` |
| `lib/features/reminiscence/presentation/pages/reminiscence_landing.dart` | `275c56688e94be12` |
| `lib/features/social_suggestions/data/suggestion_pool.dart` | `c29cfca6d8801f50` |
| `lib/features/social_suggestions/presentation/pages/social_suggestions_page.dart` | `73f9a20f81bbbce9` |
| `lib/features/thought_exercise/presentation/naming_thought_card.dart` | `d57fa69a2442f53a` |
| `lib/features/thought_exercise/presentation/thought_exercise_page.dart` | `a4ee8f21fb069fa9` |
| `lib/features/today/presentation/widgets/daily_mood_prompt.dart` | `12d2a7e31766ae00` |
| `lib/features/today/presentation/widgets/pending_prompts_banner.dart` | `4c614b51582caf21` |
| `lib/features/today/presentation/widgets/week1_nudge_banner.dart` | `6d35394278dbb920` |
| `lib/features/weekly_pr/data/weekly_pr_response.dart` | `3c7703ded366538a` |
| `lib/features/weekly_pr/data/weekly_pr_window.dart` | `a5e913f0377b041d` |
| `lib/features/weekly_pr/presentation/pages/weekly_pr_page.dart` | `a529b04b0971cf56` |
| `lib/l10n/app_en.arb` | `662baa475b4cb9ab` |
| `lib/l10n/app_zh.arb` | `8498930f129735d0` |
| `lib/theme/app_mood_encoding.dart` | `8b35030e760f0320` |

## 要带回研究侧的发现

导出时看到的、可能影响 HREC 附件、编码手册或组间差异清单的地方：

1. **通通规则组开场题库是 20 条，不是 16 条**。`tung_tung_rule_pool.dart` 第 31–33 行注释写「研究团队要删到 16 条」，第 12、13、15、17 条标了「待文化顾问审阅」，代码里还没删。
2. **回忆课程是 4 周 4 个主题**，但回忆入口页的介绍写「6 個主題、6 個禮拜」（`reminiscence_landing.dart`），两者不一致。
3. **DJG 是 6 条版**，措辞是粤语工作草稿（`djg_es_response.dart` 第 8–10 行写明要换成问卷 v1.3 正式文字）；选项是「係 / 多少啦 / 唔係」，和注释里的「是 / 多少 / 否」不同。
4. **App 内没有 UCLA 题目**，只有研究员在登录页输入基线总分（用于分层）。
5. **每周孤独探针**：页面写好了，但没有入口，开关默认关，老人看不到；服务器周日 09:00 的排程也不发推送。
6. **行动计划 24 小时提醒**只写进 Firestore，代码里没有发送它的部分，老人收不到。
7. **规则组没有反思（M5）、没有每周小结、没有个性化问候**；规则组签到和回忆是表单，没有对话回应。
8. **Hybrid 组首页个性化开场白只为阿珍/阿伯和通通生成**，没有小欣的版本（`agent_greeting_service.dart`）。
9. **「安全标记」没有 LLM prompt**：安全检测是关键词词库；「5 个 LLM 机制标记」是模型回复后用代码规则算的，不调用模型。
10. **心情文字只有一套在用**：首页、签到、每日心情都用「好差 / 差 / 麻麻地 / 幾好 / 好好」（`check_in_shared.dart`）。`app_mood_encoding.dart` 里的「好辛苦 / 差啲 / 一般 / 好 / 好開心」没有显示出来：进度图只用了它的颜色和形状（`progress_page.dart` 第 278–290 行）。
11. PGIC 写入的集合是 `pgic`，但数据模型注释（`pgic_response.dart` 第 3 行）写成 `pgic_responses`。
12. 旧版 PPR 量表（12 题 + 2 题）仍在代码里，只能从测试工具进入，参与者看不到。
13. 推送只有中文版、标题都是「陪住」；两组文案和时间完全相同。
14. **onboarding 记忆告知只给 Hybrid 组**（组间差异）：Phase B 记忆模式的用户在介绍三个夥伴时多看到一句「佢哋會記得你講過嘅嘢……你隨時可以喺「設定 → 我記得嘅嘢」睇返同刪走。」（`agent_onboarding_page.dart` 第 372–386 行）。规则组看不到。ICF 和组间差异清单要写进去。
