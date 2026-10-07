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
/// weather, news, opening hours, prices, addresses) and the reply text is
/// a PLACEHOLDER — the research team writes the final wording (draft in
/// docs/dev-reports/T9-flags-20261007.md).  Bump [version] whenever
/// either changes.
library;

class TungTungSearchIntent {
  const TungTungSearchIntent._();

  /// Logged with every fixed reply so analysts can join keyword set ×
  /// wording.
  static const String version = '2026-10-placeholder';

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

  /// PLACEHOLDER — not approved wording.  Must not reach participants
  /// before the research team replaces it (flag stays off until then).
  static String reply({required bool isEn}) => isEn
      ? '[PLACEHOLDER — fixed reply while search is off, pending research sign-off]'
      : '【占位：搜一搜關閉時嘅固定回應，待研究團隊定稿】';
}
