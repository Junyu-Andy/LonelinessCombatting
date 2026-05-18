/// B.6 — brief PPR controller (Sprint 2.3).
///
/// Encapsulates the policy decisions around when the brief 2-item PPR is
/// surfaced and whether it can be skipped:
///
///   • Trigger: either an explicit "結束" (end-session) tap, or the 60-second
///     idle window from [IdleSessionTimer].
///   • Mandatory-first rule: the FIRST brief PPR shown per-(uid, agentId)
///     pair must be non-dismissable.  Subsequent prompts on the same agent
///     are skippable (稍後 button).  The flag lives on the user profile
///     ([UserProfile.firstPprSeenByAgent]) — never on the PPR doc itself,
///     because the modal needs to decide before any PPR doc exists.
///
/// The UI layer (`BriefPprModal`) calls into this controller for the
/// mandatory decision and for marking the agent as seen on first dismissal.
/// Persisting actual PPR responses still goes through [PprResponseRepository].
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/data/user_profile.dart';

class BriefPprController {
  BriefPprController({required this.available});

  final bool available;

  /// True when this is the first brief PPR for the (profile, agentId)
  /// pair — i.e. the modal must NOT show the 稍後 (Later) button.
  bool isMandatoryFor({
    required UserProfile? profile,
    required String agentId,
  }) {
    if (profile == null) return false; // guest mode — never mandatory
    return !profile.firstPprSeenByAgent.containsKey(agentId);
  }

  /// Mark the first PPR as seen for [agentId].  Called by the modal on
  /// submit OR on first skip (after the mandatory-first prompt the user
  /// is allowed to skip future ones).
  Future<void> markSeen({
    required String uid,
    required String agentId,
    DateTime? when,
  }) async {
    if (!available) return;
    final ts = when ?? DateTime.now();
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        'firstPprSeenByAgent': {agentId: ts.toIso8601String()},
      },
      SetOptions(merge: true),
    );
  }
}
