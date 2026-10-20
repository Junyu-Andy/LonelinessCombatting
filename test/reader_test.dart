// 1020c 小讀本 — the switch, the manifest, what the App does to the HTML,
// the link policy, the usage events, the 讀少少 list and the reader page.
//
// 1021: the 14 packaged units (manifest parts, icons), the native top bar
// (peizhuReader.back(), the title from peizhu:view, the 「?」 Hybrid only),
// the read state (readIds / setRead), chat_siu_yan, 「讀下一篇」, and the
// hard rule that every peizhu:// link in the packaged files is handled.
//
// The WebView is a platform view and does not render in `flutter test`,
// so the pages get a fake [ReaderSurface] that plays the page's
// `window.peizhuReader` (the real one is checked on phones).  The arm
// split runs in the two Phase B builds:
//   flutter test --dart-define=PHASE_B=true test/reader_test.dart
//     → Hybrid profile: the 「?」 shown; rule profile: no button, no LLM
//   flutter test --dart-define=PHASE_B=true --dart-define=FORCE_ARM=B \
//     test/reader_test.dart                → rule arm only
// In the default (Phase A) build everyone is Hybrid.
import 'dart:async';
import 'dart:convert';

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
import 'package:app_demo/features/context/presentation/pages/check_in_page.dart';
import 'package:app_demo/features/curious_companion/presentation/pages/tung_tung_page.dart';
import 'package:app_demo/features/education/data/education_library.dart';
import 'package:app_demo/features/education/data/reader_html.dart';
import 'package:app_demo/features/education/data/reader_qa_prompt.dart';
import 'package:app_demo/features/education/data/reader_read_marks.dart';
import 'package:app_demo/features/education/data/reader_test_unit.dart';
import 'package:app_demo/features/education/data/reader_unit.dart';
import 'package:app_demo/features/education/presentation/pages/education_library_page.dart';
import 'package:app_demo/features/education/presentation/pages/reader_page.dart';
import 'package:app_demo/features/education/presentation/reader/reader_icons.dart';
import 'package:app_demo/features/education/presentation/reader/reader_surface.dart';
import 'package:app_demo/features/me/presentation/pages/me_page.dart';
import 'package:app_demo/features/me/presentation/widgets/me_tool_card.dart';
import 'package:app_demo/features/social_suggestions/presentation/pages/social_suggestions_page.dart';
import 'package:app_demo/features/thought_exercise/presentation/thought_exercise_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Stands in for the WebView: shows a line of text, keeps the request and
/// plays the page.  It answers the App's calls into `window.peizhuReader`
/// the way the 14 real units do (their script: `back()` goes from a
/// section to the contents and returns true, at the contents returns
/// false; leaving a section marks it read; `readIds()`), and lets a test
/// play what the page posts (section reached, `peizhu:view`).
class FakeReaderSurface extends ReaderSurface {
  ReaderSurfaceRequest? last;
  int builds = 0;
  String? _html;

  /// The page: 'toc' or the section shown; what it counts as read.
  String view = 'toc';
  Set<String> pageRead = {};
  List<String> sections = const ['s1', 's2', 's3'];

  /// False: a page without `window.peizhuReader` (an older unit).
  bool hasReaderApi = true;
  int backCalls = 0;
  int readIdsCalls = 0;

  @override
  Widget build(BuildContext context, ReaderSurfaceRequest request) {
    if (request.html != _html) {
      // A new page (first load or 「讀下一篇」): it starts at its contents
      // with what the App handed it through setRead.
      _html = request.html;
      view = 'toc';
      pageRead = setReadIn(request.html).toSet();
    }
    last = request;
    builds++;
    request.bridge.attach(_eval);
    return const Center(
      key: Key('fake_reader_view'),
      child: Text('（網頁內容：真機上由 WebView 顯示）'),
    );
  }

  /// The ids the App's setRead script hands the page, or none.
  static List<String> setReadIn(String html) {
    final m = RegExp(r'r\.setRead\(ids\);[\s\S]*?\}\)\((\[[^\]]*\])\);')
        .firstMatch(html);
    if (m == null) return const [];
    return (jsonDecode(m.group(1)!) as List).cast<String>();
  }

  Future<Object?> _eval(String js) async {
    if (js.contains('r.back()')) {
      backCalls++;
      if (!hasReaderApi) return 'none';
      if (view == 'toc') return 'close';
      go('toc');
      return 'stay';
    }
    if (js.contains('r.readIds()')) {
      readIdsCalls++;
      // Android style: the JSON of the JSON string.
      return jsonEncode(jsonEncode(hasReaderApi ? pageRead.toList() : []));
    }
    return null;
  }

  /// The page's go(id): leaving a section marks it read, then
  /// `peizhu:view` (which the App's script posts with readIds()).
  void go(String id) {
    if (view != 'toc') pageRead.add(view);
    view = id;
    final i = sections.indexOf(id);
    last!.onMessage(jsonEncode({
      'view': id,
      'index': id == 'toc' ? 0 : i + 1,
      'total': sections.length,
      'read': pageRead.toList(),
    }));
    if (id != 'toc') last!.onMessage(id); // the section is on screen
  }

  /// The reader taps a link in the page.
  void tap(String url) {
    final d = decideReaderNavigation(url,
        isMainFrame: true, initialLoadPending: false);
    switch (d.action) {
      case ReaderNavAction.cta:
        last!.onCta(d.cta!);
      case ReaderNavAction.openUnit:
        last!.onOpenUnit(d.unitId!);
      case ReaderNavAction.allow:
      case ReaderNavAction.block:
        break;
    }
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

/// A unit in the 1021 shape: contents + three sections, peizhuReader.
const _unitA = ReaderUnit(
    id: 'u1_alpha', titleZh: '孤單係咩', minutes: 7, order: 1,
    part: 1, partTitleZh: '認識孤單', icon: 'help_outline');
const _unitB = ReaderUnit(
    id: 'u2_beta', titleZh: '由一小步開始', minutes: 6, order: 2,
    part: 2, partTitleZh: '自己同身邊嘅人可以做咩', icon: 'stairs');

String _unitHtml(String title, {String? next}) => '<!doctype html><html>'
    '<head><title>$title</title><style>body{font-size:calc(17px * var(--fs, 1))}'
    '</style></head><body><div id="toc" data-view="toc"><h1>$title</h1>'
    '<a class="cta" href="peizhu://cta/chat_siu_yan">同小欣講吓感受</a>'
    '${next == null ? '' : '<a href="peizhu://reader/open?id=$next">讀下一篇</a>'}'
    '</div>'
    '<section id="s1" data-section="s1" hidden><h2>一</h2></section>'
    '<section id="s2" data-section="s2" hidden><h2>二</h2></section>'
    '<section id="s3" data-section="s3" hidden><h2>三</h2>'
    '<a class="cta" href="peizhu://cta/small_action">今日小行動</a></section>'
    '<script>window.peizhuReader={};</script></body></html>';

FakeReaderSource _source() => FakeReaderSource(
      [readerTestUnit, _unitA, _unitB],
      htmlById: {
        readerTestUnit.id: readerTestUnitHtml,
        _unitA.id: _unitHtml(_unitA.titleZh, next: _unitB.id),
        _unitB.id: _unitHtml(_unitB.titleZh),
      },
      textById: {
        readerTestUnit.id: readerTestUnitText,
        _unitA.id: '孤單係咩：文字',
        _unitB.id: '由一小步開始：文字',
      },
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

/// The units packaged in assets/readers/ (the 14 of readers-1021.zip),
/// with their files — read once, outside the widget tests' fake clock.
class _Packaged {
  _Packaged(this.units, this.html, this.text);
  final List<ReaderUnit> units;
  final Map<String, String> html;
  final Map<String, String> text;

  FakeReaderSource source() =>
      FakeReaderSource(units, htmlById: html, textById: text);
}

Future<_Packaged> _loadPackaged() async {
  const source = AssetReaderContentSource();
  final units = [
    for (final u in await source.units())
      if (u.id != readerTestUnit.id) u,
  ];
  return _Packaged(units, {
    for (final u in units) u.id: await source.html(u.id),
  }, {
    for (final u in units) u.id: await source.text(u.id),
  });
}

/// Every `peizhu://…` in a file (href or anywhere else).
final RegExp _peizhuLink = RegExp(r'''peizhu://[^\s"'<>)\\]*''');

void main() {
  late _Packaged packaged;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    packaged = await _loadPackaged();
  });

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
    test('1021: the packaged manifest — 14 units in three parts, every '
        'icon mapped, .html and .txt load, three sections each', () {
      final units = packaged.units;
      expect(units.map((u) => u.id), [
        'what_is_loneliness', 'how_lonely_am_i', 'different_needs',
        'why_it_matters', 'what_research_says', 'small_steps',
        'talking_with_children', 'thoughts_and_feelings', 'phone_and_video',
        'body_and_sleep', 'after_loss', 'community_places', 'getting_help',
        'what_companions_can_do',
      ]);
      expect(units.map((u) => u.part).toSet(), {1, 2, 3});
      expect(units.where((u) => u.part == 1).length, 4);
      expect(units.where((u) => u.part == 2).length, 7);
      expect(units.where((u) => u.part == 3).length, 3);
      for (final u in units) {
        expect(kReaderIcons.containsKey(u.icon), isTrue, reason: u.id);
        expect(u.partTitleZh, isNotEmpty, reason: u.id);
        expect(readerSectionIds(packaged.html[u.id]!), {'s1', 's2', 's3'},
            reason: u.id);
        expect(packaged.html[u.id], contains('var(--fs'), reason: u.id);
        expect(packaged.text[u.id], isNotEmpty, reason: u.id);
        expect(u.id.startsWith('zz_test'), isFalse,
            reason: 'no placeholder unit in the production assets');
      }
    });

    test('parse: order, skipped bad entries and repeated ids, bad JSON; '
        'part / partTitleZh / icon optional', () {
      final units = parseReaderManifest('''[
        {"id": "u3_later", "titleZh": "三", "minutes": 5, "order": 3},
        {"id": "u2_why_it_matters", "titleZh": "點解孤單要理", "minutes": 10, "order": 2,
         "part": 1, "partTitleZh": " 認識孤單 ", "icon": "favorite_border"},
        {"id": "U4 Bad", "titleZh": "x", "minutes": 5, "order": 4},
        {"id": "u5", "titleZh": " ", "minutes": 5, "order": 5},
        {"id": "u6", "titleZh": "六", "minutes": 0, "order": 6},
        {"id": "u7", "titleZh": "七", "minutes": 5, "order": "7"},
        {"id": "u3_later", "titleZh": "重複", "minutes": 5, "order": 1},
        {"id": "u8", "titleZh": "八", "minutes": 5, "order": 8,
         "part": "2", "partTitleZh": "x", "icon": "Bad Icon"},
        "not an object"
      ]''');
      expect(units.map((u) => u.id), ['u2_why_it_matters', 'u3_later', 'u8']);
      expect(units.first.titleZh, '點解孤單要理');
      expect(units.first.minutes, 10);
      expect(units.first.part, 1);
      expect(units.first.partTitleZh, '認識孤單');
      expect(units.first.icon, 'favorite_border');
      expect(units[1].part, isNull);
      expect(units[2].part, isNull, reason: 'part must be an int');
      expect(units[2].partTitleZh, isNull, reason: 'no part, no heading');
      expect(units[2].icon, isNull);
      expect(parseReaderManifest('not json'), isEmpty);
      expect(parseReaderManifest('{}'), isEmpty);
      expect(parseReaderManifest('[]'), isEmpty);
    });

    test('<id>.explain.json is packaged but not read: a bundle holding one '
        'still lists and opens the unit', () async {
      final bundle = _MapBundle({
        'assets/readers/manifest.json': jsonEncode([
          {'id': 'u1', 'titleZh': '一', 'minutes': 3, 'order': 1},
        ]),
        'assets/readers/u1.html': _unitHtml('一'),
        'assets/readers/u1.txt': '一',
        'assets/readers/u1.explain.json': '{"cards": []}',
      });
      final source = AssetReaderContentSource(bundle);
      expect((await source.units()).map((u) => u.id),
          [if (kReaderTestUnit) readerTestUnit.id, 'u1']);
      expect(await source.html('u1'), contains('data-section'));
      expect(await source.text('u1'), '一');
      expect(bundle.asked.where((k) => k.endsWith('.explain.json')), isEmpty);
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
      for (final c in [ReaderCta.smallAction, ReaderCta.plan, ReaderCta.thought]) {
        expect(readerTestUnitHtml, contains('peizhu://cta/${c.code}'));
      }
    });
  });

  group('what the App does to the HTML', () {
    test('CSP right after <head>, then data-chrome; viewport, --fs and '
        'styles before </head>; the page script before </body>', () {
      final out = prepareReaderHtml(
          '<html><head><title>t</title><style>p{}</style></head>'
          '<body><p>x</p></body></html>',
          fontScale: 1.18);
      expect(out, startsWith('<html><head><meta charset="utf-8">'
          '<meta http-equiv="Content-Security-Policy" content="$kReaderCsp">'
          '<script>${readerChromeScript(ask: false)}</script><title>'));
      final headEnd = out.indexOf('</head>');
      final vp = out.indexOf('name="viewport"');
      final fs = out.indexOf(':root{--fs:1.18}');
      expect(vp, greaterThan(out.indexOf('<style>p{}</style>')));
      expect(vp, lessThan(headEnd));
      expect(fs, greaterThan(vp));
      expect(fs, lessThan(headEnd));
      expect(out, contains('user-scalable=no'));
      expect(out, contains('maximum-scale=1'));
      final script = out.indexOf('<script>', headEnd);
      expect(script, greaterThan(out.indexOf('<p>x</p>')));
      expect(script, lessThan(out.indexOf('</body>')));
      expect(out, contains('window.$kReaderJsChannel'));
      expect(out, isNot(contains('setRead')), reason: 'nothing read yet');
    });

    test('1021 T-R2 (1): data-chrome="app" always; data-ask="on" only when '
        'asked (Hybrid); data-explain never', () {
      final hybrid = prepareReaderHtml(_unitHtml('一'), fontScale: 1, ask: true);
      final rule = prepareReaderHtml(_unitHtml('一'), fontScale: 1);
      expect(hybrid, contains("d.setAttribute('data-chrome','app');"));
      expect(rule, contains("d.setAttribute('data-chrome','app');"));
      expect(hybrid, contains("d.setAttribute('data-ask','on');"));
      expect(rule, isNot(contains('data-ask')));
      expect(hybrid, isNot(contains('data-explain')));
      expect(rule, isNot(contains('data-explain')));
      // The only difference between the arms.
      expect(hybrid.replaceFirst("d.setAttribute('data-ask','on');", ''), rule);
    });

    test("1021 T-R3 (2): setRead(ids) after the page's own script, before "
        "the App's page script; bad ids dropped", () {
      final out = prepareReaderHtml(_unitHtml('一'),
          fontScale: 1, readIds: ['s1', 's3', '我讀過', 'S2']);
      expect(FakeReaderSurface.setReadIn(out), ['s1', 's3']);
      final own = out.indexOf('window.peizhuReader={}');
      final setRead = out.indexOf('r.setRead(ids)');
      final channel = out.indexOf('window.$kReaderJsChannel');
      expect(own, lessThan(setRead));
      expect(setRead, lessThan(channel));
      expect(channel, lessThan(out.lastIndexOf('</body>')));
    });

    test("the page script: hidden sections are skipped; peizhu:view is "
        "posted with readIds(), never the page's title", () {
      expect(kReaderSectionScript, contains('getClientRects'));
      expect(kReaderSectionScript, contains("addEventListener('peizhu:view'"));
      expect(kReaderSectionScript, contains('p.readIds()'));
      expect(kReaderSectionScript, contains('p.current()'));
      expect(kReaderSectionScript, isNot(contains('title')));
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
      expect(withHtml.indexOf('</script>', withHtml.indexOf('<BODY>')),
          lessThan(withHtml.indexOf('</BODY>')));
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

  group('messages from the page', () {
    test('a bare id = section reached; a view object = where and what is '
        'read; text is dropped', () {
      expect((parseReaderMessage(' s2 ') as ReaderSectionReached).sectionId,
          's2');
      expect(parseReaderMessage('我讀到第三節'), isNull);
      final v = parseReaderMessage(jsonEncode({
        'view': 's2', 'index': 2, 'total': 3,
        'read': ['s1', '標題', 'S3', 7], 'title': '唔會用',
      })) as ReaderViewChanged;
      expect(v.sectionId, 's2');
      expect(v.atContents, isFalse);
      expect(v.index, 2);
      expect(v.total, 3);
      expect(v.readIds, {'s1'});
      final toc = parseReaderMessage('{"view":"toc","index":0,"total":3,'
          '"read":["s1","s2","s3"]}') as ReaderViewChanged;
      expect(toc.atContents, isTrue);
      expect(toc.readIds, {'s1', 's2', 's3'});
      for (final bad in ['{"view":"第二節"}', '{"view":3}', '{oops', '[]', '']) {
        expect(parseReaderMessage(bad), isNull, reason: bad);
      }
    });
  });

  group('the bridge to window.peizhuReader', () {
    test("back(): stay / close in either platform's shape; no page, an "
        'error or no answer = close', () async {
      final b = ReaderJsBridge();
      expect(await b.back(), isFalse, reason: 'not attached');
      for (final (answer, stay) in <(Object, bool)>[
        ('stay', true), ('"stay"', true), ('close', false), ('"close"', false),
        ('none', false), (true, false), (1, false),
      ]) {
        b.attach((_) async => answer);
        expect(await b.back(), stay, reason: '$answer');
      }
      b.attach((_) async => throw StateError('no page'));
      expect(await b.back(), isFalse);
      b.attach((_) => Completer<Object?>().future);
      expect(await b.back(timeout: const Duration(milliseconds: 10)), isFalse);
      b.detach();
      expect(b.isAttached, isFalse);
    });

    test('readIds(): Android (JSON of the JSON string) and iPhone (the '
        'string); bad ids dropped; garbage = null', () async {
      final b = ReaderJsBridge();
      expect(await b.readIds(), isNull);
      b.attach((_) async => jsonEncode(jsonEncode(['s1', 's2'])));
      expect(await b.readIds(), {'s1', 's2'});
      b.attach((_) async => jsonEncode(['s3', '第一節']));
      expect(await b.readIds(), {'s3'});
      b.attach((_) async => ['s1']);
      expect(await b.readIds(), {'s1'});
      b.attach((_) async => 'not json');
      expect(await b.readIds(), isNull);
      b.attach((_) async => throw StateError('x'));
      expect(await b.readIds(), isNull);
    });
  });

  group('links (1020c §1(3)(4); 1021 T-R4, T-R4b)', () {
    ReaderNavDecision d(String url,
            {bool main = true, bool initial = false}) =>
        decideReaderNavigation(url,
            isMainFrame: main, initialLoadPending: initial);

    test('the four CTAs', () {
      expect(d('peizhu://cta/small_action').cta, ReaderCta.smallAction);
      expect(d('peizhu://cta/plan').cta, ReaderCta.plan);
      expect(d('PEIZHU://CTA/thought').cta, ReaderCta.thought);
      expect(d('peizhu://cta/chat_siu_yan').cta, ReaderCta.chatSiuYan);
      expect(d('peizhu://cta/plan/').action, ReaderNavAction.cta);
      expect(d('peizhu://cta/plan', main: false).action, ReaderNavAction.cta);
    });

    test('「讀下一篇」: peizhu://reader/open?id=<id> → that unit', () {
      final open = d('peizhu://reader/open?id=small_steps');
      expect(open.action, ReaderNavAction.openUnit);
      expect(open.unitId, 'small_steps');
      for (final bad in [
        'peizhu://reader/open?id=Small Steps',
        'peizhu://reader/open?id=',
        'peizhu://reader/open',
        'peizhu://reader/open?id=a&id=b',
        'peizhu://reader/open?id=a&x=1',
        'peizhu://reader/close?id=a',
      ]) {
        expect(d(bad).action, ReaderNavAction.block, reason: bad);
      }
    });

    test('only the first load passes; everything else is blocked (incl. '
        'peizhu://explain, never shown)', () {
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
        'peizhu://cta/plan?x=1',
        'peizhu://home',
        'peizhu://explain?card=small_steps.c1',
        'javascript:alert(1)',
      ]) {
        expect(d(url, initial: true).action, ReaderNavAction.block,
            reason: url);
      }
      expect(isReaderExplainUrl('peizhu://explain?card=small_steps.c1'), isTrue);
    });

    test('1021 hard rule: every peizhu:// link in the 14 packaged files is '
        'handled — a CTA the App opens, a unit that is packaged, or an '
        'explain button the page never shows', () {
      final ids = {for (final u in packaged.units) u.id};
      final seen = <String, int>{};
      for (final u in packaged.units) {
        final html = packaged.html[u.id]!;
        final prepared = prepareReaderHtml(html, fontScale: 1.3, ask: true);
        for (final m in _peizhuLink.allMatches(html)) {
          final url = m.group(0)!;
          final key = url.startsWith('peizhu://explain')
              ? 'peizhu://explain?card=…'
              : url;
          seen[key] = (seen[key] ?? 0) + 1;
          final nav = d(url);
          if (nav.action == ReaderNavAction.cta) {
            expect(ReaderCta.values, contains(nav.cta), reason: url);
          } else if (nav.action == ReaderNavAction.openUnit) {
            expect(ids, contains(nav.unitId), reason: '${u.id}: $url');
            expect(nav.unitId, isNot(u.id), reason: url);
          } else {
            // Only the per-card explanations may be blocked, and only
            // because the page never shows them: each sits on an
            // <a class="ask">, the page's CSS shows .ask only under
            // html[data-explain="on"], and the App never sets it.
            expect(isReaderExplainUrl(url), isTrue, reason: '${u.id}: $url');
            final tag = html.substring(
                html.lastIndexOf('<a', m.start), html.indexOf('>', m.start));
            expect(tag, contains('class="ask"'), reason: '${u.id}: $tag');
            expect(html, contains('.ask{display:none'), reason: u.id);
            expect(html, contains('html[data-explain="on"] .ask{display:'),
                reason: u.id);
            // The App adds nothing that sets it: the prepared page has the
            // page's own mentions (its CSS) and no more.
            expect('data-explain'.allMatches(prepared).length,
                'data-explain'.allMatches(html).length, reason: u.id);
            expect(prepared, isNot(contains("'data-explain'")), reason: u.id);
          }
        }
      }
      // The inventory (docs/release/readers-file-format.md).
      expect(seen, {
        'peizhu://cta/chat_siu_yan': 28,
        'peizhu://cta/small_action': 10,
        'peizhu://cta/thought': 3,
        'peizhu://explain?card=…': 72,
        for (final id in [
          'how_lonely_am_i', 'different_needs', 'why_it_matters',
          'what_research_says', 'small_steps', 'talking_with_children',
          'thoughts_and_feelings', 'phone_and_video', 'body_and_sleep',
          'after_loss', 'community_places', 'getting_help',
          'what_companions_can_do',
        ])
          'peizhu://reader/open?id=$id': 1,
      });
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

    test('the four rows: ids, a CTA code, seconds — exactly these fields; '
        '1021: chat_siu_yan is a CTA code', () {
      rec.setProfile(_profile(ArmAssignment.b));
      rec.recordReader(UsageEventType.readerOpen, unitId: 'u2');
      rec.recordReader(UsageEventType.readerSection,
          unitId: 'u2', sectionId: 's1_intro');
      rec.recordReader(UsageEventType.readerCta, unitId: 'u2', cta: 'plan');
      rec.recordReader(UsageEventType.readerCta,
          unitId: 'u2', cta: 'chat_siu_yan');
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
        {'type': 'reader_cta', ...base, 'unitId': 'u2', 'cta': 'chat_siu_yan'},
        {'type': 'reader_close', ...base, 'unitId': 'u2', 'seconds': 95},
      ]);
      expect(kReaderCtaCodes, {for (final c in ReaderCta.values) c.code});
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

  group('read state on this phone (1021 T-R3)', () {
    test('prefs: save adds, never removes; 讀完 = every section; bad ids '
        'and bad JSON ignored', () async {
      SharedPreferences.setMockInitialValues({});
      const marks = PrefsReaderReadMarks();
      expect(await marks.load(), isEmpty);
      await marks.save('small_steps', readIds: {'s1', '第二節'}, total: 3);
      await marks.save('small_steps', readIds: {'s2'}, total: 3);
      await marks.save('Bad Id', readIds: {'s1'}, total: 3);
      var all = await marks.load();
      expect(all.keys, ['small_steps']);
      expect(all['small_steps']!.readIds, {'s1', 's2'});
      expect(all['small_steps']!.done, isFalse);
      await marks.save('small_steps', readIds: {'s3'}, total: 3);
      all = await marks.load();
      expect(all['small_steps']!.done, isTrue);
      await marks.save('small_steps', readIds: const {}, total: 0);
      expect((await marks.load())['small_steps']!.done, isTrue,
          reason: 'nothing is ever taken away');
      SharedPreferences.setMockInitialValues(
          {PrefsReaderReadMarks.key: '{oops'});
      expect(await const PrefsReaderReadMarks().load(), isEmpty);
    });
  });

  group('讀少少 list (1020c §2; 1021 T-R1)', () {
    Future<void> pumpList(WidgetTester tester,
        {required ReaderContentSource source,
        ReaderReadMarks? marks,
        FakeReaderSurface? surface,
        ArmAssignment arm = ArmAssignment.a,
        double textScale = 1.0}) async {
      await tester.pumpWidget(_harness(
        EducationLibraryPage(
          readerSource: source,
          readerSurface: surface ?? FakeReaderSurface(),
          readMarks: marks ?? InMemoryReaderReadMarks(),
        ),
        profile: _profile(arm),
        client: ThrowingLlmClient(),
        textScale: textScale,
      ));
      await _pumpFor(tester);
    }

    Future<void> expectArticlesAsBefore(WidgetTester tester) async {
      await tester.scrollUntilVisible(
          find.text('每篇短短，平實啲講。睇啱嘅，唔啱就過。'), 300);
      final first = EducationLibrary.articles.firstWhere((a) => a.enabled);
      await tester.scrollUntilVisible(find.text(first.titleZh), 300);
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

    for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
      testWidgets('${arm == ArmAssignment.a ? 'Hybrid' : 'rule arm'}: the 14 '
          'packaged units in three parts with their headings, icons, 約 n 分鐘; '
          '✓ 讀完 only when every section is read (360 wide, text 1.30)',
          (tester) async {
        RemoteFeatureFlags.current =
            const RemoteFeatureFlags(htmlReadersEnabled: true);
        tester.view.physicalSize = const Size(360, 800) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpList(tester,
            source: packaged.source(),
            arm: arm,
            textScale: 1.3,
            marks: InMemoryReaderReadMarks({
              'small_steps': const ReaderReadState(
                  readIds: {'s1', 's2', 's3'}, total: 3),
              'after_loss':
                  const ReaderReadState(readIds: {'s1', 's2'}, total: 3),
            }));
        expect(tester.takeException(), isNull);
        expect(find.text('小讀本'), findsOneWidget);
        for (final (part, heading) in [
          (1, '第一部分：認識孤單'),
          (2, '第二部分：自己同身邊嘅人可以做咩'),
          (3, '第三部分：社區同專業支援'),
        ]) {
          final f = find.byKey(Key('reader_part_$part'));
          await tester.scrollUntilVisible(f, 200);
          expect(tester.widget<Text>(f).data, heading);
        }
        await tester.scrollUntilVisible(
            find.byKey(const Key('reader_part_1')), -200);
        String? lastPart;
        for (final u in packaged.units) {
          final card = find.byKey(Key('reader_card_${u.id}'));
          await tester.scrollUntilVisible(card, 200);
          final icon =
              tester.widget<Icon>(find.byKey(Key('reader_icon_${u.id}')));
          expect(icon.icon, kReaderIcons[u.icon], reason: u.id);
          expect(
              tester
                  .widget<Text>(find.byKey(Key('reader_minutes_${u.id}')))
                  .data,
              '約 ${u.minutes} 分鐘');
          expect(find.descendant(of: card, matching: find.text(u.titleZh)),
              findsOneWidget);
          expect(find.byKey(Key('reader_done_${u.id}')),
              u.id == 'small_steps' ? findsOneWidget : findsNothing,
              reason: u.id);
          // A unit comes after its part heading.
          if ('${u.part}' != lastPart) {
            lastPart = '${u.part}';
            final heading = find.byKey(Key('reader_part_${u.part}'));
            if (heading.evaluate().isNotEmpty) {
              expect(tester.getTopLeft(heading).dy,
                  lessThan(tester.getTopLeft(card).dy), reason: u.id);
            }
          }
        }
        // No emoji: the tick is an icon and the word.
        final done = find.byKey(const Key('reader_done_small_steps'));
        await tester.scrollUntilVisible(done, -200);
        expect(find.descendant(of: done, matching: find.text('讀完')),
            findsOneWidget);
        expect(
            find.descendant(
                of: done, matching: find.byIcon(Icons.check_rounded)),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    test('part headings and grouping', () {
      expect(readerPartHeading(1, '認識孤單'), '第一部分：認識孤單');
      expect(readerPartHeading(3, '社區同專業支援'), '第三部分：社區同專業支援');
      expect(readerPartHeading(12, 'x'), '第12部分：x');
      final groups = groupReaderUnits([readerTestUnit, _unitB, _unitA]);
      expect(groups.map((g) => g.$1), [null, 1, 2]);
      expect(groups[1].$2, '認識孤單');
      expect(readerIconFor('science'), Icons.science);
      expect(readerIconFor('no_such_icon'), kReaderDefaultIcon);
      expect(readerIconFor(null), kReaderDefaultIcon);
    });

    testWidgets('open a unit, read all three sections, come back: 讀完',
        (tester) async {
      RemoteFeatureFlags.current =
          const RemoteFeatureFlags(htmlReadersEnabled: true);
      final marks = InMemoryReaderReadMarks();
      final surface = FakeReaderSurface();
      await pumpList(tester, source: _source(), marks: marks, surface: surface);
      await tester.tap(find.text(_unitA.titleZh));
      await _pumpFor(tester);
      expect(find.byType(ReaderPage), findsOneWidget);
      for (final s in ['s1', 's2', 's3']) {
        surface.go(s);
        await _pumpFor(tester, 2);
      }
      surface.go('toc');
      await tester.tap(find.byKey(ReaderPage.backKey));
      await _pumpFor(tester);
      expect(find.byType(ReaderPage), findsNothing);
      expect(marks.states[_unitA.id]!.done, isTrue);
      expect(find.byKey(Key('reader_done_${_unitA.id}')), findsOneWidget);
      expect(find.byKey(Key('reader_done_${_unitB.id}')), findsNothing);
    });

    testWidgets('做啲嘢 → the third card 讀少少 → the 小讀本 list of the '
        'packaged units (1020m four cards)', (tester) async {
      RemoteFeatureFlags.current = const RemoteFeatureFlags(
          htmlReadersEnabled: true, homeLayoutV2Enabled: true);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_harness(const Scaffold(body: MePage()),
          profile: _profile(ArmAssignment.b), client: ThrowingLlmClient()));
      await _pumpFor(tester);
      final cards = find.byType(MeToolCard);
      expect(tester.widget<MeToolCard>(cards.at(2)).title, '讀少少');
      await tester.tap(find.byKey(const ValueKey('me_tool_reading')));
      for (var i = 0;
          i < 40 && find.byKey(const Key('readers_section')).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(EducationLibraryPage), findsOneWidget);
      expect(find.byKey(const Key('readers_section')), findsOneWidget);
      expect(find.text('第一部分：認識孤單'), findsOneWidget);
      expect(find.byKey(const Key('reader_card_what_is_loneliness')),
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
          List<String> chats,
        })> openReader(WidgetTester tester, ArmAssignment arm,
        {double textScale = 1.0,
        ReaderUnit? unit,
        FakeReaderSource? source,
        InMemoryReaderReadMarks? marks}) async {
      final profile = _profile(arm);
      final r = _recorder(profile);
      final surface = FakeReaderSurface();
      final llm = ThrowingLlmClient();
      final src = source ?? _source();
      final m = marks ?? InMemoryReaderReadMarks();
      final chats = <String>[];
      await tester.pumpWidget(_harness(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReaderPage(
                      unit: unit ?? _unitA,
                      source: src,
                      surface: surface,
                      readMarks: m,
                      siuYanChat: (_) {
                        chats.add('小欣');
                        return const Scaffold(
                            key: Key('siu_yan_chat'), body: Text('小欣'));
                      },
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
        source: src,
        marks: m,
        chats: chats,
      );
    }

    String title(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(ReaderPage.titleKey)).data!;
    String subtitle(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(ReaderPage.subtitleKey)).data!;

    testWidgets('loads the asset HTML with the CSP, data-chrome and --fs = '
        'the App scale', (tester) async {
      final h = await openReader(tester, ArmAssignment.a, textScale: 1.3);
      final html = h.surface.last!.html;
      expect(html, contains('Content-Security-Policy'));
      expect(html, contains(':root{--fs:1.30}'));
      expect(html, contains("d.setAttribute('data-chrome','app');"));
      expect(html, contains(_unitA.titleZh));
    });

    testWidgets('a missing file shows a short line, not a crash',
        (tester) async {
      await openReader(tester, ArmAssignment.a,
          unit: const ReaderUnit(
              id: 'u9_missing', titleZh: '冇檔', minutes: 1, order: 9));
      expect(find.text('呢篇暫時打唔開。'), findsOneWidget);
    });

    for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
      final name = arm == ArmAssignment.a ? 'Hybrid' : 'rule arm';

      testWidgets('$name: top bar — title from peizhu:view; 「‹」 and the '
          'system back ask peizhuReader.back() first (true = stay, false = '
          'close); zero LLM calls in the rule arm', (tester) async {
        final h = await openReader(tester, arm, textScale: 1.3);
        expect(tester.takeException(), isNull);
        expect(title(tester), '孤單係咩');
        expect(subtitle(tester), '約 7 分鐘');
        h.surface.go('s2');
        await _pumpFor(tester, 2);
        expect(title(tester), '第 2／3 節');
        expect(subtitle(tester), '孤單係咩');
        // 「‹」 in a section: the page goes back to its contents, we stay.
        await tester.tap(find.byKey(ReaderPage.backKey));
        await _pumpFor(tester);
        expect(h.surface.backCalls, 1);
        expect(find.byType(ReaderPage), findsOneWidget);
        expect(title(tester), '孤單係咩');
        expect(subtitle(tester), '約 7 分鐘');
        // System back in a section: the same.
        h.surface.go('s3');
        await _pumpFor(tester, 2);
        await _systemBack(tester);
        expect(h.surface.backCalls, 2);
        expect(find.byType(ReaderPage), findsOneWidget);
        expect(title(tester), '孤單係咩');
        // At the contents: back closes, the reader returns to the list.
        await _systemBack(tester);
        expect(h.surface.backCalls, 3);
        expect(find.byType(ReaderPage), findsNothing);
        expect(h.llm.calls, 0);
        expect(_rows(h.sink).map((r) => r['type']), [
          'reader_open', 'reader_section', 'reader_section', 'reader_close',
        ]);
        expect(h.marks.states[_unitA.id]!.readIds, {'s2', 's3'});
      });

      testWidgets('$name: 「?」 top right only for Hybrid; the rule arm keeps '
          'the same space empty', (tester) async {
        await openReader(tester, arm);
        if (_isHybrid(arm)) {
          expect(find.byKey(ReaderPage.askKey), findsOneWidget);
          expect(find.byKey(ReaderPage.askSpaceKey), findsNothing);
          expect(tester.getSize(find.byKey(ReaderPage.askKey)),
              const Size(48, 48));
        } else {
          expect(find.byKey(ReaderPage.askKey), findsNothing);
          expect(find.text('?'), findsNothing);
          expect(tester.getSize(find.byKey(ReaderPage.askSpaceKey)),
              const Size(48, 48));
        }
        expect(find.text('問下通通'), findsNothing,
            reason: 'the old bottom button is gone');
      });

      testWidgets('$name: read state round trip — what the page reports '
          'is kept per unit and handed back with setRead next time',
          (tester) async {
        final marks = InMemoryReaderReadMarks();
        var h = await openReader(tester, arm, marks: marks);
        expect(FakeReaderSurface.setReadIn(h.surface.last!.html), isEmpty);
        h.surface.go('s1');
        h.surface.go('s2');
        await _pumpFor(tester, 2);
        h.surface.go('toc');
        await tester.tap(find.byKey(ReaderPage.backKey));
        await _pumpFor(tester);
        expect(find.byType(ReaderPage), findsNothing);
        expect(marks.states[_unitA.id]!.readIds, {'s1', 's2'});
        expect(marks.states[_unitA.id]!.total, 3);
        expect(marks.states[_unitA.id]!.done, isFalse);
        // Next time: setRead(["s1","s2"]) after the page's own script.
        await tester.pumpWidget(const SizedBox());
        h = await openReader(tester, arm, marks: marks);
        expect(FakeReaderSurface.setReadIn(h.surface.last!.html), ['s1', 's2']);
        expect(h.surface.pageRead, {'s1', 's2'});
        h.surface.go('s3');
        h.surface.go('toc');
        await _pumpFor(tester, 2);
        await tester.tap(find.byKey(ReaderPage.backKey));
        await _pumpFor(tester);
        expect(marks.states[_unitA.id]!.done, isTrue);
        expect(h.llm.calls, 0);
      });

      testWidgets('$name: the CTAs open the App pages (chat_siu_yan → the '
          '小欣 chat); back returns to the reader', (tester) async {
        final h = await openReader(tester, arm);
        h.surface.tap('peizhu://cta/chat_siu_yan');
        await _pumpFor(tester);
        expect(find.byKey(const Key('siu_yan_chat')), findsOneWidget);
        expect(h.chats, ['小欣']);
        await _popTop(tester);
        expect(find.byType(ReaderPage), findsOneWidget);
        h.surface.tap('peizhu://cta/thought');
        await _pumpFor(tester);
        expect(find.byType(ThoughtExercisePage), findsOneWidget);
        await _popTop(tester);
        h.surface.tap('peizhu://cta/plan');
        await _pumpFor(tester);
        expect(
            find.byType(
                _isHybrid(arm) ? ActionLoopArmAPage : ActionLoopArmBPage),
            findsOneWidget);
        await _popTop(tester);
        expect(find.byType(ReaderPage), findsOneWidget);
        expect(
            _rows(h.sink)
                .where((r) => r['type'] == 'reader_cta')
                .map((r) => r['cta']),
            ['chat_siu_yan', 'thought', 'plan']);
        if (!_isHybrid(arm)) expect(h.llm.calls, 0);
      });

      testWidgets("$name: 「讀下一篇」 (peizhu://reader/open) shows that unit "
          "in the same page, the current one's read state saved first; "
          'back returns to the list', (tester) async {
        final h = await openReader(tester, arm);
        for (final s in ['s1', 's2', 's3', 'toc']) {
          h.surface.go(s);
        }
        await _pumpFor(tester, 2);
        h.surface.tap('peizhu://reader/open?id=${_unitB.id}');
        await _pumpFor(tester);
        expect(h.marks.states[_unitA.id]!.done, isTrue);
        expect(title(tester), _unitB.titleZh);
        expect(subtitle(tester), '約 6 分鐘');
        expect(h.surface.last!.html, contains(_unitB.titleZh));
        expect(find.byType(ReaderPage), findsOneWidget);
        expect(
            _rows(h.sink).map((r) => '${r['type']}:${r['unitId']}').toList(),
            [
              'reader_open:u1_alpha',
              'reader_section:u1_alpha',
              'reader_section:u1_alpha',
              'reader_section:u1_alpha',
              'reader_close:u1_alpha',
              'reader_open:u2_beta',
            ]);
        h.surface.go('s1');
        await _pumpFor(tester, 2);
        expect(title(tester), '第 1／3 節');
        expect(subtitle(tester), _unitB.titleZh);
        await _systemBack(tester); // section → contents
        await _systemBack(tester); // contents → the list
        expect(find.byType(ReaderPage), findsNothing);
        expect(find.text('open'), findsOneWidget);
        expect(h.marks.states[_unitB.id]!.readIds, {'s1'});
        expect(_rows(h.sink).last, containsPair('type', 'reader_close'));
        expect(_rows(h.sink).last, containsPair('unitId', 'u2_beta'));
        expect(h.llm.calls, 0);
      });

      testWidgets('$name: a 「讀下一篇」 to a unit that is not packaged says '
          'so (never nothing)', (tester) async {
        final h = await openReader(tester, arm);
        h.surface.tap('peizhu://reader/open?id=not_packaged');
        await _pumpFor(tester);
        expect(find.text('呢篇暫時打唔開。'), findsOneWidget);
        expect(title(tester), _unitA.titleZh);
        expect(h.llm.calls, 0);
      });
    }

    testWidgets('a page without peizhuReader (an older unit): back closes '
        'straight away', (tester) async {
      final h = await openReader(tester, ArmAssignment.a, unit: readerTestUnit);
      h.surface.hasReaderApi = false;
      await tester.tap(find.byKey(ReaderPage.backKey));
      await _pumpFor(tester);
      expect(find.byType(ReaderPage), findsNothing);
    });

    test('the 小欣 chat CTA opens CheckInPage by default (the entry every '
        '小欣 card uses; it picks the page for the arm)', () {
      expect(ReaderPage.defaultSiuYanChat(_FakeContext()), isA<CheckInPage>());
    });

    testWidgets('Hybrid: 「?」 opens 通通 article Q&A on <id>.txt',
        (tester) async {
      final h = await openReader(tester, ArmAssignment.a);
      await tester.tap(find.byKey(ReaderPage.askKey));
      await _pumpFor(tester);
      final page = tester.widget<TungTungPage>(find.byType(TungTungPage));
      expect(page.articleContext, '孤單係咩：文字');
      expect(page.articleTitle, _unitA.titleZh);
      expect(page.articleId, 'reader_${_unitA.id}');
      expect(page.articleContextHeader, kReaderQaHeaderZh);
      expect(kReaderQaHeaderZh, contains('電腦程式夥伴'));
      expect(h.source.textReads, 1);
    }, skip: !_isHybrid(ArmAssignment.a));

    testWidgets('rule arm: no 「?」 and no LLM anywhere — open, sections, the '
        'four CTAs, 「讀下一篇」, back', (tester) async {
      final h = await openReader(tester, ArmAssignment.b);
      expect(find.byKey(ReaderPage.askKey), findsNothing);
      h.surface.go('s1');
      for (final cta in ReaderCta.values) {
        h.surface.last!.onCta(cta);
        await _pumpFor(tester);
        await _popTop(tester);
      }
      h.surface.go('toc');
      h.surface.tap('peizhu://reader/open?id=${_unitB.id}');
      await _pumpFor(tester);
      await _systemBack(tester);
      expect(find.byType(ReaderPage), findsNothing);
      expect(h.llm.calls, 0, reason: 'the rule arm never calls the LLM');
      expect(h.source.textReads, 0, reason: 'the .txt is only for Hybrid');
    }, skip: _isHybrid(ArmAssignment.b));

    testWidgets('both arms: same page apart from the 「?」 and data-ask',
        (tester) async {
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
      const askAttr = "d.setAttribute('data-ask','on');";
      expect(b.surface.last!.html.replaceFirst(askAttr, ''),
          htmlA.replaceFirst(askAttr, ''),
          reason: 'same content both arms');
      expect(htmlA.contains(askAttr), _isHybrid(ArmAssignment.a));
      expect(b.surface.last!.html.contains(askAttr), _isHybrid(ArmAssignment.b));
      expect(askA, _isHybrid(ArmAssignment.a) ? 1 : 0);
      expect(askB, _isHybrid(ArmAssignment.b) ? 1 : 0);
      List<String?> withoutAsk(List<String?> t) =>
          t.where((x) => x != '?').toList();
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

class _FakeContext extends Fake implements BuildContext {}

/// An asset bundle from a map; records what was asked for.
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);
  final Map<String, String> files;
  final List<String> asked = [];

  @override
  Future<ByteData> load(String key) async {
    asked.add(key);
    final s = files[key];
    if (s == null) throw FlutterError('no asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(s)));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    asked.add(key);
    final s = files[key];
    if (s == null) throw FlutterError('no asset $key');
    return s;
  }
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
