/// Conservative client-side keyword filter for negative-social-cognition
/// detection (Walkthrough Case 5).
///
/// The Ah Jan / Ah Bak reflective dialogue surface uses this to decide
/// whether to surface the "name the thought" card after a user turn.
/// The filter is intentionally narrow — we'd rather miss most actual
/// negative cognitions than surface false positives, because the
/// "name a thought" intervention is conspicuous and over-surfacing it
/// would feel pathologising.
///
/// Triggers are absolutist or rejection-flavoured phrasings drawn from
/// the Phase 0 transcript pilot. They are NOT distress signals — those
/// are handled by [DistressDetector]. A turn may match here without
/// raising any distress flag.
library;

class NegativeCognitionMatch {
  /// The exact substring that matched.
  final String snippet;

  /// Original user turn for surfacing back to the user.
  final String fullTurn;

  const NegativeCognitionMatch({
    required this.snippet,
    required this.fullTurn,
  });
}

class NegativeCognitionDetector {
  const NegativeCognitionDetector();

  /// Triggers are short anchor phrases. Each turn is scanned once;
  /// the first match wins.
  static const List<String> _zhTriggers = [
    '阻住佢',
    '阻住個',
    '都係阻住',
    '冇人理',
    '冇人會理',
    '冇人關心',
    '冇人會關心',
    '都唔記得我',
    '都唔會理我',
    '我冇用',
    '我都係多餘',
    '都係我嘅錯',
    '都係我唔好',
    '永遠都',
    '從來都唔',
    '一定唔得',
  ];

  static const List<String> _enTriggers = [
    'bother them',
    'no one cares',
    'nobody cares',
    "no one's going to",
    'i\'m useless',
    'i am useless',
    'always my fault',
    'never going to',
    'pointless',
    'a burden',
  ];

  /// Returns the first match in [turn], or null if none.
  NegativeCognitionMatch? scan(String turn) {
    if (turn.trim().isEmpty) return null;
    for (final t in _zhTriggers) {
      if (turn.contains(t)) {
        return NegativeCognitionMatch(snippet: t, fullTurn: turn);
      }
    }
    final lower = turn.toLowerCase();
    for (final t in _enTriggers) {
      if (lower.contains(t)) {
        return NegativeCognitionMatch(snippet: t, fullTurn: turn);
      }
    }
    return null;
  }
}
