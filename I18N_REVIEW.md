# I18N Review — Cantonese → English additions

This document lists every English translation added alongside existing Cantonese UI strings in the five priority files. Translations target a Hong Kong elderly audience, using simple and warm phrasing that mirrors the register of the existing Cantonese. The Cantonese strings are kept verbatim; only the `isEn ?` English branch was added (or its option-list equivalent). LLM system prompts, code comments, Firestore keys, analytics names, and test fixtures were not touched.

## Files modified

- `lib/features/onboarding/presentation/pages/intake_flow_page.dart`
- `lib/features/crisis/presentation/pages/emergency_support_page.dart`
- `lib/features/assessment/presentation/pages/agent_diff_page.dart`

The other two priority files already had complete `isEn ?` coverage for every user-visible string and required no edits:

- `lib/features/onboarding/presentation/pages/agent_onboarding_page.dart` — already bilingual.
- `lib/features/thought_exercise/presentation/thought_exercise_page.dart` — already bilingual.

---

## intake_flow_page.dart

### Part 2 — Important people / reconnect people

| Cantonese | English |
|---|---|
| 生命中重要嘅人 | People who matter to you |
| 你最重視嘅人係邊幾個？（最多 5 位，可以跳過） | Who are the people you care about most? (Up to 5, you can skip) |
| 聯絡頻率 | How often in touch |
| + 加一位重要嘅人 | + Add someone important |
| 聯絡頻率（可選） | How often in touch (optional) |
| 想重新聯絡嘅人 | People you would like to reconnect with |
| 有冇人你希望可以重拾聯絡？（最多 3 位，可以跳過） | Is there anyone you hope to reconnect with? (Up to 3, you can skip) |
| 阻礙原因 | What is in the way |
| + 加一位想聯絡嘅人 | + Add someone to reconnect with |
| 係咩令你唔容易聯絡？（可選） | What makes it hard to reach out? (optional) |
| 跳過 | Skip |
| 儲存並繼續 | Save and continue |

### Add-a-person dialog

| Cantonese | English |
|---|---|
| 加一個人 | Add a person |
| 姓名 / 稱呼 | Name or what you call them |
| 關係（例如：女兒、舊朋友） | Relationship (e.g. daughter, old friend) |
| 取消 | Cancel |
| 加入 | Add |

### Part 3 — Typical day / on my mind

| Cantonese | English |
|---|---|
| 你平時係點過一日？ | What does a typical day look like? |
| （可選 · 可以跳過） | (Optional · you can skip) |
| 早上通常做咩？ | What do you usually do in the morning? |
| 下晝通常做咩？ | What about the afternoon? |
| 夜晚通常做咩？ | And in the evening? |
| 而家係咩喺你心入面？ | What is on your mind right now? |
| 唔一定要答，係可選嘅。 | You do not have to answer — this is optional. |
| 有咩想講都可以寫喺度… | Anything you want to share, write it here… |

### Part 4 — Activities & topics

Section text:

| Cantonese | English |
|---|---|
| 你平時鍾意做啲咩消遣？ | What do you like to do for fun? |
| 請寫低其他消遣… | Please write your other hobbies… |
| 你有興趣講開邊啲話題？ | What topics do you enjoy talking about? |
| 請寫低其他話題… | Please write your other topics… |

Activity chip options:

| Cantonese | English |
|---|---|
| 睇電視睇劇 | Watching TV / drama |
| 聽收音機 | Listening to the radio |
| 睇報紙睇書 | Reading newspapers / books |
| 打麻雀玩啤牌 | Mahjong / card games |
| 打太極晨運 | Tai chi / morning exercise |
| 散步行山 | Walks / hiking |
| 種花種菜照顧植物 | Gardening / caring for plants |
| 煮嘢食 | Cooking |
| 宗教活動 | Religious activities |
| 做義工 | Volunteering |
| 同朋友飲茶食飯 | Yum cha / meals with friends |
| 同孫仔孫女玩 | Playing with grandchildren |
| 聽歌唱歌 | Listening to / singing songs |
| 手工 | Handicrafts |
| 其他 | Other |

Topic chip options:

| Cantonese | English |
|---|---|
| 香港舊時嘅嘢香港歷史 | Old Hong Kong / HK history |
| 飲食煮餸 | Food and cooking |
| 屋企人嘅故事 | Family stories |
| 種植動植物 | Plants and animals |
| 你嗰個年代嘅音樂戲曲電影 | Music, opera and films from your era |
| 健康養生 | Health and well-being |
| 時事新聞 | News and current events |
| 宗教信仰人生價值 | Faith and life values |
| 旅行 | Travel |
| 運動 | Sports |
| 其他 | Other |

### Part 5 — Life chapters & avoid topics

| Cantonese | English |
|---|---|
| 你想傾下人生嘅邊個階段？ | Which part of your life would you like to talk about? |
| 細個嘅時候 | Childhood |
| 讀書嘅日子 | School days |
| 出嚟做嘢返工嘅日子 | Starting work / working life |
| 拍拖結婚 | Dating and marriage |
| 湊仔女嘅日子 | Raising children |
| 搬屋移民搬區 | Moving home / migrating |
| 香港大事 | Big moments in Hong Kong |
| 呢啲年發展嘅興趣或者技能 | Interests or skills picked up over the years |
| 旅行經驗 | Travel memories |
| 我寧願講返而家唔太想再諗以前 | I'd rather talk about now, not the past |
| 有冇唔想提起嘅話題？ | Anything you would rather not talk about? |
| 係可選嘅。你寫落嘅，我哋嘅 AI 都唔會主動提起。 | This is optional. Whatever you write here, our AI won't bring up on its own. |
| 例如：某啲家庭事，或者某段時期… | For example: certain family matters, or a particular period… |

### Part 6 — Input mode & preferred times

| Cantonese | English |
|---|---|
| 你喜歡點樣同 AI 溝通？ | How do you like to talk with the AI? |
| 必填 | Required |
| 主要打字 | Mostly typing |
| 主要用語音 | Mostly voice |
| 兩樣都差唔多 | About the same |
| 暫時未知 | Not sure yet |
| 你通常幾時最方便用呢個 app？ | When is it most convenient to use this app? |
| 朝早 | Morning |
| 晏晝 | Midday |
| 下晝 | Afternoon |
| 夜晚 | Evening |
| 瞓覺之前 | Before bed |
| 冇固定時間 | No fixed time |
| 下一步 | Next |

### Done page

| Cantonese | English |
|---|---|
| 多謝你答晒所有問題！ | Thank you for answering everything! |
| 我哋已經為你度身設定好一切。\n而家可以正式開始喇！ | We've set everything up for you.\nYou can get started now! |
| 開始使用 | Start |

---

## emergency_support_page.dart

| Cantonese | English |
|---|---|
| 即時支援 | Get help now |
| 如果你有不安嘅諗法 | If you are having upsetting thoughts |
| 可以打電話搵下面任何一個聆聽者傾下。如果你或者身邊嘅人有即時危險，請即刻撥 999 或者去最近嘅急症室。 | You can call any of the listeners below for a chat. If you or someone near you is in immediate danger, please call 999 right away or go to the nearest A&E. |
| 撥 999 | Call 999 |
| 24 小時情緒支援熱線 | 24-hour emotional support hotlines |
| 撒瑪利亞防止自殺會 | Samaritan Befrienders Hong Kong |
| 全日 24 小時 | 24 hours |
| 24 小時防止自殺熱線。 | 24-hour suicide prevention hotline. |
| 香港撒瑪利亞會（多語） | The Samaritans Hong Kong (multilingual) |
| 可以粵語、普通話或英語溝通。 | Cantonese, Mandarin or English available. |
| 醫管局精神健康專線 | Hospital Authority mental health hotline |
| 24 小時 | 24 hours |
| 香港醫院管理局精神科熱線。 | Hong Kong Hospital Authority psychiatric hotline. |
| 999 緊急服務 | 999 emergency services |
| 即時危險時請即刻撥打。 | Call right away if you are in immediate danger. |
| 你嘅信任聯絡人 | Your trusted contact |
| 等嚟緊再深呼吸幾下 | While you wait, take a few deep breaths |
| 現在可以試吓嘅幾個動作 | A few things you can try now |
| 坐落或者攰住牆，慢慢深呼吸三次。 | Sit down or lean against a wall, and slowly take three deep breaths. |
| 望下周圍，講出你見到嘅三樣嘢。 | Look around, and name three things you can see. |
| 飲一啖水，畀身體一啲時間放鬆。 | Drink a sip of water and give your body a moment to relax. |
| 撥電話或者傳訊息畀上面任何一個人。 | Call or text any of the people listed above. |
| 撥打 $number | Call $number |
| 未填電話 | No phone number |
| 仲未設定信任聯絡人。可以喺「設定 → 個人資料」入面填。 | No trusted contact yet. You can add one in Settings → Profile. |
| 請手動撥打 $number | Please dial $number manually |

---

## agent_diff_page.dart

| Cantonese | English |
|---|---|
| 夥伴評估 (第 N 週) | Companion check-in (Week N) |
| A 使用頻率 | A How often |
| B 性格印象 | B Personality |
| C 情境偏好 | C Situations |
| D 你想講 | D Your thoughts |
| 上個月你用咗以下夥伴幾多次？ | In the last month, how often did you use each companion? |
| 夥伴 | Companion |
| 完全冇用 | Not at all |
| 少少 | A little |
| 定期 | Regularly |
| 好頻繁 | Very often |
| 請為每個夥伴嘅性格評分（1=完全唔符合，5=非常符合） | Please rate each companion's personality (1 = not at all, 5 = very much) |
| 以下情況你會選擇邊個夥伴？ | In these situations, which companion would you choose? |
| 小欣 | Siu Yan |
| 阿珍／阿伯 | Ah Jan / Ah Bak |
| 通通 | Tung Tung |
| 都係 | Any of them |
| 仲有咩想補充？ | Anything else you would like to share? |
| 關於呢三個夥伴，你有咩感受、意見或者建議，都可以寫喺度。 | Any thoughts, feelings or suggestions about the three companions — you can write them here. |
| 可以寫低你嘅感受或者建議… | Write your thoughts or suggestions here… |
| 多謝你嘅評估！已經儲存。 | Thank you for the check-in! Your responses are saved. |
| 提交評估 | Submit |
