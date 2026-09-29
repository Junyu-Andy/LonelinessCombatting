/// Rule-based Tung Tung replies for Arm B (Phase B).
///
/// Arm B keeps the same chat surface as Arm A but replies come from this
/// fixed, version-locked template set instead of an LLM: the user's turn
/// is matched against topic keyword lists and a pre-written Cantonese
/// reply is picked deterministically. A template never quotes the user's
/// words back — reading and reusing the user's specific content is one of
/// the LLM-unique mechanisms (`specific_content_engagement`) that Arm B
/// must not have.
///
/// Every few turns the reply carries the next opener from
/// [TungTungRulePool] so the conversation keeps moving.
///
/// Telemetry: callers log `tung_tung_rule_reply` with [RuleReply.id] and
/// [version] so analysts can join template × version.
///
/// All strings need cultural-advisor review before recruitment, same as
/// the opener pool.
library;

import 'tung_tung_rule_pool.dart';

class RuleReply {
  /// Stable template id, e.g. `food_2` or `generic_5`.
  final String id;
  final String zh;
  final String en;

  /// The opener appended to this reply, if any (for telemetry).
  final String? openerId;

  const RuleReply({
    required this.id,
    required this.zh,
    required this.en,
    this.openerId,
  });

  String text({required bool isEn}) => isEn ? en : zh;
}

typedef _Template = ({String zh, String en});

class _Topic {
  final String id;
  final List<String> keywords;
  final List<_Template> replies;
  const _Topic(this.id, this.keywords, this.replies);
}

class TungTungRuleResponder {
  const TungTungRuleResponder._();

  /// Bump whenever a keyword list or template changes.
  static const String version = '2026-09-v1';

  /// A new opener is appended on every [openerEvery]-th user turn.
  static const int openerEvery = 3;

  // Order matters: the first topic whose keyword appears wins. Health
  // sits first so 食藥 / 睇醫生 never get a food or outing template. Its
  // replies stay neutral — Tung Tung gives no medical advice in either arm.
  static const List<_Topic> _topics = [
    _Topic('health', [
      '藥', '醫生', '醫院', '覆診', '診所', '病', '痛', '唔舒服', '血壓',
      'doctor', 'hospital', 'medicine', 'sick', 'pain', 'clinic',
    ], [
      (zh: '身體嘅事真係要好好照顧。有咩需要，記得同醫生或者屋企人講。',
        en: 'Health matters deserve care. If you need anything, do tell your doctor or family.'),
      (zh: '辛苦你喇。今日其他時間，你想做啲咩令自己舒服啲？',
        en: 'That sounds tiring. What would you like to do later today to feel a bit better?'),
    ]),
    _Topic('food', [
      '食', '飲茶', '茶樓', '點心', '煮', '餸', '飯', '麵', '粥', '湯',
      '茶餐廳', '奶茶', '街市', 'food', 'eat', 'cook', 'dim sum', 'tea',
    ], [
      (zh: '講起食嘢，真係好多回憶。你平時鍾意自己煮，定係出去食多啲？',
        en: 'Food brings back so many memories. Do you usually cook, or eat out more?'),
      (zh: '食嘢真係生活一大樂趣。有冇一樣嘢，你食極都唔厭？',
        en: 'Food is one of life\'s pleasures. Is there something you never get tired of?'),
      (zh: '聽落好正。你覺得而家同以前嘅味道，有冇唔同咗？',
        en: 'Sounds lovely. Do you think flavours are different now compared with before?'),
    ]),
    _Topic('music', [
      '歌', '音樂', '粵曲', '唱', '收音機', '電台', '聽歌', 'music', 'song',
      'sing', 'radio',
    ], [
      (zh: '音樂真係好神奇，一首歌可以帶人返去好耐之前。你最常喺咩時候聽歌？',
        en: 'Music is magical — one song can take you back years. When do you usually listen?'),
      (zh: '好歌真係百聽唔厭。你鍾意自己唱，定係淨係聽？',
        en: 'A good song never gets old. Do you like singing along, or just listening?'),
      (zh: '有啲歌一響起就會記起某個時候。你有冇咁樣嘅歌？',
        en: 'Some songs bring back a whole moment. Do you have a song like that?'),
    ]),
    _Topic('screen', [
      '戲', '電影', '電視', '劇', '節目', '新聞', 'movie', 'film', 'tv',
      'show', 'news',
    ], [
      (zh: '睇戲睇節目都係好好嘅消遣。你鍾意邊一類多啲？',
        en: 'Films and shows are a nice way to pass time. Which kind do you enjoy most?'),
      (zh: '有時睇完一齣好戲，會諗好耐。你最近有冇睇到印象深嘅？',
        en: 'A good show can stay with you. Seen anything memorable lately?'),
      (zh: '你通常自己一個睇，定係同人一齊睇多啲？',
        en: 'Do you usually watch alone, or with other people?'),
    ]),
    _Topic('outing', [
      '行街', '散步', '公園', '行山', '出街', '旅行', '去咗', '街', '海邊',
      'walk', 'park', 'hike', 'travel', 'trip',
    ], [
      (zh: '出去行下真係幾舒服。你最鍾意去邊度行？',
        en: 'Getting out for a walk feels good. Where do you most like to go?'),
      (zh: '周圍行行，成日會見到新嘢。你通常幾點出去？',
        en: 'Walking around, you often spot something new. What time do you usually go out?'),
      (zh: '香港有好多地方值得行。有冇一個地方你成日都想再去？',
        en: 'Hong Kong has so many places to wander. Is there one you keep wanting to revisit?'),
    ]),
    _Topic('weather', [
      '天氣', '熱', '凍', '落雨', '天晴', '颱風', '冷', 'weather', 'hot',
      'cold', 'rain', 'sunny', 'typhoon',
    ], [
      (zh: '天氣真係影響心情。你鍾意咩天氣多啲？',
        en: 'Weather really shapes the mood. What kind of weather do you like best?'),
      (zh: '呢排天氣變得好快。你平時點樣照顧自己？',
        en: 'The weather changes so quickly lately. How do you look after yourself?'),
      (zh: '每個季節都有佢嘅味道。你最鍾意邊個季節？',
        en: 'Every season has its own feel. Which one is your favourite?'),
    ]),
    _Topic('hobby', [
      '興趣', '嗜好', '麻雀', '象棋', '書法', '畫', '種花', '花', '太極',
      '跳舞', '手工', '睇書', 'hobby', 'mahjong', 'chess', 'paint', 'garden',
      'tai chi', 'read',
    ], [
      (zh: '有個興趣真係好好。你玩咗幾耐㗎喇？',
        en: 'Having a hobby is lovely. How long have you been doing it?'),
      (zh: '聽落好有意思。你係自己學識，定係有人教？',
        en: 'That sounds meaningful. Did you teach yourself, or did someone show you?'),
      (zh: '做自己鍾意嘅嘢，時間過得特別快。你通常幾時做？',
        en: 'Time flies doing what you enjoy. When do you usually do it?'),
    ]),
    _Topic('pet', [
      '狗', '貓', '雀', '魚', '寵物', 'dog', 'cat', 'bird', 'fish', 'pet',
    ], [
      (zh: '小動物真係好可愛。你鍾意貓定係狗多啲？',
        en: 'Animals are so endearing. Do you prefer cats or dogs?'),
      (zh: '有小動物陪住，屋企都熱鬧啲。你以前有冇養過？',
        en: 'Animals make a home livelier. Have you ever kept one?'),
    ]),
    _Topic('festival', [
      '節', '過年', '新年', '中秋', '端午', '冬至', '聖誕', '生日', 'festival',
      'new year', 'birthday', 'christmas',
    ], [
      (zh: '過節總係特別有氣氛。你最鍾意邊個節日？',
        en: 'Festivals always have a special feel. Which one do you like most?'),
      (zh: '每個節日都有唔同嘅習俗。你以前係點樣過嘅？',
        en: 'Each festival has its own customs. How did you use to celebrate?'),
    ]),
    _Topic('past', [
      '以前', '細個', '當年', '年輕', '後生', '舊時', '嗰陣', 'when i was',
      'young', 'used to', 'back then',
    ], [
      (zh: '以前嘅日子真係好多故事。嗰陣時嘅生活係點樣㗎？',
        en: 'The old days hold so many stories. What was life like back then?'),
      (zh: '聽落好有味道。你覺得同而家比，最大分別係咩？',
        en: 'That sounds full of character. What\'s the biggest difference compared with now?'),
      (zh: '好多嘢都變咗。有冇啲嘢你覺得以前嗰種更好？',
        en: 'So much has changed. Is there anything you think was better before?'),
    ]),
  ];

  static const List<_Template> _generic = [
    (zh: '原來係咁。可唔可以講多少少？', en: 'I see. Could you tell me a little more?'),
    (zh: '聽落幾有意思。你點睇？', en: 'That sounds interesting. What do you make of it?'),
    (zh: '多謝你分享。你第一次接觸係幾時？', en: 'Thanks for sharing. When did you first come across it?'),
    (zh: '明白。你覺得最有趣嘅地方係邊度？', en: 'I see. What do you find most interesting about it?'),
    (zh: '好呀，慢慢講，我喺度聽緊。', en: 'Sure — take your time, I\'m listening.'),
    (zh: '嗯，咁你平時會同邊個傾開呢啲？', en: 'Mm. Who do you usually chat about this with?'),
  ];

  /// Reply to the user's [userTurnIndex]-th turn (0-based) of this
  /// session. Deterministic for the same text and index.
  ///
  /// [openerOffset] shifts which opener is appended (e.g. the session's
  /// starting opener index) so consecutive sessions don't repeat.
  static RuleReply reply(
    String userText, {
    required int userTurnIndex,
    int openerOffset = 0,
  }) {
    final lower = userText.toLowerCase();
    String id;
    _Template t;

    _Topic? topic;
    for (final candidate in _topics) {
      if (candidate.keywords.any(lower.contains)) {
        topic = candidate;
        break;
      }
    }
    if (topic != null) {
      final i = userTurnIndex % topic.replies.length;
      id = '${topic.id}_$i';
      t = topic.replies[i];
    } else {
      final i = userTurnIndex % _generic.length;
      id = 'generic_$i';
      t = _generic[i];
    }

    // Every openerEvery-th turn, move the conversation on with a fresh
    // opener question from the pool.
    if ((userTurnIndex + 1) % openerEvery == 0) {
      final opener = TungTungRulePool.openerFor(
          openerOffset + 1 + userTurnIndex ~/ openerEvery);
      return RuleReply(
        id: id,
        zh: '${t.zh}\n\n另外想問下你：${opener.zh}',
        en: '${t.en}\n\nAlso, I wanted to ask: ${opener.en}',
        openerId: opener.id,
      );
    }
    return RuleReply(id: id, zh: t.zh, en: t.en);
  }
}
