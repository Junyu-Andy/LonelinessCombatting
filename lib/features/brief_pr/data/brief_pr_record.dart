/// T25 (registry C14) — the Brief PR v2 record, `users/{uid}/brief_pr/{sessionId}`.
///
/// One document per invited session, keyed by the session id so a retry
/// after background / offline / crash can never create a second record
/// (`set` with merge is idempotent).  Old records (`schemaVersion` 2,
/// auto ids, written by the popup `BriefPrPage`) stay readable; nothing
/// here rewrites them.  Scores are stored RAW (the insensitivity item is
/// not reversed; analysis applies 8 − x).
///
/// Field names (English, see the T25 report for the table):
///   uid, sessionId, agentId, agentDisplayName, sessionType, endReason,
///   sessionEndedAt, lastReplyAt, invitedAt, invitedDayKey, inviteChannel,
///   everShown, shownAt, ratedAt, finalStatus, dueNotInvitedReason,
///   understanding, validation, caring, insensitivity, arm,
///   schemaVersion (3), scheduleVersion (2),
///   studyWeek / studyDay — NOT yet written (T24's helpers; listed missing).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// `finalStatus` values (C14).  Null while the invitation is pending
/// ("shown but unanswered" is transient and never stored as a status).
class BriefPrStatus {
  BriefPrStatus._();
  static const completed = 'completed';
  static const partiallyCompleted = 'partially_completed';
  static const skipped = 'skipped';
  static const expired = 'expired';
  static const dueNotInvited = 'due_not_invited';
}

/// `dueNotInvitedReason` values.
class BriefPrDueNotInvitedReason {
  BriefPrDueNotInvitedReason._();
  static const crisis = 'crisis';
  static const systemError = 'system_error';

  /// 10/14 fix: the catch-up card (S10b) would need a time phrase the copy
  /// spec does not provide yet (only 今朝 / 尋晚 / 星期X 下晝 are final), so
  /// the elder is not asked rather than shown a 【占位】 draft.
  static const copyPending = 'copy_pending';
}

/// `inviteChannel` values: the card on the companion list page right after
/// the session (S10a) or the catch-up card on the next app open (S10b).
class BriefPrInviteChannel {
  BriefPrInviteChannel._();
  static const listPage = 'list_page';
  static const catchUp = 'catch_up';
}

/// The four item keys, in questionnaire order.
const briefPrItemKeys = ['understanding', 'validation', 'caring', 'insensitivity'];

class BriefPrRecord {
  static const int currentSchemaVersion = 3;
  static const int scheduleVersion = 2;

  const BriefPrRecord({
    required this.uid,
    required this.sessionId,
    required this.agentId,
    required this.agentDisplayName,
    required this.sessionType,
    required this.endReason,
    required this.sessionEndedAt,
    this.lastReplyAt,
    this.invitedAt,
    this.invitedDayKey,
    this.inviteChannel,
    this.everShown = false,
    this.shownAt,
    this.ratedAt,
    this.finalStatus,
    this.dueNotInvitedReason,
    this.items = const {},
    this.arm,
  });

  final String uid;
  final String sessionId;
  final String agentId;

  /// 小欣 / 阿珍 / 阿伯 / 通通 at invitation time (阿珍 vs 阿伯 follows the
  /// participant's `ahJanAhBakVariant`).
  final String agentDisplayName;
  final String sessionType;
  final String endReason;
  final DateTime sessionEndedAt;

  /// Last complete reply in the session; the 2-hour expiry clock starts
  /// here (falls back to [sessionEndedAt] when missing).
  final DateTime? lastReplyAt;
  final DateTime? invitedAt;

  /// Local date of [invitedAt] as `YYYY-MM-DD`; the daily cap counts on it.
  final String? invitedDayKey;
  final String? inviteChannel;
  final bool everShown;
  final DateTime? shownAt;
  final DateTime? ratedAt;
  final String? finalStatus;
  final String? dueNotInvitedReason;

  /// Raw 1–7 scores by item key; a missing key = not answered.
  final Map<String, int> items;
  final String? arm;

  bool get isPending => finalStatus == null;
  DateTime get expiryAnchor => lastReplyAt ?? sessionEndedAt;

  BriefPrRecord copyWith({
    DateTime? invitedAt,
    String? invitedDayKey,
    String? inviteChannel,
    bool? everShown,
    DateTime? shownAt,
    DateTime? ratedAt,
    String? finalStatus,
    String? dueNotInvitedReason,
    Map<String, int>? items,
    String? arm,
  }) =>
      BriefPrRecord(
        uid: uid,
        sessionId: sessionId,
        agentId: agentId,
        agentDisplayName: agentDisplayName,
        sessionType: sessionType,
        endReason: endReason,
        sessionEndedAt: sessionEndedAt,
        lastReplyAt: lastReplyAt,
        invitedAt: invitedAt ?? this.invitedAt,
        invitedDayKey: invitedDayKey ?? this.invitedDayKey,
        inviteChannel: inviteChannel ?? this.inviteChannel,
        everShown: everShown ?? this.everShown,
        shownAt: shownAt ?? this.shownAt,
        ratedAt: ratedAt ?? this.ratedAt,
        finalStatus: finalStatus ?? this.finalStatus,
        dueNotInvitedReason: dueNotInvitedReason ?? this.dueNotInvitedReason,
        items: items ?? this.items,
        arm: arm ?? this.arm,
      );

  static String dayKey(DateTime local) {
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  Map<String, dynamic> toMap() => {
        'schemaVersion': currentSchemaVersion,
        'scheduleVersion': scheduleVersion,
        'uid': uid,
        'sessionId': sessionId,
        'sessionRef': sessionId, // same key the old records used
        'agentId': agentId,
        'agentDisplayName': agentDisplayName,
        'sessionType': sessionType,
        'endReason': endReason,
        'sessionEndedAt': Timestamp.fromDate(sessionEndedAt),
        'lastReplyAt':
            lastReplyAt == null ? null : Timestamp.fromDate(lastReplyAt!),
        'invitedAt': invitedAt == null ? null : Timestamp.fromDate(invitedAt!),
        'invitedDayKey': invitedDayKey,
        'inviteChannel': inviteChannel,
        'everShown': everShown,
        'shownAt': shownAt == null ? null : Timestamp.fromDate(shownAt!),
        'ratedAt': ratedAt == null ? null : Timestamp.fromDate(ratedAt!),
        'finalStatus': finalStatus,
        'dueNotInvitedReason': dueNotInvitedReason,
        for (final k in briefPrItemKeys) k: items[k],
        'arm': arm,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Reads a v3 record; returns null for an old (v2) popup record or any
  /// document without the v3 keys.
  static BriefPrRecord? fromMap(Map<String, dynamic> m) {
    if (m['schemaVersion'] != currentSchemaVersion) return null;
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
    final ended = ts(m['sessionEndedAt']);
    final sid = m['sessionId'];
    if (ended == null || sid is! String) return null;
    final items = <String, int>{};
    for (final k in briefPrItemKeys) {
      final v = m[k];
      if (v is num) items[k] = v.toInt();
    }
    return BriefPrRecord(
      uid: (m['uid'] as String?) ?? '',
      sessionId: sid,
      agentId: (m['agentId'] as String?) ?? '',
      agentDisplayName: (m['agentDisplayName'] as String?) ?? '',
      sessionType: (m['sessionType'] as String?) ?? 'free_chat',
      endReason: (m['endReason'] as String?) ?? '',
      sessionEndedAt: ended,
      lastReplyAt: ts(m['lastReplyAt']),
      invitedAt: ts(m['invitedAt']),
      invitedDayKey: m['invitedDayKey'] as String?,
      inviteChannel: m['inviteChannel'] as String?,
      everShown: m['everShown'] == true,
      shownAt: ts(m['shownAt']),
      ratedAt: ts(m['ratedAt']),
      finalStatus: m['finalStatus'] as String?,
      dueNotInvitedReason: m['dueNotInvitedReason'] as String?,
      items: items,
      arm: m['arm'] as String?,
    );
  }
}
