import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_profile.dart';

/// Block-balanced random arm assignment. Runs as a single Firestore
/// transaction against a global counter doc at `meta/arm_counter`, so two
/// concurrent signups can't both grab the same arm and unbalance the cohort.
///
/// Assignment policy:
///   - If aCount < bCount → assign A.
///   - If bCount < aCount → assign B.
///   - If equal → 50/50 random.
///
/// Counter doc shape: `{aCount: int, bCount: int}`. Auto-created on first
/// run. Per Spec, participants never see which arm they're in; the only
/// trace of assignment is the `arm` field on their user profile and the
/// counter doc, which lives outside `users/`.
class ArmAssigner {
  ArmAssigner({Random? rng}) : _rng = rng ?? Random.secure();

  final Random _rng;

  static const _counterPath = 'meta/arm_counter';

  Future<ArmAssignment> assign(FirebaseFirestore db) async {
    final ref = db.doc(_counterPath);
    return db.runTransaction<ArmAssignment>((txn) async {
      final snap = await txn.get(ref);
      final data = snap.data() ?? const <String, dynamic>{};
      final aCount = (data['aCount'] as int?) ?? 0;
      final bCount = (data['bCount'] as int?) ?? 0;

      final ArmAssignment chosen;
      if (aCount < bCount) {
        chosen = ArmAssignment.a;
      } else if (bCount < aCount) {
        chosen = ArmAssignment.b;
      } else {
        chosen = _rng.nextBool() ? ArmAssignment.a : ArmAssignment.b;
      }

      txn.set(
        ref,
        {
          'aCount': chosen == ArmAssignment.a ? aCount + 1 : aCount,
          'bCount': chosen == ArmAssignment.b ? bCount + 1 : bCount,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return chosen;
    });
  }
}
