// 1020c 一 — 今日嘅小邀請 with the #126 switch `suggestionsUseProfileEnabled`:
//   - Hybrid, switch on: the model gets the elder's shared 重要嘅人 and
//     shared 想重新聯絡嘅人 (1020e 二.13: 「可以講」 only, as in the memory),
//     up to ten interests and 唔想提起嘅話題, and the request
//     carries agentId siu_yan (the server adds 小欣's memory block);
//     switch off: none of these, no agentId (as before);
//   - rule arm: the page is exactly the same with the switch on or off —
//     the fixed pool, and no model call at all.
//
// Arm.of reads the profile's arm only in a Phase B build, so the rule-arm
// case runs in tool/ci_flutter_tests.sh "phase B arm gating"
// (--dart-define=PHASE_B=true); in the default build it is skipped.
// Synthetic data only; no Firebase.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/arm/arm_scope.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/social_suggestions/data/suggestion_pool.dart';
import 'package:app_demo/features/social_suggestions/presentation/pages/social_suggestions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _forced = String.fromEnvironment('FORCE_ARM');
final bool _ruleTestable = FeatureFlags.phaseB && _forced != 'A';
final bool _hybridTestable = !FeatureFlags.phaseB || _forced != 'B';

class _FakeLlm implements LlmClient {
  _FakeLlm({this.forbid = false});
  final bool forbid;
  final calls = <({String? agentId, String? systemPrompt, String input})>[];

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
    calls.add((agentId: agentId, systemPrompt: systemPrompt, input: userInput));
    if (forbid) throw TestFailure('rule arm called the LLM ($moduleId)');
    return const LlmRawResponse(text: '- 打個電話畀阿玲。\n- 去公園行下。');
  }
}

UserProfile _profile(ArmAssignment arm) => UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: arm,
      consent: const ConsentFlags(
        functionalData: true,
        transcriptRetention: true,
      ),
      closeContacts: const [
        CloseContact(name: '阿玲', relation: '女兒', share: true),
        CloseContact(name: '何生', relation: '舊同事', share: false),
      ],
      reconnectContacts: const [
        CloseContact(name: '陳太', relation: '舊鄰居', share: false),
        CloseContact(name: '阿強', relation: '舊同事', share: true),
      ],
      interests: const ['yum_cha', 'gardening'],
      avoidTopics: '老伴',
    );

Future<_FakeLlm> _open(WidgetTester tester, ArmAssignment arm) async {
  final fake = _FakeLlm(forbid: arm == ArmAssignment.b);
  final llm = LlmGateway(client: fake);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh'), profile: _profile(arm)),
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
      child: const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: [Locale('zh'), Locale('en')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SocialSuggestionsPage(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return fake;
}

List<String> _cards(WidgetTester tester) => [
      for (final e in find
          .descendant(of: find.byType(Card), matching: find.byType(Text))
          .evaluate())
        (e.widget as Text).data ?? '',
    ];

void main() {
  tearDown(() => RemoteFeatureFlags.current = const RemoteFeatureFlags());

  testWidgets('Hybrid, switch on: the profile fields and agentId go out',
      (tester) async {
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(suggestionsUseProfileEnabled: true);
    final llm = await _open(tester, ArmAssignment.a);
    expect(llm.calls, hasLength(1));
    final c = llm.calls.single;
    expect(c.agentId, 'siu_yan', reason: 'server adds 小欣 memory');
    expect(c.systemPrompt, contains('電腦程式夥伴'));
    expect(c.input, contains('重要嘅人：阿玲（女兒）'));
    expect(c.input, isNot(contains('何生')), reason: 'not shared');
    expect(c.input, contains('想重新聯絡嘅人：阿強（舊同事）'));
    expect(c.input, isNot(contains('陳太')),
        reason: '1020e: not ticked 「可以講」 → not sent');
    expect(c.input, contains('鍾意做嘅嘢：'));
    expect(c.input, contains('唔想提起嘅話題：老伴'));
  }, skip: !_hybridTestable);

  testWidgets('Hybrid, switch off: no profile fields, no agentId',
      (tester) async {
    final llm = await _open(tester, ArmAssignment.a);
    expect(llm.calls, hasLength(1));
    final c = llm.calls.single;
    expect(c.agentId, isNull);
    for (final s in ['阿玲', '陳太', '阿強', '老伴', '鍾意做嘅嘢']) {
      expect(c.input, isNot(contains(s)));
    }
  }, skip: !_hybridTestable);

  testWidgets('rule arm: the same fixed pool with the switch on or off, '
      'and no model call', (tester) async {
    final off = await _open(tester, ArmAssignment.b);
    final cardsOff = _cards(tester);
    expect(off.calls, isEmpty);

    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(suggestionsUseProfileEnabled: true);
    await tester.pumpWidget(const SizedBox());
    final on = await _open(tester, ArmAssignment.b);
    expect(on.calls, isEmpty, reason: 'the rule arm never calls the LLM');
    expect(_cards(tester), cardsOff);
    final pool = const SuggestionPool().rotate(
        seed: DateTime.now().difference(DateTime(DateTime.now().year)).inDays);
    expect(_cards(tester), contains(pool.first.zh));
  }, skip: !_ruleTestable);
}
