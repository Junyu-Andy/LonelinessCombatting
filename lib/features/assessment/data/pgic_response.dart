/// PGIC (Patient Global Impression of Change) weekly assessment data model.
///
/// Stored at `users/{uid}/pgic_responses/{auto-id}`.

import 'package:cloud_firestore/cloud_firestore.dart';

class PgicResponse {
  /// 1-7 scale (1 = much better, 7 = much worse).
  final int value;
  final DateTime answeredAt;

  /// ISO week number (1-53) of the year the response was submitted.
  final int isoWeek;

  const PgicResponse({
    required this.value,
    required this.answeredAt,
    required this.isoWeek,
  });

  Map<String, dynamic> toFirestore() => {
        'value': value,
        'answeredAt': FieldValue.serverTimestamp(),
        'isoWeek': isoWeek,
      };

  factory PgicResponse.fromFirestore(Map<String, dynamic> map) {
    DateTime parseDate(dynamic v) {
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      try {
        final dynamic dyn = v;
        final result = dyn.toDate();
        if (result is DateTime) return result;
      } catch (_) {}
      return DateTime.now();
    }

    return PgicResponse(
      value: (map['value'] as num?)?.toInt() ?? 4,
      answeredAt: parseDate(map['answeredAt']),
      isoWeek: (map['isoWeek'] as num?)?.toInt() ?? 1,
    );
  }

  /// ISO week number for a given date (1-53).
  ///
  /// Handles the year boundaries the naive formula got wrong: early
  /// January days that belong to the previous ISO year returned week 0,
  /// and late December days in 52-week years returned 53 — both would
  /// have stored an unjoinable week key had the study spanned New Year.
  static int isoWeekFor(DateTime date) {
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    final wday = date.weekday; // 1=Mon … 7=Sun
    final week = (dayOfYear - wday + 10) ~/ 7;
    if (week < 1) return _weeksInIsoYear(date.year - 1);
    if (week > _weeksInIsoYear(date.year)) return 1;
    return week;
  }

  /// 53 iff the year starts on Thursday, or is a leap year starting on
  /// Wednesday (ISO 8601); otherwise 52.
  static int _weeksInIsoYear(int year) {
    final jan1 = DateTime(year, 1, 1).weekday;
    final isLeap =
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    final has53 = jan1 == DateTime.thursday ||
        (isLeap && jan1 == DateTime.wednesday);
    return has53 ? 53 : 52;
  }
}
