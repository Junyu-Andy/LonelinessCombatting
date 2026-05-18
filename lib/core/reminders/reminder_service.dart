import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/auth/data/user_profile.dart';

/// Spec §M7: "Plan saved with a follow-up reminder for the next session
/// after the planned time." Spec §Adherence: "Reminders configurable by
/// user; respect quiet hours."
///
/// B.10 (Sprint 4 fix): when the user has activated 今日休息 today, the
/// schedule API skips writing the reminder doc entirely.  This is the
/// "dignified pause" behaviour from Product Overview §3.4 — reminders
/// must be suppressed for the day, not merely flagged.  Reminders whose
/// `fireAt` is on a future day still go through, since 今日休息 only
/// covers the current local day.
///
/// This file holds the *interface* between app code and a future local-
/// notification implementation. Concrete delivery (Android channel + iOS
/// permission prompt + `flutter_local_notifications` wire-up) is left
/// for a later sprint so the build doesn't gain a heavy native
/// dependency before we're ready to test on a real device.
///
/// For now the service:
///   - Persists each reminder to `users/{uid}/reminders/{id}` so that
///     when the device-side scheduler comes online it can read the
///     queue and register OS-level alarms.
///   - Skips delivery silently in guest mode or when Firebase is down.
abstract class ReminderService {
  /// Schedule a reminder for [uid].  When [profile] is non-null and
  /// `profile.isQuietToday == true`, requests for **today** are
  /// suppressed (B.10).  Returns null when suppressed.
  Future<String?> schedule({
    required String uid,
    required ReminderRequest request,
    UserProfile? profile,
  });

  Future<void> cancel({required String uid, required String reminderId});
}

class ReminderRequest {
  /// Domain identifier the reminder belongs to. Today only `m7_followup`
  /// is used; `m2_daily_checkin` and `m3_weekly_session` will join when
  /// the dose schedule lands.
  final String kind;

  /// When the reminder should fire (local time).
  final DateTime fireAt;

  /// What the body of the notification should read.
  final String titleZh;
  final String titleEn;
  final String bodyZh;
  final String bodyEn;

  /// Optional cross-link to an `action_plans/{id}` or other doc the
  /// reminder is about. Used by the inbox UI to deep-link.
  final String? linkedDocId;

  const ReminderRequest({
    required this.kind,
    required this.fireAt,
    required this.titleZh,
    required this.titleEn,
    required this.bodyZh,
    required this.bodyEn,
    this.linkedDocId,
  });

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'fireAt': fireAt.toIso8601String(),
        'titleZh': titleZh,
        'titleEn': titleEn,
        'bodyZh': bodyZh,
        'bodyEn': bodyEn,
        'linkedDocId': linkedDocId,
        'createdAt': FieldValue.serverTimestamp(),
        'delivered': false,
      };
}

/// Firestore-backed queue. Stores the intent to fire; a future
/// scheduler (e.g. `flutter_local_notifications` initialised in main)
/// will pick it up and register the OS-level alarm.
class FirestoreReminderQueue implements ReminderService {
  FirestoreReminderQueue({required this.available});
  final bool available;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders');

  @override
  Future<String?> schedule({
    required String uid,
    required ReminderRequest request,
    UserProfile? profile,
  }) async {
    if (!available) return null;
    // B.10 — suppress reminders for today when 今日休息 is active.
    // Reminders scheduled for tomorrow or later go through.
    if (profile != null && profile.isQuietToday) {
      final now = DateTime.now();
      final sameDay = request.fireAt.year == now.year &&
          request.fireAt.month == now.month &&
          request.fireAt.day == now.day;
      if (sameDay) return null;
    }
    final doc = await _ref(uid).add(request.toMap());
    return doc.id;
  }

  @override
  Future<void> cancel({required String uid, required String reminderId}) async {
    if (!available) return;
    await _ref(uid).doc(reminderId).delete();
  }
}
