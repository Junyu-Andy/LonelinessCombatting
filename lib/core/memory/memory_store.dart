import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-module long-term memory. Stores **summaries**, not transcripts, so
/// later sessions can reference earlier content without re-reading huge
/// histories.
///
/// Spec §M3 engineering notes: "uses long-term summaries (under 500 words
/// per session) rather than full transcripts." This store is used by M3
/// (reminiscence), M4 (cognitive restructuring), M6 (social suggestions),
/// and M7 (action loop).
///
/// Storage layout:
///   `users/{uid}/memory/{moduleId}/entries/{autoId}`
/// Each entry: `{summary, createdAt, moduleId, tags, arm}`.
///
/// Transcripts (Arm A only, opt-in) live in a separate subcollection and
/// are not touched by this class.
class MemoryStore {
  MemoryStore({required this.available});

  /// False when Firebase isn't configured. Calls become no-ops and reads
  /// return empty so guest-mode demos don't crash.
  final bool available;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Persist a session summary for [moduleId].
  ///
  /// [hasTranscriptConsent] MUST reflect the participant's current
  /// `consent.transcriptRetention` flag. If false, the call is a no-op —
  /// the session can still proceed in-memory but nothing is written.
  /// This is the ethics gate: without explicit opt-in we never store
  /// free-text that could be replayed by a future model call.
  Future<void> writeSummary({
    required String uid,
    required String moduleId,
    required String summary,
    required String armCode,
    required bool hasTranscriptConsent,
    List<String> tags = const [],
  }) async {
    if (!available) return;
    if (!hasTranscriptConsent) return;
    if (summary.trim().isEmpty) return;
    final clipped = _clip(summary);
    await _db
        .collection('users')
        .doc(uid)
        .collection('memory')
        .doc(moduleId)
        .collection('entries')
        .add({
      'summary': clipped,
      'tags': tags,
      'arm': armCode,
      'moduleId': moduleId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Most-recent-first. Default cap is 5 entries — enough for the LLM to
  /// reference "last week you mentioned..." without ballooning the prompt.
  Future<List<MemoryEntry>> recent({
    required String uid,
    required String moduleId,
    int limit = 5,
  }) async {
    if (!available) return const [];
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('memory')
        .doc(moduleId)
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => MemoryEntry.fromMap(d.id, d.data())).toList();
  }

  /// Cross-module read for cases where one module (e.g. M4 cognitive
  /// restructuring) wants context from another (e.g. M2 daily check-in).
  Future<List<MemoryEntry>> recentAcross({
    required String uid,
    required List<String> moduleIds,
    int perModule = 3,
  }) async {
    final results = <MemoryEntry>[];
    for (final id in moduleIds) {
      results.addAll(await recent(uid: uid, moduleId: id, limit: perModule));
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  /// 500 words ≈ 1000 chars in Chinese, ~3000 in English. Use a conservative
  /// hard cap of 2000 chars and let the caller summarise upstream.
  static const _maxChars = 2000;
  String _clip(String text) {
    if (text.length <= _maxChars) return text;
    return '${text.substring(0, _maxChars - 1)}…';
  }
}

class MemoryEntry {
  final String id;
  final String summary;
  final List<String> tags;
  final String moduleId;
  final String armCode;
  final DateTime createdAt;

  const MemoryEntry({
    required this.id,
    required this.summary,
    required this.tags,
    required this.moduleId,
    required this.armCode,
    required this.createdAt,
  });

  factory MemoryEntry.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return MemoryEntry(
      id: id,
      summary: (map['summary'] as String?) ?? '',
      tags: ((map['tags'] as List?)?.cast<String>()) ?? const [],
      moduleId: (map['moduleId'] as String?) ?? '',
      armCode: (map['arm'] as String?) ?? '',
      createdAt: parseDate(map['createdAt']),
    );
  }
}
