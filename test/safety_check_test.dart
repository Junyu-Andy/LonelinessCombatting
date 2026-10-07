// T7 — the shared safety-check entry point (lib/core/safety/safety_check.dart).
//
//   - T6's 20 risk sentences: the Hybrid path (LlmGateway) and the rule
//     path (SafetyService.checkUserText) give the same level and the same
//     event for every sentence;
//   - one sentence through every input point: scanned, event carries
//     source / inputPoint / turnId;
//   - the `safetyScanAllInputs` switch;
//   - one turn = one event (reply scan writes only above the input);
//   - hotline filter on AI replies, and the crisis link in chat bubbles;
//   - checkAndRoute opens the crisis page (acute) / support sheet (moderate).
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/config/phase_a_config.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/safety/hotline_filter.dart';
import 'package:app_demo/core/safety/safety_check.dart';
import 'package:app_demo/core/safety/safety_event_writer.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/crisis/presentation/pages/emergency_support_page.dart';
import 'package:app_demo/shared/widgets/rich_chat_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures what would be written to `safety_events`.
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
  }) async {
    if (!match.isEscalation) return;
    rows.add({
      'uid': uid,
      'source': source.code,
      'inputPoint': inputPoint,
      'turnId': turnId,
      'tier': match.level.tierCode,
      'matchedTerm': match.matchedTerm,
    });
  }
}

class _FakeClient implements LlmClient {
  _FakeClient(this.reply, {this.serverReplaced = 0});
  final String reply;
  final int serverReplaced;
  int calls = 0;

  @override
  Future<LlmRawResponse> complete({
    required String moduleId,
    String? systemPrompt,
    String? promptKey,
    String? agentId,
    String? variantName,
    String? contextSuffix,
    required List<LlmTurn> history,
    required String userInput,
    bool regenerate = false,
    Map<String, dynamic>? agentContextSnapshot,
  }) async {
    calls++;
    return LlmRawResponse(text: reply, hotlineReplaced: serverReplaced);
  }
}

List<Map<String, dynamic>> _t6Sentences() {
  final raw = File(
    'docs/dev-reports/T6-safety-parity-20261006-scripts/sentences.json',
  ).readAsStringSync();
  return (jsonDecode(raw)['sentences'] as List).cast<Map<String, dynamic>>();
}

/// One synthetic sentence per input point (none from real conversations).
const Map<SafetyInputPoint, String> _perPoint = {
  SafetyInputPoint.chatCheckIn: '我真係想死，冇人理我。',
  SafetyInputPoint.chatReminiscence: '嗰陣時我已經想自殺。',
  SafetyInputPoint.chatReflective: '我覺得自己好冇用。',
  SafetyInputPoint.chatTungTung: '我想燒炭算數。',
  SafetyInputPoint.articleQa: '睇完呢篇我更加覺得冇晒希望。',
  SafetyInputPoint.checkInNote: '今晚想了結自己。',
  SafetyInputPoint.reminiscenceNote: '老伴過咗身之後好難捱。',
  SafetyInputPoint.systemGenerated: '呢位用戶之前提過：想死。',
  SafetyInputPoint.thoughtExercise: '我成日諗住自殺。',
  SafetyInputPoint.intakeOnMind: '我覺得活落去冇意思，唔想再生。',
  SafetyInputPoint.intakeAvoidTopics: '唔好同我講自殺嘅嘢。',
  SafetyInputPoint.intakeOtherText: '夜晚成日一個人，冇人理我。',
  SafetyInputPoint.agentDiff: '佢哋都幫唔到我，我想死。',
  SafetyInputPoint.feedbackOther: '講咩都冇用，我想死。',
  SafetyInputPoint.actionPlan: '同仔女講再見，然後燒炭。',
  SafetyInputPoint.actionFollowup: '冇去到，我覺得自己係負累。',
  SafetyInputPoint.pprFreeText: '我好想了結自己。',
  SafetyInputPoint.reminiscenceSummaryEdit: '嗰年我想跳樓。',
  SafetyInputPoint.m3SessionEdit: '其實我想自殺。',
  SafetyInputPoint.searchQuery: '點樣自殺最快',
  SafetyInputPoint.adaFreeText: '三個都冇用，我想死。',
  SafetyInputPoint.day7OpenEnded: '用完一個禮拜，我仲係好想了結自己。',
};

/// moduleIds the Hybrid pages pass for each conversational point.
const Map<SafetyInputPoint, String> _moduleFor = {
  SafetyInputPoint.chatCheckIn: 'm2_check_in',
  SafetyInputPoint.chatReminiscence: 'm3_reminiscence_w3',
  SafetyInputPoint.chatReflective: 'reflective_dialogue',
  SafetyInputPoint.chatTungTung: 'tung_tung_chat',
  SafetyInputPoint.articleQa: 'm8_education_sleep',
  SafetyInputPoint.actionPlan: 'm7_action_loop_summary',
  SafetyInputPoint.actionFollowup: 'm7_action_loop_followup',
  SafetyInputPoint.systemGenerated: 'm6_suggestions',
};

void main() {
  setUp(() => PhaseAConfig.current = const PhaseAConfig());

  group('T6 20 sentences — Hybrid path == rule path', () {
    final sentences = _t6Sentences();
    test('fixture has the 20 sentences', () {
      expect(sentences, hasLength(20));
    });

    for (final s in sentences) {
      test('${s['id']} ${s['intended']}', () async {
        final text = s['text'] as String;
        // Rule arm (check-in note, the Arm B surface for the same chat).
        final wB = _RecordingWriter();
        final rB = SafetyService(
          writer: wB,
        ).checkUserText(text, point: SafetyInputPoint.checkInNote, uid: 'u');
        // Hybrid arm: the gateway's input scan, benign reply.
        final wA = _RecordingWriter();
        final client = _FakeClient('多謝你話我知。');
        final rA =
            await LlmGateway(
              safety: SafetyService(writer: wA),
              client: client,
            ).send(
              moduleId: 'm2_check_in',
              systemPrompt: 'sys',
              history: const [],
              userInput: text,
              uid: 'u',
            );
        expect(rA.inputFlag.level, rB.level, reason: 'same detection');
        expect(rA.inputFlag.matchedTerm, rB.match.matchedTerm);
        expect(wA.rows.length, wB.rows.length, reason: 'same event count');
        expect(wA.rows.length, rB.isEscalation ? 1 : 0);
        for (var i = 0; i < wA.rows.length; i++) {
          expect(wA.rows[i]['source'], 'user_input');
          expect(wB.rows[i]['source'], 'user_input');
          expect(wA.rows[i]['tier'], wB.rows[i]['tier']);
        }
        // Acute: the model is never called on the Hybrid side.
        expect(client.calls, rB.isAcute ? 0 : 1);
        expect(rA.shortCircuited, rB.isAcute);
      });
    }

    test('lexicon results match the T6 report (v5 unchanged)', () {
      const service = SafetyService();
      final hits = {
        for (final s in sentences)
          s['id']: service.detect(s['text'] as String).level.tierCode,
      };
      expect(hits['A1'], 'acute');
      expect(hits['A8'], 'acute');
      expect(hits['M4'], 'moderate_review');
      expect(hits['A2'], 'none', reason: 'known lexicon gap (T6)');
      expect(hits.values.where((v) => v != 'none'), hasLength(9));
    });
  });

  group('every input point', () {
    test('the table covers every SafetyInputPoint', () {
      expect(_perPoint.keys.toSet(), SafetyInputPoint.values.toSet());
    });

    for (final e in _perPoint.entries) {
      test('${e.key.code}: scanned, event tagged', () {
        final w = _RecordingWriter();
        final r = SafetyService(
          writer: w,
        ).checkUserText(e.value, point: e.key, uid: 'u', turnId: 'turn-x');
        expect(r.scanned, isTrue);
        expect(r.isEscalation, isTrue, reason: e.value);
        expect(w.rows, hasLength(1));
        expect(w.rows.single['inputPoint'], e.key.code);
        expect(w.rows.single['source'], e.key.source.code);
        expect(w.rows.single['turnId'], 'turn-x');
      });
    }

    for (final e in _moduleFor.entries) {
      test('gateway ${e.value} → ${e.key.code}', () async {
        expect(SafetyInputPoint.forModule(e.value), e.key);
        final w = _RecordingWriter();
        await LlmGateway(
          safety: SafetyService(writer: w),
          client: _FakeClient('好。'),
        ).send(
          moduleId: e.value,
          systemPrompt: 'sys',
          history: const [],
          userInput: _perPoint[e.key]!,
        );
        expect(w.rows.single['inputPoint'], e.key.code);
      });
    }

    test('opener / summary calls are system-generated', () {
      expect(
        SafetyInputPoint.forModule('m3_reminiscence_w2_opener'),
        SafetyInputPoint.systemGenerated,
      );
      expect(
        SafetyInputPoint.forModule('m3_reminiscence_w2_summary'),
        SafetyInputPoint.systemGenerated,
      );
      expect(
        SafetyInputPoint.forModule('greeting_siu_yan'),
        SafetyInputPoint.systemGenerated,
      );
    });
  });

  group('safetyScanAllInputs switch', () {
    test('off: T7 inputs skipped, conversations still scanned', () {
      PhaseAConfig.current = const PhaseAConfig(safetyScanAllInputs: false);
      final w = _RecordingWriter();
      final s = SafetyService(writer: w);
      final off = s.checkUserText(
        '我真係想死',
        point: SafetyInputPoint.thoughtExercise,
      );
      expect(off.scanned, isFalse);
      expect(off.level, DistressLevel.none);
      final on = s.checkUserText('我真係想死', point: SafetyInputPoint.checkInNote);
      expect(on.scanned, isTrue);
      expect(on.isAcute, isTrue);
      expect(w.rows, hasLength(1));
    });

    test('default is on', () {
      expect(const PhaseAConfig().safetyScanAllInputs, isTrue);
      expect(const PhaseAConfig().hotlineFilterClient, isTrue);
      expect(
        PhaseAConfig.fromMap({
          'safetyScanAllInputs': false,
        }).safetyScanAllInputs,
        isFalse,
      );
    });
  });

  group('one turn = one event', () {
    Future<_RecordingWriter> turn(String input, String reply) async {
      final w = _RecordingWriter();
      await LlmGateway(
        safety: SafetyService(writer: w),
        client: _FakeClient(reply),
      ).send(
        moduleId: 'm2_check_in',
        systemPrompt: 'sys',
        history: const [],
        userInput: input,
      );
      return w;
    }

    test('input and reply at the same tier → one event', () async {
      final w = await turn('我覺得自己好冇用', '你唔係冇用。');
      expect(w.rows, hasLength(1));
      expect(w.rows.single['source'], 'user_input');
    });

    test('reply above the input → second event, same turnId', () async {
      final w = await turn('我覺得自己好冇用', '撒瑪利亞防止自殺會可以幫你。');
      expect(w.rows, hasLength(2));
      expect(w.rows[1]['source'], 'ai_output_scan');
      expect(w.rows[0]['turnId'], w.rows[1]['turnId']);
    });

    test('benign input, flagged reply → one ai_output_scan event', () async {
      final w = await turn('今日去咗飲茶', '撒瑪利亞防止自殺會');
      expect(w.rows.single['source'], 'ai_output_scan');
    });

    test('every turn gets its own turnId', () async {
      final a = await turn('我好冇用', '好。');
      final b = await turn('我好冇用', '好。');
      expect(a.rows.single['turnId'], isNot(b.rows.single['turnId']));
    });
  });

  group('hotline filter', () {
    final cases =
        jsonDecode(
              File(
                'test/fixtures/hotline_filter_cases.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    test('same cases as the server filter', () {
      for (final c in (cases['phones'] as List).cast<Map>()) {
        final r = filterHotlines(c['text'] as String);
        expect(r.count, c['count'], reason: '${c['text']} → ${r.text}');
      }
      for (final c in (cases['nonPhones'] as List).cast<Map>()) {
        final r = filterHotlines(c['text'] as String);
        expect(r.count, 0, reason: '${c['text']} → ${r.text}');
        expect(r.text, c['text']);
      }
    });

    test('gateway replaces numbers the server missed', () async {
      final r = await LlmGateway(client: _FakeClient('可以打 2389 2222 或者 999。'))
          .send(
            moduleId: 'm2_check_in',
            systemPrompt: 'sys',
            history: const [],
            userInput: '我好唔開心',
          );
      expect(r.text, '可以打 $kHotlineToken 或者 $kHotlineToken。');
      expect(r.hotlineReplaced, 2);
    });

    test('server count is carried through', () async {
      final r =
          await LlmGateway(
            client: _FakeClient('可以撳 $kHotlineToken。', serverReplaced: 1),
          ).send(
            moduleId: 'm2_check_in',
            systemPrompt: 'sys',
            history: const [],
            userInput: '我好唔開心',
          );
      expect(r.hotlineReplaced, 1);
    });

    test('client pass can be switched off', () async {
      PhaseAConfig.current = const PhaseAConfig(hotlineFilterClient: false);
      final r = await LlmGateway(client: _FakeClient('打 2389 2222')).send(
        moduleId: 'm2_check_in',
        systemPrompt: 'sys',
        history: const [],
        userInput: 'hi',
      );
      expect(r.text, '打 2389 2222');
    });

    testWidgets('token renders as a link to the crisis page', (tester) async {
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: RichChatText(
              text: '你可以撳 $kHotlineToken 搵人傾。',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
      expect(find.byType(HotlineLink), findsOneWidget);
      expect(find.textContaining('【'), findsNothing);
      await tester.tap(find.byType(HotlineLink));
      await tester.pumpAndSettle();
      expect(find.byType(EmergencySupportPage), findsOneWidget);
    });
  });

  group('checkAndRoute (form pages)', () {
    Future<void> submit(WidgetTester tester, String text) async {
      await tester.pumpWidget(
        _scoped(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => SafetyService.of(context).checkAndRoute(
                  context,
                  text,
                  point: SafetyInputPoint.thoughtExercise,
                ),
                child: const Text('save'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
    }

    testWidgets('acute → crisis page', (tester) async {
      await submit(tester, '我真係想死');
      expect(find.byType(EmergencySupportPage), findsOneWidget);
    });

    testWidgets('moderate_interrupt → support sheet', (tester) async {
      await submit(tester, '我覺得自己好冇用');
      expect(find.byType(DistressModerateSheet), findsOneWidget);
      expect(find.byType(EmergencySupportPage), findsNothing);
    });

    testWidgets('moderate_review → nothing visible', (tester) async {
      await submit(tester, '老伴過咗身');
      expect(find.byType(DistressModerateSheet), findsNothing);
      expect(find.byType(EmergencySupportPage), findsNothing);
    });

    testWidgets('benign → nothing', (tester) async {
      await submit(tester, '今日天氣好好');
      expect(find.byType(DistressModerateSheet), findsNothing);
      expect(find.byType(EmergencySupportPage), findsNothing);
    });
  });
}

Widget _app(Widget home) => AppSettingsScope(
  settings: AppSettings(locale: const Locale('zh')),
  child: AnalyticsScope(
    analytics: AnalyticsService(firebaseReady: false),
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  ),
);

Widget _scoped(Widget home) {
  final llm = LlmGateway(client: _FakeClient(''));
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  return CoreServicesScope(
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
    safety: SafetyService(writer: _RecordingWriter()),
    child: _app(home),
  );
}
