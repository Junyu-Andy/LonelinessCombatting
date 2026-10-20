// 1020 F / A (batch 2) — 小欣's one chat window behind the remote switch
// `checkInChatV2Enabled`, both arms:
//   - the check-in runs as bubbles with button replies, same questions,
//     buttons and order in both arms (Q3b answered / 唔講住; Q4 answered /
//     唔講住; Q1 唔想答 → XG);
//   - rule arm: X1–X5 by the Q1 band (no repeat of the last few), R4a / R4b,
//     SY0 when done, SY / SN free chat — and ZERO LLM calls;
//   - Hybrid: the LLM writes the two replies (prompt siu_yan_v3), R4b for
//     Q4 唔講住, an LLM opener when done;
//   - check_in_responses fields, the valid check-in session, the Brief PR
//     card (never pushed), safety hits (no template, safety flow);
//   - switch off: CheckInPage is exactly the old pages.
//
// Arm.of reads the profile's arm only in a Phase B build, so the two-arm
// cases run with:
//   flutter test --dart-define=PHASE_B=true test/check_in_chat_v2_test.dart
// (tool/ci_flutter_tests.sh "phase B arm gating").  In the default build
// everybody is Hybrid: the Hybrid and pure cases run, the rule-arm cases
// are skipped.  Synthetic data only; no Firebase.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/arm/arm_scope.dart';
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
import 'package:app_demo/core/safety/safety_copy.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_scheduler.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/pages/brief_pr_flow_page.dart';
import 'package:app_demo/features/brief_pr/presentation/pages/brief_pr_page.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/context/data/check_in_chat_copy.dart';
import 'package:app_demo/features/context/data/check_in_response_store.dart';
import 'package:app_demo/features/context/data/siu_yan_rule_chat_pool.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_a.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_b.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_page.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/crisis/presentation/pages/emergency_support_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_pool.dart';
import 'package:app_demo/features/researcher_dashboard/presentation/widgets/safety_alerts_section.dart';
import 'package:app_demo/features/today/data/mood_recorder.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _forced = String.fromEnvironment('FORCE_ARM');

/// The rule arm is reachable only in a Phase B build (profile arm B).
final bool _ruleTestable = FeatureFlags.phaseB && _forced != 'A';

/// Everybody is Hybrid in a Phase A build; Phase B needs profile arm A.
final bool _hybridTestable = !FeatureFlags.phaseB || _forced != 'B';

/// Both arms in one run (the parity test).
final bool _bothTestable = FeatureFlags.phaseB && _forced.isEmpty;

/// Fake model.  The rule arm must never get here: [forbid] makes any call
/// a test failure (also counted, in case a page swallows the throw).
class _FakeLlm implements LlmClient {
  _FakeLlm({this.forbid = false, this.failSkip = false});
  final bool forbid;

  /// 1020e 二.8: answer `[簽到·唔講住]` with nothing (→ R4b fallback).
  final bool failSkip;
  final calls = <({String moduleId, String? promptKey, String suffix,
      String input})>[];

  static const reply1 = '聽落你尋日都幾充實。';
  static const reply2 = '可以去附近公園行下，慢慢嚟。';
  static const opener = '今日想傾咩都得，我喺度。';
  static const chat = '好呀，再同我講多啲。';
  static const skip = '好，今日就慢慢嚟。';

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
    final suffix = contextSuffix ?? '';
    calls.add((
      moduleId: moduleId,
      promptKey: promptKey,
      suffix: suffix,
      input: userInput,
    ));
    if (forbid) {
      throw TestFailure('rule arm called the LLM ($moduleId)');
    }
    if (suffix.contains('[簽到·回應一]')) return const LlmRawResponse(text: reply1);
    if (suffix.contains('[簽到·回應二]')) return const LlmRawResponse(text: reply2);
    if (suffix.contains('[簽到·唔講住]')) {
      return LlmRawResponse(text: failSkip ? '' : skip);
    }
    if (suffix.contains('[開場·check-in 已做]')) {
      return const LlmRawResponse(text: opener);
    }
    return const LlmRawResponse(text: chat);
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

/// 09:30 on study day 7 (W0 10/14) → Q0 「早晨」, study week 1.
final _morning = DateTime(2026, 10, 21, 9, 30);

class _Run {
  _Run(this.arm);
  final ArmAssignment arm;
  late _FakeLlm llm;
  final store = InMemoryCheckInResponseStore();
  final history = InMemoryRuleReplyHistoryStore();
  final prompts = <(String, String, List<String>)>[];
  final navKey = GlobalKey<NavigatorState>();
  int actionPlans = 0;

  /// 1020e 二.8: the fake model fails the Q4 唔講住 call.
  bool failSkip = false;

  bool get rule => arm == ArmAssignment.b;

  Map<String, dynamic> get record {
    expect(store.docs, hasLength(1), reason: 'one check-in record');
    return store.docs.values.single;
  }

  Map<String, dynamic> answer(String q) =>
      Map<String, dynamic>.from(record['answers'][q] as Map);
}

Widget _harness(_Run run, {Widget? home}) {
  run.llm = _FakeLlm(forbid: run.rule, failSkip: run.failSkip);
  final llm = LlmGateway(client: run.llm);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  return AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh'), profile: _profile(run.arm)),
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
            home: home ?? const Scaffold(body: Text('home')),
          ),
        ),
      ),
    ),
  );
}

SiuYanChatPage _page(
  _Run run, {
  bool doneToday = false,
  int? moodToday,
  DateTime? now,
  bool lowMoodEntry = false,
}) =>
    SiuYanChatPage(
      lowMoodEntry: lowMoodEntry,
      checkedInToday: (_) async => doneToday,
      latestMoodToday: (_) async => moodToday,
      responseStore: run.store,
      replyHistory: run.history,
      clock: () => now ?? _morning,
      onOpenActionPlan: (_) async => run.actionPlans++,
      onPromptShown: (id, text, buttons) => run.prompts.add((id, text, buttons)),
    );

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

/// Lets the 700 ms template pause and any fake-LLM future finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _tapAnswer(WidgetTester tester, String q, String code) async {
  await tester.tap(find.byKey(ValueKey('check_in_answer_${q}_$code')));
  await _settle(tester);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await _settle(tester);
}

Future<void> _skip(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('check_in_skip')));
  await _settle(tester);
}

Finder _says(String text) => find.textContaining(text, findRichText: true);

/// Q1 → Q6 with the given answers.  [q3b] / [q4]: null = 唔講住.
Future<void> _checkIn(
  WidgetTester tester, {
  String q1 = 'good',
  String q2 = 'a_little',
  String q3 = 'small',
  String? q3b = '同阿女去咗飲茶',
  String? q4 = '下晝去公園行下',
  String q5 = 'no',
}) async {
  await _tapAnswer(tester, 'Q1', q1);
  await _tapAnswer(tester, 'Q2', q2);
  await _tapAnswer(tester, 'Q3', q3);
  if (CheckInChatCopy.q3OpensQ3b.contains(q3)) {
    expect(_says(CheckInChatCopy.q3b), findsOneWidget);
    if (q3b == null) {
      await _skip(tester);
    } else {
      await _type(tester, q3b);
    }
  }
  expect(_says(CheckInChatCopy.q4), findsOneWidget);
  if (q4 == null) {
    await _skip(tester);
  } else {
    await _type(tester, q4);
  }
  expect(_says(CheckInChatCopy.q5), findsOneWidget);
  await _tapAnswer(tester, 'Q5', q5);
}

String _x(String id) =>
    RuleReplyPool.checkInChatEntries.firstWhere((e) => e.id == id).zh;

void main() {
  late PhaseBConfig savedConfig;
  late BriefPrStore savedBriefStore;
  late RemoteFeatureFlags savedFlags;
  late InMemoryBriefPrStore briefStore;

  // The one-time 「今日傾到呢度」 note would cover the composer.
  setUpAll(SessionCloseHint.claimFirstUse);

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    savedConfig = PhaseBConfig.current;
    // Session v2 on (the Phase B setting): valid sessions, Brief PR card.
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    savedBriefStore = BriefPrV2.store;
    briefStore = InMemoryBriefPrStore();
    BriefPrV2.store = briefStore;
    savedFlags = RemoteFeatureFlags.current;
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(checkInChatV2Enabled: true);
  });

  tearDown(() {
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedBriefStore;
    RemoteFeatureFlags.current = savedFlags;
    ChatSessionRecorder.resetProcessStateForTest();
  });

  group('copy and pools (pure)', () {
    test('Q0: 早晨 before noon, 你好 from 12:00', () {
      expect(CheckInChatCopy.q0(DateTime(2026, 10, 21, 11, 59)),
          '早晨！想問下你尋日嘅情況，幾條就得。');
      expect(CheckInChatCopy.q0(DateTime(2026, 10, 21, 12, 0)),
          '你好！想問下你尋日嘅情況，幾條就得。');
    });

    test('Q1 buttons map to X1 … X5 by band; 唔想答 has none', () {
      final bands = [
        for (final o in CheckInChatCopy.q1Options)
          RuleReplyPool.checkInChatSubPool(o.code).map((e) => e.id).toList(),
      ];
      // 1020e 二.12: buttons low → high (好唔開心 … 好開心), scores 1–5.
      expect(bands, [
        ['X5-1', 'X5-2', 'X5-3', 'X5-4'],
        ['X4-1', 'X4-2', 'X4-3', 'X4-4'],
        ['X3-1', 'X3-2', 'X3-3', 'X3-4'],
        ['X2-1', 'X2-2', 'X2-3', 'X2-4'],
        ['X1-1', 'X1-2', 'X1-3', 'X1-4'],
        <String>[],
      ]);
      expect([for (final o in CheckInChatCopy.q1Options) o.score],
          [1, 2, 3, 4, 5, null]);
    });

    test('SY / SN go round the whole group; never a repeat within the '
        'last few', () {
      List<String> run(bool low, int n) {
        var recent = <String>[];
        final out = <String>[];
        for (var i = 0; i < n; i++) {
          final e = SiuYanRuleChatPool.pick(low: low, recent: recent);
          out.add(e.id);
          recent = SiuYanRuleChatPool.remember(recent, e.id);
        }
        return out;
      }

      final general = run(false, 8);
      expect(general, ['SY1', 'SY2', 'SY3', 'SY4', 'SY5', 'SY6', 'SY1', 'SY2']);
      final low = run(true, 6);
      expect(low, ['SN1', 'SN2', 'SN3', 'SN4', 'SN1', 'SN2']);
      for (final seq in [general, low]) {
        for (var i = 3; i < seq.length; i++) {
          expect(seq.sublist(i - 3, i), isNot(contains(seq[i])));
        }
      }
      // Mood turning low mid-way: SN, without repeating its own recent.
      expect(
          SiuYanRuleChatPool.pick(low: true, recent: const ['SY1', 'SN1']).id,
          'SN2');
    });

    test('the only button labels the Hybrid page ever sends as the turn '
        '(Q3, 唔講住 — when nothing was typed) match no lexicon term', () {
      const detector = DistressDetector();
      for (final label in [
        for (final o in CheckInChatCopy.q3Options) o.label,
        CheckInChatCopy.skipLabel,
      ]) {
        expect(detector.analyze(label).level, DistressLevel.none,
            reason: label);
      }
      // Q1's 好唔開心 is a `low` lexicon hit (no safety event); it is never
      // the turn text: a question bubble always follows it.
      expect(detector.analyze('好唔開心').level, DistressLevel.low);
    });

    test('low mood: daily_mood 1 or 2, or a low-mood opener', () {
      expect(SiuYanRuleChatPool.isLow(latestMoodToday: 1), isTrue);
      expect(SiuYanRuleChatPool.isLow(latestMoodToday: 2), isTrue);
      expect(SiuYanRuleChatPool.isLow(latestMoodToday: 3), isFalse);
      expect(SiuYanRuleChatPool.isLow(), isFalse);
      expect(SiuYanRuleChatPool.isLow(lowMoodEntry: true), isTrue);
    });

    test('a completed chat check-in is a valid session in both arms', () {
      const rules = SessionRules(v2: true, idleTimeoutMin: 30);
      const done = SessionTally(
        sessionType: SessionType.checkIn,
        userMessageCount: 2,
        replyCount: 2,
        checkInCompleted: true,
      );
      const notDone = SessionTally(
        sessionType: SessionType.checkIn,
        userMessageCount: 1,
        replyCount: 1,
      );
      expect(rules.isValid(done), isTrue);
      expect(rules.isValid(notDone), isFalse, reason: 'no mood, not done');
      expect(SessionTally.fromMap(done.toMap()).checkInCompleted, isTrue);
      expect(notDone.toMap().containsKey('checkInCompleted'), isFalse,
          reason: 'old rows unchanged');
      expect(SessionType.forModule(SiuYanChatPage.chatModule),
          SessionType.freeChat);
    });
  });

  group('switch off — the old pages, unchanged', () {
    // What CheckInPage builds, without pumping CheckInArmA (its mood
    // lookup needs Firebase).
    Future<Widget> built(WidgetTester tester) async {
      late Widget out;
      final run = _Run(ArmAssignment.a);
      await tester.pumpWidget(_harness(run,
          home: Builder(builder: (context) {
            out = const CheckInPage().build(context);
            return const SizedBox();
          })));
      return out;
    }

    testWidgets('off (field missing / not true): the old ArmGate — Hybrid '
        'CheckInArmA, rule arm CheckInArmB', (tester) async {
      for (final flags in [
        const RemoteFeatureFlags(),
        RemoteFeatureFlags.fromMap(const {'checkInChatV2Enabled': 'true'}),
        RemoteFeatureFlags.fromMap(const {'checkInChatV2Enabled': 1}),
      ]) {
        RemoteFeatureFlags.current = flags;
        final w = await built(tester);
        expect(w, isA<ArmGate>());
        final gate = w as ArmGate;
        final ctx = tester.element(find.byType(SizedBox).first);
        expect(gate.armA(ctx), isA<CheckInArmA>());
        expect(gate.armB(ctx), isA<CheckInArmB>());
      }
    });

    testWidgets('on (literally true): the chat window for both arms',
        (tester) async {
      RemoteFeatureFlags.current =
          RemoteFeatureFlags.fromMap(const {'checkInChatV2Enabled': true});
      expect(await built(tester), isA<SiuYanChatPage>());
    });

    testWidgets('off, rule arm: the old form page opens, no chat window',
        (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags();
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, const CheckInPage());
      expect(find.byType(SiuYanChatPage), findsNothing);
      expect(find.byType(CheckInArmB), findsOneWidget);
      expect(find.text('你今日點呀？'), findsOneWidget);
      expect(find.text('儲存今日 Check-in'), findsOneWidget);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);
  });

  group('rule arm', () {
    testWidgets('full check-in, Q3b and Q4 answered: X by Q1, R4a, '
        'records, valid session, card not pushed, zero LLM calls',
        (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run));
      expect(_says('早晨！想問下你尋日嘅情況，幾條就得。'), findsOneWidget);
      expect(_says(CheckInChatCopy.q1), findsOneWidget);
      await _checkIn(tester, q1: 'good');
      expect(_says(_x('X2-1')), findsOneWidget, reason: 'reply 1 = X2');
      expect(_says(CheckInChatCopy.r4a), findsOneWidget, reason: 'reply 2');
      expect(_says(CheckInChatCopy.r4b), findsNothing);
      expect(_says(CheckInChatCopy.q6), findsOneWidget);
      expect(run.actionPlans, 0, reason: '唔使喇');

      final r = run.record;
      expect(r['arm'], 'B');
      expect(r['flow'], 'chat_v2');
      expect(r['schema_version'], 2);
      expect(r['date_iso'], '2026-10-21');
      expect(r['study_day'], 7);
      expect(r['study_week'], 1);
      expect(r['completed'], isTrue);
      expect(r['session_id'], isNotNull);
      expect(r['response1_id'], 'X2-1');
      expect(r['response2_id'], 'R4a');
      expect(r['questions_shown'],
          ['Q0', 'Q1', 'Q2', 'Q3', 'Q3b', 'Q4', 'Q5', 'Q6']);
      expect(run.answer('Q1'), {
        'question_id': 'Q1',
        'value': 'good',
        'label': '幾好',
        'score': 4,
      });
      expect(run.answer('Q2'),
          {'question_id': 'Q2', 'value': 'a_little', 'label': '少少', 'index': 1});
      expect(run.answer('Q3'),
          {'question_id': 'Q3', 'value': 'small', 'label': '一啲小事', 'index': 1});
      expect(run.answer('Q3b'),
          {'question_id': 'Q3b', 'skipped': false, 'text': '同阿女去咗飲茶'});
      expect(run.answer('Q4'),
          {'question_id': 'Q4', 'skipped': false, 'text': '下晝去公園行下'});
      expect(run.answer('Q5')['value'], 'no');
      expect(await run.history.recent(uid: 'u1', agentId: 'siu_yan'),
          ['X2-1']);

      // Leaving: the check-in session is valid → one pending invitation
      // (the card), and nothing is pushed.
      await tester.tap(find.text('今日傾到呢度'));
      await _settle(tester);
      expect(find.byType(SiuYanChatPage), findsNothing);
      expect(find.byType(BriefPrPage), findsNothing);
      expect(find.byType(BriefPrFlowPage), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(briefStore.records, hasLength(1));
      final invite = briefStore.records.values.single;
      expect(invite.sessionType, 'check_in');
      expect(invite.sessionId, r['session_id']);
      expect(invite.isPending, isTrue);
      expect(run.llm.calls, isEmpty, reason: 'rule arm: zero LLM calls');
    }, skip: !_ruleTestable);

    testWidgets('Q3b and Q4 唔講住: X still shown, R4b', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run));
      await _checkIn(tester, q1: 'very_unhappy', q3: 'big', q3b: null, q4: null);
      expect(_says(_x('X5-1')), findsOneWidget);
      expect(_says(CheckInChatCopy.r4b), findsOneWidget);
      expect(_says(CheckInChatCopy.r4a), findsNothing);
      expect(run.answer('Q3b'),
          {'question_id': 'Q3b', 'skipped': true, 'text': null});
      expect(run.answer('Q4'),
          {'question_id': 'Q4', 'skipped': true, 'text': null});
      expect(run.record['response2_id'], 'R4b');
      expect(run.record['completed'], isTrue);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('Q1 唔想答 → XG; Q3 冇 skips Q3b; Q5 好呀 opens the plan',
        (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run));
      await _checkIn(tester, q1: 'prefer_not', q3: 'none', q5: 'yes');
      expect(_says(CheckInChatCopy.xg), findsOneWidget);
      expect(_says(CheckInChatCopy.q3b), findsNothing);
      expect(run.record['response1_id'], 'XG');
      expect(run.answer('Q1')['score'], isNull);
      expect(run.record['answers'].containsKey('Q3b'), isFalse);
      expect(run.record['questions_shown'],
          ['Q0', 'Q1', 'Q2', 'Q3', 'Q4', 'Q5', 'Q6']);
      expect(run.actionPlans, 1);
      expect(_says(CheckInChatCopy.q6), findsOneWidget);
      expect(await run.history.recent(uid: 'u1', agentId: 'siu_yan'), isEmpty);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('X rotation: the next check-in in the same band gets the '
        'next template (no repeat of the last 3)', (tester) async {
      final run = _Run(ArmAssignment.b);
      await run.history.save(
          uid: 'u1', agentId: 'siu_yan', recent: const ['X3-1', 'X3-2']);
      await _open(tester, run, _page(run));
      await _checkIn(tester, q1: 'so_so', q3: 'none');
      expect(_says(_x('X3-3')), findsOneWidget);
      expect(_says(_x('X3-1')), findsNothing);
      expect(await run.history.recent(uid: 'u1', agentId: 'siu_yan'),
          ['X3-1', 'X3-2', 'X3-3']);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('free chat after the check-in: SY lines rotate, same '
        'session, zero LLM calls', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run));
      await _checkIn(tester, q3: 'none', q4: null);
      await _type(tester, '今日天氣幾好');
      await _type(tester, '想出去行下');
      await _type(tester, '聽日見');
      expect(_says(SiuYanRuleChatPool.general[0].zh), findsOneWidget);
      expect(_says(SiuYanRuleChatPool.general[1].zh), findsOneWidget);
      expect(_says(SiuYanRuleChatPool.general[2].zh), findsOneWidget);
      expect(await run.history.recent(uid: 'u1', agentId: 'siu_yan_chat'),
          ['SY1', 'SY2', 'SY3']);
      await tester.tap(find.text('今日傾到呢度'));
      await _settle(tester);
      expect(briefStore.records, hasLength(1), reason: 'one session');
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('check-in already done: SY0, then SY replies; ≥3 replied '
        'messages make a valid free-chat session', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run, doneToday: true));
      expect(_says(CheckInChatCopy.sy0), findsOneWidget);
      expect(_says(CheckInChatCopy.q1), findsNothing);
      expect(run.prompts.map((p) => p.$1), ['SY0']);
      await _type(tester, '今朝去咗街市');
      await _type(tester, '買咗啲菜');
      expect(_says(SiuYanRuleChatPool.general[0].zh), findsOneWidget);
      expect(_says(SiuYanRuleChatPool.general[1].zh), findsOneWidget);
      await tester.tap(find.text('今日傾到呢度'));
      await _settle(tester);
      expect(briefStore.records, isEmpty, reason: '2 messages: not valid');
      expect(run.store.docs, isEmpty, reason: 'no check-in record');
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('three replied messages → valid free chat (card)',
        (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run, doneToday: true));
      await _type(tester, '一');
      await _type(tester, '二');
      await _type(tester, '三');
      await tester.tap(find.text('今日傾到呢度'));
      await _settle(tester);
      expect(briefStore.records, hasLength(1));
      expect(briefStore.records.values.single.sessionType, 'free_chat');
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('low mood today (daily_mood 2): SN lines', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run, doneToday: true, moodToday: 2));
      await _type(tester, '今日好攰');
      await _type(tester, '瞓唔著');
      expect(_says(SiuYanRuleChatPool.low[0].zh), findsOneWidget);
      expect(_says(SiuYanRuleChatPool.low[1].zh), findsOneWidget);
      expect(_says(SiuYanRuleChatPool.general[0].zh), findsNothing);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('acute at Q3b: no template, crisis page, check-in stops',
        (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run));
      await _tapAnswer(tester, 'Q1', 'not_good');
      await _tapAnswer(tester, 'Q2', 'none');
      await _tapAnswer(tester, 'Q3', 'big');
      await _type(tester, '我真係想死');
      expect(find.byType(EmergencySupportPage), findsOneWidget);
      run.navKey.currentState!.pop();
      await _settle(tester);
      for (final e in RuleReplyPool.checkInChatEntries) {
        expect(_says(e.zh), findsNothing);
      }
      expect(_says(SafetyCopy.acuteAck('siu_yan', isEn: false)), findsOneWidget);
      expect(_says(CheckInChatCopy.q4), findsNothing);
      expect(run.record['stopped_by_safety'], isTrue);
      expect(run.record['completed'], isFalse);
      expect(run.record['response1_id'], 'none_safety');
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('moderate at Q4: no R4a, support sheet, then Q5',
        (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run));
      await _tapAnswer(tester, 'Q1', 'so_so');
      await _tapAnswer(tester, 'Q2', 'none');
      await _tapAnswer(tester, 'Q3', 'none');
      await _type(tester, '冇人理我');
      expect(find.text('我冇事，繼續'), findsOneWidget, reason: 'support sheet');
      await tester.tap(find.text('我冇事，繼續'));
      await _settle(tester);
      expect(_says(CheckInChatCopy.r4a), findsNothing);
      // The S-3 support line, when the acknowledgements JSON is loaded
      // (not in unit tests).
      final ack = SafetyCopy.moderateAck('siu_yan', isEn: false);
      if (ack != null) expect(_says(ack), findsOneWidget);
      expect(_says(CheckInChatCopy.q5), findsOneWidget);
      expect(run.record['response2_id'], 'none_safety');
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('the Brief PR questionnaire offers 唔評住 (skip) in the '
        'rule arm too', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run));
      await _checkIn(tester, q3: 'none', q4: null);
      await tester.tap(find.text('今日傾到呢度'));
      await _settle(tester);
      final invite = briefStore.records.values.single;
      run.navKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => BriefPrFlowPage(
          record: invite,
          scheduler: BriefPrScheduler(
            store: briefStore,
            rules: const SessionRules(v2: true, idleTimeoutMin: 30),
            processStartedAt: DateTime(2026, 10, 21),
          ),
        ),
      ));
      await _settle(tester);
      expect(find.text(BriefPrFlowPage.abandonLabel), findsOneWidget);
      await tester.tap(find.text(BriefPrFlowPage.abandonLabel));
      await _settle(tester);
      expect(briefStore.records.values.single.finalStatus, 'skipped');
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);
  });

  group('Hybrid arm', () {
    testWidgets('full check-in: LLM writes reply 1 and 2 (siu_yan_v3), '
        'questions fixed, records, valid session', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, _page(run));
      await _checkIn(tester, q1: 'good');
      expect(_says(_FakeLlm.reply1), findsOneWidget);
      expect(_says(_FakeLlm.reply2), findsOneWidget);
      for (final e in RuleReplyPool.checkInChatEntries) {
        expect(_says(e.zh), findsNothing, reason: 'no rule template');
      }
      expect(_says(CheckInChatCopy.q6), findsOneWidget);
      expect(run.llm.calls, hasLength(2));
      final c1 = run.llm.calls[0];
      expect(c1.promptKey, 'siu_yan_v3');
      expect(c1.moduleId, 'm2_check_in');
      expect(c1.suffix, contains('[簽到·回應一]'));
      expect(c1.suffix, contains('Q1 尋日成日整體過得點：幾好'));
      expect(c1.suffix, contains('Q2 尋日有冇同人傾過偈：少少'));
      expect(c1.suffix, contains('Q3 尋日有冇咩特別事：一啲小事'));
      expect(c1.input, '同阿女去咗飲茶');
      final c2 = run.llm.calls[1];
      expect(c2.suffix, contains('[簽到·回應二]'));
      expect(c2.input, '下晝去公園行下');

      final r = run.record;
      expect(r['arm'], 'A');
      expect(r['response1_id'], 'llm');
      expect(r['response2_id'], 'llm');
      expect(r['completed'], isTrue);
      expect(run.answer('Q3b')['text'], '同阿女去咗飲茶');

      // Chatting on: same session, the LLM gets today's answers.
      await _type(tester, '今日都幾好');
      expect(_says(_FakeLlm.chat), findsOneWidget);
      expect(run.llm.calls.last.suffix, contains('[今日 check-in]'));
      await tester.tap(find.text('今日傾到呢度'));
      await _settle(tester);
      expect(find.byType(BriefPrPage), findsNothing);
      expect(briefStore.records, hasLength(1));
      expect(briefStore.records.values.single.sessionType, 'check_in');
    }, skip: !_hybridTestable);

    testWidgets('Q3b and Q4 唔講住: reply 1 from the LLM; reply 2 = one '
        'sentence from the LLM ([簽到·唔講住], 1020e 二.8)', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, _page(run));
      await _checkIn(tester, q3: 'small', q3b: null, q4: null);
      expect(run.llm.calls, hasLength(2), reason: 'reply 1 and reply 2');
      expect(run.llm.calls.first.input, '唔講住');
      expect(run.llm.calls.first.suffix,
          contains('Q3b 係咩事：（用戶揀咗「唔講住」）'));
      final skip = run.llm.calls.last;
      expect(skip.promptKey, 'siu_yan_v3');
      expect(skip.input, '唔講住');
      expect(skip.suffix, contains('[簽到·唔講住]'));
      expect(skip.suffix, contains('Q4 今日有咩打算：（用戶揀咗「唔講住」）'));
      expect(skip.suffix, isNot(contains('[簽到·回應二]')));
      expect(_says(_FakeLlm.reply1), findsOneWidget);
      expect(_says(_FakeLlm.skip), findsOneWidget);
      expect(_says(CheckInChatCopy.r4b), findsNothing);
      expect(_says(_FakeLlm.reply2), findsNothing);
      expect(run.record['response2_id'], 'llm');
      expect(_says(CheckInChatCopy.q5), findsOneWidget);
    }, skip: !_hybridTestable);

    testWidgets('Q4 唔講住, model fails → the fixed R4b, logged llm_fallback',
        (tester) async {
      final run = _Run(ArmAssignment.a)..failSkip = true;
      await _open(tester, run, _page(run));
      await _checkIn(tester, q3: 'none', q4: null);
      expect(run.llm.calls.last.suffix, contains('[簽到·唔講住]'));
      expect(_says(CheckInChatCopy.r4b), findsOneWidget);
      expect(run.record['response2_id'], 'llm_fallback');
      expect(_says(CheckInChatCopy.q5), findsOneWidget);
    }, skip: !_hybridTestable);

    testWidgets('Q1 唔想答: LLM reply 1 (no XG), answers in the prompt',
        (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, _page(run));
      await _checkIn(tester, q1: 'prefer_not', q3: 'none');
      expect(_says(CheckInChatCopy.xg), findsNothing);
      expect(_says(_FakeLlm.reply1), findsOneWidget);
      expect(run.llm.calls.first.suffix,
          contains('Q1 尋日成日整體過得點：唔想答'));
      expect(run.llm.calls.first.input, '冇', reason: 'the Q3 button');
      expect(run.record['response1_id'], 'llm');
    }, skip: !_hybridTestable);

    testWidgets('check-in already done: an LLM opener, then the LLM chat',
        (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, _page(run, doneToday: true));
      expect(_says(_FakeLlm.opener), findsOneWidget);
      expect(_says(CheckInChatCopy.q1), findsNothing);
      expect(run.llm.calls.single.moduleId, 'greeting_siu_yan');
      expect(run.llm.calls.single.suffix, contains('[開場·check-in 已做]'));
      await _type(tester, '今日去咗街市');
      expect(_says(_FakeLlm.chat), findsOneWidget);
      expect(run.llm.calls.last.moduleId, 'm2_check_in');
    }, skip: !_hybridTestable);

    testWidgets('acute at Q4: gateway short-circuits (no model call), crisis '
        'page, check-in stops', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, _page(run));
      await _tapAnswer(tester, 'Q1', 'so_so');
      await _tapAnswer(tester, 'Q2', 'none');
      await _tapAnswer(tester, 'Q3', 'none');
      final before = run.llm.calls.length;
      await _type(tester, '我真係想死');
      expect(find.byType(EmergencySupportPage), findsOneWidget);
      run.navKey.currentState!.pop();
      await _settle(tester);
      expect(run.llm.calls.length, before, reason: 'acute never reaches it');
      expect(_says(CheckInChatCopy.q5), findsNothing);
      expect(run.record['stopped_by_safety'], isTrue);
    }, skip: !_hybridTestable);
  });

  testWidgets('both arms: identical question texts, buttons and order',
      (tester) async {
    Future<List<(String, String, List<String>)>> walk(ArmAssignment arm) async {
      ChatSessionRecorder.resetProcessStateForTest();
      final run = _Run(arm);
      await _open(tester, run, _page(run));
      await _checkIn(tester, q3: 'small', q5: 'yes');
      return run.prompts;
    }

    final a = await walk(ArmAssignment.a);
    final b = await walk(ArmAssignment.b);
    expect(a.map((p) => p.$1).toList(),
        ['Q0', 'Q1', 'Q2', 'Q3', 'Q3b', 'Q4', 'Q5', 'Q6']);
    expect(b.length, a.length);
    for (var i = 0; i < a.length; i++) {
      expect(b[i].$1, a[i].$1);
      expect(b[i].$2, a[i].$2, reason: a[i].$1);
      expect(b[i].$3, a[i].$3, reason: a[i].$1);
    }
    expect(a[1].$3, ['好唔開心', '唔係幾好', '一般般', '幾好', '好開心', '唔想答']);
    expect(a[2].$3, ['冇', '少少', '幾多', '好多']);
    expect(a[3].$3, ['冇', '一啲小事', '一件大事']);
    expect(a[6].$3, ['好呀', '唔使喇']);
  }, skip: !_bothTestable);

  testWidgets('afternoon: Q0 says 你好', (tester) async {
    final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
    await _open(
        tester, run, _page(run, now: DateTime(2026, 10, 21, 15, 0)));
    expect(_says('你好！想問下你尋日嘅情況，幾條就得。'), findsOneWidget);
    expect(_says('早晨！'), findsNothing);
  });

  // 1020e 二.10 — rule arm: moderate_review (grief, past hardship; logged,
  // no pop-up) gets an SN line; moderate_interrupt / acute get none.
  group('rule arm, moderate_review → SN', () {
    const grief = '老伴走咗之後好難過';

    test('the grief example is a moderate_review hit', () {
      expect(const DistressDetector().analyze(grief).level,
          DistressLevel.moderateReview);
    });

    testWidgets('free chat: an SN line (even on a good-mood day), no sheet',
        (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run, doneToday: true, moodToday: 5));
      await _type(tester, grief);
      expect(_says(SiuYanRuleChatPool.low[0].zh), findsOneWidget);
      expect(_says(SiuYanRuleChatPool.general[0].zh), findsNothing);
      expect(find.text('我冇事，繼續'), findsNothing, reason: 'no pop-up');
      await _type(tester, '今日天氣幾好');
      expect(_says(SiuYanRuleChatPool.general[0].zh), findsOneWidget,
          reason: 'a plain message is back to SY');
      expect(await run.history.recent(uid: 'u1', agentId: 'siu_yan_chat'),
          ['SN1', 'SY1']);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('free chat: moderate_interrupt still gets no line',
        (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run, doneToday: true));
      await _type(tester, '冇人理我');
      await tester.tap(find.text('我冇事，繼續'));
      await _settle(tester);
      for (final e in [...SiuYanRuleChatPool.general,
        ...SiuYanRuleChatPool.low]) {
        expect(_says(e.zh), findsNothing);
      }
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('check-in Q3b / Q4: an SN line instead of X / R4a, then on',
        (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run));
      await _checkIn(tester, q1: 'very_happy', q3: 'big', q3b: grief,
          q4: '$grief，今日唔知做咩好');
      expect(_says(SiuYanRuleChatPool.low[0].zh), findsOneWidget);
      expect(_says(SiuYanRuleChatPool.low[1].zh), findsOneWidget);
      for (final e in RuleReplyPool.checkInChatSubPool('very_happy')) {
        expect(_says(e.zh), findsNothing, reason: 'no X1 after grief');
      }
      expect(_says(CheckInChatCopy.r4a), findsNothing);
      expect(run.record['response1_id'], 'SN1');
      expect(run.record['response2_id'], 'SN2');
      expect(run.record['completed'], isTrue);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);
  });

  // 1020e 二.9 — acute stops the check-in; once the researcher marks the
  // alert 誤觸 (server writes falseAlarm on the row) the same day's next
  // visit resumes at the stopped question; the next day it does not.
  group('false alarm (誤觸) resume', () {
    Map<String, dynamic> stoppedRow({
      String date = '2026-10-21',
      String at = 'Q3b',
      bool marked = true,
    }) =>
        {
          'uid': 'u1',
          'arm': 'B',
          'flow': 'chat_v2',
          'schema_version': 2,
          'date_iso': date,
          'study_day': 7,
          'study_week': 1,
          'session_id': 's_old',
          'answers': {
            'Q1': {'question_id': 'Q1', 'value': 'not_good',
              'label': '唔係幾好', 'score': 2},
            'Q2': {'question_id': 'Q2', 'value': 'none', 'label': '冇',
              'index': 0},
            'Q3': {'question_id': 'Q3', 'value': 'big', 'label': '一件大事',
              'index': 2},
            if (at == 'Q4')
              'Q3b': {'question_id': 'Q3b', 'skipped': true, 'text': null},
            at: {'question_id': at, 'skipped': false, 'text': '（停低嗰句）'},
          },
          'questions_shown': [
            'Q0', 'Q1', 'Q2', 'Q3', 'Q3b', if (at == 'Q4') 'Q4',
          ],
          'response1_id': at == 'Q4' ? 'X4-1' : 'none_safety',
          'response2_id': null,
          'stopped_by_safety': true,
          'stopped_at': at,
          'completed': false,
          if (marked) 'falseAlarm': true,
          if (marked) 'markedBy': 'r1',
          if (marked) 'markedAt': '2026-10-21T02:00:00Z',
        };

    for (final arm in [ArmAssignment.b, ArmAssignment.a]) {
      final tag = arm == ArmAssignment.b ? 'rule' : 'Hybrid';
      testWidgets('$tag: stopped at Q3b, marked → resumes at Q3b and '
          'finishes; a new row, the old one untouched', (tester) async {
        final run = _Run(arm);
        run.store.docs['ci_old'] = stoppedRow();
        await _open(tester, run, _page(run));
        expect(_says(CheckInChatCopy.q3b), findsOneWidget);
        expect(_says(CheckInChatCopy.q1), findsNothing, reason: 'no restart');
        expect(_says('早晨！'), findsNothing);
        expect(run.prompts.map((p) => p.$1).first, 'Q3b');
        await _type(tester, '同阿女去咗飲茶');
        expect(_says(CheckInChatCopy.q4), findsOneWidget);
        await _type(tester, '下晝去公園行下');
        await _tapAnswer(tester, 'Q5', 'no');
        expect(_says(CheckInChatCopy.q6), findsOneWidget);
        expect(run.store.docs, hasLength(2));
        final fresh = run.store.docs.entries
            .firstWhere((e) => e.key != 'ci_old')
            .value;
        expect(fresh['resumed_from'], 'ci_old');
        expect(fresh['completed'], isTrue);
        expect(fresh['stopped_by_safety'], isFalse);
        expect(fresh.containsKey('falseAlarm'), isFalse,
            reason: 'the App never writes the mark');
        final answers = Map<String, dynamic>.from(fresh['answers'] as Map);
        expect(answers['Q1']['value'], 'not_good', reason: 'carried over');
        expect(answers['Q3']['value'], 'big');
        expect(answers['Q3b']['text'], '同阿女去咗飲茶');
        expect(fresh['questions_shown'],
            ['Q0', 'Q1', 'Q2', 'Q3', 'Q3b', 'Q4', 'Q5', 'Q6']);
        expect(run.store.docs['ci_old']!['completed'], isFalse);
        expect(run.store.docs['ci_old']!['falseAlarm'], isTrue);
        if (arm == ArmAssignment.b) {
          expect(_says(_x('X4-1')), findsOneWidget, reason: 'Q1 band kept');
          expect(run.llm.calls, isEmpty);
        } else {
          expect(run.llm.calls.first.suffix,
              contains('Q1 尋日成日整體過得點：唔係幾好'));
        }
        // Valid session: the invitation card is scheduled.
        await tester.tap(find.text('今日傾到呢度'));
        await _settle(tester);
        expect(briefStore.records, hasLength(1));
      }, skip: arm == ArmAssignment.b ? !_ruleTestable : !_hybridTestable);

      testWidgets('$tag: stopped at Q4, marked → resumes at Q4',
          (tester) async {
        final run = _Run(arm);
        run.store.docs['ci_old'] = stoppedRow(at: 'Q4');
        await _open(tester, run, _page(run));
        expect(_says(CheckInChatCopy.q4), findsOneWidget);
        expect(_says(CheckInChatCopy.q3b), findsNothing);
        await _skip(tester);
        expect(_says(CheckInChatCopy.q5), findsOneWidget);
        await _tapAnswer(tester, 'Q5', 'no');
        final fresh = run.store.docs.entries
            .firstWhere((e) => e.key != 'ci_old')
            .value;
        expect(fresh['response1_id'], 'X4-1', reason: 'reply 1 carried');
        expect(fresh['completed'], isTrue);
        if (arm == ArmAssignment.b) expect(run.llm.calls, isEmpty);
      }, skip: arm == ArmAssignment.b ? !_ruleTestable : !_hybridTestable);
    }

    testWidgets('the next day: no resume, a fresh check-in', (tester) async {
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
      run.store.docs['ci_old'] = stoppedRow(date: '2026-10-20');
      await _open(tester, run, _page(run));
      expect(_says('早晨！想問下你尋日嘅情況，幾條就得。'), findsOneWidget);
      expect(_says(CheckInChatCopy.q1), findsOneWidget);
      expect(_says(CheckInChatCopy.q3b), findsNothing);
    });

    // 1020h 一 — a crisis stop today that the researcher did not mark
    // counts as today's check-in (as the server's P2 rule): reopening the
    // window gives the chat, as when the check-in was done — never Q0 again.
    for (final arm in [ArmAssignment.b, ArmAssignment.a]) {
      final tag = arm == ArmAssignment.b ? 'rule' : 'Hybrid';
      testWidgets('$tag: not marked (a real crisis stop): no resume, no new '
          'check-in — the chat opener', (tester) async {
        final run = _Run(arm);
        run.store.docs['ci_old'] = stoppedRow(marked: false);
        await _open(tester, run, _page(run));
        expect(_says(CheckInChatCopy.q1), findsNothing, reason: 'no restart');
        expect(_says(CheckInChatCopy.q3b), findsNothing, reason: 'no resume');
        expect(_says('早晨！想問下你尋日嘅情況，幾條就得。'), findsNothing);
        if (arm == ArmAssignment.b) {
          expect(_says(CheckInChatCopy.sy0), findsOneWidget);
          expect(run.prompts.map((p) => p.$1), ['SY0']);
          expect(run.llm.calls, isEmpty);
        } else {
          expect(run.llm.calls.single.suffix,
              contains('[開場·check-in 已做]'));
        }
        expect(run.store.docs.keys, ['ci_old'], reason: 'no new row');
      }, skip: arm == ArmAssignment.b ? !_ruleTestable : !_hybridTestable);
    }

    testWidgets('not marked yesterday: today a new check-in from Q0',
        (tester) async {
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
      run.store.docs['ci_old'] =
          stoppedRow(date: '2026-10-20', marked: false);
      await _open(tester, run, _page(run));
      expect(_says(CheckInChatCopy.q1), findsOneWidget);
      expect(_says(CheckInChatCopy.sy0), findsNothing);
    });

    test('1020h 一 (4): "today" is the Hong Kong date, whatever the phone '
        'time zone', () {
      expect(MoodRecorder.dateIsoFor(DateTime.utc(2026, 10, 20, 15, 59)),
          '2026-10-20');
      expect(MoodRecorder.dateIsoFor(DateTime.utc(2026, 10, 20, 16, 0)),
          '2026-10-21', reason: '00:00 in Hong Kong');
      expect(MoodRecorder.dateIsoFor(DateTime.utc(2026, 10, 21, 2, 0)),
          '2026-10-21');
    });

    testWidgets('already resumed once today: no second resume',
        (tester) async {
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
      run.store.docs['ci_old'] = stoppedRow();
      run.store.docs['ci_new'] = {'uid': 'u1', 'flow': 'chat_v2',
        'date_iso': '2026-10-21', 'resumed_from': 'ci_old',
        'completed': false};
      await _open(tester, run, _page(run));
      expect(_says(CheckInChatCopy.q1), findsOneWidget);
      expect(_says(CheckInChatCopy.q3b), findsNothing);
    });

    testWidgets('rule arm end to end: acute at Q3b stops (stopped_at Q3b); '
        'after the server mark, reopening resumes there', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _page(run));
      await _tapAnswer(tester, 'Q1', 'so_so');
      await _tapAnswer(tester, 'Q2', 'none');
      await _tapAnswer(tester, 'Q3', 'small');
      await _type(tester, '我真係想死');
      expect(find.byType(EmergencySupportPage), findsOneWidget);
      run.navKey.currentState!.pop();
      await _settle(tester);
      final id = run.store.docs.keys.single;
      expect(run.store.docs[id]!['stopped_by_safety'], isTrue);
      expect(run.store.docs[id]!['stopped_at'], 'Q3b');
      expect(run.store.docs[id]!['completed'], isFalse);
      // Leave; the researcher marks 誤觸 (markSafetyFalseAlarm, server).
      run.navKey.currentState!.pop();
      await _settle(tester);
      run.store.docs[id] = {...run.store.docs[id]!, 'falseAlarm': true,
        'markedBy': 'r1', 'markedAt': 'now'};
      ChatSessionRecorder.resetProcessStateForTest();
      run.navKey.currentState!
          .push(MaterialPageRoute<void>(builder: (_) => _page(run)));
      await _settle(tester);
      expect(_says(CheckInChatCopy.q3b), findsOneWidget);
      expect(_says(CheckInChatCopy.q1), findsNothing);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    test('a marked check-in alone never counts as done (no event)', () {
      // Done today = a `check_in_submitted` event (status chip, banner,
      // this page).  A stopped check-in never logs it; only a completed
      // one does (_finishCheckIn).  The row-level rule for P2 is batch 4.
      expect(CheckInChatRecord.stoppedQuestionOf(stoppedRow()), 'Q3b');
      expect(CheckInChatRecord.stoppedQuestionOf(
          {'response2_id': 'none_safety'}), 'Q4');
      expect(CheckInChatRecord.stoppedQuestionOf({}), isNull);
    });
  });

  // 1020e 二.9 — the dashboard's 「標記誤觸」 (unblinded researcher tool).
  group('dashboard 標記誤觸', () {
    final created = DateTime.utc(2026, 10, 21, 2, 0);
    SafetyAlertView alert({Map<String, dynamic> extra = const {}}) =>
        SafetyAlertView.fromData('AL1', {
          'researchId': 'RCT-01',
          'level': 'acute',
          'alertVersion': 3,
          'sourceGroup': 'participant_input',
          'agentId': 'siu_yan',
          'createdAt': Timestamp.fromDate(created),
          ...extra,
        });

    Future<void> pumpRow(WidgetTester tester, SafetyAlertView a,
        MarkFalseAlarm? mark) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SafetyAlertRow(
            alert: a,
            isEn: false,
            acknowledge: (_) async {},
            markFalseAlarm: mark,
          ),
        ),
      ));
    }

    test('the switch decides whether the list offers it', () {
      Future<void> mark(String _) async {}
      RemoteFeatureFlags.current = const RemoteFeatureFlags();
      expect(SafetyAlertsSection.offeredMark(mark), isNull);
      RemoteFeatureFlags.current = RemoteFeatureFlags.fromMap(
          const {'safetyFalseAlarmMarkEnabled': true});
      expect(SafetyAlertsSection.offeredMark(mark), isNotNull);
      expect(RemoteFeatureFlags.fromMap(
              const {'safetyFalseAlarmMarkEnabled': 'true'})
          .safetyFalseAlarmMarkEnabled, isFalse);
    });

    testWidgets('switch off: no button', (tester) async {
      await pumpRow(tester, alert(), null);
      expect(find.text('標記誤觸'), findsNothing);
      expect(find.text('確認處理'), findsOneWidget, reason: 'T34 unchanged');
    });

    testWidgets('confirm → the callable gets the alert id; row shows the mark',
        (tester) async {
      final calls = <String>[];
      await pumpRow(tester, alert(), (id) async => calls.add(id));
      await tester.tap(find.text('標記誤觸'));
      await tester.pumpAndSettle();
      expect(find.text('標記為誤觸？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('false_alarm_cancel')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'cancel does nothing');
      await tester.tap(find.text('標記誤觸'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('false_alarm_confirm')));
      await tester.pumpAndSettle();
      expect(calls, ['AL1']);
      expect(find.textContaining('已標記誤觸'), findsOneWidget);
      expect(find.text('標記誤觸'), findsNothing);
    });

    testWidgets('a stored mark shows with its time; no button',
        (tester) async {
      await pumpRow(
          tester,
          alert(extra: {
            'falseAlarm': true,
            'markedAt': Timestamp.fromDate(created.add(
                const Duration(hours: 1))),
          }),
          (_) async => fail('must not be offered again'));
      expect(find.textContaining('已標記誤觸 · 2026-10-21 11:00'),
          findsOneWidget);
      expect(find.text('標記誤觸'), findsNothing);
    });

    testWidgets('a failed call is shown, no mark', (tester) async {
      await pumpRow(
          tester, alert(), (_) async => throw Exception('permission-denied'));
      await tester.tap(find.text('標記誤觸'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('false_alarm_confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('標記失敗'), findsOneWidget);
      expect(find.textContaining('已標記誤觸'), findsNothing);
    });
  });
}
