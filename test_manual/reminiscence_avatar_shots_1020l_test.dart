// 1020l §一 (4) — screenshots of the 阿伯 avatar for Junyu: the
// 「接著傾 · 同阿伯講舊時」 card (where the big 「珍」 was) next to the
// companion tiles, and the reminiscence week page (switch
// `reminiscenceV2Enabled` on) with 阿伯 in the top bar; each also with the
// pictures missing (then 阿伯's own initial 「伯」).  Three screens:
// phone 360 × 800 at App text 1.06 (標準), the same phone at 1.30 (特大),
// iPad 820 × 1180 at 1.06.  Not part of CI.
//
//   flutter test test_manual/reminiscence_avatar_shots_1020l_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1020l-shots/avatar/*.png.  Needs the WenQuanYi Zen
// Hei font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc) for the Chinese
// text; without SHOTS nothing is drawn.  Synthetic data; nothing is written.
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
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/my_story/data/my_story_progress.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_store.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_v2_page.dart';
import 'package:app_demo/features/today/presentation/widgets/agent_tile_row.dart';
import 'package:app_demo/features/today/presentation/widgets/continue_chat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _dir = '../docs/dev-reports/1020l-shots/avatar';

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

class _Screen {
  const _Screen(this.tag, this.size, this.scale);
  final String tag;
  final Size size;
  final double scale;
}

final _screens = [
  _Screen('phone_360_x106', const Size(360, 800), AppFontScale.standard.multiplier),
  _Screen('phone_360_x130', const Size(360, 800), AppFontScale.xLarge.multiplier),
  _Screen('ipad_820_x106', const Size(820, 1180), AppFontScale.standard.multiplier),
];

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

/// No agent pictures: as if they were missing or broken.
class _NoAgentPicturesBundle extends CachingAssetBundle {
  static bool _isAgentPicture(String key) => key.startsWith('assets/agents/');

  @override
  Future<ByteData> load(String key) => _isAgentPicture(key)
      ? Future<ByteData>.error(FlutterError('no picture: $key'))
      : rootBundle.load(key);

  @override
  Future<ImmutableBuffer> loadBuffer(String key) => _isAgentPicture(key)
      ? Future<ImmutableBuffer>.error(FlutterError('no picture: $key'))
      : rootBundle.loadBuffer(key);
}

UserProfile _profile() => UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: ArmAssignment.a,
      armAssignmentMode: 'pilot_designated',
      cohort: 'phase_b',
      w0Date: '2026-10-14',
      ahJanAhBakVariant: AgentGenderVariant.masculine,
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

Future<void> _pump(WidgetTester tester, _Screen screen, Widget home,
    {required bool noPictures}) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = screen.size * 2.0;
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
  Widget app = MaterialApp(
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
          .copyWith(textScaler: TextScaler.linear(screen.scale)),
      child: child!,
    ),
    home: home,
  );
  if (noPictures) {
    app = DefaultAssetBundle(bundle: _NoAgentPicturesBundle(), child: app);
  }
  await tester.pumpWidget(AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh'), profile: _profile()),
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
          child: app,
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  // Decode the avatar images so they are drawn (missing ones stay missing).
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
    PhaseBConfig.current = const PhaseBConfig();
    BriefPrV2.store = InMemoryBriefPrStore();
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(reminiscenceV2Enabled: true);
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

  for (final screen in _screens) {
    for (final noPictures in [false, true]) {
      final suffix = noPictures ? '_no_picture' : '';

      testWidgets('${screen.tag}: 接著傾 card$suffix', (tester) async {
        if (!_shots) return;
        await tester.runAsync(_loadFonts);
        await _pump(
            tester,
            screen,
            Scaffold(
              appBar: AppBar(title: const Text('傾偈')),
              body: ListView(
                children: [
                  ContinueChatCard(
                      progressReader: MyStoryProgressReader(available: false)),
                  const AgentTileRow(),
                ],
              ),
            ),
            noPictures: noPictures);
        expect(find.text('同阿伯講舊時'), findsOneWidget);
        expect(find.textContaining('珍'), findsNothing);
        await _shot(tester, 'card_${screen.tag}$suffix');
      });

      testWidgets('${screen.tag}: 講舊時 week page$suffix', (tester) async {
        if (!_shots) return;
        await tester.runAsync(_loadFonts);
        await _pump(
            tester,
            screen,
            ReminiscenceV2Page(
                theme: ReminiscenceTheme.byIndex(1),
                clock: () => DateTime(2026, 10, 21, 10)),
            noPictures: noPictures);
        expect(find.textContaining('珍'), findsNothing);
        await _shot(tester, 'week_page_${screen.tag}$suffix');
      });
    }
  }
}
