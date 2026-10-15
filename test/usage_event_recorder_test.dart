// T40 (registry C23) — usage events (foreground / background).  The pure
// recorder: switch, enrolment, the cold-start foreground held until the
// profile is known, matched pairs, and the row shape.  Both arms use the
// same recorder (it never looks at the arm).
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/usage/usage_event_recorder.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile profile(String uid, {String? cohort, String? arm}) =>
    UserProfile.fromMap(uid, {
      'uid': uid,
      if (cohort != null) 'cohort': cohort,
      if (arm != null) 'arm': arm,
    });

void main() {
  late InMemoryUsageEventSink sink;
  late bool on;
  late DateTime now;
  late UsageEventRecorder rec;

  setUp(() {
    sink = InMemoryUsageEventSink();
    on = true;
    now = DateTime(2026, 10, 15, 9, 0);
    rec = UsageEventRecorder(
      sink: sink,
      enabled: () => on,
      clock: () => now,
      platform: 'android',
      appVersion: '1.0.0',
      buildNumber: '3',
    );
  });

  group('switch and enrolment', () {
    test('flag parses: only literal true turns it on; default off', () {
      expect(const RemoteFeatureFlags().usageEventsEnabled, isFalse);
      expect(RemoteFeatureFlags.fromMap({}).usageEventsEnabled, isFalse);
      expect(RemoteFeatureFlags.fromMap({'usageEventsEnabled': 'true'})
          .usageEventsEnabled, isFalse);
      expect(RemoteFeatureFlags.fromMap({'usageEventsEnabled': true})
          .usageEventsEnabled, isTrue);
    });

    test('switch off: nothing is written, whatever happens', () {
      on = false;
      rec.onForeground();
      rec.setProfile(profile('u1', cohort: 'phase_b', arm: 'A'));
      rec.onBackground();
      rec.onForeground();
      rec.onBackground();
      expect(sink.events, isEmpty);
    });

    test('not registered (no cohort): nothing, including a tester', () {
      rec.onForeground();
      rec.setProfile(profile('u1'));
      rec.onBackground();
      rec.onForeground();
      rec.onBackground();
      expect(sink.events, isEmpty);
    });

    test('signed out: nothing', () {
      rec.onForeground();
      rec.setProfile(null);
      rec.onBackground();
      expect(sink.events, isEmpty);
    });

    for (final cohort in ['phase_b', 'pilot']) {
      for (final arm in ['A', 'B']) {
        test('enrolled $cohort arm $arm: foreground then background', () {
          rec.setProfile(profile('u1', cohort: cohort, arm: arm));
          rec.onForeground();
          now = now.add(const Duration(minutes: 3));
          rec.onBackground();
          expect(sink.events.map((e) => e.type.code),
              ['foreground', 'background']);
          expect(sink.events[0].clientAt, DateTime(2026, 10, 15, 9, 0));
          expect(sink.events[1].clientAt, DateTime(2026, 10, 15, 9, 3));
          expect(sink.events.every((e) => e.uid == 'u1'), isTrue);
        });
      }
    }
  });

  group('cold start', () {
    test('foreground before the profile is known is written once the '
        'enrolled profile arrives, with the ORIGINAL time', () {
      rec.onForeground(DateTime(2026, 10, 15, 8, 59, 30));
      expect(sink.events, isEmpty);
      now = DateTime(2026, 10, 15, 9, 0, 2);
      rec.setProfile(profile('u1', cohort: 'pilot', arm: 'B'));
      expect(sink.events.length, 1);
      expect(sink.events.single.type, UsageEventType.foreground);
      expect(sink.events.single.clientAt, DateTime(2026, 10, 15, 8, 59, 30));
      // The profile stream emits again: no duplicate.
      rec.setProfile(profile('u1', cohort: 'pilot', arm: 'B'));
      expect(sink.events.length, 1);
    });

    test('the switch is read when the profile lands (flags are re-read on '
        'sign-in), not at the foreground', () {
      on = false;
      rec.onForeground();
      on = true;
      rec.setProfile(profile('u1', cohort: 'phase_b', arm: 'A'));
      expect(sink.events.map((e) => e.type.code), ['foreground']);
    });

    test('registration landing while the App is open (cohort appears on a '
        'later profile emission): foreground written then, background '
        'later', () {
      rec.onForeground();
      rec.setProfile(profile('u1'));
      expect(sink.events, isEmpty);
      now = now.add(const Duration(minutes: 10));
      rec.setProfile(profile('u1', cohort: 'phase_b', arm: 'A'));
      expect(sink.events.map((e) => e.type.code), ['foreground']);
      expect(sink.events.single.clientAt, DateTime(2026, 10, 15, 9, 0),
          reason: 'the stretch started at 9:00');
      rec.onBackground();
      expect(sink.events.map((e) => e.type.code),
          ['foreground', 'background']);
    });
  });

  group('pairs', () {
    test('a background without a recorded foreground is not written', () {
      rec.onForeground();
      rec.setProfile(profile('u1'));
      rec.setProfile(profile('u1', cohort: 'phase_b', arm: 'A'));
      // recorded now (flush) — so background pairs with it
      rec.onBackground();
      expect(sink.events.map((e) => e.type.code),
          ['foreground', 'background']);
      sink.events.clear();
      // Switch turned off mid-stretch: foreground written, background not.
      rec.onForeground();
      on = false;
      rec.onBackground();
      expect(sink.events.map((e) => e.type.code), ['foreground']);
    });

    test('repeated lifecycle states do not double-write (iOS fires '
        'inactive → hidden → paused)', () {
      rec.setProfile(profile('u1', cohort: 'phase_b', arm: 'A'));
      rec.onForeground();
      rec.onForeground();
      rec.onBackground();
      rec.onBackground();
      rec.onBackground();
      expect(sink.events.map((e) => e.type.code),
          ['foreground', 'background']);
    });

    test('three cycles = six rows in order', () {
      rec.setProfile(profile('u1', cohort: 'pilot', arm: 'A'));
      for (var i = 0; i < 3; i++) {
        rec.onForeground();
        rec.onBackground();
      }
      expect(sink.events.map((e) => e.type.code), [
        'foreground', 'background', 'foreground', 'background',
        'foreground', 'background',
      ]);
    });

    test('account change mid-stretch: the new account starts fresh', () {
      rec.setProfile(profile('u1', cohort: 'phase_b', arm: 'A'));
      rec.onForeground();
      rec.setProfile(profile('u2', cohort: 'phase_b', arm: 'B'));
      rec.onBackground();
      expect(sink.events.map((e) => '${e.uid}:${e.type.code}'),
          ['u1:foreground', 'u2:foreground', 'u2:background']);
    });
  });

  group('row', () {
    test('toMap: the client fields only; clientAt is a Timestamp; '
        'schemaVersion 1; no arm, no text', () {
      rec.setProfile(profile('u1', cohort: 'phase_b', arm: 'A'));
      rec.onForeground();
      final map = sink.events.single.toMap();
      expect(map.keys.toSet(), {
        'type', 'clientAt', 'appVersion', 'buildNumber', 'platform',
        'schemaVersion',
      });
      expect(map['type'], 'foreground');
      expect(map['clientAt'], isA<Timestamp>());
      expect((map['clientAt'] as Timestamp).toDate(),
          DateTime(2026, 10, 15, 9, 0));
      expect(map['appVersion'], '1.0.0');
      expect(map['buildNumber'], '3');
      expect(map['platform'], 'android');
      expect(map['schemaVersion'], 1);
    });
  });
}
