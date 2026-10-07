/// T17 — per-screen saving for the ADA and the day-7 open questions.
///
/// One document per administration (doc id = timepoint), written with
/// merge on every screen change.  Firestore rules (firestore.rules,
/// `ada_responses` / `day7_open_responses`) let only the owner read and
/// write it, and freeze it once `status == "submitted"`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

/// T17b (ada.md §6.6) — a researcher fills in a participant's answers on
/// the phone.  Participants' documents are owner-only in the rules, so
/// staff read and write through two callables that check the Auth role
/// (`functions/ada.js`: `adaStaffLoad`, `adaStaffSave`).  The server
/// stamps `channel: "phone_by_staff"` and the staff uid, refuses a
/// submitted document, and runs the safety lexicon on any free text.
abstract class StaffSurveyDraftStore implements SurveyDraftStore {
  /// True once after a save whose free text hit the safety lexicon at an
  /// escalation level (the server has written the safety event).
  bool takeSafetyFlag();
}

class CallableStaffSurveyDraftStore implements StaffSurveyDraftStore {
  CallableStaffSurveyDraftStore({FirebaseFunctions? functions})
      : _fn = functions ?? FirebaseFunctions.instanceFor(region: 'asia-east2');
  final FirebaseFunctions _fn;
  bool _flag = false;

  @override
  bool takeSafetyFlag() {
    final f = _flag;
    _flag = false;
    return f;
  }

  @override
  Future<Map<String, dynamic>?> load(
      String uid, String collection, String docId) async {
    final res = await _fn.httpsCallable('adaStaffLoad').call<dynamic>(
        {'uid': uid, 'collection': collection, 'docId': docId});
    final data = res.data;
    if (data is! Map || data['doc'] is! Map) return null;
    return Map<String, dynamic>.from(data['doc'] as Map);
  }

  @override
  Future<void> save(String uid, String collection, String docId,
      Map<String, dynamic> data) async {
    final res = await _fn.httpsCallable('adaStaffSave').call<dynamic>({
      'uid': uid,
      'collection': collection,
      'docId': docId,
      'data': jsonSafe(data),
    });
    final out = res.data;
    if (out is Map && out['safetyEscalation'] == true) _flag = true;
  }

  /// DateTime → ISO string (callables carry JSON only).
  static Object? jsonSafe(Object? v) {
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Map) {
      return {for (final e in v.entries) '${e.key}': jsonSafe(e.value)};
    }
    if (v is List) return v.map(jsonSafe).toList();
    return v;
  }
}

/// Tests and screenshots: [InMemorySurveyDraftStore] with the server's
/// phone-channel stamp and a scripted safety flag.
class InMemoryStaffSurveyDraftStore extends InMemorySurveyDraftStore
    implements StaffSurveyDraftStore {
  bool nextSafetyFlag = false;
  bool _flag = false;

  @override
  bool takeSafetyFlag() {
    final f = _flag;
    _flag = false;
    return f;
  }

  @override
  Future<void> save(String uid, String collection, String docId,
      Map<String, dynamic> data) async {
    await super.save(uid, collection, docId,
        {...data, 'channel': 'phone_by_staff', 'staffUid': 'staff-test'});
    if (nextSafetyFlag) _flag = true;
  }
}
