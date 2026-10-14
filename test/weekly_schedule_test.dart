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
import 'package:app_demo/core/scheduling/study_week.dart';
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
      expect(WeeklySchedule.modeForCohort('pilot'), WeeklyScheduleMode.pilot);
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
}
