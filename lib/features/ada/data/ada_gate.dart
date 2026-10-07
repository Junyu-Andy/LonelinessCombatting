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

/// T17b — parts of the day-7 flow (ada.md §6.2), in order.
enum Day7Part { ada, open }

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

  /// T17b — what the day-7 flow holds: the ADA full form (when the ADA is
  /// on and a `day7` timepoint is configured) and the open questions.
  /// Empty in a Phase B build.
  static List<Day7Part> day7Parts(
      {bool? phaseB, PhaseAScheduleConfig? config}) {
    if (phaseB ?? FeatureFlags.phaseB) return const [];
    final c = config ?? PhaseAScheduleConfig.current;
    return [
      if (c.adaEnabled && c.timepointById(kDay7TimepointId) != null)
        Day7Part.ada,
      if (c.day7OpenEndedEnabled) Day7Part.open,
    ];
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
