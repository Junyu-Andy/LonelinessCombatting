// Shared harness for the Arm B check-in / reminiscence template-reply
// tests (decision 0023).  Not a test file itself.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
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
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Fails the test if anything reaches the LLM (Arm B must never call it).
class NoLlmClient implements LlmClient {
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

/// Wraps [home] (pushed on top of a blank root so the page can pop) in
/// the scopes the Arm B pages read.  No Firebase, no profile.
Widget ruleReplyHarness(Widget home, NoLlmClient client) {
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
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => home)),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
