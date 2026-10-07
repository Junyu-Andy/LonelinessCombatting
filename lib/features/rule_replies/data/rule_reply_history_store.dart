/// Decision 0023 — "recently used" template ids per user × agent, so a
/// reply is not repeated within [RuleReplyPool.recentWindow] submissions.
///
/// Stored at `users/{uid}/rule_reply_history/{agentId}` as
/// `{recent: [templateId, …] (oldest first), pool_version, updated_at}`.
/// The owner already has read/write on user sub-collections, so no rule
/// change is needed.  Any failure (offline, signed out) reads as "no
/// history" — the pick is still valid, it just may repeat.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'rule_reply_pool.dart';

abstract class RuleReplyHistoryStore {
  Future<List<String>> recent({required String? uid, required String agentId});
  Future<void> save({
    required String? uid,
    required String agentId,
    required List<String> recent,
  });
}

class FirestoreRuleReplyHistoryStore implements RuleReplyHistoryStore {
  final bool available;
  const FirestoreRuleReplyHistoryStore({required this.available});

  DocumentReference<Map<String, dynamic>> _doc(String uid, String agentId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('rule_reply_history')
          .doc(agentId);

  @override
  Future<List<String>> recent({
    required String? uid,
    required String agentId,
  }) async {
    if (!available || uid == null) return const [];
    try {
      // Offline reads can wait for the server; never block the reply.
      final snap = await _doc(
        uid,
        agentId,
      ).get().timeout(const Duration(seconds: 2));
      final raw = snap.data()?['recent'];
      if (raw is List) return raw.whereType<String>().toList();
    } catch (_) {}
    return const [];
  }

  @override
  Future<void> save({
    required String? uid,
    required String agentId,
    required List<String> recent,
  }) async {
    if (!available || uid == null) return;
    try {
      await _doc(uid, agentId).set({
        'recent': recent,
        'pool_version': RuleReplyPool.version,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}

/// Test / offline double.
class InMemoryRuleReplyHistoryStore implements RuleReplyHistoryStore {
  final Map<String, List<String>> _byAgent = {};

  @override
  Future<List<String>> recent({
    required String? uid,
    required String agentId,
  }) async => List.of(_byAgent[agentId] ?? const []);

  @override
  Future<void> save({
    required String? uid,
    required String agentId,
    required List<String> recent,
  }) async {
    _byAgent[agentId] = List.of(recent);
  }
}
