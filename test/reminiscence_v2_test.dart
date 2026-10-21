// 1020d (回憶 v2) — the weekly page for both arms, the chapter, the
// ratings, 我嘅人生小篇章 and the leave buttons, behind the remote switches
// `reminiscenceV2Enabled` and `leaveButtonV2Enabled`:
//   - same opener, same eight questions in order, same 唔想講, both arms;
//   - rule arm: fixed lines (G1–G3 rotated, Q7 line, 唔想講 line), its
//     chapter laid out on the phone — ZERO LLM calls (the fake model fails
//     the test if called; every rule-arm test also asserts 0 calls);
//   - Hybrid: one LLM follow-up and one short reply per question
//     (`ah_jan_ah_bak_v3`, `[回憶·追問]` / `[回憶·回應]`), 唔想講 without an
//     LLM call, the follow-up cap (1, configurable to 2), the chapter
//     request doc and the 'ready' display;
//   - leave and come back: history and progress kept (also with transcript
//     consent off: the words stay on the device);
//   - safety: an acute / moderate_interrupt hit stops the questions;
//   - valid session: ≥ 3 questions answered in the visit;
//   - leave buttons; switches off: unchanged.
//
// Arm.of reads the profile's arm only in a Phase B build:
//   flutter test --dart-define=PHASE_B=true test/reminiscence_v2_test.dart
// (tool/ci_flutter_tests.sh "phase B arm gating").  In the default build
// everybody is Hybrid: the rule-arm cases are skipped.  Synthetic data
// only; no Firebase; fake model, fake stores, fake clock.
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
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
import 'package:app_demo/core/llm/transcript_consent_prompter.dart';
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
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_button.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/crisis/presentation/pages/emergency_support_page.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_copy.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_models.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_store.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_a_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_chapters_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_landing.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_v2_page.dart';
import 'package:app_demo/features/reminiscence/presentation/reminiscence_router.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_pool.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _forced = String.fromEnvironment('FORCE_ARM');

/// The rule arm is reachable only in a Phase B build (profile arm B).
final bool _ruleTestable = FeatureFlags.phaseB && _forced != 'A';

/// Everybody is Hybrid in a Phase A build; Phase B needs profile arm A.
final bool _hybridTestable = !FeatureFlags.phaseB || _forced != 'B';

final bool _bothTestable = FeatureFlags.phaseB && _forced.isEmpty;

/// Fake model.  The rule arm must never get here: [forbid] makes any call
/// a test failure (also counted, in case a page swallows the throw).
class _FakeLlm implements LlmClient {
  _FakeLlm({this.forbid = false});
  final bool forbid;
  bool fail = false;
  final calls = <({
    String moduleId,
    String? promptKey,
    String? variantName,
    String suffix,
    String input,
    String? systemPrompt,
  })>[];

  static const followup = '嗰條街附近有冇一間舖頭，你到而家都記得？';
  static const followup2 = '嗰陣係邊個帶你去㗎？';
  static const reply = '聽落嗰條街好有生氣，多謝你講。';
  static const more = '多謝你講多咗，我記住喇。';
  static const summary = '呢個禮拜你講起深水埗嘅舊屋同阿嫲。';

  List<String> get markers =>
      [for (final c in calls) if (c.promptKey != null) c.suffix.split('\n').first];

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
      variantName: variantName,
      suffix: suffix,
      input: userInput,
      systemPrompt: systemPrompt,
    ));
    if (forbid) throw TestFailure('rule arm called the LLM ($moduleId)');
    if (fail) return const LlmRawResponse(text: '', error: 'network');
    if (moduleId.endsWith('_summary')) {
      return const LlmRawResponse(text: summary);
    }
    final first = suffix.split('\n').first;
    if (first == ReminiscenceV2Page.markerFollowup) {
      return LlmRawResponse(
          text: suffix.contains('\n追問：') ? followup2 : followup);
    }
    if (first == ReminiscenceV2Page.markerReply) {
      return const LlmRawResponse(text: reply);
    }
    if (first == ReminiscenceV2Page.markerMore) {
      return const LlmRawResponse(text: more);
    }
    return const LlmRawResponse(text: 'unexpected');
  }
}

class _FakeMemoryV1 extends MemoryV1Service {
  @override
  Future<void> endSession(String agentId) async {}
}

UserProfile _profile(ArmAssignment arm, {bool retain = true}) => UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: arm,
      armAssignmentMode: 'pilot_designated',
      cohort: 'phase_b',
      w0Date: '2026-10-14',
      consent: ConsentFlags(
        functionalData: true,
        transcriptRetention: retain,
      ),
      firstIntroSeen: {
        'siu_yan': DateTime(2026, 10, 1),
        'ah_jan_ah_bak': DateTime(2026, 10, 1),
        'tung_tung': DateTime(2026, 10, 1),
      },
    );

/// Study day 7 (W0 10/14) → study week 1.
final _now = DateTime(2026, 10, 21, 10, 0);

class _Run {
  _Run(this.arm, {this.retain = true});
  final ArmAssignment arm;
  final bool retain;
  late _FakeLlm llm;
  final weeks = InMemoryReminiscenceWeekStore();
  final chapters = InMemoryReminiscenceChapterStore();
  final ratings = InMemoryReminiscenceRatingStore();
  final summaries = InMemoryReminiscenceSummaryWriter();
  final navKey = GlobalKey<NavigatorState>();

  bool get rule => arm == ArmAssignment.b;

  Map<String, dynamic> week([int w = 1]) => weeks.doc('u1', w)!;
  List<Map<String, dynamic>> messages([int w = 1]) => [
        for (final m in (week(w)['messages'] as List))
          Map<String, dynamic>.from(m as Map)
      ];
  List<String> kinds([int w = 1]) =>
      [for (final m in messages(w)) m['kind'] as String];
  Map<String, dynamic> chapter([int w = 1]) =>
      chapters.docs['u1/week_$w']!;

  void install() {
    ReminiscenceV2Stores.weekOverride = weeks;
    ReminiscenceV2Stores.chaptersOverride = chapters;
    ReminiscenceV2Stores.ratingsOverride = ratings;
    ReminiscenceV2Stores.summaryOverride = summaries;
  }
}

Widget _harness(_Run run, {Widget? home}) {
  run.llm = _FakeLlm(forbid: run.rule);
  final llm = LlmGateway(client: run.llm);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  return AppSettingsScope(
    settings: AppSettings(
        locale: const Locale('zh'),
        profile: _profile(run.arm, retain: run.retain)),
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

ReminiscenceV2Page _page(int week) => ReminiscenceV2Page(
    theme: ReminiscenceTheme.byIndex(week), clock: () => _now);

Future<void> _boot(WidgetTester tester, _Run run, {Widget? home}) async {
  // Device pixel ratio 1: a tall page without a huge snapshot bitmap.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 6000);
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  run.install();
  await tester.pumpWidget(_harness(run, home: home));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, _Run run, {int week = 1}) async {
  await _boot(tester, run);
  await _push(tester, run, week: week);
}

Future<void> _push(WidgetTester tester, _Run run, {int week = 1}) async {
  run.navKey.currentState!
      .push(MaterialPageRoute<void>(builder: (_) => _page(week)));
  await _settle(tester);
}

/// Lets the 700 ms template pause and any fake-LLM future finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// While 「整理緊…」 shows (an endless spinner): pump frames, no settle.
Future<void> _pumps(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('reminiscence_input')), text);
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await _settle(tester);
}

Future<void> _skip(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('reminiscence_skip')));
  await _settle(tester);
}

Future<void> _leave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('session_close_button')));
  await _settle(tester);
}

Finder _says(String text) => find.textContaining(text, findRichText: true);

/// Answers for week 1 (no safety words).
const _answers = [
  '我喺深水埗北河街大，一家人住板間房。',
  '有一日打風，成條街浸晒水。',
  '屋企有阿爸阿媽同兩個家姐，我同阿嫲最親。',
  '阿嫲成日煲綠豆沙俾我飲。',
  '朝早返學，放學幫手執嘢，晚黑喺街度玩。',
  '有一年中秋去維園睇燈籠，好開心。',
  '最難捱係冇錢交學費，後來阿媽幫人車衫。',
  '細個嘅日子教識我要慳，要顧住屋企人。',
];

/// Every question answered.  Hybrid: answer, follow-up answer.
Future<void> _answerAll(WidgetTester tester, _Run run,
    {Set<int> skip = const {}}) async {
  for (var q = 1; q <= 8; q++) {
    if (skip.contains(q)) {
      await _skip(tester);
      continue;
    }
    await _type(tester, _answers[q - 1]);
    if (!run.rule) await _type(tester, '補充第 $q 題');
  }
}

void main() {
  late PhaseBConfig savedConfig;
  late BriefPrStore savedBriefStore;
  late RemoteFeatureFlags savedFlags;
  late InMemoryBriefPrStore briefStore;

  setUpAll(() {
    // The one-time notes would cover the composer.
    SessionCloseHint.claimFirstUse();
    SessionCloseHint.claimLeaveFirstUse();
  });

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    savedConfig = PhaseBConfig.current;
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    savedBriefStore = BriefPrV2.store;
    briefStore = InMemoryBriefPrStore();
    BriefPrV2.store = briefStore;
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

  group('switches', () {
    test('only a literal true turns each switch on', () {
      for (final v in [null, 'true', 1, false]) {
        final f = RemoteFeatureFlags.fromMap(
            {'reminiscenceV2Enabled': v, 'leaveButtonV2Enabled': v});
        expect(f.reminiscenceV2Enabled, isFalse);
        expect(f.leaveButtonV2Enabled, isFalse);
      }
      final on = RemoteFeatureFlags.fromMap(
          {'reminiscenceV2Enabled': true, 'leaveButtonV2Enabled': true});
      expect(on.reminiscenceV2Enabled, isTrue);
      expect(on.leaveButtonV2Enabled, isTrue);
      expect(const RemoteFeatureFlags().reminiscenceV2Enabled, isFalse);
      expect(const RemoteFeatureFlags().leaveButtonV2Enabled, isFalse);
    });

    test('follow-up cap: default 1, configurable to 2, clamped', () {
      expect(const PhaseBConfig().reminiscenceFollowupsMax, 1);
      expect(PhaseBConfig.fromMap(const {}).reminiscenceFollowupsMax, 1);
      expect(
          PhaseBConfig.fromMap(const {'reminiscenceFollowupsMax': 2})
              .reminiscenceFollowupsMax,
          2);
      expect(
          PhaseBConfig.fromMap(const {'reminiscenceFollowupsMax': 5})
              .reminiscenceFollowupsMax,
          2);
      expect(
          PhaseBConfig.fromMap(const {'reminiscenceFollowupsMax': 0})
              .reminiscenceFollowupsMax,
          1);
      expect(const PhaseBConfig().reminiscenceV2ValidMinQuestions, 3);
    });

    test('valid session: ≥ 3 questions answered in the visit (v2 rows only)',
        () {
      const rules = SessionRules(v2: true, idleTimeoutMin: 30);
      SessionTally t(int n) => SessionTally(
            sessionType: SessionType.reminiscence,
            userMessageCount: 10,
            replyCount: 10,
            reminiscenceV2: true,
            reminiscenceQuestionsAnswered: n,
          );
      expect(rules.isValid(t(2)), isFalse, reason: '10 replies, 2 answers');
      expect(rules.isValid(t(3)), isTrue);
      expect(SessionTally.fromMap(t(3).toMap()).reminiscenceQuestionsAnswered,
          3);
      const old = SessionTally(
          sessionType: SessionType.reminiscence,
          userMessageCount: 3,
          replyCount: 3);
      expect(rules.isValid(old), isTrue, reason: 'old pages: unchanged');
      expect(old.toMap().containsKey('reminiscenceV2'), isFalse);
    });

    testWidgets('off: the old pages, 我嘅回憶, 今日傾到呢度', (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags();
      final run = _Run(ArmAssignment.a);
      await _boot(tester, run, home: const ReminiscenceLandingPage());
      expect(find.text('我嘅回憶'), findsOneWidget);
      expect(find.text(ReminiscenceV2Copy.chaptersPageTitle), findsNothing);
      final ctx = tester.element(find.byType(ReminiscenceLandingPage));
      final page = ReminiscenceRouter.pageFor(ctx, ReminiscenceTheme.byIndex(1));
      expect(page, FeatureFlags.phaseB && run.rule
          ? isA<ReminiscenceArmBPage>()
          : isA<ReminiscenceArmAPage>());
      expect(SessionCloseButton.currentLabel, '今日傾到呢度');
      expect(run.llm.calls, isEmpty);
    });

    testWidgets('off, rule arm: the old form page opens', (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags();
      final run = _Run(ArmAssignment.b);
      await _boot(tester, run, home: const ReminiscenceLandingPage());
      await tester.tap(find.text('童年同屋企'));
      await _settle(tester);
      expect(find.byType(ReminiscenceArmBPage), findsOneWidget);
      expect(find.byType(ReminiscenceV2Page), findsNothing);
      expect(find.text('儲存呢段回憶'), findsOneWidget);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('on: the landing opens the v2 page and offers 我嘅人生小篇章',
        (tester) async {
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
      await _boot(tester, run, home: const ReminiscenceLandingPage());
      expect(find.text('我嘅回憶'), findsNothing);
      expect(find.text(ReminiscenceV2Copy.chaptersPageTitle), findsOneWidget);
      await tester.tap(find.text('童年同屋企'));
      await _settle(tester);
      expect(find.byType(ReminiscenceV2Page), findsOneWidget);
      if (run.rule) expect(run.llm.calls, isEmpty);
    });
  });

  group('rule arm', () {
    testWidgets('week 1, all 8 questions: opener, questions in order, fixed '
        'lines rotated, Q7 line, closing + button, valid session, '
        'ZERO LLM calls', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run);
      final week = ReminiscenceV2Copy.week(1);
      for (final line in ReminiscenceV2Copy.openerFor(1, name: '阿珍')) {
        expect(_says(line), findsOneWidget);
      }
      expect(_says(week.question(1)), findsOneWidget);
      expect(_says(week.question(2)), findsNothing);
      expect(find.byKey(const ValueKey('reminiscence_skip')), findsOneWidget);
      expect(find.text(ReminiscenceV2Copy.skipLabel), findsOneWidget);

      await _answerAll(tester, run);

      expect(run.kinds(), [
        // 1020o (4a): the week's picture first.
        'scene', 'opener', 'opener', 'opener',
        for (var q = 1; q <= 7; q++) ...['question', 'answer', 'fixed_line'],
        'question', 'answer', 'closing',
      ]);
      final msgs = run.messages();
      final lines = [
        for (final m in msgs)
          if (m['kind'] == 'fixed_line') m['copyId'],
      ];
      expect(lines, ['G1', 'G2', 'G3', 'G1', 'G2', 'G3', 'Q7']);
      expect(
          [for (final m in msgs) if (m['kind'] == 'question') m['text']],
          week.questions);
      expect(msgs.firstWhere((m) => m['copyId'] == 'Q7')['text'],
          ReminiscenceV2Copy.q7Line);
      for (final m in msgs) {
        expect(m['role'], m['kind'] == 'answer' ? 'user' : 'assistant');
        expect(m['at'], _now);
        expect(m['id'], isNotEmpty);
      }
      expect(_says(ReminiscenceV2Copy.closingLine), findsOneWidget);
      expect(find.text(ReminiscenceV2Copy.finishWeekLabel), findsOneWidget);
      expect(find.byKey(const Key('reminiscence_input')), findsNothing);

      final doc = run.week();
      expect(doc['weekIndex'], 1);
      expect(doc['arm'], 'B');
      expect(doc['configVersion'], ReminiscenceV2Copy.version);
      expect(doc['status'], 'questions_done');
      expect(doc['currentQuestion'], 9);
      expect(doc['followupsAsked'], isEmpty);
      expect(doc['transcriptRetained'], isTrue);
      expect(doc['createdAt'], isNotNull);
      expect(doc['updatedAt'], isNotNull);

      // Leaving: ≥ 3 answered → valid → one Brief PR card, nothing pushed.
      await _leave(tester);
      expect(find.byType(ReminiscenceV2Page), findsNothing);
      expect(briefStore.records, hasLength(1));
      expect(briefStore.records.values.single.sessionType, 'reminiscence');
      expect(run.llm.calls, isEmpty, reason: 'rule arm: zero LLM calls');
    }, skip: !_ruleTestable);

    testWidgets('Q7 唔想講: the 唔想講 line, not the Q7 line; Q8 唔想講: '
        'straight to the closing line', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run);
      await _answerAll(tester, run, skip: {7, 8});
      final msgs = run.messages();
      final q7 = [for (final m in msgs) if (m['questionIndex'] == 7) m];
      expect([for (final m in q7) m['kind']], ['question', 'skip', 'fixed_line']);
      expect(q7[1]['text'], '唔想講');
      expect(q7[2]['text'], ReminiscenceV2Copy.skipLine);
      expect(msgs.where((m) => m['copyId'] == 'Q7'), isEmpty);
      final q8 = [for (final m in msgs) if (m['questionIndex'] == 8) m];
      expect([for (final m in q8) m['kind']], ['question', 'skip']);
      expect(run.kinds().last, 'closing');
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('chapter on the phone: verbatim words, 唔想講 omitted, '
        'chapter doc fields, summary, three ratings with 唔評住, 改一改 + '
        'edit ratio — zero LLM calls', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run);
      await _answerAll(tester, run, skip: {2, 7});
      await tester.tap(find.byKey(const Key('reminiscence_finish_week')));
      await _settle(tester);

      final week = ReminiscenceV2Copy.week(1);
      final expected = [
        for (final q in [1, 3, 4, 5, 6, 8])
          '${week.shortTitle(q)}\n${_answers[q - 1]}',
      ].join('\n\n');
      final c = run.chapter();
      expect(c['weekIndex'], 1);
      expect(c['source'], 'rule');
      expect(c['status'], 'ready');
      expect(c['ruleText'], expected);
      expect(c['version'], 1);
      expect(c['requestId'], isA<String>());
      expect((c['requestId'] as String).length, 16);
      expect(c['requestedAt'], isA<DateTime>());
      final input = c['input'] as Map<String, dynamic>;
      expect(input['themeZh'], '童年同屋企');
      expect((input['items'] as List)[1]['skipped'], isTrue);
      expect((input['items'] as List)[0]['answer'], _answers[0]);
      // The App never writes the server's fields.
      final w = run.chapters.writes.single.data;
      expect(w.keys.toSet(), {
        'weekIndex', 'source', 'status', 'requestId', 'requestedAt', 'input',
        'ruleText', 'version', 'editedText', 'editRatio', 'savedAt',
      });
      expect(w['requestedAt'], InMemoryReminiscenceChapterStore.serverTimestamp);
      expect(w['editedText'], InMemoryReminiscenceChapterStore.deleted);
      for (final k in ['finalText', 'rounds', 'flags', 'generatedAt']) {
        expect(w.containsKey(k), isFalse, reason: k);
      }
      expect(run.week()['status'], 'chapter_ready');

      // Same screen as Hybrid: banner, title, text, then the rating.
      expect(find.text('第 1 章整理好喇'), findsOneWidget);
      expect(find.text('第 1 章：童年同屋企'), findsOneWidget);
      expect(find.text(expected), findsOneWidget);
      expect(find.text(ReminiscenceV2Copy.week(1).shortTitle(2)), findsNothing);
      expect(find.text(ReminiscenceV2Copy.editLabel), findsNothing,
          reason: 'rating first');

      // The 80-character slot: the elder's words, no LLM.
      expect(run.summaries.saved.single.armCode, 'B');
      expect(run.summaries.saved.single.summary, contains(_answers[0]));

      // Ratings: 6, 唔評住, 7.
      expect(find.text(ReminiscenceV2Copy.ratingItems[0].question), findsOneWidget);
      expect(find.text('完全唔啱'), findsOneWidget);
      expect(find.text('完全啱'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reminiscence_rating_option_6')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reminiscence_rating_next')));
      await tester.pumpAndSettle();
      expect(find.text(ReminiscenceV2Copy.ratingItems[1].question), findsOneWidget);
      await tester.tap(find.byKey(const Key('reminiscence_rating_skip')));
      await tester.pumpAndSettle();
      expect(find.text(ReminiscenceV2Copy.ratingItems[2].question), findsOneWidget);
      await tester.tap(find.byKey(const Key('reminiscence_rating_option_7')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reminiscence_rating_next')));
      await _settle(tester);
      expect(run.ratings.rows.single, {
        'weekIndex': 1,
        'studyWeek': 1,
        'chapterVersion': 1,
        'source': 'rule',
        'accuracy': 6,
        'satisfaction': null,
        'share': 7,
        'skipped': {'accuracy': false, 'satisfaction': true, 'share': false},
        'uid': 'u1',
        'ratedAt': '<serverTimestamp>',
      });
      expect(run.week()['ratedRequestId'], c['requestId']);

      // 改一改 → 儲存.
      await tester.tap(find.byKey(const Key('reminiscence_chapter_edit')));
      await tester.pumpAndSettle();
      final edited = expected.replaceFirst('深水埗', '長沙灣');
      await tester.enterText(
          find.byKey(const Key('reminiscence_chapter_edit_field')), edited);
      await tester.tap(find.byKey(const Key('reminiscence_chapter_save')));
      await _settle(tester);
      final saved = run.chapter();
      expect(saved['editedText'], edited);
      expect(saved['editRatio'], closeTo(3 / expected.runes.length, 1e-9));
      expect(saved['savedAt'], isA<DateTime>());
      expect(saved['ruleText'], expected, reason: 'the original stays');
      expect(find.text(ReminiscenceV2Copy.savedLabel), findsOneWidget);
      expect(run.llm.calls, isEmpty, reason: 'rule arm: zero LLM calls');
    }, skip: !_ruleTestable);

    testWidgets('再講多啲: fixed line; 重新整理 → version 2, rate again — '
        'zero LLM calls', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run);
      await _answerAll(tester, run);
      await tester.tap(find.byKey(const Key('reminiscence_finish_week')));
      await _settle(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('reminiscence_rating_skip')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('reminiscence_regenerate')), findsNothing,
          reason: 'nothing new yet');
      await tester.tap(find.byKey(const Key('reminiscence_more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reminiscence_skip')), findsNothing);
      await _type(tester, '仲有隻狗叫旺財。');
      expect(_says(ReminiscenceV2Copy.extraLine), findsOneWidget);
      expect(run.kinds().sublist(run.kinds().length - 2), ['extra', 'extra_reply']);
      await tester.tap(find.byKey(const Key('reminiscence_regenerate')));
      await _settle(tester);
      final c = run.chapter();
      expect(c['version'], 2);
      expect(c['ruleText'], endsWith('再講多啲\n仲有隻狗叫旺財。'));
      expect(run.chapters.writes, hasLength(2));
      expect(run.chapters.writes[1].data['requestId'],
          isNot(run.chapters.writes[0].data['requestId']));
      expect((c['input'] as Map)['extras'], [
        {'text': '仲有隻狗叫旺財。', 'reply': ReminiscenceV2Copy.extraLine}
      ]);
      expect(find.byKey(const Key('reminiscence_rating_question')), findsOneWidget,
          reason: 'new version, rate again');
      expect(run.summaries.saved, hasLength(1), reason: 'summary once');
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('grief (moderate_review) at Q3: a Z5 line, the questions go '
        'on', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run);
      await _type(tester, _answers[0]);
      await _type(tester, _answers[1]);
      await _type(tester, '阿嫲過咗身好多年，我好掛住佢。');
      final z5 = RuleReplyPool.entries.firstWhere((e) => e.id == 'Z5-1').zh;
      expect(_says(z5), findsOneWidget);
      expect(_says(ReminiscenceV2Copy.week(1).question(4)), findsOneWidget);
      expect(run.messages().where((m) => m['safety'] != null), isEmpty);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('acute at Q2: crisis page, questions stop, the answer is '
        'marked; next visit continues at Q3', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run);
      await _type(tester, _answers[0]);
      await _type(tester, '我真係想死');
      expect(find.byType(EmergencySupportPage), findsOneWidget);
      run.navKey.currentState!.pop();
      await _settle(tester);
      expect(_says(ReminiscenceV2Copy.week(1).question(3)), findsNothing);
      expect(find.byKey(const Key('reminiscence_input')), findsNothing);
      final flagged = run.messages().where((m) => m['safety'] != null).single;
      expect(flagged['safety'], 'acute');
      expect(flagged['questionIndex'], 2);
      // Leave and come back: the next question.
      run.navKey.currentState!.pop();
      await _settle(tester);
      await _push(tester, run);
      expect(_says(ReminiscenceV2Copy.week(1).question(3)), findsOneWidget);
      expect(find.byKey(const Key('reminiscence_input')), findsOneWidget);
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('moderate_interrupt at Q1: support sheet, questions stop',
        (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run);
      await _type(tester, '冇人理我');
      expect(find.text('我冇事，繼續'), findsOneWidget);
      await tester.tap(find.text('我冇事，繼續'));
      await _settle(tester);
      expect(_says(ReminiscenceV2Copy.week(1).question(2)), findsNothing);
      expect(run.messages().last['safety'], 'moderate_interrupt');
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);
  });

  group('Hybrid', () {
    testWidgets('one follow-up then one short reply per question; markers, '
        'prompt key, moduleId; 唔想講 makes no LLM call', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run);
      await _type(tester, _answers[0]);
      expect(_says(_FakeLlm.followup), findsOneWidget);
      expect(_says(ReminiscenceV2Copy.week(1).question(2)), findsNothing);
      expect(find.byKey(const ValueKey('reminiscence_skip')), findsOneWidget);
      final c1 = run.llm.calls.single;
      expect(c1.promptKey, 'ah_jan_ah_bak_v3');
      expect(c1.moduleId, 'm3_reminiscence_w1');
      expect(c1.variantName, '阿珍');
      expect(c1.input, _answers[0]);
      expect(c1.suffix.split('\n').take(4).toList(), [
        '[回憶·追問]',
        '本週主題：童年同屋企',
        '題目：${ReminiscenceV2Copy.week(1).question(1)}',
        '老人答：${_answers[0]}',
      ]);

      await _type(tester, '北河街有間涼茶舖。');
      expect(_says(_FakeLlm.reply), findsOneWidget);
      expect(_says(ReminiscenceV2Copy.week(1).question(2)), findsOneWidget);
      final c2 = run.llm.calls[1];
      expect(c2.input, '北河街有間涼茶舖。');
      expect(c2.suffix.split('\n').take(6).toList(), [
        '[回憶·回應]',
        '本週主題：童年同屋企',
        '題目：${ReminiscenceV2Copy.week(1).question(1)}',
        '老人答：${_answers[0]}',
        '追問：${_FakeLlm.followup}',
        '老人再答：北河街有間涼茶舖。',
      ]);

      // 唔想講 on Q2: the fixed line, no LLM call.
      await _skip(tester);
      expect(run.llm.calls, hasLength(2));
      expect(_says(ReminiscenceV2Copy.skipLine), findsOneWidget);
      expect(_says(ReminiscenceV2Copy.week(1).question(3)), findsOneWidget);

      expect(run.kinds().sublist(4), [
        'question', 'answer', 'followup', 'followup_answer', 'reply',
        'question', 'skip', 'fixed_line', 'question',
      ]);
      expect(run.week()['followupsAsked'], {'1': 1});
      expect(run.week()['arm'], 'A');
      expect(run.week()['currentQuestion'], 3);
      for (final r in RuleReplyPool.entries) {
        expect(_says(r.zh), findsNothing);
      }
      for (final g in ReminiscenceV2Copy.generalLines) {
        expect(_says(g), findsNothing, reason: 'no rule-arm line in Hybrid');
      }
    }, skip: !_hybridTestable);

    testWidgets('whole week with Q7 唔想講: closing line and button; 14 LLM '
        'calls (7 answered questions × 2)', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run);
      await _answerAll(tester, run, skip: {7});
      expect(run.llm.calls, hasLength(14));
      expect(run.llm.markers, [
        for (var i = 0; i < 7; i++) ...['[回憶·追問]', '[回憶·回應]'],
      ]);
      expect(_says(ReminiscenceV2Copy.closingLine), findsOneWidget);
      expect(find.text(ReminiscenceV2Copy.finishWeekLabel), findsOneWidget);
      final q7 = [
        for (final m in run.messages())
          if (m['questionIndex'] == 7) m['kind']
      ];
      expect(q7, ['question', 'skip', 'fixed_line']);
      expect(run.week()['status'], 'questions_done');
      expect(run.week()['followupsAsked'],
          {'1': 1, '2': 1, '3': 1, '4': 1, '5': 1, '6': 1, '8': 1});
    }, skip: !_hybridTestable);

    testWidgets('follow-up cap 2 (app_config/phase_b.reminiscenceFollowupsMax)',
        (tester) async {
      PhaseBConfig.current = const PhaseBConfig(
          sessionBriefPrV2Enabled: true, reminiscenceFollowupsMax: 2);
      final run = _Run(ArmAssignment.a);
      await _open(tester, run);
      await _type(tester, _answers[0]);
      await _type(tester, '北河街有間涼茶舖。');
      expect(_says(_FakeLlm.followup2), findsOneWidget);
      expect(run.llm.calls[1].suffix.split('\n').first, '[回憶·追問]');
      expect(run.llm.calls[1].suffix, contains('追問：${_FakeLlm.followup}'));
      await _type(tester, '阿媽帶我去。');
      expect(_says(_FakeLlm.reply), findsOneWidget);
      expect(run.llm.markers, ['[回憶·追問]', '[回憶·追問]', '[回憶·回應]']);
      expect(run.week()['followupsAsked'], {'1': 2});
      expect(_says(ReminiscenceV2Copy.week(1).question(2)), findsOneWidget);
    }, skip: !_hybridTestable);

    testWidgets('LLM failure: a neutral fixed line, then the next question',
        (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run);
      run.llm.fail = true;
      await _type(tester, _answers[0]);
      final m = run.messages().last;
      expect(m['kind'], 'question');
      final fb = run.messages()[run.messages().length - 2];
      expect(fb['kind'], 'fixed_line');
      expect(fb['copyId'], 'llm_fallback');
      expect(ReminiscenceV2Copy.generalLines, contains(fb['text']));
    }, skip: !_hybridTestable);

    testWidgets('acute: no model call for it, crisis page, questions stop',
        (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run);
      await _type(tester, '我真係想死');
      expect(find.byType(EmergencySupportPage), findsOneWidget);
      run.navKey.currentState!.pop();
      await _settle(tester);
      expect(run.llm.calls, isEmpty, reason: 'acute never reaches the model');
      expect(_says(_FakeLlm.followup), findsNothing);
      expect(_says(ReminiscenceV2Copy.week(1).question(2)), findsNothing);
      expect(find.byKey(const Key('reminiscence_input')), findsNothing);
      expect(run.messages().last['safety'], 'acute');
    }, skip: !_hybridTestable);

    testWidgets('chapter request doc, 整理緊…, then ready from the server: '
        '第 N 章整理好喇, text, ratings; summary via the LLM',
        (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run);
      await _answerAll(tester, run, skip: {2});
      final before = run.llm.calls.length;
      await tester.tap(find.byKey(const Key('reminiscence_finish_week')));
      await _pumps(tester);

      final c = run.chapter();
      expect(c['source'], 'hybrid');
      expect(c['status'], 'requested');
      expect(c['weekIndex'], 1);
      expect(c['requestId'], isA<String>());
      final w = run.chapters.writes.single.data;
      expect(w.keys.toSet(), {
        'weekIndex', 'source', 'status', 'requestId', 'requestedAt', 'input',
        'editedText', 'editRatio', 'savedAt',
      }, reason: 'no ruleText / version / server fields from the App');
      final items = (c['input'] as Map)['items'] as List;
      expect(items[0]['followups'], [
        {'q': _FakeLlm.followup, 'a': '補充第 1 題'}
      ]);
      expect(items[0]['reply'], _FakeLlm.reply);
      expect(items[1]['skipped'], isTrue);
      expect(run.week()['status'], 'chapter_requested');
      expect(find.byKey(const Key('reminiscence_chapter_generating')),
          findsOneWidget);
      expect(_says('整理緊…'), findsOneWidget);
      // The 80-character summary: one LLM call, as before.
      expect(run.llm.calls.length, before + 1);
      expect(run.llm.calls.last.moduleId, 'm3_reminiscence_w1_summary');
      expect(run.summaries.saved.single.summary, _FakeLlm.summary);
      expect(run.summaries.saved.single.armCode, 'A');

      // The server: generating → ready.
      run.chapters.serverWrite('u1', 1, {'status': 'generating'});
      await _pumps(tester);
      expect(find.byKey(const Key('reminiscence_chapter_generating')),
          findsOneWidget);
      const text = '我喺深水埗北河街大。阿嫲成日煲綠豆沙俾我飲。';
      run.chapters.serverWrite('u1', 1, {
        'status': 'ready',
        'finalText': text,
        'version': 1,
        'rounds': 1,
        'generatedAt': DateTime(2026, 10, 21, 10, 5),
      });
      await _settle(tester);
      expect(find.text('第 1 章整理好喇'), findsOneWidget);
      expect(find.text('第 1 章：童年同屋企'), findsOneWidget);
      expect(find.text(text), findsOneWidget);
      expect(run.week()['status'], 'chapter_ready');
      expect(find.byKey(const Key('reminiscence_rating_question')),
          findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('reminiscence_rating_option_5')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('reminiscence_rating_next')));
        await tester.pumpAndSettle();
      }
      expect(run.ratings.rows.single['source'], 'hybrid');
      expect(run.ratings.rows.single['chapterVersion'], 1);
      expect(run.ratings.rows.single['accuracy'], 5);
      expect(run.ratings.rows.single['skipped'],
          {'accuracy': false, 'satisfaction': false, 'share': false});

      // 再講多啲 → LLM reply → 重新整理 → requested again, new requestId.
      await tester.tap(find.byKey(const Key('reminiscence_more')));
      await tester.pumpAndSettle();
      await _type(tester, '仲有一樣，阿爸識整風箏。');
      expect(_says(_FakeLlm.more), findsOneWidget);
      expect(run.llm.calls.last.suffix.split('\n').take(2).toList(),
          ['[回憶·再講多啲]', '本週主題：童年同屋企']);
      await tester.tap(find.byKey(const Key('reminiscence_regenerate')));
      await _pumps(tester);
      expect(run.chapter()['status'], 'requested');
      expect(run.chapters.writes, hasLength(2));
      expect(run.chapters.writes[1].data['requestId'],
          isNot(run.chapters.writes[0].data['requestId']));
      expect(((run.chapter()['input'] as Map)['extras'] as List).single,
          {'text': '仲有一樣，阿爸識整風箏。', 'reply': _FakeLlm.more});
      expect(find.byKey(const Key('reminiscence_chapter_generating')),
          findsOneWidget);
      expect(run.summaries.saved, hasLength(1));
    }, skip: !_hybridTestable);
  });

  group('both arms', () {
    testWidgets('leave mid-way (離開（會暫存）) and come back: history and '
        'progress kept, opener not repeated', (tester) async {
      for (final arm in [
        if (_hybridTestable) ArmAssignment.a,
        if (_ruleTestable) ArmAssignment.b,
      ]) {
        ChatSessionRecorder.resetProcessStateForTest();
        final run = _Run(arm);
        await _open(tester, run);
        expect(find.text(ReminiscenceV2Copy.leaveLabel), findsOneWidget);
        await _type(tester, _answers[0]);
        if (arm == ArmAssignment.a) {
          // Leave while the follow-up waits for its answer.
          expect(_says(_FakeLlm.followup), findsOneWidget);
        } else {
          await _type(tester, _answers[1]);
        }
        final kindsBefore = run.kinds();
        await _leave(tester);
        expect(find.byType(ReminiscenceV2Page), findsNothing);
        expect(find.text('home'), findsOneWidget);
        expect(run.week()['status'], 'in_progress', reason: 'week not finished');

        await _push(tester, run);
        expect(run.kinds(), kindsBefore, reason: 'nothing added on return');
        expect(_says(_answers[0]), findsOneWidget);
        if (arm == ArmAssignment.a) {
          expect(_says(_FakeLlm.followup), findsOneWidget);
          await _type(tester, '北河街有間涼茶舖。');
          expect(_says(_FakeLlm.reply), findsOneWidget);
          expect(_says(ReminiscenceV2Copy.week(1).question(2)), findsOneWidget);
        } else {
          expect(_says(ReminiscenceV2Copy.week(1).question(3)), findsOneWidget);
          expect(run.llm.calls, isEmpty);
        }
        expect(_says(ReminiscenceV2Copy.week1Opener[1]), findsOneWidget);
        await _leave(tester);
      }
    });

    testWidgets('transcript consent off: the server doc has no words, the '
        'device keeps them, coming back still works', (tester) async {
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a,
          retain: false);
      TranscriptConsentPrompter.resetForTest();
      await _open(tester, run);
      await _type(tester, _answers[0]);
      if (!run.rule) {
        // Hybrid, as the old arm A page: the one-time 「要唔要我記得返」
        // nudge; 「唔使住」 keeps consent off.
        await tester.tap(find.text('唔使住'));
        await _settle(tester);
        await _type(tester, '北河街有間涼茶舖。');
      }
      expect(run.week()['messages'], isEmpty);
      expect(run.week()['transcriptRetained'], isFalse);
      expect(run.week()['currentQuestion'], 2);
      final device = run.weeks.deviceMessages['u1/week_1']!;
      expect(device.map((m) => m.text), contains(_answers[0]));
      await _leave(tester);
      await _push(tester, run);
      expect(_says(_answers[0]), findsOneWidget);
      expect(_says(ReminiscenceV2Copy.week(1).question(2)), findsOneWidget);
      if (run.rule) expect(run.llm.calls, isEmpty);
    });

    testWidgets('valid session needs 3 answered questions: 2 → no Brief PR '
        'card; 唔想講 does not count', (tester) async {
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
      await _open(tester, run);
      await _type(tester, _answers[0]);
      if (!run.rule) await _type(tester, 'a');
      await _skip(tester);
      await _type(tester, _answers[2]);
      if (!run.rule) await _type(tester, 'b');
      await _leave(tester);
      expect(briefStore.records, isEmpty, reason: '2 answered: not valid');
      await _push(tester, run);
      await _type(tester, _answers[3]);
      if (!run.rule) await _type(tester, 'c');
      await _leave(tester);
      expect(briefStore.records, isEmpty, reason: 'a new visit: 1 answered');
      if (run.rule) expect(run.llm.calls, isEmpty);
    });

    testWidgets('week 2: the 歡迎返嚟 opener with theme and chapter number',
        (tester) async {
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
      await _open(tester, run, week: 2);
      expect(_says('歡迎返嚟。今個禮拜我哋講後生時期同工作，一樣係幾條問題，慢慢嚟。'),
          findsOneWidget);
      expect(_says('講完我會幫你整理成第2章。'), findsOneWidget);
      expect(_says('如果冇問題，我哋就開始。'), findsOneWidget);
      expect(_says(ReminiscenceV2Copy.week(2).question(1)), findsOneWidget);
      if (run.rule) expect(run.llm.calls, isEmpty);
    });

    testWidgets('identical opener, questions and buttons in both arms',
        (tester) async {
      Future<List<String>> walk(ArmAssignment arm) async {
        ChatSessionRecorder.resetProcessStateForTest();
        final run = _Run(arm);
        await _open(tester, run);
        await _answerAll(tester, run, skip: {4});
        await _leave(tester);
        return [
          for (final m in run.messages())
            if (m['kind'] == 'scene' ||
                m['kind'] == 'opener' ||
                m['kind'] == 'question' ||
                m['kind'] == 'closing')
              m['text'] as String,
        ];
      }

      final a = await walk(ArmAssignment.a);
      final b = await walk(ArmAssignment.b);
      expect(a, b);
      expect(a, hasLength(1 + 3 + 8 + 1));
    }, skip: !_bothTestable);

    testWidgets('我嘅人生小篇章: ready chapters by week, 改一改 again',
        (tester) async {
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
      run.chapters.serverWrite('u1', 1, {
        'weekIndex': 1,
        'source': run.rule ? 'rule' : 'hybrid',
        'status': 'ready',
        if (run.rule) 'ruleText': '第一週嘅原文' else 'finalText': '第一週嘅原文',
        'version': 1,
        'requestId': 'r1',
      });
      run.chapters.serverWrite('u1', 2, {
        'weekIndex': 2,
        'source': 'hybrid',
        'status': 'requested',
        'requestId': 'r2',
      });
      await _boot(tester, run, home: const ReminiscenceLandingPage());
      expect(find.byKey(const ValueKey('reminiscence_landing_ready_1')),
          findsOneWidget);
      expect(find.text('第 1 章整理好喇'), findsOneWidget);
      await tester.tap(find.text(ReminiscenceV2Copy.chaptersPageTitle));
      await _settle(tester);
      expect(find.byType(ReminiscenceChaptersPage), findsOneWidget);
      expect(find.text('第 1 章：童年同屋企'), findsOneWidget);
      expect(find.text('第 2 章：後生時期同工作'), findsNothing,
          reason: 'not ready');
      await tester.tap(find.text('第 1 章：童年同屋企'));
      await _settle(tester);
      expect(find.byType(ReminiscenceChapterDetailPage), findsOneWidget);
      expect(find.byKey(const Key('reminiscence_rating_question')), findsNothing);
      await tester.tap(find.byKey(const Key('reminiscence_chapter_edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('reminiscence_chapter_edit_field')), '第一週嘅改稿');
      await tester.tap(find.byKey(const Key('reminiscence_chapter_save')));
      await _settle(tester);
      expect(run.chapter()['editedText'], '第一週嘅改稿');
      expect(run.chapter()['editRatio'], closeTo(2 / 6, 1e-9));
      expect(run.chapter()[run.rule ? 'ruleText' : 'finalText'], '第一週嘅原文');
      run.navKey.currentState!.pop();
      await _settle(tester);
      expect(find.text('第一週嘅改稿'), findsOneWidget, reason: 'list shows the edit');
      run.navKey.currentState!.pop();
      await _settle(tester);
      expect(find.byKey(const ValueKey('reminiscence_landing_ready_1')),
          findsNothing, reason: 'saved: no more 整理好喇');
      expect(run.llm.calls, isEmpty);
    });
  });

  // 10/21 (decisions-log 132, 133 (4)): the landing reads the v2 week doc
  // only — no icon until done; 「講咗 n／8 條」 once one is handled; the
  // check after all eight and 「完成今個禮拜」.  Same in both arms.
  group('landing check and 講咗 n／8 條', () {
    const done1 = ValueKey('reminiscence_landing_done_1');

    /// Icons on a theme card (the picture is an image, not an icon).
    Finder cardIcons(String title, {bool skipOffstage = true}) =>
        find.descendant(
            of: find.ancestor(
                of: find.text(title, skipOffstage: skipOffstage),
                matching: find.byType(Card, skipOffstage: skipOffstage)),
            matching: find.byType(Icon, skipOffstage: skipOffstage));

    test('progress from the week doc: handled = questions before the one '
        'being asked; finished needs all eight and the press', () {
      ReminiscenceWeekProgress p(int q, String status) =>
          ReminiscenceWeekProgress.of(ReminiscenceWeekState(
              weekIndex: 1, arm: 'B', currentQuestion: q, status: status))!;
      expect(ReminiscenceWeekProgress.of(null), isNull);
      expect(p(1, ReminiscenceWeekStatus.inProgress).handled, 0);
      expect(p(3, ReminiscenceWeekStatus.inProgress).handled, 2);
      expect(p(9, ReminiscenceWeekStatus.questionsDone).handled, 8);
      expect(p(9, ReminiscenceWeekStatus.questionsDone).finished, isFalse);
      expect(p(9, ReminiscenceWeekStatus.chapterRequested).finished, isTrue);
      expect(p(9, ReminiscenceWeekStatus.chapterReady).finished, isTrue);
      // A chapter asked for before all eight (an older build): no check.
      expect(p(5, ReminiscenceWeekStatus.chapterRequested).finished, isFalse);
      expect(ReminiscenceV2Copy.weekProgress(2), '講咗 2／8 條');
    });

    for (final arm in [
      if (_hybridTestable) ArmAssignment.a,
      if (_ruleTestable) ArmAssignment.b,
    ]) {
      final name = arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';

      testWidgets('$name: answer 2 and leave → no check, 講咗 2／8 條; no '
          '完成今個禮拜 before all eight', (tester) async {
        final run = _Run(arm);
        await _boot(tester, run, home: const ReminiscenceLandingPage());
        expect(find.textContaining('講咗'), findsNothing,
            reason: 'never entered: no line');
        for (final title in ['童年同屋企', '後生時期同工作', '一生人嘅朋友']) {
          expect(cardIcons(title), findsNothing,
              reason: 'never entered: no icon ($title)');
        }
        await tester.tap(find.text('童年同屋企'));
        await _settle(tester);
        for (var q = 1; q <= 2; q++) {
          await _type(tester, _answers[q - 1]);
          if (!run.rule) await _type(tester, '補充第 $q 題');
        }
        expect(find.byKey(const Key('reminiscence_finish_week')), findsNothing);
        await _leave(tester);
        expect(find.byType(ReminiscenceV2Page), findsNothing);
        expect(find.text('講咗 2／8 條'), findsOneWidget);
        expect(find.byKey(done1), findsNothing);
        expect(cardIcons('童年同屋企'), findsNothing);
        if (run.rule) expect(run.llm.calls, isEmpty);
      });

      testWidgets('$name: all eight (Q7 唔想講) → still no check until '
          '完成今個禮拜; pressed → check, no 講咗 line', (tester) async {
        final run = _Run(arm);
        await _boot(tester, run, home: const ReminiscenceLandingPage());
        await tester.tap(find.text('童年同屋企'));
        await _settle(tester);
        await _answerAll(tester, run, skip: {7});
        expect(find.text('講咗 8／8 條', skipOffstage: false), findsOneWidget);
        expect(find.byKey(done1, skipOffstage: false), findsNothing);
        await tester.tap(find.byKey(const Key('reminiscence_finish_week')));
        if (run.rule) {
          await _settle(tester);
        } else {
          await _pumps(tester); // 整理緊… spins
        }
        run.navKey.currentState!.pop();
        await _settle(tester);
        expect(find.byType(ReminiscenceV2Page), findsNothing);
        expect(find.byKey(done1), findsOneWidget);
        expect(cardIcons('童年同屋企'), findsOneWidget);
        expect(find.textContaining('講咗'), findsNothing);
        if (run.rule) expect(run.llm.calls, isEmpty);
      });
    }

    testWidgets('an old-version record does not count: legacy saves for all '
        'four weeks, no v2 week → no check anywhere', (tester) async {
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
      for (var w = 1; w <= 4; w++) {
        await run.summaries.save(
            uid: 'u1', weekIndex: w, armCode: run.rule ? 'B' : 'A',
            summary: '舊版回憶第 $w 週');
      }
      // A week whose chapter was asked for before all eight were handled.
      await run.weeks.save(
          'u1',
          ReminiscenceWeekState(
              weekIndex: 2,
              arm: run.rule ? 'B' : 'A',
              currentQuestion: 5,
              status: ReminiscenceWeekStatus.chapterRequested),
          retainTranscript: true);
      await _boot(tester, run, home: const ReminiscenceLandingPage());
      for (var w = 1; w <= 4; w++) {
        expect(find.byKey(ValueKey('reminiscence_landing_done_$w')),
            findsNothing, reason: 'week $w');
      }
      expect(find.text('講咗 4／8 條'), findsOneWidget);
      expect(cardIcons('童年同屋企'), findsNothing);
      // The landing no longer reads the old M3 session doc at all.
      final src = File(
              'lib/features/reminiscence/presentation/pages/reminiscence_landing.dart')
          .readAsStringSync();
      expect(src, isNot(contains('m3_reminiscence')));
      expect(src, isNot(contains('cloud_firestore')));
    });
  });

  group('leave buttons (leaveButtonV2Enabled)', () {
    testWidgets('on: other companion pages show 離開 and the new first-use '
        'note once; reminiscence v2 shows 離開（會暫存）', (tester) async {
      SessionCloseHint.resetForTest();
      SessionCloseHint.claimFirstUse(); // the old note was seen before
      final run = _Run(ArmAssignment.a);
      await _boot(tester, run,
          home: Builder(
              builder: (context) => Scaffold(
                  appBar: companionAppBar(context,
                      agentId: 'siu_yan', onClose: () {}),
                  body: const Text('chat'))));
      await tester.pump();
      expect(find.text('離開'), findsOneWidget);
      expect(find.text('今日傾到呢度'), findsNothing);
      expect(find.text(SessionCloseButton.leaveFirstUseNote), findsOneWidget);
      expect(SessionCloseButton.leaveFirstUseNote,
          '撳『離開』就係今次傾完。想再傾隨時返嚟，之前講過嘅都喺度。');
      expect(SessionCloseHint.claimLeaveFirstUse(), isFalse, reason: 'once');
      expect(SessionCloseHint.claimFirstUse(), isFalse);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      await _push(tester, run);
      expect(find.text('離開（會暫存）'), findsOneWidget);
      expect(find.text(SessionCloseButton.leaveFirstUseNote), findsNothing);
    });

    testWidgets('off: 今日傾到呢度 and the old note, unchanged', (tester) async {
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(reminiscenceV2Enabled: true);
      SessionCloseHint.resetForTest();
      final run = _Run(ArmAssignment.a);
      await _boot(tester, run,
          home: Builder(
              builder: (context) => Scaffold(
                  appBar: companionAppBar(context,
                      agentId: 'siu_yan', onClose: () {}),
                  body: const Text('chat'))));
      await tester.pump();
      expect(find.text('今日傾到呢度'), findsOneWidget);
      expect(find.text('離開'), findsNothing);
      expect(find.text(SessionCloseButton.firstUseNote), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      // The v2 reminiscence page keeps S9 as it is when the switch is off.
      await _push(tester, run);
      expect(find.text('離開（會暫存）'), findsNothing);
      expect(find.text('今日傾到呢度'), findsOneWidget);
      SessionCloseHint.claimLeaveFirstUse();
    });

    testWidgets('離開（會暫存） ends the session as close_button; the week '
        'stays in progress; Brief PR card when valid', (tester) async {
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
      await _open(tester, run);
      for (var q = 0; q < 3; q++) {
        await _type(tester, _answers[q]);
        if (!run.rule) await _type(tester, '補充');
      }
      await tester.tap(find.text('離開（會暫存）'));
      await _settle(tester);
      expect(find.byType(ReminiscenceV2Page), findsNothing);
      expect(run.week()['status'], 'in_progress');
      expect(run.week()['currentQuestion'], 4);
      expect(briefStore.records, hasLength(1));
      expect(briefStore.records.values.single.sessionType, 'reminiscence');
      if (run.rule) expect(run.llm.calls, isEmpty);
    });
  });
}
