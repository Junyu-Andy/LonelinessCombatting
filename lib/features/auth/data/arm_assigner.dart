import 'package:cloud_functions/cloud_functions.dart';

import 'user_profile.dart';

/// Calls the `assignArm` Cloud Function (functions/arm.js) after signup and
/// on login while the profile has no arm.
///
/// T19 (decision 0029): Phase B arms are no longer decided here.  The
/// unblinded researcher registers the participant (research ID, W0 paper
/// DJG emotional score, Ah Jan / Ah Bak pairing) and the server allocates
/// from a permuted-block sequence (`enrollParticipant`,
/// functions/randomization.js).  With `meta/randomization_config.enabled`
/// on, `assignArm` returns no arm and the App shows the rule-arm UI until
/// the registration lands (decision 0004).  With it off, `assignArm` gives
/// Phase A / pilot accounts Arm A.
class ArmAssigner {
  const ArmAssigner();

  /// Ask the server for this signed-in user's arm. The profile doc must
  /// already exist. Idempotent: returns the stored arm on repeat calls.
  /// Throws [StateError] when the server returns no arm (Phase B, not yet
  /// registered) — callers keep the profile arm-less and retry next login.
  Future<({ArmAssignment arm, int? cell, String? mode})> assign() async {
    final result = await FirebaseFunctions.instanceFor(region: 'asia-east2')
        .httpsCallable('assignArm')
        .call<Map<String, dynamic>>()
        .timeout(const Duration(seconds: 20));
    final data = Map<String, dynamic>.from(result.data);
    final arm = ArmAssignment.tryParse(data['arm'] as String?);
    if (arm == null) throw StateError('assignArm returned no arm');
    return (
      arm: arm,
      cell: (data['cell'] as num?)?.toInt(),
      mode: data['mode'] as String?,
    );
  }
}
