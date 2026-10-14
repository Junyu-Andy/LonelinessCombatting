// T37 fix 1 — 「介紹三個夥伴」 still runs after the researcher's registration,
// behind app_config/feature_flags.onboardingAfterEnrollmentFix (default
// off).  The decision uses the onboarding-completed marker
// users/{uid}.onboardingCompletedAt instead of "a pairing exists" (the
// registration writes the pairing too).  Both orders are covered, with
// T21's enrolment gate on and off:
//   register-first : 注册 → 等待页 S8 → 登记 → 重开 App → 同意 → 入组问卷 →
//                    完整引导（配对预选登记值，S5 开关开时有 S5）→ 完成 → 主页
//   onboarding-first: today's order, unchanged.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/config/usage_copy.dart';
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
import 'package:app_demo/features/onboarding/presentation/pages/intake_flow_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the App's 「完成」 has always written besides the pairing: the
/// per-companion transcript-retention map (three keys).  The server never
/// writes it, so it is the trace of a finished onboarding from before T37.
const _appTrace = <String, bool>{
  AgentRegistry.siuYanId: true,
  AgentRegistry.ahJanAhBakId: true,
  AgentRegistry.tungTungId: true,
};

UserProfile _p({
  bool consent = false,
  bool intake = false,
  AgentGenderVariant? variant,
  String? cohort,
  String? mode,
  ArmAssignment? arm,
  DateTime? completed,
  Map<String, bool> retention = const {},
}) =>
    UserProfile(
      uid: 'u',
      email: 'e',
      displayName: 'd',
      consent: ConsentFlags(
          functionalData: consent, transcriptRetentionByAgent: retention),
      hasCompletedIntake: intake,
      ahJanAhBakVariant: variant,
      cohort: cohort,
      armAssignmentMode: mode,
      arm: arm,
      onboardingCompletedAt: completed,
    );

/// What enrollParticipant writes (functions/randomization.js): arm, cohort
/// and the pairing the researcher entered.  Everything else stays.
UserProfile _registered(UserProfile p, AgentGenderVariant pairing) =>
    p.copyWith(
        arm: ArmAssignment.b, cohort: 'phase_b', ahJanAhBakVariant: pairing);

/// The App as the AuthGate composes it below StaffGate: the enrolment
/// gate (profile read at open) → ConsentGate → main shell ('home').
class _App extends StatelessWidget {
  final AppSettings settings;
  final AnalyticsService analytics;
  final bool gateOn;
  final bool fixOn;
  const _App({
    required this.settings,
    required this.analytics,
    required this.gateOn,
    required this.fixOn,
  });

  @override
  Widget build(BuildContext context) => AnalyticsScope(
        analytics: analytics,
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
                gateOn: gateOn,
                child: ConsentGate(
                  onboardingFixOn: fixOn,
                  child: const Text('home'),
                ),
              ),
            ),
          ),
        ),
      );
}

final _home = find.text('home');
final _onboarding = find.byType(AgentOnboardingPage);
final _s8 = find.text(enrollmentWaitingS8);

/// "Close and reopen the App": the profile is read again.
Future<AnalyticsService> _open(
  WidgetTester tester,
  AppSettings settings, {
  required bool gateOn,
  required bool fixOn,
  AnalyticsService? analytics,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final a = analytics ?? AnalyticsService(firebaseReady: false);
  await tester.pumpWidget(
      _App(settings: settings, analytics: a, gateOn: gateOn, fixOn: fixOn));
  await tester.pumpAndSettle();
  return a;
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('下一步'));
  await tester.pumpAndSettle();
}

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

/// Welcome → 小欣 → the pairing slide.
Future<void> _toPairingSlide(WidgetTester tester) async {
  expect(find.text('介紹三個夥伴'), findsOneWidget);
  await _next(tester);
  await _next(tester);
  expect(find.text('揀邊個陪你做人生回顧'), findsOneWidget);
}

/// Pairing slide → 通通 → (S5) → 完成.
Future<void> _finishFromPairingSlide(WidgetTester tester) async {
  await _next(tester);
  expect(find.text('你鍾意啲咩？'), findsOneWidget, reason: '通通 interests');
  if (UsageCopy.current.onboardingUsageAdviceEnabled) {
    await _next(tester);
    expect(find.byKey(const Key('onboarding_usage_advice')), findsOneWidget,
        reason: 'S5 when its switch is on');
  }
  await tester.tap(find.text('完成'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
    UsageCopy.current = const UsageCopy();
  });

  test('switch: default off; only a literal true turns it on', () {
    expect(const RemoteFeatureFlags().onboardingAfterEnrollmentFix, isFalse);
    expect(RemoteFeatureFlags.fromMap({}).onboardingAfterEnrollmentFix,
        isFalse);
    expect(
        RemoteFeatureFlags.fromMap({'onboardingAfterEnrollmentFix': 'true'})
            .onboardingAfterEnrollmentFix,
        isFalse);
    expect(
        RemoteFeatureFlags.fromMap({'onboardingAfterEnrollmentFix': true})
            .onboardingAfterEnrollmentFix,
        isTrue);
  });

  test('marker round-trip: written as ISO text, omitted while null', () {
    final at = DateTime.utc(2026, 10, 14, 3, 4, 5);
    final done = _p(completed: at);
    expect(done.toMap()['onboardingCompletedAt'], at.toIso8601String());
    expect(UserProfile.fromMap('u', done.toMap()).onboardingCompletedAt, at);
    expect(_p().toMap().containsKey('onboardingCompletedAt'), isFalse,
        reason: 'a stale merge-write must not erase the marker');
    expect(UserProfile.fromMap('u', {}).onboardingCompletedAt, isNull);
    expect(_p(completed: at).copyWith(displayName: 'x').onboardingCompletedAt, at,
        reason: 'copyWith keeps the marker');
  });

  group('who still has to do 「介紹三個夥伴」 (ConsentGate.needsAgentOnboarding)',
      () {
    bool needs(UserProfile p, {required bool fixOn}) =>
        ConsentGate.needsAgentOnboarding(p, fixOn: fixOn);
    final now = DateTime.now();

    test('switch off: exactly today\'s rule — run while no pairing', () {
      expect(needs(_p(), fixOn: false), isTrue);
      expect(needs(_p(cohort: 'phase_b'), fixOn: false), isTrue);
      final paired = _p(variant: AgentGenderVariant.masculine);
      expect(needs(paired, fixOn: false), isFalse);
      expect(needs(_registered(_p(), AgentGenderVariant.masculine),
          fixOn: false), isFalse, reason: 'the bug: registration skips it');
      expect(needs(paired.copyWith(onboardingCompletedAt: now), fixOn: false), isFalse);
    });

    test('switch on: the marker decides', () {
      expect(needs(_p(completed: now), fixOn: true), isFalse);
      expect(needs(_registered(_p(completed: now), AgentGenderVariant.feminine),
          fixOn: true), isFalse, reason: 'onboarded, then registered');
      expect(needs(_p(variant: AgentGenderVariant.feminine, completed: now),
          fixOn: true), isFalse);
    });

    test('switch on, no marker: nothing yet → run', () {
      expect(needs(_p(), fixOn: true), isTrue);
      expect(needs(_p(consent: true, intake: true), fixOn: true), isTrue);
    });

    test('switch on, no marker, pairing from registration → run', () {
      for (final reg in [
        (cohort: 'phase_b', mode: 'randomise'),
        (cohort: 'pilot', mode: 'pilot_designated'),
        (cohort: 'phase_b', mode: null), // cohort alone
        (cohort: null, mode: 'randomise'), // registered before T21
        (cohort: null, mode: 'pilot_designated'),
      ]) {
        final p = _p(variant: AgentGenderVariant.masculine,
            cohort: reg.cohort, mode: reg.mode, arm: ArmAssignment.a);
        expect(ConsentGate.registeredByResearcher(p), isTrue, reason: '$reg');
        expect(needs(p, fixOn: true), isTrue,
            reason: 'registration wrote the pairing: $reg');
      }
    });

    test('switch on, no marker, registered, App trace → done '
        '(onboarding-first order before T37)', () {
      for (final reg in [
        (cohort: 'phase_b', mode: 'randomise'),
        (cohort: 'pilot', mode: 'pilot_designated'),
        (cohort: null, mode: 'randomise'),
      ]) {
        final p = _p(variant: AgentGenderVariant.masculine,
            cohort: reg.cohort, mode: reg.mode, arm: ArmAssignment.a,
            retention: _appTrace);
        expect(needs(p, fixOn: true), isFalse, reason: '$reg');
      }
      // The trace alone, without a pairing, is not a finished onboarding.
      expect(needs(_p(cohort: 'phase_b', retention: _appTrace), fixOn: true),
          isTrue);
    });

    test('switch on, no marker, pairing but not registered → done '
        '(finished onboarding before T37)', () {
      expect(needs(_p(variant: AgentGenderVariant.feminine), fixOn: true),
          isFalse);
      // An arm alone (force_a) is not a registration (T21 isEnrolled).
      expect(needs(_p(variant: AgentGenderVariant.feminine,
          arm: ArmAssignment.a), fixOn: true), isFalse);
      expect(needs(_p(variant: AgentGenderVariant.feminine, cohort: 'phase_a'),
          fixOn: true), isFalse);
    });
  });

  group('register-first (enrolment gate on)', () {
    testWidgets('fix on: S8 → registered → consent → intake → full onboarding '
        'with the registered pairing pre-selected → 完成 → home',
        (tester) async {
      // 1. Signed up, not registered: only S8.
      final settings = AppSettings(profile: _p());
      await _open(tester, settings, gateOn: true, fixOn: true);
      expect(_s8, findsOneWidget);
      expect(find.byType(ConsentPage), findsNothing);
      expect(_onboarding, findsNothing);
      expect(_home, findsNothing);

      // 2. The researcher registers (阿伯); the participant reopens the App.
      settings.profile = _registered(_p(), AgentGenderVariant.masculine);
      final analytics =
          await _open(tester, settings, gateOn: true, fixOn: true);
      expect(_s8, findsNothing);
      expect(find.byType(ConsentPage), findsOneWidget, reason: '開始之前 first');
      expect(_onboarding, findsNothing);

      // 3. 繼續 on the consent page → the intake questionnaire.
      await tester.tap(find.text('繼續'));
      await tester.pumpAndSettle();
      expect(find.byType(IntakeFlowPage), findsOneWidget);
      expect(settings.profile!.consent.functionalData, isTrue);

      // 4. Intake done (its own pages are unchanged) → the onboarding slides.
      settings.profile = settings.profile!.copyWith(hasCompletedIntake: true);
      await tester.pumpAndSettle();
      expect(_onboarding, findsOneWidget, reason: 'not skipped any more');
      expect(_home, findsNothing);

      // 5. The pairing slide shows the registered choice: 阿伯 selected,
      //    下一步 enabled without tapping anything.
      await _toPairingSlide(tester);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(
          find.descendant(
              of: find.ancestor(
                  of: find.text('阿伯（同輩男性）'),
                  matching: find.byType(InkWell)),
              matching: find.byIcon(Icons.radio_button_checked)),
          findsOneWidget);
      expect(_nextEnabled(tester), isTrue);

      // 6. 通通 → 完成 → home; the marker is set, the pairing unchanged,
      //    nothing logged.
      await _finishFromPairingSlide(tester);
      expect(_home, findsOneWidget);
      expect(_onboarding, findsNothing);
      final done = settings.profile!;
      expect(done.onboardingCompletedAt, isNotNull);
      expect(done.ahJanAhBakVariant, AgentGenderVariant.masculine);
      expect(done.cohort, 'phase_b', reason: 'server fields untouched');
      expect(analytics.bufferedEvents.where((e) =>
          e['name'] == 'ah_jan_ah_bak_changed'), isEmpty);

      // 7. Reopen: straight to home.
      await _open(tester, settings, gateOn: true, fixOn: true);
      expect(_home, findsOneWidget);
      expect(_onboarding, findsNothing);
    });

    testWidgets('fix on, S5 switch on: the S5 screen is part of the flow',
        (tester) async {
      UsageCopy.current = const UsageCopy({}, true);
      final settings = AppSettings(
          profile: _registered(
              _p(consent: true, intake: true), AgentGenderVariant.feminine));
      await _open(tester, settings, gateOn: true, fixOn: true);
      expect(_onboarding, findsOneWidget);
      await _toPairingSlide(tester);
      expect(_nextEnabled(tester), isTrue, reason: '阿珍 pre-selected');
      await _finishFromPairingSlide(tester); // asserts the S5 screen
      expect(_home, findsOneWidget);
      expect(settings.profile!.onboardingCompletedAt, isNotNull);
    });

    testWidgets('fix on: the participant changes the pairing → logged '
        '{from, to, at, where}; the profile takes the new value',
        (tester) async {
      final settings = AppSettings(
          profile: _registered(
              _p(consent: true, intake: true), AgentGenderVariant.masculine));
      final analytics =
          await _open(tester, settings, gateOn: true, fixOn: true);
      await _toPairingSlide(tester);
      await tester.tap(find.text('阿珍（同輩女性）'));
      await tester.pumpAndSettle();
      await _finishFromPairingSlide(tester);
      expect(_home, findsOneWidget);
      expect(settings.profile!.ahJanAhBakVariant, AgentGenderVariant.feminine);

      final changes = analytics.bufferedEvents
          .where((e) => e['name'] == 'ah_jan_ah_bak_changed')
          .toList();
      expect(changes, hasLength(1));
      final params = changes.single['params'] as Map<String, dynamic>;
      expect(params['from'], 'masculine');
      expect(params['to'], 'feminine');
      expect(params['where'], 'onboarding');
      expect(DateTime.tryParse(params['at'] as String), isNotNull);
    });

    testWidgets('fix on: changing and changing back is not a change',
        (tester) async {
      final settings = AppSettings(
          profile: _registered(
              _p(consent: true, intake: true), AgentGenderVariant.masculine));
      final analytics =
          await _open(tester, settings, gateOn: true, fixOn: true);
      await _toPairingSlide(tester);
      await tester.tap(find.text('阿珍（同輩女性）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('阿伯（同輩男性）'));
      await tester.pumpAndSettle();
      await _finishFromPairingSlide(tester);
      expect(_home, findsOneWidget);
      expect(settings.profile!.ahJanAhBakVariant, AgentGenderVariant.masculine);
      expect(analytics.bufferedEvents.where((e) =>
          e['name'] == 'ah_jan_ah_bak_changed'), isEmpty);
    });

    testWidgets('fix off (default): exactly today — the slides are skipped '
        'after registration', (tester) async {
      final settings = AppSettings(profile: _p());
      await _open(tester, settings, gateOn: true, fixOn: false);
      expect(_s8, findsOneWidget);

      settings.profile = _registered(
          _p(consent: true, intake: true), AgentGenderVariant.masculine);
      await _open(tester, settings, gateOn: true, fixOn: false);
      expect(_onboarding, findsNothing);
      expect(_home, findsOneWidget);
      expect(settings.profile!.onboardingCompletedAt, isNull);
    });
  });

  group('onboarding-first (today\'s order, enrolment gate off)', () {
    for (final fixOn in [false, true]) {
      testWidgets('fix ${fixOn ? 'on' : 'off'}: consent → intake → slides '
          '(nothing pre-selected) → 完成 → home; registration afterwards '
          'does not bring the slides back', (tester) async {
        final settings = AppSettings(profile: _p());
        final analytics =
            await _open(tester, settings, gateOn: false, fixOn: fixOn);
        expect(_s8, findsNothing);
        expect(find.byType(ConsentPage), findsOneWidget);

        settings.profile = _p(consent: true, intake: true);
        await tester.pumpAndSettle();
        expect(_onboarding, findsOneWidget);

        await _toPairingSlide(tester);
        expect(find.byIcon(Icons.radio_button_checked), findsNothing);
        expect(_nextEnabled(tester), isFalse, reason: 'must choose first');
        await tester.tap(find.text('阿珍（同輩女性）'));
        await tester.pumpAndSettle();
        await _finishFromPairingSlide(tester);
        expect(_home, findsOneWidget);
        final done = settings.profile!;
        expect(done.ahJanAhBakVariant, AgentGenderVariant.feminine);
        expect(done.onboardingCompletedAt, isNotNull,
            reason: 'the marker is written whether or not the switch is on');
        expect(analytics.bufferedEvents.where((e) =>
            e['name'] == 'ah_jan_ah_bak_changed'), isEmpty);

        // The researcher registers afterwards (today's W0 order); the
        // registration value overwrites the pairing.  Reopen: home.
        settings.profile = _registered(done, AgentGenderVariant.masculine);
        await _open(tester, settings, gateOn: false, fixOn: fixOn);
        expect(_home, findsOneWidget);
        expect(_onboarding, findsNothing);
        // And with the gate turned on later: still home.
        await _open(tester, settings, gateOn: true, fixOn: fixOn);
        expect(_home, findsOneWidget);
      });
    }

    testWidgets('fix on: registered after finishing onboarding before T37 '
        '(pairing, no marker, App trace) goes straight to home',
        (tester) async {
      final settings = AppSettings(
          profile: _registered(
              _p(consent: true, intake: true, retention: _appTrace),
              AgentGenderVariant.masculine));
      await _open(tester, settings, gateOn: true, fixOn: true);
      expect(_home, findsOneWidget);
      expect(_onboarding, findsNothing);
    });

    testWidgets('fix on: an account that finished onboarding before T37 '
        '(pairing, no marker, not registered) goes straight to home',
        (tester) async {
      final settings = AppSettings(
          profile: _p(consent: true, intake: true,
              variant: AgentGenderVariant.feminine));
      await _open(tester, settings, gateOn: false, fixOn: true);
      expect(_home, findsOneWidget);
      expect(_onboarding, findsNothing);
    });
  });

  testWidgets('ConsentGate reads the switch from RemoteFeatureFlags when no '
      'test value is given', (tester) async {
    final registered = _registered(
        _p(consent: true, intake: true), AgentGenderVariant.masculine);
    Widget app(AppSettings s) => AuthServiceScope(
          authService: AuthService(available: false),
          child: AppSettingsScope(
            settings: s,
            child: MaterialApp(
              locale: const Locale('zh'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: const ConsentGate(child: Text('home')),
            ),
          ),
        );
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    RemoteFeatureFlags.current = const RemoteFeatureFlags();
    await tester.pumpWidget(app(AppSettings(profile: registered)));
    await tester.pumpAndSettle();
    expect(_home, findsOneWidget, reason: 'off: skipped, as today');

    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(onboardingAfterEnrollmentFix: true);
    await tester.pumpWidget(app(AppSettings(profile: registered)));
    await tester.pumpAndSettle();
    expect(_onboarding, findsOneWidget, reason: 'on: the slides run');
  });
}
