/// Which memory a participant gets — the client mirror of `inScope` in
/// functions/memory.js.
///
///   off     — memory v0 (per-agent rolling summary), or none for Arm B
///   phaseB  — memory v1, mandatory for Phase B Arm A (assigned while the
///             server was randomising, or — T21 — a pilot-run account the
///             researcher set to Arm A; or a tester account in Arm A —
///             the tester arm switch); no opt-out toggle
///   optIn   — memory v1 for a tester who switched it on in a MEMORY_V1
///             build
///
/// In v1 modes the client skips the v0 fold and v0 prompt block; the
/// server assembles memory. The server's kill switch still wins: with it
/// off a v1 user simply gets no memory, as the spec requires (MEM-1).
library;

import '../../features/auth/data/user_profile.dart';
import '../feature_flags/feature_flags.dart';

enum MemoryMode { off, phaseB, optIn }

extension MemoryModeX on MemoryMode {
  bool get isV1 => this != MemoryMode.off;
}

/// Assignment modes that get the Phase B intervention as allocated
/// (mirror of PHASE_B_MODES in functions/study_period.js).
const phaseBAssignmentModes = {'randomise', 'pilot_designated'};

class MemoryModes {
  const MemoryModes._();

  static MemoryMode of(UserProfile? profile) {
    if (profile == null || profile.arm == ArmAssignment.b) {
      return MemoryMode.off;
    }
    if (FeatureFlags.phaseB &&
        profile.arm == ArmAssignment.a &&
        phaseBAssignmentModes.contains(profile.armAssignmentMode)) {
      return MemoryMode.phaseB;
    }
    // Tester arm switch (functions/tester_arm.js): a tester account in
    // Arm A takes the same path as a pilot-run Hybrid elder.
    if (FeatureFlags.phaseB &&
        profile.arm == ArmAssignment.a &&
        profile.isTester) {
      return MemoryMode.phaseB;
    }
    if (FeatureFlags.memoryV1 && profile.memoryEnabled) {
      return MemoryMode.optIn;
    }
    return MemoryMode.off;
  }
}
