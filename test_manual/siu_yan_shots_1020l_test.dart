// 1020l §一 (2)(3) — draft screenshots of the 小欣 chat window for Junyu:
// the notes now under the app bar (the S9 first-use note, the moderate
// safety notice) with the input bar / answer buttons visible, and the Q1
// answer buttons as one even grid.  Phone 360 × 800 at App text 1.06 and
// 1.30 (特大), 320 × 700 at 1.30, iPad 820 × 1180 at 1.06.  Switch
// `checkInChatV2Enabled` on.  Default build = Hybrid; the layout is the
// same in the rule arm.  Not part of CI.
//
//   flutter test test_manual/siu_yan_shots_1020l_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1020l-shots/siuyan/*.png.  Needs the WenQuanYi
// Zen Hei font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc) for the
// Chinese text; without SHOTS nothing is drawn.  Synthetic data; nothing
// is written.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/memory/memory_v1_service.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/safety/safety_copy.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/context/data/check_in_response_store.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1020l-shots/siuyan';

Future<void> _loadFonts() async {
  final cjk = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!cjk.existsSync()) fail('needs ${cjk.path}');
  final bytes = ByteData.sublistView(cjk.readAsBytesSync());
  for (final family in ['NotoSerifHK', 'NotoSansHK']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

/// The App theme, with the button labels given the Chinese test font: the
/// App's button styles name no font (the phone's own font is used), which
/// the test renderer draws as boxes.  Drawing only; nothing else changes.
ThemeData _shotTheme() {
  final t = AppTheme.light;
  ButtonStyle? withFont(ButtonStyle? s) {
    final ts = s?.textStyle?.resolve(const {});
    if (s == null || ts == null) return s;
    return s.copyWith(
        textStyle:
            WidgetStatePropertyAll(ts.copyWith(fontFamily: 'NotoSansHK')));
  }

  return t.copyWith(
    filledButtonTheme:
        FilledButtonThemeData(style: withFont(t.filledButtonTheme.style)),
    elevatedButtonTheme:
        ElevatedButtonThemeData(style: withFont(t.elevatedButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: withFont(t.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: withFont(t.textButtonTheme.style)),
  );
}

class _FakeLlm implements LlmClient {
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
    if ((contextSuffix ?? '').contains('[開場·check-in 已做]')) {
      return const LlmRawResponse(text: '今日想傾咩都得，我喺度。');
    }
    return const LlmRawResponse(text: '好呀，再同我講多啲。');
  }
}

class _FakeMemoryV1 extends MemoryV1Service {
  @override
  Future<void> endSession(String agentId) async {}
}

UserProfile _profile() => UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: ArmAssignment.a,
      armAssignmentMode: 'pilot_designated',
      cohort: 'phase_b',
      w0Date: '2026-10-14',
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

Future<void> _open(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required bool doneToday,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  // The status stream: no events (real async would report the missing
  // plugin while the fonts load).
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    (call) async => null,
  );
  final llm = LlmGateway(client: _FakeLlm());
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(AppSettingsScope(
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
              memory: memory, firestoreAvailable: false),
          agentContext: agentContext,
          sharedContext: sharedContext,
          personaResolver: PersonaResolver(
              agentContext: agentContext, sharedContext: sharedContext),
          referralRouting: ReferralRoutingService(sharedContext: sharedContext),
          handoffExecutor: HandoffExecutor(sharedContext: sharedContext),
          agentGreeting: AgentGreetingService(llm),
          memoryV1: _FakeMemoryV1(),
          child: MaterialApp(
            navigatorKey: navKey,
            debugShowCheckedModeBanner: false,
            theme: _shotTheme(),
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  navKey.currentState!.push(MaterialPageRoute<void>(
    builder: (_) => SiuYanChatPage(
      checkedInToday: (_) async => doneToday,
      latestMoodToday: (_) async => null,
      responseStore: InMemoryCheckInResponseStore(),
      replyHistory: InMemoryRuleReplyHistoryStore(),
      clock: () => DateTime(2026, 10, 21, 9, 30),
      onOpenActionPlan: (_) async {},
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_dir/$name.png'));
}

const _sizes = [
  (size: Size(360, 800), scale: 1.06, name: 'phone360_x106'),
  (size: Size(360, 800), scale: 1.30, name: 'phone360_x130'),
  (size: Size(320, 700), scale: 1.30, name: 'phone320_x130'),
  (size: Size(820, 1180), scale: 1.06, name: 'ipad820_x106'),
];

void main() {
  setUpAll(() {
    SafetyCopy.inject(
        acks: Map<String, dynamic>.from(jsonDecode(
            File(SafetyCopy.acksAsset).readAsStringSync()) as Map));
  });

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    BriefPrV2.store = InMemoryBriefPrStore();
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(checkInChatV2Enabled: true);
  });
  tearDown(RemoteFeatureFlags.resetForTest);

  for (final s in _sizes) {
    testWidgets('Q1 buttons + S9 first-use note, ${s.name}', (tester) async {
      if (!_shots) return;
      await tester.runAsync(_loadFonts);
      SessionCloseHint.resetForTest();
      await _open(tester, size: s.size, scale: s.scale, doneToday: false);
      expect(find.byKey(const ValueKey('top_notice_session_close_first_use')),
          findsOneWidget);
      await _shot(tester, 'q1_note_${s.name}');
      // Let the note's 6 s timer run out before the page goes.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    });

    testWidgets('moderate safety notice, ${s.name}', (tester) async {
      if (!_shots) return;
      await tester.runAsync(_loadFonts);
      SessionCloseHint.resetForTest();
      SessionCloseHint.claimFirstUse();
      await _open(tester, size: s.size, scale: s.scale, doneToday: true);
      await tester.enterText(find.byType(TextField), '冇人理我');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('top_notice_moderate_safety')),
          findsOneWidget);
      await _shot(tester, 'moderate_${s.name}');
    });
  }
}
