/// T12 (decision 0021) — who may open the researcher dashboard, and what
/// they may see.
///
/// Roles are Firebase Auth custom claims set by
/// `tool/provision_researcher.js` (renamed in T19, decision 0029):
///   * `role: blinded`   — blinded staff, including the PI as blinded
///                         assessor.  Sees only arm-neutral sections.
///   * `role: unblinded` — the unblinded researcher.  Sees everything,
///                         incl. per-arm counts.
/// Anyone else (participants, and the pre-T19 names `pi` / `researcher`)
/// is denied.  The same roles gate the research-ID lookup in
/// `firestore.rules` (`isUnblinded()`).
library;

enum DashboardAccess {
  denied,
  blinded,
  unblinded;

  static DashboardAccess fromClaims(Map<String, dynamic>? claims) {
    switch (claims?['role']) {
      case 'unblinded':
        return DashboardAccess.unblinded;
      case 'blinded':
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

  /// T34 — the safety-alert list (`pi_alerts`) and its 確認處理 button.
  /// Only the unblinded researcher: the alert names the source
  /// (AI reply scan exists in one arm only) and the companion, and the
  /// blinded role (W4 assessors) must see nothing of it.  The rules
  /// (`pi_alerts` read: `isUnblinded()`) and the `acknowledgeAlert`
  /// callable enforce the same line server-side.
  bool get showsSafetyAlerts => this == DashboardAccess.unblinded;

  /// T30 — pooled outcome completion rates (`outcomeCompletionSummary`):
  /// unblinded only, and only with the remote switch on; the server checks
  /// both again.
  bool showsOutcomeCompletion({required bool switchOn}) =>
      switchOn && this == DashboardAccess.unblinded;

  /// T30 — with `assessorViewEnabled` on, a `blinded` account is a W4
  /// outcome assessor: it has its own view and nothing of this dashboard.
  DashboardAccess withAssessorView({required bool assessorViewOn}) =>
      assessorViewOn && this == DashboardAccess.blinded
          ? DashboardAccess.denied
          : this;
}
