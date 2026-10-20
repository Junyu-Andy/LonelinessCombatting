// 1020g 一 (7) — the home page's questionnaire row with the v2 windows
// (`weeklyReminderV2Enabled`): W4 closes on the day its visit was recorded,
// and a finished W4 that is still inside its window (up to day 42) no
// longer hides an open W5 behind it.  Pure logic, synthetic dates.
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/scheduling/weekly_schedule.dart';
import 'package:app_demo/features/today/presentation/widgets/today_todo_rows.dart';
import 'package:app_demo/features/weekly_bundle/data/weekly_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parts submitted for the bundles in [done]; everything else open.
class _Store implements WeeklyBundleStore {
  _Store(this.done);
  final Set<String> done;

  @override
  Future<Map<WeeklyPart, String?>> partStatus(WeeklyBundle bundle) async => {
        for (final p in bundle.parts)
          p: done.contains(bundle.id) ? 'submitted' : null,
      };
}

void main() {
  final w0 = DateTime(2026, 10, 14);
  const cfg = PhaseBConfig(weeklyScheduleV2Enabled: true);
  const mode = WeeklyScheduleMode.standard;
  final bundles = WeeklySchedule.bundlesFor(cfg, mode);
  final w4 = bundles.firstWhere((b) => b.closeRule == WeeklyCloseRule.week4);
  final w5 = bundles[bundles.indexOf(w4) + 1];

  setUp(() => RemoteFeatureFlags.current =
      const RemoteFeatureFlags(weeklyReminderV2Enabled: true));
  tearDown(() => RemoteFeatureFlags.current = const RemoteFeatureFlags());

  Future<QuestionnaireRowInfo?> at(DateTime now,
          {Set<String> done = const {}, DateTime? recorded}) =>
      QuestionnaireRowInfo.resolve(
        cfg: cfg,
        mode: mode,
        w0: w0,
        now: now,
        store: _Store(done),
        week4RecordedOn: recorded,
      );

  test('W4 answered, not recorded, W5 open: the row shows W5', () async {
    final w5Open = WeeklySchedule.windowFor(w5, w0, cfg).open;
    final now = w5Open.add(const Duration(hours: 1));
    // W4 is still inside its window (no visit recorded → day 42).
    expect(WeeklySchedule.openBundlesAt(cfg, mode, w0, now)
        .map((o) => o.bundle.id), contains(w4.id));
    final i = (await at(now, done: {w4.id}))!;
    expect(i.isOpen, isTrue);
    expect(i.due!.bundle.id, w5.id);
  });

  test('W4 visit recorded: W4 closes that day, the row moves on', () async {
    final w4Open = WeeklySchedule.windowFor(w4, w0, cfg).open;
    final recorded = DateTime(w4Open.year, w4Open.month, w4Open.day + 2);
    final dayAfter = recorded.add(const Duration(days: 1, hours: 10));
    // Not answered, but closed by the recorded visit: not open any more.
    final i = await at(dayAfter, recorded: recorded);
    expect(i?.due?.bundle.id, isNot(w4.id));
    // Without the record it would still be open (up to day 42).
    final j = (await at(dayAfter))!;
    expect(j.isOpen, isTrue);
    expect(j.due!.bundle.id, w4.id);
  });
}
