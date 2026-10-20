// Shared harness for the 1020 batch 3 tests (two-page layout, mood row).
// Not a test file itself.  Synthetic data only; no Firebase.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/memory/memory_v1_service.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/context/data/check_in_response_store.dart';
import 'package:app_demo/features/context/presentation/pages/siu_yan_chat_page.dart';
import 'package:app_demo/features/rule_replies/data/rule_reply_history_store.dart';
import 'package:app_demo/features/today/data/mood_recorder.dart';
import 'package:app_demo/features/today/data/mood_row_copy.dart';
import 'package:app_demo/features/today/data/mood_row_store.dart';
import 'package:app_demo/features/today/data/small_action_row_store.dart';
import 'package:app_demo/core/usage/usage_event_recorder.dart';
import 'package:app_demo/core/usage/usage_events_scope.dart';
import 'package:app_demo/features/today/presentation/home_v2_scope.dart';
import 'package:app_demo/features/weekly_bundle/data/weekly_bundle.dart';
import 'package:app_demo/core/scheduling/weekly_schedule.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _forced = String.fromEnvironment('FORCE_ARM');

/// The rule arm is reachable only in a Phase B build (profile arm B).
final bool ruleTestable = FeatureFlags.phaseB && _forced != 'A';

/// Everybody is Hybrid in a Phase A build; Phase B needs profile arm A.
final bool hybridTestable = !FeatureFlags.phaseB || _forced != 'B';

/// Both arms in one run.
final bool bothTestable = FeatureFlags.phaseB && _forced.isEmpty;

/// The arms this build can show (for loops over both).
List<ArmAssignment> get testableArms => [
      if (hybridTestable) ArmAssignment.a,
      if (ruleTestable) ArmAssignment.b,
    ];

/// Fake model.  The rule arm must never get here: [forbid] makes any call
/// a test failure (also counted, in case a page swallows the throw).
class FakeLlm implements LlmClient {
  FakeLlm({this.forbid = false, this.fail = false});
  final bool forbid;

  /// Every call throws (the page's fallback path).
  bool fail;

  final calls = <({String moduleId, String? promptKey, String suffix,
      String input})>[];

  static const moodOpener = '見到你揀咗心情，今日發生咗咩事呀？';
  static const reply1 = '聽落你尋日都幾充實。';
  static const reply2 = '可以去附近公園行下，慢慢嚟。';
  static const opener = '今日想傾咩都得，我喺度。';
  static const chat = '好呀，再同我講多啲。';

  Iterable<({String moduleId, String? promptKey, String suffix, String input})>
      get pageCalls =>
          calls.where((c) => !c.moduleId.startsWith('greeting_ah_jan') &&
              !c.moduleId.startsWith('greeting_tung'));

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
    if (fail) throw StateError('model down');
    if (suffix.contains('[開場·心情]')) {
      return const LlmRawResponse(text: moodOpener);
    }
    if (suffix.contains('[簽到·回應一]')) return const LlmRawResponse(text: reply1);
    if (suffix.contains('[簽到·回應二]')) return const LlmRawResponse(text: reply2);
    if (suffix.contains('[開場·check-in 已做]')) {
      return const LlmRawResponse(text: opener);
    }
    return const LlmRawResponse(text: chat);
  }
}

/// Analytics that keeps every event in memory.
class RecordingAnalytics extends AnalyticsService {
  RecordingAnalytics() : super(firebaseReady: false);

  final events = <(String, Map<String, dynamic>)>[];

  @override
  Future<void> logEvent(String name,
      [Map<String, dynamic> params = const {}]) async {
    events.add((name, Map<String, dynamic>.from(params)));
  }

  List<Map<String, dynamic>> named(String name) =>
      [for (final e in events) if (e.$1 == name) e.$2];
}

class _FakeMemoryV1 extends MemoryV1Service {
  @override
  Future<void> endSession(String agentId) async {}
}

UserProfile homeProfile(ArmAssignment arm, {String? cohort = 'phase_b'}) =>
    UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: arm,
      armAssignmentMode: 'pilot_designated',
      cohort: cohort,
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

/// Weekly bundle parts: everything open, or everything done.
class FakeWeeklyStore implements WeeklyBundleStore {
  bool done = false;

  @override
  Future<Map<WeeklyPart, String?>> partStatus(WeeklyBundle bundle) async => {
        for (final p in bundle.parts) p: done ? 'submitted' : null,
      };
}

/// One run: an arm, its fakes and a clock.
class HomeRun {
  HomeRun(this.arm, {DateTime? now, this.cohort = 'phase_b'})
      : now = now ?? DateTime(2026, 10, 20, 9, 30) {
    moodStore.clock = () => this.now;
    smallActions.clock = () => this.now;
    usage.setProfile(homeProfile(arm, cohort: cohort));
  }

  final ArmAssignment arm;
  final String? cohort;
  DateTime now;
  late FakeLlm llm;
  final analytics = RecordingAnalytics();
  final moodStore = InMemoryMoodRowStore();

  /// 1020m: page 1's small-action row (plans, reminders, 遲啲先 mark).
  final smallActions = InMemorySmallActionRowStore();

  /// 1020m: how often the small-action row opened its (stub) page.
  int smallActionPageOpens = 0;

  /// 1020n: how often 「仲有 N 個計劃」 opened 我嘅計劃 (stub page).
  int myPlansPageOpens = 0;

  /// Usage events (T40 / 1020c / 1020m), switch on, kept in memory.
  final usageSink = InMemoryUsageEventSink();
  late final usage = UsageEventRecorder(
    sink: usageSink,
    enabled: () => true,
    clock: () => now,
    platform: 'test',
    appVersion: '0.0.0',
    buildNumber: '0',
  );
  final weekly = FakeWeeklyStore();
  final checkIns = InMemoryCheckInResponseStore();
  final replyHistory = InMemoryRuleReplyHistoryStore();
  final navKey = GlobalKey<NavigatorState>();
  final moodChats = <MoodChatEntry>[];
  bool checkedIn = false;
  int? daysSince;

  /// When true, M7 / M8 and the check-in row open the real
  /// [SiuYanChatPage] (with these fakes); else a stub page.
  bool realChat = true;

  bool get rule => arm == ArmAssignment.b;

  /// Seed today's (or [at]'s) mood row.
  void seedMood(int mood, DateTime at) {
    final today = MoodRecorder.dateIsoFor(at);
    final seq = moodStore.entries.where((e) => e.dateIso == today).length + 1;
    moodStore.entries.add(MoodEntry(
      id: 'seed$seq',
      mood: mood,
      dateIso: today,
      isPrimary: seq == 1,
      supplementary: seq != 1,
      entrySeqToday: seq,
      respondedAt: at,
      sourceSurface: MoodRowStore.sourceSurface,
      arm: rule ? 'B' : 'A',
    ));
  }

  SiuYanChatPage chatPage({MoodChatEntry? entry}) => SiuYanChatPage(
        moodEntry: entry,
        lowMoodEntry: entry?.lowOpener ?? false,
        checkedInToday: (_) async => checkedIn,
        latestMoodToday: (_) async =>
            moodStore.entries.isEmpty ? null : moodStore.entries.last.mood,
        responseStore: checkIns,
        replyHistory: replyHistory,
        clock: () => now,
        onOpenActionPlan: (_) async {},
      );
}

/// [theme] / [textScale]: the screenshot run uses the App's theme and a
/// CJK font; tests leave them null.
Widget homeHarness(HomeRun run,
    {required Widget home, ThemeData? theme, double? textScale}) {
  run.llm = FakeLlm(forbid: run.rule);
  final llm = LlmGateway(client: run.llm);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  return HomeV2Scope(
    checkedInToday: (_) async => run.checkedIn,
    daysSinceLastCheckIn: (_) async => run.daysSince,
    moodStore: run.moodStore,
    weeklyStore: (_) => run.weekly,
    clock: () => run.now,
    moodChatPage: (entry) {
      run.moodChats.add(entry);
      return run.realChat
          ? run.chatPage(entry: entry)
          : Scaffold(body: Text('chat ${entry.promptId}'));
    },
    checkInPage: () => run.realChat
        ? run.chatPage()
        : const Scaffold(body: Text('check-in')),
    smallActionStore: run.smallActions,
    smallActionPage: () {
      run.smallActionPageOpens++;
      return const Scaffold(body: Text('今日小行動 page'));
    },
    myPlansPage: () {
      run.myPlansPageOpens++;
      return const Scaffold(body: Text('我嘅計劃 page'));
    },
    child: AppSettingsScope(
      settings: AppSettings(
          locale: const Locale('zh'),
          profile: homeProfile(run.arm, cohort: run.cohort)),
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
            child: UsageEventsScope(
              recorder: run.usage,
              child: MaterialApp(
                navigatorKey: run.navKey,
                theme: theme,
                debugShowCheckedModeBanner: false,
                builder: textScale == null
                    ? null
                    : (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              textScaler: TextScaler.linear(textScale)),
                          child: child ?? const SizedBox.shrink(),
                        ),
                locale: const Locale('zh'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                home: home,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps [home] in a tall window (everything on screen).
Future<void> pumpHome(WidgetTester tester, HomeRun run, Widget home,
    {Size? size = const Size(800, 3000),
    ThemeData? theme,
    double? textScale}) async {
  if (size != null) {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  // No connectivity plugin in tests: report Wi-Fi so sends go through.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  tester.binding.defaultBinaryMessenger.setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    MockStreamHandler.inline(onListen: (_, __) {}),
  );
  await tester.pumpWidget(
      homeHarness(run, home: home, theme: theme, textScale: textScale));
  await settle(tester);
}

/// Lets the 700 ms template pause, the 2 s 記低咗 and fake futures finish.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder says(String text) => find.textContaining(text, findRichText: true);

/// The first study day of a bundle at its push hour (W0 = 2026-10-14).
DateTime pushTime(int day, {int hour = 20, int minute = 30}) =>
    DateTime(2026, 10, 14 + day, hour, minute);

/// Today's W0-based helpers for the questionnaire row.
WeeklyScheduleMode get standardMode => WeeklyScheduleMode.standard;
