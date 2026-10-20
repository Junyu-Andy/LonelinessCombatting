// 1020l §一 (2)(3) — 小欣's chat window (switch `checkInChatV2Enabled`):
//   (2) every note that used to pop up at the bottom over the input bar —
//       the S9 first-use note, the moderate safety notice, the voice notes,
//       the offline line, a snack bar left from the page before — is now in
//       one area under the app bar (or not drawn here at all), above the
//       input bar, with the newest message still fully visible;
//   (3) the answer buttons (Q1's five moods + 唔想答, and Q2, Q3, Q5) are
//       one even grid: same width, same height, labels centred and on one
//       line, at 360 wide with App text 1.06 and 1.30, 320 wide at 1.30 and
//       iPad width.
//   (3b) the five mood faces ([MoodFacePicker]: old check-in pages with the
//       switch off, the rule-arm reminiscence page, the old home mood
//       sheet) are the same even grid, face and word centred both ways;
//   the moderate notice's three choices, tapped inline (chat, Q3b, Q4) and
//   in the old bottom-sheet mode: same pages, same event, flow goes on.
// Both arms: run with --dart-define=PHASE_B=true (both) and with
// FORCE_ARM=B (rule arm); the default build covers Hybrid only.
// Synthetic data only; no Firebase.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
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
import 'package:app_demo/core/safety/safety_copy.dart';
import 'package:app_demo/core/session/chat_session_recorder.dart';
import 'package:app_demo/core/voice/transcription_repository.dart';
import 'package:app_demo/core/voice/voice_copy.dart';
import 'package:app_demo/core/voice/voice_input_button.dart';
import 'package:app_demo/core/voice/voice_recorder.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_store.dart';
import 'package:app_demo/features/brief_pr/data/brief_pr_v2.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_button.dart';
import 'package:app_demo/features/brief_pr/presentation/widgets/session_close_hint.dart';
import 'package:app_demo/features/context/data/check_in_chat_copy.dart';
import 'package:app_demo/features/context/data/check_in_response_store.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_a.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_arm_b.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_page.dart';
import 'package:app_demo/features/context/presentation/pages/check_in_shared.dart';
import 'package:app_demo/features/crisis/presentation/pages/emergency_support_page.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_arm_b_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_pool.dart';
import 'package:app_demo/features/wellbeing/presentation/pages/calm_page.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:app_demo/features/today/data/mood_recorder.dart';
import 'package:app_demo/shared/widgets/equal_button_grid.dart';
import 'package:app_demo/shared/widgets/top_notice_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

String _tag(ArmAssignment arm) => arm == ArmAssignment.b ? 'rule' : 'Hybrid';

/// Fake model; the rule arm must never get here.
class _FakeLlm implements LlmClient {
  _FakeLlm({this.forbid = false});
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
    final suffix = contextSuffix ?? '';
    if (suffix.contains('[開場·check-in 已做]')) {
      return const LlmRawResponse(text: '今日想傾咩都得，我喺度。');
    }
    return const LlmRawResponse(text: '好呀，再同我講多啲。');
  }
}

class _FakeMemoryV1 extends MemoryV1Service {
  @override
  Future<void> endSession(String agentId) async {}
}

class _FakeRecorder implements VoiceRecorder {
  _FakeRecorder({this.permission = true});
  final bool permission;
  StreamController<Uint8List>? _ctrl;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> start() async {
    _ctrl = StreamController<Uint8List>();
    _ctrl!.add(Uint8List.fromList(List.filled(1600, 7)));
    return _ctrl!.stream;
  }

  @override
  Future<void> stop() async => _ctrl?.close();

  @override
  Future<void> cancel() async => _ctrl?.close();

  @override
  Future<void> dispose() async {}
}

class _FailingClient implements TranscriptionClient {
  @override
  Future<TranscriptionResult> transcribe(Uint8List wavBytes) async =>
      const TranscriptionResult.failed('server_error');
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
  _Run(this.arm);
  final ArmAssignment arm;
  late _FakeLlm llm;
  final analytics = AnalyticsService(firebaseReady: false);
  final navKey = GlobalKey<NavigatorState>();
  bool get rule => arm == ArmAssignment.b;
}

Widget _harness(_Run run, double scale) {
  run.llm = _FakeLlm(forbid: run.rule);
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
        analytics: run.analytics,
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
            // The App theme: the faces' words are its bodyMedium (18 px).
            theme: AppTheme.light,
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    ),
  );
}

SiuYanChatPage _page({bool doneToday = false}) => SiuYanChatPage(
      checkedInToday: (_) async => doneToday,
      latestMoodToday: (_) async => null,
      responseStore: InMemoryCheckInResponseStore(),
      replyHistory: InMemoryRuleReplyHistoryStore(),
      clock: () => DateTime(2026, 10, 21, 9, 30),
      onOpenActionPlan: (_) async {},
    );

/// Opens [page] on a [size] screen (logical px) with App text [scale].
Future<void> _open(
  WidgetTester tester,
  _Run run,
  Widget page, {
  Size size = const Size(360, 800),
  double scale = 1.06,
  bool online = true,
  void Function(BuildContext home)? beforePush,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => [online ? 'wifi' : 'none'],
  );
  await tester.pumpWidget(_harness(run, scale));
  await tester.pumpAndSettle();
  beforePush?.call(tester.element(find.text('home')));
  run.navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await _settle(tester);
}

Future<void> _tapAnswer(WidgetTester tester, String q, String code) async {
  await tester.tap(find.byKey(ValueKey('check_in_answer_${q}_$code')));
  await _settle(tester);
}

const _inputBar = ValueKey('siu_yan_input_bar');
const _answerBar = ValueKey('siu_yan_answer_bar');
const _area = ValueKey('top_notice_area');

/// The newest chat bubble (the highest index).
Finder _latestBubble() {
  var best = -1;
  for (final e in find
      .byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('siu_yan_chat_bubble_'))
      .evaluate()) {
    final v = (e.widget.key! as ValueKey<String>).value;
    final i = int.parse(v.substring('siu_yan_chat_bubble_'.length));
    if (i > best) best = i;
  }
  expect(best, greaterThanOrEqualTo(0), reason: 'a bubble on screen');
  return find.byKey(ValueKey('siu_yan_chat_bubble_$best'));
}

/// The notes sit just under the app bar, above (not over) the bottom bar
/// [bar] (null: none shown); the newest message is wholly inside the message list and
/// overlaps neither; nothing floats (no snack bar, no bottom sheet).
void _expectTopPlacement(WidgetTester tester, Finder notice, Key? bar) {
  final app = tester.getRect(find.byType(AppBar));
  final area = tester.getRect(find.byKey(_area));
  final n = tester.getRect(notice);
  final list = tester.getRect(find.byType(ListView));
  final latest = tester.getRect(_latestBubble());
  final screen = tester.getRect(find.byType(Scaffold).last);
  // No bar (the check-in between steps): the screen's bottom edge.
  final b = bar == null
      ? Rect.fromLTWH(screen.left, screen.bottom, screen.width, 0)
      : tester.getRect(find.byKey(bar));

  expect(area.top, moreOrLessEquals(app.bottom, epsilon: 0.5),
      reason: 'right under the app bar');
  expect(n.top, greaterThanOrEqualTo(area.top - 0.5));
  expect(area.bottom, lessThanOrEqualTo(list.top + 0.5),
      reason: 'the message list starts below the notes');
  expect(area.bottom, lessThanOrEqualTo(b.top + 0.5));
  expect(area.overlaps(b), isFalse, reason: 'input bar not covered');
  expect(b.bottom, lessThanOrEqualTo(screen.bottom + 0.5),
      reason: 'input bar on screen');
  expect(latest.top, greaterThanOrEqualTo(list.top - 0.5),
      reason: 'newest message fully visible (top)');
  expect(latest.bottom, lessThanOrEqualTo(list.bottom + 0.5),
      reason: 'newest message fully visible (bottom)');
  expect(latest.overlaps(area), isFalse);
  expect(latest.overlaps(b), isFalse);
  expect(find.byType(SnackBar), findsNothing);
  expect(find.byType(BottomSheet), findsNothing);
}

/// [f] is drawn inside the top area's visible box (not scrolled away).
void _expectInsideArea(WidgetTester tester, Finder f) {
  final area = tester.getRect(find.byKey(_area));
  final r = tester.getRect(f);
  expect(r.top, greaterThanOrEqualTo(area.top - 0.5));
  expect(r.bottom, lessThanOrEqualTo(area.bottom + 0.5));
}

const _phones = [
  (size: Size(360, 800), scale: 1.06, name: '360×800 text 1.06'),
  (size: Size(360, 800), scale: 1.30, name: '360×800 text 1.30'),
];
const _small = (size: Size(320, 700), scale: 1.30, name: '320×700 text 1.30');

/// Columns expected for Q1 (6 buttons), Q2 (4) and Q3 (3).
const _moodSizes = [
  (size: Size(360, 800), scale: 1.06, name: '360 text 1.06', q1: 3, q3: 3),
  (size: Size(360, 800), scale: 1.30, name: '360 text 1.30', q1: 2, q3: 2),
  (size: Size(320, 700), scale: 1.30, name: '320 text 1.30', q1: 2, q3: 2),
  (size: Size(820, 1180), scale: 1.06, name: 'iPad 820 text 1.06', q1: 6, q3: 3),
];

void main() {
  late PhaseBConfig savedConfig;
  late BriefPrStore savedBriefStore;
  late RemoteFeatureFlags savedFlags;

  setUpAll(() {
    // The real S-3 support lines, so the newest message after a moderate
    // hit is the support line, as on the phones.
    SafetyCopy.inject(
        acks: Map<String, dynamic>.from(jsonDecode(
            File(SafetyCopy.acksAsset).readAsStringSync()) as Map));
  });

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    // Most cases: the S9 note already seen on this phone.
    SessionCloseHint.resetForTest();
    SessionCloseHint.claimFirstUse();
    savedConfig = PhaseBConfig.current;
    PhaseBConfig.current = const PhaseBConfig(sessionBriefPrV2Enabled: true);
    savedBriefStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
    savedFlags = RemoteFeatureFlags.current;
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(checkInChatV2Enabled: true);
  });

  tearDown(() {
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedBriefStore;
    RemoteFeatureFlags.current = savedFlags;
    VoiceInputButton.debugRecorderFactory = null;
    VoiceInputButton.debugTranscriptionClient = null;
    ChatSessionRecorder.resetProcessStateForTest();
  });

  group('(2) notes at the top', () {
    for (final arm in _arms) {
      final tag = _tag(arm);

      testWidgets('$tag: the S9 first-use note is under the app bar, above '
          'the Q1 buttons; gone after 6 s', (tester) async {
        SessionCloseHint.resetForTest();
        final run = _Run(arm);
        await _open(tester, run, _page());
        final note = find.text(SessionCloseButton.firstUseNote);
        expect(note, findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(const ValueKey(
                    'top_notice_${SessionCloseButton.firstUseNoticeId}')),
                matching: note),
            findsOneWidget);
        expect(_latestBubble(), findsOneWidget);
        expect(find.textContaining(CheckInChatCopy.q1, findRichText: true),
            findsOneWidget);
        _expectTopPlacement(tester, note, _answerBar);
        await tester.pump(const Duration(seconds: 7));
        await tester.pumpAndSettle();
        expect(note, findsNothing);
        if (run.rule) expect(run.llm.calls, 0);
      });

      for (final p in _phones) {
        testWidgets('$tag, ${p.name}: the moderate safety notice is at the '
            'top; input bar and the support line stay visible; sending '
            'closes it', (tester) async {
          final run = _Run(arm);
          await _open(tester, run, _page(doneToday: true),
              size: p.size, scale: p.scale);
          await _type(tester, '冇人理我');
          final notice =
              find.byKey(const ValueKey('top_notice_moderate_safety'));
          expect(notice, findsOneWidget);
          expect(
              find.descendant(
                  of: notice, matching: find.byType(DistressModerateSheet)),
              findsOneWidget);
          _expectTopPlacement(tester, notice, _inputBar);
          // The newest message is the support line (S-3).
          final ack = SafetyCopy.moderateAck('siu_yan', isEn: false);
          expect(ack, isNotNull);
          expect(
              find.descendant(
                  of: _latestBubble(),
                  matching: find.textContaining(ack!, findRichText: true)),
              findsOneWidget);
          // All three choices can be seen without scrolling.
          _expectInsideArea(tester, find.text('我冇事，繼續'));
          _expectInsideArea(tester, find.text('搵人傾'));
          // The input box is usable while it shows; sending closes it.
          await _type(tester, '今日天氣幾好');
          expect(notice, findsNothing);
          if (run.rule) expect(run.llm.calls, 0);
        });
      }

      testWidgets('$tag: 我冇事，繼續 closes the moderate notice',
          (tester) async {
        final run = _Run(arm);
        await _open(tester, run, _page(doneToday: true));
        await _type(tester, '冇人理我');
        await tester.tap(find.text('我冇事，繼續'));
        await tester.pumpAndSettle();
        expect(find.byType(DistressModerateSheet), findsNothing);
        expect(find.byKey(_area), findsNothing);
      });

      for (final p in [..._phones, _small]) {
        testWidgets('$tag, ${p.name}: moderate at Q4 — the notice at the '
            'top, all three choices in view, the support line visible; the '
            'check-in goes on to Q5 once it is closed (as with the sheet)',
            (tester) async {
          final run = _Run(arm);
          await _open(tester, run, _page(), size: p.size, scale: p.scale);
          await _tapAnswer(tester, 'Q1', 'so_so');
          await _tapAnswer(tester, 'Q2', 'none');
          await _tapAnswer(tester, 'Q3', 'none');
          await _type(tester, '冇人理我');
          final notice =
              find.byKey(const ValueKey('top_notice_moderate_safety'));
          expect(notice, findsOneWidget);
          // Waiting for the elder's choice, as the sheet did: no Q5 yet,
          // nothing at the bottom.
          expect(find.textContaining(CheckInChatCopy.q5, findRichText: true),
              findsNothing);
          expect(find.byKey(_answerBar), findsNothing);
          expect(find.byKey(_inputBar), findsNothing);
          _expectTopPlacement(tester, notice, null);
          _expectInsideArea(tester, find.text('靜一靜（4-4-6 呼吸）'));
          _expectInsideArea(tester, find.text('搵人傾'));
          _expectInsideArea(tester, find.text('我冇事，繼續'));
          await tester.tap(find.text('我冇事，繼續'));
          await _settle(tester);
          expect(notice, findsNothing);
          expect(find.textContaining(CheckInChatCopy.q5, findRichText: true),
              findsOneWidget);
          await _tapAnswer(tester, 'Q5', 'no');
          expect(find.textContaining(CheckInChatCopy.q6, findRichText: true),
              findsOneWidget);
          if (run.rule) expect(run.llm.calls, 0);
        });
      }

      testWidgets('$tag: a snack bar left on the page before is not drawn '
          'over the chat', (tester) async {
        final run = _Run(arm);
        await _open(tester, run, _page(doneToday: true),
            beforePush: (home) => ScaffoldMessenger.of(home).showSnackBar(
                const SnackBar(
                    content: Text('想同小欣講多兩句？'),
                    duration: Duration(seconds: 5))));
        expect(find.text('想同小欣講多兩句？'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
      });

      testWidgets('$tag: offline — the held-message line is at the top',
          (tester) async {
        final run = _Run(arm);
        await _open(tester, run, _page(doneToday: true), online: false);
        await _type(tester, '你好');
        final line = find.textContaining('你而家離線');
        expect(line, findsOneWidget);
        expect(find.descendant(of: find.byKey(_area), matching: line),
            findsOneWidget);
        _expectTopPlacement(tester, line, _inputBar);
      });

      testWidgets('$tag: voice on — the microphone note and S6 are at the '
          'top', (tester) async {
        RemoteFeatureFlags.current = const RemoteFeatureFlags(
            checkInChatV2Enabled: true, voiceInputEnabled: true);
        VoiceInputButton.debugRecorderFactory =
            () => _FakeRecorder(permission: false);
        final run = _Run(arm);
        await _open(tester, run, _page(doneToday: true));
        await tester.tap(find.byIcon(Icons.mic_none_rounded));
        await tester.pumpAndSettle();
        final hint = find.byKey(const ValueKey('top_notice_voice_mic_permission'));
        expect(hint, findsOneWidget);
        _expectTopPlacement(tester, hint, _inputBar);
        await tester.tap(hint);
        await tester.pumpAndSettle();
        expect(hint, findsNothing);
      });

      testWidgets('$tag: voice on — S6 (transcription failed) at the top',
          (tester) async {
        RemoteFeatureFlags.current = const RemoteFeatureFlags(
            checkInChatV2Enabled: true, voiceInputEnabled: true);
        VoiceInputButton.debugRecorderFactory = () => _FakeRecorder();
        VoiceInputButton.debugTranscriptionClient = _FailingClient();
        final run = _Run(arm);
        await _open(tester, run, _page(doneToday: true));
        await tester.tap(find.byIcon(Icons.mic_none_rounded));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.stop_circle_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        final s6 = find.text(VoiceCopy.s6TranscriptionFailed);
        expect(s6, findsOneWidget);
        expect(find.byKey(const ValueKey('voice_s6_notice')), findsNothing,
            reason: 'not the card over the newest message');
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('top_notice_voice_s6')),
                matching: s6),
            findsOneWidget);
        _expectTopPlacement(tester, s6, _inputBar);
        await tester.pump(VoiceInputButton.noticeDuration);
        await tester.pumpAndSettle();
        expect(s6, findsNothing);
      });
    }

    // Pages without a top area: unchanged.
    testWidgets('elsewhere: the S9 note is still a snack bar and the '
        'moderate notice still a bottom sheet', (tester) async {
      SessionCloseHint.resetForTest();
      final state = DistressState();
      final router = DistressRouter(state: state);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            leading: SessionCloseButton(onPressed: () {}),
            leadingWidth: 200,
          ),
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => router.route(
                  const DistressMatch(DistressLevel.moderateInterrupt),
                  context: context),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(SessionCloseButton.firstUseNote), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(DistressModerateSheet), findsOneWidget);
      // (English locale here: 「我冇事，繼續」 is its TextButton.)
      await tester.tap(find.descendant(
          of: find.byType(DistressModerateSheet),
          matching: find.byType(TextButton)));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('TopNoticeController: same id replaces; timers end with the '
        'host', (tester) async {
      final c = TopNoticeController();
      await tester.pumpWidget(MaterialApp(
        home: TopNoticeHost(
          controller: c,
          child: const Scaffold(
              body: Column(children: [TopNoticeArea(maxHeight: 300)])),
        ),
      ));
      c.showText('a', 'one', duration: const Duration(seconds: 3));
      c.showText('a', 'two', duration: const Duration(seconds: 3));
      c.showText('b', 'three');
      await tester.pump();
      expect(find.text('one'), findsNothing);
      expect(find.text('two'), findsOneWidget);
      expect(c.ids, ['a', 'b']);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('two'), findsNothing);
      expect(find.text('three'), findsOneWidget);
      await tester.tap(find.text('three'));
      await tester.pump();
      expect(c.ids, isEmpty);
      c.showText('c', 'four', duration: const Duration(seconds: 30));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('(3) answer buttons: one even grid', () {
    for (final arm in _arms) {
      final tag = _tag(arm);
      for (final s in _moodSizes) {
        testWidgets('$tag, ${s.name}: Q1 — same width and height, '
            'one-line centred labels, ${s.q1} per row; Q2 / Q3 even too',
            (tester) async {
          final run = _Run(arm);
          await _open(tester, run, _page(), size: s.size, scale: s.scale);
          expect(tester.takeException(), isNull);
          _expectEvenGrid(tester, 'Q1', CheckInChatCopy.q1Options,
              scale: s.scale, cols: s.q1);
          await _tapAnswer(tester, 'Q1', 'good');
          _expectEvenGrid(tester, 'Q2', CheckInChatCopy.q2Options,
              scale: s.scale, cols: 4);
          await _tapAnswer(tester, 'Q2', 'none');
          _expectEvenGrid(tester, 'Q3', CheckInChatCopy.q3Options,
              scale: s.scale, cols: s.q3);
          expect(tester.takeException(), isNull);
          if (run.rule) expect(run.llm.calls, 0);
        });
      }
    }

    test('column choices: even rows only', () {
      expect(EqualButtonGrid.columnChoices(6), [6, 3, 2, 1]);
      expect(EqualButtonGrid.columnChoices(5), [5, 3, 2, 1]);
      expect(EqualButtonGrid.columnChoices(4), [4, 2, 1]);
      expect(EqualButtonGrid.columnChoices(2), [2, 1]);
    });

    testWidgets('too narrow for one line: every button wraps the same '
        'way — same width, same height', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              child: EqualButtonGrid(children: [
                for (final t in ['好唔開心好唔開心', '幾好', '一般般'])
                  OutlinedButton(
                    onPressed: () {},
                    child: Text(t,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18)),
                  ),
              ]),
            ),
          ),
        ),
      ));
      final grid = tester.renderObject<RenderEqualButtonGrid>(
          find.byType(EqualButtonGrid));
      expect(grid.columns, 1);
      final rects = [
        for (final e in find.byType(OutlinedButton).evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
      for (final r in rects) {
        expect(r.width, moreOrLessEquals(rects.first.width, epsilon: 0.5));
        expect(r.height, moreOrLessEquals(rects.first.height, epsilon: 0.5));
      }
      final long = tester.renderObject<RenderParagraph>(find.text('好唔開心好唔開心'));
      expect(long.size.height, greaterThan(18 * 1.5), reason: 'it wraps');
      expect(tester.takeException(), isNull);
    });
  });

  group('(3b) MoodFacePicker: one even grid of five', () {
    // The old check-in pages and the old home mood sheet have 24 px each
    // side; the rule-arm reminiscence page 20.
    for (final side in [24.0, 20.0]) {
      for (final f in _faceSizes) {
        testWidgets('side $side, ${f.name}: ${f.cols} per row, same size, '
            'face and word centred, words on one line; picking one moves '
            'nothing', (tester) async {
          await _pumpPicker(tester, size: f.size, scale: f.scale, side: side);
          _expectEvenFaces(tester, scale: f.scale, cols: f.cols);
          final before =
              tester.getRect(find.byKey(const ValueKey('mood_face_good')));
          await tester.tap(find.byKey(const ValueKey('mood_face_veryLow')));
          await tester.pumpAndSettle();
          _expectEvenFaces(tester, scale: f.scale, cols: f.cols);
          expect(tester.getRect(find.byKey(const ValueKey('mood_face_good'))),
              before);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final f in _faceSizes) {
      testWidgets('old check-in (switch off), Hybrid mood gate, ${f.name}',
          (tester) async {
        RemoteFeatureFlags.current = const RemoteFeatureFlags();
        final run = _Run(ArmAssignment.a);
        // No mood today → the gate (首先，揀一個最似你今日心情嘅樣？).
        await _open(tester, run, CheckInArmA(moodRecorder: _NoMoodRecorder()),
            size: f.size, scale: f.scale);
        expect(find.byType(CheckInArmA), findsOneWidget);
        expect(find.byKey(const Key('check_in_mood_gate_start')),
            findsOneWidget);
        expect(find.byType(MoodFacePicker), findsOneWidget);
        _expectEvenFaces(tester, scale: f.scale, cols: f.cols);
        expect(tester.takeException(), isNull);
      }, skip: !_hybridTestable);

      testWidgets('old check-in (switch off), rule-arm form, ${f.name}',
          (tester) async {
        RemoteFeatureFlags.current = const RemoteFeatureFlags();
        final run = _Run(ArmAssignment.b);
        await _open(tester, run, const CheckInPage(),
            size: f.size, scale: f.scale);
        expect(find.byType(CheckInArmB), findsOneWidget);
        _expectEvenFaces(tester, scale: f.scale, cols: f.cols);
        expect(tester.takeException(), isNull);
        expect(run.llm.calls, 0);
      }, skip: !_ruleTestable);

      // The picker shows there only with the rule template replies on:
      //   --dart-define=RULE_TEMPLATE_REPLIES=true
      //   --dart-define=RULE_TEMPLATE_REPLIES_ALLOW_PLACEHOLDER=true
      testWidgets('rule-arm reminiscence page, ${f.name}', (tester) async {
        final run = _Run(ArmAssignment.b);
        await _open(
            tester,
            run,
            ReminiscenceArmBPage(
                theme: ReminiscenceTheme.byIndex(1),
                replyHistory: InMemoryRuleReplyHistoryStore()),
            size: f.size,
            scale: f.scale);
        // The form is a lazy list: scroll down to the faces.
        await tester.scrollUntilVisible(find.byType(MoodFacePicker), 200,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        _expectEvenFaces(tester, scale: f.scale, cols: f.cols);
        expect(tester.takeException(), isNull);
        expect(run.llm.calls, 0);
      }, skip: !RuleReplyPool.enabled);
    }
  });

  group('moderate notice: each choice', () {
    for (final arm in _arms) {
      for (final path in ['chat', 'Q3b', 'Q4']) {
        for (final choice in _Choice.values) {
          testWidgets('${_tag(arm)}, $path, inline: ${choice.name} — '
              '${choice.what}; back on the page, the flow goes on',
              (tester) async {
            final run = _Run(arm);
            await _open(tester, run, _page(doneToday: path == 'chat'));
            if (path != 'chat') {
              await _tapAnswer(tester, 'Q1', 'so_so');
              await _tapAnswer(tester, 'Q2', 'none');
              await _tapAnswer(
                  tester, 'Q3', path == 'Q3b' ? 'small' : 'none');
            }
            await _type(tester, '冇人理我');
            final notice = find.byKey(
                const ValueKey('top_notice_moderate_safety'),
                skipOffstage: false);
            expect(notice, findsOneWidget);
            final latest = _latestIndex();
            await _choose(tester, run, choice);
            expect(notice, findsNothing, reason: 'the notice is closed');
            expect(find.byType(SiuYanChatPage), findsOneWidget);
            expect(find.textContaining('冇人理我', findRichText: true),
                findsOneWidget);
            switch (path) {
              case 'chat':
                expect(find.byKey(_inputBar), findsOneWidget);
                await _type(tester, '今日天氣幾好');
                expect(_latestIndex(), latest + 2, reason: 'sent, answered');
              case 'Q3b':
                expect(
                    find.textContaining(CheckInChatCopy.q4, findRichText: true),
                    findsOneWidget);
                await _type(tester, '下晝去公園行下');
                expect(
                    find.textContaining(CheckInChatCopy.q5, findRichText: true),
                    findsOneWidget);
              case 'Q4':
                expect(
                    find.textContaining(CheckInChatCopy.q5, findRichText: true),
                    findsOneWidget);
                await _tapAnswer(tester, 'Q5', 'no');
                expect(
                    find.textContaining(CheckInChatCopy.q6, findRichText: true),
                    findsOneWidget);
            }
            if (run.rule) expect(run.llm.calls, 0);
          });
        }
      }
    }

    for (final choice in _Choice.values) {
      testWidgets('other pages, the bottom sheet (no onClose): '
          '${choice.name} — ${choice.what}, as before', (tester) async {
        final run = _Run(_arms.first);
        await _open(tester, run, const _SheetHost());
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(DistressModerateSheet), findsOneWidget);
        await _choose(tester, run, choice);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(DistressModerateSheet), findsNothing);
        expect(find.text('route done'), findsOneWidget,
            reason: 'route() returned once the sheet closed');
      });
    }
  });
}

/// No mood recorded (no Firebase in tests).
class _NoMoodRecorder extends MoodRecorder {
  @override
  Future<MoodEntry?> latestForDate(
          {required String uid, required String dateIso}) async =>
      null;

  @override
  Future<MoodEntry?> mostRecent({required String uid}) async => null;
}

enum _Choice {
  calm('opens CalmPage'),
  reach('logs moderate_sheet_opened_resources, opens the resources page'),
  ok('closes it');

  const _Choice(this.what);
  final String what;
}

/// Taps [choice] in the moderate notice (inline or sheet), checks the page
/// it opens and comes back.
Future<void> _choose(WidgetTester tester, _Run run, _Choice choice) async {
  int resourcesEvents() => run.analytics.bufferedEvents
      .where((e) => e['name'] == 'moderate_sheet_opened_resources')
      .length;
  final before = resourcesEvents();
  switch (choice) {
    case _Choice.calm:
      await tester.tap(find.text('靜一靜（4-4-6 呼吸）'));
      await tester.pumpAndSettle();
      expect(find.byType(CalmPage), findsOneWidget);
      expect(find.byType(DistressModerateSheet, skipOffstage: false),
          findsNothing);
      expect(resourcesEvents(), before);
      run.navKey.currentState!.pop();
      await _settle(tester);
    case _Choice.reach:
      await tester.tap(find.text('搵人傾'));
      await tester.pumpAndSettle();
      final page = find.byType(EmergencySupportPage);
      expect(page, findsOneWidget);
      expect(tester.widget<EmergencySupportPage>(page).from, 'moderate_sheet');
      expect(find.byType(DistressModerateSheet, skipOffstage: false),
          findsNothing);
      expect(resourcesEvents(), before + 1);
      run.navKey.currentState!.pop();
      await _settle(tester);
    case _Choice.ok:
      await tester.tap(find.text('我冇事，繼續'));
      await _settle(tester);
      expect(resourcesEvents(), before);
  }
  expect(find.byType(CalmPage), findsNothing);
  expect(find.byType(EmergencySupportPage), findsNothing);
}

/// A page without a top area: routes a moderate hit as every other page
/// does (the bottom sheet).
class _SheetHost extends StatefulWidget {
  const _SheetHost();

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
              onPressed: () async {
                await CoreServicesScope.of(context).distressRouter.route(
                    const DistressMatch(DistressLevel.moderateInterrupt),
                    context: context);
                if (mounted) setState(() => _done = true);
              },
              child: const Text('go'),
            ),
            if (_done) const Text('route done'),
          ]),
        ),
      );
}

int _latestIndex() {
  var best = -1;
  for (final e in find
      .byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('siu_yan_chat_bubble_'))
      .evaluate()) {
    final v = (e.widget.key! as ValueKey<String>).value;
    final i = int.parse(v.substring('siu_yan_chat_bubble_'.length));
    if (i > best) best = i;
  }
  return best;
}

/// Columns expected for the five faces (24 or 20 px each side).
const _faceSizes = [
  (size: Size(360, 800), scale: 1.06, name: '360 text 1.06', cols: 3),
  (size: Size(360, 800), scale: 1.30, name: '360 text 1.30', cols: 2),
  (size: Size(320, 700), scale: 1.30, name: '320 text 1.30', cols: 2),
  (size: Size(820, 1180), scale: 1.06, name: 'iPad 820 text 1.06', cols: 5),
];

Future<void> _pumpPicker(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required double side,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  MoodFace? value;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: side, vertical: 16),
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MoodFacePicker(
                  value: value, onChanged: (v) => setState(() => value = v)),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The five faces: [cols] per row, every one the same width and height,
/// rows level, the last row centred, face and word centred across, the
/// pair centred up-down, the word on one line, all on screen.
void _expectEvenFaces(
  WidgetTester tester, {
  required double scale,
  required int cols,
}) {
  final grid = tester.renderObject<RenderEqualButtonGrid>(find.descendant(
      of: find.byType(MoodFacePicker), matching: find.byType(EqualButtonGrid)));
  expect(grid.columns, cols, reason: 'faces per row');
  final gridRect = tester.getRect(find.descendant(
      of: find.byType(MoodFacePicker), matching: find.byType(EqualButtonGrid)));
  final screen = tester.getRect(find.byType(Scaffold).last);
  Rect? first;
  final rows = <double, List<Rect>>{};
  for (final face in MoodFace.values) {
    final button = find.byKey(ValueKey('mood_face_${face.name}'));
    final r = tester.getRect(button);
    first ??= r;
    expect(r.width, moreOrLessEquals(first.width, epsilon: 0.5),
        reason: '${face.name} width');
    expect(r.height, moreOrLessEquals(first.height, epsilon: 0.5),
        reason: '${face.name} height');
    expect(r.left, greaterThanOrEqualTo(screen.left - 0.5));
    expect(r.right, lessThanOrEqualTo(screen.right + 0.5));
    rows.putIfAbsent((r.top * 2).roundToDouble() / 2, () => []).add(r);
    final emoji = tester.getRect(
        find.descendant(of: button, matching: find.text(face.emoji())));
    final label = tester.getRect(
        find.descendant(of: button, matching: find.text(face.label(false))));
    expect((emoji.center.dx - r.center.dx).abs(), lessThan(1.0),
        reason: '${face.name} face centred across');
    expect((label.center.dx - r.center.dx).abs(), lessThan(1.0),
        reason: '${face.name} word centred across');
    expect(((emoji.top + label.bottom) / 2 - r.center.dy).abs(),
        lessThan(1.0), reason: '${face.name} centred up-down');
    // bodyMedium 18 px, line height 1.55: one line.
    expect(label.height, lessThan(18 * 1.55 * scale * 1.5),
        reason: '${face.name} word on one line');
  }
  expect(rows.length, (MoodFace.values.length / cols).ceil(),
      reason: 'rows level');
  for (final row in rows.values) {
    final left = row.map((r) => r.left).reduce((a, b) => a < b ? a : b);
    final right = row.map((r) => r.right).reduce((a, b) => a > b ? a : b);
    expect(((left + right) / 2 - gridRect.center.dx).abs(), lessThan(1.0),
        reason: 'each row centred');
  }
}

/// Q buttons: one grid of [cols] columns — every button the same width
/// and height, rows level, the label one line and centred, all inside the
/// answer bar and on screen.
void _expectEvenGrid(
  WidgetTester tester,
  String q,
  List<CheckInOption> options, {
  required double scale,
  required int cols,
}) {
  final grid =
      tester.renderObject<RenderEqualButtonGrid>(find.byType(EqualButtonGrid));
  expect(grid.columns, cols, reason: '$q columns');
  final bar = tester.getRect(find.byKey(_answerBar));
  final screen = tester.getRect(find.byType(Scaffold).last);
  expect(bar.bottom, lessThanOrEqualTo(screen.bottom + 0.5));
  Rect? first;
  final tops = <double>{};
  for (final o in options) {
    final button = find.byKey(ValueKey('check_in_answer_${q}_${o.code}'));
    final r = tester.getRect(button);
    first ??= r;
    expect(r.width, moreOrLessEquals(first.width, epsilon: 0.5),
        reason: '${o.label} width');
    expect(r.height, moreOrLessEquals(first.height, epsilon: 0.5),
        reason: '${o.label} height');
    expect(r.left, greaterThanOrEqualTo(bar.left - 0.5));
    expect(r.right, lessThanOrEqualTo(bar.right + 0.5));
    tops.add((r.top * 2).roundToDouble() / 2);
    final label = find.descendant(of: button, matching: find.text(o.label));
    final l = tester.getRect(label);
    // One line: a 18 px label at this App text scale.
    expect(l.height, lessThan(18 * scale * 1.5), reason: '${o.label} one line');
    expect((l.center.dx - r.center.dx).abs(), lessThan(1.0),
        reason: '${o.label} centred across');
    expect((l.center.dy - r.center.dy).abs(), lessThan(1.0),
        reason: '${o.label} centred up-down');
  }
  expect(tops.length, (options.length / cols).ceil(), reason: 'rows level');
}
