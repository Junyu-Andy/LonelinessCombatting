/// B.4 — Tung Tung 20-item static interest-chat pool for Arm B.
///
/// Research Review v2 Item 2: expanded from 16 → 20 candidates.
/// Research team will select the final 16; 4 are marked ⚠️ for review.
/// Version lock: bump [_version] whenever the item list changes so analysts
/// can join opener_id × version in telemetry.
///
/// Telemetry contract (caller's responsibility):
///   AnalyticsService.logEvent('tung_tung_opener_shown', {
///     'opener_id': '<id>',
///     'pool_version': TungTungRulePool.version,
///     'turn_index': turnIndex,
///   });
///
/// Per Phase A Proposal §2.3 + Product Overview §4.3, rule-based Tung
/// Tung is delivered via this static pool (parallel to M5's reflective-
/// dialogue pool), preserving three-agent surface symmetry while keeping
/// LLM curious-chat affordances Hybrid-only.
///
/// The pool is hardcoded; cultural advisor review is a Phase A
/// prerequisite (Product Overview §10.2).
library;

class TungTungRulePool {
  const TungTungRulePool._();

  /// Version lock — bump when the item list changes. Analysts join
  /// opener_id × version to detect pool changes mid-study.
  static const String version = '2026-06-v2';

  /// 20 interest-conversation openers across common HK older-adult
  /// interest categories. Research team to cull to 16 before Phase A.
  /// ⚠️ items 12, 13, 15, 17 flagged for cultural advisor review.
  static const List<({String id, String zh, String en})> items = [
    (id: 'tt01', zh: '你今日有冇睇新聞？最近有冇咩嘢令你覺得有趣？',
      en: 'Did you watch the news today? Anything that caught your interest?'),
    (id: 'tt02', zh: '今個季節市場有咩當造嘅嘢食？',
      en: 'What seasonal foods are in the markets right now?'),
    (id: 'tt03', zh: '今日嘅天氣令你諗起咩呢？',
      en: "What does today's weather remind you of?"),
    (id: 'tt04', zh: '你以前最鍾意嘅一首歌係咩？',
      en: 'What was your favourite song from years ago?'),
    (id: 'tt05', zh: '你有冇睇過一齣戲令你睇完仲記得？',
      en: 'Is there a film you watched that you still remember?'),
    (id: 'tt06', zh: '你細個鍾意食咩零食？',
      en: 'What snacks did you love as a kid?'),
    (id: 'tt07', zh: '你曾經住過嘅地方入面，邊一個最有意思？',
      en: "Of the places you've lived, which one feels most meaningful?"),
    (id: 'tt08', zh: '你有冇養過寵物？係咩動物？',
      en: 'Have you ever kept a pet? What kind?'),
    (id: 'tt09', zh: '你最鍾意嘅茶餐廳菜式係咩？',
      en: "What's your favourite cha chaan teng dish?"),
    (id: 'tt10', zh: '你最近行過邊條街令你覺得舒服？',
      en: 'Which street have you walked lately that felt nice?'),
    (id: 'tt11', zh: '你有冇一個老朋友，諗起佢就會笑？',
      en: 'Is there an old friend who makes you smile when you think of them?'),
    (id: 'tt12', zh: '你有冇諗過去邊度旅行？', // ⚠️ mobility assumption — advisor review
      en: 'Where would you go if you could travel anywhere?'),
    (id: 'tt13', zh: '你最近聽到一首歌或者廣播令你停低過一陣？',
      en: 'Has a song or broadcast made you pause lately?'),
    (id: 'tt14', zh: '你鍾意煮咩嘢食？有冇一道菜係你拿手嘅？',
      en: 'What do you like to cook? Is there a dish you make especially well?'),
    (id: 'tt15', zh: '你細個喺邊條街長大？嗰條街而家仲喺唔喺？', // ⚠️ neighbourhood change sensitivity
      en: 'Which street did you grow up on? Is it still there?'),
    (id: 'tt16', zh: '你最近有冇去過茶樓？印象最深係坐喺邊度？',
      en: 'Have you been to a dim sum restaurant lately? Where do you like to sit?'),
    (id: 'tt17', zh: '你有冇參加過邊個社區活動？係點樣嘅感覺？', // ⚠️ social network assumption
      en: 'Have you ever joined a community activity? What was it like?'),
    (id: 'tt18', zh: '你鍾意喺家裏邊定係出去逛逛？',
      en: 'Do you prefer staying at home or going out for a walk?'),
    (id: 'tt19', zh: '你細個最開心嘅一個節日係咩？係點過嘅？',
      en: 'What was your favourite festival as a child? How did you celebrate?'),
    (id: 'tt20', zh: '你有冇一件珍貴嘅舊物品，仲留住佢？',
      en: 'Do you have a treasured old object you still keep?'),
  ];

  /// Returns the next opener in rotation given the [turnIndex] (number
  /// of turns the user has had with rule-based Tung Tung so far).
  ///
  /// Callers should log analytics event `tung_tung_opener_shown` with
  /// the returned `id` and [version] for Phase A calibration.
  static ({String id, String zh, String en}) openerFor(int turnIndex) {
    final idx = turnIndex.abs() % items.length;
    return items[idx];
  }
}
