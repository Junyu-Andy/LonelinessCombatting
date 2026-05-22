/// Repository for saving and loading the intake questionnaire response.
///
/// Document path: `users/{uid}/onboarding/intake` (Sprint 1 spec).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'intake_response.dart';

class IntakeRepository {
  static const _subcollection = 'onboarding';
  static const _docId = 'intake';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid).collection(_subcollection).doc(_docId);

  /// Upsert the full intake response to Firestore.
  /// Silently ignores errors (guest mode / Firebase unavailable).
  Future<void> save(String uid, IntakeResponse response) async {
    try {
      await _doc(uid).set(response.toFirestore(), SetOptions(merge: true));
    } catch (_) {
      // Graceful degradation: Firebase unavailable in guest mode.
    }
  }

  /// Load an existing intake response. Returns null if not started.
  Future<IntakeResponse?> load(String uid) async {
    try {
      final snap = await _doc(uid).get();
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      return IntakeResponse.fromFirestore(data);
    } catch (_) {
      return null;
    }
  }

  /// Incremental save: marks a part as done and persists to Firestore.
  /// Used for progress resume without requiring a full response object.
  Future<void> markPartDone(String uid, int part) async {
    try {
      await _doc(uid).set(
        {
          'completedParts': FieldValue.arrayUnion([part]),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Graceful degradation.
    }
  }
}
