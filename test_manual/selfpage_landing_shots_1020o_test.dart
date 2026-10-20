// 1020o — screenshots for Junyu.  Not part of CI.
//
//   第一节: 自己 → 「我嘅人生小篇章」 entry, and the chapters page (one
//           ready chapter, and empty) in the normal and the high-contrast
//           theme: phone 360 × 800, App text 1.06.
//   第四节: the 人生點滴 landing page for 阿珍 and 阿伯, normal and high
//           contrast, App text 1.06 and 1.30 (特大), top of the page and
//           scrolled to the end; the theme pictures are not in the repo
//           yet, so the cards show the number tile.
//
//   flutter test test_manual/selfpage_landing_shots_1020o_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1020o-shots/selfpage/*.png and
// docs/dev-reports/1020o-shots/landing/*.png.  Needs the WenQuanYi Zen Hei
// font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc) for the Chinese
// text; without SHOTS nothing is drawn.  Synthetic data; Hybrid profile
// (the 反思傾偈 card at the end of the landing is Hybrid only).
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
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
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_store.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_chapters_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_landing.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _selfDir = '../docs/dev-reports/1020o-shots/selfpage';
const _landingDir = '../docs/dev-reports/1020o-shots/landing';

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

/// The App theme, with the button labels given the Chinese test font: the
/// App's button styles name no font (the phone's own font is used), which
/// the test renderer draws as boxes.  Drawing only; nothing else changes.
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

Future<void> _pump(WidgetTester tester, Widget home,
    {required AgentGenderVariant variant,
    required bool highContrast,
    required double scale}) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(720, 1600);
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
    settings: AppSettings(locale: const Locale('zh'), profile: _profile(variant)),
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
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: home,
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String path) async {
  // Decode the pictures so they are drawn (missing ones stay missing).
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e, onError: (_, __) {});
    }
  });
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(path));
}

void _readyChapters(InMemoryReminiscenceChapterStore store) {
  store.serverWrite('u1', 1, {
    'weekIndex': 1,
    'source': 'hybrid',
    'status': 'ready',
    'finalText': '我喺深水埗北河街大，一家人住板間房。阿嫲成日煲綠豆沙俾我飲，'
        '夏天傍晚成條街都係人，細路喺街度玩到天黑先返屋企。',
    'version': 1,
    'requestId': 'r1',
  });
  store.serverWrite('u1', 2, {
    'weekIndex': 2,
    'source': 'hybrid',
    'status': 'ready',
    'finalText': '十六歲入工廠做車衣，朝八晚八。師傅好惡，但係教識我做嘢要有交帶。',
    'version': 1,
    'requestId': 'r2',
  });
}

void main() {
  late InMemoryReminiscenceChapterStore chapters;

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    PhaseBConfig.current = const PhaseBConfig();
    BriefPrV2.store = InMemoryBriefPrStore();
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(reminiscenceV2Enabled: true);
    chapters = InMemoryReminiscenceChapterStore();
    ReminiscenceV2Stores.weekOverride = InMemoryReminiscenceWeekStore();
    ReminiscenceV2Stores.chaptersOverride = chapters;
    ReminiscenceV2Stores.ratingsOverride = InMemoryReminiscenceRatingStore();
    ReminiscenceV2Stores.summaryOverride = InMemoryReminiscenceSummaryWriter();
  });

  tearDown(() {
    RemoteFeatureFlags.resetForTest();
    ReminiscenceV2Stores.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
  });

  final x106 = AppFontScale.standard.multiplier;
  final x130 = AppFontScale.xLarge.multiplier;

  // 第一节 ------------------------------------------------------------------

  testWidgets('自己 page: 我嘅人生小篇章 entry', (tester) async {
    if (!_shots) return;
    await tester.runAsync(_loadFonts);
    await _pump(tester, const SettingsPage(),
        variant: AgentGenderVariant.masculine,
        highContrast: false,
        scale: x106);
    await tester.ensureVisible(find.byKey(const Key('me_life_chapters_entry')));
    await tester.pumpAndSettle();
    await _shot(tester, '$_selfDir/me_entry_360_x106.png');
  });

  for (final hc in [false, true]) {
    final tag = hc ? 'high_contrast' : 'normal';
    testWidgets('小篇章 page, two chapters, $tag', (tester) async {
      if (!_shots) return;
      await tester.runAsync(_loadFonts);
      _readyChapters(chapters);
      await _pump(tester, const ReminiscenceChaptersPage(),
          variant: AgentGenderVariant.masculine, highContrast: hc, scale: x106);
      expect(find.text('第 1 章：童年同屋企'), findsOneWidget);
      await _shot(tester, '$_selfDir/chapters_${tag}_360_x106.png');
    });

    testWidgets('小篇章 page, empty, $tag', (tester) async {
      if (!_shots) return;
      await tester.runAsync(_loadFonts);
      await _pump(tester, const ReminiscenceChaptersPage(),
          variant: AgentGenderVariant.masculine, highContrast: hc, scale: x106);
      await _shot(tester, '$_selfDir/chapters_empty_${tag}_360_x106.png');
    });
  }

  // 第四节 ------------------------------------------------------------------

  for (final variant in AgentGenderVariant.values) {
    final who = variant == AgentGenderVariant.masculine ? 'ah_bak' : 'ah_jan';
    for (final hc in [false, true]) {
      for (final scale in [x106, x130]) {
        final tag =
            '${who}_${hc ? 'high_contrast' : 'normal'}_360_x${(scale * 100).round()}';
        testWidgets('landing $tag', (tester) async {
          if (!_shots) return;
          await tester.runAsync(_loadFonts);
          chapters.serverWrite('u1', 1, {
            'weekIndex': 1,
            'source': 'hybrid',
            'status': 'ready',
            'finalText': '我喺深水埗北河街大。',
            'version': 1,
            'requestId': 'r1',
          });
          await _pump(tester, const ReminiscenceLandingPage(),
              variant: variant, highContrast: hc, scale: scale);
          await _shot(tester, '$_landingDir/${tag}_top.png');
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -3000));
          await tester.pumpAndSettle();
          await _shot(tester, '$_landingDir/${tag}_end.png');
        });
      }
    }
  }
}
