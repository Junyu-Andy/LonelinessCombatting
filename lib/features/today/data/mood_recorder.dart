import 'package:cloud_firestore/cloud_firestore.dart';

/// Writes and reads the `users/{uid}/daily_mood` collection under the
/// new multi-entry schema (Home Layout Spec §2).
///
/// One day can now hold many entries.  The first entry of the day is
/// marked `is_primary: true` and is the only one that flows into Gate
/// computation and outcome analyses — the protocol's "one mood per day"
/// contract is preserved.  Every subsequent entry the same day is
/// stored with `supplementary: true` so it surfaces in the timeline /
/// LLM context without polluting the primary measurement.
///
/// Schema:
/// ```
/// users/{uid}/daily_mood/{autoId} = {
///   mood: int (1..5),
///   date_iso: 'YYYY-MM-DD',
///   is_primary: bool,
///   supplementary: bool,
///   entry_seq_today: int (1, 2, 3, ...),
///   prompted_at: serverTimestamp,
///   responded_at: serverTimestamp,
///   source_surface: 'home_hero' | ...,
///   arm: 'A' | 'B',
/// }
/// ```
class MoodRecorder {
  final FirebaseFirestore _db;
  MoodRecorder({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  static String dateIsoFor(DateTime t) {
    final y = t.year.toString().padLeft(4, '0');
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('daily_mood');

  /// Records one mood entry.  Computes whether it's the day's primary
  /// or a supplementary follow-up by counting existing entries with
  /// the same `date_iso`.  Returns the resulting [MoodEntry].
  Future<MoodEntry> record({
    required String uid,
    required int mood,
    required String arm,
    String sourceSurface = 'home_hero',
    DateTime? promptedAt,
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    final dateIso = dateIsoFor(stamp);
    final col = _col(uid);

    // Count today's existing entries to derive entry_seq_today.  No
    // orderBy here so Firestore doesn't need a composite index — the
    // result set per day is tiny (single-digit) and we only need the
    // size.  Concurrent writes from a second device may race; the
    // analytics layer dedupes on (uid, date_iso, is_primary).
    final existingToday =
        await col.where('date_iso', isEqualTo: dateIso).get();
    final seq = existingToday.docs.length + 1;
    final isPrimary = seq == 1;

    final data = <String, dynamic>{
      'mood': mood,
      'date_iso': dateIso,
      'is_primary': isPrimary,
      'supplementary': !isPrimary,
      'entry_seq_today': seq,
      'prompted_at': promptedAt != null
          ? Timestamp.fromDate(promptedAt)
          : FieldValue.serverTimestamp(),
      'responded_at': FieldValue.serverTimestamp(),
      'source_surface': sourceSurface,
      'arm': arm,
    };
    final ref = await col.add(data);
    return MoodEntry(
      id: ref.id,
      mood: mood,
      dateIso: dateIso,
      isPrimary: isPrimary,
      supplementary: !isPrimary,
      entrySeqToday: seq,
      respondedAt: stamp,
      sourceSurface: sourceSurface,
      arm: arm,
    );
  }

  /// Reads the most recent mood entry for [dateIso] (today's latest if
  /// the user has logged multiple times).  Returns null when nothing
  /// has been logged for that day.  Tolerates both the new schema and
  /// legacy `daily_mood/{YYYY-MM-DD}` docs written by earlier builds.
  Future<MoodEntry?> latestForDate({
    required String uid,
    required String dateIso,
  }) async {
    final col = _col(uid);
    try {
      final q = await col.where('date_iso', isEqualTo: dateIso).get();
      if (q.docs.isNotEmpty) {
        // Sort client-side to avoid needing a composite index on
        // (date_iso, responded_at).  Day-level result set is small.
        final docs = q.docs.toList()
          ..sort((a, b) {
            final ta = _ts(a.data()['responded_at']);
            final tb = _ts(b.data()['responded_at']);
            return tb.compareTo(ta);
          });
        return MoodEntry.fromDoc(docs.first);
      }
    } catch (_) {
      // Falls through to legacy lookup.
    }
    // Legacy fallback — Sprint 1 wrote one doc per day keyed by date.
    try {
      final legacy = await col.doc(dateIso).get();
      if (legacy.exists) return MoodEntry.fromLegacy(legacy);
    } catch (_) {}
    return null;
  }

  /// Reads the most recent mood entry on or before today.  Used by the
  /// Siu Yan opener when there's no record for today and we want to
  /// reference the user's last known mood ("上次你話麻麻地").
  Future<MoodEntry?> mostRecent({required String uid}) async {
    final col = _col(uid);
    try {
      final q = await col
          .orderBy('responded_at', descending: true)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return MoodEntry.fromDoc(q.docs.first);
    } catch (_) {}
    // Legacy fallback: doc IDs are YYYY-MM-DD strings which sort
    // lexicographically by date.
    try {
      final q = await col
          .orderBy(FieldPath.documentId, descending: true)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return MoodEntry.fromLegacy(q.docs.first);
    } catch (_) {}
    return null;
  }

  /// Streams the count of distinct mood-logging days in the window
  /// `[from, until)`.  Counts a day once even if the user logged
  /// multiple supplementary entries.  Used by the home facts recap.
  Future<int> distinctDaysInRange({
    required String uid,
    required DateTime from,
    required DateTime until,
  }) async {
    final col = _col(uid);
    final fromIso = dateIsoFor(from);
    final untilIso = dateIsoFor(until);
    try {
      final q = await col
          .where('date_iso', isGreaterThanOrEqualTo: fromIso)
          .where('date_iso', isLessThan: untilIso)
          .get();
      final days = <String>{};
      for (final d in q.docs) {
        final iso = d.data()['date_iso'];
        if (iso is String) days.add(iso);
      }
      return days.length;
    } catch (_) {
      return 0;
    }
  }

  static DateTime _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
    return DateTime(2000);
  }
}

class MoodEntry {
  final String id;
  final int mood;
  final String dateIso;
  final bool isPrimary;
  final bool supplementary;
  final int entrySeqToday;
  final DateTime respondedAt;
  final String sourceSurface;
  final String arm;

  const MoodEntry({
    required this.id,
    required this.mood,
    required this.dateIso,
    required this.isPrimary,
    required this.supplementary,
    required this.entrySeqToday,
    required this.respondedAt,
    required this.sourceSurface,
    required this.arm,
  });

  factory MoodEntry.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final responded = data['responded_at'];
    return MoodEntry(
      id: d.id,
      mood: (data['mood'] as num?)?.toInt() ?? 0,
      dateIso: (data['date_iso'] as String?) ?? '',
      isPrimary: (data['is_primary'] as bool?) ?? false,
      supplementary: (data['supplementary'] as bool?) ?? false,
      entrySeqToday: (data['entry_seq_today'] as num?)?.toInt() ?? 0,
      respondedAt: responded is Timestamp ? responded.toDate() : DateTime.now(),
      sourceSurface: (data['source_surface'] as String?) ?? 'unknown',
      arm: (data['arm'] as String?) ?? 'B',
    );
  }

  /// Builds an entry from a legacy `daily_mood/{YYYY-MM-DD}` doc whose
  /// schema was `{value: int, timestamp}`.  Treated as a primary entry
  /// so legacy users don't lose their Gate-eligible first-of-day.
  factory MoodEntry.fromLegacy(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const {};
    final ts = data['timestamp'];
    return MoodEntry(
      id: d.id,
      mood: (data['value'] as num?)?.toInt() ??
          (data['mood'] as num?)?.toInt() ??
          0,
      dateIso: d.id,
      isPrimary: true,
      supplementary: false,
      entrySeqToday: 1,
      respondedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      sourceSurface: 'legacy',
      arm: (data['arm'] as String?) ?? 'B',
    );
  }
}
