import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_profile.dart';

/// C.2 — stratified block-balanced arm assignment.
///
/// Participants are stratified into 4 cells (0–3) by age group before
/// randomisation, so arm balance holds within each stratum.  Within a cell
/// the same block-balanced algorithm as the original binary counter applies:
///
///   - If cellACount < cellBCount → assign A.
///   - If cellBCount < cellACount → assign B.
///   - If equal → 50/50 random.
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
///
/// **Phase A gate:** [forceArmA] = true assigns every participant to Arm A
/// regardless of strata.  The counter is still incremented (in the correct
/// cell) so balance data is preserved for Phase B transition auditing.
///
/// Strata cell assignment: determined by [strataCell] which maps age group
/// to one of 0–3. Missing / unknown age group → cell 0.
class ArmAssigner {
  ArmAssigner({
    Random? rng,
    bool forceArmA = true,
  })  : _rng = rng ?? Random.secure(),
        _forceArmA = forceArmA;

  final Random _rng;

  /// Phase A gate. When true all participants receive Arm A; the strata
  /// counter still updates so data is available for Phase B analysis.
  final bool _forceArmA;

  static const _counterPath = 'meta/arm_counter';

  /// Map an age-group string (captured at onboarding) to a strata cell 0–3.
  ///
  ///   cell 0 → 60–64
  ///   cell 1 → 65–69
  ///   cell 2 → 70–74
  ///   cell 3 → 75+
  ///
  /// Unknown / null → cell 0 (youngest stratum acts as default).
  static int strataCell(String? ageGroup) {
    switch (ageGroup) {
      case '60-64':
        return 0;
      case '65-69':
        return 1;
      case '70-74':
        return 2;
      case '75+':
        return 3;
      default:
        return 0;
    }
  }

  Future<({ArmAssignment arm, int cell})> assign(
    FirebaseFirestore db, {
    String? ageGroup,
  }) async {
    final cell = strataCell(ageGroup);
    final cellKey = 'cell_$cell';
    final ref = db.doc(_counterPath);

    return db.runTransaction<({ArmAssignment arm, int cell})>((txn) async {
      final snap = await txn.get(ref);
      final data = snap.data() ?? const <String, dynamic>{};
      final cellData = (data[cellKey] as Map<String, dynamic>?) ?? {};
      final aCount = (cellData['aCount'] as int?) ?? 0;
      final bCount = (cellData['bCount'] as int?) ?? 0;

      final ArmAssignment chosen;
      if (_forceArmA) {
        chosen = ArmAssignment.a;
      } else if (aCount < bCount) {
        chosen = ArmAssignment.a;
      } else if (bCount < aCount) {
        chosen = ArmAssignment.b;
      } else {
        chosen = _rng.nextBool() ? ArmAssignment.a : ArmAssignment.b;
      }

      txn.set(
        ref,
        {
          cellKey: {
            'aCount': chosen == ArmAssignment.a ? aCount + 1 : aCount,
            'bCount': chosen == ArmAssignment.b ? bCount + 1 : bCount,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return (arm: chosen, cell: cell);
    });
  }
}
