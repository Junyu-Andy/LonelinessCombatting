/// C20 / decision 0020 — does `consent.sharedContextUse` let one agent
/// use what the participant told another agent?
///
/// Behind [PhaseAConfig.enforceSharedContextConsent] (default OFF).  While
/// the switch is off nothing changes: sharing works as before, whatever
/// the stored consent says.  With the switch on, sharing needs
/// `consent.sharedContextUse == true`; otherwise each agent only uses its
/// own memory.
///
/// App-side (memory v0) places it gates:
///   - Siu Yan's weekly callback to Ah Jan/Ah Bak's reminiscence summary
///     (check_in_arm_a.dart → CrossModuleMemoryService);
///   - the user's sentence copied into `shared_context.pendingReferrals`
///     as `triggerSnippet` (referral_routing_service.dart).
/// Memory v1 is gated on the server (functions/memory.js
/// `effectivePolicy`), reading the same key from `app_config/phase_a`.
///
/// Not gated: the mood score snippet (`recentMoodSummary`) — it is a 1–5
/// score from the home page or check-in, read only by Siu Yan, not
/// another agent's memory.
library;

import '../../features/auth/data/user_profile.dart';
import '../config/phase_a_config.dart';

class SharedContextConsent {
  const SharedContextConsent._();

  /// True when cross-agent sharing is allowed for [profile].
  static bool allowsCrossAgent(UserProfile? profile, {PhaseAConfig? config}) {
    final cfg = config ?? PhaseAConfig.current;
    if (!cfg.enforceSharedContextConsent) return true;
    return profile?.consent.sharedContextUse == true;
  }

  /// The text stored as a pending referral's `triggerSnippet`: the user's
  /// sentence when sharing is allowed, empty otherwise (the target agent
  /// must not receive what was said to the source agent).
  static String referralSnippet(UserProfile? profile, String userTurn,
          {PhaseAConfig? config}) =>
      allowsCrossAgent(profile, config: config) ? userTurn : '';
}
