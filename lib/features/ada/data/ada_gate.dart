/// T17 (SPEC:C22, decision 0026) — who sees the ADA, the day-7 open
/// questions and the old W2/W4 companion assessment (agent_diff).
///
/// | Build | ADA / day-7 open | Old agent_diff |
/// |---|---|---|
/// | Phase A (default) | `app_config/phaseA_schedule` switches (default off) | shown unless `adaEnabled` (ADA replaces it) |
/// | `PHASE_B=true` | never | only with `LEGACY_AGENT_DIFF_PHASE_B=true` (default off, registry v2 C15) |
library;

import '../../../core/config/phase_a_schedule_config.dart';
import '../../../core/feature_flags/feature_flags.dart';

class AdaGate {
  const AdaGate._();

  static bool adaVisible({bool? phaseB, PhaseAScheduleConfig? config}) {
    if (phaseB ?? FeatureFlags.phaseB) return false;
    return (config ?? PhaseAScheduleConfig.current).adaEnabled;
  }

  static bool day7OpenVisible(
      {bool? phaseB, PhaseAScheduleConfig? config}) {
    if (phaseB ?? FeatureFlags.phaseB) return false;
    return (config ?? PhaseAScheduleConfig.current).day7OpenEndedEnabled;
  }

  static bool legacyAgentDiffVisible({
    bool? phaseB,
    bool? legacyInPhaseB,
    PhaseAScheduleConfig? config,
  }) {
    if (phaseB ?? FeatureFlags.phaseB) {
      return legacyInPhaseB ?? FeatureFlags.legacyAgentDiffInPhaseB;
    }
    return !(config ?? PhaseAScheduleConfig.current).adaEnabled;
  }
}
