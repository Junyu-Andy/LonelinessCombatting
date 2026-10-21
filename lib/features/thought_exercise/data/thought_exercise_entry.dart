/// B.4 — Thought Exercise entry (Sprint 1.5, corrected to spec May 2026;
/// form v2 10/21, decisions-log 10/21 item 133 (2), PI final handoff).
///
/// Firestore path: `users/{uid}/thought_exercise/{id}`
///
/// Form v2 (10/21) — the questions and the stored field each one writes.
/// The field names are the v1 names, so analysis compares the same fields:
///   一 心入面有冇一句說話轉嚟轉去？ → thought (required; auto-filled when
///                                    entered via Siu Yan's offer pathway)
///   二 寫低之後，你而家覺得點？    → emotionEmoji (required)
///      有幾強烈？(1–10)          → intensityBefore (required)
///   三 呢個諗法係由咩引起？      → situation (optional; '' when blank)
///   四 好朋友都咁諗，你會同佢講咩？ → anotherWayToLook (optional; '' when
///                                    blank)
///   exit re-rating             → intensityAfter (1–10, written on 完成)
///   version                    → 2 ([currentVersion]); a record without
///                                the field is form v1.
///
/// v1 had a required 「嗰陣係咩情況？」 (situation) and a required
/// 「一個令呢個諗法可能成立嘅理由」 (oneReasonTrue).  v2 no longer asks
/// the reason: [oneReasonTrue] is null on new entries and not written;
/// it is still read back from v1 records.
///
/// Provenance (metadata, not content):
///   agentId, agentInvitationText, originTurnRef — cached at create-time
///   for the B.5 audit trigger so it can resolve provenance race-free.
///
/// **Pixel-identical across arms.**  Only the entry pathway differs
/// (Siu Yan offer with auto-filled 一 in Arm A; tab-tile only in
/// Arm B).  The tool itself, fields, intro text, history view are
/// identical (Phase B Proposal §4.7).  No model call.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class ThoughtExerciseEntry {
  /// The form version written on every new record (`version`).  Records
  /// without the field were saved by form v1.
  static const int currentVersion = 2;

  final String? id;

  // --- v2 三 由咩引起 (optional; v1: 嗰陣係咩情況？) ---
  final String situation;

  // --- v2 二: emotion + intensity_before ---
  final String emotionEmoji;
  final int intensityBefore; // 1–10

  // --- v2 一: the thought ---
  final String thought;

  // --- v1 only: one reason it might be true.  Null = not asked (v2);
  // not written then. ---
  final String? oneReasonTrue;

  // --- v2 四 好朋友 reply (optional; v1: 另一個角度) ---
  final String anotherWayToLook;

  /// Form version: 1 = v1 (no field stored), 2 = 10/21 questions.
  final int version;

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
    this.oneReasonTrue,
    required this.anotherWayToLook,
    this.version = currentVersion,
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
      version: version,
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
        if (oneReasonTrue != null) 'oneReasonTrue': oneReasonTrue,
        'anotherWayToLook': anotherWayToLook,
        'version': version,
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
      oneReasonTrue: map['oneReasonTrue'] as String?,
      anotherWayToLook: (map['anotherWayToLook'] as String?) ?? '',
      version: (map['version'] as num?)?.toInt() ?? 1,
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
