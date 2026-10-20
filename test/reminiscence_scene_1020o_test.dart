// 1020o 第四节 (4a) — the week's scene picture (Junyu 10/20 第 91 条).
//
// When the elder opens a week of 回憶 v2, the companion's first bubble is
// the week's landscape picture (assets/reminiscence/scene_N.jpg, 4:3, as
// wide as a chat bubble) with the week's line under it; then the opener
// (ReminiscenceV2Copy.openerFor) as before, then question 1.  The line
// waits for no reply.  Both arms the same, no model call; the rule arm
// never reaches the model.  The scene is not sent to the model (not in the
// Hybrid history).  No picture → no bubble.  On coming back the bubble is
// not added again: it stays the first bubble of the week's thread.
// decisions-log 10/20 第 99/100 条: the first visit opens at the picture
// (its top on screen; the elder scrolls down to question 1) on a phone at
// App text 1.06 and 1.30 and on an iPad; coming back, or without the
// picture, the page opens at the newest message as before; after the
// elder's answer the list follows the newest message again.
//
//   flutter test test/reminiscence_scene_1020o_test.dart
//   flutter test --dart-define=PHASE_B=true test/reminiscence_scene_1020o_test.dart
//   flutter test --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
//     test/reminiscence_scene_1020o_test.dart
//
// Synthetic data only; no Firebase; fake model, fake stores, fake clock.
import 'dart:async';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/wide_screen_frame.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
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
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_copy.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_store.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_v2_page.dart';
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

/// The four lines, verbatim (1020o (4a)).
const _lines = {
  1: '睇吓呢幅圖，有冇令你諗起細個嘅日子？',
  2: '睇吓呢幅圖，有冇令你諗起後生嗰陣做嘢嘅日子？',
  3: '睇吓呢幅圖，有冇令你諗起一個老朋友？',
  4: '睇吓呢幅圖。今個禮拜，想聽下你想留畀後生一代嘅說話。',
};

/// Fake model: records each call's history; the rule arm fails the test.
class _FakeLlm implements LlmClient {
  _FakeLlm({required this.forbid});
  final bool forbid;
  final calls = <({String moduleId, List<LlmTurn> history})>[];

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
    calls.add((moduleId: moduleId, history: List.of(history)));
    if (forbid) throw TestFailure('rule arm called the LLM ($moduleId)');
    return const LlmRawResponse(text: '嗰條街附近有冇一間舖頭，你到而家都記得？');
  }
}

class _FakeMemoryV1 extends MemoryV1Service {
  @override
  Future<void> endSession(String agentId) async {}
}

/// Scene pictures that fail to load (listed, but broken).
class _BrokenScenesBundle extends CachingAssetBundle {
  static bool _scene(String key) =>
      key.startsWith('assets/reminiscence/scene_');

  @override
  Future<ByteData> load(String key) => _scene(key)
      ? Future<ByteData>.error(FlutterError('broken: $key'))
      : rootBundle.load(key);

  @override
  Future<ImmutableBuffer> loadBuffer(String key) => _scene(key)
      ? Future<ImmutableBuffer>.error(FlutterError('broken: $key'))
      : rootBundle.loadBuffer(key);
}

/// An App built without the scene pictures: the asset manifest does not
/// list them.
class _NoScenesBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<T> loadStructuredBinaryData<T>(
      String key, FutureOr<T> Function(ByteData data) parser) async {
    if (key != 'AssetManifest.bin') {
      return super.loadStructuredBinaryData(key, parser);
    }
    const codec = StandardMessageCodec();
    final map = Map<Object?, Object?>.from(
        codec.decodeMessage(await rootBundle.load(key)) as Map);
    map.removeWhere(
        (k, _) => (k as String).startsWith('assets/reminiscence/scene_'));
    return parser(codec.encodeMessage(map)!);
  }
}

UserProfile _profile(ArmAssignment arm) => UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: arm,
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

final _now = DateTime(2026, 10, 21, 10, 0);

class _Run {
  _Run(this.arm, {this.bundle, this.wide = false});

  /// The iPad column (app.dart's WideScreenFrame).
  final bool wide;
  final ArmAssignment arm;
  final AssetBundle? bundle;
  late final _FakeLlm llm = _FakeLlm(forbid: arm == ArmAssignment.b);
  final weeks = InMemoryReminiscenceWeekStore();
  final navKey = GlobalKey<NavigatorState>();

  bool get rule => arm == ArmAssignment.b;

  List<Map<String, dynamic>> messages([int w = 1]) => [
        for (final m in (weeks.doc('u1', w)!['messages'] as List))
          Map<String, dynamic>.from(m as Map)
      ];
  List<String> kinds([int w = 1]) =>
      [for (final m in messages(w)) m['kind'] as String];

  void install() {
    ReminiscenceV2Stores.weekOverride = weeks;
    ReminiscenceV2Stores.chaptersOverride = InMemoryReminiscenceChapterStore();
    ReminiscenceV2Stores.ratingsOverride = InMemoryReminiscenceRatingStore();
    ReminiscenceV2Stores.summaryOverride = InMemoryReminiscenceSummaryWriter();
  }
}

Widget _harness(_Run run) {
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
    builder: (context, child) =>
        WideScreenFrame(enabled: run.wide, child: child!),
    home: const Scaffold(body: Text('home')),
  );
  if (run.bundle != null) {
    app = DefaultAssetBundle(bundle: run.bundle!, child: app);
  }
  return AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh'), profile: _profile(run.arm)),
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _boot(WidgetTester tester, _Run run,
    {Size size = const Size(400, 6000)}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  run.install();
  await tester.pumpWidget(_harness(run));
  await tester.pumpAndSettle();
}

Future<void> _push(WidgetTester tester, _Run run, int week) async {
  run.navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => ReminiscenceV2Page(
          theme: ReminiscenceTheme.byIndex(week), clock: () => _now)));
  await _settle(tester);
}

Finder _says(String text) => find.textContaining(text, findRichText: true);

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
    // As the v2 page tests: Brief PR v2 on (its store in memory).
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    savedBriefStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
    savedFlags = RemoteFeatureFlags.current;
    RemoteFeatureFlags.current = const RemoteFeatureFlags(
        reminiscenceV2Enabled: true, leaveButtonV2Enabled: true);
  });

  tearDown(() {
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedBriefStore;
    RemoteFeatureFlags.current = savedFlags;
    ReminiscenceV2Stores.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
  });

  test('the four lines and pictures (copy = spec, by week)', () {
    expect(ReminiscenceV2Copy.sceneLines, _lines);
    for (final w in [1, 2, 3, 4]) {
      expect(ReminiscenceV2Copy.sceneAsset(w), 'assets/reminiscence/scene_$w.jpg');
    }
  });

  for (final arm in _arms) {
    final tag = arm == ArmAssignment.b ? 'rule' : 'hybrid';

    for (final week in [1, 2, 3, 4]) {
      testWidgets('$tag, week $week: picture + line first, then the opener',
          (tester) async {
        final run = _Run(arm);
        await _boot(tester, run);
        await _push(tester, run, week);

        final bubble = find.byKey(const Key('reminiscence_scene_bubble'));
        expect(bubble, findsOneWidget);
        expect(
            find.descendant(of: bubble, matching: _says(_lines[week]!)),
            findsOneWidget);
        // The bubble is built around the week's picture.
        final picture = find.byKey(ValueKey('reminiscence_scene_$week'));
        expect(find.descendant(of: picture, matching: bubble), findsOneWidget);
        expect(
            (tester.widget<Image>(picture).image as AssetImage).assetName,
            'assets/reminiscence/scene_$week.jpg');
        // 4:3, as wide as a chat bubble.
        final art = tester.getSize(find.descendant(
            of: bubble, matching: find.byType(AspectRatio)));
        expect(art.width / art.height, closeTo(4 / 3, 0.01));
        expect(tester.getSize(bubble).width, closeTo(400 * 0.88, 0.5));

        // Before the opener; then question 1 (the line waits for nothing).
        final opener =
            ReminiscenceV2Copy.openerFor(week, name: '阿伯').first;
        expect(tester.getTopLeft(bubble).dy,
            lessThan(tester.getTopLeft(_says(opener)).dy));
        expect(_says(ReminiscenceV2Copy.week(week).question(1)),
            findsOneWidget);
        expect(find.byKey(const Key('reminiscence_input')), findsOneWidget);

        expect(run.kinds(week).take(5),
            ['scene', 'opener', 'opener', 'opener', 'question']);
        final first = run.messages(week).first;
        expect(first['text'], _lines[week]);
        expect(first['copyId'], 'scene_$week');
        expect(run.llm.calls, isEmpty);
      });
    }

    testWidgets('$tag: answer question 1 — the scene is not sent to the '
        'model; leave and come back — shown once, not added again',
        (tester) async {
      final run = _Run(arm);
      await _boot(tester, run);
      await _push(tester, run, 1);
      await tester.enterText(
          find.byKey(const Key('reminiscence_input')), '我喺深水埗大。');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await _settle(tester);
      if (run.rule) {
        expect(run.llm.calls, isEmpty);
      } else {
        expect(run.llm.calls, isNotEmpty);
        for (final c in run.llm.calls) {
          final said = c.history.map((t) => t.text).join('\n');
          expect(said.contains('睇吓呢幅圖'), isFalse, reason: c.moduleId);
          // The opener still is (as before).
          expect(said.contains('你好，我係阿伯'), isTrue, reason: c.moduleId);
        }
      }
      final before = run.kinds();
      expect(before.where((k) => k == 'scene'), hasLength(1));

      await tester.tap(find.byKey(const Key('session_close_button')));
      await _settle(tester);
      expect(find.byType(ReminiscenceV2Page), findsNothing);
      await _push(tester, run, 1);
      expect(run.kinds(), before, reason: 'nothing added on return');
      expect(find.byKey(const Key('reminiscence_scene_bubble')), findsOneWidget);
      expect(_says(_lines[1]!), findsOneWidget);
      if (run.rule) expect(run.llm.calls, isEmpty);
    });

    testWidgets('$tag: picture cannot load → no bubble at all',
        (tester) async {
      final run = _Run(arm, bundle: _BrokenScenesBundle());
      await _boot(tester, run);
      await _push(tester, run, 1);
      expect(find.byKey(const Key('reminiscence_scene_bubble')), findsNothing);
      expect(_says(_lines[1]!), findsNothing);
      expect(_says(ReminiscenceV2Copy.openerFor(1, name: '阿伯').first),
          findsOneWidget);
      expect(_says(ReminiscenceV2Copy.week(1).question(1)), findsOneWidget);
      if (run.rule) expect(run.llm.calls, isEmpty);
    });

    testWidgets('$tag: App without the picture → no scene message at all',
        (tester) async {
      final run = _Run(arm, bundle: _NoScenesBundle());
      await _boot(tester, run);
      await _push(tester, run, 2);
      expect(find.byKey(const Key('reminiscence_scene_bubble')), findsNothing);
      expect(_says(_lines[2]!), findsNothing);
      expect(run.kinds(2).take(4), ['opener', 'opener', 'opener', 'question']);
      if (run.rule) expect(run.llm.calls, isEmpty);
    });

    testWidgets('$tag: largest text on a small phone — the bubble fits',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final run = _Run(arm);
      await _boot(tester, run, size: const Size(360, 800));
      await _push(tester, run, 4);
      final bubble = find.byKey(const Key('reminiscence_scene_bubble'));
      expect(bubble, findsOneWidget);
      expect(tester.getSize(bubble).width, closeTo(360 * 0.88, 0.5));
      expect(tester.takeException(), isNull);
    });

    // decisions-log 10/20 第 99 条 -------------------------------------------

    for (final screen in [
      (name: 'phone ×1.30', size: const Size(360, 800), scale: 1.3, wide: false),
      (name: 'phone ×1.06', size: const Size(360, 800), scale: 1.06, wide: false),
      (name: 'iPad ×1.06', size: const Size(820, 1180), scale: 1.06, wide: true),
    ]) {
      testWidgets('$tag, ${screen.name}: first visit opens at the picture',
          (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = screen.scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final run = _Run(arm, wide: screen.wide);
        await _boot(tester, run, size: screen.size);
        await _push(tester, run, 1);
        final bubble = find.byKey(const Key('reminiscence_scene_bubble'));
        expect(bubble, findsOneWidget);
        final list = tester.getRect(find.byType(ListView));
        final top = tester.getTopLeft(bubble).dy;
        expect(top, inInclusiveRange(list.top, list.bottom - 1),
            reason: 'the picture starts on screen');
        // When the week does not fit (phones), the page is scrolled to its
        // start: only the week title above the picture.  (On an iPad it
        // all fits and the list sits at the bottom, as every chat page.)
        if (_position(tester).maxScrollExtent > 0) {
          expect(_position(tester).pixels,
              closeTo(_position(tester).maxScrollExtent, 0.5));
          expect(top - list.top, lessThan(120),
              reason: 'at the top (only the week title above it)');
        }
        // Question 1 is further down (reached by scrolling) on a phone at
        // the largest text.
        if (screen.scale > 1.2) {
          expect(_onScreen(tester, _says(ReminiscenceV2Copy.week(1).question(1))),
              isFalse);
        }
        // The page stays there (nothing pushes it back down).
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(bubble).dy, closeTo(top, 0.5));
        if (run.rule) expect(run.llm.calls, isEmpty);
      });
    }

    testWidgets('$tag: coming back opens at the newest message, as before',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final run = _Run(arm);
      await _boot(tester, run, size: const Size(360, 800));
      await _push(tester, run, 1);
      await tester.tap(find.byKey(const Key('session_close_button')));
      await _settle(tester);
      await _push(tester, run, 1);
      expect(_position(tester).pixels, 0, reason: 'at the newest message');
      expect(_onScreen(tester, _says(ReminiscenceV2Copy.week(1).question(1))),
          isTrue);
      expect(_onScreen(tester, find.byKey(const Key('reminiscence_scene_bubble'))),
          isFalse);
    });

    testWidgets('$tag: no picture — opens at the opener / question as before',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final run = _Run(arm, bundle: _NoScenesBundle());
      await _boot(tester, run, size: const Size(360, 800));
      await _push(tester, run, 1);
      expect(_position(tester).pixels, 0);
      expect(_onScreen(tester, _says(ReminiscenceV2Copy.week(1).question(1))),
          isTrue);
    });

    testWidgets('$tag: after the first answer the list follows the newest '
        'message', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final run = _Run(arm);
      await _boot(tester, run, size: const Size(360, 800));
      await _push(tester, run, 1);
      expect(_position(tester).pixels, greaterThan(0), reason: 'at the picture');
      await tester.enterText(
          find.byKey(const Key('reminiscence_input')), '我喺深水埗大。');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await _settle(tester);
      expect(_position(tester).pixels, 0, reason: 'back at the newest message');
      final newest = run.messages().last['text'] as String;
      expect(_onScreen(tester, _says(newest).last), isTrue, reason: newest);
      if (run.rule) expect(run.llm.calls, isEmpty);
    });
  }
}

/// The message list's scroll position.
ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
        .first)
    .position;

/// Whether [f]'s top is inside the message list's visible area.
bool _onScreen(WidgetTester tester, Finder f) {
  final hits = f.hitTestable().evaluate();
  if (f.evaluate().isEmpty) return false;
  final list = tester.getRect(find.byType(ListView));
  final r = tester.getRect(f.first);
  return hits.isNotEmpty && r.top >= list.top - 0.5 && r.top < list.bottom;
}
