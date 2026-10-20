// 1020e §2.14 — the researcher explanation gate in front of the intake,
// behind app_config/feature_flags.researcherIntakeGateEnabled (default off).
//
//   flag off : 注册 → 開始之前 → 入组问卷 (exactly as before)
//   flag on  : 注册 → 開始之前 → 等候页「請等研究人員同你講解，再繼續。」
//              → 研究员在正中连点 3 下（2 秒内）→ 入组问卷 → 引导 → 主页
//
// Both arms go through the same page and the same flow; every flow test
// runs for a Hybrid, a rule-arm and a not-yet-assigned profile, and the
// file also runs in the PHASE_B and PHASE_B + FORCE_ARM=B suites
// (tool/ci_flutter_tests.sh).  Synthetic profiles only; the unlock is
// written to a fake store.
import 'dart:async';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/consent/presentation/consent_gate.dart';
import 'package:app_demo/features/consent/presentation/pages/consent_page.dart';
import 'package:app_demo/features/enrollment/presentation/enrollment_wait_gate.dart';
import 'package:app_demo/features/onboarding/presentation/pages/agent_onboarding_page.dart';
import 'package:app_demo/features/onboarding/presentation/pages/intake_people_page.dart';
import 'package:app_demo/features/onboarding/presentation/pages/intake_short_page.dart';
import 'package:app_demo/features/onboarding/presentation/researcher_intake_gate.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(360, 780);

/// The page size the gate measures (no app bar: the whole screen).
final _zone = ResearcherIntakeGate.centreZone(_size);

class _FakeStore implements IntakeGateUnlockStore {
  final List<String> uids = [];
  @override
  Future<void> markUnlocked(String uid) async => uids.add(uid);
}

class _Clock {
  DateTime now = DateTime.utc(2026, 10, 20, 2);
  void advance(Duration d) => now = now.add(d);
}

const _arms = <ArmAssignment?>[ArmAssignment.a, ArmAssignment.b, null];
String _armName(ArmAssignment? a) => a?.code ?? 'none';

UserProfile _p({
  ArmAssignment? arm,
  bool consent = false,
  bool intake = false,
  bool peopleDone = false,
  AgentGenderVariant? variant,
  String? cohort,
  DateTime? onboarded,
  DateTime? unlocked,
}) => UserProfile(
  uid: 'u1',
  email: 'e@example.com',
  displayName: '測試',
  arm: arm,
  cohort: cohort,
  armAssignmentMode: cohort == null ? null : 'randomise',
  consent: ConsentFlags(functionalData: consent),
  hasCompletedIntake: intake,
  intakePeopleDone: peopleDone,
  ahJanAhBakVariant: variant,
  onboardingCompletedAt: onboarded,
  intakeGateUnlockedAt: unlocked,
);

/// The App below StaffGate, as AuthGate composes it: enrolment gate →
/// ConsentGate (consent → [gate] → intake → 介紹三個夥伴) → 'home'.
Widget _app(
  AppSettings settings, {
  required bool? gateOn,
  _FakeStore? store,
  bool researcherIntakeOn = false,
  bool enrolmentGateOn = false,
}) => AnalyticsScope(
  analytics: AnalyticsService(firebaseReady: false),
  child: AuthServiceScope(
    authService: AuthService(available: false),
    child: AppSettingsScope(
      settings: settings,
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: EnrollmentWaitGate(
          profile: settings.profile,
          gateOn: enrolmentGateOn,
          child: ConsentGate(
            onboardingFixOn: true,
            researcherIntakeOn: researcherIntakeOn,
            researcherIntakeGateOn: gateOn,
            intakeGateStore: store,
            child: const Text('home'),
          ),
        ),
      ),
    ),
  ),
);

/// "Close and reopen the App": unmount everything, then build again from
/// [settings] (the profile as read from the server at sign-in).
Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(_size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

final _gateText = find.text(researcherIntakeGateText);
final _home = find.text('home');
final _intake = find.byType(IntakeShortPage);

Future<void> _tapAt(WidgetTester tester, Offset at, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.tapAt(at);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _acceptConsent(WidgetTester tester) async {
  expect(find.byType(ConsentPage), findsOneWidget);
  await tester.tap(find.text('繼續'));
  await tester.pumpAndSettle();
}

/// Everything a viewer can see or press on the waiting page.
List<String> _visible(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

void _expectBareWaitingPage(WidgetTester tester) {
  expect(_gateText, findsOneWidget);
  expect(_visible(tester), [
    researcherIntakeGateText,
  ], reason: 'one line, no hint');
  expect(
    find.byWidgetPredicate(
      (w) =>
          w is ButtonStyleButton ||
          w is IconButton ||
          w is FloatingActionButton ||
          w is InkWell ||
          w is Icon ||
          w is EditableText,
    ),
    findsNothing,
    reason: 'no button, no icon, no field',
  );
  // A screen reader finds nothing to press either.
  expect(
    tester
        .widget<GestureDetector>(find.byKey(const Key('intake_gate_tap_area')))
        .excludeFromSemantics,
    isTrue,
  );
  expect(_intake, findsNothing);
  expect(find.byType(IntakePeoplePage), findsNothing);
  expect(_home, findsNothing);
}

void main() {
  tearDown(() => RemoteFeatureFlags.current = const RemoteFeatureFlags());

  group('switch and field', () {
    test('switch: default off; only a literal true turns it on', () {
      expect(const RemoteFeatureFlags().researcherIntakeGateEnabled, isFalse);
      expect(
        RemoteFeatureFlags.fromMap({}).researcherIntakeGateEnabled,
        isFalse,
      );
      for (final v in ['true', 1, 'yes', null, false]) {
        expect(
          RemoteFeatureFlags.fromMap({
            'researcherIntakeGateEnabled': v,
          }).researcherIntakeGateEnabled,
          isFalse,
          reason: '$v',
        );
      }
      expect(
        RemoteFeatureFlags.fromMap({
          'researcherIntakeGateEnabled': true,
        }).researcherIntakeGateEnabled,
        isTrue,
      );
    });

    test('a failed re-read keeps the last value read (lastKnown); nothing '
        'read yet = unknown', () async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags(
        researcherIntakeGateEnabled: true,
      );
      // No Firebase in tests: this read fails like a time-out would.
      await RemoteFeatureFlags.load();
      expect(
        RemoteFeatureFlags.current.researcherIntakeGateEnabled,
        isFalse,
        reason: 'current: unchanged behaviour, all off on failure',
      );
      expect(RemoteFeatureFlags.lastKnown?.researcherIntakeGateEnabled, isTrue);

      RemoteFeatureFlags.resetForTest(attempted: true);
      expect(RemoteFeatureFlags.lastKnown, isNull);
      RemoteFeatureFlags.resetForTest();
      expect(
        RemoteFeatureFlags.lastKnown,
        isNotNull,
        reason: 'never tried (guest mode / tests): the defaults',
      );
    });

    test(
      'intakeGateUnlockedAt: read back, kept by copyWith, never in toMap',
      () {
        final at = DateTime.utc(2026, 10, 20, 2, 3, 4);
        final p = _p(unlocked: at);
        expect(
          p.toMap().containsKey('intakeGateUnlockedAt'),
          isFalse,
          reason: 'only the server time is written (the unlock store)',
        );
        expect(p.copyWith(displayName: 'x').intakeGateUnlockedAt, at);
        expect(
          UserProfile.fromMap('u1', {
            'intakeGateUnlockedAt': at,
          }).intakeGateUnlockedAt,
          at,
        );
        expect(
          UserProfile.fromMap('u1', {
            'intakeGateUnlockedAt': Timestamp.fromDate(at),
          }).intakeGateUnlockedAt!.toUtc(),
          at,
        );
        expect(UserProfile.fromMap('u1', {}).intakeGateUnlockedAt, isNull);
      },
    );

    test('the unlock store writes the server time, nothing else', () {
      final payload = FirestoreIntakeGateUnlockStore.payload();
      expect(payload.keys, ['intakeGateUnlockedAt']);
      expect(payload['intakeGateUnlockedAt'], isA<FieldValue>());
    });

    test('centre zone: the middle cell of a 3 × 3 grid', () {
      expect(_zone, const Rect.fromLTWH(120, 260, 120, 260));
      expect(_zone.contains(_size.center(Offset.zero)), isTrue);
      expect(_zone.contains(const Offset(119, 390)), isFalse);
      expect(_zone.contains(const Offset(180, 259)), isFalse);
    });

    test('who meets the gate (ResearcherIntakeGate.applies)', () {
      final now = DateTime.now();
      expect(ResearcherIntakeGate.applies(_p()), isTrue, reason: 'new');
      expect(ResearcherIntakeGate.applies(_p(unlocked: now)), isFalse);
      expect(
        ResearcherIntakeGate.applies(_p(onboarded: now)),
        isFalse,
        reason: 'finished 介紹三個夥伴',
      );
      expect(
        ResearcherIntakeGate.applies(_p(variant: AgentGenderVariant.feminine)),
        isFalse,
        reason: 'onboarded before the T37 marker, not registered',
      );
      expect(
        ResearcherIntakeGate.applies(
          _p(
            variant: AgentGenderVariant.masculine,
            cohort: 'phase_b',
            arm: ArmAssignment.b,
          ),
        ),
        isTrue,
        reason: 'pairing written by an old registration, not onboarded',
      );
    });
  });

  for (final arm in _arms) {
    group('arm ${_armName(arm)}', () {
      testWidgets('flag off: sign-up → 開始之前 → the five questions, as '
          'before', (tester) async {
        final store = _FakeStore();
        final settings = AppSettings(profile: _p(arm: arm));
        await _open(tester, _app(settings, gateOn: false, store: store));
        await _acceptConsent(tester);
        expect(_gateText, findsNothing);
        expect(_intake, findsOneWidget);
        expect(store.uids, isEmpty);
        expect(settings.profile!.intakeGateUnlockedAt, isNull);
      });

      testWidgets('flag off, researcher intake on: straight to 重要嘅人', (
        tester,
      ) async {
        final settings = AppSettings(profile: _p(arm: arm, consent: true));
        await _open(
          tester,
          _app(
            settings,
            gateOn: false,
            researcherIntakeOn: true,
            store: _FakeStore(),
          ),
        );
        expect(_gateText, findsNothing);
        expect(find.byType(IntakePeoplePage), findsOneWidget);
      });

      testWidgets('flag on: after sign-up and 開始之前 the App stops on the '
          'waiting page — one line, no button, no hint', (tester) async {
        final settings = AppSettings(profile: _p(arm: arm));
        await _open(tester, _app(settings, gateOn: true, store: _FakeStore()));
        await _acceptConsent(tester);
        _expectBareWaitingPage(tester);
      });

      testWidgets('flag on: 3 taps outside the centre, or 2 in it, do '
          'nothing; 3 quick taps in the centre open the intake and store '
          'the unlock', (tester) async {
        final store = _FakeStore();
        final settings = AppSettings(profile: _p(arm: arm, consent: true));
        await _open(tester, _app(settings, gateOn: true, store: store));
        _expectBareWaitingPage(tester);

        // Corners, edges and just outside the centre cell do nothing
        // (and do not count towards the three).
        for (final at in [
          const Offset(10, 10),
          const Offset(350, 770),
          _zone.centerLeft - const Offset(2, 0),
          _zone.centerRight + const Offset(2, 0),
          _zone.topCenter - const Offset(0, 2),
          _zone.bottomCenter + const Offset(0, 2),
        ]) {
          await _tapAt(tester, at, times: 3);
          expect(_gateText, findsOneWidget, reason: 'outside: $at');
        }
        await _tapAt(tester, _zone.center, times: 2);
        expect(_gateText, findsOneWidget, reason: 'two taps');
        expect(store.uids, isEmpty);
        expect(settings.profile!.intakeGateUnlockedAt, isNull);

        await _tapAt(tester, _zone.center);
        expect(_gateText, findsNothing, reason: 'the third quick tap');
        expect(_intake, findsOneWidget);
        expect(store.uids, ['u1'], reason: 'one server-time write');
        expect(settings.profile!.intakeGateUnlockedAt, isNotNull);
      });

      testWidgets('flag on: leaving the App on the waiting page brings it '
          'back; once unlocked it never shows again', (tester) async {
        final store = _FakeStore();
        final signedUp = _p(arm: arm, consent: true);
        await _open(
          tester,
          _app(AppSettings(profile: signedUp), gateOn: true, store: store),
        );
        expect(_gateText, findsOneWidget);

        // Restart (nothing was unlocked): the same page again.
        await _open(
          tester,
          _app(AppSettings(profile: signedUp), gateOn: true, store: store),
        );
        expect(_gateText, findsOneWidget);
        expect(_intake, findsNothing);

        // Unlock, leave mid-intake, restart: the server now holds the time.
        await _tapAt(tester, _zone.center, times: 3);
        expect(_intake, findsOneWidget);
        expect(store.uids, ['u1']);
        final stored = signedUp.copyWith(
          intakeGateUnlockedAt: DateTime.utc(2026, 10, 20, 2),
        );
        await _open(
          tester,
          _app(AppSettings(profile: stored), gateOn: true, store: store),
        );
        expect(_gateText, findsNothing);
        expect(_intake, findsOneWidget, reason: 'straight back to the intake');

        // Intake done → onboarding → home; reopening never shows the gate.
        final settings = AppSettings(profile: stored);
        await _open(tester, _app(settings, gateOn: true, store: store));
        settings.profile = stored.copyWith(
          hasCompletedIntake: true,
          intakePeopleDone: true,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AgentOnboardingPage), findsOneWidget);
        expect(_gateText, findsNothing);
        settings.profile = settings.profile!.copyWith(
          ahJanAhBakVariant: AgentGenderVariant.feminine,
          onboardingCompletedAt: DateTime.now(),
        );
        await _open(tester, _app(settings, gateOn: true, store: store));
        expect(_home, findsOneWidget);
        expect(_gateText, findsNothing);
        expect(store.uids, ['u1'], reason: 'written once');
      });

      testWidgets('flag on: an account that already finished onboarding '
          'never sees the gate — even if an intake page would show again', (
        tester,
      ) async {
        final done = DateTime.utc(2026, 10, 10);
        for (final (profile, researcherIntake, expected) in [
          // Fully onboarded → home.
          (
            _p(
              arm: arm,
              consent: true,
              intake: true,
              peopleDone: true,
              variant: AgentGenderVariant.masculine,
              onboarded: done,
            ),
            false,
            _home,
          ),
          // Onboarded before 10/16: researcher intake on shows 重要嘅人
          // again (intakePeopleDone is new) — but no gate in front of it.
          (
            _p(
              arm: arm,
              consent: true,
              intake: true,
              variant: AgentGenderVariant.masculine,
              onboarded: done,
            ),
            true,
            find.byType(IntakePeoplePage),
          ),
          // Onboarded before the T37 marker (pairing, not registered).
          (
            _p(
              arm: arm,
              consent: true,
              intake: true,
              variant: AgentGenderVariant.feminine,
            ),
            true,
            find.byType(IntakePeoplePage),
          ),
        ]) {
          await _open(
            tester,
            _app(
              AppSettings(profile: profile),
              gateOn: true,
              researcherIntakeOn: researcherIntake,
              store: _FakeStore(),
            ),
          );
          expect(_gateText, findsNothing, reason: '$expected');
          expect(expected, findsOneWidget);
        }
      });

      testWidgets('flag on, researcher intake on: the gate stands in front '
          'of 重要嘅人 the same way', (tester) async {
        final store = _FakeStore();
        final settings = AppSettings(profile: _p(arm: arm, consent: true));
        await _open(
          tester,
          _app(settings, gateOn: true, researcherIntakeOn: true, store: store),
        );
        _expectBareWaitingPage(tester);
        await _tapAt(tester, _zone.center, times: 3);
        expect(find.byType(IntakePeoplePage), findsOneWidget);
        expect(store.uids, ['u1']);
      });

      testWidgets('flag on, register-first order: S8 → registered → 開始之前 '
          '→ gate → intake', (tester) async {
        final settings = AppSettings(profile: _p());
        final store = _FakeStore();
        await _open(
          tester,
          _app(settings, gateOn: true, store: store, enrolmentGateOn: true),
        );
        expect(find.text(enrollmentWaitingS8), findsOneWidget);
        expect(_gateText, findsNothing, reason: 'S8 comes first');

        settings.profile = _p(
          arm: arm ?? ArmAssignment.b,
          cohort: 'phase_b',
          variant: AgentGenderVariant.masculine,
        );
        await _open(
          tester,
          _app(settings, gateOn: true, store: store, enrolmentGateOn: true),
        );
        await _acceptConsent(tester);
        _expectBareWaitingPage(tester);
        await _tapAt(tester, _zone.center, times: 3);
        expect(_intake, findsOneWidget);
      });
    });
  }

  testWidgets('both arms see the very same waiting page', (tester) async {
    final seen = <String, List<String>>{};
    for (final arm in _arms) {
      await _open(
        tester,
        _app(
          AppSettings(profile: _p(arm: arm, consent: true)),
          gateOn: true,
          store: _FakeStore(),
        ),
      );
      seen[_armName(arm)] = _visible(tester);
    }
    expect(
      seen.values.map((v) => v.join('|')).toSet(),
      hasLength(1),
      reason: '$seen',
    );
  });

  group('tap timing (clock injected)', () {
    Future<(_Clock, _FakeStore, AppSettings)> pumpGate(
      WidgetTester tester,
    ) async {
      final clock = _Clock();
      final store = _FakeStore();
      final settings = AppSettings(profile: _p(consent: true));
      await tester.binding.setSurfaceSize(_size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppSettingsScope(
          settings: settings,
          child: MaterialApp(
            home: Builder(
              builder: (context) => ResearcherIntakeGate(
                profile: AppSettingsScope.of(context).profile!,
                gateOn: true,
                store: store,
                clock: () => clock.now,
                child: const Text('intake'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (clock, store, settings);
    }

    Future<void> tapCentre(WidgetTester tester) async {
      await tester.tapAt(_zone.center);
      await tester.pumpAndSettle();
    }

    testWidgets('3 slow taps (1.1 s apart, 2.2 s in all) do not unlock', (
      tester,
    ) async {
      final (clock, store, _) = await pumpGate(tester);
      for (var i = 0; i < 6; i++) {
        await tapCentre(tester);
        clock.advance(const Duration(milliseconds: 1100));
      }
      expect(_gateText, findsOneWidget);
      expect(store.uids, isEmpty);
    });

    testWidgets('3 taps exactly 2 s from first to last unlock', (tester) async {
      final (clock, store, settings) = await pumpGate(tester);
      await tapCentre(tester);
      clock.advance(const Duration(seconds: 1));
      await tapCentre(tester);
      clock.advance(const Duration(seconds: 1));
      await tapCentre(tester);
      expect(find.text('intake'), findsOneWidget);
      expect(store.uids, ['u1']);
      expect(settings.profile!.intakeGateUnlockedAt, clock.now);
    });

    testWidgets('a slow start does not count: 1 tap, pause, then 3 quick '
        'taps unlock; outside taps in between neither count nor reset', (
      tester,
    ) async {
      final (clock, store, _) = await pumpGate(tester);
      await tapCentre(tester);
      clock.advance(const Duration(seconds: 5));
      await tapCentre(tester);
      clock.advance(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(20, 20)); // outside
      await tester.pumpAndSettle();
      await tapCentre(tester);
      expect(_gateText, findsOneWidget, reason: 'only 2 in the window');
      clock.advance(const Duration(milliseconds: 300));
      await tapCentre(tester);
      expect(find.text('intake'), findsOneWidget);
      expect(store.uids, ['u1']);
    });

    testWidgets('the intake opens at once even if the parent does not '
        'rebuild; further taps write nothing more', (tester) async {
      final store = _FakeStore();
      final settings = AppSettings(profile: _p(consent: true));
      await tester.binding.setSurfaceSize(_size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppSettingsScope(
          settings: settings,
          child: MaterialApp(
            home: ResearcherIntakeGate(
              profile: _p(consent: true), // fixed: no dependency on the scope
              gateOn: true,
              store: store,
              child: const Text('intake'),
            ),
          ),
        ),
      );
      await _tapAt(tester, _zone.center, times: 3);
      expect(find.text('intake'), findsOneWidget);
      await _tapAt(tester, _zone.center, times: 3);
      expect(store.uids, ['u1']);
      expect(settings.profile!.intakeGateUnlockedAt, isNotNull);
    });
  });

  group(
    'switch timing: the gate never decides on a switch it has not read',
    () {
      Widget gate(
        Future<void> Function(Duration) reload, {
        Duration wait = const Duration(seconds: 8),
        _FakeStore? store,
      }) => AppSettingsScope(
        settings: AppSettings(profile: _p(consent: true)),
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) => ResearcherIntakeGate(
              profile: AppSettingsScope.of(context).profile!,
              reloadFlags: reload,
              flagWait: wait,
              store: store ?? _FakeStore(),
              child: const Text('intake'),
            ),
          ),
        ),
      );

      final loading = find.byKey(const Key('intake_gate_loading'));

      setUp(() => RemoteFeatureFlags.resetForTest(attempted: true));
      tearDown(RemoteFeatureFlags.resetForTest);

      testWidgets('read already in (sign-in re-read): no wait at all', (
        tester,
      ) async {
        RemoteFeatureFlags.current = const RemoteFeatureFlags(
          researcherIntakeGateEnabled: true,
        );
        var reads = 0;
        await tester.pumpWidget(gate((_) async => reads++));
        await tester.pumpAndSettle();
        expect(_gateText, findsOneWidget);
        expect(reads, 0);
      });

      for (final on in [true, false]) {
        testWidgets('nothing read yet: 「等一陣…」 (no intake, no gate) until '
            'the re-read lands, then ${on ? 'the gate' : 'the intake'}', (
          tester,
        ) async {
          final pending = Completer<void>();
          await tester.pumpWidget(gate((_) => pending.future));
          await tester.pump();
          expect(loading, findsOneWidget);
          expect(find.text('等一陣…'), findsOneWidget);
          expect(
            find.text('intake'),
            findsNothing,
            reason: 'a slow read never skips the gate',
          );
          expect(_gateText, findsNothing);

          await tester.pump(const Duration(seconds: 5));
          expect(loading, findsOneWidget);

          RemoteFeatureFlags.current = RemoteFeatureFlags(
            researcherIntakeGateEnabled: on,
          );
          pending.complete();
          await tester.pump();
          await tester.pump();
          expect(loading, findsNothing);
          expect(on ? _gateText : find.text('intake'), findsOneWidget);
        });
      }

      testWidgets('reads keep failing: after the wait the waiting page shows '
          'anyway (fail closed), retries go on with longer time-outs, and the '
          'researcher can still unlock', (tester) async {
        await tester.binding.setSurfaceSize(_size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final timeouts = <Duration>[];
        final store = _FakeStore();
        await tester.pumpWidget(
          gate((t) async {
            timeouts.add(t);
            throw TimeoutException('slow network');
          }, store: store),
        );
        await tester.pump();
        expect(loading, findsOneWidget);
        await tester.pump(const Duration(seconds: 7));
        expect(loading, findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        expect(loading, findsNothing);
        expect(_gateText, findsOneWidget, reason: 'never blocks forever');
        await tester.pump(const Duration(seconds: 60));
        expect(timeouts.length, greaterThan(3), reason: 'still re-reading');
        expect(timeouts.first, const Duration(seconds: 6));
        expect(timeouts.last, const Duration(seconds: 20));

        await tester.tapAt(_zone.center);
        await tester.pump();
        await tester.tapAt(_zone.center);
        await tester.pump();
        await tester.tapAt(_zone.center);
        await tester.pump();
        expect(find.text('intake'), findsOneWidget);
        expect(store.uids, ['u1']);
        // Unlocked: no more re-reads.
        final n = timeouts.length;
        await tester.pump(const Duration(seconds: 60));
        expect(timeouts.length, n);
      });

      testWidgets('waited out, then a re-read says off: the intake opens by '
          'itself', (tester) async {
        var fail = true;
        await tester.pumpWidget(
          gate((_) async {
            if (fail) throw TimeoutException('slow network');
            RemoteFeatureFlags.current = const RemoteFeatureFlags();
          }, wait: const Duration(seconds: 2)),
        );
        await tester.pump(const Duration(seconds: 3));
        expect(_gateText, findsOneWidget);
        fail = false;
        await tester.pump(const Duration(seconds: 15));
        expect(find.text('intake'), findsOneWidget);
        expect(_gateText, findsNothing);
      });

      testWidgets('ConsentGate follows a re-read that lands later (choice of '
          'intake page included)', (tester) async {
        await tester.binding.setSurfaceSize(_size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final settings = AppSettings(profile: _p(consent: true));
        await tester.pumpWidget(
          AnalyticsScope(
            analytics: AnalyticsService(firebaseReady: false),
            child: AuthServiceScope(
              authService: AuthService(available: false),
              child: AppSettingsScope(
                settings: settings,
                child: MaterialApp(
                  locale: const Locale('zh'),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  home: ConsentGate(
                    intakeGateStore: _FakeStore(),
                    child: const Text('home'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(loading, findsOneWidget);

        // AuthGate's sign-in re-read (or the gate's own) lands: both the
        // gate switch and researcherIntakeEnabled are now known.
        RemoteFeatureFlags.current = const RemoteFeatureFlags(
          researcherIntakeGateEnabled: true,
          researcherIntakeEnabled: true,
        );
        RemoteFeatureFlags.reads.value++;
        await tester.pump();
        await tester.pump();
        expect(_gateText, findsOneWidget);
        await tester.tapAt(_zone.center);
        await tester.pump();
        await tester.tapAt(_zone.center);
        await tester.pump();
        await tester.tapAt(_zone.center);
        await tester.pumpAndSettle();
        expect(
          find.byType(IntakePeoplePage),
          findsOneWidget,
          reason: 'the page researcherIntakeEnabled asks for',
        );
      });
    },
  );

  testWidgets('waiting page fits a small phone at the largest text size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const ResearcherIntakeWaitingPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_gateText, findsOneWidget);
  });
}
