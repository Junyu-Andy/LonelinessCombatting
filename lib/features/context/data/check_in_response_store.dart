/// 1020 F (3) — the chat check-in's answers in `users/{uid}/check_in_responses`.
///
/// One document per check-in, created at the first answer (Q1) and merged
/// after every later step, so an abandoned check-in still leaves what was
/// answered (`completed: false`).  Both arms write the same fields.  Rows
/// written by the old rule-arm form (switch off) keep their old fields
/// (`mood`, `talked`, `social_day`, `significant_event`, `note`) and have
/// no `flow`; new rows carry `flow: 'chat_v2'` and `schema_version: 2`.
///
/// Fields (new rows):
///
/// ```
/// arm             'A' | 'B'
/// flow            'chat_v2'
/// schema_version  2
/// copy_version    CheckInChatCopy.version (wording of the questions)
/// date_iso        'YYYY-MM-DD', phone date of the check-in (as before)
/// study_day       int | null   W0 = day 0 (lib/core/scheduling/study_week)
/// study_week      int | null   ceil(study_day / 7); 0 on / before W0
/// session_id      the agent session the check-in belongs to
/// answers         map keyed by question id:
///   Q1  {question_id, value, label, score}   value very_happy | good | so_so
///                                            | not_good | very_unhappy |
///                                            prefer_not; score 5..1 / null
///   Q2  {question_id, value, label, index}   none | a_little | quite_a_bit
///                                            | a_lot; index 0..3
///   Q3  {question_id, value, label, index}   none | small | big; index 0..2
///   Q3b {question_id, skipped, text}         only when Q3 was small / big
///   Q4  {question_id, skipped, text}
///   Q5  {question_id, value, label}          yes | no
/// questions_shown ['Q0', 'Q1', …] in the order shown
/// response1_id    X1-1 … X5-4 | XG (rule arm) | llm | llm_fallback (Hybrid)
///                 | none_safety (a safety hit: no template, safety flow)
/// response2_id    R4a | R4b (rule arm; Hybrid 唔講住 also R4b) | llm |
///                 llm_fallback | none_safety
/// stopped_by_safety  true when an acute hit ended the check-in early
/// completed       true once Q5 is answered
/// created_at / updated_at / completed_at   server timestamps
/// ```
///
/// The Q3b / Q4 words are stored here only.  In the rule arm they never
/// go to the model; like every other input they pass the shared safety
/// check (lexicon, plus the classifier when its switch is on — the same in
/// both arms).  `turns` keep only their length, as on every chat page.
library;

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

abstract class CheckInResponseStore {
  /// A new document id for one check-in.
  String newId();

  /// Create ([first]) or merge one check-in record.
  Future<void> write({
    required String uid,
    required String id,
    required Map<String, dynamic> data,
    required bool first,
  });
}

class FirestoreCheckInResponseStore implements CheckInResponseStore {
  const FirestoreCheckInResponseStore({required this.available});

  final bool available;

  @override
  String newId() {
    // Local id: Firestore accepts any id, and this needs no Firebase app
    // (guest / test runs never write anyway).
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final noise = Random().nextInt(1 << 30).toRadixString(36);
    return 'ci_$now$noise';
  }

  @override
  Future<void> write({
    required String uid,
    required String id,
    required Map<String, dynamic> data,
    required bool first,
  }) async {
    if (!available) return;
    try {
      // Fire-and-forget at the call site: offline, the SDK queues it.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('check_in_responses')
          .doc(id)
          .set({
        ...data,
        if (first) 'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        if (data['completed'] == true)
          'completed_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Permission / format errors: the analytics event still has the
      // answers' codes.
    }
  }
}

/// Test / offline double: keeps the merged documents in memory.
class InMemoryCheckInResponseStore implements CheckInResponseStore {
  final Map<String, Map<String, dynamic>> docs = {};
  int writes = 0;
  int _next = 0;

  @override
  String newId() => 'ci_${_next++}';

  @override
  Future<void> write({
    required String uid,
    required String id,
    required Map<String, dynamic> data,
    required bool first,
  }) async {
    writes++;
    docs[id] = {...?docs[id], ...data, 'uid': uid};
  }
}

/// The live record of one chat check-in; [toMap] is what [CheckInResponseStore]
/// writes.
class CheckInChatRecord {
  CheckInChatRecord({
    required this.arm,
    required this.dateIso,
    required this.copyVersion,
    this.studyDay,
    this.studyWeek,
  });

  final String arm;
  final String dateIso;
  final String copyVersion;
  final int? studyDay;
  final int? studyWeek;

  String? sessionId;
  final Map<String, Map<String, dynamic>> answers = {};
  final List<String> questionsShown = [];
  String? response1Id;
  String? response2Id;
  bool stoppedBySafety = false;
  bool completed = false;

  Map<String, dynamic> toMap() => {
        'arm': arm,
        'flow': 'chat_v2',
        'schema_version': 2,
        'copy_version': copyVersion,
        'date_iso': dateIso,
        'study_day': studyDay,
        'study_week': studyWeek,
        'session_id': sessionId,
        'answers': {
          for (final e in answers.entries) e.key: Map.of(e.value),
        },
        'questions_shown': List.of(questionsShown),
        'response1_id': response1Id,
        'response2_id': response2Id,
        'stopped_by_safety': stoppedBySafety,
        'completed': completed,
      };
}
