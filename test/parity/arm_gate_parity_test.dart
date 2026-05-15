import 'package:app_demo/core/arm/arm_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parity_harness.dart';

/// P5.2 example — exercises the harness on a small static widget so
/// the pattern is reviewable without pulling in a full module's
/// dependency graph. Real per-page parity tests follow the same
/// shape but wrap the actual module page (e.g. TodayPage) and
/// inject mock services where needed.
///
/// To regenerate goldens locally:
///   flutter test --update-goldens test/parity/arm_gate_parity_test.dart
void main() {
  group('P5.2 parity smoke', () {
    testWidgets(
      'ArmGate body uses ArmA branch when profile.arm == a',
      (tester) async {
        await tester.pumpWidget(
          wrapWithArm(
            arm: ArmAssignment.a,
            child: const ArmGate(
              armA: _DummyArmBody(label: 'A'),
              armB: _DummyArmBody(label: 'B'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('A'), findsOneWidget);
        expect(find.text('B'), findsNothing);
      },
    );

    testWidgets(
      'ArmGate body uses ArmB branch when profile.arm == b',
      (tester) async {
        await tester.pumpWidget(
          wrapWithArm(
            arm: ArmAssignment.b,
            child: const ArmGate(
              armA: _DummyArmBody(label: 'A'),
              armB: _DummyArmBody(label: 'B'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('B'), findsOneWidget);
        expect(find.text('A'), findsNothing);
      },
    );

    testWidgets(
      'Strict-parity helper produces matching golden across both arms',
      (tester) async {
        Widget build() => Container(
              padding: const EdgeInsets.all(24),
              color: const Color(0xFFFFFFFF),
              child: const Center(
                child: Text(
                  'Identical in both arms',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 20, color: Color(0xFF111111)),
                ),
              ),
            );
        await assertStrictParity(
          tester: tester,
          goldenKey: 'demo_strict_parity_card',
          build: build,
        );
      },
      // Goldens land in test/parity/goldens/. Skip in CI until the
      // dissertation team commits the baseline images.
      skip: true,
    );
  });
}

class _DummyArmBody extends StatelessWidget {
  final String label;
  const _DummyArmBody({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, textDirection: TextDirection.ltr),
    );
  }
}
