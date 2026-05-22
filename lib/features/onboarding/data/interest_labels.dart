/// Shared interest-ID → display label lookup.
///
/// IDs are the canonical string values stored in UserProfile.interests.
/// Any ID not in this map falls back to the raw ID string.
class InterestLabels {
  InterestLabels._();

  static const Map<String, ({String zh, String en})> _labels = {
    'yum_cha':         (zh: '飲茶／一盅兩件',   en: 'Yum cha / dim sum'),
    'cooking':         (zh: '煮食',              en: 'Cooking'),
    'wet_market':      (zh: '逛街市',            en: 'Wet market'),
    'buffet':          (zh: '食自助餐',          en: 'Buffet dining'),
    'tv_drama':        (zh: '睇電視劇',          en: 'TV drama'),
    'radio':           (zh: '聽收音機',          en: 'Radio'),
    'reading':         (zh: '看書／睇雜誌',      en: 'Books / magazines'),
    'mahjong':         (zh: '打牌／打麻雀',      en: 'Cards / mahjong'),
    'gardening':       (zh: '種花種菜',          en: 'Gardening'),
    'chatting':        (zh: '跟人傾偈',          en: 'Chatting with people'),
    'hiking':          (zh: '行山',              en: 'Hiking'),
    'park_walk':       (zh: '公園散步',          en: 'Park walks'),
    'tai_chi':         (zh: '太極拳',            en: 'Tai chi'),
    'swimming':        (zh: '游水',              en: 'Swimming'),
    'cantonese_opera': (zh: '粵劇／戲曲',        en: 'Cantonese opera'),
    'museums':         (zh: '睇展覽／博物館',    en: 'Museums & galleries'),
    'elderly_centre':  (zh: '老人中心活動',      en: 'Elderly centre activities'),
    'religious':       (zh: '去教會／廟宇',      en: 'Church / temple'),
    'visit_friends':   (zh: '探望朋友',          en: 'Visiting friends'),
    'volunteering':    (zh: '義工服務',          en: 'Volunteering'),
    'meditation':      (zh: '靜坐／冥想',        en: 'Meditation'),
    'prayer':          (zh: '祈禱／膜拜',        en: 'Prayer / worship'),
    'news':            (zh: '新聞時事',          en: 'News & current affairs'),
  };

  static String label(String id, bool isEn) {
    final entry = _labels[id];
    if (entry == null) return id;
    return isEn ? entry.en : entry.zh;
  }
}
