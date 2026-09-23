import 'package:app_demo/core/config/phase_a_config.dart';
import 'package:app_demo/core/scheduling/enrolment_day.dart';
import 'package:app_demo/core/scheduling/schedule_simulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Enrolled Wednesday 2026-09-09 at 18:00.
  final enrolled = DateTime(2026, 9, 9, 18);
  const cfg = PhaseAConfig();

  test('enrolment day is 1-based by calendar date', () {
    expect(enrolmentDay(enrolled, DateTime(2026, 9, 9, 23)), 1);
    expect(enrolmentDay(enrolled, DateTime(2026, 9, 10, 9)), 2);
    expect(enrolmentDay(enrolled, DateTime(2026, 9, 22, 9)), 14);
    expect(dateOfEnrolmentDay(enrolled, 14), DateTime(2026, 9, 22));
  });

  List<String> titles(DateTime d) => ScheduleSimulator.forDate(
        enrolledAt: enrolled, date: d, config: cfg,
      ).map((e) => e.titleZh).toList();

  test('day 14 (Tue) gets the W2 push, the W2 card and the open weekly card', () {
    final t = titles(DateTime(2026, 9, 22));
    expect(t, contains('第 2 週問卷推送'));
    expect(t, contains('第 2 週問卷卡片（DJG-ES → 夥伴評估）'));
    expect(t, contains('週評卡片（仲開緊）'));
    expect(t, contains('每日心情提醒'));
  });

  test('Sunday gets the weekly push and opens the weekly card; no daily push', () {
    final t = titles(DateTime(2026, 9, 13));
    expect(t, contains('每週問卷提醒'));
    expect(t, contains('週評卡片（PGIC → 12 題 PR）'));
    expect(t, isNot(contains('每日心情提醒')));
  });

  test('Wednesday records a missed week', () {
    expect(titles(DateTime(2026, 9, 16)), contains('記錄「上週未答」'));
  });

  test('first-week nudge only on days 3 and 6', () {
    expect(titles(DateTime(2026, 9, 11)), contains('首週提示「你仲未同 X 傾過」'));
    expect(titles(DateTime(2026, 9, 12)), isNot(contains('首週提示「你仲未同 X 傾過」')));
    expect(titles(DateTime(2026, 9, 14)), contains('首週提示「你仲未同 X 傾過」'));
  });

  test('nothing before enrolment', () {
    expect(titles(DateTime(2026, 9, 8)), isEmpty);
  });
}
