/// T25 — storage behind the Brief PR v2 scheduler.
///
/// [BriefPrStore] is the small interface the scheduler needs; the App uses
/// [FirestoreBriefPrStore] (`users/{uid}/brief_pr/{sessionId}` plus the
/// scheduler's marks on `users/{uid}/sessions/{sessionId}`), tests and the
/// screenshot harness use [InMemoryBriefPrStore].
///
/// Every write is `set(merge: true)` keyed by the session id: a retry after
/// background / offline / crash never duplicates a record.  Firestore's
/// offline queue keeps an answer that could not be sent and retries it;
/// on top of that [FirestoreBriefPrStore] retries a failed write three
/// times before giving up (the record then stays pending and expires).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/session/chat_session_recorder.dart';
import 'brief_pr_record.dart';

abstract class BriefPrStore {
  Future<BriefPrRecord?> get(String uid, String sessionId);

  /// Create or update the record for `record.sessionId`.
  Future<void> put(BriefPrRecord record);

  /// Invitations for [agentId] whose `invitedDayKey` is [dayKey]
  /// (`due_not_invited` rows excluded — they are not invitations).
  Future<int> countInvited(String uid, String agentId, String dayKey);

  /// Records with `finalStatus == null`.
  Future<List<BriefPrRecord>> pending(String uid);

  /// The scheduler's marks on the session row.
  Future<void> patchSession(
      String uid, String sessionId, Map<String, dynamic> patch);
}

class FirestoreBriefPrStore implements BriefPrStore {
  FirestoreBriefPrStore({FirebaseFirestore? db}) : _db = db;

  final FirebaseFirestore? _db;
  FirebaseFirestore get _firestore => _db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection('users').doc(uid).collection('brief_pr');

  @override
  Future<BriefPrRecord?> get(String uid, String sessionId) async {
    try {
      final snap = await _col(uid).doc(sessionId).get();
      final data = snap.data();
      return data == null ? null : BriefPrRecord.fromMap(data);
    } catch (e) {
      if (kDebugMode) debugPrint('[BriefPrStore] get failed: $e');
      return null;
    }
  }

  @override
  Future<void> put(BriefPrRecord record) async {
    final ref = _col(record.uid).doc(record.sessionId);
    final map = record.toMap();
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await ref.set(map, SetOptions(merge: true));
        return;
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    if (kDebugMode) debugPrint('[BriefPrStore] put failed: $lastError');
  }

  @override
  Future<int> countInvited(String uid, String agentId, String dayKey) async {
    try {
      // Two equalities: no composite index needed.
      final snap = await _col(uid)
          .where('agentId', isEqualTo: agentId)
          .where('invitedDayKey', isEqualTo: dayKey)
          .get();
      return snap.docs
          .map((d) => BriefPrRecord.fromMap(d.data()))
          .where((r) => r != null && r.finalStatus != BriefPrStatus.dueNotInvited)
          .length;
    } catch (e) {
      if (kDebugMode) debugPrint('[BriefPrStore] count failed: $e');
      // Fail closed: an unreadable count must not create a second
      // invitation for the day.
      return 1 << 20;
    }
  }

  @override
  Future<List<BriefPrRecord>> pending(String uid) async {
    try {
      final snap = await _col(uid).where('finalStatus', isNull: true).get();
      return snap.docs
          .map((d) => BriefPrRecord.fromMap(d.data()))
          .whereType<BriefPrRecord>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[BriefPrStore] pending failed: $e');
      return const [];
    }
  }

  @override
  Future<void> patchSession(
          String uid, String sessionId, Map<String, dynamic> patch) =>
      ChatSessionRecorder.patchSession(
          uid: uid, sessionId: sessionId, patch: patch, db: _db);
}

/// In-memory store for tests and the screenshot harness.
class InMemoryBriefPrStore implements BriefPrStore {
  final Map<String, BriefPrRecord> records = {};
  final Map<String, Map<String, dynamic>> sessionPatches = {};
  int putCount = 0;

  /// When set, every write throws so callers' retry paths can be tested.
  bool failWrites = false;

  String _key(String uid, String sid) => '$uid/$sid';

  @override
  Future<BriefPrRecord?> get(String uid, String sessionId) async =>
      records[_key(uid, sessionId)];

  @override
  Future<void> put(BriefPrRecord record) async {
    if (failWrites) throw StateError('write failed');
    putCount++;
    records[_key(record.uid, record.sessionId)] = record;
  }

  @override
  Future<int> countInvited(String uid, String agentId, String dayKey) async =>
      records.values
          .where((r) =>
              r.uid == uid &&
              r.agentId == agentId &&
              r.invitedDayKey == dayKey &&
              r.finalStatus != BriefPrStatus.dueNotInvited)
          .length;

  @override
  Future<List<BriefPrRecord>> pending(String uid) async =>
      records.values.where((r) => r.uid == uid && r.isPending).toList();

  @override
  Future<void> patchSession(
      String uid, String sessionId, Map<String, dynamic> patch) async {
    final k = _key(uid, sessionId);
    sessionPatches[k] = {...?sessionPatches[k], ...patch};
  }
}
