/// T35 — when the W8 questionnaire shows in the App (handover 1021-W8 一;
/// decision 0036).  Pure; mirrors functions/w8_questionnaire.js (the same
/// study days, test/w8_questionnaire_test.dart and
/// functions/test/w8_questionnaire_test.js check the same dates).
///
///   W0 = study day 0 ([studyDayOf], the phone's Hong Kong date).
///   day 56 00:00   the window opens (the server pushes at 10:00)
///   end of day 63  the window closes; answers after it are still taken,
///                  the server marks them outOfWindow
///   end of day 70  the home card goes (handover 一 (5)); from day 71
///                  nothing shows
///
/// Who: a Phase B build and a registered account (RCT-, PB-, PILOT-;
/// [Cohorts.isEnrolled]) with a W0 date.  Both arms the same; no switch
/// (decisions-log 10/20 item 87).  The server pushes testers nothing; a
/// tester whose own arm switch gave it a study period sees the card like
/// a pilot participant (for checking), and every tester can preview the
/// whole flow in 測試員工具 → 每週問卷測試.
library;

import '../../../core/scheduling/study_week.dart';
import '../../../core/scheduling/w0_date.dart';
import '../../../core/study/cohorts.dart';
import '../../auth/data/user_profile.dart';

class W8Schedule {
  W8Schedule._();

  static const openDay = 56;
  static const remind1Day = 58;
  static const remind2Day = 60;
  static const closeDay = 63;
  static const lastCardDay = 70;

  /// Study day of [now] for W0 [w0].
  static int dayOf(DateTime w0, DateTime now) => studyDayOf(w0, now);

  /// The home card shows on days 56–70.
  static bool cardShows(DateTime w0, DateTime now) {
    final d = dayOf(w0, now);
    return d >= openDay && d <= lastCardDay;
  }

  /// Inside the window (days 56–63)?  After it answers still count, the
  /// server stamps them outOfWindow.
  static bool inWindow(DateTime w0, DateTime now) {
    final d = dayOf(w0, now);
    return d >= openDay && d <= closeDay;
  }

  /// Calendar date of a W8 study day.
  static DateTime dateOf(DateTime w0, int day) => dateOfStudyDay(w0, day);
}

class W8Gate {
  W8Gate._();

  /// The W8 card may show for [profile] in a build with [phaseB].
  static bool activeFor(UserProfile? profile, {required bool phaseB}) =>
      phaseB &&
      profile != null &&
      Cohorts.isEnrolled(profile.cohort) &&
      w0DateFor(profile) != null;
}
