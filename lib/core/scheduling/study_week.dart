/// T24 — study-week arithmetic (SPEC:C15; research note 10/9 item 11 and
/// its correction).  THE one place the App turns a moment into a study day
/// / study week; the server mirrors it in functions/study_week.js, and
/// test/fixtures/study_week_table.json feeds both tests the same cases.
///
///   W0 (the enrolment visit, [w0DateFor]) is study day 0.  Study day k is
///   the k-th calendar day after W0 (negative before W0).  Study week:
///       day 0           → week 0
///       days 1–7        → week 1
///       days 8–14       → week 2       i.e. week = ceil(day / 7)
///       …                 (follow-up weeks keep counting)
///   Days before W0 report week 0 as well.
///
/// Dates are the phone's wall clock, which for this study is Hong Kong
/// time (no daylight saving); the server uses Hong Kong dates.  Note the
/// older [enrolmentDay] counts W0 as day 1 — T18's W2 window keeps that;
/// everything T24 adds uses this file.
library;

/// Study day of [now] for a participant whose W0 is [w0] (calendar dates;
/// the time of day of either argument is ignored).
int studyDayOf(DateTime w0, DateTime now) {
  final a = DateTime(w0.year, w0.month, w0.day);
  final b = DateTime(now.year, now.month, now.day);
  // Round to absorb the 23/25-hour days HK does not have but tests might.
  return (b.difference(a).inHours / 24).round();
}

/// Study week of a study day: 0 for day 0 (and before), ceil(day / 7)
/// after.
int studyWeekOf(int day) => day <= 0 ? 0 : (day + 6) ~/ 7;

/// Study week of [now].
int studyWeekAt(DateTime w0, DateTime now) => studyWeekOf(studyDayOf(w0, now));

/// Calendar date of study day [day] (day 0 = W0).
DateTime dateOfStudyDay(DateTime w0, int day) =>
    DateTime(w0.year, w0.month, w0.day + day);
