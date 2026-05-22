/// Centralised compile-time feature flags (Sprint 3).
///
/// Phase A vs Phase B differs on a handful of switches.  Rather than scatter
/// `if (someEnvVar)` checks across the codebase, we collect them here:
///
///   - [weeklyProbeEnabled]      — C.1.  Off in Phase A (kill switch on by
///                                  default).  Server-side cron still emits
///                                  the queue, but the client UI never
///                                  surfaces it.
///   - [phaseB_armBSurfaces]     — C.3.  Off in Phase A.  When false, the
///                                  app renders only Arm A widgets and the
///                                  Arm B branch of ArmGate is treated as
///                                  "never reached".  Hides "問下呢篇"
///                                  buttons + weekly LLM summary card.
///   - [forceArmAEverywhere]     — Mirror of the C.2 server-side
///                                  `forceArmA` gate so the client doesn't
///                                  even attempt to render Arm B paths.
///
/// dart-define overrides (rebuild required):
///   flutter build apk --dart-define=WEEKLY_PROBE=true
///   flutter build apk --dart-define=PHASE_B=true
///
/// Code path: import this file wherever a flag is consulted; do NOT read
/// the dart-define strings directly so flag callsites stay greppable.
library;

class FeatureFlags {
  const FeatureFlags._();

  static const _weeklyProbeDefine =
      String.fromEnvironment('WEEKLY_PROBE', defaultValue: 'false');
  static const _phaseBDefine =
      String.fromEnvironment('PHASE_B', defaultValue: 'false');

  /// C.1 — Weekly loneliness probe surfaced to client.  Defaults OFF for
  /// Phase A so the cron-written queue stays invisible to users.
  static bool get weeklyProbeEnabled => _weeklyProbeDefine == 'true';

  /// C.3 — Phase B surfaces enabled.  Defaults OFF for Phase A.  When
  /// false, [phaseB_armBSurfaces] also forces every Arm B affordance to
  /// be unmounted (not just visually hidden).
  static bool get phaseB => _phaseBDefine == 'true';

  /// C.3 — Phase A: assume forceArmA = true on the server, so render
  /// only Arm A paths.  Returns true unless Phase B is enabled.
  static bool get forceArmAEverywhere => !phaseB;

  /// C.3 — Hybrid-only affordances that must NOT mount in Phase A or for
  /// an Arm B participant.  The arm tutorial / education surface keys
  /// off this set.  Hardcoded — do not extend dynamically.
  static const Set<String> hybridOnlyAffordances = {
    'ask_about_this_article', // "問下呢篇"
    'weekly_llm_summary_card',
    'cross_referral_suggestion',
    'naming_thought_invitation', // Siu Yan negative-cognition card
  };

  /// Returns true when [affordanceKey] is allowed to mount given the
  /// current arm + phase configuration.  Use this instead of bare
  /// `Arm.isA(context)` checks to guarantee the right gating in Phase A.
  static bool allowsAffordance(String affordanceKey, {required bool isArmA}) {
    if (!hybridOnlyAffordances.contains(affordanceKey)) return true;
    if (!isArmA) return false;
    return true;
  }
}
