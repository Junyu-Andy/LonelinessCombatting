// 1020o 第四节 (4a) — screenshots of the week-1 opening with the scene
// picture, for Junyu.  Not part of CI.
//
//   Phone 360 × 800 at App text 1.30 (特大), 阿珍 and 阿伯, normal and high
//   contrast: as the elder lands on the page — since decisions-log 10/20
//   第 99 条 the first visit opens at the picture — and `_start`, scrolled
//   to the start of the week (the same view).  iPad 820 × 1180 (the
//   600-wide column, 1020l) at 1.06.
//
//   flutter test test_manual/reminiscence_scene_shots_1020o_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1020o-shots/scene/*.png.  Needs the WenQuanYi Zen
// Hei font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc); without SHOTS
// nothing is drawn.  Synthetic data; Hybrid profile (the opening is the
// same in both arms); the fake model is never reached before an answer.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/app/wide_screen_frame.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
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
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_store.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_v2_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1020o-shots/scene';

Future<void> _loadFonts() async {
  final cjk = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!cjk.existsSync()) fail('needs ${cjk.path}');
  final bytes = ByteData.sublistView(cjk.readAsBytesSync());
  for (final family in ['NotoSerifHK', 'NotoSansHK']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons =
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

/// The App theme, with the button labels given the Chinese test font
/// (drawing only).
ThemeData _shotTheme(bool highContrast) {
  final t = highContrast ? AppTheme.highContrast : AppTheme.light;
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
      const LlmRawResponse(text: '');
}

class _FakeMemoryV1 extends MemoryV1Service {
  @override
  Future<void> endSession(String agentId) async {}
}

UserProfile _profile(AgentGenderVariant variant) => UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: ArmAssignment.a,
      armAssignmentMode: 'pilot_designated',
      cohort: 'phase_b',
      w0Date: '2026-10-14',
      ahJanAhBakVariant: variant,
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

Future<void> _pump(WidgetTester tester,
    {required AgentGenderVariant variant,
    required bool highContrast,
    required Size size,
    required double scale}) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = size * 2.0;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  final llm = LlmGateway(client: _NoLlm());
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  await tester.pumpWidget(AppSettingsScope(
    settings: AppSettings(
        locale: const Locale('zh'),
        highContrast: highContrast,
        profile: _profile(variant)),
    child: AuthServiceScope(
      authService: AuthService(available: false),
      child: AnalyticsScope(
        analytics: AnalyticsService(firebaseReady: false)
          ..setEnvironment(arm: 'A'),
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
          memoryV1: _FakeMemoryV1(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _shotTheme(highContrast),
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
              // As app.dart: the iPad column (phones untouched).
              child: WideScreenFrame(enabled: true, child: child!),
            ),
            home: ReminiscenceV2Page(
                theme: ReminiscenceTheme.byIndex(1),
                clock: () => DateTime(2026, 10, 21, 10)),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e, onError: (_, __) {});
    }
  });
  await tester.pumpAndSettle();
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_dir/$name.png'));
}

void main() {
  setUpAll(() {
    SessionCloseHint.claimFirstUse();
    SessionCloseHint.claimLeaveFirstUse();
  });

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    BriefPrV2.store = InMemoryBriefPrStore();
    RemoteFeatureFlags.current = const RemoteFeatureFlags(
        reminiscenceV2Enabled: true, leaveButtonV2Enabled: true);
    ReminiscenceV2Stores.weekOverride = InMemoryReminiscenceWeekStore();
    ReminiscenceV2Stores.chaptersOverride = InMemoryReminiscenceChapterStore();
    ReminiscenceV2Stores.ratingsOverride = InMemoryReminiscenceRatingStore();
    ReminiscenceV2Stores.summaryOverride = InMemoryReminiscenceSummaryWriter();
  });

  tearDown(() {
    RemoteFeatureFlags.resetForTest();
    ReminiscenceV2Stores.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
  });

  for (final variant in AgentGenderVariant.values) {
    final who = variant == AgentGenderVariant.masculine ? 'ah_bak' : 'ah_jan';
    for (final hc in [false, true]) {
      final tag = '${who}_${hc ? 'high_contrast' : 'normal'}_360_x130';
      testWidgets('week 1 opening $tag', (tester) async {
        if (!_shots) return;
        await tester.runAsync(_loadFonts);
        await _pump(tester,
            variant: variant,
            highContrast: hc,
            size: const Size(360, 800),
            scale: AppFontScale.xLarge.multiplier);
        await _shot(tester, 'week1_${tag}_landing');
        // Scroll up to the start of the week: the picture.
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reminiscence_scene_bubble')),
            findsOneWidget);
        await _shot(tester, 'week1_${tag}_start');
      });
    }
  }

  testWidgets('week 1 opening, iPad', (tester) async {
    if (!_shots) return;
    await tester.runAsync(_loadFonts);
    await _pump(tester,
        variant: AgentGenderVariant.masculine,
        highContrast: false,
        size: const Size(820, 1180),
        scale: AppFontScale.standard.multiplier);
    await _shot(tester, 'week1_ah_bak_normal_ipad_820_x106');
  });
}
