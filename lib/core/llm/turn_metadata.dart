/// B.2 — per-turn metadata written alongside every LLM response.
///
/// Arm A turns populate all fields from the CF response.
/// Arm B turns write this with [systemPromptHash] = null so the schema
/// is symmetric across arms (required for parity audit).
library;

class TurnMetadata {
  /// SHA-256 hex digest of the resolved system prompt (after all variable
  /// substitution and whitespace normalisation).  Null for Arm B turns.
  final String? systemPromptHash;

  /// The prompt key passed to the CF (e.g. `siu_yan_v1`).
  final String? promptKey;

  /// Which agent generated this turn.
  final String? agentId;

  /// Client-side session identifier from [AnalyticsService.sessionId].
  final String? sessionId;

  const TurnMetadata({
    this.systemPromptHash,
    this.promptKey,
    this.agentId,
    this.sessionId,
  });

  /// Empty metadata for Arm B turns — null hash keeps the schema symmetric.
  const TurnMetadata.armB({String? agentId, String? sessionId})
      : systemPromptHash = null,
        promptKey = null,
        agentId = agentId,
        sessionId = sessionId;

  Map<String, dynamic> toMap() => {
        'systemPromptHash': systemPromptHash,
        'promptKey': promptKey,
        'agentId': agentId,
        'sessionId': sessionId,
      };

  factory TurnMetadata.fromMap(Map<String, dynamic> map) => TurnMetadata(
        systemPromptHash: map['systemPromptHash'] as String?,
        promptKey: map['promptKey'] as String?,
        agentId: map['agentId'] as String?,
        sessionId: map['sessionId'] as String?,
      );
}
