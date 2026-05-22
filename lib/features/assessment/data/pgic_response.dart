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
  static int isoWeekFor(DateTime date) {
    // ISO 8601 week: week containing Thursday of the year.
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    final wday = date.weekday; // 1=Mon … 7=Sun
    return ((dayOfYear - wday + 10) / 7).floor();
  }
}
