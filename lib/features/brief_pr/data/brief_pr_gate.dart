/// Brief PR surfacing gate.
///
/// Sprint 1 §3 — decides whether to surface the brief PR modal at
/// session end, and whether the surfaced prompt is the anchor (first per
/// agent per participant).

import 'package:cloud_firestore/cloud_firestore.dart';

class BriefPrGate {
  BriefPrGate({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Returns true iff:
  ///   - the session lasted ≥ 180 s,
  ///   - it had ≥ 3 exchange turns (user turns), and
  ///   - no brief_pr has already been recorded today for this (agentId).
  Future<bool> shouldSurfaceBriefPr({
    required String uid,
    required String agentId,
    required DateTime sessionStartedAt,
    required int exchangeCount,
  }) async {
    final now = DateTime.now();
    final duration = now.difference(sessionStartedAt).inSeconds;
    if (duration < 180) return false;
    if (exchangeCount < 3) return false;

    try {
      // Single-field query + client-side date filter ON PURPOSE: the
      // original equality+range query needs a composite index that is
      // not deployed anywhere (no firestore.indexes.json), so it threw
      // failed-precondition and the catch below turned the "once per
      // day" gate into "every session".  Per-user brief_pr stays tiny,
      // so filtering client-side is free and index-proof.
      final startOfToday = DateTime(now.year, now.month, now.day);
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('brief_pr')
          .where('agentId', isEqualTo: agentId)
          .get();
      final alreadyToday = snap.docs.any((d) {
        final raw = d.data()['promptedAt'];
        final t = raw is Timestamp
            ? raw.toDate()
            : (raw is String ? DateTime.tryParse(raw) : null);
        return t != null && !t.isBefore(startOfToday);
      });
      return !alreadyToday;
    } catch (_) {
      // Firebase unavailable (guest mode) — surface anyway so dev/demo
      // flow can be walked. Production data won't be lost because the
      // write below also tolerates Firebase being unreachable.
      return true;
    }
  }

  /// Returns true iff no prior brief_pr document exists for this
  /// (uid, agentId) pair. Anchor prompt suppresses the skip button.
  Future<bool> isAnchorPromptFor({
    required String uid,
    required String agentId,
  }) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('brief_pr')
          .where('agentId', isEqualTo: agentId)
          .limit(1)
          .get();
      return snap.docs.isEmpty;
    } catch (_) {
      return true;
    }
  }
}
