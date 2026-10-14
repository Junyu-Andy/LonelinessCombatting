// T24 — study-week arithmetic (lib/core/scheduling/study_week.dart) against
// the shared table test/fixtures/study_week_table.json, which
// functions/test/study_week_test.js also reads: the App and the server must
// agree on every row.
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/core/scheduling/study_week.dart';
import 'package:flutter_test/flutter_test.dart';

/// An instant → the Hong Kong wall-clock time the phone would show.
DateTime hkLocal(String iso) {
  final u = DateTime.parse(iso).toUtc().add(const Duration(hours: 8));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

DateTime dateKey(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

void main() {
  final table = jsonDecode(
          File('test/fixtures/study_week_table.json').readAsStringSync())
      as Map<String, dynamic>;
  final cases = (table['cases'] as List).cast<Map<String, dynamic>>();

  test('shared table: study day and week of every case', () {
    expect(cases.length, greaterThanOrEqualTo(12));
    for (final c in cases) {
      final w0 = dateKey(c['w0'] as String);
      final at = hkLocal(c['at'] as String);
      expect(studyDayOf(w0, at), c['day'], reason: c['name'] as String);
      expect(studyWeekAt(w0, at), c['week'], reason: c['name'] as String);
    }
  });

  test('boundaries: days 0, 1, 7, 8, 28, 29 → weeks 0, 1, 1, 2, 4, 5', () {
    const expectWeek = {0: 0, 1: 1, 7: 1, 8: 2, 14: 2, 15: 3, 28: 4, 29: 5, 56: 8};
    expectWeek.forEach((d, w) => expect(studyWeekOf(d), w, reason: 'day $d'));
    expect(studyWeekOf(-3), 0);
  });

  test('time of day never changes the day; date of a study day', () {
    final w0 = DateTime(2026, 10, 19, 15, 30);
    expect(studyDayOf(w0, DateTime(2026, 10, 26, 0, 0, 1)), 7);
    expect(studyDayOf(w0, DateTime(2026, 10, 26, 23, 59)), 7);
    expect(studyDayOf(w0, DateTime(2026, 10, 27)), 8);
    expect(dateOfStudyDay(w0, 29), DateTime(2026, 11, 17));
    expect(dateOfStudyDay(DateTime(2026, 12, 28), 7), DateTime(2027, 1, 4));
  });
}
