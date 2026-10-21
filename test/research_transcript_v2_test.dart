// Decision 0069 (decisions-log 10/20 items 65, 80, 99/100) — the
// research transcript `users/{uid}/chat_transcripts`, schema 2: every elder
// message and every companion bubble, both arms, while
// `researchTranscriptEnabled` is on.
//   - recorder: openers before a session become `companion` rows when the
//     session starts (dropped if none starts); a button press and the turn
//     it leads to are one row; later bubbles join the open row, joined by a
//     blank line; a crisis end writes at once; the App going to the
//     background writes every open row; switch off → nothing;
//   - the row keys are exactly firestore.rules' `transcriptKeys()`;
//   - every TurnRecord in lib/ passes `shownReply:`;
//   - one synthetic session per chat page per arm, rows asserted in order:
//     小欣 check-in v2 and chat (rule / Hybrid; both arms identical apart
//     from the replies), the crisis message after acute, 回憶 v2 (rule /
//     Hybrid; the weekly scene line never stored; a later visit's
//     `shown_again`), 通通 (rule / Hybrid, incl. the fallback line), 想法
//     練習對話 and the old check-in page (Hybrid), the rule-arm form
//     submission.  The rule arm makes ZERO model calls in every case.
//
// Arm.of reads the profile's arm only in a Phase B build:
//   flutter test --dart-define=PHASE_B=true test/research_transcript_v2_test.dart
// (tool/ci_flutter_tests.sh "phase B arm gating" and "phase B arm B pages").
// In the default build everybody is Hybrid: the rule-arm cases are skipped.
// Synthetic data only; no Firebase: rows go to
// ChatSessionRecorder.debugTranscriptSink.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
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
import 'package:app_demo/core/safety/safety_copy.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/core/session/idle_session_timer.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/data/rule_submission_flow.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/context/data/check_in_chat_copy.dart';
import 'package:app_demo/features/context/data/check_in_response_store.dart';
import 'package:app_demo/features/context/data/siu_yan_rule_chat_pool.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_a.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/crisis/presentation/pages/emergency_support_page.dart';
import 'package:app_demo/features/crisis/presentation/widgets/crisis_chat_message.dart';
import 'package:app_demo/features/curious_companion/data/tung_tung_rule_pool.dart';
import 'package:app_demo/features/curious_companion/presentation/pages/tung_tung_page.dart';
import 'package:app_demo/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_copy.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_store.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_v2_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_pool.dart';
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

/// Both arms in one run (the parity case).
final bool _bothTestable = FeatureFlags.phaseB && _forced.isEmpty;

const _acute = '我真係想死';

Map<String, dynamic> _json(String path) =>
    Map<String, dynamic>.from(jsonDecode(File(path).readAsStringSync()) as Map);

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake model.  The rule arm must never get here: [forbid] makes any call
/// a test failure (also counted, in case a page swallows the throw).
class _FakeLlm implements LlmClient {
  _FakeLlm({this.forbid = false});
  final bool forbid;

  /// Every call fails (→ the page's fallback line).
  bool fail = false;
  final calls = <String>[];

  static const reply1 = '聽落你尋日都幾充實。';
  static const reply2 = '可以去附近公園行下，慢慢嚟。';
  static const opener = '今日想傾咩都得，我喺度。';
  static const skip = '好，今日就慢慢嚟。';
  static const chat = '好呀，再同我講多啲。';
  static const followup = '嗰條街附近有冇一間舖頭，你到而家都記得？';
  static const reply = '聽落嗰條街好有生氣，多謝你講。';

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
    if (fail) return const LlmRawResponse(text: '', error: 'network');
    final suffix = contextSuffix ?? '';
    final first = suffix.split('\n').first;
    if (suffix.contains('[簽到·回應一]')) return const LlmRawResponse(text: reply1);
    if (suffix.contains('[簽到·回應二]')) return const LlmRawResponse(text: reply2);
    if (suffix.contains('[簽到·唔講住]')) return const LlmRawResponse(text: skip);
    if (suffix.contains('[開場·check-in 已做]')) {
      return const LlmRawResponse(text: opener);
    }
    if (first == ReminiscenceV2Page.markerFollowup) {
      return const LlmRawResponse(text: followup);
    }
    if (first == ReminiscenceV2Page.markerReply) {
      return const LlmRawResponse(text: reply);
    }
    if (moduleId.endsWith('_summary')) {
      return const LlmRawResponse(text: '呢個禮拜你講起舊屋。');
    }
    return const LlmRawResponse(text: chat);
  }
}

/// No real idle clock in the pure recorder tests.
class _NoIdle extends IdleSessionTimer {
  _NoIdle(Duration d, void Function() onIdle)
      : super(idleDuration: d, onIdle: onIdle);
  @override
  void start() {}
  @override
  void bumpActivity() {}
  @override
  void dispose() {}
}

class _FakeMemoryV1 extends MemoryV1Service {
  @override
  Future<void> endSession(String agentId) async {}
}

/// One captured transcript row.
class _Row {
  _Row(this.uid, this.id, this.m);
  final String uid;
  final String id;
  final Map<String, dynamic> m;
  String get role => m['role'] as String;
  String? get userText => m['userText'] as String?;
  String? get userInput => m['userInput'] as String?;
  String get reply => m['replyText'] as String;
  List<String> get parts =>
      reply.isEmpty ? const [] : reply.split(TranscriptRow.partSeparator);
  String get status => m['replyStatus'] as String;
  String get sessionId => m['sessionId'] as String;
  String get moduleId => m['moduleId'] as String;

  /// Role, input and (for buttons and companions) the words: what must be
  /// the same in both arms.
  String get shape => '$role|$userInput|'
      '${userInput == 'button' ? userText : ''}';

  @override
  String toString() => '$role/$userInput/$userText → $parts ($status)';
}

final _rows = <_Row>[];

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

  /// The fake model fails every call from the start.
  bool failLlm = false;
  final navKey = GlobalKey<NavigatorState>();
  final checkIns = InMemoryCheckInResponseStore();
  final replyHistory = InMemoryRuleReplyHistoryStore();
  final weeks = InMemoryReminiscenceWeekStore();
  final chapters = InMemoryReminiscenceChapterStore();
  bool get rule => arm == ArmAssignment.b;

  void install() {
    ReminiscenceV2Stores.weekOverride = weeks;
    ReminiscenceV2Stores.chaptersOverride = chapters;
    ReminiscenceV2Stores.ratingsOverride = InMemoryReminiscenceRatingStore();
    ReminiscenceV2Stores.summaryOverride = InMemoryReminiscenceSummaryWriter();
  }
}

Widget _harness(_Run run) {
  run.llm = _FakeLlm(forbid: run.rule)..fail = run.failLlm;
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

Future<void> _boot(WidgetTester tester, _Run run) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 6000);
  addTearDown(tester.view.reset);
  // No connectivity plugin in tests: report Wi-Fi so sends go through.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  run.install();
  await tester.pumpWidget(_harness(run));
  await tester.pumpAndSettle();
}

Future<void> _push(WidgetTester tester, _Run run, Widget page) async {
  unawaited(run.navKey.currentState!
      .push(MaterialPageRoute<void>(builder: (_) => page)));
  await _settle(tester);
}

Future<void> _open(WidgetTester tester, _Run run, Widget page) async {
  await _boot(tester, run);
  await _push(tester, run, page);
}

/// Lets the 700 ms template pause and any fake-LLM future finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Leave the page (back): the open row is written.
Future<void> _close(WidgetTester tester, _Run run) async {
  run.navKey.currentState!.pop();
  await _settle(tester);
}

Future<void> _type(WidgetTester tester, String text, {Finder? field}) async {
  await tester.enterText(field ?? find.byType(TextField).last, text);
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded).last);
  await _settle(tester);
}

Future<void> _tapAnswer(WidgetTester tester, String q, String code) async {
  await tester.tap(find.byKey(ValueKey('check_in_answer_${q}_$code')));
  await _settle(tester);
}

String _label(List<CheckInOption> options, String code) =>
    options.firstWhere((o) => o.code == code).label;

SiuYanChatPage _siuYan(_Run run, {bool doneToday = false}) => SiuYanChatPage(
      checkedInToday: (_) async => doneToday,
      latestMoodToday: (_) async => null,
      responseStore: run.checkIns,
      replyHistory: run.replyHistory,
      clock: () => _morning,
      onOpenActionPlan: (_) async {},
    );

/// The crisis message as the transcript stores it.
String get _crisis => CrisisChatMessage.transcriptText();

/// Every row: one session, the right agent, nothing sent to a model.
void _commonChecks(List<_Row> rows, {required String agentId}) {
  expect(rows, isNotEmpty);
  for (final r in rows) {
    expect(r.m['schemaVersion'], 2);
    expect(r.m['agentId'], agentId);
    expect(r.m['turnId'], r.id);
    expect(r.sessionId, isNotEmpty);
    expect(r.m.keys, isNot(contains('arm')));
    if (r.role == 'companion') {
      expect(r.userText, isNull);
      expect(r.userInput, isNull);
      expect(r.m['userSentAt'], isNull);
      expect(r.reply, isNotEmpty);
    } else {
      expect(r.role, 'elder');
      expect(r.m['userSentAt'], isA<Timestamp>());
    }
  }
}

// ---------------------------------------------------------------------------
// The scripted sessions (shared by the per-arm and the parity cases)
// ---------------------------------------------------------------------------

/// 小欣 check-in v2 to the end, then one chat message.
Future<List<_Row>> _checkInSession(WidgetTester tester, _Run run) async {
  _rows.clear();
  await _open(tester, run, _siuYan(run));
  await _tapAnswer(tester, 'Q1', 'good');
  await _tapAnswer(tester, 'Q2', 'a_little');
  await _tapAnswer(tester, 'Q3', 'small');
  await _type(tester, '同阿女去咗飲茶');
  await _type(tester, '下晝去公園行下');
  await _tapAnswer(tester, 'Q5', 'no');
  await _type(tester, '今晚想早啲瞓');
  await _close(tester, run);
  return List.of(_rows);
}

void _expectCheckInRows(List<_Row> rows, _Run run) {
  _commonChecks(rows, agentId: 'siu_yan');
  expect(rows, hasLength(8), reason: rows.join('\n'));
  // Q0 + Q1, asked before the elder did anything.
  expect(rows[0].role, 'companion');
  expect(rows[0].parts, [CheckInChatCopy.q0(_morning), CheckInChatCopy.q1]);
  expect(rows[0].status, 'fixed_reply');
  // The three buttons, each with the question that followed.
  final buttons = [
    (_label(CheckInChatCopy.q1Options, 'good'), CheckInChatCopy.q2),
    (_label(CheckInChatCopy.q2Options, 'a_little'), CheckInChatCopy.q3),
    (_label(CheckInChatCopy.q3Options, 'small'), CheckInChatCopy.q3b),
  ];
  for (var i = 0; i < 3; i++) {
    expect(rows[1 + i].userInput, 'button');
    expect(rows[1 + i].userText, buttons[i].$1);
    expect(rows[1 + i].parts, [buttons[i].$2]);
    expect(rows[1 + i].status, 'fixed_reply');
  }
  // Q3b typed: reply 1 and Q4.
  expect(rows[4].userInput, 'text');
  expect(rows[4].userText, '同阿女去咗飲茶');
  expect(rows[4].parts, hasLength(2));
  expect(rows[4].parts[1], CheckInChatCopy.q4);
  // Q4 typed: reply 2 and Q5.
  expect(rows[5].userText, '下晝去公園行下');
  expect(rows[5].parts, hasLength(2));
  expect(rows[5].parts[1], CheckInChatCopy.q5);
  // Q5 button: Q6.
  expect(rows[6].userInput, 'button');
  expect(rows[6].userText, _label(CheckInChatCopy.q5Options, 'no'));
  expect(rows[6].parts, [CheckInChatCopy.q6]);
  // The chat after the check-in.
  expect(rows[7].userText, '今晚想早啲瞓');
  expect(rows[7].parts, hasLength(1));
  // One session, the check-in module.
  expect(rows.map((r) => r.sessionId).toSet(), hasLength(1));
  expect(rows.map((r) => r.moduleId).toSet(), {SiuYanChatPage.checkInModule});
  if (run.rule) {
    expect(
        RuleReplyPool.checkInChatSubPool('good').map((e) => e.zh),
        contains(rows[4].parts[0]));
    expect(rows[4].status, 'rule_based');
    expect(rows[5].parts[0], CheckInChatCopy.r4a);
    expect(rows[5].status, 'rule_based');
    expect(SiuYanRuleChatPool.general.map((e) => e.zh),
        contains(rows[7].parts[0]));
    expect(rows[7].status, 'rule_based');
    expect(run.llm.calls, isEmpty, reason: 'the rule arm never calls the LLM');
  } else {
    expect(rows[4].parts[0], _FakeLlm.reply1);
    expect(rows[4].status, 'ok');
    expect(rows[5].parts[0], _FakeLlm.reply2);
    expect(rows[7].parts, [_FakeLlm.chat]);
  }
}

/// 回憶 v2, week 1, first visit: answer Q1, 唔想講 Q2, leave.
Future<List<_Row>> _reminiscenceFirstVisit(
    WidgetTester tester, _Run run) async {
  _rows.clear();
  await _open(tester, run, _reminiscence());
  // The week's scene picture with its line is on screen (and must not be
  // written).
  expect(find.byKey(const Key('reminiscence_scene_bubble')), findsOneWidget);
  expect(find.textContaining(ReminiscenceV2Copy.sceneLines[1]!,
          findRichText: true),
      findsOneWidget);
  await _type(tester, '我喺深水埗北河街大。',
      field: find.byKey(const Key('reminiscence_input')));
  if (!run.rule) {
    await _type(tester, '有間士多。',
        field: find.byKey(const Key('reminiscence_input')));
  }
  await tester.tap(find.byKey(const ValueKey('reminiscence_skip')));
  await _settle(tester);
  await _close(tester, run);
  return List.of(_rows);
}

ReminiscenceV2Page _reminiscence() => ReminiscenceV2Page(
    theme: ReminiscenceTheme.byIndex(1),
    clock: () => DateTime(2026, 10, 21, 10, 0));

void _expectReminiscenceRows(List<_Row> rows, _Run run) {
  _commonChecks(rows, agentId: 'ah_jan_ah_bak');
  final week = ReminiscenceV2Copy.week(1);
  final opener = ReminiscenceV2Copy.openerFor(1,
      name: AgentRegistry.ahJanAhBakName(null));
  // Opener (three bubbles) and Q1 — never the scene line.
  expect(rows[0].role, 'companion');
  expect(rows[0].parts, [...opener, week.question(1)]);
  expect(rows[0].status, 'fixed_reply');
  for (final r in rows) {
    expect(r.reply, isNot(contains(ReminiscenceV2Copy.sceneLines[1]!)),
        reason: 'the weekly scene line is not stored');
  }
  final skip = rows.last;
  expect(skip.userInput, 'button');
  expect(skip.userText, ReminiscenceV2Copy.skipLabel);
  expect(skip.parts, [ReminiscenceV2Copy.skipLine, week.question(3)]);
  if (run.rule) {
    expect(rows, hasLength(3), reason: rows.join('\n'));
    expect(rows[1].userText, '我喺深水埗北河街大。');
    expect(rows[1].parts, hasLength(2));
    expect(ReminiscenceV2Copy.generalLines, contains(rows[1].parts[0]));
    expect(rows[1].parts[1], week.question(2));
    expect(rows[1].status, 'rule_based');
    expect(run.llm.calls, isEmpty, reason: 'the rule arm never calls the LLM');
  } else {
    expect(rows, hasLength(4), reason: rows.join('\n'));
    expect(rows[1].userText, '我喺深水埗北河街大。');
    expect(rows[1].parts, [_FakeLlm.followup]);
    expect(rows[1].status, 'ok');
    expect(rows[2].userText, '有間士多。');
    expect(rows[2].parts, [_FakeLlm.reply, week.question(2)]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    _rows.clear();
    ChatSessionRecorder.debugTranscriptSink =
        (uid, id, row) => _rows.add(_Row(uid, id, row));
    savedConfig = PhaseBConfig.current;
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    savedBriefStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
    savedFlags = RemoteFeatureFlags.current;
    RemoteFeatureFlags.current = const RemoteFeatureFlags(
      researchTranscriptEnabled: true,
      checkInChatV2Enabled: true,
      reminiscenceV2Enabled: true,
    );
  });

  tearDown(() {
    ChatSessionRecorder.debugTranscriptSink = null;
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedBriefStore;
    RemoteFeatureFlags.current = savedFlags;
    ReminiscenceV2Stores.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
  });

  // -------------------------------------------------------------------------
  group('recorder (pure)', () {
    final t0 = DateTime(2026, 10, 21, 9, 0);

    ChatSessionRecorder rec({String moduleId = 'siu_yan_chat'}) =>
        ChatSessionRecorder(
          uid: 'u1',
          agentId: 'siu_yan',
          moduleId: moduleId,
          analytics: AnalyticsService(firebaseReady: false),
          available: false,
          clock: () => t0,
          timerFactory: (d, f) => _NoIdle(d, f),
        );

    TurnRecord turn({
      String? userText = '今日去咗飲茶。',
      String reply = '聽落幾開心喎。',
      List<String>? shown,
      LlmStatus status = LlmStatus.ok,
      bool shortCircuited = false,
    }) =>
        TurnRecord(
          agentId: 'siu_yan',
          moduleId: 'siu_yan_chat',
          userSent: t0,
          replyShown: t0.add(const Duration(seconds: 3)),
          modality: InputModality.text,
          charCount: userText?.length ?? 0,
          userText: userText,
          detector: const DistressMatch(DistressLevel.none),
          shortCircuited: shortCircuited,
          ackShown: false,
          response: LlmResponse(
            text: reply,
            inputFlag: const DistressMatch(DistressLevel.none),
            outputFlag: const DistressMatch(DistressLevel.none),
            shortCircuited: shortCircuited,
            metadata: const TurnMetadata(systemPromptHash: 'h'),
            status: status,
          ),
          shownReply: shown,
        );

    test('keys are exactly firestore.rules transcriptKeys() (schema 2); '
        'schema 1 keys still listed for older builds', () {
      final rules = File('firestore.rules').readAsStringSync();
      List<String> keys(String fn) {
        final m = RegExp('function $fn\\(\\) \\{\\s*return \\[([^\\]]*)\\]')
            .firstMatch(rules);
        expect(m, isNotNull, reason: fn);
        return RegExp(r"'([a-zA-Z]+)'")
            .allMatches(m!.group(1)!)
            .map((x) => x.group(1)!)
            .toList();
      }

      final elder = turn().transcriptMap(sessionId: 's', turnId: 't');
      final companion = (TranscriptRow.companion(
              id: 'c', agentId: 'siu_yan', moduleId: 'm')
            ..add('早晨', status: 'fixed_reply', at: t0))
          .toMap(sessionId: 's');
      expect(elder.keys.toSet(), keys('transcriptKeys').toSet());
      expect(companion.keys.toSet(), keys('transcriptKeys').toSet());
      expect(keys('transcriptKeysV1').toSet(), {
        'sessionId', 'turnId', 'agentId', 'moduleId', 'userText',
        'replyText', 'replyStatus', 'userSentAt', 'replyShownAt',
        'receivedAt', 'schemaVersion',
      });
      expect(rules, contains('d.schemaVersion == 2'));
      expect(rules, contains('d.schemaVersion == 1'));
      expect(rules, contains("d.userInput in ['text', 'voice', 'button']"));
    });

    test('an opener waits for the session, then is its first row; no '
        'session → not kept', () async {
      final r = rec();
      r.transcriptCompanion('早晨！');
      r.transcriptCompanion('尋日點？');
      expect(_rows, isEmpty, reason: 'no session yet');
      await r.ensureStarted();
      expect(_rows, hasLength(1));
      final c = _rows.single;
      expect(c.role, 'companion');
      expect(c.parts, ['早晨！', '尋日點？']);
      expect(c.sessionId, r.sessionId);
      expect(c.status, 'fixed_reply');
      expect(c.m['replyShownAt'], Timestamp.fromDate(t0));
      r.dispose();

      _rows.clear();
      final never = rec();
      never.transcriptCompanion('你好啊。');
      never.dispose();
      expect(_rows, isEmpty, reason: 'opener never answered: no session');
    });

    test('a button and the turn it leads to are one row; the next '
        'question joins it; the next message writes it', () async {
      final r = rec(moduleId: 'm2_check_in');
      await r.ensureStarted();
      r.transcriptButton('一啲小事');
      final id = await r.logTurn(turn(
          userText: null, reply: 'X1', status: LlmStatus.ruleBased));
      expect(id, isNull, reason: 'logging unavailable in tests');
      r.transcriptCompanion('今日有咩打算？');
      expect(_rows, isEmpty, reason: 'the row stays open');
      await r.logTurn(turn(userText: '去公園', reply: 'R4a'));
      expect(_rows, hasLength(1));
      final b = _rows.single;
      expect(b.userText, '一啲小事');
      expect(b.userInput, 'button');
      expect(b.reply, 'X1\n\n今日有咩打算？');
      expect(b.status, 'rule_based');
      r.dispose();
      expect(_rows, hasLength(2));
      expect(_rows[1].userText, '去公園');
      expect(_rows[1].userInput, 'text');
      expect(_rows[1].parts, ['R4a']);
    });

    test('shownReply is what the transcript keeps (fallback line, safety '
        'line, crisis message), not the model text', () {
      final m = turn(
              reply: 'flagged model text',
              status: LlmStatus.fallback,
              shown: ['唔好意思，我啱啱行慢咗。', '', 'ACK'])
          .transcriptMap(sessionId: 's', turnId: 't');
      expect(m['replyText'], '唔好意思，我啱啱行慢咗。\n\nACK');
      expect(m['replyText'], isNot(contains('flagged')));
      expect(m['role'], 'elder');
      expect(m['userInput'], 'text');
    });

    test('a crisis end that runs first still writes the row at once',
        () async {
      final r = rec();
      await r.ensureStarted();
      final logged = r.logTurn(turn(
          userText: _acute,
          reply: '',
          shown: [_crisis],
          status: LlmStatus.shortCircuited,
          shortCircuited: true));
      final ended = r.end(SessionEndReason.crisis);
      await Future.wait([logged, ended]);
      expect(_rows, hasLength(1));
      expect(_rows.single.userText, _acute);
      expect(_rows.single.reply, _crisis);
      expect(_rows.single.status, 'short_circuited');
      // A line shown after the end waits for the next session.
      r.transcriptCompanion('later');
      expect(_rows, hasLength(1));
      r.dispose();
      expect(_rows, hasLength(1));
    });

    test('the App going to the background writes every open row; while '
        'there rows are written at once', () async {
      final r = rec();
      await r.ensureStarted();
      await r.logTurn(turn());
      expect(_rows, isEmpty);
      ChatSessionRecorder.transcriptAppPaused();
      expect(_rows, hasLength(1));
      r.transcriptCompanion('跟住呢？');
      expect(_rows, hasLength(2));
      expect(_rows[1].role, 'companion');
      ChatSessionRecorder.transcriptAppResumed();
      await r.logTurn(turn(userText: '再講'));
      expect(_rows, hasLength(2));
      r.dispose();
      expect(_rows, hasLength(3));
    });

    test('switch off: nothing, even with every call made', () async {
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(checkInChatV2Enabled: true);
      final r = rec();
      r.transcriptCompanion('早晨');
      await r.ensureStarted();
      r.transcriptButton('好');
      await r.logTurn(turn());
      await r.end(SessionEndReason.back);
      r.dispose();
      ChatSessionRecorder.transcriptAppPaused();
      expect(_rows, isEmpty);
    });

    test('long replies are clipped to the rules limit', () async {
      final r = rec();
      await r.ensureStarted();
      await r.logTurn(turn(userText: 'a' * 6000, shown: ['b' * 9000]));
      r.transcriptCompanion('c' * 3000);
      r.dispose();
      expect(_rows.single.userText!.length, TranscriptRow.maxUserChars);
      expect(_rows.single.reply.length, TranscriptRow.maxReplyChars);
    });

    test('the crisis message text: opening, every number as on the crisis '
        'page, the button', () {
      final lines = _crisis.split('\n');
      expect(lines.first, CrisisChatMessage.openingZh);
      expect(lines.last, '〔${CrisisChatMessage.buttonZh}〕');
      for (final r in SafetyCopy.crisis.resources) {
        expect(lines, contains('${r.nameZh} ${r.number}'));
      }
      expect(_crisis, isNot(contains(TranscriptRow.partSeparator)));
    });

    test('every TurnRecord in lib/ passes shownReply (what was shown)', () {
      final missing = <String>[];
      var count = 0;
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        for (final m in RegExp(r'\bTurnRecord\(').allMatches(src)) {
          final before = src.substring(0, m.start);
          if (before.endsWith('class ') || before.endsWith('const ')) continue;
          var depth = 0;
          var end = m.end - 1;
          for (var i = m.end - 1; i < src.length; i++) {
            if (src[i] == '(') depth++;
            if (src[i] == ')') depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
          count++;
          if (!src.substring(m.end, end).contains('shownReply:')) {
            missing.add('${f.path}:${'\n'.allMatches(before).length + 1}');
          }
        }
      }
      expect(count, greaterThanOrEqualTo(15));
      expect(missing, isEmpty);
    });

    test('rule-arm form submission (check-in B, reminiscence B): the line '
        'shown, or the crisis message after acute', () async {
      Future<void> submit(String text, DistressLevel level,
          {List<String>? shown}) async {
        final r = await RuleSubmissionFlow.record(
          uid: 'u1',
          agentId: 'siu_yan',
          moduleId: 'm2_check_in',
          analytics: AnalyticsService(firebaseReady: false),
          available: false,
          text: text,
          detector: DistressMatch(level),
          userSent: t0,
          replyText: '收到喇。聽日再見。',
          shownReply: shown,
        );
        r.dispose();
      }

      await submit('今日幾好', DistressLevel.none);
      await submit(_acute, DistressLevel.acute, shown: [_crisis]);
      expect(_rows, hasLength(2));
      expect(_rows[0].userText, '今日幾好');
      expect(_rows[0].parts, ['收到喇。聽日再見。']);
      expect(_rows[0].status, 'rule_based');
      expect(_rows[1].parts, [_crisis]);
      expect(_rows[1].status, 'short_circuited');
      expect(_rows[0].sessionId, isNot(_rows[1].sessionId));
    });
  });

  // -------------------------------------------------------------------------
  group('小欣 check-in v2 and chat', () {
    testWidgets('rule arm: every question, button, reply and chat line, in '
        'order; zero LLM calls', (tester) async {
      final run = _Run(ArmAssignment.b);
      _expectCheckInRows(await _checkInSession(tester, run), run);
    }, skip: !_ruleTestable);

    testWidgets('Hybrid: the same rows, the model replies', (tester) async {
      final run = _Run(ArmAssignment.a);
      _expectCheckInRows(await _checkInSession(tester, run), run);
    }, skip: !_hybridTestable);

    testWidgets('parity: both arms write the same rows apart from the '
        'replies', (tester) async {
      final rule = await _checkInSession(tester, _Run(ArmAssignment.b));
      ChatSessionRecorder.resetProcessStateForTest();
      final hybrid = await _checkInSession(tester, _Run(ArmAssignment.a));
      expect([for (final r in rule) r.shape], [for (final r in hybrid) r.shape]);
      // Companion and button rows are word for word the same.
      for (var i = 0; i < rule.length; i++) {
        if (rule[i].role == 'companion' || rule[i].userInput == 'button') {
          expect(rule[i].reply, hybrid[i].reply, reason: 'row $i');
        }
      }
    }, skip: !_bothTestable);

    testWidgets('rule arm, 唔講住 at Q3b and Q4: the button rows carry XG '
        '/ R4b and the next question', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _siuYan(run));
      await _tapAnswer(tester, 'Q1', CheckInChatCopy.q1PreferNot);
      await _tapAnswer(tester, 'Q2', 'none');
      await _tapAnswer(tester, 'Q3', 'big');
      await tester.tap(find.byKey(const ValueKey('check_in_skip')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('check_in_skip')));
      await _settle(tester);
      await _close(tester, run);
      final rows = List.of(_rows);
      _commonChecks(rows, agentId: 'siu_yan');
      final skips = rows.where((r) => r.userText == CheckInChatCopy.skipLabel);
      expect([for (final r in skips) r.parts], [
        [CheckInChatCopy.xg, CheckInChatCopy.q4],
        [CheckInChatCopy.r4b, CheckInChatCopy.q5],
      ]);
      for (final r in skips) {
        expect(r.userInput, 'button');
      }
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('rule arm, already done today: SY0 opens, a reply, then '
        'acute → the crisis message; zero LLM calls', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _siuYan(run, doneToday: true));
      await _type(tester, '今日好悶');
      await _type(tester, _acute);
      expect(find.byType(EmergencySupportPage), findsOneWidget);
      run.navKey.currentState!.pop();
      await _settle(tester);
      await _close(tester, run);
      final rows = List.of(_rows);
      _commonChecks(rows, agentId: 'siu_yan');
      expect(rows, hasLength(3), reason: rows.join('\n'));
      expect(rows[0].role, 'companion');
      expect(rows[0].parts, [CheckInChatCopy.sy0]);
      expect(rows[0].status, 'rule_based');
      expect(rows[1].userText, '今日好悶');
      expect(SiuYanRuleChatPool.general.map((e) => e.zh),
          contains(rows[1].parts.single));
      expect(rows[2].userText, _acute);
      expect(rows[2].parts, [_crisis]);
      expect(rows[2].status, 'short_circuited');
      expect(rows.map((r) => r.moduleId).toSet(), {SiuYanChatPage.chatModule});
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('Hybrid, already done today: the model opener, a reply, '
        'then acute → the crisis message', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, _siuYan(run, doneToday: true));
      await _type(tester, '今日好悶');
      await _type(tester, _acute);
      expect(find.byType(EmergencySupportPage), findsOneWidget);
      run.navKey.currentState!.pop();
      await _settle(tester);
      await _close(tester, run);
      final rows = List.of(_rows);
      _commonChecks(rows, agentId: 'siu_yan');
      expect(rows, hasLength(3), reason: rows.join('\n'));
      expect(rows[0].parts, [_FakeLlm.opener]);
      expect(rows[0].status, 'ok');
      expect(rows[1].parts, [_FakeLlm.chat]);
      expect(rows[2].parts, [_crisis]);
      expect(rows[2].status, 'short_circuited');
    }, skip: !_hybridTestable);

    testWidgets('Hybrid, the model fails: the fallback line shown is kept',
        (tester) async {
      final run = _Run(ArmAssignment.a)..failLlm = true;
      await _open(tester, run, _siuYan(run, doneToday: true));
      await _type(tester, '今日好悶');
      await _close(tester, run);
      final rows = List.of(_rows);
      // SY0 after the failed opener call, then the fallback line.
      expect(rows[0].parts, [CheckInChatCopy.sy0]);
      expect(rows[0].status, 'fallback');
      expect(rows[1].parts, [SafetyCopy.llmFallback('siu_yan', isEn: false)]);
      expect(rows[1].status, 'fallback');
    }, skip: !_hybridTestable);
  });

  // -------------------------------------------------------------------------
  group('回憶 v2', () {
    testWidgets('rule arm: opener + Q1, fixed line + next question, 唔想講 '
        'row; no scene line; zero LLM calls', (tester) async {
      final run = _Run(ArmAssignment.b);
      _expectReminiscenceRows(await _reminiscenceFirstVisit(tester, run), run);
    }, skip: !_ruleTestable);

    testWidgets('Hybrid: follow-up, reply + next question, 唔想講 row',
        (tester) async {
      final run = _Run(ArmAssignment.a);
      _expectReminiscenceRows(await _reminiscenceFirstVisit(tester, run), run);
    }, skip: !_hybridTestable);

    testWidgets('a later visit: the waiting question opens the new session '
        '(shown_again), then the answer and the next lines', (tester) async {
      // The rule arm where the build reaches it, else Hybrid: the rows
      // are the same apart from the replies.
      final run = _Run(_ruleTestable ? ArmAssignment.b : ArmAssignment.a);
      await _reminiscenceFirstVisit(tester, run);
      final firstSession = _rows.first.sessionId;
      _rows.clear();
      await _push(tester, run, _reminiscence());
      await _type(tester, '屋企有阿嫲。',
          field: find.byKey(const Key('reminiscence_input')));
      await _close(tester, run);
      final rows = List.of(_rows);
      _commonChecks(rows, agentId: 'ah_jan_ah_bak');
      final q3 = ReminiscenceV2Copy.week(1).question(3);
      expect(rows[0].role, 'companion');
      expect(rows[0].parts, [ReminiscenceV2Copy.skipLine, q3]);
      expect(rows[0].status, TranscriptRow.statusShownAgain);
      expect(rows[0].sessionId, isNot(firstSession));
      expect(rows[1].userText, '屋企有阿嫲。');
      expect(rows.map((r) => r.sessionId).toSet(), hasLength(1));
      if (run.rule) expect(run.llm.calls, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('通通', () {
    testWidgets('rule arm: the pool opener, then the template; zero LLM '
        'calls', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, const TungTungPage());
      await _type(tester, '我今日去咗飲茶');
      await _close(tester, run);
      final rows = List.of(_rows);
      _commonChecks(rows, agentId: 'tung_tung');
      expect(rows, hasLength(2), reason: rows.join('\n'));
      expect(rows[0].role, 'companion');
      expect(TungTungRulePool.items.map((o) => o.zh),
          contains(rows[0].parts.single));
      expect(rows[0].status, 'rule_based');
      expect(rows[1].userText, '我今日去咗飲茶');
      expect(rows[1].parts.single, isNotEmpty);
      expect(rows[1].status, 'rule_based');
      expect(find.textContaining(rows[1].parts.single, findRichText: true),
          findsNothing, reason: 'page closed');
      expect(run.llm.calls, isEmpty);
    }, skip: !_ruleTestable);

    testWidgets('Hybrid: opener, model reply, then the fallback line',
        (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, const TungTungPage());
      await _type(tester, '我今日去咗飲茶');
      run.llm.fail = true;
      await _type(tester, '仲有呢？');
      await _close(tester, run);
      final rows = List.of(_rows);
      _commonChecks(rows, agentId: 'tung_tung');
      expect(rows, hasLength(3), reason: rows.join('\n'));
      expect(rows[0].role, 'companion');
      expect(rows[0].parts.single, startsWith('你好啊。'));
      expect(rows[1].parts, [_FakeLlm.chat]);
      expect(rows[1].status, 'ok');
      expect(rows[2].parts,
          [SafetyCopy.llmFallback('tung_tung', isEn: false)]);
      expect(rows[2].status, 'fallback');
    }, skip: !_hybridTestable);
  });

  // -------------------------------------------------------------------------
  group('Hybrid-only pages', () {
    testWidgets('想法練習對話: the opening line, then the reply',
        (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, const ReflectiveDialoguePage());
      await _type(tester, '今日諗起以前啲朋友');
      await _close(tester, run);
      final rows = List.of(_rows);
      _commonChecks(rows, agentId: 'ah_jan_ah_bak');
      expect(rows, hasLength(2), reason: rows.join('\n'));
      expect(rows[0].role, 'companion');
      expect(rows[0].parts, ['你想諗咩、想講咩都得，我喺度聽。']);
      expect(rows[1].userText, '今日諗起以前啲朋友');
      expect(rows[1].parts, [_FakeLlm.chat]);
    }, skip: !_hybridTestable);

    testWidgets('old check-in page (CheckInArmA): opener, then the reply',
        (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, const CheckInArmA(initialMoodValue: 4));
      await _type(tester, '今日行咗公園');
      await _close(tester, run);
      final rows = List.of(_rows);
      _commonChecks(rows, agentId: 'siu_yan');
      expect(rows, hasLength(2), reason: rows.join('\n'));
      expect(rows[0].parts, ['你話今日幾好。咁今日最好嘅一刻係咩呢？']);
      expect(rows[1].userText, '今日行咗公園');
      expect(rows[1].parts, [_FakeLlm.chat]);
    }, skip: !_hybridTestable);
  });
}
