import 'package:flutter/material.dart';

import '../../../../core/arm/arm_scope.dart';
import '../../../../core/feature_flags/remote_feature_flags.dart';
import 'check_in_arm_a.dart';
import 'check_in_arm_b.dart';
import 'siu_yan_chat_page.dart';

/// M2 — Daily Emotional Check-In. The entry point for both arms; the
/// implementation lives in [_CheckInArmA] (LLM-augmented) and
/// [_CheckInArmB] (rule-based). Identical AppBar copy + entry tile so
/// participants can't tell which version they're in.
///
/// 1020 F: with `app_config/feature_flags.checkInChatV2Enabled` on, every
/// entry (小欣 card, status chip, missed-check-in banner, continue card,
/// hand-off) opens [SiuYanChatPage] instead — one chat window for both
/// arms.  Off: exactly as before.
class CheckInPage extends StatelessWidget {
  const CheckInPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (RemoteFeatureFlags.current.checkInChatV2Enabled) {
      return const SiuYanChatPage();
    }
    return ArmGate(
      armA: (_) => const CheckInArmA(),
      armB: (_) => const CheckInArmB(),
    );
  }
}
