/// Brief Perceived Partner Responsiveness (PR) data model.
///
/// Sprint 1 §3 — captured at the end of a substantive (≥180s, ≥3 exchanges)
/// agent session. Four 0–100 sliders measure perceived understanding,
/// validation, caring and (reverse-coded) insensitivity.
///
/// Stored at `users/{uid}/brief_pr/{auto-id}`.

import 'package:cloud_firestore/cloud_firestore.dart';

class BriefPrResponse {
  /// 'siu_yan' | 'ah_jan_ah_bak' | 'tung_tung'
  final String agentId;

  /// Display name shown to participant — 小欣 / 阿珍 / 阿伯 / 通通.
  final String agentDisplayName;

  /// Optional Firestore path of the session this PR is anchored to.
  final String? sessionRef;

  /// Slider values 0–100. Null if user skipped the prompt entirely.
  final int? understanding;
  final int? validation;
  final int? caring;
  final int? insensitivity;

  /// True iff this is the first brief PR ever recorded for this
  /// (uid, agentId) pair. Skip button is suppressed when anchor.
  final bool isAnchorPrompt;

  /// 'completed' | 'skipped'
  final String status;

  final DateTime promptedAt;
  final DateTime respondedAt;

  /// 'A' | 'B' — RCT arm.
  final String arm;

  const BriefPrResponse({
    required this.agentId,
    required this.agentDisplayName,
    this.sessionRef,
    this.understanding,
    this.validation,
    this.caring,
    this.insensitivity,
    required this.isAnchorPrompt,
    required this.status,
    required this.promptedAt,
    required this.respondedAt,
    required this.arm,
  });

  Map<String, dynamic> toFirestore() => {
        'agentId': agentId,
        'agentDisplayName': agentDisplayName,
        'sessionRef': sessionRef,
        'understanding': understanding,
        'validation': validation,
        'caring': caring,
        'insensitivity': insensitivity,
        'isAnchorPrompt': isAnchorPrompt,
        'status': status,
        'promptedAt': Timestamp.fromDate(promptedAt),
        'respondedAt': FieldValue.serverTimestamp(),
        'arm': arm,
      };
}
