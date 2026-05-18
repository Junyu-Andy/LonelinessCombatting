/// B.4 — Tung Tung 16-item static interest-chat pool for Arm B.
///
/// Per Phase A Proposal §2.3 + Product Overview §4.3, rule-based Tung
/// Tung is delivered via a 16-item static interest-chat pool (parallel
/// to M5's reflective-dialogue pool), preserving the three-agent surface
/// symmetry while keeping the LLM curious-chat affordances Hybrid-only.
///
/// Anticipated underutilisation: spec acknowledges this surface will be
/// underutilised in the Rule-based arm relative to the Hybrid arm.  This
/// is framed as an empirical confirmation that LLM affordances are
/// structural to the Social Integration pathway (Phase B Proposal §4.7).
///
/// The pool is hardcoded; cultural advisor review is a Phase A
/// prerequisite (Product Overview §10.2).
library;

class TungTungRulePool {
  const TungTungRulePool._();

  /// 16 interest-conversation openers across common HK older-adult
  /// interest categories.  Indexed; sequential rotation rather than
  /// random so each user sees the same order (deterministic per arm).
  static const List<({String zh, String en})> items = [
    (
      zh: '你今日有冇睇新聞？最近有冇咩嘢令你覺得有趣？',
      en: 'Did you watch the news today? Anything that caught your interest?',
    ),
    (
      zh: '今個季節市場有咩當造嘅嘢食？',
      en: 'What seasonal foods are in the markets right now?',
    ),
    (
      zh: '你以前有冇試過去新界邊個地方行山？',
      en: "Have you ever been hiking in the New Territories? Where?",
    ),
    (
      zh: '今日嘅天氣令你諗起咩呢？',
      en: 'What does today\'s weather remind you of?',
    ),
    (
      zh: '你以前最鍾意嘅一首歌係咩？',
      en: 'What was your favourite song from years ago?',
    ),
    (
      zh: '你有冇睇過一齣戲令你睇完仲記得？',
      en: 'Is there a film you watched that you still remember?',
    ),
    (
      zh: '你細個鍾意食咩零食？',
      en: 'What snacks did you love as a kid?',
    ),
    (
      zh: '你曾經住過嘅地方入面，邊一個最有意思？',
      en: 'Of the places you\'ve lived, which one feels most meaningful?',
    ),
    (
      zh: '你有冇養過寵物？係咩動物？',
      en: 'Have you ever kept a pet? What kind?',
    ),
    (
      zh: '你最鍾意嘅茶餐廳菜式係咩？',
      en: "What's your favourite cha chaan teng dish?",
    ),
    (
      zh: '你最近行過邊條街令你覺得舒服？',
      en: 'Which street have you walked lately that felt nice?',
    ),
    (
      zh: '你有冇邊樣技能或者手藝想學？',
      en: 'Is there a skill or craft you\'d like to learn?',
    ),
    (
      zh: '你以前嘅工作教咗你啲咩你而家仲用緊？',
      en: 'What did your past work teach you that you still use today?',
    ),
    (
      zh: '你有冇一個老朋友，諗起佢就會笑？',
      en: 'Is there an old friend who makes you smile when you think of them?',
    ),
    (
      zh: '你有冇諗過去邊度旅行？',
      en: "Where would you go if you could travel anywhere?",
    ),
    (
      zh: '你最近聽到一首歌或者廣播令你停低過一陣？',
      en: 'Has a song or broadcast made you pause lately?',
    ),
  ];

  /// Returns the next opener in rotation given the [turnIndex] (number
  /// of turns the user has had with rule-based Tung Tung so far).
  static ({String zh, String en}) openerFor(int turnIndex, {bool isEn = false}) {
    final idx = turnIndex.abs() % items.length;
    return items[idx];
  }
}
