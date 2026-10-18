// T49e-3 — 小欣签到页、阿珍／阿伯回忆页：每种结束（收尾按钮、返回、切换陪伴者、
// 30 分钟超时）都恰好一次把对话交给服务器整理记忆（memoryEndSession）。
//
// The count depends on the build:
//   PHASE_B=true                  → Hybrid profile → exactly 1 per session
//   PHASE_B=true FORCE_ARM=B      → rule arm       → 0
//   default (Phase A) build       → memory v1 off  → 0 (client fold path)
//
//   flutter test --dart-define=PHASE_B=true test/memory_handover_pages_test.dart
//   flutter test --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
//     test/memory_handover_pages_test.dart
//
// Synthetic data only: no Firebase (every service runs with available false)
// and fake LLM / memory v1 clients.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/memory/memory_v1_service.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_a.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _armB = String.fromEnvironment('FORCE_ARM') == 'B';

/// One hand-over per finished session in a Phase B Hybrid build; none for
/// the rule arm, none in a Phase A build (memory v1 off there).
final int _perSession = FeatureFlags.phaseB && !_armB ? 1 : 0;

class _FakeMemoryV1 extends MemoryV1Service {
  final ended = <String>[];

  @override
  Future<void> endSession(String agentId) async => ended.add(agentId);
}

class _FakeLlm implements LlmClient {
  final modules = <String>[];

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
    modules.add(moduleId);
    return const LlmRawResponse(text: '好呀，同我講多啲。');
  }
}

UserProfile _profile() => UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: _armB ? ArmAssignment.b : ArmAssignment.a,
      armAssignmentMode: 'pilot_designated',
      consent: const ConsentFlags(
        functionalData: true,
        transcriptRetention: true,
      ),
      firstIntroSeen: {
        'siu_yan': DateTime(2026, 10, 1),
        'ah_jan_ah_bak': DateTime(2026, 10, 1),
        'tung_tung': DateTime(2026, 10, 1),
      },
    );

void main() {
  late _FakeMemoryV1 mem;
  late _FakeLlm llmClient;
  late GlobalKey<NavigatorState> navKey;
  late PhaseBConfig savedConfig;
  late BriefPrStore savedStore;

  // The one-time 「今日傾到呢度」 snackbar would cover the send button.
  setUpAll(SessionCloseHint.claimFirstUse);

  setUp(() {
    mem = _FakeMemoryV1();
    llmClient = _FakeLlm();
    navKey = GlobalKey<NavigatorState>();
    ChatSessionRecorder.resetProcessStateForTest();
    // Session v2 on (the Phase B setting): 30-minute idle clock, S9 close
    // button, switch_agent; the Brief PR scheduler writes to memory only.
    savedConfig = PhaseBConfig.current;
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    savedStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
  });

  tearDown(() {
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedStore;
    ChatSessionRecorder.resetProcessStateForTest();
  });

  Widget harness() {
    final llm = LlmGateway(client: llmClient);
    final agentContext = AgentContextService(available: false);
    final sharedContext = SharedContextService(available: false);
    final memory = MemoryStore(available: false);
    final state = DistressState();
    return AppSettingsScope(
      settings: AppSettings(locale: const Locale('zh'), profile: _profile()),
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
            memoryV1: mem,
            child: MaterialApp(
              navigatorKey: navKey,
              locale: const Locale('zh'),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, Widget page) async {
    // No connectivity plugin in tests: report Wi-Fi so sends go through.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pumpAndSettle();
  }

  Future<void> say(WidgetTester tester, String text) async {
    final before = llmClient.modules.length;
    await tester.enterText(find.byType(TextField).first, text);
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded).first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(llmClient.modules.length, before + 1,
        reason: 'the message reached the (fake) model');
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> idleOut(WidgetTester tester) async {
    await tester.pump(const Duration(minutes: 31));
    await tester.pumpAndSettle();
  }

  /// Another companion's session starts: v2 closes this one as
  /// `switch_agent` and calls the page's `onSwitchedAway`.
  Future<void> switchAway(WidgetTester tester) async {
    final other = ChatSessionRecorder(
      uid: 'u1',
      agentId: 'tung_tung',
      moduleId: 'm4_tung_tung',
      analytics: AnalyticsService(firebaseReady: false),
      available: false,
      rules: const SessionRules(v2: true, idleTimeoutMin: 30),
    );
    await other.ensureStarted();
    await tester.pumpAndSettle();
    await other.end(SessionEndReason.back);
    other.dispose();
  }

  void expectHandovers(String agentId, int sessions) {
    expect(mem.ended, List.filled(sessions * _perSession, agentId),
        reason: 'memoryEndSession($agentId) once per finished session');
    expect(llmClient.modules, isNot(contains('rolling_summary_fold')),
        reason: 'no client-side fold call in these builds');
  }

  group('小欣签到页 (siu_yan)', () {
    Widget page() => const CheckInArmA(initialMoodValue: 4);

    testWidgets('(a) 1 message, then back → once', (tester) async {
      await open(tester, page());
      await say(tester, '今日去咗公園行吓。');
      await back(tester);
      expectHandovers('siu_yan', 1);
    });

    testWidgets('(a2) 1 message, then S9 close button → once', (tester) async {
      await open(tester, page());
      await say(tester, '今日去咗公園行吓。');
      await tester.tap(find.byKey(const Key('session_close_button')));
      await tester.pumpAndSettle();
      expectHandovers('siu_yan', 1);
    });

    testWidgets('(b) idle timeout → once; leaving afterwards adds none',
        (tester) async {
      await open(tester, page());
      await say(tester, '今日去咗公園行吓。');
      await idleOut(tester);
      expectHandovers('siu_yan', 1);
      await back(tester);
      expectHandovers('siu_yan', 1);
    });

    testWidgets('(b2) idle, then a new message and back → once per session',
        (tester) async {
      await open(tester, page());
      await say(tester, '今日去咗公園行吓。');
      await idleOut(tester);
      await say(tester, '返到屋企喇。');
      await back(tester);
      expectHandovers('siu_yan', 2);
    });

    testWidgets('(c) switch companion → once; leaving afterwards adds none',
        (tester) async {
      await open(tester, page());
      await say(tester, '今日去咗公園行吓。');
      await switchAway(tester);
      expectHandovers('siu_yan', 1);
      await back(tester);
      expectHandovers('siu_yan', 1);
    });

    testWidgets('(d) no message, then back → once', (tester) async {
      await open(tester, page());
      await back(tester);
      expectHandovers('siu_yan', 1);
    });
  });

  group('阿珍／阿伯回忆页 (ah_jan_ah_bak)', () {
    Widget page() => ReminiscenceArmAPage(theme: ReminiscenceTheme.all.first);

    Future<void> openSummary(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('session_close_button')));
      await tester.pumpAndSettle();
      expect(find.text('儲存'), findsOneWidget);
    }

    testWidgets('(a) S9 → summary → 儲存 → once', (tester) async {
      await open(tester, page());
      await say(tester, '細個住喺深水埗。');
      await openSummary(tester);
      expectHandovers('ah_jan_ah_bak', 0);
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();
      expectHandovers('ah_jan_ah_bak', 1);
    });

    testWidgets('(b) back → once', (tester) async {
      await open(tester, page());
      await say(tester, '細個住喺深水埗。');
      await back(tester);
      expectHandovers('ah_jan_ah_bak', 1);
    });

    testWidgets('(c) idle timeout → once; leaving afterwards adds none',
        (tester) async {
      await open(tester, page());
      await say(tester, '細個住喺深水埗。');
      await idleOut(tester);
      expectHandovers('ah_jan_ah_bak', 1);
      await back(tester);
      expectHandovers('ah_jan_ah_bak', 1);
    });

    testWidgets('(d) switch companion → once; leaving afterwards adds none',
        (tester) async {
      await open(tester, page());
      await say(tester, '細個住喺深水埗。');
      await switchAway(tester);
      expectHandovers('ah_jan_ah_bak', 1);
      await back(tester);
      expectHandovers('ah_jan_ah_bak', 1);
    });

    testWidgets('(e) idle while the summary screen is up → none; 儲存 → once',
        (tester) async {
      await open(tester, page());
      await say(tester, '細個住喺深水埗。');
      await openSummary(tester);
      await idleOut(tester);
      expectHandovers('ah_jan_ah_bak', 0);
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();
      expectHandovers('ah_jan_ah_bak', 1);
    });

    testWidgets('(f) back from the summary screen without 儲存 → once',
        (tester) async {
      await open(tester, page());
      await say(tester, '細個住喺深水埗。');
      await openSummary(tester);
      await back(tester);
      expectHandovers('ah_jan_ah_bak', 1);
    });
  });
}
