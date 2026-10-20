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
/// stopped_at      the question it stopped at (Q3b / Q4), else null
/// resumed_from    on a check-in resumed after a 誤觸 mark: the id of the
///                 stopped row it continues (that row is left as it was)
/// completed       true once Q5 is answered
/// created_at / updated_at / completed_at   server timestamps
///
/// 1020e 二.9 — server-only (markSafetyFalseAlarm; firestore.rules lets no
/// client write them), on the stopped row:
/// falseAlarm      true once the researcher marked the alert 誤觸
/// markedBy        the researcher's uid
/// markedAt        server time of the mark
/// ```
///
/// A stopped row with `falseAlarm: true` and `completed` not true is
/// resumed on the elder's next visit the same day ([SiuYanChatPage]): a
/// new row (`resumed_from`) carries the earlier answers and asks the
/// stopped question again.  The next day nothing is resumed.
///
/// The Q3b / Q4 words are stored here only.  In the rule arm they never
/// go to the model; like every other input they pass the shared safety
/// check (lexicon, plus the classifier when its switch is on — the same in
/// both arms).  `turns` keep only their length, as on every chat page.
library;

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// 1020h 一 / 10/20 第 99–100 条 — a chat check-in that an acute hit ended
/// today and the researcher did not mark 誤觸 counts as today's check-in,
/// as on the server (`functions/daily_checkin_push.js`): 小欣's page opens
/// as the chat, not a new check-in, and the home row shows the tick.  One
/// rule for both places.  Both arms.
bool isStoppedUnmarked(Map<String, dynamic> row) =>
    row['flow'] == 'chat_v2' &&
    row['stopped_by_safety'] == true &&
    row['completed'] != true &&
    row['falseAlarm'] != true;

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

  /// 1020e 二.9 — the rows of one day (`date_iso`), id → data; empty when
  /// unavailable.
  Future<Map<String, Map<String, dynamic>>> rowsForDay({
    required String uid,
    required String dateIso,
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

  @override
  Future<Map<String, Map<String, dynamic>>> rowsForDay({
    required String uid,
    required String dateIso,
  }) async {
    if (!available) return const {};
    try {
      // Single-field query: no composite index needed.
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('check_in_responses')
          .where('date_iso', isEqualTo: dateIso)
          .get()
          .timeout(const Duration(seconds: 3));
      return {for (final d in snap.docs) d.id: d.data()};
    } catch (_) {
      return const {};
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

  @override
  Future<Map<String, Map<String, dynamic>>> rowsForDay({
    required String uid,
    required String dateIso,
  }) async =>
      {
        for (final e in docs.entries)
          if (e.value['uid'] == uid && e.value['date_iso'] == dateIso)
            e.key: Map.of(e.value),
      };
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

  /// 1020e 二.9 — Q3b / Q4 when an acute hit stopped the check-in there.
  String? stoppedAt;

  /// 1020e 二.9 — the stopped row this one resumes after a 誤觸 mark.
  String? resumedFrom;
  bool completed = false;

  /// Question ids in check-in order (Q0 and Q6 carry no answer).
  static const List<String> questionOrder = ['Q1', 'Q2', 'Q3', 'Q3b', 'Q4'];

  /// 1020e 二.9 — which question a stopped row stopped at: `stopped_at`,
  /// or (older rows) the reply marked `none_safety`.  Null when it cannot
  /// be told.
  static String? stoppedQuestionOf(Map<String, dynamic> row) {
    final at = row['stopped_at'];
    if (at == 'Q3b' || at == 'Q4') return at as String;
    if (row['response2_id'] == 'none_safety') return 'Q4';
    if (row['response1_id'] == 'none_safety') return 'Q3b';
    return null;
  }

  /// 1020e 二.9 — a new record continuing the stopped row [id] / [row]: the
  /// answers and questions before [stoppedAt] are carried over; the
  /// stopped question is asked again.
  factory CheckInChatRecord.resumeOf({
    required String id,
    required Map<String, dynamic> row,
    required String stoppedAt,
    required String arm,
    required String dateIso,
    required String copyVersion,
  }) {
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    final r = CheckInChatRecord(
      arm: arm,
      dateIso: dateIso,
      copyVersion: copyVersion,
      studyDay: asInt(row['study_day']),
      studyWeek: asInt(row['study_week']),
    );
    final before =
        questionOrder.sublist(0, questionOrder.indexOf(stoppedAt));
    final answers = row['answers'];
    if (answers is Map) {
      for (final q in before) {
        final a = answers[q];
        if (a is Map) r.answers[q] = Map<String, dynamic>.from(a);
      }
    }
    final shown = row['questions_shown'];
    if (shown is List) {
      for (final q in shown.whereType<String>()) {
        if (q == stoppedAt) break;
        r.questionsShown.add(q);
      }
    }
    if (stoppedAt == 'Q4') r.response1Id = row['response1_id'] as String?;
    r.resumedFrom = id;
    return r;
  }

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
        'stopped_at': stoppedAt,
        'resumed_from': resumedFrom,
        'completed': completed,
      };
}
