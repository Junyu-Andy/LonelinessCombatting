/// Spec §M8: a curated library of short articles, identical across arms.
/// Topics (from spec): what loneliness is and isn't; why it matters for
/// health; how thoughts affect feelings; small actions that help; talking
/// with family; finding community resources in HK.
///
/// Sprint 4 ships **15 articles** matching the Phase A Proposal §2.3
/// M8 target ("target 15 articles"); each is <400 words, fact-light and
/// framing-heavy.  Cultural advisor review remains a Phase A
/// prerequisite (Product Overview §10.2) before HREC submission.
///
/// Format guidelines (locked):
///   - Plain Cantonese-friendly Traditional Chinese on zh side
///   - English on en side
///   - No medical advice, no diagnostic claims, no commands
///   - End with an opening, not a directive ("如果你想…", "If you'd like…")
class EducationArticle {
  final String id;
  final String titleZh;
  final String titleEn;
  final String bodyZh;
  final String bodyEn;
  const EducationArticle({
    required this.id,
    required this.titleZh,
    required this.titleEn,
    required this.bodyZh,
    required this.bodyEn,
  });
}

class EducationLibrary {
  const EducationLibrary();

  static const articles = <EducationArticle>[
    EducationArticle(
      id: 'what_loneliness_is',
      titleZh: '孤獨感係咩？',
      titleEn: 'What is loneliness?',
      bodyZh: '''
孤獨感唔係「一個人」嘅意思。一個人都可以感到平靜；身邊好多人都可以好孤獨。

研究上有兩種：
1. 情感上嘅孤獨 — 覺得冇人真正了解自己。
2. 社交上嘅孤獨 — 覺得自己冇屬於邊個圈子。

呢個感覺好真實，但唔代表「你有問題」。佢係一個信號，話你嘅關係或者意義感需要少少照顧。

慢慢嚟。一個小行動，已經足夠。
''',
      bodyEn: '''
Loneliness is not the same as being alone. You can feel calm by
yourself. You can also feel deeply lonely in a crowded room.

Researchers describe two kinds:
1. Emotional loneliness — feeling no one truly understands you.
2. Social loneliness — feeling you don't belong to a group.

It is a real feeling, but it doesn't mean something is wrong with you.
It's a signal that your relationships or sense of meaning need a little
care.

There's no rush. One small action is enough.
''',
    ),
    EducationArticle(
      id: 'thoughts_and_feelings',
      titleZh: '諗法點樣影響感覺',
      titleEn: 'How thoughts shape feelings',
      bodyZh: '''
有時，一個諗法浮現，跟住個情緒就跟住嚟。

例：「打畀阿女只會煩到佢。」呢句一諗，可能會覺得攰、無力，跟住就唔打喇。

但呢句係一個諗法，唔一定係事實。同一個情境，可以有另一個諗法：
「阿女可能都希望聽到我聲。」

呢個唔係「諗開心啲」就解決。但係將諗法當作一個「假設」，可以畀自己一個小空隙，
喺諗法同感覺之間。

如果你想試下，可以喺 app 入面用「檢視一個諗法」呢個工具。
''',
      bodyEn: '''
Sometimes a thought arrives and a feeling follows.

For example: "Calling my daughter would just bother her." That single
thought can quietly leave us feeling tired and unable to call.

But it is a thought, not a fact. The same moment can hold another
thought: "Maybe she'd like to hear my voice."

This isn't about "thinking positive". Treating a thought as a hypothesis
just gives you a tiny gap between the thought and the feeling.

If you'd like to try, the "Examine a worry" tool inside this app walks
you through it gently.
''',
    ),
    EducationArticle(
      id: 'small_actions_help',
      titleZh: '為咩小行動有用',
      titleEn: 'Why small actions help',
      bodyZh: '''
當人覺得孤獨，大件事 — 約飯局、搬屋、報團 — 通常會覺得太遠、太重。

但研究發現：小行動嘅累積效果，係改善孤獨感最穩定嘅方法。

「小」嘅標準：
- 唔使準備
- 唔使等別人答應
- 5-10 分鐘可以做
- 唔成功都唔會覺得自己失敗

例如：傳一句短訊。落樓散下步。錄個語音畀仔女。

每個小行動，都係一個訊號，提醒自己：「我仲可以動。」
''',
      bodyEn: '''
When loneliness is heavy, big things — dinners, moves, joining a group
— tend to feel too far and too much.

Research keeps finding the same thing: small actions, repeated, are the
most reliable way to ease loneliness.

What counts as small:
- No preparation needed.
- No one else has to say yes first.
- Doable in 5–10 minutes.
- "Failure" doesn't actually feel like failure.

Send a short message. Take a walk downstairs. Record a voice note for
a child or grandchild.

Each small action is a quiet reminder to yourself: "I can still move."
''',
    ),
    EducationArticle(
      id: 'hk_resources',
      titleZh: '香港邊度可以搵幫手',
      titleEn: 'Where to find help in Hong Kong',
      bodyZh: '''
有時，自己一個處理唔嚟。呢個唔係軟弱 — 係懂得搵資源。

24 小時情緒支援熱線：
- 撒瑪利亞會：2896 0000
- 生命熱線：2382 0000

長者中心（部分區）：
- 香港老人權益促進會
- 賽馬會長者中心
- 區內社會福利署綜合家庭服務中心

緊急情況：撥 999。

如果你想，呢個 app 嘅「危機支援」入面有完整列表。
''',
      bodyEn: '''
Some days are too much to carry alone. Reaching out isn't weakness —
it's knowing the map.

24-hour emotional support hotlines:
- Samaritans Hong Kong: 2896 0000
- Suicide Prevention Services: 2382 0000

Elder centres (across districts):
- Hong Kong Association for Senior Citizens
- Jockey Club elder centres
- District-level SWD integrated family service centres

In an emergency: call 999.

The "Crisis Help" page in this app has the full list whenever you need it.
''',
    ),
    EducationArticle(
      id: 'why_loneliness_matters_health',
      titleZh: '點解孤獨會影響身體',
      titleEn: 'Why loneliness matters for the body',
      bodyZh: '''
研究人員留意到，長期感到孤獨嘅人，身體會出現一啲變化：
- 瞓得唔深
- 血壓有時較高
- 容易覺得攰

呢啲唔係「諗多咗」。身體確實會跟住情緒走。

不過反過嚟都一樣：當生活入面多咗一啲被了解嘅時刻、多咗一啲小行動，呢啲指標可以慢慢回返。

唔需要一次過大改變。一個禮拜，多一次主動嘅小聯絡，已經算係照顧緊自己嘅身體。
''',
      bodyEn: '''
Researchers have noticed that people who feel lonely for long periods
sometimes show small changes in the body:
- Lighter, less restful sleep
- Slightly higher blood pressure on some days
- Easier-than-usual tiredness

This isn't imagined. The body really does follow the heart.

The reverse is also true. When life starts to hold more moments of
feeling understood, more small actions, these signs can ease.

You don't need a complete change. One more deliberate small contact a
week is already taking care of your body.
''',
    ),
    EducationArticle(
      id: 'sleep_and_loneliness',
      titleZh: '瞓得唔好同孤獨嘅關係',
      titleEn: 'Sleep and loneliness',
      bodyZh: '''
有人話：「白天唔覺，夜晚先覺孤獨。」其實好多人都係咁。

夜晚靜咗，諗法會大聲啲。
身體攰，但個腦轉唔停。
有時翻來覆去，更加覺得自己一個。

呢個唔係軟弱。係夜晚嘅特性。

如果你瞓唔到：
- 唔好強迫自己即刻瞓著
- 開盞細燈，做啲輕嘅事，例如聽歌或者翻新照片
- 第二日如果攰，畀自己空間休息

唔好覺得「瞓唔到」就一定要做啲咩。安靜陪自己一陣，都係一種休息。
''',
      bodyEn: '''
Some people say: "I don't notice it during the day — only at night."
Many do.

At night, things go quiet and thoughts get louder. The body is tired
but the mind keeps turning. Tossing and turning makes the feeling of
being alone sharper.

This isn't weakness. It's what nights do.

If you can't sleep:
- Don't force yourself to fall asleep
- Turn on a soft light, do something gentle — listen to music, look at
  old photos
- If you're tired the next day, give yourself space to rest

"Can't sleep" doesn't always need a fix. Sitting quietly with yourself
is also rest.
''',
    ),
    EducationArticle(
      id: 'talking_with_family',
      titleZh: '同屋企人開口',
      titleEn: 'Opening up with family',
      bodyZh: '''
唔少長者話：「冇嘢同佢哋講」、「驚煩到佢哋」。

呢個諗法好真實。同時又係一個諗法，唔係事實。

開口唔一定要講「大件事」。可以由細節開始：
- 「我尋日喺街市見到舊朋友。」
- 「最近個天令我諗起爸爸。」
- 「我而家覺得有少少悶。」

你唔需要解釋自己嘅情緒。將真實嘅一句話寄出去，已經係一個橋樑。

如果對方反應冷淡，唔代表你做錯。你已經試咗。
''',
      bodyEn: '''
Many older adults say: "I have nothing to talk about with them" or "I
don't want to bother them."

That thought is real. It's also just a thought.

Opening up doesn't have to mean a "big topic". A small detail is enough:
- "I saw an old friend at the market yesterday."
- "The weather lately reminds me of my father."
- "I'm feeling a little dull right now."

You don't need to explain your feelings. Sending one true sentence is
itself a bridge.

If the other person seems distant, it doesn't mean you did anything
wrong. You already tried.
''',
    ),
    EducationArticle(
      id: 'friendship_later_life',
      titleZh: '老咗點樣交朋友',
      titleEn: 'Friendship in later life',
      bodyZh: '''
有人話：「呢個年紀邊度交到朋友？」

研究發現一件事 — 上咗年紀後，新朋友通常喺三個情境出現：
1. 重複嘅地方（茶餐廳、街市、公園、社區中心）
2. 一齊做嘅事（行山、做義工、做手工）
3. 已有朋友嘅朋友（一頓飯、一個介紹）

朋友唔一定要好深。一個「點頭朋友」都已經減少孤獨。

如果你諗起一個曾經認識嘅人，可以發一個短訊，唔需要解釋好多。「諗起你」三個字，已經夠。
''',
      bodyEn: '''
"How do you make new friends at this age?"

Studies notice that later in life, new friendships tend to grow in
three places:
1. Repeated locations (cha chaan tengs, markets, parks, community
   centres)
2. Doing something together (walking, volunteering, crafts)
3. Friends-of-friends (a meal, an introduction)

Friendships don't have to be deep. A "nod-and-smile friend" already
softens loneliness.

If someone you once knew comes to mind, you can send a short message.
You don't need to explain much. "Thinking of you" is enough.
''',
    ),
    EducationArticle(
      id: 'pets_comfort',
      titleZh: '寵物對情緒嘅作用',
      titleEn: 'Pets and emotional comfort',
      bodyZh: '''
有寵物嘅長者通常話：「佢識聽我講嘢。」

研究確實顯示，照顧一隻動物，可以：
- 多咗每日嘅小規律（餵食、散步）
- 多咗身體接觸（摸毛、抱）
- 多咗一個唔需要解釋嘅伴侶

但養寵物都有實際考慮 — 體力、住屋、長遠安排。

如果而家唔適合養，可以：
- 喺公園同流浪貓打招呼
- 探親戚或鄰居嘅寵物
- 睇下動物嘅短片

呢啲都係真實嘅小慰藉。
''',
      bodyEn: '''
Older adults with pets often say: "He knows how to listen."

Research does find that caring for an animal can:
- Add small daily routines (feeding, walking)
- Add physical touch (stroking, holding)
- Add a companion who needs no explanations

Pets also come with real considerations — energy, housing, long-term
arrangements.

If having a pet doesn't fit your life now, you can:
- Greet stray cats at the park
- Visit a relative or neighbour's pet
- Watch short animal videos

These count as real small comforts.
''',
    ),
    EducationArticle(
      id: 'grief_and_loneliness',
      titleZh: '哀傷同孤獨',
      titleEn: 'When grief meets loneliness',
      bodyZh: '''
失去咗一個重要嘅人之後，「孤獨」呢個字嘅意思會變。

唔再係「冇人陪」，而係「冇咗嗰個人」。

呢個感覺有自己嘅時間。
- 早期：可能日夜都有
- 中期：突然喺一首歌、一條街、一道菜出現
- 之後：仲喺度，但唔再淹冇你

冇所謂「應該幾耐」。
冇所謂「應該點樣」。

如果你想記住個人：
- 寫一封冇寄出嘅信
- 喺特別日子準備一份佢鍾意嘅食物
- 同識佢嘅人講起佢

記得佢，唔係令你停留咗，係令你帶住佢繼續行。
''',
      bodyEn: '''
After you lose someone important, the word "lonely" changes meaning.

It's no longer "no one is here." It's "that person is not here."

The feeling has its own timeline:
- Early on: it may be there day and night
- Later: it shows up suddenly through a song, a street, a dish
- Eventually: still there, but no longer drowning you

There's no "right length of time." No "right way."

If you want to hold them:
- Write a letter you don't send
- Prepare a food they loved on a special day
- Speak about them with people who knew them

Remembering them isn't staying behind. It's carrying them forward.
''',
    ),
    EducationArticle(
      id: 'mh_jong_bo_fan_yan',
      titleZh: '「唔好麻煩人」呢個諗法',
      titleEn: 'The "don\'t trouble anyone" mindset',
      bodyZh: '''
香港人好多時帶住一句：「唔好麻煩人。」

呢句話有佢嘅好 — 體諒、自立、有禮貌。

但長期帶住佢生活，可能會：
- 唔好意思開口要求幫手
- 唔好意思接受別人嘅關心
- 慢慢變成「冇人理我」嘅感覺

其實，俾人幫一啲小事，反而拉近距離。對方覺得被需要、被信任。

下次有人問「要唔要幫手？」，可以試下答「要，唔該」。
你會發現，呢個唔係麻煩。係互相。
''',
      bodyEn: '''
Many Hong Kongers carry the line: "Don't trouble anyone."

There's value in it — consideration, independence, politeness.

But carried for too long, it can mean:
- Hesitating to ask for help
- Brushing off other people's care
- Slowly turning into "no one looks after me"

Letting someone help with a small thing actually draws people closer.
They feel needed, trusted.

Next time someone asks "Do you need help?", try answering: "Yes,
please."

You'll find it isn't a burden. It's mutual.
''',
    ),
    EducationArticle(
      id: 'one_small_routine',
      titleZh: '建立一個小習慣',
      titleEn: 'Building one small routine',
      bodyZh: '''
情緒好嘅日子，靠靈感。情緒差嘅日子，靠習慣。

一個小習慣，唔需要動力，自己會浮上嚟。

點樣設計：
- 揀一個固定時間（早餐前、午飯後、瞓覺前）
- 揀一件 5 分鐘以內嘅事（沖一杯茶、行落街、寫一句嘢）
- 連續做 7 日

第 8 日，你會發現自己會自動做。

慢慢加多個。一個月後，你會有 2-3 個錨點托住你嘅一日。

呢啲唔係「自律」。係仁慈地對自己。
''',
      bodyEn: '''
Good days run on inspiration. Hard days run on habit.

A small routine doesn't need motivation. It surfaces on its own.

How to design one:
- Pick a fixed time (before breakfast, after lunch, before bed)
- Pick a 5-minute act (brewing tea, walking downstairs, writing one
  sentence)
- Repeat for 7 days

By day 8, you'll notice you do it without thinking.

Slowly add another. After a month you'll have 2–3 anchors holding up
your day.

This isn't "self-discipline". It's being kind to yourself.
''',
    ),
    EducationArticle(
      id: 'tired_body_lonely_mind',
      titleZh: '身體攰，但個心覺得孤獨',
      titleEn: 'Tired body, lonely mind',
      bodyZh: '''
有時你會覺得：「我攰到唔想動，但我又唔想一個人。」

呢兩個感覺睇落矛盾，其實成日同時出現。

幾個方法：
- 唔需要強迫自己出門。約一個熟人，喺屋企飲杯茶
- 打個電話／視像，唔需要傾耐
- 聽電台、收音機，有人聲已經幫到
- 寫一段語音畀仔女或者朋友

「陪伴」唔一定要面對面。
「動」唔一定要好大件事。
細微嘅、輕鬆嘅，已經夠。
''',
      bodyEn: '''
Sometimes you feel: "I'm too tired to move, but I don't want to be
alone."

These two feelings look contradictory. They often arrive together.

A few ways:
- You don't have to go out. Invite someone close over for tea
- Make a short phone or video call — it doesn't need to be long
- Turn on the radio or a podcast; another voice can help
- Record a short voice note for your child or a friend

"Company" doesn't have to mean face-to-face.
"Action" doesn't have to mean a big thing.
Small and light is enough.
''',
    ),
    EducationArticle(
      id: 'saying_yes_when_unsure',
      titleZh: '唔肯定都應承下',
      titleEn: 'Saying yes when you\'re not sure',
      bodyZh: '''
當人覺得孤獨，被邀請嘅時候反而會諗：「都係算啦。」

呢個其實係孤獨自我延續嘅一個小機制：
- 諗：「去都唔好玩」
- 唔去
- 之後更加覺得「我冇朋友」

唔代表你每次都要應承。
但有時，唔肯定都應承下，反而會發現自己唔似預期咁攰。

幾個提議：
- 設定時間限制（「我可以去半個鐘」）
- 帶定後備計劃（如果想走，可以走）
- 提醒自己：唔好玩都係資料，可以幫你下次決定

每應承一次，你就比孤獨少咗一格話事權。
''',
      bodyEn: '''
When loneliness is heavy, an invitation often gets answered with:
"Maybe not today."

This is one of the quiet ways loneliness keeps itself going:
- Think: "It won't be fun anyway"
- Don't go
- Afterwards feel: "I have no friends"

You don't have to say yes every time.
But sometimes, saying yes when you're not sure turns out lighter than
you expected.

A few helpers:
- Set a time limit ("I can stay half an hour")
- Have an exit plan ready (you can leave any time)
- Remind yourself: "Not fun" is information — useful for next time

Every yes takes a little ground back from loneliness.
''',
    ),
    EducationArticle(
      id: 'reading_and_feeling_less_alone',
      titleZh: '睇書同唔覺孤獨',
      titleEn: 'Reading and feeling less alone',
      bodyZh: '''
有人話：「一本好書，似一個陪我嘅人。」

研究發現，睇故事、回憶錄、人物傳記，會喺腦入面開啟「社交想像」嘅區域 — 即係你個腦會當一個唔識嘅人物，係一個朋友。

呢個唔係幻覺。係人類嘅一個自然能力。

如果你想試：
- 揀一本你熟悉嘅作者
- 唔需要一次睇好多 — 一日一段
- 揀一個固定地方，譬如窗邊嘅椅子，令呢個動作有畫面

書唔會代替人。但喺孤獨嘅時候，佢可以幫你保持「我同呢個世界連繫緊」嘅感覺。
''',
      bodyEn: '''
Some people say: "A good book is like a companion."

Research finds that reading stories, memoirs, biographies activates the
social-imagination parts of the brain — your mind treats an unmet
character as a kind of friend.

This isn't an illusion. It's a natural human capacity.

If you'd like to try:
- Pick an author you already love
- You don't need to read much — one passage a day is enough
- Choose a fixed spot, like a chair by the window, so the act has an
  image attached to it

Books don't replace people. But on lonelier days, they can help you
keep the feeling of "I'm still connected to the world."
''',
    ),
  ];

  static EducationArticle? byId(String id) {
    for (final a in articles) {
      if (a.id == id) return a;
    }
    return null;
  }
}
