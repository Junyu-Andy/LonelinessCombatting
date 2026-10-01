// Arm B Tung Tung page: rule openers + template replies, never the LLM.
//
// Arm.of only reads the randomised arm in a Phase B build, so run with:
//   flutter test --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
//     test/tung_tung_arm_b_test.dart
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
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
import 'package:app_demo/core/safety/safety_copy.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/curious_companion/data/tung_tung_rule_pool.dart';
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

const _armB = String.fromEnvironment('FORCE_ARM') == 'B';

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

  testWidgets('opens with a rule-pool opener and replies from templates',
      (tester) async {
    // No connectivity plugin in tests: report Wi-Fi so the send isn't
    // parked in the offline-resend queue.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final openerShown = TungTungRulePool.items.any((o) => find
        .textContaining(o.zh, findRichText: true)
        .evaluate()
        .isNotEmpty);
    expect(openerShown, isTrue, reason: 'first bubble is a pool opener');

    await tester.enterText(find.byType(TextField).first, '我今日去咗飲茶');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded).first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(client.calls, 0, reason: 'Arm B must never call the LLM');
    expect(find.textContaining('LLM REPLY', findRichText: true), findsNothing);
    expect(find.textContaining('我今日去咗飲茶', findRichText: true), findsWidgets);
    expect(find.textContaining('食嘢', findRichText: true), findsWidgets,
        reason: 'food-topic template reply');
  }, skip: !(FeatureFlags.phaseB && _armB));
  testWidgets('acute input shows the hotline and no template reply',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '我真係想死');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded).first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(client.calls, 0);
    // Router pushes the crisis page on top; the chat page underneath
    // carries the same acute template Arm A shows (hotline from the
    // crisis-resources config).
    final acute = SafetyCopy.acuteAck('tung_tung', isEn: false);
    expect(find.textContaining(acute, findRichText: true,
        skipOffstage: false), findsWidgets);
    expect(find.textContaining('原來係咁', findRichText: true,
        skipOffstage: false), findsNothing);
  }, skip: !(FeatureFlags.phaseB && _armB));
}
