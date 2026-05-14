/// Spec §M8: a curated library of short articles, identical across arms.
/// Topics (from spec): what loneliness is and isn't; why it matters for
/// health; how thoughts affect feelings; small actions that help; talking
/// with family; finding community resources in HK.
///
/// Sprint 3 ships 4 seed articles, each <400 words. The full ~15 will be
/// authored with the clinical consultant. Content here is meant to be
/// editable — fact-light, framing-heavy.
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
  ];

  static EducationArticle? byId(String id) {
    for (final a in articles) {
      if (a.id == id) return a;
    }
    return null;
  }
}
