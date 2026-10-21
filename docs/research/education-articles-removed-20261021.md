# 「讀少少」旧文章已删除（2026-10-21）

结论：10/21 起「讀少少」只剩 14 篇小讀本，原来的 15 篇旧文章从 App 删除（decisions-log 10/21 第 133 条 (1)）。以前留下的 `article_qa` 记录和 `m8_article_opened` 事件不动，分析时用下表对照文章编号。

怎样分辨记录来自哪里：

- 旧文章的问答：`articleId` 是下表的编号本身，模块名是 `m8_education_<编号>`。
- 小讀本的问答：`articleId` 是 `reader_<小讀本编号>`。
- 注意：`thoughts_and_feelings` 既是旧文章编号，也是一篇小讀本的编号。不带 `reader_` 的是旧文章，带 `reader_` 的是小讀本。

| 编号（id） | 中文标题 | 英文标题 |
| --- | --- | --- |
| what_loneliness_is | 孤獨感係咩？ | What is loneliness? |
| thoughts_and_feelings | 諗法點樣影響感覺 | How thoughts shape feelings |
| small_actions_help | 為咩小行動有用 | Why small actions help |
| hk_resources | 香港邊度可以搵幫手 | Where to find help in Hong Kong |
| why_loneliness_matters_health | 點解孤獨會影響身體 | Why loneliness matters for the body |
| sleep_and_loneliness | 瞓得唔好同孤獨嘅關係 | Sleep and loneliness |
| talking_with_family | 同屋企人開口 | Opening up with family |
| friendship_later_life | 老咗點樣交朋友 | Friendship in later life |
| pets_comfort | 寵物對情緒嘅作用 | Pets and emotional comfort |
| grief_and_loneliness | 哀傷同孤獨 | When grief meets loneliness |
| mh_jong_bo_fan_yan | 「唔好麻煩人」呢個諗法 | The "don't trouble anyone" mindset |
| one_small_routine | 建立一個小習慣 | Building one small routine |
| tired_body_lonely_mind | 身體攰，但個心覺得孤獨 | Tired body, lonely mind |
| saying_yes_when_unsure | 唔肯定都應承下 | Saying yes when you're not sure |
| reading_and_feeling_less_alone | 睇書同唔覺孤獨 | Reading and feeling less alone |

文章全文可以在 git 里找回：`lib/features/education/data/education_library.dart`（删除前最后一版在 main 的 36d12ab）。
