// 1020o / 1020p 补充 一 (decisions-log 10/20 item 97): the crisis page list
// was checked on 2026-10-20.  The date is filled in; the four numbers are
// exactly as before; the page footer shows the date in both arms.
import 'dart:convert';
import 'dart:io';

import 'package:app_demo/core/safety/safety_copy.dart';
import 'package:app_demo/features/analytics/data/analytics_service.dart';
import 'package:app_demo/features/analytics/presentation/analytics_scope.dart';
import 'package:app_demo/features/auth/data/user_profile.dart';
import 'package:app_demo/features/crisis/presentation/pages/emergency_support_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parity/parity_harness.dart';

Map<String, dynamic> _json() =>
    jsonDecode(
          File('functions/prompts/crisis_resources.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  test('verifiedDate is 2026-10-20; the four numbers are unchanged', () {
    final d = _json();
    expect(d['verifiedDate'], '2026-10-20');
    final numbers = [
      for (final r in d['resources'] as List)
        ((r as Map)['nameZh'], r['number']),
    ];
    expect(numbers, const [
      ('生命熱線', '2382 0000'),
      ('撒瑪利亞會', '2896 0000'),
      ('醫院管理局精神健康專線', '2466 7350'),
      ('急症室 / 999', '999'),
    ]);
  });

  for (final arm in [ArmAssignment.a, ArmAssignment.b]) {
    testWidgets('arm ${arm.name}: the crisis page footer shows the date', (
      tester,
    ) async {
      SafetyCopy.inject(crisis: _json());
      await tester.pumpWidget(
        AnalyticsScope(
          analytics: AnalyticsService(firebaseReady: false),
          child: wrapWithArm(
            arm: arm,
            child: const EmergencySupportPage(from: 'test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final footer = find.text('資料核對日期：2026-10-20');
      await tester.scrollUntilVisible(
        footer,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(footer, findsOneWidget);
      expect(find.textContaining('待核對'), findsNothing);
    });
  }
}
