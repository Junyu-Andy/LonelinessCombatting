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
  // v4-2026-07: D1–D6 (see docs/safety/distress_detector_lexicon_v4-2026-07.md).
  // D4 (hopelessness unified at moderate) is flagged PI-clinical-signoff-pending
  // in that doc — applied here for testing per Junyu's direction.
  static const String wordlistVersion = 'v4-2026-07';

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
  // v4-2026-07 lexicon — full changelog + PI decisions (D1–D6) in
  // docs/safety/distress_detector_lexicon_v4-2026-07.md.  Acute-first check
  // order is load-bearing: several acute terms contain moderate terms
  // (e.g. 真係想死 ⊃ 想死).  冇-based terms are emitted in 冇/沒/無 variants.
  static const _acute = <String>[
    // EN — ideation
    'kill myself', 'end my life', 'end it all', 'suicide', 'want to die',
    'better off dead', 'no point living', 'no reason to live',
    'no will to live', 'lost my will to live', 'lost the will to live',
    "can't go on", 'cant go on', 'cannot go on', 'can not go on',
    "don't want to live", 'dont want to live', 'rather be dead',
    'take my own life', 'taking my own life', 'no way out', 'only way out',
    "if i'm dead", 'if im dead', 'kill himself', 'kill herself',
    // EN — worthlessness
    "i'm worthless", 'i am worthless', 'im worthless', 'i have no worth',
    'no reason to exist', 'nobody needs me', 'no one needs me',
    // EN — self-harm (v4)
    'self harm', 'self-harm', 'harm myself', 'hurt myself', 'hurting myself',
    'cut myself', 'cutting myself',
    // EN — harm-to-others
    'want to kill someone', 'want to kill him', 'want to kill her',
    'want to kill them', 'want to hurt someone',
    // 繁體/粵語 — ideation
    '自殺', '好想死', '真係想死', '真想死', '結束自己', '結束我嘅生命',
    '了結自己', '了結生命', '想跳樓', '上吊', '燒炭',
    '冇咗我會好啲', '沒咗我會好啲', '無咗我會好啲',
    '冇咗我會好過', '沒咗我會好過', '無咗我會好過',
    '冇我嘅世界', '沒我嘅世界', '無我嘅世界', '想消失', '消失咗就好',
    '冇我會好過', '沒我會好過', '無我會好過',
    '冇我會好啲', '沒我會好啲', '無我會好啲',
    '冇得救', '沒得救', '無得救', '冇路可走', '沒路可走', '無路可走',
    '冇後路', '沒後路', '無後路', '唔想再生', '不如死咗',
    '再活落去都冇意思', '再活落去都沒意思', '再活落去都無意思',
    '活落去冇意思', '活落去沒意思', '活落去無意思',
    '生存冇意義', '生存沒意義', '生存無意義',
    '生存冇意思', '生存沒意思', '生存無意思',
    '唔想活', '活唔落去', '諗唔開',
    // 繁體/粵語 — worthlessness
    '活著冇價值', '活著沒價值', '活著無價值',
    '生存冇價值', '生存沒價值', '生存無價值',
    '我冇價值', '我沒價值', '我無價值',
    '冇存在價值', '沒存在價值', '無存在價值',
    '我係多餘', '我係廢人', '冇人需要我', '沒人需要我', '無人需要我',
    // 繁體/粵語 — self-harm (v4)
    '自殘', '傷害自己', '𠝹手',
    // 繁體/粵語 — harm-to-others
    '想殺人', '我想殺死', '我想殺咗', '想傷害人', '我想傷害佢', '我想弄死',
    // 简体 — ideation
    '自杀', '真的想死', '结束自己', '了结自己', '了结生命', '想跳楼', '烧炭',
    '没我会更好', '没得救', '没有出路', '没路可走', '没有后路', '不如死了',
    '没意思活下去', '活下去没意思', '不想活', '活不下去', '想不开',
    '生存没有意义',
    // 简体 — worthlessness
    '活着没价值', '生存没有价值', '我没有价值', '我没价值', '没有存在价值',
    '没存在价值', '我是多余的', '我是废人', '没人需要我',
    // 简体 — self-harm (v4)
    '自残', '伤害自己',
    // 简体 — harm-to-others
    '想杀人', '我想杀死', '我想杀了', '想伤害别人', '我想伤害他',
  ];

  static const _moderate = <String>[
    // EN
    'hopeless', 'burden', 'nobody cares', 'no one cares', 'lost my husband',
    'lost my wife', 'passed away', 'just died', 'grieving', "can't cope",
    'cant cope', 'overwhelmed', 'falling apart',
    // 繁體/粵語 — distress
    '冇用', '沒用', '無用', '冇人理我', '沒人理我', '無人理我',
    '冇人關心', '沒人關心', '無人關心', '冇人愛我', '沒人愛我', '無人愛我',
    '都唔理我', '都唔關心我', '拖累', '累贅', '負累', '負擔',
    '頂唔順', '撐唔住', '撐不住', '好辛苦', '辛苦到', '絕望',
    '冇晒希望', '沒晒希望', '無晒希望', '孤獨到痛', '崩潰', '崩到爆',
    // 繁體/粵語 — ideation-adjacent (D1: demoted from acute)
    '想死',
    // 繁體/粵語 — loss / grief
    '失去咗', '老伴走咗', '剛去世', '過咗身', '過世', '離世', '哀傷', '悲痛',
    // 简体
    '没用', '没人理', '没人关心', '没人爱我', '累赘', '负担',
    '撑不住', '顶不住', '绝望', '没有希望', '崩溃',
    '老伴走了', '刚去世', '过世', '离世',
  ];

  static const _low = <String>[
    // EN
    'lonely', 'alone', 'isolated', 'no one to talk to', 'empty', 'sad',
    'feeling low', 'down today',
    // 繁體/粵語
    '孤獨', '孤單', '寂寞', '一個人', '冇人陪', '沒人陪', '無人陪', '空虛',
    '唔開心', '好悶', '悶悶哋', '冇心機', '沒心機', '無心機',
    '冇咩心機', '沒咩心機', '無咩心機', '冇神冇氣', '沒神沒氣', '無神無氣',
    '冇精神', '沒精神', '無精神', '失落', '低落', '心情差',
    // 简体
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
