// dev-tasks-1014e §2.11 (10/15 item 3 (1)) — the registration page, the
// unblinded researcher's landing page since T19, gets an entry to the
// 研究員儀錶板 (T34 safety alerts + 確認處理, T30 pooled completion, the
// T12 sections).  Until now that page had no entry at all.  The dashboard
// page itself re-checks the `unblinded` claim, and a `blinded` account
// never reaches the registration page (StaffGate), so the button is
// unblinded-only by construction.
import 'package:app_demo/features/enrollment/data/enrollment_service.dart';
import 'package:app_demo/features/enrollment/presentation/enrollment_page.dart';
import 'package:app_demo/features/enrollment/presentation/staff_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEnrollment implements EnrollmentBackend {
  @override
  Future<EnrollmentResult> submit(EnrollmentInput input,
          {required bool dryRun}) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('registration page shows the 研究員儀錶板 entry (no switch) and '
      'opens it', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
        home: EnrollmentPage(
            backend: _FakeEnrollment(),
            today: () => DateTime(2026, 10, 15),
            opsDashboardOn: false,
            onOpenResearcherDashboard: () => opened++)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('enroll_researcher_dashboard')), findsOneWidget);
    expect(find.byTooltip('研究員儀錶板'), findsOneWidget);
    await tester.tap(find.byKey(const Key('enroll_researcher_dashboard')));
    expect(opened, 1);
  });

  test('a blinded account is never routed to the registration page', () {
    expect(staffRouteFor({'role': 'blinded'}, assessorViewOn: true),
        StaffRoute.assessor);
    expect(staffRouteFor({'role': 'blinded'}, assessorViewOn: false),
        StaffRoute.participant);
    expect(staffRouteFor({'role': 'unblinded'}, assessorViewOn: true),
        StaffRoute.enrollment);
  });
}
