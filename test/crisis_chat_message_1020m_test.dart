// 1020m 第三节 (decisions-log 10/20 item 84) — after an acute trigger every
// chat window shows ONE fixed safety message (CrisisChatMessage), both arms
// alike, never written by the model:
//   - its numbers are exactly the crisis page's, read from the same config
//     (`functions/prompts/crisis_resources.json` via SafetyCopy) — every
//     check below compares against that loader, never against literals;
//   - 「打開緊急求助頁」 under it opens the crisis page;
//   - no other number appears in the chat (the old per-agent acute
//     template, which named only 撒瑪利亞會, is gone);
//   - the acute flow itself (detection, crisis page, session end) is
//     unchanged; the rule arm makes zero LLM calls; a model reply's phone
//     number is still replaced by the crisis-page link (T7 filter);
//   - the message is never sent to the model in later turns.
//
// Pages: 小欣 chat (check-in and free chat), 通通, 回憶 v2 (both arms);
// the old Hybrid check-in, 回憶 v1 and 反思對話 (Hybrid only); the old
// rule-arm check-in and 回憶 forms (rule arm only).
//
// Arm.of reads the profile's arm only in a Phase B build:
//   flutter test test/crisis_chat_message_1020m_test.dart          (Hybrid)
//   flutter test --dart-define=PHASE_B=true test/crisis_chat_message_1020m_test.dart
//   flutter test --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
//     test/crisis_chat_message_1020m_test.dart                     (rule arm)
// Synthetic data only; no Firebase; fake model.
import 'dart:convert';
import 'dart:io';

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
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/memory/memory_v1_service.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/safety/hotline_filter.dart';
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
import 'package:app_demo/features/context/presentation/pages/check_in_arm_a.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_b.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/crisis/presentation/pages/emergency_support_page.dart';
import 'package:app_demo/features/crisis/presentation/widgets/crisis_chat_message.dart';
import 'package:app_demo/features/curious_companion/presentation/pages/tung_tung_page.dart';
import 'package:app_demo/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_store.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_v2_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _forced = String.fromEnvironment('FORCE_ARM');

/// The rule arm is reachable only in a Phase B build (profile arm B).
final bool _ruleTestable = FeatureFlags.phaseB && _forced != 'A';

/// Everybody is Hybrid in a Phase A build; Phase B needs profile arm A.
final bool _hybridTestable = !FeatureFlags.phaseB || _forced != 'B';

bool _testable(ArmAssignment arm) =>
    arm == ArmAssignment.a ? _hybridTestable : _ruleTestable;

/// The existing acute test sentence (T6 / T7, used across the suite).
const _acute = '我真係想死';

Map<String, dynamic> _json(String path) =>
    Map<String, dynamic>.from(jsonDecode(File(path).readAsStringSync()) as Map);

/// Fake model.  The rule arm must never get here: [forbid] makes any call
/// a test failure (also counted, in case a page swallows the throw).
class _FakeLlm implements LlmClient {
  _FakeLlm({this.forbid = false});
  final bool forbid;

  /// What the model answers (every call).
  String reply = '好呀，同我講多啲。';
  final calls = <({String moduleId, String input, List<LlmTurn> history})>[];

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
    calls.add((moduleId: moduleId, input: userInput, history: history));
    if (forbid) throw TestFailure('rule arm called the LLM ($moduleId)');
    return LlmRawResponse(text: reply);
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
      interests: const ['yum_cha'],
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

/// 09:30 on study day 7 (W0 10/14).
final _now = DateTime(2026, 10, 21, 9, 30);

class _Run {
  /// [arm] null: no profile (the old rule-arm forms write to Firestore
  /// when a profile is set; they are tested as in rule_reply_pages_test).
  _Run(this.arm);
  final ArmAssignment? arm;
  late _FakeLlm llm;
  final navKey = GlobalKey<NavigatorState>();
  final checkIns = InMemoryCheckInResponseStore();
  final history = InMemoryRuleReplyHistoryStore();

  bool get rule => arm != ArmAssignment.a;

  void installReminiscenceStores() {
    ReminiscenceV2Stores.weekOverride = InMemoryReminiscenceWeekStore();
    ReminiscenceV2Stores.chaptersOverride = InMemoryReminiscenceChapterStore();
    ReminiscenceV2Stores.ratingsOverride = InMemoryReminiscenceRatingStore();
    ReminiscenceV2Stores.summaryOverride = InMemoryReminiscenceSummaryWriter();
  }
}

Widget _harness(_Run run) {
  run.llm = _FakeLlm(forbid: run.rule);
  final llm = LlmGateway(client: run.llm);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  final arm = run.arm;
  return AppSettingsScope(
    settings: AppSettings(
        locale: const Locale('zh'),
        profile: arm == null ? null : _profile(arm)),
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

Future<void> _open(WidgetTester tester, _Run run, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // No connectivity plugin in tests: report Wi-Fi so sends go through.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  await tester.pumpWidget(_harness(run));
  await tester.pumpAndSettle();
  run.navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
  await _settle(tester);
}

/// Lets the 700 ms template pause and any fake-model future finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text, {Finder? field}) async {
  await tester.enterText(field ?? find.byType(TextField).first, text);
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded).first);
  await _settle(tester);
}

SiuYanChatPage _siuYan(_Run run, {bool doneToday = false}) => SiuYanChatPage(
      checkedInToday: (_) async => doneToday,
      latestMoodToday: (_) async => null,
      responseStore: run.checkIns,
      replyHistory: run.history,
      clock: () => _now,
      onOpenActionPlan: (_) async {},
    );

// ---------------------------------------------------------------------
// What the chat shows
// ---------------------------------------------------------------------

/// Every run of digits (spaces inside a number allowed) of 3 or more.
List<String> _numbersIn(String text) => [
      for (final m in RegExp(r'[0-9０-９][0-9０-９ ]*[0-9０-９]').allMatches(text))
        if (m[0]!.replaceAll(' ', '').length >= 3) m[0]!.replaceAll(' ', ''),
    ];

/// Every number on the screen's top route (offstage routes skipped).
List<String> _numbersOnScreen(WidgetTester tester) => [
      for (final t in tester.widgetList<RichText>(find.byType(RichText)))
        ..._numbersIn(t.text.toPlainText()),
    ]..sort();

/// The numbers the message must show: those in the crisis config's names
/// and numbers, as the crisis page shows them — read from the loader.
List<String> _expectedNumbers() => [
      for (final r in SafetyCopy.crisis.resources) ...[
        ..._numbersIn(r.name(false)),
        ..._numbersIn(r.number),
      ],
    ]..sort();

/// The old per-agent acute lines (safety_acknowledgements.json, filled as
/// the removed acuteAck filled them) — none may appear any more.
List<String> _oldAcuteLines() {
  final acks = _json('functions/prompts/safety_acknowledgements.json');
  return [
    for (final agent in ['siu_yan', 'ah_jan_ah_bak', 'tung_tung'])
      SafetyCopy.fillHotline(
          ((acks[agent] as Map)['acute'] as Map)['zh'] as String,
          isEn: false),
  ];
}

/// After the acute flow's crisis page is closed: exactly one fixed message
/// with the crisis page's numbers, nothing else numeric in the chat, the
/// old template gone; its button opens the crisis page with the same list.
Future<void> _expectCrisisMessage(WidgetTester tester, _Run run) async {
  final message = find.byType(CrisisChatMessage);
  expect(message, findsOneWidget, reason: 'one fixed safety message');
  final resources = SafetyCopy.crisis.resources;
  expect(resources, isNotEmpty);
  for (final r in resources) {
    final number = find.descendant(
        of: message, matching: find.byKey(CrisisChatMessage.numberKey(r.id)));
    expect(number, findsOneWidget, reason: r.id);
    expect(tester.widget<Text>(number).data, r.number, reason: r.id);
    expect(
        find.descendant(of: message, matching: find.text(r.name(false))),
        findsOneWidget,
        reason: r.id);
  }
  expect(
      find.descendant(of: message, matching: find.text(CrisisChatMessage.openingZh)),
      findsOneWidget);
  expect(_numbersIn(CrisisChatMessage.openingZh), isEmpty);
  // No number in the chat other than the crisis page's (and each once).
  expect(_numbersOnScreen(tester), _expectedNumbers());
  // The old template (named only the acuteTemplateReference hotline).
  for (final line in _oldAcuteLines()) {
    expect(find.textContaining(line, findRichText: true), findsNothing);
  }
  final ref = SafetyCopy.crisis.acuteReference!;
  expect(find.textContaining(ref.nameZh, findRichText: true), findsOneWidget,
      reason: '${ref.nameZh} only in the list, as on the crisis page');
  expect(
      find.descendant(
          of: message,
          matching: find.textContaining(ref.nameZh, findRichText: true)),
      findsOneWidget);
  // No 【緊急熱線】 token left as text either.
  expect(find.textContaining(kHotlineToken, findRichText: true), findsNothing);

  // 「打開緊急求助頁」 → the crisis page, the same list.
  expect(find.text(CrisisChatMessage.buttonZh), findsOneWidget);
  await tester.ensureVisible(find.byKey(CrisisChatMessage.openButtonKey));
  await tester.tap(find.byKey(CrisisChatMessage.openButtonKey));
  await tester.pumpAndSettle();
  final page = find.byType(EmergencySupportPage);
  expect(page, findsOneWidget);
  expect(tester.widget<EmergencySupportPage>(page).from, CrisisChatMessage.from);
  for (final r in resources) {
    expect(find.descendant(of: page, matching: find.text(r.number)),
        findsOneWidget,
        reason: 'crisis page shows ${r.id} as the message does');
  }
  run.navKey.currentState!.pop();
  await tester.pumpAndSettle();
  expect(find.byType(EmergencySupportPage), findsNothing);
  expect(find.byType(CrisisChatMessage), findsOneWidget);
}

/// The acute flow (unchanged): the crisis page opens by itself; close it.
Future<void> _closeAcuteCrisisPage(WidgetTester tester, _Run run) async {
  final page = find.byType(EmergencySupportPage);
  expect(page, findsOneWidget, reason: 'acute opens the crisis page');
  expect(tester.widget<EmergencySupportPage>(page).from, 'acute_route');
  run.navKey.currentState!.pop();
  await _settle(tester);
}

/// The acute text never reached the model; the rule arm made no call.
void _expectModelCalls(_Run run) {
  if (run.rule) {
    expect(run.llm.calls, isEmpty, reason: 'rule arm: zero LLM calls');
    return;
  }
  for (final c in run.llm.calls) {
    expect(c.input, isNot(contains(_acute)),
        reason: 'acute input never reaches the model (${c.moduleId})');
  }
}

/// Nothing the message shows is ever sent to the model as history.
void _expectNotInHistory(_Run run) {
  final shown = [
    CrisisChatMessage.openingZh,
    for (final r in SafetyCopy.crisis.resources) r.number,
  ];
  for (final c in run.llm.calls) {
    for (final t in c.history) {
      for (final s in shown) {
        expect(t.text, isNot(contains(s)), reason: c.moduleId);
      }
      expect(t.text.trim(), isNotEmpty,
          reason: 'no empty turn in the history (${c.moduleId})');
    }
  }
}

void main() {
  late PhaseBConfig savedConfig;
  late BriefPrStore savedBriefStore;
  late RemoteFeatureFlags savedFlags;

  setUpAll(() {
    // The real config files, as the app loads them (no asset bundle).
    SafetyCopy.inject(
      acks: _json('functions/prompts/safety_acknowledgements.json'),
      crisis: _json('functions/prompts/crisis_resources.json'),
      fallbacks: _json('assets/config/llm_fallback_messages.json'),
    );
    // The one-time notes would cover the composer.
    SessionCloseHint.claimFirstUse();
    SessionCloseHint.claimLeaveFirstUse();
  });

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    savedConfig = PhaseBConfig.current;
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    savedBriefStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
    savedFlags = RemoteFeatureFlags.current;
    RemoteFeatureFlags.current = const RemoteFeatureFlags(
        checkInChatV2Enabled: true, reminiscenceV2Enabled: true);
  });

  tearDown(() {
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedBriefStore;
    RemoteFeatureFlags.current = savedFlags;
    ReminiscenceV2Stores.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
    SafetyCopy.inject(
        crisis: _json('functions/prompts/crisis_resources.json'));
  });

  group('the message itself', () {
    test('detection unchanged: the test sentence is acute', () {
      expect(const DistressDetector().analyze(_acute).level,
          DistressLevel.acute);
      expect(DistressDetector.wordlistVersion, 'v5-2026-09');
    });

    test('no number written in the widget or the chat pages', () {
      for (final path in [
        'lib/features/crisis/presentation/widgets/crisis_chat_message.dart',
        'lib/features/context/presentation/pages/siu_yan_chat_page.dart',
        'lib/features/context/presentation/pages/check_in_arm_a.dart',
        'lib/features/context/presentation/pages/check_in_arm_b.dart',
        'lib/features/curious_companion/presentation/pages/tung_tung_page.dart',
        'lib/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart',
        'lib/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart',
        'lib/features/reminiscence/presentation/pages/reminiscence_v2_page.dart',
        'lib/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart',
      ]) {
        final src = File(path).readAsStringSync();
        for (final r in SafetyCopy.crisis.resources) {
          if (r.number.length < 4) continue; // 999 also appears as e.g. radius
          expect(src, isNot(contains(r.number)), reason: '$path ${r.id}');
        }
        for (final n in ['撒瑪利亞', 'acuteAck']) {
          expect(src, isNot(contains(n)), reason: '$path $n');
        }
      }
    });

    testWidgets('lists whatever the config lists (a two-item config → two '
        'items, the crisis page the same)', (tester) async {
      final full = _json('functions/prompts/crisis_resources.json');
      final two = Map<String, dynamic>.from(full)
        ..['resources'] = (full['resources'] as List).take(2).toList();
      SafetyCopy.inject(crisis: two);
      expect(SafetyCopy.crisis.resources, hasLength(2));
      final run = _Run(null);
      await _open(
          tester,
          run,
          const Scaffold(body: SingleChildScrollView(child: CrisisChatMessage())));
      expect(_numbersOnScreen(tester), _expectedNumbers());
      expect(_expectedNumbers(), hasLength(2));
      await tester.tap(find.byKey(CrisisChatMessage.openButtonKey));
      await tester.pumpAndSettle();
      final page = find.byType(EmergencySupportPage);
      for (final r in SafetyCopy.crisis.resources) {
        expect(find.descendant(of: page, matching: find.text(r.number)),
            findsOneWidget);
      }
      expect(run.llm.calls, isEmpty);
    });
  });

  for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
    final name = arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';

    group('$name — pages both arms use', () {
      testWidgets('小欣 check-in: acute at Q3b', (tester) async {
        final run = _Run(arm);
        await _open(tester, run, _siuYan(run));
        for (final (q, code) in [('Q1', 'not_good'), ('Q2', 'none'), ('Q3', 'big')]) {
          await tester.tap(find.byKey(ValueKey('check_in_answer_${q}_$code')));
          await _settle(tester);
        }
        await _send(tester, _acute);
        await _closeAcuteCrisisPage(tester, run);
        await _expectCrisisMessage(tester, run);
        expect(run.checkIns.docs.values.single['stopped_by_safety'], isTrue);
        _expectModelCalls(run);
      }, skip: !_testable(arm));

      testWidgets('小欣 free chat: acute', (tester) async {
        final run = _Run(arm);
        await _open(tester, run, _siuYan(run, doneToday: true));
        await _send(tester, _acute);
        await _closeAcuteCrisisPage(tester, run);
        await _expectCrisisMessage(tester, run);
        _expectModelCalls(run);
        // Chatting on: the message is never sent to the model.
        await _send(tester, '我飲咗杯茶。');
        await _expectCrisisMessage(tester, run);
        _expectNotInHistory(run);
        _expectModelCalls(run);
      }, skip: !_testable(arm));

      testWidgets('通通: acute', (tester) async {
        final run = _Run(arm);
        await _open(tester, run, const TungTungPage());
        await _send(tester, _acute);
        await _closeAcuteCrisisPage(tester, run);
        await _expectCrisisMessage(tester, run);
        _expectModelCalls(run);
        await _send(tester, '我飲咗杯茶。');
        _expectNotInHistory(run);
        _expectModelCalls(run);
      }, skip: !_testable(arm));

      testWidgets('回憶 v2: acute at Q1', (tester) async {
        final run = _Run(arm)..installReminiscenceStores();
        await _open(
            tester,
            run,
            ReminiscenceV2Page(
                theme: ReminiscenceTheme.byIndex(1), clock: () => _now));
        await _send(tester, _acute,
            field: find.byKey(const Key('reminiscence_input')));
        await _closeAcuteCrisisPage(tester, run);
        await _expectCrisisMessage(tester, run);
        _expectModelCalls(run);
      }, skip: !_testable(arm));
    });
  }

  group('Hybrid-only pages', () {
    testWidgets('old 小欣 check-in (CheckInArmA): acute', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, const CheckInArmA(initialMoodValue: 4));
      await _send(tester, _acute);
      await _closeAcuteCrisisPage(tester, run);
      await _expectCrisisMessage(tester, run);
      _expectModelCalls(run);
      await _send(tester, '我飲咗杯茶。');
      _expectNotInHistory(run);
    }, skip: !_hybridTestable);

    testWidgets('回憶 v1 (ReminiscenceArmAPage): acute', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(
          tester, run, ReminiscenceArmAPage(theme: ReminiscenceTheme.all.first));
      await _send(tester, _acute);
      await _closeAcuteCrisisPage(tester, run);
      await _expectCrisisMessage(tester, run);
      _expectModelCalls(run);
      await _send(tester, '細個住喺深水埗。');
      _expectNotInHistory(run);
    }, skip: !_hybridTestable);

    testWidgets('反思對話: acute', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, const ReflectiveDialoguePage());
      await _send(tester, _acute);
      await _closeAcuteCrisisPage(tester, run);
      await _expectCrisisMessage(tester, run);
      _expectModelCalls(run);
      await _send(tester, '我飲咗杯茶。');
      _expectNotInHistory(run);
    }, skip: !_hybridTestable);

    testWidgets('acute on the model reply (output scan): the reply, then the '
        'same fixed message; the crisis page opens as before', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, _siuYan(run, doneToday: true));
      run.llm.reply = '你係咪話$_acute？';
      await _send(tester, '今日好攰。');
      await _closeAcuteCrisisPage(tester, run);
      await _expectCrisisMessage(tester, run);
    }, skip: !_hybridTestable);

    testWidgets('T7 filter still applies: a number in a model reply becomes '
        'the crisis-page link; no fixed message without acute',
        (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, _siuYan(run, doneToday: true));
      final other = _json('functions/prompts/crisis_resources.json');
      final samaritans = (other['resources'] as List)
          .cast<Map>()
          .firstWhere((r) => r['acuteTemplateReference'] == true);
      run.llm.reply = '可以打${samaritans['nameZh']} ${samaritans['number']}。';
      await _send(tester, '今日好攰。');
      expect(find.byType(HotlineLink), findsOneWidget);
      expect(_numbersOnScreen(tester), isEmpty,
          reason: 'the number was replaced by the link');
      expect(find.byType(CrisisChatMessage), findsNothing);
      expect(find.byType(EmergencySupportPage), findsNothing);
    }, skip: !_hybridTestable);
  });

  group('rule-arm forms (old check-in and 回憶 v1)', () {
    testWidgets('CheckInArmB: acute note', (tester) async {
      final run = _Run(null);
      await _open(tester, run, CheckInArmB(replyHistory: run.history));
      await tester.tap(find.text('😔'));
      await tester.tap(find.text('少少'));
      await tester.tap(find.text('麻麻'));
      await tester.tap(find.text('一啲小事'));
      await tester.enterText(find.byType(TextField), _acute);
      await tester.pump();
      await tester.tap(find.text('儲存今日 Check-in'));
      await _settle(tester);
      await _closeAcuteCrisisPage(tester, run);
      await _expectCrisisMessage(tester, run);
      expect(find.text('收到喇。聽日再見。'), findsNothing);
      expect(run.llm.calls, isEmpty, reason: 'rule arm: zero LLM calls');
    });

    testWidgets('CheckInArmB: a safe note shows no message', (tester) async {
      final run = _Run(null);
      await _open(tester, run, CheckInArmB(replyHistory: run.history));
      await tester.tap(find.text('🙂'));
      await tester.tap(find.text('少少'));
      await tester.tap(find.text('麻麻'));
      await tester.tap(find.text('一啲小事'));
      await tester.enterText(find.byType(TextField), '今日去咗飲茶');
      await tester.pump();
      await tester.tap(find.text('儲存今日 Check-in'));
      await _settle(tester);
      expect(find.byType(CrisisChatMessage), findsNothing);
      expect(find.byType(EmergencySupportPage), findsNothing);
    });

    testWidgets('ReminiscenceArmBPage: acute memory', (tester) async {
      final run = _Run(null);
      await _open(
          tester,
          run,
          ReminiscenceArmBPage(
              theme: ReminiscenceTheme.byIndex(1), replyHistory: run.history));
      await tester.enterText(find.byType(TextField), _acute);
      await tester.pump();
      await tester.tap(find.text('儲存呢段回憶'));
      await _settle(tester);
      await _closeAcuteCrisisPage(tester, run);
      await _expectCrisisMessage(tester, run);
      expect(run.llm.calls, isEmpty, reason: 'rule arm: zero LLM calls');
    });
  });

  group('moderate is unchanged (no fixed message)', () {
    for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
      testWidgets('小欣 free chat, ${arm.code}: moderate_interrupt',
          (tester) async {
        final run = _Run(arm);
        await _open(tester, run, _siuYan(run, doneToday: true));
        await _send(tester, '冇人理我');
        expect(find.byType(EmergencySupportPage), findsNothing);
        expect(find.byType(CrisisChatMessage), findsNothing);
        expect(find.text('我冇事，繼續'), findsOneWidget,
            reason: 'the moderate notice, as before');
        final ack = SafetyCopy.moderateAck('siu_yan', isEn: false)!;
        expect(find.textContaining(ack, findRichText: true), findsOneWidget);
        _expectModelCalls(run);
      }, skip: !_testable(arm));
    }
  });
}
