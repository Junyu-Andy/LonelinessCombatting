/// T12 (decision 0021) — who may open the researcher dashboard, and what
/// they may see.
///
/// Roles are Firebase Auth custom claims set by
/// `tool/provision_researcher.js`:
///   * `role: researcher` — blinded.  Sees only arm-neutral sections.
///   * `role: pi`         — unblinded.  Sees everything, incl. per-arm
///                          counts.
/// Anyone else (participants) is denied.  The same roles gate the
/// research-ID lookup in `firestore.rules` (`isUnblinded()`).
library;

enum DashboardAccess {
  denied,
  blinded,
  unblinded;

  static DashboardAccess fromClaims(Map<String, dynamic>? claims) {
    switch (claims?['role']) {
      case 'pi':
        return DashboardAccess.unblinded;
      case 'researcher':
        return DashboardAccess.blinded;
      default:
        return DashboardAccess.denied;
    }
  }

  bool get allowed => this != DashboardAccess.denied;

  /// Per-arm participant counts ("Arm A / Arm B").
  bool get showsArmCounts => this == DashboardAccess.unblinded;

  /// Sections whose data exists in only one arm, so any non-zero number
  /// points at the Hybrid arm: retained transcript turns
  /// (`agent_contexts`), cross-agent referrals (`shared_context`
  /// pendingReferrals) and the Thought-Exercise audit queue (AI
  /// invitation text from Siu Yan).
  bool get showsSingleArmSections => this == DashboardAccess.unblinded;
}
