/// Phase A baseline — M-2 Weekly PR window + referent rules (T-15).
import 'package:app_demo/core/config/phase_a_config.dart';
import 'package:app_demo/features/weekly_pr/data/weekly_pr_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cfg = PhaseAConfig();
  // 2026-09-13 is a Sunday; 2026-09-14 Monday.
  final sun1959 = DateTime(2026, 9, 13, 19, 59);
  final sun2000 = DateTime(2026, 9, 13, 20, 0);
  final mon = DateTime(2026, 9, 14, 9, 0);
  final tue2359 = DateTime(2026, 9, 15, 23, 59);
  final wed = DateTime(2026, 9, 16, 0, 1);

  group('WeeklyPrWindow', () {
    test('opens Sunday 20:00 and closes Tuesday 23:59', () {
      expect(WeeklyPrWindow.isOpen(sun1959, config: cfg), false);
      expect(WeeklyPrWindow.isOpen(sun2000, config: cfg), true);
      expect(WeeklyPrWindow.isOpen(mon, config: cfg), true);
      expect(WeeklyPrWindow.isOpen(tue2359, config: cfg), true);
      expect(WeeklyPrWindow.isOpen(wed, config: cfg), false);
    });

    test('rated week is the ISO week whose Sunday opened the window', () {
      final monday7 = DateTime(2026, 9, 7);
      expect(WeeklyPrWindow.ratedWeekMonday(sun2000, config: cfg), monday7);
      expect(WeeklyPrWindow.ratedWeekMonday(mon, config: cfg), monday7);
      expect(WeeklyPrWindow.ratedWeekMonday(tue2359, config: cfg), monday7);
      // Wednesday onwards still refers to the week that just closed.
      expect(WeeklyPrWindow.ratedWeekMonday(wed, config: cfg), monday7);
      // Sunday before the push refers to the previous week.
      expect(WeeklyPrWindow.ratedWeekMonday(sun1959, config: cfg), DateTime(2026, 8, 31));
      expect(WeeklyPrWindow.ratedWeekIso(monday7), '2026-W37');
    });

    test('referent range is Monday 00:00 → Sunday 20:00', () {
      final (start, end) = WeeklyPrWindow.referentRange(DateTime(2026, 9, 7), config: cfg);
      expect(start, DateTime(2026, 9, 7));
      expect(end, DateTime(2026, 9, 13, 20));
    });

    test('hasClosed flips after Tuesday 23:59:59', () {
      final monday7 = DateTime(2026, 9, 7);
      expect(WeeklyPrWindow.hasClosed(monday7, tue2359, config: cfg), false);
      expect(WeeklyPrWindow.hasClosed(monday7, wed, config: cfg), true);
    });
  });

  group('chooseReferent (max sessions → tie turns → tie recency)', () {
    final t0 = DateTime(2026, 9, 8, 10);
    final t1 = DateTime(2026, 9, 10, 10);
    test('most sessions wins', () {
      final r = chooseReferent([
        AgentWeekUsage(agentId: 'siu_yan', sessionCount: 3, userTurnCount: 5, lastUsedAt: t0),
        AgentWeekUsage(agentId: 'tung_tung', sessionCount: 2, userTurnCount: 20, lastUsedAt: t1),
      ]);
      expect(r.agent!.agentId, 'siu_yan');
      expect(r.rule, ReferentRule.maxSessions);
    });
    test('tie on sessions → more user turns', () {
      final r = chooseReferent([
        AgentWeekUsage(agentId: 'siu_yan', sessionCount: 2, userTurnCount: 5, lastUsedAt: t1),
        AgentWeekUsage(agentId: 'tung_tung', sessionCount: 2, userTurnCount: 9, lastUsedAt: t0),
      ]);
      expect(r.agent!.agentId, 'tung_tung');
      expect(r.rule, ReferentRule.tieTurns);
    });
    test('tie on sessions and turns → most recent', () {
      final r = chooseReferent([
        AgentWeekUsage(agentId: 'siu_yan', sessionCount: 2, userTurnCount: 5, lastUsedAt: t1),
        AgentWeekUsage(agentId: 'ah_jan_ah_bak', sessionCount: 2, userTurnCount: 5, lastUsedAt: t0),
      ]);
      expect(r.agent!.agentId, 'siu_yan');
      expect(r.rule, ReferentRule.tieRecency);
    });
    test('no sessions → none', () {
      final r = chooseReferent(const []);
      expect(r.agent, isNull);
      expect(r.rule, ReferentRule.none);
    });
    test('single agent → max_sessions', () {
      final r = chooseReferent([
        AgentWeekUsage(agentId: 'siu_yan', sessionCount: 1, userTurnCount: 2, lastUsedAt: t0),
      ]);
      expect(r.rule, ReferentRule.maxSessions);
    });
  });
}
