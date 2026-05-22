import 'package:app_demo/core/safety/safety_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SafetyOverlay', () {
    testWidgets('pill is hidden globally', (tester) async {
      // The persistent "搵人傾" pill was removed on product feedback;
      // distress routing still surfaces a safety sheet on detection.
      await tester.pumpWidget(MaterialApp(
        home: SafetyOverlay(child: const Scaffold(body: SizedBox())),
      ));
      await tester.pump();
      expect(find.text('搵人傾'), findsNothing);
    });

    testWidgets('suppressor is a safe no-op', (tester) async {
      // SafetyOverlaySuppressor stays in the tree for callers that
      // already wrap themselves; with the pill gone it simply does
      // nothing visible and must not throw.
      await tester.pumpWidget(MaterialApp(
        home: SafetyOverlay(
          child: const Scaffold(
            body: SafetyOverlaySuppressor(child: SizedBox()),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('搵人傾'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
