/// Brief Perceived Partner Responsiveness (PR) data model.
///
/// Sprint 1 §3 — captured at the end of a substantive (≥180s, ≥3 exchanges)
/// agent session. Four 1–7 discrete, labelled ratings measure perceived
/// understanding, validation, caring and (negatively-worded) insensitivity.
///
/// Scale change C1 (2026-06): switched from a 0–100 continuous slider to a
/// 1–7 discrete labelled scale (gerontology default; re-aligns with the
/// Reis PPRS / Crasta PRI Likert metric). Values are stored RAW — S4
/// (insensitivity) is NOT reverse-scored at write time; the analysis
/// pipeline applies 8 − x. `schemaVersion` distinguishes old 0–100 records
/// (absent / 1) from new 1–7 records (2).
///
/// Stored at `users/{uid}/brief_pr/{auto-id}`.

import 'package:cloud_firestore/cloud_firestore.dart';

class BriefPrResponse {
  /// Document schema version. 1 (or absent) = legacy 0–100 sliders;
  /// 2 = 1–7 discrete scale (C1).
  static const int currentSchemaVersion = 2;

  /// 'siu_yan' | 'ah_jan_ah_bak' | 'tung_tung'
  final String agentId;

  /// Display name shown to participant — 小欣 / 阿珍 / 阿伯 / 通通.
  final String agentDisplayName;

  /// Optional Firestore path of the session this PR is anchored to.
  final String? sessionRef;

  /// Discrete responses 1–7 (raw; S4 not reverse-scored). Null when the
  /// participant skipped the whole battery.
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
        'schemaVersion': currentSchemaVersion,
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
