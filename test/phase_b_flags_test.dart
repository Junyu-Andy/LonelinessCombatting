// C18 Phase B switches (decision 0019): 搜一搜, voice input, and Tung
// Tung's fixed search-off reply.  Default (Phase A) build = Hybrid page.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/safety/safety_copy.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/core/voice/voice_input_button.dart';
import 'package:app_demo/features/curious_companion/data/search_repository.dart';
import 'package:app_demo/features/curious_companion/data/tung_tung_search_intent.dart';
import 'package:app_demo/features/curious_companion/presentation/pages/tung_tung_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingClient implements LlmClient {
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
    return const LlmRawResponse(text: 'LLM REPLY');
  }
}

void main() {
  late _CountingClient client;

  Widget harness() {
    client = _CountingClient();
    final llm = LlmGateway(client: client);
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
            child: const MaterialApp(
              locale: Locale('zh'),
              supportedLocales: [Locale('zh'), Locale('en')],
              localizationsDelegates: [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: TungTungPage(),
            ),
          ),
        ),
      ),
    );
  }


  setUp(() => RemoteFeatureFlags.current = const RemoteFeatureFlags());
  tearDown(() => RemoteFeatureFlags.current = const RemoteFeatureFlags());

  void mockOnline(WidgetTester tester) {
    // No connectivity plugin in tests: report Wi-Fi so the send isn't
    // parked in the offline-resend queue.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded).first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  group('RemoteFeatureFlags', () {
    test('everything is off by default', () {
      const f = RemoteFeatureFlags();
      expect(f.webSearchEnabled, isFalse);
      expect(f.voiceInputEnabled, isFalse);
      expect(f.searchOffReplyEnabled, isFalse);
      expect(RemoteFeatureFlags.current.voiceInputEnabled, isFalse);
    });

    test('only a literal true turns a flag on', () {
      expect(RemoteFeatureFlags.fromMap({}).webSearchEnabled, isFalse);
      final odd = RemoteFeatureFlags.fromMap({
        'webSearchEnabled': 'true',
        'voiceInputEnabled': 1,
        'searchOffReplyEnabled': null,
      });
      expect(odd.webSearchEnabled, isFalse);
      expect(odd.voiceInputEnabled, isFalse);
      expect(odd.searchOffReplyEnabled, isFalse);
      final on = RemoteFeatureFlags.fromMap({
        'webSearchEnabled': true,
        'voiceInputEnabled': true,
        'searchOffReplyEnabled': true,
      });
      expect(on.webSearchEnabled, isTrue);
      expect(on.voiceInputEnabled, isTrue);
      expect(on.searchOffReplyEnabled, isTrue);
    });

    test('load without Firebase keeps everything off', () async {
      final f = await RemoteFeatureFlags.load(available: false);
      expect(f.webSearchEnabled || f.voiceInputEnabled, isFalse);
    });
  });

  group('TungTungSearchIntent', () {
    test('matches look-up questions', () {
      for (final t in ['今日天氣點呀？', '幫我查吓天文台', '有咩新聞', '圖書館幾點開',
          '呢樣嘢幾錢', 'Can you look up the weather?']) {
        expect(TungTungSearchIntent.matches(t), isTrue, reason: t);
      }
    });

    test('does not match everyday or distress sentences', () {
      for (final t in ['我聽日去醫院檢查下', '邊度有人關心我', '我唔識上網',
          '我唔知點去面對', '我今日去咗飲茶', '搵下朋友傾偈']) {
        expect(TungTungSearchIntent.matches(t), isFalse, reason: t);
      }
    });

    // T33 — the final text S1a; verbatim check in final_copy_test.dart.
    test('reply is the final S1a text, no placeholder left', () {
      expect(TungTungSearchIntent.reply(isEn: false), isNot(contains('占位')));
      expect(TungTungSearchIntent.reply(isEn: true), isNot(contains('PLACEHOLDER')));
    });
  });

  test('search repository sends nothing while search is off', () async {
    final r = await SearchRepository(available: true).search('今日天氣');
    expect(r.unavailable, isTrue);
    expect(r.reason, 'disabled');
  });

  testWidgets('voice button renders nothing while voice input is off',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VoiceInputButton(onText: (_) {})),
    ));
    await tester.pump();
    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
  });

  // Default (Phase A) build renders the Hybrid page; Phase B builds are
  // covered by test/tung_tung_arm_b_test.dart for the rule arm.
  group('Tung Tung page, Hybrid arm', () {
    testWidgets('no mic and no search button by default', (tester) async {
      mockOnline(tester);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
      expect(find.byIcon(Icons.travel_explore_outlined), findsNothing);
      expect(find.byType(VoiceInputButton), findsOneWidget,
          reason: 'code kept, only hidden');
    });

    testWidgets('search-type question goes to the LLM while the reply flag '
        'is off', (tester) async {
      mockOnline(tester);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await send(tester, '今日天氣點呀？');
      expect(client.calls, 1);
      expect(find.textContaining('占位', findRichText: true), findsNothing);
    });

    testWidgets('fixed reply flag on: search-type question gets the fixed '
        'line and no LLM call', (tester) async {
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(searchOffReplyEnabled: true);
      mockOnline(tester);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await send(tester, '今日天氣點呀？');
      expect(client.calls, 0);
      expect(find.textContaining(TungTungSearchIntent.reply(isEn: false),
          findRichText: true), findsOneWidget);

      // An ordinary turn still goes to the LLM.
      await send(tester, '我今日去咗飲茶');
      expect(client.calls, 1);
    });

    testWidgets('fixed reply flag on: a distress hit keeps the safety flow',
        (tester) async {
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(searchOffReplyEnabled: true);
      mockOnline(tester);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await send(tester, '天氣咁差，我真係想死');
      expect(find.textContaining(TungTungSearchIntent.reply(isEn: false),
          findRichText: true, skipOffstage: false), findsNothing);
      final acute = SafetyCopy.acuteAck('tung_tung', isEn: false);
      expect(find.textContaining(acute, findRichText: true,
          skipOffstage: false), findsWidgets);
    });
  }, skip: FeatureFlags.phaseB);
}
