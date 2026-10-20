// T24 — the weekly schedule (lib/core/scheduling/weekly_schedule.dart):
// config keys, bundles, windows, the week-4 close rule, the pilot
// compression and the gate — against the shared table
// test/fixtures/weekly_schedule_table.json that
// functions/test/weekly_schedule_test.js also reads.
//
// tool/ci_flutter_tests.sh runs this file in the default build (gate shut
// whatever the switch says) and with PHASE_B=true (gate opens).
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/scheduling/study_week.dart';
import 'package:app_demo/core/scheduling/w0_date.dart';
import 'package:app_demo/core/scheduling/weekly_schedule.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/weekly_bundle/data/weekly_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime hkLocal(String iso) {
  final u = DateTime.parse(iso).toUtc().add(const Duration(hours: 8));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

DateTime dateKey(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String two(int n) => n.toString().padLeft(2, '0');
String hkStr(DateTime d) =>
    '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';

void main() {
  final table = jsonDecode(
          File('test/fixtures/weekly_schedule_table.json').readAsStringSync())
      as Map<String, dynamic>;
  final cfg = PhaseBConfig.fromMap({
    ...(table['config'] as Map<String, dynamic>),
    'weeklyScheduleV2Enabled': true,
  });
  final std = table['standard'] as Map<String, dynamic>;
  final pilot = table['pilot'] as Map<String, dynamic>;

  group('config keys (app_config/phase_b)', () {
    test('defaults: switch off, days and hours as the task text', () {
      const d = PhaseBConfig();
      expect(d.weeklyScheduleV2Enabled, false);
      expect(d.weeklyBundleDays, [7, 14, 21, 26]);
      expect(d.weeklyWindowDays, 3);
      expect(d.week4CloseDay, 29);
      expect(d.djgWeeks, [1, 2, 3]);
      expect(d.pgicOnlyDays, [35, 42, 49]);
      expect(d.weeklyPushHour, 20);
      expect(d.socialContactProbeEnabled, false);
      expect(d.pilotBundleDays, [1, 3, 5, 7]);
      expect(d.pilotWindowDays, 1);
    });

    test('only literal true switches on; bad lists keep the default', () {
      expect(PhaseBConfig.fromMap({'weeklyScheduleV2Enabled': 'true'})
          .weeklyScheduleV2Enabled, false);
      expect(PhaseBConfig.fromMap({'weeklyScheduleV2Enabled': true})
          .weeklyScheduleV2Enabled, true);
      expect(PhaseBConfig.fromMap({'socialContactProbeEnabled': 1})
          .socialContactProbeEnabled, false);
      expect(PhaseBConfig.fromMap({'weeklyBundleDays': [7, 7, 21]})
          .weeklyBundleDays, [7, 14, 21, 26]);
      expect(PhaseBConfig.fromMap({'weeklyBundleDays': ['7']})
          .weeklyBundleDays, [7, 14, 21, 26]);
      expect(PhaseBConfig.fromMap({'pgicOnlyDays': [35.9, 42]}).pgicOnlyDays,
          [35, 42]);
      expect(PhaseBConfig.fromMap({'weeklyPushHour': 26}).weeklyPushHour, 2);
      expect(PhaseBConfig.fromMap({'pilotWindowDays': 0}).pilotWindowDays, 1);
    });
  });

  group('shared table', () {
    test('standard bundles, parts, windows', () {
      final w0 = dateKey(std['w0'] as String);
      final bundles = WeeklySchedule.bundlesFor(cfg, WeeklyScheduleMode.standard);
      final expected = (std['bundles'] as List).cast<Map<String, dynamic>>();
      expect(bundles.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        final e = expected[i];
        final b = bundles[i];
        expect(b.id, e['id']);
        expect(b.studyWeek, e['studyWeek']);
        expect(b.pushDay, e['pushDay']);
        expect(b.parts.map((p) => p.code).toList(), e['parts'], reason: b.id);
        final w = WeeklySchedule.windowFor(b, w0, cfg);
        expect(w.open, hkLocal(e['open'] as String), reason: '${b.id} open');
        expect(w.close, hkLocal(e['close'] as String), reason: '${b.id} close');
      }
      final social = PhaseBConfig.fromMap({
        ...(table['config'] as Map<String, dynamic>),
        'socialContactProbeEnabled': true,
      });
      final sb = WeeklySchedule.bundlesFor(social, WeeklyScheduleMode.standard);
      expect(sb.first.parts.map((p) => p.code).toList(), std['socialPartsW1']);
      for (final b in sb.skip(4)) {
        expect(b.parts, [WeeklyPart.pgic], reason: b.id);
      }
    });

    test('week-4 close: visit day 27 / day 31 / none', () {
      final w0 = dateKey(std['w0'] as String);
      for (final c in (std['week4Close'] as List).cast<Map<String, dynamic>>()) {
        final visit = c['w4VisitDate'] == null ? null : dateKey(c['w4VisitDate'] as String);
        expect(WeeklySchedule.week4CloseFor(w0, visit, cfg),
            hkLocal(c['close'] as String), reason: c['case'] as String);
        final w4 = WeeklySchedule.bundlesFor(cfg, WeeklyScheduleMode.standard)[3];
        expect(WeeklySchedule.windowFor(w4, w0, cfg, w4VisitDate: visit).close,
            hkLocal(c['close'] as String), reason: c['case'] as String);
      }
    });

    test('pilot bundles: days 1, 3, 5, 7; DJG in the first three; 1-day windows', () {
      final w0 = dateKey(pilot['w0'] as String);
      final bundles = WeeklySchedule.bundlesFor(cfg, WeeklyScheduleMode.pilot);
      final expected = (pilot['bundles'] as List).cast<Map<String, dynamic>>();
      expect(bundles.length, 4);
      for (var i = 0; i < expected.length; i++) {
        final e = expected[i];
        final b = bundles[i];
        expect(b.id, e['id']);
        expect(b.pushDay, e['pushDay']);
        expect(b.parts.map((p) => p.code).toList(), e['parts'], reason: b.id);
        final w = WeeklySchedule.windowFor(b, w0, cfg);
        expect(w.open, hkLocal(e['open'] as String), reason: '${b.id} open');
        expect(w.close, hkLocal(e['close'] as String), reason: '${b.id} close');
        if (i > 0) {
          expect(WeeklySchedule.windowFor(bundles[i - 1], w0, cfg).close
              .isAfter(w.open), false, reason: 'no overlap');
        }
      }
    });

    test('Weekly PR referent range of W2', () {
      final w0 = dateKey(std['w0'] as String);
      final b = WeeklySchedule.bundlesFor(cfg, WeeklyScheduleMode.standard)[1];
      final (start, end) = WeeklySchedule.referentRangeFor(b, w0, cfg, WeeklyScheduleMode.standard);
      final r = std['referentRangeW2'] as Map<String, dynamic>;
      expect(start, hkLocal(r['start'] as String));
      expect(end, hkLocal(r['end'] as String));
    });
  });

  group('open bundle at a moment', () {
    final w0 = DateTime(2026, 10, 19);
    const mode = WeeklyScheduleMode.standard;
    test('before / inside / at close / between bundles', () {
      expect(WeeklySchedule.openBundleAt(cfg, mode, w0, DateTime(2026, 10, 26, 19, 59)), null);
      expect(WeeklySchedule.openBundleAt(cfg, mode, w0, DateTime(2026, 10, 26, 20))!.bundle.id, 'W1');
      expect(WeeklySchedule.openBundleAt(cfg, mode, w0, DateTime(2026, 10, 29, 19, 59, 59))!.bundle.id, 'W1');
      expect(WeeklySchedule.openBundleAt(cfg, mode, w0, DateTime(2026, 10, 29, 20)), null);
      expect(WeeklySchedule.openBundleAt(cfg, mode, w0, DateTime(2026, 11, 17, 23, 59))!.bundle.id, 'W4');
      expect(WeeklySchedule.openBundleAt(cfg, mode, w0, DateTime(2026, 11, 18)), null);
      expect(WeeklySchedule.openBundleAt(cfg, mode, w0, DateTime(2026, 12, 8, 9))!.bundle.id, 'W7');
      expect(WeeklySchedule.openBundleAt(cfg, WeeklyScheduleMode.pilot, w0, DateTime(2026, 10, 22, 21))!.bundle.id, 'W2');
    });
  });

  test('date table: W0 on every weekday, 8 weeks (printed for the report)', () {
    final lines = <String>[];
    for (final k in (table['w0Weekdays'] as List).cast<String>()) {
      final w0 = dateKey(k);
      for (final b in WeeklySchedule.bundlesFor(cfg, WeeklyScheduleMode.standard)) {
        final w = WeeklySchedule.windowFor(b, w0, cfg);
        expect(studyDayOf(w0, w.open), b.pushDay);
        if (b.closeRule == WeeklyCloseRule.week4) {
          expect(w.close, dateOfStudyDay(w0, 30));
        } else {
          expect(w.close.difference(w.open), const Duration(days: 3));
        }
        expect(b.parts.contains(WeeklyPart.djg), b.studyWeek <= 3);
        expect(b.pushDay <= 49, true); // W8 belongs to T35
        lines.add('$k W${b.bundleWeek} day ${b.pushDay} ${hkStr(w.open)} → ${hkStr(w.close)} ${b.parts.map((p) => p.code).join('→')}');
      }
    }
    expect(lines.length, 7 * 7);
    // ignore: avoid_print
    print(lines.join('\n'));
  });

  group('gate', () {
    const enrolled = UserProfile(uid: 'u', email: 'e', displayName: 'n', cohort: 'phase_b');
    const pilotP = UserProfile(uid: 'u', email: 'e', displayName: 'n', cohort: 'pilot');
    const unregistered = UserProfile(uid: 'u', email: 'e', displayName: 'n');
    test('switch off → shut whatever the build (today\'s behaviour)', () {
      expect(WeeklyBundleGate.activeFor(const PhaseBConfig(), enrolled, phaseB: true), false);
      expect(WeeklyBundleGate.activeFor(const PhaseBConfig(), enrolled, phaseB: false), false);
    });
    test('switch on → Phase B build and a registered cohort only', () {
      const on = PhaseBConfig(weeklyScheduleV2Enabled: true);
      expect(WeeklyBundleGate.activeFor(on, enrolled, phaseB: true), true);
      expect(WeeklyBundleGate.activeFor(on, pilotP, phaseB: true), true);
      expect(WeeklyBundleGate.activeFor(on, unregistered, phaseB: true), false);
      expect(WeeklyBundleGate.activeFor(on, null, phaseB: true), false);
      expect(WeeklyBundleGate.activeFor(on, enrolled, phaseB: false), false);
    });
    test('this build: ${FeatureFlags.phaseB ? 'PHASE_B' : 'default'}', () {
      final saved = PhaseBConfig.current;
      addTearDown(() => PhaseBConfig.current = saved);
      PhaseBConfig.current = const PhaseBConfig(weeklyScheduleV2Enabled: true);
      expect(WeeklyBundleGate.active(enrolled), FeatureFlags.phaseB);
      PhaseBConfig.current = const PhaseBConfig();
      expect(WeeklyBundleGate.active(enrolled), false);
    });
    test('mode by cohort', () {
      expect(WeeklySchedule.modeForCohort('phase_b'), WeeklyScheduleMode.standard);
      expect(WeeklySchedule.modeForCohort('pilot'), WeeklyScheduleMode.standard);
      expect(WeeklySchedule.modeForCohort('phase_a'), null);
      expect(WeeklySchedule.modeForCohort(null), null);
    });
  });

  test('part codes and collections match the server', () {
    expect(WeeklyPart.values.map((p) => p.code).toList(),
        ['djg', 'weekly_pr', 'pgic', 'social_contact']);
    expect(WeeklyPart.values.map((p) => p.collection).toList(),
        ['djg_responses', 'weekly_pr', 'pgic', 'social_contact_probes']);
  });

  test('no arm check anywhere in the weekly bundle code', () {
    for (final f in [
      'lib/core/scheduling/weekly_schedule.dart',
      'lib/core/scheduling/study_week.dart',
      'lib/features/weekly_bundle/data/weekly_bundle.dart',
      'lib/features/weekly_bundle/presentation/weekly_bundle_flow_page.dart',
      'lib/features/weekly_bundle/presentation/social_contact_probe_page.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains('ArmGate'), false, reason: f);
      expect(src.contains('isArmA'), false, reason: f);
      expect(src.contains('arm_scope'), false, reason: f);
    }
  });

  // -------------------------------------------------------------------------
  // 1020e 二.1–二.3: weeklyReminderV2Enabled (same fixture as the server).
  // -------------------------------------------------------------------------
  group('v2 windows (weeklyReminderV2Enabled)', () {
    final v2 = table['v2'] as Map<String, dynamic>;
    final w0 = dateKey(v2['w0'] as String);
    const mode = WeeklyScheduleMode.standard;
    final bundles = WeeklySchedule.bundlesFor(cfg, mode);

    test('switch: only a literal true in app_config/feature_flags', () {
      expect(const RemoteFeatureFlags().weeklyReminderV2Enabled, false);
      expect(RemoteFeatureFlags.fromMap({'weeklyReminderV2Enabled': true})
          .weeklyReminderV2Enabled, true);
      expect(RemoteFeatureFlags.fromMap({'weeklyReminderV2Enabled': 'true'})
          .weeklyReminderV2Enabled, false);
      expect(RemoteFeatureFlags.fromMap({}).weeklyReminderV2Enabled, false);
    });

    test('shared table: W1–W3 whole days, W4 to day 42, W5–W7 as T24', () {
      final expected = (v2['bundles'] as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < expected.length; i++) {
        final e = expected[i];
        final w = WeeklySchedule.windowFor(bundles[i], w0, cfg, v2: true);
        expect(bundles[i].id, e['id']);
        expect(w.open, hkLocal(e['open'] as String), reason: '${e['id']} open');
        expect(w.close, hkLocal(e['close'] as String), reason: '${e['id']} close');
      }
      expect(bundles.map(WeeklySchedule.isV2Bundle).toList(),
          [true, true, true, true, false, false, false]);
    });

    test('flag off (explicit or default): exactly the T24 table', () {
      final std = (table['standard'] as Map<String, dynamic>)['bundles'] as List;
      for (var i = 0; i < std.length; i++) {
        final e = std[i] as Map<String, dynamic>;
        for (final w in [
          WeeklySchedule.windowFor(bundles[i], w0, cfg, v2: false,
              week4RecordedOn: DateTime(2026, 11, 15)),
          WeeklySchedule.windowFor(bundles[i], w0, cfg),
        ]) {
          expect(w.open, hkLocal(e['open'] as String), reason: '${e['id']}');
          expect(w.close, hkLocal(e['close'] as String), reason: '${e['id']}');
        }
      }
    });

    test('flag on in RemoteFeatureFlags.current → callers that pass nothing '
        'get the v2 windows', () {
      final saved = RemoteFeatureFlags.current;
      addTearDown(() => RemoteFeatureFlags.current = saved);
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(weeklyReminderV2Enabled: true);
      expect(WeeklySchedule.v2Default, true);
      final w1 = WeeklySchedule.windowFor(bundles[0], w0, cfg);
      expect(w1.open, DateTime(2026, 10, 26));
      expect(w1.close, DateTime(2026, 10, 29));
      expect(WeeklySchedule.openBundleAt(cfg, mode, w0,
          DateTime(2026, 10, 26, 0, 1))!.bundle.id, 'W1');
      final (start, end) =
          WeeklySchedule.referentRangeFor(bundles[1], w0, cfg, mode);
      final r = v2['referentRangeW2'] as Map<String, dynamic>;
      expect(start, hkLocal(r['start'] as String));
      expect(end, hkLocal(r['end'] as String));
    });

    test('week-4 close by the recorded W4 visit (early, before opening, '
        'late, after day 42, none)', () {
      for (final c in (v2['week4Close'] as List).cast<Map<String, dynamic>>()) {
        final rec = c['w4RecordedOn'] == null
            ? null
            : dateKey(c['w4RecordedOn'] as String);
        expect(WeeklySchedule.week4CloseV2(w0, rec, bundles[3]),
            hkLocal(c['close'] as String), reason: c['case'] as String);
        expect(WeeklySchedule.windowFor(bundles[3], w0, cfg,
                v2: true, week4RecordedOn: rec).close,
            hkLocal(c['close'] as String), reason: c['case'] as String);
      }
    });

    test('open at a moment: day 7 00:00 to day 9 23:59:59; W4 closes the '
        'night the visit is recorded', () {
      ({WeeklyBundle bundle, WeeklyWindow window})? at(DateTime t,
              {DateTime? rec}) =>
          WeeklySchedule.openBundleAt(cfg, mode, w0, t,
              v2: true, week4RecordedOn: rec);
      expect(at(DateTime(2026, 10, 25, 23, 59)), null); // day 6
      expect(at(DateTime(2026, 10, 26))!.bundle.id, 'W1'); // day 7 00:00
      expect(at(DateTime(2026, 10, 28, 23, 59, 59))!.bundle.id, 'W1');
      expect(at(DateTime(2026, 10, 29)), null); // day 10
      expect(at(DateTime(2026, 11, 14))!.bundle.id, 'W4'); // day 26
      final rec = DateTime(2026, 11, 15); // recorded on day 27
      expect(at(DateTime(2026, 11, 15, 23, 59), rec: rec)!.bundle.id, 'W4');
      expect(at(DateTime(2026, 11, 16), rec: rec), null);
      expect(at(DateTime(2026, 11, 16))!.bundle.id, 'W4',
          reason: 'not recorded: still open');
      // Day 43: W4 closed at the end of day 42; W6 (day 42 20:00) is open.
      expect(at(DateTime(2026, 12, 1))!.bundle.id, 'W6');
      expect(at(DateTime(2026, 11, 30, 23, 59))!.bundle.id, 'W4');
    });

    test('W4 open to day 42 overlaps W5 / W6; the card takes the first one '
        'still to do', () async {
      final t = DateTime(2026, 11, 23, 21); // day 35, W5 open since 20:00
      final open = WeeklySchedule.openBundlesAt(cfg, mode, w0, t, v2: true);
      expect(open.map((o) => o.bundle.id).toList(), ['W4', 'W5']);
      final done = _MapStore({'W4': 'completed'});
      expect((await WeeklyBundleDue.firstNotDone(open, done))!.bundle.id, 'W5');
      expect((await WeeklyBundleDue.firstNotDone(open, _MapStore({})))!
          .bundle.id, 'W4');
      expect(await WeeklyBundleDue.firstNotDone(
          open, _MapStore({'W4': 'completed', 'W5': 'completed'})), null);
      // Flag off: W4 closed on day 29, only W5.
      expect(WeeklySchedule.openBundlesAt(cfg, mode, w0, t, v2: false)
          .map((o) => o.bundle.id).toList(), ['W5']);
    });

    test('w4RecordedOn: read from the profile, never written back', () {
      final p = UserProfile.fromMap('u', {
        'email': 'e', 'displayName': 'n', 'cohort': 'rct',
        'w0Date': '2026-10-19', 'w4RecordedOn': '2026-11-15',
      });
      expect(p.w4RecordedOn, '2026-11-15');
      expect(w4RecordedOnFor(p), DateTime(2026, 11, 15));
      expect(w4RecordedOnFor(p.copyWith(displayName: 'm')),
          DateTime(2026, 11, 15));
      expect(p.toMap().containsKey('w4RecordedOn'), false);
      expect(w4RecordedOnFor(UserProfile.fromMap(
          'u', {'email': 'e', 'w4RecordedOn': '2026-02-30'})), null);
      expect(w4RecordedOnFor(null), null);
    });
  });
}

/// Every part of a bundle has the status in [byBundle] (null = not started).
class _MapStore implements WeeklyBundleStore {
  _MapStore(this.byBundle);
  final Map<String, String> byBundle;

  @override
  Future<Map<WeeklyPart, String?>> partStatus(WeeklyBundle bundle) async =>
      {for (final p in bundle.parts) p: byBundle[bundle.id]};
}
