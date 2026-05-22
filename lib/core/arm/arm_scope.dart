import 'package:flutter/widgets.dart';

import '../../app/app_settings_scope.dart';
import '../../features/auth/data/user_profile.dart';

/// Thin lookup helper for the current participant's RCT arm. Reads from
/// the user profile held in [AppSettings], so it stays reactive: if the
/// profile changes (sign-in, sign-out, arm backfill on first login),
/// widgets that depend on this rebuild automatically.
///
/// Modules should call [Arm.of] in their build method. For Arm B–only
/// surfaces that must never invoke an LLM, treat a missing arm (guest
/// mode, demo) as Arm B — fail safe.
///
/// Local dev escape hatch: pass `--dart-define=FORCE_ARM=A` (or B) at
/// build time to override the profile lookup. Useful when Firebase
/// isn't configured yet and you still want to walk the Arm A LLM
/// surfaces. **Never** ship a release build with this set.
class Arm {
  const Arm._();

  static const _forced = String.fromEnvironment('FORCE_ARM');

  /// The participant's assigned arm, or null in guest / demo mode.
  static ArmAssignment? of(BuildContext context) {
    // TEST OVERRIDE — Phase A pilot is forcing every user to Arm A so
    // the researcher can run end-to-end LLM walk-throughs without
    // hitting Arm B rule-based fallbacks. Revert this stub before
    // randomisation goes live for Phase B.
    return ArmAssignment.a;
    // ignore: dead_code
    if (_forced.isNotEmpty) {
      return ArmAssignment.tryParse(_forced);
    }
    return AppSettingsScope.of(context).profile?.arm;
  }

  /// Convenience: true iff this user is in the LLM-augmented arm.
  static bool isA(BuildContext context) => of(context) == ArmAssignment.a;

  /// Convenience: true iff this user is in the rule-based arm OR the
  /// app is in guest mode. Guest mode falls into B so the demo cannot
  /// accidentally show LLM behaviour to people who haven't signed up.
  static bool isB(BuildContext context) => !isA(context);
}

/// Renders one of two children depending on the participant's arm.
/// Keeps Arm A and Arm B implementations side-by-side in source so the
/// reviewer can see they match in copy, layout, and affordances —
/// the only difference is the engine behind the screen.
class ArmGate extends StatelessWidget {
  /// Shown to Arm A (hybrid: rule + LLM) participants.
  final WidgetBuilder armA;

  /// Shown to Arm B (rule-based) participants and to anonymous /
  /// guest users. Fail-safe default.
  final WidgetBuilder armB;

  const ArmGate({super.key, required this.armA, required this.armB});

  @override
  Widget build(BuildContext context) {
    return Arm.isA(context) ? armA(context) : armB(context);
  }
}
