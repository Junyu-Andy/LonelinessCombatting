// T21 (registry v8 C01): the waiting page before registration.  S8 is
// copied word for word from the final copy; the gate is off unless the
// config says literally true; when on, only registered (cohort phase_b /
// pilot) and tester accounts get past it.
import 'dart:io';

import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/enrollment/presentation/enrollment_wait_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _p({String? cohort, bool tester = false, ArmAssignment? arm}) =>
    UserProfile(
        uid: 'u',
        email: 'e',
        displayName: 'd',
        cohort: cohort,
        isTester: tester,
        arm: arm);

Widget _gate(UserProfile? profile, {bool? gateOn}) => MaterialApp(
      home: EnrollmentWaitGate(
        profile: profile,
        gateOn: gateOn,
        child: const Text('participant app'),
      ),
    );

void main() {
  test('S8 matches docs/spec/copy/short-texts.md word for word', () {
    final row = File('docs/spec/copy/short-texts.md')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('| S8 |'));
    // | 编号 | 用在哪里 | 文字 | 说明 | 任务 |
    expect(enrollmentWaitingS8, row.split('|')[3].trim());
  });

  test('the gate is off unless literally true', () {
    expect(const RemoteFeatureFlags().enrollmentGateEnabled, isFalse);
    expect(RemoteFeatureFlags.fromMap({}).enrollmentGateEnabled, isFalse);
    expect(
        RemoteFeatureFlags.fromMap({'enrollmentGateEnabled': 'true'})
            .enrollmentGateEnabled,
        isFalse);
    expect(
        RemoteFeatureFlags.fromMap({'enrollmentGateEnabled': true})
            .enrollmentGateEnabled,
        isTrue);
  });

  test('cohort is read from Firestore but never written', () {
    final p = UserProfile.fromMap('u', {'cohort': 'pilot', 'arm': 'A'});
    expect(p.cohort, 'pilot');
    expect(p.isEnrolled, isTrue);
    expect(p.toMap().containsKey('cohort'), isFalse);
    expect(UserProfile.fromMap('u', {'cohort': 'phase_b'}).isEnrolled, isTrue);
    for (final c in [null, 'phase_a', 'B', '']) {
      expect(UserProfile.fromMap('u', {'cohort': c}).isEnrolled, isFalse,
          reason: '$c');
    }
  });

  test('who waits', () {
    bool wait(bool on, UserProfile? p) =>
        EnrollmentWaitGate.shouldWait(gateOn: on, profile: p);
    expect(wait(false, _p()), isFalse);
    expect(wait(true, _p()), isTrue);
    expect(wait(true, _p(arm: ArmAssignment.a)), isTrue,
        reason: 'an arm alone (force_a) is not a registration');
    expect(wait(true, _p(cohort: 'phase_b')), isFalse);
    expect(wait(true, _p(cohort: 'pilot')), isFalse);
    expect(wait(true, _p(tester: true)), isFalse);
    expect(wait(true, null), isFalse);
  });

  testWidgets('gate off (default): the App as before', (tester) async {
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
    await tester.pumpWidget(_gate(_p()));
    expect(find.text('participant app'), findsOneWidget);
    expect(find.text(enrollmentWaitingS8), findsNothing);
  });

  testWidgets('gate on, not registered: only S8, nothing else',
      (tester) async {
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(enrollmentGateEnabled: true);
    addTearDown(() => RemoteFeatureFlags.current = const RemoteFeatureFlags());
    await tester.pumpWidget(_gate(_p(arm: ArmAssignment.a)));
    expect(find.text(enrollmentWaitingS8), findsOneWidget);
    expect(find.text('participant app'), findsNothing);
    expect(find.byType(ButtonStyleButton), findsNothing);
    expect(find.byType(TextField), findsNothing);
    // One piece of text on the page: S8.
    expect(find.byType(Text), findsOneWidget);
  });

  for (final p in [_p(cohort: 'phase_b'), _p(cohort: 'pilot'),
    _p(tester: true)]) {
    testWidgets('gate on, ${p.cohort ?? 'tester'}: the App', (tester) async {
      await tester.pumpWidget(_gate(p, gateOn: true));
      expect(find.text('participant app'), findsOneWidget);
      expect(find.text(enrollmentWaitingS8), findsNothing);
    });
  }
}
