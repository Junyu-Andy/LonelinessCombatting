/// Layer-1 of the cross-referral routing pipeline (Dev Req §5.1).
///
/// Runs after each user turn, before the LLM call. Returns at most one
/// match per turn (first-match-wins) so we never propose multiple
/// handoffs simultaneously.
library;

import 'triggers_config.dart';

class KeywordFilter {
  const KeywordFilter();

  /// Scan [turn] for a referral candidate while currently inside
  /// [sourceAgentId]. Returns null if no trigger fires, or the trigger
  /// targets the same agent (self-referral).
  ReferralMatch? scan({
    required String turn,
    required String sourceAgentId,
  }) {
    if (turn.trim().isEmpty) return null;
    final lower = turn.toLowerCase();
    for (final trigger in ReferralTriggersConfig.all) {
      if (trigger.targetAgentId == sourceAgentId) continue;
      if (trigger.sourceAgents.isNotEmpty &&
          !trigger.sourceAgents.contains(sourceAgentId)) {
        continue;
      }
      for (final phrase in trigger.phrases) {
        final p = phrase.toLowerCase();
        if (lower.contains(p)) {
          return ReferralMatch(
            trigger: trigger,
            matchedPhrase: phrase,
            fullTurn: turn,
          );
        }
      }
    }
    return null;
  }
}
