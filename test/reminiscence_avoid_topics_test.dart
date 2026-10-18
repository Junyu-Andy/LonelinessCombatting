// T49b (task sheet 1018 §B7 b) — the Hybrid reminiscence page sends the
// same "⛔ 用戶要求唔好提起呢啲話題" line in its contextSuffix as the other
// three Hybrid chat pages (check_in_arm_a.dart), when the profile has
// avoidTopics.  Synthetic profile, fake LLM client; no network.
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
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every call's moduleId → contextSuffix.
class _RecordingClient implements LlmClient {
  final Map<String, String?> suffixByModule = {};

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
    suffixByModule[moduleId] = contextSuffix;
    return const LlmRawResponse(text: '嗰間舖頭喺邊條街？');
  }
}

const _avoidLine = '⛔ 用戶要求唔好提起呢啲話題（就算唔小心都唔好）：';

void main() {
  late _RecordingClient client;

  Widget harness(UserProfile profile) {
    client = _RecordingClient();
    final llm = LlmGateway(client: client);
    final agentContext = AgentContextService(available: false);
    final sharedContext = SharedContextService(available: false);
    final memory = MemoryStore(available: false);
    final state = DistressState();
    return AppSettingsScope(
      settings: AppSettings(locale: const Locale('zh'), profile: profile),
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
              home: ReminiscenceArmAPage(theme: ReminiscenceTheme.all.first),
            ),
          ),
        ),
      ),
    );
  }

  UserProfile profile({String? avoidTopics}) => UserProfile(
        uid: 'synthetic_t49b',
        email: 'synthetic@example.invalid',
        displayName: '陳太',
        arm: ArmAssignment.a,
        // Consent already given, so the first send skips the prompt.
        consent: const ConsentFlags(
          functionalData: true,
          transcriptRetention: true,
        ),
        avoidTopics: avoidTopics,
      );

  Future<String?> sendOneTurn(WidgetTester tester, UserProfile p) async {
    // No connectivity plugin in tests: report Wi-Fi so the send isn't
    // parked in the offline-resend queue.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
    await tester.pumpWidget(harness(p));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // First-visit intro card (FirstIntroOverlay) — dismiss it.
    if (find.text('好，開始').evaluate().isNotEmpty) {
      await tester.tap(find.text('好，開始'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byType(TextField).first, '我細個住喺深水埗。');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded).first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final module = 'm3_reminiscence_w${ReminiscenceTheme.all.first.weekIndex}';
    expect(client.suffixByModule.containsKey(module), isTrue,
        reason: 'turn call made: ${client.suffixByModule.keys}');
    final suffix = client.suffixByModule[module];
    // Leave the page so its timers stop.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 30));
    return suffix;
  }

  testWidgets('avoidTopics set → contextSuffix carries the ⛔ line',
      (tester) async {
    final suffix = await sendOneTurn(tester, profile(avoidTopics: '前夫、賭錢'));
    expect(suffix, isNotNull);
    expect(suffix, contains('$_avoidLine前夫、賭錢'));
    expect(suffix, contains('今週主題'), reason: 'theme lock kept');
  });

  testWidgets('no avoidTopics → no ⛔ line', (tester) async {
    final suffix = await sendOneTurn(tester, profile());
    expect(suffix ?? '', isNot(contains('⛔')));
  });

  testWidgets('empty avoidTopics → no ⛔ line', (tester) async {
    final suffix = await sendOneTurn(tester, profile(avoidTopics: ''));
    expect(suffix ?? '', isNot(contains('⛔')));
  });
}
