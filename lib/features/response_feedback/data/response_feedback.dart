/// Response feedback (thumbs up/down) data model.
///
/// Sprint 2 §2 — per-agent-response feedback captured immediately below
/// each agent message bubble. Stored at
/// `users/{uid}/response_feedback/{auto}`.

import 'package:cloud_firestore/cloud_firestore.dart';

class ResponseFeedback {
  final String agentId;
  final String moduleId;
  final String arm;
  /// 'up' | 'down'
  final String rating;
  /// Null for up; one or more category ids for down.
  final List<String>? reasonCategories;
  final String? reasonOtherText;
  final String? turnRef;
  final DateTime submittedAt;

  /// True once a later feedback supersedes this one for the same turn.
  final bool superseded;
  final DateTime? supersededAt;

  /// True iff the modal was dismissed by tap-outside rather than the
  /// 完成 button.
  final bool unintentionalDismiss;

  const ResponseFeedback({
    required this.agentId,
    required this.moduleId,
    required this.arm,
    required this.rating,
    this.reasonCategories,
    this.reasonOtherText,
    this.turnRef,
    required this.submittedAt,
    this.superseded = false,
    this.supersededAt,
    this.unintentionalDismiss = false,
  });

  Map<String, dynamic> toFirestore() => {
        'agentId': agentId,
        'moduleId': moduleId,
        'arm': arm,
        'rating': rating,
        'reasonCategories': reasonCategories,
        'reasonOtherText': reasonOtherText,
        'turnRef': turnRef,
        'submittedAt': FieldValue.serverTimestamp(),
        'superseded': superseded,
        'supersededAt':
            supersededAt == null ? null : Timestamp.fromDate(supersededAt!),
        'unintentionalDismiss': unintentionalDismiss,
      };
}

/// Reason categories shown on the thumbs-down modal.
///
/// M-6 (Phase A baseline 2026-09): exactly four, single-select —
/// 唔明白我 / 講錯話題 / 冇幫助 / 其他.  The id is what lands in
/// `turns.feedback.reason`; the `uncomfortable` option from the earlier
/// five-chip sheet was retired.
class ResponseFeedbackReasons {
  static const notUnderstand = 'not_understand';
  static const wrongTopic = 'wrong_topic';
  static const notHelpful = 'not_helpful';
  static const other = 'other';

  static const all = [
    notUnderstand,
    wrongTopic,
    notHelpful,
    other,
  ];

  static const labels = {
    notUnderstand: '唔明白我',
    wrongTopic: '講錯話題',
    notHelpful: '冇幫助',
    other: '其他',
  };

  static const labelsEn = {
    notUnderstand: "Didn't understand me",
    wrongTopic: 'Wrong topic',
    notHelpful: 'Not helpful',
    other: 'Other',
  };
}
