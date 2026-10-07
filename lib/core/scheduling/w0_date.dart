/// The W0 (enrolment) date — THE single place the App decides it (T18,
/// decision 0027).
///
/// Today W0 is the account's `createdAt` (the same field the existing
/// 「入組第 N 天」 counting uses, see enrolment_day.dart, and the server's
/// functions/djg_w2.js `w0DateKey`).  T19 swaps this for the date the
/// researcher registers; change it here and in `w0DateKey` only.
library;

import '../../features/auth/data/user_profile.dart';

/// W0 for [profile], or null when unknown.  Only the calendar date counts
/// (day 1 = this date, see [enrolmentDay]).
DateTime? w0DateFor(UserProfile? profile) => profile?.createdAt;
