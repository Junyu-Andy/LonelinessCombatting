/// B.4 — expanded thought-exercise entry (Sprint 1.5).
///
/// Replaces the legacy [ThoughtRecord] model.  New entries are written to
/// `users/{uid}/thought_exercise/entries/{id}`.  The legacy
/// `users/{uid}/thought_records` collection is kept for existing reads but
/// receives no further writes after Sprint 1.
///
/// 7-field schema:
///   1. thought                 — the automatic negative thought being examined
///   2. oneReasonTrue           — one piece of evidence that supports it
///   3. anotherWayToLook        — an alternative balanced perspective
///   4. agentId                 — which agent offered the exercise
///   5. agentInvitationText     — the exact invitation text, cached at entry
///                                creation to avoid the shortTermBuffer race
///                                (Dev Req B.5 audit notes)
///   6. originTurnRef           — Firestore path to the assistant turn that
///                                spawned this entry (for B.5 audit linkage)
///   7. createdAt               — server timestamp
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class ThoughtExerciseEntry {
  final String? id;

  // --- fields 1–3: exercise content ---
  final String thought;
  final String oneReasonTrue;
  final String anotherWayToLook;

  // --- fields 4–6: provenance ---
  final String? agentId;

  /// The verbatim invitation text the agent used to introduce this exercise.
  /// Cached here at entry-create time so the B.5 audit trigger can read
  /// `agentInvitationText` without racing against shortTermBuffer rotation.
  final String? agentInvitationText;

  /// Firestore document path (not a DocumentReference) to the assistant turn
  /// that offered this exercise, e.g.
  /// `users/{uid}/agent_contexts/siu_yan`.
  final String? originTurnRef;

  // --- field 7: timestamp ---
  final DateTime createdAt;

  const ThoughtExerciseEntry({
    this.id,
    required this.thought,
    required this.oneReasonTrue,
    required this.anotherWayToLook,
    this.agentId,
    this.agentInvitationText,
    this.originTurnRef,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'thought': thought,
        'oneReasonTrue': oneReasonTrue,
        'anotherWayToLook': anotherWayToLook,
        'agentId': agentId,
        'agentInvitationText': agentInvitationText,
        'originTurnRef': originTurnRef,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ThoughtExerciseEntry.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    final raw = map['createdAt'];
    DateTime ts;
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else if (raw is String) {
      ts = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }
    return ThoughtExerciseEntry(
      id: id,
      thought: (map['thought'] as String?) ?? '',
      oneReasonTrue: (map['oneReasonTrue'] as String?) ?? '',
      anotherWayToLook: (map['anotherWayToLook'] as String?) ?? '',
      agentId: map['agentId'] as String?,
      agentInvitationText: map['agentInvitationText'] as String?,
      originTurnRef: map['originTurnRef'] as String?,
      createdAt: ts,
    );
  }
}

class ThoughtExerciseRepository {
  ThoughtExerciseRepository({required this.available});

  final bool available;

  // Collection path: users/{uid}/thought_exercise/{id}
  // Spec ref: "thought_exercise/entries" means the 'thought_exercise'
  // subcollection whose documents are the entries.
  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('thought_exercise');

  Future<String?> create(String uid, ThoughtExerciseEntry entry) async {
    if (!available) return null;
    final ref = await _ref(uid).add(entry.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp());
    return ref.id;
  }

  Stream<List<ThoughtExerciseEntry>> recent(String uid, {int limit = 10}) {
    if (!available) return const Stream.empty();
    return _ref(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ThoughtExerciseEntry.fromMap(d.id, d.data()))
            .toList());
  }
}
