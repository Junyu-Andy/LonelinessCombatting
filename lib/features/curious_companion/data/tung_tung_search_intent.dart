/// Tung Tung's fixed answer to search-type questions while "搜一搜" is off
/// (decision 0019, SPEC:C18).
///
/// Behind [RemoteFeatureFlags.searchOffReplyEnabled] (default off).  When
/// the flag is on and web search is off, a user turn that [matches] gets
/// [reply] instead of the usual reply — in BOTH arms, after the same
/// distress check, and only when that check finds nothing (any safety
/// hit keeps the normal safety flow untouched):
///
///   - Hybrid arm: the LLM is not called for that turn.
///   - Rule arm:   the line replaces the topic template.
///
/// The keyword list is deliberately narrow (explicit look-up words,
/// weather, news, opening hours, prices, addresses).  T33: [reply] is the
/// final text S1a from `docs/spec/copy/short-texts.md`, verbatim
/// (`test/final_copy_test.dart` compares it).  Bump [version] whenever
/// the keywords or the wording change.
library;

class TungTungSearchIntent {
  const TungTungSearchIntent._();

  /// Logged with every fixed reply so analysts can join keyword set ×
  /// wording.
  static const String version = '2026-10-10-s1a';

  /// Stable template id for telemetry.
  static const String replyId = 'search_off_fixed';

  static const List<String> _keywords = [
    // Explicit "look it up" requests.
    // (No bare 查下 / 搵下 / 上網 / 點去 / 邊度有: they also appear in
    // 檢查下, 搵下朋友, 唔識上網, 點去面對, 邊度有人關心我.)
    '幫我查', '查一查', '上網查', '上網搵', '搜尋', '搜一搜',
    'google', 'search', 'look up', 'look it up',
    // Live information Tung Tung cannot know without a search.
    '天氣', '天文台', '新聞', '幾點開', '開幾點', '開到幾點',
    '幾錢', '價錢', '地址',
    'weather', 'news', 'opening hours', 'address',
  ];

  /// True when [text] looks like a question that needs a web search.
  static bool matches(String text) {
    final t = text.toLowerCase();
    for (final k in _keywords) {
      if (t.contains(k)) return true;
    }
    return false;
  }

  /// S1a (final, 10/10).  Cantonese only — there is no English final
  /// copy, so the English UI shows the same line.
  static const String replyS1a =
      '呢樣嘢要上網查先知，我而家查唔到。你可以問下屋企人、社工，或者睇下電視新聞。';

  static String reply({required bool isEn}) => replyS1a;
}
