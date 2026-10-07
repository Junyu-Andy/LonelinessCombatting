// T15 screenshot entrypoint (not shipped): renders one Arm A / Arm B page
// with offline fakes so Playwright can drive it in Chromium.
//
//   flutter build web --no-web-resources-cdn \
//     -t docs/dev-reports/T15-rule-based-replies-20261007-screenshots/t15_screens_main.dart \
//     [--dart-define=RULE_TEMPLATE_REPLIES=true \
//      --dart-define=RULE_TEMPLATE_REPLIES_ALLOW_PLACEHOLDER=true]
//   open index.html?page=checkin_a|checkin_b|remi_a|remi_b
//
// The Hybrid (Arm A) reply is a canned mock string — no LLM is called.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
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
import 'package:app_demo/features/context/presentation/pages/check_in_arm_a.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_b.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class _MockHybrid implements LlmClient {
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
  }) async =>
      const LlmRawResponse(text: '（截圖示意：Hybrid 組呢度係 AI 回覆）');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final page = Uri.base.queryParameters['page'] ?? 'checkin_b';
  final week1 = ReminiscenceTheme.byIndex(1);
  final Widget home = switch (page) {
    'checkin_a' => const CheckInArmA(),
    'remi_a' => ReminiscenceArmAPage(theme: week1),
    'remi_b' => ReminiscenceArmBPage(
        theme: week1, replyHistory: InMemoryRuleReplyHistoryStore()),
    _ => CheckInArmB(replyHistory: InMemoryRuleReplyHistoryStore()),
  };
  final llm = LlmGateway(client: _MockHybrid());
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  runApp(AppSettingsScope(
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
              memory: memory, firestoreAvailable: false),
          agentContext: agentContext,
          sharedContext: sharedContext,
          personaResolver: PersonaResolver(
              agentContext: agentContext, sharedContext: sharedContext),
          referralRouting: ReferralRoutingService(sharedContext: sharedContext),
          handoffExecutor: HandoffExecutor(sharedContext: sharedContext),
          agentGreeting: AgentGreetingService(llm),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            locale: const Locale('zh', 'HK'),
            supportedLocales: const [Locale('zh', 'HK'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: home,
          ),
        ),
      ),
    ),
  ));
}
