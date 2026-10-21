// 1020l §二 (2) — iPad: the pages sit in one centred column at most 600
// wide (WideScreenFrame, installed in MaterialApp.builder in app.dart,
// switch wideScreenFrameEnabled).  Phones (360 × 800, 412 × 915, upright or
// sideways) must not change at all: no layout widget is added and every
// box is where it was.  Same for both arms (no arm read anywhere).
//
// Synthetic data only; every service is unavailable, the LLM is a stub.
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:app_demo/app/app.dart';
import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/app/main_shell.dart';
import 'package:app_demo/app/wide_screen_frame.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/fcm/fcm_service.dart';
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/safety/safety_overlay.dart';
import 'package:app_demo/core/usage/usage_event_recorder.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _phones = <Size>[Size(360, 800), Size(412, 915)];
const _phonesSideways = <Size>[Size(800, 360), Size(915, 412)];
const _ipads = <Size>[Size(820, 1180), Size(1180, 820)];

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

String _name(Size s) => '${s.width.toInt()}×${s.height.toInt()}';

// ---------------------------------------------------------------------------
// A small App: the same builder shape as app.dart (text scale, then the
// frame), a home page with an app bar, a list, a bottom navigation bar and
// buttons for a dialog, a SnackBar, a bottom sheet and a second page.
// ---------------------------------------------------------------------------

const _bodyKey = Key('home_body');

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('睇今日')),
      body: ListView(
        key: _bodyKey,
        children: [
          for (var i = 0; i < 3; i++)
            const Card(child: ListTile(title: Text('今日要做嘅事'))),
          ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(
                title: Text('dialog title'),
                content: Text('dialog body'),
              ),
            ),
            child: const Text('dialog'),
          ),
          ElevatedButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('snack text'))),
            child: const Text('snack'),
          ),
          ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const SizedBox(
                  height: 200, child: Center(child: Text('sheet text'))),
            ),
            child: const Text('sheet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                    body: Center(child: Text('second page'))))),
            child: const Text('push'),
          ),
          const TextField(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: '睇今日'),
          NavigationDestination(icon: Icon(Icons.forum), label: '搵人傾'),
          NavigationDestination(icon: Icon(Icons.checklist), label: '做啲嘢'),
          NavigationDestination(icon: Icon(Icons.person), label: '自己'),
        ],
      ),
    );
  }
}

/// [frame] false = the App as before 1020l (no frame in the tree at all).
Widget _app({
  required bool frame,
  bool enabled = true,
  double scale = 1.06,
  GlobalKey<NavigatorState>? nav,
}) =>
    MaterialApp(
      navigatorKey: nav,
      theme: AppTheme.light,
      builder: (context, child) {
        final inner = child ?? const SizedBox.shrink();
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: frame ? WideScreenFrame(enabled: enabled, child: inner) : inner,
        );
      },
      home: const _Home(),
    );

/// The whole render tree, depth first: each object's type and, for a box,
/// its place and size on screen.  Two equal lists = no object added,
/// removed, moved or resized.
List<String> _geometry(WidgetTester tester) {
  final out = <String>[];
  void visit(RenderObject r) {
    out.add(r is RenderBox && r.hasSize
        ? '${r.runtimeType} ${r.localToGlobal(Offset.zero)} ${r.size}'
        : '${r.runtimeType}');
    r.visitChildren(visit);
  }

  tester.binding.renderViews.forEach(visit);
  return out;
}

MediaQueryData _innerMq(WidgetTester tester) =>
    MediaQuery.of(tester.element(find.byKey(_bodyKey)));

/// What the page's Scaffold itself is given (before it hands the top and
/// bottom insets to its bars).
MediaQueryData _pageMq(WidgetTester tester) =>
    MediaQuery.of(tester.element(find.byType(Scaffold)));

Rect _column(WidgetTester tester) =>
    tester.getRect(find.byKey(WideScreenFrame.columnKey));

void _expectInside(Rect inner, Rect outer, String what) {
  expect(inner.left, greaterThanOrEqualTo(outer.left - 0.01), reason: what);
  expect(inner.right, lessThanOrEqualTo(outer.right + 0.01), reason: what);
  expect(inner.top, greaterThanOrEqualTo(outer.top - 0.01), reason: what);
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + 0.01), reason: what);
}

// ---------------------------------------------------------------------------
// The real App (MyApp, guest mode: every service unavailable).
// ---------------------------------------------------------------------------

class _Llm implements LlmClient {
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
  }) async =>
      const LlmRawResponse(text: '好呀。');
}

Widget _myApp() {
  final llm = LlmGateway(client: _Llm());
  final memory = MemoryStore(available: false);
  final agentContext = AgentContextService(available: false);
  final sharedContext = SharedContextService(available: false);
  final state = DistressState();
  return MyApp(
    settings: AppSettings(locale: const Locale('zh')),
    authService: AuthService(available: false),
    analytics: AnalyticsService(firebaseReady: false),
    llm: llm,
    memory: memory,
    distress: const DistressDetector(),
    distressState: state,
    distressRouter: DistressRouter(state: state),
    crossModuleMemory:
        CrossModuleMemoryService(memory: memory, firestoreAvailable: false),
    agentContext: agentContext,
    sharedContext: sharedContext,
    personaResolver: PersonaResolver(
        agentContext: agentContext, sharedContext: sharedContext),
    referralRouting: ReferralRoutingService(sharedContext: sharedContext),
    handoffExecutor: HandoffExecutor(sharedContext: sharedContext),
    agentGreeting: AgentGreetingService(llm),
    fcm: FcmService(available: false),
    usageEvents: UsageEventRecorder(sink: InMemoryUsageEventSink()),
  );
}

Future<void> _pumpMyApp(WidgetTester tester, Size size,
    {required bool on}) async {
  _setSize(tester, size);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => ['wifi'],
  );
  // The 10/21 home (two pages, mood row) and the switch under test.
  RemoteFeatureFlags.current = RemoteFeatureFlags(
    homeLayoutV2Enabled: true,
    moodRowV2Enabled: true,
    wideScreenFrameEnabled: on,
  );
  await tester.pumpWidget(_myApp());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  tearDown(RemoteFeatureFlags.resetForTest);

  group('which screens get the column', () {
    test('phones (upright or sideways) never; iPads always', () {
      for (final s in [..._phones, ..._phonesSideways]) {
        expect(WideScreenFrame.appliesTo(s), isFalse, reason: _name(s));
      }
      for (final s in [..._ipads, const Size(744, 1133), const Size(1133, 744)]) {
        expect(WideScreenFrame.appliesTo(s), isTrue, reason: _name(s));
      }
      // iPad split view narrower than the column: the page keeps its width.
      expect(WideScreenFrame.appliesTo(const Size(590, 820)), isFalse);
      expect(WideScreenFrame.appliesTo(const Size(600, 1180)), isFalse);
    });

    test('the switch is off unless the document says true', () {
      expect(const RemoteFeatureFlags().wideScreenFrameEnabled, isFalse);
      expect(RemoteFeatureFlags.fromMap(const {}).wideScreenFrameEnabled,
          isFalse);
      expect(
          RemoteFeatureFlags.fromMap(const {'wideScreenFrameEnabled': 'true'})
              .wideScreenFrameEnabled,
          isFalse);
      expect(
          RemoteFeatureFlags.fromMap(const {'wideScreenFrameEnabled': true})
              .wideScreenFrameEnabled,
          isTrue);
    });

    test('inside the column: its width; side insets less the margin', () {
      const outer = MediaQueryData(
        size: Size(820, 1180),
        padding: EdgeInsets.fromLTRB(150, 24, 30, 20),
        viewPadding: EdgeInsets.fromLTRB(150, 24, 30, 20),
        viewInsets: EdgeInsets.only(bottom: 300),
        systemGestureInsets: EdgeInsets.fromLTRB(120, 0, 120, 0),
        textScaler: TextScaler.linear(1.3),
        displayFeatures: [
          DisplayFeature(
              bounds: Rect.fromLTWH(400, 0, 20, 1180),
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureFlat),
        ],
      );
      final inner = WideScreenFrame.columnData(outer);
      expect(inner.size, const Size(600, 1180));
      // Margin is (820 − 600) / 2 = 110 on each side.
      expect(inner.padding, const EdgeInsets.fromLTRB(40, 24, 0, 20));
      expect(inner.viewPadding, const EdgeInsets.fromLTRB(40, 24, 0, 20));
      expect(inner.viewInsets, const EdgeInsets.only(bottom: 300),
          reason: 'the keyboard keeps its height');
      expect(inner.systemGestureInsets, const EdgeInsets.fromLTRB(10, 0, 10, 0));
      expect(inner.textScaler, const TextScaler.linear(1.3));
      expect(inner.displayFeatures.single.bounds,
          const Rect.fromLTWH(290, 0, 20, 1180));
    });
  });

  group('phones: nothing changes', () {
    for (final size in [..._phones, ..._phonesSideways]) {
      for (final scale in const [1.06, 1.30]) {
        testWidgets('${_name(size)} × 字體 $scale: every box where it was',
            (tester) async {
          _setSize(tester, size);
          await tester.pumpWidget(_app(frame: false, scale: scale));
          await tester.pumpAndSettle();
          final before = _geometry(tester);
          final mqBefore = _innerMq(tester);
          final mqCount = find.byType(MediaQuery).evaluate().length;

          await tester.pumpWidget(Container()); // fresh tree
          await tester.pumpWidget(_app(frame: true, scale: scale));
          await tester.pumpAndSettle();
          expect(find.byKey(WideScreenFrame.columnKey), findsNothing);
          expect(_geometry(tester), before);
          expect(_innerMq(tester), mqBefore);
          expect(_innerMq(tester).size, size);
          expect(find.byType(MediaQuery).evaluate().length, mqCount,
              reason: 'no MediaQuery added');
          expect(tester.getRect(find.byType(Scaffold)), Offset.zero & size);
        });
      }
    }

    testWidgets('360×800: dialog, SnackBar and sheet exactly as before',
        (tester) async {
      _setSize(tester, const Size(360, 800));
      final shots = <bool, List<Rect>>{};
      for (final frame in [false, true]) {
        await tester.pumpWidget(Container());
        await tester.pumpWidget(_app(frame: frame));
        await tester.pumpAndSettle();
        await tester.tap(find.text('dialog'));
        await tester.pumpAndSettle();
        final dialog = tester.getRect(find.byType(AlertDialog));
        Navigator.of(tester.element(find.text('dialog body'))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('snack'));
        await tester.pumpAndSettle();
        final snack = tester.getRect(find.byType(SnackBar));
        await tester.tap(find.text('sheet'));
        await tester.pumpAndSettle();
        final sheet = tester.getRect(find.text('sheet text'));
        shots[frame] = [dialog, snack, sheet];
      }
      expect(shots[true], shots[false]);
    });

    for (final size in _phones) {
      testWidgets('the real App (MyApp) on a ${_name(size)} phone: switch on '
          'and off draw the same', (tester) async {
        await _pumpMyApp(tester, size, on: false);
        final off = _geometry(tester);
        await tester.pumpWidget(Container());
        await _pumpMyApp(tester, size, on: true);
        expect(find.byType(WideScreenFrame), findsOneWidget);
        expect(find.byKey(WideScreenFrame.columnKey), findsNothing);
        // The frame owns no render object: its first one is the page's.
        expect(tester.renderObject(find.byType(WideScreenFrame)),
            same(tester.renderObject(find.byType(SafetyOverlay))));
        expect(_geometry(tester), off);
        expect(tester.getRect(find.byType(MainShell)).width, size.width);
        expect(tester.getRect(find.byType(NavigationBar)).left, 0);
        expect(tester.getRect(find.byType(NavigationBar)).width, size.width);
      });
    }
  });

  group('iPad: one centred column ≤ 600', () {
    for (final size in _ipads) {
      testWidgets('${_name(size)}: page, MediaQuery, bar and background',
          (tester) async {
        _setSize(tester, size);
        await tester.pumpWidget(_app(frame: true));
        await tester.pumpAndSettle();
        final left = (size.width - 600) / 2;
        expect(_column(tester), Rect.fromLTWH(left, 0, 600, size.height));
        final page = tester.getRect(find.byType(Scaffold));
        expect(page, Rect.fromLTWH(left, 0, 600, size.height));
        expect(page.center.dx, size.width / 2);
        expect(_innerMq(tester).size, Size(600, size.height),
            reason: 'pages that read the screen width see the column');
        expect(tester.getRect(find.byType(NavigationBar)).width, 600);
        expect(tester.getRect(find.byType(NavigationBar)).left, left);
        expect(tester.getRect(find.byType(AppBar)).width, 600);
        // The margins are the App's background, not black.
        final box = tester.widget<ColoredBox>(find
            .ancestor(
                of: find.byKey(WideScreenFrame.columnKey),
                matching: find.byType(ColoredBox))
            .first);
        expect(box.color, AppTheme.light.scaffoldBackgroundColor);
      });

      testWidgets('${_name(size)}: dialog, SnackBar and sheet in the column',
          (tester) async {
        _setSize(tester, size);
        await tester.pumpWidget(_app(frame: true));
        await tester.pumpAndSettle();
        final column = _column(tester);

        await tester.tap(find.text('dialog'));
        await tester.pumpAndSettle();
        expect(find.text('dialog body'), findsOneWidget);
        final dialog = tester.getRect(find.byType(AlertDialog));
        _expectInside(dialog, column, 'dialog');
        expect(dialog.center.dx, closeTo(size.width / 2, 0.01));
        expect(tester.getRect(find.byType(ModalBarrier).last), column,
            reason: 'the dimmed area is the column');
        Navigator.of(tester.element(find.text('dialog body'))).pop();
        await tester.pumpAndSettle();
        expect(find.text('dialog body'), findsNothing);

        await tester.tap(find.text('snack'));
        await tester.pumpAndSettle();
        expect(find.text('snack text'), findsOneWidget);
        final snack = tester.getRect(find.byType(SnackBar));
        _expectInside(snack, column, 'SnackBar');
        expect(snack.width, greaterThan(500),
            reason: 'the SnackBar spans the column');
        expect(
            snack.bottom,
            lessThanOrEqualTo(
                tester.getRect(find.byType(NavigationBar)).top + 0.01),
            reason: 'the SnackBar sits above the navigation bar');

        await tester.tap(find.text('sheet'));
        await tester.pumpAndSettle();
        expect(find.text('sheet text'), findsOneWidget);
        final sheet = tester.getRect(find.ancestor(
            of: find.text('sheet text'), matching: find.byType(BottomSheet)));
        _expectInside(sheet, column, 'bottom sheet');
        expect(sheet.bottom, size.height);
      });

      testWidgets('${_name(size)}: keyboard and safe areas', (tester) async {
        _setSize(tester, size);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
        await tester.pumpWidget(_app(frame: true));
        await tester.pumpAndSettle();
        expect(_pageMq(tester).padding,
            const EdgeInsets.only(top: 24, bottom: 20));
        expect(_pageMq(tester).viewPadding,
            const EdgeInsets.only(top: 24, bottom: 20));
        expect(_pageMq(tester).size.width, 600);

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(_pageMq(tester).viewInsets.bottom, 300);
        expect(tester.getRect(find.byKey(_bodyKey)).bottom,
            size.height - 300,
            reason: 'the page shrinks above the keyboard');
      });
    }

    testWidgets('switch off: iPad exactly as before', (tester) async {
      for (final size in _ipads) {
        _setSize(tester, size);
        await tester.pumpWidget(Container());
        await tester.pumpWidget(_app(frame: false));
        await tester.pumpAndSettle();
        final before = _geometry(tester);
        await tester.pumpWidget(Container());
        await tester.pumpWidget(_app(frame: true, enabled: false));
        await tester.pumpAndSettle();
        expect(find.byKey(WideScreenFrame.columnKey), findsNothing);
        expect(_geometry(tester), before, reason: _name(size));
        expect(tester.getRect(find.byType(Scaffold)).width, size.width);
      }
    });

    testWidgets('resizing (split view) keeps the open page', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      _setSize(tester, const Size(820, 1180));
      await tester.pumpWidget(_app(frame: true, nav: nav));
      await tester.pumpAndSettle();
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();
      final navigator = nav.currentState;
      expect(find.text('second page'), findsOneWidget);

      tester.view.physicalSize = const Size(400, 1180);
      await tester.pumpAndSettle();
      expect(find.byKey(WideScreenFrame.columnKey), findsNothing);
      expect(find.text('second page'), findsOneWidget);
      expect(nav.currentState, same(navigator));

      tester.view.physicalSize = const Size(1180, 820);
      await tester.pumpAndSettle();
      expect(find.byKey(WideScreenFrame.columnKey), findsOneWidget);
      expect(find.text('second page'), findsOneWidget);
      expect(nav.currentState, same(navigator));
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsOneWidget);
    });

    for (final size in _ipads) {
      testWidgets('the real App (MyApp) on ${_name(size)}: column on with the '
          'switch, full width without', (tester) async {
        await _pumpMyApp(tester, size, on: true);
        final left = (size.width - 600) / 2;
        expect(_column(tester), Rect.fromLTWH(left, 0, 600, size.height));
        final shell = tester.getRect(find.byType(MainShell));
        expect(shell.left, left);
        expect(shell.width, 600);
        expect(tester.getRect(find.byType(NavigationBar)).width, 600);
        expect(
            MediaQuery.sizeOf(tester.element(find.byType(MainShell))).width,
            600);

        await tester.pumpWidget(Container());
        await _pumpMyApp(tester, size, on: false);
        expect(find.byKey(WideScreenFrame.columnKey), findsNothing);
        expect(tester.getRect(find.byType(MainShell)).width, size.width);
      });
    }
  });
}
