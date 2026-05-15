import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/safety/distress_detector.dart';

/// Status flag on the single M3 session document per week.
enum M3SessionStatus { notStarted, inProgress, completed }

extension M3SessionStatusX on M3SessionStatus {
  String get firestoreCode => switch (this) {
        M3SessionStatus.notStarted => 'notStarted',
        M3SessionStatus.inProgress => 'inProgress',
        M3SessionStatus.completed => 'completed',
      };

  static M3SessionStatus parse(String? raw) {
    switch (raw) {
      case 'inProgress':
        return M3SessionStatus.inProgress;
      case 'completed':
        return M3SessionStatus.completed;
      default:
        return M3SessionStatus.notStarted;
    }
  }
}

/// One conversational turn captured during the session. The Firestore
/// array of turns is consent-gated: when transcript consent is off,
/// the array is written empty (but the session metadata + sanitized
/// end-of-session summary still land).
class M3Turn {
  final bool fromAssistant;
  final String text;
  final DateTime timestamp;

  const M3Turn({
    required this.fromAssistant,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'speaker': fromAssistant ? 'assistant' : 'user',
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  static M3Turn fromMap(Map<String, dynamic> map) {
    final raw = map['timestamp'];
    DateTime when;
    if (raw is Timestamp) {
      when = raw.toDate();
    } else if (raw is String) {
      when = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      when = DateTime.now();
    }
    return M3Turn(
      fromAssistant: (map['speaker'] as String?) == 'assistant',
      text: (map['text'] as String?) ?? '',
      timestamp: when,
    );
  }
}

/// Aggregated session document. One per (uid, weekIndex).
///
/// Schema: `users/{uid}/memory/m3_reminiscence/sessions/week_{n}`.
class M3SessionDoc {
  final int weekIndex;
  final M3SessionStatus status;
  final String armCode; // 'A' | 'B'
  final List<M3Turn> turns;
  final String? endSummaryOriginal;
  final String? endSummaryEdited;
  final bool endSummaryUserEdited;
  final List<DistressFlagRecord> distressFlags;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const M3SessionDoc({
    required this.weekIndex,
    required this.status,
    required this.armCode,
    required this.turns,
    required this.endSummaryOriginal,
    required this.endSummaryEdited,
    required this.endSummaryUserEdited,
    required this.distressFlags,
    required this.startedAt,
    required this.completedAt,
  });

  bool get isCompleted => status == M3SessionStatus.completed;

  /// What other modules (cross-module callback, prior-week hint) should
  /// see as "this session's summary": edited if the user touched it,
  /// otherwise the LLM original (Arm A) or the raw note (Arm B).
  String? get callbackSummary {
    if (endSummaryEdited != null && endSummaryEdited!.trim().isNotEmpty) {
      return endSummaryEdited;
    }
    return endSummaryOriginal;
  }

  static M3SessionDoc empty(int weekIndex) {
    return M3SessionDoc(
      weekIndex: weekIndex,
      status: M3SessionStatus.notStarted,
      armCode: '',
      turns: const [],
      endSummaryOriginal: null,
      endSummaryEdited: null,
      endSummaryUserEdited: false,
      distressFlags: const [],
      startedAt: null,
      completedAt: null,
    );
  }

  static M3SessionDoc fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final rawTurns = (map['turns'] as List?) ?? const [];
    return M3SessionDoc(
      weekIndex: (map['week_number'] as int?) ?? 0,
      status: M3SessionStatusX.parse(map['status'] as String?),
      armCode: (map['arm'] as String?) ?? '',
      turns: [
        for (final t in rawTurns)
          if (t is Map<String, dynamic>) M3Turn.fromMap(t),
      ],
      endSummaryOriginal: map['end_summary_original'] as String?,
      endSummaryEdited: map['end_summary_edited'] as String?,
      endSummaryUserEdited:
          (map['end_summary_user_edited'] as bool?) ?? false,
      distressFlags: [
        for (final f in ((map['distress_flags'] as List?) ?? const []))
          if (f is Map<String, dynamic>) DistressFlagRecord.fromMap(f),
      ],
      startedAt: parseDate(map['started_at']),
      completedAt: parseDate(map['completed_at']),
    );
  }
}

class DistressFlagRecord {
  final int turnIndex;
  final DistressLevel level;

  const DistressFlagRecord({required this.turnIndex, required this.level});

  Map<String, dynamic> toMap() => {
        'turn_index': turnIndex,
        'level': level.name,
      };

  static DistressFlagRecord fromMap(Map<String, dynamic> map) {
    return DistressFlagRecord(
      turnIndex: (map['turn_index'] as int?) ?? 0,
      level: _parseLevel(map['level'] as String?),
    );
  }

  static DistressLevel _parseLevel(String? raw) {
    for (final v in DistressLevel.values) {
      if (v.name == raw) return v;
    }
    return DistressLevel.none;
  }
}

/// Firestore I/O for M3 sessions. One doc per (uid, weekIndex) at
/// `users/{uid}/memory/m3_reminiscence/sessions/week_{n}`.
///
/// Consent gating: when [hasTranscriptConsent] is false, the turns
/// array is written empty, but session metadata (week, arm, status,
/// timestamps) and the user-reviewed end-of-session summary still
/// land — those are user-facing artefacts, not raw transcript.
class M3SessionStore {
  M3SessionStore({required this.available});

  final bool available;

  DocumentReference<Map<String, dynamic>> _docRef(String uid, int weekIndex) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('memory')
          .doc('m3_reminiscence')
          .collection('sessions')
          .doc('week_$weekIndex');

  Future<M3SessionDoc?> read({
    required String uid,
    required int weekIndex,
  }) async {
    if (!available) return null;
    try {
      final snap = await _docRef(uid, weekIndex).get();
      if (!snap.exists) return null;
      return M3SessionDoc.fromMap(snap.data() ?? const {});
    } catch (_) {
      return null;
    }
  }

  Future<Map<int, M3SessionDoc>> readAll({
    required String uid,
    required List<int> weekIndexes,
  }) async {
    if (!available) return const {};
    final futures = weekIndexes.map((w) => read(uid: uid, weekIndex: w));
    final docs = await Future.wait(futures);
    final result = <int, M3SessionDoc>{};
    for (var i = 0; i < weekIndexes.length; i++) {
      final d = docs[i];
      if (d != null) result[weekIndexes[i]] = d;
    }
    return result;
  }

  /// Idempotent — first call writes started_at, subsequent calls leave
  /// metadata alone unless [force] is true.
  Future<void> startSession({
    required String uid,
    required int weekIndex,
    required String armCode,
  }) async {
    if (!available) return;
    final ref = _docRef(uid, weekIndex);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        final data = snap.data() ?? const {};
        if (M3SessionStatusX.parse(data['status'] as String?) ==
            M3SessionStatus.completed) {
          return;
        }
        tx.set(
          ref,
          {
            'status': M3SessionStatus.inProgress.firestoreCode,
            'arm': armCode,
          },
          SetOptions(merge: true),
        );
        return;
      }
      tx.set(ref, {
        'week_number': weekIndex,
        'status': M3SessionStatus.inProgress.firestoreCode,
        'arm': armCode,
        'started_at': FieldValue.serverTimestamp(),
        'turns': <Map<String, dynamic>>[],
      });
    });
  }

  /// Append turns. Pass [hasTranscriptConsent]=false to skip the raw
  /// turn write entirely — only the timestamp / distress metadata still
  /// gets recorded.
  Future<void> appendTurns({
    required String uid,
    required int weekIndex,
    required List<M3Turn> turns,
    required bool hasTranscriptConsent,
  }) async {
    if (!available) return;
    if (!hasTranscriptConsent) return;
    if (turns.isEmpty) return;
    await _docRef(uid, weekIndex).set(
      {
        'turns': FieldValue.arrayUnion([for (final t in turns) t.toMap()]),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> recordDistressFlag({
    required String uid,
    required int weekIndex,
    required int turnIndex,
    required DistressLevel level,
  }) async {
    if (!available) return;
    if (level == DistressLevel.none) return;
    await _docRef(uid, weekIndex).set(
      {
        'distress_flags': FieldValue.arrayUnion([
          DistressFlagRecord(turnIndex: turnIndex, level: level).toMap(),
        ]),
      },
      SetOptions(merge: true),
    );
  }

  /// Write the LLM-generated summary at session close. [endSummaryEdited]
  /// is whatever the user accepted (which may equal [endSummaryOriginal]
  /// when they tapped "use original"). [userEdited] is whether the
  /// edited text differs from the original.
  ///
  /// Both summary fields are user-reviewed sanitized output, so they
  /// land even when transcript consent is off (matches the M3 spec
  /// and CrossModuleMemoryService rationale).
  Future<void> finalizeSession({
    required String uid,
    required int weekIndex,
    required String armCode,
    String? endSummaryOriginal,
    String? endSummaryEdited,
    required bool userEdited,
  }) async {
    if (!available) return;
    await _docRef(uid, weekIndex).set(
      {
        'status': M3SessionStatus.completed.firestoreCode,
        'arm': armCode,
        'completed_at': FieldValue.serverTimestamp(),
        if (endSummaryOriginal != null && endSummaryOriginal.isNotEmpty)
          'end_summary_original': endSummaryOriginal,
        if (endSummaryEdited != null && endSummaryEdited.isNotEmpty)
          'end_summary_edited': endSummaryEdited,
        'end_summary_user_edited': userEdited,
      },
      SetOptions(merge: true),
    );
  }

  /// Re-edit a previously-finalized summary from the detail page.
  /// The *original* field is immutable; only the edited field changes.
  Future<void> reEditSummary({
    required String uid,
    required int weekIndex,
    required String newEdited,
  }) async {
    if (!available) return;
    await _docRef(uid, weekIndex).set(
      {
        'end_summary_edited': newEdited,
        'end_summary_user_edited': true,
      },
      SetOptions(merge: true),
    );
  }
}
