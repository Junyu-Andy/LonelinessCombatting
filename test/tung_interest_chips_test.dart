// 10/16 — 通通 interest chips: two at a time plus 「換一換」 (S18); the
// whole list used to spill over several lines above the input.  Any
// build (the chips are the same in both arms; the LLM is never called
// here because nothing is sent).
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
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/curious_companion/data/tung_tung_rule_pool.dart';
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
      settings: AppSettings(locale: const Locale('zh'))
        ..profile = UserProfile(
            uid: 'u', email: 'e', displayName: 'd',
            consent: const ConsentFlags(functionalData: true),
            interests: const ['yum_cha', 'mahjong', 'hiking', 'news']),
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


  testWidgets('10/16: two interest chips at a time; 換一換 rotates through '
      'the rest', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    // First visit: the intro overlay (好，開始) sits on top of the chat.
    await tester.tap(find.text('好，開始'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tung_interest_chip_yum_cha')), findsOneWidget);
    expect(find.byKey(const Key('tung_interest_chip_mahjong')), findsOneWidget);
    expect(find.byKey(const Key('tung_interest_chip_hiking')), findsNothing);
    expect(find.text('換一換'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('tung_interest_shuffle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tung_interest_shuffle')),
        warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tung_interest_chip_hiking')), findsOneWidget);
    expect(find.byKey(const Key('tung_interest_chip_news')), findsOneWidget);
    expect(find.byKey(const Key('tung_interest_chip_yum_cha')), findsNothing);
    await tester.tap(find.byKey(const Key('tung_interest_shuffle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tung_interest_chip_yum_cha')), findsOneWidget,
        reason: 'wraps around');
    // Tapping a chip drafts the message as before.
    await tester.ensureVisible(find.byKey(const Key('tung_interest_chip_yum_cha')));
    await tester.tap(find.byKey(const Key('tung_interest_chip_yum_cha')));
    await tester.pump();
    final input = tester.widget<TextField>(find.byType(TextField).first);
    expect(input.controller!.text, '我想傾下 飲茶／一盅兩件');
  });
}
