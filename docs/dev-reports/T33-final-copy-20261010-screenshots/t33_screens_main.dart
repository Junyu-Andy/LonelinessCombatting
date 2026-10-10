// T33 screenshot entrypoint (not shipped): renders the Arm B check-in /
// reminiscence page with offline fakes so Playwright can drive it in
// Chromium.  Same setup as the T15 entrypoint, Arm B pages only.
//
//   flutter build web --no-web-resources-cdn \
//     -t docs/dev-reports/T33-final-copy-20261010-screenshots/t33_screens_main.dart \
//     --dart-define=RULE_TEMPLATE_REPLIES=true \
//     --dart-define=RULE_TEMPLATE_REPLIES_ALLOW_PLACEHOLDER=true
//   open index.html?page=checkin_b|remi_b|onboarding_s5
//
// No LLM is called.  `onboarding_s5` turns the S5 switch on locally.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/config/usage_copy.dart';
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
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/onboarding/presentation/pages/agent_onboarding_page.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_b.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class _NoLlm implements LlmClient {
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
      const LlmRawResponse(text: '（Arm B 唔應該叫到 LLM）');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final page = Uri.base.queryParameters['page'] ?? 'checkin_b';
  final week1 = ReminiscenceTheme.byIndex(1);
  final Widget home = switch (page) {
    'remi_b' => ReminiscenceArmBPage(
        theme: week1, replyHistory: InMemoryRuleReplyHistoryStore()),
    'onboarding_s5' => const AgentOnboardingPage(),
    _ => CheckInArmB(replyHistory: InMemoryRuleReplyHistoryStore()),
  };
  if (page == 'onboarding_s5') {
    UsageCopy.current = const UsageCopy({}, true);
  }
  final llm = LlmGateway(client: _NoLlm());
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  runApp(AppSettingsScope(
    settings: AppSettings(
        locale: const Locale('zh'),
        // Onboarding needs a profile; the Arm B pages run without one
        // (no Firestore writes).
        profile: page == 'onboarding_s5'
            ? const UserProfile(uid: 'u', email: 'e', displayName: 'd')
            : null),
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
