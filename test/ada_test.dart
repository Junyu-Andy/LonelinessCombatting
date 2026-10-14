// T17 / T17b (SPEC:C22, decisions 0026, 0030) — ADA v1.0
// (docs/spec/instruments/ada.md), the day-7 flow and the researcher page,
// Phase A only.  Runs in the default build and again with PHASE_B=true
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
import 'package:app_demo/features/ada/presentation/ada_staff_page.dart';
import 'package:app_demo/features/ada/presentation/day7_flow_page.dart';
import 'package:app_demo/features/ada/presentation/day7_open_page.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/core/scheduling/pending_prompts_service.dart';
import 'package:app_demo/features/today/presentation/widgets/pending_prompts_banner.dart';
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

/// Answers every B screen (all companions 4).
Future<void> _answerB(WidgetTester tester) async {
  for (final t in AdaTraits.all) {
    expect(find.text('「${AdaTraits.labelsZh[t]}」'), findsOneWidget);
    for (final a in AdaAgents.all) {
      await _rate(tester, t, a, 4);
    }
    await _next(tester);
  }
}

/// Answers A (usage 2 = 兩至三次) on the current screen.
Future<void> _answerA(WidgetTester tester) async {
  for (final a in AdaAgents.all) {
    await _tapKey(tester, 'usage_${a}_2');
  }
  await _next(tester);
}

Map<String, dynamic> _doc(InMemorySurveyDraftStore s, String coll, String id) =>
    s.docs[InMemorySurveyDraftStore.key(_uid, coll, id)]!;

class _FakeStaffSource implements AdaStaffSource {
  @override
  Future<List<AdaDay7Row>> day7Status() async => const [
        AdaDay7Row(uid: 'u1', label: '陳生 · u1', status: 'overdue',
            enrolmentDay: 10, partial: true, pushSentAt: '2026-10-07 19:00',
            reminderSentAt: '2026-10-08 19:00'),
        AdaDay7Row(uid: 'u2', label: 'u2', status: 'in_progress',
            enrolmentDay: 8, pushSentAt: '2026-10-08 10:00'),
        AdaDay7Row(uid: 'u3', label: 'u3', status: 'not_started',
            enrolmentDay: 6),
        AdaDay7Row(uid: 'u4', label: 'u4', status: 'completed',
            enrolmentDay: 9, channel: 'phone_by_staff'),
      ];
}

void main() {
  setUp(() => PhaseAScheduleConfig.current = const PhaseAScheduleConfig());

  group('PhaseAScheduleConfig (ada.md §2)', () {
    test('defaults: off; visit1 short (B+D) day 1; day7 full days 7–9', () {
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
      expect(AdaForm.short.hasUsage, isFalse);
      expect(AdaForm.short.hasScenarios, isFalse);
      expect(AdaForm.full.hasUsage, isTrue);
      expect(AdaForm.full.hasScenarios, isTrue);
      expect(c.day7Window, (7, 9));
      expect(c.adaHelpPhone, '');
      expect(c.adaDay7ReminderDefaultTime, '10:00');
      expect(c.day7FlowMinutes, isNull);
    });

    test('changing config moves timepoints and forms (§9.2)', () {
      final c = PhaseAScheduleConfig.fromMap({
        'adaEnabled': 'true',
        'day7OpenEndedEnabled': 1,
        'adaAllowSkip': false,
        'adaTimepoints': [
          {'id': 'visit1', 'form': 'full', 'dayFrom': 2, 'dayTo': 3},
          {'id': 'day7', 'form': 'short', 'dayFrom': 8, 'dayTo': 12},
          {'id': 'bad/id', 'form': 'short', 'dayFrom': 5, 'dayTo': 5},
          {'form': 'short', 'dayFrom': 6, 'dayTo': 6},
        ],
        'adaHelpPhone': ' 2345 6789 ',
        'adaDay7ReminderTimeOptions': ['09:00', '19:30', '23:00', '20:00'],
        'adaDay7ReminderDefaultTime': '07:00',
        'day7FlowMinutes': 15,
      });
      expect(c.adaEnabled, isFalse);
      expect(c.day7OpenEndedEnabled, isFalse);
      expect(c.adaAllowSkip, isFalse);
      expect(c.adaTimepoints, hasLength(2));
      expect(c.adaTimepointForDay(1), isNull);
      expect(c.adaTimepointForDay(2)!.form, AdaForm.full);
      expect(c.adaTimepointForDay(12)!.form, AdaForm.short);
      expect(c.day7Window, (8, 12));
      expect(c.day7OpenEndedOnDay(12), isTrue);
      expect(c.day7OpenEndedOnDay(13), isFalse);
      expect(c.adaHelpPhone, '2345 6789');
      expect(c.adaDay7ReminderTimeOptions, ['09:00', '20:00']);
      expect(c.adaDay7ReminderDefaultTime, '10:00');
      expect(c.day7FlowMinutes, 15);
      expect(PhaseAScheduleConfig.fromMap({'adaEnabled': true}).adaEnabled,
          isTrue);
    });
  });

  group('ADA v1.0 wording (ada.md §3, verbatim)', () {
    test('A, B, C, D text and options', () {
      expect(AdaUsage.questionZh, '過去 7 日，你大約同每位陪伴者傾過幾多次？');
      expect(AdaUsage.labelsZh, ['完全冇', '一次', '兩至三次', '四次或以上']);
      expect(AdaTraits.promptZh, '下面每一句，有幾似每位陪伴者？');
      expect([for (final t in AdaTraits.all) AdaTraits.labelsZh[t]],
          ['溫暖、關心人', '似自己同年紀嘅人', '好奇，鍾意問我嘢', '聽我講而唔評判我']);
      expect(AdaTraits.scaleZh, ['完全唔似', '少少似', '有啲似', '幾似', '好似']);
      expect(AdaScenarios.promptZh, '如果你想做下面呢啲嘢，你會首先搵邊位陪伴者？');
      expect([for (final s in AdaScenarios.all) AdaScenarios.labelsZh[s]],
          ['講下今日點過', '講下舊時嘅回憶、人生經歷', '學啲新嘢', '心情唔好嘅時候', '日常閒聊']);
      expect(AdaScenarios.anyZh, '邊個都得');
      expect(AdaFreeText.questionZh,
          '用你自己嘅說話，話我哋知三位陪伴者有咩唔同？有冇邊位你會想同佢傾多啲？點解？');
      expect(adaItemsVersion, 'ada-v1.0-20261007');
      expect(adaItemsVersion, isNot('ada-placeholder-20261007'));
    });
  });

  group('AdaGate', () {
    const on = PhaseAScheduleConfig(adaEnabled: true, day7OpenEndedEnabled: true);
    const off = PhaseAScheduleConfig();

    test('Phase B: ADA, day-7 flow never, whatever the config says (§9.4)',
        () {
      expect(AdaGate.adaVisible(phaseB: true, config: on), isFalse);
      expect(AdaGate.day7OpenVisible(phaseB: true, config: on), isFalse);
      expect(AdaGate.day7Parts(phaseB: true, config: on), isEmpty);
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

    test('Phase A: config switches; day-7 parts follow them', () {
      expect(AdaGate.adaVisible(phaseB: false, config: off), isFalse);
      expect(AdaGate.adaVisible(phaseB: false, config: on), isTrue);
      expect(AdaGate.day7Parts(phaseB: false, config: off), isEmpty);
      expect(AdaGate.day7Parts(phaseB: false, config: on),
          [Day7Part.ada, Day7Part.open]);
      expect(
          AdaGate.day7Parts(
              phaseB: false,
              config: const PhaseAScheduleConfig(day7OpenEndedEnabled: true)),
          [Day7Part.open]);
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
        expect(AdaGate.day7Parts(config: on), isEmpty);
        expect(AdaGate.legacyAgentDiffVisible(config: off),
            FeatureFlags.legacyAgentDiffInPhaseB);
        expect(FeatureFlags.legacyAgentDiffInPhaseB, isFalse,
            reason: 'default build of Phase B follows registry v2 C15');
      } else {
        expect(AdaGate.adaVisible(config: on), isTrue);
        expect(AdaGate.adaVisible(config: off), isFalse);
        expect(AdaGate.day7Parts(config: on), isNotEmpty);
        // T22: the old agent_diff follows adaEnabled in a Phase A build.
        expect(AdaGate.legacyAgentDiffVisible(config: on), isFalse);
        expect(AdaGate.legacyAgentDiffVisible(config: off), isTrue);
      }
    });
  });

  group('ADA page', () {
    testWidgets(
        'short form (B+D) at visit 1: 7 screens incl. reminder time, '
        'saved per screen, submitted (§9.1)', (tester) async {
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
      expect(find.byKey(const ValueKey('survey_help')), findsOneWidget);
      await _next(tester); // intro → B (no Part A in the short form)
      expect(find.text(AdaUsage.questionZh), findsNothing);
      expect(find.text(AdaTraits.promptZh), findsOneWidget);
      // Avatars beside every name; 阿珍 with her own picture.
      expect(find.byKey(const ValueKey('ada_avatar_asset_assets/agents/ah_jan_avatar.png')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('ada_avatar_asset_assets/agents/siu_yan_avatar.png')),
          findsOneWidget);
      expect(find.text('阿珍'), findsOneWidget);
      expect(find.textContaining('阿伯'), findsNothing);
      expect(find.byKey(const ValueKey('survey_help')), findsOneWidget);
      await _answerB(tester);
      expect(find.text('第 6 / 7 頁'), findsOneWidget);
      expect(find.text(AdaFreeText.questionZh), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('long_text_field')), '小欣最關心我。');
      await _next(tester);
      // Last screen: the day-7 reminder time (ada.md §6.1).
      expect(find.text('第 7 / 7 頁'), findsOneWidget);
      expect(find.byKey(const ValueKey('survey_help')), findsOneWidget);
      await _tapKey(tester, 'reminder_time_19:00');
      await _next(tester);
      expect(find.byKey(const ValueKey('survey_done')), findsOneWidget);

      final d = _doc(store, kAdaCollection, 'visit1');
      expect(d['formVersion'], 'short');
      expect(d['timepoint'], 'visit1');
      expect(d['studyPhase'], 'A');
      expect(d['uid'], _uid);
      expect(d['channel'], 'app');
      expect(d['itemsVersion'], adaItemsVersion);
      expect(d.containsKey('usage'), isFalse);
      expect(d.containsKey('scenarios'), isFalse);
      expect((d['traits'] as Map)['warm'],
          {'siu_yan': 4, 'ah_jan_ah_bak': 4, 'tung_tung': 4});
      expect(d['freeText'], '小欣最關心我。');
      expect(d['freeTextStatus'], 'answered');
      expect(d['freeTextInputMode'], 'typed');
      expect(d['day7ReminderTime'], '19:00');
      expect(d['status'], 'submitted');
      expect(d['startedAt'], isA<DateTime>());
      expect(d['submittedAt'], isA<DateTime>());
      expect(d['ahJanAhBakVariant'], 'feminine');
      expect(d.keys.where((k) => k.toLowerCase().contains('total')), isEmpty,
          reason: 'no totals (§4.4)');
      expect(store.saves, 7);
    });

    testWidgets('reminder time skipped → stored "skipped" (server default)',
        (tester) async {
      final store = InMemorySurveyDraftStore();
      await _pumpPage(tester,
          AdaPage(timepoint: _short, store: store, uid: _uid, voiceEnabled: false));
      await _next(tester);
      for (var i = 0; i < AdaTraits.all.length + 1; i++) {
        await _tapKey(tester, 'survey_skip');
      }
      expect(find.textContaining('10:00'), findsWidgets);
      await _tapKey(tester, 'survey_skip');
      expect(find.byKey(const ValueKey('survey_done')), findsOneWidget);
      expect(_doc(store, kAdaCollection, 'visit1')['day7ReminderTime'],
          kSkipped);
    });

    testWidgets(
        'full form (A+B+C+D) with 阿伯: 12 screens, avatars, skip recorded '
        '(§9.1, §9.3)', (tester) async {
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
      expect(find.text(AdaUsage.questionZh), findsOneWidget);
      for (final l in AdaUsage.labelsZh) {
        expect(find.text(l), findsNWidgets(3));
      }
      expect(find.text('阿伯'), findsOneWidget);
      expect(find.textContaining('阿珍'), findsNothing);
      expect(find.byKey(const ValueKey('ada_avatar_asset_assets/agents/ah_bak_avatar.png')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('survey_back')));
      await tester.pumpAndSettle();
      await _next(tester);
      await _answerA(tester);
      await _answerB(tester);
      for (final s in AdaScenarios.all) {
        expect(find.text('「${AdaScenarios.labelsZh[s]}」'), findsOneWidget);
        expect(find.text('阿伯'), findsOneWidget);
        expect(find.textContaining('阿珍'), findsNothing);
        expect(find.text('邊個都得'), findsOneWidget);
        expect(find.byKey(const ValueKey('ada_avatar_tung_tung')), findsOneWidget);
        if (s == AdaScenarios.learnNew) {
          await _tapKey(tester, 'survey_skip');
        } else {
          await _tapKey(tester, 'scenario_${s}_ah_jan_ah_bak');
          await _next(tester);
        }
      }
      // D skipped; no reminder screen on day 7.
      await _tapKey(tester, 'survey_skip');
      expect(find.byKey(const ValueKey('survey_done')), findsOneWidget);

      final d = _doc(store, kAdaCollection, 'day7');
      expect(d['formVersion'], 'full');
      expect(d['ahJanAhBakVariant'], 'masculine');
      expect(d['usage'], {'siu_yan': 2, 'ah_jan_ah_bak': 2, 'tung_tung': 2});
      expect((d['scenarios'] as Map)['learn_new'], kSkipped);
      expect((d['scenarios'] as Map)['day_recap'], 'ah_jan_ah_bak');
      expect(d['freeText'], isNull);
      expect(d['freeTextStatus'], kSkipped);
      expect(d.containsKey('day7ReminderTime'), isFalse);
      expect(d['status'], 'submitted');
    });

    testWidgets('no pairing on file: both names, neutral avatar',
        (tester) async {
      await _pumpPage(
          tester,
          AdaPage(
              timepoint: _full,
              store: InMemorySurveyDraftStore(),
              uid: _uid,
              voiceEnabled: false));
      await _next(tester);
      expect(find.text('阿珍／阿伯'), findsOneWidget);
      expect(find.byKey(const ValueKey('ada_avatar_asset_assets/agents/ah_jan_avatar.png')),
          findsNothing);
    });

    testWidgets('incomplete screen: hint, no advance; skip marks the rest',
        (tester) async {
      final store = InMemorySurveyDraftStore();
      await _pumpPage(tester,
          AdaPage(timepoint: _full, store: store, uid: _uid, voiceEnabled: false));
      await _next(tester);
      await _tapKey(tester, 'usage_siu_yan_0');
      await _next(tester);
      expect(find.text('第 2 / 12 頁'), findsOneWidget);
      expect(find.byKey(const ValueKey('survey_hint')), findsOneWidget);
      await _tapKey(tester, 'survey_skip');
      expect(find.text('第 3 / 12 頁'), findsOneWidget);
      final d = _doc(store, kAdaCollection, 'day7');
      expect(d['usage'],
          {'siu_yan': 0, 'ah_jan_ah_bak': kSkipped, 'tung_tung': kSkipped});
      expect(d['status'], 'in_progress');
      expect(d['lastScreen'], 2);
      await tester.tap(find.byKey(const ValueKey('survey_back')));
      await tester.pumpAndSettle();
      expect(find.text('第 2 / 12 頁'), findsOneWidget);
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

    testWidgets('a draft resumes where it was left (§9.6)', (tester) async {
      final store = InMemorySurveyDraftStore();
      store.docs[InMemorySurveyDraftStore.key(_uid, kAdaCollection, 'day7')] =
          {
        'status': 'in_progress',
        'lastScreen': 2,
        'usage': {'siu_yan': 3, 'ah_jan_ah_bak': 1, 'tung_tung': 0},
        'startedAt': DateTime(2026, 10, 7),
      };
      await _pumpPage(tester,
          AdaPage(timepoint: _full, store: store, uid: _uid, voiceEnabled: false));
      expect(find.text('第 3 / 12 頁'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('survey_back')));
      await tester.pumpAndSettle();
      final d = _doc(store, kAdaCollection, 'day7');
      expect(d['usage'], {'siu_yan': 3, 'ah_jan_ah_bak': 1, 'tung_tung': 0});
      expect(d['startedAt'], DateTime(2026, 10, 7), reason: 'not overwritten');
    });

    testWidgets('voice off: no mic; voice on: mic row shown (§9.5)',
        (tester) async {
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
        for (var i = 0; i < AdaTraits.all.length; i++) {
          await _tapKey(tester, 'survey_skip');
        }
        expect(find.text(AdaFreeText.questionZh), findsOneWidget);
        expect(find.byKey(const ValueKey('long_text_mic_row')),
            voice ? findsOneWidget : findsNothing);
        expect(find.text('或者用講嘅'), voice ? findsOneWidget : findsNothing);
      }
    });

    testWidgets('help button: no number configured → no dialling, a note',
        (tester) async {
      await _pumpPage(
          tester,
          AdaPage(
              timepoint: _short,
              store: InMemorySurveyDraftStore(),
              uid: _uid,
              voiceEnabled: false));
      await _tapKey(tester, 'survey_help');
      expect(find.byKey(const ValueKey('survey_help_no_number')),
          findsOneWidget);
    });

    testWidgets('Part D goes through SafetyService (ada_free_text, §7)',
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
      for (var i = 0; i < AdaTraits.all.length; i++) {
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
      expect(find.byKey(const ValueKey('survey_help')), findsOneWidget);
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
      expect(d['channel'], 'app');
      expect(d['enrolmentDay'], 7);
      expect(store.saves, 3);
    });

    testWidgets('open text goes through SafetyService (day7_open_ended, §7)',
        (tester) async {
      final writer = _RecordingWriter();
      await _pumpPage(
          tester,
          Day7OpenPage(
              store: InMemorySurveyDraftStore(), uid: _uid, voiceEnabled: false),
          safety: SafetyService(writer: writer));
      await tester.enterText(find.byKey(const ValueKey('long_text_field')),
          '用完一個禮拜，我仲係好想了結自己。');
      await tester.tap(find.byKey(const ValueKey('survey_next')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(writer.rows.single['inputPoint'], 'day7_open_ended');
    });

    testWidgets('voice on shows the mic row', (tester) async {
      await _pumpPage(
          tester,
          Day7OpenPage(
              store: InMemorySurveyDraftStore(), uid: _uid, voiceEnabled: true));
      expect(find.byKey(const ValueKey('long_text_mic_row')), findsOneWidget);
    });
  });

  group('Day-7 flow (ada.md §6.2–6.3)', () {
    testWidgets(
        'intro with placeholder time; part 1 of 2, stop, resume; part 2 of 2',
        (tester) async {
      final store = InMemorySurveyDraftStore();
      Widget flow() => Day7FlowPage(
            key: UniqueKey(),
            parts: const [Day7Part.ada, Day7Part.open],
            adaTimepoint: _full,
            store: store,
            uid: _uid,
            variant: AgentGenderVariant.feminine,
            voiceEnabled: false,
          );
      await _pumpPage(tester, flow());
      expect(find.text('【占位】預計時間：試跑後再定'), findsOneWidget);
      expect(find.byKey(const ValueKey('survey_help')), findsOneWidget);
      expect(find.text('未開始'), findsNWidgets(2));
      await _tapKey(tester, 'day7_start');
      expect(find.text('第 1 部分，共 2 部分'), findsOneWidget);
      await _next(tester); // intro → A
      await _answerA(tester);
      // Stop in the middle (back out of the part).
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('做咗一半'), findsOneWidget);
      expect(find.text('繼續'), findsOneWidget);

      // Next time: a fresh flow page resumes on B1 of part 1.
      await _pumpPage(tester, flow());
      await _tapKey(tester, 'day7_start');
      expect(find.text('第 1 部分，共 2 部分'), findsOneWidget);
      expect(find.text('第 3 / 12 頁'), findsOneWidget);
      for (var i = 0; i < 4 + 5 + 1; i++) {
        await _tapKey(tester, 'survey_skip');
      }
      await _tapKey(tester, 'survey_done_button');
      // Straight on to part 2.
      expect(find.text('第 2 部分，共 2 部分'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await _tapKey(tester, 'survey_skip');
      }
      await _tapKey(tester, 'survey_done_button');
      expect(find.text('全部做完喇，多謝你！'), findsOneWidget);
      expect(_doc(store, kAdaCollection, 'day7')['status'], 'submitted');
      expect(_doc(store, kAdaCollection, 'day7')['usage'],
          {'siu_yan': 2, 'ah_jan_ah_bak': 2, 'tung_tung': 2});
      expect(_doc(store, kDay7OpenCollection, 'day7')['status'], 'submitted');
    });

    testWidgets('configured minutes replace the placeholder', (tester) async {
      PhaseAScheduleConfig.current =
          const PhaseAScheduleConfig(day7FlowMinutes: 15);
      await _pumpPage(
          tester,
          Day7FlowPage(
              parts: const [Day7Part.open],
              adaTimepoint: _full,
              store: InMemorySurveyDraftStore(),
              uid: _uid));
      expect(find.text('大約要 15 分鐘。'), findsOneWidget);
      expect(find.text('一共有 1 部分。可以隨時停，下次會由停低嗰度繼續。'),
          findsOneWidget);
    });
  });

  group('Home card (ada.md §6.1)', () {
    testWidgets('one 第 7 日問卷 card instead of two', (tester) async {
      await _pumpPage(
          tester,
          const Scaffold(
            body: PendingPromptsBanner(
              preset: PendingPrompts(
                pgic: false,
                weeklyPr: false,
                weeklyPrWeekIso: null,
                weeklyPrAgent: null,
                djgEsW2: false,
                agentDiffW2: false,
                agentDiffW4: false,
                day7Flow: [Day7Part.ada, Day7Part.open],
                enrolmentDay: 7,
              ),
            ),
          ));
      expect(find.text('第 7 日問卷'), findsOneWidget);
      expect(find.byKey(const ValueKey('day7_flow_card')), findsOneWidget);
    });
  });

  group('Researcher page and phone completion (ada.md §6.6–6.7, §9.8)', () {
    testWidgets('four states shown; completed has no phone button',
        (tester) async {
      await _pumpPage(tester, AdaStaffPage(source: _FakeStaffSource()));
      expect(find.text('已超時（做咗一部分）'), findsOneWidget);
      expect(find.text('進行中'), findsOneWidget);
      expect(find.text('未開始'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.byKey(const ValueKey('ada_staff_phone_u1')), findsOneWidget);
      expect(find.byKey(const ValueKey('ada_staff_phone_u4')), findsNothing);
      expect(find.text('未開始 1 · 進行中 1 · 已完成 1 · 已超時 1'), findsOneWidget);
    });

    testWidgets('phone completion writes channel phone_by_staff, no mic',
        (tester) async {
      final store = InMemoryStaffSurveyDraftStore();
      await _pumpPage(
          tester,
          AdaStaffPage(
            source: _FakeStaffSource(),
            storeFactory: () => store,
            parts: const [Day7Part.open],
          ));
      await _tapKey(tester, 'ada_staff_phone_u1');
      expect(find.text('第 7 日問卷（電話代填）'), findsOneWidget);
      await _tapKey(tester, 'day7_start');
      expect(find.text('電話代填（研究員）'), findsOneWidget);
      expect(find.byKey(const ValueKey('long_text_mic_row')), findsNothing);
      await tester.enterText(
          find.byKey(const ValueKey('long_text_field')), '電話入面講：通通好有趣。');
      await _next(tester);
      final d = store.docs[
          InMemorySurveyDraftStore.key('u1', kDay7OpenCollection, 'day7')]!;
      expect(d['channel'], AdaChannel.phoneByStaff);
      expect(d['uid'], 'u1');
    });

    testWidgets('staff safety hit: server flag → notice for the researcher',
        (tester) async {
      final store = InMemoryStaffSurveyDraftStore()..nextSafetyFlag = true;
      final writer = _RecordingWriter();
      await _pumpPage(
          tester,
          Day7OpenPage(
            store: store,
            uid: 'u1',
            channel: AdaChannel.phoneByStaff,
          ),
          safety: SafetyService(writer: writer));
      await tester.enterText(find.byKey(const ValueKey('long_text_field')),
          '佢話我仲係好想了結自己。');
      await tester.tap(find.byKey(const ValueKey('survey_next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff_safety_notice')), findsOneWidget);
      expect(writer.rows, isEmpty,
          reason: 'the server writes the event for the participant');
    });
  });
}
