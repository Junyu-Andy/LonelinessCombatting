// 1020l §二 (2) — screenshots for Junyu: the home page and 小欣's chat window
// on an iPad, upright (820 × 1180) and sideways (1180 × 820), before (switch
// off) and after (switch `wideScreenFrameEnabled` on); and the home page on a
// 360 × 800 phone at 字號 1.06 and 1.30 (特大) with the switch on, checked
// pixel for pixel against the same page with no frame in the tree at all.
// Not part of CI.
//
//   flutter test test_manual/wide_screen_shots_1020l_test.dart \
//     --dart-define=SHOTS=true --update-goldens
//
// Writes docs/dev-reports/1020l-shots/ipad/*.png.  Needs the WenQuanYi Zen
// Hei font (/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc) for the Chinese
// text; without SHOTS nothing is drawn.  The arm follows the build
// (FORCE_ARM=B for the rule arm).  Synthetic data; nothing is written.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/app/main_shell.dart';
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
import 'package:app_demo/features/context/data/check_in_response_store.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:app_demo/features/today/data/mood_row_store.dart';
import 'package:app_demo/features/today/presentation/home_v2_scope.dart';
import 'package:app_demo/features/today/presentation/widgets/mood_row_v2.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _shots = bool.fromEnvironment('SHOTS');
const _armB = String.fromEnvironment('FORCE_ARM') == 'B';
const _dir = '../docs/dev-reports/1020l-shots/ipad';

const _portrait = Size(820, 1180);
const _landscape = Size(1180, 820);
const _phone = Size(360, 800);

Future<void> _loadFonts() async {
  final cjk = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
  if (!cjk.existsSync()) fail('needs ${cjk.path}');
  final bytes = ByteData.sublistView(cjk.readAsBytesSync());
  for (final family in ['NotoSerifHK', 'NotoSansHK']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  // The mood faces are emoji; without this font they draw as boxes.
  final emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  if (emoji.existsSync()) {
    await (FontLoader('ShotEmoji')
          ..addFont(
              Future.value(ByteData.sublistView(emoji.readAsBytesSync()))))
        .load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

/// The App theme, with the button labels given the Chinese test font: the
/// App's button styles name no font (the phone's own font is used), which
/// the test renderer draws as boxes; the emoji font is the fallback for the
/// mood faces.  Drawing only; nothing else changes.
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
    textTheme: t.textTheme.apply(fontFamilyFallback: const ['ShotEmoji']),
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

class _Llm implements LlmClient {
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
      const LlmRawResponse(text: '好呀，同我講多啲。');
}

UserProfile _profile() => UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: _armB ? ArmAssignment.b : ArmAssignment.a,
      armAssignmentMode: 'pilot_designated',
      cohort: 'pilot',
      w0Date: '2026-10-14',
      hasCompletedIntake: true,
      ahJanAhBakVariant: AgentGenderVariant.feminine,
      consent: const ConsentFlags(
          functionalData: true, transcriptRetention: true),
      interests: const ['yum_cha', 'mahjong'],
      firstIntroSeen: {
        'siu_yan': DateTime(2026, 10, 1),
        'ah_jan_ah_bak': DateTime(2026, 10, 1),
        'tung_tung': DateTime(2026, 10, 1),
      },
    );

/// The App's scopes around the real bottom-navigation shell, with the
/// same MaterialApp.builder shape as app.dart: the text scale, then the
/// frame ([frame] false = no frame in the tree at all, as before 1020l).
Widget _app(GlobalKey<NavigatorState> nav,
    {required double scale, bool frame = true}) {
  final llm = LlmGateway(client: _Llm());
  final memory = MemoryStore(available: false);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
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
              memory: memory, firestoreAvailable: false),
          agentContext: agentContext,
          sharedContext: sharedContext,
          personaResolver: PersonaResolver(
              agentContext: agentContext, sharedContext: sharedContext),
          referralRouting: ReferralRoutingService(sharedContext: sharedContext),
          handoffExecutor: HandoffExecutor(sharedContext: sharedContext),
          agentGreeting: AgentGreetingService(llm),
          memoryV1: const MemoryV1Service(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: nav,
            theme: _shotTheme(),
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) {
              final inner = child ?? const SizedBox.shrink();
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: frame
                    ? WideScreenFrame(
                        enabled:
                            RemoteFeatureFlags.current.wideScreenFrameEnabled,
                        child: inner)
                    : inner,
              );
            },
            home: HomeV2Scope(
              checkedInToday: (_) async => false,
              daysSinceLastCheckIn: (_) async => 1,
              moodStore: InMemoryMoodRowStore(),
              clock: () => DateTime(2026, 10, 21, 10, 0),
              child: const MainShell(),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Size size,
    {required bool on,
    double scale = 1.06,
    bool frame = true,
    GlobalKey<NavigatorState>? nav}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  tester.binding.defaultBinaryMessenger.setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    MockStreamHandler.inline(onListen: (_, sink) => sink.success(['wifi'])),
  );
  // The 10/21 build's page switches, and the one under test.
  RemoteFeatureFlags.current = RemoteFeatureFlags(
    homeLayoutV2Enabled: true,
    moodRowV2Enabled: true,
    checkInChatV2Enabled: true,
    wideScreenFrameEnabled: on,
  );
  MoodRowV2.resetForTest();
  await tester.pumpWidget(Container());
  await tester.pumpWidget(
      _app(nav ?? GlobalKey<NavigatorState>(), scale: scale, frame: frame));
  await tester.pump(const Duration(seconds: 1));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // Decode the pictures so they are drawn.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dir/$name.png'));

Future<Uint8List> _pixels(WidgetTester tester) async {
  final element = find.byType(MaterialApp).evaluate().single;
  final bytes = await tester.runAsync(() async {
    final image = await captureImage(element);
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

void main() {
  setUpAll(SessionCloseHint.claimFirstUse);
  late BriefPrStore savedStore;
  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    PhaseBConfig.current = const PhaseBConfig(
        sessionBriefPrV2Enabled: true, weeklyScheduleV2Enabled: true);
    savedStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
  });
  tearDown(() {
    RemoteFeatureFlags.resetForTest();
    PhaseBConfig.current = const PhaseBConfig();
    BriefPrV2.store = savedStore;
    ChatSessionRecorder.resetProcessStateForTest();
    MoodRowV2.resetForTest();
  });

  for (final (size, tag) in const [
    (_portrait, 'portrait'),
    (_landscape, 'landscape'),
  ]) {
    testWidgets('iPad $tag: home before / after', (tester) async {
      if (!_shots) return;
      await tester.runAsync(_loadFonts);
      await _pump(tester, size, on: false);
      expect(find.byKey(WideScreenFrame.columnKey), findsNothing);
      await _shot(tester, 'ipad_${tag}_home_before');
      await _pump(tester, size, on: true);
      expect(tester.getSize(find.byKey(WideScreenFrame.columnKey)).width, 600);
      await _shot(tester, 'ipad_${tag}_home');
    });

    testWidgets('iPad $tag: 小欣 chat window', (tester) async {
      if (!_shots) return;
      await tester.runAsync(_loadFonts);
      final nav = GlobalKey<NavigatorState>();
      await _pump(tester, size, on: true, nav: nav);
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => SiuYanChatPage(
                checkedInToday: (_) async => false,
                latestMoodToday: (_) async => null,
                responseStore: InMemoryCheckInResponseStore(),
                replyHistory: InMemoryRuleReplyHistoryStore(),
                onOpenActionPlan: (_) async {},
              )));
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      for (final key in ['Q1_not_good', 'Q2_a_little']) {
        final f = find.byKey(ValueKey('check_in_answer_$key'));
        if (f.evaluate().isEmpty) break;
        await tester.tap(f);
        await tester.pump(const Duration(seconds: 1));
        await _settle(tester);
      }
      expect(tester.getSize(find.byType(SiuYanChatPage)).width, 600);
      await _shot(tester, 'ipad_${tag}_chat');
    });
  }

  for (final (scale, tag) in const [(1.06, 'x106'), (1.30, 'x130')]) {
    testWidgets('phone 360×800 字號 $scale: home, no change', (tester) async {
      if (!_shots) return;
      await tester.runAsync(_loadFonts);
      await _pump(tester, _phone, on: true, scale: scale, frame: false);
      final before = await _pixels(tester);
      await _pump(tester, _phone, on: true, scale: scale);
      expect(find.byType(WideScreenFrame), findsOneWidget);
      expect(find.byKey(WideScreenFrame.columnKey), findsNothing);
      expect(await _pixels(tester), before,
          reason: 'with the switch on, the phone is pixel for pixel the same '
              'as with no frame at all');
      await _shot(tester, 'phone_360x800_${tag}_home');
    });
  }
}
