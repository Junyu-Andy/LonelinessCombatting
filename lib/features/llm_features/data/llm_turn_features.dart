/// B.1 — per-turn LLM mechanism-of-change feature record (Sprint 2.1).
///
/// Stores the 5 flag bundle returned by `proxyDeepSeek` so analysts can
/// regress per-turn mechanism usage against outcome scores.
///
/// **Arm B writes are skipped at the repo layer** — see [armBSkip] gate in
/// [LlmTurnFeaturesRepository.write].  Arm B does not call the LLM gateway,
/// so the schema only carries Arm A data and analysts treat absence-of-row
/// as Arm B at analysis time.
///
/// Firestore path: `users/{uid}/llm_turn_features/{turnId}`
///
/// The 5 flags (see functions/llm_flags.js for detector logic):
///   - personalization_specific
///   - memory_callback
///   - empathic_reflection
///   - open_question
///   - adaptive_register
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class LlmTurnFeatures {
  final String? id;
  final String agentId;
  final String moduleId;

  /// Hash of the resolved system prompt (B.2 link).
  final String? systemPromptHash;

  /// The 5 boolean flags from the CF detector.
  final Map<String, bool> flags;

  /// Detector version — bumped in functions/llm_flags.js when heuristics change.
  /// Used by analysts to filter out flags computed by an earlier version.
  final int detectorVersion;

  final DateTime createdAt;

  const LlmTurnFeatures({
    this.id,
    required this.agentId,
    required this.moduleId,
    this.systemPromptHash,
    required this.flags,
    required this.detectorVersion,
    required this.createdAt,
  });

  /// Parse the raw CF response shape — `{personalization_specific: bool, …,
  /// _version: int}` — into the typed split (flags map + version).
  factory LlmTurnFeatures.fromCloudFunctionPayload({
    required String agentId,
    required String moduleId,
    String? systemPromptHash,
    required Map<String, dynamic> raw,
  }) {
    final flags = <String, bool>{};
    int version = 1;
    raw.forEach((k, v) {
      if (k == '_version' && v is int) {
        version = v;
      } else if (v is bool) {
        flags[k] = v;
      }
    });
    return LlmTurnFeatures(
      agentId: agentId,
      moduleId: moduleId,
      systemPromptHash: systemPromptHash,
      flags: flags,
      detectorVersion: version,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'agentId': agentId,
        'moduleId': moduleId,
        'systemPromptHash': systemPromptHash,
        'flags': flags,
        'detectorVersion': detectorVersion,
        'createdAt': createdAt.toIso8601String(),
      };
}

class LlmTurnFeaturesRepository {
  LlmTurnFeaturesRepository({required this.available});
  final bool available;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('llm_turn_features');

  /// Write a feature record. Returns the new doc id, or null if skipped
  /// (Arm B or unavailable).
  ///
  /// [isArmA] gates the write: per Open Q #2 (default = no Arm B write),
  /// only Arm A turns persist features.
  Future<String?> write({
    required String uid,
    required bool isArmA,
    required LlmTurnFeatures features,
  }) async {
    if (!available) return null;
    if (!isArmA) return null; // armBSkip
    final ref = await _ref(uid).add(features.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp());
    return ref.id;
  }
}
