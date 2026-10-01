/// Brief PR surfacing gate.
///
/// Sprint 1 §3 — decides whether to surface the brief PR modal at
/// session end, and whether the surfaced prompt is the anchor (first per
/// agent per participant).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/phase_a_config.dart';
import '../../../core/session/chat_session_recorder.dart';

class BriefPrGate {
  BriefPrGate({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// M-1 (Phase A baseline 2026-09) — returns true iff the agent session
  /// ended for a non-crisis reason and had at least
  /// [PhaseAConfig.briefPRMinTurns] user turns that reached the model
  /// (fallback turns excluded upstream).
  ///
  /// The pre-baseline 180 s duration floor and once-per-day-per-agent
  /// dedup were dropped: the spec asks for a slider after *every*
  /// qualifying session.  Kept async + parameterised so call sites and
  /// the anchor lookup below are unchanged.
  Future<bool> shouldSurfaceBriefPr({
    required String uid,
    required String agentId,
    required DateTime sessionStartedAt,
    required int exchangeCount,
    String? endReason,
  }) async {
    final minTurns = PhaseAConfig.current.briefPRMinTurns;
    if (kDebugMode) {
      debugPrint('[BriefPrGate] agent=$agentId  turns=$exchangeCount '
          '(need >=$minTurns)  endReason=$endReason');
    }
    if (endReason == SessionEndReason.crisis) return false;
    return exchangeCount >= minTurns;
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
