// T17 (SPEC:C22, decision 0026) — ADA and day-7 open questions, Phase A
// only.  Runs in the default build and again with PHASE_B=true
// (tool/ci_flutter_tests.sh): the "real build flags" group checks the
// build it runs in.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/config/phase_a_schedule_config.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/safety/safety_check.dart';
import 'package:app_demo/core/safety/safety_classifier.dart';
import 'package:app_demo/core/safety/safety_event_writer.dart';
import 'package:app_demo/features/ada/data/ada_gate.dart';
import 'package:app_demo/features/ada/data/ada_items.dart';
import 'package:app_demo/features/ada/data/survey_draft_store.dart';
import 'package:app_demo/features/ada/presentation/ada_page.dart';
import 'package:app_demo/features/ada/presentation/day7_open_page.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingWriter extends SafetyEventWriter {
  _RecordingWriter() : super(available: false);
  final List<Map<String, Object?>> rows = [];

  @override
  Future<void> maybeWrite({
    String? uid,
    required SafetySource source,
    required DistressMatch match,
    required String inputText,
    String? inputPoint,
    String? turnId,
    String? agentId,
    String? sessionId,
    String? detector,
    ClassifierVerdict? classifier,
  }) async {
    if (!match.isEscalation) return;
    rows.add({'uid': uid, 'inputPoint': inputPoint, 'level': match.level});
  }
}

const _uid = 'synthetic-ada-001';

Widget _harness(Widget page, {SafetyService? safety}) {
  final llm = LlmGateway();
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  return AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh')),
    child: AuthServiceScope(
      authService: AuthService(available: false),
      child: AnalyticsScope(
        analytics: AnalyticsService(firebaseReady: false),
        child: CoreServicesScope(
          llm: llm,
          memory: memory,
          distress: const DistressDetector(),
          distressState: state,
          distressRouter: DistressRouter(state: state),
          crossModuleMemory: CrossModuleMemoryService(
            memory: memory,
            firestoreAvailable: false,
          ),
          agentContext: agentContext,
          sharedContext: sharedContext,
          personaResolver: PersonaResolver(
            agentContext: agentContext,
            sharedContext: sharedContext,
          ),
          referralRouting: ReferralRoutingService(sharedContext: sharedContext),
          handoffExecutor: HandoffExecutor(sharedContext: sharedContext),
          agentGreeting: AgentGreetingService(llm),
          safety: safety,
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: page,
          ),
        ),
      ),
    ),
  );
}

const _short =
    AdaTimepoint(id: 'visit1', form: AdaForm.short, dayFrom: 1, dayTo: 1);
const _full = AdaTimepoint(id: 'day7', form: AdaForm.full, dayFrom: 7, dayTo: 9);

Future<void> _pumpPage(WidgetTester tester, Widget page,
    {SafetyService? safety}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness(page, safety: safety));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) => _tapKey(tester, 'survey_next');

Future<void> _rate(WidgetTester tester, String trait, String agent, int v) async {
  final f = find.descendant(
    of: find.byKey(ValueKey('trait_${trait}_$agent')),
    matching: find.text('$v'),
  );
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Answers A and every B screen (all agents: usage 2, trait 4).
Future<void> _answerAB(WidgetTester tester) async {
  await _next(tester); // intro → A
  for (final a in AdaAgents.all) {
    await _tapKey(tester, 'usage_${a}_2');
  }
  await _next(tester);
  for (final t in AdaTraits.all) {
    for (final a in AdaAgents.all) {
      await _rate(tester, t, a, 4);
    }
    await _next(tester);
  }
}

Map<String, dynamic> _doc(InMemorySurveyDraftStore s, String coll, String id) =>
    s.docs[InMemorySurveyDraftStore.key(_uid, coll, id)]!;

void main() {
  group('PhaseAScheduleConfig', () {
    test('defaults: everything off, visit1 short + day7 full', () {
      const c = PhaseAScheduleConfig();
      expect(c.adaEnabled, isFalse);
      expect(c.day7OpenEndedEnabled, isFalse);
      expect(c.adaAllowSkip, isTrue);
      expect(c.adaTimepointForDay(1)!.id, 'visit1');
      expect(c.adaTimepointForDay(1)!.form, AdaForm.short);
      expect(c.adaTimepointForDay(7)!.form, AdaForm.full);
      expect(c.adaTimepointForDay(9)!.id, 'day7');
      expect(c.adaTimepointForDay(2), isNull);
      expect(c.adaTimepointForDay(10), isNull);
    });

    test('only literal true turns a switch on; timepoints configurable', () {
      final c = PhaseAScheduleConfig.fromMap({
        'adaEnabled': 'true',
        'day7OpenEndedEnabled': 1,
        'adaAllowSkip': false,
        'adaTimepoints': [
          {'id': 'v1', 'form': 'full', 'dayFrom': 1, 'dayTo': 2,
            'recallWindowZh': '喺過去一個星期'},
          {'id': 'bad/id', 'form': 'short', 'dayFrom': 5, 'dayTo': 5},
          {'form': 'short', 'dayFrom': 6, 'dayTo': 6},
        ],
      });
      expect(c.adaEnabled, isFalse);
      expect(c.day7OpenEndedEnabled, isFalse);
      expect(c.adaAllowSkip, isFalse);
      expect(c.adaTimepoints, hasLength(1));
      expect(c.adaTimepointForDay(2)!.form, AdaForm.full);
      expect(c.adaTimepointForDay(2)!.recallWindowZh, '喺過去一個星期');
      expect(PhaseAScheduleConfig.fromMap({'adaEnabled': true}).adaEnabled,
          isTrue);
    });
  });

  group('AdaGate', () {
    const on = PhaseAScheduleConfig(adaEnabled: true, day7OpenEndedEnabled: true);
    const off = PhaseAScheduleConfig();

    test('Phase B: ADA and day-7 never, whatever the config says', () {
      expect(AdaGate.adaVisible(phaseB: true, config: on), isFalse);
      expect(AdaGate.day7OpenVisible(phaseB: true, config: on), isFalse);
    });

    test('Phase B: old agent_diff off by default, flag restores it', () {
      expect(
          AdaGate.legacyAgentDiffVisible(
              phaseB: true, legacyInPhaseB: false, config: off),
          isFalse);
      expect(
          AdaGate.legacyAgentDiffVisible(
              phaseB: true, legacyInPhaseB: true, config: on),
          isTrue);
    });

    test('Phase A: config switches; ADA on replaces the old page', () {
      expect(AdaGate.adaVisible(phaseB: false, config: off), isFalse);
      expect(AdaGate.adaVisible(phaseB: false, config: on), isTrue);
      expect(AdaGate.day7OpenVisible(phaseB: false, config: on), isTrue);
      expect(AdaGate.legacyAgentDiffVisible(phaseB: false, config: off),
          isTrue);
      expect(AdaGate.legacyAgentDiffVisible(phaseB: false, config: on),
          isFalse);
    });

    test('real build flags (${FeatureFlags.phaseB ? 'PHASE_B' : 'Phase A'})',
        () {
      if (FeatureFlags.phaseB) {
        expect(AdaGate.adaVisible(config: on), isFalse);
        expect(AdaGate.day7OpenVisible(config: on), isFalse);
        expect(AdaGate.legacyAgentDiffVisible(config: off),
            FeatureFlags.legacyAgentDiffInPhaseB);
        expect(FeatureFlags.legacyAgentDiffInPhaseB, isFalse,
            reason: 'default build of Phase B follows registry v2 C15');
      } else {
        expect(AdaGate.adaVisible(config: on), isTrue);
        expect(AdaGate.adaVisible(config: off), isFalse);
      }
    });
  });

  group('ADA page', () {
    testWidgets('short form (A+B+D): 7 screens, saved per screen, submitted',
        (tester) async {
      final store = InMemorySurveyDraftStore();
      await _pumpPage(
          tester,
          AdaPage(
            timepoint: _short,
            store: store,
            uid: _uid,
            variant: AgentGenderVariant.feminine,
            enrolmentDay: 1,
            voiceEnabled: false,
          ));
      expect(find.text('第 1 / 7 頁'), findsOneWidget);
      await _answerAB(tester);
      // D: no Part C screens in the short form.
      expect(find.text('第 7 / 7 頁'), findsOneWidget);
      expect(find.text(AdaFreeText.questionZh), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('long_text_field')), '小欣最關心我。');
      await _next(tester);
      expect(find.byKey(const ValueKey('survey_done')), findsOneWidget);

      final d = _doc(store, kAdaCollection, 'visit1');
      expect(d['formVersion'], 'short');
      expect(d['timepoint'], 'visit1');
      expect(d['studyPhase'], 'A');
      expect(d['uid'], _uid);
      expect(d['itemsVersion'], adaItemsVersion);
      expect(d['usage'], {'siu_yan': 2, 'ah_jan_ah_bak': 2, 'tung_tung': 2});
      expect((d['traits'] as Map)['warm'],
          {'siu_yan': 4, 'ah_jan_ah_bak': 4, 'tung_tung': 4});
      expect(d.containsKey('scenarios'), isFalse);
      expect(d['freeText'], '小欣最關心我。');
      expect(d['freeTextStatus'], 'answered');
      expect(d['freeTextInputMode'], 'typed');
      expect(d['status'], 'submitted');
      expect(d['startedAt'], isA<DateTime>());
      expect(d['submittedAt'], isA<DateTime>());
      expect(d['ahJanAhBakVariant'], 'feminine');
      // intro, A, 4 × B, submit = 7 saves.
      expect(store.saves, 7);
    });

    testWidgets('full form (A+B+C+D) with 阿伯: 12 screens, skip recorded',
        (tester) async {
      final store = InMemorySurveyDraftStore();
      await _pumpPage(
          tester,
          AdaPage(
            timepoint: _full,
            store: store,
            uid: _uid,
            variant: AgentGenderVariant.masculine,
            voiceEnabled: false,
          ));
      expect(find.text('第 1 / 12 頁'), findsOneWidget);
      await _next(tester);
      expect(find.text('阿伯'), findsOneWidget);
      expect(find.textContaining('阿珍'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('survey_back')));
      await tester.pumpAndSettle();
      await _answerAB(tester);
      // C: 5 scenario screens; 阿伯 offered, never 阿珍.
      for (final s in AdaScenarios.all) {
        expect(find.text('阿伯'), findsOneWidget);
        expect(find.textContaining('阿珍'), findsNothing);
        if (s == AdaScenarios.learnNew) {
          await _tapKey(tester, 'survey_skip');
        } else {
          await _tapKey(tester, 'scenario_${s}_ah_jan_ah_bak');
          await _next(tester);
        }
      }
      // D skipped too.
      await _tapKey(tester, 'survey_skip');
      expect(find.byKey(const ValueKey('survey_done')), findsOneWidget);

      final d = _doc(store, kAdaCollection, 'day7');
      expect(d['formVersion'], 'full');
      expect(d['ahJanAhBakVariant'], 'masculine');
      expect((d['scenarios'] as Map)['learn_new'], kSkipped);
      expect((d['scenarios'] as Map)['day_recap'], 'ah_jan_ah_bak');
      expect(d['freeText'], isNull);
      expect(d['freeTextStatus'], kSkipped);
      expect(d['status'], 'submitted');
    });

    testWidgets('incomplete screen: hint, no advance; skip marks the rest',
        (tester) async {
      final store = InMemorySurveyDraftStore();
      await _pumpPage(tester,
          AdaPage(timepoint: _short, store: store, uid: _uid, voiceEnabled: false));
      await _next(tester);
      await _tapKey(tester, 'usage_siu_yan_0');
      await _next(tester);
      expect(find.text('第 2 / 7 頁'), findsOneWidget);
      expect(find.textContaining('跳過'), findsWidgets);
      await _tapKey(tester, 'survey_skip');
      expect(find.text('第 3 / 7 頁'), findsOneWidget);
      final d = _doc(store, kAdaCollection, 'visit1');
      expect(d['usage'],
          {'siu_yan': 0, 'ah_jan_ah_bak': kSkipped, 'tung_tung': kSkipped});
      expect(d['status'], 'in_progress');
      expect(d['lastScreen'], 2);
      // Back keeps the answers.
      await tester.tap(find.byKey(const ValueKey('survey_back')));
      await tester.pumpAndSettle();
      expect(find.text('第 2 / 7 頁'), findsOneWidget);
      expect(find.text('已跳過'), findsNWidgets(2));
    });

    testWidgets('allowSkip off: no skip button', (tester) async {
      await _pumpPage(
          tester,
          AdaPage(
              timepoint: _short,
              allowSkip: false,
              store: InMemorySurveyDraftStore(),
              uid: _uid,
              voiceEnabled: false));
      await _next(tester);
      expect(find.byKey(const ValueKey('survey_skip')), findsNothing);
    });

    testWidgets('a draft resumes where it was left', (tester) async {
      final store = InMemorySurveyDraftStore();
      store.docs[InMemorySurveyDraftStore.key(_uid, kAdaCollection, 'visit1')] =
          {
        'status': 'in_progress',
        'lastScreen': 2,
        'usage': {'siu_yan': 3, 'ah_jan_ah_bak': 1, 'tung_tung': 0},
        'startedAt': DateTime(2026, 10, 7),
      };
      await _pumpPage(tester,
          AdaPage(timepoint: _short, store: store, uid: _uid, voiceEnabled: false));
      expect(find.text('第 3 / 7 頁'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('survey_back')));
      await tester.pumpAndSettle();
      final d = _doc(store, kAdaCollection, 'visit1');
      expect(d['usage'], {'siu_yan': 3, 'ah_jan_ah_bak': 1, 'tung_tung': 0});
      expect(d['startedAt'], DateTime(2026, 10, 7), reason: 'not overwritten');
    });

    testWidgets('voice off: no mic; voice on: mic row shown', (tester) async {
      for (final voice in [false, true]) {
        await _pumpPage(
            tester,
            AdaPage(
                key: ValueKey(voice),
                timepoint: _short,
                store: InMemorySurveyDraftStore(),
                uid: _uid,
                voiceEnabled: voice));
        await _next(tester);
        await _tapKey(tester, 'survey_skip');
        for (var i = 0; i < AdaTraits.all.length; i++) {
          await _tapKey(tester, 'survey_skip');
        }
        expect(find.text(AdaFreeText.questionZh), findsOneWidget);
        expect(find.byKey(const ValueKey('long_text_mic_row')),
            voice ? findsOneWidget : findsNothing);
        expect(find.text('或者用講嘅'), voice ? findsOneWidget : findsNothing);
      }
    });

    testWidgets('Part D goes through SafetyService (ada_free_text)',
        (tester) async {
      final writer = _RecordingWriter();
      await _pumpPage(
          tester,
          AdaPage(
              timepoint: _short,
              store: InMemorySurveyDraftStore(),
              uid: _uid,
              voiceEnabled: false),
          safety: SafetyService(writer: writer));
      await _next(tester);
      for (var i = 0; i < 1 + AdaTraits.all.length; i++) {
        await _tapKey(tester, 'survey_skip');
      }
      await tester.enterText(
          find.byKey(const ValueKey('long_text_field')), '三個都冇用，我想死。');
      await tester.tap(find.byKey(const ValueKey('survey_next')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(writer.rows, hasLength(1));
      expect(writer.rows.single['inputPoint'], 'ada_free_text');
      expect(writer.rows.single['uid'], _uid);
    });
  });

  group('Day-7 open questions', () {
    testWidgets('3 screens, one skipped, per-screen save, frozen on submit',
        (tester) async {
      final store = InMemorySurveyDraftStore();
      await _pumpPage(tester,
          Day7OpenPage(store: store, uid: _uid, enrolmentDay: 7, voiceEnabled: false));
      expect(find.text(Day7OpenQuestions.questionsZh['q1']!), findsOneWidget);
      expect(find.byKey(const ValueKey('long_text_mic_row')), findsNothing);
      await tester.enterText(
          find.byKey(const ValueKey('long_text_field')), '習慣咗每朝同小欣講早晨。');
      await _next(tester);
      await _tapKey(tester, 'survey_skip');
      await tester.enterText(
          find.byKey(const ValueKey('long_text_field')), '想通通講多啲新聞。');
      await _next(tester);
      expect(find.byKey(const ValueKey('survey_done')), findsOneWidget);
      final d = _doc(store, kDay7OpenCollection, kDay7OpenDocId);
      final a = d['answers'] as Map;
      expect(a['q1'], containsPair('status', 'answered'));
      expect(a['q1'], containsPair('inputMode', 'typed'));
      expect(a['q2'], containsPair('status', kSkipped));
      expect(a['q3'], containsPair('text', '想通通講多啲新聞。'));
      expect(d['status'], 'submitted');
      expect(d['enrolmentDay'], 7);
      expect(store.saves, 3);
    });

    testWidgets('voice on shows the mic row', (tester) async {
      await _pumpPage(
          tester,
          Day7OpenPage(
              store: InMemorySurveyDraftStore(), uid: _uid, voiceEnabled: true));
      expect(find.byKey(const ValueKey('long_text_mic_row')), findsOneWidget);
    });
  });
}
