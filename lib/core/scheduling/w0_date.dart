/// The W0 (enrolment) date — THE single place the App decides it (T18,
/// decision 0027; T19, decision 0029).
///
/// Prefers the W0 date the unblinded researcher entered at registration
/// (`users/{uid}.w0Date`, `YYYY-MM-DD`, server-written by
/// `enrollParticipant`).  Without it (not registered yet, Phase A, pilot)
/// it falls back to the account's `createdAt`, as before.  The server's
/// functions/djg_w2.js `w0DateKey` follows the same order.
library;

import '../../features/auth/data/user_profile.dart';

/// W0 for [profile], or null when unknown.  Only the calendar date counts
/// (day 1 = this date, see [enrolmentDay]).
DateTime? w0DateFor(UserProfile? profile) {
  final registered = _parseDateKey(profile?.w0Date);
  return registered ?? profile?.createdAt;
}

DateTime? _parseDateKey(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final date = DateTime(y, mo, d);
  // Reject impossible dates (2026-02-30 would roll over to March).
  if (date.year != y || date.month != mo || date.day != d) return null;
  return date;
}
