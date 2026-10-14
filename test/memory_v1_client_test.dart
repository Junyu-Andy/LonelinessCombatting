// Memory v1, client side. The v1-active cases need a MEMORY_V1 build:
//   flutter test --dart-define=MEMORY_V1=true test/memory_v1_client_test.dart
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/rolling_summary_compiler.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/feature_flags/feature_flags.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/memory_mode.dart';
import 'package:app_demo/core/memory/memory_v1_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/memory/data/memory_layers_copy.dart';
import 'package:app_demo/features/memory/presentation/pages/remembered_page.dart';
import 'package:app_demo/features/onboarding/presentation/pages/agent_onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMemory extends MemoryV1Service {
  _FakeMemory(this.items);

  final List<MemoryItem> items;
  final ended = <String>[];
  final deleted = <String>[];
  final confirmed = <String>[];

  @override
  Future<void> endSession(String agentId) async => ended.add(agentId);

  @override
  Stream<List<MemoryItem>> watch(String uid, MemoryLayer layer) =>
      Stream.value(items.where((i) => i.layer == layer).toList());

  @override
  Future<void> delete(String uid, MemoryItem item) async =>
      deleted.add(item.id);

  @override
  Future<void> confirm(String uid, MemoryItem item) async =>
      confirmed.add(item.id);
}

class _NoLlm implements LlmClient {
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
    return const LlmRawResponse(text: '');
  }
}

UserProfile _profile({bool memory = true}) =>
    UserProfile(uid: 'u1', email: 'a@b.c', displayName: '陳太',
        memoryEnabled: memory);

void main() {
  group('UserProfile.memoryEnabled', () {
    test('round-trips as memory_enabled and defaults to false', () {
      final map = _profile().toMap();
      expect(map['memory_enabled'], isTrue);
      expect(UserProfile.fromMap('u1', map).memoryEnabled, isTrue);
      expect(UserProfile.fromMap('u1', const {}).memoryEnabled, isFalse);
      expect(_profile(memory: false).copyWith(memoryEnabled: true)
          .memoryEnabled, isTrue);
    });
  });

  group('MemoryModes', () {
    UserProfile p({ArmAssignment? arm, String? mode, bool optIn = false}) =>
        UserProfile(uid: 'u', email: 'e', displayName: 'd', arm: arm,
            armAssignmentMode: mode, memoryEnabled: optIn);

    test('Arm B never has memory v1', () {
      expect(MemoryModes.of(p(arm: ArmAssignment.b, mode: 'randomise',
          optIn: true)), MemoryMode.off);
    });

    test('Phase B Arm A is v1 without opting in (Phase B builds)', () {
      expect(MemoryModes.of(p(arm: ArmAssignment.a, mode: 'randomise')),
          FeatureFlags.phaseB ? MemoryMode.phaseB : MemoryMode.off);
    });

    test('Phase A pilot users (force_a) keep v0', () {
      expect(MemoryModes.of(p(arm: ArmAssignment.a, mode: 'force_a')),
          MemoryMode.off);
    });

    test('testers opt in on a MEMORY_V1 build', () {
      expect(MemoryModes.of(p(arm: ArmAssignment.a, optIn: true)),
          FeatureFlags.memoryV1 ? MemoryMode.optIn : MemoryMode.off);
    });

    test('armAssignmentMode is read from Firestore but never written', () {
      final profile = UserProfile.fromMap(
          'u', {'arm': 'A', 'armAssignmentMode': 'randomise'});
      expect(profile.armAssignmentMode, 'randomise');
      expect(profile.toMap().containsKey('armAssignmentMode'), isFalse);
    });
  });

  group('PersonaResolver', () {
    PersonaResolver resolver() => PersonaResolver(
          agentContext: AgentContextService(available: false),
          sharedContext: SharedContextService(available: false),
        );

    test('keeps the v0 summary block when v1 is not active', () async {
      final ctx = await resolver()
          .resolve(agentId: 'siu_yan', profile: _profile(memory: false));
      expect(ctx!.contextSuffix, contains('[過往摘要]'));
    });

    test('drops the v0 summary block for v1 users', () async {
      final ctx =
          await resolver().resolve(agentId: 'siu_yan', profile: _profile());
      expect(ctx!.contextSuffix ?? '', isNot(contains('[過往摘要]')));
    }, skip: !FeatureFlags.memoryV1);
  });

  group('session end', () {
    test('v1 hands the session to the server instead of folding', () async {
      final client = _NoLlm();
      final mem = _FakeMemory(const []);
      await RollingSummaryCompiler(
        agentContext: AgentContextService(available: false),
        llm: LlmGateway(client: client),
        memoryV1Service: mem,
      ).compileAtSessionEnd(uid: 'u1', agentId: 'tung_tung', memoryV1: true);
      expect(mem.ended, ['tung_tung']);
      expect(client.calls, 0);
    });

    test('v0 path never calls the v1 service', () async {
      final mem = _FakeMemory(const []);
      await RollingSummaryCompiler(
        agentContext: AgentContextService(available: false),
        llm: LlmGateway(client: _NoLlm()),
        memoryV1Service: mem,
      ).compileAtSessionEnd(uid: 'u1', agentId: 'tung_tung');
      expect(mem.ended, isEmpty);
    });
  });

  // The page lists memories only when v1 is live for the user, which needs a
  // MEMORY_V1 (or Phase B) build; the default-build suite skips these.
  group('RememberedPage', skip: !FeatureFlags.memoryV1, () {
    Widget page(_FakeMemory mem, {bool memory = true}) => AppSettingsScope(
          settings: AppSettings(
              locale: const Locale('zh'), profile: _profile(memory: memory)),
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: RememberedPage(service: mem),
          ),
        );

    const pending = MemoryItem(id: 'p1', layer: MemoryLayer.fact,
        agentId: 'siu_yan', title: '膝頭', body: '膝頭痛',
        pendingConfirmation: true, sensitive: true);
    const fact = MemoryItem(id: 'f1', layer: MemoryLayer.fact,
        agentId: 'tung_tung', title: '飲早茶', body: '鍾意飲早茶');
    const summary = MemoryItem(id: 's1', layer: MemoryLayer.summary,
        agentId: 'tung_tung', title: '2026-09-28', body: '傾咗飲茶');

    testWidgets('groups items and names the companion told', (tester) async {
      await tester.pumpWidget(page(_FakeMemory([pending, fact, summary])));
      await tester.pumpAndSettle();
      expect(find.text('呢啲要唔要記住？'), findsOneWidget);
      expect(find.text('關於你嘅嘢'), findsOneWidget);
      expect(find.text('之前傾過'), findsOneWidget);
      expect(find.text('同小欣講嘅'), findsOneWidget);
      expect(find.text('同通通講嘅'), findsNWidgets(2));
    });

    testWidgets('confirming a sensitive item', (tester) async {
      final mem = _FakeMemory([pending]);
      await tester.pumpWidget(page(mem));
      await tester.pumpAndSettle();
      await tester.tap(find.text('好，記住'));
      await tester.pumpAndSettle();
      expect(mem.confirmed, ['p1']);
    });

    testWidgets('deleting asks first, then deletes', (tester) async {
      final mem = _FakeMemory([fact]);
      await tester.pumpWidget(page(mem));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(mem.deleted, isEmpty);
      await tester.tap(find.text('唔好記').last);
      await tester.pumpAndSettle();
      expect(mem.deleted, ['f1']);
    });

    testWidgets('T31: S7 notice only with its switch on', (tester) async {
      addTearDown(
          () => RemoteFeatureFlags.current = const RemoteFeatureFlags());
      final notice = find.byKey(const Key('memory_layers_notice'));
      await tester.pumpWidget(page(_FakeMemory([fact])));
      await tester.pumpAndSettle();
      expect(notice, findsNothing);

      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(memoryLayersNoticeEnabled: true);
      await tester.pumpWidget(page(_FakeMemory([fact])));
      await tester.pumpAndSettle();
      expect(find.text(MemoryLayersCopy.s7), findsOneWidget);
      expect(find.text('飲早茶'), findsOneWidget);

      // Also above the empty state; never for someone without memory.
      await tester.pumpWidget(page(_FakeMemory(const [])));
      await tester.pumpAndSettle();
      expect(notice, findsOneWidget);
      expect(find.text('暫時未記住任何嘢。'), findsOneWidget);
      await tester.pumpWidget(page(_FakeMemory([fact]), memory: false));
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
    });

    testWidgets('memory off shows a notice, not the lists', (tester) async {
      await tester.pumpWidget(page(_FakeMemory([fact]), memory: false));
      await tester.pumpAndSettle();
      expect(find.textContaining('記憶已經熄咗'), findsOneWidget);
      expect(find.text('飲早茶'), findsNothing);
    });
  });

  group('onboarding', () {
    Future<void> pump(WidgetTester tester, UserProfile profile) async {
      await tester.pumpWidget(AppSettingsScope(
        settings: AppSettings(locale: const Locale('zh'), profile: profile),
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: [Locale('zh'), Locale('en')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AgentOnboardingPage(),
        ),
      ));
      await tester.pump();
    }

    final notice = find.byKey(const Key('onboarding_memory_notice'));

    testWidgets('Phase B Arm A is told memory is on', (tester) async {
      await pump(tester, const UserProfile(uid: 'u', email: 'e',
          displayName: 'd', arm: ArmAssignment.a,
          armAssignmentMode: 'randomise'));
      expect(notice, FeatureFlags.phaseB ? findsOneWidget : findsNothing);
    });

    testWidgets('Arm B and Phase A pilot users are not', (tester) async {
      for (final p in const [
        UserProfile(uid: 'u', email: 'e', displayName: 'd',
            arm: ArmAssignment.b, armAssignmentMode: 'randomise'),
        UserProfile(uid: 'u', email: 'e', displayName: 'd',
            arm: ArmAssignment.a, armAssignmentMode: 'force_a'),
      ]) {
        await pump(tester, p);
        expect(notice, findsNothing);
      }
    });
  });
}
