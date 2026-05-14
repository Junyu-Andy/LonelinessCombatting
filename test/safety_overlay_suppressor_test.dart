import 'package:app_demo/core/safety/safety_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      builder: (_, _) => SafetyOverlay(child: child),
      home: const SizedBox.shrink(),
    );

void main() {
  group('SafetyOverlay + SafetyOverlaySuppressor', () {
    testWidgets('pill is visible by default', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SafetyOverlay(child: const Scaffold(body: SizedBox())),
      ));
      await tester.pump();
      expect(find.text('搵人傾'), findsOneWidget);
    });

    testWidgets('suppressor hides the pill while mounted', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SafetyOverlay(
          child: const Scaffold(
            body: SafetyOverlaySuppressor(child: SizedBox()),
          ),
        ),
      ));
      // One frame for postFrameCallback to fire.
      await tester.pump();
      await tester.pump();
      expect(find.text('搵人傾'), findsNothing);
    });
  });
}
