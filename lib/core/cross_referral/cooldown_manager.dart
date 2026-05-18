/// Layer-3 cooldown (Dev Req §5.3).
///
/// After any referral suggestion is shown for a (user, source agent)
/// pair, suppress further suggestions from that source for the next
/// 10 user turns OR 24 hours, whichever is shorter.
///
/// The 10-turn count is tracked in-memory per conversation session.
/// The 24-hour timer is persisted via the proposedAt timestamps on
/// pending referrals in shared_context.
library;

class CooldownState {
  final int turnsSinceLastSuggestion;
  final DateTime? lastSuggestionAt;

  const CooldownState({
    this.turnsSinceLastSuggestion = 999,
    this.lastSuggestionAt,
  });

  bool get isActive {
    if (turnsSinceLastSuggestion < 10) return true;
    final when = lastSuggestionAt;
    if (when == null) return false;
    return DateTime.now().difference(when) < const Duration(hours: 24);
  }
}

class CooldownManager {
  /// Cooldown per source agent id. Lives only for the duration of the
  /// app session — the persistent 24h check uses the timestamp on
  /// pending referrals in shared_context.
  final Map<String, CooldownState> _byAgent = {};

  CooldownState forAgent(String sourceAgentId) {
    return _byAgent[sourceAgentId] ?? const CooldownState();
  }

  /// Call on every user turn to advance the turn counter for [agentId].
  void onUserTurn(String agentId) {
    final cur = _byAgent[agentId];
    if (cur == null) return;
    _byAgent[agentId] = CooldownState(
      turnsSinceLastSuggestion: cur.turnsSinceLastSuggestion + 1,
      lastSuggestionAt: cur.lastSuggestionAt,
    );
  }

  /// Call when a suggestion was just surfaced from [agentId].
  void recordSurfaced(String agentId) {
    _byAgent[agentId] = CooldownState(
      turnsSinceLastSuggestion: 0,
      lastSuggestionAt: DateTime.now(),
    );
  }

  /// Seed the cooldown from a persisted timestamp (e.g. the most
  /// recent referral entry in shared_context). The turn counter
  /// resets to 0 since we can't reconstruct prior turn counts across
  /// app launches; the 24h timer carries authority instead.
  void seedFrom({required String agentId, required DateTime proposedAt}) {
    _byAgent[agentId] = CooldownState(
      turnsSinceLastSuggestion: 0,
      lastSuggestionAt: proposedAt,
    );
  }
}
