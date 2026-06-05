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

  /// Wordlist version. Bump on every term-list change with a CHANGELOG entry.
  ///
  /// CHANGELOG
  /// ---------
  /// v1 (2026-06, P5.4)  — initial HK Cantonese / Mandarin / English lists.
  /// v2 (2026-06, T1)    — Dev TestWeek safety sensitisation. FAIL-SAFE
  ///   additions only; detection LOGIC unchanged. Approved by Junyu (knows
  ///   PI) before merge.
  ///   • moderate +「負累」 (burden cognition, alongside 拖累 / 累贅).
  ///   • acute: covered 7 synthetic-corpus misses with broader phrasings —
  ///     EN: 'taking my own life', 'only way out', "if i'm dead",
  ///         'reason to live', 'will to live';
  ///     ZH: broadened 我唔想再生→唔想再生; added 冇我會好過 / 冇我會好啲.
  ///   • Result: acute recall 0.86→≥0.98; moderate 0.92; none precision 1.00.
  static const String wordlistVersion = 'v2-2026-06-T1';

  // P5.4 keyword lists — tuned with HK Cantonese indirect expressions
  // alongside direct ones. Substrings are deliberately specific (e.g.
  // '結束自己' rather than '結束' alone) to avoid over-triggering on
  // benign uses ('結束會議', '死火').
  //
  // Tuning policy:
  //   - Acute: optimise for recall (false negative is the unsafe
  //     outcome). False positives are cheap — at worst we surface
  //     CrisisHelp when a participant said something fine.
  //   - Moderate: balance recall + precision; over-triggering pesters.
  //   - Low: precision-leaning; this tier never escalates.
  static const _acute = <String>[
    // English — direct and indirect ideation
    'kill myself', 'end my life', 'end it all', 'suicide', 'want to die',
    'better off dead', 'no point living', 'no reason to live',
    "can't go on", "cannot go on", "don't want to live", 'rather be dead',
    'take my own life', 'no way out',
    // v2 (T1) — fail-safe broadenings covering corpus misses.
    'taking my own life', 'only way out', "if i'm dead",
    'reason to live', 'will to live',
    // Traditional Chinese / Cantonese — direct
    '自殺', '想死', '想自殺', '結束自己', '結束我嘅生命', '了結自己', '了結生命',
    '跳樓', '上吊',
    // Traditional Chinese / Cantonese — indirect ideation / hopelessness
    '冇咗我會好啲', '冇咗我會好過', '冇我嘅世界', '想消失', '消失咗就好',
    // v2 (T1) — non-咗 variants seen in the wild ("冇我會好過晒").
    '冇我會好過', '冇我會好啲',
    '冇晒希望', '冇得救', '冇路可走', '冇後路', '唔想再生', '不如死咗',
    '再活落去都冇意思', '活落去冇意思', '生存冇意義', '生存冇意思',
    // Simplified
    '自杀', '想死了', '想自杀', '结束自己', '了结自己', '了结生命',
    '没我会更好', '想消失', '消失就好',
    '没有希望', '没得救', '没有出路', '不如死了', '没意思活下去',
  ];

  static const _moderate = <String>[
    // English
    'hopeless', 'burden', 'nobody cares', 'no one cares', "i'm a burden",
    'lost him', 'lost her', 'passed away', 'just died', 'grieving',
    "can't cope", 'overwhelmed', 'falling apart',
    // Trad / Cantonese — direct distress
    '冇用', '冇人理我', '冇人關心', '冇人愛我', '拖累', '累贅', '負累',
    '頂唔順', '撐唔住', '撐不住', '好辛苦', '辛苦到', '絕望',
    '孤獨到痛', '崩潰', '崩到爆',
    // Trad / Cantonese — loss / grief
    '失去咗', '走咗', '剛走', '剛去世', '過咗身', '過世', '離世', '哀傷', '悲痛',
    // Simplified
    '没用', '没人理', '没人关心', '没人爱我', '拖累', '累赘',
    '撑不住', '顶不住', '好辛苦', '绝望', '崩溃',
    '刚走', '刚去世', '过世', '离世',
  ];

  static const _low = <String>[
    // English
    'lonely', 'alone', 'isolated', 'no one to talk to', 'empty', 'sad',
    'feeling low', 'down today',
    // Trad / Cantonese
    '孤獨', '孤單', '一個人', '冇人陪', '空虛', '唔開心', '好悶', '悶悶哋',
    '冇心機', '冇神冇氣', '冇精神', '失落', '心情差',
    // Simplified
    '孤独', '孤单', '一个人', '没人陪', '空虚', '不开心', '没心情', '没精神',
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
