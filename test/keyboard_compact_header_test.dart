// 1020c item 二 — keyboard occlusion: behind the remote switch
// `app_config/feature_flags.keyboardCompactHeaderEnabled` (default off),
// while the keyboard is open the top bar is one line (48 px, S9 / back
// kept) and a chat list goes back to the newest message; the full bar
// returns when the keyboard closes.  Switch off: nothing changes.
//
// Small phone (iPhone SE 375×667 and a 360×640 Android), the App's largest
// font (1.30), a simulated keyboard of 300 px (`tester.view.viewInsets`).
// Pages: 小欣's chat window (SiuYanChatPage) and 通通 (TungTungPage), in
// both arms, plus one form page (ThoughtExercisePage).
//
// Arm.of reads the profile's arm only in a Phase B build, so the two-arm
// cases run with:
//   flutter test --dart-define=PHASE_B=true test/keyboard_compact_header_test.dart
// (tool/ci_flutter_tests.sh "phase B arm gating" and "phase B arm B
// pages").  In the default build everybody is Hybrid and the rule-arm
// cases are skipped.  Synthetic data only; no Firebase.  The rule arm's
// fake model fails the test if it is ever called.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/companion_app_bar.dart';
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
import 'package:app_demo/features/context/data/check_in_response_store.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/curious_companion/presentation/pages/tung_tung_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:app_demo/features/thought_exercise/presentation/thought_exercise_page.dart';
import 'package:app_demo/shared/widgets/keyboard_compact.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _forced = String.fromEnvironment('FORCE_ARM');

/// The rule arm is reachable only in a Phase B build (profile arm B).
final bool _ruleTestable = FeatureFlags.phaseB && _forced != 'A';

/// Everybody is Hybrid in a Phase A build; Phase B needs profile arm A.
final bool _hybridTestable = !FeatureFlags.phaseB || _forced != 'B';

const _keyboard = 300.0;
const _scale = 1.3; // the App's largest font (特大)

/// Short replies so the newest one fits the small screen.
class _FakeLlm implements LlmClient {
  _FakeLlm({required this.forbid});
  final bool forbid;
  int calls = 0;

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
    calls++;
    if (forbid) throw TestFailure('rule arm called the LLM ($moduleId)');
    return const LlmRawResponse(text: '好呀，再同我講多啲。');
  }
}

class _FakeMemoryV1 extends MemoryV1Service {
  @override
  Future<void> endSession(String agentId) async {}
}

UserProfile _profile(ArmAssignment arm) => UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: arm,
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

class _Run {
  _Run(this.arm) : llm = _FakeLlm(forbid: arm == ArmAssignment.b);
  final ArmAssignment arm;
  final _FakeLlm llm;
  final navKey = GlobalKey<NavigatorState>();
}

Widget _harness(_Run run) {
  final llm = LlmGateway(client: run.llm);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  return AppSettingsScope(
    settings:
        AppSettings(locale: const Locale('zh'), profile: _profile(run.arm)),
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
          memoryV1: _FakeMemoryV1(),
          child: MaterialApp(
            navigatorKey: run.navKey,
            // The real theme: its 72 px top bar is the thing being fixed.
            theme: AppTheme.light,
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // Same wrapper as app.dart, at the largest App font.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(_scale)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    ),
  );
}

/// The phone: logical size, status bar, no keyboard yet.
void _phone(WidgetTester tester, Size size, double statusBar) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = FakeViewPadding(top: statusBar);
  addTearDown(tester.view.reset);
  // No connectivity plugin in tests: report Wi-Fi so sends go through.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, _Run run, Widget page) async {
  await tester.pumpWidget(_harness(run));
  await tester.pumpAndSettle();
  run.navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
  await _settle(tester);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded).last);
  await _settle(tester);
}

Future<void> _keyboardUp(WidgetTester tester) async {
  await tester.showKeyboard(find.byType(TextField).last);
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
  await tester.pumpAndSettle();
}

Future<void> _keyboardDown(WidgetTester tester) async {
  tester.view.viewInsets = FakeViewPadding.zero;
  await tester.pumpAndSettle();
}

SiuYanChatPage _siuYan() => SiuYanChatPage(
      // Check-in already done today: straight to the chat.
      checkedInToday: (_) async => true,
      latestMoodToday: (_) async => 4,
      responseStore: InMemoryCheckInResponseStore(),
      replyHistory: InMemoryRuleReplyHistoryStore(),
      onOpenActionPlan: (_) async {},
    );

AppBar _bar(WidgetTester tester) => tester.widget<AppBar>(find.byType(AppBar));

double _barBottom(WidgetTester tester) =>
    tester.getRect(find.byType(AppBar)).bottom;

/// The message list (the reversed ListView on the chat page).
Finder get _list => find.byWidgetPredicate(
    (w) => w is ListView && w.reverse && w.scrollDirection == Axis.vertical);

/// The newest message: the text in the list closest to the input box.
Rect _newest(WidgetTester tester) {
  Rect? best;
  for (final e in find
      .descendant(of: _list, matching: find.byType(RichText))
      .evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) continue;
    final r = box.localToGlobal(Offset.zero) & box.size;
    if (best == null || r.bottom > best.bottom) best = r;
  }
  expect(best, isNotNull, reason: 'the list shows messages');
  return best!;
}

/// The input box and the newest message are on screen above the keyboard
/// and below the top bar.
void _expectInputAndNewestVisible(WidgetTester tester, Size size) {
  final keyboardTop = size.height - _keyboard;
  final field = tester.getRect(find.byType(TextField).last);
  final top = _barBottom(tester);
  expect(field.bottom, lessThanOrEqualTo(keyboardTop + 0.5),
      reason: 'input box above the keyboard');
  expect(field.top, greaterThanOrEqualTo(top - 0.5),
      reason: 'input box below the top bar');
  final viewport = tester.getRect(_list);
  final newest = _newest(tester);
  expect(newest.top, greaterThanOrEqualTo(viewport.top - 0.5),
      reason: 'newest message not cut at the top ($newest in $viewport)');
  expect(newest.bottom, lessThanOrEqualTo(viewport.bottom + 0.5),
      reason: 'newest message not under the input box');
  expect(viewport.top, greaterThanOrEqualTo(top - 0.5));
  expect(viewport.bottom, lessThanOrEqualTo(field.top + 0.5));
}

typedef _PageCase = ({String name, Widget Function() page});

final _pages = <_PageCase>[
  (name: '小欣 chat window', page: _siuYan),
  (name: '通通', page: () => const TungTungPage()),
];

const _iphoneSe = (name: 'iPhone SE 375×667', size: Size(375, 667), bar: 20.0);
const _android = (name: 'Android 360×640', size: Size(360, 640), bar: 24.0);

void main() {
  late PhaseBConfig savedConfig;
  late BriefPrStore savedBriefStore;
  late RemoteFeatureFlags savedFlags;

  // The one-time 「今日傾到呢度」 note would cover the composer.
  setUpAll(SessionCloseHint.claimFirstUse);

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    savedConfig = PhaseBConfig.current;
    // Session v2 on (the Phase B setting): S9 「今日傾到呢度」 top-left.
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    savedBriefStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
    savedFlags = RemoteFeatureFlags.current;
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
  });

  tearDown(() {
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedBriefStore;
    RemoteFeatureFlags.current = savedFlags;
    ChatSessionRecorder.resetProcessStateForTest();
  });

  void flagOn() => RemoteFeatureFlags.current =
      RemoteFeatureFlags.fromMap(const {'keyboardCompactHeaderEnabled': true});

  group('the switch', () {
    test('off unless the field is literally true', () {
      expect(const RemoteFeatureFlags().keyboardCompactHeaderEnabled, isFalse);
      for (final v in <Object?>[null, 'true', 1, false, 'yes']) {
        expect(
            RemoteFeatureFlags.fromMap({'keyboardCompactHeaderEnabled': v})
                .keyboardCompactHeaderEnabled,
            isFalse,
            reason: '$v');
      }
      expect(RemoteFeatureFlags.fromMap(const {}).keyboardCompactHeaderEnabled,
          isFalse);
      expect(
          RemoteFeatureFlags.fromMap(
                  const {'keyboardCompactHeaderEnabled': true})
              .keyboardCompactHeaderEnabled,
          isTrue);
    });
  });

  for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
    final armName = arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';
    final skip = arm == ArmAssignment.a ? !_hybridTestable : !_ruleTestable;

    for (final p in _pages) {
      group('${p.name} — $armName', () {
        for (final phone in [_iphoneSe, _android]) {
          testWidgets(
              'switch on, ${phone.name}: keyboard open → one-line bar '
              '(S9 kept), input box and newest message visible; keyboard '
              'closed → full bar again', (tester) async {
            flagOn();
            _phone(tester, phone.size, phone.bar);
            final run = _Run(arm);
            await _open(tester, run, p.page());
            await _type(tester, '今日去咗公園');
            await _type(tester, '想飲茶');

            // Keyboard closed: the full 72 px bar with the 32 px avatar.
            expect(_bar(tester).toolbarHeight, isNull);
            expect(_barBottom(tester), phone.bar + 72);
            expect(tester.widget<CompanionTitle>(find.byType(CompanionTitle))
                .compact, isFalse);
            final close = find.byKey(const Key('session_close_button'));
            final closeSize = tester.getSize(close);

            await _keyboardUp(tester);
            expect(_bar(tester).toolbarHeight, KeyboardCompact.toolbarHeight);
            expect(_barBottom(tester), phone.bar + KeyboardCompact.toolbarHeight);
            expect(tester.widget<CompanionTitle>(find.byType(CompanionTitle))
                .compact, isTrue);
            // The end-session button keeps its place and its full size.
            expect(close.hitTestable(), findsOneWidget);
            expect(tester.getSize(close), closeSize);
            expect(tester.getRect(close).left,
                lessThan(phone.size.width / 2), reason: 'still top-left');
            _expectInputAndNewestVisible(tester, phone.size);

            await _keyboardDown(tester);
            expect(_bar(tester).toolbarHeight, isNull);
            expect(_barBottom(tester), phone.bar + 72);
            expect(tester.widget<CompanionTitle>(find.byType(CompanionTitle))
                .compact, isFalse);
            if (arm == ArmAssignment.b) expect(run.llm.calls, 0);
          }, skip: skip);
        }

        testWidgets('switch off: the keyboard changes nothing (bar stays '
            '72 px, list not moved)', (tester) async {
          _phone(tester, _iphoneSe.size, _iphoneSe.bar);
          final run = _Run(arm);
          await _open(tester, run, p.page());
          await _type(tester, '今日去咗公園');
          final before = _bar(tester);
          final listBefore = tester.getRect(_list);
          await _keyboardUp(tester);
          final after = _bar(tester);
          expect(after.toolbarHeight, isNull);
          expect(after.leadingWidth, before.leadingWidth);
          expect(_barBottom(tester), _iphoneSe.bar + 72);
          expect(tester.widget<CompanionTitle>(find.byType(CompanionTitle))
              .compact, isFalse);
          expect(tester.getRect(_list).top, listBefore.top,
              reason: 'the list starts under the same full bar');
          // The input box itself is above the keyboard as before (10/15).
          expect(tester.getRect(find.byType(TextField).last).bottom,
              lessThanOrEqualTo(_iphoneSe.size.height - _keyboard + 0.5));
          if (arm == ArmAssignment.b) expect(run.llm.calls, 0);
        }, skip: skip);

        testWidgets('scrolled up to read, then the keyboard opens: switch on '
            '→ back to the newest message; switch off → stays',
            (tester) async {
          // Off first, then on, same steps.
          for (final on in [false, true]) {
            RemoteFeatureFlags.current = on
                ? RemoteFeatureFlags.fromMap(
                    const {'keyboardCompactHeaderEnabled': true})
                : const RemoteFeatureFlags();
            _phone(tester, _android.size, _android.bar);
            final run = _Run(arm);
            await _open(tester, run, p.page());
            for (var i = 0; i < 4; i++) {
              await _type(tester, '第 $i 句：今日去咗公園行下');
            }
            // Read older messages: drag the list down.
            await tester.drag(_list, const Offset(0, 300));
            await tester.pumpAndSettle();
            final state = tester.state<ScrollableState>(find.descendant(
                of: _list, matching: find.byType(Scrollable)));
            expect(state.position.pixels, greaterThan(0),
                reason: 'scrolled away from the newest');
            await _keyboardUp(tester);
            if (on) {
              expect(state.position.pixels, 0,
                  reason: 'back to the newest message');
              _expectInputAndNewestVisible(tester, _android.size);
            } else {
              expect(state.position.pixels, greaterThan(0),
                  reason: 'switch off: the list is not moved');
            }
            await _keyboardDown(tester);
            if (arm == ArmAssignment.b) expect(run.llm.calls, 0);
            // Next round from a fresh tree.
            await tester.pumpWidget(const SizedBox());
            ChatSessionRecorder.resetProcessStateForTest();
          }
        }, skip: skip);
      });
    }
  }

  group('S9 off (back arrow) and other pages', () {
    testWidgets('session v1 (no S9): the compact bar keeps the back arrow',
        (tester) async {
      PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: false);
      flagOn();
      _phone(tester, _android.size, _android.bar);
      final run = _Run(_hybridTestable ? ArmAssignment.a : ArmAssignment.b);
      await _open(tester, run, const TungTungPage());
      await _keyboardUp(tester);
      expect(_bar(tester).toolbarHeight, KeyboardCompact.toolbarHeight);
      expect(find.byType(BackButton).hitTestable(), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(TungTungPage), findsNothing, reason: 'back works');
    });

    testWidgets('通通 article Q&A: the article line goes with the bar while '
        'typing and comes back after', (tester) async {
      flagOn();
      _phone(tester, _android.size, _android.bar);
      final run = _Run(_hybridTestable ? ArmAssignment.a : ArmAssignment.b);
      await _open(
          tester,
          run,
          const TungTungPage(
              articleTitle: '點樣同屋企人傾偈',
              articleContext: '合成文章內容',
              articleId: 'synthetic'));
      final banner = find.textContaining('根據文章');
      expect(banner, findsOneWidget);
      await _keyboardUp(tester);
      expect(banner, findsNothing);
      await _keyboardDown(tester);
      expect(banner, findsOneWidget);
    });

    testWidgets('a form page (望一望心入面, both arms the same page): one-line '
        'bar while typing, same title words; switch off unchanged',
        (tester) async {
      for (final on in [true, false]) {
        RemoteFeatureFlags.current = on
            ? RemoteFeatureFlags.fromMap(
                const {'keyboardCompactHeaderEnabled': true})
            : const RemoteFeatureFlags();
        _phone(tester, _android.size, _android.bar);
        final run = _Run(_hybridTestable ? ArmAssignment.a : ArmAssignment.b);
        await _open(tester, run, const ThoughtExercisePage());
        expect(_barBottom(tester), _android.bar + 72);
        await _keyboardUp(tester);
        expect(_barBottom(tester),
            _android.bar + (on ? KeyboardCompact.toolbarHeight : 72));
        expect(find.descendant(
                of: find.byType(AppBar), matching: find.text('望一望心入面')),
            findsOneWidget);
        final field = tester.getRect(find.byType(TextField).first);
        expect(field.bottom,
            lessThanOrEqualTo(_android.size.height - _keyboard + 0.5));
        await _keyboardDown(tester);
        expect(_barBottom(tester), _android.bar + 72);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
