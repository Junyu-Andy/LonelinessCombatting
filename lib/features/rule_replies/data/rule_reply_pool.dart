/// Decision 0023 — template replies for the Arm B single-submission
/// surfaces: Siu Yan check-in (M2) and Ah Jan / Ah Bak reminiscence (M3).
///
/// T33: the 41 final texts from `docs/spec/copy/rule-templates.md`
/// (10/10, with the research team's character corrections), copied verbatim — `test/final_copy_test.dart` compares every
/// entry against that file.  Edit the spec file first, never only here.
///
/// Each entry belongs to one sub-pool = agent × mood band:
///
///   - `agent`: `siu_yan` / `ah_jan_ah_bak` (AgentRegistry ids); `any`
///     for the one generic entry G-1.
///   - `band`: one per mood face (MoodFace.rank 1..5, see [moodBands]):
///       5 好開心 `very_happy` (X1 / Z1)   4 幾好 `good` (X2 / Z2)
///       3 一般般 `so_so` (X3 / Z3)        2 唔係幾好 `not_good` (X4 / Z4)
///       1 好唔開心 `very_unhappy` (X5 / Z5)
///     plus `none` (no mood picked — reminiscence only, G-1).  The
///     reminiscence grief route (`moderate_review` hit) asks for
///     [bandGrief], which is the Z5 group whatever mood was picked.
///   - `id`: the spec id (X1-1 … Z5-4, G-1); logged as `template_id`.
///   - `zh`: the reply.  Ah Jan and Ah Bak share one pool.  There is no
///     English final copy, so the English UI shows the same text.
///
/// Selection (see `RuleReplyPicker`): first entry of the sub-pool, in list
/// order, not used in the last [recentWindow] replies of this agent; if
/// every entry was used, the least recently used one.  No LLM.
///
/// Telemetry: callers log `rule_template_reply` with the entry id and
/// [version] so analysts can join template × version.
library;

import '../../../core/feature_flags/feature_flags.dart';

typedef RuleReplyEntry = ({
  String id,
  String agent,
  String band,
  String zh,
});

class RuleReplyPool {
  const RuleReplyPool._();

  /// Version lock — bump whenever an entry or [moodBands] changes.
  static const String version = '2026-10-10-final';

  /// Marker that every unreviewed text starts with.
  static const String placeholderMarker = '【占位】';

  /// "Not repeated within the last N replies" (per user × agent).
  static const int recentWindow = 3;

  static const String agentAny = 'any';
  static const String bandNone = 'none';

  /// Reminiscence text that hit `moderate_review` (grief / past hardship).
  static const String bandGrief = 'grief';

  /// Mood (MoodFace.rank, 1..5) → sub-pool band.  Null mood → `none`.
  static const Map<int, String> moodBands = {
    1: 'very_unhappy',
    2: 'not_good',
    3: 'so_so',
    4: 'good',
    5: 'very_happy',
  };

  static String bandFor(int? mood) =>
      mood == null ? bandNone : (moodBands[mood] ?? 'so_so');

  static const String themeCheckIn = 'check_in';
  static String themeForWeek(int weekIndex) => 'w$weekIndex';

  static const List<RuleReplyEntry> entries = [
    (
      id: 'X1-1',
      agent: 'siu_yan',
      band: 'very_happy',
      zh: '聽到你今日咁開心，我都開心埋！有咩好事，得閒講俾我聽呀。',
    ),
    (
      id: 'X1-2',
      agent: 'siu_yan',
      band: 'very_happy',
      zh: '今日心情咁靚，真係好事。記得留返啲時間做自己鍾意嘅嘢。',
    ),
    (
      id: 'X1-3',
      agent: 'siu_yan',
      band: 'very_happy',
      zh: '見到你今日精神咁好，我都放心晒。今日好好享受下啦。',
    ),
    (
      id: 'X1-4',
      agent: 'siu_yan',
      band: 'very_happy',
      zh: '多謝你同我分享好心情！開心嘅日子值得記住，今日最開心係邊一刻呢？',
    ),
    (
      id: 'X2-1',
      agent: 'siu_yan',
      band: 'good',
      zh: '今日過得幾好，聽到都覺得安心。有咩想傾，我喺度。',
    ),
    (
      id: 'X2-2',
      agent: 'siu_yan',
      band: 'good',
      zh: '幾好已經好好㗎喇。今日有冇邊件事令你覺得舒服啲？',
    ),
    (
      id: 'X2-3',
      agent: 'siu_yan',
      band: 'good',
      zh: '多謝你話俾我知。今日餘下嘅時間，都希望你過得自在。',
    ),
    (
      id: 'X2-4',
      agent: 'siu_yan',
      band: 'good',
      zh: '平平穩穩又一日，都係一種福氣。得閒再嚟搵我傾偈。',
    ),
    (
      id: 'X3-1',
      agent: 'siu_yan',
      band: 'so_so',
      zh: '一般般嘅日子都好正常，唔使逼自己一定要好開心。',
    ),
    (
      id: 'X3-2',
      agent: 'siu_yan',
      band: 'so_so',
      zh: '收到。今日如果有啲悶，可以同我傾下，或者睇下 app 入面嘅文章。',
    ),
    (
      id: 'X3-3',
      agent: 'siu_yan',
      band: 'so_so',
      zh: '有啲日子就係平平淡淡，多謝你照實話我知。',
    ),
    (
      id: 'X3-4',
      agent: 'siu_yan',
      band: 'so_so',
      zh: '今日感覺一般，都唔緊要。想講多啲，我隨時都喺度聽。',
    ),
    (
      id: 'X4-1',
      agent: 'siu_yan',
      band: 'not_good',
      zh: '聽到你今日唔係幾好，辛苦你喇。想講多啲我喺度聽，想靜一靜都得。',
    ),
    (
      id: 'X4-2',
      agent: 'siu_yan',
      band: 'not_good',
      zh: '唔開心嘅時候，肯講出嚟已經唔容易。多謝你話俾我知。',
    ),
    (
      id: 'X4-3',
      agent: 'siu_yan',
      band: 'not_good',
      zh: '今日可能有啲難過，唔使急住好返。慢慢嚟，我陪住你。',
    ),
    (
      id: 'X4-4',
      agent: 'siu_yan',
      band: 'not_good',
      zh: '有啲日子係會比較難捱。除咗同我講，如果有信得過嘅人，都可以搵佢哋傾下。',
    ),
    (
      id: 'X5-1',
      agent: 'siu_yan',
      band: 'very_unhappy',
      zh: '聽到你今日好唔開心，我好想陪下你。想講咩都得，我喺度聽。',
    ),
    (
      id: 'X5-2',
      agent: 'siu_yan',
      band: 'very_unhappy',
      zh: '好難受嘅時候，唔使一個人頂住。多謝你肯話俾我知。',
    ),
    (
      id: 'X5-3',
      agent: 'siu_yan',
      band: 'very_unhappy',
      zh: '今日好唔開心，辛苦你喇。你唔使即刻講原因，想講嘅時候我都喺度。',
    ),
    (
      id: 'X5-4',
      agent: 'siu_yan',
      band: 'very_unhappy',
      zh: '如果覺得好難頂，可以打開 app 入面嘅求助資料，嗰度有可以即刻傾嘅熱線。你唔係一個人。',
    ),
    (
      id: 'Z1-1',
      agent: 'ah_jan_ah_bak',
      band: 'very_happy',
      zh: '多謝你同我分享呢段回憶，聽落好溫暖。我哋呢一代人，好多開心嘢都係咁一點一滴累積返嚟。',
    ),
    (
      id: 'Z1-2',
      agent: 'ah_jan_ah_bak',
      band: 'very_happy',
      zh: '講起呢段往事，你應該都笑緊。好嘢嚟㗎，值得記住。',
    ),
    (
      id: 'Z1-3',
      agent: 'ah_jan_ah_bak',
      band: 'very_happy',
      zh: '呢啲美好嘅日子，講多幾次都唔會厭。得閒再講多啲俾我聽。',
    ),
    (
      id: 'Z1-4',
      agent: 'ah_jan_ah_bak',
      band: 'very_happy',
      zh: '聽完你講，我都諗起自己後生嗰陣。多謝你肯分享。',
    ),
    (
      id: 'Z2-1',
      agent: 'ah_jan_ah_bak',
      band: 'good',
      zh: '多謝你寫低呢段回憶。舊時嘅事，慢慢講、慢慢諗，都幾有味道。',
    ),
    (
      id: 'Z2-2',
      agent: 'ah_jan_ah_bak',
      band: 'good',
      zh: '呢段往事講得好好，我好鍾意聽。下次再講多啲。',
    ),
    (
      id: 'Z2-3',
      agent: 'ah_jan_ah_bak',
      band: 'good',
      zh: '人生行咗咁遠，回頭望下，原來有咁多值得講嘅嘢。',
    ),
    (
      id: 'Z2-4',
      agent: 'ah_jan_ah_bak',
      band: 'good',
      zh: '你肯同我分享，我好珍惜。有時間再嚟同我傾舊事。',
    ),
    (
      id: 'Z3-1',
      agent: 'ah_jan_ah_bak',
      band: 'so_so',
      zh: '有啲回憶未必特別開心或者唔開心，但都係人生嘅一部分。多謝你講。',
    ),
    (
      id: 'Z3-2',
      agent: 'ah_jan_ah_bak',
      band: 'so_so',
      zh: '舊時嘅事，有時諗返起都幾平淡，不過都係自己行過嘅路。',
    ),
    (
      id: 'Z3-3',
      agent: 'ah_jan_ah_bak',
      band: 'so_so',
      zh: '多謝你寫低呢段。想再講多啲，或者講第二件事，都得。',
    ),
    (
      id: 'Z3-4',
      agent: 'ah_jan_ah_bak',
      band: 'so_so',
      zh: '慢慢諗，唔使急。我哋可以一個題目一個題目咁傾。',
    ),
    (
      id: 'Z4-1',
      agent: 'ah_jan_ah_bak',
      band: 'not_good',
      zh: '講返呢段往事，心入面可能唔多好受。多謝你肯同我講。',
    ),
    (
      id: 'Z4-2',
      agent: 'ah_jan_ah_bak',
      band: 'not_good',
      zh: '有啲回憶諗起都會有啲難過，咁係好正常嘅。想停一停都得。',
    ),
    (
      id: 'Z4-3',
      agent: 'ah_jan_ah_bak',
      band: 'not_good',
      zh: '你行過咁多難關，真係唔容易。多謝你信我，同我講呢段。',
    ),
    (
      id: 'Z4-4',
      agent: 'ah_jan_ah_bak',
      band: 'not_good',
      zh: '唔開心嘅往事，講出嚟有時會舒服啲，有時會更難受。你覺得點樣舒服就點樣嚟。',
    ),
    (
      id: 'Z5-1',
      agent: 'ah_jan_ah_bak',
      band: 'very_unhappy',
      zh: '呢段回憶好沉重，多謝你肯講出嚟。如果想停低休息下，完全冇問題。',
    ),
    (
      id: 'Z5-2',
      agent: 'ah_jan_ah_bak',
      band: 'very_unhappy',
      zh: '諗起呢啲事，一定好難受。你唔使一個人揹住，想講嘅時候我都喺度聽。',
    ),
    (
      id: 'Z5-3',
      agent: 'ah_jan_ah_bak',
      band: 'very_unhappy',
      zh: '有啲傷心事，過咗幾多年都仲會痛。你肯分享，我好感激。',
    ),
    (
      id: 'Z5-4',
      agent: 'ah_jan_ah_bak',
      band: 'very_unhappy',
      zh: '如果講完覺得好難頂，可以打開 app 入面嘅求助資料，嗰度有可以即刻傾嘅熱線。今日辛苦你喇。',
    ),
    (
      id: 'G-1',
      agent: 'any',
      band: 'none',
      zh: '多謝你同我分享。想再傾，我隨時都喺度。',
    ),
  ];

  /// True while any entry still carries [placeholderMarker].
  static bool get hasPlaceholders =>
      entries.any((e) => e.zh.startsWith(placeholderMarker));

  /// Effective switch for callers.  Off unless RULE_TEMPLATE_REPLIES=true,
  /// and refuses placeholder text unless explicitly allowed (tests and
  /// screenshots only).
  static bool get enabled =>
      FeatureFlags.ruleTemplateReplies &&
      (!hasPlaceholders || FeatureFlags.ruleTemplateRepliesAllowPlaceholder);

  /// The sub-pool for [agent] × [band], in list order.
  ///   - `none` → G-1.
  ///   - [bandGrief] → the Ah Jan / Ah Bak `very_unhappy` group (Z5).
  ///   - anything else empty → G-1, so a reply is always found.
  static List<RuleReplyEntry> subPool({
    required String agent,
    required String band,
  }) {
    List<RuleReplyEntry> pick(String a, String b) =>
        entries.where((e) => e.agent == a && e.band == b).toList();
    final generic = pick(agentAny, bandNone);
    if (band == bandNone) return generic;
    if (band == bandGrief) return pick('ah_jan_ah_bak', 'very_unhappy');
    final exact = pick(agent, band);
    return exact.isNotEmpty ? exact : generic;
  }
}
