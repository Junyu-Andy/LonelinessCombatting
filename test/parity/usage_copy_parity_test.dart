import 'package:app_demo/core/config/usage_copy.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/settings/presentation/pages/faq_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parity_harness.dart';

/// T20 — the usage-frequency copy is the same in both arms, both with
/// today's text and with a configured line.
void main() {
  tearDown(() => UsageCopy.current = const UsageCopy());

  Future<void> openSkipAnswer(WidgetTester tester, ArmAssignment arm) async {
    await tester.pumpWidget(wrapWithArm(arm: arm, child: const FaqPage()));
    await tester.tap(find.text('我冇填 check-in 會唔會有事？'));
    await tester.pumpAndSettle();
  }

  for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
    testWidgets('FAQ skip answer, arm ${arm.name}: today\'s text by default',
        (tester) async {
      await openSkipAnswer(tester, arm);
      expect(find.textContaining('就算一整個星期冇填'), findsOneWidget);
    });

    testWidgets('FAQ skip answer, arm ${arm.name}: configured line',
        (tester) async {
      UsageCopy.current =
          UsageCopy.fromMap({'faq_skip_checkin_answer_zh': '定稿文字'});
      await openSkipAnswer(tester, arm);
      expect(find.text('定稿文字'), findsOneWidget);
      expect(find.textContaining('就算一整個星期冇填'), findsNothing);
    });
  }
}
