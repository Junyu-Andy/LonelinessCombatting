// 10/20 decisions-log item 98 (decision 0067) — weeks 5–7 (PGIC only) on
// whole Hong Kong days, like weeks 1–3, with `weeklyReminderV2Enabled` on;
// PhaseBConfig.weeklyPushHour defaults to 10.
//
// The windows come from the shared table test/fixtures/weekly_schedule_table
// .json (`v2` section) that functions/test/weekly_schedule_test.js reads
// too; the home questionnaire row's words (請盡快回答 → 聽日截止 → 今晚截止)
// for week 5 come from its `rowStatesW5` cases and follow the same rule as
// weeks 1–3.  Synthetic dates and accounts, no Firebase; both arms.
//
// tool/ci_flutter_tests.sh runs this file in the default build and in both
// Phase B suites (the home widget cases need a Phase B build).
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/app/main_shell.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/scheduling/weekly_schedule.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/today/data/home_v2_copy.dart';
import 'package:app_demo/features/today/presentation/widgets/daily_mood_prompt.dart';
import 'package:app_demo/features/today/presentation/widgets/mood_row_v2.dart';
import 'package:app_demo/features/today/presentation/widgets/today_todo_rows.dart';
import 'package:app_demo/features/weekly_bundle/data/weekly_bundle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_v2_harness.dart';

DateTime hkLocal(String iso) {
  final u = DateTime.parse(iso).toUtc().add(const Duration(hours: 8));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

DateTime dateKey(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Every part of the bundles in [done] submitted; the rest not started.
class _Store implements WeeklyBundleStore {
  _Store(this.done);
  final Set<String> done;

  @override
  Future<Map<WeeklyPart, String?>> partStatus(WeeklyBundle bundle) async => {
        for (final p in bundle.parts)
          p: done.contains(bundle.id) ? 'submitted' : null,
      };
}

const _v2 = RemoteFeatureFlags(weeklyReminderV2Enabled: true);

void main() {
  final table = jsonDecode(
          File('test/fixtures/weekly_schedule_table.json').readAsStringSync())
      as Map<String, dynamic>;
  final v2 = table['v2'] as Map<String, dynamic>;
  final w0 = dateKey(v2['w0'] as String);
  const mode = WeeklyScheduleMode.standard;
  PhaseBConfig cfgWith(int pushHour) => PhaseBConfig.fromMap({
        ...(table['config'] as Map<String, dynamic>),
        'weeklyScheduleV2Enabled': true,
        'weeklyPushHour': pushHour,
      });
  final cfg = cfgWith(20);

  late RemoteFeatureFlags savedFlags;
  late PhaseBConfig savedConfig;
  setUp(() {
    savedFlags = RemoteFeatureFlags.current;
    savedConfig = PhaseBConfig.current;
    RemoteFeatureFlags.current = _v2;
  });
  tearDown(() {
    RemoteFeatureFlags.current = savedFlags;
    PhaseBConfig.current = savedConfig;
  });

  group('windows (shared table, same as the server)', () {
    test('PhaseBConfig.weeklyPushHour defaults to 10 (production)', () {
      expect(const PhaseBConfig().weeklyPushHour, 10);
      expect(PhaseBConfig.fromMap({}).weeklyPushHour, 10);
      expect(PhaseBConfig.fromMap({'weeklyPushHour': 'x'}).weeklyPushHour, 10);
      expect(PhaseBConfig.fromMap({'weeklyPushHour': 20}).weeklyPushHour, 20);
    });

    test('W5–W7: day 35 00:00 → end of day 37 (42–44, 49–51), whatever '
        'weeklyPushHour says', () {
      final rows = (v2['bundles'] as List)
          .cast<Map<String, dynamic>>()
          .where((e) => ['W5', 'W6', 'W7'].contains(e['id']))
          .toList();
      expect(rows.length, 3);
      for (final hour in [20, 10, 7]) {
        final c = cfgWith(hour);
        for (final e in rows) {
          final b = WeeklySchedule.bundleById(c, mode, e['id'] as String)!;
          expect(b.pgicOnly, isTrue);
          expect(WeeklySchedule.isV2Bundle(b), isTrue);
          final w = WeeklySchedule.windowFor(b, w0, c);
          expect(w.open, hkLocal(e['open'] as String), reason: '${e['id']}');
          expect(w.close, hkLocal(e['close'] as String), reason: '${e['id']}');
          expect(w.open, dateOfDay(w0, b.pushDay));
          expect(w.close, dateOfDay(w0, b.pushDay + 3));
        }
      }
    });

    test('same rule as W1–W3: open at 00:00 of the push day, three whole '
        'days', () {
      for (final b in WeeklySchedule.bundlesFor(cfg, mode)) {
        if (b.closeRule == WeeklyCloseRule.week4) continue;
        final w = WeeklySchedule.windowFor(b, w0, cfg);
        expect(w.open, dateOfDay(w0, b.pushDay), reason: b.id);
        expect(w.close, dateOfDay(w0, b.pushDay + b.windowDays), reason: b.id);
      }
    });

    test('the fixture pushes (server v2StepsFor): open on day 1, the one '
        'reminder on day 2, nothing on day 3, no e-mail', () {
      final pushes = (v2['pushes'] as List)
          .cast<Map<String, dynamic>>()
          .where((p) => ['W5', 'W6', 'W7'].contains(p['bundle']));
      for (final id in ['W5', 'W6', 'W7']) {
        final b = WeeklySchedule.bundleById(cfg, mode, id)!;
        final w = WeeklySchedule.windowFor(b, w0, cfg);
        final mine = pushes.where((p) => p['bundle'] == id).toList();
        expect(mine.map((p) => p['step']).toList(), ['open', 'remind1']);
        expect(dateKey(mine[0]['date'] as String), w.open, reason: id);
        expect(dateKey(mine[1]['date'] as String),
            w.open.add(const Duration(days: 1)), reason: id);
        expect(mine.map((p) => p['copyId']).toList(), ['S14-open', 'S14-rem']);
        expect(mine.any((p) => p['email'] == true), isFalse);
        // The reminder day is the row's 聽日截止 day.
        expect(
            QuestionnaireRowInfo.openState(
                b, w, dateKey(mine[1]['date'] as String).add(
                    const Duration(hours: 10))),
            QuestionnaireOpenState.tomorrow,
            reason: id);
      }
    });

    test('open at a moment around W5 (W4 recorded on day 30)', () {
      final rec = dateOfDay(w0, 30);
      String? at(DateTime t) => WeeklySchedule.openBundleAt(cfg, mode, w0, t,
              week4RecordedOn: rec)
          ?.bundle
          .id;
      expect(at(dateOfDay(w0, 35).subtract(const Duration(minutes: 1))),
          isNull);
      expect(at(dateOfDay(w0, 35)), 'W5');
      expect(at(dateOfDay(w0, 38).subtract(const Duration(seconds: 1))), 'W5');
      expect(at(dateOfDay(w0, 38)), isNull);
    });

    test('flag off: W5 exactly T24 at weeklyPushHour (default 10), 72 h', () {
      const c = PhaseBConfig(weeklyScheduleV2Enabled: true);
      final b = WeeklySchedule.bundleById(c, mode, 'W5')!;
      final w = WeeklySchedule.windowFor(b, w0, c, v2: false);
      expect(w.open, dateOfDay(w0, 35).add(const Duration(hours: 10)));
      expect(w.close, dateOfDay(w0, 38).add(const Duration(hours: 10)));
      // The old T24 table (weeklyPushHour 20 set in the fixture config).
      final std = (table['standard'] as Map<String, dynamic>)['bundles']
          as List;
      final e = std[4] as Map<String, dynamic>;
      final t24 = WeeklySchedule.windowFor(b, w0, cfg, v2: false);
      expect(t24.open, hkLocal(e['open'] as String));
      expect(t24.close, hkLocal(e['close'] as String));
    });
  });

  group('home questionnaire row, week 5 (fixture rowStatesW5)', () {
    final rows = (v2['rowStatesW5'] as Map<String, dynamic>)['cases'] as List;
    Future<QuestionnaireRowInfo?> at(DateTime now) =>
        QuestionnaireRowInfo.resolve(
          cfg: cfg,
          mode: mode,
          w0: w0,
          now: now,
          store: _Store({'W1', 'W2', 'W3', 'W4'}),
        );

    test('each case: state, words and the deadline line', () async {
      for (final c in rows.cast<Map<String, dynamic>>()) {
        final now = hkLocal(c['at'] as String);
        final i = (await at(now))!;
        final state = c['state'] as String;
        if (state == 'upcoming') {
          expect(i.isOpen, isFalse, reason: c['at'] as String);
          expect(i.opensOn, dateKey(c['opensOn'] as String),
              reason: c['at'] as String);
          expect(i.text, HomeV2Copy.w4(i.opensOn!));
          continue;
        }
        expect(i.isOpen, isTrue, reason: c['at'] as String);
        expect(i.due!.bundle.id, 'W5', reason: c['at'] as String);
        expect(i.state!.name, state, reason: c['at'] as String);
        // The last day of the window is day 37 (2026-11-25, Wednesday).
        expect(i.subtitle, '11月25日（星期三）截止', reason: c['at'] as String);
      }
      expect((await at(hkLocal('2026-11-23T10:00:00+08:00')))!.text,
          '問卷開咗，請盡快回答。');
      expect((await at(hkLocal('2026-11-24T10:00:00+08:00')))!.text,
          '問卷開咗，聽日截止。');
      expect((await at(hkLocal('2026-11-25T10:00:00+08:00')))!.text,
          '問卷開咗，今晚截止。');
    });

    test('W5–W7 are worded day by day exactly as W1–W3', () {
      for (final b in WeeklySchedule.bundlesFor(cfg, mode)) {
        if (b.closeRule == WeeklyCloseRule.week4) continue;
        final w = WeeklySchedule.windowFor(b, w0, cfg);
        final d0 = dateOfDay(w0, b.pushDay);
        expect([
          for (final (day, hour) in [(0, 0), (0, 10), (1, 10), (2, 10),
            (2, 23)])
            QuestionnaireRowInfo.openState(
                b, w, d0.add(Duration(days: day, hours: hour))),
        ], [
          QuestionnaireOpenState.asap,
          QuestionnaireOpenState.asap,
          QuestionnaireOpenState.tomorrow,
          QuestionnaireOpenState.tonight,
          QuestionnaireOpenState.tonight,
        ], reason: b.id);
      }
    });

    test('answered on day 35: the row moves on to W6 (opens day 42)',
        () async {
      final i = (await QuestionnaireRowInfo.resolve(
        cfg: cfg,
        mode: mode,
        w0: w0,
        now: hkLocal('2026-11-23T12:00:00+08:00'),
        store: _Store({'W1', 'W2', 'W3', 'W4', 'W5'}),
      ))!;
      expect(i.isOpen, isFalse);
      expect(i.opensOn, DateTime(2026, 11, 30));
    });

    test('the old card (pending prompts) picks W5 on days 35–37 only', () async {
      final store = _Store({'W1', 'W2', 'W3', 'W4'});
      Future<String?> due(DateTime t) async =>
          (await WeeklyBundleDue.firstNotDone(
                  WeeklySchedule.openBundlesAt(cfg, mode, w0, t), store))
              ?.bundle
              .id;
      expect(await due(hkLocal('2026-11-22T23:59:00+08:00')), isNull);
      expect(await due(hkLocal('2026-11-23T00:00:00+08:00')), 'W5');
      expect(await due(hkLocal('2026-11-25T23:59:00+08:00')), 'W5');
      expect(await due(hkLocal('2026-11-26T00:00:00+08:00')), isNull);
    });

    test('flag off: as before (window from 10:00 day 35 to 10:00 day 38: '
        '請盡快回答 on days 35–36, 聽日截止 day 37, 今晚截止 day 38)', () {
      const c = PhaseBConfig(weeklyScheduleV2Enabled: true);
      final b = WeeklySchedule.bundleById(c, mode, 'W5')!;
      final w = WeeklySchedule.windowFor(b, w0, c, v2: false);
      final d35 = dateOfDay(w0, 35);
      expect([
        for (final day in [0, 1, 2, 3])
          QuestionnaireRowInfo.openState(
              b, w, d35.add(Duration(days: day, hours: day == 3 ? 9 : 11))),
      ], [
        QuestionnaireOpenState.asap,
        QuestionnaireOpenState.asap,
        QuestionnaireOpenState.tomorrow,
        QuestionnaireOpenState.tonight,
      ]);
    });
  });

  group('home page row (MainShell), week 5, both arms', () {
    // The harness's W0 is 2026-10-14: day 35 = 11/18 (Wednesday), day 37 =
    // 11/20 (Friday), day 42 = 11/25.
    setUpAll(SessionCloseHint.claimFirstUse);
    setUp(() {
      PhaseBConfig.current = const PhaseBConfig(
          sessionBriefPrV2Enabled: true,
          weeklyScheduleV2Enabled: true,
          weeklyPushHour: 20);
      RemoteFeatureFlags.current = const RemoteFeatureFlags(
          homeLayoutV2Enabled: true,
          moodRowV2Enabled: true,
          checkInChatV2Enabled: true,
          weeklyReminderV2Enabled: true);
      MoodRowV2.resetForTest();
      DailyMoodPrompt.resetForTest();
      ChatSessionRecorder.resetProcessStateForTest();
    });
    tearDown(() {
      MoodRowV2.resetForTest();
      ChatSessionRecorder.resetProcessStateForTest();
    });

    for (final arm in testableArms) {
      final tag = arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';
      for (final (now, title, subtitle) in [
        (DateTime(2026, 11, 17, 23, 59), '下次問卷',
            '11月18日（星期三）開，開咗之後三日內答都得。'),
        (DateTime(2026, 11, 18, 0, 5), '問卷開咗，請盡快回答', '11月20日（星期五）截止'),
        (DateTime(2026, 11, 18, 10), '問卷開咗，請盡快回答', '11月20日（星期五）截止'),
        (DateTime(2026, 11, 19, 10), '問卷開咗，聽日截止', '11月20日（星期五）截止'),
        (DateTime(2026, 11, 20, 10), '問卷開咗，今晚截止', '11月20日（星期五）截止'),
        (DateTime(2026, 11, 20, 23, 59), '問卷開咗，今晚截止', '11月20日（星期五）截止'),
        (DateTime(2026, 11, 21, 10), '下次問卷',
            '11月25日（星期三）開，開咗之後三日內答都得。'),
      ]) {
        testWidgets('$tag: $now → $title', (tester) async {
          final run = HomeRun(arm, now: now);
          run.weekly.doneBundles.addAll(['W1', 'W2', 'W3', 'W4']);
          await pumpHome(tester, run, const MainShell());
          final open =
              find.byKey(const ValueKey('today_todo_questionnaire_open'));
          final next =
              find.byKey(const ValueKey('today_todo_questionnaire_next'));
          if (!FeatureFlags.phaseB) {
            // The study-week schedule needs a Phase B build.
            expect(open, findsNothing);
            expect(next, findsNothing);
            return;
          }
          final isOpen = title != '下次問卷';
          expect(isOpen ? open : next, findsOneWidget);
          final tile = tester.widget<TodoRowTile>(isOpen ? open : next);
          expect(tile.title, title);
          expect(tile.subtitle, subtitle);
          expect(tile.onTap == null, !isOpen);
          if (run.rule) expect(run.llm.calls, isEmpty);
        });
      }
    }
  });
}

/// 00:00 of study day [day] (W0 = day 0), local calendar.
DateTime dateOfDay(DateTime w0, int day) =>
    DateTime(w0.year, w0.month, w0.day + day);
