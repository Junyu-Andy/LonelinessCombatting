// 1020o 第三节 (decision 0066) — 自己 → 我的設定 → 「安靜時段」: one line and
// two choices, 「由」 and 「到」, no on/off switch.  The pickers offer only
// the allowed half-hour times (QuietHoursRange); a pick writes "HH:mm" to
// users/{uid}.quietHoursStart / quietHoursEnd and one quiet_hours_changed
// usage event.  Same page for both arms.  Runs in the default build and in
// the two Phase B lists of tool/ci_flutter_tests.sh.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/notifications/quiet_hours_range.dart';
import 'package:app_demo/core/usage/usage_event_recorder.dart';
import 'package:app_demo/core/usage/usage_events_scope.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/settings/data/quiet_hours_store.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _profile(ArmAssignment arm,
        {String? start, String? end, String? cohort = 'rct'}) =>
    UserProfile(
      uid: 'synthetic-qh',
      email: 'qh@test.invalid',
      displayName: '陳婆婆',
      arm: arm,
      cohort: cohort,
      quietHoursStart: start,
      quietHoursEnd: end,
    );

class _Harness {
  _Harness(UserProfile profile)
      : settings = AppSettings(locale: const Locale('zh'), profile: profile) {
    recorder.setProfile(profile);
  }

  /// The App's text size: 特大 (1.30), the size every page is checked at.
  static const double scale = 1.30;

  final AppSettings settings;
  final store = InMemoryQuietHoursStore();
  final sink = InMemoryUsageEventSink();
  late final UsageEventRecorder recorder = UsageEventRecorder(
      sink: sink, enabled: () => true, appVersion: '0', buildNumber: '0');

  Widget get app => AppSettingsScope(
        settings: settings,
        child: UsageEventsScope(
          recorder: recorder,
          child: MaterialApp(
            locale: const Locale('zh'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: MySettingsPage(quietHoursStore: store),
          ),
        ),
      );
}

Future<_Harness> _open(WidgetTester tester, UserProfile profile) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = _Harness(profile);
  await tester.pumpWidget(h.app);
  await tester.pumpAndSettle();
  return h;
}

String _rowValue(WidgetTester tester, String key) {
  final texts = tester
      .widgetList<Text>(find.descendant(
          of: find.byKey(Key(key)), matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  return texts.last!;
}

List<String> _sheetOptions(WidgetTester tester) => tester
    .widgetList<InkWell>(find.descendant(
        of: find.byKey(const Key('quiet_hours_sheet')),
        matching: find.byType(InkWell)))
    .map((w) => (w.key! as ValueKey<String>)
        .value
        .replaceFirst('quiet_hours_option_', ''))
    .toList();

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('QuietHoursRange (【待 Junyu 定】 start 20:00–23:00, end 06:00–08:00)',
      () {
    test('half-hour steps inside the range only', () {
      expect(QuietHoursRange.startOptions, [
        '20:00', '20:30', '21:00', '21:30', '22:00', '22:30', '23:00', //
      ]);
      expect(QuietHoursRange.endOptions,
          ['06:00', '06:30', '07:00', '07:30', '08:00']);
      expect(QuietHoursRange.startOptions, contains(QuietHoursRange.defaultStart));
      expect(QuietHoursRange.endOptions, contains(QuietHoursRange.defaultEnd));
    });

    test('a stored value is shown the way the server uses it', () {
      expect(QuietHoursRange.effectiveStart(null), '22:00');
      expect(QuietHoursRange.effectiveEnd(null), '08:00');
      expect(QuietHoursRange.effectiveStart('21:30'), '21:30');
      // Outside the range → the nearest edge (functions/quiet_hours.js).
      expect(QuietHoursRange.effectiveStart('19:00'), '20:00');
      expect(QuietHoursRange.effectiveStart('23:45'), '23:00');
      expect(QuietHoursRange.effectiveEnd('09:00'), '08:00');
      expect(QuietHoursRange.effectiveEnd('05:00'), '06:00');
      // Malformed → the default, as the server falls back to the global.
      expect(QuietHoursRange.effectiveStart('9pm'), '22:00');
      expect(QuietHoursRange.effectiveEnd('25:00'), '08:00');
    });
  });

  group('UserProfile', () {
    test('reads the two fields; profile saves never write them', () {
      final p = UserProfile.fromMap('u1', {
        'email': 'a@b.c',
        'displayName': 'x',
        'quietHoursStart': '20:30',
        'quietHoursEnd': '06:00',
      });
      expect(p.quietHoursStart, '20:30');
      expect(p.quietHoursEnd, '06:00');
      final map = p.toMap();
      expect(map.containsKey('quietHoursStart'), isFalse);
      expect(map.containsKey('quietHoursEnd'), isFalse);
      expect(map.containsKey('quietHoursEnabled'), isFalse);
      // Another setting's save keeps them in memory.
      final q = p.copyWith(memoryEnabled: true);
      expect(q.quietHoursStart, '20:30');
      expect(q.quietHoursEnd, '06:00');
      // Wrong type in the doc → treated as not set.
      final r = UserProfile.fromMap(
          'u1', {'quietHoursStart': 2000, 'quietHoursEnd': true});
      expect(r.quietHoursStart, isNull);
      expect(r.quietHoursEnd, isNull);
    });
  });

  for (final arm in ArmAssignment.values) {
    group('arm ${arm.code}', () {
      testWidgets('安靜時段: the line, 由 22:00, 到 08:00 by default; no switch',
          (tester) async {
        await _open(tester, _profile(arm));
        expect(find.text('安靜時段'), findsOneWidget);
        expect(find.text('呢段時間 App 唔會彈出通知。'), findsOneWidget);
        expect(find.text('由'), findsOneWidget);
        expect(find.text('到'), findsOneWidget);
        expect(_rowValue(tester, 'quiet_hours_start'), '22:00');
        expect(_rowValue(tester, 'quiet_hours_end'), '08:00');
        expect(
            find.descendant(
                of: find.byKey(const Key('quiet_hours_card')),
                matching: find.byType(Switch)),
            findsNothing);
        // 高對比 is still there, above.
        expect(find.text('高對比模式'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('「由」 offers only 20:00…23:00 in half hours; a pick saves '
          'HH:mm and logs one event', (tester) async {
        final h = await _open(tester, _profile(arm));
        await _tap(tester, find.byKey(const Key('quiet_hours_start')));
        expect(find.text('安靜時段：由'), findsOneWidget);
        expect(_sheetOptions(tester), QuietHoursRange.startOptions);
        for (final no in ['19:30', '23:30', '06:00', '08:00', '22:15']) {
          expect(find.byKey(Key('quiet_hours_option_$no')), findsNothing);
        }
        await _tap(tester, find.byKey(const Key('quiet_hours_option_20:30')));
        expect(find.byKey(const Key('quiet_hours_sheet')), findsNothing);
        expect(_rowValue(tester, 'quiet_hours_start'), '20:30');
        expect(h.store.docs['synthetic-qh'], {'quietHoursStart': '20:30'});
        expect(h.settings.profile!.quietHoursStart, '20:30');
        expect(h.settings.profile!.quietHoursEnd, isNull,
            reason: '到 untouched: the server keeps the global end');
        final rows = h.sink.events.map((e) => e.toMap()..remove('clientAt'));
        expect(rows.toList(), [
          {
            'type': 'quiet_hours_changed', 'appVersion': '0',
            'buildNumber': '0', 'platform': 'unknown', 'schemaVersion': 1,
            'field': 'start', 'from': '22:00', 'to': '20:30',
          },
        ]);
      });

      testWidgets('「到」 offers only 06:00…08:00; the same time again writes '
          'nothing', (tester) async {
        final h = await _open(tester, _profile(arm, start: '21:00'));
        expect(_rowValue(tester, 'quiet_hours_start'), '21:00');
        await _tap(tester, find.byKey(const Key('quiet_hours_end')));
        expect(find.text('安靜時段：到'), findsOneWidget);
        expect(_sheetOptions(tester), QuietHoursRange.endOptions);
        // The current one is marked.
        expect(
            find.descendant(
                of: find.byKey(const Key('quiet_hours_option_08:00')),
                matching: find.byIcon(Icons.check_rounded)),
            findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        await _tap(tester, find.byKey(const Key('quiet_hours_option_08:00')));
        expect(h.store.docs, isEmpty);
        expect(h.sink.events, isEmpty);
        await _tap(tester, find.byKey(const Key('quiet_hours_end')));
        await _tap(tester, find.byKey(const Key('quiet_hours_option_06:00')));
        expect(_rowValue(tester, 'quiet_hours_end'), '06:00');
        expect(h.store.docs['synthetic-qh'], {'quietHoursEnd': '06:00'});
        expect(h.sink.events.single.toMap()['field'], 'end');
        expect(h.sink.events.single.toMap()['from'], '08:00');
        expect(h.sink.events.single.toMap()['to'], '06:00');
      });

      testWidgets('a stored out-of-range value shows as the range edge',
          (tester) async {
        await _open(tester, _profile(arm, start: '19:00', end: '09:30'));
        expect(_rowValue(tester, 'quiet_hours_start'), '20:00');
        expect(_rowValue(tester, 'quiet_hours_end'), '08:00');
      });
    });
  }

  testWidgets('not enrolled: the pick is saved, no usage event',
      (tester) async {
    final h = await _open(tester, _profile(ArmAssignment.a, cohort: null));
    await _tap(tester, find.byKey(const Key('quiet_hours_start')));
    await _tap(tester, find.byKey(const Key('quiet_hours_option_23:00')));
    expect(h.store.docs['synthetic-qh'], {'quietHoursStart': '23:00'});
    expect(h.sink.events, isEmpty);
  });

  testWidgets('largest text on an iPad width and a small phone: no overflow',
      (tester) async {
    addTearDown(tester.view.reset);
    for (final size in const [Size(320, 640), Size(820, 1180)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final h = _Harness(_profile(ArmAssignment.b));
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('quiet_hours_start')));
      expect(tester.takeException(), isNull, reason: '$size');
      await _tap(tester, find.byKey(const Key('quiet_hours_option_22:30')));
      expect(_rowValue(tester, 'quiet_hours_start'), '22:30');
    }
  });
}
