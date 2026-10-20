// 1020e 二.7 — action plan, two remote switches (both default off):
//   actionPlanSimplifiedEnabled — one rule in both arms: only 做咩 (the
//     suggestion, pre-filled and editable) and 幾時 are required; a plan
//     waiting for 「件事點呀」 can have 做咩 / 幾時 changed or be deleted
//     (soft); new plan fields and m7_* events only when on.
//   actionPlanMemoryEnabled — the Hybrid planner's two model calls send
//     agentId siu_yan (server adds 小欣's memory block) with the
//     「電腦程式夥伴」 prompts.
// Switch off: pages, stored fields and model calls exactly as before.
//
// Pages are opened directly, so most cases run in every build.  The
// follow-up page picks its arm with Arm.isA, which reads the profile only
// in a Phase B build:
//   flutter test --dart-define=PHASE_B=true test/action_plan_simplified_test.dart
// (tool/ci_flutter_tests.sh "phase B arm gating").  The rule arm's fake
// model fails the test if it is ever called.  Synthetic data; no Firebase
// (a fake ActionPlanRepository stands in for Firestore).
import 'dart:async';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
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
import 'package:app_demo/features/action_loop/data/action_plan.dart';
import 'package:app_demo/features/action_loop/data/action_plan_copy.dart';
import 'package:app_demo/features/action_loop/presentation/pages/action_loop_arm_a_page.dart';
import 'package:app_demo/features/action_loop/presentation/pages/action_loop_arm_b_page.dart';
import 'package:app_demo/features/action_loop/presentation/pages/action_loop_followup_page.dart';
import 'package:app_demo/features/action_loop/presentation/pages/action_loop_landing.dart';
import 'package:app_demo/features/action_loop/presentation/pages/action_plan_edit_page.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _forced = String.fromEnvironment('FORCE_ARM');

/// The follow-up page's rule-arm branch is reachable only in Phase B.
final bool _ruleArmReachable = FeatureFlags.phaseB && _forced != 'A';
final bool _hybridReachable = !FeatureFlags.phaseB || _forced != 'B';

const _suggestion = '約屋企人去飲茶，唔使一定週末，平日人少啲仲舒服。';

class _Call {
  _Call(this.moduleId, this.agentId, this.systemPrompt, this.userInput);
  final String moduleId;
  final String? agentId;
  final String? systemPrompt;
  final String userInput;
}

class _FakeLlm implements LlmClient {
  _FakeLlm({required this.forbid});
  final bool forbid;
  final calls = <_Call>[];

  /// Calls made while forbidden (the gateway might swallow the throw, so
  /// [_open] also checks this is still 0 when the test ends).
  int forbiddenAttempts = 0;

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
    if (forbid) {
      forbiddenAttempts++;
      throw TestFailure('model called where it must not be ($moduleId)');
    }
    calls.add(_Call(moduleId, agentId, systemPrompt, userInput));
    return const LlmRawResponse(text: '聽朝我會約阿明去飲茶。');
  }
}

class _Analytics extends AnalyticsService {
  _Analytics() : super(firebaseReady: false);
  final events = <String, Map<String, dynamic>>{};

  @override
  Future<void> logEvent(String name,
      [Map<String, dynamic> params = const {}]) async {
    events[name] = params;
  }
}

class _FakeRepo extends ActionPlanRepository {
  _FakeRepo([List<ActionPlan>? plans])
      : plans = plans ?? <ActionPlan>[],
        super(available: true);
  final List<ActionPlan> plans;
  final created = <ActionPlan>[];
  final updates = <Map<String, String>>[];
  final deleted = <String>[];

  @override
  Future<String?> create(String uid, ActionPlan plan) async {
    created.add(plan);
    return 'new${created.length}';
  }

  @override
  Future<List<String>> update(String uid, ActionPlan before,
      {required String action, required String whenText}) async {
    final changes =
        ActionPlanEdits.changes(before, action: action, whenText: whenText);
    updates.add({'id': before.id!, ...changes});
    if (changes.isNotEmpty) _replace(before, action.trim(), whenText.trim());
    return changes.keys.toList();
  }

  @override
  Future<void> softDelete(String uid, ActionPlan plan,
      {required String from}) async {
    deleted.add('${plan.id}:$from');
    plans.removeWhere((p) => p.id == plan.id);
    _changes.add(_pending);
  }

  @override
  Future<void> updateOutcome(String uid, String planId,
      {required FollowUpOutcome outcome, String? note}) async {}

  // Like Firestore snapshots: the current list, then every change.
  final _changes = StreamController<List<ActionPlan>>.broadcast();
  List<ActionPlan> get _pending => plans.where((p) => p.isPending).toList();

  @override
  Stream<List<ActionPlan>> pending(String uid) async* {
    yield _pending;
    yield* _changes.stream;
  }

  void _replace(ActionPlan before, String action, String whenText) {
    final i = plans.indexWhere((p) => p.id == before.id);
    if (i < 0) return;
    plans[i] = ActionPlan(
      id: before.id, action: action, whenText: whenText,
      whereText: before.whereText, whoWith: before.whoWith,
      fallback: before.fallback, armCode: before.armCode,
      createdAt: before.createdAt, planFormVersion: before.planFormVersion,
      editCount: before.editCount + 1,
    );
    _changes.add(_pending);
  }
}

ActionPlan _plan(String id, {String arm = 'B'}) => ActionPlan(
      id: id,
      action: '傳個「早晨」短訊畀屋企人。',
      whenText: '上晝',
      whereText: '屋企',
      whoWith: '阿明',
      fallback: '聽日再試',
      armCode: arm,
      createdAt: DateTime(2026, 10, 19, 10),
    );

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
    );

class _Run {
  _Run(this.arm, {bool? forbidLlm})
      : llm = _FakeLlm(forbid: forbidLlm ?? arm == ArmAssignment.b);
  final ArmAssignment arm;
  final _FakeLlm llm;
  final analytics = _Analytics();
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
          memoryV1: const MemoryV1Service(),
          child: MaterialApp(
            navigatorKey: run.navKey,
            theme: AppTheme.light,
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

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
  _phone(tester);
  addTearDown(() => expect(run.llm.forbiddenAttempts, 0,
      reason: 'the model was called where it must not be'));
  await tester.pumpWidget(_harness(run));
  await tester.pumpAndSettle();
  run.navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await _settle(tester);
}

Future<void> _typeA(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('plan_a_field')), text);
  await tester.pumpAndSettle();
}

bool _saveEnabledB(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('plan_b_save'))).onPressed !=
    null;

const _oldKeys = {
  'action', 'whenText', 'whereText', 'whoWith', 'fallback', 'arm',
  'createdAt', 'scheduledFor', 'outcome', 'followUpNote',
};

void main() {
  late _FakeRepo repo;

  setUp(() {
    repo = _FakeRepo();
    ActionPlanRepository.testOverride = repo;
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
  });

  tearDown(() {
    ActionPlanRepository.testOverride = null;
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
  });

  void flags({bool simple = false, bool memory = false}) {
    RemoteFeatureFlags.current = RemoteFeatureFlags(
      actionPlanSimplifiedEnabled: simple,
      actionPlanMemoryEnabled: memory,
    );
  }

  test('switches: only a literal true turns them on', () {
    for (final v in ['true', 1, null, false]) {
      final f = RemoteFeatureFlags.fromMap({
        'actionPlanSimplifiedEnabled': v,
        'actionPlanMemoryEnabled': v,
      });
      expect(f.actionPlanSimplifiedEnabled, isFalse, reason: '$v');
      expect(f.actionPlanMemoryEnabled, isFalse, reason: '$v');
    }
    final on = RemoteFeatureFlags.fromMap(const {
      'actionPlanSimplifiedEnabled': true,
      'actionPlanMemoryEnabled': true,
    });
    expect(on.actionPlanSimplifiedEnabled, isTrue);
    expect(on.actionPlanMemoryEnabled, isTrue);
    expect(const RemoteFeatureFlags().actionPlanSimplifiedEnabled, isFalse);
    expect(const RemoteFeatureFlags().actionPlanMemoryEnabled, isFalse);
  });

  group('data', () {
    test('switch off: toMap has exactly the ten old keys', () {
      expect(_plan('p').toMap().keys.toSet(), _oldKeys);
    });

    test('new fields only when set; parsed back; deleted is not pending', () {
      final p = ActionPlan(
        action: 'a', whenText: 'w', whereText: '', whoWith: '', fallback: '',
        armCode: 'A', createdAt: DateTime(2026, 10, 20),
        planFormVersion: 2, source: ActionPlanSource.suggestion,
        seedAction: 's',
      );
      final m = p.toMap();
      expect(m['planFormVersion'], 2);
      expect(m['source'], 'suggestion');
      expect(m['seedAction'], 's');
      final back = ActionPlan.fromMap('x', {
        ...m,
        'editCount': 2,
        'deletedAt': '2026-10-20T10:00:00.000',
      });
      expect(back.planFormVersion, 2);
      expect(back.editCount, 2);
      expect(back.isPending, isFalse);
      expect(ActionPlan.fromMap('y', m).isPending, isTrue);
      expect(ActionPlan.fromMap('y', m).editCount, 0);
    });

    test('joinFilled leaves out empty items; old plans read as before', () {
      expect(ActionPlan.joinFilled(['上晝', '屋企', '阿明']), '上晝 · 屋企 · 阿明');
      expect(ActionPlan.joinFilled(['上晝', '', ' ']), '上晝');
    });

    test('edits: only real changes; original on the first edit only', () {
      final p = _plan('p');
      expect(ActionPlanEdits.changes(p, action: ' ${p.action} ', whenText: '上晝'),
          isEmpty);
      final c = ActionPlanEdits.changes(p, action: '打電話畀阿明', whenText: '上晝');
      expect(c, {'action': '打電話畀阿明'});
      final now = DateTime(2026, 10, 20, 9);
      final d = ActionPlanEdits.updateData(p, c, nowLocal: now);
      expect(d['action'], '打電話畀阿明');
      expect(d['original'], {'action': p.action, 'whenText': '上晝'});
      expect(d['editLogEntry'], {
        'atLocal': now.toIso8601String(),
        'fields': ['action'],
        'before': {'action': p.action},
      });
      final edited = ActionPlan.fromMap('p', {...p.toMap(), 'editCount': 1});
      expect(
          ActionPlanEdits.updateData(edited, {'whenText': '晚上'}, nowLocal: now)
              .containsKey('original'),
          isFalse);
      expect(ActionPlanEdits.updateData(p, const {}, nowLocal: now), isEmpty);
    });
  });

  group('switch off: unchanged', () {
    testWidgets('rule arm: all five needed, old fields only, no model',
        (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, const ActionLoopArmBPage(seedAction: _suggestion));
      expect(find.byKey(const Key('plan_b_save_hint')), findsNothing);
      expect(find.textContaining(ActionPlanCopy.optionalSuffix), findsNothing);
      await _tap(tester, find.text('上晝'));
      expect(_saveEnabledB(tester), isFalse, reason: 'still needs all four');
      for (final t in ['屋企', '一個人', '聽日再試']) {
        await _tap(tester, find.text(t));
      }
      expect(_saveEnabledB(tester), isTrue);
      // A second tap does not clear a chip with the switch off.
      await _tap(tester, find.text('屋企'));
      expect(_saveEnabledB(tester), isTrue);
      await _tap(tester, find.byKey(const Key('plan_b_save')));
      expect(repo.created, hasLength(1));
      final m = repo.created.single.toMap();
      expect(m.keys.toSet(), _oldKeys);
      expect(m['whereText'], '屋企');
      expect(run.analytics.events.keys.where((k) => k.startsWith('m7_')),
          isEmpty);
    });

    testWidgets('Hybrid: starts at 幾時, four required steps, old prompt, '
        'no agentId', (tester) async {
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, const ActionLoopArmAPage(seedAction: _suggestion));
      expect(find.text('第 2 步 / 共 6 步'), findsOneWidget);
      expect(find.byKey(const Key('plan_a_action_card')), findsNothing);
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      expect(find.text('第 2 步 / 共 6 步'), findsOneWidget, reason: 'empty: stays');
      expect(find.byKey(const Key('plan_a_empty_hint')), findsNothing);
      for (final t in ['聽朝', '公園', '阿明', '遲啲再試']) {
        await _typeA(tester, t);
        await _tap(tester, find.byKey(const Key('plan_a_next')));
      }
      expect(find.byKey(const Key('plan_a_add_details')), findsNothing);
      expect(run.llm.calls, hasLength(1));
      final call = run.llm.calls.single;
      expect(call.moduleId, 'm7_action_loop_summary');
      expect(call.agentId, isNull);
      expect(call.systemPrompt, contains('你係一個鼓勵者'));
      expect(call.userInput.split('\n'), hasLength(5));
      await _tap(tester, find.byKey(const Key('plan_a_save')));
      expect(repo.created.single.toMap().keys.toSet(), _oldKeys);
      expect(run.analytics.events.keys.where((k) => k.startsWith('m7_')),
          isEmpty);
    });

    testWidgets('list: no 改 / 刪除 on the card', (tester) async {
      repo.plans.add(_plan('p1'));
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, const ActionLoopLandingPage());
      expect(find.text('傳個「早晨」短訊畀屋企人。'), findsOneWidget);
      expect(find.text('上晝 · 阿明'), findsOneWidget);
      expect(find.byKey(const Key('plan_card_edit_p1')), findsNothing);
      expect(find.byKey(const Key('plan_card_delete_p1')), findsNothing);
    });
  });

  group('switch on: fewer required items', () {
    testWidgets('rule arm from a suggestion: only 幾時; new fields; no model',
        (tester) async {
      flags(simple: true);
      final run = _Run(ArmAssignment.b);
      run.analytics.setEnvironment(arm: 'B');
      await _open(tester, run, const ActionLoopArmBPage(seedAction: _suggestion));
      final field =
          tester.widget<TextField>(find.byKey(const Key('plan_b_action')));
      expect(field.controller!.text, _suggestion, reason: 'pre-filled, whole');
      expect(field.maxLines, greaterThan(1), reason: 'wraps');
      expect(find.byKey(const Key('plan_b_save_hint')), findsOneWidget);
      expect(find.text('邊度${ActionPlanCopy.optionalSuffix}'), findsOneWidget);
      expect(_saveEnabledB(tester), isFalse);
      // An optional chip can be picked and cleared again.
      await _tap(tester, find.text('屋企'));
      await _tap(tester, find.text('屋企'));
      await _tap(tester, find.text('晚上'));
      expect(_saveEnabledB(tester), isTrue);
      expect(find.byKey(const Key('plan_b_save_hint')), findsNothing);
      // 做咩 can be changed.
      await tester.enterText(find.byKey(const Key('plan_b_action')), '去飲茶');
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('plan_b_save')));
      final p = repo.created.single;
      expect(p.action, '去飲茶');
      expect(p.whenText, '晚上');
      expect([p.whereText, p.whoWith, p.fallback], ['', '', '']);
      final m = p.toMap();
      expect(m['planFormVersion'], 2);
      expect(m['source'], ActionPlanSource.suggestion);
      expect(m['seedAction'], _suggestion);
      expect(m['arm'], 'B');
      expect(run.analytics.events['m7_plan_saved'],
          {'source': 'suggestion', 'filled': ['whenText']});
    });

    testWidgets('rule arm: empty 做咩 cannot be saved; source from caller',
        (tester) async {
      flags(simple: true);
      final run = _Run(ArmAssignment.b);
      run.analytics.setEnvironment(arm: 'B');
      await _open(tester, run,
          const ActionLoopArmBPage(source: ActionPlanSource.checkInQ5));
      await _tap(tester, find.text('上晝'));
      expect(_saveEnabledB(tester), isFalse);
      await tester.enterText(find.byKey(const Key('plan_b_action')), '散步');
      await tester.pumpAndSettle();
      expect(_saveEnabledB(tester), isTrue);
      await _tap(tester, find.byKey(const Key('plan_b_save')));
      expect(repo.created.single.source, ActionPlanSource.checkInQ5);
      expect(repo.created.single.seedAction, isNull);
    });

    testWidgets('Hybrid from a suggestion: 做咩 shown and editable, then '
        '幾時 → 檢視 → save', (tester) async {
      flags(simple: true);
      final run = _Run(ArmAssignment.a);
      run.analytics.setEnvironment(arm: 'A');
      await _open(tester, run, const ActionLoopArmAPage(seedAction: _suggestion));
      expect(find.text('第 1 步 / 共 3 步'), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(const Key('plan_a_field')));
      expect(field.controller!.text, _suggestion);
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      expect(find.text('第 2 步 / 共 3 步'), findsOneWidget);
      expect(find.text(ActionPlanCopy.youWantTo(_suggestion)), findsOneWidget);
      // Empty 幾時: a line says what to do; the step stays.
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      expect(find.byKey(const Key('plan_a_empty_hint')), findsOneWidget);
      expect(find.text('第 2 步 / 共 3 步'), findsOneWidget);
      await _typeA(tester, '聽朝');
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      expect(find.text('第 3 步 / 共 3 步'), findsOneWidget);
      expect(run.llm.calls.single.userInput,
          'action: $_suggestion\nwhen: 聽朝', reason: 'blank items not sent');
      expect(run.llm.calls.single.agentId, isNull, reason: 'memory switch off');
      expect(find.byKey(const Key('plan_a_add_details')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('plan_a_save')));
      final p = repo.created.single;
      expect([p.action, p.whenText, p.whereText, p.whoWith, p.fallback],
          [_suggestion, '聽朝', '', '', '']);
      expect(p.planFormVersion, 2);
      expect(p.source, ActionPlanSource.suggestion);
      expect(p.seedAction, _suggestion);
      expect(run.analytics.events['m7_plan_saved'],
          {'source': 'suggestion', 'filled': ['whenText']});
    });

    testWidgets('Hybrid: optional details can be added or skipped',
        (tester) async {
      flags(simple: true);
      final run = _Run(ArmAssignment.a);
      run.analytics.setEnvironment(arm: 'A');
      await _open(tester, run, const ActionLoopArmAPage(seedAction: _suggestion));
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      await _typeA(tester, '聽朝');
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      await _tap(tester, find.byKey(const Key('plan_a_add_details')));
      expect(find.text('第 1 步 / 共 3 步'), findsOneWidget);
      expect(find.textContaining(ActionPlanCopy.optionalTypedSuffix),
          findsOneWidget);
      // 邊度: skip; 同邊個: type; 唔得點: empty 下一步 = skip too.
      await _tap(tester, find.byKey(const Key('plan_a_skip')));
      await _typeA(tester, '阿明');
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      expect(find.byKey(const Key('plan_a_save')), findsOneWidget);
      expect(find.byKey(const Key('plan_a_add_details')), findsNothing,
          reason: 'offered once');
      expect(run.llm.calls, hasLength(2), reason: 'summary again');
      expect(run.llm.calls.last.userInput,
          'action: $_suggestion\nwhen: 聽朝\nwith: 阿明');
      await _tap(tester, find.byKey(const Key('plan_a_save')));
      final p = repo.created.single;
      expect([p.whereText, p.whoWith, p.fallback], ['', '阿明', '']);
      expect(run.analytics.events['m7_plan_saved'],
          {'source': 'suggestion', 'filled': ['whenText', 'whoWith']});
    });

    testWidgets('Hybrid without a suggestion: 做咩 is required',
        (tester) async {
      flags(simple: true);
      final run = _Run(ArmAssignment.a);
      run.analytics.setEnvironment(arm: 'A');
      await _open(tester, run,
          const ActionLoopArmAPage(source: ActionPlanSource.checkInQ5));
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      expect(find.byKey(const Key('plan_a_empty_hint')), findsOneWidget);
      expect(find.text('第 1 步 / 共 3 步'), findsOneWidget);
      await _typeA(tester, '打電話畀阿明');
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      await _typeA(tester, '今晚');
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      await _tap(tester, find.byKey(const Key('plan_a_save')));
      expect(repo.created.single.source, ActionPlanSource.checkInQ5);
      expect(repo.created.single.seedAction, isNull);
    });
  });

  group('switch on: change or delete a plan (same in both arms, no model)',
      () {
    for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
      testWidgets('${arm.name}: 改 → change 做咩 → saved, event, list updated',
          (tester) async {
        flags(simple: true);
        repo.plans.add(_plan('p1', arm: arm == ArmAssignment.a ? 'A' : 'B'));
        // The edit flow must never call the model, in either arm.
        final run = _Run(arm, forbidLlm: true);
        run.analytics.setEnvironment(arm: arm == ArmAssignment.a ? 'A' : 'B');
        await _open(tester, run, const ActionLoopLandingPage());
        expect(find.byKey(const Key('plan_card_edit_p1')), findsOneWidget);
        expect(find.byKey(const Key('plan_card_delete_p1')), findsOneWidget);
        await _tap(tester, find.byKey(const Key('plan_card_edit_p1')));
        expect(find.text(ActionPlanCopy.editTitle), findsOneWidget);
        final a = tester.widget<TextField>(find.byKey(const Key('plan_edit_action')));
        final w = tester.widget<TextField>(find.byKey(const Key('plan_edit_when')));
        expect(a.controller!.text, '傳個「早晨」短訊畀屋企人。');
        expect(w.controller!.text, '上晝');
        await tester.enterText(
            find.byKey(const Key('plan_edit_action')), '打電話畀阿明');
        await _tap(tester, find.byKey(const Key('plan_edit_when_晚上')));
        await _tap(tester, find.byKey(const Key('plan_edit_save')));
        expect(repo.updates.single,
            {'id': 'p1', 'action': '打電話畀阿明', 'whenText': '晚上'});
        expect(run.analytics.events['m7_plan_edited'],
            {'fields': ['action', 'whenText']});
        expect(find.text(ActionPlanCopy.editTitle), findsNothing, reason: 'closed');
        expect(find.text('打電話畀阿明'), findsOneWidget, reason: 'list updated');
        expect(find.text('晚上 · 阿明'), findsOneWidget);
        expect(repo.deleted, isEmpty);
      });

      testWidgets('${arm.name}: 刪除 asks first; 唔刪 keeps it; 刪除 soft-deletes',
          (tester) async {
        flags(simple: true);
        repo.plans.addAll([_plan('p1'), _plan('p2')]);
        final run = _Run(arm, forbidLlm: true);
        run.analytics.setEnvironment(arm: arm == ArmAssignment.a ? 'A' : 'B');
        await _open(tester, run, const ActionLoopLandingPage());
        await _tap(tester, find.byKey(const Key('plan_card_delete_p1')));
        expect(find.text(ActionPlanCopy.deleteConfirm), findsOneWidget);
        await _tap(tester, find.byKey(const Key('plan_delete_no')));
        expect(repo.deleted, isEmpty);
        expect(run.analytics.events.containsKey('m7_plan_deleted'), isFalse);
        await _tap(tester, find.byKey(const Key('plan_card_delete_p1')));
        await _tap(tester, find.byKey(const Key('plan_delete_yes')));
        expect(repo.deleted, ['p1:landing']);
        expect(run.analytics.events['m7_plan_deleted'], {'from': 'landing'});
        expect(find.text(ActionPlanCopy.deleted), findsOneWidget);
        expect(find.byKey(const Key('plan_card_delete_p1')), findsNothing,
            reason: 'gone from 等住跟進');
        expect(find.byKey(const Key('plan_card_delete_p2')), findsOneWidget);
      });
    }

    testWidgets('edit page: both items needed; delete from the page',
        (tester) async {
      flags(simple: true);
      final run = _Run(ArmAssignment.b);
      run.analytics.setEnvironment(arm: 'B');
      await _open(tester, run, ActionPlanEditPage(plan: _plan('p9')));
      await tester.enterText(find.byKey(const Key('plan_edit_when')), ' ');
      await _tap(tester, find.byKey(const Key('plan_edit_save')));
      expect(find.byKey(const Key('plan_edit_need_both')), findsOneWidget);
      expect(repo.updates, isEmpty);
      await _tap(tester, find.byKey(const Key('plan_edit_delete')));
      await _tap(tester, find.byKey(const Key('plan_delete_yes')));
      expect(repo.deleted, ['p9:edit']);
      expect(find.text(ActionPlanCopy.editTitle), findsNothing, reason: 'closed');
    });

    testWidgets('edit page: nothing changed → nothing written',
        (tester) async {
      flags(simple: true);
      final run = _Run(ArmAssignment.b);
      run.analytics.setEnvironment(arm: 'B');
      await _open(tester, run, ActionPlanEditPage(plan: _plan('p9')));
      await _tap(tester, find.byKey(const Key('plan_edit_save')));
      expect(repo.updates, isEmpty);
      expect(run.analytics.events.containsKey('m7_plan_edited'), isFalse);
    });

    testWidgets('follow-up page leaves out items that were skipped',
        (tester) async {
      flags(simple: true);
      final run = _Run(ArmAssignment.a);
      final p = ActionPlan(
        id: 'p3', action: '去飲茶', whenText: '聽朝', whereText: '', whoWith: '',
        fallback: '', armCode: 'A', createdAt: DateTime(2026, 10, 20),
        planFormVersion: 2,
      );
      await _open(tester, run, ActionLoopFollowUpPage(plan: p));
      expect(find.text('聽朝'), findsOneWidget);
      expect(find.textContaining(' · '), findsNothing);
    });
  });

  group('switch actionPlanMemoryEnabled (Hybrid; rule arm never calls)', () {
    testWidgets('on: summary sends agentId siu_yan and the new prompt',
        (tester) async {
      flags(memory: true);
      final run = _Run(ArmAssignment.a);
      await _open(tester, run, const ActionLoopArmAPage(seedAction: _suggestion));
      for (final t in ['聽朝', '公園', '阿明', '遲啲再試']) {
        await _typeA(tester, t);
        await _tap(tester, find.byKey(const Key('plan_a_next')));
      }
      final call = run.llm.calls.single;
      expect(call.moduleId, 'm7_action_loop_summary');
      expect(call.agentId, 'siu_yan');
      expect(call.systemPrompt, contains('電腦程式夥伴'));
      expect(call.systemPrompt, isNot(contains('你係一個鼓勵者')));
    });

    testWidgets('on, with the simplified rule too: still siu_yan',
        (tester) async {
      flags(simple: true, memory: true);
      final run = _Run(ArmAssignment.a);
      run.analytics.setEnvironment(arm: 'A');
      await _open(tester, run, const ActionLoopArmAPage(seedAction: _suggestion));
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      await _typeA(tester, '聽朝');
      await _tap(tester, find.byKey(const Key('plan_a_next')));
      expect(run.llm.calls.single.agentId, 'siu_yan');
    });

    testWidgets('on: rule arm planner never calls the model', (tester) async {
      flags(simple: true, memory: true);
      final run = _Run(ArmAssignment.b);
      run.analytics.setEnvironment(arm: 'B');
      await _open(tester, run, const ActionLoopArmBPage(seedAction: _suggestion));
      await _tap(tester, find.text('上晝'));
      await _tap(tester, find.byKey(const Key('plan_b_save')));
      expect(repo.created, hasLength(1));
    });

    if (_hybridReachable) {
      testWidgets('on: Hybrid 「件事點呀」 reply sends agentId siu_yan',
          (tester) async {
        flags(memory: true);
        final run = _Run(ArmAssignment.a);
        await _open(tester, run, ActionLoopFollowUpPage(plan: _plan('p1')));
        await _tap(tester, find.text('做到喇'));
        await _tap(tester, find.text('儲存'));
        final call = run.llm.calls.single;
        expect(call.moduleId, 'm7_action_loop_followup');
        expect(call.agentId, 'siu_yan');
        expect(call.systemPrompt, contains('電腦程式夥伴'));
      });

      testWidgets('off: Hybrid 「件事點呀」 reply as before (no agentId)',
          (tester) async {
        final run = _Run(ArmAssignment.a);
        await _open(tester, run, ActionLoopFollowUpPage(plan: _plan('p1')));
        await _tap(tester, find.text('做到喇'));
        await _tap(tester, find.text('儲存'));
        final call = run.llm.calls.single;
        expect(call.agentId, isNull);
        expect(call.systemPrompt, contains('你係一個鼓勵者'));
      });
    }

    if (_ruleArmReachable) {
      testWidgets('on: rule arm 「件事點呀」 never calls the model',
          (tester) async {
        flags(simple: true, memory: true);
        final run = _Run(ArmAssignment.b);
        await _open(tester, run, ActionLoopFollowUpPage(plan: _plan('p1')));
        await _tap(tester, find.text('做到喇'));
        await tester.enterText(find.byType(TextField), '好開心');
        await _tap(tester, find.text('儲存'));
        expect(find.text('已儲存'), findsOneWidget);
      });
    }
  });
}
