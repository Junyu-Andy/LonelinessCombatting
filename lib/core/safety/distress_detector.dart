/// Severity tiers for free-text input. Rule-based, deterministic, identical
/// in both arms (per Master Feature Spec §Safety controls).
///
/// Phase A baseline (S-1, 2026-09): the former single `moderate` tier is
/// split in two so that grief / hardship language spoken *as part of a
/// life-review memory* is logged for weekly review but does not interrupt
/// the participant, while present-tense hopelessness / burden / "nobody
/// cares" language still surfaces the soft support prompt.
///
/// Tiers (check order is acute → moderateInterrupt → moderateReview → low →
/// none; the first tier with a hit wins, so the enum order below is the
/// severity order and `index` comparisons are valid):
/// - [none]: no concerning content detected.
/// - [low]: language suggesting persistent loneliness, sadness, or isolation.
///   Module flows can soften copy; no escalation.
/// - [moderateReview]: recent loss / grief / past hardship.  LLM still
///   replies; **no** prompt, **no** template, **no** pill change.  Logged +
///   flagged for the research team's weekly review.
/// - [moderateInterrupt]: hopelessness, "burden" / worthlessness cognitions,
///   "nobody cares", overwhelmed.  LLM still replies; the per-agent safety
///   template is shown *in addition* and the soft support sheet is offered.
///   Logged + weekly review.
/// - [acute]: self-harm, suicidal ideation, harm-to-others. LLM is
///   short-circuited; full-screen crisis page + acute template; notify the
///   research team within 24 h.
enum DistressLevel {
  none,
  low,
  moderateReview,
  moderateInterrupt,
  acute;

  /// Either moderate tier (the pre-S-1 `moderate` band).
  bool get isModerate =>
      this == DistressLevel.moderateReview ||
      this == DistressLevel.moderateInterrupt;

  /// Snake-case tier code used in Firestore `turns.detector.tier`
  /// (`none` / `low` / `moderate_review` / `moderate_interrupt` / `acute`).
  String get tierCode => switch (this) {
        DistressLevel.none => 'none',
        DistressLevel.low => 'low',
        DistressLevel.moderateReview => 'moderate_review',
        DistressLevel.moderateInterrupt => 'moderate_interrupt',
        DistressLevel.acute => 'acute',
      };

  /// Legacy 4-band label (`none` / `low` / `moderate` / `acute`) kept for
  /// the `safety_events.level` field, whose Firestore rule and Cloud
  /// Function trigger predate the S-1 split.
  String get legacyLevelCode => isModerate ? 'moderate' : name;

  /// Parses either the enum name, the snake-case tier code, or the legacy
  /// `moderate` label (mapped to [moderateInterrupt], the fail-safe side).
  static DistressLevel parse(String? raw) {
    switch (raw) {
      case 'low':
        return DistressLevel.low;
      case 'moderate_review':
      case 'moderateReview':
        return DistressLevel.moderateReview;
      case 'moderate':
      case 'moderate_interrupt':
      case 'moderateInterrupt':
        return DistressLevel.moderateInterrupt;
      case 'acute':
        return DistressLevel.acute;
      default:
        return DistressLevel.none;
    }
  }
}

/// Lexical category of the matched term (Phase A `turns.detector.category`).
/// Lets the PI filter e.g. `harm_to_others` or third-person `ideation`
/// false positives during manual review without re-running the detector.
enum DistressCategory {
  ideation,
  worthlessness,
  selfHarm,
  harmToOthers,
  lossGrief,
  hardship,
  distress,
  low;

  String get code => switch (this) {
        DistressCategory.ideation => 'ideation',
        DistressCategory.worthlessness => 'worthlessness',
        DistressCategory.selfHarm => 'self_harm',
        DistressCategory.harmToOthers => 'harm_to_others',
        DistressCategory.lossGrief => 'loss_grief',
        DistressCategory.hardship => 'hardship',
        DistressCategory.distress => 'distress',
        DistressCategory.low => 'low',
      };
}

class DistressMatch {
  final DistressLevel level;

  /// The first matched keyword. Useful for analytics + audit; never shown to
  /// the user verbatim.
  final String? matchedTerm;

  /// Category of [matchedTerm]; null when [level] is [DistressLevel.none].
  final DistressCategory? category;

  const DistressMatch(this.level, [this.matchedTerm, this.category]);

  /// True for both moderate tiers and acute — i.e. the turn is written to
  /// `safety_events` and flagged for weekly review.
  bool get isEscalation => level.isModerate || level == DistressLevel.acute;

  /// True only when the participant-facing template + soft prompt fire
  /// (moderate_interrupt) — moderate_review is deliberately silent.
  bool get interrupts => level == DistressLevel.moderateInterrupt;
}

/// One lexicon group: every term carries the tier + category it maps to.
class _TermGroup {
  final DistressLevel level;
  final DistressCategory category;
  final List<String> terms;
  const _TermGroup(this.level, this.category, this.terms);
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
  // v5-2026-09 (Phase A baseline, S-1): the 67 moderate terms are split into
  //   moderate_review (19: loss/grief + past hardship) and
  //   moderate_interrupt (48: everything else).  Term SET unchanged from v4;
  //   only the tier assignment and the new per-term category changed.
  //   Check order acute → moderate_interrupt → moderate_review → low.
  //   S-7: the four 絕望-family terms live in [_hopelessnessTerms] and take
  //   [hopelessnessTier] so the PI's pending decision (keep moderate →
  //   interrupt, or promote to acute) is a one-line lexicon edit.
  static const String wordlistVersion = 'v5-2026-09';

  /// S-7 — tier for 冇晒希望 / 沒晒希望 / 無晒希望 / 没有希望.  Default
  /// (PI decision pending) keeps the v4 D4 position: moderate → interrupt.
  /// Flip to [DistressLevel.acute] if clinical sign-off promotes them; no
  /// other code changes are needed.
  static const DistressLevel hopelessnessTier = DistressLevel.moderateInterrupt;
  static const List<String> _hopelessnessTerms = [
    '冇晒希望', '沒晒希望', '無晒希望', '没有希望',
  ];

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
  // ---------------------------------------------------------------------
  // ACUTE — unchanged from v4 (term set + order).  Grouped by category.
  // ---------------------------------------------------------------------
  static const _acuteGroups = <_TermGroup>[
    _TermGroup(DistressLevel.acute, DistressCategory.ideation, [
      // EN — ideation
      'kill myself', 'end my life', 'end it all', 'suicide', 'want to die',
      'better off dead', 'no point living', 'no reason to live',
      'no will to live', 'lost my will to live', 'lost the will to live',
      "can't go on", 'cant go on', 'cannot go on', 'can not go on',
      "don't want to live", 'dont want to live', 'rather be dead',
      'take my own life', 'taking my own life', 'no way out', 'only way out',
      "if i'm dead", 'if im dead', 'kill himself', 'kill herself',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.worthlessness, [
      // EN — worthlessness
      "i'm worthless", 'i am worthless', 'im worthless', 'i have no worth',
      'no reason to exist', 'nobody needs me', 'no one needs me',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.selfHarm, [
      // EN — self-harm (v4)
      'self harm', 'self-harm', 'harm myself', 'hurt myself', 'hurting myself',
      'cut myself', 'cutting myself',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.harmToOthers, [
      // EN — harm-to-others
      'want to kill someone', 'want to kill him', 'want to kill her',
      'want to kill them', 'want to hurt someone',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.ideation, [
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
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.worthlessness, [
      // 繁體/粵語 — worthlessness
      '活著冇價值', '活著沒價值', '活著無價值',
      '生存冇價值', '生存沒價值', '生存無價值',
      '我冇價值', '我沒價值', '我無價值',
      '冇存在價值', '沒存在價值', '無存在價值',
      '我係多餘', '我係廢人', '冇人需要我', '沒人需要我', '無人需要我',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.selfHarm, [
      // 繁體/粵語 — self-harm (v4)
      '自殘', '傷害自己', '𠝹手',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.harmToOthers, [
      // 繁體/粵語 — harm-to-others
      '想殺人', '我想殺死', '我想殺咗', '想傷害人', '我想傷害佢', '我想弄死',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.ideation, [
      // 简体 — ideation
      '自杀', '真的想死', '结束自己', '了结自己', '了结生命', '想跳楼', '烧炭',
      '没我会更好', '没得救', '没有出路', '没路可走', '没有后路', '不如死了',
      '没意思活下去', '活下去没意思', '不想活', '活不下去', '想不开',
      '生存没有意义',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.worthlessness, [
      // 简体 — worthlessness
      '活着没价值', '生存没有价值', '我没有价值', '我没价值', '没有存在价值',
      '没存在价值', '我是多余的', '我是废人', '没人需要我',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.selfHarm, [
      // 简体 — self-harm (v4)
      '自残', '伤害自己',
    ]),
    _TermGroup(DistressLevel.acute, DistressCategory.harmToOthers, [
      // 简体 — harm-to-others
      '想杀人', '我想杀死', '我想杀了', '想伤害别人', '我想伤害他',
    ]),
  ];

  // ---------------------------------------------------------------------
  // MODERATE_INTERRUPT — 48 of the v4 moderate terms: present-tense
  // hopelessness / burden / worthlessness / "nobody cares" / overwhelmed,
  // plus the D1-demoted bare 想死.  Template + soft prompt fire.
  // ---------------------------------------------------------------------
  static const _moderateInterruptGroups = <_TermGroup>[
    // Term ORDER inside this tier mirrors v4 so `matchedTerm` (first hit)
    // is unchanged for messages that contain several moderate terms
    // (e.g. T-6 「冇人理我，我係個負擔」 → 冇人理我).
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.distress, [
      // EN
      'hopeless', 'burden', 'nobody cares', 'no one cares', "can't cope",
      'cant cope', 'overwhelmed', 'falling apart',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.worthlessness, [
      // 繁體/粵語 — worthlessness
      '冇用', '沒用', '無用',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.distress, [
      // 繁體/粵語 — nobody cares / nobody loves me
      '冇人理我', '沒人理我', '無人理我',
      '冇人關心', '沒人關心', '無人關心', '冇人愛我', '沒人愛我', '無人愛我',
      '都唔理我', '都唔關心我',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.worthlessness, [
      // 繁體/粵語 — burden cognitions
      '拖累', '累贅', '負累', '負擔',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.distress, [
      // 繁體/粵語 — can't cope / hopeless / collapse
      '頂唔順', '撐唔住', '撐不住', '絕望',
      '孤獨到痛', '崩潰', '崩到爆',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.ideation, [
      // 繁體/粵語 — ideation-adjacent (D1: demoted from acute)
      '想死',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.worthlessness, [
      // 简体 — worthlessness
      '没用',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.distress, [
      // 简体 — nobody cares
      '没人理', '没人关心', '没人爱我',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.worthlessness, [
      // 简体 — burden
      '累赘', '负担',
    ]),
    _TermGroup(DistressLevel.moderateInterrupt, DistressCategory.distress, [
      // 简体 — can't cope / hopeless / collapse
      '撑不住', '顶不住', '绝望', '崩溃',
    ]),
  ];

  // ---------------------------------------------------------------------
  // MODERATE_REVIEW — 19 of the v4 moderate terms: loss / grief and past
  // hardship.  These are the normal vocabulary of a life review: the LLM
  // replies and keeps listening; nothing interrupts; logged for review.
  // ---------------------------------------------------------------------
  static const _moderateReviewGroups = <_TermGroup>[
    _TermGroup(DistressLevel.moderateReview, DistressCategory.lossGrief, [
      // 繁體/粵語 — loss / grief
      '失去咗', '老伴走咗', '剛去世', '過咗身', '過世', '離世', '哀傷', '悲痛',
    ]),
    _TermGroup(DistressLevel.moderateReview, DistressCategory.hardship, [
      // 繁體/粵語 — hardship
      '好辛苦', '辛苦到',
    ]),
    _TermGroup(DistressLevel.moderateReview, DistressCategory.lossGrief, [
      // 简体 — loss / grief
      '老伴走了', '刚去世', '过世', '离世',
    ]),
    _TermGroup(DistressLevel.moderateReview, DistressCategory.lossGrief, [
      // EN — loss / grief
      'lost my husband', 'lost my wife', 'passed away', 'just died', 'grieving',
    ]),
  ];

  static const _lowGroups = <_TermGroup>[
    _TermGroup(DistressLevel.low, DistressCategory.low, [
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
    ]),
  ];

  /// S-7 hopelessness family, placed according to [hopelessnessTier].
  static const _hopelessnessGroup = _TermGroup(
    hopelessnessTier,
    DistressCategory.distress,
    _hopelessnessTerms,
  );

  /// All groups in check order (first hit wins).  The S-7 group is spliced
  /// in at the head of whichever tier [hopelessnessTier] names, so the
  /// acute-first ordering invariant holds for either PI decision.
  static List<_TermGroup> get _orderedGroups => [
        if (hopelessnessTier == DistressLevel.acute) _hopelessnessGroup,
        ..._acuteGroups,
        if (hopelessnessTier == DistressLevel.moderateInterrupt)
          _hopelessnessGroup,
        ..._moderateInterruptGroups,
        if (hopelessnessTier == DistressLevel.moderateReview)
          _hopelessnessGroup,
        ..._moderateReviewGroups,
        if (hopelessnessTier == DistressLevel.low) _hopelessnessGroup,
        ..._lowGroups,
      ];

  /// Lexicon export for docs / spec tooling (`tool/export_spec_inputs.py`
  /// reads the Dart source; this accessor serves the in-app version page
  /// and contract tests).  Returns `(tier, category, term)` in check order.
  static List<(DistressLevel, DistressCategory, String)> get lexicon => [
        for (final g in _orderedGroups)
          for (final t in g.terms) (g.level, g.category, t),
      ];

  /// Terms per tier — used by contract tests to lock the S-1 split
  /// (19 review / 48 interrupt) and the v4 term set.
  static Set<String> termsFor(DistressLevel level) => {
        for (final e in lexicon)
          if (e.$1 == level) e.$3,
      };

  DistressMatch analyze(String text) {
    if (text.trim().isEmpty) return const DistressMatch(DistressLevel.none);
    final lower = text.toLowerCase();
    for (final g in _orderedGroups) {
      for (final t in g.terms) {
        if (lower.contains(t.toLowerCase())) {
          return DistressMatch(g.level, t, g.category);
        }
      }
    }
    return const DistressMatch(DistressLevel.none);
  }
}
