// 1020o — 自己 page and the 人生點滴 landing page (both arms, no switch).
//
// 第一节: the 自己 entry 「人生回顧」 became 「我嘅人生小篇章」 with the line
// 「每個禮拜講完，整理好嘅小文章都喺度。」 and opens the v2 chapters page;
// the old My Story page is deleted (its Hybrid-only 「反思傾偈」 entry moved
// to the landing page).  The chapters page and the landing page are
// readable in high contrast.
// 第四节: the landing page shows the chosen companion's picture (阿珍 or
// 阿伯; initial 珍 / 伯 without the picture) with the bubble
// 「我係{name}。…」 (an `app_config/usage_copy` override replaces it, with
// {name} filled in); each theme card has its one line (by week index), no
// 「第 N 週」, and the picture tile (the number tile while
// assets/reminiscence/theme_N.png is missing).
//
//   flutter test test/selfpage_landing_1020o_test.dart
//   flutter test --dart-define=PHASE_B=true test/selfpage_landing_1020o_test.dart
//   flutter test --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
//     test/selfpage_landing_1020o_test.dart
//
// Synthetic data only; no Firebase; the rule arm fails the test if it
// reaches the model.
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/agent_avatar.dart';
import 'package:app_demo/core/agents/agent_registry.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/config/phase_b_config.dart';
import 'package:app_demo/core/config/usage_copy.dart';
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
import 'package:app_demo/features/reflective_dialogue/presentation/pages/reflective_dialogue_page.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_themes.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_copy.dart';
import 'package:app_demo/features/reminiscence/data/reminiscence_v2_store.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_chapters_page.dart';
import 'package:app_demo/features/reminiscence/presentation/pages/reminiscence_landing.dart';
import 'package:app_demo/features/settings/presentation/pages/settings_page.dart';
import 'package:app_demo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const _janAsset = 'assets/agents/ah_jan_avatar.png';
const _bakAsset = 'assets/agents/ah_bak_avatar.png';

class _FakeLlm implements LlmClient {
  _FakeLlm({required this.forbid});
  final bool forbid;
  final calls = <String>[];

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
    return const LlmRawResponse(text: '好呀，慢慢講。');
  }
}

class _FakeMemoryV1 extends MemoryV1Service {
  @override
  Future<void> endSession(String agentId) async {}
}

/// No agent pictures (as if missing): the avatar shows the initial.
class _NoAgentPicturesBundle extends CachingAssetBundle {
  static bool _isAgentPicture(String key) => key.startsWith('assets/agents/');

  @override
  Future<ByteData> load(String key) => _isAgentPicture(key)
      ? Future<ByteData>.error(FlutterError('no picture: $key'))
      : rootBundle.load(key);

  @override
  Future<ImmutableBuffer> loadBuffer(String key) => _isAgentPicture(key)
      ? Future<ImmutableBuffer>.error(FlutterError('no picture: $key'))
      : rootBundle.loadBuffer(key);
}

UserProfile _profile(ArmAssignment arm, AgentGenderVariant variant) =>
    UserProfile(
      uid: 'u1',
      email: 'synthetic@example.com',
      displayName: '測試',
      arm: arm,
      armAssignmentMode: 'pilot_designated',
      cohort: 'phase_b',
      w0Date: '2026-10-14',
      ahJanAhBakVariant: variant,
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
  _Run(this.arm, this.variant,
      {this.highContrast = false, this.noPictures = false});
  final ArmAssignment arm;
  final AgentGenderVariant variant;
  final bool highContrast;
  final bool noPictures;
  late final _FakeLlm llm = _FakeLlm(forbid: arm == ArmAssignment.b);
  late final AppSettings settings =
      AppSettings(locale: const Locale('zh'), profile: _profile(arm, variant));
  final navKey = GlobalKey<NavigatorState>();
  final chapters = InMemoryReminiscenceChapterStore();

  bool get rule => arm == ArmAssignment.b;
  bool get bak => variant == AgentGenderVariant.masculine;
  String get name => bak ? '阿伯' : '阿珍';

  void install() {
    ReminiscenceV2Stores.weekOverride = InMemoryReminiscenceWeekStore();
    ReminiscenceV2Stores.chaptersOverride = chapters;
    ReminiscenceV2Stores.ratingsOverride = InMemoryReminiscenceRatingStore();
    ReminiscenceV2Stores.summaryOverride = InMemoryReminiscenceSummaryWriter();
  }

  /// A ready, not yet saved chapter for week 1 (synthetic text).
  void readyChapter() => chapters.serverWrite('u1', 1, {
        'weekIndex': 1,
        'source': rule ? 'rule' : 'hybrid',
        'status': 'ready',
        if (rule) 'ruleText': '細個住喺深水埗。' else 'finalText': '細個住喺深水埗。',
        'version': 1,
        'requestId': 'r1',
      });
}

Widget _harness(_Run run, Widget home) {
  final llm = LlmGateway(client: run.llm);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  Widget app = MaterialApp(
    navigatorKey: run.navKey,
    theme: run.highContrast ? AppTheme.highContrast : AppTheme.light,
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: home,
  );
  if (run.noPictures) {
    app = DefaultAssetBundle(bundle: _NoAgentPicturesBundle(), child: app);
  }
  return AppSettingsScope(
    settings: run.settings,
    child: AuthServiceScope(
      authService: AuthService(available: false),
      child: AnalyticsScope(
        analytics: AnalyticsService(firebaseReady: false)
          ..setEnvironment(arm: run.rule ? 'B' : 'A'),
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
          child: app,
        ),
      ),
    ),
  );
}

Future<void> _boot(WidgetTester tester, _Run run, Widget home) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 3000);
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  run.install();
  await tester.pumpWidget(_harness(run, home));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder _anyText(Pattern s) => find.textContaining(s, findRichText: true);

Finder _picture(String asset) => find.byWidgetPredicate((w) =>
    w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == asset);

// --- contrast -------------------------------------------------------------

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The colour painted behind [e]: the nearest Material / decoration /
/// coloured box above it (translucent ones blended onto what is under).
Color _background(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is Material && w.type != MaterialType.transparency) c = w.color;
    if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    }
    if (w is ColoredBox) c = w.color;
    if (c != null && c.a > 0) {
      layers.add(c);
      if (c.a >= 1) return false;
    }
    return true;
  });
  var bg = Colors.white;
  for (final c in layers.reversed) {
    bg = Color.alphaBlend(c, bg);
  }
  return bg;
}

/// Every visible text on the page reaches [min] contrast with what is
/// painted behind it.
void _expectReadable(WidgetTester tester, double min, String where) {
  final texts = find.byType(RichText, skipOffstage: true);
  var checked = 0;
  for (final e in texts.evaluate()) {
    final rt = e.widget as RichText;
    if (rt.text.toPlainText().trim().isEmpty) continue;
    final spans = <TextStyle>[];
    rt.text.visitChildren((s) {
      final st = s.style;
      if (st?.color != null) spans.add(st!);
      return true;
    });
    final bg = _background(e);
    for (final st in spans) {
      final fg = Color.alphaBlend(st.color!, bg);
      final ratio = _contrast(fg, bg);
      expect(ratio, greaterThanOrEqualTo(min),
          reason: '$where: 「${rt.text.toPlainText()}」 '
              '${st.color} on $bg = ${ratio.toStringAsFixed(2)}');
      checked++;
    }
  }
  expect(checked, greaterThan(3), reason: '$where: texts checked');
}

void main() {
  late PhaseBConfig savedConfig;
  late BriefPrStore savedBriefStore;
  late RemoteFeatureFlags savedFlags;
  late UsageCopy savedCopy;

  setUp(() {
    ChatSessionRecorder.resetProcessStateForTest();
    savedConfig = PhaseBConfig.current;
    PhaseBConfig.current = const PhaseBConfig();
    savedBriefStore = BriefPrV2.store;
    BriefPrV2.store = InMemoryBriefPrStore();
    savedFlags = RemoteFeatureFlags.current;
    RemoteFeatureFlags.current =
        const RemoteFeatureFlags(reminiscenceV2Enabled: true);
    savedCopy = UsageCopy.current;
  });

  tearDown(() {
    PhaseBConfig.current = savedConfig;
    BriefPrV2.store = savedBriefStore;
    RemoteFeatureFlags.current = savedFlags;
    UsageCopy.current = savedCopy;
    ReminiscenceV2Stores.resetForTest();
    ChatSessionRecorder.resetProcessStateForTest();
  });

  test('the old My Story page is gone and nothing refers to it', () {
    expect(
        File('lib/features/my_story/presentation/pages/my_story_page.dart')
            .existsSync(),
        isFalse);
    expect(Directory('lib/features/my_story/presentation').existsSync(),
        isFalse);
    final self = 'test/selfpage_landing_1020o_test.dart';
    for (final dir in ['lib', 'test', 'test_manual']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart') || f.path.endsWith(self)) {
          continue;
        }
        final src = f.readAsStringSync();
        expect(src.contains('MyStoryPage'), isFalse, reason: f.path);
        expect(src.contains('my_story_page.dart'), isFalse, reason: f.path);
        expect(src.contains('my_story/presentation'), isFalse, reason: f.path);
      }
    }
  });

  for (final arm in _arms) {
    final armTag = arm == ArmAssignment.b ? 'rule' : 'hybrid';

    testWidgets('$armTag: 自己 → 「我嘅人生小篇章」 opens the chapters page',
        (tester) async {
      final run = _Run(arm, AgentGenderVariant.masculine);
      await _boot(tester, run, const SettingsPage());
      expect(find.text('人生回顧'), findsNothing);
      expect(find.text('慢慢嚟，可以跳過唔想講嘅時期。'), findsNothing);
      final entry = find.byKey(const Key('me_life_chapters_entry'));
      expect(entry, findsOneWidget);
      expect(find.descendant(of: entry, matching: find.text('我嘅人生小篇章')),
          findsOneWidget);
      expect(
          find.descendant(
              of: entry, matching: find.text('每個禮拜講完，整理好嘅小文章都喺度。')),
          findsOneWidget);
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(ReminiscenceChaptersPage), findsOneWidget);
      expect(find.text(ReminiscenceV2Copy.chaptersEmpty), findsOneWidget);
      expect(run.llm.calls, isEmpty);
    });

    for (final variant in AgentGenderVariant.values) {
      final tag =
          '$armTag · ${variant == AgentGenderVariant.masculine ? '阿伯' : '阿珍'}';

      testWidgets('$tag: landing — companion bubble, theme lines, picture '
          'tiles', (tester) async {
        final run = _Run(arm, variant)..readyChapter();
        await _boot(tester, run, const ReminiscenceLandingPage());

        // (1) The chosen companion's picture and the bubble.
        final avatar = find.byKey(const Key('reminiscence_landing_avatar'));
        expect(tester.widget<AgentAvatar>(avatar).selectedVariant, variant);
        expect(
            find.descendant(
                of: avatar, matching: _picture(run.bak ? _bakAsset : _janAsset)),
            findsOneWidget);
        expect(
            tester
                .widget<Text>(find.byKey(const Key('reminiscence_landing_intro')))
                .data,
            '我係${run.name}。我哋一共講四個題目，一個禮拜講一個，每次大約十五至二十五分鐘。'
            '冇標準答案，記得幾多講幾多。');
        expect(_anyText('每星期一節'), findsNothing);
        expect(_anyText('一共 4 個主題'), findsNothing);
        if (run.bak) {
          expect(_anyText('珍'), findsNothing);
        } else {
          expect(_anyText('阿伯'), findsNothing);
        }

        // (2) One line per theme, on the card of that theme; no 「第 N 週」.
        expect(_anyText(RegExp(r'第 ?\d+ ?週')), findsNothing);
        for (final t in ReminiscenceTheme.all) {
          final card = find.ancestor(
              of: find.text(t.titleZh), matching: find.byType(Card));
          final line = ReminiscenceV2Copy.themeLines[t.weekIndex]!;
          expect(find.descendant(of: card, matching: find.text(line)),
              findsOneWidget,
              reason: t.titleZh);
          // (3) The picture tile asks for theme_N.png.  While the file is
          // not in the repo, the number tile shows; once Junyu's picture is
          // dropped in, it does not (the test needs no change then).
          expect(
              find.descendant(
                  of: card,
                  matching:
                      _picture('assets/reminiscence/theme_${t.weekIndex}.png')),
              findsOneWidget);
          final number = find.descendant(
              of: card,
              matching:
                  find.byKey(ValueKey('reminiscence_landing_number_${t.weekIndex}')));
          final hasPicture =
              File('assets/reminiscence/theme_${t.weekIndex}.png').existsSync();
          if (hasPicture) {
            expect(number, findsNothing, reason: 'picture ${t.weekIndex}');
          } else {
            expect(number, findsOneWidget, reason: 'fallback ${t.weekIndex}');
            expect(
                find.descendant(
                    of: number, matching: find.text('${t.weekIndex}')),
                findsOneWidget);
          }
        }
        expect(find.text('細個住嘅地方、屋企嘅人'), findsOneWidget);
        expect(find.text('後生嗰陣做過嘅嘢，返工或者打理屋企都算'), findsOneWidget);
        expect(find.text('一路以嚟陪住你嘅朋友'), findsOneWidget);
        expect(find.text('做人嘅道理，想話畀後生一代知嘅嘢'), findsOneWidget);

        // (4) 「第 N 章整理好喇」 and the arrow / tick stay.
        expect(find.byKey(const ValueKey('reminiscence_landing_ready_1')),
            findsOneWidget);
        expect(find.text('第 1 章整理好喇'), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);

        // The 小篇章 button on this page stays (第一节 (2)).
        expect(find.byKey(const Key('reminiscence_chapters_entry')),
            findsOneWidget);

        // 反思傾偈 (moved from the old My Story page): Hybrid only.
        expect(find.text('反思傾偈'), run.rule ? findsNothing : findsOneWidget);
        expect(run.llm.calls, isEmpty);
      });

      testWidgets('$tag: landing scrolled to the end and back (cards rebuilt)',
          (tester) async {
        final run = _Run(arm, variant)..readyChapter();
        // A phone at the largest text: the last cards are built only when
        // scrolled to, the first ones are dropped and built again.
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _boot(tester, run, const ReminiscenceLandingPage());
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        final list = find.byType(Scrollable).first;
        for (var i = 0; i < 2; i++) {
          await tester.drag(list, const Offset(0, -3000));
          await tester.pumpAndSettle();
          await tester.drag(list, const Offset(0, 3000));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('reminiscence_landing_intro')),
            findsOneWidget);
        expect(find.text('細個住嘅地方、屋企嘅人'), findsOneWidget);
      });

      testWidgets('$tag: landing, picture missing → own initial',
          (tester) async {
        final run = _Run(arm, variant, noPictures: true);
        await _boot(tester, run, const ReminiscenceLandingPage());
        final initial = find.descendant(
            of: find.byKey(const Key('reminiscence_landing_avatar')),
            matching: find.byKey(const ValueKey('agent_avatar_initial')));
        expect(initial, findsOneWidget);
        expect(tester.widget<Text>(initial).data, run.bak ? '伯' : '珍');
        if (run.bak) expect(_anyText('珍'), findsNothing);
      });

      testWidgets('$tag: high contrast — landing and 小篇章 readable',
          (tester) async {
        final run = _Run(arm, variant, highContrast: true)..readyChapter();
        await _boot(tester, run, const ReminiscenceLandingPage());
        _expectReadable(tester, 4.5, 'landing (high contrast)');
        run.navKey.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => const ReminiscenceChaptersPage()));
        await tester.pumpAndSettle();
        expect(find.text('第 1 章：童年同屋企'), findsOneWidget);
        expect(find.text('細個住喺深水埗。'), findsOneWidget);
        _expectReadable(tester, 4.5, '小篇章 (high contrast)');
        run.navKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(run.llm.calls, isEmpty);
      });
    }

    testWidgets('$armTag: normal theme — landing and 小篇章 readable',
        (tester) async {
      final run = _Run(arm, AgentGenderVariant.masculine)..readyChapter();
      await _boot(tester, run, const ReminiscenceLandingPage());
      _expectReadable(tester, 3.0, 'landing');
      run.navKey.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const ReminiscenceChaptersPage()));
      await tester.pumpAndSettle();
      _expectReadable(tester, 3.0, '小篇章');
    });
  }

  testWidgets('usage_copy override replaces the whole bubble; {name} filled',
      (tester) async {
    UsageCopy.current = UsageCopy.fromMap(const {
      'reminiscence_landing_intro_zh': '我係{name}，我哋講{weeks}個題目。',
    });
    final run = _Run(_arms.first, AgentGenderVariant.masculine);
    await _boot(tester, run, const ReminiscenceLandingPage());
    expect(
        tester
            .widget<Text>(find.byKey(const Key('reminiscence_landing_intro')))
            .data,
        '我係阿伯，我哋講4個題目。');
    expect(ReminiscenceLandingPage.introText(AgentGenderVariant.feminine,
            isEn: false),
        '我係阿珍，我哋講4個題目。');
  });

  testWidgets('hybrid: 反思傾偈 on the landing opens the reflective chat',
      (tester) async {
    final run = _Run(ArmAssignment.a, AgentGenderVariant.masculine);
    await _boot(tester, run, const ReminiscenceLandingPage());
    final entry =
        find.byKey(const Key('reminiscence_landing_reflective_chat'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(ReflectiveDialoguePage), findsOneWidget);
  }, skip: !_hybridTestable);
}
