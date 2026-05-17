/// Layer-1 keyword / entity triggers for cross-referral routing
/// (Developer Requirements §5.1).
///
/// Each target agent has a set of trigger phrases that, when seen in
/// a user turn, raise a referral candidacy flag. The flag is then
/// passed to the Layer-2 LLM judgement to decide SURFACE / DEFER / SKIP.
///
/// Triggers ship as Dart constants rather than a runtime-loaded asset
/// because (a) they're small, (b) we want them version-controlled with
/// the matching prompt copy, and (c) parity audits compare arms in part
/// by walking this list.
library;

/// One trigger definition.
class ReferralTrigger {
  /// The agent the user should be referred TO.
  final String targetAgentId;

  /// Substrings to match in the user turn. Matched case-insensitively
  /// for the English entries and literally for the Cantonese entries.
  final List<String> phrases;

  /// Which agents this trigger applies for as the SOURCE (i.e. the
  /// agent currently in the conversation). Empty = applies for all
  /// source agents.
  final List<String> sourceAgents;

  /// Free-text label for analytics / debug.
  final String tag;

  const ReferralTrigger({
    required this.targetAgentId,
    required this.phrases,
    required this.sourceAgents,
    required this.tag,
  });
}

class ReferralTriggersConfig {
  ReferralTriggersConfig._();

  static const List<ReferralTrigger> all = [
    // → Ah Jan / Ah Bak (reminiscence + reflective material)
    ReferralTrigger(
      targetAgentId: 'ah_jan_ah_bak',
      tag: 'ah_jan_time_terms',
      sourceAgents: ['siu_yan', 'tung_tung'],
      phrases: [
        '細個',
        '以前嗰陣',
        '年青嗰陣',
        '嗰啲年',
        '童年',
        '結婚',
        '當年',
        'when i was young',
        'back then',
        'in the old days',
      ],
    ),
    ReferralTrigger(
      targetAgentId: 'ah_jan_ah_bak',
      tag: 'ah_jan_memory_verbs',
      sourceAgents: ['siu_yan', 'tung_tung'],
      phrases: [
        '諗起',
        '想起',
        '記得',
        '回憶',
        'i remember',
        'reminded me of',
      ],
    ),

    // → Tung Tung (interests / curiosity / lookups)
    ReferralTrigger(
      targetAgentId: 'tung_tung',
      tag: 'tung_tung_lookup_intent',
      sourceAgents: ['siu_yan', 'ah_jan_ah_bak'],
      phrases: [
        '我想知',
        '邊度有',
        '係咩',
        '點解',
        '查下',
        'i want to know',
        'where can i find',
        'what is',
      ],
    ),
    ReferralTrigger(
      targetAgentId: 'tung_tung',
      tag: 'tung_tung_interest_keywords',
      sourceAgents: ['siu_yan', 'ah_jan_ah_bak'],
      phrases: [
        '粵劇',
        '馬經',
        '新聞',
        '飲茶',
        '麻雀',
        '種花',
        '老歌',
        'cantonese opera',
        'news',
        'mahjong',
      ],
    ),

    // → Siu Yan (acute emotional / isolation content)
    ReferralTrigger(
      targetAgentId: 'siu_yan',
      tag: 'siu_yan_acute_emotion',
      sourceAgents: ['ah_jan_ah_bak', 'tung_tung'],
      phrases: [
        '好慘',
        '好難過',
        '唔開心',
        '唔知點算',
        'so sad',
        'so hard',
        "i don't know what to do",
      ],
    ),
    ReferralTrigger(
      targetAgentId: 'siu_yan',
      tag: 'siu_yan_isolation',
      sourceAgents: ['ah_jan_ah_bak', 'tung_tung'],
      phrases: [
        '冇人理',
        '孤獨',
        '一個人',
        'lonely',
        'no one',
        'alone',
      ],
    ),
  ];
}

class ReferralMatch {
  final ReferralTrigger trigger;
  final String matchedPhrase;
  final String fullTurn;

  const ReferralMatch({
    required this.trigger,
    required this.matchedPhrase,
    required this.fullTurn,
  });
}
