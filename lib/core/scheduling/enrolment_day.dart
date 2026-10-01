/// Enrolment-day arithmetic shared by the client and mirrored in the Cloud
/// Functions (`week2Push`).  **Day 1 = the calendar day the account was
/// created**; day N = that date + (N − 1) days.  Calendar dates, not 24-hour
/// blocks, so an 18:00 signup is on day 2 at 09:00 the next morning.
///
/// Spec wording 「入組第 14 天」 therefore means `enrolmentDay == 14`.
library;

int enrolmentDay(DateTime createdAt, DateTime now) {
  final c = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final n = DateTime(now.year, now.month, now.day);
  // Round to absorb the 23/25-hour days HK does not have but tests might.
  return (n.difference(c).inHours / 24).round() + 1;
}

/// Calendar date of enrolment day [day] (1-based).
DateTime dateOfEnrolmentDay(DateTime createdAt, int day) =>
    DateTime(createdAt.year, createdAt.month, createdAt.day + day - 1);
