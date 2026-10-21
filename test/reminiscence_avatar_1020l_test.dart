// 1020l §一 (4) — the 阿珍／阿伯 avatar follows the elder's own choice.
//
// The field report: an elder who chose 阿伯 saw a big 「珍」 in the round
// avatar on the left of 「接著傾 · 同阿伯講舊時」 (the continue-chatting
// card that opens 講舊時).  That card drew a fixed 「珍」 for 阿珍／阿伯.
// Now every avatar on the way into and inside the reminiscence pages is
// the chosen companion's picture, and when the picture cannot load, that
// companion's own initial (阿伯 → 伯, 阿珍 → 珍; never the shared 「阿」).
//
// Checked here, for 阿伯 and for 阿珍, on both arms the build can reach:
//   - the continue-chatting card (picture, name; follows a later switch);
//   - the landing, the old week pages (switch `reminiscenceV2Enabled` off:
//     arm A / arm B page by arm) and the v2 week page and 我嘅人生小篇章
//     (switch on): the top-bar avatar is the chosen companion's picture,
//     no 「珍」 anywhere for 阿伯; the bar follows a later switch;
//   - the first-intro card on the reminiscence page;
//   - picture missing (a bundle with no agent pictures): 伯 / 珍;
//   - the cross-referral card and the profile page (same pattern).
//
//   flutter test test/reminiscence_avatar_1020l_test.dart
//   flutter test --dart-define=PHASE_B=true test/reminiscence_avatar_1020l_test.dart
//   flutter test --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
//     test/reminiscence_avatar_1020l_test.dart
//
// Synthetic data only; no Firebase; fake model (the rule arm fails the
// test if it reaches the model).
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/agent_avatar.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/agents/companion_app_bar.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/cross_referral/referral_suggestion_card.dart';
import 'package:app_demo/core/cross_referral/triggers_config.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
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
import 'package:app_demo/features/agent_profile/controller/agent_profile_controller.dart';
import 'package:app_demo/features/agent_profile/ui/profile_header.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/my_story/data/my_story_progress.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_copy.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_store.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_chapters_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_landing.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_v2_page.dart';
import 'package:app_demo/features/today/presentation/widgets/continue_chat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _forced = String.fromEnvironment('FORCE_ARM');

/// The rule arm is reachable only in a Phase B build (profile arm B).
final bool _ruleTestable = FeatureFlags.phaseB && _forced != 'A';

/// Everybody is Hybrid in a Phase A build; Phase B needs profile arm A.
final bool _hybridTestable = !FeatureFlags.phaseB || _forced != 'B';

final List<ArmAssignment> _arms = [
  if (_hybridTestable) ArmAssignment.a,
  if (_ruleTestable) ArmAssignment.b,
];

const _janAsset = 'assets/agents/ah_jan_avatar.png';
const _bakAsset = 'assets/agents/ah_bak_avatar.png';

/// Fake model.  The rule arm must never get here.
class _FakeLlm implements LlmClient {
  _FakeLlm({required this.forbid});
  final bool forbid;
  final calls = <String>[];

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
    calls.add(moduleId);
    if (forbid) throw TestFailure('rule arm called the LLM ($moduleId)');
    return const LlmRawResponse(text: '好呀，慢慢講。');
  }
}

class _FakeMemoryV1 extends MemoryV1Service {
  @override
  Future<void> endSession(String agentId) async {}
}

/// An asset bundle without the agent pictures: every `assets/agents/`
/// file fails to load (as a missing or broken picture would), the rest
/// comes from the real bundle.
class _NoAgentPicturesBundle extends CachingAssetBundle {
  static bool _isAgentPicture(String key) => key.startsWith('assets/agents/');

  @override
  Future<ByteData> load(String key) {
    if (_isAgentPicture(key)) {
      return Future<ByteData>.error(FlutterError('no picture: $key'));
    }
    return rootBundle.load(key);
  }

  @override
  Future<ImmutableBuffer> loadBuffer(String key) {
    if (_isAgentPicture(key)) {
      return Future<ImmutableBuffer>.error(FlutterError('no picture: $key'));
    }
    return rootBundle.loadBuffer(key);
  }
}

UserProfile _profile(ArmAssignment arm, AgentGenderVariant variant,
        {bool introSeen = true}) =>
    UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: arm,
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
        if (introSeen) 'ah_jan_ah_bak': DateTime(2026, 10, 1),
        'tung_tung': DateTime(2026, 10, 1),
      },
    );

class _Run {
  _Run(this.arm, this.variant, {this.introSeen = true, this.noPictures = false});
  final ArmAssignment arm;
  final AgentGenderVariant variant;
  final bool introSeen;
  final bool noPictures;
  late final _FakeLlm llm = _FakeLlm(forbid: arm == ArmAssignment.b);
  late final AppSettings settings = AppSettings(
      locale: const Locale('zh'),
      profile: _profile(arm, variant, introSeen: introSeen));
  final navKey = GlobalKey<NavigatorState>();
  final chapters = InMemoryReminiscenceChapterStore();

  bool get rule => arm == ArmAssignment.b;
  bool get bak => variant == AgentGenderVariant.masculine;

  void install() {
    ReminiscenceV2Stores.weekOverride = InMemoryReminiscenceWeekStore();
    ReminiscenceV2Stores.chaptersOverride = chapters;
    ReminiscenceV2Stores.ratingsOverride = InMemoryReminiscenceRatingStore();
    ReminiscenceV2Stores.summaryOverride = InMemoryReminiscenceSummaryWriter();
  }

  /// Switch 阿珍 ↔ 阿伯 the way the profile page does ([back]: to the
  /// run's own choice again).
  void switchCompanion({bool back = false}) {
    final other =
        bak ? AgentGenderVariant.feminine : AgentGenderVariant.masculine;
    settings.profile = settings.profile!
        .copyWith(ahJanAhBakVariant: back ? variant : other);
  }
}

Widget _harness(_Run run, Widget home) {
  final llm = LlmGateway(client: run.llm);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  Widget app = MaterialApp(
    navigatorKey: run.navKey,
    locale: const Locale('zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
  if (run.noPictures) {
    app = DefaultAssetBundle(bundle: _NoAgentPicturesBundle(), child: app);
  }
  return AppSettingsScope(
    settings: run.settings,
    child: AuthServiceScope(
      authService: AuthService(available: false),
      child: AnalyticsScope(
        analytics: AnalyticsService(firebaseReady: false)
          ..setEnvironment(arm: run.rule ? 'B' : 'A'),
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
  );
}

Future<void> _boot(WidgetTester tester, _Run run, Widget home) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 2400);
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  run.install();
  await tester.pumpWidget(_harness(run, home));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder _anyText(String s) => find.textContaining(s, findRichText: true);

Finder _picture(String asset) => find.byWidgetPredicate((w) =>
    w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == asset);

/// The chosen companion everywhere on screen: its picture, its name; for
/// 阿伯 no 「珍」 at all (and no 阿珍 picture), for 阿珍 no 阿伯.
void _expectCompanion(WidgetTester tester, _Run run, {String? where}) {
  final reason = where ?? '';
  final mine = run.bak ? _bakAsset : _janAsset;
  final other = run.bak ? _janAsset : _bakAsset;
  expect(_picture(mine), findsWidgets, reason: '$reason: own picture');
  expect(_picture(other), findsNothing, reason: '$reason: other picture');
  if (run.bak) {
    expect(_anyText('珍'), findsNothing, reason: '$reason: no 「珍」');
  } else {
    expect(_anyText('阿伯'), findsNothing, reason: '$reason: no 阿伯');
  }
  for (final a in tester.widgetList<AgentAvatar>(find.byType(AgentAvatar))) {
    if (a.agent.id != AgentRegistry.ahJanAhBakId) continue;
    expect(a.selectedVariant, run.variant, reason: '$reason: avatar variant');
  }
}

/// The top bar of a reminiscence page: avatar + the chosen name.
void _expectBar(WidgetTester tester, _Run run, {required String where}) {
  final title = find.byType(CompanionTitle);
  expect(title, findsWidgets, reason: where);
  expect(
      find.descendant(
          of: title.first, matching: _picture(run.bak ? _bakAsset : _janAsset)),
      findsOneWidget,
      reason: '$where: bar picture');
  expect(
      tester.widget<Text>(find.byKey(const Key('companion_title'))).data,
      run.bak ? '阿伯' : '阿珍',
      reason: '$where: bar name');
}

void main() {
  late PhaseBConfig savedConfig;
  late BriefPrStore savedBriefStore;
  late RemoteFeatureFlags savedFlags;

  setUpAll(() {
    SessionCloseHint.claimFirstUse();
    SessionCloseHint.claimLeaveFirstUse();
  });

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    savedConfig = PhaseBConfig.current;
    PhaseBConfig.current = const PhaseBConfig();
    savedBriefStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
    savedFlags = RemoteFeatureFlags.current;
  });

  tearDown(() {
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedBriefStore;
    RemoteFeatureFlags.current = savedFlags;
    ReminiscenceV2Stores.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
  });

  test('initial: the companion\'s own character, never the shared 「阿」', () {
    expect(avatarInitial('阿伯'), '伯');
    expect(avatarInitial('阿珍'), '珍');
    expect(avatarInitial('小欣'), '小');
    expect(avatarInitial('通通'), '通');
    expect(avatarInitial('阿'), '阿');
    expect(avatarInitial(''), '');
    final ahJan = AgentRegistry.byId(AgentRegistry.ahJanAhBakId);
    expect(ahJan.resolveVariant(AgentGenderVariant.masculine).initialZh, '伯');
    expect(ahJan.resolveVariant(AgentGenderVariant.feminine).initialZh, '珍');
  });

  for (final arm in _arms) {
    for (final variant in AgentGenderVariant.values) {
      final tag = '${arm == ArmAssignment.b ? 'rule' : 'hybrid'} · '
          '${variant == AgentGenderVariant.masculine ? '阿伯' : '阿珍'}';

      testWidgets('$tag: 「接著傾」 card — the chosen picture and name, and a '
          'later switch', (tester) async {
        final run = _Run(arm, variant);
        await _boot(
            tester,
            run,
            Scaffold(
                body: ContinueChatCard(
                    progressReader: MyStoryProgressReader(available: false))));
        final card = find.byKey(const ValueKey('continue_chat_avatar'));
        expect(card, findsOneWidget);
        expect(find.text(run.bak ? '同阿伯講舊時' : '同阿珍講舊時'), findsOneWidget);
        expect(
            find.descendant(
                of: card, matching: _picture(run.bak ? _bakAsset : _janAsset)),
            findsOneWidget);
        _expectCompanion(tester, run, where: 'card');

        run.switchCompanion();
        await tester.pumpAndSettle();
        expect(find.text(run.bak ? '同阿珍講舊時' : '同阿伯講舊時'), findsOneWidget);
        expect(
            find.descendant(
                of: card, matching: _picture(run.bak ? _janAsset : _bakAsset)),
            findsOneWidget);
        expect(run.llm.calls, isEmpty);
      });

      testWidgets('$tag: 「接著傾」 card, picture missing → own initial',
          (tester) async {
        final run = _Run(arm, variant, noPictures: true);
        await _boot(
            tester,
            run,
            Scaffold(
                body: ContinueChatCard(
                    progressReader: MyStoryProgressReader(available: false))));
        final initial = find.descendant(
            of: find.byKey(const ValueKey('continue_chat_avatar')),
            matching: find.byKey(const ValueKey('agent_avatar_initial')));
        expect(initial, findsOneWidget);
        expect(tester.widget<Text>(initial).data, run.bak ? '伯' : '珍');
        if (run.bak) expect(_anyText('珍'), findsNothing);
      });

      testWidgets('$tag: old pages (switch off) — landing and week page',
          (tester) async {
        RemoteFeatureFlags.current = const RemoteFeatureFlags();
        final run = _Run(arm, variant);
        await _boot(tester, run, const ReminiscenceLandingPage());
        if (run.bak) expect(_anyText('珍'), findsNothing, reason: 'landing');
        await tester.tap(find.text('童年同屋企'));
        await _settle(tester);
        expect(
            find.byType(
                run.rule ? ReminiscenceArmBPage : ReminiscenceArmAPage),
            findsOneWidget);
        _expectBar(tester, run, where: 'old week page');
        _expectCompanion(tester, run, where: 'old week page');
        if (run.rule) expect(run.llm.calls, isEmpty);
      });

      testWidgets('$tag: v2 pages (switch on) — week page and 小篇章, and a '
          'later switch', (tester) async {
        RemoteFeatureFlags.current =
            const RemoteFeatureFlags(reminiscenceV2Enabled: true);
        final run = _Run(arm, variant);
        run.chapters.serverWrite('u1', 1, {
          'weekIndex': 1,
          'source': run.rule ? 'rule' : 'hybrid',
          'status': 'ready',
          if (run.rule) 'ruleText': '細個住喺深水埗。' else 'finalText': '細個住喺深水埗。',
          'version': 1,
          'requestId': 'r1',
        });
        await _boot(tester, run, const ReminiscenceLandingPage());
        if (run.bak) expect(_anyText('珍'), findsNothing, reason: 'landing');
        await tester.tap(find.text('童年同屋企'));
        await _settle(tester);
        expect(find.byType(ReminiscenceV2Page), findsOneWidget);
        _expectBar(tester, run, where: 'v2 week page');
        _expectCompanion(tester, run, where: 'v2 week page');

        // Switched on the profile page (opened from the bar's avatar): the
        // bar follows at once.
        run.switchCompanion();
        await tester.pumpAndSettle();
        expect(
            tester.widget<Text>(find.byKey(const Key('companion_title'))).data,
            run.bak ? '阿珍' : '阿伯');
        expect(
            find.descendant(
                of: find.byType(CompanionTitle).first,
                matching: _picture(run.bak ? _janAsset : _bakAsset)),
            findsOneWidget);
        run.switchCompanion(back: true);
        await tester.pumpAndSettle();

        run.navKey.currentState!.pop();
        await _settle(tester);
        await tester.tap(find.text(ReminiscenceV2Copy.chaptersPageTitle));
        await _settle(tester);
        expect(find.byType(ReminiscenceChaptersPage), findsOneWidget);
        // The list has a plain title bar (no avatar).
        if (run.bak) expect(_anyText('珍'), findsNothing, reason: '小篇章 list');
        await tester.tap(find.text('第 1 章：童年同屋企'));
        await _settle(tester);
        expect(find.byType(ReminiscenceChapterDetailPage), findsOneWidget);
        _expectBar(tester, run, where: '小篇章 chapter');
        _expectCompanion(tester, run, where: '小篇章 chapter');
        if (run.rule) expect(run.llm.calls, isEmpty);
      });

      testWidgets('$tag: picture missing on the week pages → own initial',
          (tester) async {
        for (final v2 in [false, true]) {
          RemoteFeatureFlags.current =
              RemoteFeatureFlags(reminiscenceV2Enabled: v2);
          final run = _Run(arm, variant, noPictures: true);
          await _boot(tester, run, const ReminiscenceLandingPage());
          await tester.tap(find.text('童年同屋企'));
          await _settle(tester);
          final initial = find.descendant(
              of: find.byType(CompanionTitle).first,
              matching: find.byKey(const ValueKey('agent_avatar_initial')));
          expect(initial, findsOneWidget, reason: 'v2 $v2');
          expect(tester.widget<Text>(initial).data, run.bak ? '伯' : '珍',
              reason: 'v2 $v2');
          if (run.bak) expect(_anyText('珍'), findsNothing, reason: 'v2 $v2');
          run.navKey.currentState!.pop();
          await _settle(tester);
          await tester.pumpWidget(const SizedBox());
          ReminiscenceV2Stores.resetForTest();
          ChatSessionRecorder.resetProcessStateForTest();
        }
      });

      testWidgets('$tag: first-intro card on the week page', (tester) async {
        RemoteFeatureFlags.current =
            const RemoteFeatureFlags(reminiscenceV2Enabled: true);
        final run = _Run(arm, variant, introSeen: false);
        await _boot(tester, run, const ReminiscenceLandingPage());
        await tester.tap(find.text('童年同屋企'));
        await _settle(tester);
        final dialog = find.byType(Dialog);
        expect(dialog, findsOneWidget);
        expect(
            find.descendant(
                of: dialog,
                matching: _picture(run.bak ? _bakAsset : _janAsset)),
            findsOneWidget);
        expect(find.descendant(of: dialog, matching: _anyText(
            run.bak ? '我係阿伯' : '我係阿珍')), findsOneWidget);
        _expectCompanion(tester, run, where: 'intro card');
        await tester.tap(find.byKey(const Key('first_intro_start')));
        await _settle(tester);
        expect(dialog, findsNothing);
        if (run.rule) expect(run.llm.calls, isEmpty);
      });
    }
  }

  group('same pattern elsewhere', () {
    for (final variant in AgentGenderVariant.values) {
      final bak = variant == AgentGenderVariant.masculine;
      final tag = bak ? '阿伯' : '阿珍';

      testWidgets('$tag: cross-referral card shows the chosen picture',
          (tester) async {
        final run = _Run(ArmAssignment.a, variant);
        final shared = SharedContextService(available: false);
        await _boot(
            tester,
            run,
            Scaffold(
              body: ReferralSuggestionCard(
                surfaced: SurfacedReferral(
                  match: ReferralMatch(
                    trigger: ReferralTriggersConfig.all.firstWhere(
                        (t) => t.targetAgentId == AgentRegistry.ahJanAhBakId),
                    matchedPhrase: '細個',
                    fullTurn: '細個住喺深水埗',
                  ),
                  suggestionText: '要唔要講多啲？',
                ),
                handoffExecutor: HandoffExecutor(sharedContext: shared),
                onDismiss: () {},
              ),
            ));
        expect(find.text(tag), findsOneWidget);
        _expectCompanion(tester, run, where: 'referral card');
      });

      testWidgets('$tag: profile page picture missing → own initial',
          (tester) async {
        final run = _Run(ArmAssignment.a, variant, noPictures: true);
        final resolution = const AgentProfileController().resolve(
            agentId: AgentRegistry.ahJanAhBakId,
            userProfile: run.settings.profile)!;
        await _boot(tester, run,
            Scaffold(body: ProfileHeader(resolution: resolution)));
        expect(find.text(bak ? '伯' : '珍'), findsOneWidget);
        expect(find.text('阿'), findsNothing);
      });
    }
  });
}
