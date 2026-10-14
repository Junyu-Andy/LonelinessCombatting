// T30 (registry C19 / C20; dev-tasks-1014 §三 T30): the assessor view.
//   - routing: `blinded` + switch on → assessor page, before the enrolment
//     gate; switch off → participant App as before; `unblinded` → the
//     registration page; participants and legacy names → the App;
//   - the due list shows the W4 window (day 25–31), entered / not entered
//     and the out-of-window mark, and two synthetic assessor accounts see
//     exactly the same thing;
//   - nothing on the assessor's screens names an arm, a group code, Brief
//     PR, Weekly PR, usage, chats, safety or the sequence;
//   - the paper entry: items are the approved DJG-ES wording (spec file,
//     word for word), one item per screen, two confirmations before the
//     callable, no score shown; a server refusal is shown as text;
//   - the dashboard: with the switch on a blinded account is denied; the
//     pooled completion row hides n < 5.
import 'dart:io';

import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/features/assessment/data/djg_w2.dart';
import 'package:app_demo/features/assessor/data/assessor_service.dart';
import 'package:app_demo/features/assessor/presentation/assessor_page.dart';
import 'package:app_demo/features/enrollment/presentation/staff_gate.dart';
import 'package:app_demo/features/researcher_dashboard/data/dashboard_access.dart';
import 'package:app_demo/features/researcher_dashboard/presentation/widgets/outcome_completion_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBackend implements AssessorBackend {
  _FakeBackend({this.failWith});
  final String? failWith;
  final submitted = <OutcomeEntryInput>[];
  final Map<String, EnteredSummary> entered = {};

  @override
  Future<DueList> dueList() async {
    return DueList(
        today: '2026-11-27',
        timepoint: 'W4',
        rows: [
          DueRow(
            researchId: 'PB-001',
            windowStartDate: '2026-11-26',
            windowEndDate: '2026-12-02',
            studyDay: 26,
            windowState: 'open',
            entered: {
              if (entered.containsKey('PB-001')) 'DJG-ES': entered['PB-001']!,
            },
          ),
          const DueRow(
            researchId: 'PB-002',
            windowStartDate: '2026-12-05',
            windowEndDate: '2026-12-11',
            studyDay: 17,
            windowState: 'before',
            entered: {},
          ),
          const DueRow(
            researchId: 'PB-003',
            windowStartDate: '2026-11-14',
            windowEndDate: '2026-11-20',
            studyDay: 38,
            windowState: 'after',
            entered: {
              'DJG-ES':
                  EnteredSummary(assessmentDate: '2026-11-27', outOfWindow: true)
            },
          ),
        ],
      );
  }

  @override
  Future<OutcomeEntryResult> submit(OutcomeEntryInput input) async {
    if (failWith != null) throw AssessorError(failWith!);
    submitted.add(input);
    entered[input.researchId] =
        EnteredSummary(assessmentDate: input.assessmentDate, outOfWindow: false);
    return OutcomeEntryResult(
        outOfWindow: false, missingItems: input.missingItems);
  }
}

Widget _gate(Map<String, dynamic>? claims,
        {required bool on, AssessorBackend? backend, String uid = 'staff'}) =>
    MaterialApp(
      home: StaffGate(
        uid: uid,
        loadClaims: () async => claims,
        assessorViewOn: on,
        assessorBackend: backend,
        child: const Text('participant app'),
      ),
    );

Widget _page(AssessorBackend b) => MaterialApp(
      home: AssessorPage(backend: b, today: () => DateTime(2026, 11, 27)),
    );

/// Words that must never appear on an assessor screen.
final _forbidden = RegExp(
    r'Arm|組別|组别|Group_|Hybrid|規則組|Brief PR|Weekly PR|使用量|對話|对话|安全|序列|LLM',
    caseSensitive: false);

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  test('switches are off unless literally true', () {
    expect(const RemoteFeatureFlags().assessorViewEnabled, isFalse);
    expect(const RemoteFeatureFlags().outcomeCompletionSummaryEnabled, isFalse);
    expect(RemoteFeatureFlags.fromMap({'assessorViewEnabled': 'true'})
        .assessorViewEnabled, isFalse);
    expect(RemoteFeatureFlags.fromMap({'assessorViewEnabled': true})
        .assessorViewEnabled, isTrue);
    expect(RemoteFeatureFlags.fromMap({'outcomeCompletionSummaryEnabled': true})
        .outcomeCompletionSummaryEnabled, isTrue);
  });

  test('routing rule: who goes where', () {
    StaffRoute r(Map<String, dynamic>? c, bool on) =>
        staffRouteFor(c, assessorViewOn: on);
    expect(r({'role': 'blinded'}, true), StaffRoute.assessor);
    expect(r({'role': 'blinded'}, false), StaffRoute.participant);
    expect(r({'role': 'unblinded'}, true), StaffRoute.enrollment);
    expect(r({'role': 'unblinded'}, false), StaffRoute.enrollment);
    expect(r({'role': 'sequence_uploader'}, true), StaffRoute.participant);
    expect(r({'role': 'pi'}, true), StaffRoute.participant);
    expect(r({'role': 'researcher'}, true), StaffRoute.participant);
    expect(r({}, true), StaffRoute.participant);
    expect(r(null, true), StaffRoute.participant);
  });

  test('DJG-ES items and answers equal docs/spec/instruments/djg_es.md', () {
    final lines = File('docs/spec/instruments/djg_es.md').readAsLinesSync();
    final items = lines
        .where((l) => RegExp(r'^\| q\d \|').hasMatch(l))
        .map((l) => l.split('|').map((c) => c.trim()).toList())
        .toList();
    expect(items.length, 6);
    for (var i = 0; i < 6; i++) {
      expect(DjgW2Items.items[i].id, items[i][1]);
      expect(DjgW2Items.items[i].subscale, items[i][2]);
      expect(DjgW2Items.items[i].text, items[i][3]);
    }
    final options = lines
        .where((l) => RegExp(r'^\| (yes|mostly|no) \|').hasMatch(l))
        .map((l) => l.split('|').map((c) => c.trim()).toList())
        .toList();
    expect(options.length, 3);
    for (var i = 0; i < 3; i++) {
      expect(DjgW2Items.options[i].$1, options[i][1]);
      expect(DjgW2Items.options[i].$2, options[i][2]);
    }
  });

  testWidgets('switch off (default): a blinded account gets the App',
      (tester) async {
    await tester.pumpWidget(_gate({'role': 'blinded'}, on: false));
    await tester.pumpAndSettle();
    expect(find.text('participant app'), findsOneWidget);
    expect(find.byType(AssessorPage), findsNothing);
  });

  testWidgets('switch on: blinded → assessor page (no App, no S8); '
      'participant and legacy claims → App', (tester) async {
    final b = _FakeBackend();
    await tester.pumpWidget(_gate({'role': 'blinded'}, on: true, backend: b));
    await tester.pumpAndSettle();
    expect(find.byType(AssessorPage), findsOneWidget);
    expect(find.text('participant app'), findsNothing);
    expect(find.textContaining('研究人員會幫你完成登記'), findsNothing);
    for (final claims in [
      <String, dynamic>{},
      {'role': 'pi'},
      {'role': 'researcher'},
      {'role': 'sequence_uploader'},
    ]) {
      await tester.pumpWidget(
          _gate(claims, on: true, backend: b, uid: 'u-${claims['role']}'));
      await tester.pumpAndSettle();
      expect(find.text('participant app'), findsOneWidget, reason: '$claims');
    }
  });

  testWidgets('due list: window, study day, entered and out-of-window; '
      'two assessors see the same; no forbidden words', (tester) async {
    final shots = <String>[];
    for (final uid in ['assessorKeran', 'assessorMingyan']) {
      await tester.pumpWidget(MaterialApp(
        home: StaffGate(
          uid: uid,
          loadClaims: () async => {'role': 'blinded'},
          assessorViewOn: true,
          assessorBackend: _FakeBackend(),
          child: const Text('participant app'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('PB-001'), findsOneWidget);
      expect(find.textContaining('W4 窗口 2026-11-26 至 2026-12-02（今日第 26 日）'),
          findsOneWidget);
      expect(find.textContaining('未錄入（窗口開放中）'), findsOneWidget);
      expect(find.textContaining('未到期'), findsOneWidget);
      expect(find.textContaining('已錄入（超窗）2026-11-27'), findsOneWidget);
      expect(find.byKey(const Key('enter_PB-001')), findsOneWidget);
      expect(find.byKey(const Key('enter_PB-003')), findsNothing,
          reason: 'already entered: no second entry from the App');
      final text = _allText(tester);
      expect(_forbidden.hasMatch(text), isFalse, reason: text);
      shots.add(text);
    }
    expect(shots[0], shots[1], reason: 'identical for both assessors');
  });

  testWidgets('entry: items verbatim, one per screen, two confirmations, '
      'then the callable; no score anywhere', (tester) async {
    final b = _FakeBackend();
    await tester.pumpWidget(_page(b));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('enter_PB-001')));
    await tester.pumpAndSettle();
    // Date + mode first; 下一題 disabled until a mode is picked.
    expect(find.text('2026-11-27'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(find.byKey(const Key('entry_next'))).onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('entry_mode_phone')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('entry_next')));
    await tester.pumpAndSettle();
    final answers = ['yes', 'mostly', 'no', 'skipped', 'yes', 'no'];
    for (var i = 0; i < 6; i++) {
      final item = DjgW2Items.items[i];
      expect(find.text(item.text), findsOneWidget, reason: item.id);
      expect(find.text('第 ${i + 1} 題，共 6 題'), findsOneWidget);
      for (final (_, label) in DjgW2Items.options) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.byKey(Key('entry_${item.id}_${answers[i]}')));
      await tester.pumpAndSettle();
    }
    // Summary shows labels, never a number.
    expect(find.text('請核對後提交'), findsOneWidget);
    expect(find.byKey(const Key('summary_q4')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('summary_q4'))).data,
        '缺答');
    expect(_forbidden.hasMatch(_allText(tester)), isFalse);
    expect(b.submitted, isEmpty);
    // First confirmation, cancelled: nothing sent.
    await tester.tap(find.byKey(const Key('entry_submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 題缺答'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm1_cancel')));
    await tester.pumpAndSettle();
    expect(b.submitted, isEmpty);
    // Both confirmations.
    await tester.tap(find.byKey(const Key('entry_submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm1_ok')));
    await tester.pumpAndSettle();
    expect(find.text('再確認一次'), findsOneWidget);
    expect(b.submitted, isEmpty, reason: 'not before the second confirmation');
    await tester.tap(find.byKey(const Key('confirm2_ok')));
    await tester.pumpAndSettle();
    expect(b.submitted.length, 1);
    final sent = b.submitted.single;
    expect(sent.researchId, 'PB-001');
    expect(sent.instrument, 'DJG-ES');
    expect(sent.timepoint, 'W4');
    expect(sent.mode, 'phone');
    expect(sent.assessmentDate, '2026-11-27');
    expect(sent.answers, {
      'q1': 'yes',
      'q2': 'mostly',
      'q3': 'no',
      'q4': 'skipped',
      'q5': 'yes',
      'q6': 'no',
    });
    expect(sent.toMap()['confirmed'], isTrue);
    expect(sent.toMap().containsKey('scores'), isFalse);
    expect(find.text('已錄入'), findsOneWidget);
    await tester.tap(find.byKey(const Key('entry_done')));
    await tester.pumpAndSettle();
    // Back on the list, PB-001 is now marked entered.
    expect(find.textContaining('已錄入 2026-11-27'), findsOneWidget,
        reason: _allText(tester));
    expect(find.byKey(const Key('enter_PB-001')), findsNothing);
  });

  testWidgets('a server refusal (already entered) is shown, nothing crashes',
      (tester) async {
    final b = _FakeBackend(failWith: 'already_entered');
    await tester.pumpWidget(_page(b));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('enter_PB-001')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry_mode_in_person')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('entry_next')));
    await tester.pumpAndSettle();
    for (final item in DjgW2Items.items) {
      await tester.tap(find.byKey(Key('entry_${item.id}_no')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('entry_submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm1_ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm2_ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry_error')), findsOneWidget);
    expect(find.textContaining('已經錄入過'), findsOneWidget);
  });

  test('dashboard: with the switch on a blinded account is denied; '
      'pooled completion is unblinded-only and switch-gated', () {
    expect(
        DashboardAccess.blinded.withAssessorView(assessorViewOn: true),
        DashboardAccess.denied);
    expect(DashboardAccess.blinded.withAssessorView(assessorViewOn: false),
        DashboardAccess.blinded);
    expect(DashboardAccess.unblinded.withAssessorView(assessorViewOn: true),
        DashboardAccess.unblinded);
    expect(DashboardAccess.unblinded.showsOutcomeCompletion(switchOn: true),
        isTrue);
    expect(DashboardAccess.unblinded.showsOutcomeCompletion(switchOn: false),
        isFalse);
    expect(DashboardAccess.blinded.showsOutcomeCompletion(switchOn: true),
        isFalse);
  });

  test('pooled completion row: n < 5 shows no number', () {
    const hidden = CompletionRow(
        instrument: 'DJG-ES', timepoint: 'W4', suppressed: true);
    expect(hidden.display(minN: 5), '少於 5 人，不顯示');
    // Even an unsuppressed row with n < 5 (should not happen) shows none.
    const small = CompletionRow(instrument: 'DJG-ES', timepoint: 'W4',
        suppressed: false, n: 4, completed: 4, rate: 1);
    expect(small.display(minN: 5), '少於 5 人，不顯示');
    const shown = CompletionRow(instrument: 'DJG-ES', timepoint: 'W4',
        suppressed: false, n: 8, completed: 6, rate: 0.75);
    expect(shown.display(minN: 5), '6 / 8（75%）');
    final parsed = CompletionSummary.fromMap({
      'minN': 5,
      'rows': [
        {'instrument': 'DJG-ES', 'timepoint': 'W2', 'suppressed': true}
      ],
    });
    expect(parsed.rows.single.suppressed, isTrue);
  });

  testWidgets('completion section renders the server rows', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OutcomeCompletionSection(
          isEn: false,
          load: () async => const CompletionSummary(minN: 5, rows: [
            CompletionRow(
                instrument: 'DJG-ES', timepoint: 'W4', suppressed: true),
            CompletionRow(instrument: 'DJG-ES', timepoint: 'W2',
                suppressed: false, n: 10, completed: 7, rate: 0.7),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('少於 5 人，不顯示'), findsOneWidget);
    expect(find.text('7 / 10（70%）'), findsOneWidget);
    expect(_forbidden.hasMatch(_allText(tester)), isFalse);
  });
}
