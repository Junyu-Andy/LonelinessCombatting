import 'package:app_demo/core/scheduling/w0_date.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/enrollment/data/enrollment_service.dart';
import 'package:app_demo/features/enrollment/presentation/enrollment_page.dart';
import 'package:app_demo/features/enrollment/presentation/staff_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// T19 (decision 0029): the unblinded researcher's registration page, the
/// gate that shows it only to the `unblinded` claim, and the W0 date.
class _FakeBackend implements EnrollmentBackend {
  final calls = <({EnrollmentInput input, bool dryRun})>[];
  bool enrolled = false;
  String? failWith;

  @override
  Future<EnrollmentResult> submit(EnrollmentInput input,
      {required bool dryRun}) async {
    calls.add((input: input, dryRun: dryRun));
    if (failWith != null) throw EnrollmentError(failWith!);
    final already = enrolled;
    if (!dryRun) enrolled = true;
    return EnrollmentResult(
      alreadyEnrolled: already,
      sameInput: true,
      arm: dryRun ? null : 'B',
      researchId: input.researchId.trim().toUpperCase(),
      stratum: input.stratum,
      displayName: 'Synthetic elder',
      accountCreatedAt: '2026-10-07T02:00:00.000Z',
    );
  }
}

Future<void> _fill(WidgetTester tester, {int score = 2}) async {
  await tester.enterText(find.byKey(const Key('enroll_email')), 'e@x.org');
  await tester.enterText(find.byKey(const Key('enroll_research_id')), 'b001');
  await tester.tap(find.byKey(Key('enroll_score_$score')));
  await tester.tap(find.byKey(const Key('enroll_variant_masculine')));
  await tester.pump();
}

Widget _app(EnrollmentBackend b) => MaterialApp(
      home: EnrollmentPage(backend: b, today: () => DateTime(2026, 10, 7)),
    );

void main() {
  group('w0DateFor', () {
    final created = DateTime(2026, 10, 1, 9);
    test('registered W0 date wins over createdAt', () {
      final p = UserProfile(
          uid: 'u', email: '', displayName: '', createdAt: created,
          w0Date: '2026-10-05');
      expect(w0DateFor(p), DateTime(2026, 10, 5));
    });
    test('falls back to createdAt when missing or malformed', () {
      expect(
          w0DateFor(UserProfile(
              uid: 'u', email: '', displayName: '', createdAt: created)),
          created);
      for (final bad in ['2026-02-30', '5/10/2026', '']) {
        expect(
            w0DateFor(UserProfile(
                uid: 'u',
                email: '',
                displayName: '',
                createdAt: created,
                w0Date: bad)),
            created,
            reason: bad);
      }
      expect(w0DateFor(null), isNull);
    });
    test('w0Date is read from the profile map and never written back', () {
      final p = UserProfile.fromMap('u', {'w0Date': '2026-10-05'});
      expect(p.w0Date, '2026-10-05');
      expect(p.toMap().containsKey('w0Date'), isFalse);
    });
  });

  testWidgets('check is off until every field is filled', (tester) async {
    final b = _FakeBackend();
    await tester.pumpWidget(_app(b));
    final check = find.byKey(const Key('enroll_check'));
    expect(tester.widget<FilledButton>(check).onPressed, isNull);
    await _fill(tester);
    expect(tester.widget<FilledButton>(check).onPressed, isNotNull);
  });

  testWidgets(
      'dry run first, second score must match, then the arm is shown',
      (tester) async {
    final b = _FakeBackend();
    await tester.pumpWidget(_app(b));
    await _fill(tester, score: 2);
    await tester.tap(find.byKey(const Key('enroll_check')));
    await tester.pumpAndSettle();

    expect(b.calls.single.dryRun, isTrue);
    expect(find.text('確認登記'), findsWidgets);
    expect(find.textContaining('Synthetic elder'), findsOneWidget);
    expect(find.textContaining('高層'), findsOneWidget);
    expect(find.textContaining('B 組'), findsNothing, reason: 'no arm yet');

    final confirm = find.byKey(const Key('enroll_confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.byKey(const Key('enroll_score_again_1')));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(find.textContaining('兩次情感分唔一樣'), findsOneWidget);
    await tester.tap(find.byKey(const Key('enroll_score_again_2')));
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(b.calls.length, 2);
    expect(b.calls.last.dryRun, isFalse);
    final payload = b.calls.last.input.toPayload(dryRun: false);
    expect(payload['researchId'], 'B001');
    expect(payload['w0DjgEmotional'], 2);
    expect(payload['companionVariant'], 'masculine');
    expect(payload['w0Date'], '2026-10-07');
    expect(payload['confirmed'], isTrue);
    expect(find.byKey(const Key('enroll_arm')), findsOneWidget);
    expect(find.textContaining('B 組（規則組）'), findsOneWidget);
  });

  testWidgets('cancel in the dialog allocates nothing', (tester) async {
    final b = _FakeBackend();
    await tester.pumpWidget(_app(b));
    await _fill(tester);
    await tester.tap(find.byKey(const Key('enroll_check')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(b.calls.length, 1);
    expect(b.calls.single.dryRun, isTrue);
    expect(find.byKey(const Key('enroll_arm')), findsNothing);
  });

  testWidgets('already registered: stored arm, no confirmation dialog',
      (tester) async {
    final b = _FakeBackend()..enrolled = true;
    await tester.pumpWidget(_app(b));
    await _fill(tester);
    await tester.tap(find.byKey(const Key('enroll_check')));
    await tester.pumpAndSettle();
    expect(find.text('已經登記過，組別不變'), findsOneWidget);
    expect(find.byKey(const Key('enroll_confirm')), findsNothing);
  });

  testWidgets('server refusal is shown in words', (tester) async {
    final b = _FakeBackend()..failWith = 'research_id_taken';
    await tester.pumpWidget(_app(b));
    await _fill(tester);
    await tester.tap(find.byKey(const Key('enroll_check')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已經登記咗第二個帳號'), findsOneWidget);
  });

  group('StaffGate', () {
    Widget gate(Map<String, dynamic>? claims, {bool fail = false}) =>
        MaterialApp(
          home: StaffGate(
            uid: 'x',
            loadClaims: () async {
              if (fail) throw StateError('offline');
              return claims;
            },
            child: const Text('participant app'),
          ),
        );

    for (final c in <Map<String, dynamic>?>[
      null,
      {},
      {'role': 'blinded'},
      {'role': 'pi'},
      {'role': 'researcher'},
    ]) {
      testWidgets('claims $c → participant App, no registration entry',
          (tester) async {
        await tester.pumpWidget(gate(c));
        await tester.pumpAndSettle();
        expect(find.text('participant app'), findsOneWidget);
        expect(find.text('研究員登記'), findsNothing);
      });
    }

    testWidgets('claim lookup failing → participant App', (tester) async {
      await tester.pumpWidget(gate(null, fail: true));
      await tester.pumpAndSettle();
      expect(find.text('participant app'), findsOneWidget);
    });

    testWidgets('role unblinded → registration page', (tester) async {
      await tester.pumpWidget(gate({'role': 'unblinded'}));
      await tester.pumpAndSettle();
      expect(find.text('研究員登記'), findsOneWidget);
      expect(find.text('participant app'), findsNothing);
    });
  });
}
