import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads the last check-in timestamp and tells the home banner whether
/// to nudge. Spec §Adherence support, refined in P3.2: the banner only
/// surfaces after the user has missed three consecutive days, so a
/// single quiet day doesn't feel scolding.
class AdherenceCheck {
  AdherenceCheck({required this.available});
  final bool available;

  /// Threshold in days at which the missed-check-in banner appears.
  /// P3.2: tuned up from 2 to 3 to reduce nudge frequency.
  static const bannerThresholdDays = 3;

  /// Days since the user's last `check_in_submitted` event, or null if
  /// they've never checked in or Firebase is unavailable. The banner
  /// surfaces when this is >= [bannerThresholdDays].
  Future<int?> daysSinceLastCheckIn(String uid) async {
    final when = await _lastCheckInAt(uid);
    if (when == null) return null;
    return DateTime.now().difference(when).inDays;
  }

  /// B05 — true when the user completed a check-in on the current local
  /// calendar day.  Uses a calendar compare (not a 24h window) so a
  /// check-in at 23:00 yesterday doesn't read as "done today" at 10:00.
  Future<bool> hasCheckedInToday(String uid) async {
    final when = await _lastCheckInAt(uid);
    if (when == null) return false;
    final now = DateTime.now();
    return when.year == now.year &&
        when.month == now.month &&
        when.day == now.day;
  }

  Future<DateTime?> _lastCheckInAt(String uid) async {
    if (!available) return null;
    // Single-field query + client-side max ON PURPOSE: where+orderBy on
    // different fields needs a composite index that is not deployed
    // (no firestore.indexes.json), which made this throw and silently
    // killed the missed-check-in banner.  Check-in events stay few per
    // participant, so scanning them client-side is fine.
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .where('name', isEqualTo: 'check_in_submitted')
        .get();
    DateTime? latest;
    for (final d in snap.docs) {
      final raw = d.data()['timestamp'];
      final t = raw is Timestamp
          ? raw.toDate()
          : (raw is String ? DateTime.tryParse(raw) : null);
      if (t != null && (latest == null || t.isAfter(latest))) latest = t;
    }
    return latest;
  }
}
