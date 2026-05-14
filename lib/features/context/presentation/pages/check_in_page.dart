import 'package:flutter/material.dart';

import '../../../../core/arm/arm_scope.dart';
import 'check_in_arm_a.dart';
import 'check_in_arm_b.dart';

/// M2 — Daily Emotional Check-In. The entry point for both arms; the
/// implementation lives in [_CheckInArmA] (LLM-augmented) and
/// [_CheckInArmB] (rule-based). Identical AppBar copy + entry tile so
/// participants can't tell which version they're in.
class CheckInPage extends StatelessWidget {
  const CheckInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ArmGate(
      armA: (_) => const CheckInArmA(),
      armB: (_) => const CheckInArmB(),
    );
  }
}
