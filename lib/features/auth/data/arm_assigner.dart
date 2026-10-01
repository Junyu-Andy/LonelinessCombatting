import 'package:cloud_functions/cloud_functions.dart';

import 'user_profile.dart';

/// C.2 — stratified block-balanced arm assignment (Phase B Proposal §4.4).
///
/// Phase B stratifies on TWO factors, producing 4 cells:
///   - Baseline UCLA-LS-V3 total score (median split: 30–44 "low" vs
///     45–60 "high")
///   - Age band (60–69 vs ≥70)
///
/// Cell layout:
///   cell_0  → low loneliness × 60–69
///   cell_1  → low loneliness × 70+
///   cell_2  → high loneliness × 60–69
///   cell_3  → high loneliness × 70+
///
/// Phase A is single-arm (no randomisation) but the schema is wired
/// in Phase A so the cron-side counter is ready for Phase B.
///
/// Within a cell, block-balanced assignment uses random block sizes
/// of 4 or 6 (per Phase B §4.4 — varying block size prevents allocation
/// prediction).  Implementation: the simple "if A<B then A else if B<A
/// then B else 50/50" policy approximates this within a single
/// transaction.  A future Phase B-specific block-randomisation table
/// can replace this if precise block-size variation matters.
///
/// **Assignment runs on the server** (`assignArm` Cloud Function,
/// functions/arm.js) so a client cannot influence its own arm; the
/// stratification and balancing rule there mirrors [strataCell] below.
/// Phase A vs Phase B is the server's `app_config/arm_assignment.randomise`
/// flag (absent = everyone Arm A); the counter increments in the right
/// cell either way so Phase B balance data is preserved.
///
/// Counter doc shape:
/// ```
/// meta/arm_counter: {
///   cell_0: { aCount: int, bCount: int },
///   cell_1: { aCount: int, bCount: int },
///   cell_2: { aCount: int, bCount: int },
///   cell_3: { aCount: int, bCount: int },
///   updatedAt: Timestamp,
/// }
/// ```
class ArmAssigner {
  const ArmAssigner();

  /// UCLA-LS-V3 median split per Phase B §4.4.  Total possible range is
  /// 20–80; eligibility is 30–60, with 44 as the median that splits
  /// the eligible distribution roughly in half.
  static const _uclaMedianSplit = 44;

  /// Map (UCLA-LS-V3 total, age in years) → strata cell 0–3.
  ///
  /// cell_0: low loneliness × 60–69
  /// cell_1: low loneliness × ≥70
  /// cell_2: high loneliness × 60–69
  /// cell_3: high loneliness × ≥70
  ///
  /// Missing baseline → cell 0 (most common stratum acts as default;
  /// for Phase A this doesn't matter since everyone is Arm A).
  static int strataCell({
    required int? uclaScore,
    required int? ageYears,
  }) {
    final lonelinessHigh =
        (uclaScore ?? _uclaMedianSplit) > _uclaMedianSplit;
    final older = (ageYears ?? 60) >= 70;
    if (!lonelinessHigh && !older) return 0;
    if (!lonelinessHigh && older) return 1;
    if (lonelinessHigh && !older) return 2;
    return 3;
  }

  /// Convert the [ageGroup] enum string used in onboarding to a numeric
  /// year estimate (midpoint of the band).
  static int? ageYearsFromGroup(String? ageGroup) {
    switch (ageGroup) {
      case '60-64':
        return 62;
      case '65-69':
        return 67;
      case '70-74':
        return 72;
      case '75+':
        return 77;
      default:
        return null;
    }
  }

  /// Ask the server to assign this signed-in user's arm. The profile doc
  /// must already exist (the server reads ageGroup / baselineUclaScore
  /// from it). Idempotent: returns the stored arm on repeat calls.
  Future<({ArmAssignment arm, int? cell})> assign() async {
    final result = await FirebaseFunctions.instanceFor(region: 'asia-east2')
        .httpsCallable('assignArm')
        .call<Map<String, dynamic>>()
        .timeout(const Duration(seconds: 20));
    final data = Map<String, dynamic>.from(result.data);
    final arm = ArmAssignment.tryParse(data['arm'] as String?);
    if (arm == null) throw StateError('assignArm returned no arm');
    return (arm: arm, cell: (data['cell'] as num?)?.toInt());
  }
}
