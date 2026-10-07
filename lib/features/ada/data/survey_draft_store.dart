/// T17 — per-screen saving for the ADA and the day-7 open questions.
///
/// One document per administration (doc id = timepoint), written with
/// merge on every screen change.  Firestore rules (firestore.rules,
/// `ada_responses` / `day7_open_responses`) let only the owner read and
/// write it, and freeze it once `status == "submitted"`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

abstract class SurveyDraftStore {
  Future<Map<String, dynamic>?> load(
      String uid, String collection, String docId);

  /// Merge [data] into the document.  When `data['status'] == 'submitted'`
  /// the store also stamps `submittedAt`.
  Future<void> save(String uid, String collection, String docId,
      Map<String, dynamic> data);
}

class FirestoreSurveyDraftStore implements SurveyDraftStore {
  FirestoreSurveyDraftStore({FirebaseFirestore? db}) : _db = db;
  final FirebaseFirestore? _db;

  DocumentReference<Map<String, dynamic>> _ref(
          String uid, String collection, String docId) =>
      (_db ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(uid)
          .collection(collection)
          .doc(docId);

  @override
  Future<Map<String, dynamic>?> load(
      String uid, String collection, String docId) async {
    final snap = await _ref(uid, collection, docId).get();
    return snap.data();
  }

  @override
  Future<void> save(String uid, String collection, String docId,
      Map<String, dynamic> data) {
    return _ref(uid, collection, docId).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
      if (data['status'] == 'submitted')
        'submittedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// Tests and screenshots.
class InMemorySurveyDraftStore implements SurveyDraftStore {
  final Map<String, Map<String, dynamic>> docs = {};
  int saves = 0;

  static String key(String uid, String collection, String docId) =>
      'users/$uid/$collection/$docId';

  @override
  Future<Map<String, dynamic>?> load(
          String uid, String collection, String docId) async =>
      docs[key(uid, collection, docId)];

  @override
  Future<void> save(String uid, String collection, String docId,
      Map<String, dynamic> data) async {
    saves++;
    final k = key(uid, collection, docId);
    docs[k] = {
      ...?docs[k],
      ...data,
      if (data['status'] == 'submitted') 'submittedAt': DateTime.now(),
    };
  }
}
