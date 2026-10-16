// T47 — the researcher records the intake (dev-tasks-1015-intake):
// the 入組資料 section on the registration page, the consent gate skipping
// the elder's questionnaire while `researcherIntakeEnabled` is on, and the
// short five-question page shown while it is off.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/consent/presentation/consent_gate.dart';
import 'package:app_demo/features/enrollment/data/enrollment_service.dart';
import 'package:app_demo/features/enrollment/presentation/enrollment_page.dart';
import 'package:app_demo/features/enrollment/presentation/intake_section.dart';
import 'package:app_demo/features/onboarding/data/intake_repository.dart';
import 'package:app_demo/features/onboarding/data/intake_response.dart';
import 'package:app_demo/features/onboarding/presentation/pages/intake_short_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEnrol implements EnrollmentBackend {
  @override
  Future<EnrollmentResult> submit(EnrollmentInput input,
          {required bool dryRun}) async =>
      EnrollmentResult(
          alreadyEnrolled: false, sameInput: true, arm: null,
          researchId: 'PILOT-01', stratum: '',
          companionVariant: 'feminine');
}

class _FakeIntake implements IntakeBackend {
  final calls = <({IntakeAnswers answers, String? email, String? rid})>[];
  String? failWith;
  @override
  Future<IntakeRecordResult> record(IntakeAnswers answers,
      {String? email, String? researchId}) async {
    calls.add((answers: answers, email: email, rid: researchId));
    if (failWith != null) throw IntakeError(failWith!);
    return IntakeRecordResult(
        researchId: 'PILOT-01', recordedAt: '2026-10-15T08:00:00Z',
        people: answers.importantPeople.length);
  }
}

class _MemRepo extends IntakeRepository {
  IntakeResponse? saved;
  @override
  Future<void> save(String uid, IntakeResponse response) async {
    saved = response;
  }
}

UserProfile _p({bool intake = false, AgentGenderVariant? variant}) =>
    UserProfile(
      uid: 'u',
      email: 'e',
      displayName: 'd',
      consent: const ConsentFlags(functionalData: true),
      hasCompletedIntake: intake,
      ahJanAhBakVariant: variant,
      cohort: 'pilot',
      arm: ArmAssignment.b,
    );

Widget _gate(AppSettings settings, {required bool researcherIntakeOn}) =>
    AnalyticsScope(
      analytics: AnalyticsService(firebaseReady: false),
      child: AuthServiceScope(
        authService: AuthService(available: false),
        child: AppSettingsScope(
          settings: settings,
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: ConsentGate(
              onboardingFixOn: false,
              researcherIntakeOn: researcherIntakeOn,
              child: const Text('home'),
            ),
          ),
        ),
      ),
    );

Future<void> _scrollTo(WidgetTester tester, Finder f) => tester
    .scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);

void main() {
  group('registration page: 入組資料 section (T47 §2.1)', () {
    testWidgets('records the five answers through the backend', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final intake = _FakeIntake();
      await tester.pumpWidget(MaterialApp(
          home: EnrollmentPage(
              backend: _FakeEnrol(),
              intakeBackend: intake,
              today: () => DateTime(2026, 10, 15))));
      // The researcher no longer picks the pairing.
      expect(find.byKey(const Key('enroll_variant_feminine')), findsNothing);
      expect(find.byKey(const Key('enroll_variant_note')), findsOneWidget);
      await _scrollTo(tester, find.byKey(const Key('intake_toggle')));
      await tester.tap(find.byKey(const Key('intake_toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('intake_who')), 'PILOT-01');
      await tester.tap(find.byKey(const Key('intake_goal_companionship')));
      await tester.tap(
          find.byKey(const Key('intake_goal_share_memories')));
      await tester.tap(find.byKey(const Key('intake_goal_learning')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('intake_person_name_0')), '阿女');
      await tester.enterText(
          find.byKey(const Key('intake_person_rel_0')), '女');
      await _scrollTo(tester, find.byKey(const Key('intake_person_share_0')));
      await tester.tap(find.byKey(const Key('intake_person_share_0')));
      await tester.pump();
      await _scrollTo(tester, find.byKey(const Key('intake_interest_yum_cha')));
      await tester.tap(find.byKey(const Key('intake_interest_yum_cha')));
      await tester.pump();
      await _scrollTo(tester, find.byKey(const Key('intake_avoid')));
      await tester.enterText(
          find.byKey(const Key('intake_avoid')), '唔好提我先生');
      await _scrollTo(tester, find.byKey(const Key('intake_input_voice')));
      await tester.tap(find.byKey(const Key('intake_input_voice')));
      // 10/16: the researcher's own note, not a question.
      await _scrollTo(tester, find.byKey(const Key('intake_note')));
      await tester.enterText(
          find.byKey(const Key('intake_note')), '老人家健談，咩都想講');
      await tester.pump();
      await _scrollTo(tester, find.byKey(const Key('intake_submit')));
      await tester.tap(find.byKey(const Key('intake_submit')));
      await tester.pumpAndSettle();
      expect(intake.calls.length, 1);
      final c = intake.calls.single;
      expect(c.rid, 'PILOT-01');
      expect(c.email, isNull);
      // The third goal was refused by the cap of two.
      expect(c.answers.mainGoals, ['companionship', 'share_memories']);
      expect(c.answers.importantPeople.single.name, '阿女');
      expect(c.answers.importantPeople.single.relationship, '女');
      expect(c.answers.importantPeople.single.share, isTrue); // T48
      expect(c.answers.interests, ['yum_cha']);
      expect(c.answers.avoidTopics, '唔好提我先生');
      expect(c.answers.inputMode, IntakeOptions.inputVoice);
      expect(c.answers.researcherNote, '老人家健談，咩都想講');
      expect(c.answers.toMap()['researcherNote'], '老人家健談，咩都想講');
      expect(find.byKey(const Key('intake_done')), findsOneWidget);
      expect(find.textContaining('PILOT-01'), findsWidgets);
    });

    testWidgets('an email goes as email; a refusal is shown in words',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final intake = _FakeIntake()..failWith = 'not_enrolled';
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListView(children: [IntakeSection(backend: intake)]))));
      await tester.tap(find.byKey(const Key('intake_toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('intake_who')), 'e@x.org');
      await tester.pump();
      await _scrollTo(tester, find.byKey(const Key('intake_submit')));
      await tester.tap(find.byKey(const Key('intake_submit')));
      await tester.pumpAndSettle();
      expect(intake.calls.single.email, 'e@x.org');
      expect(intake.calls.single.rid, isNull);
      expect(find.byKey(const Key('intake_error')), findsOneWidget);
      expect(find.text(intakeErrorText('not_enrolled')), findsOneWidget);
    });
  });

  group('consent gate (T47 §2.2 / §2.3)', () {
    testWidgets('switch on: no intake page even before the researcher '
        'recorded; main shell straight away', (tester) async {
      final settings = AppSettings(
          profile: _p(variant: AgentGenderVariant.feminine));
      await tester.pumpWidget(_gate(settings, researcherIntakeOn: true));
      await tester.pumpAndSettle();
      expect(find.byType(IntakeShortPage), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('switch off: the short five-question page, 完成 marks the '
        'intake done and saves interests / contacts', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = AppSettings(
          profile: _p(variant: AgentGenderVariant.feminine));
      final repo = _MemRepo();
      await tester.pumpWidget(AnalyticsScope(
        analytics: AnalyticsService(firebaseReady: false),
        child: AuthServiceScope(
          authService: AuthService(available: false),
          child: AppSettingsScope(
            settings: settings,
            child: MaterialApp(
              locale: const Locale('zh'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: ConsentGate(
                onboardingFixOn: false,
                researcherIntakeOn: false,
                child: const Text('home'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(IntakeShortPage), findsOneWidget);
      expect(find.text(IntakeShortCopy.title), findsOneWidget);
      expect(find.text(IntakeShortCopy.q5), findsOneWidget, reason: '第 1 題');
      // Fill it in through a page of our own with the memory repository.
      await tester.pumpWidget(AnalyticsScope(
        analytics: AnalyticsService(firebaseReady: false),
        child: AuthServiceScope(
          authService: AuthService(available: false),
          child: AppSettingsScope(
            settings: settings,
            child: MaterialApp(
              home: IntakeShortPage(onComplete: () {}, repository: repo),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // 10/16: one question per screen, concrete first, free text last.
      Future<void> next() async {
        await tester.tap(find.byKey(const Key('intake_short_next')));
        await tester.pumpAndSettle();
      }

      // 1 打字定講
      expect(find.text('第 1 題，共 5 題'), findsOneWidget);
      expect(find.text(IntakeShortCopy.q5), findsOneWidget);
      expect(find.text(IntakeShortCopy.q4), findsNothing);
      expect(find.byKey(const Key('intake_short_back')), findsNothing);
      await tester.tap(find.byKey(const Key('intake_short_input_both')));
      await next();
      // 2 鍾意做乜
      expect(find.text('第 2 題，共 5 題'), findsOneWidget);
      expect(find.text(IntakeShortCopy.q3), findsOneWidget);
      await _scrollTo(
          tester, find.byKey(const Key('intake_short_interest_mahjong')));
      await tester.tap(find.byKey(const Key('intake_short_interest_mahjong')));
      await next();
      // 3 重要嘅人
      expect(find.text(IntakeShortCopy.q2), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('intake_short_person_name_0')), '黃太');
      await tester.enterText(
          find.byKey(const Key('intake_short_person_rel_0')), '鄰居');
      await next();
      // 4 最想 app 幫到乜 — 上一題 keeps the answers.
      expect(find.text(IntakeShortCopy.q1), findsOneWidget);
      await tester.tap(find.byKey(const Key('intake_short_back')));
      await tester.pumpAndSettle();
      expect(find.text(IntakeShortCopy.q2), findsOneWidget);
      expect(find.text('黃太'), findsOneWidget);
      await next();
      await tester.tap(
          find.byKey(const Key('intake_short_goal_share_memories')));
      await next();
      // 5 唔想提起 (free text, last) → 完成
      expect(find.text('第 5 題，共 5 題'), findsOneWidget);
      expect(find.text(IntakeShortCopy.q4), findsOneWidget);
      expect(find.byKey(const Key('intake_short_next')), findsNothing);
      await tester.tap(find.byKey(const Key('intake_short_done')));
      await tester.pumpAndSettle();
      final p = settings.profile!;
      expect(p.hasCompletedIntake, isTrue);
      expect(p.interests, ['mahjong']);
      expect(p.closeContacts.single.name, '黃太');
      expect(p.closeContacts.single.relation, '鄰居');
      expect(p.closeContacts.single.share, isTrue); // T48: elder typed it
      expect(p.inputMode, IntakeOptions.inputBoth);
      expect(repo.saved!.mainGoals, ['share_memories']);
      expect(repo.saved!.allCompleted, isTrue);
      expect(repo.saved!.importantPeople!.single.name, '黃太');
    });
  });
}
