// decisions-log 10/21 item 133 (2) — 「望一望心入面」 form v2 (PI final
// handoff):
//   - every elder-visible word equals docs/spec/copy/thought-exercise.md
//     §1, word for word, in page order; the deleted v1 words are gone;
//   - both arms entering from 做啲嘢 get the same blank form (Arm.of is
//     read from the profile only in a Phase B build, see
//     tool/ci_flutter_tests.sh "phase B arm gating" / "phase B arm B
//     pages"); Hybrid entering from 小欣's invite gets 一 pre-filled;
//   - only 一 and 二 are required; 三 and 四 may be blank;
//   - the saved record keeps the v1 field names, adds `version: 2`, stops
//     writing `oneReasonTrue`; before/after scores as before;
//   - the safety check runs after the save, on 一/三/四;
//   - no model call anywhere in the exercise (the fake model fails the
//     test if called, in both arms);
//   - the App's largest text (1.30) on a 360 × 780 phone: no overflow.
// Synthetic data only; no Firebase.
import 'dart:io';

import 'package:app_demo/app/app_settings.dart';
import 'package:app_demo/app/app_settings_scope.dart';
import 'package:app_demo/app/app_theme.dart';
import 'package:app_demo/core/agent_context/agent_context_service.dart';
import 'package:app_demo/core/agent_context/shared_context_service.dart';
import 'package:app_demo/core/agents/persona_resolver.dart';
import 'package:app_demo/core/core_services_scope.dart';
import 'package:app_demo/core/cross_referral/handoff_executor.dart';
import 'package:app_demo/core/cross_referral/referral_routing_service.dart';
import 'package:app_demo/core/llm/agent_greeting_service.dart';
import 'package:app_demo/core/llm/llm_gateway.dart';
import 'package:app_demo/core/memory/cross_module_memory.dart';
import 'package:app_demo/core/memory/memory_store.dart';
import 'package:app_demo/core/safety/distress_detector.dart';
import 'package:app_demo/core/safety/distress_router.dart';
import 'package:app_demo/core/safety/distress_state.dart';
import 'package:app_demo/core/safety/safety_check.dart';
import 'package:app_demo/core/survey/likert_scale.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/auth_service.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/auth/presentation/auth_service_scope.dart';
import 'package:app_demo/features/crisis/presentation/pages/emergency_support_page.dart';
import 'package:app_demo/features/thought_exercise/data/thought_exercise_entry.dart';
import 'package:app_demo/features/thought_exercise/presentation/naming_thought_card.dart';
import 'package:app_demo/features/thought_exercise/presentation/thought_exercise_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _scale = 1.3; // the App's largest font (特大)

/// docs/spec/copy/thought-exercise.md §1: id → text.
Map<String, String> _copy() {
  final doc =
      File('docs/spec/copy/thought-exercise.md').readAsStringSync();
  final table = doc.split('## 1.')[1].split('## 2.')[0];
  return {
    for (final line in table.split('\n'))
      if (line.startsWith('| TE-'))
        line.split('|').map((c) => c.trim()).toList()[1]:
            line.split('|').map((c) => c.trim()).toList()[3],
  };
}

/// Any model call fails the test (the exercise never calls one).
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
    throw TestFailure('the thought exercise called the model ($moduleId)');
  }
}

/// Records what would be written to users/{uid}/thought_exercise.
class _FakeRepo extends ThoughtExerciseRepository {
  _FakeRepo(this.log) : super(available: false);
  final List<String> log;
  Map<String, dynamic>? saved;
  int? after;

  @override
  Future<String?> create(String uid, ThoughtExerciseEntry entry) async {
    saved = entry.toMap();
    log.add('save');
    return 'e1';
  }

  @override
  Future<void> setIntensityAfter({
    required String uid,
    required String entryId,
    required int intensityAfter,
  }) async {
    after = intensityAfter;
    log.add('after:$entryId');
  }
}

/// The real safety check, plus a record of each call.
class _SpySafety extends SafetyService {
  _SpySafety(this.log);
  final List<String> log;
  final texts = <String>[];
  final points = <SafetyInputPoint>[];

  @override
  Future<SafetyCheckResult> checkAndRoute(
    BuildContext context,
    String text, {
    required SafetyInputPoint point,
    String? uid,
    String? agentId,
    String? sessionId,
  }) {
    log.add('safety');
    texts.add(text);
    points.add(point);
    return super.checkAndRoute(context, text,
        point: point, uid: uid, agentId: agentId, sessionId: sessionId);
  }
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
    );

class _Run {
  _Run(this.arm);
  final ArmAssignment arm;
  final llm = _NoLlm();
  final log = <String>[];
  late final repo = _FakeRepo(log);
  late final safety = _SpySafety(log);
  final navKey = GlobalKey<NavigatorState>();
  // The App sets the arm tag at sign-in (m5_thought_exercise_saved needs it).
  late final analytics = AnalyticsService(firebaseReady: false)
    ..setEnvironment(arm: arm == ArmAssignment.a ? 'A' : 'B');
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
          safety: run.safety,
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
            // Same wrapper as app.dart, at the largest App font.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(_scale)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    ),
  );
}

/// 做啲嘢 tile: the blank form, both arms.
ThoughtExercisePage _fromTile(_Run run) =>
    ThoughtExercisePage(repository: run.repo);

/// 小欣's invite (Hybrid): 一 pre-filled, provenance set.
ThoughtExercisePage _fromInvite(_Run run, String thought) =>
    ThoughtExercisePage(
      repository: run.repo,
      initialThought: thought,
      agentId: 'siu_yan',
      agentInvitationText:
          NamingThoughtCard.invitationText(thought, isEn: false),
      originTurnRef: 'users/u1/agent_contexts/siu_yan',
    );

Future<void> _open(WidgetTester tester, _Run run, Widget page) async {
  tester.view.physicalSize = const Size(720, 1560); // 360 × 780 logical
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness(run));
  await tester.pumpAndSettle();
  run.navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
  await tester.pumpAndSettle();
}

Finder get _fields => find.byType(TextField);

Future<void> _tap(WidgetTester tester, Finder f) async {
  // Close the keyboard first: a focused box scrolls itself back on screen.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder _dot(int n) => find.descendant(
    of: find.byType(LikertScale), matching: find.text('$n'));

bool _canContinue(WidgetTester tester) => tester
        .widget<FilledButton>(find.ancestor(
            of: find.text('繼續'), matching: find.byType(FilledButton)))
        .onPressed !=
    null;

/// Every Text on screen, top to bottom (the "same page" check).
List<String> _texts(WidgetTester tester) => [
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        w.data ?? w.textSpan?.toPlainText() ?? '',
    ];

void main() {
  final copy = _copy();

  test('copy table holds every TE row', () {
    expect(copy.keys, [
      'TE-title', 'TE-intro', 'TE-q1', 'TE-q1-hint', 'TE-q2', 'TE-q2-scale',
      'TE-scale-low', 'TE-scale-high', 'TE-q3', 'TE-q4', 'TE-next',
      'TE-after-title', 'TE-after', 'TE-before-label', 'TE-now-label',
      'TE-done', 'TE-invite',
    ]);
  });

  testWidgets('form: every word from the copy file, in order; v1 words gone',
      (tester) async {
    final run = _Run(ArmAssignment.b);
    await _open(tester, run, _fromTile(run));
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text(copy['TE-title']!)),
        findsOneWidget);
    final order = [
      'TE-intro', 'TE-q1', 'TE-q1-hint', 'TE-q2', 'TE-q2-scale',
      'TE-scale-low', 'TE-q3', 'TE-q4', 'TE-next',
    ];
    var y = double.negativeInfinity;
    for (final id in order) {
      final f = find.text(copy[id]!);
      expect(f, findsOneWidget, reason: id);
      final top = tester.getTopLeft(f).dy;
      expect(top, greaterThan(y), reason: '$id comes after the one before');
      y = top;
    }
    expect(find.text(copy['TE-scale-high']!), findsOneWidget);
    // The five faces and their words are unchanged.
    for (final w in ['擔心', '唔開心', '一般', '幾好', '開心']) {
      expect(find.text(w), findsOneWidget, reason: w);
    }
    // 一 is above 二's faces; three text boxes: 一, 三, 四.
    expect(_fields, findsNWidgets(3));
    expect(tester.getTopLeft(_fields.at(0)).dy,
        lessThan(tester.getTopLeft(find.text('😟')).dy));
    expect(tester.getTopLeft(_fields.at(1)).dy,
        greaterThan(tester.getTopLeft(find.text(copy['TE-q3']!)).dy));
    expect(tester.getTopLeft(_fields.at(2)).dy,
        greaterThan(tester.getTopLeft(find.text(copy['TE-q4']!)).dy));
    for (final gone in [
      '呢度可以畀你睇返自己最近嘅心情同諗法',
      '嗰陣係咩情況',
      '可能成立嘅理由',
      '另一個角度',
      'rate',
    ]) {
      expect(find.textContaining(gone), findsNothing, reason: gone);
    }
    expect(run.llm.calls, 0);
  });

  testWidgets('前後對照: words from the copy file; 之前 / 而家 side by side',
      (tester) async {
    final run = _Run(ArmAssignment.b);
    await _open(tester, run, _fromTile(run));
    await tester.enterText(_fields.at(0), '冇人記得我');
    await _tap(tester, find.text('😔'));
    await _tap(tester, _dot(7));
    await _tap(tester, find.text('繼續'));
    expect(
        find.descendant(
            of: find.byType(AppBar),
            matching: find.text(copy['TE-after-title']!)),
        findsOneWidget);
    for (final id in [
      'TE-after', 'TE-before-label', 'TE-now-label', 'TE-done',
      'TE-scale-low', 'TE-scale-high',
    ]) {
      expect(find.text(copy[id]!), findsOneWidget, reason: id);
    }
    final before = tester.getCenter(find.text(copy['TE-before-label']!));
    final now = tester.getCenter(find.text(copy['TE-now-label']!));
    expect(before.dy, now.dy);
    expect(before.dx, lessThan(now.dx));
    expect(find.textContaining('依家'), findsNothing);
    expect(find.textContaining('rate'), findsNothing);
    expect(run.llm.calls, 0);
  });

  testWidgets('invite card (Hybrid only): the TE-invite sentence, buttons '
      'unchanged', (tester) async {
    const said = '冇人記得我';
    final want = copy['TE-invite']!.replaceAll('{那句话}', said);
    expect(NamingThoughtCard.invitationText(said, isEn: false), want);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: NamingThoughtCard(
            thought: said, onAccept: () {}, onDecline: () {}),
      ),
    ));
    expect(find.text(want), findsOneWidget);
    expect(find.text('好，試下'), findsOneWidget);
    expect(find.text('唔使住'), findsOneWidget);
    // Long sentences are cut on the card as before (the form gets it all).
    final long = '我' * 40;
    expect(NamingThoughtCard.invitationText(long, isEn: false),
        copy['TE-invite']!.replaceAll('{那句话}', '${'我' * 28}…'));
  });

  testWidgets('both arms from 做啲嘢: the same blank form, no model call',
      (tester) async {
    final seen = <List<String>>[];
    for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
      final run = _Run(arm);
      await _open(tester, run, _fromTile(run));
      for (final f in _fields.evaluate()) {
        expect((f.widget as TextField).controller!.text, '', reason: '$arm');
      }
      expect(_canContinue(tester), isFalse);
      seen.add(_texts(tester));
      expect(run.llm.calls, 0, reason: '$arm');
      await tester.pumpWidget(const SizedBox());
    }
    expect(seen[0], seen[1]);
  });

  testWidgets('Hybrid from 小欣\'s invite: 一 pre-filled with the whole '
      'sentence; saved as siu_yan_offer', (tester) async {
    final run = _Run(ArmAssignment.a);
    final said = '我覺得冇人記得我，連阿女都唔打電話返嚟，我真係冇用';
    await _open(tester, run, _fromInvite(run, said));
    expect(tester.widget<TextField>(_fields.at(0)).controller!.text, said);
    expect(tester.widget<TextField>(_fields.at(1)).controller!.text, '');
    expect(tester.widget<TextField>(_fields.at(2)).controller!.text, '');
    await _tap(tester, find.text('😟'));
    await _tap(tester, _dot(8));
    await _tap(tester, find.text('繼續'));
    final m = run.repo.saved!;
    expect(m['thought'], said);
    expect(m['entryPathway'], 'siu_yan_offer');
    expect(m['agentId'], 'siu_yan');
    expect(m['agentInvitationText'],
        NamingThoughtCard.invitationText(said, isEn: false));
    expect(m['version'], 2);
    expect(run.llm.calls, 0);
  });

  testWidgets('required: only 一 and 二; filling just those saves',
      (tester) async {
    final run = _Run(ArmAssignment.b);
    await _open(tester, run, _fromTile(run));
    expect(_canContinue(tester), isFalse);
    await tester.enterText(_fields.at(0), '冇人記得我');
    await tester.pump();
    expect(_canContinue(tester), isFalse, reason: 'no face, no number');
    await _tap(tester, find.text('😔'));
    expect(_canContinue(tester), isFalse, reason: 'no number');
    await _tap(tester, _dot(6));
    expect(_canContinue(tester), isTrue, reason: '三 and 四 may be blank');
    await tester.enterText(_fields.at(0), '   ');
    await tester.pump();
    expect(_canContinue(tester), isFalse, reason: '一 is required');
    await tester.enterText(_fields.at(0), '冇人記得我');
    await tester.pump();
    await _tap(tester, find.text('繼續'));
    final m = run.repo.saved!;
    expect(m['situation'], '');
    expect(m['anotherWayToLook'], '');
    expect(find.text(copy['TE-after']!), findsOneWidget);
  });

  testWidgets('record: v1 field names + version 2, no oneReasonTrue; '
      'before/after scores; safety check after the save on 一/三/四',
      (tester) async {
    final run = _Run(ArmAssignment.b);
    await _open(tester, run, _fromTile(run));
    await tester.enterText(_fields.at(0), '冇人記得我');
    await tester.enterText(_fields.at(1), '個仔冇覆我電話');
    await tester.enterText(_fields.at(2), '佢可能忙緊，唔代表唔記得你');
    await _tap(tester, find.text('😟'));
    await _tap(tester, _dot(8));
    await _tap(tester, find.text('繼續'));

    final m = run.repo.saved!;
    expect(m.keys.toSet(), {
      'situation', 'emotionEmoji', 'intensityBefore', 'thought',
      'anotherWayToLook', 'version', 'intensityAfter', 'agentId',
      'agentInvitationText', 'originTurnRef', 'createdAt', 'entryPathway',
    });
    expect(m.containsKey('oneReasonTrue'), isFalse);
    expect(m['thought'], '冇人記得我'); // 一
    expect(m['emotionEmoji'], '😟'); // 二
    expect(m['intensityBefore'], 8); // 二
    expect(m['situation'], '個仔冇覆我電話'); // 三
    expect(m['anotherWayToLook'], '佢可能忙緊，唔代表唔記得你'); // 四
    expect(m['version'], 2);
    expect(m['intensityAfter'], isNull);
    expect(m['entryPathway'], 'me_tile');
    // Reading it back.
    final back = ThoughtExerciseEntry.fromMap('e1', m);
    expect(back.version, 2);
    expect(back.oneReasonTrue, isNull);
    // A v1 record (no version field) reads as version 1.
    expect(ThoughtExerciseEntry.fromMap('old', const {'thought': 't'}).version,
        1);

    // Safety: same call and input point, after the save, on 一/三/四.
    expect(run.log, ['save', 'safety']);
    expect(run.safety.points, [SafetyInputPoint.thoughtExercise]);
    expect(run.safety.texts,
        ['冇人記得我\n個仔冇覆我電話\n佢可能忙緊，唔代表唔記得你']);

    // After-rating: the same 1–10 scale, written as intensityAfter.
    await _tap(tester, _dot(4));
    await _tap(tester, find.text('完成'));
    expect(run.repo.after, 4);
    expect(run.log, ['save', 'safety', 'after:e1']);
    expect(find.text('home'), findsOneWidget);
    expect(run.llm.calls, 0);
  });

  for (final field in [0, 1, 2]) {
    testWidgets('safety: acute words in box ${field + 1} of 3 open the '
        'crisis page after the save', (tester) async {
      final run = _Run(ArmAssignment.b);
      await _open(tester, run, _fromTile(run));
      await tester.enterText(_fields.at(0), field == 0 ? '我真係想死' : '冇人記得我');
      if (field > 0) await tester.enterText(_fields.at(field), '我真係想死');
      await _tap(tester, find.text('😟'));
      await _tap(tester, _dot(9));
      await _tap(tester, find.text('繼續'));
      expect(find.byType(EmergencySupportPage), findsOneWidget);
      expect(run.log.first, 'save');
      expect(run.repo.saved!['version'], 2);
      expect(run.llm.calls, 0);
    });
  }
}
