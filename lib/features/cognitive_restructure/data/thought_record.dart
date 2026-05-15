import 'package:cloud_firestore/cloud_firestore.dart';

/// One pass through M4 Cognitive Restructuring. Both arms write this
/// shape so the analysis pipeline can compare reframing depth and
/// experiment uptake without branching.
///
/// Storage: `users/{uid}/thought_records/{autoId}`.
class ThoughtRecord {
  final String? id;
  final String thought;
  final String? thoughtType; // mind-reading / fortune-telling / all-or-nothing
  final String evidenceFor;
  final String evidenceAgainst;
  final String? alternative;
  final String? experiment;
  final String armCode;
  final DateTime createdAt;

  /// Set when the user hands the experiment off to M7. Stores the resulting
  /// action_plan doc id so we can show the loop closure.
  final String? linkedActionPlanId;

  const ThoughtRecord({
    this.id,
    required this.thought,
    this.thoughtType,
    required this.evidenceFor,
    required this.evidenceAgainst,
    this.alternative,
    this.experiment,
    required this.armCode,
    required this.createdAt,
    this.linkedActionPlanId,
  });

  Map<String, dynamic> toMap() => {
        'thought': thought,
        'thoughtType': thoughtType,
        'evidenceFor': evidenceFor,
        'evidenceAgainst': evidenceAgainst,
        'alternative': alternative,
        'experiment': experiment,
        'arm': armCode,
        'createdAt': createdAt.toIso8601String(),
        'linkedActionPlanId': linkedActionPlanId,
      };

  factory ThoughtRecord.fromMap(String id, Map<String, dynamic> map) {
    DateTime parse(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return ThoughtRecord(
      id: id,
      thought: (map['thought'] as String?) ?? '',
      thoughtType: map['thoughtType'] as String?,
      evidenceFor: (map['evidenceFor'] as String?) ?? '',
      evidenceAgainst: (map['evidenceAgainst'] as String?) ?? '',
      alternative: map['alternative'] as String?,
      experiment: map['experiment'] as String?,
      armCode: (map['arm'] as String?) ?? '',
      createdAt: parse(map['createdAt']),
      linkedActionPlanId: map['linkedActionPlanId'] as String?,
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

  Future<String?> create(String uid, ThoughtRecord record) async {
    if (!available) return null;
    final ref = await _ref(uid).add(record.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp());
    return ref.id;
  }

  Future<void> linkActionPlan(
      String uid, String recordId, String actionPlanId) async {
    if (!available) return;
    await _ref(uid).doc(recordId).set(
      {'linkedActionPlanId': actionPlanId},
      SetOptions(merge: true),
    );
  }
}
