/// T6 — debug "reset my data" helper for internal testers.
///
/// Deletes the current user's own memory-related subcollections so a tester
/// can re-walk the onboarding-seed / rolling-summary flow from a clean state.
/// Owner Firestore rules (`users/{uid}/{document=**}`) already permit this —
/// no rules change required. No-op in guest mode.
///
/// Scope (deliberately narrow — never touches consent, profile, arm, PPR,
/// safety_events, or research telemetry):
///   • agent_contexts/*  — rollingSummary, shortTermBuffer, fold status
///   • shared_context/*   — recentMood snippet, pending referrals
///   • daily_mood/*       — mood log
///   • memory/{moduleId}/entries/* — cross-module rolling summaries
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class TesterTools {
  TesterTools({required this.available});

  final bool available;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Returns the number of documents deleted (best-effort).
  Future<int> resetMyData(String uid) async {
    if (!available) return 0;
    var deleted = 0;
    for (final sub in const ['agent_contexts', 'shared_context', 'daily_mood']) {
      deleted += await _deleteFlat(uid, sub);
    }
    deleted += await _deleteMemory(uid);
    return deleted;
  }

  Future<int> _deleteFlat(String uid, String sub) async {
    try {
      final snap =
          await _db.collection('users').doc(uid).collection(sub).get();
      for (final d in snap.docs) {
        await d.reference.delete();
      }
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _deleteMemory(String uid) async {
    var n = 0;
    try {
      final mem =
          await _db.collection('users').doc(uid).collection('memory').get();
      for (final m in mem.docs) {
        final entries = await m.reference.collection('entries').get();
        for (final e in entries.docs) {
          await e.reference.delete();
          n++;
        }
        await m.reference.delete();
      }
    } catch (_) {}
    return n;
  }
}
