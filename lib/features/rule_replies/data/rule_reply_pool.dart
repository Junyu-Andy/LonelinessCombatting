/// Decision 0023 — template replies for the Arm B single-submission
/// surfaces: Siu Yan check-in (M2) and Ah Jan / Ah Bak reminiscence (M3).
///
/// Format mirrors the Tung Tung pools ([TungTungRulePool],
/// [TungTungRuleResponder]): a hardcoded, version-locked list of records.
/// Each entry belongs to one sub-pool = agent × theme × mood band:
///
///   - `agent`: `siu_yan` / `ah_jan_ah_bak` (AgentRegistry ids).
///   - `theme`: `check_in` for Siu Yan; `w1`–`w4` for the weekly
///     reminiscence themes (ReminiscenceTheme.weekIndex).
///   - `band`: `low` (mood 1–2) / `mid` (3) / `high` (4–5) / `none` (no
///     mood picked — reminiscence only, the picker is optional there).
///     The 1–5 → band map is [moodBands]; change it there, not in callers.
///   - `id`: stable, unique; logged as `template_id`.
///   - `zh` / `en`: the reply.  Never quote the user's words and never
///     name the agent (Ah Jan / Ah Bak share one pool).
///
/// Selection (see `RuleReplyPicker`): first entry of the sub-pool, in list
/// order, not used in the last [recentWindow] replies of this agent; if
/// every entry was used, the least recently used one.  No LLM.
///
/// Every text below is a 【占位】 placeholder.  The research team writes
/// the final Cantonese; until then [enabled] stays false even when the
/// RULE_TEMPLATE_REPLIES flag is on (see [hasPlaceholders]).
///
/// Telemetry: callers log `rule_template_reply` with the entry id and
/// [version] so analysts can join template × version.
library;

import '../../../core/feature_flags/feature_flags.dart';

typedef RuleReplyEntry = ({
  String id,
  String agent,
  String theme,
  String band,
  String zh,
  String en,
});

class RuleReplyPool {
  const RuleReplyPool._();

  /// Version lock — bump whenever an entry or [moodBands] changes.
  static const String version = '2026-10-v0-placeholder';

  /// Marker that every unreviewed text starts with.
  static const String placeholderMarker = '【占位】';

  /// "Not repeated within the last N replies" (per user × agent).
  static const int recentWindow = 3;

  /// Mood (MoodFace.rank, 1..5) → sub-pool band.  Null mood → `none`.
  static const Map<int, String> moodBands = {
    1: 'low',
    2: 'low',
    3: 'mid',
    4: 'high',
    5: 'high',
  };

  static String bandFor(int? mood) =>
      mood == null ? 'none' : (moodBands[mood] ?? 'mid');

  static const String themeCheckIn = 'check_in';
  static String themeForWeek(int weekIndex) => 'w$weekIndex';

  static const List<RuleReplyEntry> entries = [
    // ── 小欣 · 簽到（m2_check_in）。小欣 B 必選心情，所以冇 none 子池。
    (
      id: 'sy_ci_low_1',
      agent: 'siu_yan',
      theme: 'check_in',
      band: 'low',
      zh: '【占位】小欣·簽到·心情差·第1條',
      en: '[PLACEHOLDER] Siu Yan · check-in · low mood · #1',
    ),
    (
      id: 'sy_ci_low_2',
      agent: 'siu_yan',
      theme: 'check_in',
      band: 'low',
      zh: '【占位】小欣·簽到·心情差·第2條',
      en: '[PLACEHOLDER] Siu Yan · check-in · low mood · #2',
    ),
    (
      id: 'sy_ci_low_3',
      agent: 'siu_yan',
      theme: 'check_in',
      band: 'low',
      zh: '【占位】小欣·簽到·心情差·第3條',
      en: '[PLACEHOLDER] Siu Yan · check-in · low mood · #3',
    ),
    (
      id: 'sy_ci_mid_1',
      agent: 'siu_yan',
      theme: 'check_in',
      band: 'mid',
      zh: '【占位】小欣·簽到·心情中·第1條',
      en: '[PLACEHOLDER] Siu Yan · check-in · so-so mood · #1',
    ),
    (
      id: 'sy_ci_mid_2',
      agent: 'siu_yan',
      theme: 'check_in',
      band: 'mid',
      zh: '【占位】小欣·簽到·心情中·第2條',
      en: '[PLACEHOLDER] Siu Yan · check-in · so-so mood · #2',
    ),
    (
      id: 'sy_ci_mid_3',
      agent: 'siu_yan',
      theme: 'check_in',
      band: 'mid',
      zh: '【占位】小欣·簽到·心情中·第3條',
      en: '[PLACEHOLDER] Siu Yan · check-in · so-so mood · #3',
    ),
    (
      id: 'sy_ci_high_1',
      agent: 'siu_yan',
      theme: 'check_in',
      band: 'high',
      zh: '【占位】小欣·簽到·心情好·第1條',
      en: '[PLACEHOLDER] Siu Yan · check-in · good mood · #1',
    ),
    (
      id: 'sy_ci_high_2',
      agent: 'siu_yan',
      theme: 'check_in',
      band: 'high',
      zh: '【占位】小欣·簽到·心情好·第2條',
      en: '[PLACEHOLDER] Siu Yan · check-in · good mood · #2',
    ),
    (
      id: 'sy_ci_high_3',
      agent: 'siu_yan',
      theme: 'check_in',
      band: 'high',
      zh: '【占位】小欣·簽到·心情好·第3條',
      en: '[PLACEHOLDER] Siu Yan · check-in · good mood · #3',
    ),
    // ── 阿珍/阿伯 · 回憶第 1 週（m3_reminiscence_w1）
    (
      id: 'aj_w1_low_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w1',
      band: 'low',
      zh: '【占位】阿珍·回憶第1週·心情差·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 1 · low mood · #1',
    ),
    (
      id: 'aj_w1_low_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w1',
      band: 'low',
      zh: '【占位】阿珍·回憶第1週·心情差·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 1 · low mood · #2',
    ),
    (
      id: 'aj_w1_mid_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w1',
      band: 'mid',
      zh: '【占位】阿珍·回憶第1週·心情中·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 1 · so-so mood · #1',
    ),
    (
      id: 'aj_w1_mid_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w1',
      band: 'mid',
      zh: '【占位】阿珍·回憶第1週·心情中·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 1 · so-so mood · #2',
    ),
    (
      id: 'aj_w1_high_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w1',
      band: 'high',
      zh: '【占位】阿珍·回憶第1週·心情好·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 1 · good mood · #1',
    ),
    (
      id: 'aj_w1_high_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w1',
      band: 'high',
      zh: '【占位】阿珍·回憶第1週·心情好·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 1 · good mood · #2',
    ),
    (
      id: 'aj_w1_none_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w1',
      band: 'none',
      zh: '【占位】阿珍·回憶第1週·心情未選·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 1 · no mood picked · #1',
    ),
    (
      id: 'aj_w1_none_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w1',
      band: 'none',
      zh: '【占位】阿珍·回憶第1週·心情未選·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 1 · no mood picked · #2',
    ),
    // ── 阿珍/阿伯 · 回憶第 2 週（m3_reminiscence_w2）
    (
      id: 'aj_w2_low_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w2',
      band: 'low',
      zh: '【占位】阿珍·回憶第2週·心情差·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 2 · low mood · #1',
    ),
    (
      id: 'aj_w2_low_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w2',
      band: 'low',
      zh: '【占位】阿珍·回憶第2週·心情差·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 2 · low mood · #2',
    ),
    (
      id: 'aj_w2_mid_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w2',
      band: 'mid',
      zh: '【占位】阿珍·回憶第2週·心情中·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 2 · so-so mood · #1',
    ),
    (
      id: 'aj_w2_mid_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w2',
      band: 'mid',
      zh: '【占位】阿珍·回憶第2週·心情中·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 2 · so-so mood · #2',
    ),
    (
      id: 'aj_w2_high_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w2',
      band: 'high',
      zh: '【占位】阿珍·回憶第2週·心情好·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 2 · good mood · #1',
    ),
    (
      id: 'aj_w2_high_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w2',
      band: 'high',
      zh: '【占位】阿珍·回憶第2週·心情好·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 2 · good mood · #2',
    ),
    (
      id: 'aj_w2_none_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w2',
      band: 'none',
      zh: '【占位】阿珍·回憶第2週·心情未選·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 2 · no mood picked · #1',
    ),
    (
      id: 'aj_w2_none_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w2',
      band: 'none',
      zh: '【占位】阿珍·回憶第2週·心情未選·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 2 · no mood picked · #2',
    ),
    // ── 阿珍/阿伯 · 回憶第 3 週（m3_reminiscence_w3）
    (
      id: 'aj_w3_low_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w3',
      band: 'low',
      zh: '【占位】阿珍·回憶第3週·心情差·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 3 · low mood · #1',
    ),
    (
      id: 'aj_w3_low_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w3',
      band: 'low',
      zh: '【占位】阿珍·回憶第3週·心情差·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 3 · low mood · #2',
    ),
    (
      id: 'aj_w3_mid_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w3',
      band: 'mid',
      zh: '【占位】阿珍·回憶第3週·心情中·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 3 · so-so mood · #1',
    ),
    (
      id: 'aj_w3_mid_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w3',
      band: 'mid',
      zh: '【占位】阿珍·回憶第3週·心情中·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 3 · so-so mood · #2',
    ),
    (
      id: 'aj_w3_high_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w3',
      band: 'high',
      zh: '【占位】阿珍·回憶第3週·心情好·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 3 · good mood · #1',
    ),
    (
      id: 'aj_w3_high_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w3',
      band: 'high',
      zh: '【占位】阿珍·回憶第3週·心情好·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 3 · good mood · #2',
    ),
    (
      id: 'aj_w3_none_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w3',
      band: 'none',
      zh: '【占位】阿珍·回憶第3週·心情未選·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 3 · no mood picked · #1',
    ),
    (
      id: 'aj_w3_none_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w3',
      band: 'none',
      zh: '【占位】阿珍·回憶第3週·心情未選·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 3 · no mood picked · #2',
    ),
    // ── 阿珍/阿伯 · 回憶第 4 週（m3_reminiscence_w4）
    (
      id: 'aj_w4_low_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w4',
      band: 'low',
      zh: '【占位】阿珍·回憶第4週·心情差·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 4 · low mood · #1',
    ),
    (
      id: 'aj_w4_low_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w4',
      band: 'low',
      zh: '【占位】阿珍·回憶第4週·心情差·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 4 · low mood · #2',
    ),
    (
      id: 'aj_w4_mid_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w4',
      band: 'mid',
      zh: '【占位】阿珍·回憶第4週·心情中·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 4 · so-so mood · #1',
    ),
    (
      id: 'aj_w4_mid_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w4',
      band: 'mid',
      zh: '【占位】阿珍·回憶第4週·心情中·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 4 · so-so mood · #2',
    ),
    (
      id: 'aj_w4_high_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w4',
      band: 'high',
      zh: '【占位】阿珍·回憶第4週·心情好·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 4 · good mood · #1',
    ),
    (
      id: 'aj_w4_high_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w4',
      band: 'high',
      zh: '【占位】阿珍·回憶第4週·心情好·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 4 · good mood · #2',
    ),
    (
      id: 'aj_w4_none_1',
      agent: 'ah_jan_ah_bak',
      theme: 'w4',
      band: 'none',
      zh: '【占位】阿珍·回憶第4週·心情未選·第1條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 4 · no mood picked · #1',
    ),
    (
      id: 'aj_w4_none_2',
      agent: 'ah_jan_ah_bak',
      theme: 'w4',
      band: 'none',
      zh: '【占位】阿珍·回憶第4週·心情未選·第2條',
      en: '[PLACEHOLDER] Ah Jan · reminiscence week 4 · no mood picked · #2',
    ),
  ];

  /// True while any entry still carries [placeholderMarker].
  static bool get hasPlaceholders =>
      entries.any((e) => e.zh.startsWith(placeholderMarker));

  /// Effective switch for callers.  Off unless RULE_TEMPLATE_REPLIES=true,
  /// and refuses placeholder text unless explicitly allowed.
  static bool get enabled =>
      FeatureFlags.ruleTemplateReplies &&
      (!hasPlaceholders || FeatureFlags.ruleTemplateRepliesAllowPlaceholder);

  /// The sub-pool for [agent] × [theme] × [band], in list order.  Falls
  /// back to the same agent × theme with band `mid` when the requested
  /// band is empty (e.g. `none` on check-in), so a reply is always found.
  static List<RuleReplyEntry> subPool({
    required String agent,
    required String theme,
    required String band,
  }) {
    List<RuleReplyEntry> pick(String b) => entries
        .where((e) => e.agent == agent && e.theme == theme && e.band == b)
        .toList();
    final exact = pick(band);
    return exact.isNotEmpty ? exact : pick('mid');
  }
}
