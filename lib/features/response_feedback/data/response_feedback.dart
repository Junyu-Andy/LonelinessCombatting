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
class ResponseFeedbackReasons {
  static const notUnderstand = 'not_understand';
  static const wrongTopic = 'wrong_topic';
  static const notHelpful = 'not_helpful';
  static const uncomfortable = 'uncomfortable';
  static const other = 'other';

  static const all = [
    notUnderstand,
    wrongTopic,
    notHelpful,
    uncomfortable,
    other,
  ];

  static const labels = {
    notUnderstand: '唔明白我講咩',
    wrongTopic: '講錯重點 / 唔啱題',
    notHelpful: '唔幫到我',
    uncomfortable: '唔舒服 / 唔啱我',
    other: '其他',
  };
}
