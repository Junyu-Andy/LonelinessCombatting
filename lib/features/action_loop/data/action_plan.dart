import 'package:cloud_firestore/cloud_firestore.dart';

/// M7 implementation-intention record. Conceptually one if-then plan:
///   "If <when> <where>, with <whoWith>, I will <action>. If it doesn't
///    work out, I will <fallback>."
///
/// Lives at `users/{uid}/action_plans/{autoId}`. The follow-up surface
/// reads this collection to ask "件事點呀？" once the planned moment has
/// passed.
class ActionPlan {
  final String? id;
  final String action;
  final String whenText; // free text e.g. "tomorrow morning" / "聽朝"
  final String whereText;
  final String whoWith;
  final String fallback;

  /// Arm code at the time of authoring. Used for analysis splits.
  final String armCode;

  /// When the plan was created.
  final DateTime createdAt;

  /// Optional concrete reminder time. If null, the follow-up surface
  /// uses a 24-hour heuristic.
  final DateTime? scheduledFor;

  /// Set by the follow-up surface when the user answers "did it happen?".
  final FollowUpOutcome? outcome;

  /// Optional free-text the user added at follow-up.
  final String? followUpNote;

  const ActionPlan({
    this.id,
    required this.action,
    required this.whenText,
    required this.whereText,
    required this.whoWith,
    required this.fallback,
    required this.armCode,
    required this.createdAt,
    this.scheduledFor,
    this.outcome,
    this.followUpNote,
  });

  Map<String, dynamic> toMap() => {
        'action': action,
        'whenText': whenText,
        'whereText': whereText,
        'whoWith': whoWith,
        'fallback': fallback,
        'arm': armCode,
        'createdAt': createdAt.toIso8601String(),
        'scheduledFor': scheduledFor?.toIso8601String(),
        'outcome': outcome?.name,
        'followUpNote': followUpNote,
      };

  factory ActionPlan.fromMap(String id, Map<String, dynamic> map) {
    DateTime parse(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return ActionPlan(
      id: id,
      action: (map['action'] as String?) ?? '',
      whenText: (map['whenText'] as String?) ?? '',
      whereText: (map['whereText'] as String?) ?? '',
      whoWith: (map['whoWith'] as String?) ?? '',
      fallback: (map['fallback'] as String?) ?? '',
      armCode: (map['arm'] as String?) ?? '',
      createdAt: parse(map['createdAt']),
      scheduledFor: map['scheduledFor'] == null ? null : parse(map['scheduledFor']),
      outcome: FollowUpOutcomeX.tryParse(map['outcome'] as String?),
      followUpNote: map['followUpNote'] as String?,
    );
  }
}

enum FollowUpOutcome { happened, partial, didNotHappen }

extension FollowUpOutcomeX on FollowUpOutcome {
  static FollowUpOutcome? tryParse(String? raw) {
    if (raw == null) return null;
    for (final v in FollowUpOutcome.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// Thin Firestore CRUD for [ActionPlan]. Stays tiny on purpose; if it
/// grows we move it to its own service like `AuthService`.
class ActionPlanRepository {
  ActionPlanRepository({required this.available});

  final bool available;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('action_plans');

  Future<String?> create(String uid, ActionPlan plan) async {
    if (!available) return null;
    final ref = await _ref(uid).add(plan.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp());
    return ref.id;
  }

  Future<void> updateOutcome(
    String uid,
    String planId, {
    required FollowUpOutcome outcome,
    String? note,
  }) async {
    if (!available) return;
    await _ref(uid).doc(planId).set(
      {
        'outcome': outcome.name,
        if (note != null) 'followUpNote': note,
        'followedUpAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Plans without an `outcome` yet, ordered by `createdAt` ascending so
  /// the oldest awaiting follow-up is shown first.
  Stream<List<ActionPlan>> pending(String uid) {
    if (!available) return const Stream.empty();
    return _ref(uid)
        .where('outcome', isNull: true)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs
            .map((d) => ActionPlan.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<List<ActionPlan>> all(String uid) {
    if (!available) return const Stream.empty();
    return _ref(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ActionPlan.fromMap(d.id, d.data()))
            .toList());
  }
}
