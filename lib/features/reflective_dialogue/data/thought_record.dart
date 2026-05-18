/// One thought-record exercise produced by the embedded "naming a
/// thought" tool (Walkthrough Case 5 / Dev Req §M4 deprecation note).
///
/// The exercise is intentionally minimal — three free-text fields, no
/// Socratic cross-examination — so the function stays inside the
/// non-clinical envelope the design committed to.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class ThoughtRecord {
  final String? id;
  final String thought;
  final String oneReasonTrue;
  final String anotherWayToLook;
  final DateTime createdAt;

  /// The conversation surface that spawned the exercise, if any.
  /// `m3_reflective_dialogue` for the agent-routed flow, `me_tile`
  /// for the direct-from-Me-tab entry.
  final String? originSurface;

  const ThoughtRecord({
    this.id,
    required this.thought,
    required this.oneReasonTrue,
    required this.anotherWayToLook,
    required this.createdAt,
    this.originSurface,
  });

  Map<String, dynamic> toMap() => {
        'thought': thought,
        'oneReasonTrue': oneReasonTrue,
        'anotherWayToLook': anotherWayToLook,
        'createdAt': createdAt.toIso8601String(),
        'originSurface': originSurface,
      };

  factory ThoughtRecord.fromMap(String id, Map<String, dynamic> map) {
    final raw = map['createdAt'];
    DateTime ts;
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else if (raw is String) {
      ts = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }
    return ThoughtRecord(
      id: id,
      thought: (map['thought'] as String?) ?? '',
      oneReasonTrue: (map['oneReasonTrue'] as String?) ?? '',
      anotherWayToLook: (map['anotherWayToLook'] as String?) ?? '',
      createdAt: ts,
      originSurface: map['originSurface'] as String?,
    );
  }
}

class ThoughtRecordRepository {
  ThoughtRecordRepository({required this.available});

  final bool available;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('thought_records');

  /// Deprecated after Sprint 1 (B.4). New code MUST write to
  /// [ThoughtExerciseRepository] instead.  This method is kept for
  /// backwards-compatible reads of existing test docs only.
  @Deprecated('Use ThoughtExerciseRepository.create — see B.4 sprint notes')
  Future<String?> create(String uid, ThoughtRecord record) async {
    if (!available) return null;
    final ref = await _ref(uid).add(record.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp());
    return ref.id;
  }

  Stream<List<ThoughtRecord>> recent(String uid, {int limit = 10}) {
    if (!available) return const Stream.empty();
    return _ref(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ThoughtRecord.fromMap(d.id, d.data()))
            .toList());
  }
}
