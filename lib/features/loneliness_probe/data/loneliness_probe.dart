/// C.1 — weekly loneliness probe (Sprint 3.3).
///
/// Single-item slider (UCLA-3 short-form analogue) captured once per week
/// when [FeatureFlags.weeklyProbeEnabled] is true.  Phase A: flag is off
/// so this code path is reachable in unit tests but never surfaced.
///
/// Trigger flow:
///   1. CF cron writes `pending_loneliness_probes/{uid}` every Sunday 09:00 HKT.
///   2. Client polls the doc on app open via [LonelinessProbeRepository.pending].
///   3. UI renders [LonelinessProbeSliderPage] when pending && flag true.
///   4. Submission writes to `users/{uid}/loneliness_probes/{auto-id}` and
///      clears the pending mirror.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class LonelinessProbeResponse {
  final String? id;
  final int score;        // 0–10 inclusive
  final DateTime answeredAt;

  /// ISO week the probe was for (e.g. "2026-W20").  Lets analysts join
  /// responses to the cron's intended schedule without depending on
  /// answeredAt precision.
  final String isoWeek;

  const LonelinessProbeResponse({
    this.id,
    required this.score,
    required this.answeredAt,
    required this.isoWeek,
  });

  Map<String, dynamic> toMap() => {
        'score': score,
        'answeredAt': answeredAt.toIso8601String(),
        'isoWeek': isoWeek,
      };

  factory LonelinessProbeResponse.fromMap(String id, Map<String, dynamic> m) {
    final raw = m['answeredAt'];
    DateTime ts;
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else if (raw is String) {
      ts = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }
    return LonelinessProbeResponse(
      id: id,
      score: (m['score'] as num?)?.toInt() ?? 0,
      answeredAt: ts,
      isoWeek: (m['isoWeek'] as String?) ?? _isoWeekOf(ts),
    );
  }

  static String _isoWeekOf(DateTime dt) {
    // Simple ISO-8601 week: tied to Asia/Hong_Kong wall time.
    final jan4 = DateTime(dt.year, 1, 4);
    final firstThursdayWeek = jan4.weekday;
    final dayOfYear = dt.difference(DateTime(dt.year, 1, 1)).inDays + 1;
    final week =
        ((dayOfYear - dt.weekday + 10 - firstThursdayWeek) / 7).floor();
    return '${dt.year}-W${week.toString().padLeft(2, '0')}';
  }
}

class LonelinessProbeRepository {
  LonelinessProbeRepository({required this.available});
  final bool available;

  CollectionReference<Map<String, dynamic>> _responsesRef(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('loneliness_probes');

  /// Whether the CF cron has queued a pending probe for [uid] that hasn't
  /// been answered yet.  Reads `pending_loneliness_probes/{uid}` via the
  /// admin-mirrored path; clients can read their own pending probe via
  /// the per-user `pending_loneliness_probes` (mirrored on the profile).
  Future<bool> hasPending(String uid) async {
    if (!available) return false;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('pending_loneliness_probes')
        .doc('current')
        .get();
    return doc.exists && (doc.data()?['status'] == 'pending');
  }

  Future<String?> submit(
    String uid,
    LonelinessProbeResponse response,
  ) async {
    if (!available) return null;
    final ref = await _responsesRef(uid).add(response.toMap()
      ..['answeredAt'] = FieldValue.serverTimestamp());
    // Clear the pending mirror so the next app open doesn't re-prompt.
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('pending_loneliness_probes')
        .doc('current')
        .set({'status': 'answered', 'answeredAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
    return ref.id;
  }
}
