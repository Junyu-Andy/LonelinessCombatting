/// Central registry of the three agents that make up the companion app
/// (Siu Yan, Ah Jan / Ah Bak, Tung Tung) plus the tool catalogue.
///
/// Per Developer Requirements §3 — registry entries describe identity,
/// presentation, PPR sub-component (Reis), Weiss provision, and the
/// server-side prompt key that the Cloud Function will resolve.
///
/// The registry stays a pure-Dart data layer: no Firestore, no I/O.
/// Consumers (UI, agent_context, persona_resolver) read from
/// [AgentRegistry.all] / [byId] and never construct AgentDefinition
/// instances ad-hoc.
library;

import 'package:flutter/material.dart';

/// Reis PPR (Perceived Partner Responsiveness) sub-components, per the
/// 3-agent → 3-component design mapping (Design Rationale §5).
enum PprSubcomponent {
  caring, // Siu Yan
  understanding, // Ah Jan / Ah Bak
  socialIntegration, // Tung Tung (also covers Weiss social-integration)
}

/// Ah Jan / Ah Bak gender variants. Persisted in the user profile as
/// `ahJanAhBakVariant`. Other agents have `variant == null`.
enum AgentGenderVariant {
  feminine, // 阿珍
  masculine; // 阿伯

  String get code => switch (this) {
        AgentGenderVariant.feminine => 'feminine',
        AgentGenderVariant.masculine => 'masculine',
      };

  static AgentGenderVariant? tryParse(String? code) {
    switch (code) {
      case 'feminine':
        return AgentGenderVariant.feminine;
      case 'masculine':
        return AgentGenderVariant.masculine;
      default:
        return null;
    }
  }
}

/// Display data for a single variant of an agent (e.g. one entry for
/// 阿珍 and one for 阿伯). Non-gendered agents have a single entry.
class AgentDisplayVariant {
  final String displayNameZh;
  final String displayNameEn;
  final String avatarAsset;
  final AgentGenderVariant? variant;

  const AgentDisplayVariant({
    required this.displayNameZh,
    required this.displayNameEn,
    required this.avatarAsset,
    this.variant,
  });
}

/// Static description of an agent. Holds presentation, mapping to the
/// research constructs, and the server-side prompt key. The actual
/// system prompt text lives in `functions/prompts/{key}.txt` so clients
/// cannot tamper with it (Dev Req §3.2, §8).
class AgentDefinition {
  /// Stable id used as a Firestore subkey under `users/{uid}/agent_contexts/`.
  final String id;

  /// Short role label used in UI copy and analytics tagging.
  final String role;

  /// Coral / sage / sky etc. — used for agent tile accents and the
  /// agent-scoped surfaces. Must be reproducible across arms.
  final Color accentColor;

  /// Which PPR sub-component this agent measures. The Phase A PPR
  /// analysis partitions on this field.
  final PprSubcomponent pprSubcomponent;

  /// Modules whose LLM calls (in Hybrid) MUST go through this agent's
  /// system prompt + agent_context. Pure documentation field; the
  /// actual wiring is done module-by-module in Sprint 2.
  final List<String> primaryModules;

  /// Server-side prompt key (e.g. `siu_yan_v1`). The Cloud Function
  /// resolves the key to the active prompt text. Versioning lives in
  /// the function bundle so client never sees prompt text.
  final String systemPromptKey;

  /// First-turn self-introduction key. Resolved by [FirstIntroHandler]
  /// against [_firstIntroTexts]. We keep intro text on the client (not
  /// the server) because it must render even when the LLM proxy is
  /// unreachable — the first intro is presentational, not generated.
  final String introTextKey;

  /// All display variants. For non-gendered agents, length == 1 and
  /// `variant == null`. For Ah Jan / Ah Bak, length == 2 keyed by
  /// [AgentGenderVariant].
  final List<AgentDisplayVariant> variants;

  /// Short one-line description shown on the Home tile.
  final String tileSubtitleZh;
  final String tileSubtitleEn;

  const AgentDefinition({
    required this.id,
    required this.role,
    required this.accentColor,
    required this.pprSubcomponent,
    required this.primaryModules,
    required this.systemPromptKey,
    required this.introTextKey,
    required this.variants,
    required this.tileSubtitleZh,
    required this.tileSubtitleEn,
  });

  bool get hasGenderVariants => variants.length > 1;

  /// Resolve the display variant for the given selection. Falls back
  /// to the first variant for agents without gender alternatives, and
  /// to the feminine variant when an Ah Jan / Ah Bak selection has
  /// not yet been made (the onboarding step forces a choice but
  /// defensive code keeps the UI renderable mid-flow).
  AgentDisplayVariant resolveVariant(AgentGenderVariant? selected) {
    if (!hasGenderVariants) return variants.first;
    if (selected == null) return variants.first;
    return variants.firstWhere(
      (v) => v.variant == selected,
      orElse: () => variants.first,
    );
  }
}

/// First-turn self-introduction copy (Dev Req §3.3). Stored client-side
/// so it renders even with no network — these strings are presentation,
/// not generated content. The cloud function never returns these.
class AgentIntroText {
  final String zh;
  final String en;
  const AgentIntroText({required this.zh, required this.en});
}

const _firstIntroTexts = <String, AgentIntroText>{
  'siu_yan_v1': AgentIntroText(
    zh: '你好啊，我係小欣，一個 AI 機械人。我會喺日日陪你傾下偈，'
        '聽你今日點。你想點開始都得。',
    en:
        'Hi, I\'m Siu Yan, an AI robot. I\'ll keep you company day by day '
        'and listen to how you\'re doing. We can start however you like.',
  ),
  'ah_jan_ah_bak_v1': AgentIntroText(
    zh: '你好，我係阿珍／阿伯，一個 AI 機械人。我會聽你講你嘅故事，'
        '唔會評論，亦都唔會教你做人。慢慢嚟。',
    en:
        'Hello, I\'m Ah Jan / Ah Bak, an AI robot. I\'ll listen to your '
        'stories without judging or telling you how to live. Take your time.',
  ),
  'tung_tung_v1': AgentIntroText(
    zh: '你好，我係通通，一個 AI 機械人。乜嘢都鍾意聽下，'
        '咩都鍾意傾下。你最近有冇咩想知嘅嘢？',
    en:
        'Hi, I\'m Tung Tung, an AI robot. I\'m curious about almost '
        'anything. What have you been wondering about lately?',
  ),
};

/// Canonical list of agents. Order is the order they appear on Home.
class AgentRegistry {
  AgentRegistry._();

  static const String siuYanId = 'siu_yan';
  static const String ahJanAhBakId = 'ah_jan_ah_bak';
  static const String tungTungId = 'tung_tung';

  /// Returned in display order (Home tile order).
  static const List<AgentDefinition> all = [
    AgentDefinition(
      id: siuYanId,
      role: 'companion',
      accentColor: Color(0xFFF0997B), // coral
      pprSubcomponent: PprSubcomponent.caring,
      primaryModules: ['m2_daily_checkin', 'm9_motivational'],
      systemPromptKey: 'siu_yan_v1',
      introTextKey: 'siu_yan_v1',
      tileSubtitleZh: '日日陪你傾偈，聽你今日點',
      tileSubtitleEn: 'Daily companion — hears how you are',
      variants: [
        AgentDisplayVariant(
          displayNameZh: '小欣',
          displayNameEn: 'Siu Yan',
          avatarAsset: 'assets/agents/siu_yan_robot.png',
        ),
      ],
    ),
    AgentDefinition(
      id: ahJanAhBakId,
      role: 'reflective_peer_listener',
      accentColor: Color(0xFF8AA68A), // sage
      pprSubcomponent: PprSubcomponent.understanding,
      primaryModules: ['m3_reminiscence', 'm5_reflective_dialogue'],
      systemPromptKey: 'ah_jan_ah_bak_v1',
      introTextKey: 'ah_jan_ah_bak_v1',
      tileSubtitleZh: '聽你講你嘅故事，唔評論',
      tileSubtitleEn: 'Reflective listener — hears your story',
      variants: [
        AgentDisplayVariant(
          variant: AgentGenderVariant.feminine,
          displayNameZh: '阿珍',
          displayNameEn: 'Ah Jan',
          avatarAsset: 'assets/agents/ah_jan_robot.png',
        ),
        AgentDisplayVariant(
          variant: AgentGenderVariant.masculine,
          displayNameZh: '阿伯',
          displayNameEn: 'Ah Bak',
          avatarAsset: 'assets/agents/ah_bak_robot.png',
        ),
      ],
    ),
    AgentDefinition(
      id: tungTungId,
      role: 'curious_companion',
      accentColor: Color(0xFF6CA9D6), // sky
      pprSubcomponent: PprSubcomponent.socialIntegration,
      primaryModules: ['interest_chat', 'm8_education_qa'],
      systemPromptKey: 'tung_tung_v1',
      introTextKey: 'tung_tung_v1',
      tileSubtitleZh: '同你傾下你鍾意嘅嘢',
      tileSubtitleEn: 'Curious companion — chats about your interests',
      variants: [
        AgentDisplayVariant(
          displayNameZh: '通通',
          displayNameEn: 'Tung Tung',
          avatarAsset: 'assets/agents/tung_tung_robot.png',
        ),
      ],
    ),
  ];

  static AgentDefinition byId(String id) {
    return all.firstWhere(
      (a) => a.id == id,
      orElse: () => throw ArgumentError('Unknown agent id: $id'),
    );
  }

  static AgentDefinition? tryById(String? id) {
    if (id == null) return null;
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  static AgentIntroText? introTextFor(String key) => _firstIntroTexts[key];
}
