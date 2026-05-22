/// B.4 — Thought Exercise entry (Sprint 1.5, corrected to spec May 2026).
///
/// Per Phase A Proposal §2.3 and Product Overview §5.2, the schema is
/// **5 content fields + before/after emotion intensity**, NOT three fields.
/// This file replaces the earlier 3-field draft.
///
/// Firestore path: `users/{uid}/thought_exercise/{id}`
///
/// 5 content fields:
///   1. situation              — one-line context (嗰陣係咩情況？)
///   2. emotionEmoji           — selected emoji label
///   3. intensityBefore        — 1–10 slider value
///   4. thought                — the cognition; auto-filled if entered via
///                                Siu Yan's offer pathway
///   5. oneReasonTrue          — one reason it might be true (validates first)
///   6. anotherWayToLook       — alternative perspective; may be blank
///
/// Exit re-rating:
///   7. intensityAfter         — re-rated 1–10 slider at save
///
/// Provenance (metadata, not part of the 5+2 content schema):
///   agentId, agentInvitationText, originTurnRef — cached at create-time
///   for the B.5 audit trigger so it can resolve provenance race-free.
///
/// **Pixel-identical across arms.**  Only the entry pathway differs
/// (Siu Yan offer with auto-filled Field 3 in Arm A; tab-tile only in
/// Arm B).  The tool itself, fields, intro text, history view are
/// identical (Phase B Proposal §4.7).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class ThoughtExerciseEntry {
  final String? id;

  // --- Field 1: situation ---
  final String situation;

  // --- Field 2: emotion + intensity_before ---
  final String emotionEmoji;
  final int intensityBefore; // 1–10

  // --- Field 3: thought ---
  final String thought;

  // --- Field 4: reason ---
  final String oneReasonTrue;

  // --- Field 5: alternative (may be empty) ---
  final String anotherWayToLook;

  // --- Exit re-rating ---
  final int? intensityAfter; // 1–10; null if user closed without re-rating

  // --- Provenance (Siu Yan offer pathway / B.5 audit) ---
  final String? agentId;
  final String? agentInvitationText;
  final String? originTurnRef;

  final DateTime createdAt;

  /// "siu_yan_offer" | "me_tile" — used by the audit trigger to detect
  /// which entry pathway produced the record.
  final String entryPathway;

  const ThoughtExerciseEntry({
    this.id,
    required this.situation,
    required this.emotionEmoji,
    required this.intensityBefore,
    required this.thought,
    required this.oneReasonTrue,
    required this.anotherWayToLook,
    this.intensityAfter,
    this.agentId,
    this.agentInvitationText,
    this.originTurnRef,
    required this.createdAt,
    this.entryPathway = 'me_tile',
  });

  ThoughtExerciseEntry copyWith({int? intensityAfter}) {
    return ThoughtExerciseEntry(
      id: id,
      situation: situation,
      emotionEmoji: emotionEmoji,
      intensityBefore: intensityBefore,
      thought: thought,
      oneReasonTrue: oneReasonTrue,
      anotherWayToLook: anotherWayToLook,
      intensityAfter: intensityAfter ?? this.intensityAfter,
      agentId: agentId,
      agentInvitationText: agentInvitationText,
      originTurnRef: originTurnRef,
      createdAt: createdAt,
      entryPathway: entryPathway,
    );
  }

  Map<String, dynamic> toMap() => {
        'situation': situation,
        'emotionEmoji': emotionEmoji,
        'intensityBefore': intensityBefore,
        'thought': thought,
        'oneReasonTrue': oneReasonTrue,
        'anotherWayToLook': anotherWayToLook,
        'intensityAfter': intensityAfter,
        'agentId': agentId,
        'agentInvitationText': agentInvitationText,
        'originTurnRef': originTurnRef,
        'createdAt': createdAt.toIso8601String(),
        'entryPathway': entryPathway,
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
      situation: (map['situation'] as String?) ?? '',
      emotionEmoji: (map['emotionEmoji'] as String?) ?? '',
      intensityBefore: (map['intensityBefore'] as num?)?.toInt() ?? 5,
      thought: (map['thought'] as String?) ?? '',
      oneReasonTrue: (map['oneReasonTrue'] as String?) ?? '',
      anotherWayToLook: (map['anotherWayToLook'] as String?) ?? '',
      intensityAfter: (map['intensityAfter'] as num?)?.toInt(),
      agentId: map['agentId'] as String?,
      agentInvitationText: map['agentInvitationText'] as String?,
      originTurnRef: map['originTurnRef'] as String?,
      createdAt: ts,
      entryPathway: (map['entryPathway'] as String?) ?? 'me_tile',
    );
  }
}

class ThoughtExerciseRepository {
  ThoughtExerciseRepository({required this.available});
  final bool available;

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

  /// Update only the exit intensity rating (called after the user re-rates
  /// on close).  We allow a separate write so the user can close the page
  /// and re-rate later if needed — although the default flow is to require
  /// the re-rating before save.
  Future<void> setIntensityAfter({
    required String uid,
    required String entryId,
    required int intensityAfter,
  }) async {
    if (!available) return;
    await _ref(uid).doc(entryId).set(
      {'intensityAfter': intensityAfter},
      SetOptions(merge: true),
    );
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
