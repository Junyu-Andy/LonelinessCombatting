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
    if (!available) return null;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .where('name', isEqualTo: 'check_in_submitted')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final raw = snap.docs.first.data()['timestamp'];
    DateTime? when;
    if (raw is Timestamp) {
      when = raw.toDate();
    } else if (raw is String) {
      when = DateTime.tryParse(raw);
    }
    if (when == null) return null;
    return DateTime.now().difference(when).inDays;
  }
}
