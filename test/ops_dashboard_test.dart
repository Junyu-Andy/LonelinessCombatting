// T39 (registry C19 / C20) — operations dashboard, App side, with a fake
// backend: the switch, the entry on the registration page, access
// denied for a non-unblinded claim, the per-person table and its filters,
// the follow-up stage and the 舊構建口徑 flag, the daily grid (60-minute
// cap shown, 不可用 on the legacy basis), the CSV page, and the rule that
// no outcome word ever appears on these screens.
import 'package:app_demo/core/feature_flags/remote_feature_flags.dart';
import 'package:app_demo/features/enrollment/data/enrollment_service.dart';
import 'package:app_demo/features/enrollment/presentation/enrollment_page.dart';
import 'package:app_demo/features/ops_dashboard/data/ops_dashboard_service.dart';
import 'package:app_demo/features/ops_dashboard/presentation/ops_dashboard_page.dart';
import 'package:app_demo/features/ops_dashboard/presentation/ops_person_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _person(String rid,
        {String period = 'PILOT',
        String arm = 'A',
        int unopened = 0,
        String stage = 'none',
        bool legacy = false,
        bool openedToday = true}) =>
    {
      'researchId': rid,
      'studyPeriod': period,
      'arm': arm,
      'w0Date': '2026-10-15',
      'studyDay': 10,
      'lastUseAt': '2026-10-25T01:00:00.000Z',
      'openedToday': openedToday,
      'consecutiveUnopenedDays': unopened,
      'stage': stage,
      'legacyBasis': legacy,
      'validSessions': {
        'total': 3,
        'byCompanion': {'siu_yan': 1, 'ah_jan_ah_bak': 0, 'tung_tung': 2},
        'byType': {'free_chat': 3, 'check_in': 0, 'reminiscence': 0},
      },
      'briefPr': {
        'invited': 3, 'completed': 2, 'partially_completed': 0,
        'skipped': 1, 'expired': 0, 'due_not_invited': 0,
      },
      'weekly': {
        'W1': 'done', 'W2': 'missed', 'W3': 'open', 'W4': 'not_yet',
        'W5': 'not_yet', 'W6': 'not_yet', 'W7': 'not_yet', 'W8': 'not_built',
      },
      'moodDays': 4,
      'memory': arm == 'A' ? {'shared': 2, 'private': 5} : null,
      'voice': {'uses': 1, 'failures': 0},
      'safety': {'acute': 0, 'moderate': 1, 'low': 2, 'pendingAck': 0},
      'w8Status': 'not_built',
      'debriefStatus': 'not_built',
    };

Map<String, dynamic> _day(int d, String key,
        {bool opened = true, int? minutes = 12, String basis = 'usage'}) =>
    {
      'dayKey': key,
      'studyDay': d,
      'basis': basis,
      'opened': opened,
      'firstOpenAt': opened ? '09:00' : null,
      'foregroundMinutes': minutes,
      'validSessions': {'siu_yan': 1, 'ah_jan_ah_bak': 0, 'tung_tung': 0},
      'briefPrInvited': 1,
      'briefPrCompleted': 1,
    };

class _FakeBackend implements OpsBackend {
  _FakeBackend({this.failWith});
  final String? failWith;
  final calls = <String>[];

  @override
  Future<OpsPeople> people() async {
    calls.add('people');
    if (failWith != null) throw OpsError(failWith!);
    return OpsPeople.fromMap({
      'today': '2026-10-25',
      'people': [
        _person('PILOT-01'),
        _person('PILOT-02', unopened: 4, stage: 'whatsapp',
            openedToday: false),
        _person('PILOT-03', arm: 'B', unopened: 7, stage: 'phone',
            openedToday: false),
        _person('PB-002', period: 'B', arm: 'B', unopened: 3,
            stage: 'whatsapp', legacy: true, openedToday: false),
        _person('PB-003', period: 'B', unopened: 6,
            stage: 'follow_up_period', openedToday: false),
      ],
      'dueList': [
        {'researchId': 'PILOT-03', 'studyPeriod': 'PILOT',
          'consecutiveUnopenedDays': 7, 'stage': 'phone'},
        {'researchId': 'PILOT-02', 'studyPeriod': 'PILOT',
          'consecutiveUnopenedDays': 4, 'stage': 'whatsapp'},
        {'researchId': 'PB-002', 'studyPeriod': 'B',
          'consecutiveUnopenedDays': 3, 'stage': 'whatsapp'},
      ],
    });
  }

  @override
  Future<OpsPersonDetail> person(String researchId) async {
    calls.add('person:$researchId');
    if (failWith != null) throw OpsError(failWith!);
    final legacy = researchId == 'PB-002';
    return OpsPersonDetail.fromMap({
      'today': '2026-10-25',
      'person': _person(researchId, legacy: legacy,
          arm: legacy ? 'B' : 'A', period: legacy ? 'B' : 'PILOT'),
      'days': [
        _day(1, '2026-10-16', minutes: legacy ? null : 12,
            basis: legacy ? 'legacy' : 'usage'),
        _day(2, '2026-10-17', opened: false, minutes: legacy ? null : 0,
            basis: legacy ? 'legacy' : 'usage'),
        _day(3, '2026-10-18', minutes: legacy ? null : 60,
            basis: legacy ? 'legacy' : 'usage'),
      ],
      'recentSessions': [
        {'startedAt': '2026-10-18T01:01:00.000Z', 'agentId': 'tung_tung',
          'sessionType': 'free_chat', 'userMessageCount': 4,
          'durationMinutes': 19, 'endReason': 'close_button',
          'isValid': true, 'briefPrStatus': 'completed'},
      ],
    });
  }

  @override
  Future<OpsCsv> csv({String? researchId}) async {
    calls.add('csv:$researchId');
    if (failWith != null) throw OpsError(failWith!);
    return const OpsCsv(
        filename: 'ops_daily_PILOT-01_2026-10-25.csv',
        csv: 'researchId,studyPeriod,arm,studyDay,dayKey,opened,firstOpenAt,'
            'foregroundMinutes,validSessions_siu_yan,'
            'validSessions_ah_jan_ah_bak,validSessions_tung_tung,'
            'briefPrInvited,briefPrCompleted,basis\n'
            'PILOT-01,PILOT,A,1,2026-10-16,1,09:00,12,1,0,0,1,1,usage\n',
        rows: 1);
  }
}

class _FakeEnrollment implements EnrollmentBackend {
  @override
  Future<EnrollmentResult> submit(EnrollmentInput input,
          {required bool dryRun}) =>
      throw UnimplementedError();
}

Widget _page(OpsBackend b, {String? role = 'unblinded'}) => MaterialApp(
      home: OpsDashboardPage(
        backend: b,
        loadClaims: () async => role == null ? null : {'role': role},
      ),
    );

/// Outcome words that must never appear on an ops screen.
final _forbidden = RegExp(
    r'DJG|UCLA|PHQ|GAD|PGIC|社會接觸|社会接触|AIMHS|分數|分数|score',
    caseSensitive: false);

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  test('switch: off unless literally true', () {
    expect(const RemoteFeatureFlags().opsDashboardEnabled, isFalse);
    expect(RemoteFeatureFlags.fromMap({}).opsDashboardEnabled, isFalse);
    expect(RemoteFeatureFlags.fromMap({'opsDashboardEnabled': 'true'})
        .opsDashboardEnabled, isFalse);
    expect(RemoteFeatureFlags.fromMap({'opsDashboardEnabled': true})
        .opsDashboardEnabled, isTrue);
  });

  testWidgets('registration page: the 營運看板 button only with the switch on',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
        home: EnrollmentPage(
            backend: _FakeEnrollment(),
            today: () => DateTime(2026, 10, 25),
            opsDashboardOn: false)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('enroll_ops_dashboard')), findsNothing);

    await tester.pumpWidget(MaterialApp(
        home: EnrollmentPage(
            backend: _FakeEnrollment(),
            today: () => DateTime(2026, 10, 25),
            opsDashboardOn: true,
            onOpenOpsDashboard: () => opened++)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('enroll_ops_dashboard')), findsOneWidget);
    await tester.tap(find.byKey(const Key('enroll_ops_dashboard')));
    expect(opened, 1);
  });

  testWidgets('blinded / participant / no claims: access denied, no call '
      'reaches the backend\'s data on screen', (tester) async {
    for (final role in ['blinded', 'pi', null]) {
      final b = _FakeBackend();
      await tester.pumpWidget(_page(b, role: role));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ops_denied')), findsOneWidget,
          reason: 'role $role');
      expect(find.byKey(const Key('ops_person_PILOT-01')), findsNothing);
    }
  });

  testWidgets('server refusal (switch off) shows the researcher text',
      (tester) async {
    await tester.pumpWidget(_page(_FakeBackend(failWith: 'disabled')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ops_error')), findsOneWidget);
    expect(find.textContaining('opsDashboardEnabled'), findsOneWidget);
  });

  testWidgets('table: one line per person, stage text, due list, legacy '
      'flag, rule arm memory 不適用, no outcome word', (tester) async {
    final b = _FakeBackend();
    await tester.pumpWidget(_page(b));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ops_person_PILOT-01')), findsOneWidget);
    expect(find.textContaining('共 5 人'), findsOneWidget);
    String shown() =>
        tester.widget<Text>(find.byKey(const Key('ops_filtered'))).data!;
    expect(shown(), '顯示 5 人：PILOT-01、PILOT-02、PILOT-03、PB-002、PB-003');

    final scroll = find.byType(Scrollable).first;
    Future<Text> stage(String rid) async {
      await tester.scrollUntilVisible(find.byKey(Key('ops_stage_$rid')), 200,
          scrollable: scroll);
      return tester.widget<Text>(find.byKey(Key('ops_stage_$rid')));
    }

    final s2 = await stage('PILOT-02');
    expect(s2.data, contains('連續 4 日冇打開'));
    expect(s2.data, contains('回訪階段：WhatsApp'));
    expect(find.textContaining('共享 2／私有 5'), findsWidgets);
    expect(find.byKey(const Key('ops_legacy_PILOT-01')), findsNothing);
    final s3 = await stage('PILOT-03');
    expect(s3.data, contains('回訪階段：電話'));
    expect(find.textContaining('記憶 不適用'), findsWidgets);
    await tester.scrollUntilVisible(find.byKey(const Key('ops_legacy_PB-002')),
        200, scrollable: scroll);
    expect(find.byKey(const Key('ops_legacy_PB-002')), findsOneWidget);
    final s4 = await stage('PB-003');
    expect(s4.data, contains('隨訪期，只記錄'));
    expect(s4.data, contains('連續 6 日冇打開'));

    // Due list (page 1 item 7): order by days desc, no arm word.
    await tester.scrollUntilVisible(find.byKey(const Key('ops_due_PILOT-03')),
        -200, scrollable: scroll);
    final due = tester.widget<Text>(find.byKey(const Key('ops_due_PILOT-03')));
    expect(due.data, contains('連續 7 日冇打開'));
    expect(due.data, contains('電話'));
    expect(due.data, isNot(contains('組')));

    expect(_allText(tester), isNot(matches(_forbidden)));
  });

  testWidgets('filters: period, arm, 3 日冇用', (tester) async {
    await tester.pumpWidget(_page(_FakeBackend()));
    await tester.pumpAndSettle();
    String shown() =>
        tester.widget<Text>(find.byKey(const Key('ops_filtered'))).data!;
    await tester.tap(find.byKey(const Key('ops_filter_unused')));
    await tester.pumpAndSettle();
    expect(shown(), '顯示 4 人：PILOT-02、PILOT-03、PB-002、PB-003');
    expect(find.byKey(const Key('ops_person_PILOT-01')), findsNothing);
    expect(find.byKey(const Key('ops_person_PILOT-02')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ops_filter_arm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B 組（規則組）').last);
    await tester.pumpAndSettle();
    expect(shown(), '顯示 2 人：PILOT-03、PB-002');

    await tester.tap(find.byKey(const Key('ops_filter_period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phase B').last);
    await tester.pumpAndSettle();
    expect(shown(), '顯示 1 人：PB-002');
    expect(find.byKey(const Key('ops_person_PB-002')), findsOneWidget);
  });

  testWidgets('person page: daily grid with 60-minute cap, sessions, '
      'CSV page with copy; legacy person shows 不可用', (tester) async {
    final b = _FakeBackend();
    await tester.pumpWidget(_page(b));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ops_person_PILOT-01')));
    await tester.pumpAndSettle();
    expect(b.calls, contains('person:PILOT-01'));
    expect(find.byKey(const Key('ops_day_grid')), findsOneWidget);
    expect(tester.widget<Text>(
        find.byKey(const Key('ops_day_minutes_2026-10-18'))).data, '60');
    expect(tester.widget<Text>(
        find.byKey(const Key('ops_day_opened_2026-10-17'))).data, '冇');
    expect(find.textContaining('通通　自由傾偈　老人 4 句　19 分鐘'),
        findsOneWidget);
    expect(_allText(tester), isNot(matches(_forbidden)));

    await tester.tap(find.byKey(const Key('ops_person_csv')));
    await tester.pumpAndSettle();
    expect(b.calls, contains('csv:PILOT-01'));
    expect(find.byKey(const Key('ops_csv_text')), findsOneWidget);
    expect(find.byKey(const Key('ops_csv_copy')), findsOneWidget);
    expect(find.textContaining('ops_daily_PILOT-01_2026-10-25.csv'),
        findsOneWidget);
    expect(_allText(tester), isNot(matches(_forbidden)));
  });

  testWidgets('legacy person page: 舊構建口徑 note and 不可用 minutes',
      (tester) async {
    final b = _FakeBackend();
    await tester.pumpWidget(MaterialApp(
        home: OpsPersonPage(researchId: 'PB-002', backend: b)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ops_person_legacy')), findsOneWidget);
    expect(tester.widget<Text>(
        find.byKey(const Key('ops_day_minutes_2026-10-16'))).data, '不可用');
  });
}
