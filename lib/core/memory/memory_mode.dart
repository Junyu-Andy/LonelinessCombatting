/// Which memory a participant gets — the client mirror of `inScope` in
/// functions/memory.js.
///
///   off     — memory v0 (per-agent rolling summary), or none for Arm B
///   phaseB  — memory v1, mandatory for Phase B Arm A (assigned while the
///             server was randomising); no opt-out toggle
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

class MemoryModes {
  const MemoryModes._();

  static MemoryMode of(UserProfile? profile) {
    if (profile == null || profile.arm == ArmAssignment.b) {
      return MemoryMode.off;
    }
    if (FeatureFlags.phaseB &&
        profile.arm == ArmAssignment.a &&
        profile.armAssignmentMode == 'randomise') {
      return MemoryMode.phaseB;
    }
    if (FeatureFlags.memoryV1 && profile.memoryEnabled) {
      return MemoryMode.optIn;
    }
    return MemoryMode.off;
  }
}
