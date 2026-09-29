/// Client side of memory v1 (see functions/memory.js).
///
/// The server owns every write to `users/{uid}/mem_*`. The client only:
///   • tells the server a chat session ended (`memoryEndSession`), and
///   • lets the user see, delete, and confirm their memory items on the
///     「我記得嘅嘢」 page (firestore.rules allows exactly that).
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// The three layers a user can see and manage.
enum MemoryLayer {
  fact('mem_facts'),
  followup('mem_followups'),
  summary('mem_summaries');

  const MemoryLayer(this.collection);
  final String collection;
}

/// One memory item as shown on the 「我記得嘅嘢」 page.
class MemoryItem {
  final String id;
  final MemoryLayer layer;
  final String agentId;

  /// Heading line: a fact's key, a follow-up's description, or a
  /// summary's date.
  final String title;

  /// Body line: a fact's value, a follow-up's date, or a summary's text.
  final String body;

  /// Sensitive facts wait for the user's go-ahead before any agent uses
  /// them.
  final bool pendingConfirmation;
  final bool sensitive;
  final DateTime? createdAt;

  const MemoryItem({
    required this.id,
    required this.layer,
    required this.agentId,
    required this.title,
    required this.body,
    this.pendingConfirmation = false,
    this.sensitive = false,
    this.createdAt,
  });

  static DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;

  factory MemoryItem.fromDoc(MemoryLayer layer, String id, Map data) {
    final agentId = (data['agent_id'] as String?) ?? '';
    final sensitive = data['sensitivity'] == 'sensitive';
    switch (layer) {
      case MemoryLayer.fact:
        return MemoryItem(
          id: id,
          layer: layer,
          agentId: agentId,
          title: (data['key'] as String?) ?? '',
          body: (data['value'] as String?) ?? '',
          pendingConfirmation: data['status'] == 'pending_confirmation',
          sensitive: sensitive,
          createdAt: _ts(data['created_at']),
        );
      case MemoryLayer.followup:
        return MemoryItem(
          id: id,
          layer: layer,
          agentId: agentId,
          title: (data['description'] as String?) ?? '',
          body: (data['due_date'] as String?) ?? '',
          sensitive: sensitive,
          createdAt: _ts(data['created_at']),
        );
      case MemoryLayer.summary:
        return MemoryItem(
          id: id,
          layer: layer,
          agentId: agentId,
          title: (data['day_key'] as String?) ?? '',
          body: (data['summary'] as String?) ?? '',
          sensitive: sensitive,
          createdAt: _ts(data['ended_at']),
        );
    }
  }
}

class MemoryV1Service {
  const MemoryV1Service();

  /// Ask the server to extract this agent's session into memory. Fire and
  /// forget: if it fails, the server's 30-minute sweep picks it up.
  Future<void> endSession(String agentId) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-east2')
          .httpsCallable('memoryEndSession')
          .call(<String, dynamic>{'agentId': agentId})
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      if (kDebugMode) debugPrint('[memory_v1] endSession failed: $e');
    }
  }

  CollectionReference<Map<String, dynamic>> _col(
          String uid, MemoryLayer layer) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(layer.collection);

  /// Items the user should see: active and awaiting-confirmation facts,
  /// pending follow-ups, and recent summaries.
  Stream<List<MemoryItem>> watch(String uid, MemoryLayer layer) {
    final Query<Map<String, dynamic>> q = switch (layer) {
      MemoryLayer.fact => _col(uid, layer)
          .where('status', whereIn: ['active', 'pending_confirmation']),
      MemoryLayer.followup => _col(uid, layer)
          .where('status', whereIn: ['pending', 'asked']),
      MemoryLayer.summary =>
        _col(uid, layer).orderBy('ended_at', descending: true).limit(20),
    };
    return q.snapshots().map((snap) => snap.docs
        .map((d) => MemoryItem.fromDoc(layer, d.id, d.data()))
        .toList());
  }

  Future<void> delete(String uid, MemoryItem item) =>
      _col(uid, item.layer).doc(item.id).delete();

  /// pending_confirmation → active; the rules allow no other client edit.
  Future<void> confirm(String uid, MemoryItem item) =>
      _col(uid, MemoryLayer.fact).doc(item.id).update({'status': 'active'});
}
