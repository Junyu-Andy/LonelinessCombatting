// 1020c 小讀本 — the switch, the manifest, what the App does to the HTML,
// the link policy, the usage events, the 讀少少 list and the reader page.
//
// The WebView is a platform view and does not render in `flutter test`,
// so the pages get a fake [ReaderSurface] (the real one is checked on
// phones, 1020c §4).  The arm split runs in the two Phase B builds:
//   flutter test --dart-define=PHASE_B=true test/reader_test.dart
//     → Hybrid profile: 「問下通通」 shown; rule profile: no button, no LLM
//   flutter test --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
//     test/reader_test.dart                → rule arm only
// In the default (Phase A) build everyone is Hybrid.
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
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
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/usage/usage_event_recorder.dart';
import 'package:app_demo/core/usage/usage_events_scope.dart';
import 'package:app_demo/features/action_loop/presentation/pages/action_loop_arm_a_page.dart';
import 'package:app_demo/features/action_loop/presentation/pages/action_loop_arm_b_page.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/curious_companion/presentation/pages/tung_tung_page.dart';
import 'package:app_demo/features/education/data/education_library.dart';
import 'package:app_demo/features/education/data/reader_html.dart';
import 'package:app_demo/features/education/data/reader_qa_prompt.dart';
import 'package:app_demo/features/education/data/reader_read_marks.dart';
import 'package:app_demo/features/education/data/reader_test_unit.dart';
import 'package:app_demo/features/education/data/reader_unit.dart';
import 'package:app_demo/features/education/presentation/pages/education_library_page.dart';
import 'package:app_demo/features/education/presentation/pages/reader_page.dart';
import 'package:app_demo/features/education/presentation/reader/reader_surface.dart';
import 'package:app_demo/features/social_suggestions/presentation/pages/social_suggestions_page.dart';
import 'package:app_demo/features/thought_exercise/presentation/thought_exercise_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _forcedB = String.fromEnvironment('FORCE_ARM') == 'B';

/// The arm a profile with [arm] actually gets in this build.
bool _isHybrid(ArmAssignment arm) =>
    !FeatureFlags.phaseB || (!_forcedB && arm == ArmAssignment.a);

/// Counts every LLM call and fails it: the rule arm must never get here.
class ThrowingLlmClient implements LlmClient {
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
    throw StateError('the rule arm reached the LLM ($moduleId)');
  }
}

/// Stands in for the WebView: shows a line of text and keeps the request
/// so a test can play the page's section messages and CTA taps.
class FakeReaderSurface extends ReaderSurface {
  ReaderSurfaceRequest? last;
  int builds = 0;

  @override
  Widget build(BuildContext context, ReaderSurfaceRequest request) {
    last = request;
    builds++;
    return const Center(
      key: Key('fake_reader_view'),
      child: Text('（網頁內容：真機上由 WebView 顯示）'),
    );
  }
}

class FakeReaderSource extends ReaderContentSource {
  FakeReaderSource(this.list,
      {this.htmlById = const {}, this.textById = const {}});

  final List<ReaderUnit> list;
  final Map<String, String> htmlById;
  final Map<String, String> textById;
  int textReads = 0;

  @override
  Future<List<ReaderUnit>> units() async => list;

  @override
  Future<String> html(String id) async =>
      htmlById[id] ?? (throw StateError('no html for $id'));

  @override
  Future<String> text(String id) async {
    textReads++;
    return textById[id] ?? (throw StateError('no txt for $id'));
  }
}

const _unit2 = ReaderUnit(
    id: 'u2_why_it_matters', titleZh: '點解孤單要理', minutes: 10, order: 2);

const _unit2Html = '<html><head><style>body{font-size:calc(18px*var(--fs))}'
    '</style></head><body><section data-section="s1">一</section>'
    '<section data-section="s2">二</section></body></html>';

FakeReaderSource _source() => FakeReaderSource(
      [readerTestUnit, _unit2],
      htmlById: {readerTestUnit.id: readerTestUnitHtml, _unit2.id: _unit2Html},
      textById: {readerTestUnit.id: readerTestUnitText, _unit2.id: '二號文字'},
    );

UserProfile _profile(ArmAssignment arm) => UserProfile(
      uid: 'u1',
      email: 'e',
      displayName: '陳婆婆',
      arm: arm,
      cohort: 'phase_b',
    );

/// Recorder with the switch on and the enrolled profile set.
({UsageEventRecorder recorder, InMemoryUsageEventSink sink}) _recorder(
    UserProfile profile) {
  final sink = InMemoryUsageEventSink();
  final rec = UsageEventRecorder(
    sink: sink,
    enabled: () => true,
    platform: 'android',
    appVersion: '1.0.0',
    buildNumber: '3',
  )..setProfile(profile);
  return (recorder: rec, sink: sink);
}

Widget _harness(
  Widget home, {
  required UserProfile profile,
  required LlmClient client,
  UsageEventRecorder? recorder,
  double textScale = 1.0,
}) {
  final llm = LlmGateway(client: client);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final memory = MemoryStore(available: false);
  final state = DistressState();
  Widget app = MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: recorder == null
          ? child!
          : UsageEventsScope(recorder: recorder, child: child!),
    ),
    home: home,
  );
  return AppSettingsScope(
    settings: AppSettings(locale: const Locale('zh'), profile: profile),
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
          child: app,
        ),
      ),
    ),
  );
}

List<Map<String, Object?>> _rows(InMemoryUsageEventSink sink) => [
      for (final e in sink.events)
        {for (final kv in e.toMap().entries) kv.key: kv.value}
          ..remove('clientAt'),
    ];

Future<void> _pumpFor(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Android back key / iPhone back gesture: the navigator's maybePop.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _pumpFor(tester);
}

/// Close whatever page is on top (a CTA page may ask before leaving).
Future<void> _popTop(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).last).pop();
  await _pumpFor(tester);
}

void main() {
  setUp(() {
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
  });
  tearDown(() {
    RemoteFeatureFlags.current = const RemoteFeatureFlags();
  });

  group('switch', () {
    test('htmlReadersEnabled: default off, only literal true turns it on', () {
      expect(const RemoteFeatureFlags().htmlReadersEnabled, isFalse);
      expect(RemoteFeatureFlags.fromMap({}).htmlReadersEnabled, isFalse);
      for (final v in ['true', 1, 'yes', null, false]) {
        expect(RemoteFeatureFlags.fromMap({'htmlReadersEnabled': v})
            .htmlReadersEnabled, isFalse, reason: '$v');
      }
      expect(RemoteFeatureFlags.fromMap({'htmlReadersEnabled': true})
          .htmlReadersEnabled, isTrue);
    });
  });

  group('manifest', () {
    test('the committed manifest.json is an empty list', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final units = await const AssetReaderContentSource().units();
      expect(units, isEmpty,
          reason: kReaderTestUnit ? 'READER_TEST_UNIT build' : '[]');
    }, skip: kReaderTestUnit);

    test('parse: order, skipped bad entries and repeated ids, bad JSON', () {
      final units = parseReaderManifest('''[
        {"id": "u3_later", "titleZh": "三", "minutes": 5, "order": 3},
        {"id": "u2_why_it_matters", "titleZh": "點解孤單要理", "minutes": 10, "order": 2},
        {"id": "U4 Bad", "titleZh": "x", "minutes": 5, "order": 4},
        {"id": "u5", "titleZh": " ", "minutes": 5, "order": 5},
        {"id": "u6", "titleZh": "六", "minutes": 0, "order": 6},
        {"id": "u7", "titleZh": "七", "minutes": 5, "order": "7"},
        {"id": "u3_later", "titleZh": "重複", "minutes": 5, "order": 1},
        "not an object"
      ]''');
      expect(units.map((u) => u.id), ['u2_why_it_matters', 'u3_later']);
      expect(units.first.titleZh, '點解孤單要理');
      expect(units.first.minutes, 10);
      expect(parseReaderManifest('not json'), isEmpty);
      expect(parseReaderManifest('{}'), isEmpty);
      expect(parseReaderManifest('[]'), isEmpty);
    });

    test('the placeholder test unit is only in a READER_TEST_UNIT build', () {
      // Normal builds and CI: the constant is false, so every reference to
      // the test unit is dead code and the AOT build drops it.
      expect(kReaderTestUnit, const bool.fromEnvironment('READER_TEST_UNIT'));
      expect(readerTestUnitHtml, contains('測試'));
      expect(readerTestUnitText, contains('測試'));
      expect(readerSectionIds(readerTestUnitHtml),
          {'s1_intro', 's2_middle', 's3_actions'});
      expect(readerTestUnitHtml, contains('var(--fs'));
      for (final c in ReaderCta.values) {
        expect(readerTestUnitHtml, contains('peizhu://cta/${c.code}'));
      }
    });
  });

  group('what the App does to the HTML', () {
    test('CSP right after <head>; viewport, --fs and styles before </head>; '
        'section script before </body>', () {
      final out = prepareReaderHtml(
          '<html><head><title>t</title><style>p{}</style></head>'
          '<body><p>x</p></body></html>',
          fontScale: 1.18);
      expect(out, startsWith('<html><head><meta charset="utf-8">'
          '<meta http-equiv="Content-Security-Policy" content="$kReaderCsp">'
          '<title>'));
      final headEnd = out.indexOf('</head>');
      final vp = out.indexOf('name="viewport"');
      final fs = out.indexOf(':root{--fs:1.18}');
      expect(vp, greaterThan(out.indexOf('<style>p{}</style>')));
      expect(vp, lessThan(headEnd));
      expect(fs, greaterThan(vp));
      expect(fs, lessThan(headEnd));
      expect(out, contains('user-scalable=no'));
      expect(out, contains('maximum-scale=1'));
      final script = out.indexOf('<script>');
      expect(script, greaterThan(out.indexOf('<p>x</p>')));
      expect(script, lessThan(out.indexOf('</body>')));
      expect(out, contains('window.$kReaderJsChannel'));
    });

    test('the CSP refuses everything external', () {
      for (final d in [
        "default-src 'none'",
        "connect-src 'none'",
        "frame-src 'none'",
        "form-action 'none'",
        "base-uri 'none'",
        'img-src data:',
      ]) {
        expect(kReaderCsp, contains(d));
      }
      expect(kReaderCsp, isNot(contains('http')));
      expect(kReaderCsp, isNot(contains('*')));
    });

    test('a file without <head> or </body> still gets everything', () {
      final bare = prepareReaderHtml('<p data-section="a">x</p>',
          fontScale: 1.3);
      expect(bare, startsWith('<head><meta charset="utf-8"><meta '
          'http-equiv="Content-Security-Policy"'));
      expect(bare, contains(':root{--fs:1.30}'));
      expect(bare, endsWith('</script>'));
      final withHtml = prepareReaderHtml('<HTML lang="zh"><BODY>x</BODY></HTML>',
          fontScale: 1.06);
      expect(withHtml, startsWith('<HTML lang="zh"><head><meta charset'));
      expect(withHtml, contains('--fs:1.06'));
      expect(withHtml.indexOf('<script>'), lessThan(withHtml.indexOf('</BODY>')));
      // <header> is not <head>.
      final header = prepareReaderHtml('<header>x</header>', fontScale: 1);
      expect(header, startsWith('<head>'));
    });

    test('--fs: two decimals, out-of-range values clamped', () {
      expect(readerFontScaleCss(1.0), '1.00');
      expect(readerFontScaleCss(1.24), '1.24');
      expect(readerFontScaleCss(9), '3.00');
      expect(readerFontScaleCss(double.nan), '1.00');
    });

    test('section ids: only well-formed data-section values', () {
      expect(
          readerSectionIds('<a data-section="s1"><b data-section=\'s2-b\'>'
              '<i data-section="第三節"><u data-section="S4"><p data-section="">'),
          {'s1', 's2-b'});
    });
  });

  group('links (1020c §1(3)(4))', () {
    ReaderNavDecision d(String url,
            {bool main = true, bool initial = false}) =>
        decideReaderNavigation(url,
            isMainFrame: main, initialLoadPending: initial);

    test('the three CTAs', () {
      expect(d('peizhu://cta/small_action').cta, ReaderCta.smallAction);
      expect(d('peizhu://cta/plan').cta, ReaderCta.plan);
      expect(d('PEIZHU://CTA/thought').cta, ReaderCta.thought);
      expect(d('peizhu://cta/plan/').action, ReaderNavAction.cta);
      expect(d('peizhu://cta/plan', main: false).action, ReaderNavAction.cta);
    });

    test('only the first load passes; everything else is blocked', () {
      expect(d('about:blank', initial: true).action, ReaderNavAction.allow);
      expect(d('data:text/html,x', initial: true).action,
          ReaderNavAction.allow);
      expect(d('about:blank').action, ReaderNavAction.block);
      expect(d('about:blank', main: false, initial: true).action,
          ReaderNavAction.block);
      for (final url in [
        'https://www.example.com/',
        'http://example.com',
        '//example.com',
        'tel:23456789',
        'mailto:a@b.c',
        'intent://x#Intent;end',
        'file:///etc/hosts',
        'about:blank#s2',
        'peizhu://cta/call',
        'peizhu://cta/plan/extra',
        'peizhu://home',
        'javascript:alert(1)',
      ]) {
        expect(d(url, initial: true).action, ReaderNavAction.block,
            reason: url);
      }
    });
  });

  group('usage events (1020c §1(5))', () {
    late InMemoryUsageEventSink sink;
    late bool on;
    late UsageEventRecorder rec;

    setUp(() {
      sink = InMemoryUsageEventSink();
      on = true;
      rec = UsageEventRecorder(
        sink: sink,
        enabled: () => on,
        clock: () => DateTime(2026, 10, 21, 10),
        platform: 'ios',
        appVersion: '1.0.0',
        buildNumber: '4',
      );
    });

    test('same switch and enrolment check as foreground / background', () {
      rec.setProfile(const UserProfile(
          uid: 'u1', email: 'e', displayName: 'x', arm: ArmAssignment.a));
      expect(rec.recordReader(UsageEventType.readerOpen, unitId: 'u1'),
          isFalse);
      rec.setProfile(_profile(ArmAssignment.b));
      on = false;
      expect(rec.recordReader(UsageEventType.readerOpen, unitId: 'u1'),
          isFalse);
      expect(sink.events, isEmpty);
    });

    test('the four rows: ids, a CTA code, seconds — exactly these fields', () {
      rec.setProfile(_profile(ArmAssignment.b));
      rec.recordReader(UsageEventType.readerOpen, unitId: 'u2');
      rec.recordReader(UsageEventType.readerSection,
          unitId: 'u2', sectionId: 's1_intro');
      rec.recordReader(UsageEventType.readerCta, unitId: 'u2', cta: 'plan');
      rec.recordReader(UsageEventType.readerClose, unitId: 'u2', seconds: 95);
      final base = {
        'appVersion': '1.0.0',
        'buildNumber': '4',
        'platform': 'ios',
        'schemaVersion': 1,
      };
      expect(_rows(sink), [
        {'type': 'reader_open', ...base, 'unitId': 'u2'},
        {'type': 'reader_section', ...base, 'unitId': 'u2',
          'sectionId': 's1_intro'},
        {'type': 'reader_cta', ...base, 'unitId': 'u2', 'cta': 'plan'},
        {'type': 'reader_close', ...base, 'unitId': 'u2', 'seconds': 95},
      ]);
    });

    test('anything that could carry text is dropped', () {
      rec.setProfile(_profile(ArmAssignment.a));
      expect(rec.recordReader(UsageEventType.readerOpen, unitId: '點解孤單'),
          isFalse);
      expect(rec.recordReader(UsageEventType.readerSection,
          unitId: 'u2', sectionId: '我讀到呢度'), isFalse);
      expect(rec.recordReader(UsageEventType.readerSection, unitId: 'u2'),
          isFalse);
      expect(rec.recordReader(UsageEventType.readerCta,
          unitId: 'u2', cta: 'call_hotline'), isFalse);
      expect(rec.recordReader(UsageEventType.readerClose, unitId: 'u2'),
          isFalse);
      expect(rec.recordReader(UsageEventType.foreground, unitId: 'u2'),
          isFalse);
      expect(sink.events, isEmpty);
      // Extra fields on the wrong type are not written.
      rec.recordReader(UsageEventType.readerOpen,
          unitId: 'u2', sectionId: 's1', cta: 'plan', seconds: 3);
      expect(_rows(sink).single.keys, isNot(contains('sectionId')));
      expect(_rows(sink).single.keys, isNot(contains('seconds')));
      // A phone left on: seconds clamped.
      rec.recordReader(UsageEventType.readerClose,
          unitId: 'u2', seconds: 999999);
      expect(_rows(sink).last['seconds'], kReaderMaxSeconds);
    });

    test('foreground / background rows are unchanged', () {
      rec.setProfile(_profile(ArmAssignment.a));
      rec.onForeground();
      rec.onBackground();
      expect(_rows(sink).map((r) => (r.keys.toList()..sort()).join(',')),
          everyElement('appVersion,buildNumber,platform,schemaVersion,type'));
      expect(sink.events, hasLength(2));
    });
  });

  group('讀少少 list (1020c §2)', () {
    Future<void> pumpList(WidgetTester tester,
        {required ReaderContentSource source,
        ReaderReadMarks? marks,
        FakeReaderSurface? surface}) async {
      await tester.pumpWidget(_harness(
        EducationLibraryPage(
          readerSource: source,
          readerSurface: surface ?? FakeReaderSurface(),
          readMarks: marks ?? InMemoryReaderReadMarks(),
        ),
        profile: _profile(ArmAssignment.a),
        client: ThrowingLlmClient(),
      ));
      await _pumpFor(tester);
    }

    Future<void> expectArticlesAsBefore(WidgetTester tester) async {
      expect(find.text('每篇短短，平實啲講。睇啱嘅，唔啱就過。'), findsOneWidget);
      final first = EducationLibrary.articles.firstWhere((a) => a.enabled);
      expect(find.text(first.titleZh), findsOneWidget);
    }

    testWidgets('switch off: no 小讀本 section, the source is not even read',
        (tester) async {
      final source = _source();
      var asked = false;
      await pumpList(tester,
          source: _SpySource(source, onUnits: () => asked = true));
      expect(find.byKey(const Key('readers_section')), findsNothing);
      expect(find.text('小讀本'), findsNothing);
      expect(asked, isFalse);
      await expectArticlesAsBefore(tester);
    });

    testWidgets('switch on, no packaged unit: still hidden', (tester) async {
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(htmlReadersEnabled: true);
      await pumpList(tester, source: FakeReaderSource(const []));
      expect(find.byKey(const Key('readers_section')), findsNothing);
      await expectArticlesAsBefore(tester);
    });

    testWidgets('switch on: section on top, units by order, minutes, '
        'ticks for units read on this phone', (tester) async {
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(htmlReadersEnabled: true);
      await pumpList(tester,
          source: _source(),
          marks: InMemoryReaderReadMarks({_unit2.id}));
      expect(find.text('小讀本'), findsOneWidget);
      expect(find.text('每隔幾日睇一篇就得，唔使一次睇晒。'), findsOneWidget);
      expect(find.text('大約 3 分鐘'), findsOneWidget);
      expect(find.text('大約 10 分鐘'), findsOneWidget);
      final y1 = tester.getTopLeft(find.text(readerTestUnit.titleZh)).dy;
      final y2 = tester.getTopLeft(find.text(_unit2.titleZh)).dy;
      expect(y1, lessThan(y2), reason: 'order 0 before order 2');
      expect(find.byKey(Key('reader_read_${_unit2.id}')), findsOneWidget);
      expect(find.byKey(Key('reader_read_${readerTestUnit.id}')), findsNothing);
      // The articles still follow, below the section.
      final articles =
          tester.getTopLeft(find.text('每篇短短，平實啲講。睇啱嘅，唔啱就過。')).dy;
      expect(articles, greaterThan(y2));
    });

    testWidgets('open a unit, come back: the tick appears (set on close)',
        (tester) async {
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(htmlReadersEnabled: true);
      final marks = InMemoryReaderReadMarks();
      final surface = FakeReaderSurface();
      await pumpList(tester,
          source: _source(), marks: marks, surface: surface);
      await tester.tap(find.text(readerTestUnit.titleZh));
      await _pumpFor(tester);
      expect(find.byType(ReaderPage), findsOneWidget);
      expect(find.byKey(const Key('fake_reader_view')), findsOneWidget);
      // The app bar's back arrow.
      await tester.tap(find.byType(BackButton));
      await _pumpFor(tester);
      expect(find.byType(ReaderPage), findsNothing);
      expect(marks.ids, {readerTestUnit.id});
      expect(find.byKey(Key('reader_read_${readerTestUnit.id}')),
          findsOneWidget);
    });
  });

  group('reader page', () {
    Future<
        ({
          FakeReaderSurface surface,
          InMemoryUsageEventSink sink,
          ThrowingLlmClient llm,
          FakeReaderSource source,
          InMemoryReaderReadMarks marks,
        })> openReader(WidgetTester tester, ArmAssignment arm,
        {double textScale = 1.0, ReaderUnit? unit}) async {
      final profile = _profile(arm);
      final r = _recorder(profile);
      final surface = FakeReaderSurface();
      final llm = ThrowingLlmClient();
      final source = _source();
      final marks = InMemoryReaderReadMarks();
      await tester.pumpWidget(_harness(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReaderPage(
                      unit: unit ?? readerTestUnit,
                      source: source,
                      surface: surface,
                      readMarks: marks,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        profile: profile,
        client: llm,
        recorder: r.recorder,
        textScale: textScale,
      ));
      await tester.tap(find.text('open'));
      await _pumpFor(tester);
      return (
        surface: surface,
        sink: r.sink,
        llm: llm,
        source: source,
        marks: marks,
      );
    }

    testWidgets('loads the asset HTML with the CSP and --fs = the App scale',
        (tester) async {
      final h = await openReader(tester, ArmAssignment.a, textScale: 1.3);
      final html = h.surface.last!.html;
      expect(html, contains('Content-Security-Policy'));
      expect(html, contains(':root{--fs:1.30}'));
      expect(html, contains('測試小讀本'));
      expect(find.text(readerTestUnit.titleZh), findsOneWidget); // app bar
    });

    testWidgets('a missing file shows a short line, not a crash',
        (tester) async {
      await openReader(tester, ArmAssignment.a,
          unit: const ReaderUnit(
              id: 'u9_missing', titleZh: '冇檔', minutes: 1, order: 9));
      expect(find.text('呢篇暫時打唔開。'), findsOneWidget);
    });

    testWidgets('events: open, each known section once, close with seconds; '
        'nothing that is not an id', (tester) async {
      final h = await openReader(tester, ArmAssignment.b);
      final req = h.surface.last!;
      req.onSection('s1_intro');
      req.onSection('s1_intro'); // again → not recorded twice
      req.onSection(' s2_middle ');
      req.onSection('我讀到第三節'); // text → dropped
      req.onSection('s9_not_in_file'); // not in this file → dropped
      await tester.pump(const Duration(seconds: 2));
      await _systemBack(tester); // Android back → the 讀少少 list
      expect(find.byType(ReaderPage), findsNothing);
      final rows = _rows(h.sink);
      expect(rows.map((r) => r['type']),
          ['reader_open', 'reader_section', 'reader_section', 'reader_close']);
      expect(rows[1]['sectionId'], 's1_intro');
      expect(rows[2]['sectionId'], 's2_middle');
      expect(rows.every((r) => r['unitId'] == readerTestUnit.id), isTrue);
      expect(rows.last['seconds'], isA<int>());
      for (final r in rows) {
        for (final v in r.values) {
          if (v is String) {
            expect(RegExp(r'^[a-z0-9_.-]+$').hasMatch(v), isTrue,
                reason: 'no text in a usage row: $v');
          }
        }
      }
      expect(h.marks.ids, {readerTestUnit.id});
    });

    testWidgets('CTA thought → 望一望心入面; back returns to the reader',
        (tester) async {
      final h = await openReader(tester, ArmAssignment.a);
      h.surface.last!.onCta(ReaderCta.thought);
      await _pumpFor(tester);
      expect(find.byType(ThoughtExercisePage), findsOneWidget);
      expect(_rows(h.sink).last,
          containsPair('cta', 'thought'));
      await _popTop(tester);
      expect(find.byType(ThoughtExercisePage), findsNothing);
      expect(find.byType(ReaderPage), findsOneWidget);
    });

    testWidgets('CTA plan → this arm\'s planner, new plan', (tester) async {
      const arm = _forcedB ? ArmAssignment.b : ArmAssignment.a;
      final h = await openReader(tester, arm);
      h.surface.last!.onCta(ReaderCta.plan);
      await _pumpFor(tester);
      if (_isHybrid(arm)) {
        expect(find.byType(ActionLoopArmAPage), findsOneWidget);
        expect(tester.widget<ActionLoopArmAPage>(
            find.byType(ActionLoopArmAPage)).seedAction, isNull);
      } else {
        expect(find.byType(ActionLoopArmBPage), findsOneWidget);
        expect(tester.widget<ActionLoopArmBPage>(
            find.byType(ActionLoopArmBPage)).seedAction, isNull);
      }
      expect(_rows(h.sink).last, containsPair('type', 'reader_cta'));
      expect(_rows(h.sink).last, containsPair('cta', 'plan'));
    });

    testWidgets('Hybrid: 「問下通通」 opens 通通 article Q&A on <id>.txt',
        (tester) async {
      final h = await openReader(tester, ArmAssignment.a);
      expect(find.byKey(ReaderPage.askKey), findsOneWidget);
      expect(find.text('問下通通'), findsOneWidget);
      await tester.tap(find.byKey(ReaderPage.askKey));
      await _pumpFor(tester);
      final page = tester.widget<TungTungPage>(find.byType(TungTungPage));
      expect(page.articleContext, readerTestUnitText);
      expect(page.articleTitle, readerTestUnit.titleZh);
      expect(page.articleId, 'reader_${readerTestUnit.id}');
      expect(page.articleContextHeader, kReaderQaHeaderZh);
      expect(kReaderQaHeaderZh, contains('電腦程式夥伴'));
      expect(kReaderQaHeaderZh, isNot(contains('AI 機械人')));
      expect(h.source.textReads, 1);
    }, skip: !_isHybrid(ArmAssignment.a));

    testWidgets('rule arm: no 「問下通通」 and no LLM anywhere — open, '
        'sections, the three CTAs, close', (tester) async {
      final h = await openReader(tester, ArmAssignment.b);
      expect(find.byKey(ReaderPage.askKey), findsNothing);
      expect(find.text('問下通通'), findsNothing);
      final req = h.surface.last!;
      req.onSection('s1_intro');
      for (final cta in ReaderCta.values) {
        req.onCta(cta);
        await _pumpFor(tester);
        await _popTop(tester);
      }
      expect(find.byType(ReaderPage), findsOneWidget);
      await _systemBack(tester);
      expect(find.byType(ReaderPage), findsNothing);
      expect(h.llm.calls, 0, reason: 'the rule arm never calls the LLM');
      expect(h.source.textReads, 0, reason: 'the .txt is only for Hybrid');
      expect(_rows(h.sink).map((r) => r['type']), [
        'reader_open',
        'reader_section',
        'reader_cta',
        'reader_cta',
        'reader_cta',
        'reader_close',
      ]);
    }, skip: _isHybrid(ArmAssignment.b));

    testWidgets('both arms: same page apart from 「問下通通」', (tester) async {
      // Hybrid and rule pages in this build, one after the other: the only
      // difference allowed is the ask bar (registry C08).
      List<String?> texts() => [
            for (final e in find.byType(Text).evaluate())
              (e.widget as Text).data,
          ];
      final a = await openReader(tester, ArmAssignment.a);
      final textsA = texts();
      final askA = find.byKey(ReaderPage.askKey).evaluate().length;
      final htmlA = a.surface.last!.html;
      await tester.pumpWidget(const SizedBox());
      final b = await openReader(tester, ArmAssignment.b);
      final textsB = texts();
      final askB = find.byKey(ReaderPage.askKey).evaluate().length;
      expect(b.surface.last!.html, htmlA, reason: 'same content both arms');
      expect(askA, _isHybrid(ArmAssignment.a) ? 1 : 0);
      expect(askB, _isHybrid(ArmAssignment.b) ? 1 : 0);
      List<String?> withoutAsk(List<String?> t) =>
          t.where((x) => x != '問下通通').toList();
      expect(withoutAsk(textsB), withoutAsk(textsA));
    });

    testWidgets('small_action CTA (rule arm) → 今日嘅小邀請, static pool',
        (tester) async {
      final h = await openReader(tester, ArmAssignment.b);
      h.surface.last!.onCta(ReaderCta.smallAction);
      await _pumpFor(tester);
      expect(find.byType(SocialSuggestionsPage), findsOneWidget);
      expect(h.llm.calls, 0);
    }, skip: _isHybrid(ArmAssignment.b));
  });
}

/// Records whether the list page asked for the units.
class _SpySource extends ReaderContentSource {
  _SpySource(this.inner, {required this.onUnits});

  final ReaderContentSource inner;
  final VoidCallback onUnits;

  @override
  Future<List<ReaderUnit>> units() {
    onUnits();
    return inner.units();
  }

  @override
  Future<String> html(String id) => inner.html(id);

  @override
  Future<String> text(String id) => inner.text(id);
}
