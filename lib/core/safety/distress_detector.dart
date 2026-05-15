/// Severity bands for free-text input. Rule-based, deterministic, identical
/// in both arms (per Master Feature Spec §Safety controls).
///
/// Tiers:
/// - [none]: no concerning content detected.
/// - [low]: language suggesting persistent loneliness, sadness, or isolation.
///   Module flows can soften copy; no escalation.
/// - [moderate]: hopelessness, "burden" cognitions, recent loss / grief.
///   Surface resources at end of session; flag for research team weekly review.
/// - [acute]: self-harm or suicidal ideation. Immediate in-session resource
///   prompt + crisis line; notify research team within 24h.
enum DistressLevel { none, low, moderate, acute }

class DistressMatch {
  final DistressLevel level;

  /// The first matched keyword. Useful for analytics + audit; never shown to
  /// the user verbatim.
  final String? matchedTerm;

  const DistressMatch(this.level, [this.matchedTerm]);

  bool get isEscalation =>
      level == DistressLevel.moderate || level == DistressLevel.acute;
}

/// Rule-based detector. Cantonese / Mandarin / English keyword lists, lower-
/// cased substring match. Intentionally over-triggers in the [moderate] /
/// [acute] tiers — false positives surface resources; false negatives don't.
///
/// **Not LLM-dependent on purpose.** Safety equivalence between Arm A and
/// Arm B requires that the same input produces the same flag regardless of
/// which arm a user is in. The LLM may augment the response, but the trigger
/// must be deterministic.
class DistressDetector {
  const DistressDetector();

  static const _acute = <String>[
    // English
    'kill myself', 'end my life', 'suicide', 'want to die', 'better off dead',
    'no point living', "can't go on",
    // Traditional Chinese / Cantonese
    '自殺', '想死', '結束自己', '了結自己', '冇晒希望', '冇得救', '我唔想再生', '不如死咗',
    // Simplified
    '自杀', '想死了', '结束自己', '没有希望', '不如死了',
  ];

  static const _moderate = <String>[
    // English
    'hopeless', 'burden', 'nobody cares', 'no one cares', "i'm a burden",
    'lost him', 'lost her', 'passed away', 'just died', 'grieving',
    // Trad / Cantonese
    '冇用', '冇人理我', '冇人關心', '拖累', '累贅', '失去咗', '走咗', '剛走', '剛去世', '過咗身',
    '哀傷', '悲痛',
    // Simplified
    '没用', '没人理', '没人关心', '拖累', '累赘', '刚走', '刚去世', '过世',
  ];

  static const _low = <String>[
    // English
    'lonely', 'alone', 'isolated', 'no one to talk to', 'empty', 'sad',
    // Trad / Cantonese
    '孤獨', '孤單', '一個人', '冇人陪', '空虛', '唔開心', '好悶',
    // Simplified
    '孤独', '孤单', '一个人', '没人陪', '空虚', '不开心',
  ];

  DistressMatch analyze(String text) {
    if (text.trim().isEmpty) return const DistressMatch(DistressLevel.none);
    final lower = text.toLowerCase();

    String? hit(List<String> terms) {
      for (final t in terms) {
        if (lower.contains(t.toLowerCase())) return t;
      }
      return null;
    }

    final acute = hit(_acute);
    if (acute != null) return DistressMatch(DistressLevel.acute, acute);
    final moderate = hit(_moderate);
    if (moderate != null) return DistressMatch(DistressLevel.moderate, moderate);
    final low = hit(_low);
    if (low != null) return DistressMatch(DistressLevel.low, low);
    return const DistressMatch(DistressLevel.none);
  }
}
